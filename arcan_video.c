/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
 *
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <signal.h>
#include <stddef.h>
#include <math.h>
#include <assert.h>
#include <errno.h>

#include <pthread.h>
#include <semaphore.h>

#define CLAMP(x, l, h) (((x) > (h)) ? (h) : (((x) < (l)) ? (l) : (x)))

#ifndef ASYNCH_CONCURRENT_THREADS
#define ASYNCH_CONCURRENT_THREADS 12 
#endif

#include GL_HEADERS

#include "arcan_math.h"
#include "arcan_general.h"
#include "platform/platform.h"
#include "arcan_video.h"
#include "arcan_ttf.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_frameserver_backend.h"
#include "arcan_target_const.h"
#include "arcan_target_launcher.h"
#include "arcan_shdrmgmt.h"
#include "arcan_videoint.h"
#include "arcan_img.h"

#ifndef offsetof
#define offsetof(type, member) ((size_t)((char*)&(*(type*)0).member\
 - (char*)&(*(type*)0)))
#endif

long long ARCAN_VIDEO_WORLDID = -1;
static surface_properties empty_surface();
static sem_t asynchsynch;

struct arcan_video_display arcan_video_display = {
	.bpp = 0, .width = 0, .height = 0, .conservative = false,
	.deftxs = GL_CLAMP_TO_EDGE, .deftxt = GL_CLAMP_TO_EDGE,
	.scalemode = ARCAN_VIMAGE_NOPOW2,
	.filtermode = ARCAN_VFILTER_BILINEAR,
	.suspended = false,
	.vsync = true,
	.msasamples = 4,
	.c_ticks = 1,
	.default_vitemlim = 1024,
	.imageproc = imageproc_normal,
    .mipmap = true
};

struct arcan_video_context vcontext_stack[CONTEXT_STACK_LIMIT] = {
	{
		.n_rtargets = 0,
		.vitem_ofs = 1,
		.nalive    = 0,
		.world = {
			.tracetag = "(world)",
			.current  = {
				.opa = 1.0,
.rotation.quaternion.w = 1.0
			}
		}
	}
};
unsigned vcontext_ind = 0;

/* 
 * additional internal forwards that do not really belong to videoint.h 
 */ 
static bool detach_fromtarget(struct rendertarget* dst, arcan_vobject* src);
static void attach_object(struct rendertarget* dst, arcan_vobject* src);
static void reorder_object(struct rendertarget* dst, arcan_vobject* src);
static arcan_errc update_zv(arcan_vobject* vobj, unsigned short newzv);
static void rebase_transform(struct surface_transform*, arcan_tickv);
static bool alloc_fbo(struct rendertarget* dst);
static bool activate_fbo(struct rendertarget* dst);
static void process_rendertarget(struct rendertarget* tgt, float fract);
static arcan_vobject* new_vobject(arcan_vobj_id* id, 
struct arcan_video_context* dctx);
static inline void build_modelview(float* dmatr, 
	float* imatr, surface_properties* prop, arcan_vobject* src);

static inline void trace(const char* msg, ...)
{
#ifdef TRACE_ENABLE
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
#endif
}

static const char* video_tracetag(arcan_vobject* src)
{
	return src == NULL || src->tracetag == NULL ? "(unknown)" : src->tracetag;
}

/* a default more-or-less empty context */
static struct arcan_video_context* current_context = vcontext_stack;

static void drop_glres(struct storage_info_t* s)
{
	assert(s->refcount);
	s->refcount--;

	if (s->refcount == 0){
		if (s->txmapped != TXSTATE_OFF && s->vinf.text.glid){
			glDeleteTextures(1, &s->vinf.text.glid);

			if (s->vinf.text.raw)
				free(s->vinf.text.raw);
		}

		memset(s, '\0', sizeof(struct storage_info_t));
		free(s);
	}
}

void push_globj(arcan_vobject* dst, bool noupload, 
		struct arcan_img_meta* meta)
{
	struct storage_info_t* s = dst->vstore; 
	if (s->txmapped == TXSTATE_OFF)
		return;

	if (noupload)
		glBindTexture(GL_TEXTURE_2D, s->vinf.text.glid);
	else{
		glGenTextures(1, &s->vinf.text.glid); 
		s->refcount = 1;
		glBindTexture(GL_TEXTURE_2D, s->vinf.text.glid);
	}

	assert(dst->vstore->txu != 0);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, s->txu);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, s->txv);

/* 
 * Mipmapping API/ Mapping is a bit clumsy at the moment,
 * should be reworked to individual vobj- setting
 * that can handle different sources for different mipmap
 * levels
 */
	bool mipmap = arcan_video_display.mipmap;
#ifndef GL_GENERATE_MIPMAP
		if (mipmap)
			glGenerateMipmap(GL_TEXTURE_2D);
#else
		glTexParameteri(GL_TEXTURE_2D, GL_GENERATE_MIPMAP, mipmap);
#endif

	switch (s->filtermode){
	case ARCAN_VFILTER_NONE:
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	break;

	case ARCAN_VFILTER_LINEAR:
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	break;

	case ARCAN_VFILTER_BILINEAR:
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	break;

	case ARCAN_VFILTER_TRILINEAR:
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, 
			GL_LINEAR_MIPMAP_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	break;
	}

	if (!noupload){
/*
 * some drivers expose this kind of functionality, but with CodeXL/GDEbugger etc.
 * support being a bit sketchy, this little hack can be enabled with a debugbuild
 * and a txdump subfolder in cwd 
 */
#ifdef _DEBUG
		if (arcan_video_display.txdump && s->vinf.text.raw){
			static int seqn = 0;
			int outfd = fmt_open(O_RDWR | O_CREAT, S_IRWXU, "%sgldump%d.png", 
				arcan_video_display.txdump, seqn++);
			if (-1 != outfd)
				arcan_rgba32_pngfile(outfd, 
					(char*) s->vinf.text.raw, s->w, s->h, false);
		}
#endif
		if (s->txmapped == TXSTATE_DEPTH)
			glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, s->w, s->h, 0,
				GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, 0);
		else
			glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, s->w, s->h, 
				0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, s->vinf.text.raw);
	}

	if (arcan_video_display.conservative){
		free(s->vinf.text.raw);
		s->vinf.text.raw = NULL;
		s->vinf.text.s_raw = 0;
	}

	glBindTexture(GL_TEXTURE_2D, 0);
}

void arcan_video_default_texfilter(enum arcan_vfilter_mode mode)
{
	arcan_video_display.filtermode = mode;
}

void arcan_video_default_imageprocmode(enum arcan_imageproc_mode mode)
{
	arcan_video_display.imageproc = mode;
}

static struct rendertarget* find_rendertarget(arcan_vobject* vobj)
{
	for (int i = 0; i < current_context->n_rtargets && vobj; i++)
		if (current_context->rtargets[i].color == vobj)
			return &current_context->rtargets[i];

	return NULL;
}

static void addchild(arcan_vobject* parent, arcan_vobject* child)
{
	arcan_vobject** slot = NULL;
	for (int i = 0; i < parent->childslots; i++){
		if (parent->children[i] == NULL){
		 slot = &parent->children[i];
			break;
		}
	}

/* grow and set element */
	if (!slot){
		arcan_vobject** news = realloc(parent->children,
			(parent->childslots + 8) * sizeof(void*));

		if (news != NULL){
			parent->children = news;

			for (int i = 0; i < 8; i++)
				parent->children[parent->childslots + i] = NULL;

			slot = &parent->children[parent->childslots];
			parent->childslots += 8;
		}
		else
			return;
	}

	if (child->flags.clone)
		parent->extrefc.instances++;
	else
		parent->extrefc.links++;

	child->parent = parent;
	*slot = child;
}

/*
 * recursively sweep children and 
 * flag their caches for updates as well
 */
static void invalidate_cache(arcan_vobject* vobj)
{
	if (!vobj->valid_cache)
		return;

	vobj->valid_cache = false;

	for (int i = 0; i < vobj->childslots; i++)
		if (vobj->children[i])
			invalidate_cache(vobj->children[i]);
}

static void dropchild(arcan_vobject* parent, arcan_vobject* child)
{
	for (int i = 0; i < parent->childslots; i++){
		if (parent->children[i] == child){
			parent->children[i] = NULL;
			if (child->flags.clone)
				parent->extrefc.instances--;
			else
				parent->extrefc.links--;
			child->parent = &current_context->world;
			break;
		}	
	}	
}

/* scan through each cell in use, and either deallocate / wrap with deleteobject
 * or pause frameserver connections and (conservative) delete resources that can
 * be recreated later on. */
static void deallocate_gl_context(struct arcan_video_context* context, bool del)
{
/* index (0) is always worldid */
	for (int i = 1; i < context->vitem_limit; i++) {
		if (context->vitems_pool[i].flags.in_use){
			arcan_vobject* current = &(context->vitems_pool[i]);

/* before doing any modification, wait for any async load calls to finish(!),
 * question is IF this should invalidate or not */
			if (current->feed.state.tag == ARCAN_TAG_ASYNCIMG)
				arcan_video_pushasynch(i);

/* for persistant objects, deleteobject will only be "effective" if we're at
 * the stack layer where the object was created */
			if (del)
				arcan_video_deleteobject(i);

/* only non-persistant objects will have their GL objects removed immediately */
			else if (current->flags.persist == false){
				arcan_frameserver* dstfsrv = current->feed.state.ptr;

/* glid 0 will be used as a flag for shared storages */
				if (current->vstore->txmapped != TXSTATE_OFF 
					&& current->vstore->vinf.text.glid){
					glDeleteTextures(1, &current->vstore->vinf.text.glid);
					current->vstore->vinf.text.glid = 0;
				}

				if (dstfsrv && current->feed.state.tag == ARCAN_TAG_FRAMESERV)
					arcan_frameserver_pause(dstfsrv, true);
			}
		}
	}

/* pool is dynamically sized and size is set on layer push */
	if (del){
		free(context->vitems_pool);
		context->vitems_pool = NULL;
	}
}

static inline void step_active_frame(arcan_vobject* vobj)
{
	if (!vobj->frameset)
		return;

	vobj->frameset_meta.current = (vobj->frameset_meta.current + 1) % 
		vobj->frameset_meta.capacity;
	vobj->current_frame = vobj->frameset[ vobj->frameset_meta.current ];
}

/* 
 * Iterate a saved context, and reallocate all resources associated with it.
 * Note that this doesn't really consider other forms of gl storage at the
 * moment, particularly rendertargets(!)
 * 
 */
static void reallocate_gl_context(struct arcan_video_context* context)
{
	arcan_tickv cticks = arcan_video_display.c_ticks;

/* If there's nothing saved, we reallocate */
	if (!context->vitems_pool){
		context->vitem_limit = arcan_video_display.default_vitemlim;
		context->vitem_ofs   = 1;
		context->vitems_pool = (arcan_vobject*) calloc( sizeof(arcan_vobject),
			context->vitem_limit);
	}
	else for (int i = 1; i < context->vitem_limit; i++)
		if (context->vitems_pool[i].flags.in_use){
			arcan_vobject* current = &context->vitems_pool[i];
			surface_transform* ctrans = current->transform;	

			if (current->flags.persist)
				continue;

			if (current->flags.clone)
				continue;

/* since there may be queued transforms in an already pushed context,
 * we maintain the timing and reset them to match the changes that 
 * has already occurred */
			if (ctrans && cticks > context->last_tickstamp)
				rebase_transform(ctrans, cticks - context->last_tickstamp);

/* for conservative memory management mode we need to reallocate 
 * static resources. getimage will strdup the source so to avoid leaking,
 * copy and free */
			if (arcan_video_display.conservative &&	
				(char)current->feed.state.tag == ARCAN_TAG_IMAGE){
					char* fname = strdup( current->vstore->vinf.text.source ); 
					free(current->vstore->vinf.text.source);
				arcan_video_getimage(fname, current, 
					arcan_video_dimensions(current->origw, current->origh), false);
				free(fname); 
			}
			else
				if (current->vstore->txmapped != TXSTATE_OFF)
					push_globj(current, false, NULL);

			arcan_frameserver* movie = current->feed.state.ptr;
			if (current->feed.state.tag == ARCAN_TAG_FRAMESERV && movie){ 
				arcan_audio_rebuild(movie->aid);
				arcan_frameserver_resume(movie);
				arcan_audio_play(movie->aid, false, 0.0);
			}
		}
}

unsigned arcan_video_nfreecontexts()
{
		return CONTEXT_STACK_LIMIT - 1 - vcontext_ind;
}

static void rebase_transform(struct surface_transform* current, arcan_tickv ofs)
{
	if (current->move.startt){
		current->move.startt += ofs;
		current->move.endt   += ofs;
	}

	if (current->rotate.startt){
		current->rotate.startt += ofs;
		current->rotate.endt   += ofs;
	}

	if (current->scale.startt){
		current->scale.startt += ofs;
		current->scale.endt   += ofs;
	}

	if (current->next)
		rebase_transform(current->next, ofs);
}

/* Sweeps src and matches 1:1 with cells in dst if they are set as "persistent",
 * if such a relation exists, copy it downwards and reset the cell so its 
 * resources won't be deallocated */
static void transfer_persists(struct arcan_video_context* src, 
	struct arcan_video_context* dst, bool delsrc)
{
/* for delsrc (pop), the item needs to exist and be persistent in BOTH src,dst 
 * otherwise (push) dst can be assumed empty */
	for (int i = 1; i < src->vitem_limit - 1; i++){
		if (src->vitems_pool[i].flags.in_use && src->vitems_pool[i].flags.persist &&
			(!delsrc || (dst->vitems_pool[i].flags.in_use && 
			dst->vitems_pool[i].flags.persist))){
			memcpy(&dst->vitems_pool[i], &src->vitems_pool[i], sizeof(arcan_vobject));

/* cross- referencing world- outside context isn't permitted */
			dst->vitems_pool[i].parent = &dst->world;

			if (delsrc){
				detach_fromtarget(&src->stdoutp, &src->vitems_pool[i]);
				memset(&src->vitems_pool[i], 0, sizeof(arcan_vobject));
			}
			else{
				dst->nalive++;
				src->vitems_pool[i].owner = NULL;
				attach_object(&dst->stdoutp, &src->vitems_pool[i]);
				trace("vcontext_stack_push() : transfer-attach: %s\n", 
					src->vitems_pool[i].tracetag);
			}
		}
/* of loop */
	}

}

signed arcan_video_pushcontext()
{
	arcan_vobject empty_vobj = {.current = {
			.position = {0}, 
			.opa = 1.0,
			.scale = {.x = 1.0, .y = 1.0, .z = 1.0},
			.rotation.quaternion = default_quat 
		} 
	};

	if (vcontext_ind + 1 == CONTEXT_STACK_LIMIT)
		return -1;

	current_context->last_tickstamp = arcan_video_display.c_ticks;

/* copy everything then manually reset some fields to defaults */
	memcpy(&vcontext_stack[ ++vcontext_ind ], current_context, 
		sizeof(struct arcan_video_context));
	deallocate_gl_context(current_context, false);

	current_context = &vcontext_stack[ vcontext_ind ];
	current_context->stdoutp.color = NULL;
	current_context->stdoutp.first = NULL;
	current_context->vitem_ofs = 1;

	current_context->world = empty_vobj;
	current_context->vitem_limit = arcan_video_display.default_vitemlim;
	current_context->vitems_pool = calloc(sizeof(arcan_vobject), 
			current_context->vitem_limit);
	current_context->rtargets[0].first = NULL;

/* propagate persistent flagged objects upwards */
	transfer_persists(&vcontext_stack[ vcontext_ind - 1], current_context, false);

	return arcan_video_nfreecontexts();
}

/* 
 * the first approach to the _extpop etc. was to create a separate 
 * FBO, a vid in the current context and a view in the next context
 * then run a separate rendertarget and readback the FBO into a texture.
 * Now we reuse the screenshot function into a buffer, use that buffer
 * to create a raw image and voilà.
 */
unsigned arcan_video_extpopcontext(arcan_vobj_id* dst)
{
	char* dstbuf;
	size_t dsz;
	
	arcan_video_refresh(0.0, true);
	bool ss = arcan_video_screenshot((void*)&dstbuf, &dsz);
	int rv = arcan_video_popcontext(); 

	if (ss){
		int w = arcan_video_display.width;
		int h = arcan_video_display.height;

/* flip y */
		img_cons cons = {.w = w, .h = h, .bpp = GL_PIXEL_BPP};
		*dst = arcan_video_rawobject((uint8_t*)dstbuf, dsz, cons, w, h, 1);
	
		if (*dst == ARCAN_EID)
			free(dstbuf);
	}

	return rv;
}

signed arcan_video_extpushcontext(arcan_vobj_id* dst)
{
	void* dstbuf;
	size_t dsz;
	
	arcan_video_refresh(0.0, true);
	bool ss = arcan_video_screenshot(&dstbuf, &dsz);
	int rv = arcan_video_pushcontext(); 

	if (ss){
		int w = arcan_video_display.width;
		int h = arcan_video_display.height;

		img_cons cons = {.w = w, .h = h, .bpp = GL_PIXEL_BPP};
		*dst = arcan_video_rawobject((uint8_t*)dstbuf, dsz, cons, w, h, 1);
	
		if (*dst == ARCAN_EID)
		free(dstbuf);
	}

	return rv;
}

