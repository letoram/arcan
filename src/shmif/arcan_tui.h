/*
 Arcan Text-Oriented User Interface Library

 Copyright (c) 2014-2018, Bjorn Stahl
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

#ifndef HAVE_ARCAN_TUI
#define HAVE_ARCAN_TUI

/*
 * [ABOUT]
 * This is a library intended to make development of rich text-oriented user
 * interfaces that are free from the legacy- cruft of terminal emulation
 * protocols, with the intent of offering better system integration, lower
 * latency, faster drawing and access to more features, and to take advantage
 * of existing display servers and window managers. It is not intended to
 * provide UI- components as such, only access to subsystems like input,
 * drawing and storage- with a bias towards text output and keyboard input.
 *
 * [PORTABILITY]
 *  In order to allow custom backends that use other IPC and drawing systems to
 *  avoid a lock-in or dependency on Arcan, there is a separate arcan_tuidefs.h
 *  as an intermediate step in order to be able to move away from the shmif-
 *  dependency entirely. It contains the type mapping of all opaque- structures
 *  provided herein and should help when writing another backend. The biggest
 *  caveat is likely custom drawing into cells as it binds the color-space to
 *  sRGB and the packing format to a macro.
 *
 * [STABILITY]
 *  The majority of the interface exposed here in terms of enumerations and
 *  types is mostly safe against breaking changes. To be extra careful, wait
 *  until a mirror- repo @github.com/letoram/arcan-tui.git has been set up
 *  and all the fields updated. This will likely coincide with the 0.5.4
 *  release.
 *
 * [THREAD SAFETY]
 *  The main allocation, initial setup routines are currently not safe for
 *  multithreaded use and there might be some state bleed between text
 *  rendering. Each individual context, however, should ultimately work both in
 *  multithreaded- and multiprocess- (though other systems such as libc memory
 *  allocation may not be) use.
 *
 * [LICENSING / ACKNOWLEDGEMENTS]
 *  The default implementation is built on a forked version of libTSM
 *  (c) David Herrmann, which pulls in dependencies that make the final
 *  output LGPL2.1+. The intent of the library and API itself is to be BSD
 *  licensed.
 *
 * [USE]
 *  Display-server/backend specific connection setup/wrapper that
 *  provides the opaque arcan_tui_conn structure. All symbols and flag
 *  values are kept separately in arcan_tuisym.h
 *
 *  struct tui_cbcfg cb {
 *     SET EVENT-HANDLERS HERE (e.g. input_key, tick, geohint, ...)
 *  };
 *
 *  arcan_tui_conn* conn = arcan_tui_open_display("mytitle", "myident");
 *  struct tui_settings cfg = arcan_tui_defaults(conn, NULL);
 *  struct tui_context* ctx = arcan_tui_setup(conn, cfg, cb, sizeof(cb));
 *
 *  normal processing loop:
 *   (use fdset/fdset_sz and timeout for poll-like behavior)
 *
 *  while (running){
 *  	struct tui_process_res res =
 *  		arcan_tui_process(&ctx, 1, NULL, 0, -1);
 *  	if (res.errc == 0){
 *
 *  	}
 *
 *  UPDATED/TIME TO DRAW?
 *  	if (-1 == arcan_tui_refresh(ctx) && errno == EINVAL)
 *  		break;
 * }
 *
 * subwindows:
 * (in subwnd handler from cbs)
 *  arcan_tui_defaults(conn, wnd);
 *  struct tui_context* con = arcan_tui_setup(conn, cfg, cb, sizeof(cb));
 *  arcan_tui_wndhint(con, ...);
 *
 * Normal use/drawing functions (all prefixed with arcan_tui_):
 *  erase_screen(ctx, prot)
 *  erase_region(ctx, x1, y1, x2, y2, prot)
 *  erase_cursor_to_screen(ctx, prot)
 *  erase_home_to_cursor(ctx, prot)
 *  erase_current_line(ctgx)
 *  erase_chars(ctx, n)
 *  write(ucs4, attr)
 *  writeu8(uint8_t* u8, size_t n, attr)
 *  insert_lines(ctx, n)
 *  newline(ctx)
 *  delete_lines(ctx, n)
 *  insert_chars(ctx, n)
 *  delete_chars(ctx, n)
 *  set_tabstop(ctx)
 *  reset_tabstop(ctx)
 *  reset_all_tabstops(ctx)
 *
 * Virtual Screen management:
 *  int ind = alloc_screen(ctx)
 *  switch_screen(ctx, ind)
 *  delete_screen(ctx, ind)
 *  scroll_up(ctx, n)
 *  scroll_down(ctx, n)
 *  set_margins(ctx, top, bottom)
 *  dimensions(ctx, size_t* rows, size_t* cols)
 *  request_subwnd(ctx, id, type)
 *
 * Cursor Management:
 *  cursorpos(ctx, size_t* x, size_t* y)
 *  tab_right(ctx, n)
 *  tab_left(ctx, n)
 *  move_to(ctx, x, y)
 *  move_up(ctx, num, scroll)
 *  move_down(ctx, num, scroll)
 *  move_left(ctx, num)
 *  move_right(ctx, num)
 *  move_line_end(ctx)
 *  move_line_home(ctx)
 *
 * Metadata:
 *  copy(ctx, msg)
 *  ident(ctx, ident)
 *
 * Context Management:
 *  reset(ctx)
 *  set_flags(ctx, flags)
 *  reset_flags(ctx, flags)
 *  defattr(ctx, attr)
 *
 * Dynamic Loading:
 *
 * For the cases where you want dynamic loading of the TUI functions,
 * define ARCAN_TUI_DYNAMIC before including the header file and the
 * normal external function entry points will be replaced with same-
 * name static scoped function pointers. In order to initialize them,
 * run the arcan_tui_dynload in the same compilation unit with a
 * loader function provided as a function pointer argument.
 *
 * [MISSING/PENDING FEATURES]
 *  [ ] Simple audio
 *  [ ] Announce binary- file input and output- capabilities
 *  [ ] Language bindings, readline like API
 *  [ ] Argument- validation mode
 *  [ ] External process- to window mapping
 *  [ ] pack/unpack function to deal with serialization of a line protocol
 *  [ ] Translation that exposes the NCurses API
 */

