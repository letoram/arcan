/*
 * Copyright 2014-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: text-user interface support library derived from the work on
 * the afsrv_terminal frameserver. Two separate builds need to be tested here,
 * one from defining SIMPLE_RENDERING, and the other with SHMIF_TUI_DISABLE_GPU
 * off along with the option of doing gpu- buffer transfers on.
 */

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <locale.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <poll.h>
#include <math.h>
#include <pthread.h>
#include <limits.h>
#include <assert.h>
_Static_assert(PIPE_BUF >= 4, "pipe atomic write should be >= 4");

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>

#ifndef SHMIF_TUI_DISABLE_GPU
#define WANT_ARCAN_SHMIF_HELPER
#endif

#include "../arcan_shmif.h"
#include "../arcan_tui.h"

#define REQID_COPYWINDOW 0xbaab

/*
 * Dislike this sort of feature enable/disable, but the dependency and extra
 * considerations from shaped text versus normal bitblt is worth it.
 */
#ifndef SIMPLE_RENDERING
#include "arcan_ttf.h"
#endif

#include "tui_draw.h"
#include "libtsm.h"
#include "libtsm_int.h"

#ifdef WITH_HARFBUZZ
static bool enable_harfbuzz = false;
#include <harfbuzz/hb.h>
#include <harfbuzz/hb-ft.h>
#include <harfbuzz/hb-icu.h>

static int render_glyph(PIXEL* dst,
	size_t width, size_t height, int stride,
	TTF_Font **font, size_t n,
	uint32_t ch,
	unsigned* xstart, uint8_t fg[4], uint8_t bg[4],
	bool usebg, bool use_kerning, int style,
	int* advance, unsigned* prev_index
)
{
	if (!ch)
		return 0;

	if (enable_harfbuzz)
		return TTF_RenderUNICODEindex(dst, width, height, stride,
			font, n, ch, xstart,fg, bg, usebg, use_kerning, style,
			advance, prev_index
		);
	else
		return TTF_RenderUNICODEglyph(dst, width, height, stride,
			font, n, ch, xstart,fg, bg, usebg, use_kerning, style,
			advance, prev_index
		);
}
#else
static int render_glyph(PIXEL* dst,
	size_t width, size_t height, int stride,
	TTF_Font **font, size_t n,
	uint32_t ch,
	unsigned* xstart, uint8_t fg[4], uint8_t bg[4],
	bool usebg, bool use_kerning, int style,
	int* advance, unsigned* prev_index
)
{
	return TTF_RenderUNICODEglyph(dst, width, height, stride,
		font, n, ch, xstart,fg, bg, usebg, use_kerning, style,
		advance, prev_index);
}
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
};

struct tui_context;
struct tui_context {
/* cfg->nal / state control */
	struct tsm_screen* screen;
	struct tsm_utf8_mach* ucsconv;

/*
 * allow a number of virtual screens for this context, these are allocated
 * when one is explicitly called, and swaps out the drawing into the output
 * context.
 * TODO: allow multiple- screens to be mapped in order onto the same buffer.
 */
	struct tsm_screen* screens[32];
	uint32_t screen_alloc;

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
	struct arcan_event last_ident;

	struct tsm_save_buf* pending_copy_window;

/* caller- event handlers */
	struct tui_cbcfg handlers;
};

char* arcan_tui_statedescr(struct tui_context* tui)
{
	char* ret;
	if (!tui)
		return NULL;

	int tfl = tui->screen->flags;

	if (-1 == asprintf(&ret,
		"frame: %d alpha: %d dblbuf: %d "
		"scroll-lock: %d "
		"rows: %d cols: %d cell_w: %d cell_h: %d pad_w: %d pad_h: %d "
		"ppcm: %f font_sz: %f font_sz_delta: %d hint: %d bmp: %d "
		"scrollback: %d sbofs: %d inscroll: %d backlog: %d "
		"mods: %d iact: %d "
		"cursor_x: %d cursor_y: %d off: %d hard_off: %d period: %d "
		"(screen)age: %d margin_top: %u margin_bottom: %u "
		"cursor_x: %u cursor_y: %u flags: %s%s%s%s%s%s",
		(int) tui->fstamp, (int) tui->alpha, (int) tui->dbl_buf,
		(int) tui->scroll_lock,
		tui->rows, tui->cols, tui->cell_w, tui->cell_h, tui->pad_w, tui->pad_h,
		tui->ppcm, tui->font_sz, tui->font_sz_delta, tui->hint, tui->force_bitmap,
		tui->scrollback, tui->sbofs, tui->in_scroll, tui->scroll_backlog,
		tui->modifiers, tui->inact_timer,
		tui->cursor_x, tui->cursor_y,
		tui->cursor_off, tui->cursor_hard_off, tui->cursor_period,
		(int) tui->screen->age, tui->screen->margin_top, tui->screen->margin_bottom,
		tui->screen->cursor_x, tui->screen->cursor_y,
		(tfl & TSM_SCREEN_INSERT_MODE) ? "insert " : "",
		(tfl & TSM_SCREEN_AUTO_WRAP) ? "autowrap " : "",
		(tfl & TSM_SCREEN_REL_ORIGIN) ? "relorig " : "",
		(tfl & TSM_SCREEN_INVERSE) ? "inverse " : "",
		(tfl & TSM_SCREEN_FIXED_POS) ? "fixed " : "",
		(tfl & TSM_SCREEN_ALTERNATE) ? "alternate " : ""
		)
	)
		return NULL;

	return ret;
}

/* additional state synch that needs negotiation and may need to be
 * re-built in the event of a RESET request */
static void queue_requests(struct tui_context* tui, bool clipboard, bool ident);

/*
 * main character drawing / blitting function,
 * only called when updating cursor or as part of update_screen
 */
static void draw_cbt(struct tui_context* tui,
	uint32_t ch, int x, int y, const struct tui_screen_attr* attr, bool empty,
	struct shape_state* state, bool noclear);

static void draw_monospace(struct tui_context* tui,
	size_t n_rows, size_t n_cols,
	struct tui_cell* front, struct tui_cell* back, struct tui_cell* custom,
	int start_x, int start_y, bool synch);

static void draw_shaped(struct tui_context* tui,
	size_t n_rows, size_t n_cols,
	struct tui_cell* front, struct tui_cell* back, struct tui_cell* custom,
	int start_x, int start_y, bool synch);

static void tsm_log(void* data, const char* file, int line,
	const char* func, const char* subs, unsigned int sev,
	const char* fmt, va_list arg)
{
	fprintf(stderr, "[%d] %s:%d - %s, %s()\n", sev, file, line, subs, func);
	vfprintf(stderr, fmt, arg);
}

const char* curslbl[] = {
	"block",
	"halfblock",
	"frame",
	"vline",
	"uline",
	NULL
};

static void resolve_cursor(
	struct tui_context* tui, int* x, int* y, int* w, int* h)
{
	if (tui->draw_function != draw_monospace){
		struct tui_cell cell =
			tui->front[tui->cursor_y * tui->cols + tui->cursor_x];
		*x = cell.real_x;
		*y = tui->cursor_y * tui->cell_h;
		*w = cell.cell_w;
		*h = tui->cell_h;
	}
	else {
		*x = tui->cursor_x * tui->cell_w;
		*y = tui->cursor_y * tui->cell_h;
		*w = tui->cell_w;
		*h = tui->cell_h;
	}
}
static shmif_pixel get_bg_col(struct tui_context* tui)
{
	return SHMIF_RGBA(
		tui->colors[TUI_COL_BG].rgb[0],
		tui->colors[TUI_COL_BG].rgb[1],
		tui->colors[TUI_COL_BG].rgb[2],
		tui->alpha
	);
}

static bool cursor_at(struct tui_context* tui, int x, int y, shmif_pixel ccol)
{
	shmif_pixel* dst = tui->acon.vidp;

	if (tui->cursor_off || tui->cursor_hard_off)
		return false;

	switch (tui->cursor){
/* other cursors gets their dirty state due to draw_cbt */
	case CURSOR_BLOCK:{
		int x2 = x + tui->cell_w;
		int y2 = y + tui->cell_h;
		if (x < tui->acon.dirty.x1)
			tui->acon.dirty.x1 = x;
		if (x2 > tui->acon.dirty.x2)
			tui->acon.dirty.x2 = x2;
		if (y < tui->acon.dirty.y1)
			tui->acon.dirty.y1 = y;
		if (y2 > tui->acon.dirty.y2)
			tui->acon.dirty.y2 = y2;
		tui->dirty |= DIRTY_UPDATED;
		draw_box(&tui->acon, x, y, tui->cell_w, tui->cell_h, ccol);
		return true;
	}
	break;
	case CURSOR_HALFBLOCK:
		draw_box(&tui->acon, x, y, tui->cell_w >> 1, tui->cell_h, ccol);
		return true;
	break;
	case CURSOR_FRAME:
		for (int col = x; col < x + tui->cell_w; col++){
			dst[y * tui->acon.pitch + col] = ccol;
			dst[(y + tui->cell_h-1 ) * tui->acon.pitch + col] = ccol;
		}

		for (int row = y+1; row < y + tui->cell_h-1; row++){
			dst[row * tui->acon.pitch + x] = ccol;
			dst[row * tui->acon.pitch + x + tui->cell_w - 1] = ccol;
		}
	break;
	case CURSOR_VLINE:
		draw_box(&tui->acon, x + 1, y, 1, tui->cell_h, ccol);
	break;
	case CURSOR_ULINE:
		draw_box(&tui->acon, x, y+tui->cell_h-1, tui->cell_w, 1, ccol);
	break;
	case CURSOR_END:
	default:
	break;
	}
	return false;
}

/*
 * -1 fail, 0 not ready, 1 ready
 */
static int wait_vready(struct tui_context* tui, bool block)
{
	int rc;
	do
	{
/* special case, on the DMS, fake-signal so the fallback migrate path gets
 * activated - normal clients should not bother with this, but we're not
 * really 'normal' */
		if (!tui->acon.addr->dms){
			arcan_shmif_signal(&tui->acon, 0);
			return -1;
		}

		if (!atomic_load(&tui->acon.addr->vready))
			return 1;

	} while (block);

	return 0;
}

static void apply_attrs(struct tui_context* tui,
	int base_x, int base_y, uint8_t fg[4], const struct tui_screen_attr* attr)
{
/*
 * We cheat with underline / strikethrough and just go relative to cell
 */
	if (attr->underline){
		int n_lines = (int)(tui->cell_h * 0.05) | 1;
		draw_box(&tui->acon, base_x, base_y + tui->cell_h - n_lines,
			tui->cell_w, n_lines, SHMIF_RGBA(fg[0], fg[1], fg[2], fg[3]));
	}

	if (attr->strikethrough){
		int n_lines = (int)(tui->cell_h * 0.05) | 1;
		draw_box(&tui->acon, base_x, (tui->cell_h >> 1) - (n_lines >> 1),
			tui->cell_w, n_lines, SHMIF_RGBA(fg[0], fg[1], fg[2], fg[3]));
	}
}

#ifndef SIMPLE_RENDERING
/* DOES NOT SUPPORT OR CONSIDER CLIPPING */
static void draw_ch(struct tui_context* tui,
	uint32_t ch, int base_x, int base_y, uint8_t fg[4], uint8_t bg[4],
	const struct tui_screen_attr* attr, struct shape_state* state,
	bool noclear)
{
	int prem = TTF_STYLE_NORMAL;
	prem |= TTF_STYLE_ITALIC * attr->italic;
	prem |= TTF_STYLE_BOLD * attr->bold;

/* might be worth it to have yet another caching layer here */

/* reset the cell regarless of state as the current drawUNICODE,...
 * doesn't actually clear it and the conditional/ write costs more */
	if (!noclear)
	draw_box(&tui->acon, base_x, base_y,
		tui->cell_w, tui->cell_h, SHMIF_RGBA(bg[0], bg[1], bg[2], bg[3]));

/* This one is incredibly costly as a deviation in style regarding
 * bold/italic can invalidate the glyph-cache. Ideally, this should
 * be sorted in tsm_screen */
	TTF_SetFontStyle(tui->font[0], prem);
	size_t allow_w = tui->cell_w + tui->cell_w *
		(base_x + tui->cell_w * 2 <= tui->acon.w - tui->pad_h);

	if (!state){
		unsigned ind = 0;
		unsigned xs = 0;
		int adv = 0;

		render_glyph(
			&tui->acon.vidp[base_y * tui->acon.pitch + base_x],
			allow_w, tui->cell_h, tui->acon.pitch,
			tui->font, tui->font[1] ? 2 : 1,
			ch, &xs, fg, bg, true, false, prem, &adv, &ind
		);
/* strikethrough / underline should really just be handled in the
 * TTF_SetFontStyle and this function can be skipped */
		apply_attrs(tui, base_x, base_y, fg, attr);
	}
	else {
		unsigned xs = 0;
		int adv = 0;
		render_glyph(
			&tui->acon.vidp[base_y * tui->acon.pitch + base_x],
			allow_w, tui->cell_h, tui->acon.pitch,
			tui->font, tui->font[1] ? 2 : 1,
			ch, &xs, fg, bg, true, false, prem, &adv, &state->ind
		);
		state->xofs += adv;
	}
}
#endif

static inline void flag_cursor(struct tui_context* c)
{
	c->cursor_upd = true;
	c->dirty = DIRTY_PENDING;
	c->inact_timer = -4;
}

static void send_cell_sz(struct tui_context* tui)
{
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE),
	};

	sprintf((char*)ev.ext.message.data,
		"cell_w:%d:cell_h:%d", tui->cell_w, tui->cell_h);
	arcan_shmif_enqueue(&tui->acon, &ev);
}

static int tsm_draw_callback(struct tsm_screen* screen, uint32_t id,
	const uint32_t* ch, size_t len, unsigned width, unsigned x, unsigned y,
	const struct tui_screen_attr* attr, tsm_age_t age, void* data)
{
	struct tui_context* tui = data;

	if (!(age && tui->age && age <= tui->age) && x < tui->cols && y < tui->rows){
		size_t pos = y * tui->cols + x;
		tui->front[pos].draw_ch = tui->front[pos].ch = *ch;
		tui->front[pos].attr = *attr;
		tui->front[pos].fstamp = tui->fstamp;
		tui->dirty |= DIRTY_PENDING;
	}

	return 0;
}

static void draw_cbt(struct tui_context* tui,
	uint32_t ch,int x1, int y1,
	const struct tui_screen_attr* attr,	bool empty,
	struct shape_state* state, bool noclear)
{
	uint8_t fgc[4] = {attr->fr, attr->fg, attr->fb, 255};
	uint8_t bgc[4] = {attr->br, attr->bg, attr->bb, tui->alpha};
	uint8_t* dfg = fgc, (* dbg) = bgc;

/*
 * For inverse, we automatically set the foreground color based on the
 * background color perception. If it's light, make the text black, if
 * it's dark, make the text white.
 */
	if (attr->inverse){
		dbg = fgc;
		dfg = bgc;
		dbg[3] = tui->alpha;
		dfg[3] = 0xff;
		float intens =
			(0.299f * dbg[0] + 0.587f * dbg[1] + 0.114f * dbg[2]) / 255.0f;
		if (intens < 0.5f){
			dfg[0] = 0xff; dfg[1] = 0xff; dfg[2] = 0xff;
		}
		else {
			dfg[0] = 0x00; dfg[1] = 0x00; dfg[2] = 0x00;
		}
	};