unsigned arcan_video_popcontext()
{
/* propagate persistent flagged objects downwards */
	if (vcontext_ind > 0)
		transfer_persists(current_context, &vcontext_stack[vcontext_ind-1], true);

	deallocate_gl_context(current_context, true);

	if (vcontext_ind > 0){
		vcontext_ind--;
		current_context = &vcontext_stack[ vcontext_ind ];
	}

	reallocate_gl_context(current_context);

	return (CONTEXT_STACK_LIMIT - 1) - vcontext_ind;
}

static inline surface_properties empty_surface()
{
	surface_properties res  = {0};
	res.rotation.quaternion = default_quat; 
	return res;
}

arcan_vobj_id arcan_video_allocid(bool* status, struct arcan_video_context* ctx)
{
	unsigned i = ctx->vitem_ofs, c = ctx->vitem_limit;
	*status = false;

	while (c--){
		if (i == 0) /* 0 is protected */
			i = 1;

		if (!ctx->vitems_pool[i].flags.in_use){
			*status = true;
			ctx->nalive++;
			ctx->vitems_pool[i].flags.in_use = true;
			ctx->vitem_ofs = (ctx->vitem_ofs + 1) >= ctx->vitem_limit ? 1 : i + 1;
			return i;
		}

		i = (i + 1) % (ctx->vitem_limit - 1);
	}

	return ARCAN_EID;
}

arcan_vobj_id arcan_video_cloneobject(arcan_vobj_id parent)
{
	if (parent == ARCAN_EID || parent == ARCAN_VIDEO_WORLDID)
		return ARCAN_EID;

	arcan_vobject* pobj = arcan_video_getobject(parent);
	arcan_vobj_id rv = ARCAN_EID;

	if (pobj == NULL || pobj->flags.persist)
		return rv;

	while (pobj->flags.clone)
		pobj = pobj->parent;

	bool status;
	rv = arcan_video_allocid(&status, current_context);

	if (status){
		arcan_vobject* nobj = arcan_video_getobject(rv);

/* use parent values as template */
		nobj->flags.clone   = true;
		nobj->blendmode     = pobj->blendmode;
		nobj->current_frame = pobj->current_frame;
		nobj->origw         = pobj->origw;
		nobj->origh         = pobj->origh;
		nobj->order         = pobj->order;
		nobj->cellid        = rv;

/* don't alter refcount for vstore */
		nobj->vstore        = pobj->vstore;
		nobj->current.scale = pobj->current.scale;

		nobj->current.rotation.quaternion = default_quat; 
		nobj->program = pobj->program;
		generate_basic_mapping(nobj->txcos, 1.0, 1.0);

		addchild(pobj, nobj);
		trace("(clone) new instance of (%d:%s) with ID: %d, total: %d\n", 
			parent, video_tracetag(pobj), nobj->cellid, 
			nobj->parent->extrefc.instances);
		arcan_video_attachobject(rv);
	}

	return rv;
}

void generate_basic_mapping(float* dst, float st, float tt)
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

void generate_mirror_mapping(float* dst, float st, float tt)
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

/* 
 * arcan_video_newvobject is used in other parts (3d, renderfun, ...)
 * as well, but they wrap to this one as to not expose more of the
 * context stack
 */ 
static arcan_vobject* new_vobject(arcan_vobj_id* id, 
	struct arcan_video_context* dctx)
{
	arcan_vobject* rv = NULL;

	bool status;
	arcan_vobj_id fid = arcan_video_allocid(&status, dctx);

	if (status) {
		rv = dctx->vitems_pool + fid;
		rv->current_frame = rv;
		rv->order = 0;

		rv->vstore = malloc(sizeof(struct storage_info_t));
		memset(rv->vstore, '\0', sizeof(struct storage_info_t));

		rv->vstore->txmapped   = TXSTATE_TEX2D;
		rv->vstore->txu        = arcan_video_display.deftxs;
		rv->vstore->txv        = arcan_video_display.deftxt;
		rv->vstore->scale      = arcan_video_display.scalemode;
		rv->vstore->imageproc  = arcan_video_display.imageproc;
		rv->vstore->filtermode = arcan_video_display.filtermode;
		rv->vstore->refcount   = 1;
		rv->childslots = 0;
		rv->children = NULL;

		rv->valid_cache = false;

		rv->blendmode = blend_normal;
		rv->flags.cliptoparent = false;

		rv->current.scale.x = 1.0;
		rv->current.scale.y = 1.0;
		rv->current.scale.z = 1.0;

		rv->current.position.x = 0;
		rv->current.position.y = 0;
		rv->current.position.z = 0;
		
		rv->current.rotation.quaternion = default_quat; 
		
		rv->current.opa = 0.0;
		
		rv->cellid = fid;
		assert(rv->cellid > 0);
		generate_basic_mapping(rv->txcos, 1.0, 1.0);

		rv->parent = &current_context->world;
		rv->mask = MASK_ORIENTATION | MASK_OPACITY | MASK_POSITION 
			| MASK_FRAMESET | MASK_LIVING;
	}

	if (id != NULL)
		*id = fid;

	return rv;
}

arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id )
{
	return new_vobject(id, current_context);
}

arcan_vobject* arcan_video_getobject(arcan_vobj_id id)
{
	arcan_vobject* rc = NULL;

	if (id > 0 && id < current_context->vitem_limit && 
		current_context->vitems_pool[id].flags.in_use)
		rc = current_context->vitems_pool + id;
	else
		if (id == ARCAN_VIDEO_WORLDID) {
			rc = &current_context->world;
		}

	return rc;
}

static bool detach_fromtarget(struct rendertarget* dst, arcan_vobject* src)
{
	arcan_vobject_litem* torem;
	assert(src);

/* already detached or empty source/target */
	if (!dst || !dst->first)
		return false;

	if (dst->camtag == src->cellid)
		dst->camtag = ARCAN_EID;

/* find it */
	torem = dst->first;
	while(torem){
		if (torem->elem == src)
			break;

		torem = torem->next;
	}
	if (!torem)
		return false;

/* (1.) remove first */
	if (dst->first == torem){
		dst->first = torem->next;

/* only one element? */
		if (dst->first){
			dst->first->previous = NULL;
		}
	}
/* (2.) remove last */
	else if (torem->next == NULL){
		assert(torem->previous);
		torem->previous->next = NULL;
	}
/* (3.) remove arbitrary */
	else {
		torem->next->previous = torem->previous;
		torem->previous->next = torem->next;
	}

/* cleanup torem */
	memset(torem, 0, sizeof(arcan_vobject_litem));
	free(torem);

	if (src->owner == dst) 
		src->owner = NULL;

	if (dst->color){
		dst->color->extrefc.attachments--;
		src->extrefc.attachments--;

		trace("(detatch) (%ld:%s) removed from rendertarget:(%ld:%s)," 
			"left: %d, attached to: %d\n", src->cellid, video_tracetag(src),
			dst->color ? dst->color->cellid : -1, video_tracetag(dst->color), 
			dst->color->extrefc.attachments, src->extrefc.attachments);

		assert(dst->color->extrefc.attachments >= 0);
	} else {
		src->extrefc.attachments--;
		trace("(detach) (%ld:%s) removed from stdout, attached to: %d\n", 
		src->cellid, video_tracetag(src), src->extrefc.attachments);
	}
	
	return true;
}

static void attach_object(struct rendertarget* dst, arcan_vobject* src)
{
	arcan_vobject_litem* new_litem = malloc(sizeof *new_litem);
	new_litem->next = new_litem->previous = NULL;
	new_litem->elem = src;

/* (pre) if orphaned, assign */
	if (src->owner == NULL){
		src->owner = dst;
	}

/* 2. insert first into empty? */
	if (!dst->first)
		dst->first = new_litem;
	else
/* 3. insert first with n >= 1 */
	if (dst->first->elem->order > src->order) {
		new_litem->next = dst->first;
		dst->first = new_litem;
		new_litem->next->previous = new_litem;
	}
/* 4. insert last or arbitrary */
	else {
		bool last;
		arcan_vobject_litem* ipoint = dst->first;

/* 5. scan for insertion point */
		do
			last = (ipoint->elem->order <= src->order);
		while (last && ipoint->next && (ipoint = ipoint->next));

/* 6. insert last? */
		if (last) {
			new_litem->previous = ipoint;
			ipoint->next = new_litem;
		}

		else {
/* 7. insert arbitrary */
			ipoint->previous->next = new_litem;
			new_litem->previous = ipoint->previous;
			ipoint->previous = new_litem;
			new_litem->next = ipoint;
		}
	}

	if (dst->color){
		src->extrefc.attachments++;
		dst->color->extrefc.attachments++;
		trace("(attach) (%d:%s) attached to rendertarget:(%ld:%s), "
			"src-count: %d, dst-count: %d\n", src->cellid, video_tracetag(src),
			dst->color ? dst->color->cellid : -1, 
			dst->color ? video_tracetag(dst->color) : "(stdout)", 
			src->extrefc.attachments, dst->color->extrefc.attachments);
	} else {
		src->extrefc.attachments++;
		trace("(attach) (%d:%s) attached to stdout, count: %d\n", src->cellid, 
		video_tracetag(src), src->extrefc.attachments);
	}
}

arcan_errc arcan_video_attachobject(arcan_vobj_id id)
{
	arcan_vobject* src = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;

	if (src){
/* make sure that there isn't already one attached */
		detach_fromtarget(&current_context->stdoutp, src);
		attach_object(&current_context->stdoutp, src);

		rv = ARCAN_OK;
	}

	return rv;
}

/* run through the chain and delete all occurences at ofs */
static void swipe_chain(surface_transform* base, unsigned ofs, unsigned size)
{
	while (base) {
		memset((char*)base + ofs, 0, size);
		base = base->next;
	}
}

/* copy a transform and at the same time, compact it into 
 * a better sized buffer */
static surface_transform* dup_chain(surface_transform* base)
{
	if (!base)
		return NULL;

	unsigned count = 1;
	surface_transform* res = (surface_transform*) 
		malloc(sizeof(surface_transform));
	surface_transform* current = res;

	while (base)
	{
		memcpy(current, base, sizeof(surface_transform));

		if (base->next)
			current->next = (surface_transform*) malloc(sizeof(surface_transform));
		else
			current->next = NULL;

		current = current->next;
		base = base->next;
	}

	return res;
}

arcan_errc arcan_video_inheritorder(arcan_vobj_id id, bool val)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id != ARCAN_VIDEO_WORLDID && vobj->order >= 0){
		rv = ARCAN_OK;
		vobj->flags.orderofs = val;

		update_zv(vobj, vobj->parent->order);
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


const char* const arcan_video_readtag(arcan_vobj_id id)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	return vobj ? vobj->tracetag : "(no tag)";
}

arcan_errc arcan_video_transformmask(arcan_vobj_id id, 
	enum arcan_transform_mask mask)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		vobj->mask = mask;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_linkobjs(arcan_vobj_id srcid, arcan_vobj_id parentid, 
	enum arcan_transform_mask mask)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* src = arcan_video_getobject(srcid);
	arcan_vobject* dst = arcan_video_getobject(parentid);

/* link to self always means link to world */
	if (srcid == parentid || parentid == 0)
		dst = &current_context->world;

/* can't relink clone to another object, or link an object to a clone */
	if (src && (src->flags.clone || src->flags.persist))
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

	if (dst && (dst->flags.clone || dst->flags.persist))
		return ARCAN_ERRC_CLONE_NOT_PERMITTED; 

	else if (src && dst) {
		arcan_vobject* current = dst;

/* traverse destination and make sure we don't create cycles */
		while (current) {
			if (current->parent == src)
				return ARCAN_ERRC_CLONE_NOT_PERMITTED;
			else
				current = current->parent;
		}

		rv = ARCAN_OK;

/* already linked to dst? do nothing */
		if (src->parent == dst)
			return rv;

/* otherwise, first decrement parent counter */
		else if (src->parent != &current_context->world)
			dropchild(src->parent, src);

/* create link connection, and update counter */
		if (dst != &current_context->world){
			addchild(dst, src);
			trace("(link) (%d:%s) linked to (%d:%s), count: %d\n", 
				src->cellid, src->tracetag == NULL ? "(unknown)" : src->tracetag,
				dst->cellid, dst->tracetag ? "(unknown)" : dst->tracetag, 
				src->parent->extrefc.links);
		}

		if (src->flags.orderofs)
			update_zv(src, src->parent->order);

/* reset all transformations as they don't make sense in this space */
		swipe_chain(src->transform, offsetof(surface_transform, blend),
			sizeof(struct transf_blend ));
		swipe_chain(src->transform, offsetof(surface_transform, move), 
			sizeof(struct transf_move  ));
		swipe_chain(src->transform, offsetof(surface_transform, scale),
			sizeof(struct transf_scale ));
		swipe_chain(src->transform, offsetof(surface_transform, rotate),
			sizeof(struct transf_rotate));

		src->mask = mask;
	}

	return rv;
}

static void arcan_video_gldefault()
{
	glEnable(GL_SCISSOR_TEST);
	glDisable(GL_DEPTH_TEST);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

#ifdef GL_MULTISAMPLE
	if (arcan_video_display.msasamples)
		glEnable(GL_MULTISAMPLE);
#endif

	glEnable(GL_BLEND);
	glClearColor(0.0, 0.0, 0.0, 1.0f);

/*
 * -- Removed as they were causing trouble with NVidia GPUs (white line outline
 * where triangles connect 
 * glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);
 * glHint(GL_POLYGON_SMOOTH_HINT, GL_NICEST);
 * glEnable(GL_LINE_SMOOTH);
 * glEnable(GL_POLYGON_SMOOTH);
*/

	build_orthographic_matrix(current_context->stdoutp.projection, 0, 
		arcan_video_display.width, arcan_video_display.height, 0, 0, 1);
	identity_matrix(current_context->stdoutp.base);
	glScissor(0, 0, arcan_video_display.width, arcan_video_display.height);
	glFrontFace(GL_CW);
	glCullFace(GL_BACK);
}

const char* defvprg =
#ifdef GL_ES_VERSION_2_0
"#version 100\n"
#else
"#version 120\n"
#endif
"uniform mat4 modelview;\n"
"uniform mat4 projection;\n"

"attribute vec2 texcoord;\n"
"varying vec2 texco;\n"
"attribute vec4 vertex;\n"
"void main(){\n"
"	gl_Position = (projection * modelview) * vertex;\n"
"   texco = texcoord;\n"
"}";

const char* deffprg =
#ifdef GL_ES_VERSION_2_0
"#version 100\n"
"precision mediump float;\n"
#else
"#version 120\n"
#endif
"uniform sampler2D map_diffuse;\n"
"varying vec2 texco;\n"
"uniform float obj_opacity;\n"
"void main(){\n"
"   vec4 col = texture2D(map_diffuse, texco);\n"
"   col.a = col.a * obj_opacity;\n"
"	gl_FragColor = col;\n"
"}";

const char* defcvprg =
#ifdef GL_ES_VERSION_2_0
"#version 100\n"
#else
"#version 120\n"
#endif
"uniform mat4 modelview;\n"
"uniform mat4 projection;\n"
"attribute vec4 vertex;\n"
"void main(){\n"
" gl_Position = (projection * modelview) * vertex;\n"
"}";

const char* defcfprg =
#ifdef GL_ES_VERSION_2_0
"#version 100\n"
"precision mediump float;\n"
#else
"#version 120\n"
#endif
"varying vec2 texco;\n"
"uniform vec3 obj_col;\n"
"uniform float obj_opacity;\n"
"void main(){\n"
"   gl_FragColor = vec4(obj_col.rgb, obj_opacity);\n"
"}\n";

arcan_errc arcan_video_init(uint16_t width, uint16_t height, uint8_t bpp, 
	bool fs, bool frames, bool conservative)
{
	static char caption[64];
	static bool firstinit = true;

/* might be called multiple times so.. */
	if (firstinit){
		sem_init(&asynchsynch, 0, ASYNCH_CONCURRENT_THREADS);
		firstinit = false;
	}

	if (!platform_video_init(width, height, bpp, fs, frames, conservative)){
		arcan_warning("platform_video_init() failed.\n");
		return ARCAN_ERRC_BADVMODE;
	}

/* flip twice (back->front->display) to hopefully wash out initial jitter */
	platform_video_timing(&arcan_video_display.vsync_timing, 
		&arcan_video_display.vsync_stddev, &arcan_video_display.vsync_variance);

/* 
 * try to get a decent measurement of actual timing, this is not really used for
 * synchronization but rather as a guess of we're actually vsyncing and how 
 * processing should be scheduled in relation to vsync, or if we should yield at
 * appropriate times.
 */

	arcan_warning("arcan_video_init(), timing estimate"
	"	(mean: %f, deviation: %f, variance: %f)\n", 
		arcan_video_display.vsync_timing,
		arcan_video_display.vsync_stddev,
		arcan_video_display.vsync_variance);

	arcan_video_display.conservative = conservative;
	arcan_video_display.defaultshdr  = arcan_shader_build("DEFAULT",
		NULL, defvprg, deffprg);
	arcan_video_display.defclrshdr   = arcan_shader_build("DEFAULT_COLOR",
		NULL, defcvprg, defcfprg);

	TTF_Init();
	current_context->world.current.scale.x = 1.0;
	current_context->world.current.scale.y = 1.0;
	current_context->vitem_limit = arcan_video_display.default_vitemlim;
	current_context->vitems_pool = calloc(sizeof(arcan_vobject),
		current_context->vitem_limit);

	arcan_video_gldefault();

/*
 * DEBUG build + a txdump subfolder stores a copy of all
 * static textures being uploaded 
 */
#ifdef _DEBUG
	FILE* test = fopen("./txdump/.test", "w+");
	if (test){
		fclose(test);
		unlink("./txdump/.test");
		arcan_video_display.txdump = strdup("./txdump/");	
	}
#endif

	return ARCAN_OK;
}

