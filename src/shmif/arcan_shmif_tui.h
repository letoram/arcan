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
 *                                [THREAD UNSAFE]
 * Support functions for building a text-based user interfaces that draws using
 * Arcan. One of its primary uses is acting as the rendering backend for the
 * terminal emulator, but is useful for building other TUIs without all the
 * complexity, overhead, latency and dependencies from the [terminal+shell+
 * program[curses]], which in many cases are quite considerable due to baudrate
 * and resize protocol propagation.
 *
 * It covers all the boiler-plate needed for features like live migration,
 * dynamic font switching, select/copy/paste, binary blob transfers, mapping
 * subwindows etc.
 *
 * It is based on libtsms screen and unicode handling, which unfortunately
 * pulls in a shl_htable implementation that is LGPL2.1+, meaning that we
 * also degrade to LGPL until that component has been replaced.
 *
 * >> See tests/frameservers/tui_test for a template/example of use. <<
 *
 * This library attempts to eventually become a stable ABI, avoid exposing
 * the most volatile shmif_ structure (arcan_event) or raw offsets into
 * con.addr
 *
 * Missing:
 * [ ] serialized- API that wraps and serializes callbacks back to a queue
 *     so that it can fit into callback driven software without getting a
 *     'nested callbacks' mess.
 *
 * [ ] linenoise- integration
 *
 * [ ] abstract component helpers for things like popup-select style windows
 *
 * [ ] query label callback not yet used
 *
 * [ ] Normal "Curses" rendering- backend to not break term- compatibility
 *     for programs reworked to use this interface
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

/* either using strings or pre-opened fonts, the latter case is when*/
	const char* font_fn;
	const char* font_fb_fn;
	int font_fds[2];
	enum tui_cursors cursor;
	bool mouse_fwd;

/* simulate refresh-rate to balance
 * throughput, responsiveness, power consumption */
	int refresh_rate;
};

struct tui_context;

/*
 * match the labelhint structure in shmif_event
 */
struct tui_labelent {
	char label[16];
	char initial[16];
	char descr[58];
	uint16_t subb;
	uint8_t idatatype;
};

/*
 * fill in the events you want to handle, will be dispaced during process
 */
struct tui_cbcfg {
/*
 * appended last to any invoked callback
 */
	void* tag;

/*
 * Called when the label-list has been invalidated and during first
 * return true if [dstlbl] was successfully set.
 * [lang/country] correspond to the last known GEOHINT.
 * if NULL, that information is not used.
 */
	bool (*query_label)(struct tui_context*,
		size_t ind, const char* country, const char* lang,
		struct tui_labelent* dstlbl);

/*
 * an explicit label- input has been sent,
 * return true if the label is consumed (no further processing)
 */
	bool (*input_label)(struct tui_context*,
		const char* label, bool active, void*);

/*
 * an explicit analog- label input has been sent,
 * [n] number of samples in [smpls]
 * [rel] set if relative some previous or device/datatype specific pos
 * [datatype] see shmif_event.h, to get type
 */
	bool (*input_alabel)(struct tui_context*,
		const char* label, const int16_t* smpls,
		size_t n, bool rel, uint8_t datatype, void*
	);

/*
 * mouse motion/button, may not always be enabled depending on mouse-
 * management flag switch (user-controlled between select/copy/paste and
 * normal)
 */
	void (*input_mouse_motion)(struct tui_context*,
		bool relative, int x, int y, int modifiers, void*);

