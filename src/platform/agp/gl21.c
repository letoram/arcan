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
#include "arcan_shdrmgmt.h"

static const char* defvprg =
"#version 120\n"
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
"#version 120\n"
"uniform sampler2D map_diffuse;\n"
"varying vec2 texco;\n"
"uniform float obj_opacity;\n"
"void main(){\n"
"   vec4 col = texture2D(map_diffuse, texco);\n"
"   col.a = col.a * obj_opacity;\n"
"	gl_FragColor = col;\n"
"}";

const char* defcfprg =
"#version 120\n"
"varying vec2 texco;\n"
"uniform vec3 obj_col;\n"
"uniform float obj_opacity;\n"
"void main(){\n"
"   gl_FragColor = vec4(obj_col.rgb, obj_opacity);\n"
"}\n";

const char * defcvprg =
"#version 120\n"
"uniform mat4 modelview;\n"
"uniform mat4 projection;\n"
"attribute vec4 vertex;\n"
"void main(){\n"
" gl_Position = (projection * modelview) * vertex;\n"
"}";

arcan_shader_id agp_default_shader(enum SHADER_TYPES type)
{
	static arcan_shader_id shids[SHADER_TYPE_ENDM];
	static bool defshdr_build;

	assert(type < SHADER_TYPE_ENDM);

	if (!defshdr_build){
		shids[0] = arcan_shader_build("DEFAULT", NULL, defvprg, deffprg);
		shids[1] = arcan_shader_build("DEFAULT_COLOR", NULL, defcvprg, defcfprg);
		defshdr_build = true;
	}

	return shids[type];
}

void agp_shader_source(enum SHADER_TYPES type,
	const char** vert, const char** frag)
{
	switch(type){
		case BASIC_2D:
			*vert = defvprg;
			*frag = deffprg;
		break;

		case COLOR_2D:
			*vert = defcvprg;
			*frag = defcfprg;
		break;

		default:
			*vert = NULL;
			*frag = NULL;
		break;
	}
}

const char* agp_shader_language()
{
	return "GLSL120";
}

const char* agp_backend_ident()
{
	return "OPENGL21";
}

void agp_readback_synchronous(struct storage_info_t* dst)
{
	if (!dst->txmapped == TXSTATE_TEX2D || !dst->vinf.text.raw)
		return;

	glBindTexture(GL_TEXTURE_2D, dst->vinf.text.glid);
	glGetTexImage(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT,
		GL_UNSIGNED_BYTE, dst->vinf.text.raw);
	glBindTexture(GL_TEXTURE_2D, 0);
}

void agp_drop_vstore(struct storage_info_t* s)
{
	if (!s)
		return;

	glDeleteTextures(1, &s->vinf.text.glid);
	s->vinf.text.glid = 0;

	if (GL_NONE != s->vinf.text.tid){
		glDeleteBuffers(1, &s->vinf.text.tid);
	}

	memset(s, '\0', sizeof(struct storage_info_t));
}

static void pbo_alloc(struct storage_info_t* store)
{
	GLuint pboid;
	glGenBuffers(1, &pboid);
	store->vinf.text.tid = pboid;

	glBindBuffer(GL_PIXEL_PACK_BUFFER, pboid);
	glBufferData(GL_PIXEL_PACK_BUFFER,
		store->w * store->h * store->bpp, NULL, GL_STREAM_READ);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
}

static void default_release(void* tag)
{
	if (!tag)
		return;

	glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
}

void agp_request_readback(struct storage_info_t* store)
{
	if (!store || store->txmapped != TXSTATE_TEX2D)
		return;

	if (!store->vinf.text.tid)
		pbo_alloc(store);

	glBindTexture(GL_TEXTURE_2D, store->vinf.text.glid);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, store->vinf.text.tid);
		glGetTexImage(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT,
			GL_UNSIGNED_BYTE, NULL);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
	glBindTexture(GL_TEXTURE_2D, 0);
}

struct asynch_readback_meta agp_poll_readback(struct storage_info_t* store)
{
	struct asynch_readback_meta res = {
	.release = default_release
	};

	if (!store || store->txmapped != TXSTATE_TEX2D ||
		store->vinf.text.tid == GL_NONE)
		return res;

	glBindBuffer(GL_PIXEL_PACK_BUFFER, store->vinf.text.tid);

	res.w = store->w;
	res.h = store->h;
	res.tag = (void*) 0xdeadbeef;
	res.ptr = (av_pixel*) glMapBuffer(GL_PIXEL_PACK_BUFFER, ACCESS_FLAG_RW);

	return res;
}
