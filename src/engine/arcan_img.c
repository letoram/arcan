/*
 * Copyright 2013-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <assert.h>
#include <stdio.h>
#include <inttypes.h>
#include <stdbool.h>
#include <string.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_img.h"
#include "arcan_video.h"

#define STBI_MALLOC(sz) (arcan_alloc_mem(sz, ARCAN_MEM_VBUFFER, \
	ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE))

#define STBI_FREE(ptr) (arcan_mem_free(ptr))
#define STBI_REALLOC(p,sz) realloc(p,sz)

#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_IMAGE_STATIC
#define STBI_NO_FAILURE_STRINGS
#define STB_IMAGE_WRITE_STATIC
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION

#include "external/stb_image.h"
#include "external/stb_image_write.h"

struct png_readstr
{
	char* inbuf;
	off_t inbuf_ofs;
	size_t inbuf_sz;
};

arcan_errc arcan_img_outpng(FILE* dst,
	av_pixel* inbuf, size_t inw, size_t inh, bool vflip)
{
	int outln = 0;
	bool dynout = false;
	unsigned char* outbuf = (unsigned char*) inbuf;

/* repack if the platform defines a different format than LE RGBA */
	if (sizeof(av_pixel) != 4 || RGBA(0xff, 0xaa, 0x77, 0x55) != 0x5577aaff){
		av_pixel* work = inbuf;

		uint32_t* repack = arcan_alloc_mem(inw * inh * 4, ARCAN_MEM_VBUFFER,
			ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
		if (!repack)
			return ARCAN_ERRC_OUT_OF_SPACE;
		outbuf = (unsigned char*) repack;

#define RPACK(r, g, b, a)( ((uint32_t)(a) << 24) | ((uint32_t) (b) << 16) |\
((uint32_t) (g) << 8) | ((uint32_t) (r)) )
		if (vflip){
			for (ssize_t y = inh-1; y >= 0; y--)
				for (size_t x = 0; x < inw; x++){
						uint8_t r, g, b, a;
						RGBA_DECOMP(work[y*inw+x], &r, &g, &b, &a);
						*repack++ = RPACK(r, g, b, a);
				}
		}
		else{
			size_t count = inw * inh;
			while(count--){
				uint8_t r, g, b, a;
				RGBA_DECOMP(*work++, &r, &g, &b, &a);
				*repack++ = RPACK(r, g, b, a);
			}
		}
#undef RPACK
		dynout = true;
	}
	else if (vflip){
		size_t stride = inw * 4;
		outbuf = arcan_alloc_mem(stride * inh, ARCAN_MEM_VBUFFER,
			ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

		if (!outbuf)
				return ARCAN_ERRC_OUT_OF_SPACE;

		for (ssize_t row = inh-1, step = 0; row >= 0; row--, step++)
			memcpy(&outbuf[step * stride], &inbuf[row*inw], stride);
	}

	unsigned char* png = stbi_write_png_to_mem(
		(unsigned char*) outbuf, 0, inw, inh, 4, &outln);

	fwrite(png, 1, outln, dst);
	arcan_mem_free(png);

	if (vflip || dynout)
		arcan_mem_free(outbuf);

	return ARCAN_OK;
}

av_pixel* arcan_img_repack(uint32_t* inbuf, size_t inw, size_t inh)
{
	if (sizeof(av_pixel) == 4 && RGBA(0x00, 0x00, 0xff, 0x00) == 0x00ff0000)
		return (av_pixel*) inbuf;

	av_pixel* imgbuf = arcan_alloc_mem(sizeof(av_pixel) * inw * inh,
		ARCAN_MEM_VBUFFER | ARCAN_MEM_NONFATAL, 0, ARCAN_MEMALIGN_PAGE);

		if (!imgbuf)
			goto done;

	uint32_t* in_work = inbuf;
	av_pixel* work = imgbuf;
	for (size_t count = inw * inh; count > 0; count--){
		uint32_t val = *in_work++;
		*work++ = RGBA(
 			((val & 0x000000ff) >> 0),
			((val & 0x0000ff00) >> 8),
			((val & 0x00ff0000) >> 16),
			((val & 0xff000000) >> 24)
		);
	}

done:
	arcan_mem_free(inbuf);
	return imgbuf;
}

