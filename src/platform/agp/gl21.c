/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>
#include <unistd.h>

#include "glfun.h"

#include "../video_platform.h"
#include PLATFORM_HEADER

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

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

const char* agp_ident()
{
	return "OPENGL21";
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

const char** agp_envopts()
{
	static const char* env[] = {
		NULL, NULL
	};
	return env;
}

const char* agp_shader_language()
{
	return "GLSL120";
}

static void set_pixel_store(size_t w, struct stream_meta const meta)
{
	glPixelStorei(GL_UNPACK_SKIP_ROWS, meta.y1);
	glPixelStorei(GL_UNPACK_SKIP_PIXELS, meta.x1);
	glPixelStorei(GL_UNPACK_ROW_LENGTH, w);
}

static void reset_pixel_store()
{
	glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
	glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
	glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
}

void agp_readback_synchronous(struct storage_info_t* dst)
{
	if (!(dst->txmapped == TXSTATE_TEX2D) || !dst->vinf.text.raw)
		return;

	glBindTexture(GL_TEXTURE_2D, dst->vinf.text.glid);
	glGetTexImage(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT,
		GL_UNSIGNED_BYTE, dst->vinf.text.raw);
	dst->update_ts = arcan_timemillis();
	glBindTexture(GL_TEXTURE_2D, 0);
}

void agp_drop_vstore(struct storage_info_t* s)
{
	if (!s)
		return;

	glDeleteTextures(1, &s->vinf.text.glid);
	s->vinf.text.glid = 0;

	if (GL_NONE != s->vinf.text.rid)
		glDeleteBuffers(1, &s->vinf.text.rid);

	if (GL_NONE != s->vinf.text.wid)
		glDeleteBuffers(1, &s->vinf.text.wid);

	if (s->vinf.text.tag)
		platform_video_map_handle(s, -1);
}

static void pbo_stream(struct storage_info_t* s,
	av_pixel* buf, struct stream_meta* meta, bool synch)
{
	agp_activate_vstore(s);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, s->vinf.text.wid);
	size_t ntc = s->w * s->h;

	av_pixel* ptr = glMapBuffer(GL_PIXEL_UNPACK_BUFFER,GL_WRITE_ONLY);

	if (!ptr)
		return;

	av_pixel* obuf = buf;

/* note, explicitly replace with a simd unaligned version */
	if ( ((uintptr_t)ptr % 16) == 0 && ((uintptr_t)buf % 16) == 0	)
		memcpy(ptr, buf, ntc * sizeof(av_pixel));
	else
		for (size_t i = 0; i < ntc; i++)
			*ptr++ = *buf++;

/* synch :- on-host backing store, one extra copy into local buffer */
	if (synch){
		buf = obuf;
		ptr = s->vinf.text.raw;
		s->update_ts = arcan_timemillis();

		if ( ((uintptr_t)ptr % 16) == 0 && ((uintptr_t)buf % 16) == 0	)
			memcpy(ptr, buf, ntc * sizeof(av_pixel));
		else
			for (size_t i = 0; i < ntc; i++)
				*ptr++ = *buf++;
	}

	glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);

	glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, s->w, s->h,
		GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, 0);

	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
	agp_deactivate_vstore();
}

/* positions and offsets in meta have been verified in _frameserver */
static void pbo_stream_sub(struct storage_info_t* s,
	av_pixel* buf, struct stream_meta* meta, bool synch)
{
	if ( (float)(meta->w * meta->h) / (s->w * s->h) > 0.5)
		return pbo_stream(s, buf, meta, synch);

	agp_activate_vstore(s);
	size_t row_sz = meta->w * sizeof(av_pixel);
	set_pixel_store(s->w, *meta);
	glTexSubImage2D(GL_TEXTURE_2D, 0, meta->x1, meta->y1, meta->w, meta->h,
		GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, buf);
	reset_pixel_store();
	agp_deactivate_vstore(s);

	if (synch){
		av_pixel* cpy = s->vinf.text.raw;
		for (size_t y = meta->y1; y < meta->y1 + meta->h; y++)
		memcpy(&cpy[y * s->w + meta->x1], &buf[y * s->w + meta->x1], row_sz);
		s->update_ts = arcan_timemillis();
	}

/*
 * Currently disabled approach to update subregion using PBO, experienced
 * data corruption / driver bugs on several drivers :'(
 */

#if 0
	av_pixel* ptr = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY);

glBindBuffer(GL_PIXEL_UNPACK_BUFFER, s->vinf.text.wid);


/* warning, with the normal copy we check alignment in beforehand as we have
 * had cases where glMapBuffer intermittently returns unaligned pointers AND
 * the compiler has emitted intrinsics that assumed alignment */
	for (size_t y = meta->y1; y < meta->y1 + meta->h; y++)
		memcpy(&ptr[y * s->w + meta->x1], &buf[y * s->w + meta->x1], row_sz);

		glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
	glTexSubImage2D(GL_TEXTURE_2D, 0, meta->x1, meta->y1, meta->w, meta->h,
		GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, 0);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
#endif
}