	void (*input_mouse_button)(struct tui_context*,
		int last_x, int last_y, int button, bool active, int modifiers, void*);

/*
 * single UTF8- character
 */
	bool (*input_utf8)(struct tui_context*, const char* u8, size_t len, void*);

/*
 * other KEY where we are uncertain about origin, filled on a best-effort
 * (should be last-line of defence after label->utf8|sym->mouse->[key]
 */
	void (*input_key)(struct tui_context*, uint32_t symest,
		uint8_t scancode, uint8_t mods, uint16_t subid, void* tag);

/*
 * other input- that wasn't handled in the other callbacks
 */
	void (*input_misc)(struct tui_context*, const arcan_ioevent*, void*);

/*
 * state transfer, [input=true] if we should receive a state-block that was
 * previously saved or [input=false] if we should store. dup+thread+write or
 * write to use or ignore (closed after call)
 */
	void (*state)(struct tui_context*, bool input, int fd, void*);

/*
 * request to send or receive a binary chunk, [input=true,size=0] for streams
 * of unknown size, [input=false] then size is 'recommended' upper limit, if set.
 */
	void (*bchunk)(struct tui_context*, bool input, uint64_t size, int fd, void*);

/*
 * one video frame has been pasted, accessible during call lifespan
 */
	void (*vpaste)(struct tui_context*,
		shmif_pixel*, size_t w, size_t h, size_t stride, void*);

/*
 * paste-action, audio stream block [channels interleaved]
 */
	void (*apaste)(struct tui_context*,
		shmif_asample*, size_t n_samples, size_t frequency, size_t nch, void*);

/*
 * events that wasn't covered by the TUI internal event loop that might
 * be of interest to the outer connection / management
 */
	void (*raw_event)(struct tui_context*, arcan_tgtevent*, void*);

/*
 * periodic parent-driven clock
 */
	void (*tick)(struct tui_context*, void*);

/*
 * pasted a block of text, continuous flag notes if there are more to come
 */
	void (*utf8)(struct tui_context*,
		const uint8_t* str, size_t len, bool cont, void*);

/*
 * the underlying size has changed, expressed in both pixels and rows/columns
 */
	void (*resized)(struct tui_context*,
		size_t neww, size_t newh, size_t col, size_t row, void*);

/*
 * only reset levels that should require action on behalf of the caller are
 * being forwarded, this currently excludes > 1
 */
	void (*reset)(struct tui_context*, int level, void*);

/*
 * comparable to a locale switch (which the backend obviously cannot perform
 * without introducing subtle bugs like . -> , without the caller knowing,
 * but with more detail.
 *
 * check ISO-3166-1 for a3_country, ISO-639-2 for a3_language
 */
	void (*geohint)(struct tui_context*, float lat, float longitude, float elev,
		const char* a3_country, const char* a3_language, void*);

/*
 * [RESERVED, NOT_IMPLEMENTED]
 * for cells that have been written with the CUSTOM_DRAW attribute,
 * this function will be triggered whenever such a cell should be updated
 *
 * [vidp] will be aligned to the upper-left corner of the cell. The number
 * of horizontal pixels will be [px_w] * [cols] (the possibility of multiple
 * CUSTOM_DRAW cells on a row). cell_w = px_w / cols, cell_h = px_h.
 * Add [pitch] to [vidp] to increment row.
 *
 * Note that [cols] may cover several cells on the same row
 */
	void (*draw_call)(struct tui_context*, shmif_pixel* vidp,
		size_t px_w, size_t px_h, size_t cols, size_t pitch, void*);

/*
 * A new subwindow has arrived, map it using arcan_shmif_acquire:
 * arcan_shmif_cont newc = arcan_shmif_acquire(acon, NULL, SEGID_your_type, 0);
 * and then run the normal _tui setup for event management etc.
 */
	void (*subwindow)(struct tui_context*,
		enum ARCAN_SEGID type, uint32_t id, struct arcan_shmif_cont* cont, void*);

/*
 * add new callbacks here as needed, since the setup requires a sizeof of
 * this struct as an argument, we get some light indirect versioning
 */
};

struct tui_settings arcan_tui_defaults();

/*
 * Use the contents of [arg_arr] and/or [tui_model:may be NULL] to modify the
 * defaults in tui_settings. This might duplicate descriptors into the target
 * settings structures that will be taken control of by the tui_setup call.
 * Manually cleanup if _apply_arg is not forwarded to _tui_setup.
 */
