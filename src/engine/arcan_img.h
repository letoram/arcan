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
 * Privilege-separated wrapper around arcan_img_decode. Untrusted
 * sources (shmif bchunk, a12 binary transfer) are routed through a
 * short-lived decode frameserver spawned via
 * arcan_frameserver_spawn_subsegment(); decode happens under
 * arcan_shmif_privsep() with pledge("stdio rpath") on OpenBSD.
 *
 * Trusted appl-local resources fall through to direct in-process
 * decode unless ARCAN_IMG_INPROC has been disabled.
 *
 * Sources are flagged untrusted by passing a hint prefixed with
 * "untrusted:" -- callers in the shmif and a12 paths apply this
 * prefix; appl resource loaders pass the raw filename.
 */
arcan_errc arcan_img_load_sandboxed(const char* hint,
	char* inbuf, size_t inbuf_sz,
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