#include "arcan_tuidefs.h"
#include "arcan_tuisym.h"

struct tui_settings {
	uint8_t bgc[3], fgc[3], cc[3], clc[4];
	uint8_t alpha;
	float ppcm;
	int hint;

	float font_sz; /* mm */
	size_t cell_w, cell_h;

/* either using strings or pre-opened fonts */
	const char* font_fn;
	const char* font_fb_fn;
	int font_fds[2];

/* see: enum tui_cursors */
	int cursor;
	bool mouse_fwd;

/* simulate refresh-rate to balance
 * throughput, responsiveness, power consumption */
	int refresh_rate;

/* number of 25Hz ticks between blink-in/blink-off */
	unsigned cursor_period;

/* 0 : disabled, 0 < n <= cell_h
 * - enable vertical smooth scrolling in px. */
	unsigned smooth_scroll;

/* see syms for possible render flags */
	unsigned render_flags;
};

struct tui_context;

struct tui_screen_attr {
	union {
		uint8_t fc[3];
		struct {
			uint8_t fr;
			uint8_t fg;
			uint8_t fb;
		};
	};
	union {
		uint8_t bc[3];
		struct {
			uint8_t br; /* background red */
			uint8_t bg; /* background green */
			uint8_t bb; /* background blue */
		};
	};
	unsigned int bold : 1; /* bold character */
	unsigned int underline : 1; /* underlined character */
	unsigned int italic : 1;
	unsigned int inverse : 1; /* inverse colors */
	unsigned int protect : 1; /* cannot be erased */
	unsigned int blink : 1; /* blinking character */
	unsigned int strikethrough : 1;
	unsigned int shape_break : 1; /* reset shaping and align to grid */

/*  > 127: cell is used for a custom draw-call, will be used with -127
 *         subtracted in custom draw callback. The actual ch field can
 *         thus be used for storing additional drawing hints.
 * 0..127: act as a user-supplied type-id, will be drawn as normal but
 *         can be queried for in selection buffers etc. */
	uint8_t custom_id;
};

/* _Static_assert(sizeof(tui_screen_attr) == 8) */

static inline bool tui_attr_equal(
	struct tui_screen_attr a, struct tui_screen_attr b)
{
	return (
		a.fr == b.fr &&
		a.fg == b.fg &&
		a.fb == b.fb &&
		a.br == b.br &&
		a.bg == b.bg &&
		a.bb == b.bb &&
		a.bold == b.bold &&
		a.underline == b.underline &&
		a.italic == b.italic &&
		a.inverse == b.inverse &&
		a.protect == b.protect &&
		a.blink == b.blink &&
		a.strikethrough == b.strikethrough &&
		a.shape_break == b.shape_break &&
		a.custom_id == b.custom_id
	);
}

struct tui_cell {
/* drawing properties */
	struct tui_screen_attr attr;

/* used for substitutions */
	uint32_t ch, draw_ch;

/* resolved after shaping has been applied */
	uint32_t real_x;
	uint8_t cell_w;

/* cycling counter for when the cell was last updated */
	uint8_t fstamp;
};

/*
 * used with the 'query_label' callback.
 */
struct tui_labelent {
/* 7-bit ascii reference string */
	char label[16];

/* user-readable short description */
	char descr[58];

/* button : 0
 * axis-motion : 1
 * touch : 2 */
	uint8_t idatatype;

/* match enum tuik_syms in _tuisyms.h */
	uint16_t initial;
/*optional alias- for label */
	uint16_t subv;
/* modifier-mask, from _tuisyms.h */
	uint16_t modifiers;
};

/*
 * fill in the events you want to handle, will be dispatched during process
 */
