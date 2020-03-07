/*
 Arcan Text-Oriented User Interface Library

 Copyright (c) 2014-2019, Bjorn Stahl
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
 *  This is a library intended to allow the development of rich text-oriented
 *  user interfaces that are free from the legacy- cruft of terminal emulation
 *  protocols, offering better system integration, lower latency, faster drawing
 *  and access to more features, and to take advantage of existing display
 *  servers and window managers. It is not intended to provide normal toolkit
 *  like components as such, only access to subsystems like input, drawing
 *  and storage- with a bias towards text output and keyboard input.
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
 *  and all the fields updated.
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
 * [ONTOLOGY]
 *  Cell   - Smallest drawable unit, contains a UNCODE codepoint and
 *           formatting attributes.
 *
 *  Glyph  - Character from a font which is mapped to the codepoint
 *           of a cell in order to transform it to something visible
 *           (drawing or 'blitting')
 *
 *  Screen - Buffer of cols*rows of cells.
 *
 *  Line   - Refers to a single sequence of columns.
 *
 *  Main Screen - A screen tied to the livespan of the TUI conncetion
 *
 *  [Sub] - Window - Additional screens with a dependency/relationship to
 *                   the main screen. Allocated asynchronously and can be
 *                   rejected. Use sparringly and with the assumption that
 *                   an allocation is likely to fail.
 *
 *  Drawing command that operate on a screen also works for a window.
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
 *  struct tui_context* ctx = arcan_tui_setup(conn, NULL, cb, sizeof(cb));
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
 * [ADVANCED EXAMPLES]
 *  See the builtin widgets (arcan_tui_bufferwnd, arcan_tui_listwnd)
 *
 * subwindows:
 * (in subwnd handler from cbs)
 *  struct tui_context* con = arcan_tui_setup(conn, parent, cb, sizeof(cb));
 *  arcan_tui_wndhint(con, ...);
 *
 * Normal use/drawing functions (all prefixed with arcan_tui_):
 *  erase_screen(ctx, prot)
 *  erase_region(ctx, x1, y1, x2, y2, prot)
 *  eraseattr_region(ctx, x1, y1, x2, y2, prot, attr)
 *  eraseattr_screen(ctx, prot, attr)
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
 * [DEPRECATION/REFACTORING]
 *  [ ] Remove TSM
 *  [ ] Implement line- mode as a widget and remove all scrollback/
 *      wrapping control functions from the arcan_tui_xxx namespace
 */

#include "arcan_tuidefs.h"
#include "arcan_tuisym.h"

struct tui_context;

struct tui_constraints {
	int anch_row, anch_col;
	int max_rows, max_cols;
	int min_rows, min_cols;
};

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

