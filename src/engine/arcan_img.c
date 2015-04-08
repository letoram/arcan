/*
 * Copyright 2013-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <assert.h>
#include <stdio.h>
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

#include "external/stb_image.h"
#include "external/stb_image_write.h"

struct png_readstr
{
	char* inbuf;
	off_t inbuf_ofs;
	size_t inbuf_sz;
};

arcan_errc arcan_rgba32_pngfile(FILE* dst, char* inbuf, int inw, int inh, bool vflip)
{
	int outln;

	char* outbuf = inbuf;

	if (vflip){
		size_t stride = inw * 4;
		outbuf = arcan_alloc_mem(stride * inh, ARCAN_MEM_VBUFFER,
			ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

		for (ssize_t row = inh-1, step = 0; row >= 0; row--, step++)
			memcpy(&outbuf[step * stride], &inbuf[row * stride], stride);
	}

	unsigned char* png = stbi_write_png_to_mem(
		(unsigned char*) outbuf, 0, inw, inh, 4, &outln);

	fwrite(png, 1, outln, dst);
	free(png);

	if (vflip)
		arcan_mem_free(outbuf);

	return ARCAN_OK;
}

arcan_errc arcan_pkm_raw(const uint8_t* inbuf, size_t inbuf_sz, char** outbuf,
		int* outw, int* outh, struct arcan_img_meta* meta, outimg_allocator alloc)
{
#ifdef ETC1_SUPPORT
/* extract header fields */
	int pwidth  = (inbuf[ 8] << 8) | inbuf[ 9];
	int pheight = (inbuf[10] << 8) | inbuf[11];
	int width   = (inbuf[12] << 8) | inbuf[13];
	int height  = (inbuf[14] << 8) | inbuf[15];

/* strip header */
	*outbuf = alloc(inbuf_sz - 16);
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

arcan_errc arcan_dds_raw(const uint8_t* inbuf, size_t inbuf_sz, char** outbuf,
	int* outw, int* outh, struct arcan_img_meta* meta, outimg_allocator alloc)
{
#ifdef DDS_SUPPORT
	struct dds_dsta_fmt* dds_img_data;
	DDSurfacedesc2 ddsd;

	strncmp(inbuf, "DDS ", 4) == 0;

/* read DDSD */
/* alloc outbuf as DDSIMAGEDATA */
/* check FourCC from DDSD for supported formats;
   FOURCC_DXT1,3,5 (factor 2, 4, 4 as CR)
	 something weird with dwLinearSize?
	 check mipmapcount (linearsize * factor from fourCC)
	 now we have raw-data
	 FOURCC DXT1 only gives RGB, no alpha channel
	 DXT1 has a block size of 8, otherwise 16
	 foreach mipmap level;
			(1, 1 dimension if 0 0,
			glCompressedTexImage(level, formatv, cw, ch, 0,
				(cw+3)/4 * (ch+3)/4 * blocksize)
			slide buffer offset with size
			shift down width / height
*/
#else
	return ARCAN_ERRC_UNSUPPORTED_FORMAT;
#endif
}

arcan_errc arcan_img_decode(const char* hint, char* inbuf, size_t inbuf_sz,
	char** outbuf, int* outw, int* outh, struct arcan_img_meta* meta,
	bool vflip, outimg_allocator imalloc)
{
	arcan_errc rv = ARCAN_ERRC_BAD_RESOURCE;
	int len = strlen(hint);

	if (len >= 3){
		if (strcasecmp(hint + (len - 3), "PNG") == 0 ||
			strcasecmp(hint + (len - 3), "JPG") == 0 ||
			(len == 4 && strcasecmp(hint + (len - 4), "JPEG") == 0))
		{
			int outf;
			char* buf = (char*) stbi_load_from_memory(
				(stbi_uc const*) inbuf, inbuf_sz, outw, outh, &outf, 4);
			if (buf){
				*outbuf = buf;
				return ARCAN_OK;
			}
		}
		else if (strcasecmp(hint + (len - 3), "JPG") == 0 ||
			(len >= 4 && strcasecmp(hint + (len - 4), "JPEG") == 0)){
//			arcan_warning("use libjpeg(turbo)");
		}
		else if (strcasecmp(hint + (len - 3), "PKM") == 0){
			return arcan_pkm_raw((uint8_t*)inbuf, inbuf_sz,
				outbuf, outw, outh, meta, imalloc);
		}
		else if (strcasecmp(hint + (len - 3), "DDS") == 0){
			return arcan_dds_raw((uint8_t*)inbuf, inbuf_sz,
				outbuf, outw, outh, meta, imalloc);
		}
	}

	return rv;
}