arcan_errc arcan_pkm_raw(const uint8_t* inbuf, size_t inbuf_sz,
		uint32_t** outbuf, size_t* outw, size_t* outh, struct arcan_img_meta* meta)
{
#ifdef ETC1_SUPPORT
/* extract header fields */
	int pwidth  = (inbuf[ 8] << 8) | inbuf[ 9];
	int pheight = (inbuf[10] << 8) | inbuf[11];
	int width   = (inbuf[12] << 8) | inbuf[13];
	int height  = (inbuf[14] << 8) | inbuf[15];

/* strip header */
	*outbuf = arcan_mem_alloc(inbuf_sz - 16,
		ARCAN_MEM_VBUFFER, ARCAN_MEMALIGN_PAGE);

	memcpy(*outbuf, inbuf + 16, inbuf_sz - 16);
	meta->compressed = true;
	meta->pwidth = pwidth;
	meta->pheight = pheight;
	meta->c_size = (pwidth * pheight) >> 1;
	*outw = width;
	*outh = height;

	return ARCAN_OK;
#else
	return ARCAN_ERRC_UNSUPPORTED_FORMAT;
#endif
}

/*
struct dds_data_fmt
{
	GLsizei  width;
	GLsizei  height;
	GLint    components;
	GLenum   format;
	int      numMipMaps;
	GLubyte *pixels;
};
*/

arcan_errc arcan_dds_raw(const uint8_t* inbuf, size_t inbuf_sz,
	uint32_t** outbuf, size_t* outw, size_t* outh, struct arcan_img_meta* meta)
{
#ifdef DDS_SUPPORT
	struct dds_dsta_fmt* dds_img_data;
	DDSurfacedesc2 ddsd;

	strncmp(inbuf, "DDS ", 4) == 0;

/* read DDSD */
/* alloc outbuf as DDSIMAGEDATA */
/* check FourCC from DDSD for supported formats;
 * FOURCC_DXT1,3,5 (factor 2, 4, 4 as CR)
 * something weird with dwLinearSize?
 * check mipmapcount (linearsize * factor from fourCC)
 * now we have raw-data
 * FOURCC DXT1 only gives RGB, no alpha channel
 * DXT1 has a block size of 8, otherwise 16
 * foreach mipmap level;
 *  (1, 1 dimension if 0 0,
 *  glCompressedTexImage(level, formatv, cw, ch, 0,
 *  (cw+3)/4 * (ch+3)/4 * blocksize)
 *  slide buffer offset with size
 *  shift down width / height
*/
#else
	return ARCAN_ERRC_UNSUPPORTED_FORMAT;
#endif
}

void arcan_img_init()
{
	static bool initialized;
	if (initialized)
		return;

	initialized = true;
}

arcan_errc arcan_img_decode(const char* hint, char* inbuf, size_t inbuf_sz,
	uint32_t** outbuf, size_t* outw, size_t* outh,
	struct arcan_img_meta* meta, bool vflip)
{
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;
	int len = strlen(hint);

	if (len >= 3){
		if (strcasecmp(hint + (len - 3), "PNG") == 0 ||
			strcasecmp(hint + (len - 3), "JPG") == 0 ||
			(len >= 4 && strcasecmp(hint + (len - 4), "JPEG") == 0)
		){
			int outf;
			int w, h;
/* three things to note here,
 * 1. PNG Z-Lib state is not thread safe in current stbi-, neither is the
 *    flip-on-load toggle. This should be fixed upstream - now we hang on
 *    to the __thread gcc/clang extension.
 * 2. stbi uses arcan_alloc_mem with arguments that guarantee alignment
 * 3. this does not handle hi/norm/lo- quality re-packing or anti-repack
 *    protection, but rather assumes that the buffer contents has the right
 *    format, should be adressed when we go through all functions to try push
 *    for 10-bit and 16-bit support.
 */
			stbi_set_flip_vertically_on_load(vflip);
			uint32_t* buf = (uint32_t*) stbi_load_from_memory(
				(stbi_uc const*) inbuf, inbuf_sz, &w, &h, &outf, 4);

			if (buf){
				*outbuf = buf;
				*outw = w;
				*outh = h;
				return ARCAN_OK;
			}
		}
		else if (strcasecmp(hint + (len - 3), "PKM") == 0){
			return arcan_pkm_raw((uint8_t*)inbuf, inbuf_sz,
				outbuf, outw, outh, meta);
		}
		else if (strcasecmp(hint + (len - 3), "DDS") == 0){
			return arcan_dds_raw((uint8_t*)inbuf, inbuf_sz,
				outbuf, outw, outh, meta);
		}
	}

	return rv;
}
