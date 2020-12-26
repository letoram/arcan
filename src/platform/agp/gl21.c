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
#include <inttypes.h>

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

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

#define debug_print(fmt, ...) \
            do { if (DEBUG) arcan_warning("%lld:%s:%d:%s(): " fmt "\n",\
						arcan_timemillis(), "agp-gl21:", __LINE__, __func__,##__VA_ARGS__); } while (0)

#ifndef verbose_print
#define verbose_print
#endif

agp_shader_id agp_default_shader(enum SHADER_TYPES type)
{
	verbose_print("set shader: %s", type == BASIC_2D ? "basic_2d" :
		(type == COLOR_2D ? "color_2d" : (type == BASIC_3D ? "basic_3d" : "invalid")));

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

static void pbo_alloc_read(struct agp_vstore* store)
{
	GLuint pboid;
	struct agp_fenv* env = agp_env();
	env->gen_buffers(1, &pboid);
	store->vinf.text.rid = pboid;

	env->bind_buffer(GL_PIXEL_PACK_BUFFER, pboid);
	env->buffer_data(GL_PIXEL_PACK_BUFFER,
		store->w * store->h * store->bpp, NULL, GL_STREAM_COPY);
	env->bind_buffer(GL_PIXEL_PACK_BUFFER, 0);

	verbose_print("allocated %zu*%zu read-pbo",
		(size_t) store->w, (size_t) store->h);
}

static void pbo_alloc_write(struct agp_vstore* store)
{
	GLuint pboid;
	struct agp_fenv* env = agp_env();
	env->gen_buffers(1, &pboid);
	store->vinf.text.wid = pboid;

	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, pboid);
	env->buffer_data(GL_PIXEL_UNPACK_BUFFER,
		store->w * store->h * store->bpp, NULL, GL_STREAM_DRAW);
	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, 0);

	verbose_print("allocated %zu*%zu write-pbo",
		(size_t) store->w, (size_t) store->h);
}

static void rebuild_pbo(struct agp_vstore* s)
{
	struct agp_fenv* env = agp_env();
	if (s->vinf.text.wid){
		env->delete_buffers(1, &s->vinf.text.wid);
		pbo_alloc_write(s);
	}

	if (s->vinf.text.rid){
		env->delete_buffers(1, &s->vinf.text.rid);
		pbo_alloc_read(s);
	}
}

static void set_pixel_store(size_t w, struct stream_meta const meta)
{
	struct agp_fenv* env = agp_env();
	env->pixel_storei(GL_UNPACK_SKIP_ROWS, meta.y1);
	env->pixel_storei(GL_UNPACK_SKIP_PIXELS, meta.x1);
	env->pixel_storei(GL_UNPACK_ROW_LENGTH, w);
	verbose_print(
		"pixel store: skip %zu rows, %zu pixels, len: %zu", meta.x1, meta.y1, w);
}

static void reset_pixel_store()
{
	struct agp_fenv* env = agp_env();
	env->pixel_storei(GL_UNPACK_SKIP_ROWS, 0);
	env->pixel_storei(GL_UNPACK_SKIP_PIXELS, 0);
	env->pixel_storei(GL_UNPACK_ROW_LENGTH, 0);
	verbose_print("pixel store: reset");
}

void agp_readback_synchronous(struct agp_vstore* dst)
{
	if (!(dst->txmapped == TXSTATE_TEX2D) || !dst->vinf.text.raw)
		return;
	struct agp_fenv* env = agp_env();

	verbose_print(
		"synchronous readback from id: %u", (unsigned)agp_resolve_texid(dst));

	env->bind_texture(GL_TEXTURE_2D, agp_resolve_texid(dst));
	env->get_tex_image(GL_TEXTURE_2D, 0,
		GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, dst->vinf.text.raw);
	dst->update_ts = arcan_timemillis();
	env->bind_texture(GL_TEXTURE_2D, 0);
}

static void pbo_stream(struct agp_vstore* s,
	av_pixel* buf, struct stream_meta* meta, bool synch)
{
	agp_activate_vstore(s);
	struct agp_fenv* env = agp_env();

	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, s->vinf.text.wid);
	size_t ntc = s->w * s->h;

	av_pixel* ptr = env->map_buffer(GL_PIXEL_UNPACK_BUFFER,GL_WRITE_ONLY);

	if (!ptr){
		verbose_print("(%"PRIxPTR") failed to map PBO for writing", (uintptr_t) s);
		return;
	}

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

	verbose_print(
		"(%"PRIxPTR") pbo stream update %zu*%zu", (uintptr_t) s, s->w, s->h);

	env->unmap_buffer(GL_PIXEL_UNPACK_BUFFER);

	env->tex_subimage_2d(GL_TEXTURE_2D, 0, 0, 0, s->w, s->h,
		s->vinf.text.s_fmt ? s->vinf.text.s_fmt : GL_PIXEL_FORMAT,
		GL_UNSIGNED_BYTE, 0
	);

	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, 0);
	agp_deactivate_vstore();
}