uint16_t arcan_video_screenw()
{
	return arcan_video_display.width;
}

uint16_t arcan_video_screenh()
{
	return arcan_video_display.height;
}

uint16_t nexthigher(uint16_t k)
{
	k--;
	for (int i=1; i < sizeof(uint16_t) * 8; i = i * 2)
		k = k | k >> i;
	return k+1;
}

arcan_errc arcan_video_getimage(const char* fname, arcan_vobject* dst, 
	img_cons forced, bool asynchsrc)
{
/* 
 * with asynchsynch, it's likely that we get a storm of requests 
 * and we'd likely suffer thrashing, so limit this. 
 * also, look into using pthread_setschedparam and switch to 
 * pthreads exclusively 
 */
	sem_wait(&asynchsynch);
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;

	char* imgbuf = NULL;
	int inw, inh;

/* try- open */
	data_source inres = arcan_open_resource(fname);
	if (inres.fd == BADFD){
		sem_post(&asynchsynch);
		return ARCAN_ERRC_BAD_RESOURCE;
	}

/* mmap (preferred) or buffer (mmap not working / 
 * useful due to alignment) */
	map_region inmem = arcan_map_resource(&inres, false);
	if (inmem.ptr == NULL){
		sem_post(&asynchsynch);
		arcan_release_resource(&inres);
		return ARCAN_ERRC_BAD_RESOURCE;
	}

	struct arcan_img_meta meta = {0};
	rv = arcan_img_decode(fname, inmem.ptr, inmem.sz, &imgbuf, &inw, &inh,
	&meta, dst->vstore->imageproc == imageproc_fliph, malloc);

	arcan_release_map(inmem);
	arcan_release_resource(&inres);

	if (rv == ARCAN_OK){
		uint16_t neww, newh;
	
/* store this so we can maintain aspect ratios etc. while still
 * possibly aligning to next power of two */
		dst->origw = inw;
		dst->origh = inh;

		neww = inw;
		newh = inh;

/* the thread_loader will take care of converting the asynchsrc 
 * to an image once its completely done */
		if (!asynchsrc)
			dst->feed.state.tag = ARCAN_TAG_IMAGE;

/* need to keep the identification string in order to rebuild
 * on a forced push/pop */
		struct storage_info_t* dstframe = dst->vstore;
		dstframe->vinf.text.source = strdup(fname);

		enum arcan_vimage_mode desm = dst->vstore->scale;

		if (meta.compressed)
			goto push_comp;

/* the user requested specific dimensions,
 * so we force the rescale texture mode for mismatches and set 
 * dimensions accordingly */
		if (forced.h > 0 && forced.w > 0){
			neww = ARCAN_VIMAGE_SCALEPOW2 ? nexthigher(forced.w) : forced.w;
			newh = ARCAN_VIMAGE_SCALEPOW2 ? nexthigher(forced.h) : forced.h;
				
			dstframe->vinf.text.s_raw = neww * newh * GL_PIXEL_BPP;
			dstframe->vinf.text.raw   = malloc(dstframe->vinf.text.s_raw); 
			stretchblit(imgbuf, inw, inh, (uint32_t*) dstframe->vinf.text.raw, 
				neww, newh, dst->vstore->imageproc == imageproc_fliph);
			free(imgbuf);
		}
		else if (desm == ARCAN_VIMAGE_SCALEPOW2){
			neww = nexthigher(neww);
			newh = nexthigher(newh);

			if (neww != inw || newh != inh){
				dstframe->vinf.text.s_raw = neww * newh * GL_PIXEL_BPP;
				dstframe->vinf.text.raw = malloc(dstframe->vinf.text.s_raw);
				stretchblit(imgbuf, inw, inh, (uint32_t*) dstframe->vinf.text.raw, 
					neww, newh, dst->vstore->imageproc == imageproc_fliph);
				free(imgbuf);
			} 
			else {
				dstframe->vinf.text.s_raw = neww * newh * GL_PIXEL_BPP;
				dstframe->vinf.text.raw = (uint8_t*) imgbuf;
			}
		} 
		else { 
			neww = inw; 
			newh = inh;
			dstframe->vinf.text.raw   = (uint8_t*) imgbuf;
			dstframe->vinf.text.s_raw = inw * inh * GL_PIXEL_BPP;
		}

		dst->vstore->w = neww;
		dst->vstore->h = newh;

/*
 * for the asynch case, we need to do this separately as we're in a different
 * thread and forcibly assigning the glcontext to another thread is expensive */

push_comp:
		if (!asynchsrc && dst->vstore->txmapped != TXSTATE_OFF)
			push_globj(dst, false, &meta);
	}

	sem_post(&asynchsynch);
	return rv;
}

void arcan_video_3dorder(enum arcan_order3d order){
		arcan_video_display.order3d = order;
}

static void rescale_origwh(arcan_vobject* dst, float fx, float fy)
{
	vector svect = build_vect(fx, fy, 1.0);

	dst->current.scale = mul_vector( dst->current.scale, svect );
	surface_transform* current = dst->transform;

	while (current){
		current->scale.startd = mul_vector(current->scale.startd, svect);
		current->scale.endd   = mul_vector(current->scale.endd, svect);
		current = current->next;
	}
}

arcan_errc arcan_video_allocframes(arcan_vobj_id id, unsigned char capacity,
	enum arcan_framemode mode)
{
	arcan_vobject* target = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	if (!target)
		return rv;

	if (target->flags.clone || target->flags.persist)
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

/* we need to drop the current frameset before defining a new one */
		if (target->frameset){
			for (int i = 0; i < target->frameset_meta.capacity; i++){
				arcan_vobject* torem = target->frameset[i];

				torem->extrefc.framesets--;
				trace("(allocframe) drop old from (%d:%s), (%d:%s) stripped.\n",
						id, video_tracetag(target), torem->cellid, video_tracetag(torem));
				assert(torem->extrefc.framesets >= 0);

				target->frameset[i] = NULL;

/* cascade delete those that are detached from everything else */
				if (torem && torem != target && torem->owner == NULL)
					arcan_video_deleteobject(torem->cellid);
			}

			free(target->frameset);
			target->frameset = NULL;
		}

/* reset frameset relevant members */
		target->current_frame = target;
		target->frameset = malloc(sizeof(arcan_vobject*) * capacity);

/* fill each slot with references to self */
		for (int i = 0; i < capacity; i++){
			target->frameset[i] = target;
			target->frameset[i]->extrefc.framesets++;
			trace("(allocframe) self-attached to (%d:%s)\n", target->cellid, 
				video_tracetag(target) );
		}

		target->frameset_meta.current = 0;
		target->frameset_meta.capacity = capacity;
		target->frameset_meta.framemode = mode;

	return ARCAN_OK;
}

arcan_errc arcan_video_framecyclemode(arcan_vobj_id id, signed mode)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

/* all the real work is done in tick/render */
	if (vobj){
		vobj->frameset_meta.mode = mode;
		vobj->frameset_meta.counter = abs(mode);
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_shareglstore(arcan_vobj_id sid, arcan_vobj_id did)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* src = arcan_video_getobject(sid);
	arcan_vobject* dst = arcan_video_getobject(did);

	if (src && dst && src != dst){
		if (src->vstore->txmapped == TXSTATE_OFF || 
			src->vstore->vinf.text.glid == 0 ||
			src->flags.persist || dst->flags.persist || src->flags.clone ||
			dst->flags.clone)
			return ARCAN_ERRC_UNACCEPTED_STATE;

		drop_glres(dst->vstore);
		dst->vstore = src->vstore;
		dst->vstore->refcount++;
		memcpy(dst->txcos, src->txcos, sizeof(dst->txcos));
	
		rv = ARCAN_OK;
	}

	return rv;
}

/* solid and null are essentially treated the same,
 * the difference being there's no program associated 
 * in the vstore for the nullobject */
arcan_vobj_id arcan_video_solidcolor(float origw, float origh,
	uint8_t r, uint8_t g, uint8_t b, unsigned short zv)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_vobject* newvobj = arcan_video_newvobject(&rv);
	if (!newvobj)
		return rv; 

	newvobj->origw = origw;
	newvobj->origh = origh;
	newvobj->vstore->txmapped = TXSTATE_OFF;
	newvobj->vstore->vinf.col.r = (float)r / 255.0f;
	newvobj->vstore->vinf.col.g = (float)g / 255.0f;
	newvobj->vstore->vinf.col.b = (float)b / 255.0f;
	newvobj->program = arcan_video_display.defclrshdr;
	arcan_video_attachobject(rv);

	return rv;	
}

arcan_vobj_id arcan_video_nullobject(float origw, 
	float origh, unsigned short zv)
{
	arcan_vobj_id rv =  arcan_video_solidcolor(origw, origh, 0, 0, 0, zv);

	if (rv != ARCAN_EID){
		arcan_vobject* vobj   = arcan_video_getobject(rv);
		vobj->program = 0;
		arcan_video_attachobject(rv);
	}

	return rv;
}

arcan_vobj_id arcan_video_rawobject(uint8_t* buf, size_t bufs, 
	img_cons cons, float origw, float origh, unsigned short zv)
{
	arcan_vobj_id rv = ARCAN_EID;

	if (buf && bufs == (cons.w * cons.h * cons.bpp) 
		&& cons.bpp == GL_PIXEL_BPP) {
		arcan_vobject* newvobj = arcan_video_newvobject(&rv);

		if (!newvobj)
			return ARCAN_EID;

		struct storage_info_t* ds = newvobj->vstore;

		ds->w   = cons.w;
		ds->h   = cons.h;
		ds->bpp = cons.bpp;
		ds->vinf.text.s_raw = bufs;
		ds->vinf.text.raw   = buf;
		newvobj->origw = origw;
		newvobj->origh = origh;

		ds->txmapped = TXSTATE_TEX2D;
		glGenTextures(1, &ds->vinf.text.glid);

		glBindTexture(GL_TEXTURE_2D, ds->vinf.text.glid);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

		newvobj->blendmode = blend_normal;

		glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT,
			ds->w, ds->h, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, ds->vinf.text.raw);

		glBindTexture(GL_TEXTURE_2D, 0);
		newvobj->order = zv;
	
		arcan_video_attachobject(rv);
	}

	return rv;
}

static arcan_errc attach_readback(arcan_vobj_id src)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* dstobj = arcan_video_getobject(src);

	if (dstobj){
		if (dstobj->vstore->w != arcan_video_screenw() || 
			dstobj->vstore->h != arcan_video_screenh()){
			return ARCAN_ERRC_BAD_ARGUMENT;
		}

		current_context->stdoutp.color = dstobj;

		if (current_context->stdoutp.fbo == 0){
			if (!alloc_fbo(&current_context->stdoutp)){
				current_context->stdoutp.color = NULL;
				rv = ARCAN_ERRC_UNACCEPTED_STATE;
			}
			else
				rv = ARCAN_OK;
		}

	}

	return rv;
}

arcan_errc arcan_video_attachtorendertarget(arcan_vobj_id did, 
	arcan_vobj_id src, bool detach)
{
	if (src == ARCAN_VIDEO_WORLDID)
		return attach_readback(did);

	arcan_vobject* dstobj = arcan_video_getobject(did);
	arcan_vobject* srcobj = arcan_video_getobject(src);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

/* don't allow to attach to self, that FBO behavior would be undefined 
 * and don't allow persist attachments as the other object can go out of 
 * scope */
	if (dstobj == srcobj || srcobj->flags.persist || dstobj->flags.persist)
		return ARCAN_ERRC_BAD_ARGUMENT;

	if (dstobj && srcobj){
/* find dstobj in rendertargets */
		rv = ARCAN_ERRC_UNACCEPTED_STATE;

/* linear search for rendertarget matching the destination id */
		for (int ind = 0; ind < current_context->n_rtargets; ind++){
			if (current_context->rtargets[ind].color == dstobj){

/* find whatever rendertarget we're already attached to, and detach */
				bool c;
				if (srcobj->owner && detach)
					c = detach_fromtarget(srcobj->owner, srcobj);

/* try and detach (most likely fail) to make sure that we don't get duplicates*/
				bool a = detach_fromtarget(&current_context->rtargets[ind], srcobj);
				attach_object(&current_context->rtargets[ind], srcobj);

				rv = ARCAN_OK;
			}

		}
	}

	return rv;
}

static bool activate_fbo(struct rendertarget* dst)
{
	glBindFramebuffer(GL_FRAMEBUFFER, dst->fbo);
	return true;
}

/* 
 * Allocate an FBO and set ut up to receive a combination of(DPTH,STENCIL,COLOR)
 * The destination storage is predefined in (dst->color) 
 */
static bool alloc_fbo(struct rendertarget* dst)
{
	if (!arcan_video_display.fbo_support)
		return false;

	glGenFramebuffers(1, &dst->fbo);

/* need both stencil and depth buffer, but we don't need the data from them */
	glBindFramebuffer(GL_FRAMEBUFFER, dst->fbo);

	if (dst->mode > RENDERTARGET_DEPTH)
	{
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, 
			GL_TEXTURE_2D, dst->color->vstore->vinf.text.glid, 0);

/* need a Z buffer in the offscreen rendering but don't want 
 * to store it, so setup a renderbuffer */
		if (dst->mode > RENDERTARGET_COLOR) {
			glGenRenderbuffers(1, &dst->depth);

/* could use GL_DEPTH_COMPONENT only if we'd know that there
 * wouldn't be any clipping in the active rendertarget */
			glBindRenderbuffer(GL_RENDERBUFFER, dst->depth);
			glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8,
				dst->color->vstore->w, dst->color->vstore->h);

			glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
				GL_RENDERBUFFER, dst->depth);
		}
	}
	else {
/* DEPTH buffer only (shadowmapping, ...) convert the storage to
 * contain a depth texture */
		int w = dst->color->vstore->w;
		int h = dst->color->vstore->h;
		drop_glres(dst->color->vstore);

		dst->color->vstore = malloc(sizeof(struct storage_info_t));
		struct storage_info_t* store = dst->color->vstore;

		memset(store, '\0', sizeof(struct storage_info_t));

		store->txmapped   = TXSTATE_DEPTH;
		store->txu        = GL_CLAMP;
		store->txv        = GL_CLAMP;
		store->scale      = ARCAN_VIMAGE_NOPOW2; 
		store->imageproc  = imageproc_normal; 
		store->filtermode = ARCAN_VFILTER_NONE;
		store->refcount   = 1;
		store->w = w;
		store->h = h;
	
/* generate ID etc. special path for TXSTATE_DEPTH */
		push_globj(dst->color, false, NULL); 

		glDrawBuffer(GL_NONE);
		glReadBuffer(GL_NONE);

		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
			GL_TEXTURE_2D, store->vinf.text.glid, 0);
	}

/* basic error handling / status checking
 * may be possible that we should cache this in the 
 * rendertarget and only call when / if something changes as
 * it's not certain that drivers won't stall the pipeline on this */
	GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
	
	if (status != GL_FRAMEBUFFER_COMPLETE){
		arcan_video_display.fbo_support = false;
		arcan_warning("Error using rendertarget (FBO), feature disabled.\n");
		return false;
	}

	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	return true;
}

arcan_errc arcan_video_alterreadback ( arcan_vobj_id did, int readback )
{
	if (did == ARCAN_VIDEO_WORLDID){
		current_context->stdoutp.readback = readback;
		return ARCAN_OK;
	}

	arcan_vobject* vobj = arcan_video_getobject(did);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* rtgt = find_rendertarget(vobj);
	if (rtgt){
		rtgt->readback = readback;
		return ARCAN_OK;
	}

	return ARCAN_ERRC_UNACCEPTED_STATE;
}

arcan_errc arcan_video_setuprendertarget(arcan_vobj_id did, 
	int readback, bool scale, enum rendertarget_mode format) 
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(did);
	if (!vobj)
		return rv;

	bool is_rtgt = find_rendertarget(vobj) != NULL;
	if (is_rtgt){
		arcan_warning("arcan_video_setuprendertarget() source vid"
			"already is a rendertarget\n");
		rv = ARCAN_ERRC_BAD_ARGUMENT;
		return rv;
	}