struct tui_cbcfg {
/*
 * appended last to any invoked callback
 */
	void* tag;

/*
 * Called when the label-list has been invalidated and during setup.  [ind]
 * indicates the requested label index. This will be sweeped from low (0) and
 * incremented until query_label() returns false.
 *
 * A new sweep may be initiated on a new GEOHINT or a state reset.
 *
 * [lang] and [country] are either set to the last known GEOHINT
 * or [NULL] to indicate some default unspecified english.
 *
 * [dstlbl] should be filled out according to the labelent structure and the
 * function should return TRUE if there is a label at the requested index - or
 * FALSE if there are no more labels to register.
 */
	bool (*query_label)(struct tui_context*,
		size_t ind, const char* country, const char* lang,
		struct tui_labelent* dstlbl, void*);

/*
 * An explicit label- input has been sent,
 *
 * [label] is a string identifier that may correspond to an
 *         exposed label from previous calls to query_label().
 * [active] indicates that the unspecified source input device
 *          has transitioned from an inactive to an active state
 *          (rasing) or from a previously active to an inactive
 *          state (falling).
 *
 * return TRUE if the label was consumed, FALSE if the label
 * should be treated by a (possible) internal/masked implementation.
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
 * Mouse motion has occured within the context. [x] and [y] indicate
 * the current CELL (x -> col, y -> row). Will only happen if mouse
 * events are set to be forwarded by some TUI implementation specific
 * means.
 */
	void (*input_mouse_motion)(struct tui_context*,
		bool relative, int x, int y, int modifiers, void*);

/*
 * Mouse button state has changed for some button index.
 */
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
 * periodic parent-driven clock
 */
	void (*tick)(struct tui_context*, void*);

/*
 * pasted a block of text, continuous flag notes if there are more to come
 */
	void (*utf8)(struct tui_context*,
		const uint8_t* str, size_t len, bool cont, void*);

/*
 * The underlying size has changed, expressed in both pixels and rows/columns
 * WARNING:
 *  Be careful not to process, refresh or other similar actions from the
 *  context of this or the 'resize' callback. Only modifications to the
 *  normals cells should be considered.
 */
	void (*resized)(struct tui_context*,
		size_t neww, size_t newh, size_t col, size_t row, void*);

/*
 * only reset levels that should require action on behalf of the caller are
 * being forwarded, this covers levels > 1.
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
 * [EXPERIMENTAL]
 * Marked as experimental due to the possibility of explicitly require a
 * differently typed surface as the actual carrier (maybe a subseg
 * with a media type acting as tileset would suffice..).
 *
 * This is used to indicate that custom- drawn cells NEEDS to be updated
 * [invalidated=true], and to query if the specified regions has been updated
 * (return true). Use type-unique IDs and stick to continous regions as to not
 * kill efficiency outright.
 *
 * A custom-draw call have the cell- attribute of a custom_id > 127
 * (0..127 are used for type-/metadata- annotation)
 *
 * This is grouped on continous columns only, and can be invoked by
 * multiple worker threads in parallel.
 *
 * The pixel format is fixed to BGRA in sRGB color space. A convenience
 * blit pattern is:
 * vidp[src_cy * ystep + src_cx] = TUI_PACK(R, G, B, 0xff or alpha)
 *
 * Note that vidp is aligned to actual start-row (can be at an offset in the
 * case of soft-scrolling) and cell_h can be less than the current cell height.
 *
 * return [true] if the designated region was updated. if invalidated is
 * set is set, the vidp is assumed to be updated regardless of return value.
 */
	bool (*draw_call)(struct tui_context*, tui_pixel* vidp,
		uint8_t custom_id, size_t ystep_index, uint8_t cell_yofs,
		uint8_t cell_w, uint8_t cell_h, size_t cols,
		bool invalidated, void*);

/*
 * The color-mapping (palette) has been updated and new attributes
 * take this into account. If the program is running in the alternate-
 * screen mode, use this as a trigger to redraw and recolor.
 */
	void (*recolor)(struct tui_context*, void*);

/*
 * A new subwindow has arrived or the request has failed (=NULL). This should
 * either be bound to a new tui context via the arcan_tui_setup() call using
 * the provided connection argument here and return true, OR don't touch it
 * and return false.
 *
 * WARNING: mapping the connection via arcan_tui_setup and returning FALSE
 * may cause use-after-free or other memory corruption issues.
 */
	bool (*subwindow)(
		struct tui_context*, arcan_tui_conn*, uint32_t id, uint8_t type, void*);

/*
 * Dynamic glyph substitution callback per updated row. This allows you to
 * change cell attributes pre-rendering, particularly for the purpose of
 * indicating/updating shaping-breaks so that, if the renderer is operating
 * in a shaped mode, can realign appropriately - but also to perform custom/
 * manual glyph substitutions or disable the default- shaper/substituter.
 *
 * return true if the contents of the cells were modified, false otherwise.
 *
 * For more advanced shaping that depend on the font and font properties
 * used, leave the callback to its default callback table state or forward-
 * chain to the default callback state from here (though check if it is set).
 */
	bool (*substitute)(struct tui_context*,
		struct tui_cell* cells, size_t n_cells, size_t row, void* t);

/*
 * The underlying size is about to change, expressed in both pixels and
 * rows/columns
 */
	void (*resize)(struct tui_context*,
		size_t neww, size_t newh, size_t col, size_t row, void*);

/*
 * Window visibility and input focus state has changed
 */
	void (*visibility)(struct tui_context*, bool visible, bool focus, void*);

/*
 * Context has changed liveness state
 * 0 : normal operation
 * 1 : suspend state, execution should be suspended, next event will
 *     exec_state into normal or terminal state
 * 2 : terminal state, context is dead
 */
	void (*exec_state)(struct tui_context*, int state);

/*
 * Add new callbacks here as needed, since the setup requires a sizeof of
 * this struct as an argument, we get some light indirect versioning
 */
};