/* positions and offsets in meta have been verified in _frameserver */
static void pbo_stream_sub(struct agp_vstore* s,
	av_pixel* buf, struct stream_meta* meta, bool synch)
{
	struct agp_fenv* env = agp_env();
	if ( (float)(meta->w * meta->h) / (s->w * s->h) > 0.5)
		return pbo_stream(s, buf, meta, synch);

	agp_activate_vstore(s);
	size_t row_sz = meta->w * sizeof(av_pixel);
	set_pixel_store(s->w, *meta);

	verbose_print(
		"(%"PRIxPTR") pbo stream sub-update %zu+%zu*%zu+%zu",
		(uintptr_t) s, meta->x1, meta->w, meta->y1, meta->h
	);

	env->tex_subimage_2d(GL_TEXTURE_2D, 0, meta->x1, meta->y1, meta->w, meta->h,
		s->vinf.text.s_fmt ? s->vinf.text.s_fmt : GL_PIXEL_FORMAT,
		GL_UNSIGNED_BYTE, buf
	);
	reset_pixel_store();
	agp_deactivate_vstore(s);

	if (synch){
		size_t x2 = meta->x1 + meta->w;
		size_t y2 = meta->y1 + meta->h;

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

static inline void setup_unpack_pbo(struct agp_vstore* s, void* buf)
{
	struct agp_fenv* env = agp_env();
	agp_activate_vstore(s);
	verbose_print("(%"PRIxPTR") build unpack", (uintptr_t) s);
	env->gen_buffers(1, &s->vinf.text.wid);
	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, s->vinf.text.wid);
	env->buffer_data(GL_PIXEL_UNPACK_BUFFER,
		s->w * s->h * sizeof(av_pixel) , buf, GL_STREAM_DRAW);
	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, 0);
	agp_deactivate_vstore();
}

static void alloc_buffer(struct agp_vstore* s)
{
	if (s->vinf.text.s_raw != s->w * s->h * sizeof(av_pixel)){
		arcan_mem_free(s->vinf.text.raw);
		s->vinf.text.raw = NULL;
	}

	if (!s->vinf.text.raw){
		verbose_print("(%"PRIxPTR") alloc buffer", (uintptr_t) s);
		s->vinf.text.s_raw = s->w * s->h * sizeof(av_pixel);
		s->vinf.text.raw = arcan_alloc_mem(s->vinf.text.s_raw,
			ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);
	}
}

struct stream_meta agp_stream_prepare(struct agp_vstore* s,
		struct stream_meta meta, enum stream_type type)
{
	struct agp_fenv* env = agp_env();
	struct stream_meta res = meta;
	res.state = true;
	res.type = type;