void arcan_tui_apply_arg(struct tui_settings*,
	struct arg_arr*, struct tui_context*);

/*
 * takes control over an existing connection, it is imperative that no ident-
 * or event processing has been done, so [con] should come straight from a
 * normal arcan_shmif_open call.
 *
 * settings, cfg and con will all be copied to an internal tracker,
 * if (return) !null, the contents of con is undefined
 */
struct tui_context* arcan_tui_setup(struct arcan_shmif_cont* con,
	const struct tui_settings* set, const struct tui_cbcfg* cfg,
	size_t cfg_sz, ...
);

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
 *  TUI_ERRC_BAD_FD - then the .bad field will show bad descriptors
 *  TUI_ERRC_BAD_CTX - then the .ok field will show bad contexts
 */
struct tui_process_res {
	uint32_t ok;
	uint32_t bad;
	int errc;
};
struct tui_process_res arcan_tui_process(
	struct tui_context** contexts, size_t n_contexts,
	int* fdset, size_t fdset_sz, int timeout);

/*
 * If the TUI- managed connection is marked as dirty, synch the
 * relevant regions and return (handles multiple- contexts)
 *
 * returns a bitmask over the contexts that were updated
 */
uint64_t arcan_tui_refresh(
	struct tui_context** contexts, size_t n_contexts);

/*
 * Explicitly invalidate the context, next refresh will likely
 * redraw fully. Should only be needed in exceptional cases
 */
void arcan_tui_invalidate(struct tui_context*);

/*
 * get temporary access to the current state of the TUI/context,
 * returned pointer is undefined between calls to process/refresh
 */
struct arcan_shmif_cont* arcan_tui_acon(struct tui_context*);

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
	TUI_ALTERNATE = 64,
	TUI_CUSTOM_DRAW = 128,
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

/*
 * try to send the contents of utf8_msg, careful with length of this
 * string as it will be split into ~64b chunks that each consume an
 * event-queue slot, and may therefore stall for long periods of time.
 *
 * if mouse_fwd mode has been enabled (by user or in the _tui_setup),
 * this is the only way to send data to the pasteboard.
 *
 * will fail if the pasteboard has been disabled (by user).
 */
bool arcan_tui_paste(struct tui_context*, const char* utf8_msg);

/*
 * update title or identity
 */
void arcan_tui_ident(struct tui_context*, const char* ident);

/*
 * Send a new request for a subwindow with life-span that depends on
 * the main connection. The subwindows don't survive migration, if that
 * is needed for the data that should be contained -- setup a new full
 * connection. May be needed to inherit font settings to subsegments.
 */
void arcan_tui_request_subwnd(struct tui_context*, uint32_t id);

/* clear cells to default state, if protect toggle is set,
 * cells marked with a protected attribute will be ignored */
void arcan_tui_erase_screen(struct tui_context*, bool protect);
void arcan_tui_erase_region(struct tui_context*,
	size_t x1, size_t y1, size_t x2, size_t y2, bool protect);
void arcan_tui_erase_sb(struct tui_context*);

/*
 * helpers that match erase_region + invalidate + cursporpos
 */
void arcan_tui_erase_cursor_to_screen(struct tui_context*, bool protect);
void arcan_tui_erase_screen_to_cursor(struct tui_context*, bool protect);
void arcan_tui_erase_cursor_to_end(struct tui_context*, bool protect);
void arcan_tui_erase_home_to_cursor(struct tui_context*, bool protect);
void arcan_tui_erase_current_line(struct tui_context*, bool protect);
void arcan_tui_erase_chars(struct tui_context*, size_t n);

/*
 * insert a new UCS4* (tsm uses an internal format with a hash-table for
 * metadata, but UCS4 is acceptable right now) at the current cursor position
 * with the specified attribute mask.
 */
void arcan_tui_write(struct tui_context*,
	uint32_t ucode, struct tui_screen_attr*);

