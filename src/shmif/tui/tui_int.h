#ifndef HAVE_TUI_INT

#define REQID_COPYWINDOW 0xbaab

enum dirty_state {
	DIRTY_NONE = 0,
	DIRTY_CURSOR = 1,
	DIRTY_PARTIAL = 2,
	DIRTY_FULL = 4
};

/* globally shared 'local copy/paste' target where tsm- screen
 * data gets copy/pasted */
static volatile _Atomic int paste_destination = -1;

struct color {
	uint8_t rgb[3];
	uint8_t bg[3];
	bool bgset;
};

struct tui_font;
struct tui_raster_context;
struct tui_context;

struct tui_context {
/* cfg->nal / state control */
	struct tsm_screen* screen;
	struct tsm_utf8_mach* ucsconv;
	struct tui_raster_context* raster;

/* BASE is the only allocation here, and front/back are aliases into it.  We
 * use the double- buffering as a refactoring stage to eventually get rid of
 * the tsm_screen implementation and layer scrollback mode on top of the screen
 * implementation rather than mixing them like it is done now. The base/front
 * are compared and built into the packed tui_rasterer screen format */
	struct tui_cell* base;
	struct tui_cell* front;
	struct tui_cell* back;
	uint8_t fstamp;

/* rbuf is used to package / convert the representation in base(front|back)
 * to a line format that can be used to forward to a raster engine. The size
 * is derived when allocating base
 */
	uint8_t* rbuf;

/* fwd_rbuf is a temporary thing while we move to always just forward /
 * write into the rbuf with no rendering */
	bool rbuf_fwd;

	unsigned flags;
	bool inactive, subseg;
	int inact_timer;

/* font rendering / tracking - we support one main that defines cell size
 * and one secondary that can be used for alternative glyphs */
	struct tui_font* font[2];

	float font_sz; /* size in mm */
	int hint;
	int render_flags;
	float ppcm;
	enum dirty_state dirty;

/* mouse and/or selection management */
	int mouse_x, mouse_y;
	uint32_t mouse_btnmask;
	int lm_x, lm_y;
	int bsel_x, bsel_y;
	int last_dbl_x,last_dbl_y;
	bool in_select;
	int scrollback;
	bool mouse_forward;
	bool scroll_lock;
	bool select_townd;
	bool defocus;

/* if we receive a label set in mouse events, we switch to a different
 * interpreteation where drag, click, dblclick, wheelup, wheeldown work */
	bool gesture_support;

/* tracking when to reset scrollback */
	int sbofs;

/* color, cursor and other drawing states */
	int rows;
	int cols;
	int cell_w, cell_h, pad_w, pad_h;
	int modifiers;

	struct color colors[TUI_COL_INACTIVE+1];

	bool cursor_off; /* current blink state */
	bool cursor_hard_off; /* user / state toggle */
	bool cursor_upd; /* invalidation, need to draw- old / new */
	int cursor_period; /* blink setting */
	struct {
		bool active;
		size_t row, col;
	} last_cursor;
	enum tui_cursors cursor; /* visual style */

	uint8_t alpha;

/* track last time counter we did update on to avoid overdraw */
	uint_fast32_t age;

/* upstream connection */
	struct arcan_shmif_cont acon;
	struct arcan_shmif_cont clip_in;
	struct arcan_shmif_cont clip_out;

/* retain these so that we can renegotiate on crash */
	struct arcan_event last_ident;
	struct arcan_event last_state_sz;
	struct arcan_event last_bchunk_in;
	struct arcan_event last_bchunk_out;

/* cached after calls to tui_wndhint */
	struct tui_constraints last_constraints;

	struct tsm_save_buf* pending_copy_window;

/* NEWSEGEMENT -> on_subwindow -> handover call chain */
	bool got_pending;
	struct arcan_event pending_wnd;

/* caller- event handlers */
	struct tui_cbcfg handlers;
};

/* ========================================================================== */
/*                       SCREEN (tui_screen.c) related code                   */
/* ========================================================================== */

/*
 * redraw and synchronise the output with our external source.
 */
int tui_screen_refresh(struct tui_context* tui);

/*
 * cell dimensions or cell quantities has changed, rebuild the display
 */
void tui_screen_resized(struct tui_context* tui);

/*
 * this is normally called from within refresh, but can be used to obtain
 * a tpack representation of the screen front-buffer or back buffer.
 *
 * if [full] is set, the type generated will always be an I frame
 *                   regardless of the dirty state of the window
 *
 * if [commit] is set, the contents of the back buffer will be synched
 *                     to the front-buffer
 *
 * if [back] is set, the contents of the back buffer will be used
 *                   rather than the front buffer
 */
struct tpack_gen_opts {
	bool full;
	bool synch;
	bool back;
};

int tui_screen_tpack(struct tui_context* tui,
	struct tpack_gen_opts opts, uint8_t** rbuf, size_t* rbuf_sz);

/* ========================================================================== */
/*                  DISPATCH  (tui_dispatch.c) related code                   */
/* ========================================================================== */

/*
 * Poll the incoming event queue on the tui segment, process TARGET events
 * and forward IO events to
 */
void tui_event_poll(struct tui_context* tui);

/*
 * necessary on setup and when having been 'reset'
 */
void tui_queue_requests(struct tui_context* tui, bool clipboard, bool ident);

/* ========================================================================== */
/*                  CLIPBOARD (tui_clipboard.c) related code                  */
/* ========================================================================== */

/*
 * Process events from the clipboard (if any), called from the main API impl.
 * as part of the process stage if a clipboard / pasteboard is currently
 * allocated.
 */
void tui_clipboard_check(struct tui_context* tui);

/*
 * Set the selected text with len as the current clipboard output contents
 */
bool tui_clipboard_push(struct tui_context* tui, const char* sel, size_t len);


/* ========================================================================== */
/*                    INPUT (tui_input.c) related code                        */
/* ========================================================================== */

/*
 * Send LABELHINTs that mach the set of implemented inputs and bindings.
 */
void tui_expose_labels(struct tui_context* tui);

/*
 * Should be routed into this function from the dispatch
 */
void tui_input_event(
	struct tui_context* tui, arcan_ioevent* ioev, const char* label);

/* ========================================================================== */
/*                    FONT (tui_fontmgr.c) related code                       */
/* ========================================================================== */

/*
 * consume a FONTHINT event and apply the changes to the tui context
 */
void tui_fontmgmt_fonthint(struct tui_context* tui, struct arcan_tgtevent* ev);

/*
 * setup / copy the font state from one context to another
 */
void tui_fontmgmt_inherit(struct tui_context* tui, struct tui_context* parent);

/*
 * setup the font stat from the 'start' state provided from the connection
 */
void tui_fontmgmt_setup(
	struct tui_context* tui, struct arcan_shmif_initial* init);

/*
 * check if any of the attached fonts has a glyph for the specific codepoint
 */
bool tui_fontmgmt_hasglyph(struct tui_context* tui, uint32_t cp);

/*
 * Call whenever the properties of the underlying fonts etc. has changed,
 * may cause loading / unloading / build etc.
 */
void tui_fontmgmt_invalidate(struct tui_context* tui);

#endif
