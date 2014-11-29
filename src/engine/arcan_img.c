/*
 * Copyright 2013-2014, Björn Ståhl
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

#include <zlib.h>
#include <png.h>

#ifdef TJPEG
#endif

#ifdef SDLIMAGE
#include <SDL_image.h>
#endif

struct png_readstr
{
	char* inbuf;
	off_t inbuf_ofs;
	size_t inbuf_sz;
};


#ifdef _SDL_IMAGE_H
/* copy RGBA src row by row with optional "flip",
 * swidth <= dwidth */
static inline void imagecopy(uint32_t* dst, uint32_t* src, int dwidth, int
	swidth, int height, bool flipv)
{
	if (flipv)
	{
		for (int drow = height-1, srow = 0; srow < height; srow++, drow--)
			memcpy(&dst[drow * dwidth], &src[srow * swidth], swidth * 4);
	}
	else
		for (int row = 0; row < height; row++)
			memcpy(&dst[row * dwidth], &src[row * swidth], swidth * 4);
}
#endif

/*
 * Ideally, this copy shouldn't be needed --
 * patch libpng to have a memory interface
 */
static void png_readfun(png_structp png_ptr, png_bytep outb, png_size_t ntr)
{
	struct png_readstr* indata = png_get_io_ptr(png_ptr);
	memcpy(outb, indata->inbuf + indata->inbuf_ofs, ntr);
	indata->inbuf_ofs += ntr;
}

arcan_errc arcan_rgba32_pngfile(FILE* dst, char* inbuf, int inw, int inh, bool vflip)
{
	png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING,
		NULL, NULL, NULL);

	if (!png_ptr)
		return ARCAN_ERRC_BAD_ARGUMENT;

	png_infop info_ptr = png_create_info_struct(png_ptr);
	if (!info_ptr){
 		png_destroy_write_struct(&png_ptr, (png_infopp)NULL);
		return ARCAN_ERRC_BAD_ARGUMENT;
	}

	if (setjmp(png_jmpbuf(png_ptr))){
		png_destroy_write_struct(&png_ptr, &info_ptr);
		return ARCAN_ERRC_BAD_ARGUMENT;
	}

	png_init_io(png_ptr, dst);

	png_set_compression_level(png_ptr, Z_BEST_COMPRESSION);
	png_set_IHDR(png_ptr, info_ptr, inw, inh, 8, PNG_COLOR_TYPE_RGB_ALPHA,
		PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);

	png_write_info(png_ptr, info_ptr);

	if (vflip)
		for (int row = inh-1; row >= 0; row--)
			png_write_row(png_ptr, (png_bytep) inbuf + (row * 4 * inw));
	else
		for (int row = 0; row < inh; row++)
			png_write_row(png_ptr, (png_bytep) inbuf + (row * 4 * inw));

	png_write_end(png_ptr, info_ptr);
	png_destroy_write_struct(&png_ptr, &info_ptr);

	fclose(dst);
	return ARCAN_OK;
}

arcan_errc arcan_png_rgba32(char* inbuf, size_t inbuf_sz,
	char** outbuf, int* outw, int* outh, bool vflip, outimg_allocator pngalloc){
	arcan_errc rv = ARCAN_ERRC_UNSUPPORTED_FORMAT;
	uint8_t* rowdec = NULL;

/* HEADER check */
	if (png_sig_cmp((unsigned char*) inbuf, 0, 8))
		return rv;

/* prepare read wrapper */
	png_structp png_ptr     = NULL;
	png_infop   info_ptr    = NULL;

	if (!(png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING,
		 NULL, NULL, NULL)) )
			return rv;

/* extract header fields */
	if ( !(info_ptr = png_create_info_struct(png_ptr)) ){
		rv = ARCAN_ERRC_BAD_RESOURCE;
		goto cleanup;
	}

	if (setjmp(png_jmpbuf(png_ptr))){
		rv = ARCAN_ERRC_BAD_RESOURCE;
		goto cleanup;
	}

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

	int bd = 0;
	int cspace = -1;
	int32_t status = png_get_IHDR(png_ptr, info_ptr, &w, &h, &bd,
		 &cspace, NULL, NULL, NULL);

	size_t out_sz  = w * h * 4;

	*outw = w;
	*outh = h;

	if ( 1 != status || NULL == (*outbuf = pngalloc(out_sz)) )
		goto cleanup;

/* interface requirement that outbuf comes aligned */
	uint32_t* out32  = vflip ? (uint32_t*)(*outbuf) + (w * h - w) :
		(uint32_t*)(*outbuf);