	int x2 = x1 + tui->cell_w;
	int y2 = y1 + tui->cell_h;

/* update dirty rectangle for synchronization */
	if (x1 < (int)tui->acon.dirty.x1)
		tui->acon.dirty.x1 = x1 >= 0 ? x1 : 0;
	if (x2 > tui->acon.dirty.x2)
		tui->acon.dirty.x2 = x2;
	if (y1 < (int)tui->acon.dirty.y1)
		tui->acon.dirty.y1 = y1 >= 0 ? y1 : 0;
	if (y2 > tui->acon.dirty.y2)
		tui->acon.dirty.y2 = y2;

	tui->dirty |= DIRTY_UPDATED;

/* Don't go through the font- path if the cell is just whitespace */
	if (empty){
		draw_box(&tui->acon, x1, y1, tui->cell_w, tui->cell_h,
			SHMIF_RGBA(dbg[0], dbg[1], dbg[2], tui->alpha));
			apply_attrs(tui, x1, y1, bgc, attr
		);
		return;
	}

	if (
#ifndef SIMPLE_RENDERING
			tui->force_bitmap || !tui->font[0]
#else
			1
#endif
		){
		draw_ch_u32(tui->font_bitmap,
			&tui->acon, ch, x1, y1,
			SHMIF_RGBA(dfg[0], dfg[1], dfg[2], dfg[3]),
			SHMIF_RGBA(dbg[0], dbg[1], dbg[2], dbg[3]),
			tui->cols * tui->cell_w,
			tui->rows * tui->cell_h
		);
	}
#ifndef SIMPLE_RENDERING
	else{
/*
 * Special case, if base_y < 0 - we blit into a temporary buffer and do our
 * line copies from there. The reason is that TTF_RenderUNICODEglyph is
 * complicated enough, and the blit-partial case is not needed in Arcan. This
 * gets worse with shaping rules and since it's in the scroll-in/scroll-out
 * areas this gets triggered, just treat those as an edge case.
 *
 * This works by having two scratch- rows and a separate clipped blit- stage.
 * Since it's only used for scrolling, the dirty- region part is easy. We
 * work on full in- out- rows instead of 'per char' to use the same code
 * for shaping.
 */
		if (y1 < 0){
			if (tui->blitbuffer){
				shmif_pixel* vidp = tui->acon.vidp;
				tui->acon.vidp = tui->blitbuffer;
				draw_ch(tui, ch, x1, 0, dfg, dbg, attr, state, false);
				tui->acon.vidp = vidp;
				tui->blitbuffer_dirty |= 1;
			}
		}
		else if (y1 + tui->cell_h > tui->acon.h - tui->pad_h){
			if (tui->blitbuffer){
				shmif_pixel* vidp = tui->acon.vidp;
				tui->acon.vidp = &tui->blitbuffer[tui->acon.pitch * tui->cell_h];
				draw_ch(tui, ch, x1, 0, dfg, dbg, attr, state, false);
				tui->acon.vidp = vidp;
				tui->blitbuffer_dirty |= 2;
			}
		}
		else
			draw_ch(tui, ch, x1, y1, dfg, dbg, attr, state, false);
	}
#endif
}

/*
 * This drawing function takes shaping and kerning into account and thus works
 * on a line basis. It makes things more complicated as we are no longer tied to
 * a strict cell-grid structure and need to track line/offset in order for
 * cursor- drawing etc. to work.
 */
#ifndef SIMPLE_RENDERING
static void draw_shaped(struct tui_context* tui,
	size_t n_rows, size_t n_cols,
	struct tui_cell* front, struct tui_cell* back, struct tui_cell* custom,
	int start_x, int start_y, bool synch)
{
	int cw = tui->cell_w;
	int ch = tui->cell_h;

	for (size_t row = 0; row < n_rows; row++){

/* scan a full row for changes, since we need to redo the whole row
 * on an eventual change as the shaping might have changed */
		if (synch && !(tui->dirty & DIRTY_PENDING_FULL)){
			bool row_changed = false;
			struct tui_cell* front_row = &front[tui->cols * row];
			struct tui_cell* back_row = &back[tui->cols * row];
			for (size_t col = 0; col < n_cols; col++){
				if (front_row[col].fstamp != back_row[col].fstamp ||row==tui->cursor_y){
					row_changed = true;
					break;
				}
			}
			if (!row_changed)
				continue;
		}

		struct shape_state state = {.ind = 0};
		struct tui_cell* front_row = &front[tui->cols * row];
		struct tui_cell* back_row = &back[tui->cols * row];
		int xofs = 0;

/* clear the entire row */
		int cury = row * ch + start_y;
		shmif_pixel bgcol = get_bg_col(tui);
		draw_box(&tui->acon, 0, cury, tui->acon.w, cury+tui->cell_h, bgcol);
		tui->acon.dirty.x2 = tui->acon.w;

		if (tui->handlers.substitute)
			tui->handlers.substitute(tui,
				&front[row * tui->cols], n_cols, row, tui->handlers.tag);

		for (size_t col = 0; col < n_cols; col++){
/* custom-draw cells always reset the state tracking */
			if (front_row[col].attr.custom_id > 127){
				tui->got_custom = true;
				state = (struct shape_state){.xofs = col * cw};
				continue;
			}

/* Draw character, apply kerning or, if enabled, full shaping. We assume
 * (which is not correct) that the shaped output will not grow to exceed the
 * cell size limit. This should be fixed alongside proper wcswidth style
 * screen management */
			int last_ofs = state.xofs;
			draw_cbt(tui, front_row[col].draw_ch,
				start_x + state.xofs, cury,
				&front_row[col].attr, false, &state, true
			);
			front_row[col].real_x = start_x + last_ofs;
			front_row[col].cell_w = state.xofs - last_ofs;

/* Shape-break has us resetting to the intended / non-kerned position,
 * for the least intrusive effect, this pretty much needs to be set
 * after every word - with special detail to 'formatted columns' */
			if (front_row[col].attr.shape_break){
				state = (struct shape_state){.xofs = col * cw};
			}

/* update target buffer */
			if (synch && front != back){
				back_row[col] = front_row[col];
			}
		}
	}
}
#endif

/*
 * slightly more complicated to support smooth scrolling, draw n_rows and
 * n_cols from front/back (assume no padding) synch means that front and back
 * should be set to the same value after drawing and be used for 'dirty updates'
 */
static void draw_monospace(struct tui_context* tui,
	size_t n_rows, size_t n_cols,
	struct tui_cell* front, struct tui_cell* back, struct tui_cell* custom,
	int start_x, int start_y, bool synch)
{
	struct tui_cell* fpos = front;
	struct tui_cell* bpos = back;
	int cw = tui->cell_w;
	int ch = tui->cell_h;
/*
 * KEEP AS A NOTE: shouldn't be needed after refactor
	if (row == tui->cursor_x && col == tui->cursor_y){
		tui->cursor_upd = true;
	}
 */
	for (size_t row = 0; row < n_rows; row++){
		if (tui->handlers.substitute &&
			tui->handlers.substitute(tui,
				&front[row * tui->cols], n_cols, row, tui->handlers.tag)){
/* invalidate the entire row */
			for (size_t col = 0; col < n_cols; col++)
				front[row * tui->cols + col].fstamp = tui->fstamp;
		}

		for (size_t col = 0; col < n_cols; col++){

/* only update if the source position has changed, treat custom_id separate */
			if (synch && !(tui->dirty & DIRTY_PENDING_FULL)
				&& fpos->fstamp == bpos->fstamp){
				fpos++, bpos++, custom++;
				continue;
			}

/* this ensures the custom- ID buffer is updated, when we step through it
 * in the custom step, the cells will be marked 0ed after use. since the
 * custom cells may be updated whenever, the got_custom state is updated
 * so DIRTY_PENDING doesn't get cleared at synch. */
			if (fpos->attr.custom_id > 127){
				*custom = *fpos;
				fpos++, bpos++, custom++;
				tui->got_custom = true;
				continue;
			}

/* update the cell */
			draw_cbt(tui, fpos->draw_ch,
				col * cw + start_x, row * ch + start_y, &fpos->attr, false, NULL,false);

			if (synch)
				*custom = *bpos = *fpos;

			fpos++, bpos++, custom++;
		}
	}
/* FIXME: custom draw-call goes here */
}

static void clear_framebuffer(struct tui_context* tui)
{
	size_t npx = tui->acon.w * tui->acon.h;
	shmif_pixel* dst = tui->acon.vidp;
	shmif_pixel bgc = SHMIF_RGBA(
		tui->colors[TUI_COL_BG].rgb[0],
		tui->colors[TUI_COL_BG].rgb[1],
		tui->colors[TUI_COL_BG].rgb[2],
		tui->alpha
	);

	while (npx--)
		*dst++ = bgc;
}

/*
 * blit the scroll-in and scroll-out buffers into the tui->acon vidp
 */
static void apply_blitbuffer(struct tui_context* tui, int sign)
{
	shmif_pixel* dst, (* src);

/* top row */
	if (tui->blitbuffer_dirty & 1){
		int row = sign * -tui->scroll_px;
		dst = tui->acon.vidp;
		src = &tui->blitbuffer[tui->acon.pitch * row];

		for (; row < tui->cell_h; row++,
			dst += tui->acon.pitch, src += tui->acon.pitch)
			memcpy(dst, src, tui->acon.stride);
	}

/* bottom row */
	if (tui->blitbuffer_dirty & 2){
		int y = tui->cell_h * tui->rows + sign * tui->scroll_px;
		dst = &tui->acon.vidp[y * tui->acon.pitch];
		src = &tui->blitbuffer[tui->acon.pitch * tui->cell_h];

		for (; y < tui->acon.h - tui->pad_h;
			y++, src += tui->acon.pitch, dst += tui->acon.pitch)
			memcpy(dst, src, tui->acon.stride);
	}

/* reset the smooth-scroll blitbuffer */
	shmif_pixel col = get_bg_col(tui);

	shmif_pixel* cvp = tui->acon.vidp;
	tui->acon.vidp = tui->blitbuffer;
	draw_box(&tui->acon, 0, 0, tui->acon.w, tui->cell_h*2, col);
	tui->acon.vidp = cvp;
	tui->blitbuffer_dirty = 0;
}

/*
 * Used when smooth-scrolling, we know that the back buffer now contains our
 * last "stable" view, then we scroll in from the front buffer as often we can.
 * In order to not turn irresponsive, we can only do one- synch at a time here
 * and just submit an EAGAIN to the caller.
 * Caller should guarantee that scroll_backlog <= rows on screen
 */
static void apply_scroll(struct tui_context* tui)
{
/*
 * scroll down, +n
 * still update the front buffer, this may force characters to 'swap in'
 */

/*
 * this work-around / restriction works for problems when fed with the terminal
 * like constraints, but may fail elsewhere.
 */
	if (tui->cursor_y != tui->rows-1){
		tui->scroll_backlog = 0;
		return;
	}

	tui->age = tsm_screen_draw(tui->screen, tsm_draw_callback, tui);
	int step_sz = abs(tui->scroll_backlog) - tui->in_scroll > tui->smooth_thresh ?
		tui->cell_h : tui->smooth_scroll;
	if (step_sz == 0)
		step_sz = 1;
	else if (step_sz > tui->cell_h)
		step_sz = tui->cell_h;

	if (tui->scroll_backlog > 0){
		if (tui->scroll_backlog > tui->rows)
			tui->scroll_backlog = tui->rows;

		if (!tui->in_scroll){
			tui->scroll_px = -step_sz;

/* copy 'last' row on new front buffer into our hidden scrolling region,
 * this needs to be done repeatedly as tsm_screen_draw may have changed */
			memcpy(&tui->back[tui->rows * tui->cols],
				&tui->front[(tui->rows - tui->scroll_backlog) * tui->cols],
				sizeof(struct tui_cell) * tui->cols
			);
		}

/* if we (in order to not go too slow on half / full page) need to jump
 * larger steps, just do many small steps but without drawing / synching */
		if (-1 == wait_vready(tui, true))
			return;

/* while this is running, the rest of the application is unresponsive,
 * can preempt and try that if it's better, but should really only
 * have an effect on slow- step-sizes */
		while(1){
			tui->dirty |= DIRTY_PENDING_FULL;
			tui->draw_function(tui, tui->rows+1, tui->cols,
				tui->back, tui->back, tui->custom, 0, tui->scroll_px, false);
			if (tui->blitbuffer_dirty && tui->scroll_px){
				apply_blitbuffer(tui, 1);
			}
			arcan_shmif_signal(&tui->acon, SHMIF_SIGVID);

/* retain correct step-size so we don't get a bias against cell size */
			tui->scroll_px -= step_sz;
			if (tui->scroll_px <= -tui->cell_h){
				if (tui->scroll_backlog - tui->in_scroll - 1){
					tui->scroll_px += tui->cell_h;
					tui->in_scroll++;

/* 1. move/scroll the related cells */
				memmove(tui->back, &tui->back[tui->cols],
					sizeof(struct tui_cell) * tui->cols * tui->rows);

/* 2. copy MORE and more to account for the fact that the contents may
 * be modified by the client going back and modifying the lines we are
 * scrolling (even make may do this apparently) */
					memcpy(
						&tui->back[(tui->rows - tui->in_scroll) * tui->cols],
						&tui->front[(tui->rows - tui->scroll_backlog) * tui->cols],
							sizeof(struct tui_cell) * tui->cols * (tui->in_scroll + 1));
				}
				else{
					tui->scroll_backlog = 0;
					tui->scroll_px = 0;
					tui->in_scroll = 0;
					tui->draw_function(tui, tui->rows, tui->cols,
						tui->front, tui->back, tui->custom, 0, 0, true);
					arcan_shmif_signal(&tui->acon, SHMIF_SIGVID);
					tui->dirty = 0;
				}
/* return after each completed iteration so the system is responsive */
			break;
			}
		}
	}
	else {
/* caller should assure that this doesn't occur but for the sake of safety */
		if (tui->scroll_backlog < -tui->rows)
			tui->scroll_backlog = -tui->rows;

/* recall: back is over-/under-allocated by one row for this reason,
 * otherwise this is just a version of the above with different ofsets
 * and stepping rules */
		struct tui_cell* top = &tui->back[-tui->cols];

		if (!tui->in_scroll){
			memcpy(top, &tui->front[(-tui->scroll_backlog - 1) * tui->cols],
				sizeof(struct tui_cell)*tui->cols);
			tui->scroll_px = tui->cell_h - step_sz;
			tui->in_scroll++;
		}

		if (-1 == wait_vready(tui, true))
			return;

		while(1){
			tui->dirty |= DIRTY_PENDING_FULL;
			tui->draw_function(tui, tui->rows+1, tui->cols,
				top, top, tui->custom, 0, -tui->scroll_px, false);
			if (tui->blitbuffer_dirty && tui->scroll_px){
				apply_blitbuffer(tui, -1);
			}

			arcan_shmif_signal(&tui->acon, SHMIF_SIGVID);
			tui->scroll_px -= step_sz;
			if (tui->scroll_px <= 0){
				tui->scroll_px += tui->cell_h;
/* same 'weird' thing here, we move-scroll but also copy in/over, a few k
 * transfers could be saved, but that was slower than just copying */
				tui->in_scroll++;
				if (tui->scroll_backlog + tui->in_scroll <= 0){
					memmove(tui->back, top,
						sizeof(struct tui_cell) * tui->rows * tui->cols);
					memcpy(top,
						&tui->front[(-tui->scroll_backlog - tui->in_scroll) * tui->cols],
						tui->in_scroll * sizeof(struct tui_cell) * tui->cols);
				}
				else {
					tui->scroll_backlog = 0;
					tui->scroll_px = 0;
					tui->in_scroll = 0;
					tui->draw_function(tui, tui->rows, tui->cols,
						tui->front, tui->back, tui->custom, 0, 0, true);
					arcan_shmif_signal(&tui->acon, SHMIF_SIGVID);
					tui->dirty = 0;
				}
				break;
			};
		}
	}
}

