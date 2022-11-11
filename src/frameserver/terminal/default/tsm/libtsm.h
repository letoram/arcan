/*
 * TSM - Main Header
 *
 * Copyright (c) 2011-2013 David Herrmann <dh.herrmann@gmail.com>
 *               2016-2017 Bjorn Stahl <contact@arcan-fe.com>
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

#ifndef TSM_LIBTSM_H
#define TSM_LIBTSM_H

#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

struct tsm_vte;

enum tsm_vte_modifier {
	TSM_SHIFT_MASK	 = (ARKMOD_LSHIFT | ARKMOD_RSHIFT),
	TSM_LOCK_MASK		 = (ARKMOD_NUM),
	TSM_CONTROL_MASK = (ARKMOD_LCTRL | ARKMOD_RCTRL),
	TSM_ALT_MASK		 = (ARKMOD_LALT | ARKMOD_RALT),
	TSM_LOGO_MASK		 = (ARKMOD_LMETA | ARKMOD_RMETA),
};

enum vte_color {
	VTE_COLOR_INVAL = -1,
	VTE_COLOR_BLACK = 0,
	VTE_COLOR_RED,
	VTE_COLOR_GREEN,
	VTE_COLOR_YELLOW,
	VTE_COLOR_BLUE,
	VTE_COLOR_MAGENTA,
	VTE_COLOR_CYAN,
	VTE_COLOR_LIGHT_GREY,
	VTE_COLOR_DARK_GREY,
	VTE_COLOR_LIGHT_RED,
	VTE_COLOR_LIGHT_GREEN,
	VTE_COLOR_LIGHT_YELLOW,
	VTE_COLOR_LIGHT_BLUE,
	VTE_COLOR_LIGHT_MAGENTA,
	VTE_COLOR_LIGHT_CYAN,
	VTE_COLOR_WHITE,
	VTE_COLOR_FOREGROUND,
	VTE_COLOR_BACKGROUND,
	VTE_COLOR_NUM
};

/* keep in sync with TSM_INPUT_INVALID */
#define TSM_VTE_INVALID 0xffffffff

typedef void (*tsm_vte_write_cb) (struct tsm_vte *vte,
				  const char *u8,
				  size_t len,
				  void *data);

enum tsm_vte_group {
	TSM_GROUP_FREE,
	TSM_GROUP_OSC
};

typedef void (*tsm_str_cb) (struct tsm_vte *vte, enum tsm_vte_group group,
	const char *u8, size_t len, bool crop, void* data);

void tsm_set_strhandler(struct tsm_vte *vte,
	tsm_str_cb cb, size_t limit, void* data);

int tsm_vte_new(struct tsm_vte **out,
		struct tui_context *con, tsm_vte_write_cb write_cb, void *data);

void tsm_vte_ref(struct tsm_vte *vte);
void tsm_vte_unref(struct tsm_vte *vte);

int tsm_vte_set_palette(struct tsm_vte *vte, const char *palette);
void tsm_vte_set_color(struct tsm_vte *vte,
	enum vte_color ind, const uint8_t rgb[3]);
void tsm_vte_get_color(struct tsm_vte *vte,
	enum vte_color ind, uint8_t *rgb);

void tsm_vte_reset(struct tsm_vte *vte);
void tsm_vte_hard_reset(struct tsm_vte *vte);
void tsm_vte_input(struct tsm_vte *vte, const char *u8, size_t len);
bool tsm_vte_handle_keyboard(struct tsm_vte *vte, uint32_t keysym,
			     uint32_t ascii, unsigned int mods,
			     uint32_t unicode);
void tsm_vte_mouse_button(struct tsm_vte *vte, int index, bool press, int mods);
void tsm_vte_mouse_motion(struct tsm_vte *vte, int x, int y, int mods);
void tsm_vte_paste(struct tsm_vte *vte, const char *u8, size_t len);