/* 16 bit / channel => 8 bit */
	if (bd == 16)
 		png_set_strip_16(png_ptr);

/* convert greyscale to RGB */
	if (cspace == PNG_COLOR_TYPE_GRAY ||
		cspace == PNG_COLOR_TYPE_GRAY_ALPHA)
			png_set_gray_to_rgb(png_ptr);

/* expand palette to RGB */
		if (cspace == PNG_COLOR_TYPE_PALETTE){
  		png_set_palette_to_rgb(png_ptr);
			cspace = PNG_COLOR_TYPE_RGB;
		}
/* expand greyscale to 8bits */
/*  if (cspace == PNG_COLOR_TYPE_GRAY && bd < 8)
		png_set_gray_1_2_4_to_8(png_ptr);  */

/* maintain greyscale transparency */
	if (png_get_valid(png_ptr, info_ptr,
		PNG_INFO_tRNS)) png_set_tRNS_to_alpha(png_ptr);

	if (cspace == PNG_COLOR_TYPE_RGB)
 		png_set_filler(png_ptr, 0xff, PNG_FILLER_AFTER);

	rowdec = malloc( w * 4 );

/*
 * expand, use RGBAPACK macro anyhow as that may shift to
 * 565 if needed on the current platform
 * */
		for (int row = 0; row < h; row++){
			png_read_row(png_ptr, (png_bytep) rowdec, NULL);

			for (int col = 0; col < w * 4; col += 4){
				*out32++ = RGBA(rowdec[col],
					rowdec[col+1], rowdec[col+2], rowdec[col+3]);
			}
			out32 -= vflip ? w + w : 0;
		}

	rv = ARCAN_OK;

cleanup:
	png_destroy_read_struct(&png_ptr, info_ptr ? &info_ptr : NULL, NULL);
	free(rowdec);
	return rv;

/*
 * we don't clear *outbuf if it's allocated, that's up to the
 * caller to track. png_destroy_read will cascade to cleaning
 * up the other png structures we used
 */
}

/*
 * provided only for backwards compatiblity (particularly for those
 * depending on .ico) and SDL_Image is to be deprecated / removed in this prj
 * there are notable preconditions to fulfill beforehand
 */
#ifdef _SDL_IMAGE_H
arcan_errc arcan_sdlimage_rgba32(char* inbuf, size_t inbuf_sz, char** outbuf,
	int* outw, int* outh, bool flipv, outimg_allocator alloc){
	SDL_RWops* rwops = SDL_RWFromConstMem(inbuf, inbuf_sz);
	SDL_Surface* res;
	arcan_errc rv = ARCAN_OK;

	*outbuf = NULL;
	*outw   = 0;
	*outh   = 0;

	if ( rwops && (res = IMG_Load_RW(rwops, 1)) ){
		*outw = res->w;
		*outh = res->h;

		SDL_Surface* glimg =
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
			SDL_CreateRGBSurface(SDL_SWSURFACE, res->w, res->h, 32,
				0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
#else
			SDL_CreateRGBSurface(SDL_SWSURFACE, res->w, res->h, 32,
				0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000);
#endif
		SDL_SetAlpha(res, 0, SDL_ALPHA_TRANSPARENT);
		SDL_BlitSurface(res, NULL, glimg, NULL);

		*outbuf = alloc(res->w * res->h * 4);
		imagecopy((uint32_t*) (*outbuf), glimg->pixels, *outw, *outw, *outh, flipv);

		SDL_FreeSurface(res);
		SDL_FreeSurface(glimg);
	}
	else
		rv = ARCAN_ERRC_UNSUPPORTED_FORMAT;

/* IMG_Load_RW with a non-zero second argument means that RWops will
 * be freed internally, so no need to do that here */

	return rv;
}
#endif

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

/*
 * always try LibPNG / LibTurboJPEG first, then resort to whatever
 * other native image library that might be available as fallbacks below
 */

	if (len >= 3){
		if (strcasecmp(hint + (len - 3), "PNG") == 0){
			rv = arcan_png_rgba32(inbuf, inbuf_sz, outbuf, outw, outh, vflip, imalloc);
			if (rv == ARCAN_OK)
				return ARCAN_OK;
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

#ifdef _SDL_IMAGE_H
	rv = arcan_sdlimage_rgba32(inbuf, inbuf_sz, outbuf, outw, outh,vflip,imalloc);
#endif

	return rv;
}