	switch (type){
	case STREAM_RAW:
		verbose_print("(%"PRIxPTR") prepare upload (raw)", (uintptr_t) s);
		if (!s->vinf.text.wid)
			setup_unpack_pbo(s, NULL);

		alloc_buffer(s);

		res.buf = s->vinf.text.raw;
		res.state = res.buf != NULL;
	break;

	case STREAM_RAW_DIRECT_COPY:
		alloc_buffer(s);
	case STREAM_RAW_DIRECT:
		verbose_print("(%"PRIxPTR") prepare upload (raw/direct)", (uintptr_t) s);
		if (!s->vinf.text.wid)
			setup_unpack_pbo(s, meta.buf);

		if (meta.dirty)
			pbo_stream_sub(s, meta.buf, &meta, type == STREAM_RAW_DIRECT_COPY);
		else
			pbo_stream(s, meta.buf, &meta, type == STREAM_RAW_DIRECT_COPY);
	break;

/* resynch: drop PBOs and GLid, alloc / upload and rebuild possible PBOs */
	case STREAM_EXT_RESYNCH:
		verbose_print("(%"PRIxPTR") resynch stream", (uintptr_t) s);
		agp_null_vstore(s);
		agp_update_vstore(s, true);
		rebuild_pbo(s);
	break;

	case STREAM_RAW_DIRECT_SYNCHRONOUS:
		agp_activate_vstore(s);

		if (meta.dirty){
			verbose_print("(%"PRIxPTR") raw synch sub (%zu+%zu*%zu+%zu)",
				(uintptr_t) s, meta.x1, meta.w, meta.y1, meta.h);
			set_pixel_store(s->w, meta);
			env->tex_subimage_2d(GL_TEXTURE_2D, 0, meta.x1, meta.y1, meta.w, meta.h,
				s->vinf.text.s_fmt ? s->vinf.text.s_fmt : GL_PIXEL_FORMAT,
				GL_UNSIGNED_BYTE, meta.buf
			);

			reset_pixel_store();
		}
		else{
			verbose_print(
				"(%"PRIxPTR") raw synch (%zu*%zu)", (uintptr_t) s, meta.w, meta.h);
				env->tex_subimage_2d(GL_TEXTURE_2D, 0, 0, 0, s->w, s->h,
				s->vinf.text.s_fmt ? s->vinf.text.s_fmt : GL_PIXEL_FORMAT,
				GL_UNSIGNED_BYTE, meta.buf
			);
		}
		agp_deactivate_vstore();
	break;

	case STREAM_HANDLE:
/* bind eglImage to GLID, and we don't have any filtering for external,
 * also cheat a bit around vstore setup */
		if (!s->vinf.text.glid){
			env->gen_textures(1, &s->vinf.text.glid);
			env->active_texture(GL_TEXTURE0);
			env->bind_texture(GL_TEXTURE_2D, s->vinf.text.glid);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			env->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		}

/* There is a subtle thing here in that the format might not be immediately
 * usable, particularly so with multiplanar objects. In those cases we need
 * a reblit-stage setup, and the vstore structure is not prepared for this
 * yet (possibly as a src_vstore and a repack shader) */
		res.state = platform_video_map_buffer(s, meta.planes, meta.used);

/* Even if this fails, keep the glid around as it'll be life-span managed
 * with the originating source rather and the failure-fallback path will
 * push us to repopulate */
	break;
	}

	return res;
}

void agp_stream_release(struct agp_vstore* s, struct stream_meta meta)
{
	struct agp_fenv* env = agp_env();
	if (meta.dirty)
		pbo_stream_sub(s, s->vinf.text.raw, &meta, false);
	else
		pbo_stream(s, s->vinf.text.raw, &meta, false);

	verbose_print("(%"PRIxPTR") release", (uintptr_t) s);
	env->unmap_buffer(GL_PIXEL_UNPACK_BUFFER);
	env->bind_buffer(GL_PIXEL_UNPACK_BUFFER, GL_NONE);
}

void agp_stream_commit(struct agp_vstore* s, struct stream_meta meta)
{
}

static void default_release(void* tag)
{
	if (!tag)
		return;
	struct agp_fenv* env = agp_env();

	env->unmap_buffer(GL_PIXEL_PACK_BUFFER);
	env->bind_buffer(GL_PIXEL_PACK_BUFFER, 0);
}

void agp_resize_vstore(struct agp_vstore* s, size_t w, size_t h)
{
	struct agp_fenv* env = agp_env();
	s->w = w;
	s->h = h;
	s->bpp = sizeof(av_pixel);

	verbose_print("(%"PRIxPTR") resize to %zu * %zu", (uintptr_t) s, w, h);
	alloc_buffer(s);
	rebuild_pbo(s);

	agp_update_vstore(s, true);
}

void agp_request_readback(struct agp_vstore* store)
{
	if (!store || store->txmapped != TXSTATE_TEX2D)
		return;
	struct agp_fenv* env = agp_env();

	if (!store->vinf.text.rid)
		pbo_alloc_read(store);

	verbose_print("(%"PRIxPTR":glid %u) getTexImage2D => PBO",
		(uintptr_t) store, (unsigned) store->vinf.text.glid);

	env->bind_texture(GL_TEXTURE_2D, agp_resolve_texid(store));
	env->bind_buffer(GL_PIXEL_PACK_BUFFER, store->vinf.text.rid);
	env->get_tex_image(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, NULL);
	env->bind_buffer(GL_PIXEL_PACK_BUFFER, 0);
	env->bind_texture(GL_TEXTURE_2D, 0);
}

struct asynch_readback_meta agp_poll_readback(struct agp_vstore* store)
{
	struct agp_fenv* env = agp_env();
	struct asynch_readback_meta res = {
	.release = default_release
	};

	if (!store || store->txmapped != TXSTATE_TEX2D ||
		store->vinf.text.rid == GL_NONE)
		return res;

	env->bind_buffer(GL_PIXEL_PACK_BUFFER, store->vinf.text.rid);

	res.w = store->w;
	res.h = store->h;
	res.tag = (void*) 0xdeadbeef;
	res.ptr = (av_pixel*) env->map_buffer(GL_PIXEL_PACK_BUFFER, GL_READ_WRITE);

	return res;
}