static inline void setup_unpack_pbo(struct storage_info_t* s, void* buf)
{
	agp_activate_vstore(s);
	glGenBuffers(1, &s->vinf.text.wid);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, s->vinf.text.wid);
	glBufferData(GL_PIXEL_UNPACK_BUFFER,
		s->w * s->h * sizeof(av_pixel) , buf, GL_STREAM_DRAW);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
	agp_deactivate_vstore();
}

static void alloc_buffer(struct storage_info_t* s)
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

struct stream_meta agp_stream_prepare(struct storage_info_t* s,
		struct stream_meta meta, enum stream_type type)
{
	struct stream_meta res = meta;
	res.state = true;
	res.type = type;

	switch (type){
	case STREAM_RAW:
		if (!s->vinf.text.wid)
			setup_unpack_pbo(s, NULL);

		alloc_buffer(s);

		res.buf = s->vinf.text.raw;
		res.state = res.buf != NULL;
	break;

	case STREAM_RAW_DIRECT_COPY:
		alloc_buffer(s);

	case STREAM_RAW_DIRECT:
		if (!s->vinf.text.wid)
			setup_unpack_pbo(s, meta.buf);

		if (meta.dirty)
			pbo_stream_sub(s, meta.buf, &meta, type == STREAM_RAW_DIRECT_COPY);
		else
			pbo_stream(s, meta.buf, &meta, type == STREAM_RAW_DIRECT_COPY);
	break;

	case STREAM_RAW_DIRECT_SYNCHRONOUS:
		agp_activate_vstore(s);

		if (meta.dirty){
			set_pixel_store(s->w, meta);
			glTexSubImage2D(GL_TEXTURE_2D, 0, meta.x1, meta.y1, meta.w, meta.h,
				GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, meta.buf);
			reset_pixel_store();
		}
		else
			glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, s->w, s->h,
				GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, meta.buf);
		agp_deactivate_vstore();
	break;

	case STREAM_HANDLE:
/* if platform_video_map_handle fails here, prepare an empty vstore and attempt
 * again, if that succeeds it means that we had to go through a RTT
 * indirection, if that fails we should convey back to the client that
	we can't accept this kind of transfer */
	res.state = platform_video_map_handle(s, meta.handle);
	break;
	}

	return res;
}

void agp_stream_release(struct storage_info_t* s, struct stream_meta meta)
{
	if (meta.dirty)
		pbo_stream_sub(s, s->vinf.text.raw, &meta, false);
	else
		pbo_stream(s, s->vinf.text.raw, &meta, false);
	glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, GL_NONE);
}

void agp_stream_commit(struct storage_info_t* s, struct stream_meta meta)
{
}

static void pbo_alloc_read(struct storage_info_t* store)
{
	GLuint pboid;
	glGenBuffers(1, &pboid);
	store->vinf.text.rid = pboid;

	glBindBuffer(GL_PIXEL_PACK_BUFFER, pboid);
	glBufferData(GL_PIXEL_PACK_BUFFER,
		store->w * store->h * store->bpp, NULL, GL_STREAM_COPY);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
}

static void pbo_alloc_write(struct storage_info_t* store)
{
	GLuint pboid;
	glGenBuffers(1, &pboid);
	store->vinf.text.wid = pboid;

	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pboid);
	glBufferData(GL_PIXEL_UNPACK_BUFFER,
		store->w * store->h * store->bpp, NULL, GL_STREAM_DRAW);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
}

static void default_release(void* tag)
{
	if (!tag)
		return;

	glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
}

void agp_resize_vstore(struct storage_info_t* s, size_t w, size_t h)
{
	s->w = w;
	s->h = h;
	s->bpp = sizeof(av_pixel);

	alloc_buffer(s);

	if (s->vinf.text.wid){
		glDeleteBuffers(1, &s->vinf.text.wid);
		pbo_alloc_write(s);
	}

	if (s->vinf.text.rid){
		glDeleteBuffers(1, &s->vinf.text.rid);
		pbo_alloc_read(s);
	}

	agp_update_vstore(s, true);
}

void agp_request_readback(struct storage_info_t* store)
{
	if (!store || store->txmapped != TXSTATE_TEX2D)
		return;

	if (!store->vinf.text.rid)
		pbo_alloc_read(store);

	glBindTexture(GL_TEXTURE_2D, store->vinf.text.glid);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, store->vinf.text.rid);
	glGetTexImage(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, NULL);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
	glBindTexture(GL_TEXTURE_2D, 0);
}

struct asynch_readback_meta agp_poll_readback(struct storage_info_t* store)
{
	struct asynch_readback_meta res = {
	.release = default_release
	};

	if (!store || store->txmapped != TXSTATE_TEX2D ||
		store->vinf.text.rid == GL_NONE)
		return res;

	glBindBuffer(GL_PIXEL_PACK_BUFFER, store->vinf.text.rid);

	res.w = store->w;
	res.h = store->h;
	res.tag = (void*) 0xdeadbeef;
	res.ptr = (av_pixel*) glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_READ_WRITE);

	return res;
}
