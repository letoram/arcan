/*
 * Arcan Retexturing Frameserver/Hijack Support Code (incomplete)
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <arcan_shmif.h>
#include <assert.h>

#include "retexture.h"

#include GL_HEADERS

#ifndef RETEXTURE_PREFIX
#define RETEXTURE_PREFIX
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define GLLOCAL_SYMBOL(fun) EVAL(RETEXTURE_PREFIX, fun)

/*
 * This weird hack tracks glTexImage* calls with checksum/ID
 * allowing for dumping or replacing. The reason for the interface
 * design is to allow it to be inserted into both the sdl hijacklib
 * and the libretro frameserver. Other plans including replacing
 * or modifying shaders, VBOs etc.
 */

/*
 * Limited set of color formats, only a single thread / glcontext
 * supported for now, no PBO transfers, no compressed textures,
 * no different mipmap- levels, only supported targets are TEXTURE_2D.
 */

/*
 * Work-items left:
 * 0. Setup a log (dump to disk) define that also stores hashid
 * 1. Test in situ replacement by hard-coding a specific texture swap
 * 2. Get the texture page preview output working
 * 3. Switch the hard coded swap with dynamic entries from parent
 * 4. Let parent switch between a static and a streamed source
 */

struct track_elem
{
/* we split between active and alive for now in order to
 * not have to update / reload when the underlying software uses
 * texture caches etc. slots are re-used on !active, !alive. */
	bool active, alive;

/* translation / detection */
	uint32_t djbhash;
	GLint glid;
	GLenum target;
	GLint format;

/* detect if mipmap levels are manually updated */
	int last_level;

/* detect if we have a streaming texture slot */
	int updates;

/* inbuf is copied on updates, until the number of updates in the
 * slot exceeds a certain value (or we flag that the extra cost
 * is accepted) to differentiate between static textures and those
 * with streaming updates */
	struct {
		int width;
		int height;
		int bpp;
		int stride;
		uint32_t* data;
	} inbuf, outbuf;
};

/*
 * we use this to (a) batch- alloc, (b) map GL-ID to linear IDs
 * (i.e. bucket increases incrementally, as do the subid which
 * is not a guarantee with OpenGL IDs.
 */
struct track_bucket
{
	struct track_elem* elems;
	size_t total, avail;
};

static struct {
/* states; uninitialized -> initialized -> running | suspended */
	int running;
	bool local_copy;
	int block_sz;

	struct track_bucket* buckets;
	int n_buckets;

	struct extcon {
		uint32_t* vidp;
		uint16_t* audp;
		struct arcan_shmif_cont* cont;
		struct arcan_evctx inevq;
		struct arcan_evctx outevq;
	} in, out;

/* notification channel for discoveries / changes */
	arcan_event* dqueue;

/* forward table for hijacked OGL functions */
	void (*teximage2d)(GLenum, GLint, GLint,
		GLsizei, GLsizei, GLint, GLenum, GLenum, const GLvoid*);
	void (*deletetextures)(GLsizei, const GLuint*);

} retexctx = {0};

static bool supported_format(GLenum target, GLint format)
{
	return (target == GL_TEXTURE_2D &&
		(	format == (GL_RGBA | GL_BGRA) ));
}

static struct track_elem* get_elem_byglid(unsigned long glid)
{
	for (int i=0; i < retexctx.n_buckets; i++){
		for (int j=0; j <retexctx.buckets[i].total; j++){
			if (retexctx.buckets[i].elems[j].glid == glid)
				return &retexctx.buckets[i].elems[j];
		}
	}

	return NULL;
}

static struct track_elem* get_elem_bydjbid(unsigned long id)
{
	for (int i=0; i < retexctx.n_buckets; i++){
		for (int j=0; j <retexctx.buckets[i].total; j++){
			if (retexctx.buckets[i].elems[j].djbhash == id)
				return &retexctx.buckets[i].elems[j];
		}
	}

	return NULL;
}

static struct track_elem* alloc_id(unsigned long id, int* bucket, int* elem)
{
	int dbucket = 0;

	for (; dbucket < retexctx.n_buckets; dbucket++)
		if (retexctx.buckets[dbucket].avail > 0 ||
			retexctx.buckets[dbucket].total == 0)
			break;

/* grow pool */
	if (dbucket == retexctx.n_buckets){
		size_t new_c = (retexctx.n_buckets + 1) * 2;
		struct track_bucket* newblock = realloc(retexctx.buckets,
			new_c * sizeof(struct track_bucket));

		if (!newblock)
			return NULL;

		retexctx.buckets = newblock;
		memset(&retexctx.buckets[dbucket], '\0',
			sizeof(struct track_bucket) * (new_c - retexctx.n_buckets));

		retexctx.n_buckets = new_c;
	}

/* populate with cells */
	if (retexctx.buckets[dbucket].total == 0){
		size_t nbsz = retexctx.block_sz;
		retexctx.block_sz *= 1.5;

		retexctx.buckets[dbucket].elems =
			malloc(sizeof(struct track_elem) * nbsz);

		if (!retexctx.buckets[dbucket].elems){
			return NULL;
		}

		memset(retexctx.buckets[dbucket].elems, '\0',
			sizeof(struct track_elem) * nbsz);

		retexctx.buckets[dbucket].avail = nbsz;
		retexctx.buckets[dbucket].total = nbsz;
	}

/* find first free */
	struct track_elem* dst = NULL;
	int slot = 0;
	for (; slot < retexctx.buckets[dbucket].total; slot++){
		if (!retexctx.buckets[dbucket].elems[slot].alive &&
			!retexctx.buckets[dbucket].elems[slot].active){
			dst = &retexctx.buckets[dbucket].elems[slot];
			break;
		}
	}

	assert(dst);