enum tui_process_errc {
	TUI_ERRC_OK = 0,
	TUI_ERRC_BAD_ARG = -1,
	TUI_ERRC_BAD_FD = -2,
	TUI_ERRC_BAD_CTX = -3,
};

struct tui_region {
	int dx, dy;
	size_t x, y;
	size_t w, h;
};

struct tui_process_res {
	uint32_t ok;
	uint32_t bad;
	int errc;
};
#ifndef ARCAN_TUI_DYNAMIC

/*
 * Grab the default settings for a reference connection or a previously
 * allocated context. If both [conn] and [ref] are NULL, return some safe
 * build-time defaults. Otherwise bias towards [conn] and fill in any
 * blanks from [ref].
 */
struct tui_settings arcan_tui_defaults(
	arcan_tui_conn* conn, struct tui_context* ref);

/*
 * Take a reference connection [conn != NULL] and wrap/take over control
 * over that to implement the TUI abstraction. The actual contents of [con]
 * is implementation defined and depends on the backend and TUI
 * implementation used.
 *
 * The functions implemented in [cfg] will be used as event- callbacks,
 * and [cfg_sz] is a simple sizeof(struct tui_cbcfg) as a primitive means
 * of versioning.
 */
struct tui_context* arcan_tui_setup(arcan_tui_conn* con,
	const struct tui_settings* set, const struct tui_cbcfg* cfg,
	size_t cfg_sz, ...
);

/*
 * Destroy the tui context and the managed connection. If the exit state
 * is successful (EXIT_SUCCESS equivalent), leave [message] as NULL.
 * Otherwise provide a short user-readable error description.
 */
void arcan_tui_destroy(struct tui_context*, const char* message);

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
struct tui_process_res arcan_tui_process(
	struct tui_context** contexts, size_t n_contexts,
	int* fdset, size_t fdset_sz, int timeout);

/*
 * Extract the current set of pollable descriptors (for custom
 * multiplexing) and store at most [fddst_lim] into [fdset].
 *
 * This set can change between _tui_process calls, and thus need
 * to be repopulated. Returns the number of descriptors that have
 * been stored.
 */
size_t arcan_tui_get_handles(
	struct tui_context** contexts, size_t n_contexts,
	int fddst[], size_t fddst_lim);

/*
 * Update and synch the specified context.
 * Returns:
 *  1 on success
 *  0 on state-ok but no need to sync
 * -1 and errno (:EAGAIN) if the connection is already busy synching
 * -1 and errno (:EINVAL) if the connection is broken
 */
int arcan_tui_refresh(struct tui_context*);

/*
 * Explicitly invalidate the context, next refresh will likely
 * redraw fully. Should only be needed in exceptional cases
 */
void arcan_tui_invalidate(struct tui_context*);

/*
 * get temporary access to the current state of the TUI/context,
 * returned pointer is undefined between calls to process/refresh
 */
arcan_tui_conn* arcan_tui_acon(struct tui_context*);

/*
 * Open a new connection to a TUI- capable display and return an opaque
 * connection reference or NULL if no connection could be established. If a
 * handle is provided, forward it to arcan_tui_setup which will take over
 * lifecycle management for the connection.
 */
arcan_tui_conn* arcan_tui_open_display(const char* title, const char* ident);

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
bool arcan_tui_copy(struct tui_context*, const char* utf8_msg);

/*
 * update title or identity
 */
void arcan_tui_ident(struct tui_context*, const char* ident);

/*
 * get a copy of the contents of the front(f = true) or last(f = false)
 * cell-level buffer at the x, y coordinates. If x,y is out of bounds,
 * an empty cell will be returned.
 */
struct tui_cell arcan_tui_getxy(struct tui_context*, size_t x, size_t y,bool f);

/*
 * Send a new request for a subwindow with life-span that depends on the main
 * connection. The subwindows don't survive migration and will thus be lost on
 * a ->reset.
 *
 * A request is asynchronous, and [id] is only used for the caller to be able
 * to pair the event delivery with a request. See the (subwindow) tui_cbcfg
 * entry for more details. Note that subwindows can be delivered as an explicit
 * "I want you to deal with this" kind of scenario, typically for the TUI_DEBUG
 * type as a means of dynamically enabling implementation-defined debug output
 * on demand.
 *
 * The possible types are defined as part of arcan_tuisym.h
 */