/* hard-coded number of render-targets allowed */
	if (current_context->n_rtargets < RENDERTARGET_LIMIT){
		int ind = current_context->n_rtargets++;
		struct rendertarget* dst = &current_context->rtargets[ ind ];

		dst->mode     = format; 
		dst->readback = readback;
		dst->color    = vobj;
		dst->camtag   = ARCAN_EID;

		vobj->extrefc.attachments++;
		trace("(setuprendertarget), (%d:%s) defined as rendertarget."
			"attachments: %d\n", vobj->cellid, video_tracetag(vobj), 
			vobj->extrefc.attachments);

/* alter projection so the GL texture gets stored in the way 
 * the images are rendered in normal mode, with 0,0 being upper left */
		build_orthographic_matrix(dst->projection, 0, vobj->origw, 0, 
			vobj->origh, 0, 1);
		identity_matrix(dst->base);

		if (scale){
			float xs = ((float)vobj->vstore->w / (float)arcan_video_display.width);
			float ys = ((float)vobj->vstore->h / (float)arcan_video_display.height);

/* since we may likely have a differently sized FBO, scale it */
			scale_matrix(dst->base, xs, ys, 1.0);
		} 

		alloc_fbo(dst);

/* allocate a readback buffer with the PBO */
		if (readback != 0){
			dst->readback     = readback;
			dst->readcnt      = abs(readback);

			if (arcan_video_display.pbo_support){
				glGenBuffers(1, &dst->pbo);
				glBindBuffer(GL_PIXEL_PACK_BUFFER, dst->pbo);
				glBufferData(GL_PIXEL_PACK_BUFFER, 
					vobj->vstore->w*vobj->vstore->h *
					vobj->vstore->bpp, NULL, GL_STREAM_READ);
				glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
			}
			else
				arcan_warning("PBO readback missing, alternate support fixme.\n");
		}

		rv = ARCAN_OK;
	}
	else
		rv = ARCAN_ERRC_OUT_OF_SPACE;

	return rv;
}

arcan_errc arcan_video_setactiveframe(arcan_vobj_id dst, unsigned fid)
{
	arcan_vobject* dstvobj = arcan_video_getobject(dst);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dstvobj && dstvobj->frameset){
		if (dstvobj->flags.clone)
			dstvobj->frameset = dstvobj->parent->frameset;

		dstvobj->frameset_meta.current = fid < 
			dstvobj->frameset_meta.capacity ? fid : 0;
		dstvobj->current_frame = dstvobj->frameset[dstvobj->frameset_meta.current];
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_vobj_id arcan_video_setasframe(arcan_vobj_id dst, arcan_vobj_id src, 
	unsigned fid, bool detach, arcan_errc* errc)
{
	arcan_vobject* dstvobj = arcan_video_getobject(dst);
	arcan_vobject* srcvobj = arcan_video_getobject(src);
	arcan_vobj_id rv = ARCAN_EID;

	if (!dstvobj || !srcvobj){
		*errc = ARCAN_ERRC_NO_SUCH_OBJECT;
		return rv;
	}

	if (dstvobj->flags.clone || dstvobj->flags.persist || srcvobj->flags.persist ||
		srcvobj->flags.clone || srcvobj->vstore->txmapped == TXSTATE_OFF 
		|| dstvobj->vstore->txmapped == TXSTATE_OFF){
		if (errc)
			*errc = ARCAN_ERRC_BAD_ARGUMENT;
		return rv;
	}

	if (dstvobj && srcvobj){
		if (dstvobj->frameset && fid < dstvobj->frameset_meta.capacity){

/* 
 * if we want to manage the frame entirely through this object, 
 * we can detach src and stop worrying about deleting it 
 */
			if (detach && srcvobj != dstvobj && srcvobj->owner)
				detach_fromtarget(srcvobj->owner, srcvobj);

/* 
 * if there already is an object in the desired slot, 
 * return the management responsibility to the user
 * */
			arcan_vobject* frame = dstvobj->frameset[fid];

			frame->extrefc.framesets--;
			trace("(setasframe) detatched (%d:%s) from (%d:%s), left: %d\n", 
				frame->cellid, video_tracetag(frame), dstvobj->cellid, 
				video_tracetag(dstvobj), frame->extrefc.framesets);
			assert(frame->extrefc.framesets >= 0);

			if (frame != dstvobj)
				rv = frame->cellid;

			dstvobj->frameset[fid] = srcvobj;
			srcvobj->extrefc.framesets++;
			trace("(setasframe) attached (%d:%s) in frameset (%d:%s) slot (%d)\n", 
				srcvobj->cellid, video_tracetag(srcvobj), dstvobj->cellid, 
				video_tracetag(dstvobj), fid);

			if (errc)
				*errc = ARCAN_OK;
		}
		else
			if (errc) *errc = ARCAN_ERRC_OUT_OF_SPACE;
	}
	else
		if (errc) *errc = ARCAN_ERRC_NO_SUCH_OBJECT;

	return rv;
}

struct thread_loader_args {
/* where the results will be stored */
	arcan_vobject* dst;
	arcan_vobj_id dstid;
	char* fname;
	intptr_t tag;
	img_cons constraints;
};

/* if the loading failed, we'll add a small black image in its stead,
 * and emit a failed video event */
static void* thread_loader(void* in)
{
	arcan_event result;
	struct thread_loader_args* largs = (struct thread_loader_args*) in;
	arcan_vobject* dst = largs->dst;

/* 
 * while this happens, the following members of the struct are not to be touched
 * elsewhere: origw / origh, vstore->>tag/source, vstore->
 */
	arcan_errc rc = arcan_video_getimage(largs->fname, dst, 
		largs->constraints, true);

	result.data.video.data = largs->tag;

	if (rc == ARCAN_OK){ /* emit OK event */
		result.kind = EVENT_VIDEO_ASYNCHIMAGE_LOADED;
		result.data.video.constraints.w = dst->origw;
		result.data.video.constraints.h = dst->origh;
	} else {
		dst->origw = 32;
		dst->origh = 32;
		dst->vstore->vinf.text.s_raw = 32 * 32 * GL_PIXEL_BPP;
		dst->vstore->vinf.text.raw = malloc(dst->vstore->vinf.text.s_raw);
		memset(dst->vstore->vinf.text.raw, 0, dst->vstore->vinf.text.s_raw);
		dst->vstore->w = 32;
		dst->vstore->h = 32;
		dst->vstore->vinf.text.source = strdup(largs->fname);
		result.data.video.data = largs->tag;
		result.data.video.constraints.w = 32;
		result.data.video.constraints.h = 32;
		result.kind = EVENT_VIDEO_ASYNCHIMAGE_LOAD_FAILED;
		/* emit FAILED event */
	}

	result.data.video.source = largs->dstid;
	result.category = EVENT_VIDEO;

	arcan_event_enqueue(arcan_event_defaultctx(), &result);
	free(largs->fname);

	memset(largs, 0xba, sizeof(struct thread_loader_args));
	free(largs);


	return NULL;
}

/* create a new vobj, fill it out with enough vals that we can treat it
 * as any other, but while the ASYNCIMG tag is active, it will be skipped in
 * rendering (linking, instancing etc. sortof works) but any external (script)
 * using the object before receiving a LOADED event may give undefined results*/
static arcan_vobj_id loadimage_asynch(const char* fname, 
	img_cons constraints, intptr_t tag)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_vobject* dstobj = arcan_video_newvobject(&rv);
	assert(dstobj);

	struct thread_loader_args* args = calloc(sizeof(struct thread_loader_args),1);
	args->dstid = rv;
	args->dst = dstobj;

	if (!args->dst){
		free(args);
		return ARCAN_EID;
	}

	args->fname = strdup(fname);
	args->tag = tag;
	args->constraints = constraints;
	dstobj->feed.state.tag = ARCAN_TAG_ASYNCIMG;
	dstobj->feed.state.ptr = malloc(sizeof(pthread_t));
	pthread_create((pthread_t*) dstobj->feed.state.ptr, NULL, 
		thread_loader, (void*) args);

	return rv;
}

arcan_errc arcan_video_pushasynch(arcan_vobj_id source)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(source);

	if (vobj){
		if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMG){
		/* protect us against premature invocation */
			pthread_join(*(pthread_t*) vobj->feed.state.ptr, NULL);
			free(vobj->feed.state.ptr);
			vobj->feed.state.ptr = NULL;

			push_globj(vobj, false, NULL);

			vobj->feed.state.tag = ARCAN_TAG_IMAGE;
			vobj->feed.state.ptr = NULL;
		}
		else rv = ARCAN_ERRC_UNACCEPTED_STATE;
	}

	return rv;
}

static arcan_vobj_id loadimage(const char* fname, img_cons constraints, 
	arcan_errc* errcode)
{
	GLuint gtid = 0;
	arcan_vobj_id rv = 0;

	arcan_vobject* newvobj = arcan_video_newvobject(&rv);
	if (newvobj == NULL)
		return ARCAN_EID;

	arcan_errc rc = arcan_video_getimage(fname, newvobj, constraints, false);

	if (rc != ARCAN_OK) 
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
		rv = &vobj->feed.state;
	}

	return rv;
}

arcan_errc arcan_video_alterfeed(arcan_vobj_id id, arcan_vfunc_cb cb,
	vfunc_state state)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && vobj->flags.clone)
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

	if (vobj) {
		vobj->feed.state = state;
		vobj->feed.ffunc = cb;

		rv = ARCAN_OK;
	}

	return rv;
}

static int8_t empty_ffunc(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf
	,uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, 
	vfunc_state state){
	return 0;
}

arcan_vfunc_cb arcan_video_emptyffunc()
{
	return (arcan_vfunc_cb) empty_ffunc;
}

arcan_vobj_id arcan_video_setupfeed(arcan_vfunc_cb ffunc, 
	img_cons constraints, uint8_t ntus, uint8_t ncpt)
{
	if (!ffunc)
		return 0;

	arcan_vobj_id rv = 0;
	arcan_vobject* newvobj = arcan_video_newvobject(&rv);

	if (ffunc && newvobj) {
		struct storage_info_t* vstor = newvobj->vstore;
/* preset */
		newvobj->origw = constraints.w;
		newvobj->origh = constraints.h;
		newvobj->vstore->bpp = ncpt == 0 ? GL_PIXEL_BPP : ncpt;

		if (newvobj->vstore->scale == ARCAN_VIMAGE_NOPOW2){
			newvobj->vstore->w = constraints.w;
			newvobj->vstore->h = constraints.h;
		}
		else {
/* For feeds, we don't do the forced- rescale on 
 * every frame, way too expensive */
			newvobj->vstore->w = nexthigher(constraints.w);
			newvobj->vstore->h = nexthigher(constraints.h);
			float hx = (float)constraints.w / (float)newvobj->vstore->w;
			float hy = (float)constraints.h / (float)newvobj->vstore->h;
			generate_basic_mapping(newvobj->txcos, hx, hy);
		}

/* allocate */
		vstor->vinf.text.s_raw = newvobj->vstore->w * newvobj->vstore->h * 
			newvobj->vstore->bpp;
		vstor->vinf.text.raw = malloc(vstor->vinf.text.s_raw);
		memset(vstor->vinf.text.raw, '\0', vstor->vinf.text.s_raw);

		newvobj->feed.ffunc = ffunc;
		push_globj(newvobj, false, NULL);
	}

	return rv;
}

/* some targets like to change size dynamically (thanks for that),
 * thus, drop the allocated buffers, generate new one and tweak txcos */
arcan_errc arcan_video_resizefeed(arcan_vobj_id id, img_cons store, 
	img_cons display)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && (vobj->flags.clone == true ||
        vobj->feed.state.tag != ARCAN_TAG_FRAMESERV))
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

	if (vobj) {
		if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMG)
			arcan_video_pushasynch(id);

		float fx = (float)vobj->origw / (float)display.w;
		float fy = (float)vobj->origh / (float)display.h;

		vobj->origw = display.w;
		vobj->origh = display.h;

		rescale_origwh(vobj, fx, fy);

		vobj->vstore->w = vobj->vstore->scale == ARCAN_VIMAGE_NOPOW2 ? 
			store.w : nexthigher(store.w);

		vobj->vstore->h = vobj->vstore->scale == ARCAN_VIMAGE_NOPOW2 ? 
			store.h : nexthigher(store.h);

		vobj->vstore->vinf.text.s_raw = vobj->vstore->w * vobj->vstore->h * 
			GL_PIXEL_BPP;

		vobj->vstore->vinf.text.raw = malloc(vobj->vstore->vinf.text.s_raw);
		memset(vobj->vstore->vinf.text.raw, '\0', vobj->vstore->vinf.text.s_raw);

		float hx = vobj->vstore->scale == ARCAN_VIMAGE_NOPOW2 ? 1.0 : 
			(float)store.w / (float)vobj->vstore->w;
		float hy = vobj->vstore->scale == ARCAN_VIMAGE_NOPOW2 ? 1.0 : 
			(float)store.h / (float)vobj->vstore->h;

/* as the dimensions may be different, we need to 
 * reinitialize the gl-storage as well */
		glDeleteTextures(1, &vobj->vstore->vinf.text.glid);
		vobj->vstore->vinf.text.glid = 0;

		push_globj(vobj, false, NULL);

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_vobj_id arcan_video_loadimageasynch(const char* rloc, 
	img_cons constraints, intptr_t tag)
{
	arcan_vobj_id rv = loadimage_asynch(rloc, constraints, tag);

	if (rv > 0) {
		arcan_vobject* vobj = arcan_video_getobject(rv);

		if (vobj){
			vobj->current.rotation.quaternion = default_quat;
			arcan_video_attachobject(rv);
		}
	}

	return rv;
}

arcan_vobj_id arcan_video_loadimage(const char* rloc, 
	img_cons constraints, unsigned short zv)
{
	arcan_vobj_id rv = loadimage((char*) rloc, constraints, NULL);

/* the asynch version could've been deleted in between, 
 * so we need to double check */
		if (rv > 0) {
		arcan_vobject* vobj = arcan_video_getobject(rv);
		if (vobj){
			vobj->order = zv;
			vobj->current.rotation.quaternion = default_quat; 
			arcan_video_attachobject(rv);
		}
	}

	return rv;
}

arcan_vobj_id arcan_video_addfobject(arcan_vfunc_cb feed, vfunc_state state,
	img_cons constraints, unsigned short zv)
{
	arcan_vobj_id rv;
	const int feed_ntus = 1;

	if ((rv = arcan_video_setupfeed(feed, constraints, feed_ntus,
		constraints.bpp)) > 0) {
		arcan_vobject* vobj = arcan_video_getobject(rv);
		vobj->order = abs(zv);
		vobj->feed.state = state;

		if (state.tag == ARCAN_TAG_3DOBJ)
			vobj->order *= -1;

		arcan_video_attachobject(rv);
	}

	return rv;
}

arcan_errc arcan_video_scaletxcos(arcan_vobj_id id, float sfs, float sft)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj){
		generate_basic_mapping(vobj->txcos, 1.0, 1.0);
		vobj->txcos[0] *= sfs; 	vobj->txcos[2] *= sfs; 	
		vobj->txcos[4] *= sfs; 	vobj->txcos[6] *= sfs;
		vobj->txcos[1] *= sft; 	vobj->txcos[3] *= sft; 	
		vobj->txcos[5] *= sft; 	vobj->txcos[7] *= sft;

		rv = ARCAN_OK;
	}

	return rv;
}


arcan_errc arcan_video_forceblend(arcan_vobj_id id, enum arcan_blendfunc mode)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		vobj->blendmode = mode;
		rv = ARCAN_OK;
	}

	return rv;
}

unsigned short arcan_video_getzv(arcan_vobj_id id)
{
	unsigned short rv = 0;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		rv = vobj->order;
	}

	return rv;
}

/* no parent resolve performed */
static arcan_errc update_zv(arcan_vobject* vobj, unsigned short newzv)
{
	
	struct rendertarget* owner = vobj->owner;

	if (!owner) 
		return ARCAN_ERRC_UNACCEPTED_STATE;

/*
 * attach also works like an insertion sort where 
 * the insertion criterion is <= order, to aid dynamic 
 * corruption checks, this could be further optimized
 * by using the fact that we're simply "sliding" in the
 * same chain.
 */
	int oldv = vobj->order;
	detach_fromtarget(owner, vobj);
		vobj->order = newzv;
		if (vobj->feed.state.tag == ARCAN_TAG_3DOBJ)
			vobj->order *= -1;
	attach_object(owner, vobj);

/* 
 * unfortunately, we need to do this recursively AND
 * take account for the fact that we may relatively speaking shrink
 * the distance between our orderv vs. parent 
 */
	for (int i = 0; i < vobj->childslots; i++)
		if (vobj->children[i] && vobj->children[i]->flags.orderofs){
			int distance = vobj->children[i]->order - oldv;
			update_zv(vobj->children[i], newzv + distance);
		}
	
	return ARCAN_OK;
}

/* change zval (see arcan_video_addobject) for a particular object.
 * return value is an error code */
arcan_errc arcan_video_setzv(arcan_vobj_id id, unsigned short newzv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* calculate order relative to parent if that's toggled
 * clip to 16bit US and ignore if the parent is a 3dobj */
	if (vobj->flags.orderofs){
		if (vobj->parent->order < 0)
			return ARCAN_ERRC_UNACCEPTED_STATE;
	
		int newv = newzv + vobj->parent->order;
		newzv = newv > 65535 ? 65535 : newv;
	}

/* 
 * Then propagate to any child that might've inherited
 */
	update_zv(vobj, newzv);

	return ARCAN_OK;
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
		if (lifetime == 0){
			vobj->lifetime = -1;
		}
		else
/* make sure the object is flagged as alive */
			vobj->mask |= MASK_LIVING;

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
		surface_transform* current = vobj->transform;

		while (current) {
			surface_transform* next = current->next;
			free(current);
			current = next;
		}
		vobj->transform = NULL;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_instanttransform(arcan_vobj_id id){
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && vobj->transform) {
			surface_transform* current = vobj->transform;
			while (current){
				if (current->move.startt){
					vobj->current.position = current->move.endp;
				}

				if (current->blend.startt)
					vobj->current.opa = current->blend.endopa;

				if (current->rotate.startt)
					vobj->current.rotation = current->rotate.endo;

				if (current->scale.startt)
					vobj->current.scale = current->scale.endd;

				current = current->next;
			}

		invalidate_cache(vobj);
		arcan_video_zaptransform(id);
	}

	return rv;
}