/*
 * Return true of the state machine is inside of an unfinished escape sequence
 * and needs more data. The idea is to use this as an indicator to defer refresh
 * or not.
 */
bool tsm_vte_inseq(struct tsm_vte *vte);


/**
 * Logging Callback
 *
 * @data: user-provided data
 * @file: Source code file where the log message originated or NULL
 * @line: Line number in source code or 0
 * @func: C function name or NULL
 * @subs: Subsystem where the message came from or NULL
 * @sev: Kernel-style severity between 0=FATAL and 7=DEBUG
 * @format: printf-formatted message
 * @args: arguments for printf-style @format
 *
 * This is the type of a logging callback function. You can always pass NULL
 * instead of such a function to disable logging.
 */
typedef void (*tsm_log_t) (void *data,
	  const char *file,
	  int line,
	  const char *func,
	  const char *subs,
	  unsigned int sev,
	  const char *format,
	  va_list args);

/** @} */

/**
 * @defgroup symbols Unicode Helpers
 * Unicode helpers
 *
 * Unicode uses 32bit types to uniquely represent symbols. However, combining
 * characters allow modifications of such symbols but require additional space.
 * To avoid passing around allocated strings, TSM provides a symbol-table which
 * can store combining-characters with their base-symbol to create a new symbol.
 * This way, only the symbol-identifiers have to be passed around (which are
 * simple integers). No string allocation is needed by the API user.
 *
 * The symbol table is currently not exported. Once the API is fixed, we will
 * provide it to outside users.
 *
 * Additionally, this contains some general UTF8/UCS4 helpers.
 *
 * @{
 */

/* UCS4 helpers */

#define TSM_UCS4_MAX (0x7fffffffUL)
#define TSM_UCS4_INVALID (TSM_UCS4_MAX + 1)
#define TSM_UCS4_REPLACEMENT (0xfffdUL)

/* ucs4 to utf8 converter */

unsigned int tsm_ucs4_get_width(uint32_t ucs4);
size_t tsm_ucs4_to_utf8(uint32_t ucs4, char *out);
char *tsm_ucs4_to_utf8_alloc(const uint32_t *ucs4, size_t len, size_t *len_out);

/* symbols */

typedef uint32_t tsm_symbol_t;

/** @} */

/**
 * @defgroup screen Terminal Screens
 * Virtual terminal-screen implementation
 *
 * A TSM screen respresents the real screen of a terminal/application. It does
 * not render anything, but only provides a table of cells. Each cell contains
 * the stored symbol, attributes and more. Applications iterate a screen to
 * render each cell on their framebuffer.
 *
 * Screens provide all features that are expected from terminals. They include
 * scroll-back buffers, alternate screens, cursor positions and selection
 * support. Thus, it needs event-input from applications to drive these
 * features. Most of them are optional, though.
 *
 * @{
 */

struct tsm_screen;
typedef uint_fast32_t tsm_age_t;

#define TSM_SCREEN_INSERT_MODE	0x01
#define TSM_SCREEN_AUTO_WRAP	0x02
#define TSM_SCREEN_REL_ORIGIN	0x04
#define TSM_SCREEN_INVERSE	0x08
#define TSM_SCREEN_FIXED_POS	0x20
#define TSM_SCREEN_ALTERNATE	0x40

typedef int (*tsm_screen_draw_cb) (struct tsm_screen *con,
	uint32_t id,
	const uint32_t *ch,
	size_t len,
	unsigned int width,
	unsigned int posx,
	unsigned int posy,
	const struct tui_screen_attr *attr,
	tsm_age_t age,
	void *data
);

/*
 * Customline covers reserved rows that the caller draw separately
 * and are are ignored by the normal drawcalls. tsm_screen_insert_custom_lines
 * are used to add them into the normal line-tracking. They will always yield
 * draw-calls, they do not wrap
 */
