/*
 Arcan Shared Memory Interface

 Copyright (c) 2014-2016, Bjorn Stahl
 All rights reserved.

 Redistribution and use in source and binary forms,
 with or without modification, are permitted provided that the
 following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 THE POSSIBILITY OF SUCH DAMAGE.
*/

#ifndef _HAVE_ARCAN_SHMIF_TUI
#define _HAVE_ARCAN_SHMIF_TUI

/*
 * Support functions for building a text-based user interfaces that draws using
 * Arcan. One of its primary uses is acting as the rendering backend for the
 * terminal emulator, but is useful for building other TUIs without all the
 * complexity, overhead, latency and dependencies from the [terminal+shell+
 * program[curses]], which in many cases are quite considerable due to baudrate
 * and resize protocol propagation.
 *
 * It covers all the boiler-plate needed for features like live migration,
 * dynamic font switching, select/copy/paste, binary blob transfers etc.
 *
 * It is based on libtsms screen and unicode handling, which unfortunately
 * pulls in a shl_htable implementation that is LGPL2.1+, meaning that we
 * also degrade to LGPL until that component has been replaced.
 *
 * A very interesting venue to explore here would be to tag cells with a
 * custom attribute that just forwards blitting to the caller in order to
 * support embedding graphics etc. It would also allow the terminal emulator
 * etc. to add sixel- support.
 */

enum tui_cursors {
	CURSOR_BLOCK = 0,
	CURSOR_HALFBLOCK,
	CURSOR_FRAME,
	CURSOR_VLINE,
	CURSOR_ULINE,
	CURSOR_END
};

/* grab the default values from arcan_tui_defaults, change if needed
 * (some will also change dynamically) and pass to the _setup routine */

struct tui_settings {
	uint8_t bgc[3], fgc[3];
	uint8_t alpha;
	shmif_pixel ccol;
	shmif_pixel clcol;
	float ppcm;
	int hint;
	size_t font_sz;
	size_t cell_w, cell_h;
	const char* font_fn;
	const char* font_fb_fn;
	enum tui_cursors cursor;
};

struct tui_cbcfg {
/* LABEL input,
 * MOUSE motion
 * DIRINPUT
 * UTF8 input,
 * OTHERIO,
 * statexfer,
 * bchunk,
 * vpaste,
 * apaste,
 * textpaste,
 * RESIZED */
	void* tag;
};

struct tui_settings arcan_tui_defaults();

/*
 * takes control over an existing connection, it is imperative that no ident-
 * or event processing has been done, so [con] should come straight from a
 * normal arcan_shmif_open call.
 */
struct tui_context* arcan_tui_setup(struct arcan_shmif_cont* con,
	const struct tui_settings* set, const struct tui_cbcfg* cfg, ...);

void arcan_tui_destroy(struct tui_context*);

enum tui_process_errc {
	TUI_ERRC_OK = 0,
	TUI_ERRC_BAD_ARG = -1,
	TUI_ERRC_BAD_FD = -2,
	TUI_ERRC_BAD_CTX = -3,
};
/*
 * callback driven approach with custom I/O multiplexation
 *
 * poll the main loop with a specified timeout (typically -1 in its
 * separate process or thread is fine)
 * [fdset_sz and n_contexts] are limited to 32 each.
 *
 * returns a bitmask with the active descriptors, always provide and
 * check [errc], if:
 *  TUI_ERRC_BAD_ARG - missing contexts/fdset or too many contexts/sets
 *  TUI_ERRC_BAD_FD - then the mask will show bad descriptors
 *  TUI_ERRC_BAD_CTX - then the mask will show bad contexts
 */
uint64_t arcan_tui_process(
	struct tui_context** contexts, size_t n_contexts,
	int* fdset, size_t fdset_sz, int timeout, int* errc);

void arcan_tui_refresh(
	struct tui_context** contexts, size_t n_contexts);

void arcan_tui_enqueue(struct tui_context*, arcan_event*);

/*
 * The rest are just renamed / remapped arcan_tui_ calls from libtsm-
 * (which hides inside the tui_context) selected based on what the tsm/pty
 * management required assuming that it is good enough.
 */
enum tui_flags {
	TUI_INSERT_MODE = 1,
	TUI_AUTO_WRAP = 2,
	TUI_REL_ORIGIN = 4,
	TUI_INVERSE = 8,
	TUI_HIDE_CURSOR = 16,
	TUI_FIXED_POS = 32,
	TUI_ALTERNATE = 64
};

struct tui_screen_attr {
	int8_t fccode; /* foreground color code or <0 for rgb */
	int8_t bccode; /* background color code or <0 for rgb */
	uint8_t fr; /* foreground red */
	uint8_t fg; /* foreground green */
	uint8_t fb; /* foreground blue */
	uint8_t br; /* background red */
	uint8_t bg; /* background green */
	uint8_t bb; /* background blue */
	unsigned int bold : 1; /* bold character */
	unsigned int underline : 1; /* underlined character */
	unsigned int italic : 1;
	unsigned int inverse : 1; /* inverse colors */
	unsigned int protect : 1; /* cannot be erased */
	unsigned int blink : 1; /* blinking character */
};

/* clear cells to default state, if protect toggle is set,
 * cells marked with a protected attribute will be ignored */
void arcan_tui_erase_screen(struct tui_context*, bool protect);
void arcan_tui_erase_region(struct tui_context*,
	size_t x1, size_t y1, size_t x2, size_t y2, bool protect);
void arcan_tui_refinc(struct tui_context*);
void arcan_tui_refdec(struct tui_context*);
void arcan_tui_defattr(struct tui_context*, struct tui_screen_attr*);
void arcan_tui_write(struct tui_context*, uint32_t ucode, struct tui_screen_attr*);
bool arcan_tui_writeu8(struct tui_context*, uint8_t* u8, size_t, struct tui_screen_attr*);
void arcan_tui_cursorpos(struct tui_context*, size_t* x, size_t* y);
void arcan_tui_reset(struct tui_context*);
void arcan_tui_set_flags(struct tui_context*, enum tui_flags);
void arcan_tui_reset_flags(struct tui_context*, enum tui_flags);
void arcan_tui_set_tabstop(struct tui_context*);
void arcan_tui_reset(struct tui_context*);
void arcan_tui_insert_lines(struct tui_context*, size_t);
void arcan_tui_delete_lines(struct tui_context*, size_t);
void arcan_tui_insert_chars(struct tui_context*, size_t);
void arcan_tui_delete_chars(struct tui_context*, size_t);
void arcan_tui_tab_right(struct tui_context*, size_t);
void arcan_tui_tab_left(struct tui_context*, size_t);
void arcan_tui_scroll_up(struct tui_context*, size_t);
void arcan_tui_scroll_down(struct tui_context*, size_t);
void arcan_tui_reset_tabstop(struct tui_context*);
void arcan_tui_reset_all_tabstops(struct tui_context*);
void arcan_tui_move_to(struct tui_context*, size_t x, size_t y);
void arcan_tui_move_up(struct tui_context*, size_t num, bool scroll);
void arcan_tui_move_down(struct tui_context*, size_t num, bool scroll);
void arcan_tui_move_left(struct tui_context*, size_t);
void arcan_tui_move_right(struct tui_context*, size_t);
void arcan_tui_move_line_end(struct tui_context*);
void arcan_tui_move_line_home(struct tui_context*);
void arcan_tui_newline(struct tui_context*);
int arcan_tui_set_margins(struct tui_context*, size_t top, size_t bottom);
#endif