arcan_errc arcan_video_objecttexmode(arcan_vobj_id id, 
	enum arcan_vtex_mode modes, enum arcan_vtex_mode modet)
{
	arcan_vobject* src = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src){
		src->vstore->txu = modes == ARCAN_VTEX_REPEAT ? 
			GL_REPEAT : GL_CLAMP_TO_EDGE;
		src->vstore->txv = modet == ARCAN_VTEX_REPEAT ? 
			GL_REPEAT : GL_CLAMP_TO_EDGE;
		push_globj(src, true, NULL);
	}

	return rv;
}

arcan_errc arcan_video_objectfilter(arcan_vobj_id id, 
	enum arcan_vfilter_mode mode)
{
	arcan_vobject* src = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

/* fake an upload with disabled filteroptions */
	if (src){
		src->vstore->filtermode = mode;
		push_globj(src, true, NULL);
	}

	return rv;
}

arcan_errc arcan_video_transformcycle(arcan_vobj_id sid, bool flag)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* src = arcan_video_getobject(sid);

	if (src)
	{
		src->flags.cycletransform = flag;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_copyprops ( arcan_vobj_id sid, arcan_vobj_id did )
{
	if (sid == did)
		return ARCAN_OK;

	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	arcan_vobject* src = arcan_video_getobject(sid);
	arcan_vobject* dst = arcan_video_getobject(did);

	if (src && dst){
		surface_properties newprop;
		arcan_resolve_vidprop(src, 0.0, &newprop);

		dst->current = newprop;
/* we need to translate scale */
		if (newprop.scale.x > 0 && newprop.scale.y > 0){
			int dstw = newprop.scale.x * src->origw;
			int dsth = newprop.scale.y * src->origh;

			dst->current.scale.x = (float) dstw / (float) dst->origw;
			dst->current.scale.y = (float) dsth / (float) dst->origh;
		}

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_copytransform(arcan_vobj_id sid, arcan_vobj_id did)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	arcan_vobject* src, (* dst);

	if (sid == did)
		rv = ARCAN_ERRC_BAD_ARGUMENT;

	src = arcan_video_getobject(sid);
	dst = arcan_video_getobject(did);

/* remove what's happening in destination, move 
 * pointers from source to dest and done. */
	if (src && dst && src != dst){

		memcpy(&dst->current, &src->current, sizeof(surface_properties));

		arcan_video_zaptransform(did);
		dst->transform = dup_chain(src->transform);
		update_zv(dst, src->order);

		invalidate_cache(dst);

/* in order to NOT break resizefeed etc. this copy actually 
 * requires a modification of the transformation
 * chain, as scale is relative origw? */
		dst->origw = src->origw;
		dst->origh = src->origh;

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_transfertransform(arcan_vobj_id sid, arcan_vobj_id did)
{
	arcan_errc rv = arcan_video_copytransform(sid, did);

	if (rv == ARCAN_OK){
		arcan_vobject* src = arcan_video_getobject(sid);
		arcan_video_zaptransform(sid);
		src->transform = NULL;
	}

	return rv;
}

/* remove a video object that is also a rendertarget (FBO) output */
static void drop_rtarget(arcan_vobject* vobj)
{
/* check if vobj is indeed a rendertarget */
	struct rendertarget* dst = NULL;
	int cascade_c = 0;
	arcan_vobject** pool;

	unsigned dstind;

/* linear search for the vobj among rendertargets */
	for (dstind = 0; dstind < current_context->n_rtargets; dstind++){
		if (current_context->rtargets[dstind].color == vobj){
			dst = &current_context->rtargets[dstind];
			break;
		}
	}

	if (!dst)
		return;

/* found one, disassociate with the context */
	current_context->n_rtargets--;
	assert(current_context->n_rtargets >= 0);

	if (vobj->tracetag)
		arcan_warning("(arcan_video_deleteobject(reference-pass) -- "
			"remove rendertarget (%s)\n", vobj->tracetag);

/* kill GPU resources */
	if (arcan_video_display.fbo_support){
		glDeleteFramebuffers(1, &dst->fbo);
		glDeleteRenderbuffers(1,&dst->depth);
	}

/* PBOs activated for those rendertargets used with readback */
	if (dst->pbo)
		glDeleteBuffers(1, &dst->pbo);

/* create a temporary copy of all the elements in the rendertarget */
	arcan_vobject_litem* current = dst->first;
	size_t pool_sz = (dst->color->extrefc.attachments) * sizeof(arcan_vobject*);
	pool = malloc(pool_sz);

/* note the contents of the rendertarget as "detached" from the source vobj */
	while (current){
		arcan_vobject* base = current->elem;
		pool[cascade_c++]  = base;

/* rtarget has one less attachment, and base is attached to one less */
		vobj->extrefc.attachments--;
		base->extrefc.attachments--;

		trace("(deleteobject::drop_rtarget) remove attached (%d:%s) from"
			"	rendertarget (%d:%s), left: %d:%d\n",
			current->elem->cellid, video_tracetag(current->elem), vobj->cellid, 
			video_tracetag(vobj),vobj->extrefc.attachments,base->extrefc.attachments);
		assert(base->extrefc.attachments >= 0);
		assert(vobj->extrefc.attachments >= 0);

/* cleanup and unlink before moving on */
		arcan_vobject_litem* last = current;
		current->elem = NULL;
		current = current->next;
		last->next = (struct arcan_vobject_litem*) 0xdeadbeef;
		free(last);
	}

/* compact the context array of rendertargets */
	if (dstind+1 < RENDERTARGET_LIMIT)
		memmove(&current_context->rtargets[dstind], 
			&current_context->rtargets[dstind+1], 
			sizeof(struct rendertarget) * (RENDERTARGET_LIMIT - 1 - dstind));

/* always kill the last element */
	memset(&current_context->rtargets[RENDERTARGET_LIMIT- 1], 0, 
		sizeof(struct rendertarget));

/* self-reference gone */
	vobj->extrefc.attachments--;
	trace("(deleteobject::drop_rtarget) remove self reference from "
		"rendertarget (%d:%s)\n", vobj->cellid, video_tracetag(vobj));
	assert(vobj->extrefc.attachments == 0);

/* sweep the list of rendertarget children, and see if we have the 
 * responsibility of cleaning it up */
	for (int i = 0; i < cascade_c; i++)
		if (pool[i] && pool[i]->flags.in_use && pool[i]->owner == dst){
			pool[i]->owner = NULL;

/* cascade or push to stdout as new owner */
			if ((pool[i]->mask & MASK_LIVING) > 0 || pool[i]->flags.clone)
				arcan_video_deleteobject(pool[i]->cellid);
			else
				attach_object(&current_context->stdoutp, pool[i]);
		}

	free(pool);
}

/* by far, the most involved and dangerous function in this .o, 
 * hence the many safe-guards checks and tracing output,
 * the simplest of objects (just an image or whatnot) should have
 * a minimal cost, with everything going up from there.
 * Things to consider:
 * persistence (existing in multiple stack layers, only allowed to be deleted 
 * IF it doesn't exist at a lower layer
 * cloning (instances of an object),
 * rendertargets (objects that gets rendered to)
 * links (objects linked to others to be deleted in a cascading fashion)
 * frameset (object with a n links to other objects that are used to determine 
 * what to draw currently).
 *
 * an object can belong to either a parent object (ultimately, WORLD), 
 * one or more rendertargets, one or more framesets at the same time, 
 * and these deletions should also sustain a full context wipe */
arcan_errc arcan_video_deleteobject(arcan_vobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);
	int cascade_c = 0;

/* some objects can't be deleted */
	if (!vobj || id == ARCAN_VIDEO_WORLDID || id == ARCAN_EID){
		return rv;
	}

/* when a persist is defined in a lower layer, we know that the lowest layer
 * is the last on to have the persistflag) */
	if (vobj->flags.persist &&
		(vcontext_ind > 0 && vcontext_stack[vcontext_ind - 1].vitems_pool[
			vobj->cellid].flags.persist)){
		rv = ARCAN_ERRC_UNACCEPTED_STATE;
		return rv;
	}

	if (current_context->stdoutp.color == vobj){
		current_context->stdoutp.color = NULL;
		glBindBuffer(GL_FRAMEBUFFER, 0);
		glDeleteFramebuffers(1, &current_context->stdoutp.fbo);
		current_context->stdoutp.fbo = 0;
	}

/* step one, disassociate from ALL rendertargets,  */
	detach_fromtarget(&current_context->stdoutp, vobj);
	for (unsigned int i = 0; i < current_context->n_rtargets && 
		vobj->extrefc.attachments; i++)
		detach_fromtarget(&current_context->rtargets[i], vobj);

/* step two, disconnect from parent, WORLD references doesn't count */
	if (vobj->parent && vobj->parent != &current_context->world)
		dropchild(vobj->parent, vobj);

/* vobj might be a rendertarget itself, so detach all its
 * possible members, free FBO/PBO resources etc. */
	drop_rtarget(vobj);

/* populate a pool of cascade deletions, none of this applies to
 * instances as they can only really be part of a rendertarget, 
 * and those are handled separately */
	unsigned sum = vobj->flags.clone ? 0 :
		vobj->frameset_meta.capacity + vobj->extrefc.links + 
		vobj->extrefc.framesets + vobj->extrefc.instances;
	
	arcan_vobject* pool[ (sum + 1) ];

	if (sum){
		memset(pool, 0, sizeof(pool));

/* the frameset is either populated with self-references, 
 * or references to other objects. add references to other objects to a 
 * pool of cascade deletions */
		for (unsigned i = 0; i < vobj->frameset_meta.capacity; i++){
			arcan_vobject* dobj = vobj->frameset[i];
			dobj->extrefc.framesets--;

			trace("(deleteobject) disassociate (%d:%s) from frameset (%d:%s)"
				", left: %d\n", dobj->cellid, video_tracetag(dobj), id, 
				video_tracetag(vobj), dobj->extrefc.framesets);
			assert(dobj->extrefc.framesets >= 0);

/* self-references and instances of self doesn't need to cascade here */
			if (dobj == vobj ||
				dobj->owner != NULL)
				continue;

/* if deletions are masked to cascade, add it to the list,
 * else reattach to world as a last resort */
				if ( (dobj->mask & MASK_LIVING) > 0)
					pool[cascade_c++] = dobj;
				else
					attach_object(&current_context->stdoutp, dobj);
			}
		}

/* drop all children, add those that should be deleted to the pool */
		for (int i = 0; i < vobj->childslots; i++){
			arcan_vobject* cur = vobj->children[i];
			if (cur){
				if (cur->flags.clone || (cur->mask & MASK_LIVING) > 0)
					pool[cascade_c++] = cur;
	
				dropchild(vobj, cur);
			}
		}

		free(vobj->children);
		vobj->childslots = 0;

	current_context->nalive--;

/* time to drop all associated resources */
	arcan_video_zaptransform(id);

/* full- object specific clean-up */
	if (vobj->flags.clone == false){
		if (vobj->feed.ffunc){
			vobj->feed.ffunc(ffunc_destroy, 0, 0, 0, 0, 0, 0, vobj->feed.state);

			vobj->feed.state.ptr = NULL;
			vobj->feed.ffunc = NULL;
			vobj->feed.state.tag = ARCAN_TAG_NONE;
		}

/* synchronize with the threadloader so we don't get a race */
		if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMG){
			pthread_join(*(pthread_t*) vobj->feed.state.ptr, NULL);
			free(vobj->feed.state.ptr);
			vobj->feed.state.ptr = NULL;
		}

		free(vobj->frameset);
		vobj->frameset = NULL;

/* video storage, will take care of refcounting in case of 
 * shared storage etc. */
		drop_glres( vobj->vstore );
		vobj->vstore = NULL;
	}

	if (vobj->extrefc.attachments | vobj->extrefc.framesets | 
		vobj->extrefc.links | vobj->extrefc.instances){
		arcan_warning("[BUG] Broken reference counters for expiring objects, "
			"tracetag? (%s)\n", vobj->tracetag ? vobj->tracetag : "(NO TAG)");
#ifdef _DEBUG
		abort();
#endif
	}

	free(vobj->tracetag);

/* lots of default values are assumed to be 0, so reset the 
 * entire object to be sure. will help leak detectors as well */
	memset(vobj, 0, sizeof(arcan_vobject));

	for (int i = 0; i < cascade_c; i++){
		if (!pool[i])
			continue;

		trace("(deleteobject) cascade pool entry (%d), %d:%s\n", i, pool[i]->cellid,
			pool[i]->tracetag ? pool[i]->tracetag : "(NO TAG)");

		if (pool[i]->flags.in_use)
			arcan_video_deleteobject(pool[i]->cellid);
	}

	return ARCAN_OK;
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

arcan_vobj_id arcan_video_findparent(arcan_vobj_id id)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_vobject* vobj = arcan_video_getobject(id);

		if (vobj){
			rv = id;

			if (vobj->parent && vobj->parent->owner) {
				rv = vobj->parent->cellid;
			}
		}

	return rv;
}

arcan_vobj_id arcan_video_findchild(arcan_vobj_id parentid, unsigned ofs)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_vobject* vobj = arcan_video_getobject(parentid);

	if (!vobj)
		return rv;

	for (int i = 0; i < vobj->childslots; i++){
		if (vobj->children[i]){
			if (ofs > 0)
				ofs--;
			else
				return vobj->children[i]->cellid;
		}
	}

	return rv;
}

arcan_errc arcan_video_objectrotate(arcan_vobj_id id, float roll, float pitch,
	float yaw, unsigned int tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj) {
		rv = ARCAN_OK;
		invalidate_cache(vobj);

		/* clear chains for rotate attribute
		 * if time is set to override and be immediate */
		if (tv == 0) {
			swipe_chain(vobj->transform, offsetof(surface_transform, rotate), 
				sizeof(struct transf_rotate));
			vobj->current.rotation.roll  = roll;
			vobj->current.rotation.pitch = pitch;
			vobj->current.rotation.yaw   = yaw;
			vobj->current.rotation.quaternion = build_quat_taitbryan(roll,pitch,yaw);
		}
		else { /* find endpoint to attach at */
			surface_orientation bv  = vobj->current.rotation;
			surface_transform* base = vobj->transform;
			surface_transform* last = base;

			/* figure out the starting angle */
			while (base && base->rotate.startt) {
				if (!base->next)
					bv = base->rotate.endo;

				last = base;
				base = base->next;
			}

			if (!base){
				if (last)
					base = last->next = calloc(sizeof(surface_transform), 1);
				else
					base = last = calloc(sizeof(surface_transform), 1);
			}

			if (!vobj->transform)
				vobj->transform = base;

			base->rotate.startt = last->rotate.endt < arcan_video_display.c_ticks ? 
				arcan_video_display.c_ticks : last->rotate.endt;
			base->rotate.endt   = base->rotate.startt + tv;
			base->rotate.starto = bv;

			base->rotate.endo.roll  = roll;
			base->rotate.endo.pitch = pitch;
			base->rotate.endo.yaw   = yaw;
			base->rotate.endo.quaternion = build_quat_taitbryan(roll, pitch, yaw);

			base->rotate.interp = (abs(bv.roll - roll) > 180.0 || 
				abs(bv.pitch - pitch) > 180.0 || abs(bv.yaw - yaw) > 180.0) ?
				interpolate_normalized_linear : interpolate_normalized_linear_large;
		}
	}
	
	return rv;
}

arcan_errc arcan_video_origoshift(arcan_vobj_id id, 
	float sx, float sy, float sz)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		invalidate_cache(vobj);
		vobj->flags.origoofs = true;
		vobj->origo_ofs.x = sx;
		vobj->origo_ofs.y = sy;
		vobj->origo_ofs.z = sz;
		rv = ARCAN_OK;
	}

	return rv;
}

/* alter object opacity, range 0..1 */
arcan_errc arcan_video_objectopacity(arcan_vobj_id id, 
	float opa, unsigned int tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);
	opa = CLAMP(opa, 0.0, 1.0);

	if (vobj) {
		rv = ARCAN_OK;
		invalidate_cache(vobj);

		/* clear chains for rotate attribute
		 * if time is set to ovverride and be immediate */
		if (tv == 0) {
			swipe_chain(vobj->transform, offsetof(surface_transform, blend), 
				sizeof(struct transf_blend));
			vobj->current.opa = opa;
		}
		else { /* find endpoint to attach at */
			float bv = vobj->current.opa;

			surface_transform* base = vobj->transform;
			surface_transform* last = base;

			while (base && base->blend.startt) {
				bv = base->blend.endopa;
				last = base;
				base = base->next;
			}

			if (!base){
				if (last)
					base = last->next = calloc(sizeof(surface_transform), 1);
				else
					base = last = calloc(sizeof(surface_transform), 1);
			}

			if (!vobj->transform)
				vobj->transform = base;

			base->blend.startt = last->blend.endt < arcan_video_display.c_ticks ? 
				arcan_video_display.c_ticks : last->blend.endt;
			base->blend.endt = base->blend.startt + tv;
			base->blend.startopa = bv;
			base->blend.endopa = opa + 0.0000000001;
			base->blend.interp = interpolate_linear;
		}
	}

	return rv;
}

