/*
 * Copyright 2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>

#include "glfun.h"

#include "../video_platform.h"
#include "../platform.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_mem.h"
#include "arcan_videoint.h"

struct rendertarget_store
{
	GLuint fbo;
	GLuint depth;
	GLuint color;

	enum rendertarget_mode mode;
	struct storage_info_t* store;
};

static bool alloc_fbo(struct rendertarget_store* dst)
{
	glGenFramebuffers(1, &dst->fbo);

/* need both stencil and depth buffer, but we don't need the data from them */
	glBindFramebuffer(GL_FRAMEBUFFER, dst->fbo);

	if (dst->mode > RENDERTARGET_DEPTH)
	{
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			GL_TEXTURE_2D, dst->store->vinf.text.glid, 0);

/* need a Z buffer in the offscreen rendering but don't want
 * bo store it, so setup a renderbuffer */
		if (dst->mode > RENDERTARGET_COLOR) {
			glGenRenderbuffers(1, &dst->depth);

/* could use GL_DEPTH_COMPONENT only if we'd know that there
 * wouldn't be any clipping in the active rendertarget */
			glBindRenderbuffer(GL_RENDERBUFFER, dst->depth);
			glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8,
				dst->store->w, dst->store->h);

			glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
				GL_RENDERBUFFER, dst->depth);
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
		arcan_warning("FBO support assumed broken, check drivers.\n");
		return false;
	}

	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	return true;
}

void agp_empty_vstore(struct storage_info_t* vs, size_t w, size_t h)
{
	size_t sz = w * h * GL_PIXEL_BPP;
	vs->vinf.text.s_raw = sz;
	vs->vinf.text.raw = arcan_alloc_mem(
		vs->vinf.text.s_raw,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE
	);
	vs->w = w;
	vs->h = h;

	agp_update_vstore(vs, true);

	arcan_mem_free(vs->vinf.text.raw);
	vs->vinf.text.raw = 0;
	vs->vinf.text.s_raw = 0;
}

void agp_setup_rendertarget(struct rendertarget* dst,
	struct storage_info_t* vstore, enum rendertarget_mode m)
{
	if (dst->store){
		arcan_mem_free(dst->store);
	}

	dst->store = arcan_alloc_mem(sizeof(struct rendertarget_store),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	dst->store->store = vstore;
	dst->store->mode = m;

	alloc_fbo(dst->store);
}

extern void agp_gl_ext_init();

void agp_init()
{
	agp_gl_ext_init();

	glEnable(GL_SCISSOR_TEST);
	glDisable(GL_DEPTH_TEST);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glFrontFace(GL_CW);
	glCullFace(GL_BACK);

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
}

void agp_drop_rendertarget(struct rendertarget* tgt)
{
	glDeleteFramebuffers(1,&tgt->store->fbo);
	glDeleteRenderbuffers(1,&tgt->store->depth);
	tgt->store->fbo = GL_NONE;
	tgt->store->depth = GL_NONE;
}

void agp_activate_rendertarget(struct rendertarget* tgt)
{
	size_t w, h;

	if (!tgt){
		w = arcan_video_display.width;
		h = arcan_video_display.height;
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}
	else {
		w = tgt->store->store->w;
		h = tgt->store->store->h;
		glBindFramebuffer(GL_FRAMEBUFFER, tgt->store->fbo);
	}

	glScissor(0, 0, w, h);
	glViewport(0, 0, w, h);
}

void agp_rendertarget_clear()
{
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

void agp_pipeline_hint(enum pipeline_mode mode)
{
	switch (mode){
		case PIPELINE_2D:
			glDisable(GL_CULL_FACE);
			glDisable(GL_DEPTH_TEST);
		break;

		case PIPELINE_3D:
			glEnable(GL_DEPTH_TEST);
			glClear(GL_DEPTH_BUFFER_BIT);
		break;
	}
}

void agp_null_vstore(struct storage_info_t* store)
{
	if (!store ||
		store->txmapped != TXSTATE_TEX2D || store->vinf.text.glid == GL_NONE)
		return;

	glDeleteTextures(1, &store->vinf.text.glid);
	store->vinf.text.glid = 0;
}

void agp_resize_rendertarget(struct rendertarget* tgt, size_t neww,
	size_t newh)
{
	if (!tgt || !tgt->store){
		arcan_warning("attempted resize on broken rendertarget\n");
		return;
	}

/* same dimensions, no need to resize */
	if (tgt->store->store->w == neww && tgt->store->store->h == newh)
		return;

	struct storage_info_t* os = tgt->store->store;
	enum rendertarget_mode mode = tgt->store->mode;

/* we inplace- modify, want the refcounter intact */
	agp_null_vstore(os);
	arcan_mem_free(os->vinf.text.raw);
	os->vinf.text.raw = NULL;
	os->vinf.text.s_raw = 0;
	agp_empty_vstore(os, neww, newh);

/* drop old FBO IDs etc. */
	agp_drop_rendertarget(tgt);
	agp_setup_rendertarget(tgt, os, mode);
}

void agp_activate_vstore_multi(struct storage_info_t** backing, size_t n)
{
	char buf[] = "map_tu99";

	for (int i = 0; i < n && i < 99; i++){
		glActiveTexture(GL_TEXTURE0 + i);
		glBindTexture(GL_TEXTURE_2D, backing[i]->vinf.text.glid);
		if (i > 10){
			buf[6] = '0' + (i / 10);
			buf[7] = '0' + (i % 10);
			buf[8] = '\0';
		}
		else {
			buf[6] = '0' + i;
			buf[7] = '\0';
		}
		arcan_shader_forceunif(buf, shdrint, &i, false);
	}

	glActiveTexture(GL_TEXTURE0);
}

void agp_update_vstore(struct storage_info_t* s, bool copy)
{
	if (s->txmapped == TXSTATE_OFF)
		return;

	FLAG_DIRTY();

	if (!copy)
		glBindTexture(GL_TEXTURE_2D, s->vinf.text.glid);
	else{
		glGenTextures(1, &s->vinf.text.glid);

/* for the launch_resume and resize states, were we'd push a new
 * update	but have multiple references */
		if (s->refcount == 0)
			s->refcount = 1;

		glBindTexture(GL_TEXTURE_2D, s->vinf.text.glid);
	}

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, s->txu);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, s->txv);

