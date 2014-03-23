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

#include GL_HEADERS

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
	uint32_t djbhash;
	GLint glid;
	GLenum target;
	GLint format;
	int last_level;
	int updates;

/* inbuf is copied on updates, until the number of updates in the
 * slot exceeds a certain value (or we flag that the extra cost 
 * is accepted) to differentiate between static textures and those
 * with streaming updates */
	uint32_t* inbuf;
	uint32_t* outbuf;
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
	arcan_event* dqueue;
	struct track_bucket* buckets;	
	bool running;
} retexture_state;

static bool supported_format(GLenum target, GLint format)
{
	return (target == GL_TEXTURE_2D && 
		(	format == GL_RGBA || GL_BGRA )); 
}

/*
 * We use hash (djb on data reversed) as a data identifier
 * across runs
 */ 
static unsigned long djb_hash(const char* str, size_t nb)
{
	unsigned long hash = 5381;
	int c;

	while (nb)
		hash = ((hash << 5) + hash) + str[nb--]; /* hash * 33 + c */

	return hash;
}

/*
 * It is up to the calling library to perform the actual hijack,
 * e.g. patching the existing symbol to redirect / jump here
 * and a separate stack cleanup 
 */
void arcan_glTexImage2D(GLenum target, GLint level, GLsizei width,
	GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid* data)
{
	if (!retexture_state.running || !supported_format(format)){
		rextexture_state.teximage2d(target, level, width, 
			height, border, format, type, data);
		return;
	}

	GLint did;
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &did);
	struct track_elem* delem = get_elem_byglid(did);
	if (!delem){
		delem = alloc_id( did, 
			djb_hash((const char*) data, width * height * 4),
			width * height * 4 );
	}

	retexture_state.teximage2d(target, level, width,
		height, border, format, type, data);	
}

void arcan_glDeleteTextures(GLsizei n, const GLuint* textures)
{
/* 1. mark the block as invalid */
/* 2. (optional) emit event */
	retexture_state.deletetextures(n, textures);
}

void arcan_frameserver_retexture_update(int bucket, int id,
	int w, int h, int bpp, int stride, void* buf)
{
/*
 * 1. get entry pointer
 * 2. deallocate previous local copy (if any) and get a new one
 * 3. copy data into the new one
 * 4. run appropriate glTexImage call to update
 */ 
}

static void* fetch_texture(struct track_elem* src, 
	int* w, int* h, int*bpp, int* stride)
{
	return NULL;
}

/*
 * Request a copy of the original state for a known ID
 * by its bucket, ...
 */
void* arcan_frameserver_retexture_fetchp(int bucket, int id,
	int* w, int* h, int* bpp, int* stride){
i	
	return fetch_texture(retexture_state.buckets[bucket].
}

void* arcan_frameserver_retexture_fetchid(GLuint tid, int* w,
	int* h, int* bpp, int* stride)
{
	return NULL;	
}

/* 
 * If <ann> is set, textures arriving / disappearing will be 
 * emitted to this buffer. Set local to true if we should maintain
 * local copies
 */
void arcan_frameserver_retexture_init(arcan_event* ann, bool local)
{
	retexture_state.running = false;
	retexture_state.dqueue = ann;
/* 
 * map up pointers to wrapper functions
 */ 
}