/* linear transition from current position to a new desired position,
 * if time is 0 the move will be instantaneous (and not generate an event)
 * otherwise time denotes how many ticks it should take to move the object
 * from its start position to it's final. 
 * An event will in this case be generated */
arcan_errc arcan_video_objectmove(arcan_vobj_id id, float newx, 
	float newy, float newz, unsigned int tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj) {
		rv = ARCAN_OK;
		invalidate_cache(vobj);

/* clear chains for rotate attribute
 * if time is set to ovverride and be immediate */
		if (tv == 0) {
			swipe_chain(vobj->transform, offsetof(surface_transform, move), 
				sizeof(struct transf_move));
			vobj->current.position.x = newx;
			vobj->current.position.y = newy;
			vobj->current.position.z = newz;
		}
/* find endpoint to attach at */
		else { 
			surface_transform* base = vobj->transform;
			surface_transform* last = base;

/* figure out the coordinates which the transformation is chained to */
			point bwp = vobj->current.position;

			while (base && base->move.startt) {
				bwp = base->move.endp;

				last = base;
				base = base->next;
			}

			if (!base){
				if (last)
					base = last->next = calloc(sizeof(surface_transform), 1);
				else
					base = last = calloc(sizeof(surface_transform), 1);
			}

			point newp = {newx, newy, newz};

			if (!vobj->transform)
				vobj->transform = base;

			base->move.startt = last->move.endt < arcan_video_display.c_ticks ?
				arcan_video_display.c_ticks : last->move.endt;
			base->move.endt   = base->move.startt + tv;
			base->move.interp = interpolate_linear;
			base->move.startp = bwp;
			base->move.endp   = newp;
		}
	}

	return rv;
}

/* scale the video object to match neww and newh, with stepx or 
 * stepy at 0 it will be instantaneous,
 * otherwise it will move at stepx % of delta-size each tick
 * return value is an errorcode, run through char* arcan_verror(int8_t) */
arcan_errc arcan_video_objectscale(arcan_vobj_id id, float wf, 
	float hf, float df, unsigned tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj) {
		const int immediately = 0;
		rv = ARCAN_OK;
		invalidate_cache(vobj);

		if (tv == immediately) {
			swipe_chain(vobj->transform, offsetof(surface_transform, scale), 
				sizeof(struct transf_scale));

			vobj->current.scale.x = wf;
			vobj->current.scale.y = hf;
			vobj->current.scale.z = df;
		}
		else {
			surface_transform* base = vobj->transform;
			surface_transform* last = base;

/* figure out the coordinates which the transformation is chained to */
			scalefactor bs = vobj->current.scale;

			while (base && base->scale.startt) {
				bs = base->scale.endd;

				last = base;
				base = base->next;
			}

			if (!base){
				if (last)
					base = last->next = calloc(sizeof(surface_transform), 1);
				else
					base = last = calloc(sizeof(surface_transform), 1);
			}

			if (!vobj->transform)
				vobj->transform = base;

			base->scale.startt = last->scale.endt < arcan_video_display.c_ticks ?
				arcan_video_display.c_ticks : last->scale.endt;
			base->scale.endt = base->scale.startt + tv;
			base->scale.interp = interpolate_linear;
			base->scale.startd = bs;
			base->scale.endd.x = wf;
			base->scale.endd.y = hf;
			base->scale.endd.z = df;
		}
	}

	return rv;
}

/* called whenever a cell in update has a time that reaches 0 */
static void compact_transformation(arcan_vobject* base, 
	unsigned int ofs, unsigned int count)
{
	if (!base || !base->transform) return;

	surface_transform* last = NULL;
	surface_transform* work = base->transform;
	/* copy the next transformation */

	while (work && work->next) {
		assert(work != work->next);
		memcpy((char*)(work) + ofs, (char*)(work->next) + ofs, count);
		last = work;
		work = work->next;
	}

	/* reset the last one */
	memset((char*) work + ofs, 0, count);

	/* if it is now empty, free and delink */
	if (!(work->blend.startt |
	          work->scale.startt |
	          work->move.startt |
	          work->rotate.startt )
	   )	{
		free(work);
		if (last)
			last->next = NULL;
		else
			base->transform = NULL;
	}
}

arcan_errc arcan_video_setprogram(arcan_vobj_id id, arcan_shader_id shid)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && arcan_shader_valid(shid)) {
		vobj->program = shid;
		rv = ARCAN_OK;
	}

	return rv;
}

static quat interp_rotation(quat* q1, quat* q2, 
	float fract, enum arcan_interp_function fun)
{
	switch (fun){
	case interpolate_linear :
	case interpolate_normalized_linear: return nlerp_quat180(*q1, *q2, fract); 
	case interpolate_normalized_linear_large: return nlerp_quat360(*q1,*q2,fract);
	case interpolate_spherical: return slerp_quat180(*q1, *q2, fract); 
	case interpolate_spherical_large : return slerp_quat360(*q1, *q2, fract); 
	}
  return *q1;
}

static bool update_object(arcan_vobject* ci, unsigned long long stamp)
{
	bool upd = false;

/* update parent if this has not already been updated this cycle */
	if (ci->last_updated < stamp &&
		ci->parent && ci->parent != &current_context->world &&
		ci->parent->last_updated != stamp){
		update_object(ci->parent, stamp);
	}

	ci->last_updated = stamp;

	if (!ci->transform)
		return false;

	if (ci->transform->blend.startt) {
		upd = true;
		float fract = lerp_fract(ci->transform->blend.startt, 
			ci->transform->blend.endt, stamp);
		ci->current.opa = lerp_val(ci->transform->blend.startopa, 
			ci->transform->blend.endopa, fract);

		if (fract > 0.9999f) {
			ci->current.opa = ci->transform->blend.endopa;

			if (ci->flags.cycletransform){
				arcan_video_objectopacity(ci->cellid, ci->transform->blend.endopa, 
					ci->transform->blend.endt - ci->transform->blend.startt);
			}

			compact_transformation(ci,
				offsetof(surface_transform, blend),
				sizeof(struct transf_blend));

/* only fire event if we've run out of the 
 * transform chain for the current value */
			if (!ci->transform || ci->transform->blend.startt == 0) {
				arcan_event ev = {.category = EVENT_VIDEO, 
					.kind = EVENT_VIDEO_BLENDED
				};

				ev.data.video.source = ci->cellid;
				arcan_event_enqueue(arcan_event_defaultctx(), &ev);
			}
		}
	}

	if (ci->transform && ci->transform->move.startt) {
		upd = true;
		float fract = lerp_fract(ci->transform->move.startt, 
			ci->transform->move.endt, stamp);
		ci->current.position = lerp_vector(ci->transform->move.startp, 
			ci->transform->move.endp, fract);

		if (fract > 0.9999f) {
			ci->current.position = ci->transform->move.endp;

			if (ci->flags.cycletransform)
				arcan_video_objectmove(ci->cellid,
					 ci->transform->move.endp.x,
					 ci->transform->move.endp.y,
					 ci->transform->move.endp.z,
					 ci->transform->move.endt - ci->transform->move.startt);

			compact_transformation(ci,
				offsetof(surface_transform, move),
				sizeof(struct transf_move));

			if (!ci->transform || ci->transform->move.startt == 0) {
				arcan_event ev = {.category = EVENT_VIDEO, .kind = EVENT_VIDEO_MOVED};
				ev.data.video.source = ci->cellid;
				arcan_event_enqueue(arcan_event_defaultctx(), &ev);
			}
		}
	}

	if (ci->transform && ci->transform->scale.startt) {
		upd = true;
		float fract = lerp_fract(ci->transform->scale.startt, 
			ci->transform->scale.endt, stamp);
		ci->current.scale = lerp_vector(ci->transform->scale.startd, 
			ci->transform->scale.endd, fract);

		if (fract > 0.9999f) {
			ci->current.scale = ci->transform->scale.endd;

			if (ci->flags.cycletransform)
				arcan_video_objectscale(ci->cellid, ci->transform->scale.endd.x,
					ci->transform->scale.endd.y,
					ci->transform->scale.endd.z,
					ci->transform->scale.endt - ci->transform->scale.startt);

			compact_transformation(ci,
				offsetof(surface_transform, scale),
				sizeof(struct transf_scale));

			if (!ci->transform || ci->transform->scale.startt == 0) {
				arcan_event ev = {.category = EVENT_VIDEO, .kind = EVENT_VIDEO_SCALED};
				ev.data.video.source = ci->cellid;
				arcan_event_enqueue(arcan_event_defaultctx(), &ev);
			}
		}
	}

	if (ci->transform && ci->transform->rotate.startt) {
		upd = true;
		float fract = lerp_fract(ci->transform->rotate.startt, 
			ci->transform->rotate.endt, stamp);

/* close enough */
		if (fract > 0.9999f) {
			ci->current.rotation = ci->transform->rotate.endo;
			if (ci->flags.cycletransform)
				arcan_video_objectrotate(ci->cellid,
					ci->transform->rotate.endo.roll,
					ci->transform->rotate.endo.pitch,
					ci->transform->rotate.endo.yaw,
					ci->transform->rotate.endt - ci->transform->rotate.startt);

			compact_transformation(ci,
				offsetof(surface_transform, rotate),
				sizeof(struct transf_rotate));

			if (!ci->transform || ci->transform->rotate.startt == 0) {
				arcan_event ev = { .category = EVENT_VIDEO, 
					.kind = EVENT_VIDEO_ROTATED
				};
				ev.data.video.source = ci->cellid;
				arcan_event_enqueue(arcan_event_defaultctx(), &ev);
			}
		}
		else
			ci->current.rotation.quaternion = 
				interp_rotation(&ci->transform->rotate.starto.quaternion,
				&ci->transform->rotate.endo.quaternion, fract, 
				ci->transform->rotate.interp);
	}

	return upd;
}

static void expire_object(arcan_vobject* obj){
	if (obj->lifetime && --obj->lifetime == 0)
	{
		arcan_event dobjev = {
		.category = EVENT_VIDEO,
		.kind = EVENT_VIDEO_EXPIRE
		};

		dobjev.data.video.source = obj->cellid;

#ifdef _DEBUG
		if (obj->tracetag){
			arcan_warning("arcan_event(EXPIRE) -- "
				"traced object expired (%s)\n", obj->tracetag);
		}
#endif

		arcan_event_enqueue(arcan_event_defaultctx(), &dobjev);
	}
}

/* process a logical time-frame (which more or less means, 
 * update / rescale / redraw / flip) returns msecs elapsed */
static void tick_rendertarget(struct rendertarget* tgt)
{
	unsigned now = arcan_frametime();
	arcan_vobject_litem* current = tgt->first;

	while (current){
		arcan_vobject* elem = current->elem;
		if (elem->last_updated != arcan_video_display.c_ticks){
/* is the item to be updated? */
			update_object(elem, arcan_video_display.c_ticks);
		}

		if (elem->feed.ffunc)
			elem->feed.ffunc(ffunc_tick, 0, 0, 0, 0, 0, 0, elem->feed.state);

/* special case for "unreachables", e.g. detached frameset cells */
		for (int i = 0; i < elem->frameset_meta.capacity; i++){
			arcan_vobject* cell = elem->frameset[i];
			if (cell->owner == NULL && cell->feed.ffunc)
				elem->feed.ffunc(ffunc_tick, 0, 0, 0, 0, 0, 0, elem->feed.state);
		}

/* mode > 0, cycle every 'n' ticks */
		if (elem->frameset_meta.mode > 0){
			elem->frameset_meta.counter--;
			if (elem->frameset_meta.counter == 0){
				elem->frameset_meta.counter = abs( elem->frameset_meta.mode );
				step_active_frame(elem);
			}
		}

		if ((elem->mask & MASK_LIVING) > 0)
			expire_object(elem);
		
		current = current->next;
	}
}

#ifndef SHADER_TIME_PERIOD
#define SHADER_TIME_PERIOD 128
#endif
unsigned arcan_video_tick(unsigned steps)
{
	if (steps == 0)
		return 0;

	unsigned now = arcan_frametime();
	uint32_t tsd = arcan_video_display.c_ticks % SHADER_TIME_PERIOD;

	do {
		update_object(&current_context->world, arcan_video_display.c_ticks);

		arcan_shader_envv(TIMESTAMP_D, &tsd, sizeof(uint32_t));

		for (int i = 0; i < current_context->n_rtargets; i++)
			tick_rendertarget(&current_context->rtargets[i]);

		tick_rendertarget(&current_context->stdoutp);
		arcan_video_display.c_ticks++;
		steps = steps - 1;
	} while (steps);

	return arcan_frametime() - now;
}

arcan_errc arcan_video_setclip(arcan_vobj_id id, enum arcan_clipmode mode)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		vobj->flags.cliptoparent = mode;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_persistobject(arcan_vobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		if (vobj->flags.clone == false &&
			vobj->frameset_meta.capacity == 0 &&
			vobj->vstore->refcount == 1 && 
			vobj->parent == &current_context->world){
			vobj->flags.persist = true;
			rv = ARCAN_OK;
		}
		else
			rv = ARCAN_ERRC_UNACCEPTED_STATE;
	}

	return rv;
}

bool arcan_video_visible(arcan_vobj_id id)
{
	bool rv = false;
	arcan_vobject* vobj= arcan_video_getobject(id);

	if (vobj && id > 0)
		return vobj->current.opa > 0.001;

	return rv;
}

/* take sprops, apply them to the coordinates in vobj with proper 
 * masking (or force to ignore mask), store the results in dprops */
static void apply(arcan_vobject* vobj, surface_properties* dprops, float lerp, 
	surface_properties* sprops, bool force)
{
	*dprops = vobj->current;

	if (vobj->transform){
		surface_transform* tf = vobj->transform;
		unsigned ct = arcan_video_display.c_ticks;

		if (tf->move.startt)
			dprops->position = lerp_vector(tf->move.startp,
				tf->move.endp,
				lerp_fract(tf->move.startt, tf->move.endt, (float)ct + lerp));

		if (tf->scale.startt)
			dprops->scale = lerp_vector(tf->scale.startd, tf->scale.endd, 
				lerp_fract(tf->scale.startt, tf->scale.endt, (float)ct + lerp));

		if (tf->blend.startt)
			dprops->opa = lerp_val(tf->blend.startopa, tf->blend.endopa, 
				lerp_fract(tf->blend.startt, tf->blend.endt, (float)ct + lerp));

		if (tf->rotate.startt){
			dprops->rotation.quaternion = interp_rotation(
				&tf->rotate.starto.quaternion, &tf->rotate.endo.quaternion,
				lerp_fract(tf->rotate.startt, tf->rotate.endt, 
					(float)ct + lerp), tf->rotate.interp);

			vector ang = angle_quat(dprops->rotation.quaternion);
			dprops->rotation.roll  = ang.x;
			dprops->rotation.pitch = ang.y;
			dprops->rotation.yaw   = ang.z;
		}

		if (!sprops)
			return;
	}

/*	if (force || (vobj->mask & MASK_SCALE) > 0){
		printf("%f, %f, %f => %f, %f, %f\n", dprops->scale.x, dprops->scale.y,
										dprops->scale.z, sprops->scale.x, sprops->scale.y, sprops->scale.z);
		dprops->scale.x *= sprops->scale.x;
		dprops->scale.y *= sprops->scale.y;
		dprops->scale.z *= sprops->scale.z;
	} */

/* translate to sprops */
	if (force || (vobj->mask & MASK_POSITION) > 0)
		dprops->position = add_vector(dprops->position, sprops->position);

	if (force || (vobj->mask & MASK_ORIENTATION) > 0){
		dprops->rotation.yaw   += sprops->rotation.yaw;
		dprops->rotation.pitch += sprops->rotation.pitch;
		dprops->rotation.roll  += sprops->rotation.roll;
		dprops->rotation.quaternion = mul_quat( sprops->rotation.quaternion, 
			dprops->rotation.quaternion );

#ifdef _DEBUG
/*		vector ang = angle_quat(dprops->rotation.quaternion);
			dprops->rotation.roll  = ang.x;
			dprops->rotation.pitch = ang.y;
			dprops->rotation.yaw   = ang.z; */
#endif
	}

	if (force || (vobj->mask & MASK_OPACITY) > 0){
		dprops->opa *= sprops->opa;
	}
}

/* 
 * Caching works as follows;
 * Any object that has a parent with an ongoing transformation
 * has its valid_cache property set to false
 * upon changing it to true a copy is made and stored in prop_cache
 * and a resolve- pass is performed with its results stored in prop_matr 
 * which is then re-used every rendercall.
 * Queueing a transformation immediately invalidates the cache.
 */
void arcan_resolve_vidprop(arcan_vobject* vobj, float lerp, 
	surface_properties* props)
{
	if (vobj->valid_cache)
		*props = vobj->prop_cache;

/* first recurse to parents */
	else if (vobj->parent && vobj->parent != &current_context->world){
		surface_properties dprop = empty_surface();
		arcan_resolve_vidprop(vobj->parent, lerp, &dprop);
		apply(vobj, props, lerp, &dprop, false);
	}
	else
		apply(vobj, props, lerp, &current_context->world.current, true);

	arcan_vobject* current = vobj;
	bool can_cache = true;
	while (current){
		if (current->transform){
			can_cache = false;
			break;
		}
		current = current->parent;
	}

	if (can_cache && vobj->owner && vobj->valid_cache == false){
		surface_properties dprop = *props; 
		vobj->prop_cache  = *props;
		vobj->valid_cache = true;
		build_modelview(vobj->prop_matr, vobj->owner->base, &dprop, vobj);
	}
 	else;
}

