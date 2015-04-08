/*
 * Copyright 2013-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_IMG
#define _HAVE_ARCAN_IMG

struct arcan_img_meta {
	bool compressed;
	bool mipmapped;
	int pwidth, pheight;
	size_t c_size;
};

typedef void* (*outimg_allocator)( size_t );

/*
 * Wrapper around the other decode functions in that it tries to
 * identify (heuristically, experimentally or by the 'hint' inbuf)
 * the data source and choose decoding routine accordingly.
 * If *outraw is set, the image data is in a native-compressed format (ETC1, ...)
 * and needs to be forwarded / treated as such (no postproc.)
 */
arcan_errc arcan_img_decode(const char* hint, char* inbuf, size_t inbuf_sz,
	char** outbuf, int* outw, int* outh,
	struct arcan_img_meta* outm, bool vflip, outimg_allocator);

/*
 * use a pre-opened filedescriptor to encode the contents of inbuf with dimensions
 * of inw * inh (4BPP, no padding), will close the descriptor on completion
 */
arcan_errc arcan_rgba32_pngfile(FILE* dst, char* inbuf, int inw, int inh, bool vflip);

/*
 * treat 'inbuf' as a tightly packed RGBA32 buffer with the dimensions of (inw, inh)
 * and store the resulting output in 'outbuf'. The encoded size will be stored in
 * outsz and allocated by calling outimg_allocator, which could be set to malloc.
 */
arcan_errc arcan_rgba32_png(char* inbuf, int inw, int inh, char** outbuf,
	size_t* outsz, outimg_allocator);

/*
 * SDL_image backward compatiblity, can ideally be disabled entirely.
 */
#ifdef _SDL_IMAGE_H
arcan_errc arcan_sdlimage_rgba32(char* inbuf, size_t inbuf_sz, char** outbuf,
	int* outw, int* outh, bool vflip, outimg_allocator);
#endif

#endif
