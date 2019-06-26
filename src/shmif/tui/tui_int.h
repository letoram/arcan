#ifndef HAVE_TUI_INT

#ifdef WITH_HARFBUZZ
static bool enable_harfbuzz = false;
#include <harfbuzz/hb.h>
#include <harfbuzz/hb-ft.h>
#include <harfbuzz/hb-icu.h>
#endif

enum dirty_state {
	DIRTY_NONE = 0,
	DIRTY_UPDATED = 1,
	DIRTY_PENDING = 2,
	DIRTY_PENDING_FULL = 4
};

struct shape_state {
	unsigned ind;
	int xofs;
};

typedef void (*tui_draw_fun)(
		struct tui_context* tui,
		size_t n_rows, size_t n_cols,
		struct tui_cell* front, struct tui_cell* back,
		struct tui_cell* custom,
		int start_x, int start_y, bool synch
	);

/* globally shared 'local copy/paste' target where tsm- screen
 * data gets copy/pasted */
static volatile _Atomic int paste_destination = -1;

struct color {
	uint8_t rgb[3];
	uint8_t bg[3];
	bool bgset;
};

struct tui_context;
struct tui_context {
/* cfg->nal / state control */
	struct tsm_screen* screen;
	struct tsm_utf8_mach* ucsconv;

/* FRONT, BACK, CUSTOM ALIAS BASE. ONLY BASE IS AN ALLOCATION. used to quickly
 * detect changes when it is time to update as a means of allowing smooth
 * scrolling on single- line stepping and to cut down on possible processing
 * latency for terminals. Custom is used as a scratch buffer in order to batch
 * multiple cells with the same custom id together.
 *
 * the cell-buffers act as a cache for the draw-call cells with a front and a
 * back in order to do more advanced heuristics. These are used to detect if
 * scrolling has occured and to permit smooth scrolling, but also to get more
 * efficient draw-calls for custom-tagged cells, for more advanced font
 * rendering, to work around some of the quirks with tsms screen and get
 * multi-threaded rendering going.
 */
	struct tui_cell* base;
	struct tui_cell* front;
	struct tui_cell* back;
	struct tui_cell* custom;
	shmif_pixel* blitbuffer;
	int blitbuffer_dirty;
	uint8_t fstamp;

	unsigned flags;
	bool focus, inactive, subseg;
	int inact_timer;

#ifndef SHMIF_TUI_DISABLE_GPU
	bool is_accel;
#endif

/* font rendering / tracking - we support one main that defines cell size
 * and one secondary that can be used for alternative glyphs */
#ifndef SIMPLE_RENDERING
	TTF_Font* font[2];
#ifdef WITH_HARFBUZZ
	hb_font_t* hb_font;
#endif
#endif
	struct tui_font_ctx* font_bitmap;
	bool force_bitmap;
	bool dbl_buf;

/*
 * Two different kinds of drawing functions depending on the font-path taken.
 * One 'normal' mono-space and one 'extended' (expensive) where you also get
 * non-monospace, kerning and possibly shaping/ligatures
 */
	tui_draw_fun draw_function;
	tui_draw_fun shape_function;

	float font_sz; /* size in mm */
	int font_sz_delta; /* user requested step, pt */
	int hint;
	int render_flags;
	int font_fd[2];
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

/* if we receive a label set in mouse events, we switch to a different
 * interpreteation where drag, click, dblclick, wheelup, wheeldown work */
	bool gesture_support;

/* tracking when to reset scrollback */
	int sbofs;

/* set at config-time, enables scrollback for normal- line operations,
 * 0: disabled,
 *>0: step-size (px)
 */
	unsigned smooth_scroll;
	int scroll_backlog;
	int in_scroll;
	int scroll_px;
	int smooth_thresh;

/* color, cursor and other drawing states */
	int rows;
	int cols;
	int cell_w, cell_h, pad_w, pad_h;
	int modifiers;
	bool got_custom; /* track if we have any on-screen dynamic cells */

	struct color colors[TUI_COL_INACTIVE+1];

	int cursor_x, cursor_y; /* last cached position */
	bool cursor_off; /* current blink state */
	bool cursor_hard_off; /* user / state toggle */
	bool cursor_upd; /* invalidation, need to draw- old / new */
	int cursor_period; /* blink setting */
	enum tui_cursors cursor; /* visual style */

	uint8_t alpha;

/* track last time counter we did update on to avoid overdraw */
	tsm_age_t age;

/* upstream connection */
	struct arcan_shmif_cont acon;
	struct arcan_shmif_cont clip_in;
	struct arcan_shmif_cont clip_out;

/* retain these so that we can renegotiate on crash */
	struct arcan_event last_ident;
	struct arcan_event last_state_sz;
	struct arcan_event last_bchunk_in;
	struct arcan_event last_bchunk_out;

	struct tsm_save_buf* pending_copy_window;

/* caller- event handlers */
	struct tui_cbcfg handlers;
};

#endif