/*
 * called on:
 * update_screensize
 * arcan_tui_refresh
 * arcan_tui_invalidate
 */
static void update_screen(struct tui_context* tui, bool ign_inact)
{
/* don't redraw while we have an update pending or when we
 * are in an invisible state */
	if (tui->inactive && !ign_inact)
		return;

/* dirty will be set from screen resize, fix the pad region */
	if (tui->dirty & DIRTY_PENDING_FULL){
		tui->acon.dirty.x1 = 0;
		tui->acon.dirty.x2 = tui->acon.w;
		tui->acon.dirty.y1 = 0;
		tui->acon.dirty.y2 = tui->acon.h;
		tsm_screen_selection_reset(tui->screen);

		shmif_pixel col = get_bg_col(tui);

		if (tui->pad_w)
			draw_box(&tui->acon,
				tui->acon.w-tui->pad_w-1, 0, tui->pad_w+1, tui->acon.h, col);
		if (tui->pad_h)
			draw_box(&tui->acon,
				0, tui->acon.h-tui->pad_h-1, tui->acon.w, tui->pad_h+1, col);
	}
	else
/* "always" erase previous cursor, except when cfg->nal screen state explicitly
 * say that cursor drawing should be turned off */
		;

/* FIXME
 * if shaping/ligatures/non-monospace is enabled, we treat this row by row,
 * though this strategy is somewhat flawed if its word wrapped and we start on
 * a new word. There's surely some harfbuzz- trick to this, but baby-steps */

/* NORMAL drawing
 * draw everything that is different and not marked as custom, track the start
 * of every custom entry and sweep- seek- those separately so that they can be
 * drawn as large, continous regions */
	tui->got_custom = false;

/* basic safe-guard */
	if (!tui->front)
		return;

/*
 * Redraw where the cursor is in its intended state if the state of the cursor
 * has been updated
 */
	if (tui->cursor_upd){
/* FIXME: for shaped drawing, we invalidate the entire cursor- row and the
 * blitting should be reworked to account for that */
		if (tui->cursor_y >= tui->rows)
			tui->cursor_y = tui->rows-1;
		if (tui->cursor_x >= tui->cols)
			tui->cursor_x = tui->cols-1;
		int x, y, w, h;
		resolve_cursor(tui, &x, &y, &w, &h);
		struct tui_cell* tc = &tui->front[tui->cursor_y * tui->cols + tui->cursor_x];
		draw_cbt(tui, tc->draw_ch, x, y, &tc->attr, tc->ch == 0, NULL, false);
	}

/* This is the wrong way to n' buffer here, but as a temporary workaround
 * due to design issues with this part in shmif */
	if (tui->dbl_buf)
		tui->dirty |= DIRTY_PENDING_FULL;

	tui->draw_function(tui, tui->rows, tui->cols,
		tui->front, tui->back, tui->custom, 0, 0, true);

	tui->cursor_x = tsm_screen_get_cursor_x(tui->screen);
	tui->cursor_y = tsm_screen_get_cursor_y(tui->screen);

/* draw the new cursor */
	if (tui->cursor_upd && !(tui->cursor_off | tui->cursor_hard_off) ){
		shmif_pixel col = SHMIF_RGBA(
			tui->colors[tui->scroll_lock ? TUI_COL_ALTCURSOR : TUI_COL_CURSOR].rgb[0],
			tui->colors[tui->scroll_lock ? TUI_COL_ALTCURSOR : TUI_COL_CURSOR].rgb[1],
			tui->colors[tui->scroll_lock ? TUI_COL_ALTCURSOR : TUI_COL_CURSOR].rgb[2],
			0xff
		);

		int x, y, w, h;
		resolve_cursor(tui, &x, &y, &w, &h);
		if (cursor_at(tui, x, y, col)){
			struct tui_cell* tc =
				&tui->front[tui->cursor_y * tui->cols + tui->cursor_x];
			struct tui_screen_attr attr = tc->attr;
			int group = tui->scroll_lock ? TUI_COL_ALTCURSOR : TUI_COL_CURSOR;
			attr.inverse = true;
			attr.fr = tui->colors[group].rgb[0];
			attr.fg = tui->colors[group].rgb[1];
			attr.fb = tui->colors[group].rgb[2];
			draw_cbt(tui, tc->draw_ch, x, y, &attr, tc->ch == 0, NULL, true);
		}
	}

	tui->dirty &= ~(DIRTY_PENDING | DIRTY_PENDING_FULL);
}

static bool page_up(struct tui_context* tui)
{
	if (!tui || (tui->flags & TUI_ALTERNATE))
		return true;

	tui->cursor_upd = true;
	tui->cursor_off = true;
	tui->sbofs += tui->rows;
	arcan_tui_scroll_up(tui, tui->rows);
	return true;
}

static bool page_down(struct tui_context* tui)
{
	if (!tui || (tui->flags & TUI_ALTERNATE))
		return true;

	if (tui->sbofs > 0){
		tui->sbofs -= tui->rows;
		tui->sbofs = tui->sbofs < 0 ? 0 : tui->sbofs;
		tui->cursor_upd = true;
		tui->cursor_off = true;
		arcan_tui_scroll_down(tui, tui->rows);
	}
	return true;
}

static int mod_to_scroll(int mods, int screenh)
{
	int rv = 1;
	if (mods & ARKMOD_LSHIFT)
		rv = screenh >> 1;
	if (mods & ARKMOD_RSHIFT)
		rv += screenh >> 1;
	if (mods & ARKMOD_LCTRL)
		rv += screenh >> 1;
	if (mods & ARKMOD_RCTRL)
		rv += screenh >> 1;
	return rv;
}

static bool copy_window(struct tui_context* tui)
{
/* if no pending copy-window request, make a copy of the active screen
 * and spawn a dispatch thread for it */
	if (tui->pending_copy_window)
		return true;

	if (tsm_screen_save(
		tui->screen, true, &tui->pending_copy_window)){
		arcan_shmif_enqueue(&tui->acon, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_TUI,
			.ext.segreq.id = REQID_COPYWINDOW
		});
	}

	return true;
}

static bool scroll_up(struct tui_context* tui)
{
	if (!tui || (tui->flags & TUI_ALTERNATE))
		return true;

	int nf = mod_to_scroll(tui->modifiers, tui->rows);
	arcan_tui_scroll_up(tui, nf);
	tui->sbofs += nf;
	return true;
}

static bool scroll_down(struct tui_context* tui)
{
	if (!tui || (tui->flags & TUI_ALTERNATE))
		return true;

	int nf = mod_to_scroll(tui->modifiers, tui->rows);
	if (tui->sbofs > 0){
		arcan_tui_scroll_down(tui, nf);
		tui->sbofs -= nf;
		tui->sbofs = tui->sbofs < 0 ? 0 : tui->sbofs;
		return true;
	}
	return false;
}

static bool move_up(struct tui_context* tui)
{
	if (tui->scroll_lock){
		page_up(tui);
		return true;
	}
/*	else if (tui->modifiers & (TUIK_LMETA | TUIK_RMETA)){
		if (tui->modifiers & (TUIK_LSHIFT | TUIK_RSHIFT))
			page_up(tui);
		else{
			tsm_screen_sb_up(tui->screen, 1);
			tui->sbofs += 1;
			tui->dirty |= DIRTY_PENDING;
		}
		return true;
	}
 else */
	if (tui->handlers.input_label)
		return tui->handlers.input_label(tui, "UP", NULL, tui->handlers.tag);

	return false;
}

static bool move_down(struct tui_context* tui)
{
	if (tui->scroll_lock){
		page_down(tui);
		return true;
	}
/*
 * else if (tui->modifiers & (TUIK_LMETA | TUIK_RMETA)){
		if (tui->modifiers & (TUIK_LSHIFT | TUIK_RSHIFT))
			page_up(tui);
		else{
			tsm_screen_sb_down(tui->screen, 1);
			tui->sbofs -= 1;
			tui->dirty |= DIRTY_PENDING;
		}
		return true;
	}
	else
*/
	if (tui->handlers.input_label)
		return tui->handlers.input_label(tui, "DOWN", NULL, tui->handlers.tag);

	return false;
}

static bool push_msg(struct tui_context* tui, const char* sel, size_t len)
{
/*
 * there are more advanced clipboard options to be used when
 * we have the option of exposing other devices using a fuse- vfs
 * in: /vdev/istream, /vdev/vin, /vdev/istate
 * out: /vdev/ostream, /dev/vout, /vdev/vstate, /vdev/dsp
 */
	if (!tui->clip_out.vidp || !sel || !len)
		return false;

	arcan_event msgev = {
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	uint32_t state = 0, codepoint = 0;
	const char* outs = sel;
	size_t maxlen = sizeof(msgev.ext.message.data) - 1;

/* utf8- point aligned against block size */
	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i <= maxlen - 1; i++){
			if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(sel[i])))
				lastok = i;

			if (i != lastok){
				if (0 == i)
					return false;
			}
		}

		memcpy(msgev.ext.message.data, outs, lastok);
		msgev.ext.message.data[lastok] = '\0';
		len -= lastok;
		outs += lastok;
		if (len)
			msgev.ext.message.multipart = 1;
		else
			msgev.ext.message.multipart = 0;

		arcan_shmif_enqueue(&tui->clip_out, &msgev);
	}

/* flush remaining */
	if (len){
		snprintf((char*)msgev.ext.message.data, maxlen, "%s", outs);
		msgev.ext.message.multipart = 0;
		arcan_shmif_enqueue(&tui->clip_out, &msgev);
	}
	return true;
}

bool arcan_tui_copy(struct tui_context* tui, const char* utf8_msg)
{
	return push_msg(tui, utf8_msg, strlen(utf8_msg));
}

static void select_copy(struct tui_context* tui)
{
	char* sel = NULL;
	ssize_t len;
/*
 * The tsm_screen selection code is really icky and well-deserving of a
 * rewrite. The 'select_townd' toggle here is that the selection function
 * originally converted to utf8, while we work with UCS4 locally
 */
	int dst = atomic_load(&paste_destination);
	if (tui->select_townd && -1 != dst){
		len = tsm_screen_selection_copy(tui->screen, &sel, false);
		if (!len || len <= 1)
			return;

/* spinlock on block, we have already _Static_assert on PIPE_BUF */
		while (len >= 4){
			int rv = write(dst, sel, 4);
			if (-1 == rv){
				if (errno == EINVAL)
					break;
				else
					continue;
			}
			len -= 4;
			sel += 4;
		}

/* always send a new line (even if it doesn't go through) */
		uint32_t ch = '\n';
		write(dst, &ch, 4);
		return;
	}

	len = tsm_screen_selection_copy(tui->screen, &sel, true);
	if (!sel || len <= 1)
		return;

	len--;

/* empty cells gets marked as NULL, but that would cut the copy short */
	for (size_t i = 0; i < len; i++){
		if (sel[i] == '\0')
			sel[i] = ' ';
	}

	push_msg(tui, sel, len);
	free(sel);
}

struct tui_cell arcan_tui_getxy(
	struct tui_context* tui, size_t x, size_t y, bool fl)
{
	if (y >= tui->rows || x >= tui->cols)
		return (struct tui_cell){};

	return fl ?
		tui->front[y * tui->rows + x] :
		tui->back[y * tui->rows + x];
}

static bool select_at(struct tui_context* tui)
{
	tsm_screen_selection_reset(tui->screen);
	unsigned sx, sy, ex, ey;
	int rv = tsm_screen_get_word(tui->screen,
		tui->mouse_x, tui->mouse_y, &sx, &sy, &ex, &ey);

	if (0 == rv){
		tsm_screen_selection_reset(tui->screen);
		tsm_screen_selection_start(tui->screen, sx, sy);
		tsm_screen_selection_target(tui->screen, ex, ey);
		select_copy(tui);
		tui->dirty |= DIRTY_PENDING;
	}

	tui->in_select = false;
	return true;
}

static bool select_row(struct tui_context* tui)
{
	tsm_screen_selection_reset(tui->screen);
	tsm_screen_selection_start(tui->screen, 0, tui->cursor_y);
	tsm_screen_selection_target(tui->screen, tui->cols-1, tui->cursor_y);
	select_copy(tui);
	tui->dirty |= DIRTY_PENDING;
	tui->in_select = false;
	return true;
}

struct lent {
	int ctx;
	const char* lbl;
	const char* descr;
	bool(*ptr)(struct tui_context*);
};

static bool setup_font(struct tui_context* tui,
	int fd, float font_sz, int mode);

bool inc_fontsz(struct tui_context* tui)
{
	tui->font_sz_delta += 2;
	setup_font(tui, BADFD, 0, 0);
	return true;
}

bool dec_fontsz(struct tui_context* tui)
{
	if (tui->font_sz > 8)
		tui->font_sz_delta -= 2;
	setup_font(tui, BADFD, 0, 0);
	return true;
}

static bool scroll_lock(struct tui_context* tui)
{
	tui->scroll_lock = !tui->scroll_lock;
	if (!tui->scroll_lock){
		tui->in_scroll = tui->sbofs = 0;
		tsm_screen_sb_reset(tui->screen);
		tui->scroll_backlog = 0;
		tui->cursor_upd = true;
		tui->cursor_off = false;
		tui->dirty |= DIRTY_PENDING;
	}
	return true;
}

static bool mouse_forward(struct tui_context* tui)
{
	tui->mouse_forward = !tui->mouse_forward;
	return true;
}

static bool sel_sw(struct tui_context* tui)
{
	tui->select_townd = !tui->select_townd;
	return true;
}

