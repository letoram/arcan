/*
 * Copyright 2014-2017, Björn Ståhl
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

#include "glfun.h"

#include "../video_platform.h"
#include PLATFORM_HEADER

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

/*
 * Workaround for missing GL_DRAW_FRAMEBUFFER_BINDING
 */
#if defined(GLES2) || defined(GLES3)
	#define BIND_FRAMEBUFFER(X) do { st_last_fbo = (X);\
		env->bind_framebuffer(GL_FRAMEBUFFER, (X)); } while(0)
GLuint st_last_fbo;
#else
	#define BIND_FRAMEBUFFER(X) env->bind_framebuffer(GL_FRAMEBUFFER, (X))
#endif

struct agp_rendertarget
{
	GLuint fbo;
	GLuint depth;

	GLuint msaa_fbo;
	GLuint msaa_color;
	GLuint msaa_depth;

	float clearcol[4];

	enum rendertarget_mode mode;
	struct agp_vstore* store;

	bool front_active;
	struct agp_vstore* store_back;
};

unsigned agp_rendertarget_swap(struct agp_rendertarget* dst)
{
	struct agp_fenv* env = agp_env();

	if (!dst || !dst->store || !dst->store_back){
		return dst->store ? dst->store->vinf.text.glid : 0;
	}

	GLint cfbo;

/* switch rendertarget if we're not already there */
#if defined(GLES2) || defined(GLES3)
	cfbo = st_last_fbo;
#else
	env->get_integer_v(GL_DRAW_FRAMEBUFFER_BINDING, &cfbo);
#endif

	if (dst->fbo != cfbo)
		BIND_FRAMEBUFFER(dst->fbo);

/* we return the one that was used up to this point */
	int rid = dst->front_active ?
		(dst->store_back->vinf.text.glid) :
		(dst->store->vinf.text.glid);

/* and attach the one that was not used */
	int did = dst->front_active ?
		(dst->store->vinf.text.glid) :
		(dst->store_back->vinf.text.glid);

	dst->front_active = !dst->front_active;
	env->framebuffer_texture_2d(GL_FRAMEBUFFER,
		GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,did, 0);

/* and switch back to the old rendertarget */
	if (dst->fbo != cfbo)
		BIND_FRAMEBUFFER(cfbo);

	return rid;
}

static void drop_msaa(struct agp_rendertarget* dst)
{
	struct agp_fenv* env = agp_env();
	env->delete_framebuffers(1,&dst->msaa_fbo);
	env->delete_renderbuffers(1,&dst->msaa_depth);
	env->delete_textures(1,&dst->msaa_color);
	dst->msaa_fbo = dst->msaa_depth = dst->msaa_color = GL_NONE;
}

#ifndef GL_TEXTURE_2D_MULTISAMPLE
#define GL_TEXTURE_2D_MULTISAMPLE 0x9100
#endif

