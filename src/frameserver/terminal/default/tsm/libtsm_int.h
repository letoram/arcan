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
#include "arcan_shmif.h"
#include "arcan_tui.h"
#include "arcan_tuisym.h"
#include "libtsm.h"

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

/* TSM screen

void tsm_screen_set_opts(struct tsm_screen *scr, unsigned int opts);
void tsm_screen_reset_opts(struct tsm_screen *scr, unsigned int opts);
unsigned int tsm_screen_get_opts(struct tsm_screen *scr);

 */

/* available character sets */

typedef tsm_symbol_t tsm_vte_charset[96];

extern tsm_vte_charset tsm_vte_unicode_lower;
extern tsm_vte_charset tsm_vte_unicode_upper;
extern tsm_vte_charset tsm_vte_dec_supplemental_graphics;
extern tsm_vte_charset tsm_vte_dec_special_graphics;

enum mouse_data {
	MOUSE_BUTTON = 1,
	MOUSE_DRAG   = 2,
	MOUSE_MOTION = 4,
	MOUSE_SGR    = 8,
	MOUSE_X10    = 16,
	MOUSE_RXVT   = 32
};
/* max CSI arguments */
#define CSI_ARG_MAX 16

struct vte_saved_state {
	size_t cursor_x;
	size_t cursor_y;
	size_t mouse_x;
	size_t mouse_y;
	enum mouse_data mouse_state;
	struct tui_screen_attr cattr;
	bool faint;
	int c_fgcode, c_bgcode;
	int d_fgcode, d_bgcode;

	tsm_vte_charset **gl;
	tsm_vte_charset **gr;
	bool wrap_mode;
	bool origin_mode;
};

struct tsm_vte {
	unsigned long ref;

	tsm_str_cb strcb;
	void *strcb_data;
	size_t colbuf_sz;
	size_t colbuf_pos;
	char *colbuf;

	struct tui_context *con;
	int log_ctr;

	tsm_vte_write_cb write_cb;
	void *data;
	char *palette_name;

	struct tsm_utf8_mach *mach;
	unsigned long parse_cnt;
	tsm_symbol_t last_symbol;

	unsigned int state;
	enum mouse_data mstate;
	int mbutton;

	unsigned int csi_argc;
	int csi_argv[CSI_ARG_MAX];
	unsigned int csi_flags;

	uint8_t palette[VTE_COLOR_NUM][3];
	struct tui_screen_attr def_attr;
	struct tui_screen_attr cattr;
	int c_fgcode, c_bgcode;
	int d_fgcode, d_bgcode;
	bool faint;

	unsigned int flags;

	tsm_vte_charset **gl;
	tsm_vte_charset **gr;
	tsm_vte_charset **glt;
	tsm_vte_charset **grt;
	tsm_vte_charset *g0;
	tsm_vte_charset *g1;
	tsm_vte_charset *g2;
	tsm_vte_charset *g3;

	struct vte_saved_state saved_state;
	size_t alt_cursor_x;
	size_t alt_cursor_y;
};

struct cell {
	tsm_symbol_t ch;
	unsigned int width;
	struct tui_screen_attr attr;
	tsm_age_t age;
};

struct line {
	struct line *next;
	struct line *prev;

	unsigned int size;
	struct cell *cells;
	uint64_t sb_id;
	tsm_age_t age;
};

#define SELECTION_TOP -1
struct selection_pos {
	struct line *line;
	unsigned int x;
	int y;
};

struct tsm_screen {
	size_t ref;
	unsigned int flags;
	struct tsm_symbol_table *sym_table;

	/* default attributes for new cells */
	struct tui_screen_attr def_attr;

	/* ageing */
	tsm_age_t age_cnt;
	unsigned int age_reset : 1;

	/* current buffer */
	unsigned int size_x;
	unsigned int size_y;
	unsigned int margin_top;
	unsigned int margin_bottom;
	unsigned int line_num;
	struct line **lines;
	struct line **main_lines;
	struct line **alt_lines;
	tsm_age_t age;
	int vanguard;

	/* scroll-back buffer */
	unsigned int sb_count;		/* number of lines in sb */
	struct line *sb_first;		/* first line; was moved first */
	struct line *sb_last;		/* last line; was moved last*/
	unsigned int sb_max;		/* max-limit of lines in sb */
	struct line *sb_pos;		/* current position in sb or NULL */
	uint64_t sb_last_id;		/* last id given to sb-line */

	/* cursor */
	unsigned int cursor_x;
	unsigned int cursor_y;

	/* tab ruler */
	bool *tab_ruler;

	/* selection */
	bool sel_active;
	struct selection_pos sel_start;
	struct selection_pos sel_end;
	struct tui_context* owner;
};

#endif /* TSM_LIBTSM_INT_H */