/*
 * Some things missing in labelhint that we'll keep to later
 * 1. descriptions does not match geohint language
 * 2. we do not expose a default binding and the labelhint initial field
 *    should have its typing reworked (uint16 mods + uint16 sym)
 * 3. we do not use subid indexing
 */
static const struct lent labels[] = {
	{1 | 2, "LINE_UP", "Scroll 1 row up", scroll_up},
	{1 | 2, "LINE_DOWN", "Scroll 1 row down", scroll_down},
	{1 | 2, "PAGE_UP", "Scroll one page up", page_up},
	{1 | 2, "PAGE_DOWN", "Scroll one page down", page_down},
	{1 | 2, "COPY_AT", "Copy word at cursor", select_at},
	{1 | 2, "COPY_ROW", "Copy cursor row", select_row},
	{1, "MOUSE_FORWARD", "Toggle mouse forwarding", mouse_forward},
	{1 | 2, "SCROLL_LOCK", "Arrow- keys to pageup/down", scroll_lock},
	{1 | 2, "UP", "(scroll-lock) page up, UP keysym", move_up},
	{1 | 2, "DOWN", "(scroll-lock) page down, DOWN keysym", move_down},
	{1, "COPY_WINDOW", "Copy to new passive window", copy_window},
	{1 | 2, "INC_FONT_SZ", "Font size +1 pt", inc_fontsz},
	{1 | 2, "DEC_FONT_SZ", "Font size -1 pt", dec_fontsz},
	{1, "SELECT_TOGGLE", "Switch select destination (wnd, clipboard)", sel_sw},
	{0, NULL, NULL}
};

static void expose_labels(struct tui_context* tui)
{
	const struct lent* cur = labels;

/*
 * NOTE: We do not currently expose a suggested default
 */
	while(cur->lbl){
		if (tui->subseg && (cur->ctx & 2) == 0)
			continue;
		if (!tui->subseg && (cur->ctx & 1) == 0)
			continue;

		arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(LABELHINT),
			.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
		};
		snprintf(ev.ext.labelhint.label,
			COUNT_OF(ev.ext.labelhint.label),
			"%s", cur->lbl
		);
		snprintf(ev.ext.labelhint.descr,
			COUNT_OF(ev.ext.labelhint.descr),
			"%s", cur->descr
		);
		cur++;
		arcan_shmif_enqueue(&tui->acon, &ev);
	}
}

static bool consume_label(struct tui_context* tui,
	arcan_ioevent* ioev, const char* label)
{
	const struct lent* cur = labels;

	while(cur->lbl){
		if (strcmp(label, cur->lbl) == 0){
			return cur->ptr(tui);
		}
		cur++;
	}

	bool res = false;
	if (tui->handlers.input_label){
		res |= tui->handlers.input_label(tui, label, true, tui->handlers.tag);
		res |= tui->handlers.input_label(tui, label, false, tui->handlers.tag);
	}

	return res;
}

static int update_mods(int mods, int sym, bool pressed)
{
	if (pressed)
	switch(sym){
	case TUIK_LSHIFT: return mods | ARKMOD_LSHIFT;
	case TUIK_RSHIFT: return mods | ARKMOD_RSHIFT;
	case TUIK_LCTRL: return mods | ARKMOD_LCTRL;
	case TUIK_RCTRL: return mods | ARKMOD_RCTRL;
	case TUIK_COMPOSE:
	case TUIK_LMETA: return mods | ARKMOD_LMETA;
	case TUIK_RMETA: return mods | ARKMOD_RMETA;
	default:
		return mods;
	}
	else
	switch(sym){
	case TUIK_LSHIFT: return mods & (~ARKMOD_LSHIFT);
	case TUIK_RSHIFT: return mods & (~ARKMOD_RSHIFT);
	case TUIK_LCTRL: return mods & (~ARKMOD_LCTRL);
	case TUIK_RCTRL: return mods & (~ARKMOD_RCTRL);
	case TUIK_COMPOSE:
	case TUIK_LMETA: return mods & (~ARKMOD_LMETA);
	case TUIK_RMETA: return mods & (~ARKMOD_RMETA);
	default:
		return mods;
	}
}

static void ioev_ctxtbl(struct tui_context* tui,
	arcan_ioevent* ioev, const char* label)
{
	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		bool pressed = ioev->input.translated.active;
		int sym = ioev->input.translated.keysym;
		int oldm = tui->modifiers;
		tui->modifiers = update_mods(tui->modifiers, sym, pressed);
		if (!pressed)
			return;

		if (tui->in_select){
			tui->in_select = false;
			tsm_screen_selection_reset(tui->screen);
		}
		tui->inact_timer = -4;
		if (label[0] && consume_label(tui, ioev, label))
			return;

/* modifiers doesn't get set for the symbol itself which is a problem
 * for when we want to forward modifier data to another handler like mbtn */
		if (sym >= 300 && sym <= 314)
			return;

/* reset scrollback on normal input */
		if (oldm == tui->modifiers && tui->sbofs != 0){
			tui->cursor_upd = true;
			tui->cursor_off = false;
			tui->in_scroll = tui->sbofs = 0;
			tui->scroll_backlog = 0;
			tsm_screen_sb_reset(tui->screen);
			tui->dirty |= DIRTY_PENDING;
		}

/* check the incoming utf8 if it's valid, if so forward and if the handler
 * consumed the value, leave the function */
		int len = 0;
		bool valid = true;
		uint32_t codepoint = 0, state = 0;
		while (len < 5 && ioev->input.translated.utf8[len]){
			if (UTF8_REJECT == utf8_decode(&state, &codepoint,
				ioev->input.translated.utf8[len])){
				valid = false;
				break;
			}
			len++;
		}

/* disallow the private-use area */
		if ((codepoint >= 0xe000 && codepoint <= 0xf8ff))
			valid = false;

		if (valid && ioev->input.translated.utf8[0] && tui->handlers.input_utf8){
			if (tui->handlers.input_utf8 && tui->handlers.input_utf8(tui,
					(const char*)ioev->input.translated.utf8,
					len, tui->handlers.tag))
				return;
		}

/* otherwise, forward as much of the key as we know */
		if (tui->handlers.input_key)
			tui->handlers.input_key(tui,
				sym,
				ioev->input.translated.scancode,
				ioev->input.translated.modifiers,
				ioev->subid, tui->handlers.tag
			);
	}
	else if (ioev->devkind == EVENT_IDEVKIND_MOUSE){
		if (ioev->datatype == EVENT_IDATATYPE_ANALOG){
			if (ioev->subid == 0){
/*				int x, y, w, h;
				resolve_cursor(tui->mouse_x, tui->mouse_y, x, y, w, h); */
				tui->mouse_x = ioev->input.analog.axisval[0] / tui->cell_w;
			}
			else if (ioev->subid == 1){
				int yv = ioev->input.analog.axisval[0];
				tui->mouse_y = yv / tui->cell_h;

				bool upd = false;
				if (tui->mouse_x != tui->lm_x){
					tui->lm_x = tui->mouse_x;
					upd = true;
				}
				if (tui->mouse_y != tui->lm_y){
					tui->lm_y = tui->mouse_y;
					upd = true;
				}

				if (tui->mouse_forward && tui->handlers.input_mouse_motion){
					if (upd)
					tui->handlers.input_mouse_motion(tui, false,
						tui->mouse_x, tui->mouse_y, tui->modifiers, tui->handlers.tag);
					return;
				}

				if (!tui->in_select)
					return;

/* we use the upper / lower regions as triggers for scrollback + selection,
 * with a magnitude based on how far "off" we are */
				if (yv < 0.3 * tui->cell_h)
					tui->scrollback = -1 * (1 + yv / tui->cell_h);
				else if (yv > tui->rows * tui->cell_h + 0.3 * tui->cell_h)
					tui->scrollback = 1 + (yv - tui->rows * tui->cell_h) / tui->cell_h;
				else
					tui->scrollback = 0;

/* in select and drag negative in window or half-size - then use ticker
 * to scroll and an accelerated scrollback */
				if (upd){
					tsm_screen_selection_target(tui->screen, tui->lm_x, tui->lm_y);
					tui->dirty |= DIRTY_PENDING;
				}
/* in select? check if motion tile is different than old, if so,
 * tsm_selection_target */
			}
		}
/* press? press-point tsm_screen_selection_start,
 * release and press-tile ~= release_tile? copy */
		else if (ioev->datatype == EVENT_IDATATYPE_DIGITAL){
			if (ioev->subid){
				if (ioev->input.digital.active)
					tui->mouse_btnmask |=  (1 << (ioev->subid-1));
				else
					tui->mouse_btnmask &= ~(1 << (ioev->subid-1));
			}
			if (tui->mouse_forward && tui->handlers.input_mouse_button){
				tui->handlers.input_mouse_button(tui, tui->mouse_x,
					tui->mouse_y, ioev->subid, ioev->input.digital.active,
					tui->modifiers, tui->handlers.tag
				);
				return;
			}

			if (ioev->flags & ARCAN_IOFL_GESTURE){
				if (strcmp(ioev->label, "dblclick") == 0){
/* select row if double doubleclick */
					if (tui->last_dbl_x == tui->mouse_x &&
						tui->last_dbl_y == tui->mouse_y){
						tsm_screen_selection_reset(tui->screen);
						tsm_screen_selection_start(tui->screen, 0, tui->mouse_y);
						tsm_screen_selection_target(
							tui->screen, tui->cols-1, tui->mouse_y);
						select_copy(tui);
						tui->dirty |= DIRTY_PENDING;
						tui->in_select = false;
					}
/* select word */
					else{
						unsigned sx, sy, ex, ey;
						sx = sy = ex = ey = 0;
						int rv = tsm_screen_get_word(tui->screen,
							tui->mouse_x, tui->mouse_y, &sx, &sy, &ex, &ey);
						if (0 == rv){
							tsm_screen_selection_reset(tui->screen);
							tsm_screen_selection_start(tui->screen, sx, sy);
							tsm_screen_selection_target(tui->screen, ex, ey);
							select_copy(tui);
							tui->dirty |= DIRTY_PENDING;
							tui->in_select = false;
						}
					}

					tui->last_dbl_x = tui->mouse_x;
					tui->last_dbl_y = tui->mouse_y;
				}
				else if (strcmp(ioev->label, "click") == 0){
/* TODO: forward to cfg->nal? */
				}
				return;
			}
/* scroll or select?
 * NOTE: should also consider a way to specify magnitude */
			if (ioev->subid == MBTN_WHEEL_UP_IND){
				if (ioev->input.digital.active)
					scroll_up(tui);
			}
			else if (ioev->subid == MBTN_WHEEL_DOWN_IND){
				if (ioev->input.digital.active)
					scroll_down(tui);
			}
			else if (ioev->input.digital.active){
				tsm_screen_selection_start(tui->screen, tui->mouse_x, tui->mouse_y);
				tui->bsel_x = tui->mouse_x;
				tui->bsel_y = tui->mouse_y;
				tui->lm_x = tui->mouse_x;
				tui->lm_y = tui->mouse_y;
				tui->in_select = true;
			}
			else{
				if (tui->mouse_x != tui->bsel_x || tui->mouse_y != tui->bsel_y)
					select_copy(tui);

				tsm_screen_selection_reset(tui->screen);
				tui->in_select = false;
				tui->dirty |= DIRTY_PENDING;
			}
		}
		else if (tui->handlers.input_misc)
			tui->handlers.input_misc(tui, ioev, tui->handlers.tag);
	}
}

static void resize_cellbuffer(struct tui_context* tui)
{
	if (tui->base)
		free(tui->base);

	if (tui->blitbuffer)
		free(tui->blitbuffer);

	tui->base = NULL;
	if (tui->smooth_scroll)
		tui->blitbuffer = malloc(2 * tui->cell_h * tui->acon.stride);

/* window size with spare lines for scroll-in-scroll-out */
	size_t buffer_sz = (2 + tui->rows) * tui->cols * sizeof(struct tui_cell);
	tui->base = malloc(buffer_sz * 3);
	if (!tui->base){
		LOG("couldn't allocate screen buffers buffer\n");
		return;
	}

	memset(tui->base, '\0', buffer_sz);
	tui->front = tui->base;

/* for back buffer, spare one above, one below */
	tui->back = &tui->base[(tui->rows + 1) * tui->cols];
	tui->custom = &tui->back[(tui->rows + 1) * tui->cols];
}

static void update_screensize(struct tui_context* tui, bool clear)
{
	int cols = tui->acon.w / tui->cell_w;
	int rows = tui->acon.h / tui->cell_h;
	LOG("update screensize (%d * %d), (%d * %d)\n",
		cols, rows, (int)tui->acon.w, (int)tui->acon.h);

/* we respect the displayhint entirely, and pad with background
 * color of the new dimensions doesn't align with cell-size */
	shmif_pixel col = get_bg_col(tui);

	if (-1 == wait_vready(tui, true))
		return;

/* calculate the rpad/bpad regions based on the desired output size and
 * the amount consumed by the aligned number of cells */
	tui->pad_w = tui->acon.w - (cols * tui->cell_w);
	tui->pad_h = tui->acon.h - (rows * tui->cell_h);

/* if the number of cells has actually changed, we need to propagate */
	if (cols != tui->cols || rows != tui->rows){
		tui->cols = cols;
		tui->rows = rows;

		if (tui->handlers.resize)
			tui->handlers.resize(tui,
			tui->acon.w, tui->acon.h, cols, rows, tui->handlers.tag);

/* NOTE/FIXME: this only considers the active screen and not any alternate
 * screens that are around, which is probably not what we want. */
		tsm_screen_resize(tui->screen, cols, rows);
		resize_cellbuffer(tui);

		if (tui->handlers.resized)
			tui->handlers.resized(tui,
				tui->acon.w, tui->acon.h, cols, rows, tui->handlers.tag);
	}
	else {
/* if we have TUI- based screen buffering for smooth-scrolling,
 * double-buffered rendering and text shaping, that one needs to be rebuilt */
		resize_cellbuffer(tui);
	}

/* will enforce full redraw, and full redraw will also update padding.  the
 * resized- mark will also force front/back buffer resynch to avoid black or
 * corrupted smooth scroll areas */
	tui->dirty |= DIRTY_PENDING_FULL;

	if (clear)
		draw_box(&tui->acon, 0, 0, tui->acon.w, tui->acon.h, col);

	update_screen(tui, true);
}

struct bgthread_context {
	struct tui_context* tui;
	struct tsm_save_buf* buf;
	bool invalidated;
	int iopipes[2];
};

static void drop_pending(struct tsm_save_buf** tui)
{
	if (!*tui)
		return;

	free((*tui)->metadata);
	free((*tui)->scrollback);
	free((*tui)->screen);
	free(*tui);
	*tui = NULL;
}

static bool bgscreen_label(struct tui_context* c,
	const char* label, bool active, void* t)
{
	struct bgthread_context* ctx = t;
	if (!ctx->tui)
		return false;

/* atomically grab the only 'paste' target slot */
	if (strcmp(label, "PASTE_SELECT") == 0){
		if (active){
			atomic_store(&paste_destination, ctx->iopipes[1]);
		}
		return true;
	}
	return false;
}

