/*
 * Copyright 2003-2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <signal.h>
#include <stddef.h>
#include <math.h>
#include <limits.h>
#include <assert.h>
#include <errno.h>
#include <stdalign.h>

#include <pthread.h>
#include <semaphore.h>

#define CLAMP(x, l, h) (((x) > (h)) ? (h) : (((x) < (l)) ? (l) : (x)))

#ifndef ASYNCH_CONCURRENT_THREADS
#define ASYNCH_CONCURRENT_THREADS 12
#endif

#include PLATFORM_HEADER

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_ttf.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_frameserver.h"
#include "arcan_renderfun.h"
#include "arcan_videoint.h"
#include "arcan_3dbase.h"
#include "arcan_img.h"

#ifndef offsetof
#define offsetof(type, member) ((size_t)((char*)&(*(type*)0).member\
 - (char*)&(*(type*)0)))
#endif

#ifndef ARCAN_VIDEO_DEFAULT_MIPMAP_STATE
#define ARCAN_VIDEO_DEFAULT_MIPMAP_STATE true
#endif

long long ARCAN_VIDEO_WORLDID = -1;
static surface_properties empty_surface();
static sem_handle asynchsynch;

/* these match arcan_vinterpolant enum */
static arcan_interp_3d_function lut_interp_3d[] = {
	interp_3d_linear,
	interp_3d_sine,
	interp_3d_expin,
	interp_3d_expout,
	interp_3d_expinout,
};

static arcan_interp_1d_function lut_interp_1d[] = {
	interp_1d_linear,
	interp_1d_sine,
	interp_1d_expin,
	interp_1d_expout,
	interp_1d_expinout
};

struct arcan_video_display arcan_video_display = {
	.conservative = false,
	.deftxs = ARCAN_VTEX_CLAMP, ARCAN_VTEX_CLAMP,
	.scalemode = ARCAN_VIMAGE_NOPOW2,
	.filtermode = ARCAN_VFILTER_BILINEAR,
	.suspended = false,
	.msasamples = 4,
	.c_ticks = 1,
	.default_vitemlim = 1024,
	.imageproc = IMAGEPROC_NORMAL,
	.mipmap = ARCAN_VIDEO_DEFAULT_MIPMAP_STATE,
	.dirty = 0,
	.cursor.w = 24,
	.cursor.h = 16
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
static arcan_errc update_zv(arcan_vobject* vobj, unsigned short newzv);
static void rebase_transform(struct surface_transform*, int64_t);
static size_t process_rendertarget(struct rendertarget*, float);
static arcan_vobject* new_vobject(arcan_vobj_id* id,
struct arcan_video_context* dctx);
static inline void build_modelview(float* dmatr,
	float* imatr, surface_properties* prop, arcan_vobject* src);
static inline void process_readback(struct rendertarget* tgt, float fract);
static inline void poll_readback(struct rendertarget* tgt);

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

void arcan_vint_drop_vstore(struct storage_info_t* s)
{
	assert(s->refcount);
	s->refcount--;

	if (s->refcount == 0){
		if (s->txmapped != TXSTATE_OFF && s->vinf.text.glid){
			agp_drop_vstore(s);

			if (s->vinf.text.raw){
				arcan_mem_free(s->vinf.text.raw);
				s->vinf.text.raw = NULL;
			}
		}

		arcan_mem_free(s);
	}
}

void arcan_video_default_texfilter(enum arcan_vfilter_mode mode)
{
	arcan_video_display.filtermode = mode;
}

void arcan_video_default_imageprocmode(enum arcan_imageproc_mode mode)
{
	arcan_video_display.imageproc = mode;
}

struct rendertarget* find_rendertarget(arcan_vobject* vobj)
{
	for (size_t i = 0; i < current_context->n_rtargets && vobj; i++)
		if (current_context->rtargets[i].color == vobj)
			return &current_context->rtargets[i];

