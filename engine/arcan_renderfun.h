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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
 *
 */

/*
 * Renders a format string into a dynamically allocated graphics buffer,
 * returns a pointer to the buffer or NULL.
 *
 * message - obligatory !NULL UTF8 + format string
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
void* arcan_renderfun_renderfmtstr(const char* message,
	int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, bool pot,
	unsigned int* n_lines, unsigned int** lineheights,
	unsigned short* dw, unsigned short * dh, uint32_t* d_sz,
	int* maxw, int* maxh);

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
	uint32_t* dst, int dstw, int dsth, int flipy);

/*
 * Similar to arcan_renderfun_renderfmtstr, but doesn't write / blit the output,
 * only returns rendering dimensions in maxw and maxh
 */
void arcan_renderfun_stringdimensions(const char* message, int8_t line_spacing,
	int8_t tab_spacing, unsigned* tabs, unsigned* maxw, unsigned* maxh);