static bool alloc_fbo(struct agp_rendertarget* dst, bool retry)
{
	struct agp_fenv* env = agp_env();
	int mode = dst->mode & (~RENDERTARGET_DOUBLEBUFFER);

/* recall this is actually OpenGL 3.0, so it's not at all certain
 * that we will actually get it. Then we fallback 'gracefully' */
	if (!env->renderbuffer_storage_multisample || !env->tex_image_2d_multisample){
		dst->mode = (dst->mode & ~RENDERTARGET_MSAA);
		dst->mode |= RENDERTARGET_COLOR_DEPTH_STENCIL;
	}

/*
 * we need two FBOs, one for the MSAA pass and one to resolve into
 */
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

	env->gen_framebuffers(1, &dst->fbo);

/* need both stencil and depth buffer, but we don't need the data from them */
	BIND_FRAMEBUFFER(dst->fbo);

	if (mode > RENDERTARGET_DEPTH)
	{

		env->framebuffer_texture_2d(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			GL_TEXTURE_2D, dst->store->vinf.text.glid, 0);

/* need a Z buffer in the offscreen rendering but don't want
 * bo store it, so setup a renderbuffer */
		if (mode > RENDERTARGET_COLOR){
			env->gen_renderbuffers(1, &dst->depth);

/* could use GL_DEPTH_COMPONENT only if we'd know that there
 * wouldn't be any clipping in the active rendertarget */
			if (!retry){
				env->bind_renderbuffer(GL_RENDERBUFFER, dst->depth);
				env->renderbuffer_storage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8,
					dst->store->w, dst->store->h);
				env->bind_renderbuffer(GL_RENDERBUFFER, 0);
				env->framebuffer_renderbuffer(GL_FRAMEBUFFER,
					GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, dst->depth);
			}
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
			env->delete_framebuffers(1,&dst->fbo);
		if (dst->depth != GL_NONE)
			env->delete_renderbuffers(1,&dst->depth);

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
/*
 * though the d_fmt may differ from s_fmt here, we treat s_fmt and
 */
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
	switch (hint){
	case VSTORE_HINT_LODEF:
		vs->vinf.text.d_fmt = GL_UNSIGNED_SHORT_5_6_5;
		vs->vinf.text.s_fmt = GL_RGBA;
		vs->vinf.text.s_type = GL_UNSIGNED_SHORT;
	break;
	case VSTORE_HINT_LODEF_NOALPHA:
		vs->vinf.text.d_fmt = GL_UNSIGNED_SHORT_4_4_4_4;
		vs->vinf.text.s_fmt = GL_RGB;
		vs->vinf.text.s_type = GL_UNSIGNED_SHORT;
	break;
	case VSTORE_HINT_NORMAL:
	case VSTORE_HINT_NORMAL_NOALPHA:
		vs->vinf.text.d_fmt = GL_STORE_PIXEL_FORMAT;
	break;
	case VSTORE_HINT_HIDEF:
	case VSTORE_HINT_HIDEF_NOALPHA:
		vs->vinf.text.d_fmt = GL_UNSIGNED_INT_10_10_10_2;
		vs->vinf.text.s_type = GL_UNSIGNED_INT_10_10_10_2;
		vs->vinf.text.s_fmt = GL_UNSIGNED_INT;
		vs->vinf.text.s_raw = sizeof(unsigned) * w * h * 4;
	break;
	case VSTORE_HINT_F16:
		vs->vinf.text.d_fmt = GL_RGB16F;
		vs->vinf.text.s_type = GL_FLOAT;
		vs->vinf.text.s_raw = w * h * sizeof(float) * 4;
	break;
	case VSTORE_HINT_F16_NOALPHA:
		vs->vinf.text.d_fmt = GL_RGBA16F;
		vs->vinf.text.s_type = GL_FLOAT;
		vs->vinf.text.s_raw = w * h * sizeof(float) * 4;
	break;
	case VSTORE_HINT_F32:
		vs->vinf.text.d_fmt = GL_RGBA32F;
		vs->vinf.text.s_type = GL_FLOAT;
		vs->vinf.text.s_raw = w * h * sizeof(float) * 4;
	break;
	case VSTORE_HINT_F32_NOALPHA:
		vs->vinf.text.d_fmt = GL_RGB32F;
		vs->vinf.text.s_type = GL_FLOAT;
		vs->vinf.text.s_raw = w * h * sizeof(float) * 4;
	break;
	default:
	break;
	}

/* note, the local source format is always the native shmif_pixel so that we
 * don't break one of the many functions that was built on this assumption */
	vs->w = w;
	vs->h = h;
	vs->bpp = sizeof(av_pixel);
	vs->vinf.text.s_raw = vs->bpp * vs->w * vs->h;
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

struct agp_rendertarget* agp_setup_rendertarget(
	struct agp_vstore* vstore, enum rendertarget_mode m)
{
	struct agp_rendertarget* r = arcan_alloc_mem(sizeof(struct agp_rendertarget),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	r->store = vstore;
	r->mode = m;
	r->clearcol[3] = 1.0;

/* need this tracking because there's no external memory management for _back */
	r->front_active = true;

	if (m & RENDERTARGET_DOUBLEBUFFER){
		r->store_back = arcan_alloc_mem(sizeof(struct agp_vstore),
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		r->store_back->vinf.text.s_fmt = vstore->vinf.text.s_fmt;
		r->store_back->vinf.text.d_fmt = vstore->vinf.text.d_fmt;
		agp_empty_vstore(r->store_back, vstore->w, vstore->h);
	}

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

void agp_drop_rendertarget(struct agp_rendertarget* tgt)
{
	if (!tgt)
		return;
	struct agp_fenv* env = agp_env();

	env->delete_framebuffers(1,&tgt->fbo);
	env->delete_renderbuffers(1,&tgt->depth);
	tgt->fbo = GL_NONE;
	tgt->depth = GL_NONE;

	if (tgt->msaa_fbo != GL_NONE){
		drop_msaa(tgt);
	}

	arcan_mem_free(tgt);
}

void agp_activate_rendertarget(struct agp_rendertarget* tgt)
{
	size_t w, h;
	struct agp_fenv* env = agp_env();
	if (!tgt || !(tgt->mode & RENDERTARGET_RETAIN_ALPHA)){
		env->blend_src_alpha = GL_ONE;
		env->blend_dst_alpha = GL_ONE;
		agp_blendstate(BLEND_NORMAL);
	}
	else {
		env->blend_src_alpha = GL_SRC_ALPHA;
		env->blend_dst_alpha = GL_ONE_MINUS_SRC_ALPHA;
	}
	agp_blendstate(BLEND_NORMAL);

#ifdef HEADLESS_NOARCAN
	BIND_FRAMEBUFFER(tgt?tgt->fbo:0);
#else
	struct monitor_mode mode = platform_video_dimensions();

	if (!tgt){
		w = mode.width;
		h = mode.height;
		BIND_FRAMEBUFFER(0);
		env->clear_color(0, 0, 0, 1);
	}
	else {
		w = tgt->store->w;
		h = tgt->store->h;
		BIND_FRAMEBUFFER(tgt->fbo);
		env->clear_color(tgt->clearcol[0],
			tgt->clearcol[1], tgt->clearcol[2], tgt->clearcol[3]);
	}

	env->scissor(0, 0, w, h);
	env->viewport(0, 0, w, h);
#endif
}

void agp_rendertarget_clear()
{
	agp_env()->clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

void agp_pipeline_hint(enum pipeline_mode mode)
{
	struct agp_fenv* env = agp_env();
	switch (mode){
	case PIPELINE_2D:
		if (mode != env->mode){
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
	if (!store ||
		store->txmapped != TXSTATE_TEX2D || store->vinf.text.glid == GL_NONE)
		return;

	agp_env()->delete_textures(1, &store->vinf.text.glid);
	store->vinf.text.glid = GL_NONE;
}

static void erase_store(struct agp_vstore* os)
{
	if (!os)
		return;

	agp_null_vstore(os);
	arcan_mem_free(os->vinf.text.raw);
	os->vinf.text.raw = NULL;
	os->vinf.text.s_raw = 0;
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

	erase_store(tgt->store);
	erase_store(tgt->store_back);

	struct agp_fenv* env = agp_env();

	agp_empty_vstore(tgt->store, neww, newh);
	if (tgt->store_back)
		agp_empty_vstore(tgt->store_back, neww, newh);

/* we inplace- modify, want the refcounter intact */
	env->delete_framebuffers(1,&tgt->fbo);
	env->delete_renderbuffers(1,&tgt->depth);
	tgt->fbo = GL_NONE;
	tgt->depth = GL_NONE;
	alloc_fbo(tgt, false);
}

void agp_activate_vstore_multi(struct agp_vstore** backing, size_t n)
{
	char buf[] = {'m', 'a', 'p', '_', 't', 'u', 0, 0, 0};
	struct agp_fenv* env = agp_env();

	for (int i = 0; i < n && i < 99; i++){
		env->active_texture(GL_TEXTURE0 + i);
		env->bind_texture(GL_TEXTURE_2D, backing[i]->vinf.text.glid);
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
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	break;

	case ARCAN_VFILTER_LINEAR:
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	break;

	case ARCAN_VFILTER_BILINEAR:
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	break;

	case ARCAN_VFILTER_TRILINEAR:
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
	case BLEND_NONE: /* -dumb compiler- */
	case BLEND_FORCE:
	case BLEND_NORMAL:
		env->blend_func_separate(
			GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
			env->blend_src_alpha, env->blend_dst_alpha
		);
	break;

	case BLEND_MULTIPLY:
		env->blend_func_separate(
			GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
			env->blend_src_alpha, env->blend_dst_alpha
		);
	break;

	case BLEND_ADD:
		env->blend_func_separate(
			GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
			env->blend_src_alpha, env->blend_dst_alpha
		);
	break;

	default:
	break;
	}
}

void agp_draw_vobj(float x1, float y1, float x2, float y2,
	const float* txcos, const float* model)
{
	GLfloat verts[] = {
		x1, y1,
		x2, y1,
		x2, y2,
		x1, y2
	};
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
}

static void toggle_debugstates(float* modelview)
{
	struct agp_fenv* env = agp_env();
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
		*col = rtgt->store->vinf.text.glid;
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
		env->enable_vertex_attrarray(attribs[0]);
		env->vertex_attrpointer(attribs[0],
			base->vertex_size, GL_FLOAT, GL_FALSE, 0, base->verts);
	}

	if (attribs[1] != -1 && base->normals){
		env->enable_vertex_attrarray(attribs[1]);
		env->vertex_attrpointer(attribs[1], 3, GL_FLOAT, GL_FALSE,0, base->normals);
	}
	else
		attribs[1] = -1;

	if (attribs[2] != -1 && base->txcos){
		env->enable_vertex_attrarray(attribs[2]);
		env->vertex_attrpointer(attribs[2], 2, GL_FLOAT, GL_FALSE, 0, base->txcos);
	}
	else
		attribs[2] = -1;

	if (attribs[3] != -1 && base->colors){
		env->enable_vertex_attrarray(attribs[3]);
		env->vertex_attrpointer(attribs[3], 3, GL_FLOAT, GL_FALSE, 0, base->colors);
	}
	else
		attribs[3] = -1;

	if (attribs[4] != -1 && base->txcos2){
		env->enable_vertex_attrarray(attribs[4]);
		env->vertex_attrpointer(attribs[4], 2, GL_FLOAT, GL_FALSE, 0, base->txcos2);
	}
	else
		attribs[4] = -1;

	if (attribs[5] != -1 && base->tangents){
		env->enable_vertex_attrarray(attribs[5]);
		env->vertex_attrpointer(attribs[5],4,GL_FLOAT,GL_FALSE,0,base->tangents);
	}
	else
		attribs[5] = -1;

	if (attribs[6] != -1 && base->bitangents){
		env->enable_vertex_attrarray(attribs[6]);
		env->vertex_attrpointer(attribs[6],4,GL_FLOAT,GL_FALSE,0,base->bitangents);
	}
	else
		attribs[6] = -1;

	if (attribs[7] != -1 && base->weights){
		env->enable_vertex_attrarray(attribs[7]);
		env->vertex_attrpointer(attribs[7], 4, GL_FLOAT, GL_FALSE, 0,base->weights);
	}
	else
		attribs[7] = -1;

	if (attribs[8] != -1 && base->joints){
		env->enable_vertex_attrarray(attribs[8]);
		env->vertex_iattrpointer(attribs[8], 4, GL_UNSIGNED_SHORT, 0, base->joints);
	}
	else
		attribs[8] = -1;

	if (base->type == AGP_MESH_TRISOUP){
		if (base->indices)
			env->draw_elements(GL_TRIANGLES, base->n_indices,
				GL_UNSIGNED_INT, base->indices);
		else
			env->draw_arrays(GL_TRIANGLES, 0, base->n_vertices);
	}
	else if (base->type == AGP_MESH_POINTCLOUD){
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

	memset(s, '\0', sizeof(struct agp_vstore));
}

static void setup_culling(enum agp_mesh_flags fl)
{
	struct agp_fenv* env = agp_env();

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
				setup_culling(fl);
#if !defined(GLES2) && !defined(GLES3)
				env->polygon_mode(GL_FRONT_AND_BACK, GL_FILL);
				env->color_mask(false, false, false, false);
				setup_transfer(base, fl);

				env->polygon_mode(GL_FRONT_AND_BACK, GL_LINE);
				env->color_mask(true, true, true, true);
				env->depth_func(GL_LESS);
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
			setup_culling(fl);
		}

		env->model_flags = fl;
	}

	setup_transfer(base, fl);
}

/*
 * mark that the contents of the mesh has changed dynamically
 * and that possible GPU- side cache might need to be updated.
 */
void agp_invalidate_mesh(struct agp_mesh_store* bs)
{
}

void agp_activate_vstore(struct agp_vstore* s)
{
	agp_env()->bind_texture(GL_TEXTURE_2D, s->vinf.text.glid);
}

void agp_deactivate_vstore()
{
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

	memset(s, '\0', sizeof(struct agp_mesh_store));
}

void agp_save_output(size_t w, size_t h, av_pixel* dst, size_t dsz)
{
	struct agp_fenv* env = agp_env();
	env->read_buffer(GL_FRONT);
	assert(w * h * sizeof(av_pixel) == dsz);

	env->read_pixels(0, 0, w, h, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, dst);
}
