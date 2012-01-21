/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <signal.h>
#include <stddef.h>
#include <math.h>
#include <assert.h>

#ifdef POOR_GL_SUPPORT
#define GLEW_STATIC
#define NO_SDL_GLEXT
#include <glew.h>

#endif

#define GL_GLEXT_PROTOTYPES 1
#define CLAMP(x, l, h) (((x) > (h)) ? (h) : (((x) < (l)) ? (l) : (x)))

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_opengl.h>
#include <SDL_byteorder.h>
#include <SDL_ttf.h>

#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_frameserver_backend.h"
#include "arcan_target_const.h"
#include "arcan_target_launcher.h"
#include "arcan_videoint.h"

#ifndef ARCAN_FONT_CACHE_LIMIT
#define ARCAN_FONT_CACHE_LIMIT 8
#endif

struct text_format {
	TTF_Font* font;
	SDL_Color col;
	uint8_t alpha;
	uint8_t tab;
	uint8_t newline;
	bool cr;
	int style;
	char* endofs;
};

struct font_entry {
	TTF_Font* data;
	char* identifier;
	uint8_t size;
	uint8_t usecount;
};

long long ARCAN_VIDEO_WORLDID = -1;

static unsigned int font_cache_size = ARCAN_FONT_CACHE_LIMIT;
static struct font_entry font_cache[ARCAN_FONT_CACHE_LIMIT] = {0};

struct arcan_video_display arcan_video_display = {
	.bpp = 0, .width = 0, .height = 0, .conservative = false,
	.deftxs = GL_CLAMP_TO_EDGE, .deftxt = GL_CLAMP_TO_EDGE,
	.screen = NULL, .scalemode = ARCAN_VIMAGE_SCALEPOW2,
	.suspended = false
};

struct arcan_video_context {
	uint16_t vitem_ofs;
	struct text_format curr_style;
	
	arcan_vobject world;
	arcan_vobject* vitems_pool;
	arcan_vobject_litem* first;
};

static void dump_transformation(surface_transform* dst, int count);
arcan_errc arcan_video_attachobject(arcan_vobj_id id);
arcan_errc arcan_video_deleteobject(arcan_vobj_id id);
static arcan_errc arcan_video_getimage(const char* fname, arcan_vobject* dst, arcan_vstorage* dstframe);

static struct arcan_video_context context_stack[CONTEXT_STACK_LIMIT] = {
	{
		.vitem_ofs = 1,
		.curr_style = {
			.col = {.r = 0xff, .g = 0xff, .b = 0xff}
		},
		.world = {
			.current  = {
				.x   = 0,
				.y   = 0,
				.opa = 1.0,
				.w   = 1.0,
				.h   = 1.0
			},
			.transform = {
				.opa = {1.0, 1.0}
			}
		}
	}
};
static unsigned context_ind = 0;

/* a default more-or-less empty context */
static struct arcan_video_context* current_context = context_stack;

static void kill_shader(GLuint* dprg, GLuint* vprg, GLuint* fprg){
	if (*dprg)
		glDeleteProgram(*dprg);

	if (*vprg)
		glDeleteShader(*vprg);
	
	if (*fprg)
		glDeleteShader(*fprg);
	
	*dprg = *vprg = *fprg = 0;
}

static void build_shader(GLuint* dprg, GLuint* vprg, GLuint* fprg, const char* vprogram, const char* fprogram)
{
	char buf[256];
	int rlen;

	kill_shader(dprg, vprg, fprg);
	
	*dprg = glCreateProgram();
	*vprg = glCreateShader(GL_VERTEX_SHADER);
	*fprg = glCreateShader(GL_FRAGMENT_SHADER);

	glShaderSource(*vprg, 1, &vprogram, NULL);
	glShaderSource(*fprg, 1, &fprogram, NULL);

	glCompileShader(*vprg);
	glCompileShader(*fprg);
	
	glGetShaderInfoLog(*vprg, 256, &rlen, buf);
	if (rlen)
		arcan_warning("Warning: Couldn't compiler Shader vertex program: %s\n", buf);

	glGetShaderInfoLog(*fprg, 256, &rlen, buf);
	if (rlen)
		arcan_warning("Warning: Couldn't compiler Shader fragment Program: %s\n", buf);

	glAttachShader(*dprg, *fprg);
	glAttachShader(*dprg, *vprg);

	glLinkProgram(*dprg);

	glGetProgramInfoLog(*dprg, 256, &rlen, buf);
	if (rlen)
		arcan_warning("Warning: Problem linking Shader Program: %s\n", buf);

/*	glUseProgram(*dprg); */
}

static void allocate_and_store_globj(arcan_vobject* current){
	glGenTextures(1, &current->gl_storage.glid);
	glBindTexture(GL_TEXTURE_2D, current->gl_storage.glid);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, current->gl_storage.w, current->gl_storage.h, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, current->default_frame.raw);

	if (current->gpu_program.fragment && 
		current->gpu_program.vertex){
			build_shader(&current->gl_storage.program, &current->gl_storage.vertex, &current->gl_storage.fragment,
						   current->gpu_program.vertex, current->gpu_program.fragment);
		}
}


/* scan through each cell in use.
 * if we want to clean the context permanently (delete flag)
 * just wrap the call to deleteobject,
 * otherwise we're in a suspend situation (i.e. just clean up some openGL resources,
 * and pause possble movies */
static void deallocate_gl_context(struct arcan_video_context* context, bool delete)
{
	for (int i = 1; i < VITEM_POOLSIZE; i++) {
		if (current_context->vitems_pool[i].flags.in_use){
			
			if (delete)
				arcan_video_deleteobject(i); /* will also delink from the render list */
			else {
				arcan_vobject* current = &(current_context->vitems_pool[i]);
				glDeleteTextures(1, &current->gl_storage.glid);
				kill_shader(&current->gl_storage.program, 
							&current->gl_storage.fragment,
							&current->gl_storage.vertex);

				if (current->state.tag == ARCAN_TAG_MOVIE && current->state.ptr)
					arcan_frameserver_pause((arcan_frameserver*) current->state.ptr, true);
			}
		}
	}
}

/* go through a saved context, and reallocate all resources associated with it */
static void reallocate_gl_context(struct arcan_video_context* context)
{
	
	for (int i = 1; i < VITEM_POOLSIZE; i++)
		if (current_context->vitems_pool[i].flags.in_use){
			arcan_vobject* current = &current_context->vitems_pool[i];
		/* conservative means that we do not keep a copy of the originally decoded memory,
		 * essentially halving memory consumption but increasing cost of pop() and push() */
			if (arcan_video_display.conservative && (char)current->default_frame.tag == ARCAN_TAG_IMAGE){
				arcan_video_getimage(current->default_frame.source, current, &current->default_frame); 
			}
			else
				allocate_and_store_globj(current);

			if (current->state.tag == ARCAN_TAG_MOVIE && current->state.ptr) {
				arcan_frameserver* movie = (arcan_frameserver*) current->state.ptr;

				arcan_audio_rebuild(movie->aid);
				arcan_frameserver_resume(movie);
				arcan_audio_play(movie->aid);
			}
		}
}

unsigned arcan_video_nfreecontexts()
{
		return CONTEXT_STACK_LIMIT - 1 - context_ind;
}

signed arcan_video_pushcontext()
{
	struct text_format empty_style = { .col = {.r = 0xff, .g = 0xff, .b = 0xff} };
	arcan_vobject empty_vobj = { .current = {.x = 0, .y = 0, .opa = 1.0}, .transform = { .opa = {1.0, 1.0} } };

	if (context_ind + 1 == CONTEXT_STACK_LIMIT)
		return -1;
	
	/* copy everything then manually reset some fields */
	memcpy(&context_stack[ ++context_ind ], current_context, sizeof(struct arcan_video_context));
	deallocate_gl_context(current_context, false);
	
	current_context = &context_stack[ context_ind ];

	current_context->curr_style = empty_style;
	current_context->vitem_ofs = 1;
	current_context->world = empty_vobj;
	current_context->world.current.w = 1.0;
	current_context->world.current.h = 1.0;
	current_context->vitems_pool = (arcan_vobject*) calloc(sizeof(arcan_vobject), VITEM_POOLSIZE);
	current_context->first = NULL;

	return arcan_video_nfreecontexts();
}

unsigned arcan_video_popcontext()
{
	deallocate_gl_context(current_context, true);
	
	if (context_ind > 0){
		context_ind--;
		current_context = &context_stack[ context_ind ];		
	}

	reallocate_gl_context(current_context);
	
	return (CONTEXT_STACK_LIMIT - 1) - context_ind;
}

arcan_vobj_id arcan_video_allocid(bool* status)
{
	arcan_vobj_id rv = 0, i;
	*status = false;

	for (i = current_context->vitem_ofs; i < VITEM_POOLSIZE; i++)
		if (!current_context->vitems_pool[i].flags.in_use) {
			*status = true;
			current_context->vitems_pool[i].flags.in_use = true;
			rv = i;
			break;
		}

	if (i == VITEM_POOLSIZE - 1) {
		current_context->vitem_ofs = 1;
	}
	else {
		current_context->vitem_ofs = i + 1;
	}

	return rv;
}

arcan_vobj_id arcan_video_cloneobject(arcan_vobj_id parent)
{
	arcan_vobject* pobj = arcan_video_getobject(parent);
	arcan_vobj_id rv;

	if (pobj == NULL)
		return 0;

	bool status;
	rv = arcan_video_allocid(&status);

	if (status) {
		arcan_vobject* nobj = arcan_video_getobject(rv);
		memcpy(nobj, pobj, sizeof(arcan_vobject));
		nobj->current.x = 0;
		nobj->current.y = 0;
		nobj->current.w = 1.0;
		nobj->current.h = 1.0;
		nobj->parent = pobj;
		nobj->flags.clone = true;
		memset(&nobj->transform, 0, sizeof(surface_transform));
		arcan_video_attachobject(rv);
	}

	return rv;
}

static void generate_basic_mapping(float* dst, float st, float tt)
{
	dst[0] = 0.0;
	dst[1] = 0.0;
	dst[2] = st;
	dst[3] = 0.0;
	dst[4] = st;
	dst[5] = tt;
	dst[6] = 0.0;
	dst[7] = tt;
}

static void generate_mirror_mapping(float* dst, float st, float tt)
{
	dst[6] = 0.0;
	dst[7] = 0.0;
	dst[4] = st;
	dst[5] = 0.0;
	dst[2] = st;
	dst[3] = tt;
	dst[0] = 0.0;
	dst[1] = tt;
}

arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id)
{
	arcan_vobject* rv = NULL;
	bool status;
	arcan_vobj_id fid = arcan_video_allocid(&status);

	if (status) {
		rv = current_context->vitems_pool + fid;
		rv->current_frame = rv;
		rv->gl_storage.txu = arcan_video_display.deftxs;
		rv->gl_storage.txv = arcan_video_display.deftxt;
		rv->gl_storage.scale = arcan_video_display.scalemode;
		rv->flags.cliptoparent = false;
		rv->current.w = 1.0;
		rv->current.h = 1.0;
		generate_basic_mapping(rv->txcos, 1.0, 1.0);
		rv->parent = &current_context->world;
		rv->mask = MASK_ORIENTATION | MASK_OPACITY | MASK_POSITION;
	}

	if (id != NULL)
		*id = fid;

	return rv;
}

/* not what one might initially think, this is only
 * to create a surrogate clone where some properties are similar
 * in order to do some predictions (such as transforms),
 * not act as a proper depth- clone */
arcan_vobject* arcan_video_dupobject(arcan_vobject* vobj)
{
	if (!vobj)
		return NULL;
	arcan_vobject* res = (arcan_vobject*) malloc(sizeof(arcan_vobject));
	memcpy(res, vobj, sizeof(arcan_vobject));

	surface_transform* current = &vobj->transform;
	surface_transform* target = &res->transform;
	while (current) {
		memcpy(target, current, sizeof(surface_transform));

		/* reroute next- pointers and allocate */
		current = current->next;
		if (current) {
			target->next = (surface_transform*) malloc(sizeof(surface_transform));
			target = target->next;
		}
	}

	return res;
}

bool arcan_video_remdup(arcan_vobject* vobj)
{
	if (!vobj)
		return false;
	surface_transform* current = vobj->transform.next;

	while (current) {
		surface_transform* prev = current;
		current = current->next;
		free(prev);
	};

	free(vobj);
	return true;
}

arcan_vobject* arcan_video_getobject(arcan_vobj_id id)
{
	arcan_vobject* rc = NULL;

	if (id > 0 && id < VITEM_POOLSIZE && current_context->vitems_pool[id].flags.in_use)
		rc = current_context->vitems_pool + id;
	else
		if (id == ARCAN_VIDEO_WORLDID) {
			rc = &current_context->world;
		}

	return rc;
}

arcan_errc arcan_video_attachobject(arcan_vobj_id id)
{
	arcan_vobject* src = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;

	if (src) {
		/* allocate new llist- item */
		arcan_vobject_litem* new_litem = (arcan_vobject_litem*) calloc(sizeof(arcan_vobject_litem), 1);
		new_litem->elem = src;
		new_litem->cellid = id;
		src->owner = new_litem;

		/* case #1, no previous item or first */
		if (!current_context->first) {
			current_context->first = new_litem;
		}
		else
			if (current_context->first->elem->order > src->order) { /* insert first */
				new_litem->next = current_context->first;
				current_context->first = new_litem;
				new_litem->next->previous = new_litem;
			} /* insert "anywhere" */
			else {
				bool last = true;
				arcan_vobject_litem* ipoint = current_context->first;
				/* scan for insertion point */
				do {
					last = (ipoint->elem->order <= src->order);
				}
				while (last && ipoint->next && (ipoint = ipoint->next));

				if (last) {
					new_litem->previous = ipoint;
					ipoint->next = new_litem;
				}
				else {
					ipoint->previous->next = new_litem;
					new_litem->previous = ipoint->previous;
					ipoint->previous = new_litem;
					new_litem->next = ipoint;
				}
			}
		rv = ARCAN_OK;
	}

	return rv;
}

/* run through the chain and delete all occurences at ofs */
static void swipe_chain(surface_transform* base, unsigned int ofs)
{
	while (base) {
		memset((void*)base + ofs, 0, sizeof(unsigned int));
		base = base->next;
	}
}

arcan_errc arcan_video_detatchobject(arcan_vobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;
	arcan_vobject* src = arcan_video_getobject(id);

	if (src && src->owner) {
		arcan_vobject_litem* current_litem = src->owner;

/* with frameset objects, we can get a detatch call
 * even though it's not attached */
		if (!src->owner)
			return ARCAN_ERRC_UNACCEPTED_STATE;
			
		src->owner = NULL;

		/* double-linked */
		if (current_litem->previous)
			current_litem->previous->next = current_litem->next;
		else
			current_context->first = current_litem->next; /* only first cell lacks a previous node */

		if (current_litem->next)
			current_litem->next->previous = current_litem->previous;

		memset(current_litem, 0, sizeof(arcan_vobject_litem));
		free(current_litem);
	}

	return rv;
}

enum arcan_transform_mask arcan_video_getmask(arcan_vobj_id id)
{
	enum arcan_transform_mask mask = 0;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0)
		mask = vobj->mask;

	return mask;
}


arcan_errc arcan_video_transformmask(arcan_vobj_id id, enum arcan_transform_mask mask)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		vobj->mask = mask;
		rv = ARCAN_OK;
	}

	return rv;
}


arcan_errc arcan_video_linkobjs(arcan_vobj_id srcid, arcan_vobj_id parentid, enum arcan_transform_mask mask)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* src = arcan_video_getobject(srcid);
	arcan_vobject* dst = arcan_video_getobject(parentid);

	if (srcid == parentid || parentid == 0)
		dst = &current_context->world;

	if (src && src->flags.clone)
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;
	else if (src && dst) {
		arcan_vobject* current = dst;

		while (current) {
			if (current->parent == src)
				return ARCAN_ERRC_CLONE_NOT_PERMITTED;
			else
				current = current->parent;
		}
	
		src->parent = dst;

		swipe_chain(&src->transform, offsetof(surface_transform, time_rotate));
		swipe_chain(&src->transform, offsetof(surface_transform, time_move));
		swipe_chain(&src->transform, offsetof(surface_transform, time_opacity));
		swipe_chain(&src->transform, offsetof(surface_transform, time_scale));
		rv = ARCAN_OK;
		src->mask = mask;
	}

	return rv;
}

static void arcan_video_gldefault()
{
	glEnable(GL_TEXTURE_2D);
	glEnable(GL_SCISSOR_TEST);
	glDisable(GL_ALPHA_TEST);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_LIGHTING);
	glDisable(GL_FOG);
	glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
	glEnable(GL_BLEND);
	glClearColor(0.0, 0.0, 0.0, 1.0f);
	glAlphaFunc(GL_GREATER, 0);
	glMatrixMode(GL_PROJECTION);
	SDL_ShowCursor(0);
	glLoadIdentity();

	glOrtho(0, arcan_video_display.width, arcan_video_display.height, 0, 0, 1);
	glScissor(0, 0, arcan_video_display.width, arcan_video_display.height);
/*	glOrtho(ox, (float)current_context->world.current.w - 1.0f + ox, (float)current_context->world.current.h - 1.0 + oy,
	        oy, 0.0, (float)current_context->world.current.w - 1.0 + ox); */
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	glFrontFace(GL_CW);
	glCullFace(GL_BACK);
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
}

arcan_errc arcan_video_init(uint16_t width, uint16_t height, uint8_t bpp, bool fs, bool frames, bool conservative)
{
	/* some GL attributes have to be set before creating the video-surface */
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, 1);
	SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 1);
	SDL_WM_SetCaption("Arcan", "Arcan");

	arcan_video_display.fullscreen = fs;
	arcan_video_display.sdlarg = (fs ? SDL_FULLSCREEN : 0) | SDL_OPENGL | (frames ? SDL_NOFRAME : 0);
	arcan_video_display.screen = SDL_SetVideoMode(width, height, bpp, arcan_video_display.sdlarg);
	arcan_video_display.width = width;
	arcan_video_display.height = height;
	arcan_video_display.bpp = bpp;
	arcan_video_display.conservative = conservative;
		
	if (arcan_video_display.screen) {
		if (TTF_Init() == -1) {
			arcan_warning("Warning: arcan_video_init(), Couldn't initialize freetype. Text rendering disabled.\n");
			arcan_video_display.text_support = false;
		}
		else
			arcan_video_display.text_support = true;

		current_context->world.current.w = 1.0;
		current_context->world.current.h = 1.0;

		current_context->vitems_pool = (arcan_vobject*) calloc(sizeof(arcan_vobject), VITEM_POOLSIZE);
		arcan_video_gldefault();
		arcan_3d_setdefaults();
	}

#ifdef POOR_GL_SUPPORT
	glewInit();
#endif

	return arcan_video_display.screen ? ARCAN_OK : ARCAN_ERRC_BADVMODE;
}

uint16_t arcan_video_screenw()
{
	return arcan_video_display.screen ? arcan_video_display.screen->w : 0;
}

uint16_t arcan_video_screenh()
{
	return arcan_video_display.screen ? arcan_video_display.screen->h : 0;
}

static inline uint16_t nexthigher(uint16_t k)
{
	k--;
	for (int i=1; i < sizeof(uint16_t) * 8; i = i * 2)
		k = k | k >> i;
	return k+1;
}

/* this is not particularly reliable either */
void arcan_video_fullscreen()
{
	SDL_WM_ToggleFullScreen(arcan_video_display.screen);
}