	retexctx.buckets[dbucket].avail--;
	dst->active = true;
	dst->djbhash = id;

	*bucket = dbucket;
	*elem = slot;

	return dst;
}

/*
 * We use hash (djb on data reversed) as a data identifier
 * across runs or tracking usage patterns where the same texture
 * will be updated in different slots
 */
static unsigned long djb_hash(const char* str, size_t nb)
{
	unsigned long hash = 5381;

	while (nb)
		hash = ((hash << 5) + hash) + str[nb--]; /* hash * 33 + c */

	return hash;
}

void arcan_retexture_tick()
{
	if (!retexctx.in.cont)
		return;

/* events we are interested in:
 * switching graphing mode
 * (i.e. how active texture preview should be refreshed on the output page)
 * incoming texture
 * (should be copied into local buffer and run through arcan retex_update)
 */
	arcan_event inev;
	while( arcan_event_poll(&retexctx.in.inevq, &inev) == 1 ){
	}

/*
 * FIXME: Rebuild active texture page (if dirty),
 * signal output for transfer
 */
}

/* #include "londepng.c" */
/*
 * It is up to the calling library to perform the actual hijack,
 * e.g. patching the existing symbol to redirect / jump here
 * and a separate stack cleanup
 */
void GLLOCAL_SYMBOL(glTexImage2D) (GLenum target, GLint level, GLint iformat,
	GLsizei width, GLsizei height, GLint border, GLenum format,
	GLenum type, const GLvoid* data)
{
	if (!retexctx.running || !supported_format(target, format) ||
		width < 64 || height < 64)
		goto upload;

	size_t nb = width * height * 4;
	unsigned long id = djb_hash(data, nb);

	char comp[64];
	static int seqn;
	snprintf(comp, 64, "dump_%d_%ld.png", seqn++, id);
/*	lodepng_encode32_file(comp, data, width, height); */
/*
 * we also use texture updates as a "tick" to determine which
 * cached textured could be discarded to not have the decay run
 * rampant and "leak" memory
 */

	GLint did;
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &did);
	struct track_elem* delem = get_elem_bydjbid(id);

	if (!delem){
		int bucket, elem;
		delem = alloc_id(did, &bucket, &elem);
	}

	delem->glid = did;

	if (retexctx.local_copy){
		if (delem->inbuf.data)
			free(delem->inbuf.data);

		delem->inbuf.data = malloc(nb);
		delem->inbuf.width = width;
		delem->inbuf.height = height;
		delem->inbuf.data = malloc(nb);
		delem->inbuf.stride = width * 4;
	 	memcpy(delem->inbuf.data, data, nb);

		delem->format = format;
		delem->last_level = level;
	}

/* already have an impostor defined, don't let the upload go through */
	if (delem->outbuf.data)
		return;

upload:
	retexctx.teximage2d(target, level, iformat, width,
		height, border, format, type, data);
}

void GLLOCAL_SYMBOL(glDeleteTextures) (GLsizei n, const GLuint* textures)
{
/* 1. mark the block as invalid */
	for (int i = 0; i < n; i++){
		struct track_elem* delem = get_elem_byglid(textures[i]);
		if (delem)
			delem->active = false;
	}

/* 2. (optional) emit event */

/* 3. forward */
	retexctx.deletetextures(n, textures);
}

void arcan_retexture_update(int bucket, int id,
	int w, int h, int bpp, int stride, void* buf)
{
/*
 * 1. get entry pointer
 * 2. deallocate previous local copy (if any) and get a new one
 * 3. copy data into the new one
 * 4. run appropriate glTexImage call to update
 */
}

/*
 * Request a copy of the original state for a known ID
 * by its bucket, ...
 */
void* arcan_retexture_fetchp(int bucket, int id,
	int* w, int* h, int* bpp, int* stride)
{
	return NULL;
}

void* arcan_retexture_fetchid(GLuint tid, int* w,
	int* h, int* bpp, int* stride)
{
	return NULL;
}

void arcan_retexture_enable()
{
	retexctx.running = true;
}

void arcan_retexture_disable()
{
	retexctx.running = false;
}

void arcan_retexture_update_shmif(
	struct arcan_shmif_cont* inseg,
	struct arcan_shmif_cont* outseg)
{
/*
 * FIXME: free if new inseg is sent,
 * this implies that the parent has switched to a different
 * output mechanism (explicit push or stream)
 */
	if (inseg){
		retexctx.in.cont = inseg;
		arcan_shmif_calcofs( retexctx.in.cont->addr,
			(uint8_t**) &retexctx.in.vidp, (uint8_t**) &retexctx.in.audp);
		arcan_shmif_setevqs(retexctx.in.cont->addr, retexctx.in.cont->esem,
			&(retexctx.in.inevq), &(retexctx.in.outevq), false);
	}

	if (outseg){
		retexctx.out.cont = outseg;
		arcan_shmif_calcofs( retexctx.out.cont->addr,
			(uint8_t**) &retexctx.out.vidp, (uint8_t**) &retexctx.out.audp);
		arcan_shmif_setevqs(retexctx.in.cont->addr, retexctx.in.cont->esem,
			&(retexctx.in.inevq), &(retexctx.in.outevq), false);
	}
}

/*
 * If <ann> is set, textures arriving / disappearing will be
 * emitted to this buffer. Set local to true if we should maintain
 * local copies
 */
void arcan_retexture_init(arcan_event* ann, bool local)
{
	retexctx.running = false;
	retexctx.dqueue = ann;
	retexctx.block_sz = 16;
	retexctx.local_copy = true;
	retexctx.teximage2d = GLSYM_FUNCTION("glTexImage2D");
	retexctx.deletetextures = GLSYM_FUNCTION("glDeleteTextures");
}