typedef int (*tsm_screen_customline_cb) (struct tsm_screen *con,

/* user-defined ID to help associating what to draw */
	uint32_t id,
	unsigned int row,
/* if n' lines were added but only n-m lines are visible due to the current
 * scrolling settings, the number of missing lines will be shown */
	unsigned int ofs_top,
	unsigned int ofs_bottom,

/* the number of rows covered, >= 1, <= height */
	size_t n_rows,

/* user-tag */
	void* data
);

/* blocks are individually allocated, including the save_buf */
struct tsm_save_buf {
	size_t metadata_sz;
	uint8_t* metadata;

	size_t scrollback_sz;
	uint8_t* scrollback;

	size_t screen_sz;
	uint8_t* screen;
};

int tsm_screen_new(
	struct tui_context*, struct tsm_screen **out, tsm_log_t log, void *log_data);
void tsm_screen_ref(struct tsm_screen *con);
void tsm_screen_unref(struct tsm_screen *con);

unsigned int tsm_screen_get_width(struct tsm_screen *con);
unsigned int tsm_screen_get_height(struct tsm_screen *con);
int tsm_screen_resize(struct tsm_screen *con, unsigned int x,
		unsigned int y);
int tsm_screen_set_margins(struct tsm_screen *con,
	  unsigned int top, unsigned int bottom);
void tsm_screen_set_max_sb(struct tsm_screen *con, unsigned int max);
void tsm_screen_clear_sb(struct tsm_screen *con);

int tsm_screen_sb_up(struct tsm_screen *con, unsigned int num);
int tsm_screen_sb_down(struct tsm_screen *con, unsigned int num);
int tsm_screen_sb_page_up(struct tsm_screen *con, unsigned int num);
int tsm_screen_sb_page_down(struct tsm_screen *con, unsigned int num);
void tsm_screen_sb_reset(struct tsm_screen *con);

struct tui_screen_attr tsm_screen_get_def_attr(struct tsm_screen* con);

void tsm_screen_set_def_attr(struct tsm_screen *con,
		const struct tui_screen_attr *attr);
void tsm_screen_reset(struct tsm_screen *con);
void tsm_screen_set_flags(struct tsm_screen *con, unsigned int flags);
void tsm_screen_reset_flags(struct tsm_screen *con, unsigned int flags);
unsigned int tsm_screen_get_flags(struct tsm_screen *con);

unsigned int tsm_screen_get_cursor_x(struct tsm_screen *con);
unsigned int tsm_screen_get_cursor_y(struct tsm_screen *con);

void tsm_screen_set_tabstop(struct tsm_screen *con);
void tsm_screen_reset_tabstop(struct tsm_screen *con);
void tsm_screen_reset_all_tabstops(struct tsm_screen *con);

void tsm_screen_write(struct tsm_screen *con, tsm_symbol_t ch,
		const struct tui_screen_attr *attr);
void tsm_screen_setattr(struct tsm_screen *con,
	const struct tui_screen_attr *attr, size_t x, size_t y);
int tsm_screen_newline(struct tsm_screen *con);
int tsm_screen_scroll_up(struct tsm_screen *con, unsigned int num);
int tsm_screen_scroll_down(struct tsm_screen *con, unsigned int num);
void tsm_screen_move_to(struct tsm_screen *con, unsigned int x,
			unsigned int y);
int tsm_screen_move_up(struct tsm_screen *con, unsigned int num,
			bool scroll);
int tsm_screen_move_down(struct tsm_screen *con, unsigned int num,
	 bool scroll);
