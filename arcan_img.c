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

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <assert.h>
#include <stdbool.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_img.h"
#include "arcan_video.h"

#include <png.h>

struct png_readstr
{
	char* inbuf;
	off_t inbuf_ofs;
	size_t inbuf_sz;
};

/*
 * Ideally, this copy shouldn't be needed --
 * patch libpng to have a memory interface
 */ 
static void png_readfun(png_structp png_ptr, png_bytep outb, png_size_t ntr)
{
	struct png_readstr* indata = png_ptr->io_ptr;
	memcpy(outb, indata->inbuf + indata->inbuf_ofs, ntr);
	indata->inbuf_ofs += ntr;
}

int arcan_png_rgba32(char* inbuf, size_t inbuf_sz,
	char** outbuf, int* outw, int* outh,
	png_allocator pngalloc){
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;

/* HEADER check */	
	if (png_sig_cmp((unsigned char*) inbuf, 0, 8))
		return rv;

/* prepare read wrapper */
	png_structp png_ptr;
	if (!(png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING,
		 NULL, NULL, NULL)) )
		goto cleanup;

/* extract header fields */
	png_infop info_ptr;
	if ( !(info_ptr = png_create_info_struct(png_ptr)) )
		goto cleanup;

/* 
 * libpng expects a read() like interface, wrap
 * our memory buffer into that one 
 */
	struct png_readstr readptr = {
		.inbuf     = inbuf,
		.inbuf_ofs = 0,
		.inbuf_sz  = inbuf_sz
	};
	png_set_read_fn(png_ptr, &readptr, png_readfun);

/* 
 * finally we can access image data
 */
	png_read_info(png_ptr, info_ptr);
	*outw = 0;
	*outh = 0;

/* 
 * Get output buffer
 */ 
	png_uint_32 w, h;
	int bpp = 0;
	int cspace = -1;
	int32_t status = png_get_IHDR(png_ptr, info_ptr, &w, &h, &bpp,
		 &cspace, NULL, NULL, NULL);

	*outw = w;
	*outh = h;	
	
	if ( 1 != status || NULL == (*outbuf = pngalloc(w * h * /* 32bpp */ 4)) )
		goto cleanup;

/* interface requirement that outbuf comes aligned */
	int32_t* out32  = (int32_t*) *outbuf;
	uint8_t* rowdec =  malloc( png_get_rowbytes(png_ptr, info_ptr) );
	assert( (intptr_t)out32 % 4 == 0 && rowdec);

/*
 * color conversion -> precision matching, row-wise
 */
	if (cspace == PNG_COLOR_TYPE_RGB){
		for (int row = 0; row < h; row++){
			png_read_row(png_ptr, (png_bytep) rowdec, NULL);
			for (int col = 0; col < w * 3; col += 3)
				RGBAPACK(rowdec[col], rowdec[col+1], rowdec[col+2], 255, out32++);	
		}
		rv = ARCAN_OK;
	}
	else if (cspace == PNG_COLOR_TYPE_RGBA){
		for (int row = 0; row < h; row++){
			png_read_row(png_ptr, (png_bytep) rowdec, NULL);
			for (int col = 0; col < w * 4; col += 4)
				RGBAPACK(rowdec[col], rowdec[col+1], rowdec[col+2], rowdec[col+3], out32++);
		}
		rv = ARCAN_OK;
	}
	else {
		arcan_warning("arcan_png_rgba32() -- unsupported color-space (%d)\n", cspace);
		goto cleanup;
	}


cleanup:
	if (png_ptr)
		png_destroy_read_struct(&png_ptr, NULL, NULL);	

	return rv;

/* 
 * we don't clear *outbuf if it's allocated, that's up to the
 * caller to track. png_destroy_read will cascade to cleaning
 * up the other png structures we used
 */	
}