static arcan_errc arcan_video_getimage(const char* fname, arcan_vobject* dst, arcan_vstorage* dstframe)
{
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;
	SDL_Surface* res = IMG_Load(fname);

	if (res) {
		/* quick workaround as the width / height specified in the target resoruce will be based
		 * on power-of-two padding due to GLtexture limits (not that they "exist" in 2.0 but better be safe ..) */
		dst->origw = res->w;
		dst->origh = res->h;
		dstframe->tag = ARCAN_TAG_IMAGE;
		dstframe->source = strdup(fname);
		
		/* let SDL do byte-order conversion and make sure we have BGRA, ... */
		SDL_Surface* gl_image =
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
		    SDL_CreateRGBSurface(SDL_SWSURFACE, res->w, res->h, 32, 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
#else
		    SDL_CreateRGBSurface(SDL_SWSURFACE, res->w, res->h, 32, 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000);
#endif
		SDL_SetAlpha(res, 0, SDL_ALPHA_TRANSPARENT);
		SDL_BlitSurface(res, NULL, gl_image, NULL);

		glGenTextures(1, &dst->gl_storage.glid);
		glBindTexture(GL_TEXTURE_2D, dst->gl_storage.glid);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, dst->gl_storage.txu);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, dst->gl_storage.txv);

		uint16_t neww, newh;
		if (dst->gl_storage.scale == ARCAN_VIMAGE_NOPOW2){
			neww = gl_image->w;
			newh = gl_image->h;
		}
		else {
			neww = nexthigher(gl_image->w);
			newh = nexthigher(gl_image->h);
		}
		
		dst->gl_storage.w = neww;
		dst->gl_storage.h = newh;
		
		dstframe->s_raw = neww * newh * 4;
		dstframe->raw = (uint8_t*) calloc(dstframe->s_raw, 1);

		/* line-by-line copy */

		if (newh != gl_image->h || neww != gl_image->w){
			if (dst->gl_storage.scale == ARCAN_VIMAGE_SCALEPOW2 && 
				(newh != gl_image->h || neww != gl_image->w))
				gluScaleImage(GL_PIXEL_FORMAT, 
							gl_image->w, gl_image->h, GL_UNSIGNED_BYTE, gl_image->pixels,
							neww, newh, GL_UNSIGNED_BYTE, dstframe->raw);
			
			else if (dst->gl_storage.scale == ARCAN_VIMAGE_TXCOORD){
				for (int row = 0; row < gl_image->h; row++)
					memcpy(&dstframe->raw[neww * row * 4],
						   &(((uint8_t*)gl_image->pixels)[gl_image->w * row * 4]),
						   gl_image->w * 4);

			/* Patch texture coordinates */
				float hx = (float)dst->origw / (float)dst->gl_storage.w;
				float hy = (float)dst->origh / (float)dst->gl_storage.h;
				generate_basic_mapping(dst->txcos, hx, hy);
			}
		}
		else
			memcpy(dstframe->raw, gl_image->pixels, dstframe->s_raw);
		
	/* whileas the gpu texture format is (4 byte alignment, BGRA) and the 
	 * glfunctions will waste membw- to convert to that, setting the "proper" 
	 * format here seems to generate a bad (full-white texture), investigate! */
		glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, neww, newh, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, dstframe->raw);

		SDL_FreeSurface(res);
		SDL_FreeSurface(gl_image);
		
		if (arcan_video_display.conservative){
			free(dst->default_frame.raw);
			dst->default_frame.raw = 0;
		}

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_allocframes(arcan_vobj_id id, uint8_t capacity)
{
	arcan_vobject* target = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (target && target->flags.clone)
		rv = ARCAN_ERRC_CLONE_NOT_PERMITTED;

	if (target && target->flags.clone == false) {
	/* ignore truncation and same- size */
		if (target->frameset_capacity < capacity) {
			arcan_vobject** newset = (arcan_vobject**) realloc(target->frameset, capacity * sizeof(arcan_vobject*));
			if (newset != NULL){
	/* during rendering, if the current frame is "empty", the default frame will be used */
				target->frameset = newset;
				memset(target->frameset + (target->frameset_capacity), 
					0,
					(capacity - target->frameset_capacity) * sizeof(arcan_vobject*));
				target->frameset_capacity = capacity;
				rv = ARCAN_OK;
			}
			else 
				rv = ARCAN_ERRC_OUT_OF_SPACE;
		}
		else if (target->frameset_capacity > capacity){
			
		}
	}

	return rv;
}

arcan_vobj_id arcan_video_rawobject(uint8_t* buf, size_t bufs, img_cons constraints, float origw, float origh, unsigned short zv)
{
	arcan_vobj_id rv = 0;

	if (buf && bufs == (constraints.w * constraints.h * constraints.bpp) && constraints.bpp == 4) {
		arcan_vobject* newvobj = arcan_video_newvobject(&rv);

		if (!newvobj)
			return ARCAN_EID;

		newvobj->gl_storage.w = constraints.w;
		newvobj->gl_storage.h = constraints.h;
		newvobj->origw = origw;
		newvobj->origh = origh;
		newvobj->current.opa = 0.0f;
		newvobj->current.angle = 0.0f;

	/* allocate */
		glGenTextures(1, &newvobj->gl_storage.glid);

		glBindTexture(GL_TEXTURE_2D, newvobj->gl_storage.glid);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

		newvobj->gl_storage.ncpt = constraints.bpp;
		newvobj->default_frame.s_raw = bufs;
		newvobj->default_frame.raw = buf;
		glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, newvobj->gl_storage.w, newvobj->gl_storage.h, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, newvobj->default_frame.raw);
		glBindTexture(GL_TEXTURE_2D, 0);
		newvobj->order = 0;
		arcan_video_attachobject(rv);
	}

	return rv;
}

arcan_errc arcan_video_setactiveframe(arcan_vobj_id dst, unsigned fid)
{
	arcan_vobject* dstvobj = arcan_video_getobject(dst);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (dstvobj){
		if (fid < dstvobj->frameset_capacity){
			if (dstvobj->frameset[fid])
				dstvobj->current_frame = dstvobj->frameset[fid];
			else
				dstvobj->current_frame = dstvobj;

			rv = ARCAN_OK;
		}
	}
	
	return rv;
}

arcan_errc arcan_video_setasframe(arcan_vobj_id dst, arcan_vobj_id src, unsigned fid, bool detatch)
{
	arcan_vobject* dstvobj = arcan_video_getobject(dst);
	arcan_vobject* srcvobj = arcan_video_getobject(src);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (dstvobj && srcvobj){
		if (fid < dstvobj->frameset_capacity){
			if (detatch)
				arcan_video_detatchobject(src);

			dstvobj->frameset[fid] = srcvobj;
		}
		else 
			rv = ARCAN_ERRC_OUT_OF_SPACE;
	}
	
	return rv;
}

arcan_vobj_id arcan_video_loadimage_asynch(const char* fname, img_cons constraints, arcan_errc* errcode)
{
    return ARCAN_ERRC_NO_SUCH_OBJECT;
}

arcan_vobj_id arcan_video_loadimage(const char* fname, img_cons constraints, arcan_errc* errcode)
{
	GLuint gtid = 0;
	arcan_vobj_id rv = 0;

	arcan_vobject* newvobj = arcan_video_newvobject(&rv);
	if (newvobj == NULL)
		return ARCAN_EID;
	
	arcan_errc rc = arcan_video_getimage(fname, newvobj, &newvobj->default_frame);

	if (rc == ARCAN_OK) {
		newvobj->current.x = 0;
		newvobj->current.y = 0;
		newvobj->current.opa = 1.0f;
		newvobj->current.angle = 0.0f;
	}
	else
		arcan_video_deleteobject(rv);

	if (errcode != NULL)
		*errcode = rc;

	return rv;
}


vfunc_state* arcan_video_feedstate(arcan_vobj_id id)
{
	void* rv = NULL;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		rv = &vobj->state;
	}

	return rv;
}

arcan_errc arcan_video_alterfeed(arcan_vobj_id id, arcan_vfunc_cb cb, vfunc_state state)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && vobj->flags.clone)
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;
	
	if (vobj && id > 0) {
		if (cb) {
			vobj->state = state;
			vobj->ffunc = cb;
			rv = ARCAN_OK;
			if (state.tag == ARCAN_TAG_3DOBJ){
				vobj->order = abs(vobj->order) * -1;
			} else vobj->order = abs(vobj->order);
		}
		else
			rv = ARCAN_ERRC_BAD_ARGUMENT;
	}

	return rv;
}

static int8_t empty_ffunc(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state state){
	return 0;
}

arcan_vfunc_cb arcan_video_emptyffunc()
{
	return (arcan_vfunc_cb) empty_ffunc;
}

arcan_vobj_id arcan_video_setupfeed(arcan_vfunc_cb ffunc, img_cons constraints, uint8_t ntus, uint8_t ncpt)
{
	if (!ffunc)
		return 0;

	arcan_vobj_id rv = 0;
	arcan_vobject* newvobj = arcan_video_newvobject(&rv);

	if (ffunc && newvobj) {
		arcan_vstorage* vstor = &newvobj->default_frame;
		/* preset */
		newvobj->current.x = 0;
		newvobj->current.y = 0;
		newvobj->origw = constraints.w;
		newvobj->origh = constraints.h;
		newvobj->current.opa = 1.0f;
		newvobj->current.angle = 0.0f;
		newvobj->gl_storage.ncpt = ncpt;

		if (newvobj->gl_storage.scale == ARCAN_VIMAGE_NOPOW2){
			newvobj->gl_storage.w = constraints.w;
			newvobj->gl_storage.h = constraints.h;
		}
		else {
		/* For feeds, we don't do the forced- rescale on every frame, way too expensive */
			newvobj->gl_storage.w = nexthigher(constraints.w);
			newvobj->gl_storage.h = nexthigher(constraints.h);
			float hx = (float)constraints.w / (float)newvobj->gl_storage.w;
			float hy = (float)constraints.h / (float)newvobj->gl_storage.h;
			generate_basic_mapping(newvobj->txcos, hx, hy);
		}

		/* allocate */
		glGenTextures(1, &newvobj->gl_storage.glid);

		glBindTexture(GL_TEXTURE_2D, newvobj->gl_storage.glid);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

		vstor->s_raw = newvobj->gl_storage.w * newvobj->gl_storage.h * newvobj->gl_storage.ncpt;
		vstor->raw = (uint8_t*) calloc(vstor->s_raw, 1);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, newvobj->gl_storage.w, newvobj->gl_storage.h, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, vstor->raw);
		glBindTexture(GL_TEXTURE_2D, 0);
		newvobj->ffunc = ffunc;
	}

	return rv;
}

/* some targets like to change size dynamically (thanks for that),
 * thus, drop the allocated buffers, generate new one and tweak txcos */