static inline void draw_vobj(float x, float y, float x2, float y2, 
	float zv, float* txcos)
{
	GLfloat verts[] = { x,y, x2,y, x2,y2, x,y2 };
	bool settex = false;

	GLint attrindv = arcan_shader_vattribute_loc(ATTRIBUTE_VERTEX);
	GLint attrindt = arcan_shader_vattribute_loc(ATTRIBUTE_TEXCORD);

	if (attrindv != -1){
		glEnableVertexAttribArray(attrindv);
		glVertexAttribPointer(attrindv, 2, GL_FLOAT, GL_FALSE, 0, verts);

		if (txcos && attrindt != -1){
			settex = true;
			glEnableVertexAttribArray(attrindt);
			glVertexAttribPointer(attrindt, 2, GL_FLOAT, GL_FALSE, 0, txcos);
		}

		glDrawArrays(GL_TRIANGLE_FAN, 0, 4);

		if (settex)
			glDisableVertexAttribArray(attrindt);

		glDisableVertexAttribArray(attrindv);
	}
}

static inline void build_modelview(float* dmatr, 
	float* imatr, surface_properties* prop, arcan_vobject* src)
{
	float omatr[16], tmatr[16];
/* now position represents centerpoint in screen coordinates */
	prop->scale.x *= src->origw * 0.5f;
	prop->scale.y *= src->origh * 0.5f;
	prop->position.x += prop->scale.x;
	prop->position.y += prop->scale.y;

	src->rotate_state = 
		abs(prop->rotation.roll)  > EPSILON ||
		abs(prop->rotation.pitch) > EPSILON ||
		abs(prop->rotation.yaw)   > EPSILON;	 

	memcpy(tmatr, imatr, sizeof(float) * 16);

	if (src->rotate_state)
		matr_quatf(norm_quat (prop->rotation.quaternion), omatr);

/* rotate around user-defined point rather than own center */
	if (src->flags.origoofs && src->rotate_state){
		translate_matrix(tmatr, 
			prop->position.x + src->origo_ofs.x,
			prop->position.y + src->origo_ofs.y, 0.0);

		multiply_matrix(dmatr, tmatr, omatr);
		translate_matrix(dmatr, -src->origo_ofs.x, -src->origo_ofs.y, 0.0); 
	}
	else	
		translate_matrix(tmatr, prop->position.x, prop->position.y, 0.0); 

	if (src->rotate_state)	
		multiply_matrix(dmatr, tmatr, omatr);
	else
		memcpy(dmatr, tmatr, sizeof(float) * 16);
}

static inline void setup_surf(struct rendertarget* dst,
	surface_properties* prop, arcan_vobject* src)
{
	if (src->feed.state.tag == ARCAN_TAG_ASYNCIMG)
 		return;

/* currently, we only cache the primary rendertarget */
	if (src->valid_cache && dst == src->owner){
		prop->scale.x *= src->origw * 0.5f;
		prop->scale.y *= src->origh * 0.5f;
		prop->position.x += prop->scale.x;
		prop->position.y += prop->scale.y;

		arcan_shader_envv(MODELVIEW_MATR, src->prop_matr, sizeof(float) * 16);
	}
	else {	
		float dmatr[16];
		build_modelview(dmatr, dst->base, prop, src); 
		arcan_shader_envv(MODELVIEW_MATR, dmatr, sizeof(float) * 16);
	}

	arcan_shader_envv(OBJ_OPACITY, &prop->opa, sizeof(float));
}

static inline void draw_colorsurf(struct rendertarget* dst,
	surface_properties prop, arcan_vobject* src, float r, float g, float b)
{
	float cval[3] = {r, g, b};	

	setup_surf(dst, &prop, src);
	arcan_shader_forceunif("obj_col", shdrvec3, (void*) &cval, false); 
	draw_vobj(-prop.scale.x, -prop.scale.y, prop.scale.x, 
		prop.scale.y, 0, NULL);
}

static inline void draw_texsurf(struct rendertarget* dst,
	surface_properties prop, arcan_vobject* src, float* txcos)
{
	setup_surf(dst, &prop, src);
	draw_vobj(-prop.scale.x, -prop.scale.y, prop.scale.x, 
		prop.scale.y, 0, txcos);
}

static void ffunc_process(arcan_vobject* dst)
{
/*
 * if there's a feed function, try and grab a new sample and upload,
 * make sure that we use the current elements "feed function",but set 
 * the target to its current active frame, most of the time, 
 * they are the same */

	if (dst->flags.clone == false && dst->feed.ffunc &&
		dst->feed.ffunc(ffunc_poll, 0, 0, 0, 0, 0, 0, dst->feed.state) == 
			FFUNC_RV_GOTFRAME) {
		arcan_vobject* cframe = dst->current_frame;

/* cycle active frame */
		if (dst->frameset_meta.mode < 0){
			dst->frameset_meta.counter--;

			if (dst->frameset_meta.counter == 0){
				dst->frameset_meta.counter = abs( dst->frameset_meta.mode );
				step_active_frame(dst);

				cframe = dst->current_frame;
			}
		}

	enum arcan_ffunc_rv funcres = dst->feed.ffunc(ffunc_render,
		cframe->vstore->vinf.text.raw, cframe->vstore->vinf.text.s_raw,
		cframe->vstore->w, cframe->vstore->h, cframe->vstore->bpp,
		cframe->vstore->vinf.text.glid,
		dst->feed.state);

/*
 * special "hack" for situations where the ffunc can do the 
 * gl-calls without an additional memtransfer (some video/targets, 
 * particularly in no POW2 Textures), this interface should really be
 * changed to use glBufferData + GL_STREAM_COPY or GL_DYNAMIC_COPY 
*/
		if (funcres == FFUNC_RV_COPIED){
			glBindTexture(GL_TEXTURE_2D, cframe->vstore->vinf.text.glid);
			glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cframe->vstore->w, 
				cframe->vstore->h, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, 
				cframe->vstore->vinf.text.raw);
		}
	}

	return;
}

/*
 * scan all 'feed objects' (possible optimization, keep these tracked
 * in a separate list and run prior to all other rendering, might gain 
 * something when other pseudo-asynchronous operations (e.g. PBO) are concerned
 */
static void poll_list(arcan_vobject_litem* current)
{
	while(current && current->elem){
	arcan_vobject* cframe = current->elem->current_frame;
	arcan_vobject* celem  = current->elem;

	ffunc_process(celem);

/* special treatment for "orphans" */
	for (unsigned int i = 0; i < celem->frameset_meta.capacity; i++)
		if (celem->frameset[i]->owner == NULL)
			ffunc_process(celem->frameset[i]);

		current = current->next;
	}
}

void arcan_video_pollfeed(){
	for (int i = 0; i < current_context->n_rtargets; i++)
		poll_list(current_context->rtargets[i].first);

	poll_list(current_context->stdoutp.first);
}

void arcan_video_setblend(const surface_properties* dprops, 
	const arcan_vobject* elem)
{
/* only blend if the object isn't entirely solid or 
 * if the object has specific settings */
	if (dprops->opa > 0.999f && elem->blendmode == blend_disable)
		glDisable(GL_BLEND);
	else{
		glEnable(GL_BLEND);
		switch (elem->blendmode){
		case blend_force:
		case blend_normal: glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA); 
		break;
		case blend_multiply: glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA); 
		break;
		case blend_add: glBlendFunc(GL_ONE, GL_ONE); 
		break;
		default:
			arcan_warning("unknown blend-mode specified(%d)\n", elem->blendmode);
		}
	}
}

static void process_rendertarget(struct rendertarget* tgt, float fract)
{
	arcan_vobject* world = &current_context->world;
	arcan_vobject_litem* current = tgt->first;
	int width, height;

	if (tgt->color){
		width = tgt->color->origw;
		height = tgt->color->origh;
	}
	else{
		width = arcan_video_display.width;
		height = arcan_video_display.height;
	}

/* since the rendertargets may vary in size etc. 
 * we setup the viewport/scissoring here */
	glScissor(0, 0, width, height);
	glViewport(0, 0, width, height);

/* should possibly have a "per rendertarget" flag to disable this one
 * amounts to quite some overdraw on low- power devices */
	glClear(GL_COLOR_BUFFER_BIT);
	arcan_debug_pumpglwarnings("refreshGL:pre3d");

/* first, handle all 3d work 
 * (which may require multiple passes etc.) */
	if (!arcan_video_display.order3d == order3d_first && 
		current && current->elem->order < 0){
		current = arcan_refresh_3d(tgt->camtag, current, fract);
	}

/* skip a possible 3d pipeline */
	while (current && current->elem->order < 0)
		current = current->next;

	arcan_debug_pumpglwarnings("refreshGL:pre2d");

	if (current){
	/* make sure we're in a decent state for 2D */
		glDisable(GL_DEPTH_TEST);

		arcan_shader_activate(arcan_video_display.defaultshdr);
		arcan_shader_envv(PROJECTION_MATR, tgt->projection, sizeof(float)*16);
		arcan_shader_envv(FRACT_TIMESTAMP_F, &fract, sizeof(float));

		while (current && current->elem->order >= 0){
#ifdef _DEBUG
			char cvid[24];
			snprintf(cvid,24,"refreshGL:2d(%d)", (unsigned) current->elem->cellid);
			if (arcan_debug_pumpglwarnings(cvid) == -1){
				arcan_warning("fatal: GL error detected, check dump.\n");
				abort();
			};
#endif

			arcan_vobject* elem = current->elem;
			surface_properties* csurf = &elem->current;

/* calculate coordinate system translations, world cannot be masked */
			surface_properties dprops = empty_surface();
			arcan_resolve_vidprop(elem, fract, &dprops);

/* don't waste time on objects that aren't supposed to be visible */
			if ( dprops.opa < EPSILON || elem == current_context->stdoutp.color){
				current = current->next;
				continue;
			}

/* special safeguards, current_frame could've been deleted and replaced 
 * leaving a dangling pointer here,or frameset location might've moved */
			if (elem->flags.clone){
				if ( (elem->mask & MASK_FRAMESET) > 0 ){
					enum arcan_framemode mode = elem->frameset_meta.framemode;
					elem->frameset = elem->parent->frameset;
					elem->frameset_meta = elem->parent->frameset_meta;
					elem->current_frame = elem->parent->current_frame;
					elem->frameset_meta.mode = mode;
				} else {
					elem->frameset = elem->parent->frameset;
					elem->frameset_meta.capacity = elem->parent->frameset_meta.capacity;

					assert(elem->parent && elem->parent != &current_context->world);
					elem->current_frame = (elem->parent->frameset_meta.capacity > 0 &&
						elem->parent->frameset[ elem->frameset_meta.current ]) ?
					elem->parent->frameset[elem->frameset_meta.current] : 
					elem->parent->current_frame;
				}
			}

/* enable clipping using stencil buffer */
			bool clipped = false;
			if (elem->flags.cliptoparent != ARCAN_CLIP_OFF && 
				elem->parent != &current_context->world){
/* toggle stenciling, reset into zero, draw parent bounding area to 
 * stencil only,redraw parent into stencil, draw new object 
 * then disable stencil. */
				clipped = true;
				glEnable(GL_STENCIL_TEST);
				glDisable(GL_BLEND);

				glClearStencil(0);
				glClear(GL_STENCIL_BUFFER_BIT);
				glColorMask(0, 0, 0, 0);
				glStencilFunc(GL_ALWAYS, 1, 1);
				glStencilOp(GL_REPLACE, GL_REPLACE, GL_REPLACE);

/* switch to default color shader as we don't want any fancy 
 * vertex processing or texturing interfering with clipping */
				arcan_shader_activate(arcan_video_display.defclrshdr);
				arcan_vobject* celem = elem;

				if (celem->flags.cliptoparent == ARCAN_CLIP_SHALLOW){
					surface_properties pprops = empty_surface();
					arcan_resolve_vidprop(celem->parent, fract, &pprops);
					draw_colorsurf(tgt, pprops, celem->parent, 1.0, 1.0, 1.0);
				}
				else
/* deep -> draw all objects that aren't clipping to parent,
 * terminate when a shallow clip- object is found */
				while (celem->parent != &current_context->world){
					surface_properties pprops = empty_surface();
					arcan_resolve_vidprop(celem->parent, fract, &pprops);

					if (celem->parent->flags.cliptoparent == ARCAN_CLIP_OFF)
						draw_colorsurf(tgt, pprops, celem->parent, 1.0, 1.0, 1.0);
					else if (celem->parent->flags.cliptoparent == ARCAN_CLIP_SHALLOW){
						draw_colorsurf(tgt, pprops, celem->parent, 1.0, 1.0, 1.0);
						break;
					}

					celem = celem->parent;
				}

				glColorMask(1, 1, 1, 1);
				glStencilFunc(GL_EQUAL, 1, 1);
				glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
			}

/* if the object is not txmapped (or null, in that case give up) */ 
		if (elem->vstore->txmapped == TXSTATE_OFF){
			if (elem->program != 0){
				arcan_shader_activate(elem->program);
				draw_colorsurf(tgt, dprops, elem, elem->vstore->vinf.col.r,
					elem->vstore->vinf.col.g, elem->vstore->vinf.col.b);
			}

			if (clipped)
				glDisable(GL_STENCIL_TEST);

			current = current->next;
			continue;
		}

		arcan_shader_activate( elem->program > 0 ? 
			elem->program : arcan_video_display.defaultshdr );

/* depending on frameset- mode, we may need to split 
 * the frameset up into multitexturing */
		int cfind  = elem->frameset_meta.current;
		int unbc = 0;
		if (elem->frameset_meta.capacity > 0 && 
			elem->frameset_meta.framemode == ARCAN_FRAMESET_MULTITEXTURE){
			int j = GL_MAX_TEXTURE_UNITS < elem->frameset_meta.capacity ? 
				GL_MAX_TEXTURE_UNITS : elem->frameset_meta.capacity;
			unbc = 0;

			for(int i = 0; i < j; i++){
				char unifbuf[16];
				unifbuf[15] = '\0';

				int frameind = ((cfind - i) % j + j)  % j;

				glActiveTexture(GL_TEXTURE0 + i);
				glBindTexture(GL_TEXTURE_2D, 
					elem->frameset[ frameind ]->vstore->vinf.text.glid);
				snprintf(unifbuf, 15, "map_tu%d", i);
				arcan_shader_forceunif(unifbuf, shdrint, &i, false);
			}

			glActiveTexture(GL_TEXTURE0);
		}
		else
			glBindTexture(GL_TEXTURE_2D, 
				elem->current_frame->vstore->vinf.text.glid);

		float* txcos = elem->current_frame->txcos;

		if ( (elem->mask & MASK_MAPPING) > 0)
			txcos = elem->parent != &current_context->world ? 
				elem->parent->txcos : elem->txcos;
		else if (elem->flags.clone)
			txcos = elem->txcos;

		arcan_video_setblend(&dprops, elem);
		draw_texsurf(tgt, dprops, elem, txcos);

/* even though there might be latent "other frames" bound,
 * they won't change much unless the program itself uses multitexturing 
		if (unbc){
			for (int i = 1; i <= unbc-1; i++){
				glActiveTexture(GL_TEXTURE0 + i);
				glBindTexture(GL_TEXTURE_2D, 0);
			}
			glActiveTexture(GL_TEXTURE0);
		}
*/

		if (clipped)
			glDisable(GL_STENCIL_TEST);

			current = current->next;
		}
	}

/* reset and try the 3d part again if requested */
	current = tgt->first;
	if (current && current->elem->order < 0 && 
		arcan_video_display.order3d == order3d_last)
		current = arcan_refresh_3d(tgt->camtag, current, fract);
}

arcan_errc arcan_video_forceread(arcan_vobj_id sid, void** dptr, size_t* dsize)
{
/*
 * more involved tha one may think, the store doesn't have to be representative
 * in case of rendertargets, and for streaming readbacks of those we already
 * have readback toggles etc. Thus this function is only for "one-off" reads
 * where a blocking behavior may be accepted, especially outside a main 
 * renderloop as this will force a sync for the pipeline. 
 */
	
	arcan_vobject* vobj = arcan_video_getobject(sid);
	struct storage_info_t* dstore = vobj->vstore;

	if (!vobj || !dstore) 
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	*dsize = GL_PIXEL_BPP * dstore->w * dstore->h; 
	*dptr  = malloc(*dsize);

	glBindTexture(GL_TEXTURE_2D, dstore->vinf.text.glid); 
	glGetTexImage(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, *dptr);
	glBindTexture(GL_TEXTURE_2D, 0);

	return ARCAN_OK;
}

arcan_errc arcan_video_screenshot(void** dptr, size_t* dsize)
{
	*dsize = sizeof(char) * arcan_video_display.width * 
		arcan_video_display.height * GL_PIXEL_BPP;

	*dptr = malloc( *dsize );

	if (!(*dptr)){
		*dsize = 0;
		return ARCAN_ERRC_OUT_OF_SPACE;
	}

	glReadBuffer(GL_FRONT);

	glReadPixels(0, 0, arcan_video_display.width, 
		arcan_video_display.height, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, *dptr);

	return ARCAN_OK;
}

