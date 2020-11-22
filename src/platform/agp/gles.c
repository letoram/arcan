/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: Simplified AGP platform for GLES 2/3. We need a slightly
 * different shader format and we lack some key features that kill this
 * platform rather badly (PBO uploads and asynch data fetch).
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>

#include "glfun.h"

#include "../video_platform.h"
#include "../platform.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#ifdef GLES3
#include <GLES3/gl3.h>
#include <GLES3/gl3ext.h>
#else
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

void glReadBuffer(GLenum mode)
{
}

void glWriteBuffer(GLenum mode)
{
}

#endif

static const char* defvprg =
"#version 100\n"
"precision mediump float;\n"
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
"#version 100\n"
"precision mediump float;\n"
"uniform sampler2D map_diffuse;\n"
"varying vec2 texco;\n"
"uniform float obj_opacity;\n"
"void main(){\n"
"   vec4 col = texture2D(map_diffuse, texco);\n"
"   col.a = col.a * obj_opacity;\n"
"	gl_FragColor = col;\n"
"}";

const char* defcfprg =
"#version 100\n"
"precision mediump float;\n"
"varying vec2 texco;\n"
"uniform vec3 obj_col;\n"
"uniform float obj_opacity;\n"
"void main(){\n"
"   gl_FragColor = vec4(obj_col.rgb, obj_opacity);\n"
"}\n";

const char * defcvprg =
"#version 100\n"
"precision mediump float;\n"
"uniform mat4 modelview;\n"
"uniform mat4 projection;\n"
"attribute vec4 vertex;\n"
"void main(){\n"
" gl_Position = (projection * modelview) * vertex;\n"
"}";

agp_shader_id agp_default_shader(enum SHADER_TYPES type)
{
	static agp_shader_id shids[SHADER_TYPE_ENDM];
	static bool defshdr_build;

	assert(type < SHADER_TYPE_ENDM);

	if (!defshdr_build){
		shids[BASIC_2D] = agp_shader_build("DEFAULT", NULL, defvprg, deffprg);
		shids[COLOR_2D] = agp_shader_build(
			"DEFAULT_COLOR", NULL, defcvprg, defcfprg);
		shids[BASIC_3D] = shids[BASIC_2D];
		defshdr_build = true;
	}

	return shids[type];
}

const char** agp_envopts()
{
	static const char* env[] = {
		NULL, NULL
	};
	return env;
}

const char* agp_shader_language()
{
	return "GLSL100";
}

const char* agp_ident()
{
#ifdef GLES3
	return "GLES3";
#else
	return "GLES2";
#endif
}

void agp_shader_source(enum SHADER_TYPES type,
	const char** vert, const char** frag)
{
	switch(type){
	case BASIC_2D:
		case BASIC_3D:
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

#ifdef GLES3
static void pbo_alloc_write(struct agp_vstore* store)
{
	struct agp_fenv* env = agp_env();
	GLuint pboid;
	env->gen_buffers(1, &pboid);
	store->vinf.text.wid = pboid;

	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, pboid);
	env->buffer_data(GL_PIXEL_UNPACK_BUFFER,
		store->w * store->h * store->bpp, NULL, GL_STREAM_READ);
	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, 0);
}
#endif

void agp_env_help(FILE* out)
{
/* write agp specific tuning here,
 * use ARCAN_AGP_ as symbol prefix */
}

void glDrawBuffer(GLint mode)
{
}

/*
 * NOTE: not yet implemented, there's few "clean" ways for
 * getting this behavior in GLES2,3 -- either look for an
 * extension that permits it or create an intermediate
 * rendertarget, blit to it, and then glReadPixels (seriously...)
 *
 * Possibly use a pool of a few stores at least as
 * the amount of readbacks should be rather limited
 * (we're talking recording, streaming or remoting)
 * something like:
 *
 *	glGenRenderbuffers(1, &readback.texid);
 *  glBindRenderbuffer(GL_RENDERBUFFER, readback.texid);
 *	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA, w, h);
 *
 *	glGenFramebuffers(1, &readback.fboid);
 *	glBindFramebuffer(GL_FRAMEBUFFER, readback.fboid);
 *	glFramebufferRenderbuffer(GL_FRAMEBUFFER,
 *		GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, readback.texid);
 *
 *	glViewport(0, 0, width, height);
 *	glReadPixels(0, 0, width, height, GL_RGBA, GL_RGBA, dstbuf);
 */

void agp_readback_synchronous(struct agp_vstore* dst)
{
	arcan_warning("agp(gles) - readbacks not supported\n");
}

