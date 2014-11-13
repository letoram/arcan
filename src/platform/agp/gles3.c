#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>

#include GL_HEADERS

#include "../video_platform.h"
#include "../platform.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

/*
 * Is there a way of doing this in GLES that is not so horrible?
 * This approach will be limited to the current canvas size.
 */
void argp_buffer_readback_synchronous(struct storage_info_t* dst)
{
	static struct {
		bool ready;
		GLuint texid;
		GLuint fboid;
	} readback;

	if (!readback.ready){
		glGenRenderbuffers(1, &readback.texid);
		glBindRenderbuffer(GL_RENDERBUFFER, readback.texid);
		glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA,
			arcan_video_display.canvasw, arcan_video_display.canvash);

		glGenFramebuffers(1, &readback.fboid);
		glBindFramebuffer(GL_FRAMEBUFFER, readback.fboid);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER,
			GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, readback.texid);
	}

	glViewport(0, 0, width, height);
	glReadPixels(0, 0, width, height, GL_RGBA, GL_RGBA, dstbuf);
}

struct asynch_readback_meta argp_buffer_readback_asynchronous(
	struct storage_info_t* dst, bool poll)
{
	struct asynch_readback_meta res = {0};
//	glBindBuffer(GL_PIXEL_PACK_BUFFER, tgt->pbo);
//	readback_texture(dstore->vinf.text.glid, dstore->w, dstore->h, 0, 0);
//  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
//
	return res;
}

