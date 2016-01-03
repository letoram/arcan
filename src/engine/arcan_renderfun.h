/*
 * Copyright 2008-2016, Björn Ståhl
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
 * \n (insert newline)
 * \r (insert carriage return)
 * \b or \!b (switch bold on or off, state persists between calls)
 * \i or \!i (switch italic on or off, state persists between calls)
 * \u or \!u (switch underline on or off, state persists between calls)
 * \pfname (load and embedd image from fname into string, dimensions limited)
 * \Pfname,w,h (load and stretch image from fname into string)
 */
av_pixel* arcan_renderfun_renderfmtstr(const char* message,
	arcan_vobj_id dst, int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs,
	bool pot, unsigned int* n_lines, unsigned int** lineheights,
	size_t* dw, size_t* dh, uint32_t* d_sz,
	size_t* maxw, size_t* maxh, bool norender
);

/*
 * Extended version with an array of messages (NULL terminated) where
 * each % 2 message is interpreted as possible format string and each %2+1 is
 * interpreted as text only.
 */
av_pixel* arcan_renderfun_renderfmtstr_extended(const char** message,
	arcan_vobj_id dst, int8_t line_spacing, int8_t tab_spacing,
	unsigned int* tabs, bool pot,
	unsigned int* n_lines, unsigned int** lineheights,
	size_t* dw, size_t* dh, uint32_t* d_sz,
	size_t* maxw, size_t* maxh, bool norender
);

/*
 * Set the default font that will be used for format strings
 * that do not explicitly say which font to use. 'ident' is
 * some unique- non filesystem-valid string 'fd' is an open
 * file-handle to a supported font file, sz the default size
 * and hint is: 0 - no anti-aliasing, 1 - light any other
 * value - truetype default
 */
bool arcan_video_defaultfont(const char* ident,
	file_handle fd, size_t sz, int hint);

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