arcan_errc arcan_video_resizefeed(arcan_vobj_id id, img_cons constraints, bool mirror)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);
	
	if (vobj && vobj->flags.clone == true)
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;
	
	if (vobj) {
		free(vobj->default_frame.raw);
		
		if (vobj->gl_storage.scale == ARCAN_VIMAGE_NOPOW2){
			vobj->origw = vobj->gl_storage.w = constraints.w;
			vobj->origh = vobj->gl_storage.h = constraints.h;
		}
		else {
			vobj->gl_storage.w = nexthigher(constraints.w);
			vobj->gl_storage.h = nexthigher(constraints.h);
			vobj->origw = constraints.w;
			vobj->origh = constraints.h;
		}
		
		vobj->default_frame.s_raw = vobj->gl_storage.w * vobj->gl_storage.h * 4;
		vobj->default_frame.raw = (uint8_t*) calloc(vobj->default_frame.s_raw,1);

		float hx = vobj->gl_storage.scale == ARCAN_VIMAGE_NOPOW2 ? 1.0 : (float)constraints.w / (float)vobj->gl_storage.w;
		float hy = vobj->gl_storage.scale == ARCAN_VIMAGE_NOPOW2 ? 1.0 : (float)constraints.h / (float)vobj->gl_storage.h;

		/* as the dimensions may be different, we need to reinitialize the gl-storage as well */
		glBindTexture(GL_TEXTURE_2D, vobj->gl_storage.glid);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, vobj->gl_storage.w, vobj->gl_storage.h, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, vobj->default_frame.raw);
		if (mirror)
			generate_mirror_mapping(vobj->txcos, hx, hy);
		else
			generate_basic_mapping(vobj->txcos, hx, hy);
			
		glBindTexture(GL_TEXTURE_2D, 0);

		/* scale- values are no longer correct,
		 * to correct "in engine", rerun compact transform, set the object size to the newfound one,
		 * then push a system event.
		 * opted for the "in script" option, thus just pushing an event */
		arcan_event ev = {.category = EVENT_VIDEO, .kind = EVENT_VIDEO_RESIZED};
		ev.data.video.source = id;
		ev.data.video.constraints = constraints;
		ev.data.video.constraints.w = vobj->origw;
		ev.data.video.constraints.h = vobj->origh;
		arcan_event_enqueue(&ev);
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_vobj_id arcan_video_addobject(const char* rloc,img_cons constraints, unsigned short zv)
{
	arcan_vobj_id rv;

	if ((rv = arcan_video_loadimage((char*) rloc, constraints, NULL)) > 0) {
		arcan_vobject* vobj = arcan_video_getobject(rv);
		vobj->order = zv;
		arcan_video_attachobject(rv);
	}

	return rv;
}

arcan_vobj_id arcan_video_addfobject(arcan_vfunc_cb feed, vfunc_state state, img_cons constraints, unsigned short zv)
{
	arcan_vobj_id rv;
	const int feed_ntus = 1;

	if ((rv = arcan_video_setupfeed(feed, constraints, feed_ntus, constraints.bpp)) > 0) {
		arcan_vobject* vobj = arcan_video_getobject(rv);
		vobj->order = zv;
		vobj->state = state;

		if (state.tag == ARCAN_TAG_3DOBJ)
			vobj->order = -1 * zv;
		
		arcan_video_attachobject(rv);
	}

	return rv;
}

arcan_errc arcan_video_scaletxcos(arcan_vobj_id id, float sfs, float sft)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj){
		vobj->txcos[0] *= sfs; 	vobj->txcos[2] *= sfs; 	vobj->txcos[4] *= sfs; 	vobj->txcos[6] *= sfs;
		vobj->txcos[1] *= sft; 	vobj->txcos[3] *= sft; 	vobj->txcos[5] *= sft; 	vobj->txcos[7] *= sft;
				
		rv = ARCAN_OK;
	}

	return rv;
}

/*
 * This one is a mess,
 * (a) begin by splitting the input string into a linked list of data elements.
 * each element can EITHER modfiy to current cursor position OR represent a rendered surface.

 * (b) take the linked list, sweep through it and figure out which dimensions it requires,
 * allocate a corresponding storage object.

 * (c) sweep the list yet again, render to the storage object.
*/

// TTF_FontHeight sets line-spacing.
struct rcell {

	bool surface;
	unsigned int width;
	unsigned int height;

	union {
		SDL_Surface* surf;

		struct {
			uint8_t newline;
			uint8_t tab;
			bool cr;
		} format;
	} data;

	struct rcell* next;
};

/* Simple font-cache */
static TTF_Font* grab_font(const char* fname, uint8_t size)
{
	int leasti = 0, i;
	const int nchannels_rgba = 4;

	if (!fname || !arcan_video_display.text_support)
		return NULL;

	for (i = 0; i < font_cache_size; i++) {
		/* (a) no need to look further, either empty slot or no font found. */
		if (font_cache[i].data == NULL)
			break;
		if (strcmp(fname, font_cache[i].identifier) == 0 &&
		        font_cache[i].size == size) {
			font_cache[i].usecount++;
			return font_cache[i].data;
		}

		if (font_cache[i].usecount < font_cache[leasti].usecount)
			leasti = i;
	}

	/* (b) no match, no empty slot. */
	if (font_cache[i].data != NULL) {
		free(font_cache[leasti].identifier);
		TTF_CloseFont(font_cache[leasti].data);
	}
	else
		i = leasti;

	/* load in new font */
	font_cache[i].data = TTF_OpenFont(fname, size);
	font_cache[i].identifier = strdup(fname);
	font_cache[i].usecount = 1;
	font_cache[i].size = size;

	return font_cache[i].data;
}

/*
 * starting from a suspected format character,
 * repeatedly look for format characters.
 * When there is none- left to be found,
 */
struct text_format formatend(char* base, struct text_format prev, char* orig, bool* ok) {
	struct text_format failed = {0};
	prev.newline = prev.tab = prev.cr = 0; /* don't carry caret modifiers */
	
	bool inv = false;

	while (*base) {
		if (isspace(*base)) {
			base++;
			continue;
		}

		if (*base != '\\') {
			prev.endofs = base;
			break;
		}

		else {
		retry:
			switch (*(base+1)) {
					char* fontbase = base+1;
					char* numbase;
					char cbuf[2];

					/* missing; halign row, lalign row, ralign row */
				case '!':
					inv = true;
					base++;
					*base = '\\';
					goto retry;
					break;
				case 't':
					prev.tab++;
					base += 2;
					break;
				case 'n':
					prev.newline++;
					base += 2;
					break;
				case 'r':
					prev.cr = true;
					base += 2;
					break;
				case 'b':
					prev.style = (inv ? prev.style & !TTF_STYLE_BOLD : prev.style | TTF_STYLE_BOLD);
					inv = false;
					base+=2;
					break;
				case 'i':
					prev.style = (inv ? prev.style & !TTF_STYLE_ITALIC : prev.style | TTF_STYLE_ITALIC);
					inv = false;
					base+=2;
					break;
				case 'u':
					prev.style = (inv ? prev.style & TTF_STYLE_UNDERLINE : prev.style | TTF_STYLE_UNDERLINE);
					inv = false;
					base+=2;
					break;
				case '#':
					base += 2;
					for (int i = 0; i < 3; i++) {
						/* slide to cell */
						if (!isxdigit(*base) || !isxdigit(*(base+1))) {
							arcan_warning("Warning: arcan_video_renderstring(), couldn't scan font colour directive (#rrggbb, 0-9, a-f)\n");
							*ok = false;
// 							return failed;
						}

						base += 2;
					}
					/* now we know 6 valid chars are there, time to collect. */
					cbuf[0] = *(base - 6);
					cbuf[1] = *(base - 5);
					prev.col.r = strtol(cbuf, 0, 16);
					cbuf[0] = *(base - 4);
					cbuf[1] = *(base - 3);
					prev.col.g = strtol(cbuf, 0, 16);
					cbuf[0] = *(base - 2);
					cbuf[1] = *(base - 1);
					prev.col.b = strtol(cbuf, 0, 16);

					break;

// 					/* read 6(+2) characters, convert in pairs of two to hex, fill SDL_Color and set .alpha */
					break;
				case 'f':
					fontbase = (base += 2);
					while (*base != ',') {
						if (*base == 0) {
							arcan_warning("Warning: arcan_video_renderstring(), couldn't scan font directive '%s' (%s)\n", fontbase, orig);
							*ok = false;
							return failed;
						}
						base++;
					}

					*base = 0; /* now fontbase points to the full filename, wrap that through the resource finder */
					base++;
					numbase = base;

					while (*base != 0 && isdigit(*base))
						base++;

					if (numbase == base)
						arcan_warning("Warning: arcan_video_renderstring(), missing size argument in font specification (%s).\n", orig);
					else {
						char ch = *base;
						*base = 0;

						char* fname = arcan_find_resource(fontbase, ARCAN_RESOURCE_SHARED | ARCAN_RESOURCE_THEME);
						TTF_Font* font = NULL;

						if (!fname){
							arcan_warning("Warning: arcan_video_renderstring(), couldn't find font (%s) (%s)\n", fontbase, orig);
							*ok = false;
							return failed;
						}
						else
							if ((font =
							            grab_font(fname,
							                      strtoul(numbase, NULL, 10))) == NULL){
								arcan_warning("Warning: arcan_video_renderstring(), couldn't open font (%s) (%s)\n", fname, orig);
								free(fname);
								*ok = false;
								return failed;
							}
							else
								prev.font = font;

						free(fname);
						*base = ch;
					}

					/* scan until whitespace or ',' (filename) then if ',' scan to non-number */
					break;
				default:
					arcan_warning("Warning: arcan_video_renderstring(), unknown escape sequence: '\\%c' (%s)\n", *(base+1), orig);
					*ok = false;
					return failed;
			}
		}
	}

	if (*base == 0)
		prev.endofs = base;

//	printf("formatblock(lf:%i, tab:%i, cr:%i)\n", prev.newline, prev.tab, prev.cr);
	*ok = true;
	return prev;
}