	return NULL;
}

static void addchild(arcan_vobject* parent, arcan_vobject* child)
{
	arcan_vobject** slot = NULL;
	for (size_t i = 0; i < parent->childslots; i++){
		if (parent->children[i] == NULL){
		 slot = &parent->children[i];
			break;
		}
	}

/* grow and set element */
	if (!slot){
		arcan_vobject** news = arcan_alloc_mem(
			(parent->childslots + 8) * sizeof(void*),
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL
		);

		if (parent->children){
			memcpy(news, parent->children, parent->childslots * sizeof(void*));
			arcan_mem_free(parent->children);
		}

		parent->children = news;
		for (size_t i = 0; i < 8; i++)
			parent->children[parent->childslots + i] = NULL;

		slot = &parent->children[parent->childslots];
		parent->childslots += 8;
	}

	if (FL_TEST(child, FL_CLONE))
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
	FLAG_DIRTY(vobj);

	if (!vobj->valid_cache)
		return;

	vobj->valid_cache = false;

	for (size_t i = 0; i < vobj->childslots; i++)
		if (vobj->children[i])
			invalidate_cache(vobj->children[i]);
}

static void dropchild(arcan_vobject* parent, arcan_vobject* child)
{
	for (size_t i = 0; i < parent->childslots; i++){
		if (parent->children[i] == child){
			parent->children[i] = NULL;
			if (FL_TEST(child, FL_CLONE))
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
	for (size_t i = 1; i < context->vitem_limit; i++) {
		if (FL_TEST(&(context->vitems_pool[i]), FL_INUSE)){
			arcan_vobject* current = &(context->vitems_pool[i]);

/* before doing any modification, wait for any async load calls to finish(!),
 * question is IF this should invalidate or not */
			if (current->feed.state.tag == ARCAN_TAG_ASYNCIMGLD ||
				current->feed.state.tag == ARCAN_TAG_ASYNCIMGRD)
				arcan_video_pushasynch(i);

/* for persistant objects, deleteobject will only be "effective" if we're at
 * the stack layer where the object was created */
			if (del)
				arcan_video_deleteobject(i);

/* only non-persistant objects will have their GL objects removed immediately */
			else if (!FL_TEST(current, FL_PRSIST))
				agp_null_vstore(current->vstore);
		}
	}

/* pool is dynamically sized and size is set on layer push */
	if (del){
		arcan_mem_free(context->vitems_pool);
		context->vitems_pool = NULL;
	}
}

static inline void step_active_frame(arcan_vobject* vobj)
{
	if (!vobj->frameset)
		return;

	size_t sz = (FL_TEST(vobj, FL_CLONE) ? vobj->parent->frameset->n_frames :
		vobj->frameset->n_frames);

	vobj->frameset->index = (vobj->frameset->index + 1) % sz;
	vobj->owner->transfc++;

	FLAG_DIRTY(vobj);
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
		context->vitems_pool = arcan_alloc_mem(
			sizeof(struct arcan_vobject) * context->vitem_limit,
				ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	}
	else for (size_t i = 1; i < context->vitem_limit; i++)
		if (FL_TEST(&(context->vitems_pool[i]), FL_INUSE)){
			arcan_vobject* current = &context->vitems_pool[i];
			surface_transform* ctrans = current->transform;

			if (FL_TEST(current, FL_PRSIST))
				continue;

			if (FL_TEST(current, FL_CLONE))
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
					arcan_mem_free(current->vstore->vinf.text.source);
				arcan_video_getimage(fname, current,
					arcan_video_dimensions(current->origw, current->origh), false);
				arcan_mem_free(fname);
			}
			else
				if (current->vstore->txmapped != TXSTATE_OFF)
					agp_update_vstore(current->vstore, true);

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

static void rebase_transform(struct surface_transform* current, int64_t ofs)
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

static void push_transfer_persists(
	struct arcan_video_context* src,
	struct arcan_video_context* dst)
{
	for (size_t i = 1; i < src->vitem_limit - 1; i++){
		arcan_vobject* srcobj = &src->vitems_pool[i];
		arcan_vobject* dstobj = &dst->vitems_pool[i];

		if (!FL_TEST(srcobj, FL_INUSE | FL_PRSIST))
			continue;

		detach_fromtarget(&src->stdoutp, srcobj);
		memcpy(dstobj, srcobj, sizeof(arcan_vobject));
		dst->nalive++; /* fake allocate */
		dstobj->parent = &dst->world; /* don't cross- reference worlds */
		attach_object(&dst->stdoutp, dstobj);
		trace("vcontext_stack_push() : transfer-attach: %s\n", srcobj->tracetag);
	}
}

/*
 * if an object exists in src, is flagged persist,
 * and a similar (shadow) object is flagged persist in dst,
 * update the state in dst with src and detach/remove from src.
 */
static void pop_transfer_persists(
	struct arcan_video_context* src,
	struct arcan_video_context* dst)
{
	for (size_t i = 1; i < src->vitem_limit - 1; i++){
		arcan_vobject* srcobj = &src->vitems_pool[i];
		arcan_vobject* dstobj = &dst->vitems_pool[i];

		if (!
			(FL_TEST(srcobj, FL_INUSE | FL_PRSIST) &&
			 FL_TEST(dstobj, FL_INUSE | FL_PRSIST))
		)
			continue;

		arcan_vobject* parent = dstobj->parent;

		detach_fromtarget(&src->stdoutp, srcobj);
		src->nalive--;

		memcpy(dstobj, srcobj, sizeof(arcan_vobject));
		attach_object(&dst->stdoutp, dstobj);
		dstobj->parent = parent;
		memset(srcobj, '\0', sizeof(arcan_vobject));
	}
}

void arcan_vint_drawrt(struct storage_info_t* vs, int x, int y, int w, int h)
{
	_Alignas(16) float imatr[16];
	identity_matrix(imatr);
	arcan_shader_activate(agp_default_shader(BASIC_2D));

	agp_activate_vstore(vs);
	arcan_shader_envv(MODELVIEW_MATR, imatr, sizeof(float)*16);
	arcan_shader_envv(PROJECTION_MATR,
		arcan_video_display.window_projection, sizeof(float)*16);

	agp_blendstate(BLEND_NONE);
	agp_draw_vobj(0, 0, x + w, y + h,
		arcan_video_display.mirror_txcos, NULL);

	agp_deactivate_vstore(vs);
}

void arcan_vint_drawcursor(bool erase)
{
	if (!arcan_video_display.cursor.vstore)
		return;

	float txmatr[8];
	float* txcos = arcan_video_display.default_txcos;

/*
 * flip internal cursor position to last drawn cursor position
 */
	if (!erase){
		arcan_video_display.cursor.ox = arcan_video_display.cursor.x;
		arcan_video_display.cursor.oy = arcan_video_display.cursor.y;
	}

	int x1 = arcan_video_display.cursor.ox;
	int y1 = arcan_video_display.cursor.oy;
	int x2 = x1 + arcan_video_display.cursor.w;
	int y2 = y1 + arcan_video_display.cursor.h;

	struct monitor_mode mode = platform_video_dimensions();

	if (erase){
		float s1 = (float)x1 / mode.width;
		float s2 = (float)x2 / mode.height;
		float t1 = 1.0 - ((float)y1 / mode.width);
		float t2 = 1.0 - ((float)y2 / mode.height);

		txmatr[0] = s1;
		txmatr[1] = t1;
		txmatr[2] = s2;
		txmatr[3] = t1;
		txmatr[4] = s2;
		txmatr[5] = t2;
	 	txmatr[6] = s1;
		txmatr[7] = t2;

		txcos = txmatr;

		agp_activate_vstore(current_context->world.vstore);
	}
	else{
		agp_activate_vstore(arcan_video_display.cursor.vstore);
	}

	float opa = 1.0;
	arcan_shader_activate(agp_default_shader(BASIC_2D));
	arcan_shader_envv(OBJ_OPACITY, &opa, sizeof(float));
	agp_draw_vobj(x1, y1, x2, y2, txcos, NULL);

	agp_deactivate_vstore( erase ? current_context->world.vstore :
		arcan_video_display.cursor.vstore);
}

signed arcan_video_pushcontext()
{
	arcan_vobject empty_vobj = {
		.current = {
			.position = {0},
			.opa = 1.0,
			.scale = {.x = 1.0, .y = 1.0, .z = 1.0},
			.rotation.quaternion = default_quat
		},
/* we transfer the vstore over as that will be used as a
 * container for the main display FBO */
		.vstore = current_context->world.vstore
	};

	if (vcontext_ind + 1 == CONTEXT_STACK_LIMIT)
		return -1;

	current_context->last_tickstamp = arcan_video_display.c_ticks;

/* copy everything then manually reset some fields to defaults */
	memcpy(&vcontext_stack[ ++vcontext_ind ], current_context,
		sizeof(struct arcan_video_context));
	deallocate_gl_context(current_context, false);

	current_context = &vcontext_stack[ vcontext_ind ];
	current_context->stdoutp.first = NULL;
	current_context->vitem_ofs = 1;

	current_context->world = empty_vobj;
	current_context->stdoutp.color = &current_context->world;
	current_context->vitem_limit = arcan_video_display.default_vitemlim;
	current_context->vitems_pool = arcan_alloc_mem(
		sizeof(struct arcan_vobject) * current_context->vitem_limit,
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
	);

	current_context->rtargets[0].first = NULL;

/* propagate persistent flagged objects upwards */
	push_transfer_persists(
		&vcontext_stack[ vcontext_ind - 1], current_context);
	FLAG_DIRTY(NULL);

	return arcan_video_nfreecontexts();
}

void arcan_video_recoverexternal(bool pop, int* saved,
	int* truncated, recovery_adoptfun adopt, void* tag)
{
	unsigned lastctxa, lastctxc;
	size_t n_ext = 0;

	*saved = 0;
	*truncated = 0;

/* pass, count contexts. */
	for (size_t i = 0; i <= vcontext_ind; i++){
		struct arcan_video_context* ctx = &vcontext_stack[i];

		for (size_t j = 1; j < ctx->vitem_limit; j++)
			if (FL_TEST(&(ctx->vitems_pool[j]), FL_INUSE)){
				if (ctx->vitems_pool[j].feed.state.tag == ARCAN_TAG_FRAMESERV)
					n_ext++;
			}
	}

	struct {
		struct storage_info_t* gl_store;
		char* tracetag;
		arcan_vfunc_cb ffunc;
		vfunc_state state;
		int origw, origh;
		int zv;
	} alim[n_ext+1];

	arcan_aobj_id audbuf[n_ext+1];

	if (n_ext == 0)
		goto clense;

/* clamp number of salvaged objects, save space for WORLDID
 * and if necessary, increase the size for new contexts */
	if (n_ext >= VITEM_CONTEXT_LIMIT - 1)
		n_ext = VITEM_CONTEXT_LIMIT - 1;

	if (n_ext > arcan_video_display.default_vitemlim)
		arcan_video_display.default_vitemlim = n_ext + 1;

/* pass 2, salvage remains */
	int s_ofs = 0;

	for (size_t i = 0; i <= vcontext_ind; i++){
		struct arcan_video_context* ctx = &vcontext_stack[i];
		for (size_t j = 1; j < ctx->vitem_limit; j++)
			if (FL_TEST(&ctx->vitems_pool[j], FL_INUSE) &&
				ctx->vitems_pool[j].feed.state.tag == ARCAN_TAG_FRAMESERV){
				arcan_vobject* cobj = &ctx->vitems_pool[j];

/* only liberate objects if we have enough
 * space left to store, the rest will be lost */
				if (s_ofs < n_ext){
					alim[s_ofs].state = cobj->feed.state;
					alim[s_ofs].ffunc = cobj->feed.ffunc;
					alim[s_ofs].gl_store = cobj->vstore;
					alim[s_ofs].origw = cobj->origw;
					alim[s_ofs].origh = cobj->origh;
					alim[s_ofs].zv = i + 1;
					alim[s_ofs].tracetag = cobj->tracetag ? strdup(cobj->tracetag) : NULL;

					arcan_frameserver* fsrv = cobj->feed.state.ptr;
					audbuf[s_ofs] = fsrv->aid;

/* disassociate with cobj (when killed in pop, free wont be called),
 * and increase refcount on storage (won't be killed in pop) */
					cobj->vstore->refcount++;
					cobj->feed.state.tag = ARCAN_TAG_NONE;
					cobj->feed.ffunc = NULL;
					cobj->feed.state.ptr = NULL;

					s_ofs++;
				}
				else
					(*truncated)++;
			}
	}

/* pop them all, will also create a new fresh
 * context with at least enough space */
clense:
	if (pop){
		lastctxc = arcan_video_popcontext();

		while ( lastctxc != (lastctxa = arcan_video_popcontext()))
			lastctxc = lastctxa;
	}

	if (n_ext == 0)
		return;

/* pass 3, setup new world. */
	for (size_t i = 0; i < s_ofs; i++){
		arcan_vobj_id did;
		arcan_vobject* vobj = new_vobject(&did, current_context);
		vobj->vstore = alim[i].gl_store;
		vobj->feed.state = alim[i].state;
		vobj->feed.ffunc = alim[i].ffunc;
		vobj->origw = alim[i].origw;
		vobj->origh = alim[i].origh;
		vobj->order = alim[i].zv;
		vobj->blendmode = BLEND_NORMAL;
		vobj->tracetag = alim[i].tracetag;

		arcan_video_attachobject(did);

		(*saved)++;
		if (adopt)
			adopt(did, tag);
	}

	arcan_audio_purge(audbuf, s_ofs);
	arcan_event_purge();
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
	av_pixel* dstbuf;
	size_t dsz;

	FLAG_DIRTY(NULL);

	arcan_vint_refresh(0.0, &dsz);

	bool ss = arcan_video_screenshot((void*)&dstbuf, &dsz) == ARCAN_OK;
	int rv = arcan_video_popcontext();

	if (ss){
		struct monitor_mode mode = platform_video_dimensions();
		int w = mode.width;
		int h = mode.height;

		img_cons cons = {.w = w, .h = h, .bpp = GL_PIXEL_BPP};
		*dst = arcan_video_rawobject(dstbuf, cons, w, h, 1);

		if (*dst == ARCAN_EID){
			arcan_mem_free(dstbuf);
		}
		else{
/* flip y by using texture coordinates */
			arcan_vobject* vobj = arcan_video_getobject(*dst);
			vobj->txcos = arcan_alloc_mem(sizeof(float) * 8,
				ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);

			generate_mirror_mapping(vobj->txcos, 1.0, 1.0);
		}
	}

	return rv;
}

signed arcan_video_extpushcontext(arcan_vobj_id* dst)
{
	av_pixel* dstbuf;
	size_t dsz;

	FLAG_DIRTY(NULL);
	arcan_vint_refresh(0.0, &dsz);
	bool ss = arcan_video_screenshot(&dstbuf, &dsz) == ARCAN_OK;
	int rv = arcan_video_pushcontext();

	if (ss){
		struct monitor_mode mode = platform_video_dimensions();
		int w = mode.width;
		int h = mode.height;

		img_cons cons = {.w = w, .h = h, .bpp = GL_PIXEL_BPP};
		*dst = arcan_video_rawobject(dstbuf, cons, w, h, 1);

		if (*dst == ARCAN_EID)
			arcan_mem_free(dstbuf);
		else
		{
			arcan_vobject* vobj = arcan_video_getobject(*dst);
			vobj->txcos = arcan_alloc_mem(sizeof(float) * 8,
				ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);

			generate_mirror_mapping(vobj->txcos, 1.0, 1.0);
		}
	}

	return rv;
}

unsigned arcan_video_popcontext()
{
/* propagate persistent flagged objects downwards */
	if (vcontext_ind > 0)
		pop_transfer_persists(
			current_context, &vcontext_stack[vcontext_ind-1]);

	deallocate_gl_context(current_context, true);

	if (vcontext_ind > 0){
		vcontext_ind--;
		current_context = &vcontext_stack[ vcontext_ind ];
	}

	reallocate_gl_context(current_context);
	FLAG_DIRTY(NULL);

	return (CONTEXT_STACK_LIMIT - 1) - vcontext_ind;
}

static inline surface_properties empty_surface()
{
	surface_properties res  = {
		.rotation.quaternion = default_quat
	};
	return res;
}

arcan_vobj_id arcan_video_allocid(bool* status, struct arcan_video_context* ctx)
{
	unsigned i = ctx->vitem_ofs, c = ctx->vitem_limit;
	*status = false;

	while (c--){
		if (i == 0) /* 0 is protected */
			i = 1;

		if (!FL_TEST(&ctx->vitems_pool[i], FL_INUSE)){
			*status = true;
			ctx->nalive++;
			FL_SET(&ctx->vitems_pool[i], FL_INUSE);
			ctx->vitem_ofs = (ctx->vitem_ofs + 1) >= ctx->vitem_limit ? 1 : i + 1;
			return i;
		}

		i = (i + 1) % (ctx->vitem_limit - 1);
	}

	return ARCAN_EID;
}

arcan_errc arcan_video_resampleobject(arcan_vobj_id vid,
	int neww, int newh, arcan_shader_id shid)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->vstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/* allocate a temporary storage object,
 * a temporary transfer object,
 * and a temporary rendertarget */
	size_t new_sz = neww * newh * GL_PIXEL_BPP;
	av_pixel* dstbuf = arcan_alloc_mem(new_sz,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

	if (!dstbuf)
		return ARCAN_ERRC_OUT_OF_SPACE;

	arcan_vobj_id xfer = arcan_video_nullobject(neww, newh, 0);
	if (xfer == ARCAN_EID){
		arcan_mem_free(dstbuf);
		return ARCAN_ERRC_OUT_OF_SPACE;
	}
/* dstbuf is now managed by the glstore in xfer */

	arcan_video_shareglstore(vid, xfer);
	arcan_video_objectopacity(xfer, 1.0, 0);
	arcan_video_setprogram(xfer, shid);

	img_cons cons = {.w = neww, .h = newh, .bpp = GL_PIXEL_BPP};
	arcan_vobj_id dst = arcan_video_rawobject(dstbuf, cons, neww, newh, 1);

	if (dst == ARCAN_EID){
		arcan_video_deleteobject(xfer);
		arcan_mem_free(dstbuf);
		return ARCAN_ERRC_OUT_OF_SPACE;
	}

/* set up a rendertarget and a proxy transfer object */
	arcan_errc rts = arcan_video_setuprendertarget(
		dst, 0, true, RENDERTARGET_COLOR);

	if (rts != ARCAN_OK){
		arcan_video_deleteobject(dst);
		arcan_video_deleteobject(xfer);
		return rts;
	}

	vobj->origw = neww;
	vobj->origh = newh;

/* draw, transfer storages and cleanup, xfer will
 * be deleted implicitly when dst cascades */
	arcan_video_attachtorendertarget(dst, xfer, true);
	arcan_video_forceupdate(dst);
	arcan_video_shareglstore(dst, vid);
	arcan_video_deleteobject(dst);
	arcan_video_objectscale(vid, 1.0, 1.0, 1.0, 0);

/* readback so we can survive push/pop and restore external */
	struct storage_info_t* dstore = vobj->vstore;
	agp_readback_synchronous(dstore);

	return ARCAN_OK;
}

arcan_errc arcan_video_mipmapset(arcan_vobj_id vid, bool enable)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->vstore->txmapped != TXSTATE_TEX2D ||
		!vobj->vstore->vinf.text.raw)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/*
 * For both disable and enable, we need to recreate the
 * gl_store and possibly remove the old one.
 */
	void* newbuf = arcan_alloc_fillmem(vobj->vstore->vinf.text.raw,
		vobj->vstore->vinf.text.s_raw,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL,
		ARCAN_MEMALIGN_PAGE
	);

	if (!newbuf)
		return ARCAN_ERRC_OUT_OF_SPACE;

	arcan_vint_drop_vstore(vobj->vstore);
	if (enable)
		vobj->vstore->filtermode |= ARCAN_VFILTER_MIPMAP;
	else
		vobj->vstore->filtermode &= ~ARCAN_VFILTER_MIPMAP;

	vobj->vstore->vinf.text.raw = newbuf;
	agp_update_vstore(vobj->vstore, true);

	return ARCAN_OK;
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

static void populate_vstore(struct storage_info_t** vs)
{
	*vs = arcan_alloc_mem(
		sizeof(struct storage_info_t),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO,
		ARCAN_MEMALIGN_NATURAL
	);

	(*vs)->txmapped   = TXSTATE_TEX2D;
	(*vs)->txu        = arcan_video_display.deftxs;
	(*vs)->txv        = arcan_video_display.deftxt;
	(*vs)->scale      = arcan_video_display.scalemode;
	(*vs)->imageproc  = arcan_video_display.imageproc;
	(*vs)->filtermode = arcan_video_display.filtermode;
	if (arcan_video_display.mipmap)
		(*vs)->filtermode |= ARCAN_VFILTER_MIPMAP;

	(*vs)->refcount   = 1;
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

	if (!status)
		return NULL;

	rv = dctx->vitems_pool + fid;
	rv->order = 0;
	populate_vstore(&rv->vstore);

	rv->childslots = 0;
	rv->children = NULL;

	rv->valid_cache = false;

	rv->blendmode = BLEND_NORMAL;
	rv->clip = ARCAN_CLIP_OFF;

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

	rv->parent = &current_context->world;
	rv->mask = MASK_ORIENTATION | MASK_OPACITY | MASK_POSITION
		| MASK_FRAMESET | MASK_LIVING;

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
		FL_TEST(&current_context->vitems_pool[id], FL_INUSE))
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

/* (4.) mark as something easy to find in dumps */
	torem->elem = (arcan_vobject*) 0xfeedface;

/* cleanup torem */
	arcan_mem_free(torem);

	if (src->owner == dst)
		src->owner = NULL;

	if (dst->color && dst != &current_context->stdoutp){
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

	FLAG_DIRTY(NULL);
	return true;
}

static void attach_object(struct rendertarget* dst, arcan_vobject* src)
{
	arcan_vobject_litem* new_litem =
		arcan_alloc_mem(sizeof *new_litem,
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);

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

	FLAG_DIRTY(src);
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
		FLAG_DIRTY(src);

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

	surface_transform* res = arcan_alloc_mem( sizeof(surface_transform),
		ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);

	surface_transform* current = res;

	while (base)
	{
		memcpy(current, base, sizeof(surface_transform));

		if (base->next)
			current->next = arcan_alloc_mem( sizeof(surface_transform),
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);
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
		if (val)
			FL_SET(vobj, FL_ORDOFS);
		else
			FL_CLEAR(vobj, FL_ORDOFS);
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

	if (vobj && id > FL_INUSE) {
		vobj->mask = mask;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_linkobjs(arcan_vobj_id srcid, arcan_vobj_id parentid,
	enum arcan_transform_mask mask, enum parent_anchor anchorp)
{
	arcan_vobject* src = arcan_video_getobject(srcid);
	arcan_vobject* dst = arcan_video_getobject(parentid);

/* link to self always means link to world */
	if (srcid == parentid || parentid == 0)
		dst = &current_context->world;

	if (!src || !dst)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* can't relink clone to another object, or link an object to a clone */
	if (FL_TEST(src, FL_CLONE) || FL_TEST(src, FL_PRSIST) ||
		(FL_TEST(dst, FL_CLONE) || FL_TEST(dst, FL_PRSIST)))
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

	arcan_vobject* current = dst;

/* traverse destination and make sure we don't create cycles */
	while (current) {
		if (current->parent == src)
			return ARCAN_ERRC_CLONE_NOT_PERMITTED;
		else
			current = current->parent;
	}

/* already linked to dst? do nothing */
		if (src->parent == dst)
			return ARCAN_OK;

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

	if (FL_TEST(src, FL_ORDOFS))
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

	src->p_anchor = anchorp;
	src->mask = mask;
	FLAG_DIRTY(NULL);

	return ARCAN_OK;
}

arcan_errc arcan_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, bool conservative, const char* caption)
{
	static bool firstinit = true;

/* might be called multiple times so.. */
	if (firstinit){
		if (-1 == arcan_sem_init(&asynchsynch, ASYNCH_CONCURRENT_THREADS)){
			arcan_warning("video_init couldn't create synchronization handle\n");
		}

		generate_basic_mapping(arcan_video_display.default_txcos, 1.0, 1.0);
		generate_mirror_mapping(arcan_video_display.mirror_txcos, 1.0, 1.0);
		firstinit = false;
	}

	if (!platform_video_init(width, height, bpp, fs, frames, caption)){
		arcan_warning("platform_video_init() failed.\n");
		return ARCAN_ERRC_BADVMODE;
	}

	agp_init();

	arcan_video_display.in_video = true;
	arcan_video_display.conservative = conservative;

	TTF_Init();
	current_context->world.current.scale.x = 1.0;
	current_context->world.current.scale.y = 1.0;
	current_context->vitem_limit = arcan_video_display.default_vitemlim;
	current_context->vitems_pool = arcan_alloc_mem(
		sizeof(struct arcan_vobject) * current_context->vitem_limit,
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	struct monitor_mode mode = platform_video_dimensions();
	arcan_video_resize_canvas(mode.width, mode.height);

	identity_matrix(current_context->stdoutp.base);
/*
 * By default, expected video output display matches canvas 1:1,
 * canvas can be explicitly resized and these two matrices will still
 * make the output correct. For multiple- dynamic monitor configurations,
 * things get hairy; the video platform will be expected to
 * map rendertargets / videoobjects to output displays.
 */
	FLAG_DIRTY(NULL);
	return ARCAN_OK;
}

arcan_errc arcan_video_resize_canvas(size_t neww, size_t newh)
{
	struct monitor_mode mode = platform_video_dimensions();

	if (!current_context->world.vstore){
		populate_vstore(&current_context->world.vstore);
		current_context->world.vstore->filtermode &= ~ARCAN_VFILTER_MIPMAP;
		agp_empty_vstore(current_context->world.vstore, neww, newh);
		current_context->stdoutp.color = &current_context->world;
		current_context->stdoutp.art = agp_setup_rendertarget(
			current_context->world.vstore,
			RENDERTARGET_COLOR_DEPTH_STENCIL
		);
	}
	else
		agp_resize_rendertarget(current_context->stdoutp.art, neww, newh);

	build_orthographic_matrix(arcan_video_display.window_projection, 0,
		mode.phy_width, mode.phy_height, 0, 0, 1);

	build_orthographic_matrix(arcan_video_display.default_projection, 0,
		mode.width, mode.height, 0, 0, 1);

	memcpy(current_context->stdoutp.projection,
		arcan_video_display.default_projection, sizeof(float) * 16);

	FLAG_DIRTY(NULL);
	arcan_video_forceupdate(ARCAN_VIDEO_WORLDID);

	return ARCAN_OK;
}

static uint16_t nexthigher(uint16_t k)
{
	k--;
	for (size_t i=1; i < sizeof(uint16_t) * 8; i = i * 2)
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
	arcan_sem_wait(asynchsynch);
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;

	av_pixel* imgbuf = NULL;
	int inw, inh;

/* try- open */
	data_source inres = arcan_open_resource(fname);
	if (inres.fd == BADFD){
		arcan_sem_post(asynchsynch);
		return ARCAN_ERRC_BAD_RESOURCE;
	}

/* mmap (preferred) or buffer (mmap not working /
 * useful due to alignment) */
	map_region inmem = arcan_map_resource(&inres, false);
	if (inmem.ptr == NULL){
		arcan_sem_post(asynchsynch);
		arcan_release_resource(&inres);
		return ARCAN_ERRC_BAD_RESOURCE;
	}

	struct arcan_img_meta meta = {0};
	rv = arcan_img_decode(fname, inmem.ptr, inmem.sz, (char**)&imgbuf, &inw, &inh,
		&meta, dst->vstore->imageproc == IMAGEPROC_FLIPH, malloc);

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
			neww = desm == ARCAN_VIMAGE_SCALEPOW2 ? nexthigher(forced.w) : forced.w;
			newh = desm == ARCAN_VIMAGE_SCALEPOW2 ? nexthigher(forced.h) : forced.h;
			dst->origw = forced.w;
			dst->origh = forced.h;

			dstframe->vinf.text.s_raw = neww * newh * GL_PIXEL_BPP;
			dstframe->vinf.text.raw   = arcan_alloc_mem(dstframe->vinf.text.s_raw,
				ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

			arcan_renderfun_stretchblit((char*)imgbuf, inw, inh,
				(uint32_t*) dstframe->vinf.text.raw,
				neww, newh, dst->vstore->imageproc == IMAGEPROC_FLIPH);
			arcan_mem_free(imgbuf);
		}
		else if (desm == ARCAN_VIMAGE_SCALEPOW2){
			neww = nexthigher(neww);
			newh = nexthigher(newh);

			if (neww != inw || newh != inh){
				dstframe->vinf.text.s_raw = neww * newh * GL_PIXEL_BPP;
				dstframe->vinf.text.raw = arcan_alloc_mem(dstframe->vinf.text.s_raw,
					ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

				arcan_renderfun_stretchblit((char*)imgbuf, inw, inh,
					(uint32_t*)dstframe->vinf.text.raw,
					neww, newh, dst->vstore->imageproc == IMAGEPROC_FLIPH);
				arcan_mem_free(imgbuf);
			}
			else {
				dstframe->vinf.text.s_raw = neww * newh * GL_PIXEL_BPP;
				dstframe->vinf.text.raw = imgbuf;
			}
		}
		else {
			neww = inw;
			newh = inh;
			dstframe->vinf.text.raw = imgbuf;
			dstframe->vinf.text.s_raw = inw * inh * GL_PIXEL_BPP;
		}

		dst->vstore->w = neww;
		dst->vstore->h = newh;

/*
 * for the asynch case, we need to do this separately as we're in a different
 * thread and forcibly assigning the glcontext to another thread is expensive */

push_comp:
		if (!asynchsrc && dst->vstore->txmapped != TXSTATE_OFF)
			agp_update_vstore(dst->vstore, true);
	}

	arcan_sem_post(asynchsynch);
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

	if (!target || capacity == 0)
		return rv;

/* similar restrictions as with sharestore */
	if (target->vstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (FL_TEST(target, FL_CLONE) || FL_TEST(target, FL_PRSIST))
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

/* only permit framesets to grow */
	if (target->frameset){
		if (target->frameset->n_frames > capacity)
			return ARCAN_ERRC_UNACCEPTED_STATE;
	}
	else
		target->frameset = arcan_alloc_mem(sizeof(struct vobject_frameset),
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	target->frameset->n_frames = capacity;
	target->frameset->frames = arcan_alloc_mem(
			sizeof(struct storage_info_t) * capacity,
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
	);

	for (size_t i = 0; i < capacity; i++){
		target->frameset->frames[i] = target->vstore;
		target->vstore->refcount++;
	}

	target->frameset->mode = mode;

	return ARCAN_OK;
}

arcan_errc arcan_video_framecyclemode(arcan_vobj_id id, int mode)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->frameset)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	vobj->frameset->mctr = mode;
	vobj->frameset->ctr = mode;

	return ARCAN_OK;
}

void arcan_video_cursorpos(int newx, int newy, bool absolute)
{
	if (absolute){
		arcan_video_display.cursor.x = newx;
		arcan_video_display.cursor.y = newy;
	}
	else {
		arcan_video_display.cursor.x += newx;
		arcan_video_display.cursor.y += newy;
	}
}

void arcan_video_cursorsize(size_t w, size_t h)
{
	arcan_video_display.cursor.w = w;
	arcan_video_display.cursor.h = h;
}

void arcan_video_cursorstore(arcan_vobj_id src)
{
	if (arcan_video_display.cursor.vstore){
		arcan_vint_drop_vstore(arcan_video_display.cursor.vstore);
		arcan_video_display.cursor.vstore = NULL;
	}

	arcan_vobject* vobj = arcan_video_getobject(src);
	if (src == ARCAN_VIDEO_WORLDID || !vobj ||
		vobj->vstore->txmapped != TXSTATE_TEX2D)
		return;

/* texture coordinates here will always be restricted to 0..1, 0..1 */
	arcan_video_display.cursor.vstore = vobj->vstore;
	vobj->vstore->refcount++;
}

arcan_errc arcan_video_shareglstore(arcan_vobj_id sid, arcan_vobj_id did)
{
	arcan_vobject* src = arcan_video_getobject(sid);
	arcan_vobject* dst = arcan_video_getobject(did);

	if (!src || !dst || src == dst)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src->vstore->txmapped == TXSTATE_OFF ||
		src->vstore->vinf.text.glid == 0 ||
		FL_TEST(src, FL_PRSIST | FL_CLONE) ||
		FL_TEST(dst, FL_PRSIST | FL_CLONE)
	)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	arcan_vint_drop_vstore(dst->vstore);

	dst->vstore = src->vstore;
	dst->vstore->refcount++;

/*
 * customized texture coordinates unless we should use
 * defaults ...
 */
	if (src->txcos){
		if (!dst->txcos)
			dst->txcos = arcan_alloc_mem(8 * sizeof(float),
				ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);
			memcpy(dst->txcos, src->txcos, sizeof(float) * 8);
	}
	else if (dst->txcos){
		arcan_mem_free(dst->txcos);
		dst->txcos = NULL;
	}

	FLAG_DIRTY(dst);
	return ARCAN_OK;
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
	newvobj->program = agp_default_shader(COLOR_2D);
	arcan_video_attachobject(rv);

	return rv;
}

arcan_vobj_id arcan_video_nullobject(float origw,
	float origh, unsigned short zv)
{
	arcan_vobj_id rv =  arcan_video_solidcolor(origw, origh, 0, 0, 0, zv);

	if (rv != ARCAN_EID){
		arcan_vobject* vobj = arcan_video_getobject(rv);
		vobj->program = 0;
		arcan_video_attachobject(rv);
	}

	return rv;
}

arcan_vobj_id arcan_video_rawobject(av_pixel* buf,
	img_cons cons, float origw, float origh, unsigned short zv)
{
	arcan_vobj_id rv = ARCAN_EID;
	size_t bufs = cons.w * cons.h * cons.bpp;

	if (cons.bpp != GL_PIXEL_BPP)
		return ARCAN_EID;

	arcan_vobject* newvobj = arcan_video_newvobject(&rv);

	if (!newvobj)
		return ARCAN_EID;

	struct storage_info_t* ds = newvobj->vstore;

	ds->w   = cons.w;
	ds->h   = cons.h;
	ds->bpp = cons.bpp;
	ds->vinf.text.s_raw = bufs;
	ds->vinf.text.raw = buf;
	ds->txmapped = TXSTATE_TEX2D;

	newvobj->origw = origw;
	newvobj->origh = origh;
	newvobj->blendmode = BLEND_NORMAL;
	newvobj->order = zv;

	agp_update_vstore(newvobj->vstore, true);
	arcan_video_attachobject(rv);

	return rv;
}

arcan_errc arcan_video_attachtorendertarget(arcan_vobj_id did,
	arcan_vobj_id src, bool detach)
{
	if (src == ARCAN_VIDEO_WORLDID){
		arcan_warning("arcan_video_attachtorendertarget(), WORLDID attach"
			" not directly supported, use a null-surface with "
			"shared storage instead.");

		return ARCAN_ERRC_UNACCEPTED_STATE;
	}

/* don't allow to attach to self, that FBO behavior would be undefined
 * and don't allow persist attachments as the other object can go out of
 * scope */
	arcan_vobject* dstobj = arcan_video_getobject(did);
	arcan_vobject* srcobj = arcan_video_getobject(src);
	if (!dstobj || !srcobj || dstobj == srcobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (FL_TEST(dstobj, FL_PRSIST) || FL_TEST(srcobj, FL_PRSIST))
		return ARCAN_ERRC_UNACCEPTED_STATE;


/* linear search for rendertarget matching the destination id */
	for (size_t ind = 0; ind < current_context->n_rtargets; ind++){
		if (current_context->rtargets[ind].color == dstobj){
/* find whatever rendertarget we're already attached to, and detach */
			if (srcobj->owner && detach)
				detach_fromtarget(srcobj->owner, srcobj);

/* try and detach (most likely fail) to make sure that we don't get duplicates*/
			detach_fromtarget(&current_context->rtargets[ind], srcobj);
			attach_object(&current_context->rtargets[ind], srcobj);

			return ARCAN_OK;
		}
	}

	return ARCAN_ERRC_BAD_ARGUMENT;
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
	if (!rtgt)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	rtgt->readback = readback;
	rtgt->readcnt = abs(readback);
	return ARCAN_OK;
}

arcan_errc arcan_video_rendertarget_setnoclear(arcan_vobj_id did, bool value)
{
	struct rendertarget* rtgt;

	if (did == ARCAN_VIDEO_WORLDID)
		rtgt = &current_context->stdoutp;
	else {
		arcan_vobject* vobj = arcan_video_getobject(did);
		if (!vobj)
			return ARCAN_ERRC_NO_SUCH_OBJECT;

		rtgt = find_rendertarget(vobj);
	}

	if (!rtgt)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (value)
		FL_SET(rtgt, TGTFL_NOCLEAR);
	else
		FL_CLEAR(rtgt, TGTFL_NOCLEAR);

	return ARCAN_OK;
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

		FL_SET(dst, TGTFL_ALIVE);
		dst->color    = vobj;
		dst->camtag   = ARCAN_EID;
		dst->readback = readback;
		dst->art = agp_setup_rendertarget(vobj->vstore, format);

		vobj->extrefc.attachments++;
		trace("(setuprendertarget), (%d:%s) defined as rendertarget."
			"attachments: %d\n", vobj->cellid, video_tracetag(vobj),
			vobj->extrefc.attachments);

/* alter projection so the GL texture gets stored in the way
 * the images are rendered in normal mode, with 0,0 being upper left */
		build_orthographic_matrix(dst->projection, 0, vobj->origw, 0,
			vobj->origh, 0, 1);
		identity_matrix(dst->base);

		struct monitor_mode mode = platform_video_dimensions();
		if (scale){
			float xs = (float)vobj->vstore->w / (float)mode.width;
			float ys = (float)vobj->vstore->h / (float)mode.height;

/* since we may likely have a differently sized FBO, scale it */
			scale_matrix(dst->base, xs, ys, 1.0);
		}

		if (readback != 0){
			dst->readback     = readback;
			dst->readcnt      = abs(readback);
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

	if (!dstvobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!dstvobj->frameset)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	dstvobj->frameset->index = fid <
		(FL_TEST(dstvobj, FL_CLONE) ? dstvobj->parent->frameset->n_frames :
			dstvobj->frameset->n_frames) ? fid : 0;

	FLAG_DIRTY(dstvobj);
	return ARCAN_OK;
}

arcan_errc arcan_video_setasframe(arcan_vobj_id dst,
	arcan_vobj_id src, size_t fid)
{
	arcan_vobject* dstvobj = arcan_video_getobject(dst);
	arcan_vobject* srcvobj = arcan_video_getobject(src);

	if (!dstvobj || !srcvobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dstvobj->frameset == NULL || srcvobj->vstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (fid >= dstvobj->frameset->n_frames || FL_TEST(dstvobj, FL_CLONE))
		return ARCAN_ERRC_BAD_ARGUMENT;

	if (dstvobj->frameset->frames[fid] == srcvobj->vstore)
		return ARCAN_OK;

	arcan_vint_drop_vstore(dstvobj->frameset->frames[fid]);
	dstvobj->frameset->frames[fid] = srcvobj->vstore;
	dstvobj->frameset->frames[fid]->refcount++;

	return ARCAN_OK;
}

struct thread_loader_args {
	arcan_vobject* dst;
	pthread_t self;
	arcan_vobj_id dstid;
	char* fname;
	intptr_t tag;
	img_cons constraints;
	arcan_errc rc;
};

static void* thread_loader(void* in)
{
	struct thread_loader_args* largs = (struct thread_loader_args*) in;
	arcan_vobject* dst = largs->dst;
	largs->rc = arcan_video_getimage(largs->fname, dst, largs->constraints, true);
	dst->feed.state.tag = ARCAN_TAG_ASYNCIMGRD;
	return 0;
}

void arcan_video_joinasynch(arcan_vobject* img, bool emit, bool force)
{
	if (!force && img->feed.state.tag != ARCAN_TAG_ASYNCIMGRD){
		return;
	}

	struct thread_loader_args* args =
		(struct thread_loader_args*) img->feed.state.ptr;

	pthread_join(args->self, NULL);

	arcan_event loadev = {
		.category = EVENT_VIDEO,
		.data.video.data = args->tag,
		.data.video.source = args->dstid
	};

	if (args->rc == ARCAN_OK){
		loadev.kind = EVENT_VIDEO_ASYNCHIMAGE_LOADED;
		loadev.data.video.width = img->origw;
		loadev.data.video.height = img->origh;
	}
/* copy broken placeholder instead */
	else {
		img->origw = 32;
		img->origh = 32;
		img->vstore->vinf.text.s_raw = 32 * 32 * GL_PIXEL_BPP;
		img->vstore->vinf.text.raw = arcan_alloc_mem(img->vstore->vinf.text.s_raw,
			ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

		img->vstore->w = 32;
		img->vstore->h = 32;
		img->vstore->vinf.text.source = strdup(args->fname);
		img->vstore->filtermode = ARCAN_VFILTER_NONE;

		loadev.data.video.width = 32;
		loadev.data.video.height = 32;
		loadev.kind = EVENT_VIDEO_ASYNCHIMAGE_FAILED;
	}

	agp_update_vstore(img->vstore, true);

	if (emit)
		arcan_event_enqueue(arcan_event_defaultctx(), &loadev);

	arcan_mem_free(args->fname);
	arcan_mem_free(args);
	img->feed.state.ptr = NULL;
	img->feed.state.tag = ARCAN_TAG_IMAGE;
}

static arcan_vobj_id loadimage_asynch(const char* fname,
	img_cons constraints, intptr_t tag)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_vobject* dstobj = arcan_video_newvobject(&rv);
	if (!dstobj)
		return rv;

	struct thread_loader_args* args = arcan_alloc_mem(
		sizeof(struct thread_loader_args),
		ARCAN_MEM_THREADCTX, 0, ARCAN_MEMALIGN_NATURAL);

	args->dstid = rv;
	args->dst = dstobj;
	args->fname = strdup(fname);
	args->tag = tag;
	args->constraints = constraints;

	dstobj->feed.state.tag = ARCAN_TAG_ASYNCIMGLD;
	dstobj->feed.state.ptr = args;

	pthread_create(&args->self, NULL, thread_loader, (void*) args);

	return rv;
}

arcan_errc arcan_video_pushasynch(arcan_vobj_id source)
{
	arcan_vobject* vobj = arcan_video_getobject(source);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGLD ||
		vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGRD){
		/* protect us against premature invocation */
		arcan_video_joinasynch(vobj, false, true);
	}
	else
		return ARCAN_ERRC_UNACCEPTED_STATE;

	return ARCAN_OK;
}

static arcan_vobj_id loadimage(const char* fname, img_cons constraints,
	arcan_errc* errcode)
{
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
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (FL_TEST(vobj, FL_CLONE))
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

	vobj->feed.state = state;
	vobj->feed.ffunc = cb;

	return ARCAN_OK;
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

	if (!newvobj || !ffunc)
		return ARCAN_EID;

	struct storage_info_t* vstor = newvobj->vstore;
/* preset */
	newvobj->origw = constraints.w;
	newvobj->origh = constraints.h;
	newvobj->vstore->bpp = ncpt == 0 ? GL_PIXEL_BPP : ncpt;
	newvobj->vstore->filtermode &= ~ARCAN_VFILTER_MIPMAP;

	if (newvobj->vstore->scale == ARCAN_VIMAGE_NOPOW2){
		newvobj->vstore->w = constraints.w;
		newvobj->vstore->h = constraints.h;
	}
	else {
/* For feeds, we don't do the forced- rescale on
 * every frame, way too expensive, this behavior only
 * occurs if there's a custom set of texture coordinates already */
		newvobj->vstore->w = nexthigher(constraints.w);
		newvobj->vstore->h = nexthigher(constraints.h);
		float hx = (float)constraints.w / (float)newvobj->vstore->w;
		float hy = (float)constraints.h / (float)newvobj->vstore->h;
		if (newvobj->txcos)
			generate_basic_mapping(newvobj->txcos, hx, hy);
	}

/* allocate */
	vstor->vinf.text.s_raw = newvobj->vstore->w *
		newvobj->vstore->h * newvobj->vstore->bpp;
	vstor->vinf.text.raw = arcan_alloc_mem(vstor->vinf.text.s_raw,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

	newvobj->feed.ffunc = ffunc;
	agp_update_vstore(newvobj->vstore, true);

	return rv;
}

/* some targets like to change size dynamically (thanks for that),
 * thus, drop the allocated buffers, generate new one and tweak txcos */
arcan_errc arcan_video_resizefeed(arcan_vobj_id id, size_t w, size_t h)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (FL_TEST(vobj, FL_CLONE))
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

	if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGLD ||
		vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGRD)
		arcan_video_pushasynch(id);

/* rescale transformation chain */
	float fx = (float)vobj->origw / (float)w;
	float fy = (float)vobj->origh / (float)h;

/* "initial" base dimensions, important when dimensions
 * change for objects that have a shared storage elsewhere
 * but where scale differs. */
	vobj->origw = w;
	vobj->origh = h;
	rescale_origwh(vobj, fx, fy);

	vobj->vstore->vinf.text.s_raw = w * h * GL_PIXEL_BPP;
	agp_resize_vstore(vobj->vstore, w, h);

	return ARCAN_OK;
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

		if (state.tag == ARCAN_TAG_3DOBJ){
			FL_SET(vobj, FL_FULL3D);
			vobj->order *= -1;
		}

		arcan_video_attachobject(rv);
	}

	return rv;
}

arcan_errc arcan_video_scaletxcos(arcan_vobj_id id, float sfs, float sft)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj){
		if (!vobj->txcos)
			vobj->txcos = arcan_alloc_mem(8 * sizeof(float),
				ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);

		generate_basic_mapping(vobj->txcos, 1.0, 1.0);
		vobj->txcos[0] *= sfs;
		vobj->txcos[1] *= sft;
		vobj->txcos[2] *= sfs;
		vobj->txcos[3] *= sft;
		vobj->txcos[4] *= sfs;
		vobj->txcos[5] *= sft;
		vobj->txcos[6] *= sfs;
		vobj->txcos[7] *= sft;

		FLAG_DIRTY(vobj);
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
		FLAG_DIRTY(vobj);
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
	for (size_t i = 0; i < vobj->childslots; i++)
		if (vobj->children[i] && FL_TEST(vobj->children[i], FL_ORDOFS)){
			int distance = vobj->children[i]->order - oldv;
			update_zv(vobj->children[i], newzv + distance);
		}

	return ARCAN_OK;
}

/* change zval (see arcan_video_addobject) for a particular object.
 * return value is an error code */
arcan_errc arcan_video_setzv(arcan_vobj_id id, unsigned short newzv)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* calculate order relative to parent if that's toggled
 * clip to 16bit US and ignore if the parent is a 3dobj */
	if (FL_TEST(vobj, FL_ORDOFS)){
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

arcan_errc arcan_video_zaptransform(arcan_vobj_id id, float* dropped)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	surface_transform* current = vobj->transform;

	float count = 0;
	float ct = arcan_video_display.c_ticks;

	if (current){
		float max = current->move.endt;
		if (current->scale.endt > max)
			max = current->scale.endt;
		if (current->rotate.endt > max)
			max = current->rotate.endt;
		if (current->blend.endt > max)
			max = current->blend.endt;

		max /= ct;
		count += max;
	}
	while (current) {
		surface_transform* next = current->next;

		arcan_mem_free(current);
		current = next;
		count++;
	}

	if (dropped)
		*dropped = count;

	vobj->transform = NULL;

	FLAG_DIRTY(vobj);
	return ARCAN_OK;
}

arcan_errc arcan_video_tagtransform(arcan_vobj_id id,
	intptr_t tag, enum arcan_transform_mask mask)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if ((mask & ~MASK_TRANSFORMS) > 0)
		return ARCAN_ERRC_BAD_ARGUMENT;

	surface_transform* current = vobj->transform;

	while(current && mask > 0){
		if ((mask & MASK_POSITION) > 0){
			if (current->move.startt &&
			(!current->next || !current->next->move.startt)){
				mask &= ~MASK_POSITION;
				current->move.tag = tag;
			}
		}

		if ((mask & MASK_SCALE) > 0){
			if (current->scale.startt &&
			(!current->next || !current->next->scale.startt)){
				mask &= ~MASK_SCALE;
				current->scale.tag = tag;
			}
		}

		if ((mask & MASK_ORIENTATION) > 0){
			if (current->rotate.startt &&
			(!current->next || !current->next->rotate.startt)){
				mask &= ~MASK_ORIENTATION;
				current->rotate.tag = tag;
			}
		}

		if ((mask & MASK_OPACITY) > 0){
			if (current->blend.startt &&
			(!current->next || !current->next->blend.startt)){
				mask &= ~MASK_OPACITY;
				current->blend.tag = tag;
			}
		}

		current = current->next;
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_instanttransform(arcan_vobj_id id){
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_OK;

	surface_transform* current = vobj->transform;
	while (current){
		if (current->move.startt)
			vobj->current.position = current->move.endp;

		if (current->blend.startt)
			vobj->current.opa = current->blend.endopa;

		if (current->rotate.startt)
			vobj->current.rotation = current->rotate.endo;

		if (current->scale.startt)
			vobj->current.scale = current->scale.endd;

		surface_transform* tokill = current;
		current = current->next;
		arcan_mem_free(tokill);
	}

	vobj->transform = NULL;
	invalidate_cache(vobj);
	return ARCAN_OK;
}

arcan_errc arcan_video_objecttexmode(arcan_vobj_id id,
	enum arcan_vtex_mode modes, enum arcan_vtex_mode modet)
{
	arcan_vobject* src = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src){
		src->vstore->txu = modes;
		src->vstore->txv = modet;
		agp_update_vstore(src->vstore, false);
		FLAG_DIRTY(src);
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
		agp_update_vstore(src->vstore, false);
	}

	return rv;
}

arcan_errc arcan_video_transformcycle(arcan_vobj_id sid, bool flag)
{
	arcan_vobject* src = arcan_video_getobject(sid);
	if (!src)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (flag)
		FL_SET(src, FL_TCYCLE);
	else
		FL_CLEAR(src, FL_TCYCLE);

	return ARCAN_OK;
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
	arcan_vobject* src, (* dst);

	src = arcan_video_getobject(sid);
	dst = arcan_video_getobject(did);

	if (!src || !dst || src == dst)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* remove what's happening in destination, move
 * pointers from source to dest and done. */
	memcpy(&dst->current, &src->current, sizeof(surface_properties));

	arcan_video_zaptransform(did, NULL);
	dst->transform = dup_chain(src->transform);
	update_zv(dst, src->order);

	invalidate_cache(dst);

/* in order to NOT break resizefeed etc. this copy actually
 * requires a modification of the transformation
 * chain, as scale is relative origw? */
	dst->origw = src->origw;
	dst->origh = src->origh;

	return ARCAN_OK;
}

arcan_errc arcan_video_transfertransform(arcan_vobj_id sid, arcan_vobj_id did)
{
	arcan_errc rv = arcan_video_copytransform(sid, did);

	if (rv == ARCAN_OK){
		arcan_vobject* src = arcan_video_getobject(sid);
		arcan_video_zaptransform(sid, NULL);
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
	agp_drop_rendertarget(dst->art);
	dst->art = NULL;

/* create a temporary copy of all the elements in the rendertarget */
	arcan_vobject_litem* current = dst->first;
	size_t pool_sz = (dst->color->extrefc.attachments) * sizeof(arcan_vobject*);
	pool = arcan_alloc_mem(pool_sz, ARCAN_MEM_VSTRUCT, ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_NATURAL);

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
		arcan_mem_free(last);
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
	for (size_t i = 0; i < cascade_c; i++)
		if (pool[i] && FL_TEST(pool[i], FL_INUSE) &&
		(pool[i]->owner == dst || FL_TEST(pool[i]->owner, TGTFL_ALIVE))){
			pool[i]->owner = NULL;

/* cascade or push to stdout as new owner */
			if ((pool[i]->mask & MASK_LIVING) > 0 ||FL_TEST(pool[i], FL_CLONE))
				arcan_video_deleteobject(pool[i]->cellid);
			else
				attach_object(&current_context->stdoutp, pool[i]);
		}

	arcan_mem_free(pool);
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
 *
 * an object can belong to either a parent object (ultimately, WORLD),
 * one or more rendertargets, at the same time,
 * and these deletions should also sustain a full context wipe
 */
arcan_errc arcan_video_deleteobject(arcan_vobj_id id)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	int cascade_c = 0;

/* some objects can't be deleted */
	if (!vobj || id == ARCAN_VIDEO_WORLDID || id == ARCAN_EID)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* when a persist is defined in a lower layer, we know that the lowest layer
 * is the last on to have the persistflag) */
	if (FL_TEST(vobj, FL_PRSIST) &&
		(vcontext_ind > 0 && FL_TEST(
			&vcontext_stack[vcontext_ind - 1].vitems_pool[
			vobj->cellid], FL_PRSIST))
	)
		return ARCAN_ERRC_UNACCEPTED_STATE;

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

	if (vobj->frameset){
		if (!FL_TEST(vobj, FL_CLONE)){
			for (size_t i = 0; i < vobj->frameset->n_frames; i++)
				arcan_vint_drop_vstore(vobj->frameset->frames[i]);

			arcan_mem_free(vobj->frameset->frames);
			vobj->frameset->frames = NULL;
		}

		arcan_mem_free(vobj->frameset);
		vobj->frameset = NULL;
	}

/* populate a pool of cascade deletions, none of this applies to
 * instances as they can only really be part of a rendertarget,
 * and those are handled separately */
	unsigned sum = FL_TEST(vobj, FL_CLONE) ? 0 :
		vobj->extrefc.links + vobj->extrefc.instances;

	arcan_vobject* pool[ (sum + 1) ];

	if (sum)
		memset(pool, 0, sizeof(pool));

/* drop all children, add those that should be deleted to the pool */
		for (size_t i = 0; i < vobj->childslots; i++){
			arcan_vobject* cur = vobj->children[i];
			if (!cur)
				continue;

			if (FL_TEST(cur, FL_CLONE) || (cur->mask & MASK_LIVING) > 0)
				pool[cascade_c++] = cur;

			dropchild(vobj, cur);
		}

		arcan_mem_free(vobj->children);
		vobj->childslots = 0;

	current_context->nalive--;

/* time to drop all associated resources */
	arcan_video_zaptransform(id, NULL);
	arcan_mem_free(vobj->txcos);

/* full- object specific clean-up */
	if (!FL_TEST(vobj, FL_CLONE)){
		if (vobj->feed.ffunc){
			vobj->feed.ffunc(FFUNC_DESTROY, 0, 0, 0, 0, 0, vobj->feed.state);

			vobj->feed.state.ptr = NULL;
			vobj->feed.ffunc = NULL;
			vobj->feed.state.tag = ARCAN_TAG_NONE;
		}

/* synchronize with the threadloader so we don't get a race */
		if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGLD){
			arcan_video_pushasynch(id);
		}

/* video storage, will take care of refcounting in case of
 * shared storage etc. */
		arcan_vint_drop_vstore( vobj->vstore );
		vobj->vstore = NULL;
	}

	if (vobj->extrefc.attachments|vobj->extrefc.links | vobj->extrefc.instances){
		arcan_warning("[BUG] Broken reference counters for expiring objects, "
			"tracetag? (%s)\n", vobj->tracetag ? vobj->tracetag : "(NO TAG)");
#ifdef _DEBUG
		abort();
#endif
	}

	arcan_mem_free(vobj->tracetag);

/* lots of default values are assumed to be 0, so reset the
 * entire object to be sure. will help leak detectors as well */
	memset(vobj, 0, sizeof(arcan_vobject));

	for (size_t i = 0; i < cascade_c; i++){
		if (!pool[i])
			continue;

		trace("(deleteobject) cascade pool entry (%d), %d:%s\n", i, pool[i]->cellid,
			pool[i]->tracetag ? pool[i]->tracetag : "(NO TAG)");

		if (FL_TEST(pool[i], FL_INUSE))
			arcan_video_deleteobject(pool[i]->cellid);
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_override_mapping(arcan_vobj_id id, float* newmapping)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && id > 0) {
		if (vobj->txcos)
			arcan_mem_free(vobj->txcos);

		vobj->txcos = arcan_alloc_fillmem(newmapping,
			sizeof(float) * 8, ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_retrieve_mapping(arcan_vobj_id id, float* dst)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && dst && id > 0) {
		float* sptr = vobj->txcos ?
			vobj->txcos : arcan_video_display.default_txcos;
		memcpy(dst, sptr, sizeof(float) * 8);
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

	for (size_t i = 0; i < vobj->childslots; i++){
		if (vobj->children[i]){
			if (ofs > 0)
				ofs--;
			else
				return vobj->children[i]->cellid;
		}
	}

	return rv;
}

static bool recsweep(arcan_vobject* base, arcan_vobject* match, int limit)
{
	if (base == NULL || (limit != -1 && limit-- <= 0))
		return false;

	if (base == match)
		return true;

	for (size_t i = 0; i < base->childslots; i++)
		if (recsweep(base->children[i], match, limit))
			return true;

	return false;
}

bool arcan_video_isdescendant(arcan_vobj_id vid,
	arcan_vobj_id parent, int limit)
{
	arcan_vobject* base = arcan_video_getobject(parent);
	arcan_vobject* match = arcan_video_getobject(vid);

	if (base== NULL || match == NULL)
		return false;

	return recsweep(base, match, limit);
}

arcan_errc arcan_video_objectrotate(arcan_vobj_id id,
	float ang, arcan_tickv time)
{
	return arcan_video_objectrotate3d(id, ang, 0.0, 0.0, time);
}

arcan_errc arcan_video_objectrotate3d(arcan_vobj_id id,
	float roll, float pitch, float yaw, arcan_tickv tv)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	invalidate_cache(vobj);

/* clear chains for rotate attribute previous rotate objects */
	if (tv == 0) {
		swipe_chain(vobj->transform, offsetof(surface_transform, rotate),
			sizeof(struct transf_rotate));
		vobj->current.rotation.roll  = roll;
		vobj->current.rotation.pitch = pitch;
		vobj->current.rotation.yaw   = yaw;
		vobj->current.rotation.quaternion = build_quat_taitbryan(roll,pitch,yaw);

		return ARCAN_OK;
	}

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
			base = last->next = arcan_alloc_mem(sizeof(surface_transform),
							ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		else
			base = last = arcan_alloc_mem(sizeof(surface_transform),
				ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
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
	vobj->owner->transfc++;

	base->rotate.interp = (abs(bv.roll - roll) > 180.0 ||
		abs(bv.pitch - pitch) > 180.0 || abs(bv.yaw - yaw) > 180.0) ?
		nlerp_quat180 : nlerp_quat360;

	return ARCAN_OK;
}

arcan_errc arcan_video_origoshift(arcan_vobj_id id,
	float sx, float sy, float sz)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	invalidate_cache(vobj);
	FL_SET(vobj, FL_ORDOFS);
	vobj->origo_ofs.x = sx;
	vobj->origo_ofs.y = sy;
	vobj->origo_ofs.z = sz;

	return ARCAN_OK;
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
					base = last->next =
						arcan_alloc_mem(sizeof(surface_transform), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
				else
					base = last =
						arcan_alloc_mem(sizeof(surface_transform), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
			}

			if (!vobj->transform)
				vobj->transform = base;

			vobj->owner->transfc++;
			base->blend.startt = last->blend.endt < arcan_video_display.c_ticks ?
				arcan_video_display.c_ticks : last->blend.endt;
			base->blend.endt = base->blend.startt + tv;
			base->blend.startopa = bv;
			base->blend.endopa = opa + EPSILON;
			base->blend.interp = ARCAN_VINTER_LINEAR;
		}
	}

	return rv;
}

arcan_errc arcan_video_blendinterp(arcan_vobj_id id, enum arcan_vinterp inter)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	surface_transform* base = vobj->transform;

	while (base && base->blend.startt &&
		base->next && base->next->blend.startt)
			base = base->next;

	assert(base);
	base->blend.interp = inter;

	return ARCAN_OK;
}

arcan_errc arcan_video_scaleinterp(arcan_vobj_id id, enum arcan_vinterp inter)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	surface_transform* base = vobj->transform;

	while (base && base->scale.startt &&
		base->next && base->next->scale.startt)
			base = base->next;

	assert(base);
	base->scale.interp = inter;

	return ARCAN_OK;
}

arcan_errc arcan_video_moveinterp(arcan_vobj_id id, enum arcan_vinterp inter)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	surface_transform* base = vobj->transform;

	while (base && base->move.startt &&
		base->next && base->next->move.startt)
			base = base->next;

	assert(base);
	base->move.interp = inter;

	return ARCAN_OK;
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
					base = last->next =
						arcan_alloc_mem(sizeof(surface_transform), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
				else
					base = last =
						arcan_alloc_mem(sizeof(surface_transform), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
 			}

			point newp = {newx, newy, newz};

			if (!vobj->transform)
				vobj->transform = base;

			base->move.startt = last->move.endt < arcan_video_display.c_ticks ?
				arcan_video_display.c_ticks : last->move.endt;
			base->move.endt   = base->move.startt + tv;
			base->move.interp = ARCAN_VINTER_LINEAR;
			base->move.startp = bwp;
			base->move.endp   = newp;
			vobj->owner->transfc++;
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
					base = last->next = arcan_alloc_mem(sizeof(surface_transform),
							ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
				else
					base = last = arcan_alloc_mem(sizeof(surface_transform),
							ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
			}

			if (!vobj->transform)
				vobj->transform = base;

			base->scale.startt = last->scale.endt < arcan_video_display.c_ticks ?
				arcan_video_display.c_ticks : last->scale.endt;
			base->scale.endt = base->scale.startt + tv;
			base->scale.interp = ARCAN_VINTER_LINEAR;
			base->scale.startd = bs;
			base->scale.endd.x = wf;
			base->scale.endd.y = hf;
			base->scale.endd.z = df;
			vobj->owner->transfc++;
		}
	}

	return rv;
}

static void emit_transform_event(arcan_vobj_id src,
	enum arcan_transform_mask slot, intptr_t tag)
{
	arcan_event tagev = {
		.category = EVENT_VIDEO,
		.kind = EVENT_VIDEO_CHAIN_OVER,
		.data.video.data = tag,
		.data.video.source = src,
		.data.video.slot = slot
	};