/* utf8 icon or short identifier */
	uint8_t vsym[5];

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
 * Other KEY where we are uncertain about origin, filled on a best-effort
 * (should be last-line of defence after label->utf8|sym->mouse->[key].
 *
 * [keysym] matches a value from the table in arcan_tuisym.h (TUIK prefix)
 * :Ex
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
 * request to send [input=false] or receive a binary chunk, [input=true,size=0] for streams
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
 * The underlying size has changed. Note that this also sends the height in
 * pixels via [neww, newh]. This should have very few practical usecases as all
 * other positioning operations etc. are on a cell- level. If the pixel
 * resolution is not known, [neww, newh] can be set to zero.
 *
 * WARNING:
 *  Be careful not to process, refresh or other similar actions from the
 *  context of this or the 'resize' callback.
 */
	void (*resized)(struct tui_context*,
		size_t neww, size_t newh, size_t cols, size_t rows, void*);

/*
 * only reset levels that should require action on behalf of the caller are
 * being forwarded, this covers levels >= 1.
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
 * this may be invoked for two reasons, one is that the contents for some
 * reason are invalid (widgets that draw cooperatively being one example).
 *
 * The other is that the color-mapping for the window has changed. Both
 * scenarios warrant that the client fully redraws the contents of the window
 * (the underlying window implementation will make sure that only cells that
 * have legitimately changed will actually be redrawn.
 */
	void (*recolor)(struct tui_context*, void*);

/*
 * A new subwindow has arrived or the request has failed (=NULL). This should
 * either be bound to a new tui context via the arcan_tui_setup() call using
 * the provided connection argument here and return true, OR don't touch it
 * and return false.
 *
 * To map the special type 'TUI_WND_HANDOVER', the tui_handover_setup call
 * should be used on the connection argument within the scope of the callback
 * after which the client has no direct control over how the window behaves.
 *
 * WARNING: mapping the connection via arcan_tui_setup and returning FALSE
 * may cause use-after-free or other memory corruption issues.
 */
	bool (*subwindow)(struct tui_context*,
		arcan_tui_conn* connection, uint32_t id, uint8_t type, void*);

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
 * rows/columns. If the pixel dimensions aren't known, [neww, newh] will
 * be set to 0.
 */
	void (*resize)(struct tui_context*,
		size_t neww, size_t newh, size_t cols, size_t rows, void*);

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
	void (*exec_state)(struct tui_context*, int state, void*);

/*
 * This is used for interactive CLI UI integration.
 *
 * [stack] is a NULL terminated array of the on-going / current set of arguments.
 *
 * Command MUST be one out of:
 * TUI_CLI_BEGIN,
 * TUI_CLI_EVAL,
 * TUI_CLI_COMMIT,
 * TUI_CLI_CANCEL
 *
 * The return value MUST be one out of:
 * TUI_CLI_ACCEPT,
 * TUI_CLI_SUGGEST,
 * TUI_CLI_INVALID
 *
 * [n_results] is set to the upper limit of allowed feedback results that can be
 * written into [feedback]. This is relevant for [TUI_CMD_EVAL, TUI_CMD_COMMIT]
 * where a set of possible completion options may be provided, as well as where
 *
 * (important for CLI_CMD_SUGGEST) where a set of possible options are returned)
 */
	int (*cli_command)(struct tui_context*,
		const char** const stack, size_t n_elem, int command,
		const char** feedback, size_t* n_results
	);

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

enum tui_subwnd_hint {
	TUIWND_SPLIT_NONE = 0,
	TUIWND_SPLIT_LEFT = 1,
	TUIWND_SPLIT_RIGHT = 2,
	TUIWND_SPLIT_TOP = 3,
	TUIWND_SPLIT_BOTTOM = 4,
	TUIWND_JOIN_LEFT = 5,
	TUIWND_JOIN_RIGHT = 6,
	TUIWND_JOIN_TOP = 7,
	TUIWND_JOIN_DOWN = 8,
	TUIWND_TAB = 9
};

struct tui_subwnd_req {
	int dir;
	size_t rows;
	size_t columns;
	enum tui_subwnd_hint hint;
};

#ifndef ARCAN_TUI_DYNAMIC

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
struct tui_context* arcan_tui_setup(
	arcan_tui_conn* con, struct tui_context* parent,
	const struct tui_cbcfg* cfg,
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
 * Extended version of request_subwnd that allows you to also specify hints
 * to the window manager.
 *
 * The argument interpretation is the same as for arcan_tui_request_subwnd,
 * along with the common 'struct + sizeof(struct)' pattern for additional
 * arguments.
 *
 * These additional arguments server as positioning and sizing hints to
 * allow the window manager to make better decisions on where to place new
 * windows and what its respectable sizes are.
 */
void arcan_tui_request_subwnd_ext(struct tui_context*,
	unsigned type, uint16_t id, struct tui_subwnd_req req, size_t req_sz);

/*
 * Replace (copy over) the active handler table with a new one.
 * if the provided cbcfg is NULL, no change to the active set will be
 * performed, to drop all callbacks, instead, use:
 *
 * arcan_tui_update_handlers(tui,
 *     &(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));
 *
 * If [old] is provided, the old set of handlers will be stored there.
 *
 * Returns false if an invalid context was provided, or if the cb_sz was
 * larger than the .so assumed size of the handler table (application linked
 * to newer/wrong headers).
 */
bool arcan_tui_update_handlers(struct tui_context*,
	const struct tui_cbcfg* new_handlers, struct tui_cbcfg* old, size_t cb_sz);

/*
 * Signal visibility, position and dimension intent for a subwindow [wnd]
 * relative to a possible parent [par].
 *
 * [wnd] must have been allocated via the _request_subwnd -> subwindow
 * call path. [par] must be NULL or refer to the same context
 * as the subwnd call initiated from.
 *
 * The dimensions inside the constraints structure are a hint, not a guarantee.
 * The rendering handler need to always be able to draw / layout to any size,
 * even if that means cropping. Handover windows are special in the sense that
 * after forwarded, they can't be controlled other than having its requested
 * anchor being 'scrolled' with the scrollhint.
 */
void arcan_tui_wndhint(struct tui_context* wnd,
	struct tui_context* par, struct tui_constraints cons);

/*
 * Announce capability for reading (input_descr != NULL) and/or writing
 * (output_descr != NULL) some kind of user- provided file data.
 *
 * [immediately=true] - attempt to query the user 'as soon as possible'
 *                      with an open/save kind of a user dialog.
 *
 * [immediately=false] - remember, as a persistent hint, that the program
 *                       can load and/or store files that match the
 *                       description at any time.
 *
 * Both sides may result in the (bchunk) callback being triggered at
 * some point in the future.
 *
 * The 'input_descr' and 'output_descr' are EITHER simply the wildcard
 * '*' character (for all files) or a ; separated list of extensions no
 * longer than 68 characters in total, including the terminating \0.
 */
void arcan_tui_announce_io(struct tui_context* c,
	bool immediately, const char* input_descr, const char* output_descr);

/*
 * Asynchronously transfer the contents of [fdin] to [fdout]. This is
 * mainly to encourage non-blocking implementation of the bchunk handler.
 * The descriptors will be closed when the transfer is completed or if
 * it fails.
 *
 * If [sigfd] is provided (> 0),
 * the result of the operation will be written on finish as:
 *   -1 (read error)
 *   -2 (write error)
 *   -3 (alloc/arg error)
 *    0 (ok)
 *
 * [flags] is reserved for future use.
 */
void arcan_tui_bgcopy(
	struct tui_context*, int fdin, int fdout, int sigfd, int flags);

/*
 * Announce/ update an estimate of how much storage is needed to be able
 * to provide a serialized state-blob that could be used to snapshot the
 * state of the program in a restorable fashion.
 *
 * 0  : not supported (default)
 * >0 : state size in bytes
 */
void arcan_tui_statesize(struct tui_context* c, size_t sz);

/*
 * Clear all cells (or cells not marked protected) to the default attribute.
 * This MAY invalidate the entire screen for redraw. Prefer to only erase
 * regions that should actually be cleared and updated.
 */
void arcan_tui_erase_screen(struct tui_context*, bool protect);
void arcan_tui_eraseattr_screen(
	struct tui_context*, bool protect, struct tui_screen_attr);

void arcan_tui_erase_region(struct tui_context*,
	size_t x1, size_t y1, size_t x2, size_t y2, bool protect);
void arcan_tui_erase_sb(struct tui_context*);

void arcan_tui_eraseattr_region(struct tui_context*, size_t x1,
	size_t y1, size_t x2, size_t y2, bool protect, struct tui_screen_attr);

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
 * Insert a new unicode codepoint (expressed as UCS4) at the current cursor
 * position. If an attribute is provided (!null) it will be used for the
 * write operation, otherwise, the current default will be used.
 */
void arcan_tui_write(struct tui_context*,
	uint32_t ucode, struct tui_screen_attr*);

/*
 * This converts [n] bytes from [u8] as UTF-8 into multiple UCS4 writes.
 * It is a more expensive form of arcan_tui_write. If the UTF-8 failed to
 * validate completely, the function will return false - but codepoints
 * leading up to the failed sequence may have already been written. If all
 * [n] bytes were consumed, the function returns true.
 */
bool arcan_tui_writeu8(struct tui_context*,
	const uint8_t* u8, size_t n, struct tui_screen_attr*);

/*
 * This calculates the length of the provided character array and forwards
 * into arcan_tui_writeu8, same encoding and return rules apply.
 */
bool arcan_tui_writestr(
	struct tui_context*, const char* str, struct tui_screen_attr*);

/*
 * This behaves similar to the normal printf class functions, except that
 * it takes an optional [attr] and returns the number of characters written.
 *
 * It expands into arcan_tui_writestr calls.
 */
size_t arcan_tui_printf(struct tui_context* ctx,
	struct tui_screen_attr* attr, const char* msg, ...);

/*
 * retrieve the current cursor position into the [x:col] and [y:row] field
 */
void arcan_tui_cursorpos(struct tui_context*, size_t* x, size_t* y);

/*
 * Convenience, get a filled out attr structure for the specific color group
 * with the other properties being the 'default'. This consolidates:
 * attr = arcan_tui_defattr(tui, NULL)
 * arcan_tui_get_color(tui, group, attr.fg)
 * arcan_tui_getbgcolor(tui, group, attr.bg)
 */
struct tui_screen_attr arcan_tui_defcattr(struct tui_context* tui, int group);

/*
 * Fill out rgb[] with the current foreground values of the specified color
 * group. see the enum tui_color_group for valid values.
 */
void arcan_tui_get_color(struct tui_context* tui, int group, uint8_t rgb[3]);

/*
 * Fill out rgb[] with the matching background value for the specified color
 * group. see the enum tui_color_group for valid values. For some groups, the
 * foreground and background color group slots are shared.
 */
void arcan_tui_get_bgcolor(struct tui_context* tui, int group, uint8_t rgb[3]);

/*
 * Update the foreground color field for the specified group.
 */
void arcan_tui_set_color(struct tui_context* tui, int group, uint8_t rgb[3]);

/*
 * Update the background color field for the specified group. For some groups,
 * the foreground and background color group slots are shared.
 */
void arcan_tui_set_bgcolor(struct tui_context* tui, int group, uint8_t rgb[3]);

/*
 * Reset state-tracking, scrollback buffers, ...
 * This does not reset/rebuild dynamic keybindings
 */
void arcan_tui_reset(struct tui_context*);

/*
 * Reset and requery the list of active inputs
 */
void arcan_tui_reset_labels(struct tui_context*);

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
 * use from within a on_subwindow handler in order to forward the subwindow
 * to an external process. Only a connection from within the handle will work.
 * Optional constraints suggest anchoring and sizing constraints.
 *
 * [Path] points to an absolute path of the binary to hand over control to.
 * [Argv] is a null-terminated array of strings that will be used as command
 *        line arguments.
 * [Env]  is a null-terminated array of strings that will be set as the new
 *        process environments.
 *
 * [flags] is a bitmap of resources handover controls. See tuisym.h for enum.
 *          TUI_DETACH_PROCESS | TUI_DETACH_STDIN | TUI_DETACH_STDOUT |
 *          TUI_DETACH_STDERR
 *
 * will reparent the handover window (double-fork like semantics)
 * otherwise the returned pid_t will need to be handled like a normal child
 * (using wait() class of functions or a SIGCHLD handler).
 *
 * Will return -1 on failure to spawn,exec,hand-over.
 */
pid_t arcan_tui_handover(struct tui_context*, arcan_tui_conn*,
	struct tui_constraints* constraints,
	const char* path, char* const argv[], char* const env[],
	int flags);

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
 * retrieve the current dimensions (same as accessible through _resize)
 */
void arcan_tui_dimensions(struct tui_context*, size_t* rows, size_t* cols);

/* helper to convert from ucs4 (used for the cells due to random access)
 * to utf8 (used for input/output), returns number of bytes used in dst. */
size_t arcan_tui_ucs4utf8(uint32_t, char dst[static 4]);

/* version of ucs4utf8 that also ensures null-termination in the output,
 * returns number of bytes used in dst NOT INCLUDING \0 */
size_t arcan_tui_ucs4utf8_s(uint32_t, char dst[static 5]);

/* helper to convert from a single utf8 codepoint, to ucs4, returns number of
 * bytes consumed or -1 on broken input */
ssize_t arcan_tui_utf8ucs4(const char src[static 4], uint32_t* dst);

/*
 * override the default attributes that apply to resets etc.  This will return
 * the previous default attribute. If the [attr] argument is null, no change
 * will be performed.
 */
struct tui_screen_attr arcan_tui_defattr(
	struct tui_context*, struct tui_screen_attr* attr);

/*
 * Simple reference counter that blocks _free from cleaning up until
 * no more references exist on the context.
 */
void arcan_tui_refinc(struct tui_context*);

/*
 * Simple reference counter that blocks _free from cleaning up until
 * no more references exist on the context.
 */
void arcan_tui_refdec(struct tui_context*);

/*
 * move the cursor either absolutely or a number of steps,
 * optionally by also scrolling the scrollback buffer
 */
void arcan_tui_move_to(struct tui_context*, size_t x, size_t y);

/*
 * Determine of the specific UC4 unicode codepoint can be drawn with the
 * current settings or not. This may be a costly operation and can generate
 * false positives (but true negatives), the primary intended use is for 'icon'
 * and box-drawing like operations with simple ascii fallbacks.
 */
bool arcan_tui_hasglyph(struct tui_context*, uint32_t);

/*
 * mark the current cursor position as a tabstop
 * [DEPRECATE -> widget]
 */
void arcan_tui_set_tabstop(struct tui_context*);

/*
 * [DEPRECATE -> widget]
 * insert [n] number of empty lines with the default attributes
 */
void arcan_tui_insert_lines(struct tui_context*, size_t);

/*
 * [DEPRECATE -> widget]
 * CR / LF
 */
void arcan_tui_newline(struct tui_context*);

/*
 * remove [n] number of lines
 */
void arcan_tui_delete_lines(struct tui_context*, size_t);

/* [DEPRECATE -> widget]
 * insert [n] number of empty characters
 * (amounts to a loop of _write calls with the default attributes)
 */
void arcan_tui_insert_chars(struct tui_context*, size_t);
void arcan_tui_delete_chars(struct tui_context*, size_t);

/* [DEPRECATE -> widget]
 * move cursor [n] tab-stops positions forward or backwards
 */
void arcan_tui_tab_right(struct tui_context*, size_t);
void arcan_tui_tab_left(struct tui_context*, size_t);

/*
 * [DEPRECATE -> widget]
 * scroll the window [n] lines up or down in the scrollback
 * buffer this is a no-op in alt-screen.
 */
void arcan_tui_scroll_up(struct tui_context*, size_t);
void arcan_tui_scroll_down(struct tui_context*, size_t);

/*
 * [DEPRECATE -> widget]
 * remove the tabstop at the current position
 */
void arcan_tui_reset_tabstop(struct tui_context*);
void arcan_tui_reset_all_tabstops(struct tui_context*);

/* [DEPRECATE -> widget] */
void arcan_tui_move_up(struct tui_context*, size_t num, bool scroll);

/* [DEPRECATE -> widget] */
void arcan_tui_move_down(struct tui_context*, size_t num, bool scroll);

/* [DEPRECATE -> widget] */
void arcan_tui_move_left(struct tui_context*, size_t);

/* [DEPRECATE -> widget] */
void arcan_tui_move_right(struct tui_context*, size_t);

/* [DEPRECATE -> widget] */
void arcan_tui_move_line_end(struct tui_context*);

/* [DEPRECATE -> widget] */
void arcan_tui_move_line_home(struct tui_context*);

/* [DEPRECATE -> widget] */
int arcan_tui_set_margins(struct tui_context*, size_t top, size_t bottom);

#else
typedef struct tui_context*(* PTUISETUP)(
	arcan_tui_conn*, struct tui_context*, const struct tui_cbcfg*, size_t, ...);
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
typedef void (* PTUIREQSUBEXT)
	(struct tui_context*, unsigned, uint16_t, struct tui_subwnd_req, size_t);
typedef void (* PTUIUPDHND)(struct tui_context*, const struct tui_cbcfg*, struct tui_cbcfg*, size_t);
typedef void (* PTUIWNDHINT)(struct tui_context*, struct tui_context*, struct tui_constraints);
typedef void (* PTUIANNOUNCEIO)(struct tui_context*, bool, const char*, const char*);
typedef void (* PTUISTATESZ)(struct tui_context*, size_t);
typedef int (* PTUIALLOCSCR)(struct tui_context*);
typedef bool (* PTUISWSCR)(struct tui_context*, unsigned);
typedef bool (* PTUIDELSCR)(struct tui_context*, unsigned);
typedef uint32_t (* PTUISCREENS)(struct tui_context*);
typedef void (* PTUIWRITE)(struct tui_context*, uint32_t, struct tui_screen_attr*);
typedef bool (* PTUIWRITEU8)(struct tui_context*, const uint8_t*, size_t, struct tui_screen_attr*);
typedef bool (* PTUIWRITESTR)(struct tui_context*, const char*, struct tui_screen_attr*);
typedef void (* PTUICURSORPOS)(struct tui_context*, size_t*, size_t*);
typedef struct tui_screen_attr (* PTUIDEFCATTR)(struct tui_context*, int);
typedef void (* PTUIGETCOLOR)(struct tui_context* tui, int, uint8_t*);
typedef void (* PTUIGETBGCOLOR)(struct tui_context* tui, int, uint8_t*);
typedef void (* PTUISETCOLOR)(struct tui_context* tui, int, uint8_t*);
typedef void (* PTUISETBGCOLOR)(struct tui_context* tui, int, uint8_t*);
typedef void (* PTUIRESET)(struct tui_context*);
typedef void (* PTUIRESETLABELS)(struct tui_context*);
typedef void (* PTUISETFLAGS)(struct tui_context*, int);
typedef void (* PTUIRESETFLAGS)(struct tui_context*, int);
typedef void (* PTUIHASGLYPH)(struct tui_context*, uint32_t);
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
typedef void (* PTUIERASEATTRSCREEN)(struct tui_context*, bool, struct tui_screen_attr);
typedef void (* PTUIREGION)(struct tui_context*, size_t, size_t, size_t, size_t, bool);
typedef void (* PTUIERASEATTRREGION)(
	struct tui_context*, size_t, size_t, size_t, size_t, bool, struct tui_screen_attr);
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
typedef size_t (* PTUIPRINTF)(struct tui_context*, struct tui_screen_attr*, const char*, ...);
typedef void (* PTUIBGCOPY)(struct tui_context*, int fdin, int fdout, int sig, int fl);
typedef size_t (* PTUIGETHANDLES)(struct tui_context**, size_t, int[], size_t);
typedef void (* PTUIHANDOVER)(struct tui_context*, arcan_tui_conn*,
	struct tui_constraints*, const char*, char* const[], char* const[], int);
typedef size_t (* PTUIUCS4UTF8)(uint32_t, char dst[static 4]);
typedef size_t (* PTUIUCS4UTF8_S)(uint32_t, char dst[static 5]);
typedef ssize_t (* PTUIUTF8UCS4)(const char dst[static 4], uint32_t);

static PTUIHANDOVER arcan_tui_handover;
static PTUISETUP arcan_tui_setup;
static PTUIDESTROY arcan_tui_destroy;
static PTUIPROCESS arcan_tui_process;
static PTUIREFRESH arcan_tui_refresh;
static PTUIGETHANDLES arcan_tui_get_handles;
static PTUIINVALIDATE arcan_tui_invalidate;
static PTUIACON arcan_tui_acon;
static PTUIOPENDISPLAY arcan_tui_open_display;
static PTUICOPY arcan_tui_copy;
static PTUIIDENT arcan_tui_ident;
static PTUIGETXY arcan_tui_getxy;
static PTUIREQSUB arcan_tui_request_subwnd;
static PTUIREQSUBEXT arcan_tui_request_subwnd_ext;
static PTUIUPDHND arcan_tui_update_handlers;
static PTUIWNDHINT arcan_tui_wndhint;
static PTUIANNOUNCEIO arcan_tui_announce_io;
static PTUISTATESZ arcan_tui_statesize;
static PTUIWRITE arcan_tui_write;
static PTUIWRITEU8 arcan_tui_writeu8;
static PTUIWRITESTR arcan_tui_writestr;
static PTUICURSORPOS arcan_tui_cursorpos;
static PTUIDEFCATTR arcan_tui_defcattr;
static PTUIGETCOLOR arcan_tui_get_color;
static PTUIGETBGCOLOR arcan_tui_get_bgcolor;
static PTUISETCOLOR arcan_tui_set_color;
static PTUISETBGCOLOR arcan_tui_set_bgcolor;
static PTUIRESET arcan_tui_reset;
static PTUIRESETLABELS arcan_tui_reset_labels;
static PTUISETFLAGS arcan_tui_set_flags;
static PTUIHASGLYPH arcan_tui_hasglyph;
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
static PTUIERASEATTRREGION arcan_tui_eraseattr_region;
static PTUIERASEATTRSCREEN arcan_tui_eraseattr_screen;
static PTUIERASESB arcan_tui_erase_sb;
static PTUIERASECURSORTOSCR arcan_tui_erase_cursor_to_screen;
static PTUIERASESCRTOCURSOR arcan_tui_erase_screen_to_cursor;
static PTUIERASECURSORTOEND arcan_tui_erase_cursor_to_end;
static PTUIERASEHOMETOCURSOR arcan_tui_erase_home_to_cursor;
static PTUIERASECURRENTLINE arcan_tui_erase_current_line;
static PTUIERASECHARS arcan_tui_erase_chars;
static PTUISTATEDESCR arcan_tui_statedescr;
static PTUIPRINTF arcan_tui_printf;
static PTUIBGCOPY arcan_tui_bgcopy;
static PTUIUCS4UTF8 arcan_tui_ucs4utf8;
static PTUIUCS4UTF8_S arcan_tui_ucs4utf8_s;
static PTUIUTF8UCS4 arcan_tui_utf8ucs4;

/* dynamic loading function */
static bool arcan_tui_dynload(void*(*lookup)(void*, const char*), void* tag)
{
#define M(TYPE, SYM) if (! (SYM = (TYPE) lookup(tag, #SYM)) ) return false
M(PTUIHANDOVER,arcan_tui_handover);
M(PTUIDESTROY,arcan_tui_destroy);
M(PTUISETUP,arcan_tui_setup);
M(PTUIDESTROY,arcan_tui_destroy);
M(PTUIPROCESS,arcan_tui_process);
M(PTUIREFRESH,arcan_tui_refresh);
M(PTUIGETHANDLES,arcan_tui_get_handles);
M(PTUIINVALIDATE,arcan_tui_invalidate);
M(PTUIACON,arcan_tui_acon);
M(PTUIOPENDISPLAY,arcan_tui_open_display);
M(PTUICOPY,arcan_tui_copy);
M(PTUIIDENT,arcan_tui_ident);
M(PTUIGETXY,arcan_tui_getxy);
M(PTUIREQSUB,arcan_tui_request_subwnd);
M(PTUIREQSUBEXT,arcan_tui_request_subwnd_ext);
M(PTUIUPDHND,arcan_tui_update_handlers);
M(PTUIWNDHINT,arcan_tui_wndhint);
M(PTUIANNOUNCEIO,arcan_tui_announce_io);
M(PTUISTATESZ,arcan_tui_statesize);
M(PTUIWRITE,arcan_tui_write);
M(PTUIWRITEU8,arcan_tui_writeu8);
M(PTUIWRITESTR,arcan_tui_writestr);
M(PTUICURSORPOS,arcan_tui_cursorpos);
M(PTUIDEFCATTR,arcan_tui_defcattr);
M(PTUIGETCOLOR,arcan_tui_get_color);
M(PTUIGETBGCOLOR,arcan_tui_get_bgcolor);
M(PTUISETCOLOR,arcan_tui_set_color);
M(PTUISETBGCOLOR,arcan_tui_set_bgcolor);
M(PTUIRESET,arcan_tui_reset);
M(PTUIRESETLABELS,arcan_tui_reset_labels);
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
M(PTUIERASEATTRREGION,arcan_tui_eraseattr_region);
M(PTUIERASEATTRSCREEN,arcan_tui_eraseattr_screen);
M(PTUIERASESB,arcan_tui_erase_sb);
M(PTUIERASECURSORTOSCR,arcan_tui_erase_cursor_to_screen);
M(PTUIERASESCRTOCURSOR,arcan_tui_erase_screen_to_cursor);
M(PTUIERASECURSORTOEND,arcan_tui_erase_cursor_to_end);
M(PTUIERASEHOMETOCURSOR,arcan_tui_erase_home_to_cursor);
M(PTUIERASECURRENTLINE,arcan_tui_erase_current_line);
M(PTUIERASECHARS,arcan_tui_erase_chars);
M(PTUISTATEDESCR, arcan_tui_statedescr);
M(PTUIPRINTF, arcan_tui_printf);
M(PTUIBGCOPY, arcan_tui_bgcopy);
M(PTUIHASGLYPH, arcan_tui_hasglyph);
M(PTUIUCS4UTF8, arcan_tui_ucs4utf8);
M(PTUIUCS4UTF8_S, arcan_tui_ucs4utf8_s);
M(PTUIUTF8UCS4, arcan_tui_utf8ucs4);

#undef M

	return true;
}
#endif
#endif