/* a */
static int build_textchain(char* message, struct rcell* root, bool sizeonly)
{
	int rv = 0;
	struct text_format* curr_style = &current_context->curr_style;
	curr_style->col.r = curr_style->col.g = curr_style->col.b = 0xff;
	curr_style->style = 0;

	if (message) {
		struct rcell* cnode = root;
		char* current = message;
		char* base = message;
		int msglen = 0;

		/* outer loop, find first split- point */
		while (*current) {
			if (*current == '\\') {
				/* special case */
				if (*(current+1) == '\\') {
					memmove(current, current+1, strlen(current)+1);
					current += 1;
					msglen++;
				}
				else { /* split point found */
					if (msglen > 0) {
						*current = 0;
						/* render surface and slide window */
						if (!curr_style->font) {
							arcan_warning("Warning: arcan_video_renderstring(), no font specified / found.\n");
							return -1;
						}

						if (sizeonly){
							TTF_SetFontStyle(curr_style->font, curr_style->style);
							TTF_SizeUTF8(curr_style->font, base, (int*) &cnode->width, (int*) &cnode->height);
						}
						else{
							cnode->surface = true;
							TTF_SetFontStyle(curr_style->font, curr_style->style);
							cnode->data.surf = TTF_RenderUTF8_Blended(curr_style->font, base, curr_style->col);
							if (!cnode->data.surf)
								arcan_warning("Warning: arcan_video_renderstring(), couldn't render text, possible reason: %s\n", TTF_GetError());
							else
								SDL_SetAlpha(cnode->data.surf, 0, SDL_ALPHA_TRANSPARENT);
						}
						cnode = cnode->next = (struct rcell*) calloc(sizeof(struct rcell), 1);
						*current = '\\';
					}

					bool okstatus;
					*curr_style = formatend(current, *curr_style, message, &okstatus);
					if (!okstatus)
						return -1;

					/* caret modifiers need to be separately chained
					 * to avoid (three?) nasty little basecases */
					if (curr_style->newline || curr_style->tab || curr_style->cr) {
						cnode->surface = false;
						rv += curr_style->newline;
						cnode->data.format.newline = curr_style->newline;
						cnode->data.format.tab = curr_style->tab;
						cnode->data.format.cr = curr_style->cr;
						cnode = cnode->next = (void*) calloc(sizeof(struct rcell), 1);
					}

					current = base = curr_style->endofs;
					if (current == NULL)
						return -1; /* note, may this be a condition for a break rather than a return? */

					msglen = 0;
				}
			}
			else {
				msglen += 1;
				current++;
			}
		}

		/* last element .. */
		if (msglen && curr_style->font) {
			cnode->next = NULL;

			if (sizeonly){
				TTF_SetFontStyle(curr_style->font, curr_style->style);
				TTF_SizeUTF8(curr_style->font, base, (int*) &cnode->width, (int*) &cnode->height);
			}
			else{
				cnode->surface = true;
				TTF_SetFontStyle(curr_style->font, curr_style->style);
				cnode->data.surf = TTF_RenderUTF8_Blended(curr_style->font, base, curr_style->col);
				SDL_SetAlpha(cnode->data.surf, 0, SDL_ALPHA_TRANSPARENT);
			}
		}

		cnode = cnode->next = (void*) calloc(sizeof(struct rcell), 1);
		cnode->data.format.newline = 1;
		rv++;
	}

	return rv;
}

static unsigned int round_mult(unsigned num, unsigned int mult)
{
	if (num == 0 || mult == 0)
		return mult; /* intended ;-) */
	unsigned int remain = num % mult;
	return remain ? num + mult - remain : num;
}

/* tabs are messier still,
 * for each format segment, there may be 'tabc' number of tabsteps,
 * these concern only the current text block and are thus calculated from a fixed offset. */
static unsigned int get_tabofs(int offset, int tabc, int8_t tab_spacing, unsigned int* tabs)
{
	if (!tabs || *tabs == 0) /* tabc will always be >= 1 */
		return tab_spacing ? round_mult(offset, tab_spacing) + ((tabc - 1) * tab_spacing) : offset;

	unsigned int lastofs = offset;

	/* find last matching tab pos first */
	while (*tabs && *tabs < offset)
		lastofs = *tabs++;

	/* matching tab found */
	if (*tabs) {
		offset = *tabs;
		tabc--;
	}

	while (tabc--) {
		if (*tabs)
			offset = *tabs++;
		else
			offset += round_mult(offset, tab_spacing); /* out of defined tabs, pad with default spacing */

	}

	return offset;
}

static void dumptchain(struct rcell* node)
{
	int count = 0;

	while (node) {
		if (node->surface) {
			printf("[%i] image surface\n", count++);
		}
		else {
			printf("[%i] format (%i lines, %i tabs, %i cr)\n", count++, node->data.format.newline, node->data.format.tab, node->data.format.cr);
		}
		node = node->next;
	}
}

void arcan_video_stringdimensions(const char* message, int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, unsigned int* maxw, unsigned int* maxh)
{
	/* (A) */
	int chainlines;
	struct rcell root = {.surface = false};
	char* work = strdup(message);
	current_context->curr_style.newline = 0;
	current_context->curr_style.tab = 0;
	current_context->curr_style.cr = false;
	
	if ((chainlines = build_textchain(work, &root, true)) > 0) {
		struct rcell* cnode = &root;
		unsigned int linecount = 0;
		bool flushed = false;
		*maxw = 0;
		*maxh = 0;
		
		int lineh = 0;
		int curw = 0;
		int curh = 0;
		
		while (cnode) {
			if (cnode->width > 0) {
				if (cnode->height > lineh + line_spacing)
					lineh = cnode->height;

				curw += cnode->width;
			}
			else {
				if (cnode->data.format.cr)
					curw = 0;
				
				if (cnode->data.format.tab)
					curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);
				
				if (cnode->data.format.newline > 0)
					for (int i = cnode->data.format.newline; i > 0; i--) {
						*maxh += lineh + line_spacing;
						lineh = 0;
					}
			}
			
			if (curw > *maxw)
				*maxw = curw;
			
			cnode = cnode->next;
		}
	}

	struct rcell* current = root.next;
	
	while (current){
		struct rcell* prev = current;
		current = current->next;
		prev->next = (void*) 0xdeadbeef;
		free(prev);
	}

	free(work);
}
	
/* note: currently does not obey restrictions placed
 * on texturemode (i.e. everything is padded to power of two and txco hacked) */
arcan_vobj_id arcan_video_renderstring(const char* message, int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, unsigned int* n_lines, unsigned int** lineheights)
{
	arcan_vobj_id rv = ARCAN_EID;

	/* (A) */
	int chainlines;
	struct rcell* root = calloc( sizeof(struct rcell), 1);
	char* work = strdup(message);
	current_context->curr_style.newline = 0;
	current_context->curr_style.tab = 0;
	current_context->curr_style.cr = false;

	if ((chainlines = build_textchain(work, root, false)) > 0) {
		/* (B) */
		/*		dumptchain(&root); */
		struct rcell* cnode = root;
		unsigned int linecount = 0;
		bool flushed = false;
		int maxw = 0;
		int maxh = 0;
		int lineh = 0;
		int curw = 0;
		int curh = 0;
		/* note, linecount is overflow */
		unsigned int* lines = (unsigned int*) calloc(sizeof(unsigned int), chainlines + 1);
		unsigned int* curr_line = lines;

		while (cnode) {
			if (cnode->surface) {
				assert(cnode->data.surf != NULL);
				if (cnode->data.surf->h > lineh + line_spacing)
					lineh = cnode->data.surf->h;

				curw += cnode->data.surf->w;
			}
			else {
				if (cnode->data.format.cr)
					curw = 0;

				if (cnode->data.format.tab)
					curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);

				if (cnode->data.format.newline > 0)
					for (int i = cnode->data.format.newline; i > 0; i--) {
						lines[linecount++] = maxh;
						maxh += lineh + line_spacing;
						lineh = 0;
					}
			}

			if (curw > maxw)
				maxw = curw;

			cnode = cnode->next;
		}
		
		/* (C) */
		/* prepare structures */
		arcan_vobject* vobj = arcan_video_newvobject(&rv);
		if (!vobj){
			arcan_fatal("Fatal: arcan_video_renderstring(), couldn't allocate video object. Out of Memory or (more likely) out of IDs in current context. There is likely a resource leak in the scripts of the current theme.\n");
		}

		int storw = nexthigher(maxw);
		int storh = nexthigher(maxh);
		vobj->gl_storage.w = storw;
		vobj->gl_storage.h = storh;
		vobj->default_frame.s_raw = storw * storh * 4;
		vobj->default_frame.raw = (uint8_t*) calloc(vobj->default_frame.s_raw, 1);
		vobj->default_frame.tag = ARCAN_TAG_TEXT;
		vobj->flags.forceblend = true;
		vobj->origw = maxw;
		vobj->origh = maxh;
		vobj->current.opa = 1.0;
		vobj->parent = &current_context->world;
		glGenTextures(1, &vobj->gl_storage.glid);
		glBindTexture(GL_TEXTURE_2D, vobj->gl_storage.glid);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

		/* find dimensions and cleanup */
		cnode = root;
		curw = 0;
		int yofs = 0;

		SDL_Surface* canvas =
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
		    SDL_CreateRGBSurface(SDL_SWSURFACE, storw, storh, 32, 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
#else
		    SDL_CreateRGBSurface(SDL_SWSURFACE, storw, storh, 32, 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000);
#endif
		if (canvas == NULL)
			arcan_fatal("Fatal: arcan_video_renderstring(); couldn't build canvas.\n\t Input string is probably unreasonably large wide (len: %zi curw: %i)\n", strlen(message), curw);

		int line = 0;

		while (cnode) {
			if (cnode->surface) {
				SDL_Rect dstrect = {.x = curw, .y = lines[line]};
				SDL_BlitSurface(cnode->data.surf, 0, canvas, &dstrect);
				curw += cnode->data.surf->w;
			}
			else {
				if (cnode->data.format.tab > 0)
					curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);

				if (cnode->data.format.cr)
					curw = 0;

				if (cnode->data.format.newline > 0) {
					line += cnode->data.format.newline;
				}
			}
			
			cnode = cnode->next;
		}
	
	/* upload */
		memcpy(vobj->default_frame.raw, canvas->pixels, canvas->w * canvas->h * 4);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, canvas->w, canvas->h, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, vobj->default_frame.raw);
		glBindTexture(GL_TEXTURE_2D, 0);
	
		SDL_FreeSurface(canvas);

		float wv = (float)maxw / (float)vobj->gl_storage.w;
		float hv = (float)maxh / (float)vobj->gl_storage.h;

		generate_basic_mapping(vobj->txcos, wv, hv);
		arcan_video_attachobject(rv);

		if (n_lines)
			*n_lines = linecount;

		if (lineheights)
			*lineheights = lines;
		else
			free(lines);
	}
	
	struct rcell* current;

cleanup:
	current = root;
	while (current){
		assert(current != (void*) 0xdeadbeef);
		if (current->surface && current->data.surf)
			SDL_FreeSurface(current->data.surf);
			
		struct rcell* prev = current;
		current = current->next;
		prev->next = (void*) 0xdeadbeef;
		free(prev);
	}
	
	free(work);

	return rv;
}

arcan_errc arcan_video_forceblend(arcan_vobj_id id, bool on)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		vobj->flags.forceblend = on;

		rv = ARCAN_OK;
	}

	return rv;
}

