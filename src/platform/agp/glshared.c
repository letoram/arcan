/*
 * Copyright 2014-2019, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <math.h>
#include <inttypes.h>

#include "glfun.h"

#include "../video_platform.h"
#include "../platform.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_mem.h"
#include "arcan_videoint.h"

#ifdef HEADLESS_NOARCAN
#undef FLAG_DIRTY
#define FLAG_DIRTY()
#endif

#ifndef GL_VERTEX_PROGRAM_POINT_SIZE
#define GL_VERTEX_PROGRAM_POINT_SIZE GL_NONE
#endif

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

#define debug_print(fmt, ...) \
            do { if (DEBUG) arcan_warning("%lld:%s:%d:%s(): " fmt "\n",\
						arcan_timemillis(), "agp-glshared:", __LINE__, __func__,##__VA_ARGS__); } while (0)

#ifndef verbose_print
#define verbose_print
#endif

static struct agp_rendertarget* active_rendertarget;

/*
 * Workaround for missing GL_DRAW_FRAMEBUFFER_BINDING
 */
#if defined(GLES2) || defined(GLES3)
	GLuint st_last_fbo;
	#define BIND_FRAMEBUFFER(X) do {\
		verbose_print("bind fbo: %u", (unsigned)(X));\
		st_last_fbo = (X);\
		env->bind_framebuffer(GL_FRAMEBUFFER, (X)); } while(0)
#else
	#define BIND_FRAMEBUFFER(X) do {\
		verbose_print("bind fbo: %u", (unsigned)(X));\
		env->bind_framebuffer(GL_FRAMEBUFFER, (X)); } while(0)
#endif

/*
 * Typically 3 or 1 used:
 *
 *  - front (being presented somewhere)
 *  - pending (scheduled to be presented)
 *  - back (being drawn to)
 *
 * These affect any dirty target management, as any dirty changes need to apply
 * to all 3. A more subtle thing would be that the image_sharestorage would get
 * out of synch. The path that would provoke it:
 *
 *  1. create vobj
 *  2. create rendertarget, output to vobj
 *  3. map vobj to display or arcan_lwa outgoing (now next swap we have 3)
 *  4. create vobj2
 *  5. share vobj1 storage with vobj2
 *
 * there aren't many sane options to dealing with this case that wouldn't take
 * expanding the vstore to track external references and manipulate them.
 *
 * The solution, for now, was to add another level of indirection, and have
 * a resolve function for the GLID when it is actually used, which is mostly
 * within AGP. This still won't fix other indirect bindings, i.e. being used
 * for slices in a 3D texture or a cubemap.
 */
#define MAX_BUFFERS 4

struct agp_rendertarget
{
	GLuint fbo;
	GLuint depth;

	GLuint msaa_fbo;
	GLuint msaa_color;
	GLuint msaa_depth;

	ssize_t viewport[4];
	float clearcol[4];

	enum rendertarget_mode mode;
	struct agp_vstore* store;

	bool (*proxy_state)(struct agp_rendertarget* tgt, uintptr_t tag);
	uintptr_t proxy_tag;

/* used for multi-buffering mode */
	bool rz_ack;
	size_t n_stores;
	size_t dirty_flip, dirty_region, dirty_region_decay;
	size_t store_ind;
	struct agp_vstore* stores[MAX_BUFFERS];
	struct agp_vstore* shadow[MAX_BUFFERS];

	bool (*alloc)(struct agp_rendertarget*, struct agp_vstore*, int, void*);
	void* alloc_tag;
};

static void erase_store(struct agp_vstore* os)
{
	if (!os)
		return;

	agp_null_vstore(os);
	arcan_mem_free(os->vinf.text.raw);
	os->vinf.text.raw = NULL;
	os->vinf.text.s_raw = 0;
}

static void update_fbo_color(struct agp_rendertarget* dst, unsigned id)
{
	GLint cfbo;
	struct agp_fenv* env = agp_env();

/* switch rendertarget if we're not already there */
#if defined(GLES2) || defined(GLES3)
	cfbo = st_last_fbo;
#else
	env->get_integer_v(GL_DRAW_FRAMEBUFFER_BINDING, &cfbo);
#endif

	if (dst->fbo != cfbo)
		BIND_FRAMEBUFFER(dst->fbo);

	env->framebuffer_texture_2d(
		GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, id, 0);

	/* and switch back to the old rendertarget */
	if (dst->fbo != cfbo)
		BIND_FRAMEBUFFER(cfbo);
}

/*
 * build alternate stores for rendertarget swapping
 */