void arcan_tui_request_subwnd(struct tui_context*, unsigned type, uint16_t id);

/*
 * Replace (copy over) the active handler table with a new one.
 * if the provided cbcfg is NULL, no change to the active set will be
 * performed, to drop all callbacks, instead, use:
 * arcan_tui_update_handlers(tui, &(struct tui_cbcfg){}, sizeof(struct tui_cbcfg));
 */
void arcan_tui_update_handlers(
	struct tui_context*, const struct tui_cbcfg*, size_t cb_sz);

/*
 * Signal visibility and position intent for a subwindow [wnd] relative
 * to a possible parent [par].
 *
 * [wnd] must have been allocated via the _request_subwnd -> subwindow
 * call path. While as [par] must be NULL or refer to the same context
 * as the subwnd call initiated from.
 *
 * By default, [anch_row, anch_col] refer to an anchor-cell in the parent
 * window, but this behavior can switch to allow relative- positioning or
 * window-relative anchoring.
 */
void arcan_tui_wndhint(struct tui_context* wnd,
	struct tui_context* par, int anch_row, int anch_col,
	int wndflags);

/*
 * Clear all cells (or cells not marked protected) to the default attribute.
 * This MAY invalidate the entire screen for redraw. Prefer to only erase
 * regions that should actually be cleared and updated.
 */
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
 * Create an additional screen up to a fixed limit of 32.
 * Returns the new screen index (0 <= n <= 31) or -1 if all screen
 * slots have been allocated.
 */
int arcan_tui_alloc_screen(struct tui_context*);

/*
 * Switch active screen to [ind], return status indicates success/fail.
 * This will impose a render/block+synch operation.
 * Index [0] will always refer to the default screen.
 * If no screen exists at the specified [ind], the call will fail.
 */
bool arcan_tui_switch_screen(struct tui_context*, unsigned ind);

/*
 * Delete the screen specified by [ind], return status indicates success/fail.
 * Index [0] is guaranteed to always exist and cannot be deleted.
 * If the screen that is to be deleted is the same as the screen that is
 * active, index [0] will be activated first.
 * If no screen exists at the specified [ind], the call will fail.
 */
bool arcan_tui_delete_screen(struct tui_context*, unsigned ind);

/*
 * Get the screen allocation bitmap
 */
uint32_t arcan_tui_screens(struct tui_context*);

/*
 * Insert a new unicode codepoint (expressed as UCS4) at the current cursor
 * position. If an attribute is provided (!null) it will be used for the
 * write operation, otherwise, the current default will be used.
 */
void arcan_tui_write(struct tui_context*,
	uint32_t ucode, struct tui_screen_attr*);

/*
 * (Helper function)
 * This converts [n] bytes from [u8] as UTF-8 into multiple UCS4 writes.
 * It is a more expensive form of arcan_tui_write. If the UTF-8 failed to
 * validate completely, the function will return false - but codepoints
 * leading up to the failed sequence may have already been written. If all
 * [n] bytes were consumed, the function returns true.
 */
bool arcan_tui_writeu8(struct tui_context*,
	const uint8_t* u8, size_t n, struct tui_screen_attr*);

/*
 * (Helper function)
 * This calculates the length of the provided character array and forwards
 * into arcan_tui_writeu8, same encoding and return rules apply.
 */
bool arcan_tui_writestr(
	struct tui_context*, const char* str, struct tui_screen_attr*);

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

struct tui_completions {
	size_t len;
	char** cvec;
};

void arcan_tui_readline(struct tui_context*,
	void(*completion)(struct tui_context*, const char* line),
	size_t n_lines,
	size_t max
);
*/

/*
 * Fill out rgb[] with the current values of the specified color group.
 * see the enum tui_color_group for valid values.
 */
void arcan_tui_get_color(struct tui_context* tui, int group, uint8_t rgb[3]);

/*
 * Update the color field for the specified group. This
 */
void arcan_tui_set_color(struct tui_context* tui, int group, uint8_t rgb[3]);

/*
 * reset state-tracking, scrollback buffers, ...
 */
void arcan_tui_reset(struct tui_context*);

/*
 * modify the current flags/state bitmask with the values of tui_flags ( |= )
 * returns the mask as it.
 * see tuisym.h for enum tui_flags
 */
int arcan_tui_set_flags(struct tui_context*, int tui_flags);

/*
 * modify the current flags/state bitmask and unset the values of tui (& ~)
 */
void arcan_tui_reset_flags(struct tui_context*, int tui_flags);

/*
 * mark the current cursor position as a tabstop
 */
void arcan_tui_set_tabstop(struct tui_context*);

/*
 * insert [n] number of empty lines with the default attributes
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
 * this is a no-op in alt-screen.
 */
void arcan_tui_scroll_up(struct tui_context*, size_t);
void arcan_tui_scroll_down(struct tui_context*, size_t);

/*
 * remove the tabstop at the current position
 */