/* change zval (see arcan_video_addobject) for a particular object.
 * return value is an error code */
arcan_errc arcan_video_setzv(arcan_vobj_id id, unsigned short newzv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		vobj->order = newzv;
		arcan_video_detatchobject(id);
		arcan_video_attachobject(id);
		rv = ARCAN_OK;
	}

	return rv;
}

/* forcibly kill videoobject after n cycles,
 * which will reset a counter that upon expiration invocates
 * arcan_video_deleteobject(arcan_vobj_id id)
 */
arcan_errc arcan_video_setlife(arcan_vobj_id id, unsigned lifetime)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		if (lifetime == 0)
			vobj->mask &= ~MASK_LIVING;
		else
			vobj->mask |= MASK_LIVING; /* forcetoggle living */
		
		vobj->lifetime = lifetime;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_zaptransform(arcan_vobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj) {
		surface_transform* current = vobj->transform.next;
		while (current) {
			surface_transform* next = current->next;
			free(current);
			current = next;
		}
		memset(&vobj->transform, 0, sizeof(surface_transform));
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_instanttransform(arcan_vobj_id id){
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj) {
			surface_transform* current = &vobj->transform;
			while (current){
				if (current->time_move){
					vobj->current.x = current->move[0];
					vobj->current.y = current->move[1];
				}
				
				if (current->time_opacity)
					vobj->current.opa = current->opa[0];
				
				if (current->time_rotate)
					vobj->current.angle = current->rotate[0];
				
				if (current->time_scale){
					vobj->current.w = current->scale[0];
					vobj->current.h = current->scale[1];
				}
				
				current = current->next;
			}
			
		arcan_video_zaptransform(id);
	}
	
	return rv;
}

/* removes an object immediately,
 * will also scan objects on the 'to expire' list
 * in order to avoid potential race conditions */
arcan_errc arcan_video_deleteobject(arcan_vobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		if (vobj->flags.clone == false) {
			if (vobj->ffunc)
				vobj->ffunc(ffunc_destroy, 0, 0, 0, 0, 0, 0, vobj->state);

			vobj->ffunc = NULL;
			vobj->state.tag = 0;
			vobj->state.ptr = NULL;
			
			kill_shader(&vobj->gl_storage.program, 
				&vobj->gl_storage.fragment,
			   &vobj->gl_storage.vertex
			);
			
			if (vobj->gl_storage.program)
				glDeleteProgram(vobj->gl_storage.program);

			glDeleteTextures(1, &vobj->gl_storage.glid);
		}
		arcan_video_detatchobject(id);

/* scan the current context, look for clones and other objects that has this object as a parent */
		arcan_vobject_litem* current;
retry:  
		current = current_context->first;
		
		while (current && current->elem) {
			arcan_vobject* elem = current->elem;
			arcan_vobject** frameset = elem->frameset;
		
		/* remove from frameset references */
			for (unsigned framecount = 0; framecount < elem->frameset_capacity; framecount++)
				if (frameset[framecount] == vobj)
					frameset[framecount] = (arcan_vobject*) NULL;
			
		/* how to deal with those that inherit? */
			if (elem->parent == vobj) {
				if (elem->flags.clone || (elem->mask & MASK_LIVING) == 0) {
					arcan_video_deleteobject(current->cellid);
					goto retry; /* no guarantee the structure is intact */
				}
				else /* inherit parent instead */
					elem->parent = vobj->parent;
			}

			current = current->next;
		}

		arcan_video_zaptransform(id);
		/* will also set in_use to false */
		memset(vobj, 0, sizeof(arcan_vobject));
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_override_mapping(arcan_vobj_id id, float* newmapping)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && id > 0) {
		float* fv = vobj->txcos;
		memcpy(vobj->txcos, newmapping, sizeof(float) * 8);
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_retrieve_mapping(arcan_vobj_id id, float* dst)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (vobj && dst && id > 0) {
		memcpy(dst, vobj->txcos, sizeof(float) * 8);
		rv = ARCAN_OK;
	}
	
	return rv;
}

arcan_errc arcan_video_objectrotate(arcan_vobj_id id, float angle, unsigned int tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj) {
		rv = ARCAN_OK;

		/* clear chains for rotate attribute
		 * if time is set to ovverride and be immediate */
		if (tv == 0) {
			swipe_chain(&vobj->transform, offsetof(surface_transform, time_rotate));
			vobj->current.angle = angle;
			vobj->transform.rotate[0] = angle;
		}
		else { /* find endpoint to attach at */
			float bv = (float) vobj->current.angle;

			surface_transform* base = &vobj->transform;
			surface_transform* last = base;

			/* figure out the starting angle */
			while (base && base->time_rotate) {
				bv = base->rotate[0] + base->rotate[1] * base->time_rotate;
				last = base;
				base = base->next;
			}

			if (!base)
				base = last->next = (surface_transform*) calloc(sizeof(surface_transform), 1);

			base->time_rotate = tv;
			base->rotate[0] = bv;
			base->rotate[1] = ((angle - bv) + 0.00001) / (float) tv;
		}
	}

	return rv;
}

/* alter object opacity, range 0..1 */
arcan_errc arcan_video_objectopacity(arcan_vobj_id id, float opa, unsigned int tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);
	opa = CLAMP(opa, 0.0, 1.0);

	if (vobj) {
		rv = ARCAN_OK;

		/* clear chains for rotate attribute
		 * if time is set to ovverride and be immediate */
		if (tv == 0) {
			swipe_chain(&vobj->transform, offsetof(surface_transform, time_opacity));
			vobj->current.opa = opa;
			vobj->transform.opa[0] = opa;
		}
		else { /* find endpoint to attach at */
			float bv = vobj->current.opa;

			surface_transform* base = &vobj->transform;
			surface_transform* last = base;

			while (base && base->time_opacity) {
				bv = base->opa[0] + base->opa[1] * base->time_opacity;
				last = base;
				base = base->next;
			}

			if (!base)
				base = last->next = (surface_transform*) calloc(sizeof(surface_transform), 1);

			base->time_opacity = tv;
			base->opa[0] = bv;
			base->opa[1] = ((opa - bv) + 0.00001) / (float) tv;
		}
	}

	return rv;
}

arcan_errc arcan_video_delaytransform(arcan_vobj_id id, uint8_t mask, unsigned tv){
	/* for each masked category,
	 * grab the last state of the transform
	 * and then add a new one with the same value and new 'tv' */
	return 0;
}

/* linear transition from current position to a new desired position,
 * if time is 0 the move will be instantaneous (and not generate an event)
 * otherwise time denotes how many ticks it should take to move the object
 * from its start position to it's final. An event will in this case be generated */
arcan_errc arcan_video_objectmove(arcan_vobj_id id, float newx, float newy, unsigned int tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj) {
		rv = ARCAN_OK;

		/* clear chains for rotate attribute
		 * if time is set to ovverride and be immediate */
		if (tv == 0) {
			swipe_chain(&vobj->transform, offsetof(surface_transform, time_move));
			vobj->current.x = newx;
			vobj->current.y = newy;
		}
		else { /* find endpoint to attach at */
			surface_transform* base = &vobj->transform;
			surface_transform* last = base;

			/* figure out the coordinates which the transformation is chained to */
			float bwx = vobj->current.x, bwy = vobj->current.y;

			while (base && base->time_move) {
				bwx = base->move[0] + base->move[2] * base->time_move;
				bwy = base->move[1] + base->move[3] * base->time_move;
				last = base;
				base = base->next;
			}

			if (!base)
				base = last->next = (surface_transform*) calloc(sizeof(surface_transform), 1);

			base->time_move = tv;
			base->move[0] = bwx;
			base->move[1] = bwy;

			/* k = (y-y0) / (x-x0), hack around div/0 */
			base->move[2] = ((newx - bwx)+0.0001) / (float) tv;
			base->move[3] = ((newy - bwy)+0.0001) / (float) tv;
		}
	}

	return rv;
}

/* scale the video object to match neww and newh, with stepx or stepy at 0 it will be instantaneous,
 * otherwise it will move at stepx % of delta-size each tick
 * return value is an errorcode, run through char* arcan_verror(int8_t) */
arcan_errc arcan_video_objectscale(arcan_vobj_id id, float wf, float hf, unsigned int tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj) {
		const int immediately = 0;
		rv = ARCAN_OK;

		if (tv == immediately) {
			swipe_chain(&vobj->transform, offsetof(surface_transform, time_scale));

			vobj->current.w = wf;
			vobj->current.h = hf;
		}
		else {
			surface_transform* base = &vobj->transform;
			surface_transform* last = base;

			/* figure out the coordinates which the transformation is chained to */
			float bww = vobj->current.w, bwh = vobj->current.h;

			while (base && base->time_scale) {
				bww = base->scale[0] + (base->scale[2] * base->time_scale);
				bwh = base->scale[1] + (base->scale[3] * base->time_scale);
				last = base;
				base = base->next;
			}

			if (!base)
				base = last->next = (surface_transform*) calloc(sizeof(surface_transform), 1);

			base->time_scale = tv;
			base->scale[0] = bww;
			base->scale[1] = bwh;
			/* k = (y-y0) / (x-x0) */
			base->scale[2] = ((wf - bww)+0.0001) / (float) tv;
			base->scale[3] = ((hf - bwh)+0.0001) / (float) tv;
		}
	}

	return rv;
}

static void dump_transformation(surface_transform* dst, int count)
{
	if (dst) {
		printf(": %" PRIxPTR ", %i, %i, %i, %i => : %" PRIxPTR "\n", (uintptr_t) dst, dst->time_opacity, dst->time_move, dst->time_scale, dst->time_rotate, (uintptr_t) dst->next);
		dump_transformation(dst->next, count + 1);
	}

	if (count == 0)
		printf("[/Object Transformation Matrix]\n");
}

/* called whenever a cell in update has a time that reaches 0 */
static void compact_transformation(surface_transform* dst, unsigned int ofs, unsigned int count)
{
	surface_transform* last = NULL;
	surface_transform* work = dst;
	/* copy the next transformation */
	
	while (work && work->next) {
		assert(work != work->next);
		memcpy((void*)(work) + ofs, (void*)(work->next) + ofs, count);
		last = work;
		work = work->next;
	}

	/* reset the last one */
	*((uint8_t*) work + ofs) = 0;

	/* if it is now empty, free and delink */
	if (work && work != dst &&
	        !(work->time_move |
	          work->time_opacity |
	          work->time_rotate |
	          work->time_scale)
	   )	{
		free(work);
		last->next = NULL;
	}
}