static void setup_stores(struct agp_rendertarget* dst)
{
/* need this tracking because there's no external memory management for _back */
	dst->n_stores = MAX_BUFFERS;
	dst->dirty_flip = MAX_BUFFERS;
	dst->dirty_region_decay = dst->dirty_region = 0;

	TRACE_MARK_ONESHOT("agp", "setup-rtgt-vstore-swap",
		TRACE_SYS_DEFAULT, (uintptr_t) dst, MAX_BUFFERS, "");

/* build the current ones based on the reference store properties */
	for (size_t i = 0; i < MAX_BUFFERS; i++){
		dst->stores[i] = arcan_alloc_mem(sizeof(struct agp_vstore),
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		dst->stores[i]->vinf.text.s_fmt = dst->store->vinf.text.s_fmt;
		dst->stores[i]->vinf.text.d_fmt = dst->store->vinf.text.d_fmt;

		if (dst->alloc){
			dst->stores[i]->w = dst->store->w;
			dst->stores[i]->h = dst->store->h;
			dst->alloc(dst, dst->stores[i], RTGT_ALLOC_SETUP, dst->alloc_tag);
		}
		else{
			agp_empty_vstore(dst->stores[i], dst->store->w, dst->store->h);
		}
	}
}

void agp_rendertarget_allocator(struct agp_rendertarget* tgt, bool (*handler)(
	struct agp_rendertarget*, struct agp_vstore*, int action, void* tag), void* tag)
{
	if (!tgt)
		return;

/* free anything currently allocated on the rendertarget before
 * swapping out allocator */
	if (tgt->alloc){
		for (size_t i = 0; i < tgt->n_stores; i++){
			tgt->alloc(tgt, tgt->stores[i], RTGT_ALLOC_FREE, tgt->alloc_tag);
			if (tgt->shadow[i]){
				tgt->alloc(tgt, tgt->shadow[i], RTGT_ALLOC_FREE, tgt->alloc_tag);
				arcan_mem_free(tgt->shadow[i]);
				tgt->shadow[i] = NULL;
			}
		}
	}

	tgt->alloc = handler;
	tgt->alloc_tag = tag;

/* only re-allocate if _swap has been called, otherwise those allocations
 * will come soon enough, if the allocator is disabled */
	if (!tgt->n_stores)
		return;

/* and now re-allocate the buffers using the allocator, if this
 * fails, revert back (again) to the default one */
	for (size_t i = 0; i < tgt->n_stores; i++){
		tgt->alloc(tgt, tgt->stores[i], RTGT_ALLOC_SETUP, tgt->alloc_tag);
	}

/* ID might have changed, so re-attach to FBO */
	struct agp_fenv* env = agp_env();

/* same procedure as with agp_rendertarget_swap */
	GLint cfbo;
#if defined(GLES2) || defined(GLES3)
	cfbo = st_last_fbo;
#else
	env->get_integer_v(GL_DRAW_FRAMEBUFFER_BINDING, &cfbo);
#endif

	if (tgt->fbo != cfbo)
		BIND_FRAMEBUFFER(tgt->fbo);
	int front = tgt->store_ind;

	env->framebuffer_texture_2d(GL_FRAMEBUFFER,
		GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tgt->stores[front]->vinf.text.glid, 0);

/* the glid_proxy is a pointer so it will still be valid */

	BIND_FRAMEBUFFER(cfbo);
}

void agp_rendertarget_dropswap(struct agp_rendertarget* tgt)
{
	struct agp_fenv* env = agp_env();
	if (!tgt || !tgt->n_stores)
		return;

	verbose_print("dropping normal and shadow stores");
	for (size_t i = 0; i < tgt->n_stores; i++){
		if (tgt->alloc){
			tgt->alloc(tgt, tgt->stores[i], RTGT_ALLOC_FREE, tgt->alloc_tag);
		}
		else
			agp_drop_vstore(tgt->stores[i]);
/* if the source is deleted while we are in an unflushed resize */
		if (tgt->shadow[i]){
			if (tgt->alloc)
				tgt->alloc(tgt, tgt->shadow[i], RTGT_ALLOC_FREE, tgt->alloc_tag);
			else
				agp_drop_vstore(tgt->shadow[i]);

			arcan_mem_free(tgt->shadow[i]);
			tgt->shadow[i] = NULL;
		}
	}

/* revert to 'default' buffer */
	tgt->n_stores = 0;
	tgt->store->vinf.text.glid_proxy = NULL;
	tgt->alloc = NULL;
	tgt->alloc_tag = NULL;

	update_fbo_color(tgt, tgt->store->vinf.text.glid);

/* mark that we need to treat as dirty regardless of contents */
	tgt->dirty_flip++;
}

size_t agp_rendertarget_dirty(
	struct agp_rendertarget* dst, struct agp_region* dirty)
{
	if (!dst)
		return 0;

/* rather unsofisticated, we could/should have a n-buffered merge-region
 * instead of this inc/dec/decay nonsense - but all in due course */
	if (dirty){
		dst->dirty_region++;
		dst->dirty_region_decay++;
	}

	return dst->dirty_region_decay;
}

struct agp_vstore*
	agp_rendertarget_swap(struct agp_rendertarget* dst, bool* swap)
{
	struct agp_fenv* env = agp_env();
	if (!dst || !dst->store){
		*swap = false;
		return NULL;
	}

	int old_front = dst->store_ind;
	int front = dst->store_ind;

/* multi-buffer setup - no need to swap until we have populated one frame */
	if (!dst->n_stores){
		verbose_print("(%"PRIxPTR") first swap, alloc buffers", (uintptr_t) dst);
		setup_stores(dst);
		FLAG_DIRTY();
		*swap = false;
	}
/* already setup - can swap out old-front */
	else {
		front = dst->store_ind = (dst->store_ind + 1) % MAX_BUFFERS;
		*swap = true;
	}

/* Attach new front, update alias. We use the alias on the normal store to make
 * sure that 'image_sharestorage' calls will reference the currently active buffer
 * and not drag behind */
	verbose_print("(%"PRIxPTR") proxy+COLOR0 set to: %u",
		(uintptr_t) dst, dst->stores[front]->vinf.text.glid);

	update_fbo_color(dst, dst->stores[front]->vinf.text.glid);
	dst->store->vinf.text.glid_proxy = &dst->stores[front]->vinf.text.glid;

/* the contents are dirty, check the swap- count until shadow buffer flush so that
 * there is no buffer in flight or elsewise used that rely on the 'old' size */
	if (dst->dirty_flip > 0){
		dst->dirty_flip--;
		FLAG_DIRTY();
		verbose_print("(%"PRIxPTR") dirty left: %zu", (uintptr_t) dst, dst->dirty_flip);

/* now that we have 'dirtied out' and any external users should have received
 * copies of our current buffers, we can clean them up - could also let them
 * decay in 'order' but the slight memory burst should not be that big of a
 * concern */
		if (!dst->dirty_flip){
			for (size_t i = 0; i < MAX_BUFFERS; i++){
				if (!dst->shadow[i])
					continue;

				verbose_print("(%"PRIxPTR") shadow %zu:%u cleared",
					(uintptr_t) dst, i, (unsigned)dst->shadow[i]->vinf.text.glid);

				if (dst->alloc)
					dst->alloc(dst, dst->shadow[i], RTGT_ALLOC_FREE, dst->alloc_tag);
				else
					erase_store(dst->shadow[i]);

				arcan_mem_free(dst->shadow[i]);
				dst->shadow[i] = NULL;
			}
		}

/* defer the swapping one frame on a resize, seem to be a fence-synch like
 * problem with some GPU drivers as we tend to get partial damage on the first
 * frame after a swap, monitor this more closely */
		if (dst->rz_ack){
			verbose_print("(%"PRIxPTR") rz-ack defer swap", (uintptr_t) dst);
			*swap = false;
			dst->rz_ack = false;
			return NULL;
		}
	}

	verbose_print("(%"PRIxPTR") swap out glid: %u",
		(uintptr_t) dst, (unsigned) dst->stores[old_front]->vinf.text.glid);

	return dst->stores[old_front];
}

static void drop_msaa(struct agp_rendertarget* dst)
{
	struct agp_fenv* env = agp_env();
	env->delete_framebuffers(1,&dst->msaa_fbo);
	env->delete_renderbuffers(1,&dst->msaa_depth);
	env->delete_textures(1,&dst->msaa_color);
	dst->msaa_fbo = dst->msaa_depth = dst->msaa_color = GL_NONE;

	verbose_print("(%"PRIxPTR") drop MSAA", (uintptr_t) dst);
}

#ifndef GL_TEXTURE_2D_MULTISAMPLE
#define GL_TEXTURE_2D_MULTISAMPLE 0x9100
#endif

static bool alloc_fbo(struct agp_rendertarget* dst, bool retry)
{
	struct agp_fenv* env = agp_env();
	int mode = dst->mode & (~RENDERTARGET_RETAIN_ALPHA);

/* recall this is actually OpenGL 3.0, so it's not at all certain
 * that we will actually get it. Then we fallback 'gracefully' */
	if (!env->renderbuffer_storage_multisample || !env->tex_image_2d_multisample){
		dst->mode = (dst->mode & ~RENDERTARGET_MSAA);
		dst->mode |= RENDERTARGET_COLOR_DEPTH_STENCIL;
	}

	verbose_print(
		"(%"PRIxPTR") build FBO, mode: %d", (uintptr_t) dst, mode);

/*
 * we need two FBOs, one for the MSAA pass and one to resolve into
 */

#if !defined(GLES2)
	if (mode == RENDERTARGET_MSAA){
		env->gen_textures(1, &dst->msaa_color);
		env->bind_texture(GL_TEXTURE_2D_MULTISAMPLE, dst->msaa_color);
		env->tex_image_2d_multisample(GL_TEXTURE_2D_MULTISAMPLE, GL_RGB, 4,
			dst->store->w, dst->store->h, GL_TRUE);
		env->bind_texture(GL_TEXTURE_2D_MULTISAMPLE, 0);
		env->gen_framebuffers(1, &dst->msaa_fbo);
		env->gen_renderbuffers(1, &dst->msaa_depth);
		BIND_FRAMEBUFFER(dst->msaa_fbo);
		env->framebuffer_texture_2d(GL_FRAMEBUFFER,
			GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D_MULTISAMPLE, dst->msaa_color, 0);
		env->renderbuffer_storage_multisample(GL_RENDERBUFFER,
			GL_DEPTH24_STENCIL8, dst->store->w, dst->store->h);
		GLenum status = env->check_framebuffer(GL_FRAMEBUFFER);
		if (status != GL_FRAMEBUFFER_COMPLETE){
			arcan_warning("agp: couldn't create multisample FBO, falling back.\n");
			drop_msaa(dst);
			dst->mode = (dst->mode & ~RENDERTARGET_MSAA);
			dst->mode |= RENDERTARGET_COLOR_DEPTH_STENCIL;
		}
	}
#endif

	env->gen_framebuffers(1, &dst->fbo);

/* need both stencil and depth buffer, but we don't need the data from them */
	BIND_FRAMEBUFFER(dst->fbo);

	if (mode > RENDERTARGET_DEPTH)
	{
		env->framebuffer_texture_2d(GL_FRAMEBUFFER,
			GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, agp_resolve_texid(dst->store), 0);

		verbose_print("(%"PRIxPTR") COLOR0 set to %u",
			(uintptr_t) dst, (unsigned) agp_resolve_texid(dst->store));

/* need a Z buffer in the offscreen rendering but don't want
 * bo store it, so setup a renderbuffer */
		if (mode > RENDERTARGET_COLOR && !retry){
			env->gen_renderbuffers(1, &dst->depth);

/* could use GL_DEPTH_COMPONENT only if we'd know that there
 * wouldn't be any clipping in the active rendertarget */
			env->bind_renderbuffer(GL_RENDERBUFFER, dst->depth);
			env->renderbuffer_storage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8,
				dst->store->w, dst->store->h);

			env->framebuffer_renderbuffer(GL_FRAMEBUFFER,
				GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, dst->depth);
			env->bind_renderbuffer(GL_RENDERBUFFER, 0);

			verbose_print("(%"PRIxPTR") built with depth+stencil @ %zu*%zu",
				(uintptr_t) dst, dst->store->w, dst->store->h);
		}
	}
	else {
/* DEPTH buffer only (shadowmapping, ...) convert the storage to
 * contain a depth texture */
		size_t w = dst->store->w;
		size_t h = dst->store->h;

		agp_drop_vstore(dst->store);

		struct agp_vstore* store = dst->store;

		memset(store, '\0', sizeof(struct agp_vstore));

		store->txmapped   = TXSTATE_DEPTH;
		store->txu        = ARCAN_VTEX_CLAMP;
		store->txv        = ARCAN_VTEX_CLAMP;
		store->scale      = ARCAN_VIMAGE_NOPOW2;
		store->imageproc  = IMAGEPROC_NORMAL;
		store->filtermode = ARCAN_VFILTER_NONE;
		store->refcount   = 1;
		store->w = w;
		store->h = h;

/* generate ID etc. special path for TXSTATE_DEPTH */
		agp_update_vstore(store, true);

		env->draw_buffer(GL_NONE);
		env->read_buffer(GL_NONE);

		env->framebuffer_texture_2d(GL_FRAMEBUFFER,
			GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, store->vinf.text.glid, 0);
		verbose_print("(%"PRIxPTR") switched to depth-only", (uintptr_t) dst);
	}

/* basic error handling / status checking
 * may be possible that we should cache this in the
 * rendertarget and only call when / if something changes as
 * it's not certain that drivers won't stall the pipeline on this */
	GLenum status = env->check_framebuffer(GL_FRAMEBUFFER);
	if (status != GL_FRAMEBUFFER_COMPLETE){
		arcan_warning("FBO support broken, couldn't create basic FBO:\n");
		switch(status){
		case GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT:
			if (!retry){
				arcan_warning("\t Incomplete Attachment, attempting "
					"simple framebuffer, this will likely break 3D and complex"
					"clipping operations.\n");
				return alloc_fbo(dst, true);
			}
			else
				arcan_warning("\t Simple attachement broke as well "
					"likely driver issue.\n");
		break;

#ifdef GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS
		case GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS:
			arcan_warning("\t Not all attached buffers have "
				"the same dimensions.\n");
		break;
#endif

		case GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT:
			arcan_warning("\t One or several FBO attachment points are missing.\n");
		break;

		case GL_FRAMEBUFFER_UNSUPPORTED:
			arcan_warning("\t Request formats combination unsupported.\n");
		break;
		}

		if (dst->fbo != GL_NONE)
			env->delete_framebuffers(1, &dst->fbo);
		if (dst->depth != GL_NONE)
			env->delete_renderbuffers(1, &dst->depth);

		dst->fbo = dst->depth = GL_NONE;
		return false;
	}

	BIND_FRAMEBUFFER(0);
	return true;
}