void agp_request_readback(struct agp_vstore* store)
{
	arcan_warning("agp(gles) - readbacks not supported\n");
}

struct asynch_readback_meta argp_buffer_readback_asynchronous(
	struct agp_vstore* dst, bool poll)
{
	struct asynch_readback_meta res = {0};
	return res;
}

static void default_release(void* tag)
{
#ifdef GLES3
	if (!tag)
		return;
	struct agp_fenv* env = agp_env();

	env->unmap_buffer(GL_PIXEL_PACK_BUFFER);
	env->bind_buffer(GL_PIXEL_PACK_BUFFER, 0);
#endif
}

struct asynch_readback_meta agp_poll_readback(struct agp_vstore* store)
{
	struct asynch_readback_meta res = {
	.release = default_release
	};

	return res;
}

void agp_resize_vstore(struct agp_vstore* s, size_t w, size_t h)
{
	s->w = w;
	s->h = h;
	s->bpp = sizeof(av_pixel);
	size_t new_sz = w * h * s->bpp;
	struct agp_fenv* env = agp_env();

/* some cases the vstore can have been "secretly" resized to
 * the new dimensions, common case is resize in a frameserver that
 * uses shm- transfer */
	if (s->vinf.text.raw && s->vinf.text.s_raw != new_sz){
		arcan_mem_free(s->vinf.text.raw);
		s->vinf.text.s_raw = new_sz;
		s->vinf.text.raw = NULL;
	}

	if (s->vinf.text.raw == NULL)
		s->vinf.text.raw = arcan_alloc_mem(s->vinf.text.s_raw,
			ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

#ifdef GLES3
	if (s->vinf.text.wid){
		env->delete_buffers(1, &s->vinf.text.wid);
		pbo_alloc_write(s);
	}
#endif

	agp_update_vstore(s, true);
}

static void alloc_buffer(struct agp_vstore* s)
{
	if (s->vinf.text.s_raw != s->w * s->h * sizeof(av_pixel)){
		arcan_mem_free(s->vinf.text.raw);
		s->vinf.text.raw = NULL;
	}

	if (!s->vinf.text.raw){
		s->vinf.text.s_raw = s->w * s->h * sizeof(av_pixel);
		s->vinf.text.raw = arcan_alloc_mem(s->vinf.text.s_raw,
			ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);
	}
}

struct stream_meta agp_stream_prepare(struct agp_vstore* s,
		struct stream_meta meta, enum stream_type type)
{
	struct stream_meta mout = meta;
	struct agp_fenv* env = agp_env();
	mout.state = true;

	switch(type){
	case STREAM_RAW:
		alloc_buffer(s);

		mout.buf = s->vinf.text.raw;
		mout.state = mout.buf != NULL;
	break;

	case STREAM_RAW_DIRECT_COPY:{
		alloc_buffer(s);

		size_t ntc = s->w * s->h;
		av_pixel* ptr = s->vinf.text.raw, (* buf) = meta.buf;
		s->update_ts = arcan_timemillis();

		if ( ((uintptr_t)ptr % 16) == 0 && ((uintptr_t)buf % 16) == 0	)
			memcpy(ptr, buf, ntc * sizeof(av_pixel));
		else
			for (size_t i = 0; i < ntc; i++)
				*ptr++ = *buf++;
	}
	break;

/* resynch: drop PBOs and GLid, alloc / upload and rebuild possible PBOs */
	case STREAM_EXT_RESYNCH:
		agp_null_vstore(s);
		agp_update_vstore(s, true);
	break;

	case STREAM_RAW_DIRECT:
	case STREAM_RAW_DIRECT_SYNCHRONOUS:
	agp_activate_vstore(s);
		env->tex_subimage_2d(GL_TEXTURE_2D, 0, 0, 0, s->w, s->h,
			s->vinf.text.s_fmt ? s->vinf.text.s_fmt : GL_PIXEL_FORMAT,
			GL_UNSIGNED_BYTE, meta.buf
		);
		agp_deactivate_vstore();
	break;

/* see notes in gl21.c */
	case STREAM_HANDLE:
		if (!s->vinf.text.glid){
			env->gen_textures(1, &s->vinf.text.glid);
			env->active_texture(GL_TEXTURE0);
			env->bind_texture(GL_TEXTURE_2D, s->vinf.text.glid);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		}
		mout.state = platform_video_map_buffer(s, meta.planes, meta.used);

	break;
	}

	return mout;
}

void agp_stream_release(struct agp_vstore* s, struct stream_meta meta)
{
}

void agp_stream_commit(struct agp_vstore* s, struct stream_meta meta)
{
}
