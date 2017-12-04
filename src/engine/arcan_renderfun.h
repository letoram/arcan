/*
 * Copyright 2008-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * Renders a format string into a dynamically allocated graphics buffer,
 * returns a pointer to the buffer or NULL.
 *
 * message - obligatory !NULL UTF8 + format string
 * dst - video object backing store (or ARCAN_EID) to render into
 * line_spacing - (pixels) increment after each row
 * tab_spacing - (pixels) default tab-width. Can be overridden with tabs arg.
 * tabs - (NULL possible), NULL- terminated list of preset tab-widths to use.
 * If a string contains more tabs than entries, tab_spacing will be used to
 * compensate.
 * lineheights - (NULL possible), will write back a dynamically allocated buffer
 * with row offsets for each rendered line. Cleanup responsibility belong to the
 * caller.
 * pot - should the storage be padded to the next fitting power of two or not
 * *dw - will write-back the visible buffer width of the rendered text (pixels)
 * *dh - will write-back the visible buffer height of the rendered text (pixels)
 * *d_sz - will write-back the size (in bytes) of the final buffer
 * *maxw - will write-back the storage width of the rendered text (can be padded)
 * *maxh - will write-back the storage height of the rendered text (can be padded)
 *
 * possible format string arguments (\\ escapes)
 * \ffont.ttf,size (switch font, state persists between calls, number of
 *                  cached fonts can be controlled with ARCAN_FONT_CACHE_LIMIT)
 * \#rrggbb (switch color, state persists between calls)
 * \t (insert tab)
 * \T sz (insert tab, aligned to sz pt from base)
 * \n (insert newline)
 * \r (insert carriage return)
 * \v sz (set line spacing to be sz rather than the font provided metric)
 * \V undo \v
 * \b or \!b (switch bold on or off, state persists between calls)
 * \i or \!i (switch italic on or off, state persists between calls)
 * \u or \!u (switch underline on or off, state persists between calls)
 * \pfname (load and embedd image from fname into string, dimensions limited)
 * \Pfname,w,h (load and stretch image from fname)
 * \evid,w,h (load and stretch image from vid into buffer)
 * \Evid,w,h,x1,y1,x2,y2 (load and stretch subimage from vid into buffer)
 * Underneath it all are two levels of caches, one for typefaces+size+density
 * in each cached font there is one for glyphs.
 * Density is treated as a global state and used has a hidden prefix for
 * selecting typeface, so \ffont.ttf,16 can be different from \ffont.ttf,16 if
 * arcan_renderfun_outputdensity has changed, as only switching the
 * FT_Set_Char_Size(font, 0, size_pt, hdpi, vdpi) before rendering caused too
 * many costly glyph cache invalidations. Since DPI is static and homogenous
 * most of the time this only really matters in the arcan use case where
 * per-rendertarget different densities is a thing.
 */

#ifndef HAVE_RLINE_META
#define HAVE_RLINE_META
struct renderline_meta{
	int height;
	int ystart;
	int ascent; /* only accurate if there's a single font used on the line */
};
#endif

av_pixel* arcan_renderfun_renderfmtstr(const char* message,
	arcan_vobj_id dst,
	bool pot, unsigned int* n_lines, struct renderline_meta** lineheights,
	size_t* dw, size_t* dh, uint32_t* d_sz,
	size_t* maxw, size_t* maxh, bool norender
);

/*
 * Extended version with an array of messages (NULL terminated) where
 * each % 2 message is interpreted as possible format string and each %2+1 is
 * interpreted as text only.
 */
av_pixel* arcan_renderfun_renderfmtstr_extended(const char** message,
	arcan_vobj_id dst,
	bool pot, unsigned int* n_lines, struct renderline_meta** lineheights,
	size_t* dw, size_t* dh, uint32_t* d_sz,
	size_t* maxw, size_t* maxh, bool norender
);

/*
 * set the video offset used for embedded rendering of vstores, this is
 * primarily used when there's a scripting- or similar context that remaps
 * vid numbers to a different linear namespace (e.g. arcan_lua)
 */
void arcan_renderfun_vidoffset(int64_t ofs);

/*
 * Set the default font that will be used for format strings that do not
 * explicitly say which font to use. 'ident' is some unique- non
 * filesystem-valid string 'fd' is an open file-handle to a supported font
 * file, sz the default size and hint is:
 * <0 - keep previous setting
 *  0 - none,
 *  1 - mono,
 *  2 - weak,
 *  3 - normal,
 *  4 - rgb,
 *  5 - rgbv
 */
bool arcan_video_defaultfont(const char* ident,
	file_handle fd, int sz, int hint, bool append);

/*
 * Change the target output density. This is a static global and affects
 * all font operations (as output size = pt- size over density. Density
 * is expressed in pixels per centimeter.
 */
void arcan_renderfun_outputdensity(float vppcm, float hppcm);

/*
 * Retrieve the current font defaults for the fields that have their value
 * set to the correct type (NULL ignored)
 */
void arcan_video_fontdefaults(file_handle* fd, int* pt_sz, int* hint);

/*
 * Shouldn't need to be called outside debugging /troubleshooting purposes.
 */
void arcan_renderfun_reset_fontcache();

/*
 * RGBA32 only for only, rather unoptimized
 * returns -1 or failure, 0 on success
 * blits src into dst, stretching to dstw, desth, optionally inverting
 * row-order.
 */
int arcan_renderfun_stretchblit(char* src, int inw, int inh,
	uint32_t* dst, size_t dstw, size_t dsth, int flipv);
