#ifndef HAVE_TUI_INT

#define REQID_COPYWINDOW 0xbaab

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

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
	struct tui_screen_attr defattr;
	uint8_t fstamp;

	float progress[5];

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
	uint8_t mouse_state[ASHMIF_MSTATE_SZ];
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

	FILE* tpack_recdst;

/* if we receive a label set in mouse events, we switch to a different
 * interpreteation where drag, click, dblclick, wheelup, wheeldown work */
	bool gesture_support;

/* color, cursor and other drawing states */
	int rows;
	int cols;

/* track scrollback state so that we can send content-hints accordingly, to be
 * deprecated with the tsm cleanup as scrollback shouldn't exist in tui */
	long sbofs;
	struct {
		long ofs;
		unsigned len;
		struct arcan_event hint;
		bool dirty;
	} sbstat;

/* if the server-side has hinted with valid cell dimensions, skip probing */
	bool cell_auth;
	int cell_w, cell_h, pad_w, pad_h;
	int cx, cy;
	int modifiers;

	struct color colors[TUI_COL_LIMIT];

	bool cursor_off; /* current blink state */
	bool cursor_hard_off; /* user / state toggle */
	int cursor_period; /* blink setting */

/* cached to determine if the cursor has changed or not before wasting a pack */
	struct {
		bool active;
		size_t row, col;
		int style;
		uint8_t rgb[3];
		bool color_override;
	} last_cursor;

	enum tui_cursors cursor; /* visual style */
	bool cursor_color_override;
	uint8_t cursor_color[3];

	uint8_t alpha;

/* track last time counter we did update on to avoid overdraw */
	uint_fast32_t age;

/* for embedding purposes, parent-children relationships need to be tracked
 * in order for proxy-window event routing to work. */
	struct tui_context* parent;
	struct tui_context* children[256];

/* upstream connection */
	struct arcan_shmif_cont acon;
	struct arcan_shmif_cont clip_in;
	struct arcan_shmif_cont clip_out;

/* track before calling on_subwindow when it is a handover type */
	uint32_t pending_handover;
	uint32_t viewport_proxy;

/* retain these so that we can renegotiate on crash */
	struct arcan_event last_ident;
	struct arcan_event last_state_sz;

/* cached after calls to tui_wndhint */
	struct tui_constraints last_constraints;

	struct tsm_save_buf* pending_copy_window;

/* NEWSEGEMENT -> on_subwindow -> handover call chain */
	bool got_pending;
	struct arcan_event pending_wnd;

/* event hooks for slowly decoupling deprecated code */
	struct {
		void(*cursor_update)(struct tui_context* c);
		void(*input)(struct tui_context*, arcan_ioevent* iev, const char*);
		void(*reset)(struct tui_context*);
		void(*destroy)(struct tui_context*);
		void(*resize)(struct tui_context*);
		void(*refresh)(struct tui_context*);
		void(*cursor_lookup)(struct tui_context*, size_t* x, size_t* y);
	} hooks;

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

size_t tui_screen_tpack_sz(struct tui_context*);

size_t tui_screen_tpack(struct tui_context* tui,
	struct tpack_gen_opts opts, uint8_t* rbuf, size_t rbuf_sz);

/* unpack a previously provided tpack buffer unto a tui context,
 *
 * optionally as a clipped subregion. If [w | h] is set to 0 and the size
 * of the tpack content does not match that of the [tui] context, it will
 * be resized to match.
 */
int tui_tpack_unpack(struct tui_context* tui,
	uint8_t* buf, size_t buf_sz, size_t x, size_t y, size_t w, size_t h);

/* ========================================================================== */
/*                  DISPATCH  (tui_dispatch.c) related code                   */
/* ========================================================================== */

/*
 * Poll the incoming event queue on the tui segment, process TARGET events
 * and forward IO events to
 */
void tui_event_poll(struct tui_context* tui);

/*
 * Process an event as if it had originated from the display server connection
 */
void tui_event_inject(struct tui_context* tui, arcan_event* ev);
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