/*
 * In GL4.4 if we ever get to move to a less crippled version, this
 * can just be replaced with the glClearTexture
 */
void agp_empty_vstore(struct agp_vstore* vs, size_t w, size_t h)
{
	size_t sz = w * h * sizeof(av_pixel);
	if (!vs->vinf.text.s_raw){
		vs->vinf.text.s_raw = sz;
	}

/* this is to allow an override of s_fmt and still handle reset */
	if (vs->vinf.text.s_fmt == 0){
		vs->vinf.text.s_fmt = GL_PIXEL_FORMAT;
	if (vs->vinf.text.d_fmt == 0)
		vs->vinf.text.d_fmt = GL_STORE_PIXEL_FORMAT;
	}

	vs->vinf.text.raw = arcan_alloc_mem(
		vs->vinf.text.s_raw,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE
	);
	vs->w = w;
	vs->h = h;
	vs->bpp = sizeof(av_pixel);
	vs->txmapped = TXSTATE_TEX2D;

	agp_update_vstore(vs, true);

	arcan_mem_free(vs->vinf.text.raw);
	vs->vinf.text.raw = 0;
	vs->vinf.text.s_raw = 0;

	verbose_print("(%"PRIxPTR") cleared to %zu*%zu", (uintptr_t) vs, w, h);
}

bool agp_slice_vstore(struct agp_vstore* backing,
	size_t n_slices, size_t base, enum txstate txstate)
{
	if (txstate != TXSTATE_CUBE && txstate != TXSTATE_TEX3D)
		return false;

/* not all platforms actually support it */
	if (txstate == TXSTATE_TEX3D && !agp_env()->tex_image_3d)
		return false;

/* dimensions must be power of two */
	if (!base || (base & (base - 1)) != 0 ||
		!n_slices || (n_slices & (n_slices - 1)) != 0)
		return false;

/* and cubemap can only have 6 faces */
	if (txstate == TXSTATE_CUBE && n_slices != 6)
		return false;

	if (backing->vinf.text.s_fmt == 0){
		backing->vinf.text.s_fmt = GL_PIXEL_FORMAT;
	if (backing->vinf.text.d_fmt == 0)
		backing->vinf.text.d_fmt = GL_STORE_PIXEL_FORMAT;
	}

	backing->bpp = sizeof(av_pixel);
	backing->w = base;
	backing->h = base;
	backing->txmapped = txstate;

	verbose_print("(%"PRIxPTR") switched to sliced: "
		"%zu slices, %zu base, %d state", (uintptr_t) backing, n_slices, base, txstate);

/* allocation / upload is deferred to slice stage */
	return true;
}

static bool update_3dtex(
	struct agp_vstore* backing, size_t n_slices, struct agp_vstore** slices)
{
	struct agp_fenv* env = agp_env();
	env->bind_texture(GL_TEXTURE_3D, backing->vinf.text.glid);
	return true;
}

