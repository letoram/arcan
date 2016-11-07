/*
 * Copyright 2013-2016, Björn Ståhl
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

void arcan_img_init();

/*
 * Wrapper around the other decode functions in that it tries to
 * identify (heuristically, experimentally or by the 'hint' inbuf)
 * the data source and choose decoding routine accordingly.
 * If *outraw is set, the image data is in a native-compressed format
 * (ETC1, ...) and needs to be forwarded and treated as such (no postproc.)
 */
arcan_errc arcan_img_decode(const char* hint, char* inbuf, size_t inbuf_sz,
	uint32_t** outbuf, size_t* outw, size_t* outh,
	struct arcan_img_meta* outm, bool vflip
);

/*
 * take the contents of [inbuf] and unpack/[vflip],
 * then encode as PNG and write to [dst]. [dst] is kept open.
 */
arcan_errc arcan_img_outpng(FILE* dst,
	av_pixel* inbuf, size_t inw, size_t inh, bool vflip);

/*
 * make sure that inbuf is propery aligned
 * and matches the native engine color format.
 * returns NULL on failure but [inbuf] will always be freed (or re-used)
 */
av_pixel* arcan_img_repack(uint32_t* inbuf, size_t inw, size_t inh);
#endif