arcan_errc arcan_video_setprogram(arcan_vobj_id id, const char* vprogram, const char* fprogram)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && vobj->flags.clone == true)
		rv = ARCAN_ERRC_CLONE_NOT_PERMITTED;
	else if (vobj && id > 0) {
		if (vprogram)
			vobj->gpu_program.vertex = strdup(vprogram);
		if (fprogram)
			vobj->gpu_program.fragment = strdup(fprogram);
		
		build_shader(&vobj->gl_storage.program, &vobj->gl_storage.vertex, &vobj->gl_storage.fragment, vprogram, fprogram);
	}

	return rv;
}

static bool update_object(arcan_vobject* ci, unsigned int stamp)
{
	bool upd = false;

	if (ci->last_updated == stamp)
		return false;
	
/* update parent if this has not already been updated this cycle */
	if (ci->last_updated < stamp && 
		ci->parent && ci->parent != &current_context->world && 
		ci->parent->last_updated != stamp){
		update_object(ci->parent, stamp);
	}
	
	ci->last_updated = stamp;
	/* movement */
	if (ci->transform.time_move > 0) {
		upd = true;
		ci->current.x = ci->transform.move[0] += ci->transform.move[2];
		ci->current.y = ci->transform.move[1] += ci->transform.move[3];
		ci->transform.time_move--;

		if (ci->transform.time_move == 0) {
			compact_transformation(&ci->transform,
			                       offsetof(surface_transform, time_move),
			                       sizeof(unsigned int) + sizeof(float) * 4);

			/* no more events to process, fire event */
			if (ci->transform.time_move == 0 && ci->owner) {
				arcan_event ev = {.category = EVENT_VIDEO, .kind = EVENT_VIDEO_MOVED};
				ev.data.video.source = ci->owner->cellid;
				arcan_event_enqueue(&ev);
			}
		}

	}

	/* scale */
	if (ci->transform.time_scale > 0) {
		upd = true;
		ci->current.w = ci->transform.scale[0] += ci->transform.scale[2];
		ci->current.h = ci->transform.scale[1] += ci->transform.scale[3];
		ci->transform.time_scale--;

		if (ci->transform.time_scale == 0) {
			compact_transformation(&ci->transform,
			                       offsetof(surface_transform, time_scale),
			                       sizeof(unsigned int) + sizeof(float) * 4);

			if (ci->transform.time_scale == 0 && ci->owner) {
				arcan_event ev = {.category = EVENT_VIDEO, .kind = EVENT_VIDEO_SCALED};
				ev.data.video.source = ci->owner->cellid;
				arcan_event_enqueue(&ev);
			}
		}
	}

	/* opacity */
	if (ci->transform.time_opacity > 0) {
		upd = true;
		ci->current.opa = ci->transform.opa[0] += ci->transform.opa[1];
		ci->transform.time_opacity--;

		if (ci->transform.time_opacity == 0) {
			compact_transformation(&ci->transform,
			                       offsetof(surface_transform, time_opacity),
			                       sizeof(unsigned int) + sizeof(float) * 2);

			if (ci->transform.time_opacity == 0 && ci->owner) {
				arcan_event ev = {.category = EVENT_VIDEO, .kind = EVENT_VIDEO_BLENDED};
				ev.data.video.source = ci->owner->cellid;
				arcan_event_enqueue(&ev);
			}
		}
	}

	/* orientation */
	if (ci->transform.time_rotate > 0) {
		upd = true;
		ci->current.angle = ci->transform.rotate[0] += ci->transform.rotate[1];
		ci->transform.time_rotate--;

		if (ci->transform.time_rotate == 0) {
			compact_transformation(&ci->transform,
			                       offsetof(surface_transform, time_rotate),
			                       sizeof(unsigned int) + sizeof(float) * 2);

			if (ci->transform.time_rotate == 0 && ci->owner) {
				arcan_event ev = {.category = EVENT_VIDEO, .kind = EVENT_VIDEO_ROTATED};
				ev.data.video.source = ci->owner->cellid;
				arcan_event_enqueue(&ev);
			}
		}
	}

	return upd;
}

/* process a logical time-frame (which more or less means, update / rescale / redraw / flip)
 * returns msecs elapsed */
uint32_t arcan_video_tick(uint8_t steps)
{
	unsigned now = SDL_GetTicks();
	arcan_vobject_litem* current = current_context->first;
	update_object(&current_context->world, now);

	while (steps--) {
		arcan_video_display.c_ticks++;
		
		if (current)
 			do {
				arcan_vobject* elem = current->elem;
			
				/* is the item to be updated? */
				update_object(elem, now);
				if (elem->ffunc)
					elem->ffunc(ffunc_tick, 0, 0, 0, 0, 0, 0, elem->state);
				
				if ((elem->mask & MASK_LIVING) > 0) {
					if (elem->lifetime <= 0) {
						/* generate event (don't fire until deleted though) */
						arcan_event dobjev = {
							.category = EVENT_VIDEO,
							.kind = EVENT_VIDEO_EXPIRE
						};
						uint32_t tid = current->cellid;
						dobjev.tickstamp = arcan_video_display.c_ticks;
						dobjev.data.video.source = tid;

						arcan_event_enqueue(&dobjev);
						/* disable the LIVING mask, otherwise we'd fire multiple
						 * expire events when video logic is lagging behind */
						elem->mask &= ~MASK_LIVING;
					}
					else {
						elem->lifetime--;
					}
				}
			}
			while ((current = current->next) != NULL);

		current = current_context->first;
	}

	return 0;
}

arcan_errc arcan_video_setclip(arcan_vobj_id id, bool toggleon)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		vobj->flags.cliptoparent = toggleon;
		rv = ARCAN_OK;
	}
	
	return rv;
}

/* push some of the most useful context/video information
 * into the specified shader (assuming there's matching uniforms).
 * This should really be replaced with something more clever .. */
static void _setgl_stdargs(GLuint progr)
{
	GLint tick_count = glGetUniformLocation(progr, "n_ticks");

	if (tick_count != -1) {
		glUniform1i(tick_count, arcan_video_display.c_ticks);
	}
}

bool arcan_video_visible(arcan_vobj_id id)
{
	bool rv = false;
	arcan_vobject* vobj= arcan_video_getobject(id);

	if (vobj && id > 0)
		return vobj->current.opa > 0.001;

	return rv;
}

/* just draw a 'good ol' quad';
 * for GL3/GLES? compat. replace this with a small buffer ... */
static inline void draw_vobj(float x, float y, float x2, float y2, float zv, float* txcos)
{
	GLfloat verts[] = { x,y, x2,y, x2,y2, x,y2 };

    glVertexPointer(2, GL_FLOAT, 0, verts);
    glTexCoordPointer(2, GL_FLOAT, 0, txcos);
    glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
}

/* take sprops, apply them to the coordinates in vobj with proper masking (or force to ignore mask), store the results in dprops */
static void apply(arcan_vobject* vobj, surface_properties* dprops, float lerp, surface_properties* sprops, bool force)
{
	*dprops = vobj->current;
	
/* apply within own dimensions */
	if (vobj->transform.time_move){
		dprops->x = vobj->transform.move[0] + vobj->transform.move[2] * lerp;
		dprops->y = vobj->transform.move[1] + vobj->transform.move[3] * lerp;
	}
	
	if (vobj->transform.time_scale) {
		dprops->w = vobj->transform.scale[0] + vobj->transform.scale[2] * lerp;
		dprops->h = vobj->transform.scale[1] + vobj->transform.scale[3] * lerp;
	}

	if (vobj->transform.time_opacity)
		dprops->opa = vobj->transform.opa[0] + vobj->transform.opa[1] * lerp;

	if (vobj->transform.time_rotate)
		dprops->angle = vobj->transform.rotate[0] + vobj->transform.rotate[1] * lerp;
	
	if (!sprops)
		return;

/* translate to sprops */
	if (force || (vobj->mask & MASK_POSITION) > 0){
		dprops->x += sprops->x;
		dprops->y += sprops->y;
	}
	
	if (force || (vobj->mask & MASK_ORIENTATION) > 0)
		dprops->angle += sprops->angle;
		
	if (force || (vobj->mask & MASK_OPACITY) > 0)
		dprops->opa *= sprops->opa;
	
	if (force || (vobj->mask & MASK_SCALE) > 0){
		dprops->w *= sprops->w;
		dprops->h *= sprops->h;
	}
}

/* this is really grounds for some more elaborate caching strategy if CPU- bound.
 * using some frame- specific tag so that we don't repeatedly resolve with this complexity. */
void arcan_resolve_vidprop(arcan_vobject* vobj, float lerp, surface_properties* props)
{
	if (vobj->parent != &current_context->world){
		surface_properties dprop = {0};
		arcan_resolve_vidprop(vobj->parent, lerp, &dprop);
		apply(vobj, props, lerp, &dprop, false);
	} else {
		apply(vobj, props, lerp, &current_context->world.current, true);
	}
}

static inline void draw_surf(surface_properties prop, arcan_vobject* src, float* txcos)
{
	prop.w *= src->origw * 0.5;
	prop.h *= src->origh * 0.5;
	
	glPushMatrix();
		glTranslatef( prop.x + prop.w, prop.y + prop.h, 0.0);
		glRotatef( -1 * prop.angle, 0.0, 0.0, 1.0);
		draw_vobj(-prop.w, -prop.h, prop.w, prop.h, 0, txcos);
	glPopMatrix();
}

void arcan_video_pollfeed()
{
	arcan_vobject_litem* current = current_context->first;

	while(current){
/* feed objects require a check for changes
 * and re-uploading texture */
		arcan_vobject* elem = current->elem;
		arcan_vstorage* evstor = &elem->default_frame;

		if ( elem->ffunc &&
		elem->ffunc(ffunc_poll, 0, 0, 0, 0, 0, 0, elem->state) == FFUNC_RV_GOTFRAME) {
			enum arcan_ffunc_rv funcres = elem->ffunc(ffunc_render,
			evstor->raw, evstor->s_raw,
			elem->gl_storage.w, elem->gl_storage.h, elem->gl_storage.ncpt,
			elem->gl_storage.glid,
			elem->state);
			
/* special "hack" for situations where the ffunc can do the gl-calls
 * without an additional memtransfer (some video/targets, particularly in no POW2 Textures) */
			if (funcres == FFUNC_RV_COPIED){
				glBindTexture(GL_TEXTURE_2D, elem->current_frame->gl_storage.glid);
				glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, elem->current_frame->gl_storage.w, elem->current_frame->gl_storage.h, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, evstor->raw);
			}
		}

		current = current->next;
	}
}

