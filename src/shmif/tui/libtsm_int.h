/*
 * TSM - Main internal header
 *
 * Copyright (c) 2011-2013 David Herrmann <dh.herrmann@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#ifndef TSM_LIBTSM_INT_H
#define TSM_LIBTSM_INT_H

#include <stdlib.h>

#define SHL_EXPORT __attribute__((visibility("default")))

/* max combined-symbol length */
#define TSM_UCS4_MAXLEN 10

/* symbols */

struct tsm_symbol_table;

extern const tsm_symbol_t tsm_symbol_default;

int tsm_symbol_table_new(struct tsm_symbol_table **out);
void tsm_symbol_table_ref(struct tsm_symbol_table *tbl);
void tsm_symbol_table_unref(struct tsm_symbol_table *tbl);

tsm_symbol_t tsm_symbol_make(uint32_t ucs4);
tsm_symbol_t tsm_symbol_append(struct tsm_symbol_table *tbl,
			       tsm_symbol_t sym, uint32_t ucs4);
const uint32_t *tsm_symbol_get(struct tsm_symbol_table *tbl,
			       tsm_symbol_t *sym, size_t *size);
unsigned int tsm_symbol_get_width(struct tsm_symbol_table *tbl,
				  tsm_symbol_t sym);

/* utf8 state machine */

struct tsm_utf8_mach;

enum tsm_utf8_mach_state {
	TSM_UTF8_START,
	TSM_UTF8_ACCEPT,
	TSM_UTF8_REJECT,
	TSM_UTF8_EXPECT1,
	TSM_UTF8_EXPECT2,
	TSM_UTF8_EXPECT3,
};

int tsm_utf8_mach_new(struct tsm_utf8_mach **out);
void tsm_utf8_mach_free(struct tsm_utf8_mach *mach);

int tsm_utf8_mach_feed(struct tsm_utf8_mach *mach, char c);
uint32_t tsm_utf8_mach_get(struct tsm_utf8_mach *mach);
void tsm_utf8_mach_reset(struct tsm_utf8_mach *mach);

/* TSM screen */

void tsm_screen_set_opts(struct tsm_screen *scr, unsigned int opts);
void tsm_screen_reset_opts(struct tsm_screen *scr, unsigned int opts);
unsigned int tsm_screen_get_opts(struct tsm_screen *scr);

/* available character sets */

typedef tsm_symbol_t tsm_vte_charset[96];

extern tsm_vte_charset tsm_vte_unicode_lower;
extern tsm_vte_charset tsm_vte_unicode_upper;
extern tsm_vte_charset tsm_vte_dec_supplemental_graphics;
extern tsm_vte_charset tsm_vte_dec_special_graphics;

#endif /* TSM_LIBTSM_INT_H */