static void process_readback(struct rendertarget* tgt, float fract)
{
/* should we issue a new readback? */
	bool req_rb = false;

/* check if there's data ready to be copied,
 * this doesn't work for STENCIL or DEPTH */
	if (tgt->readreq && arcan_video_display.pbo_support){
		glBindBuffer(GL_PIXEL_PACK_BUFFER, tgt->pbo);
		GLubyte* src = glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_READ_ONLY);

		if (src){
			arcan_vobject* vobj = tgt->color;
			vobj->feed.ffunc(ffunc_rendertarget_readback, src, 
				vobj->vstore->w * vobj->vstore->h * vobj->vstore->bpp,
				vobj->vstore->w,  vobj->vstore->h,  vobj->vstore->bpp, 0,
				vobj->feed.state);
		}

/* TODO: EGL/GLES target doesn't have PBOs until 3.0,
 * the fallback option should be glReadPixels */
		glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
		tgt->readreq = false;
	}

/* resolution is "by frame" */
	if (tgt->readback < 0){
		tgt->readcnt--;
		if (tgt->readcnt == 0){
			req_rb = true;
			tgt->readcnt = abs(tgt->readback);
		}
	}

/* resolution is "by ms", approximately */
	else if (tgt->readback > 0){
		long long stamp = round( ((double)arcan_video_display.c_ticks + fract) * 
			(double)ARCAN_TIMER_TICK );
		if (stamp - tgt->readcnt > tgt->readback){
			req_rb = true;
			tgt->readcnt = stamp;
		}
	}

/* check if we should request new data */
	if (req_rb && arcan_video_display.pbo_support){
		glBindBuffer(GL_PIXEL_PACK_BUFFER, tgt->pbo);
		glBindTexture(GL_TEXTURE_2D, tgt->color->vstore->vinf.text.glid);
		glGetTexImage(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, 0);

/* null as PBO is responsible */
		tgt->readreq = true;
	}

cleanup:
	glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
}

void arcan_video_refresh_GL(float lerp)
{
/* for performance reasons, we should try and re-use FBOs whenever possible */
	if (arcan_video_display.fbo_support){
		for (off_t ind = 0; ind < current_context->n_rtargets; ind++){
			struct rendertarget* tgt = &current_context->rtargets[ind];
			bool active_fbo = activate_fbo(tgt);
			
			if (active_fbo){
				process_rendertarget(tgt, lerp);
				process_readback(tgt, false);
			}	
			glBindFramebuffer(GL_FRAMEBUFFER, 0);
		}
	}

/* use MRT to populate a possible "capture" FBO, 
 * the process_rendertarget function will make sure to not render the color
 * target (reading + writing to the same texture is undefined behavior), 
 * although it can be "circumvented" with instancing */
	if (current_context->stdoutp.color){
		GLenum buffers[] = {GL_BACK, GL_COLOR_ATTACHMENT0};
		arcan_debug_pumpglwarnings("mrt");
//	glBindFramebuffer(GL_FRAMEBUFFER, current_context->stdoutp.fbo);
//	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, 
//	GL_TEXTURE_2D, current_context->stdoutp.color->vstore->glid, 0);
//	glDrawBuffers(2, buffers);
		process_rendertarget(&current_context->stdoutp, lerp);
		arcan_debug_pumpglwarnings("mrtpost");
		glBindFramebuffer(GL_FRAMEBUFFER, 0);

		if (current_context->stdoutp.readback != 0){
//			process_readback(&current_context->stdoutp, lerp);
		}
	}
	else
		process_rendertarget(&current_context->stdoutp, lerp);
}

unsigned arcan_video_refresh(float tofs, bool synch)
{
/* for less interactive / latency sensitive applications the delta > .. 
 * with vsync on, the delta > .. could be removed */
	long long int pre = arcan_timemillis();
		arcan_video_refresh_GL(tofs);
	long long int post = arcan_timemillis();

	if (synch)
		platform_video_bufferswap();

	return post - pre;
}

void arcan_video_default_scalemode(enum arcan_vimage_mode newmode)
{
	arcan_video_display.scalemode = newmode;
}

void arcan_video_default_texmode(enum arcan_vtex_mode modes, 
	enum arcan_vtex_mode modet)
{
	arcan_video_display.deftxs = modes == ARCAN_VTEX_REPEAT ? 
		GL_REPEAT : GL_CLAMP_TO_EDGE;
	arcan_video_display.deftxt = modet == ARCAN_VTEX_REPEAT ? 
		GL_REPEAT : GL_CLAMP_TO_EDGE;
}

arcan_errc arcan_video_screencoords(arcan_vobj_id id, vector* res)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		rv = ARCAN_OK;

/* get object properties taking inheritance etc. into account,
 * this will automatically re-use any possible cache */
		surface_properties dprops = empty_surface();
		arcan_resolve_vidprop(vobj, 0.0, &dprops);
		dprops.scale.x *= vobj->origw * 0.5;
		dprops.scale.y *= vobj->origh * 0.5;

/* transform and rotate the bounding coordinates into screen space */
		float omatr[16], imatr[16], dmatr[16];
		int view[4] = {0, 0, arcan_video_display.width, 
			arcan_video_display.height};

		if (vobj->valid_cache)
			memcpy(dmatr, vobj->prop_matr, sizeof(float) * 16);
		else {
			identity_matrix(imatr);
			matr_quatf(dprops.rotation.quaternion, omatr);
			translate_matrix(imatr, dprops.position.x + dprops.scale.x, 
				dprops.position.y + dprops.scale.y, 0.0);
			multiply_matrix(dmatr, imatr, omatr);
		}

		float p[4][3];

/* transform the four vertices of the quad to window */
		project_matrix(-dprops.scale.x, -dprops.scale.y, 0.0, dmatr,
		current_context->stdoutp.projection, view, &res[0].x,&res[0].y,&res[0].z);

		project_matrix( dprops.scale.x, -dprops.scale.y, 0.0, dmatr, 
		current_context->stdoutp.projection, view, &res[1].x,&res[1].y,&res[1].z);

		project_matrix( dprops.scale.x,  dprops.scale.y, 0.0, dmatr, 
		current_context->stdoutp.projection, view, &res[2].x,&res[2].y,&res[2].z);

		project_matrix(-dprops.scale.x,  dprops.scale.y, 0.0, dmatr, 
		current_context->stdoutp.projection, view, &res[3].x,&res[3].y,&res[3].z);

		res[0].y = arcan_video_display.height - res[0].y;
		res[1].y = arcan_video_display.height - res[1].y;
		res[2].y = arcan_video_display.height - res[2].y;
		res[3].y = arcan_video_display.height - res[3].y;	
	}

	return rv;
}

static inline int isign(int p1_x, int p1_y, 
	int p2_x, int p2_y, int p3_x, int p3_y)
{
	return (p1_x - p3_x) * (p2_y - p3_y) - (p2_x - p3_x) * (p1_y - p3_y);
}

static inline bool itri(int x, int y, int t[6])
{
	bool b1, b2, b3;

	b1 = isign(x, y, t[0], t[1], t[2], t[3]) < 0;
	b2 = isign(x, y, t[2], t[3], t[4], t[5]) < 0;
  b3 = isign(x, y, t[4], t[5], t[0], t[1]) < 0;

	return (b1 == b2) && (b2 == b3);
}

static inline bool easypick(arcan_vobject* vobj, unsigned int x, unsigned int y)
{
	return (x>=vobj->prop_cache.position.x && y >= vobj->prop_cache.position.y&& 
		x <= (vobj->prop_cache.position.x+(vobj->origw*vobj->prop_cache.scale.x))&&
		y <= (vobj->prop_cache.position.y+(vobj->origh*vobj->prop_cache.scale.y))
		);
}

bool arcan_video_hittest(arcan_vobj_id id, unsigned int x, unsigned int y)
{
	vector projv[4];
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (ARCAN_OK == arcan_video_screencoords(id, projv)){
		if (vobj->valid_cache && vobj->rotate_state == false)
			return easypick(vobj, x, y);

		if (vobj->rotate_state){
			int t1[] =
				{ projv[0].x, projv[0].y,
				  projv[1].x, projv[1].y,
				  projv[2].x, projv[2].y};
		
			int t2[] = 
				{ projv[2].x, projv[2].y, 
					projv[3].x, projv[3].y, 
					projv[0].x, projv[0].y };

			return itri(x, y, t1) || itri(x, y, t2);	
		}
		else
			return (x >= projv[0].x && y >= projv[0].y) &&
				(x <= projv[2].x && y <= projv[2].y);
	}

	return false;
}

/*
 * since hit/rhit might be called at high frequency
 * we need to limit the CPU impact here until
 * there's proper caching of resolve_ calls
 */
static bool obj_visible(arcan_vobject* vobj)
{
	bool visible = vobj->current.opa > EPSILON;
	
	while (visible && vobj->parent && (vobj->mask & MASK_OPACITY) > 0){
		visible = vobj->current.opa > EPSILON;
	vobj = vobj->parent;	
	}

	return visible;
}

unsigned int arcan_video_rpick(arcan_vobj_id* dst, 
	unsigned count, int x, int y)
{
	if (count == 0)
		return 0;

/* skip to last item, then scan backwards */
	arcan_vobject_litem* current = current_context->stdoutp.first;
	unsigned base = 0;

	while (current->next)
		current = current->next;

	while (current && base < count){
		arcan_vobject* vobj = current->elem;

		if (vobj->cellid && (vobj->mask & MASK_UNPICKABLE)== 0 && obj_visible(vobj)
			&& arcan_video_hittest(vobj->cellid, x, y)){
				dst[base++] = vobj->cellid;
		}

		current = current->previous;
	}

	return base;
}

unsigned arcan_video_pick(arcan_vobj_id* dst, 
	unsigned count, int x, int y)
{
	if (count == 0)
		return 0;

	arcan_vobject_litem* current = current_context->stdoutp.first;
	unsigned base = 0;

	while (current && base < count) {
		arcan_vobject* vobj = current->elem;
	
		if (vobj->cellid && !(vobj->mask & MASK_UNPICKABLE) &&	
			obj_visible(vobj) && arcan_video_hittest(vobj->cellid, x, y))
				dst[base++] = vobj->cellid;

		current = current->next;
	}

	return base;
}

img_cons arcan_video_dimensions(uint16_t w, uint16_t h)
{
	img_cons res = {w, h};
	return res;
}

/* the actual storage dimensions,
 * as these might concern "% 2" texture requirement */
img_cons arcan_video_storage_properties(arcan_vobj_id id)
{
	img_cons res = {.w = 0, .h = 0, .bpp = 0};
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		res.w = vobj->vstore->w;
		res.h = vobj->vstore->h;
		res.bpp = vobj->vstore->bpp;
	}

	return res;
}

/* image dimensions at load time, without
 * any transformations being applied */
surface_properties arcan_video_initial_properties(arcan_vobj_id id)
{
	surface_properties res = empty_surface();
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		res.scale.x = vobj->origw;
		res.scale.y = vobj->origh;
	}

	return res;
}

surface_properties arcan_video_resolve_properties(arcan_vobj_id id)
{
	surface_properties res = empty_surface();
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0) {
		arcan_resolve_vidprop(vobj, 0.0, &res);
		res.scale.x *= vobj->origw;
		res.scale.y *= vobj->origh;
	}

	return res;
}

surface_properties arcan_video_current_properties(arcan_vobj_id id)
{
	surface_properties rv = empty_surface();
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		rv = vobj->current;
		rv.scale.x *= vobj->origw;
		rv.scale.y *= vobj->origh;
	}

	return rv;
}

surface_properties arcan_video_properties_at(arcan_vobj_id id, unsigned ticks)
{
	if (ticks == 0)
		return arcan_video_current_properties(id);

	bool fullprocess = ticks == (unsigned int) -1;

	surface_properties rv = empty_surface();
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		rv = vobj->current;
/* if there's no transform defined, then the ticks will be the same */
		if (vobj->transform){
/* translate ticks from relative to absolute */
			if (!fullprocess)
				ticks += arcan_video_display.c_ticks;

/* check if there is a transform for each individual attribute, and find 
 * the one that defines a timeslot within the range of the desired value */
			surface_transform* current = vobj->transform;
			if (current->move.startt){
				while ( (current->move.endt < ticks || fullprocess) && current->next 
					&& current->next->move.startt)
					current = current->next;

				if (current->move.endt <= ticks)
					rv.position = current->move.endp;
				else if (current->move.startt == ticks)
					rv.position = current->move.startp;
				else{ /* need to interpolate */
					float fract = lerp_fract(current->move.startt, 
						current->move.endt, ticks);
					rv.position = lerp_vector(current->move.startp, 
						current->move.endp, fract);
				}
			}

			current = vobj->transform;
			if (current->scale.startt){
				while ( (current->scale.endt < ticks || fullprocess) && 
					current->next && current->next->scale.startt)
					current = current->next;

				if (current->scale.endt <= ticks)
					rv.scale = current->scale.endd;
				else if (current->scale.startt == ticks)
					rv.scale = current->scale.startd;
				else{
					float fract = lerp_fract(current->scale.startt, 
						current->scale.endt, ticks);
					rv.scale = lerp_vector(current->scale.startd, 
						current->scale.endd, fract);
				}
			}

			current = vobj->transform;
			if (current->blend.startt){
				while ( (current->blend.endt < ticks || fullprocess) && 
					current->next && current->next->blend.startt)
					current = current->next;

				if (current->blend.endt <= ticks)
					rv.opa = current->blend.endopa;
				else if (current->blend.startt == ticks)
					rv.opa = current->blend.startopa;
				else{
					float fract = lerp_fract(current->blend.startt, 
						current->blend.endt, ticks);
					rv.opa = lerp_val(current->blend.startopa, 
						current->blend.endopa, fract);
				}
			}

			current = vobj->transform;
			if (current->rotate.startt){
				while ( (current->rotate.endt < ticks || fullprocess) && 
					current->next && current->next->rotate.startt)
					current = current->next;

				if (current->rotate.endt <= ticks)
					rv.rotation = current->rotate.endo;
				else if (current->rotate.startt == ticks)
					rv.rotation = current->rotate.starto;
				else{
					float fract = lerp_fract(current->rotate.startt, 
						current->rotate.endt, ticks);
					rv.rotation.quaternion = interp_rotation(
						&current->rotate.starto.quaternion, 
						&current->rotate.endo.quaternion, fract, 
						current->rotate.interp);
				}
			}
		}

		rv.scale.x *= vobj->origw;
		rv.scale.y *= vobj->origh;
	}

	return rv;
}

void platform_video_prepare_external();
bool arcan_video_prepare_external()
{
/* There seems to be no decent, portable, way to minimize + suspend 
 * and when child terminates, maximize and be sure that OpenGL / SDL context 
 * data is restored respectively. Thus we destroy the surface,
 * and then rebuild / reupload all textures. */
	if (-1 == arcan_video_pushcontext())
		return false;

	arcan_event_deinit(arcan_event_defaultctx());
	platform_video_prepare_external();

	return true;
}

unsigned arcan_video_maxorder()
{
	arcan_vobject_litem* current = current_context->stdoutp.first;
	int order = 0;

	while (current){
		if (current->elem && current->elem->order > order)
			order = current->elem->order;

		current = current->next;
	}

	return order;
}

unsigned arcan_video_contextusage(unsigned* free)
{
	if (free){
		*free = 0;
		for (unsigned i = 1; i < current_context->vitem_limit-1; i++)
			if (current_context->vitems_pool[i].flags.in_use)
				(*free)++;
	}

	return current_context->vitem_limit-1;
}

void arcan_video_contextsize(unsigned newlim)
{
/* this change isn't allowed when the shrink/expand operation would
 * change persistent objects in the stack */
	if (newlim < arcan_video_display.default_vitemlim)
		for (unsigned i = 1; i < current_context->vitem_limit-1; i++)
			if (current_context->vitems_pool[i].flags.in_use &&
				current_context->vitems_pool[i].flags.persist)
				return;

	arcan_video_display.default_vitemlim = newlim;
}

extern void platform_video_restore_external();
void arcan_video_restore_external()
{
	platform_video_restore_external();
	arcan_event_init( arcan_event_defaultctx() );
	arcan_video_gldefault();
	arcan_shader_rebuild_all();
	arcan_video_popcontext();
}

extern void platform_video_shutdown();
void arcan_video_shutdown()
{
	arcan_vobject_litem* current = current_context->stdoutp.first;
	unsigned lastctxa, lastctxc = arcan_video_popcontext();

/* this will effectively make sure that all external launchers, 
 * frameservers etc. gets killed off */
	while ( lastctxc != (lastctxa = arcan_video_popcontext()) )
		lastctxc = lastctxa;

	arcan_shader_flush();
	deallocate_gl_context(current_context, true);
	arcan_video_reset_fontcache();
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	platform_video_shutdown();
}

int arcan_debug_pumpglwarnings(const char* src){
#ifdef _DEBUG
	GLenum errc = glGetError();
	if (errc != GL_NO_ERROR){
		arcan_warning("GLError detected (%s) GL error, code: %d\n", src, errc);
		return -1;
	}
#endif
	return 1;
}

arcan_errc arcan_video_tracetag(arcan_vobj_id id, const char*const message)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		if (vobj->tracetag)
			free(vobj->tracetag);

		vobj->tracetag = strdup(message);
		rv = ARCAN_OK;
	}

	return rv;
}