void arcan_tui_reset_tabstop(struct tui_context*);
void arcan_tui_reset_all_tabstops(struct tui_context*);

/*
 * Hint that certain regions have scrolled:
 * (-1, -1) = (up, left), (1, 1 = down, right)
 * so that the render may smooth-scroll between the contents of the
 * last update and the new one.
 *
 * [ALLOCATION NOTES]
 * This allocation is not tracked and will be used/referenced until
 * the next screen refresh call. After it has been used, the dx and dy
 * fields will be set to 0.
 */
void arcan_tui_scrollhint(
	struct tui_context*, size_t n_regions, struct tui_region*);

/*
 * Build a dynamically allocated state description string that can be
 * combined with other debug information to assist in troubleshooting.
 * Caller assumes ownership of returned string.
 */
char* arcan_tui_statedescr(struct tui_context*);

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
struct tui_screen_attr arcan_tui_defattr(
	struct tui_context*, struct tui_screen_attr*);
void arcan_tui_refinc(struct tui_context*);
void arcan_tui_refdec(struct tui_context*);

#else
typedef struct tui_settings(* PTUIDEFAULTS)(arcan_tui_conn*, struct tui_context*);
typedef struct tui_context*(* PTUISETUP)(
	arcan_tui_conn*, const struct tui_settings*, const struct tui_cbcfg*, size_t, ...);
typedef void (* PTUIDESTROY)(struct tui_context*, const char* message);
typedef struct tui_process_res (* PTUIPROCESS)(
struct tui_context**, size_t, int*, size_t, int);
typedef int (* PTUIREFRESH)(struct tui_context*);
typedef void (* PTUIINVALIDATE)(struct tui_context*);
typedef arcan_tui_conn* (* PTUIACON)(struct tui_context*);
typedef arcan_tui_conn* (* PTUIOPENDISPLAY)(const char*, const char*);
typedef bool (* PTUICOPY)(struct tui_context*, const char*);
typedef void (* PTUIIDENT)(struct tui_context*, const char*);
typedef struct tui_cell (* PTUIGETXY)(struct tui_context*, size_t, size_t, bool);
typedef void (* PTUIREQSUB)(struct tui_context*, unsigned, uint16_t);
typedef void (* PTUIUPDHND)(struct tui_context*, const struct tui_cbcfg*, size_t);
typedef void (* PTUIWNDHINT)(struct tui_context*, struct tui_context*, int, int, int);
typedef int (* PTUIALLOCSCR)(struct tui_context*);
typedef bool (* PTUISWSCR)(struct tui_context*, unsigned);
typedef bool (* PTUIDELSCR)(struct tui_context*, unsigned);
typedef uint32_t (* PTUISCREENS)(struct tui_context*);
typedef void (* PTUIWRITE)(struct tui_context*, uint32_t, struct tui_screen_attr*);
typedef bool (* PTUIWRITEU8)(struct tui_context*, const uint8_t*, size_t, struct tui_screen_attr*);
typedef bool (* PTUIWRITESTR)(struct tui_context*, const char*, struct tui_screen_attr*);
typedef void (* PTUICURSORPOS)(struct tui_context*, size_t*, size_t*);
typedef void (* PTUIGETCOLOR)(struct tui_context* tui, int, uint8_t*);
typedef void (* PTUISETCOLOR)(struct tui_context* tui, int, uint8_t*);
typedef void (* PTUIRESET)(struct tui_context*);
typedef void (* PTUISETFLAGS)(struct tui_context*, int);
typedef void (* PTUIRESETFLAGS)(struct tui_context*, int);
typedef void (* PTUISETTABSTOP)(struct tui_context*);
typedef void (* PTUIINSERTLINES)(struct tui_context*, size_t);
typedef void (* PTUINEWLINE)(struct tui_context*);
typedef void (* PTUIDELETELINES)(struct tui_context*, size_t);
typedef void (* PTUIINSERTCHARS)(struct tui_context*, size_t);
typedef void (* PTUIDELETECHARS)(struct tui_context*, size_t);
typedef void (* PTUITABRIGHT)(struct tui_context*, size_t);
typedef void (* PTUITABLEFT)(struct tui_context*, size_t);
typedef void (* PTUISCROLLUP)(struct tui_context*, size_t);
typedef void (* PTUISCROLLDOWN)(struct tui_context*, size_t);
typedef void (* PTUIRESETTABSTOP)(struct tui_context*);
typedef void (* PTUIRESETALLTABSTOPS)(struct tui_context*);
typedef void (* PTUISCROLLHINT)(struct tui_context*, size_t, struct tui_region*);
typedef void (* PTUIMOVETO)(struct tui_context*, size_t, size_t);
typedef void (* PTUIMOVEUP)(struct tui_context*, size_t, bool);
typedef void (* PTUIMOVEDOWN)(struct tui_context*, size_t, bool);
typedef void (* PTUIMOVELEFT)(struct tui_context*, size_t);
typedef void (* PTUIMOVERIGHT)(struct tui_context*, size_t);
typedef void (* PTUIMOVELINEEND)(struct tui_context*);
typedef void (* PTUIMOVELINEHOME)(struct tui_context*);
typedef void (* PTUIDIMENSIONS)(struct tui_context*, size_t*, size_t*);
typedef struct tui_screen_attr
	(* PTUIDEFATTR)(struct tui_context*, struct tui_screen_attr*);