/* synch the buffer copy before so we don't lose pasted contents */
static void bgscreen_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	struct bgthread_context* ctx = t;
	if (!ctx->tui)
		return;

	struct tsm_save_buf* newbuf;
	if (ctx->invalidated && tsm_screen_save(ctx->tui->screen, true, &newbuf)){
		drop_pending(&ctx->buf);
		ctx->invalidated = false;
		ctx->buf = newbuf;
	}
}

static void bgscreen_resized(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	struct bgthread_context* ctx = t;
	if (!ctx->tui)
		return;

	tsm_screen_erase_screen(ctx->tui->screen, false);
	tsm_screen_load(ctx->tui->screen, ctx->buf, 0, 0, 0);
}

static void* bgscreen_thread_proc(void* ctxptr)
{
	struct bgthread_context* ctx = ctxptr;

	arcan_shmif_enqueue(&ctx->tui->acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(LABELHINT),
		.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL,
		.ext.labelhint.label = "PASTE_SELECT",
		.ext.labelhint.descr = "Mark window as copy recipient",
		.ext.labelhint.initial = TUIK_RETURN
	});

	tsm_screen_load(ctx->tui->screen, ctx->buf, 0, 0, TSM_LOAD_RESIZE);
	ctx->tui->cursor_hard_off = true;
	int exp = -1;

	while (true){
/* take the paste-slot if no-one has it */
		while(!atomic_compare_exchange_weak(
			&paste_destination, &exp, ctx->iopipes[1]));

		struct tui_process_res res =
			arcan_tui_process(&ctx->tui, 1, &ctx->iopipes[0], 1, -1);

		if (res.errc < TUI_ERRC_OK || res.bad)
			break;

/* paste into */
		uint32_t ch;
		while (4 == read(ctx->iopipes[0], &ch, 4)){
			if (ch == '\n')
				tsm_screen_newline(ctx->tui->screen);
			else
				arcan_tui_write(ctx->tui, ch, NULL);
			ctx->invalidated = true;
		}

		if (-1 == arcan_tui_refresh(ctx->tui) && errno == EINVAL)
			break;
	}

/* remove the paste destination if it happens to be us */
	if (-1 != ctx->iopipes[0]){
		while(!atomic_compare_exchange_weak(
			&paste_destination, &ctx->iopipes[1], -1));
		close(ctx->iopipes[0]);
		close(ctx->iopipes[1]);
	}

	arcan_tui_destroy(ctx->tui, NULL);
	drop_pending(&ctx->buf);
	free(ctx);

	return NULL;
}

/*
 * copy [src] into a background managed context that only handles clipboard,
 * scrollback etc. assume ownership over [con] and will spawn a new thread or
 * process.
 */
static void bgscreen_thread(
	struct tui_context* src, struct arcan_shmif_cont* con)
{
	struct bgthread_context* ctxptr = malloc(sizeof(struct bgthread_context));
	*ctxptr = (struct bgthread_context){
		.buf = src->pending_copy_window,
		.iopipes = {-1, -1}
	};
	if (!ctxptr || -1 == pipe(ctxptr->iopipes)){
		free(ctxptr);
		arcan_shmif_drop(con);
		drop_pending(&src->pending_copy_window);
		return;
	}

/* pipes used to communicate local clipboard data */
	fcntl(ctxptr->iopipes[0], F_SETFD, O_CLOEXEC);
	fcntl(ctxptr->iopipes[0], F_SETFL, O_NONBLOCK);
	fcntl(ctxptr->iopipes[1], F_SETFD, O_CLOEXEC);
	fcntl(ctxptr->iopipes[1], F_SETFL, O_NONBLOCK);

/* bind the context to a new tui session */
	struct tui_cbcfg cbs = {
		.tag = ctxptr,
		.resize = bgscreen_resize,
		.resized = bgscreen_resized,
		.input_label = bgscreen_label
	};
	struct tui_settings cfg = arcan_tui_defaults(con, src);
	ctxptr->tui = arcan_tui_setup(con, &cfg, &cbs, sizeof(cbs));
	if (!ctxptr->tui){
		arcan_shmif_drop(con);
		close(ctxptr->iopipes[0]);
		close(ctxptr->iopipes[1]);
		free(ctxptr);
		drop_pending(&src->pending_copy_window);
		return;
	}

	ctxptr->tui->force_bitmap = src->force_bitmap;

/* send the session to a new background thread that we detach and ignore */
	pthread_attr_t bgattr;
	pthread_attr_init(&bgattr);
	pthread_attr_setdetachstate(&bgattr, PTHREAD_CREATE_DETACHED);

	pthread_t bgthr;
	if (0 != pthread_create(&bgthr, &bgattr, bgscreen_thread_proc, ctxptr)){
		arcan_shmif_drop(con);
		drop_pending(&src->pending_copy_window);
		close(ctxptr->iopipes[0]);
		close(ctxptr->iopipes[1]);
		free(ctxptr);
		return;
	}

/* responsibility handed over to thread */
	src->pending_copy_window = NULL;
}

void arcan_tui_screencopy(
	struct tui_context* src, struct tui_context* dst, bool cur, bool alt, bool sb)
{
/*
 * 1. resize [dst] to match cellcount from src
 * 2. delegate the copying to tsm_screen
 * 3. possibly resize "back"
 */
}

void arcan_tui_request_subwnd(
	struct tui_context* tui, unsigned type, uint16_t id)
{
	if (!tui || !tui->acon.addr)
		return;

/* only allow a certain subset so shmif- doesn't bleed into this library more
 * than it already does */
	switch (type){
	case TUI_WND_TUI:
	case TUI_WND_POPUP:
	case TUI_WND_DEBUG:
	case TUI_WND_HANDOVER:
	break;
	default:
		return;
	}

	arcan_shmif_enqueue(&tui->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = type,
		.ext.segreq.id = (uint32_t) id | (1 << 31),
		.ext.segreq.width = tui->acon.w,
		.ext.segreq.height = tui->acon.h
	});
}

static void targetev(struct tui_context* tui, arcan_tgtevent* ev)
{
	switch (ev->kind){
	case TARGET_COMMAND_GRAPHMODE:
		if (ev->ioevs[0].iv == 0){
			if (tui->handlers.recolor)
				tui->handlers.recolor(tui, tui->handlers.tag);
		}
		else if (ev->ioevs[0].iv == 1){
			tui->alpha = ev->ioevs[1].fv;
			tui->dirty = DIRTY_PENDING_FULL;
		}
		else if (ev->ioevs[0].iv <= TUI_COL_INACTIVE){
			tui->colors[ev->ioevs[0].iv].rgb[0] = ev->ioevs[1].iv;
			tui->colors[ev->ioevs[0].iv].rgb[1] = ev->ioevs[2].iv;
			tui->colors[ev->ioevs[0].iv].rgb[2] = ev->ioevs[3].iv;
		}
	break;

/* sigsuspend to group */
	case TARGET_COMMAND_PAUSE:
		if (tui->handlers.exec_state)
			tui->handlers.exec_state(tui, 1);
	break;

/* sigresume to session */
	case TARGET_COMMAND_UNPAUSE:
		if (tui->handlers.exec_state)
			tui->handlers.exec_state(tui, 0);
	break;

	case TARGET_COMMAND_RESET:
		tui->modifiers = 0;
		switch(ev->ioevs[0].iv){
		case 0:
		case 1:
			if (tui->handlers.reset)
				tui->handlers.reset(tui, ev->ioevs[0].iv, tui->handlers.tag);
		break;

/* hard reset / crash recovery (server-side state lost) */
		case 2:
		case 3:
			arcan_shmif_drop(&tui->clip_in);
			arcan_shmif_drop(&tui->clip_out);
			queue_requests(tui, true, true);
		break;
		}
		tui->dirty = DIRTY_PENDING_FULL;
	break;

	case TARGET_COMMAND_BCHUNK_IN:
	case TARGET_COMMAND_BCHUNK_OUT:
		if (tui->handlers.bchunk)
			tui->handlers.bchunk(tui, ev->kind == TARGET_COMMAND_BCHUNK_IN,
				ev->ioevs[1].iv | (ev->ioevs[2].iv << 31),
				ev->ioevs[0].iv, tui->handlers.tag
			);
	break;

	case TARGET_COMMAND_SEEKCONTENT:
		if (ev->ioevs[0].iv){ /* relative */
			if (ev->ioevs[1].iv < 0){
				arcan_tui_scroll_up(tui, -1 * ev->ioevs[1].iv);
				tui->sbofs -= ev->ioevs[1].iv;
			}
			else{
				arcan_tui_scroll_down(tui, ev->ioevs[1].iv);
				tui->sbofs += ev->ioevs[1].iv;
			}
			tui->dirty |= DIRTY_PENDING;
		}
	break;

	case TARGET_COMMAND_FONTHINT:{
		int fd = BADFD;
		if (ev->ioevs[0].iv != BADFD)
			fd = arcan_shmif_dupfd(ev->ioevs[0].iv, -1, true);

		switch(ev->ioevs[3].iv){
		case -1: break;
/* happen to match TTF_HINTING values, though LED layout could be
 * modified through DISPLAYHINT but in practice, not so much. */
		default:
			tui->hint = ev->ioevs[3].iv;
		break;
		}

/* unit conversion again, we get the size in cm, truetype wrapper takes pt,
 * (at 0.03527778 cm/pt), then update_font will take ppcm into account */
		float npx = setup_font(tui, fd,
			ev->ioevs[2].fv > 0 ? ev->ioevs[2].fv : 0, ev->ioevs[4].iv);

		update_screensize(tui, false);
	}
	break;

	case TARGET_COMMAND_DISPLAYHINT:{
		bool dev =
			(ev->ioevs[0].iv && ev->ioevs[1].iv) &&
			(abs((int)ev->ioevs[0].iv - (int)tui->acon.w) > 0 ||
			abs((int)ev->ioevs[1].iv - (int)tui->acon.h) > 0);

/* visibility change */
		bool update = false;
		if (!(ev->ioevs[2].iv & 128)){
			if (ev->ioevs[2].iv & 2){
				tui->inactive = true;
			}
			else if (tui->inactive){
				tui->inactive = false;
				tui->dirty |= DIRTY_PENDING;
				update_screen(tui, false);
			}

	/* selection change */
			if (ev->ioevs[2].iv & 4){
				tui->focus = false;
				tui->modifiers = 0;
				tui->cursor_off = true;
				flag_cursor(tui);
			}
			else{
				tui->focus = true;
				tui->inact_timer = 0;
				tui->cursor_off = tui->sbofs != 0 ? true : false;
				flag_cursor(tui);
			}
			if (tui->handlers.visibility)
				tui->handlers.visibility(tui,
					!tui->inactive, tui->focus, tui->handlers.tag);
		}

/* switch cursor kind on changes to 4 in ioevs[2] */
		if (dev){
			if (!arcan_shmif_resize_ext(&tui->acon,
				ev->ioevs[0].iv, ev->ioevs[1].iv, (struct shmif_resize_ext){
					.vbuf_cnt = tui->dbl_buf ? 2 : 1
				}))
				LOG("resize to (%d * %d) failed\n", ev->ioevs[0].iv, ev->ioevs[1].iv);
			update_screensize(tui, true);
			tui->in_scroll = 0;
		}

/* currently ignoring field [3], RGB layout as freetype with
 * subpixel hinting builds isn't default / tested properly here */

		if (ev->ioevs[4].fv > 0 && fabs(ev->ioevs[4].fv - tui->ppcm) > 0.01){
			float sf = tui->ppcm / ev->ioevs[4].fv;
			tui->ppcm = ev->ioevs[4].fv;
			setup_font(tui, BADFD, 0, 0);
			tui->dirty = DIRTY_PENDING_FULL;
		}
	}
	break;

/* if the highest bit is set in the request, it's an external request
 * and it should be forwarded to the event handler */
	case TARGET_COMMAND_REQFAIL:
		if ( ((uint32_t)ev->ioevs[0].iv & (1 << 31)) ){
			if (tui->handlers.subwindow){
				tui->handlers.subwindow(tui, NULL,
					(uint32_t)ev->ioevs[0].iv & 0xffff, TUI_WND_TUI, tui->handlers.tag);
			}
		}
		else if ((uint32_t)ev->ioevs[0].iv == REQID_COPYWINDOW){
			drop_pending(&tui->pending_copy_window);
		}
	break;

/*
 * map the two clipboards needed for both cut and for paste operations
 */
	case TARGET_COMMAND_NEWSEGMENT:
		if (ev->ioevs[2].iv != SEGID_TUI && ev->ioevs[2].iv != SEGID_POPUP &&
			ev->ioevs[2].iv != SEGID_HANDOVER && ev->ioevs[2].iv != SEGID_DEBUG &&
			ev->ioevs[2].iv != SEGID_ACCESSIBILITY &&
			ev->ioevs[2].iv != SEGID_CLIPBOARD_PASTE &&
			ev->ioevs[2].iv != SEGID_CLIPBOARD
		)
			return;

		if (ev->ioevs[2].iv == SEGID_CLIPBOARD_PASTE){
			if (!tui->clip_in.vidp){
				tui->clip_in = arcan_shmif_acquire(
					&tui->acon, NULL, SEGID_CLIPBOARD_PASTE, 0);
			}
			else
				LOG("multiple paste- clipboards received, likely appl. error\n");
		}
/*
 * the requested clipboard has arrived
 */
		else if (ev->ioevs[1].iv == 0 && ev->ioevs[3].iv == 0xfeedface){
			if (!tui->clip_out.vidp){
				tui->clip_out = arcan_shmif_acquire(
					&tui->acon, NULL, SEGID_CLIPBOARD, 0);
			}
			else
				LOG("multiple clipboards received, likely appl. error\n");
		}
/*
 * special handling for our pasteboard window
 */
		else if (ev->ioevs[3].iv == REQID_COPYWINDOW && tui->pending_copy_window){
			struct arcan_shmif_cont acon =
				arcan_shmif_acquire(&tui->acon, NULL, ev->ioevs[2].iv, 0);
			bgscreen_thread(tui, &acon);
		}
/*
 * new caller requested segment, even though acon is auto- scope allocated
 * here, the API states that the normal setup procedure should be respected,
 * which means that there will be an explicit copy of acon rather than an
 * alias.
 */
		else{
			bool can_push = ev->ioevs[2].iv == SEGID_DEBUG;
			can_push |= ev->ioevs[2].iv == SEGID_ACCESSIBILITY;
			bool user_defined = (uint32_t)ev->ioevs[3].iv & (1 << 31);

			if ((can_push || user_defined) && tui->handlers.subwindow){
				struct arcan_shmif_cont acon = arcan_shmif_acquire(
					&tui->acon, NULL, ev->ioevs[2].iv, 0);
				if (!tui->handlers.subwindow(tui, &acon,
					(uint32_t)ev->ioevs[3].iv & 0xffff,
					ev->ioevs[2].iv, tui->handlers.tag
				)){
					arcan_shmif_defimpl(&tui->acon, &acon, ev->ioevs[2].iv);
				}
			}
		}
	break;

/* only flag DIRTY_PENDING and let the normal screen-update actually bundle
 * things together so that we don't risk burning an update/ synch just because
 * the cursor started blinking. */
	case TARGET_COMMAND_STEPFRAME:
		if (ev->ioevs[1].iv == 1){
			if (tui->cursor_period){
				if (tui->focus){
					tui->inact_timer++;
					if (tui->sbofs != 0){
						tui->cursor_off = true;
					}
					else
						tui->cursor_off = tui->inact_timer > 1 ? !tui->cursor_off : false;
					tui->cursor_upd = true;
					tui->dirty |= DIRTY_PENDING;
				}
				if (tui->handlers.tick)
					tui->handlers.tick(tui, tui->handlers.tag);
			}
			else{
				if (!tui->cursor_off && tui->focus){
					tui->cursor_off = true;
					flag_cursor(tui);
				}
			}
		}
		if (tui->in_select && tui->scrollback != 0){
			if (tui->scrollback < 0)
				arcan_tui_scroll_up(tui, abs(tui->scrollback));
			else
				arcan_tui_scroll_down(tui, tui->scrollback);
			tui->dirty |= DIRTY_PENDING;
		}
	break;

	case TARGET_COMMAND_GEOHINT:
		if (tui->handlers.geohint)
			tui->handlers.geohint(tui, ev->ioevs[0].fv, ev->ioevs[1].fv,
				ev->ioevs[2].fv, (char*) ev->ioevs[3].cv,
				(char*) ev->ioevs[4].cv, tui->handlers.tag
			);
	break;

	case TARGET_COMMAND_STORE:
	case TARGET_COMMAND_RESTORE:
		if (tui->handlers.state)
			tui->handlers.state(tui, ev->kind == TARGET_COMMAND_RESTORE,
				ev->ioevs[0].iv, tui->handlers.tag);
	break;

	case TARGET_COMMAND_EXIT:
		if (tui->handlers.exec_state)
			tui->handlers.exec_state(tui, 2);
		arcan_shmif_drop(&tui->acon);
	break;

	default:
	break;
	}
}

