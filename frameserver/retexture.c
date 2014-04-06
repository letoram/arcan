/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
/
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,MA 02110-1301,USA.
 *
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

/* notification channel for discoveries / changes */	
	arcan_event* dqueue;

/* forward table for hijacked OGL functions */
	void (*teximage2d)(GLenum, GLint, GLint, 
		GLsizei, GLsizei, GLint, GLenum, GLenum, const GLvoid*);
	void (*deletetextures)(GLsizei, const GLuint*);

} retexctx;

static bool supported_format(GLenum target, GLint format)
{
	return (target == GL_TEXTURE_2D && 
		(	format == GL_RGBA || GL_BGRA )); 
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

/*
 * It is up to the calling library to perform the actual hijack,
 * e.g. patching the existing symbol to redirect / jump here
 * and a separate stack cleanup 
 */
void GLLOCAL_SYMBOL(glTexImage2D) (GLenum target, GLint level, GLint iformat, 
	GLsizei width, GLsizei height, GLint border, GLenum format, 
	GLenum type, const GLvoid* data)
{
	if (!retexctx.running || !supported_format(target, format))
		goto upload;

	size_t nb = width * height * 4;
	unsigned long id = djb_hash(data, nb); 

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