static bool update_cube(
	struct agp_vstore* backing, size_t n_slices, struct agp_vstore** slices)
{
	if (n_slices != 6)
		return false;

/* the options for this one depends on [slices] -ideally we'd just want to
 * copy subdata, but that is 4.x.
 * a. most stable / expensive: readback + upload
 * b. glCopyTexImage2D
 * c. take a scratch FBO, set READ to source, DRAW to cubemap side
 * d. build a PBO and do GPU-GPU transfer that way
 * and if the GPU affinity doesn't match slice vs dst, we're back to a.
 *
 * since the primary motivation here is to use for static data, (a) is ok,
 * the dynamic cases should have 6xFBO passes or hoping for geometry- shaders
 * and setting the output layers to behave accordingly - won't happen.
 */
	struct agp_fenv* env = agp_env();
	env->bind_texture(GL_TEXTURE_CUBE_MAP, backing->vinf.text.glid);
	env->tex_param_i(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	env->tex_param_i(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	env->tex_param_i(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	env->tex_param_i(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

#if !defined(GLES2)
	env->tex_param_i(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
#endif

	verbose_print("(%"PRIxPTR") "
		"update cube-map, slices: %zu", (uintptr_t) backing, n_slices);
	for (size_t i = 0; i < n_slices; i++){
		struct agp_vstore* s = slices[i];
/* only update qualified slices - same size and updated after last synch */
		if (backing->update_ts > s->update_ts ||
			s->w != backing->w || s->h != backing->h ||
			s->txmapped != TXSTATE_TEX2D)
			continue;

		bool drop_slice = false;
		if (!s->vinf.text.raw){
			agp_readback_synchronous(s);
			drop_slice = true;
			if (!s->vinf.text.raw)
				continue;
		}

		env->tex_image_2d(
			GL_TEXTURE_CUBE_MAP_POSITIVE_X+i, 0,
			s->vinf.text.d_fmt ? s->vinf.text.d_fmt : GL_STORE_PIXEL_FORMAT,
			s->w, s->h, 0,
			s->vinf.text.s_fmt ? s->vinf.text.s_fmt : GL_PIXEL_FORMAT,
			s->vinf.text.s_type ? s->vinf.text.s_type : GL_UNSIGNED_BYTE,
			s->vinf.text.raw
		);

		if (drop_slice){
			arcan_mem_free(s->vinf.text.raw);
			s->vinf.text.raw = NULL;
			s->vinf.text.s_raw = 0;
		}
	}

	backing->update_ts = arcan_timemillis();
	env->bind_texture(GL_TEXTURE_CUBE_MAP, 0);
	return true;
}

bool agp_slice_synch(
	struct agp_vstore* backing, size_t n_slices, struct agp_vstore** slices)
{
/* each slice, if backing store match, update based on backing type */
	if (backing->txmapped != TXSTATE_TEX3D && backing->txmapped != TXSTATE_CUBE)
		return false;

	if (backing->txmapped == TXSTATE_CUBE)
		return update_cube(backing, n_slices, slices);

	if (backing->txmapped == TXSTATE_TEX3D)
		return update_3dtex(backing, n_slices, slices);

	return false;
}

#ifndef GL_RGB16F
#define GL_RGB16F 0x881B
#endif

#ifndef GL_RGBA16F
#define GL_RGBA16F 0x881A
#endif

#ifndef GL_RGBA32F
#define GL_RGBA32F 0x8814
#endif

#ifndef GL_RGB32F
#define GL_RGB32F 0x8815
#endif

void agp_empty_vstoreext(struct agp_vstore* vs,
	size_t w, size_t h, enum vstore_hint hint)
{
	size_t bpp = 4;

	switch (hint){
	case VSTORE_HINT_LODEF:
		verbose_print("(%"PRIxPTR") empty fmt: lodef", (uintptr_t) vs);
		vs->vinf.text.d_fmt = GL_RGB5_A1;
		vs->vinf.text.s_fmt = GL_RGB;
		vs->vinf.text.s_type = GL_UNSIGNED_SHORT;
		bpp = 2;
	break;
	case VSTORE_HINT_LODEF_NOALPHA:
		verbose_print("(%"PRIxPTR") empty fmt: lodef-no-alpha", (uintptr_t) vs);
		vs->vinf.text.d_fmt = GL_RGB565;
		vs->vinf.text.s_fmt = GL_RGB;
		vs->vinf.text.s_type = GL_UNSIGNED_SHORT;
		bpp = 2;
	break;
	case VSTORE_HINT_NORMAL:
	case VSTORE_HINT_NORMAL_NOALPHA:
		verbose_print("(%"PRIxPTR") empty fmt: normal", (uintptr_t) vs);
		vs->vinf.text.d_fmt = GL_STORE_PIXEL_FORMAT;
	break;
#if !defined(GLES2) && !defined(GLES3)
	case VSTORE_HINT_HIDEF:
	case VSTORE_HINT_HIDEF_NOALPHA:
		vs->vinf.text.d_fmt = GL_RGB10_A2;
		vs->vinf.text.s_type = GL_UNSIGNED_INT_10_10_10_2;
		vs->vinf.text.s_fmt = GL_RGBA;
		bpp = 4;
	break;
	case VSTORE_HINT_F16:
		verbose_print("(%"PRIxPTR") empty fmt: half-float", (uintptr_t) vs);
		vs->vinf.text.d_fmt = GL_RGBA16F;
		vs->vinf.text.s_type = GL_HALF_FLOAT;
		vs->vinf.text.s_fmt = GL_RGBA;
		bpp = 8;
	break;
	case VSTORE_HINT_F16_NOALPHA:
		verbose_print("(%"PRIxPTR") empty fmt: half-float-no-alpha", (uintptr_t) vs);
		vs->vinf.text.d_fmt = GL_RGB16F;
		vs->vinf.text.s_type = GL_HALF_FLOAT;
		vs->vinf.text.s_fmt = GL_RGB;
		bpp = 8;
	break;
	case VSTORE_HINT_F32:
		verbose_print("(%"PRIxPTR") empty fmt: float", (uintptr_t) vs);
		vs->vinf.text.d_fmt = GL_RGB32F;
		vs->vinf.text.s_type = GL_FLOAT;
		vs->vinf.text.s_fmt = GL_RGBA;
		bpp = 16;
	break;
	case VSTORE_HINT_F32_NOALPHA:
		verbose_print("(%"PRIxPTR") empty fmt: float-no-alpha", (uintptr_t) vs);
		vs->vinf.text.d_fmt = GL_RGBA32F;
		vs->vinf.text.s_type = GL_FLOAT;
		vs->vinf.text.s_fmt = GL_RGB;
		bpp = 16;
	break;
#endif
	default:
	break;
	}

/* note, the local source format is always the native shmif_pixel so that we
 * don't break one of the many functions that was built on this assumption */
	vs->w = w;
	vs->h = h;
	vs->vinf.text.s_raw = w * h * bpp;
	vs->bpp = bpp;

	vs->vinf.text.s_raw = vs->bpp * vs->w * vs->h;

/* note that alloc_mem VBUFFER assumes RGBA so we'd need to initialize the
 * others differently for 'zero' state - this is incorrect but not that
 * important */
	vs->vinf.text.raw = arcan_alloc_mem(
		vs->vinf.text.s_raw,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE
	);

	vs->txmapped = TXSTATE_TEX2D;
	agp_update_vstore(vs, true);

	arcan_mem_free(vs->vinf.text.raw);
	vs->vinf.text.raw = 0;
	vs->vinf.text.s_raw = 0;
}

bool agp_rendertarget_swapstore(
	struct agp_rendertarget* tgt, struct agp_vstore* vstore)
{
	struct agp_fenv* env = agp_env();

/* this is only safe for swapping out the color store */
	if (!tgt || !vstore ||
		vstore->txmapped != TXSTATE_TEX2D || tgt->n_stores ||
		tgt->store->w != vstore->w || tgt->store->h != vstore->h)
		return false;

	if (tgt->store == vstore)
		return true;

	tgt->store = vstore;
	BIND_FRAMEBUFFER(tgt->fbo);

	env->framebuffer_texture_2d(GL_FRAMEBUFFER,
		GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, agp_resolve_texid(vstore), 0);

	BIND_FRAMEBUFFER(0);

	return true;
}

struct agp_rendertarget* agp_setup_rendertarget(
	struct agp_vstore* vstore, enum rendertarget_mode m)
{
	if (vstore->txmapped == TXSTATE_TEX3D)
		return NULL;

	struct agp_rendertarget* r = arcan_alloc_mem(sizeof(struct agp_rendertarget),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	r->store = vstore;
	r->mode = m;
	r->viewport[0] = 0;
	r->viewport[1] = 0;
	r->viewport[2] = vstore->w;
	r->viewport[3] = vstore->h;
	r->clearcol[0] = 0.05;
	r->clearcol[1] = 0.05;
	r->clearcol[2] = 0.05;
	r->clearcol[3] = 1.0;
	verbose_print("vstore (%"PRIxPTR") bound to rendertarget "
		"(%"PRIxPTR") in mode %d", (uintptr_t) vstore, (uintptr_t) r, (int) m);

	alloc_fbo(r, false);
	return r;
}

static void* lookup_fun(void* tag, const char* sym, bool req)
{
	dlerror();
	void* res = dlsym(RTLD_DEFAULT, sym);
	if (dlerror() != NULL && req){
		arcan_fatal("agp lookup(%s) failed, missing req. symbol.\n", sym);
	}
	return res;
}

static struct agp_fenv defenv;
struct agp_fenv* agp_alloc_fenv(
	void*(lookup)(void* tag, const char* sym, bool req), void* tag)
{
	struct agp_fenv* fenv = arcan_alloc_mem(
		sizeof(struct agp_fenv),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
	);

/* FIXME:
 * need a WRITELOCK flag to the allocation and calls to writelock afterwards */
	agp_glinit_fenv(fenv, lookup ? lookup : lookup_fun, tag);
	if (!agp_env())
		agp_setenv(fenv);

	return fenv;
}

void agp_dropenv(struct agp_fenv* env)
{
	if (!env || env->cookie != 0xfeedface){
		arcan_warning("agp_dropenv() - code issue: called on bad/broken fenv\n");
		return;
	}
	env->cookie = 0xdeadbeef;

	if (env != &defenv)
		arcan_mem_free(env);

	if (agp_env() == env)
		agp_setenv(NULL);
}

void agp_init()
{
	struct agp_fenv* env = agp_env();
/* platform layer has not set the function environment */
	if (!env){
		agp_glinit_fenv(&defenv, lookup_fun, NULL);
		env = &defenv;
	}

	env->enable(GL_SCISSOR_TEST);
	env->disable(GL_DEPTH_TEST);
	env->blend_func_separate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE,GL_ONE);
	env->front_face(GL_CW);
	env->cull_face(GL_BACK);

/* possibly not available in our context due to the low version, but try */
#ifdef GL_TEXTURE_CUBE_MAP_SEAMLESS
	env->enable(GL_TEXTURE_CUBE_MAP_SEAMLESS);
#endif

#if defined(GL_MULTISAMPLE) && !defined(HEADLESS_NOARCAN)
	if (arcan_video_display.msasamples)
		env->enable(GL_MULTISAMPLE);
#endif

	env->enable(GL_BLEND);
	env->clear_color(0.0, 0.0, 0.0, 1.0f);

/*
 * -- Removed as they were causing trouble with NVidia GPUs (white line outline
 * where triangles connect
 * glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);
 * glHint(GL_POLYGON_SMOOTH_HINT, GL_NICEST);
 * glEnable(GL_LINE_SMOOTH);
 * glEnable(GL_POLYGON_SMOOTH);
*/
}

void agp_vstore_copyreg(
	struct agp_vstore* restrict src, struct agp_vstore* restrict dst,
	size_t x1, size_t y1, size_t x2, size_t y2)
{
	if (!src || !dst || y1 > dst->h || y1 > src->h || x1 > dst->w || x1 > src->w)
		return;

	if (y2 > dst->h)
		y2 = dst->h;

	if (y2 > src->h)
		y2 = src->h;

	if (x2 > dst->w)
		x2 = dst->w;

	if (x2 > src->w)
		x2 = src->w;

	if (x2 <= x1 || y2 <= y1)
		return;

	size_t line_w = (x2 - x1) * sizeof(av_pixel);
	size_t dst_pitch = dst->vinf.text.stride / sizeof(av_pixel);
	size_t src_pitch = src->vinf.text.stride / sizeof(av_pixel);

	if (!dst_pitch)
		dst_pitch = src->h * sizeof(av_pixel);

	if (!src_pitch)
		src_pitch = src->w;

	for (size_t y = y1; y < y2; y++){
		memcpy(
			&dst->vinf.text.raw[y * dst_pitch + x1],
			&src->vinf.text.raw[y * src_pitch + x1], line_w
		);
	}
}

void agp_drop_rendertarget(struct agp_rendertarget* tgt)
{
	if (!tgt)
		return;

	struct agp_fenv* env = agp_env();

	if (tgt == active_rendertarget)
		agp_activate_rendertarget(NULL);

	env->delete_framebuffers(1,&tgt->fbo);
	env->delete_renderbuffers(1,&tgt->depth);
	tgt->fbo = GL_NONE;
	tgt->depth = GL_NONE;

/*
 * a special detail here is that we can't also be paranoid and null the active
 * vstores as they might be used externally, any changes to them would break
 * upstream (though that might be desire)
 */
	if (tgt->n_stores){
		verbose_print("dropping normal and shadow stores");
		for (size_t i = 0; i < tgt->n_stores; i++){
			agp_drop_vstore(tgt->stores[i]);
/*
 * might occur if the source is deleted while we are in an unflushed resize
 */
			if (tgt->shadow[i]){
				agp_drop_vstore(tgt->shadow[i]);
				arcan_mem_free(tgt->shadow[i]);
				tgt->shadow[i] = NULL;
			}
		}
		tgt->n_stores = 0;
		tgt->store->vinf.text.glid_proxy = NULL;
	}

	if (tgt->msaa_fbo != GL_NONE){
		drop_msaa(tgt);
	}

	verbose_print("(%"PRIxPTR") rendertarget gone", (uintptr_t) tgt);
	arcan_mem_free(tgt);
}

void agp_rendertarget_proxy(struct agp_rendertarget* tgt,
	bool (*proxy_state)(struct agp_rendertarget*, uintptr_t tag), uintptr_t tag)
{
/*
 * Store the proxy_state handler into the target, this will be called on
 * rendertarget enter/leave if the rendertarget vstore is not in a
 * disqualified state (shaders, txco based mapping, ...)
 */
	tgt->proxy_state = proxy_state;
	tgt->proxy_tag = tag;
}

void agp_activate_rendertarget(struct agp_rendertarget* tgt)
{
	verbose_print("set rendertarget: %"PRIxPTR, (uintptr_t)(void*)tgt);
	size_t w, h;
	struct agp_fenv* env = agp_env();
	if (!tgt){
		agp_blendstate(BLEND_NONE);
	}
	else if (!(tgt->mode & RENDERTARGET_RETAIN_ALPHA)){
		agp_blendstate(BLEND_NORMAL);
		env->blend_src_alpha = GL_ONE;
		env->blend_dst_alpha = GL_ONE;
	}
	else {
		agp_blendstate(BLEND_NORMAL);
		env->blend_src_alpha = GL_SRC_ALPHA;
		env->blend_dst_alpha = GL_ONE_MINUS_SRC_ALPHA;
	}

#ifdef HEADLESS_NOARCAN
	BIND_FRAMEBUFFER(tgt?tgt->fbo:0);
#else
	struct monitor_mode mode = platform_video_dimensions();

	if (!tgt){
		w = mode.width;
		h = mode.height;
		BIND_FRAMEBUFFER(0);
		env->clear_color(0.05, 0.05, 0.05, 1);
		env->scissor(0, 0, w, h);
		env->viewport(0, 0, w, h);
		verbose_print("no rendertarget");
	}
/* Query the rendertarget proxy and determine if it has taken control
 * over the context output (FBO0) or not. The Refcount test is also
 * important as other uses NEED the indirection */
	else {
		if (tgt->store->refcount < 2 &&
			tgt->proxy_state && tgt->proxy_state(tgt, tgt->proxy_tag)){
			verbose_print("rendertarget-proxy");
			BIND_FRAMEBUFFER(0);
			env->clear_color(tgt->clearcol[0],
				tgt->clearcol[1], tgt->clearcol[2], tgt->clearcol[3]);
			w = tgt->store->w;
			h = tgt->store->h;
		}
		else {
			verbose_print("rendertarget-fbo(%d)", (int)tgt->fbo);
			BIND_FRAMEBUFFER(tgt->fbo);
		}
		w = tgt->store->w;
		h = tgt->store->h;
		env->clear_color(tgt->clearcol[0],
			tgt->clearcol[1], tgt->clearcol[2], tgt->clearcol[3]);

		ssize_t* vp = tgt->viewport;
		env->scissor(vp[0], vp[1], vp[2], vp[3]);
		env->viewport(vp[0], vp[1], vp[2], vp[3]);

		verbose_print("clear(%f, %f, %f, %f)",
			tgt->clearcol[0], tgt->clearcol[1], tgt->clearcol[2], tgt->clearcol[3]);
	}

	verbose_print(
		"rendertarget (%"PRIxPTR") %zu*%zu activated", (uintptr_t) tgt, w, h);
#endif
	active_rendertarget = tgt;
}

void agp_rendertarget_dirty_reset(
	struct agp_rendertarget* src, struct agp_region* dst)
{
	for (size_t i = 0; i < src->dirty_region_decay && dst; i++){
		dst[i] = (struct agp_region){
			.x1 = 0, .y1 = 0,
			.x2 = src->store->w, .y2 = src->store->h
		};
	}

/* this assumes that we are double- buffered though the reality might be
 * more or less than that - so quick workaround now and do it for real a
 * bit later */
	src->dirty_region_decay = src->dirty_region;
	src->dirty_region = 0;
}

void agp_rendertarget_clear()
{
	verbose_print("");

	agp_env()->clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	agp_rendertarget_dirty(active_rendertarget, &(struct agp_region){});
}

void agp_pipeline_hint(enum pipeline_mode mode)
{
	struct agp_fenv* env = agp_env();
	switch (mode){
	case PIPELINE_2D:
		if (mode != env->mode){
			verbose_print("pipeline -> 2d");
			env->mode = mode;
			env->disable(GL_CULL_FACE);
			env->disable(GL_DEPTH_TEST);
			env->depth_mask(GL_FALSE);
#if !defined(GLES2) && !defined(GLES3)
			env->line_width(1.0);
			env->polygon_mode(GL_FRONT_AND_BACK, GL_FILL);
#endif
		}
	break;

	case PIPELINE_3D:
		if (mode != env->mode){
			verbose_print("pipeline -> 3d");
			env->mode = mode;
			env->enable(GL_DEPTH_TEST);
			env->depth_mask(GL_TRUE);
			env->clear(GL_DEPTH_BUFFER_BIT);
			env->model_flags = 0;
		}
	break;
	}
}

void agp_null_vstore(struct agp_vstore* store)
{
/* the txmapped property here might be problematic when it comes to
 * dealloc/restore on GPU switching or suspend/restore as it does not cover
 * cubemaps, 3d textures, ... */
	if (!store ||
		store->txmapped != TXSTATE_TEX2D || store->vinf.text.glid == GL_NONE)
		return;

	struct agp_fenv* env = agp_env();
	env->delete_textures(1, &store->vinf.text.glid);
	verbose_print("cleared (%"PRIxPTR"), dropped %u",
		(uintptr_t) store, store->vinf.text.glid);
	store->vinf.text.glid = GL_NONE;
	store->vinf.text.glid_proxy = NULL;

/* null out any pending PBOs as well, those get re-allocated on demand */
	if (GL_NONE != store->vinf.text.rid){
		env->delete_buffers(1, &store->vinf.text.rid);
		store->vinf.text.rid = GL_NONE;
	}

#ifndef GLES2
	if (GL_NONE != store->vinf.text.wid){
		env->delete_buffers(1, &store->vinf.text.wid);
		store->vinf.text.wid = GL_NONE;
	}
#endif
}

void agp_rendertarget_viewport(struct agp_rendertarget* tgt,
	ssize_t x1, ssize_t y1, ssize_t x2, ssize_t y2)
{
	if (!tgt || !tgt->store){
		arcan_warning("attempted resize on broken rendertarget\n");
		return;
	}

	tgt->viewport[0] = x1;
	tgt->viewport[1] = y1;
	tgt->viewport[2] = x2;
	tgt->viewport[3] = y2;
}

void agp_resize_rendertarget(
	struct agp_rendertarget* tgt, size_t neww, size_t newh)
{
	if (!tgt || !tgt->store){
		arcan_warning("attempted resize on broken rendertarget\n");
		return;
	}

/* same dimensions, no need to resize */
	if (tgt->store->w == neww && tgt->store->h == newh)
		return;

	verbose_print(
		"resize (%"PRIxPTR") to %zu*%zu", (uintptr_t) tgt, neww, newh);

	struct agp_fenv* env = agp_env();

/*
 * If the rendertarget is using multi-buffered (direct- to display
 * scanout, shared to other processes and so on) we can't actually
 * resize the current stores right away.
 *
 * Thus we move them to a 'shadow store' that gets flushed out as
 * we swap, with possible visual corruption should we get OOM at
 * that point.
 */
	tgt->store->w = neww;
	tgt->store->h = newh;
	tgt->viewport[0] = 0;
	tgt->viewport[1] = 0;
	tgt->viewport[2] = neww;
	tgt->viewport[3] = newh;
	tgt->rz_ack = true;

	if (tgt->n_stores){
		for (size_t i = 0; i < tgt->n_stores; i++){
/*
 * Multiple resizes in short succession with pending buffers still might
 * possibly lead to bad frame contents being shown, experimentation needed.
 */
			if (tgt->shadow[i]){
				verbose_print(
					"in-rz shadow store %zu:%zu", i, tgt->shadow[i]->vinf.text.glid);
				if (tgt->alloc){
					tgt->alloc(tgt, tgt->shadow[i], RTGT_ALLOC_FREE, tgt->alloc_tag);
				}
				else
					erase_store(tgt->shadow[i]);

				arcan_mem_free(tgt->shadow[i]);
				tgt->shadow[i] = NULL;
			}

/*
 * Set the old as shadow now
 */
			tgt->shadow[i] = tgt->stores[i];
			tgt->stores[i] = NULL;
		}

/* allocate new ones from fresh index */
		setup_stores(tgt);
		tgt->store->vinf.text.glid_proxy = &tgt->stores[0]->vinf.text.glid;
		verbose_print(
			"shadows set, new proxy: %u", tgt->stores[0]->vinf.text.glid);
	}
	else {
		erase_store(tgt->store);
		agp_empty_vstore(tgt->store, neww, newh);
	}

/* we inplace- modify, want the refcounter intact */
	env->delete_framebuffers(1,&tgt->fbo);
	env->delete_renderbuffers(1,&tgt->depth);
	tgt->fbo = GL_NONE;
	tgt->depth = GL_NONE;

/* and also rebuild the containing fbo */
	alloc_fbo(tgt, false);
}

void agp_activate_vstore_multi(struct agp_vstore** backing, size_t n)
{
	char buf[] = {'m', 'a', 'p', '_', 't', 'u', 0, 0, 0};
	struct agp_fenv* env = agp_env();
	verbose_print("vstore-set-multi: %zu", n);

	for (int i = 0; i < n && i < 99; i++){
		env->active_texture(GL_TEXTURE0 + i);
		env->bind_texture(GL_TEXTURE_2D, agp_resolve_texid(backing[i]));
		if (i < 10)
			buf[6] = '0' + i;
		else{
			buf[6] = '0' + (i / 10);
			buf[7] = '0' + (i % 10);
		}
		agp_shader_forceunif(buf, shdrint, &i);
	}

	env->active_texture(GL_TEXTURE0);
}

void agp_update_vstore(struct agp_vstore* s, bool copy)
{
	struct agp_fenv* env = agp_env();
	if (s->txmapped == TXSTATE_OFF)
		return;

	verbose_print(
		"update vstore (%"PRIxPTR"), copy: %d", (uintptr_t) s, (int) copy);
	FLAG_DIRTY();

	if (!copy)
		env->bind_texture(GL_TEXTURE_2D, s->vinf.text.glid);
	else{
		if (GL_NONE == s->vinf.text.glid)
			env->gen_textures(1, &s->vinf.text.glid);

/* for the launch_resume and resize states, were we'd push a new
 * update	but have multiple references */
		if (s->refcount == 0)
			s->refcount = 1;

		env->bind_texture(GL_TEXTURE_2D, s->vinf.text.glid);
	}
	s->vinf.text.glid_proxy = NULL;

	env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,
		s->txu == ARCAN_VTEX_REPEAT ? GL_REPEAT : GL_CLAMP_TO_EDGE);
	env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,
		s->txv == ARCAN_VTEX_REPEAT ? GL_REPEAT : GL_CLAMP_TO_EDGE);

	int filtermode = s->filtermode & (~ARCAN_VFILTER_MIPMAP);
	bool mipmap = s->filtermode & ARCAN_VFILTER_MIPMAP;

/*
 * Mipmapping still misses the option to manually define mipmap levels
 */
	if (copy){
#ifndef GL_GENERATE_MIPMAP
		if (mipmap)
			env->generate_mipmap(GL_TEXTURE_2D);
#else
			env->tex_param_i(GL_TEXTURE_2D, GL_GENERATE_MIPMAP, mipmap);
#endif
	}

	switch (filtermode){
	case ARCAN_VFILTER_NONE:
		verbose_print("filter(none)");
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	break;

	case ARCAN_VFILTER_LINEAR:
		verbose_print("filter(linear)");
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	break;

	case ARCAN_VFILTER_BILINEAR:
		verbose_print("filter(bilinear)");
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	break;

	case ARCAN_VFILTER_TRILINEAR:
		verbose_print("filter(trilinear), mipmap: %d", (int) mipmap);
		if (mipmap){
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
				GL_LINEAR_MIPMAP_LINEAR);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		}
		else {
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		}
	break;
	}

	if (copy){
#if !defined(GLES2) && !defined(GLES3)
		env->pixel_storei(GL_UNPACK_ROW_LENGTH, 0);
#endif
		s->update_ts = arcan_timemillis();
		if (s->txmapped == TXSTATE_DEPTH)
			env->tex_image_2d(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, s->w, s->h, 0,
				GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, 0);
		else
			env->tex_image_2d(GL_TEXTURE_2D, 0,
				s->vinf.text.d_fmt ? s->vinf.text.d_fmt : GL_STORE_PIXEL_FORMAT,
				s->w, s->h, 0,
				s->vinf.text.s_fmt ? s->vinf.text.s_fmt : GL_PIXEL_FORMAT,
				s->vinf.text.s_type ? s->vinf.text.s_type : GL_UNSIGNED_BYTE,
				s->vinf.text.raw
			);
		verbose_print("copied");
	}

#ifndef HEADLESS_NOARCAN
	if (arcan_video_display.conservative){
		arcan_mem_free(s->vinf.text.raw);
		s->vinf.text.raw = NULL;
		s->vinf.text.s_raw = 0;
	}
#endif

	env->bind_texture(GL_TEXTURE_2D, 0);
}

void agp_prepare_stencil()
{
/* toggle stenciling, reset into zero, draw parent bounding area to
 * stencil only,redraw parent into stencil, draw new object
 * then disable stencil. */
	struct agp_fenv* env = agp_env();
	env->enable(GL_STENCIL_TEST);
	env->disable(GL_BLEND);
	env->clear_stencil(0);
	env->clear(GL_STENCIL_BUFFER_BIT);
	env->color_mask(0, 0, 0, 0);
	env->stencil_func(GL_ALWAYS, 1, 1);
	env->stencil_op(GL_REPLACE, GL_REPLACE, GL_REPLACE);
}

void agp_activate_stencil()
{
	struct agp_fenv* env = agp_env();
	env->color_mask(1, 1, 1, 1);
	env->stencil_func(GL_EQUAL, 1, 1);
	env->stencil_op(GL_KEEP, GL_KEEP, GL_KEEP);
}

void agp_disable_stencil()
{
	agp_env()->disable(GL_STENCIL_TEST);
}

static float ident[] = {
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 1.0, 0.0,
	0.0, 0.0, 0.0, 1.0
};

void agp_blendstate(enum arcan_blendfunc mode)
{
	struct agp_fenv* env = agp_env();

	if (mode == BLEND_NONE){
		env->disable(GL_BLEND);
		return;
	}

	env->enable(GL_BLEND);

	switch (mode){
	case BLEND_NONE:
	case BLEND_FORCE:
	case BLEND_NORMAL:
		verbose_print("blend-normal/force/none");
		env->blend_equation(GL_FUNC_ADD);
		env->blend_func_separate(
			GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
			env->blend_src_alpha, env->blend_dst_alpha
		);
	break;

	case BLEND_MULTIPLY:
		verbose_print("blend-multiply");
		env->blend_equation(GL_FUNC_ADD);
		env->blend_func_separate(
			GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA,
			env->blend_src_alpha, env->blend_dst_alpha
		);
	break;

	case BLEND_PREMUL:
		verbose_print("blend-premultiplied");
		env->blend_equation(GL_FUNC_ADD);
		env->blend_func_separate(
			GL_ONE, GL_ONE_MINUS_SRC_ALPHA,
			env->blend_src_alpha, env->blend_dst_alpha
		);
	break;

	case BLEND_ADD:
		verbose_print("blend-add");
		env->blend_equation(GL_FUNC_ADD);
		env->blend_func_separate(
			GL_ONE, GL_ONE,
			env->blend_src_alpha, env->blend_dst_alpha
		);
	break;

	case BLEND_SUB:
		verbose_print("blend-sub");
		env->blend_equation(GL_FUNC_SUBTRACT);
		env->blend_func_separate(
			GL_ONE, GL_ONE_MINUS_SRC_ALPHA,
			env->blend_src_alpha, env->blend_dst_alpha);

	default:
	break;
	}
}

void agp_draw_vobj(
	float x1, float y1, float x2, float y2,
	const float* txcos, const float* model)
{
	GLfloat verts[] = {
		x1, y1,
		x2, y1,
		x2, y2,
		x1, y2
	};

	verbose_print("draw-vobj(%f,%f-%f,%f)", x1, y1, x2, y2);
	bool settex = false;
	struct agp_fenv* env = agp_env();

	agp_shader_envv(MODELVIEW_MATR,
		model ? (void*) model : ident, sizeof(float) * 16);

/* projection, scissor is set when activating rendertarget */
	GLint attrindv = agp_shader_vattribute_loc(ATTRIBUTE_VERTEX);
	GLint attrindt = agp_shader_vattribute_loc(ATTRIBUTE_TEXCORD0);

	if (attrindv != -1){
		env->enable_vertex_attrarray(attrindv);
		env->vertex_attrpointer(attrindv, 2, GL_FLOAT, GL_FALSE, 0, verts);

		if (txcos && attrindt != -1){
			settex = true;
			env->enable_vertex_attrarray(attrindt);
			env->vertex_attrpointer(attrindt, 2, GL_FLOAT, GL_FALSE, 0, txcos);
		}

		env->draw_arrays(GL_TRIANGLE_FAN, 0, 4);

		if (settex)
			env->disable_vertex_attrarray(attrindt);

		env->disable_vertex_attrarray(attrindv);
	}

	agp_rendertarget_dirty(active_rendertarget, &(struct agp_region){});
}

static void toggle_debugstates(float* modelview)
{
	struct agp_fenv* env = agp_env();
	verbose_print("3d-debug");

	if (modelview){
		float white[3] = {1.0, 1.0, 1.0};
		env->depth_mask(GL_FALSE);
		env->disable(GL_DEPTH_TEST);
		env->enable_vertex_attrarray(ATTRIBUTE_VERTEX);
		agp_shader_activate(agp_default_shader(COLOR_2D));
		agp_shader_envv(MODELVIEW_MATR, modelview, sizeof(float) * 16);
		agp_shader_forceunif("obj_col", shdrvec3, (void*) white);
	}
	else{
		agp_shader_activate(agp_default_shader(COLOR_2D));
		env->enable(GL_DEPTH_TEST);
		env->depth_mask(GL_TRUE);
		env->disable_vertex_attrarray(ATTRIBUTE_VERTEX);
	}
}

void agp_rendertarget_ids(struct agp_rendertarget* rtgt, uintptr_t* tgt,
	uintptr_t* col, uintptr_t* depth)
{
	if (tgt)
		*tgt = rtgt->fbo;
	if (col)
		*col = agp_resolve_texid(rtgt->store);
	if (depth)
		*depth = rtgt->depth;
}

void agp_render_options(struct agp_render_options opts)
{
	struct agp_fenv* env = agp_env();
	env->line_width(opts.line_width);
}

static void setup_transfer(struct agp_mesh_store* base, enum agp_mesh_flags fl)
{
	struct agp_fenv* env = agp_env();
	int attribs[] = {
		agp_shader_vattribute_loc(ATTRIBUTE_VERTEX),
		agp_shader_vattribute_loc(ATTRIBUTE_NORMAL),
		agp_shader_vattribute_loc(ATTRIBUTE_TEXCORD0),
		agp_shader_vattribute_loc(ATTRIBUTE_COLOR),
		agp_shader_vattribute_loc(ATTRIBUTE_TEXCORD1),
		agp_shader_vattribute_loc(ATTRIBUTE_TANGENT),
		agp_shader_vattribute_loc(ATTRIBUTE_BITANGENT),
		agp_shader_vattribute_loc(ATTRIBUTE_JOINTS0),
		agp_shader_vattribute_loc(ATTRIBUTE_WEIGHTS1)
	};
	if (attribs[0] == -1)
		return;
	else {
		verbose_print("vertex");
		env->enable_vertex_attrarray(attribs[0]);
		env->vertex_attrpointer(attribs[0],
			base->vertex_size, GL_FLOAT, GL_FALSE, 0, base->verts);
	}

	if (attribs[1] != -1 && base->normals){
		verbose_print("normals");
		env->enable_vertex_attrarray(attribs[1]);
		env->vertex_attrpointer(attribs[1], 3, GL_FLOAT, GL_FALSE,0, base->normals);
	}
	else
		attribs[1] = -1;

	if (attribs[2] != -1 && base->txcos){
		verbose_print("texture-coordinates");
		env->enable_vertex_attrarray(attribs[2]);
		env->vertex_attrpointer(attribs[2], 2, GL_FLOAT, GL_FALSE, 0, base->txcos);
	}
	else
		attribs[2] = -1;

	if (attribs[3] != -1 && base->colors){
		verbose_print("colors");
		env->enable_vertex_attrarray(attribs[3]);
		env->vertex_attrpointer(attribs[3], 3, GL_FLOAT, GL_FALSE, 0, base->colors);
	}
	else
		attribs[3] = -1;

	if (attribs[4] != -1 && base->txcos2){
		verbose_print("texture-coordinates-alt");
		env->enable_vertex_attrarray(attribs[4]);
		env->vertex_attrpointer(attribs[4], 2, GL_FLOAT, GL_FALSE, 0, base->txcos2);
	}
	else
		attribs[4] = -1;

	if (attribs[5] != -1 && base->tangents){
		verbose_print("tangents");
		env->enable_vertex_attrarray(attribs[5]);
		env->vertex_attrpointer(attribs[5],4,GL_FLOAT,GL_FALSE,0,base->tangents);
	}
	else
		attribs[5] = -1;

	if (attribs[6] != -1 && base->bitangents){
		verbose_print("bitangents");
		env->enable_vertex_attrarray(attribs[6]);
		env->vertex_attrpointer(attribs[6],4,GL_FLOAT,GL_FALSE,0,base->bitangents);
	}
	else
		attribs[6] = -1;

	if (attribs[7] != -1 && base->weights){
		verbose_print("vertex-weights");
		env->enable_vertex_attrarray(attribs[7]);
		env->vertex_attrpointer(attribs[7], 4, GL_FLOAT, GL_FALSE, 0,base->weights);
	}
	else
		attribs[7] = -1;

	if (attribs[8] != -1 && base->joints){
		verbose_print("vertex-joints");
		env->enable_vertex_attrarray(attribs[8]);
		env->vertex_iattrpointer(attribs[8], 4, GL_UNSIGNED_SHORT, 0, base->joints);
	}
	else
		attribs[8] = -1;

	if (base->type == AGP_MESH_TRISOUP){
		if (base->indices){
			if (!base->validated){
				static bool warned;
				for (size_t i = 0; i < base->n_indices; i++){
					if (base->indices[i] > base->n_vertices){
						if (!warned){
							arcan_warning("agp_submit_mesh(), " "refusing mesh with OOB indices "
								"(%zu=>%zu/%zu\n", i, base->indices[i], base->n_vertices);
							warned = true;
						}
						return;
					}
				}
				base->validated = true;
			}
			verbose_print(
				"triangle-soup(indexed, %u indices)", (unsigned)base->n_indices);
			env->draw_elements(GL_TRIANGLES,
				base->n_indices, GL_UNSIGNED_INT, base->indices);
		}
		else{
			verbose_print(
				"triangle-soup(vertices, %u vertices)", (unsigned)base->n_vertices);
			env->draw_arrays(GL_TRIANGLES, 0, base->n_vertices);
		}
	}
	else if (base->type == AGP_MESH_POINTCLOUD){
		verbose_print("point-cloud(%u points)", (unsigned)base->n_vertices);
		env->enable(GL_VERTEX_PROGRAM_POINT_SIZE);
		env->draw_arrays(GL_POINTS, 0, base->n_vertices);
		env->disable(GL_VERTEX_PROGRAM_POINT_SIZE);
	}

	for (size_t i = 0; i < sizeof(attribs) / sizeof(attribs[0]); i++)
		if (attribs[i] != -1)
			env->disable_vertex_attrarray(attribs[i]);
}

void agp_drop_vstore(struct agp_vstore* s)
{
	if (!s || s->vinf.text.glid == GL_NONE)
		return;
	struct agp_fenv* env = agp_env();

	if (s->vinf.text.tag)
		platform_video_map_handle(s, -1);

	if (s->vinf.text.kind == STORAGE_TEXT){
		arcan_mem_free(s->vinf.text.source);
	}
	else if (s->vinf.text.kind == STORAGE_TPACK){
		arcan_mem_free(s->vinf.text.tpack.buf);
	}
	if (s->vinf.text.kind == STORAGE_TEXTARRAY){
		char** work = s->vinf.text.source_arr;
		while(*work){
			arcan_mem_free(*work);
			work++;
		}
		arcan_mem_free(s->vinf.text.source_arr);
	}

	env->delete_textures(1, &s->vinf.text.glid);
	s->vinf.text.glid = GL_NONE;

	if (GL_NONE != s->vinf.text.rid){
		env->delete_buffers(1, &s->vinf.text.rid);
		s->vinf.text.rid = GL_NONE;
	}

#ifndef GLES2
	if (GL_NONE != s->vinf.text.wid){
		env->delete_buffers(1, &s->vinf.text.wid);
		s->vinf.text.wid = GL_NONE;
	}
#endif

	verbose_print("dropped (%"PRIxPTR")", (uintptr_t) s);
	memset(s, '\0', sizeof(struct agp_vstore));
}

static void setup_culling(struct agp_mesh_store* base, enum agp_mesh_flags fl)
{
	struct agp_fenv* env = agp_env();

	if (fl & MESH_FACING_NODEPTH || base->nodepth){
		env->disable(GL_DEPTH_TEST);
	}
	else{
		switch (base->depth_func){
		case AGP_DEPTH_LESS: env->depth_func(GL_LESS); break;
		case AGP_DEPTH_LESSEQUAL: env->depth_func(GL_LEQUAL); break;
		case AGP_DEPTH_GREATER: env->depth_func(GL_GREATER); break;
		case AGP_DEPTH_GREATEREQUAL: env->depth_func(GL_GEQUAL); break;
		case AGP_DEPTH_EQUAL: env->depth_func(GL_EQUAL); break;
		case AGP_DEPTH_NOTEQUAL: env->depth_func(GL_NOTEQUAL); break;
		case AGP_DEPTH_ALWAYS: env->depth_func(GL_ALWAYS); break;
		case AGP_DETPH_NEVER: env->depth_func(GL_NEVER); break;
		default:
			env->depth_func(GL_LESS);
		break;
		}

		env->enable(GL_DEPTH_TEST);
	}

	if (fl & MESH_FACING_BOTH){
		if ((fl & MESH_FACING_BACK) == 0){
			env->enable(GL_CULL_FACE);
			env->cull_face(GL_BACK);
		}
		else if ((fl & MESH_FACING_FRONT) == 0){
			env->enable(GL_CULL_FACE);
			env->cull_face(GL_FRONT);
		}
		else
			env->disable(GL_CULL_FACE);
	}
	verbose_print("depth func: %d, flags: %d", base->depth_func, fl);
}

void agp_submit_mesh(struct agp_mesh_store* base, enum agp_mesh_flags fl)
{
/* make sure the current program actually uses the attributes from the mesh */
	struct agp_fenv* env = agp_env();

/* ignore for now */
	if (base->dirty)
		base->dirty = false;

	if (fl != env->model_flags){
		if (fl & MESH_FILL_LINE){
			if (fl == MESH_FACING_BOTH){
#if !defined(GLES2) && !defined(GLES3)
				env->polygon_mode(GL_FRONT_AND_BACK, GL_LINE);
#endif
			}
			else {
/* proper wireframe with culling requires higher level GL, barycentric coords
 * or Z prepass and then depth testing */
				setup_culling(base, fl);
#if !defined(GLES2) && !defined(GLES3)
				env->polygon_mode(GL_FRONT_AND_BACK, GL_FILL);
				env->color_mask(false, false, false, false);
				setup_transfer(base, fl);

				env->polygon_mode(GL_FRONT_AND_BACK, GL_LINE);
				env->color_mask(true, true, true, true);
				setup_transfer(base, fl);
				env->polygon_mode(GL_FRONT_AND_BACK, GL_FILL);
#else
/* no wireframe support for GLES */
#endif
				return;
			}
		}
		else{
#if !defined(GLES2) && !defined(GLES3)
			env->polygon_mode(GL_FRONT_AND_BACK, GL_FILL);
#endif
			setup_culling(base, fl);
		}

		env->model_flags = fl;
	}

	setup_transfer(base, fl);
	agp_rendertarget_dirty(active_rendertarget, &(struct agp_region){});
}

/*
 * mark that the contents of the mesh has changed dynamically
 * and that possible GPU- side cache might need to be updated.
 */
void agp_invalidate_mesh(struct agp_mesh_store* bs)
{
	verbose_print("(%"PRIxPTR")", (uintptr_t) bs);
}

void agp_activate_vstore(struct agp_vstore* s)
{
	struct agp_fenv* env = agp_env();
	switch (s->txmapped){
	case TXSTATE_OFF:
		return;
	break;
	case TXSTATE_CUBE:
		env->last_store_mode = GL_TEXTURE_CUBE_MAP;
	break;
	case TXSTATE_TEX3D:
		env->last_store_mode = GL_TEXTURE_3D;
	break;
	case TXSTATE_TEX2D:
		env->last_store_mode = GL_TEXTURE_2D;
	break;
	case TXSTATE_TPACK:
		verbose_print("tpack support incomplete (atlas-sample)\n");
		return;
	break;
	}

	verbose_print("(%"PRIxPTR") vstore, glid: %u",
		(uintptr_t) s, (unsigned) agp_resolve_texid(s));
	env->bind_texture(env->last_store_mode, agp_resolve_texid(s));
}

void agp_deactivate_vstore()
{
	verbose_print("");
	agp_env()->bind_texture(GL_TEXTURE_2D, 0);
}

void agp_rendertarget_clearcolor(
	struct agp_rendertarget* tgt, float r, float g, float b, float a)
{
	if (!tgt)
		return;
	tgt->clearcol[0] = r;
	tgt->clearcol[1] = g;
	tgt->clearcol[2] = b;
	tgt->clearcol[3] = a;
}

void agp_drop_mesh(struct agp_mesh_store* s)
{
	if (!s)
		return;

	uintptr_t targets[] = {
		(uintptr_t) s->verts, (uintptr_t) s->txcos,
		(uintptr_t) s->txcos2, (uintptr_t) s->normals,
		(uintptr_t) s->colors, (uintptr_t) s->tangents,
		(uintptr_t) s->bitangents, (uintptr_t) s->weights,
		(uintptr_t) s->weights, (uintptr_t) s->joints,
		(uintptr_t) s->indices
	};

	if (s->shared_buffer != NULL){
		arcan_mem_free(s->shared_buffer);
		uintptr_t base = (uintptr_t) s->shared_buffer;
		uintptr_t end = base + s->shared_buffer_sz;

		for (size_t i = 0; i < COUNT_OF(targets); i++){
			if (targets[i] != (uintptr_t) NULL &&
				(targets[i] < base || targets[i] >= end)){
				arcan_mem_free((void*)targets[i]);
			}
		}
	}
	else{
		for (size_t i = 0; i < COUNT_OF(targets); i++){
			if (targets[i] != (uintptr_t) NULL){
				arcan_mem_free((void*)targets[i]);
			}
		}
	}

	verbose_print("(%"PRIxPTR")", (uintptr_t) s);
	memset(s, '\0', sizeof(struct agp_mesh_store));
}

void agp_save_output(size_t w, size_t h, av_pixel* dst, size_t dsz)
{
	struct agp_fenv* env = agp_env();
	env->read_buffer(GL_FRONT);
	assert(w * h * sizeof(av_pixel) == dsz);

	verbose_print("");
	env->read_pixels(0, 0, w, h, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, dst);
}

bool agp_status_ok(const char** msg)
{
	struct agp_fenv* env = agp_env();
	return env->reset_status() == 0;
}

unsigned agp_resolve_texid(struct agp_vstore* vs)
{
	if (vs->vinf.text.glid_proxy)
		return *vs->vinf.text.glid_proxy;
	else
		return vs->vinf.text.glid;
}

bool agp_accelerated()
{
	return false;
}