static void event_dispatch(struct tui_context* tui)
{
	arcan_event ev;
	int pv;

	while ((pv = arcan_shmif_poll(&tui->acon, &ev)) > 0){
		switch (ev.category){
		case EVENT_IO:
			ioev_ctxtbl(tui, &(ev.io), ev.io.label);
		break;

		case EVENT_TARGET:
			targetev(tui, &ev.tgt);
		break;

		default:
		break;
		}
	}

	if (pv == -1)
		arcan_shmif_drop(&tui->acon);
}

static void check_pasteboard(struct tui_context* tui)
{
	arcan_event ev;
	int pv = 0;

	while ((pv = arcan_shmif_poll(&tui->clip_in, &ev)) > 0){
		if (ev.category != EVENT_TARGET)
			continue;

		arcan_tgtevent* tev = &ev.tgt;
		switch(tev->kind){
		case TARGET_COMMAND_MESSAGE:
			if (tui->handlers.utf8)
				tui->handlers.utf8(tui, (const uint8_t*) tev->message,
					strlen(tev->message), tev->ioevs[0].iv, tui->handlers.tag);
		break;
		case TARGET_COMMAND_EXIT:
			arcan_shmif_drop(&tui->clip_in);
			return;
		break;
		default:
		break;
		}
	}

	if (pv == -1)
		arcan_shmif_drop(&tui->clip_in);
}

static void queue_requests(struct tui_context* tui, bool clipboard, bool ident)
{
/* immediately request a clipboard for cut operations (none received ==
 * running appl doesn't care about cut'n'paste/drag'n'drop support). */
/* and send a timer that will be used for cursor blinking when active */
	if (clipboard)
	arcan_shmif_enqueue(&tui->acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.width = 1,
		.ext.segreq.height = 1,
		.ext.segreq.kind = SEGID_CLIPBOARD,
		.ext.segreq.id = 0xfeedface
	});

/* always request a timer as the _tick callback may need it */
	arcan_shmif_enqueue(&tui->acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(CLOCKREQ),
		.ext.clock.rate = tui->cursor_period,
		.ext.clock.id = 0xabcdef00,
	});

	if (ident && tui->last_ident.ext.kind != 0)
		arcan_shmif_enqueue(&tui->acon, &tui->last_ident);
}

#ifndef SIMPLE_RENDERING
static void probe_font(struct tui_context* tui,
	TTF_Font* font, const char* msg, size_t* dw, size_t* dh)
{
	TTF_Color fg = {.r = 0xff, .g = 0xff, .b = 0xff};
	int w = *dw, h = *dh;
	TTF_SizeUTF8(font, msg, &w, &h, TTF_STYLE_BOLD | TTF_STYLE_UNDERLINE);

/* SizeUTF8 does not give the right dimensions for all hinting */
	if (tui->hint == TTF_HINTING_RGB)
		w++;

	if (w > *dw)
		*dw = w;

	if (h > *dh)
		*dh = h;

/*
 * Flush the  cache so we're not biased or collide with byIndex or byValue
 */
	TTF_Flush_Cache(font);
}

/*
 * supporting mixing truetype and bitmap font rendering costs much
 * more than it is worth, when/if we receive a bitmap font from con,
 * just drop all truetype related resources.
 */
void drop_truetype(struct tui_context* tui)
{
	if (tui->font[0]){
		TTF_CloseFont(tui->font[0]);
		tui->font[0] = NULL;
	}

	if (tui->font_fd[0] != BADFD){
		close(tui->font_fd[0]);
		tui->font_fd[0] = BADFD;
	}

	if (tui->font_fd[1] != BADFD){
		close(tui->font_fd[1]);
		tui->font_fd[1] = BADFD;
	}

	if (tui->font[1]){
		TTF_CloseFont(tui->font[1]);
		tui->font[1] = NULL;
	}

#ifdef HAVE_HARFBUZZ
	if (tui->hb_font){
		hb_font_destroy(tui->hb_font);
		tui->hb_font = NULL;
	}
#endif
}
#endif

/*
 * first try and open/probe the font descriptor as a bitmap font
 * (header-probing is trivial)
 */
bool tryload(struct tui_context* tui, int fd, int mode, size_t px_sz)
{
	int work = dup(fd);
	if (-1 == work)
		return false;

	FILE* fpek = fdopen(work, "r");
	if (!fpek)
		return false;

	fseek(fpek, 0, SEEK_END);
	size_t buf_sz = ftell(fpek);
	fseek(fpek, 0, SEEK_SET);

	uint8_t* buf = malloc(buf_sz);
	if (!buf){
		fclose(fpek);
		return false;
	}

	bool rv = false;
	if (1 == fread(buf, buf_sz, 1, fpek)){
		rv = load_bitmap_font(tui->font_bitmap, buf, buf_sz, px_sz, mode == 1);
	}

	free(buf);
	fclose(fpek);
	return rv;
}

/*
 * modes supported now is 0 (default), 1 (append)
 * font size specified in mm, will be converted to 1/72 inch pt as per
 * the current displayhint density in pixels-per-centimeter.
 */
static bool setup_font(
	struct tui_context* tui, int fd, float font_sz, int mode)
{
	if (!(font_sz > 0))
		font_sz = tui->font_sz;

	size_t pt_size = SHMIF_PT_SIZE(tui->ppcm, font_sz) + tui->font_sz_delta;
	size_t px_sz = ceilf((float)pt_size * 0.03527778 * tui->ppcm);
	if (pt_size < 4)
		pt_size = 4;

	int modeind = mode >= 1 ? 1 : 0;

	bool bmap_font = fd != BADFD ?
		tryload(tui, fd, modeind, px_sz) :
#ifdef SIMPLE_RENDERING
	false
#else
	tui->font[0] == NULL
#endif
	;

/* re-use last descriptor and change size or grab new */
	if (BADFD == fd)
		fd = tui->font_fd[modeind];

	tui->draw_function = draw_monospace;

/* TTF wants in pt, tui-bitmap fonts wants in px. We don't support
 * mixing vector and bitmap fonts though */
	if (
#ifdef SIMPLE_RENDERING
	1 ||
#endif
	bmap_font || tui->force_bitmap){
		size_t w = 0, h = 0;
		switch_bitmap_font(tui->font_bitmap, px_sz, &w, &h);
		tui->cell_w = w;
		tui->cell_h = h;
		update_screensize(tui, false);
		send_cell_sz(tui);
#ifndef SIMPLE_RENDERING
		drop_truetype(tui);
#endif
		return true;
	}

#ifndef SIMPLE_RENDERING
	TTF_Font* font = TTF_OpenFontFD(fd, pt_size, 72.0, 72.0);
	if (!font){
		LOG("failed to open font from descriptor (%d), "
			"with size: %f\n", fd, font_sz);
		return false;
	}

	tui->draw_function = tui->shape_function;
	TTF_SetFontHinting(font, tui->hint);

	size_t w = 0, h = 0;
	static const char* set[] = {
		"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
		"m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "x", "y",
		"z", "!", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
		"M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "X", "Y",
		"Z", "|", "_"
	};

	if (mode == 0){
		tui->font_sz = font_sz;
		for (size_t i = 0; i < sizeof(set)/sizeof(set[0]); i++)
			probe_font(tui, font, set[i], &w, &h);

		if (w && h){
			tui->cell_w = w;
			tui->cell_h = h;
		}

		send_cell_sz(tui);
	}

	TTF_SetFontStyle(font, TTF_STYLE_NORMAL);
	TTF_Font* old_font = tui->font[modeind];

	tui->font[modeind] = font;

#ifdef WITH_HARFBUZZ
	if (modeind == 0){
		if (tui->hb_font){
			hb_font_destroy(tui->hb_font);
			tui->hb_font = NULL;
		}
		tui->hb_font = hb_ft_font_create((FT_Face)TTF_GetFtFace(font), NULL);
	}
#endif

/* internally, TTF_Open dup:s the descriptor, we only keep it here
 * to allow size changes without specifying a new font */
	if (tui->font_fd[modeind] != fd)
		close(tui->font_fd[modeind]);
	tui->font_fd[modeind] = fd;

	if (old_font){
		TTF_CloseFont(old_font);
		update_screensize(tui, false);
	}
	return true;
#else
	return false;
#endif
}

/*
 * get temporary access to the current state of the TUI/context,
 * returned pointer is undefined between calls to process/refresh
 */
struct arcan_shmif_cont* arcan_tui_acon(struct tui_context* c)
{
	if (!c)
		return NULL;

	return &c->acon;
}

size_t arcan_tui_get_handles(
	struct tui_context** contexts, size_t n_contexts,
	int fddst[], size_t fddst_lim)
{
	size_t ret = 0;
	if (!fddst || !contexts)
		return 0;

	for (size_t i = 0; i < n_contexts && ret < fddst_lim; i++){
		if (!contexts[i]->acon.addr)
			continue;

		fddst[ret++] = contexts[i]->acon.epipe;

		if (contexts[i]->clip_in.addr && ret < fddst_lim){
			fddst[ret++] = contexts[i]->clip_in.epipe;
		}
	}

	return ret;
}

struct tui_process_res arcan_tui_process(
	struct tui_context** contexts, size_t n_contexts,
	int* fdset, size_t fdset_sz, int timeout)
{
	struct tui_process_res res = {0};
	uint64_t rdy_mask = 0;

	if (fdset_sz + n_contexts == 0){
		res.errc = TUI_ERRC_BAD_ARG;
		return res;
	}

	if ((n_contexts && !contexts) || (fdset_sz && !fdset)){
		res.errc = TUI_ERRC_BAD_ARG;
		return res;
	}

	if (n_contexts > 32 || fdset_sz > 32){
		res.errc = TUI_ERRC_BAD_ARG;
		return res;
	}

	for (size_t i = 0; i < n_contexts; i++)
		if (!contexts[i]->acon.addr)
			res.bad |= 1 << i;

	if (res.bad){
		res.errc = TUI_ERRC_BAD_ARG;
		return res;
	}

/* From each context, we need the relevant tui->acon.epipe to poll on, along
 * with the entries from the fdset that would require us to mask- populate and
 * return. This structure is not entirely cheap to set up so there might be
 * value in caching it somewhere between runs */
	short pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[fdset_sz + (n_contexts * 2)];
	memset(fds, '\0', sizeof(fds));

/* need to distinguish between types in results and poll doesn't carry tag */
	uint64_t clip_mask = 0;

	size_t ofs = 0;
	for (size_t i = 0; i < n_contexts; i++){
		fds[ofs++] = (struct pollfd){
			.fd = contexts[i]->acon.epipe,
			.events = pollev
		};
		if (contexts[i]->clip_in.vidp){
			clip_mask |= 1 << ofs;
			fds[ofs++] = (struct pollfd){
				.fd = contexts[i]->clip_in.epipe,
				.events = pollev
			};
		}
	}
/* return condition to take responsibility for multiplexing */
	size_t fdset_ofs = ofs;
	for (size_t i = 0; i < fdset_sz; i++){
		fds[ofs++] = (struct pollfd){
			.fd = fdset[i],
			.events = pollev
		};
	}

/* pollset is packed as [n_contexts] [caller-supplied] */
	int sv = poll(fds, ofs, timeout);
	size_t nc = 0;
	for (size_t i = 0; i < fdset_ofs && sv; i++){
		if (fds[i].revents){
			sv--;
			if (clip_mask & (i << 1))
				check_pasteboard(contexts[nc]);
			else {
				event_dispatch(contexts[nc]);
				nc++;
			}
		}
	}

/* sweep second batch. caller supplied descriptor set,
 * mark the ones that are broken or with data */
	for (size_t i = fdset_ofs; i < ofs && sv; i++)
		if (fds[i].revents){
			sv--;
			if (fds[i].revents == POLLIN)
				res.ok |= 1 << (i - fdset_ofs);
			else
				res.bad |= 1 << (i - fdset_ofs);
		}

	return res;
}