typedef void (* PTUIREFINC)(struct tui_context*);
typedef void (* PTUIREFDEC)(struct tui_context*);
typedef int (* PTUISETMARGINS)(struct tui_context*, size_t, size_t);
typedef void (* PTUIERASESCREEN)(struct tui_context*, bool);
typedef void (* PTUIREGION)(struct tui_context*, size_t, size_t, size_t, size_t, bool);
typedef void (* PTUIERASESB)(struct tui_context*);
typedef void (* PTUIERASECURSORTOSCR)(struct tui_context*, bool);
typedef void (* PTUIERASESCRTOCURSOR)(struct tui_context*, bool);
typedef void (* PTUIERASETOCURSOR)(struct tui_context*, bool);
typedef void (* PTUIERASECURSORTOEND)(struct tui_context*, bool);
typedef void (* PTUIERASEHOMETOCURSOR)(struct tui_context*, bool);
typedef void (* PTUIERASECURRENTLINE)(struct tui_context*, bool);
typedef void (* PTUIERASECHARS)(struct tui_context*, size_t);
typedef void (* PTUIERASEREGION)(struct tui_context*, size_t, size_t, size_t, size_t, bool);
typedef char* (* PTUISTATEDESCR)(struct tui_context*);

static PTUIDEFAULTS arcan_tui_defaults;
static PTUISETUP arcan_tui_setup;
static PTUIDESTROY arcan_tui_destroy;
static PTUIPROCESS arcan_tui_process;
static PTUIREFRESH arcan_tui_refresh;
static PTUIINVALIDATE arcan_tui_invalidate;
static PTUIACON arcan_tui_acon;
static PTUIOPENDISPLAY arcan_tui_open_display;
static PTUICOPY arcan_tui_copy;
static PTUIIDENT arcan_tui_ident;
static PTUIGETXY arcan_tui_getxy;
static PTUIREQSUB arcan_tui_request_subwnd;
static PTUIUPDHND arcan_tui_update_handlers;
static PTUIWNDHINT arcan_tui_wndhint;
static PTUIALLOCSCR arcan_tui_alloc_screen;
static PTUISWSCR arcan_tui_switch_screen;
static PTUIDELSCR arcan_tui_delete_screen;
static PTUISCREENS arcan_tui_screens;
static PTUIWRITE arcan_tui_write;
static PTUIWRITEU8 arcan_tui_writeu8;
static PTUIWRITESTR arcan_tui_writestr;
static PTUICURSORPOS arcan_tui_cursorpos;
static PTUIGETCOLOR arcan_tui_get_color;
static PTUISETCOLOR arcan_tui_set_color;
static PTUIRESET arcan_tui_reset;
static PTUISETFLAGS arcan_tui_set_flags;
static PTUIRESETFLAGS arcan_tui_reset_flags;
static PTUISETTABSTOP arcan_tui_set_tabstop;
static PTUIINSERTLINES arcan_tui_insert_lines;
static PTUINEWLINE arcan_tui_newline;
static PTUIDELETELINES arcan_tui_delete_lines;
static PTUIINSERTCHARS arcan_tui_insert_chars;
static PTUIDELETECHARS arcan_tui_delete_chars;
static PTUITABRIGHT arcan_tui_tab_right;
static PTUITABLEFT arcan_tui_tab_left;
static PTUISCROLLUP arcan_tui_scroll_up;
static PTUISCROLLDOWN arcan_tui_scroll_down;
static PTUIRESETTABSTOP arcan_tui_reset_tabstop;
static PTUIRESETALLTABSTOPS arcan_tui_reset_all_tabstops;
static PTUISCROLLHINT arcan_tui_scrollhint;
static PTUIMOVETO arcan_tui_move_to;
static PTUIMOVEUP arcan_tui_move_up;
static PTUIMOVEDOWN arcan_tui_move_down;
static PTUIMOVELEFT arcan_tui_move_left;
static PTUIMOVERIGHT arcan_tui_move_right;
static PTUIMOVELINEEND arcan_tui_move_line_end;
static PTUIMOVELINEHOME arcan_tui_move_line_home;
static PTUIDIMENSIONS arcan_tui_dimensions;
static PTUIDEFATTR arcan_tui_defattr;
static PTUIREFINC arcan_tui_refinc;
static PTUIREFDEC arcan_tui_refdec;
static PTUISETMARGINS arcan_tui_set_margins;
static PTUIERASESCREEN arcan_tui_erase_screen;
static PTUIERASEREGION arcan_tui_erase_region;
static PTUIERASESB arcan_tui_erase_sb;
static PTUIERASECURSORTOSCR arcan_tui_erase_cursor_to_screen;
static PTUIERASESCRTOCURSOR arcan_tui_erase_screen_to_cursor;
static PTUIERASECURSORTOEND arcan_tui_erase_cursor_to_end;
static PTUIERASEHOMETOCURSOR arcan_tui_erase_home_to_cursor;
static PTUIERASECURRENTLINE arcan_tui_erase_current_line;
static PTUIERASECHARS arcan_tui_erase_chars;
static PTUISTATEDESCR arcan_tui_statedescr;