	int filtermode = s->filtermode & (~ARCAN_VFILTER_MIPMAP);
	bool mipmap = s->filtermode & ARCAN_VFILTER_MIPMAP;

/*
 * Mipmapping still misses the option to manually define mipmap levels
 */
	if (copy){
#ifndef GL_GENERATE_MIPMAP
		if (mipmap)
			glGenerateMipmap(GL_TEXTURE_2D);
#else
			glTexParameteri(GL_TEXTURE_2D, GL_GENERATE_MIPMAP, mipmap);
#endif
	}

	switch (filtermode){
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

	if (copy){
		if (s->txmapped == TXSTATE_DEPTH)
			glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, s->w, s->h, 0,
				GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, 0);
		else
			glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, s->w, s->h,
				0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, s->vinf.text.raw);
	}

	if (arcan_video_display.conservative){
		arcan_mem_free(s->vinf.text.raw);
		s->vinf.text.raw = NULL;
		s->vinf.text.s_raw = 0;
	}

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

static float ident[] =
 {1.0, 0.0, 0.0, 0.0,
  0.0, 1.0, 0.0, 0.0,
  0.0, 0.0, 1.0, 0.0,
  0.0, 0.0, 0.0, 1.0};


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
	float* txcos, float* model)
{
	GLfloat verts[] = {
		x1, y1,
		x2, y1,
		x2, y2,
	 	x1, y2
	};
	bool settex = false;

	arcan_shader_envv(MODELVIEW_MATR, model?model:ident, sizeof(float) * 16);
/* projection, scissor is set when activating rendertarget */

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

static void toggle_debugstates(float* modelview)
{
	if (modelview){
		float white[3] = {1.0, 1.0, 1.0};
		glDepthMask(GL_FALSE);
		glDisable(GL_DEPTH_TEST);
		glEnableVertexAttribArray(ATTRIBUTE_VERTEX);
		arcan_shader_activate(agp_default_shader(COLOR_2D));
		arcan_shader_envv(MODELVIEW_MATR, modelview, sizeof(float) * 16);
		arcan_shader_forceunif("obj_col", shdrvec3, (void*) white, false);
	}
	else{
		arcan_shader_activate(agp_default_shader(COLOR_2D));
		glEnable(GL_DEPTH_TEST);
		glDepthMask(GL_TRUE);
		glDisableVertexAttribArray(ATTRIBUTE_VERTEX);
	}
}

void agp_submit_mesh(struct mesh_storage_t* base, enum agp_mesh_flags fl)
{
/* make sure the current program actually uses the attributes from the mesh */
	int attribs[3] = {
		arcan_shader_vattribute_loc(ATTRIBUTE_VERTEX),
		arcan_shader_vattribute_loc(ATTRIBUTE_NORMAL),
		arcan_shader_vattribute_loc(ATTRIBUTE_TEXCORD)
	};

	if (attribs[0] == -1)
		return;
	else {
		glEnableVertexAttribArray(attribs[0]);
		glVertexAttribPointer(attribs[0], 3, GL_FLOAT, GL_FALSE, 0, base->verts);
	}

	if (attribs[1] != -1 && base->normals){
		glEnableVertexAttribArray(attribs[1]);
		glVertexAttribPointer(attribs[1], 3, GL_FLOAT, GL_FALSE,0, base->normals);
	}
	else
		attribs[1] = -1;

	if (attribs[2] != -1 && base->txcos){
		glEnableVertexAttribArray(attribs[2]);
		glVertexAttribPointer(attribs[2], 2, GL_FLOAT, GL_FALSE, 0, base->txcos);
	}
	else
		attribs[2] = -1;

		if (base->type == AGP_MESH_TRISOUP){
			if (base->indices)
				glDrawElements(GL_TRIANGLES, base->n_indices,
					GL_UNSIGNED_INT, base->indices);
			else
				glDrawArrays(GL_TRIANGLES, 0, base->n_vertices);
		}
		else if (base->type == AGP_MESH_POINTCLOUD)
			glDrawArrays(GL_POINTS, 0, base->n_vertices);

		for (size_t i = 0; i < sizeof(attribs) / sizeof(attribs[0]); i++)
			if (attribs[i] != -1)
				glDisableVertexAttribArray(attribs[i]);
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
	glBindTexture(GL_TEXTURE_2D, s->vinf.text.glid);
}

void agp_deactivate_vstore(struct storage_info_t* s)
{
	glBindTexture(GL_TEXTURE_2D, 0);
}

void agp_save_output(size_t w, size_t h, av_pixel* dst, size_t dsz)
{
	glReadBuffer(GL_FRONT);
	assert(w * h * GL_PIXEL_BPP == dsz);

	glReadPixels(0, 0, w, h, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, dst);
}