int arcan_tui_refresh(struct tui_context* tui)
{
	int rc;
	if (!tui || !tui->acon.addr || (rc = wait_vready(tui, false)) == -1){
		errno = EINVAL;
		return -1;
	}

	if (0 == rc){
		errno = EAGAIN;
		return -1;
	}

/* synch vscreen -> screen buffer */
	tui->flags = tsm_screen_get_flags(tui->screen);

/* if we're more than a full page behind, just reset it */
	if (tui->scroll_backlog){
/* alternate- screenmode requires pattern analysis to generate scroll */
		if (tui->flags & TUI_ALTERNATE){
			tui->scroll_backlog = 0;
			tui->age = tsm_screen_draw(tui->screen, tsm_draw_callback, tui);
		}
		else if (abs(tui->scroll_backlog) < tui->rows){
			apply_scroll(tui);
			errno = EAGAIN;
			return -1;
		}
		else{
			tui->age = tsm_screen_draw(tui->screen, tsm_draw_callback, tui);
			tui->scroll_backlog = 0;
			tui->in_scroll = 0;
		}
	}
	else
		tui->age = tsm_screen_draw(tui->screen, tsm_draw_callback, tui);

	if ((tui->dirty & DIRTY_PENDING) || (tui->dirty & DIRTY_PENDING_FULL))
		update_screen(tui, false);

	if (tui->dirty & DIRTY_UPDATED){
/* if we are built with GPU offloading support and nothing has happened
 * to our accelerated connection, synch, otherwise fallback and retry */
#ifndef SHMIF_TUI_DISABLE_GPU
retry:
	if (tui->is_accel){
		if (-1 == arcan_shmifext_signal(&tui->acon,
			0, SHMIF_SIGVID, SHMIFEXT_BUILTIN)){
				arcan_shmifext_drop(&tui->acon);
				tui->is_accel = false;
			goto retry;
		}
	}
	else
#endif
		arcan_shmif_signal(&tui->acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);

/* set invalid synch region until redraw changes that, the dirty
 * buffer gets copied during signal so no problem there */
		tui->acon.dirty.x1 = tui->acon.w;
		tui->acon.dirty.x2 = 0;
		tui->acon.dirty.y1 = tui->acon.h;
		tui->acon.dirty.y2 = 0;
		tui->fstamp++;
		tui->dirty = DIRTY_NONE;

		return 1;
	}

	return 0;
}

void arcan_tui_invalidate(struct tui_context* tui)
{
	if (!tui)
		return;

	tui->dirty |= DIRTY_PENDING_FULL;
	update_screen(tui, false);
}

void arcan_tui_destroy(struct tui_context* tui, const char* message)
{
	if (!tui)
		return;

	if (tui->clip_in.vidp)
		arcan_shmif_drop(&tui->clip_in);

	if (tui->clip_out.vidp)
		arcan_shmif_drop(&tui->clip_out);

	if (message)
		arcan_shmif_last_words(&tui->acon, message);

	arcan_shmif_drop(&tui->acon);
	tsm_utf8_mach_free(tui->ucsconv);
#ifndef SIMPLE_RENDERING
	drop_truetype(tui);
#endif
	drop_font_context(tui->font_bitmap);

	free(tui->base);

	for (size_t i = 0; i < 32; i++)
		if (tui->screens[i])
			tsm_screen_unref(tui->screens[i]);

	memset(tui, '\0', sizeof(struct tui_context));
	free(tui);
}

void arcan_tui_wndhint(struct tui_context* wnd,
	struct tui_context* par, int anch_row, int anch_col, int wndflags)
{
/* FIXME: translate and apply hints */
}

arcan_tui_conn* arcan_tui_open_display(const char* title, const char* ident)
{
	struct arcan_shmif_cont* res = malloc(sizeof(struct arcan_shmif_cont));
	if (!res)
		return NULL;

	struct shmif_open_ext args = {.type = SEGID_TUI };

	*res = arcan_shmif_open_ext(
		SHMIF_ACQUIRE_FATALFAIL, NULL, (struct shmif_open_ext){
			.type = SEGID_TUI,
			.title = title,
			.ident = ident,
		}, sizeof(struct shmif_open_ext)
	);

	if (!res->addr){
		free(res);
		return NULL;
	}

/* to separate a tui_open_display call from a shmif-context that is
 * retrieved from another setting, we tag the user field to know it is
 * safe to free */
	res->user = (void*) 0xfeedface;
	return res;
}

#ifdef WITH_HARFBUZZ
static bool harfbuzz_substitute(struct tui_context* tui,
	struct tui_cell* cells, size_t n_cells, size_t row, void* t)
{
	if (!tui->hb_font)
		return false;

/*
 * we'll eventually need a more refined version of this, possible
 * taking the GEOHINTS into account, or tracking it as a property
 * per row or so.
 */
	uint32_t inch[n_cells];
	uint32_t acc = 0;
	for (size_t i = 0; i < n_cells; i++){
		inch[i] = cells[i].ch;
		acc |= cells[i].ch;
	}

/* just empty row */
	if (!acc)
		return false;

	hb_buffer_t* buf = hb_buffer_create();
	hb_buffer_set_unicode_funcs(buf, hb_icu_get_unicode_funcs());
	hb_buffer_set_direction(buf, HB_DIRECTION_LTR);
	hb_buffer_set_script(buf, HB_SCRIPT_LATIN);
	hb_buffer_set_language(buf, hb_language_from_string("en", 2));
	hb_buffer_add_utf32(buf, inch, n_cells, 0, n_cells);
	hb_buffer_guess_segment_properties(buf);
	hb_buffer_set_replacement_codepoint(buf, 0);

/* NULL, 0 == features */
	hb_shape(tui->hb_font, buf, NULL, 0);

	unsigned glyphc;
	hb_glyph_info_t* ginfo = hb_buffer_get_glyph_infos(buf, &glyphc);

/* Note:
 * codepoint is in the namespace of the font!
 * mask can indicate if HB_GLYPH_FLAG_UNSAFE_TO_BREAK
 *
 * if kerning is enabled, also get the glyph_positions and apply
 * to the xofs/real_w per cell */
	bool changed = false;
	for (size_t i = 0; i < glyphc && i < n_cells; i++){
		if (cells[i].ch && cells[i].draw_ch != ginfo[i].codepoint){

/*
			printf("code point mutated: ind:%zu orig:%"PRIu32"new:%"PRIu32"\n", i,
				cells[i].ch, ginfo[i].codepoint);
 */
			cells[i].draw_ch = ginfo[i].codepoint;

			changed = true;
		}
	}

/*
 * Note: there seem to be some drawing issue with -> --> etc. anywhere
 * whileas <- substitute correctly
 */

	hb_buffer_destroy(buf);
	return changed;
}
#endif

static int parse_color(const char* inv, uint8_t outv[4])
{
	return sscanf(inv, "%"SCNu8",%"SCNu8",%"SCNu8",%"SCNu8,
		&outv[0], &outv[1], &outv[2], &outv[3]);
}

static void apply_arg(struct tui_settings* cfg,
	struct arg_arr* args, struct tui_context* src)
{
/* FIXME: if src is set, copy settings from there (and dup descriptors) */
	if (!args)
		return;

	const char* val;
	uint8_t ccol[4] = {0x00, 0x00, 0x00, 0xff};
	long vbufv = 0;

	if (arg_lookup(args, "fgc", 0, &val) && val)
		if (parse_color(val, ccol) >= 3){
			cfg->fgc[0] = ccol[0]; cfg->fgc[1] = ccol[1]; cfg->fgc[2] = ccol[2];
		}

	if (arg_lookup(args, "dblbuf", 0, &val)){
		cfg->render_flags |= TUI_RENDER_DBLBUF;
	}

	if (arg_lookup(args, "shape", 0, &val)){
		cfg->render_flags |= TUI_RENDER_SHAPED;
	}

#ifndef SHMIF_TUI_DISABLE_GPU
	if (arg_lookup(args, "accel", 0, &val))
		cfg->render_flags |= TUI_RENDER_ACCEL;
#endif

	if (arg_lookup(args, "scroll", 0, &val) && val)
		cfg->smooth_scroll = strtoul(val, NULL, 10);

#ifdef WITH_HARFBUZZ
	if (arg_lookup(args, "substitute", 0, &val) && !src){
		enable_harfbuzz = true;
	}
#endif

	if (arg_lookup(args, "bgc", 0, &val) && val)
		if (parse_color(val, ccol) >= 3){
			cfg->bgc[0] = ccol[0]; cfg->bgc[1] = ccol[1]; cfg->bgc[2] = ccol[2];
		}

	if (arg_lookup(args, "cc", 0, &val) && val)
		if (parse_color(val, ccol) >= 3){
			cfg->cc[0] = ccol[0]; cfg->cc[1] = ccol[1]; cfg->cc[2] = ccol[2];
		}

	if (arg_lookup(args, "clc", 0, &val) && val)
		if (parse_color(val, ccol) >= 3){
			cfg->clc[0] = ccol[0]; cfg->clc[1] = ccol[1]; cfg->clc[2] = ccol[2];
		}

	if (arg_lookup(args, "blink", 0, &val) && val){
		cfg->cursor_period = strtol(val, NULL, 10);
	}

	if (arg_lookup(args, "cursor", 0, &val) && val){
		const char** cur = curslbl;
		while(*cur){
			if (strcmp(*cur, val) == 0){
				cfg->cursor = (cur - curslbl);
				break;
			}
			cur++;
		}
	}

	if (arg_lookup(args, "bgalpha", 0, &val) && val)
		cfg->alpha = strtoul(val, NULL, 10);
	if (arg_lookup(args, "ppcm", 0, &val) && val){
		float ppcm = strtof(val, NULL);
		if (isfinite(ppcm) && ppcm > ARCAN_SHMPAGE_DEFAULT_PPCM * 0.5)
			cfg->ppcm = ppcm;
	}

	if (arg_lookup(args, "force_bitmap", 0, &val))
		cfg->render_flags |= TUI_RENDER_BITMAP;
}

int arcan_tui_alloc_screen(struct tui_context* ctx)
{
	int ind = ffs(~ctx->screen_alloc);
	if (0 == ind)
		return -1;

	if (0 != tsm_screen_new(&ctx->screens[ind], tsm_log, ctx))
		return -1;

	uint8_t* fg = ctx->colors[TUI_COL_TEXT].rgb;
	uint8_t* bg = ctx->colors[TUI_COL_BG].rgb;

	tsm_screen_set_def_attr(ctx->screens[ind],
		&(struct tui_screen_attr){
			.fr = fg[0], .fg = fg[1], .fb = fg[2],
			.br = bg[0], .bg = bg[1], .bb = bg[2]
	});

	ctx->screen_alloc |= 1 << ind;
	return ind;
}

struct tui_settings arcan_tui_defaults(
	arcan_tui_conn* conn, struct tui_context* ref)
{
	struct tui_settings res = {
		.cell_w = 8,
		.cell_h = 8,
		.alpha = 0xff,
		.bgc = {0x00, 0x00, 0x00},
		.fgc = {0xff, 0xff, 0xff},
		.cc = {0x00, 0xaa, 0x00},
		.clc = {0xaa, 0xaa, 0x00},
		.ppcm = ARCAN_SHMPAGE_DEFAULT_PPCM,
		.hint = 0,
		.mouse_fwd = true,
		.cursor_period = 12,
		.font_sz = 0.0416
	};

	apply_arg(&res, arcan_shmif_args(conn), ref);

	if (ref){
		res.cell_w = ref->cell_w;
		res.cell_h = ref->cell_h;
		res.alpha = ref->alpha;
		res.font_sz = ref->font_sz;
		res.hint = ref->hint;
		res.cursor_period = ref->cursor_period;
		res.render_flags = ref->render_flags;
		res.ppcm = ref->ppcm;
	}
	return res;
}

void arcan_tui_get_color(
	struct tui_context* tui, int group, uint8_t rgb[3])
{
	if (group <= TUI_COL_INACTIVE && group >= TUI_COL_PRIMARY){
		memcpy(rgb, tui->colors[group].rgb, 3);
	}
}

void arcan_tui_set_color(
	struct tui_context* tui, int group, uint8_t rgb[3])
{
	if (group <= TUI_COL_INACTIVE && group >= TUI_COL_PRIMARY){
		memcpy(tui->colors[group].rgb, rgb, 3);
	}
}

void arcan_tui_update_handlers(
	struct tui_context* tui, const struct tui_cbcfg* cbs, size_t cbs_sz)
{
	if (!tui || !cbs || cbs_sz > sizeof(struct tui_cbcfg))
		return;

	memcpy(&tui->handlers, cbs, cbs_sz);
}

bool arcan_tui_switch_screen(struct tui_context* ctx, unsigned ind)
{
	if (ind > 31 || !(ctx->screen_alloc & (1 << ind)))
		return false;

	if (ctx->screens[ind] == ctx->screen)
		return true;

	ctx->dirty |= DIRTY_PENDING_FULL;
	ctx->screen = ctx->screens[ind];
	ctx->age = 0;
	ctx->age = tsm_screen_draw(ctx->screen, tsm_draw_callback, ctx);

	return true;
}

bool arcan_tui_delete_screen(struct tui_context* ctx, unsigned ind)
{
	if (ind > 31 || !(ctx->screen_alloc & (1 << ind) || ind == 0))
		return false;

	if (ctx->screen == ctx->screens[ind])
		arcan_tui_switch_screen(ctx, 0);

	ctx->screen_alloc &= ~(1 << ind);
	tsm_screen_unref(ctx->screens[ind]);
	ctx->screens[ind] = NULL;

	return true;
}

/*
 * though we are supposed to be prerolled the colors from our display
 * server connection, it's best to have something that gets activated
 * initially regardless..
 */
static void set_builtin_palette(struct tui_context* ctx)
{
	ctx->colors[TUI_COL_CURSOR] = (struct color){0x00, 0xff, 0x00};
	ctx->colors[TUI_COL_ALTCURSOR] = (struct color){0x00, 0xff, 0x00};
	ctx->colors[TUI_COL_HIGHLIGHT] = (struct color){0x26, 0x8b, 0xd2};
	ctx->colors[TUI_COL_BG] = (struct color){0x2b, 0x2b, 0x2b};
	ctx->colors[TUI_COL_PRIMARY] = (struct color){0x13, 0x13, 0x13};
	ctx->colors[TUI_COL_SECONDARY] = (struct color){0x42, 0x40, 0x3b};
	ctx->colors[TUI_COL_TEXT] = (struct color){0xff, 0xff, 0xff};
	ctx->colors[TUI_COL_LABEL] = (struct color){0x44, 0x44, 0x44};
	ctx->colors[TUI_COL_WARNING] = (struct color){0xaa, 0xaa, 0x00};
	ctx->colors[TUI_COL_ERROR] = (struct color){0xaa, 0x00, 0x00};
	ctx->colors[TUI_COL_ALERT] = (struct color){0xaa, 0x00, 0xaa};
	ctx->colors[TUI_COL_REFERENCE] = (struct color){0x20, 0x30, 0x20};
	ctx->colors[TUI_COL_INACTIVE] = (struct color){0x20, 0x20, 0x20};
}

uint32_t arcan_tui_screens(struct tui_context* ctx)
{
	return ctx->screen_alloc;
}

