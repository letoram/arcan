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
 *
 */

#ifndef _HAVE_ARCAN_PNG
#define _HAVE_ARCAN_PNG

/* 
 * these functions wrap libpng and add basic colour conversion
 */

typedef void* (*outimg_allocator)( size_t );

/* 
 * decode the supplied input buffer 'inbuf' (limited to 'inbuf_sz') and convert to GL- ready RGBA32.
 * 'outbuf' will be allocated by calling 'png_allocator', which could simply point to malloc for most uses
 * and the same result restrictions apply as with malloc (alignment etc.)
 */
arcan_errc arcan_png_rgba32(char* inbuf, size_t inbuf_sz, 
	char** outbuf, int* outw, int* outh, outimg_allocator);

arcan_errc arcan_jpg_rgba32(char* inbuf, size_t inbuf_sz, 
	char** outbuf, int* outw, int* outh, outimg_allocator);

/* 
 * treat 'inbuf' as a tightly packed RGBA32 buffer with the dimensions of (inw, inh)
 * and store the resulting output in 'outbuf'. The encoded size will be stored in outsz and allocated
 * by calling outimg_allocator, which could be set to malloc 
 */
arcan_errc arcan_rgba32_png(char* inbuf, int inw, int inh, char** outbuf, size_t* outsz, outimg_allocator);
#endif
