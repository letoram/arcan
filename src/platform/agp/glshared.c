#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <assert.h>

#include GL_HEADERS

#include "../video_platform.h"
#include "../platform.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shdrmgmt.h"

void agp_init()
{
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
	if (arcan_video_display.pbo_support){
		glGenBuffers(1, &current_context->stdoutp.pbo);
		glBindBuffer(GL_PIXEL_PACK_BUFFER, current_context->stdoutp.pbo);
		glBufferData(GL_PIXEL_PACK_BUFFER,
			arcan_video_display.width * arcan_video_display.height * GL_PIXEL_BPP,
			NULL, GL_STREAM_READ);
		glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
	}
*/

/*
 * -- Removed as they were causing trouble with NVidia GPUs (white line outline
 * where triangles connect
 * glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);
 * glHint(GL_POLYGON_SMOOTH_HINT, GL_NICEST);
 * glEnable(GL_LINE_SMOOTH);
 * glEnable(GL_POLYGON_SMOOTH);
*/
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

void agp_update_vstore(struct storage_info_t* s, bool copy, bool mipmap)
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

	assert(s->txu != 0);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, s->txu);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, s->txv);

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
	assert(w * h * GL_PIXEL_FORMAT == dsz);

	glReadPixels(0, 0, w, h, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, dst);
}