	arcan_event_enqueue(arcan_event_defaultctx(), &tagev);
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
	if (!(work->blend.startt | work->scale.startt |
		work->move.startt | work->rotate.startt )){

		arcan_mem_free(work);
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
		FLAG_DIRTY(vobj);
		vobj->program = shid;
		rv = ARCAN_OK;
	}

	return rv;
}

static inline float lerp_fract(float startt, float endt, float ts)
{
	float rv = (EPSILON + (ts - startt)) / (endt - startt);
	rv = rv > 1.0 ? 1.0 : rv;
	return rv;
}

static int update_object(arcan_vobject* ci, unsigned long long stamp)
{
	int upd = 0;

/* update parent if this has not already been updated this cycle */
	if (ci->last_updated < stamp &&
		ci->parent && ci->parent != &current_context->world &&
		ci->parent->last_updated != stamp){
		upd += update_object(ci->parent, stamp);
	}

	ci->last_updated = stamp;

	if (!ci->transform)
		return upd;

	if (ci->transform->blend.startt) {
		upd++;
		float fract = lerp_fract(ci->transform->blend.startt,
			ci->transform->blend.endt, stamp);

		ci->current.opa = lut_interp_1d[ci->transform->blend.interp](
			ci->transform->blend.startopa,
			ci->transform->blend.endopa, fract
		);

		if (fract > 1.0-EPSILON) {
			ci->current.opa = ci->transform->blend.endopa;

			if (FL_TEST(ci, FL_TCYCLE)){
				arcan_video_objectopacity(ci->cellid, ci->transform->blend.endopa,
					ci->transform->blend.endt - ci->transform->blend.startt);
				if (ci->transform->blend.interp > 0)
					arcan_video_blendinterp(ci->cellid, ci->transform->blend.interp);
			}

			if (ci->transform->blend.tag)
				emit_transform_event(ci->cellid,
					MASK_OPACITY, ci->transform->blend.tag);

			compact_transformation(ci,
				offsetof(surface_transform, blend),
				sizeof(struct transf_blend));
		}
	}

	if (ci->transform && ci->transform->move.startt) {
		upd++;
		float fract = lerp_fract(ci->transform->move.startt,
			ci->transform->move.endt, stamp);
		ci->current.position = lut_interp_3d[ci->transform->move.interp](
				ci->transform->move.startp,
				ci->transform->move.endp, fract
			);

		if (fract > 1.0-EPSILON) {
			ci->current.position = ci->transform->move.endp;

			if (FL_TEST(ci, FL_TCYCLE)){
				arcan_video_objectmove(ci->cellid,
					 ci->transform->move.endp.x,
					 ci->transform->move.endp.y,
					 ci->transform->move.endp.z,
					 ci->transform->move.endt - ci->transform->move.startt);

				if (ci->transform->move.interp > 0)
					arcan_video_moveinterp(ci->cellid, ci->transform->move.interp);
			}

			if (ci->transform->move.tag)
				emit_transform_event(ci->cellid,
					MASK_POSITION, ci->transform->move.tag);

			compact_transformation(ci,
				offsetof(surface_transform, move),
				sizeof(struct transf_move));
		}
	}

	if (ci->transform && ci->transform->scale.startt) {
		upd++;
		float fract = lerp_fract(ci->transform->scale.startt,
			ci->transform->scale.endt, stamp);
		ci->current.scale = lut_interp_3d[ci->transform->scale.interp](
			ci->transform->scale.startd,
			ci->transform->scale.endd, fract
		);

		if (fract > 1.0-EPSILON) {
			ci->current.scale = ci->transform->scale.endd;

			if (FL_TEST(ci, FL_TCYCLE)){
				arcan_video_objectscale(ci->cellid, ci->transform->scale.endd.x,
					ci->transform->scale.endd.y,
					ci->transform->scale.endd.z,
					ci->transform->scale.endt - ci->transform->scale.startt);

				if (ci->transform->scale.interp > 0)
					arcan_video_scaleinterp(ci->cellid, ci->transform->scale.interp);
			}

			if (ci->transform->scale.tag)
				emit_transform_event(ci->cellid, MASK_SCALE, ci->transform->scale.tag);

			compact_transformation(ci,
				offsetof(surface_transform, scale),
				sizeof(struct transf_scale));
		}
	}

	if (ci->transform && ci->transform->rotate.startt) {
		upd++;
		float fract = lerp_fract(ci->transform->rotate.startt,
			ci->transform->rotate.endt, stamp);

/* close enough */
		if (fract > 1.0-EPSILON) {
			ci->current.rotation = ci->transform->rotate.endo;
			if (FL_TEST(ci, FL_TCYCLE))
				arcan_video_objectrotate3d(ci->cellid,
					ci->transform->rotate.endo.roll,
					ci->transform->rotate.endo.pitch,
					ci->transform->rotate.endo.yaw,
					ci->transform->rotate.endt - ci->transform->rotate.startt);

			if (ci->transform->rotate.tag)
				emit_transform_event(ci->cellid,
					MASK_ORIENTATION, ci->transform->rotate.tag);

			compact_transformation(ci,
				offsetof(surface_transform, rotate),
				sizeof(struct transf_rotate));
		}
		else
			ci->current.rotation.quaternion =
				ci->transform->rotate.interp(
					ci->transform->rotate.starto.quaternion,
					ci->transform->rotate.endo.quaternion, fract
				);
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
static int tick_rendertarget(struct rendertarget* tgt)
{
	tgt->transfc = 0;

	arcan_vobject_litem* current = tgt->first;

	while (current){
		arcan_vobject* elem = current->elem;

		arcan_video_joinasynch(elem, true, false);

		if (elem->last_updated != arcan_video_display.c_ticks)
			tgt->transfc += update_object(elem, arcan_video_display.c_ticks);

		if (elem->feed.ffunc && !FL_TEST(elem, FL_CLONE))
			elem->feed.ffunc(FFUNC_TICK, 0, 0, 0, 0, 0, elem->feed.state);

/* mode > 0, cycle every 'n' ticks */
		if (elem->frameset && elem->frameset->mctr != 0){
			elem->frameset->ctr--;
			if (elem->frameset->ctr == 0){
				step_active_frame(elem);
				elem->frameset->ctr = abs( elem->frameset->mctr );
			}
		}

		if ((elem->mask & MASK_LIVING) > 0)
			expire_object(elem);

		current = current->next;
	}

	return tgt->transfc;
}

unsigned arcan_video_tick(unsigned steps, unsigned* njobs)
{
	if (steps == 0)
		return 0;

	unsigned now = arcan_frametime();
	uint32_t tsd = arcan_video_display.c_ticks;

#ifdef SHADER_TIME_PERIOD
	tsd = tsd % SHADER_TIME_PERIOD;
#endif

	do {
		arcan_video_display.dirty +=
			update_object(&current_context->world, arcan_video_display.c_ticks);

		arcan_video_display.dirty +=
			arcan_shader_envv(TIMESTAMP_D, &tsd, sizeof(uint32_t));

		for (size_t i = 0; i < current_context->n_rtargets; i++)
			arcan_video_display.dirty +=
				tick_rendertarget(&current_context->rtargets[i]);

		arcan_video_display.dirty +=
			tick_rendertarget(&current_context->stdoutp);

/*
 * we don't want c_ticks running too high (the tick is monotonic, but not
 * continous) as lots of float operations are relying on this as well,
 * this will cause transformations that are scheduled across the boundary
 * to behave oddly until reset. A fix would be to rebase if that is a problem.
 */
		arcan_video_display.c_ticks =
			(arcan_video_display.c_ticks + 1) % (INT32_MAX / 3);

		steps = steps - 1;
	} while (steps);

	return arcan_frametime() - now;
}

arcan_errc arcan_video_setclip(arcan_vobj_id id, enum arcan_clipmode mode)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	vobj->clip = mode;

	return ARCAN_OK;
}

arcan_vobj_id arcan_video_cloneobject(arcan_vobj_id parent)
{
	if (parent == ARCAN_EID || parent == ARCAN_VIDEO_WORLDID)
		return ARCAN_EID;

	arcan_vobject* pobj = arcan_video_getobject(parent);
	arcan_vobj_id rv = ARCAN_EID;

	if (pobj == NULL || FL_TEST(pobj, FL_PRSIST))
		return rv;

	while (FL_TEST(pobj, FL_CLONE))
		pobj = pobj->parent;

	bool status;
	rv = arcan_video_allocid(&status, current_context);

	if (status){
		arcan_vobject* nobj = arcan_video_getobject(rv);

/* use parent values as template */
		FL_SET(nobj, FL_CLONE);
		nobj->blendmode     = pobj->blendmode;
		nobj->origw         = pobj->origw;
		nobj->origh         = pobj->origh;
		nobj->order         = pobj->order;
		nobj->cellid        = rv;

/* for this time, we inherit the parent frameset
 * (though one cannot be set exclusively) */
		if (pobj->frameset){
			nobj->frameset = arcan_alloc_mem(sizeof(struct vobject_frameset),
				ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

			nobj->frameset->index = pobj->frameset->index;
			nobj->frameset->mode = pobj->frameset->mode;
			nobj->frameset->ctr = pobj->frameset->ctr;
			nobj->frameset->mctr = pobj->frameset->mctr;
		}

/* don't alter refcount for vstore */
		nobj->vstore        = pobj->vstore;
		nobj->current.scale = pobj->current.scale;

		nobj->current.rotation.quaternion = default_quat;
		nobj->program = pobj->program;

		if (pobj->txcos){
			nobj->txcos = arcan_alloc_fillmem(pobj->txcos,
				sizeof(float)*8, ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);
		}
		else
			nobj->txcos = NULL;

		addchild(pobj, nobj);
		trace("(clone) new instance of (%d:%s) with ID: %d, total: %d\n",
			parent, video_tracetag(pobj), nobj->cellid,
			nobj->parent->extrefc.instances);
		arcan_video_attachobject(rv);
	}

	return rv;
}

arcan_errc arcan_video_persistobject(arcan_vobj_id id)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!FL_TEST(vobj, FL_CLONE) &&
		!vobj->frameset &&
		vobj->vstore->refcount == 1 &&
		vobj->parent == &current_context->world){
		FL_SET(vobj, FL_PRSIST);

		return ARCAN_OK;
	}
	else
		return ARCAN_ERRC_UNACCEPTED_STATE;
}

bool arcan_video_visible(arcan_vobj_id id)
{
	bool rv = false;
	arcan_vobject* vobj= arcan_video_getobject(id);

	if (vobj && id > 0)
		return vobj->current.opa > EPSILON;

	return rv;
}

/* take sprops, apply them to the coordinates in vobj with proper
 * masking (or force to ignore mask), store the results in dprops */
static void apply(arcan_vobject* vobj, surface_properties* dprops,
	surface_properties* sprops, float lerp, bool force)
{
	*dprops = vobj->current;

	if (vobj->transform){
		surface_transform* tf = vobj->transform;
		unsigned ct = arcan_video_display.c_ticks;

		if (tf->move.startt)
			dprops->position = lut_interp_3d[tf->move.interp](
				tf->move.startp,
				tf->move.endp,
				lerp_fract(tf->move.startt, tf->move.endt, (float)ct + lerp)
			);

		if (tf->scale.startt)
			dprops->scale = lut_interp_3d[tf->scale.interp](
				tf->scale.startd,
				tf->scale.endd,
				lerp_fract(tf->scale.startt, tf->scale.endt, (float)ct + lerp)
			);

		if (tf->blend.startt)
			dprops->opa = lut_interp_1d[tf->blend.interp](
				tf->blend.startopa,
				tf->blend.endopa,
				lerp_fract(tf->blend.startt, tf->blend.endt, (float)ct + lerp)
			);

		if (tf->rotate.startt){
			dprops->rotation.quaternion = tf->rotate.interp(
				tf->rotate.starto.quaternion, tf->rotate.endo.quaternion,
				lerp_fract(tf->rotate.startt, tf->rotate.endt,
					(float)ct + lerp)
			);

			vector ang = angle_quat(dprops->rotation.quaternion);
			dprops->rotation.roll  = ang.x;
			dprops->rotation.pitch = ang.y;
			dprops->rotation.yaw   = ang.z;
		}

		if (!sprops)
			return;
	}

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
		apply(vobj, props, &dprop, lerp, false);
		switch(vobj->p_anchor){
		case ANCHORP_UR:
			props->position.x += vobj->parent->origw * vobj->parent->current.scale.x;
		break;
		case ANCHORP_LR:
			props->position.y += vobj->parent->origh * vobj->parent->current.scale.y;
			props->position.x += vobj->parent->origw * vobj->parent->current.scale.x;
		break;
		case ANCHORP_LL:
			props->position.y += vobj->parent->origh * vobj->parent->current.scale.y;
		break;
		case ANCHORP_C:
			props->position.y += (vobj->parent->origh *
				vobj->parent->current.scale.y) / 2.0;
			props->position.x += (vobj->parent->origw *
				vobj->parent->current.scale.x) / 2.0;
		case ANCHORP_UL:
		default:
		break;
		}
	}
	else
		apply(vobj, props, &current_context->world.current, lerp, true);

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

static void calc_cp_area(arcan_vobject* vobj, point* ul, point* lr)
{
	surface_properties cur;
	arcan_resolve_vidprop(vobj, 0.0, &cur);

	ul->x = cur.position.x < ul->x ? cur.position.x : ul->x;
	ul->y = cur.position.y < ul->y ? cur.position.y : ul->y;

	float t1 = (cur.position.x + cur.scale.x * vobj->origw);
	float t2 = (cur.position.y + cur.scale.y * vobj->origh);
	lr->x = cur.position.x > t1 ? cur.position.x : t1;
	lr->y = cur.position.y > t2 ? cur.position.y : t2;

	if (vobj->parent && vobj->parent != &current_context->world)
		calc_cp_area(vobj->parent, ul, lr);
}

static inline void build_modelview(float* dmatr,
	float* imatr, surface_properties* prop, arcan_vobject* src)
{
	float _Alignas(16) omatr[16];
 	float _Alignas(16) tmatr[16];

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

	point oofs = src->origo_ofs;

/* rotate around user-defined point rather than own center */
	if (oofs.x > EPSILON || oofs.y > EPSILON){
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

static inline float time_ratio(arcan_tickv start, arcan_tickv stop)
{
	return start > 0 ? (float)(arcan_video_display.c_ticks - start) /
		(float)(stop - start) : 1.0;
}

static inline void setup_surf(struct rendertarget* dst,
	surface_properties* prop, arcan_vobject* src, float** mv)
{
	static float _Alignas(16) dmatr[16];

	if (src->feed.state.tag == ARCAN_TAG_ASYNCIMGLD)
		return;

/* currently, we only cache the primary rendertarget */
	if (src->valid_cache && dst == src->owner){
		prop->scale.x *= src->origw * 0.5f;
		prop->scale.y *= src->origh * 0.5f;
		prop->position.x += prop->scale.x;
		prop->position.y += prop->scale.y;
		*mv = src->prop_matr;
	}
	else {
		build_modelview(dmatr, dst->base, prop, src);
		*mv = dmatr;
	}

	arcan_shader_envv(OBJ_OPACITY, &prop->opa, sizeof(float));

	float sz_i[2] = {src->origw, src->origh};
	arcan_shader_envv(SIZE_INPUT, sz_i, sizeof(float)*2);

	float sz_o[2] = {prop->scale.x, prop->scale.y};
	arcan_shader_envv(SIZE_OUTPUT, sz_o, sizeof(float)*2);

	float sz_s[2] = {src->vstore->w, src->vstore->h};
	arcan_shader_envv(SIZE_STORAGE, sz_s, sizeof(float)*2);

	if (src->transform){
		struct surface_transform* trans = src->transform;
		float ev = time_ratio(trans->move.startt, trans->move.endt);
		arcan_shader_envv(TRANS_MOVE, &ev, sizeof(float));

		ev = time_ratio(trans->rotate.startt, trans->rotate.endt);
		arcan_shader_envv(TRANS_ROTATE, &ev, sizeof(float));

		ev = time_ratio(trans->scale.startt, trans->scale.endt);
		arcan_shader_envv(TRANS_SCALE, &ev, sizeof(float));
	}
	else {
		float ev = 1.0;
		arcan_shader_envv(TRANS_MOVE, &ev, sizeof(float));
		arcan_shader_envv(TRANS_ROTATE, &ev, sizeof(float));
		arcan_shader_envv(TRANS_SCALE, &ev, sizeof(float));
	}
}

static inline void draw_colorsurf(struct rendertarget* dst,
	surface_properties prop, arcan_vobject* src, float r, float g, float b)
{
	float cval[3] = {r, g, b};
/* having to do = NULL here to avoid warnings is a prime example where
 * gcc is just terrible */
	float* mvm = NULL;

	setup_surf(dst, &prop, src, &mvm);
	arcan_shader_forceunif("obj_col", shdrvec3, (void*) &cval, false);
	agp_draw_vobj(-prop.scale.x,
		-prop.scale.y, prop.scale.x,
		prop.scale.y, NULL, mvm);
}

static inline void draw_texsurf(struct rendertarget* dst,
	surface_properties prop, arcan_vobject* src, float* txcos)
{
	float* mvm = NULL;
	setup_surf(dst, &prop, src, &mvm);
	agp_draw_vobj(-prop.scale.x, -prop.scale.y, prop.scale.x,
		prop.scale.y, txcos, mvm);
}

static void ffunc_process(arcan_vobject* dst, int cookie)
{
/* we use an update cookie to make sure that we don't process
 * the same object multiple times when/if it is shared */
	if (!dst->feed.ffunc ||
		dst->feed.pcookie == cookie || FL_TEST(dst, FL_CLONE))
		return;

	dst->feed.pcookie = cookie;

/* if there is a new frame available, we make sure to flag it
 * dirty so that it will be rendered */
	if (dst->feed.ffunc(
		FFUNC_POLL, 0, 0, 0, 0, 0, dst->feed.state) == FFUNC_RV_GOTFRAME) {
		FLAG_DIRTY(dst);

/* cycle active frame store (depending on how often we want to
 * track history frames, might not be every time) */
		if (dst->frameset && dst->frameset->mctr != 0){
			dst->frameset->ctr--;

			if (dst->frameset->ctr == 0){
				dst->frameset->ctr = abs( dst->frameset->mctr );
				step_active_frame(dst);
			}
		}

		dst->feed.ffunc(FFUNC_RENDER,
			dst->vstore->vinf.text.raw, dst->vstore->vinf.text.s_raw,
			dst->vstore->w, dst->vstore->h,
			dst->vstore->vinf.text.glid,
			dst->feed.state
		);
	}

	return;
}

/*
 * scan all 'feed objects' (possible optimization, keep these tracked
 * in a separate list and run prior to all other rendering, might gain
 * something when other pseudo-asynchronous operations (e.g. PBO) are concerned
 */
static void poll_list(arcan_vobject_litem* current, int cookie)
{
	while(current && current->elem){
	arcan_vobject* celem  = current->elem;

	if (celem->feed.ffunc)
		ffunc_process(celem, cookie);

		current = current->next;
	}
}

void arcan_video_pollfeed(){
	static int vcookie = 1;
	vcookie++;

 for (off_t ind = 0; ind < current_context->n_rtargets; ind++)
		poll_readback(&current_context->rtargets[ind]);

	if (FL_TEST(&current_context->stdoutp, TGTFL_READING))
		poll_readback(&current_context->stdoutp);

	for (size_t i = 0; i < current_context->n_rtargets; i++)
		poll_list(current_context->rtargets[i].first, vcookie);

	poll_list(current_context->stdoutp.first, vcookie);
}

static inline void populate_stencil(struct rendertarget* tgt,
	arcan_vobject* celem, float fract)
{
	agp_prepare_stencil();
	arcan_shader_activate(agp_default_shader(COLOR_2D));

	if (celem->clip == ARCAN_CLIP_SHALLOW){
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

			if (celem->parent->clip == ARCAN_CLIP_OFF)
				draw_colorsurf(tgt, pprops, celem->parent, 1.0, 1.0, 1.0);

			else if (celem->parent->clip == ARCAN_CLIP_SHALLOW){
				draw_colorsurf(tgt, pprops, celem->parent, 1.0, 1.0, 1.0);
				break;
			}

			celem = celem->parent;
		}

	agp_activate_stencil();
}

static inline void bind_multitexture(arcan_vobject* elem)
{
	struct storage_info_t** frames;
	size_t sz;

	if (FL_TEST(elem, FL_CLONE)){
		frames = elem->parent->frameset->frames;
		sz = elem->parent->frameset->n_frames;
	}
	else {
		frames = elem->frameset->frames;
		sz = elem->frameset->n_frames;
	}

/* regular multitexture case, just forward */
	if (elem->frameset->index == 0){
		agp_activate_vstore_multi(frames, sz);
		return;
	}

	struct storage_info_t* elems[sz];

/* round-robin "history frame" mode, now the previous slots
 * represent previous frames */

	for (ssize_t ind = elem->frameset->index, i = 0; i < sz;
		i++, ind = (ind > 0 ? ind - 1 : sz - 1))
		elems[i] = frames[ind];

	agp_activate_vstore_multi(elems, sz);
}

/*
 * Apply clipping without using the stencil buffer,
 * cheaper but with some caveats of its own.
 * Will work particularly bad for partial clipping
 * with customized texture coordinates.
 */
static inline bool setup_shallow_texclip(arcan_vobject* elem,
	float** txcos, surface_properties* dprops, float fract)
{
	static float cliptxbuf[8];

	surface_properties pprops = empty_surface();
	arcan_resolve_vidprop(elem->parent, fract, &pprops);

	float p_x = pprops.position.x;
	float p_y = pprops.position.y;
	float p_w = pprops.scale.x * elem->parent->origw;
	float p_h = pprops.scale.y * elem->parent->origh;
	float p_xw = p_x + p_w;
	float p_yh = p_y + p_h;

	float cp_x = dprops->position.x;
	float cp_y = dprops->position.y;
	float cp_w = dprops->scale.x * elem->origw;
	float cp_h = dprops->scale.y * elem->origh;
	float cp_xw = cp_x + cp_w;
	float cp_yh = cp_y + cp_h;

/* fully outside? skip drawing */
	if (cp_xw < p_x || cp_yh < p_y ||	cp_x > p_xw || cp_y > p_yh)
		return false;

/* fully contained? don't do anything */
	else if (	cp_x >= p_x && cp_xw <= p_xw && cp_y >= p_y && cp_yh <= p_yh )
		return true;

	memcpy(cliptxbuf, *txcos, sizeof(float) * 8);
	float xrange = cliptxbuf[2] - cliptxbuf[0];
	float yrange = cliptxbuf[7] - cliptxbuf[1];

	if (cp_x < p_x){
		float sl = ((p_x - cp_x) / elem->origw) * xrange;
		cp_w -= p_x - cp_x;
		cliptxbuf[0] += sl;
		cliptxbuf[6] += sl;
		cp_x = p_x;
	}

	if (cp_y < p_y){
		float su = ((p_y - cp_y) / elem->origh) * yrange;
		cp_h -= p_y - cp_y;
		cliptxbuf[1] += su;
		cliptxbuf[3] += su;
		cp_y = p_y;
	}

	if (cp_x + cp_w > p_xw){
		float sr = ((cp_x + cp_w) - p_xw) / elem->origw * xrange;
		cp_w -= (cp_x + cp_w) - p_xw;
		cliptxbuf[2] -= sr;
		cliptxbuf[4] -= sr;
	}

	if (cp_y + cp_h > p_yh){
		float sd = ((cp_y + cp_h) - p_yh) / elem->origh * yrange;
		cp_h -= (cp_y + cp_h) - p_yh;
		cliptxbuf[5] -= sd;
		cliptxbuf[7] -= sd;
	}

/* dprops modifications should be moved to a scaled draw */
	dprops->position.x = cp_x;
	dprops->position.y = cp_y;
	dprops->scale.x = cp_w / elem->origw;
	dprops->scale.y = cp_h / elem->origh;

/* this is expensive, we should instead temporarily offset */
	elem->valid_cache = false;
	*txcos = cliptxbuf;
	return true;
}

static size_t process_rendertarget(
	struct rendertarget* tgt, float fract)
{
	arcan_vobject_litem* current = tgt->first;

	if (arcan_video_display.ignore_dirty == false &&
			arcan_video_display.dirty == 0 && tgt->transfc == 0)
		return 0;

	if (!FL_TEST(tgt, TGTFL_NOCLEAR))
		agp_rendertarget_clear();

	size_t pc = 0;

/* first, handle all 3d work
 * (which may require multiple passes etc.) */
	if (!arcan_video_display.order3d == ORDER3D_FIRST &&
		current && current->elem->order < 0){
		current = arcan_refresh_3d(tgt->camtag, current, fract);
		pc++;
	}

/* skip a possible 3d pipeline */
	while (current && current->elem->order < 0)
		current = current->next;

	if (!current)
		goto end3d;

/* make sure we're in a decent state for 2D */
	agp_pipeline_hint(PIPELINE_2D);

	arcan_shader_activate(agp_default_shader(BASIC_2D));
	arcan_shader_envv(PROJECTION_MATR, tgt->projection, sizeof(float)*16);

	while (current && current->elem->order >= 0){
		arcan_vobject* elem = current->elem;

/* calculate coordinate system translations, world cannot be masked */
		surface_properties dprops = empty_surface();
		arcan_resolve_vidprop(elem, fract, &dprops);

/* don't waste time on objects that aren't supposed to be visible */
		if ( dprops.opa < EPSILON || elem == tgt->color){
			current = current->next;
			continue;
		}

/* enable clipping using stencil buffer,
 * we need to reset the state of the stencil buffer between
 * draw calls so track if it's enabled or not */
		bool clipped = false;

/*
 * texture coordinates that will be passed to the draw call,
 * clipping and other effects may maintain a local copy and
 * manipulate these
 */
		float* txcos = elem->txcos;
		float** dstcos = &txcos;

		if ( (elem->mask & MASK_MAPPING) > 0)
			txcos = elem->parent != &current_context->world ?
				elem->parent->txcos : elem->txcos;
		else if (FL_TEST(elem, FL_CLONE))
			txcos = elem->txcos;

		if (!txcos)
			txcos = arcan_video_display.default_txcos;

/* a common clipping situation is that we have an invisible clipping parent
 * where neither objects is in a rotated state, which gives an easy way
 * out through the drawing region */
		if (elem->clip == ARCAN_CLIP_SHALLOW &&
			elem->parent != &current_context->world && !elem->rotate_state){
			if (!setup_shallow_texclip(elem, dstcos, &dprops, fract)){
				current = current->next;
				continue;
			}
		}
		else if (elem->clip != ARCAN_CLIP_OFF &&
			elem->parent != &current_context->world){
			clipped = true;
			populate_stencil(tgt, elem, fract);
		}

/* if the object is not txmapped (or null, in that case give up) */
		if (elem->vstore->txmapped == TXSTATE_OFF){
			if (elem->program != 0){
				arcan_shader_activate(elem->program);
				draw_colorsurf(tgt, dprops, elem, elem->vstore->vinf.col.r,
					elem->vstore->vinf.col.g, elem->vstore->vinf.col.b);
			}

			if (clipped)
				agp_disable_stencil();

			current = current->next;
			continue;
		}

		arcan_shader_activate( elem->program > 0 ?
			elem->program : agp_default_shader(BASIC_2D) );

/* depending on frameset- mode, we may need to split
 * the frameset up into multitexturing */

		if (elem->frameset){
			if (elem->frameset->mode == ARCAN_FRAMESET_MULTITEXTURE)
				bind_multitexture(elem);
			else{
				if (FL_TEST(elem, FL_CLONE))
					agp_activate_vstore(
						elem->parent->frameset->frames[elem->frameset->index]);
				else
					agp_activate_vstore(elem->frameset->frames[elem->frameset->index]);
			}
		}
		else
			agp_activate_vstore(elem->vstore);

		if (dprops.opa < 1.0 - EPSILON)
			agp_blendstate(elem->blendmode);
		else
			if (elem->blendmode == BLEND_FORCE)
				agp_blendstate(elem->blendmode);
			else
				agp_blendstate(BLEND_NORMAL);

		draw_texsurf(tgt, dprops, elem, *dstcos);
		pc++;

	if (clipped)
		agp_disable_stencil();

		current = current->next;
	}

/* reset and try the 3d part again if requested */
end3d:
	current = tgt->first;
	if (current && current->elem->order < 0 &&
		arcan_video_display.order3d == ORDER3D_LAST){
		arcan_shader_activate(agp_default_shader(BASIC_2D));
		current = arcan_refresh_3d(tgt->camtag, current, fract);
		if (current != tgt->first)
			pc++;
	}

	return pc;
}

arcan_errc arcan_video_forceread(arcan_vobj_id sid,
	av_pixel** dptr, size_t* dsize)
{
/*
 * more involved than one may think, the store doesn't have to be representative
 * in case of rendertargets, and for streaming readbacks of those we already
 * have readback toggles etc. Thus this function is only for "one-off" reads
 * where a blocking behavior may be accepted, especially outside a main
 * renderloop as this will possibly stall the pipeline
 */

	arcan_vobject* vobj = arcan_video_getobject(sid);
	struct storage_info_t* dstore = vobj->vstore;

	if (!vobj || !dstore)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	*dsize = GL_PIXEL_BPP * dstore->w * dstore->h;
	*dptr  = arcan_alloc_mem(*dsize, ARCAN_MEM_VBUFFER,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

	agp_readback_synchronous(dstore);
	if (dptr && dstore->vinf.text.raw){
		memcpy(*dptr, dstore->vinf.text.raw, *dsize);
		return ARCAN_OK;
	}

	arcan_mem_free(*dptr);
	return ARCAN_OK;
}

struct storage_info_t* arcan_vint_world()
{
	return current_context->stdoutp.color->vstore;
}

arcan_errc arcan_video_forceupdate(arcan_vobj_id vid)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* tgt = find_rendertarget(vobj);
	if (!tgt)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	FLAG_DIRTY(vobj);
	agp_activate_rendertarget(tgt->art);
	process_rendertarget(tgt, arcan_video_display.c_lerp);
	agp_activate_rendertarget(NULL);

	if (tgt->readback != 0){
		process_readback(tgt, arcan_video_display.c_lerp);
		poll_readback(tgt);
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_screenshot(av_pixel** dptr, size_t* dsize)
{
	struct monitor_mode mode = platform_video_dimensions();
	*dsize = sizeof(char) * mode.width * mode.height * GL_PIXEL_BPP;

	*dptr = arcan_alloc_mem(*dsize, ARCAN_MEM_VBUFFER,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

	if (!(*dptr)){
		*dsize = 0;
		return ARCAN_ERRC_OUT_OF_SPACE;
	}

	agp_save_output(mode.width, mode.height, *dptr, *dsize);

	return ARCAN_OK;
}

/* check outstanding readbacks, map and feed onwards */
static inline void poll_readback(struct rendertarget* tgt)
{
	if (!FL_TEST(tgt, TGTFL_READING))
		return;

	arcan_vobject* vobj = tgt->color;
	struct asynch_readback_meta rbb = agp_poll_readback(vobj->vstore);

	if (rbb.ptr == NULL)
		return;

	if (!vobj->feed.ffunc)
		tgt->readback = 0;
	else{
		vobj->feed.ffunc(FFUNC_READBACK, rbb.ptr,
			rbb.w * rbb.h * GL_PIXEL_BPP, rbb.w, rbb.h, 0, vobj->feed.state);
	}

	rbb.release(rbb.tag);
	FL_CLEAR(tgt, TGTFL_READING);
}

/* should we issue a new readback? */
static inline void process_readback(struct rendertarget* tgt, float fract)
{
	if (FL_TEST(tgt, TGTFL_READING) || tgt->readback == 0)
		return;

/* resolution is "by tick" */
	if (tgt->readback < 0){
		tgt->readcnt--;
		if (tgt->readcnt <= 0){
			tgt->readcnt = abs(tgt->readback);
			goto request;
		}
		else
			return;
	}

/* resolution is "by other clock", approximately */
	else if (tgt->readback > 0){
		long long stamp = round( ((double)arcan_video_display.c_ticks + fract) *
			(double)ARCAN_TIMER_TICK );
		if (stamp - tgt->readcnt > tgt->readback){
			tgt->readcnt = stamp;
		}
		else
			return;
	}

request:
	agp_request_readback(tgt->color->vstore);
	FL_SET(tgt, TGTFL_READING);
}

unsigned arcan_vint_refresh(float fract, size_t* ndirty)
{
	long long int pre = arcan_timemillis();
	size_t transfc = 0;

	arcan_video_display.c_lerp = fract;

/*
 * active shaders with a timed uniform subscription
 * count towards dirty state.
 */
	arcan_video_display.dirty +=
		arcan_shader_envv(FRACT_TIMESTAMP_F, &fract, sizeof(float));

/* rendertargets may be composed on world- output, begin there */
	for (size_t ind = 0; ind < current_context->n_rtargets; ind++){
		struct rendertarget* tgt = &current_context->rtargets[ind];

		agp_activate_rendertarget(tgt->art);
		process_rendertarget(tgt, fract);
		process_readback(&current_context->rtargets[ind], fract);

		transfc += tgt->transfc;
	}

	agp_activate_rendertarget(current_context->stdoutp.art);

	process_rendertarget(&current_context->stdoutp, fract);
	process_readback(&current_context->stdoutp, fract);
	transfc += current_context->stdoutp.transfc;

	*ndirty = arcan_video_display.dirty;
	arcan_video_display.dirty = transfc;

	long long int post = arcan_timemillis();
	return post - pre;
}

void arcan_video_default_scalemode(enum arcan_vimage_mode newmode)
{
	arcan_video_display.scalemode = newmode;
}

void arcan_video_default_texmode(enum arcan_vtex_mode modes,
	enum arcan_vtex_mode modet)
{
	arcan_video_display.deftxs = modes;
	arcan_video_display.deftxt = modet;
}

arcan_errc arcan_video_screencoords(arcan_vobj_id id, vector* res)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag == ARCAN_TAG_3DOBJ)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	surface_properties prop;

	if (vobj->valid_cache)
		prop = vobj->prop_cache;
	else {
		prop = empty_surface();
		arcan_resolve_vidprop(vobj, arcan_video_display.c_lerp, &prop);
	}

	float w = (float)vobj->origw * prop.scale.x;
	float h = (float)vobj->origh * prop.scale.y;

	res[0].x = prop.position.x;
	res[0].y = prop.position.y;
	res[1].x = res[0].x + w;
	res[1].y = res[0].y;
	res[2].x = res[1].x;
	res[2].y = res[1].y + h;
	res[3].x = res[0].x;
	res[3].y = res[2].y;

	if (abs(prop.rotation.roll) > EPSILON){
		float ang = DEG2RAD(prop.rotation.roll);
		float sinv = sinf(ang);
		float cosv = cosf(ang);

		float cpx = res[0].x + 0.5 * w;
		float cpy = res[0].y + 0.5 * h;

		for (size_t i = 0; i < 4; i++){
			float rx = cosv * (res[i].x - cpx) - sinv * (res[i].y-cpy) + cpx;
			float ry = sinv * (res[i].x - cpx) + cosv * (res[i].y-cpy) + cpy;
			res[i].x = rx;
			res[i].y = ry;
		}
	}

	return ARCAN_OK;
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

bool arcan_video_hittest(arcan_vobj_id id, unsigned int x, unsigned int y)
{
	vector projv[4];
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (ARCAN_OK != arcan_video_screencoords(id, projv)){
		if (vobj && vobj->feed.state.tag == ARCAN_TAG_3DOBJ){
			return arcan_3d_obj_bb_intersect(
				current_context->stdoutp.camtag, id, x, y);
		}
		return false;
	}

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
	if (count == 0 || !current_context->stdoutp.first)
		return 0;

/* skip to last item, then scan backwards */
	arcan_vobject_litem* current = current_context->stdoutp.first;
	unsigned base = 0;

	while (current->next)
		current = current->next;

	while (current && base < count){
		arcan_vobject* vobj = current->elem;

		if (vobj->cellid && (vobj->mask &
			MASK_UNPICKABLE) == 0 && obj_visible(vobj)){

			if (arcan_video_hittest(vobj->cellid, x, y))
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

	while (current && base < count){
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

img_cons arcan_video_storage_properties(arcan_vobj_id id)
{
	img_cons res = {.w = 0, .h = 0, .bpp = 0};
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && vobj->vstore) {
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
					rv.position = lut_interp_3d[current->move.interp](
						current->move.startp,
						current->move.endp, fract
					);
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
					rv.scale = lut_interp_3d[current->scale.interp](
						current->scale.startd,
						current->scale.endd, fract
					);
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
					rv.opa = lut_interp_1d[current->blend.interp](
						current->blend.startopa,
						current->blend.endopa,
						fract
					);
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

					rv.rotation.quaternion = current->rotate.interp(
						current->rotate.starto.quaternion,
						current->rotate.endo.quaternion, fract
					);
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

unsigned arcan_video_contextusage(unsigned* used)
{
	if (used){
		*used = 0;
		for (unsigned i = 1; i < current_context->vitem_limit-1; i++)
			if (FL_TEST(&current_context->vitems_pool[i], FL_INUSE))
				(*used)++;
	}

	return current_context->vitem_limit-1;
}

bool arcan_video_contextsize(unsigned newlim)
{
	if (newlim <= 1 || newlim >= VITEM_CONTEXT_LIMIT)
		return false;

/* this change isn't allowed when the shrink/expand operation would
 * change persistent objects in the stack */
	if (newlim < arcan_video_display.default_vitemlim)
		for (unsigned i = 1; i < current_context->vitem_limit-1; i++)
			if (FL_TEST(&current_context->vitems_pool[i], FL_INUSE|FL_PRSIST))
				return false;

	arcan_video_display.default_vitemlim = newlim;
	return true;
}

extern void platform_video_restore_external();
void arcan_video_restore_external()
{
	platform_video_restore_external();
	arcan_event_init( arcan_event_defaultctx() );
	arcan_shader_rebuild_all();
	arcan_video_popcontext();
}

extern void platform_video_shutdown();
void arcan_video_shutdown()
{
	unsigned lastctxa, lastctxc = arcan_video_popcontext();

	if (arcan_video_display.in_video == false)
		return;

	arcan_video_display.in_video = false;

/* this will effectively make sure that all external launchers,
 * frameservers etc. gets killed off */
	while ( lastctxc != (lastctxa = arcan_video_popcontext()) )
		lastctxc = lastctxa;

	arcan_shader_flush();
	deallocate_gl_context(current_context, true);
	arcan_video_reset_fontcache();
	agp_rendertarget_clear(NULL);

	platform_video_shutdown();
}

arcan_errc arcan_video_tracetag(arcan_vobj_id id, const char*const message)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		if (vobj->tracetag)
			arcan_mem_free(vobj->tracetag);

		vobj->tracetag = strdup(message);
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_vobj_id arcan_video_renderstring(const char* message,
	int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs,
	unsigned int* n_lines, unsigned int** lineheights)
{
	arcan_vobj_id rv = ARCAN_EID;
	if (!message)
		return rv;

	arcan_vobject* vobj = arcan_video_newvobject(&rv);

	if (!vobj){
		arcan_fatal("Fatal: arcan_video_renderstring(), "
			"couldn't allocate video object. Out of Memory or out of IDs "
			"in current context. There is likely a resource leak in the "
			"scripts of the current theme.\n");
	}

	size_t maxw, maxh;

	struct storage_info_t* ds = vobj->vstore;

	ds->vinf.text.raw = arcan_renderfun_renderfmtstr(
		message, line_spacing, tab_spacing,
		tabs, true, n_lines, lineheights,
		&ds->w, &ds->h, &ds->vinf.text.s_raw, &maxw, &maxh
	);

	if (ds->vinf.text.raw == NULL){
		arcan_video_deleteobject(rv);
		return ARCAN_EID;
	}

	vobj->feed.state.tag = ARCAN_TAG_TEXT;
	vobj->blendmode = BLEND_FORCE;
	vobj->origw = maxw;
	vobj->origh = maxh;
	vobj->txcos = arcan_alloc_mem(8 * sizeof(float),
		ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);
	ds->vinf.text.source = strdup(message);

	agp_update_vstore(vobj->vstore, true);

/*
 * POT but not all used,
 */
	float wv = (float)maxw / (float)vobj->vstore->w;
	float hv = (float)maxh / (float)vobj->vstore->h;
	generate_basic_mapping(vobj->txcos, wv, hv);
	arcan_video_attachobject(rv);

	return rv;
}