void tsm_screen_move_left(struct tsm_screen *con, unsigned int num);
void tsm_screen_move_right(struct tsm_screen *con, unsigned int num);
void tsm_screen_move_line_end(struct tsm_screen *con);
void tsm_screen_move_line_home(struct tsm_screen *con);
void tsm_screen_tab_right(struct tsm_screen *con, unsigned int num);
void tsm_screen_tab_left(struct tsm_screen *con, unsigned int num);
void tsm_screen_insert_lines(struct tsm_screen *con, unsigned int num);
void tsm_screen_delete_lines(struct tsm_screen *con, unsigned int num);
void tsm_screen_insert_chars(struct tsm_screen *con, unsigned int num);
void tsm_screen_delete_chars(struct tsm_screen *con, unsigned int num);
void tsm_screen_erase_cursor(struct tsm_screen *con);
void tsm_screen_erase_chars(struct tsm_screen *con, unsigned int num);
void tsm_screen_erase_region(struct tsm_screen *con,
	 unsigned int x_from,
	 unsigned int y_from,
	 unsigned int x_to,
	 unsigned int y_to,
	 bool protect);
struct tui_screen_attr tsm_attr_at_cursor(
	struct tsm_screen *con, tsm_symbol_t* out);
void tsm_screen_inc_age(struct tsm_screen *con);
void tsm_screen_erase_cursor_to_end(struct tsm_screen *con,
		bool protect);
void tsm_screen_erase_home_to_cursor(struct tsm_screen *con,
		 bool protect);
void tsm_screen_erase_current_line(struct tsm_screen *con,
	bool protect);
void tsm_screen_erase_screen_to_cursor(struct tsm_screen *con,
	bool protect);
void tsm_screen_erase_cursor_to_screen(struct tsm_screen *con,
	bool protect);
void tsm_screen_erase_screen(struct tsm_screen *con, bool protect);

void tsm_screen_selection_reset(struct tsm_screen *con);
void tsm_screen_selection_start(struct tsm_screen *con,
	unsigned int posx,
	unsigned int posy);
void tsm_screen_selection_target(struct tsm_screen *con,
	 unsigned int posx,
	 unsigned int posy);
int tsm_screen_selection_copy(struct tsm_screen *con, char **out, bool conv);

/* dynamically allocate a buffer into *dst (caller assumes ownership)
 * and fill with enough state from [src] to be restorable via _load.
 * the struct and the individual members are all separate allocations.
 * returns [true] if the destination structure pointer was populated.
 * setting [sb] to true will include the scrollback buffer */
bool tsm_screen_save(struct tsm_screen* src, bool sb, struct tsm_save_buf**);

/*
 * subset of _save, only take the screen and alt-screen at the specified
 * locations and populate into the save buffer
 */
bool tsm_screen_save_sub(struct tsm_screen* src,
	struct tsm_save_buf** out, size_t x, size_t y, size_t w, size_t h);

/* rebuild [dst] from the contents in [buf, buf_sz]. If the [dst] screen
 * size does not fit, contents will be cropped rather than wrapped. This
 * is safe to run multiple times with the same [dst] screen as a way of
 * retaining (some) screen contents in the event of a resize */
enum load_flags {
	TSM_LOAD_RESIZE = 1,
	TSM_LOAD_APPEND = 2
};

bool tsm_screen_load(struct tsm_screen* dst,
	struct tsm_save_buf* in, size_t start_x, size_t start_y, int fl);

/* returns: 0 on success, or -einval
 * starting from the character at x,y find the first and last
 * character in that word (using isspace as delimiter) */
int tsm_screen_get_word(struct tsm_screen *con,
		unsigned x, unsigned y,
		unsigned *sx, unsigned *sy,
		unsigned *ex, unsigned *ey);

/* returns: !0 if cell is empty */
int tsm_screen_empty(struct tsm_screen *con, unsigned x, unsigned y);

bool legacy_query_label(
	struct tui_context* c, int ind, struct tui_labelent* dst);
bool legacy_consume_label(struct tui_context* tui, const char* label);

tsm_age_t tsm_screen_draw(
	struct tsm_screen *con, tsm_screen_draw_cb draw_cb, void *data);

#ifdef __cplusplus
}
#endif

#endif /* TSM_LIBTSM_H */
