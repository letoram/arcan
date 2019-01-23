/*
 * TSM - Main Header
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

/*
 * Header has been stripped down to only contain the vte_ related parts.
 * Screen/scrolling/input/multiline etc. has all moved into shmif_tui.
 *
 */

#ifndef TSM_LIBTSM_H
#define TSM_LIBTSM_H

/**
 * @mainpage
 *
 * TSM is a Terminal-emulator State Machine. It implements all common DEC-VT100
 * to DEC-VT520 control codes and features. A state-machine is used to parse TTY
 * input and saved in a virtual screen. TSM does not provide any rendering,
 * glyph/font handling or anything more advanced. TSM is just a simple
 * state-machine for control-codes handling.
 * The main use-case for TSM are terminal-emulators. TSM has no dependencies
 * other than an ISO-C99 compiler and C-library. Any terminal emulator for any
 * window-environment or rendering-pipline can make use of TSM. However, TSM can
 * also be used for control-code validation, TTY-screen-capturing or other
 * advanced users of terminal escape-sequences.
 */

typedef uint32_t tsm_symbol_t;
typedef uint_fast32_t tsm_age_t;

/**
 * @defgroup vte State Machine
 * Virtual terminal emulation with state machine
 *
 * A TSM VTE object provides the terminal state machine. It takes input from the
 * application (which usually comes from a TTY/PTY from a client), parses it,
 * modifies the attach screen or returns data which has to be written back to
 * the client.
 *
 * Furthermore, VTE objects accept keyboard or mouse input from the application
 * which is interpreted compliant to DEV-VTs.
 *
 * @{
 */

/* virtual terminal emulator */

struct tsm_vte;

enum tsm_vte_modifier {
	TSM_SHIFT_MASK	 = (ARKMOD_LSHIFT | ARKMOD_RSHIFT),
	TSM_LOCK_MASK		 = (ARKMOD_NUM),
	TSM_CONTROL_MASK = (ARKMOD_LCTRL | ARKMOD_RCTRL),
	TSM_ALT_MASK		 = (ARKMOD_LSHIFT | ARKMOD_RSHIFT),
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

void debug_log(struct tsm_vte* vte, const char* msg, ...);
void tsm_vte_ref(struct tsm_vte *vte);
void tsm_vte_unref(struct tsm_vte *vte);

/* will be updated / synched OOB, used for displaying debug data */
void tsm_vte_debug(struct tsm_vte* in, arcan_tui_conn* conn);
void tsm_vte_update_debug(struct tsm_vte*);

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

#endif /* TSM_LIBTSM_H */
