/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/* Optional build-time overrides for some defines to support higher bitdepth
 * full composition path, which adds quite some overhead. */


#define OUT_DEPTH_R 10
#define OUT_DEPTH_G 10
#define OUT_DEPTH_B 10
#define OUT_DETPH_A 0

#define GL_PIXEL_HDEF_FORMAT GL_RGB10_A2

#define RGBA_HDEF(r, g, b, a) \
	(uint32_t)(\
	(uint8_t) ((a) * 3.0f) << 30 | \
	(uint16_t) ((r) * 1023.0f) << 20 | \
	(uint16_t) ((g) * 1023.0f) << 10 | \
	(uint16_t) ((b) * 1023.0f))