/*
 * similar to insert UCS4*, but takes a utf8- string and converts it before
 * mapping to corresponding UCS4* inserts. Thus, _tui_write should be preferred
 */
bool arcan_tui_writeu8(struct tui_context*,
	uint8_t* u8, size_t, struct tui_screen_attr*);

/*
 * retrieve the current cursor position into the [x:col] and [y:row] field
 */
void arcan_tui_cursorpos(struct tui_context*, size_t* x, size_t* y);

/*
 * lock input handling and switch to a libreadline (actually linenoise)
 * style management, will trigger callbacks on completion- and cancel- when
 * the control is returned.
 *
 * completion is called (line == NULL if error or user cancelled, otherwise
 * callee assumes responsibility of heap-allocated line).
 *
 * hints is
 */
struct tui_completions {
	size_t len;
	char** cvec;
};

/*
void arcan_tui_readline(struct tui_context*,
	void(*completion)(struct tui_context*, const char* line),
	size_t n_lines,
	size_t max
);
 */
/* hints, freehints, completion */


/*
 * reset state-tracking, scrollback buffers, ...
 */
void arcan_tui_reset(struct tui_context*);

/*
 * modify the current flags/state bitmask with the values of tui_flags ( |= )
 */
void arcan_tui_set_flags(struct tui_context*, enum tui_flags);

/*
 * modify the current flags/state bitmask and unset the values of tui (& ~)
 */
void arcan_tui_reset_flags(struct tui_context*, enum tui_flags);

/*
 * mark the current cursor position as a tabstop
 */
void arcan_tui_set_tabstop(struct tui_context*);

/*
 * insert [n] number of empty lines with the default attributes
 * (amounts to a loop of _write calls)
 */
void arcan_tui_insert_lines(struct tui_context*, size_t);

/*
 * CR / LF
 */
void arcan_tui_newline(struct tui_context*);

/*
 * remove [n] number of lines
 */
void arcan_tui_delete_lines(struct tui_context*, size_t);

/*
 * insert [n] number of empty characters
 * (amounts to a loop of _write calls with the default attributes)
 */
void arcan_tui_insert_chars(struct tui_context*, size_t);
void arcan_tui_delete_chars(struct tui_context*, size_t);

/*
 * move cursor [n] tab-stops positions forward or backwards
 */
void arcan_tui_tab_right(struct tui_context*, size_t);
void arcan_tui_tab_left(struct tui_context*, size_t);

/*
 * scroll the window [n] lines up or down in the scrollback buffer
 */
void arcan_tui_scroll_up(struct tui_context*, size_t);
void arcan_tui_scroll_down(struct tui_context*, size_t);

/*
 * remove the tabstop at the current position
 */
void arcan_tui_reset_tabstop(struct tui_context*);
void arcan_tui_reset_all_tabstops(struct tui_context*);

/*
 * move the cursor either absolutely or a number of steps,
 * optionally by also scrolling the scrollback buffer
 */
void arcan_tui_move_to(struct tui_context*, size_t x, size_t y);
void arcan_tui_move_up(struct tui_context*, size_t num, bool scroll);
void arcan_tui_move_down(struct tui_context*, size_t num, bool scroll);
void arcan_tui_move_left(struct tui_context*, size_t);
void arcan_tui_move_right(struct tui_context*, size_t);
void arcan_tui_move_line_end(struct tui_context*);
void arcan_tui_move_line_home(struct tui_context*);
int arcan_tui_set_margins(struct tui_context*, size_t top, size_t bottom);

/*
 * retrieve the current dimensions (same as accessible through _resize)
 */
void arcan_tui_dimensions(struct tui_context*, size_t* rows, size_t* cols);

/*
 * override the default attributes that apply to resets etc.
 */
void arcan_tui_defattr(struct tui_context*, struct tui_screen_attr*);
void arcan_tui_refinc(struct tui_context*);
void arcan_tui_refdec(struct tui_context*);
#endif