/* assumes working ortographic projection matrix based on current resolution,
 * redraw the entire scene and linearly interpolate transformations */
void arcan_video_refresh_GL(float lerp)
{
	arcan_vobject_litem* current = current_context->first;
	glClear(GL_COLOR_BUFFER_BIT);
	glEnable(GL_TEXTURE_2D);
	
	arcan_vobject* world = &current_context->world;

/* start with a pristine projection matrix,
 * as soon as we reach order == 0 (2D) we switch to a ortographic projection */
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();

	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();


/* first, handle all 3d work (which may require multiple passes etc.) */
	if (current && current->elem->order < 0){
		current = arcan_refresh_3d(current, lerp);
	}

/* if there are any nodes left, treat them as 2D (ortographic projection) */
	if (current){
		glDisable(GL_DEPTH_TEST);
		glMatrixMode(GL_PROJECTION);
		glLoadIdentity();
		glOrtho(0, arcan_video_display.width, arcan_video_display.height, 0, 0, 1);
		glScissor(0, 0, arcan_video_display.width, arcan_video_display.height);
		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();
	
		while (current){
			arcan_vobject* elem = current->elem;
			arcan_vstorage* evstor = &elem->default_frame;
			surface_properties* csurf = &elem->current;

			/* calculate coordinate system translations, 
			* world cannot be masked */
			surface_properties dprops;
			arcan_resolve_vidprop(elem, lerp, &dprops);
	
		/* time for the drawcall, assuming object is visible
		 * add occlusion test / blending threshold here ..
		 * note that objects will have been sorted based on Z already.
		 * order is split in a negative (3d) and positive (2D), negative are handled through ffunc. 
		 */
			if ( elem->order >= 0 && dprops.opa > 0.001){
				glBindTexture(GL_TEXTURE_2D, elem->current_frame->gl_storage.glid);
				glUseProgram(elem->current_frame->gl_storage.program);
				_setgl_stdargs(elem->current_frame->gl_storage.program);
				
				if (dprops.opa > 0.999 && !elem->flags.forceblend){
					glDisable(GL_BLEND);
				}
				else{
					glEnable(GL_BLEND);
					glColor4f(1.0, 1.0, 1.0, dprops.opa);
				}
				
				if (elem->flags.cliptoparent && elem->parent != &current_context->world){
				/* toggle stenciling, reset into zero, draw parent bounding area to stencil only,
				 * redraw parent into stencil, draw new object then disable stencil. */
					glEnable(GL_STENCIL_TEST);
					glClearStencil(0);
					glClear(GL_STENCIL_BUFFER_BIT);
					glColorMask(0, 0, 0, 0);
					glStencilFunc(GL_ALWAYS, 1, 1);
					glStencilOp(GL_REPLACE, GL_REPLACE, GL_REPLACE);

					arcan_vobject* celem = elem;

				/* since we can have hierarchies of partially clipped, we may need to resolve all */
					while (celem->parent != &current_context->world){
						surface_properties pprops;
						arcan_resolve_vidprop(celem->parent, lerp, &pprops);
						if (celem->parent->flags.cliptoparent == false)
							draw_surf(pprops, celem->parent, elem->current_frame->txcos);

						celem = celem->parent;
					}

					glColorMask(1, 1, 1, 1);
					glStencilFunc(GL_EQUAL, 1, 1);
					glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);

					draw_surf(dprops, elem, elem->current_frame->txcos);
					glDisable(GL_STENCIL_TEST);
				} else {
					draw_surf(dprops, elem, elem->current_frame->txcos);
				}
			}

			current = current->next;
		}
	}

	glDisable(GL_TEXTURE_2D);
}

void arcan_video_refresh(float tofs)
{
	arcan_video_refresh_GL(tofs);
	SDL_GL_SwapBuffers();
}

void arcan_video_default_scalemode(enum arcan_vimage_mode newmode)
{
	arcan_video_display.scalemode = newmode;
}

void arcan_video_default_texmode(enum arcan_vtex_mode modes, enum arcan_vtex_mode modet)
{
	arcan_video_display.deftxs = modes == ARCAN_VTEX_REPEAT ? GL_REPEAT : GL_CLAMP_TO_EDGE;
	arcan_video_display.deftxt = modet == ARCAN_VTEX_REPEAT ? GL_REPEAT : GL_CLAMP_TO_EDGE;
}

bool arcan_video_hittest(arcan_vobj_id id, unsigned int x, unsigned int y)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	
	if (vobj && id > 0) {
		surface_properties current = vobj->current;
		current.w *= vobj->origw;
		current.h *= vobj->origh;
		
		float lx = (float)x, ly = (float)y;

		/* convert to radians */
		float theta = current.angle * (2.0f * 3.14f / 360.0f);

		/* translate */
		float ox = current.x + current.w * 0.5;
		float oy = current.y + current.h * 0.5;
		float tx = x - ox;
		float ty = y - oy;

		/* rotate translated coordinates into dst- space */
		float rx = tx * cos(theta) - ty * sin(theta);
		float ry = tx * sin(theta) + ty * cos(theta);

		/* reverse translation, lx / ly now corresponds to the rotated coordinates */
		lx = rx + ox;
		ly = ry + oy;

		if (
		    (lx > (current.x) && lx < (current.x + current.w)) &&
		    (ly > (current.y) && ly < (current.y + current.h))
		) {
			/* should check if there's a collision mask added (and scale rotate coords into correct space)
			 * scale coordinates to 'fit' the proper range, extract the byte and then extract correct 'bits'
			 * as the mask only requires (w/8) * (h/8) bits of storage */
			return true;
		}

	}
	return false;
}

unsigned int arcan_video_pick(arcan_vobj_id* dst, unsigned int count, int x, int y)
{
	if (count == 0)
		return 0;

	arcan_vobject_litem* current = current_context->first;
	uint32_t base = 0;

	while (current && base < count) {
		if (arcan_video_hittest(current->cellid, x, y) && current->cellid && !(current->elem->mask & MASK_UNPICKABLE))
			dst[base++] = current->cellid;
		current = current->next;
	}

	return base;
}

/* just a wrapper for 'style' */
img_cons arcan_video_dimensions(uint16_t w, uint16_t h)
{
	img_cons res = {w, h};
	return res;
}

void arcan_video_dumppipe()
{
	arcan_vobject_litem* current = current_context->first;
	uint32_t count = 0;
	printf("-----------\n");
	if (current)
		do {
			printf("[%i] #(%i) - (ID:%u) (Order:%i) (Dimensions: %f, %f - %f, %f) (Opacity:%f)\n", current->elem->flags.in_use, count++, (unsigned) current->cellid, current->elem->order,
			       current->elem->current.x, current->elem->current.y, current->elem->current.w, current->elem->current.h, current->elem->current.opa);
		}
		while ((current = current->next) != NULL);
	printf("-----------\n");
}

/* the actual storage dimensions,
 * as these might concern "% 2" texture requirement */
img_cons arcan_video_storage_properties(arcan_vobj_id id)
{
	img_cons res = {.w = 0, .h = 0, .bpp = 0};
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		res.w = vobj->gl_storage.w;
		res.h = vobj->gl_storage.h;
		res.bpp = vobj->gl_storage.ncpt;
	}

	return res;
}

/* image dimensions at load time, without
 * any transformations being applied */
surface_properties arcan_video_initial_properties(arcan_vobj_id id)
{
	surface_properties res = {.x = 0, .y = 0, .w = 0, .h = 0};
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		res.w = vobj->origw;
		res.h = vobj->origh;
	}

	return res;
}

surface_properties arcan_video_current_properties(arcan_vobj_id id)
{
	surface_properties rv = {.x = 0 };
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		rv = vobj->current;
		rv.w *= vobj->origw;
		rv.h *= vobj->origh;
	}
	
	return rv;
}

/* Assuming current transformation chain,
 * what will the properties of the surface be in n ticks from now?
 *
 * does this by copying the object, then running the transformation chain
 * n times, copies the results and removes the object copy */
surface_properties arcan_video_properties_at(arcan_vobj_id id, uint32_t ticks)
{
	surface_properties rv = {.x = 0 };
	arcan_vobject* vobj = arcan_video_getobject(id);

	arcan_event_maskall();
	if (vobj && id > 0 && (vobj = arcan_video_dupobject(vobj))) {
		while (ticks--)
			update_object(vobj, 0);

		rv = vobj->current;
		rv.w *= vobj->origw;
		rv.h *= vobj->origh;
		arcan_video_remdup(vobj);
	}
	arcan_event_clearmask();
	
	return rv;
}

bool arcan_video_prepare_external()
{
	/* There seems to be no decent, portable, way to minimize + suspend and when child terminates, maximize and be 
	 * sure that OpenGL / SDL context data is restored respectively. Thus we destroy the surface,
	 * and then rebuild / reupload all textures. */
	if (-1 == arcan_video_pushcontext())
		return false;
	
	SDL_FreeSurface(arcan_video_display.screen);
	if (arcan_video_display.fullscreen)
		SDL_QuitSubSystem(SDL_INIT_VIDEO);

	/* We need to kill of large parts of SDL as it may hold locks on other resources that the external launch might need */
	arcan_event_deinit();

	return true;
}

void arcan_video_restore_external()
{
	if (arcan_video_display.fullscreen)
		SDL_Init(SDL_INIT_VIDEO);

	arcan_video_display.screen = SDL_SetVideoMode(arcan_video_display.width,
											arcan_video_display.height, 
											arcan_video_display.bpp, 
											arcan_video_display.sdlarg);
	arcan_event_init();
	arcan_video_gldefault();
	arcan_video_popcontext();
}

void arcan_video_shutdown()
{
	arcan_vobject_litem* current = current_context->first;
	unsigned lastctxa, lastctxc = arcan_video_popcontext();

/*  this will effectively make sure that all external launchers, frameservers etc. gets killed off */
	while ( lastctxc != (lastctxa = arcan_video_popcontext()) )
		lastctxc = lastctxa;

	SDL_QuitSubSystem(SDL_INIT_VIDEO);
}