/* dynamic loading function */
static bool arcan_tui_dynload(void*(*lookup)(void*, const char*), void* tag)
{
#define M(TYPE, SYM) if (! (SYM = (TYPE) lookup(tag, #SYM)) ) return false
M(PTUIDEFAULTS,arcan_tui_defaults);
M(PTUIDESTROY,arcan_tui_destroy);
M(PTUISETUP,arcan_tui_setup);
M(PTUIDESTROY,arcan_tui_destroy);
M(PTUIPROCESS,arcan_tui_process);
M(PTUIREFRESH,arcan_tui_refresh);
M(PTUIINVALIDATE,arcan_tui_invalidate);
M(PTUIACON,arcan_tui_acon);
M(PTUIOPENDISPLAY,arcan_tui_open_display);
M(PTUICOPY,arcan_tui_copy);
M(PTUIIDENT,arcan_tui_ident);
M(PTUIGETXY,arcan_tui_getxy);
M(PTUIREQSUB,arcan_tui_request_subwnd);
M(PTUIUPDHND,arcan_tui_update_handlers);
M(PTUIWNDHINT,arcan_tui_wndhint);
M(PTUIALLOCSCR,arcan_tui_alloc_screen);
M(PTUISWSCR,arcan_tui_switch_screen);
M(PTUIDELSCR,arcan_tui_delete_screen);
M(PTUISCREENS,arcan_tui_screens);
M(PTUIWRITE,arcan_tui_write);
M(PTUIWRITEU8,arcan_tui_writeu8);
M(PTUIWRITESTR,arcan_tui_writestr);
M(PTUICURSORPOS,arcan_tui_cursorpos);
M(PTUIGETCOLOR,arcan_tui_get_color);
M(PTUISETCOLOR,arcan_tui_set_color);
M(PTUIRESET,arcan_tui_reset);
M(PTUISETFLAGS,arcan_tui_set_flags);
M(PTUIRESETFLAGS,arcan_tui_reset_flags);
M(PTUISETTABSTOP,arcan_tui_set_tabstop);
M(PTUIINSERTLINES,arcan_tui_insert_lines);
M(PTUINEWLINE,arcan_tui_newline);
M(PTUIDELETELINES,arcan_tui_delete_lines);
M(PTUIINSERTCHARS,arcan_tui_insert_chars);
M(PTUIDELETECHARS,arcan_tui_delete_chars);
M(PTUITABRIGHT,arcan_tui_tab_right);
M(PTUITABLEFT,arcan_tui_tab_left);
M(PTUISCROLLUP,arcan_tui_scroll_up);
M(PTUISCROLLDOWN,arcan_tui_scroll_down);
M(PTUIRESETTABSTOP,arcan_tui_reset_tabstop);
M(PTUIRESETALLTABSTOPS,arcan_tui_reset_all_tabstops);
M(PTUISCROLLHINT,arcan_tui_scrollhint);
M(PTUIMOVETO,arcan_tui_move_to);
M(PTUIMOVEUP,arcan_tui_move_up);
M(PTUIMOVEDOWN,arcan_tui_move_down);
M(PTUIMOVELEFT,arcan_tui_move_left);
M(PTUIMOVERIGHT,arcan_tui_move_right);
M(PTUIMOVELINEEND,arcan_tui_move_line_end);
M(PTUIMOVELINEHOME,arcan_tui_move_line_home);
M(PTUIDIMENSIONS,arcan_tui_dimensions);
M(PTUIDEFATTR,arcan_tui_defattr);
M(PTUIREFINC,arcan_tui_refinc);
M(PTUIREFDEC,arcan_tui_refdec);
M(PTUISETMARGINS,arcan_tui_set_margins);
M(PTUIERASESCREEN,arcan_tui_erase_screen);
M(PTUIERASEREGION,arcan_tui_erase_region);
M(PTUIERASESB,arcan_tui_erase_sb);
M(PTUIERASECURSORTOSCR,arcan_tui_erase_cursor_to_screen);
M(PTUIERASESCRTOCURSOR,arcan_tui_erase_screen_to_cursor);
M(PTUIERASECURSORTOEND,arcan_tui_erase_cursor_to_end);
M(PTUIERASEHOMETOCURSOR,arcan_tui_erase_home_to_cursor);
M(PTUIERASECURRENTLINE,arcan_tui_erase_current_line);
M(PTUIERASECHARS,arcan_tui_erase_chars);
M(PTUISTATEDESCR, arcan_tui_statedescr);
#undef M

	return true;
}
#endif
#endif
