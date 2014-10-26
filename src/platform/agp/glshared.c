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

void argp_update_vstore(struct storage_info_t* s, bool copy, bool mipmap)
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

void argp_drop_vstore(struct storage_info_t* s)
{
	if (!s)
		return;

	assert(s->refcount);
	s->refcount--;

	if (s->refcount == 0){
		if (s->txmapped != TXSTATE_OFF && s->vinf.text.glid){
			glDeleteTextures(1, &s->vinf.text.glid);
			s->vinf.text.glid = 0;

			if (s->vinf.text.raw){
				arcan_mem_free(s->vinf.text.raw);
				s->vinf.text.raw = NULL;
			}
		}

		arcan_mem_free(s);
	}
}