struct tui_context* arcan_tui_setup(struct arcan_shmif_cont* con,
	const struct tui_settings* set, const struct tui_cbcfg* cbs,
	size_t cbs_sz, ...)
{
	if (!set || !con || !cbs)
		return NULL;

	struct tui_context* res = malloc(sizeof(struct tui_context));
	if (!res)
		return NULL;
	*res = (struct tui_context){};

/*
 * if the connection comes from _open_display, free the intermediate
 * context store here and move it to our tui context
 */
	bool managed = (uintptr_t)con->user == 0xfeedface;
	res->acon = *con;
	if (managed)
		free(con);

/*
 * only in a managed context can we retrieve the initial state truthfully,
 * for subsegments the values are derived from parent via the defaults stage.
 */
	struct arcan_shmif_initial* init = NULL;
	if (sizeof(struct arcan_shmif_initial) != arcan_shmif_initial(con, &init)
		&& managed){
		LOG("initial structure size mismatch, out-of-synch header/shmif lib\n");
		arcan_shmif_drop(&res->acon);
		free(res);
		return NULL;
	}

	if (tsm_screen_new(&res->screen, tsm_log, res) < 0){
		LOG("failed to build screen structure\n");
		if (managed)
			arcan_shmif_drop(&res->acon);
		free(res);
		return NULL;
	}

/*
 * due to handlers being default NULL, all fields are void* / fptr*
 * (and we assume sizeof(void*) == sizeof(fptr*) which is somewhat
 * sketchy, but if that's a concern, subtract the offset of tag),
 * and we force the caller to provide its perceived size of the
 * struct we can expand the interface without breaking old clients
 */
	if (cbs_sz > sizeof(struct tui_cbcfg) || cbs_sz % sizeof(void*) != 0){
		LOG("arcan_tui(), caller provided bad size field\n");
		return NULL;
	}
	memcpy(&res->handlers, cbs, cbs_sz);
#ifdef WITH_HARFBUZZ
	if (!cbs->substitute && enable_harfbuzz)
		res->handlers.substitute = harfbuzz_substitute;
#endif

	if (init){
		res->ppcm = init->density;
	}
	else
		res->ppcm = set->ppcm;
	res->focus = true;
	res->smooth_scroll = set->smooth_scroll;
	res->smooth_thresh = 4;

	res->font_fd[0] = BADFD;
	res->font_fd[1] = BADFD;
	res->font_sz = set->font_sz;
	res->font_bitmap = tui_draw_init(64);
	res->alpha = set->alpha;
	res->cell_w = set->cell_w;
	res->cell_h = set->cell_h;
	set_builtin_palette(res);
	memcpy(res->colors[TUI_COL_CURSOR].rgb, set->cc, 3);
	memcpy(res->colors[TUI_COL_ALTCURSOR].rgb, set->clc, 3);
	memcpy(res->colors[TUI_COL_BG].rgb, set->bgc, 3);
	memcpy(res->colors[TUI_COL_TEXT].rgb, set->fgc, 3);
	res->hint = set->hint;
	res->mouse_forward = set->mouse_fwd;
	res->cursor_period = set->cursor_period;
	res->acon.hints = SHMIF_RHINT_SUBREGION;
	res->cursor = set->cursor;
	res->render_flags = set->render_flags;
	res->force_bitmap = (set->render_flags & TUI_RENDER_BITMAP) != 0;
	res->dbl_buf = (set->render_flags & TUI_RENDER_DBLBUF);
	res->shape_function = (set->render_flags & TUI_RENDER_SHAPED) ?
#ifndef SIMPLE_RENDERING
		draw_shaped
#else
		draw_monospace
#endif
		: draw_monospace;

	if (init && init->fonts[0].fd != BADFD){
		res->hint = init->fonts[0].hinting;
		res->font_sz = init->fonts[0].size_mm;
		setup_font(res, init->fonts[0].fd, res->font_sz, 0);
		init->fonts[0].fd = BADFD;
		LOG("arcan_tui(), built-in font provided, size: %f\n", res->font_sz);

		if (init->fonts[1].fd != BADFD){
			setup_font(res, init->fonts[1].fd, res->font_sz, 1);
			init->fonts[1].fd = BADFD;
		}
	}
	else if (init->fonts[0].size_mm > 0){
		res->font_sz = init->fonts[0].size_mm;
		setup_font(res, BADFD, res->font_sz, 0);
	}
	else
		setup_font(res, BADFD, res->font_sz, 0);

	if (0 != tsm_utf8_mach_new(&res->ucsconv)){
		free(res);
		return NULL;
	}

	expose_labels(res);
	tsm_screen_set_def_attr(res->screen,
		&(struct tui_screen_attr){
			.fr = res->colors[TUI_COL_TEXT].rgb[0],
			.fg = res->colors[TUI_COL_TEXT].rgb[1],
			.fb = res->colors[TUI_COL_TEXT].rgb[2],
			.br = res->colors[TUI_COL_BG].rgb[0],
			.bg = res->colors[TUI_COL_BG].rgb[1],
			.bb = res->colors[TUI_COL_BG].rgb[2]
		}
	);
	tsm_screen_set_max_sb(res->screen, 1000);

/* clipboard, timer callbacks, no IDENT */
	queue_requests(res, true, false);

/* show the current cell dimensions to help limit resize requests */
	send_cell_sz(res);

	update_screensize(res, true);
	if (res->handlers.resized)
		res->handlers.resized(res, res->acon.w, res->acon.h,
			res->cols, res->rows, res->handlers.tag);

#ifndef SHMIF_TUI_DISABLE_GPU
	if (set->render_flags & TUI_RENDER_ACCEL){
		struct arcan_shmifext_setup setup = arcan_shmifext_defaults(con);
		setup.builtin_fbo = false;
		setup.vidp_pack = true;
		if (arcan_shmifext_setup(con, setup) == SHMIFEXT_OK){
			LOG("arcan_tui(), accelerated connection established");
			res->is_accel = true;
		}
	}
#endif

	return res;
}

/*
 * context- unwrap to screen and forward to tsm_screen
 */
void arcan_tui_erase_screen(struct tui_context* c, bool protect)
{
	if (!c)
		return;

	tsm_screen_erase_screen(c->screen, protect);
}

void arcan_tui_erase_region(struct tui_context* c,
	size_t x1, size_t y1, size_t x2, size_t y2, bool protect)
{
	if (!c)
		return;

	tsm_screen_erase_region(c->screen, x1, y1, x2, y2, protect);
}

void arcan_tui_erase_sb(struct tui_context* c)
{
	if (!c)
		tsm_screen_clear_sb(c->screen);
}

void arcan_tui_scrollhint(
	struct tui_context* c, size_t n_regions, struct tui_region* regions)
{
/*
 * FIXME: immature / incorrect
	c->scroll_backlog = steps;
	flag_cursor(c);
 */
}

void arcan_tui_refinc(struct tui_context* c)
{
	if (c)
	tsm_screen_ref(c->screen);
}

void arcan_tui_refdec(struct tui_context* c)
{
	if (c)
	tsm_screen_unref(c->screen);
}

struct tui_screen_attr
	arcan_tui_defattr(struct tui_context* c, struct tui_screen_attr* attr)
{
	if (!c)
		return (struct tui_screen_attr){};

	if (attr)
		tsm_screen_set_def_attr(c->screen, (struct tui_screen_attr*) attr);

	return tsm_screen_get_def_attr(c->screen);
}

void arcan_tui_write(struct tui_context* c, uint32_t ucode,
	struct tui_screen_attr* attr)
{
	if (!c)
		return;

	int ss = tsm_screen_write(c->screen, ucode, attr);
	if (c->smooth_scroll && ss){
		c->scroll_backlog += ss;
	}

	flag_cursor(c);
}

void arcan_tui_ident(struct tui_context* c, const char* ident)
{
	arcan_event nev = {
		.ext.kind = ARCAN_EVENT(IDENT)
	};

	size_t lim = sizeof(nev.ext.message.data)/sizeof(nev.ext.message.data[1]);
	snprintf((char*)nev.ext.message.data, lim, "%s", ident);

	if (memcmp(&c->last_ident, &nev, sizeof(arcan_event)) != 0)
		arcan_shmif_enqueue(&c->acon, &nev);
	c->last_ident = nev;
}

bool arcan_tui_writeu8(struct tui_context* c,
	const uint8_t* u8, size_t len, struct tui_screen_attr* attr)
{
	if (!(c && u8 && len > 0))
		return false;

	for (size_t i = 0; i < len; i++){
		int state = tsm_utf8_mach_feed(c->ucsconv, u8[i]);
		if (state == TSM_UTF8_ACCEPT || state == TSM_UTF8_REJECT){
			uint32_t ucs4 = tsm_utf8_mach_get(c->ucsconv);
			arcan_tui_write(c, ucs4, attr);
		}
	}
	return true;
}

bool arcan_tui_writestr(struct tui_context* c,
	const char* str, struct tui_screen_attr* attr)
{
	size_t len = strlen(str);
	return arcan_tui_writeu8(c, (const uint8_t*) str, len, attr);
}

void arcan_tui_cursorpos(struct tui_context* c, size_t* x, size_t* y)
{
	if (!c)
		return;

	if (x)
		*x = tsm_screen_get_cursor_x(c->screen);

	if (y)
		*y = tsm_screen_get_cursor_y(c->screen);
}

void arcan_tui_reset(struct tui_context* c)
{
	if (c){
		tsm_utf8_mach_reset(c->ucsconv);
		tsm_screen_reset(c->screen);
		flag_cursor(c);
	}
}

void arcan_tui_dimensions(struct tui_context* c, size_t* rows, size_t* cols)
{
	if (rows)
		*rows = c->rows;

	if (cols)
		*cols = c->cols;
}

void arcan_tui_erase_cursor_to_screen(struct tui_context* c, bool protect)
{
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_cursor_to_screen(c->screen, protect);
	}
}

void arcan_tui_erase_screen_to_cursor(struct tui_context* c, bool protect)
{
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_screen_to_cursor(c->screen, protect);
	}
}

void arcan_tui_erase_cursor_to_end(struct tui_context* c, bool protect)
{
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_cursor_to_end(c->screen, protect);
	}
}

void arcan_tui_erase_home_to_cursor(struct tui_context* c, bool protect)
{
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_home_to_cursor(c->screen, protect);
	}
}

void arcan_tui_erase_current_line(struct tui_context* c, bool protect)
{
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_current_line(c->screen, protect);
	}
}

void arcan_tui_erase_chars(struct tui_context* c, size_t num)
{
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_chars(c->screen, num);
	}
}

int arcan_tui_set_flags(struct tui_context* c, int flags)
{
	if (!c)
		return -1;

	bool oldv = c->cursor_hard_off;
	c->cursor_hard_off = flags & TUI_HIDE_CURSOR;
	if (oldv != c->cursor_hard_off)
		flag_cursor(c);

	tsm_screen_set_flags(c->screen, flags);
	c->flags = tsm_screen_get_flags(c->screen);

	if (c->flags & TUI_ALTERNATE)
		tsm_screen_sb_reset(c->screen);

	return (int) c->flags;
}

void arcan_tui_reset_flags(struct tui_context* c, int flags)
{
	if (c){
		if (flags & TUI_HIDE_CURSOR){
			c->cursor_hard_off = false;
			flag_cursor(c);
		}
		tsm_screen_reset_flags(c->screen, flags);
	}
}

void arcan_tui_set_tabstop(struct tui_context* c)
{
	if (c)
	tsm_screen_set_tabstop(c->screen);
}

void arcan_tui_insert_lines(struct tui_context* c, size_t n)
{
	if (c){
		tsm_screen_insert_lines(c->screen, n);
		flag_cursor(c);
	}
}

void arcan_tui_delete_lines(struct tui_context* c, size_t n)
{
	if (c)
	tsm_screen_delete_lines(c->screen, n);
}

void arcan_tui_insert_chars(struct tui_context* c, size_t n)
{
	if (c){
		flag_cursor(c);
		tsm_screen_insert_chars(c->screen, n);
	}
}

void arcan_tui_delete_chars(struct tui_context* c, size_t n)
{
	if (c){
		flag_cursor(c);
		tsm_screen_delete_chars(c->screen, n);
	}
}

void arcan_tui_tab_right(struct tui_context* c, size_t n)
{
	if (c){
		tsm_screen_tab_right(c->screen, n);
		flag_cursor(c);
	}
}

void arcan_tui_tab_left(struct tui_context* c, size_t n)
{
	if (c){
		flag_cursor(c);
		tsm_screen_tab_left(c->screen, n);
	}
}

void arcan_tui_scroll_up(struct tui_context* c, size_t n)
{
	if (!c || (c->flags & TUI_ALTERNATE))
		return;

	int ss = tsm_screen_sb_up(c->screen, n);
	if (c->smooth_scroll && ss)
		c->scroll_backlog += ss;

	flag_cursor(c);
}

void arcan_tui_scroll_down(struct tui_context* c, size_t n)
{
	if (!c || (c->flags & TUI_ALTERNATE))
		return;

	int ss = tsm_screen_sb_down(c->screen, n);
	if (c->smooth_scroll && ss)
		c->scroll_backlog += ss;

	flag_cursor(c);
}

void arcan_tui_reset_tabstop(struct tui_context* c)
{
	if (c)
	tsm_screen_reset_tabstop(c->screen);
}

void arcan_tui_reset_all_tabstops(struct tui_context* c)
{
	if (c)
	tsm_screen_reset_all_tabstops(c->screen);
}

void arcan_tui_move_to(struct tui_context* c, size_t x, size_t y)
{
	if (c){
		flag_cursor(c);
		tsm_screen_move_to(c->screen, x, y);
	}
}

void arcan_tui_move_up(struct tui_context* c, size_t n, bool scroll)
{
	if (c){
		flag_cursor(c);
		tsm_screen_move_up(c->screen, n, scroll);
	}
}

void arcan_tui_move_down(struct tui_context* c, size_t n, bool scroll)
{
	if (!c)
		return;

	flag_cursor(c);
	int ss = tsm_screen_move_down(c->screen, n, scroll);
	if (c->smooth_scroll){
		if (c->sbofs != 0){
			c->in_scroll = c->sbofs = 0;
			c->scroll_backlog = 0;
			c->cursor_off = false;
			c->cursor_upd = true;
		}
		c->scroll_backlog += ss;
	}
	flag_cursor(c);
}

void arcan_tui_move_left(struct tui_context* c, size_t n)
{
	if (c){
		flag_cursor(c);
		tsm_screen_move_left(c->screen, n);
	}
}

void arcan_tui_move_right(struct tui_context* c, size_t n)
{
	if (c){
		flag_cursor(c);
		tsm_screen_move_right(c->screen, n);
	}
}

void arcan_tui_move_line_end(struct tui_context* c)
{
	if (c){
		flag_cursor(c);
		tsm_screen_move_line_end(c->screen);
	}
}

void arcan_tui_move_line_home(struct tui_context* c)
{
	if (c){
		flag_cursor(c);
		tsm_screen_move_line_home(c->screen);
	}
}

void arcan_tui_newline(struct tui_context* c)
{
	if (!c)
		return;

	int ss = tsm_screen_newline(c->screen);
	if (c->smooth_scroll){
		c->scroll_backlog += ss;
	}

	flag_cursor(c);
}

int arcan_tui_set_margins(struct tui_context* c, size_t top, size_t bottom)
{
	if (c)
		return tsm_screen_set_margins(c->screen, top, bottom);
	return -EINVAL;
}
