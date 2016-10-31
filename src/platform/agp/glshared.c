/*
 * Copyright 2014-2016, Björn Ståhl
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

struct agp_rendertarget
{
	GLuint fbo;
	GLuint depth;

	enum rendertarget_mode mode;
	struct storage_info_t* store;
};

static bool alloc_fbo(struct agp_rendertarget* dst, bool retry)
{
	struct agp_fenv* env = agp_env();
	env->gen_framebuffers(1, &dst->fbo);

/* need both stencil and depth buffer, but we don't need the data from them */
	env->bind_framebuffer(GL_FRAMEBUFFER, dst->fbo);

	if (dst->mode > RENDERTARGET_DEPTH)
	{
		env->framebuffer_texture_2d(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			GL_TEXTURE_2D, dst->store->vinf.text.glid, 0);

/* need a Z buffer in the offscreen rendering but don't want
 * bo store it, so setup a renderbuffer */
		if (dst->mode > RENDERTARGET_COLOR){
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

		dst->store = arcan_alloc_mem(sizeof(struct storage_info_t),
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);

		struct storage_info_t* store = dst->store;

		memset(store, '\0', sizeof(struct storage_info_t));

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

	env->bind_framebuffer(GL_FRAMEBUFFER, 0);
	return true;
}

void agp_empty_vstore(struct storage_info_t* vs, size_t w, size_t h)
{
	size_t sz = w * h * sizeof(av_pixel);
	vs->vinf.text.s_raw = sz;
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

void agp_empty_vstoreext(struct storage_info_t* vs,
	size_t w, size_t h, enum vstore_hint hint)
{
	agp_empty_vstore(vs, w, h);
}

struct agp_rendertarget* agp_setup_rendertarget(struct storage_info_t* vstore,
	enum rendertarget_mode m)
{
	struct agp_rendertarget* r = arcan_alloc_mem(sizeof(struct agp_rendertarget),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	r->store = vstore;
	r->mode = m;

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
	env->blend_func(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
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
	arcan_mem_free(tgt);
}

void agp_activate_rendertarget(struct agp_rendertarget* tgt)
{
	size_t w, h;
	struct agp_fenv* env = agp_env();

#ifdef HEADLESS_NOARCAN
	env->bind_framebuffer(GL_FRAMEBUFFER, tgt ? tgt->fbo : 0);
#else
	struct monitor_mode mode = platform_video_dimensions();

	if (!tgt){
		w = mode.width;
		h = mode.height;
		env->bind_framebuffer(GL_FRAMEBUFFER, 0);
	}
	else {
		w = tgt->store->w;
		h = tgt->store->h;
		env->bind_framebuffer(GL_FRAMEBUFFER, tgt->fbo);
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
		env->disable(GL_CULL_FACE);
		env->disable(GL_DEPTH_TEST);
	break;

	case PIPELINE_3D:
		env->enable(GL_DEPTH_TEST);
		env->clear(GL_DEPTH_BUFFER_BIT);
	break;
	}
}

void agp_null_vstore(struct storage_info_t* store)
{
	if (!store ||
		store->txmapped != TXSTATE_TEX2D || store->vinf.text.glid == GL_NONE)
		return;

	agp_env()->delete_textures(1, &store->vinf.text.glid);
	store->vinf.text.glid = GL_NONE;
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

	struct storage_info_t* os = tgt->store;
	struct agp_fenv* env = agp_env();

/* we inplace- modify, want the refcounter intact */
	agp_null_vstore(os);
	arcan_mem_free(os->vinf.text.raw);
	os->vinf.text.raw = NULL;
	os->vinf.text.s_raw = 0;
	agp_empty_vstore(os, neww, newh);

	env->delete_framebuffers(1,&tgt->fbo);
	env->delete_renderbuffers(1,&tgt->depth);
	tgt->fbo = GL_NONE;
	tgt->depth = GL_NONE;
	alloc_fbo(tgt, false);
}

void agp_activate_vstore_multi(struct storage_info_t** backing, size_t n)
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

void agp_update_vstore(struct storage_info_t* s, bool copy)
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
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
			GL_LINEAR_MIPMAP_LINEAR);
		env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	break;
	}

	if (copy){
		s->update_ts = arcan_timemillis();
		if (s->txmapped == TXSTATE_DEPTH)
			env->tex_image_2d(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, s->w, s->h, 0,
				GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, 0);
		else
			env->tex_image_2d(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, s->w, s->h,
				0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, s->vinf.text.raw);
	}

#ifndef HEADLESS_NOARCAN
	if (arcan_video_display.conservative){
		arcan_mem_free(s->vinf.text.raw);
		s->vinf.text.raw = NULL;
		s->vinf.text.s_raw = 0;
	}
#endif

	glBindTexture(GL_TEXTURE_2D, 0);
}

void agp_prepare_stencil()
{
/* toggle stenciling, reset into zero, draw parent bounding area to
 * stencil only,redraw parent into stencil, draw new object
 * then disable stencil. */
	glEnable(GL_STENCIL_TEST);
	glDisable(GL_BLEND);
	glClearStencil(0);
	glClear(GL_STENCIL_BUFFER_BIT);
	glColorMask(0, 0, 0, 0);
	glStencilFunc(GL_ALWAYS, 1, 1);
	glStencilOp(GL_REPLACE, GL_REPLACE, GL_REPLACE);
}

void agp_activate_stencil()
{
	glColorMask(1, 1, 1, 1);
	glStencilFunc(GL_EQUAL, 1, 1);
	glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
}

void agp_disable_stencil()
{
	glDisable(GL_STENCIL_TEST);
}

static float ident[] = {
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 1.0, 0.0,
	0.0, 0.0, 0.0, 1.0
};

void agp_blendstate(enum arcan_blendfunc mode)
{
	if (mode == BLEND_NONE){
		glDisable(GL_BLEND);
		return;
	}

	glEnable(GL_BLEND);

	switch (mode){
	case BLEND_NONE: /* -dumb compiler- */
	case BLEND_FORCE:
	case BLEND_NORMAL:
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	break;

	case BLEND_MULTIPLY:
		glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA);
	break;

	case BLEND_ADD:
		glBlendFunc(GL_ONE, GL_ONE);
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
	GLint attrindt = agp_shader_vattribute_loc(ATTRIBUTE_TEXCORD);

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

void agp_submit_mesh(struct mesh_storage_t* base, enum agp_mesh_flags fl)
{
/* make sure the current program actually uses the attributes from the mesh */
	struct agp_fenv* env = agp_env();
	int attribs[3] = {
		agp_shader_vattribute_loc(ATTRIBUTE_VERTEX),
		agp_shader_vattribute_loc(ATTRIBUTE_NORMAL),
		agp_shader_vattribute_loc(ATTRIBUTE_TEXCORD)
	};

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

	if (attribs[0] == -1)
		return;
	else {
		env->enable_vertex_attrarray(attribs[0]);
		env->vertex_attrpointer(attribs[0], 3, GL_FLOAT, GL_FALSE, 0, base->verts);
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

/*
 * mark that the contents of the mesh has changed dynamically
 * and that possible GPU- side cache might need to be updated.
 */
void agp_invalidate_mesh(struct mesh_storage_t* bs)
{
}

void agp_activate_vstore(struct storage_info_t* s)
{
	agp_env()->bind_texture(GL_TEXTURE_2D, s->vinf.text.glid);
}

void agp_deactivate_vstore()
{
	agp_env()->bind_texture(GL_TEXTURE_2D, 0);
}

void agp_save_output(size_t w, size_t h, av_pixel* dst, size_t dsz)
{
	struct agp_fenv* env = agp_env();
	env->read_buffer(GL_FRONT);
	assert(w * h * sizeof(av_pixel) == dsz);

	env->read_pixels(0, 0, w, h, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, dst);
}

