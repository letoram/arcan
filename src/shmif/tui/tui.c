/*
 * Copyright 2014-2017, Björn Ståhl
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
#include "../arcan_shmif_tui.h"
#include "../arcan_shmif_tuisym.h"

/*
 * Dislike this sort of feature enable/disable, but the dependency and extra
 * considerations from shaped text versus normal bitblt is worth it.
 */
#ifndef SIMPLE_RENDERING
#include "arcan_ttf.h"
#endif

#include "libtsm.h"
#include "libtsm_int.h"
#include "tui_draw.h"

enum dirty_state {
	DIRTY_NONE = 0,
	DIRTY_UPDATED = 1,
	DIRTY_PENDING = 2,
	DIRTY_PENDING_FULL = 4
};

struct tui_cell {
	uint32_t ch;
	struct tui_screen_attr attr;

#ifndef SIMPLE_RENDERING
/* for performing picking when we have shaped rendering etc. */
	uint16_t cell_ofs;
#endif
};

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

	unsigned flags;
	bool focus, inactive;
	int inact_timer;

#ifndef SHMIF_TUI_DISABLE_GPU
	bool is_accel;
#endif

/* font rendering / tracking - we support one main that defines cell size
 * and one secondary that can be used for alternative glyphs */
#ifndef SIMPLE_RENDERING
	TTF_Font* font[2];
#endif
	struct tui_font_ctx* font_bitmap;
	bool force_bitmap;
	float font_sz; /* size in mm */
	int font_sz_delta; /* user requested step, pt */
	int hint;
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
	bool got_custom; /* track if we have any on-screen dynamic cells */

	uint8_t fgc[3], bgc[3], clc[3];

	uint8_t cc[3]; /* cursor color */
	int cursor_x, cursor_y; /* last cached position */
	bool cursor_off; /* current blink state */
	bool cursor_hard_off; /* user / state toggle */
	bool cursor_upd; /* invalidation, need to draw- old / new */
	long cursor_period; /* blink setting */
	enum tui_cursors cursor; /* visual style */

	uint8_t alpha;

/* track last time counter we did update on to avoid overdraw */
	tsm_age_t age;

/* upstream connection */
	struct arcan_shmif_cont acon;
	struct arcan_shmif_cont clip_in;
	struct arcan_shmif_cont clip_out;
	struct arcan_event last_ident;

/* caller- event handlers */
	struct tui_cbcfg handlers;
};

/* additional state synch that needs negotiation and may need to be
 * re-built in the event of a RESET request */
static void queue_requests(struct tui_context* tui, bool clipboard, bool ident);

/*
 * main character drawing / blitting function,
 * only called when updating cursor or as part of update_screen
 */
static int draw_cbt(struct tui_context* tui,
	uint32_t ch, unsigned row, unsigned col,
	int xofs, int yofs, unsigned w, unsigned h,
	const struct tui_screen_attr* attr,
	bool empty
);

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

static void cursor_at(struct tui_context* tui, int x, int y, shmif_pixel ccol)
{
	shmif_pixel* dst = tui->acon.vidp;

	if (tui->cursor_hard_off || tui->cursor_off || tui->cursor != CURSOR_BLOCK){
		struct tui_cell* tc = &tui->back[tui->cursor_y * tui->cols + tui->cursor_x];

		draw_cbt(tui, tc->ch, tui->cursor_y, tui->cursor_x, 0, 0,
			tui->cell_w, tui->cell_h, &tc->attr, false);
	}
	if (tui->cursor_off || tui->cursor_hard_off)
		return;

	switch (tui->cursor){
	case CURSOR_BLOCK:
		draw_box(&tui->acon, x, y, tui->cell_w, tui->cell_h, ccol);
	break;
	case CURSOR_HALFBLOCK:
		draw_box(&tui->acon, x, y, tui->cell_w >> 1, tui->cell_h, ccol);
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
static void draw_ch(struct tui_context* tui,
	uint32_t ch, int base_x, int base_y, uint8_t fg[4], uint8_t bg[4],
	const struct tui_screen_attr* attr)
{
	int prem = TTF_STYLE_NORMAL;
	prem |= TTF_STYLE_ITALIC * attr->italic;
	prem |= TTF_STYLE_BOLD * attr->bold;

/*
 * Should really maintain a glyph-cache here as well, using
 * ch + selected parts of attr as index and invalidate in the
 * normal font update functions
 */
	draw_box(&tui->acon, base_x, base_y, tui->cell_w, tui->cell_h,
			SHMIF_RGBA(bg[0], bg[1], bg[2], bg[3]));

/* This one is incredibly costly as a deviation in style regarding
 * bold/italic can invalidate the glyph-cache. Ideally, this should
 * be sorted in tsm_screen */
	TTF_SetFontStyle(tui->font[0], prem);
	unsigned xs = 0, ind = 0;
	int adv = 0;

	if (!TTF_RenderUNICODEglyph(
		&tui->acon.vidp[base_y * tui->acon.pitch + base_x],
		tui->cell_w, tui->cell_h, tui->acon.pitch,
		tui->font, tui->font[1] ? 2 : 1,
		ch, &xs, fg, bg, true, false, prem, &adv, &ind
	)){
	}

	apply_attrs(tui, base_x, base_y, fg, attr);
}
#endif

static inline void flag_cursor(struct tui_context* c)
{
	c->cursor_upd = true;
	c->dirty = DIRTY_PENDING;
}

static void send_cell_sz(struct tui_context* tui)
{
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE),
	};

	sprintf((char*)ev.ext.message.data, "cell_w:%d:cell_h:%d",
		tui->cell_w, tui->cell_h);
	arcan_shmif_enqueue(&tui->acon, &ev);
}

static int tsm_draw_callback(struct tsm_screen* screen, uint32_t id,
	const uint32_t* ch, size_t len, unsigned width, unsigned x, unsigned y,
	const struct tui_screen_attr* attr, tsm_age_t age, void* data)
{
	struct tui_context* tui = data;

	if (!(age && tui->age && age <= tui->age)){
		size_t pos = y * tui->cols + x;
		tui->front[pos].ch = *ch;
		tui->front[pos].attr = *attr;
		tui->dirty |= DIRTY_PENDING;
	}

	return 0;
}

static int draw_cbt(struct tui_context* tui,
	uint32_t ch, unsigned row, unsigned col,
	int xofs, int yofs, unsigned w, unsigned h,
	const struct tui_screen_attr* attr,
	bool empty
){
	uint8_t fgc[4] = {attr->fr, attr->fg, attr->fb, 255};
	uint8_t bgc[4] = {attr->br, attr->bg, attr->bb, tui->alpha};
	uint8_t* dfg = fgc, (* dbg) = bgc;
	int y1 = row * tui->cell_h + xofs;
	int x1 = col * tui->cell_w + yofs;

	if (col >= tui->cols || row >= tui->rows || x1 < 0 || y1 < 0)
		return 0;

	if (attr->inverse){
		dfg = bgc;
		dbg = fgc;
		dbg[3] = tui->alpha;
		dfg[3] = 0xff;
	}

	if (attr->faint){
		fgc[0] >>= 1; fgc[1] >>= 1; fgc[2] >>= 1;
		bgc[0] >>= 1; bgc[1] >>= 1; bgc[2] >>= 1;
	}

	int x2 = x1 + w;
	int y2 = y1 + h;

/* update dirty rectangle for synchronization */
	if (x1 < tui->acon.dirty.x1)
		tui->acon.dirty.x1 = x1;
	if (x2 > tui->acon.dirty.x2)
		tui->acon.dirty.x2 = x2;
	if (y1 < tui->acon.dirty.y1)
		tui->acon.dirty.y1 = y1;
	if (y2 > tui->acon.dirty.y2)
		tui->acon.dirty.y2 = y2;

	tui->dirty |= DIRTY_UPDATED;

/* Quick erase if nothing more is needed. There should really be better palette
 * management here to account for an inverse- palette instead */
	if (empty){
		if (attr->inverse){
			draw_box(&tui->acon, x1, y1, tui->cell_w, tui->cell_h,
				SHMIF_RGBA(fgc[0], fgc[1], fgc[2], tui->alpha));
			apply_attrs(tui, x1, y1, bgc, attr);
		}
		else{
			draw_box(&tui->acon, x1, y1, tui->cell_w, tui->cell_h,
				SHMIF_RGBA(bgc[0], bgc[1], bgc[2], tui->alpha));
			apply_attrs(tui, x1, y1, fgc, attr);
		}

		ch = 0x00000008;
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
			SHMIF_RGBA(dbg[0], dbg[1], dbg[2], dbg[3])
		);
	}
#ifndef SIMPLE_RENDERING
	else
		draw_ch(tui, ch, x1, y1, dfg, dbg, attr);
#endif

	return 0;
}

/*
 * return true of [a] and [b] have the same members. custom_id is
 * excluded from this comparison as those should always be treated
 * separately
 */
static bool cell_match(struct tui_cell* ac, struct tui_cell* bc)
{
	struct tui_screen_attr* a = &ac->attr;
	struct tui_screen_attr* b = &bc->attr;
	return (
		ac->ch == bc->ch &&
		a->fr == b->fr &&
		a->fg == b->fg &&
		a->fb == b->fb &&
		a->br == b->br &&
		a->bg == b->bg &&
		a->bb == b->bb &&
		a->bold == b->bold &&
		a->underline == b->underline &&
		a->italic == b->italic &&
		a->inverse == b->inverse &&
		a->protect == b->protect &&
		a->blink == b->blink &&
		a->faint == b->faint &&
		a->strikethrough == b->strikethrough
	);
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

/* only blink cursor if its state has actually changed, since it can
 * grow the invalidation region rather heavily */
	if (tui->cursor_upd){
		struct tui_cell* tc = &tui->back[tui->cursor_y * tui->cols + tui->cursor_x];
		draw_cbt(tui, tc->ch, tui->cursor_y, tui->cursor_x, 0, 0,
			tui->cell_w, tui->cell_h, &tc->attr, false);
	}
	tui->cursor_x = tsm_screen_get_cursor_x(tui->screen);
	tui->cursor_y = tsm_screen_get_cursor_y(tui->screen);

/* dirty will be set from screen draw */
	if (tui->dirty & DIRTY_PENDING_FULL){
		tui->acon.dirty.x1 = 0;
		tui->acon.dirty.x2 = tui->acon.w;
		tui->acon.dirty.y1 = 0;
		tui->acon.dirty.y2 = tui->acon.h;
		tsm_screen_selection_reset(tui->screen);

		shmif_pixel col = SHMIF_RGBA(
			tui->bgc[0],tui->bgc[1],tui->bgc[2],tui->alpha);

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

/* now it's time to blit, at an offset + block if we want smooth-scrolling (and
 * not resetting the dirty flag) - shaping, for shaping / ligatures: then we
 * need a stronger heuristic to step */
	struct tui_cell* fpos = tui->front;
	struct tui_cell* bpos = tui->back;
	struct tui_cell* custom = tui->custom;

/* FIXME
 * if shaping/ligatures/non-monospace is enabled, we treat this row by row,
 * though this strategy is somewhat flawed if its word wrapped and we start
 * on a new word. There's surely some harfbuzz- trick to this, but baby-steps */

/* NORMAL drawing
 * draw everything that is different and not marked as custom, track the start
 * of every custom entry and sweep- seek- those separately */
	size_t drawc = 0;
	tui->got_custom = false;

	if (tui->front){
		for (size_t y = 0; y < tui->rows; y++)
			for (size_t x = 0; x < tui->cols; x++){

/* only update if the source position has changed, treat custom_id separate */
				if (!(tui->dirty & DIRTY_PENDING_FULL) && cell_match(fpos, bpos)){
				/* || tui->double_buffered */
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
				draw_cbt(tui, fpos->ch, y, x, 0, 0,
					tui->cell_w, tui->cell_h, &fpos->attr, false);
				drawc++;
				*custom = *bpos = *fpos;

				fpos++, bpos++, custom++;
			}
	}

	if (tui->cursor_upd){
		cursor_at(tui, tui->cursor_x * tui->cell_w, tui->cursor_y * tui->cell_h,
			tui->scroll_lock ? SHMIF_RGBA(tui->clc[0], tui->clc[1], tui->clc[2],0xff):
				SHMIF_RGBA(tui->cc[0], tui->cc[1], tui->cc[2], 0xff));
		tui->cursor_upd = false;
	}

	tui->dirty &= ~(DIRTY_PENDING | DIRTY_PENDING_FULL);
}

static bool page_up(struct tui_context* tui)
{
	tsm_screen_sb_up(tui->screen, tui->rows);
	tui->sbofs += tui->rows;
	tui->dirty |= DIRTY_PENDING;
	return true;
}

static bool page_down(struct tui_context* tui)
{
	tsm_screen_sb_down(tui->screen, tui->rows);
	tui->sbofs -= tui->rows;
	tui->sbofs = tui->sbofs < 0 ? 0 : tui->sbofs;
	tui->dirty |= DIRTY_PENDING;
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

static bool scroll_up(struct tui_context* tui)
{
	int nf = mod_to_scroll(tui->modifiers, tui->rows);
	tsm_screen_sb_up(tui->screen, nf);
	tui->sbofs += nf;
	tui->dirty |= DIRTY_PENDING;
	return true;
}

static bool scroll_down(struct tui_context* tui)
{
	int nf = mod_to_scroll(tui->modifiers, tui->rows);
	tsm_screen_sb_down(tui->screen, nf);
	tui->sbofs -= nf;
	tui->sbofs = tui->sbofs < 0 ? 0 : tui->sbofs;
	tui->dirty |= DIRTY_PENDING;
	return true;
}

static bool move_up(struct tui_context* tui)
{
	if (tui->scroll_lock){
		page_up(tui);
		return true;
	}
	else if (tui->modifiers & (TUIK_LMETA | TUIK_RMETA)){
		if (tui->modifiers & (TUIK_LSHIFT | TUIK_RSHIFT))
			page_up(tui);
		else{
			tsm_screen_sb_up(tui->screen, 1);
			tui->sbofs += 1;
			tui->dirty |= DIRTY_PENDING;
		}
		return true;
	}
	else if (tui->handlers.input_label)
		return tui->handlers.input_label(tui, "UP", NULL, tui->handlers.tag);

	return false;
}

static bool move_down(struct tui_context* tui)
{
	if (tui->scroll_lock){
		page_down(tui);
		return true;
	}
	else if (tui->modifiers & (TUIK_LMETA | TUIK_RMETA)){
		if (tui->modifiers & (TUIK_LSHIFT | TUIK_RSHIFT))
			page_up(tui);
		else{
			tsm_screen_sb_down(tui->screen, 1);
			tui->sbofs -= 1;
			tui->dirty |= DIRTY_PENDING;
		}
		return true;
	}
	else if (tui->handlers.input_label)
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

/* the selection routine here seems very wonky, assume the complexity comes
 * from char.conv and having to consider scrollback */
	ssize_t len = tsm_screen_selection_copy(tui->screen, &sel);
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
		tui->sbofs = 0;
		tsm_screen_sb_reset(tui->screen);
		tui->dirty |= DIRTY_PENDING;
	}
	return true;
}

static bool mouse_forward(struct tui_context* tui)
{
	tui->mouse_forward = !tui->mouse_forward;
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
	{"LINE_UP", "Scroll 1 row up", scroll_up},
	{"LINE_DOWN", "Scroll 1 row down", scroll_down},
	{"PAGE_UP", "Scroll one page up", page_up},
	{"PAGE_DOWN", "Scroll one page down", page_down},
	{"COPY_AT", "Copy word at cursor", select_at},
	{"COPY_ROW", "Copy cursor row", select_row},
	{"MOUSE_FORWARD", "Toggle mouse forwarding", mouse_forward},
	{"SCROLL_LOCK", "Arrow- keys to pageup/down", scroll_lock},
	{"UP", "(scroll-lock) page up, UP keysym", move_up},
	{"DOWN", "(scroll-lock) page down, DOWN keysym", move_up},
	{"INC_FONT_SZ", "Font size +1 pt", inc_fontsz},
	{"DEC_FONT_SZ", "Font size -1 pt", dec_fontsz},
	{NULL, NULL}
};

static void expose_labels(struct tui_context* tui)
{
	const struct lent* cur = labels;

/*
 * NOTE: We do not currently expose a suggested default
 */
	while(cur->lbl){
		arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(LABELHINT),
			.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
		};
		snprintf(ev.ext.labelhint.label,
			sizeof(ev.ext.labelhint.label)/sizeof(ev.ext.labelhint.label[0]),
			"%s", cur->lbl
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
			tui->sbofs = 0;
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
			if (ioev->subid == 0)
				tui->mouse_x = ioev->input.analog.axisval[0] / tui->cell_w;
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

	tui->base = NULL;

	size_t buffer_sz = tui->rows * tui->cols * sizeof(struct tui_cell);
	tui->base = malloc(buffer_sz * 3);
	if (!tui->base){
		LOG("couldn't allocate screen buffers buffer\n");
		return;
	}
	memset(tui->base, '\0', buffer_sz);
	tui->front = tui->base;
	tui->back = &tui->base[tui->rows * tui->cols];
	tui->custom = &tui->base[tui->rows * tui->cols * 2];
}

static void update_screensize(struct tui_context* tui, bool clear)
{
	int cols = tui->acon.w / tui->cell_w;
	int rows = tui->acon.h / tui->cell_h;
	LOG("update screensize (%d * %d), (%d * %d)\n",
		cols, rows, (int)tui->acon.w, (int)tui->acon.h);

	shmif_pixel col = SHMIF_RGBA(
		tui->bgc[0],tui->bgc[1],tui->bgc[2],tui->alpha);

	while (atomic_load(&tui->acon.addr->vready))
		;

	if (clear)
		draw_box(&tui->acon, 0, 0, tui->acon.w, tui->acon.h, col);

	tui->pad_w = tui->acon.w - (cols * tui->cell_w);
	tui->pad_h = tui->acon.h - (rows * tui->cell_h);

	if (cols != tui->cols || rows != tui->rows){
		if (cols > tui->cols)
			tui->pad_w += (cols - tui->cols) * tui->cell_w;

		if (rows > tui->rows)
			tui->pad_h += (rows - tui->rows) * tui->cell_h;

		int dr = tui->rows - rows;
		tui->cols = cols;
		tui->rows = rows;

		if (tui->handlers.resized)
			tui->handlers.resized(tui,
				tui->acon.w, tui->acon.h, cols, rows, tui->handlers.tag);

		tsm_screen_resize(tui->screen, cols, rows);
	}

/* will enforce full redraw, and full redraw will also update padding */
	tui->dirty |= DIRTY_PENDING_FULL;

/* if we have TUI- based screen buffering for smooth-scrolling, double-buffered
 * rendering and text shaping, that one needs to be rebuilt */
	resize_cellbuffer(tui);

	update_screen(tui, true);
}

static void targetev(struct tui_context* tui, arcan_tgtevent* ev)
{
	switch (ev->kind){
/* control alpha, palette, cursor mode, ... */
	case TARGET_COMMAND_GRAPHMODE:
		if (ev->ioevs[0].iv == 1){
			tui->alpha = ev->ioevs[1].fv;
			tui->dirty = DIRTY_PENDING_FULL;
		}
	break;

/* sigsuspend to group */
	case TARGET_COMMAND_PAUSE:
	break;

/* sigresume to session */
	case TARGET_COMMAND_UNPAUSE:
	break;

	case TARGET_COMMAND_RESET:
		tui->modifiers = 0;
		switch(ev->ioevs[0].iv){
		case 0:
		case 1:
			if (tui->handlers.reset)
				tui->handlers.reset(tui, ev->ioevs[0].iv, tui->handlers.tag);
		break;
		case 2:
		case 3:
			queue_requests(tui, true, true);
			arcan_shmif_drop(&tui->clip_in);
			arcan_shmif_drop(&tui->clip_out);
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
			if (ev->ioevs[1].iv < 0)
				tsm_screen_sb_up(tui->screen, -1 * ev->ioevs[1].iv);
			else
				tsm_screen_sb_down(tui->screen, ev->ioevs[1].iv);
			tui->sbofs += ev->ioevs[1].iv;
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
				if (!tui->cursor_off){
					tui->cursor_off = true;
					flag_cursor(tui);
				}
			}
			else{
				tui->focus = true;
				tui->inact_timer = 0;
				if (tui->cursor_off){
					tui->cursor_off = false;
					flag_cursor(tui);
				}
			}
		}

/* switch cursor kind on changes to 4 in ioevs[2] */
		if (dev){
			if (!arcan_shmif_resize(&tui->acon, ev->ioevs[0].iv, ev->ioevs[1].iv))
				LOG("resize to (%d * %d) failed\n", ev->ioevs[0].iv, ev->ioevs[1].iv);
			update_screensize(tui, true);
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

/*
 * map the two clipboards needed for both cut and for paste operations
 */
	case TARGET_COMMAND_NEWSEGMENT:
		if (ev->ioevs[1].iv == 1){
			if (!tui->clip_in.vidp){
				tui->clip_in = arcan_shmif_acquire(&tui->acon,
					NULL, SEGID_CLIPBOARD_PASTE, 0);
			}
			else
				LOG("multiple paste- clipboards received, likely appl. error\n");
		}
		else if (ev->ioevs[1].iv == 0){
			if (!tui->clip_out.vidp){
				tui->clip_out = arcan_shmif_acquire(&tui->acon,
					NULL, SEGID_CLIPBOARD, 0);
			}
			else
				LOG("multiple clipboards received, likely appl. error\n");
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
					tui->cursor_off = tui->inact_timer > 1 ? !tui->cursor_off : false;
					flag_cursor(tui);
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
				tsm_screen_sb_up(tui->screen, abs(tui->scrollback));
			else
				tsm_screen_sb_down(tui->screen, tui->scrollback);
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
		arcan_shmif_drop(&tui->acon);
	break;

	default:
		if (tui->handlers.raw_event)
			tui->handlers.raw_event(tui, ev, tui->handlers.tag);
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

/* and a 1s. timer for blinking cursor */
	if (tui->cursor_period > 0)
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
	if (!tui || !tui->acon.addr){
		errno = EINVAL;
		return -1;
	}

/* synch vscreen -> screen buffer */
	tui->flags = tsm_screen_get_flags(tui->screen);
	tui->age = tsm_screen_draw(tui->screen, tsm_draw_callback, tui);

	if (atomic_load(&tui->acon.addr->vready)){
		errno = EAGAIN;
		return -1;
	}

	if ((tui->dirty & DIRTY_PENDING) || (tui->dirty & DIRTY_PENDING_FULL))
		update_screen(tui, false);
	if (tui->dirty & DIRTY_UPDATED){
/* if we are built with GPU offloading support and nothing has happened
 * to our accelerated connection, synch, otherwise fallback and retry */
#ifndef SHMIF_TUI_DISABLE_GPU
retry:
	if (tui->is_accel){
		if (-1 == arcan_shmifext_signal(&tui->acon, 0,
			SHMIF_SIGVID | SHMIF_SIGBLK_NONE, SHMIFEXT_BUILTIN)){
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

void arcan_tui_destroy(struct tui_context* tui)
{
	if (!tui)
		return;

	if (tui->clip_in.vidp)
		arcan_shmif_drop(&tui->clip_in);

	if (tui->clip_out.vidp)
		arcan_shmif_drop(&tui->clip_out);

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

struct tui_settings arcan_tui_defaults()
{
	return (struct tui_settings){
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
		.font_sz = 0.0416,
		.force_bitmap = false
	};
}

static uint8_t* grp_to_cptr(struct tui_context* tui, enum tui_color_group grp)
{
	switch (grp){
	case TUI_COL_BG:
		return tui->bgc;
	break;
	case TUI_COL_FG:
		return tui->fgc;
	break;
	case TUI_COL_CURSOR:
		return tui->cc;
	break;
	case TUI_COL_ALTCURSOR:
		return tui->clc;
	break;
	default:
	return NULL;
	}
}

void arcan_tui_get_color(struct tui_context* tui,
	enum tui_color_group group, uint8_t rgb[3])
{
	uint8_t* src = grp_to_cptr(tui, group);
	if (src)
		memcpy(rgb, src, 3);
}

void arcan_tui_update_color(struct tui_context* tui,
	enum tui_color_group group, const uint8_t rgb[3])
{
	uint8_t* dst = grp_to_cptr(tui, group);
	if (dst){
		tui->dirty |= DIRTY_PENDING_FULL;
		memcpy(dst, rgb, 3);
	}
}

static int parse_color(const char* inv, uint8_t outv[4])
{
	return sscanf(inv, "%"SCNu8",%"SCNu8",%"SCNu8",%"SCNu8,
		&outv[0], &outv[1], &outv[2], &outv[3]);
}

void arcan_tui_apply_arg(struct tui_settings* cfg,
	struct arg_arr* args, struct tui_context* src)
{
/* FIXME: if src is set, copy settings from there (and dup descriptors) */
	const char* val;
	uint8_t ccol[4] = {0x00, 0x00, 0x00, 0xff};

	if (arg_lookup(args, "fgc", 0, &val))
		if (parse_color(val, ccol) >= 3){
			cfg->fgc[0] = ccol[0]; cfg->fgc[1] = ccol[1]; cfg->fgc[2] = ccol[2];
		}

#ifdef ENABLE_GPU
	if (arg_lookup(args, "accel", 0, &val))
		cfg->prefer_accel = true;
#endif

	if (arg_lookup(args, "bgc", 0, &val))
		if (parse_color(val, ccol) >= 3){
			cfg->bgc[0] = ccol[0]; cfg->bgc[1] = ccol[1]; cfg->bgc[2] = ccol[2];
		}

	if (arg_lookup(args, "cc", 0, &val))
		if (parse_color(val, ccol) >= 3){
			cfg->cc[0] = ccol[0]; cfg->cc[1] = ccol[1]; cfg->cc[2] = ccol[2];
		}

	if (arg_lookup(args, "clc", 0, &val))
		if (parse_color(val, ccol) >= 3){
			cfg->clc[0] = ccol[0]; cfg->clc[1] = ccol[1]; cfg->clc[2] = ccol[2];
		}

	if (arg_lookup(args, "blink", 0, &val)){
		cfg->cursor_period = strtol(val, NULL, 10);
	}

	if (arg_lookup(args, "cursor", 0, &val)){
		const char** cur = curslbl;
		while(*cur){
			if (strcmp(*cur, val) == 0){
				cfg->cursor = (cur - curslbl);
				break;
			}
			cur++;
		}
	}

	if (arg_lookup(args, "bgalpha", 0, &val))
		cfg->alpha = strtoul(val, NULL, 10);
	if (arg_lookup(args, "ppcm", 0, &val)){
		float ppcm = strtof(val, NULL);
		if (isfinite(ppcm) && ppcm > ARCAN_SHMPAGE_DEFAULT_PPCM * 0.5)
			cfg->ppcm = ppcm;
	}

	if (arg_lookup(args, "force_bitmap", 0, &val))
		cfg->force_bitmap = true;
}

int arcan_tui_alloc_screen(struct tui_context* ctx)
{
	int ind = ffs(~ctx->screen_alloc);
	if (0 == ind)
		return -1;

	if (0 != tsm_screen_new(&ctx->screens[ind], tsm_log, ctx))
		return -1;

	tsm_screen_set_def_attr(ctx->screens[ind],
		&(struct tui_screen_attr){
			.fr = ctx->fgc[0], .fg = ctx->fgc[1], .fb = ctx->fgc[2],
			.br = ctx->bgc[0], .bg = ctx->bgc[1], .bb = ctx->bgc[2]
	});

	ctx->screen_alloc |= 1 << ind;
	return ind;
}

bool arcan_tui_switch_screen(struct tui_context* ctx, unsigned ind)
{
	if (ind > 31 || !(ctx->screen_alloc & (1 << ind)))
		return false;

	if (ctx->screens[ind] == ctx->screen)
		return true;

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

/*
 * Threading notice - doesn't belong here
 */
#ifndef SIMPLE_RENDERING
	TTF_Init();
#endif

	struct arcan_shmif_initial* init;
	if (sizeof(struct arcan_shmif_initial) != arcan_shmif_initial(con, &init)){
		LOG("initial structure size mismatch, out-of-synch header/shmif lib\n");
		return NULL;
	}

	struct tui_context* res = malloc(sizeof(struct tui_context));
	if (!res)
		return NULL;
	memset(res, '\0', sizeof(struct tui_context));

	if (tsm_screen_new(&res->screen, tsm_log, res) < 0){
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
		LOG("arcan_shmif_tui(), caller provided bad size field\n");
		return NULL;
	}
	memcpy(&res->handlers, cbs, cbs_sz);

	res->focus = true;
	res->ppcm = init->density;

	res->font_fd[0] = BADFD;
	res->font_fd[1] = BADFD;
	res->font_sz = set->font_sz;
	res->font_bitmap = tui_draw_init(64);

	res->alpha = set->alpha;
	res->cell_w = set->cell_w;
	res->cell_h = set->cell_h;
	memcpy(res->cc, set->cc, 3);
	memcpy(res->clc, set->clc, 3);
	memcpy(res->bgc, set->bgc, 3);
	memcpy(res->fgc, set->fgc, 3);
	res->hint = set->hint;
	res->mouse_forward = set->mouse_fwd;
	res->acon = *con;
	res->cursor_period = set->cursor_period;
	res->acon.hints = SHMIF_RHINT_SUBREGION;
	res->force_bitmap = set->force_bitmap;

	if (init->fonts[0].fd != BADFD){
		res->hint = init->fonts[0].hinting;
		res->font_sz = init->fonts[0].size_mm;
		setup_font(res, init->fonts[0].fd, res->font_sz, 0);
		init->fonts[0].fd = BADFD;
		LOG("arcan_shmif_tui(), built-in font provided, size: %f\n", res->font_sz);

		if (init->fonts[1].fd != BADFD){
			setup_font(res, init->fonts[1].fd, res->font_sz, 1);
			init->fonts[1].fd = BADFD;
		}
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
			.fr = res->fgc[0], .fg = res->fgc[1], .fb = res->fgc[2],
			.br = res->bgc[0], .bg = res->bgc[1], .bb = res->bgc[2]
	});
	tsm_screen_set_max_sb(res->screen, 1000);

/* clipboard, timer callbacks, no IDENT */
	queue_requests(res, true, false);

/* show the current cell dimensions to help limit resize requests */
	send_cell_sz(res);

	update_screensize(res, true);
	res->handlers.resized(res, res->acon.w, res->acon.h,
		res->cols, res->rows, res->handlers.tag);

#ifndef SHMIF_TUI_DISABLE_GPU
	if (set->prefer_accel){
		struct arcan_shmifext_setup setup = arcan_shmifext_defaults(con);
		setup.builtin_fbo = false;
		setup.vidp_pack = true;
		if (arcan_shmifext_setup(con, setup) == SHMIFEXT_OK){
			LOG("arcan_shmif_tui(), accelerated connection established");
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
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_screen(c->screen, protect);
	}
}

void arcan_tui_erase_region(struct tui_context* c,
	size_t x1, size_t y1, size_t x2, size_t y2, bool protect)
{
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_region(c->screen, x1, y1, x2, y2, protect);
	}
}

void arcan_tui_erase_sb(struct tui_context* c)
{
	if (c){
		tsm_screen_inc_age(c->screen);
		tsm_screen_clear_sb(c->screen);
	}
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

void arcan_tui_defattr(struct tui_context* c, struct tui_screen_attr* attr)
{
	if (c)
	tsm_screen_set_def_attr(c->screen, (struct tui_screen_attr*) attr);
}

void arcan_tui_write(struct tui_context* c, uint32_t ucode,
	struct tui_screen_attr* attr)
{
	if (c){
		tsm_screen_write(c->screen, ucode, attr);
		flag_cursor(c);
	}
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
	uint8_t* u8, size_t len, struct tui_screen_attr* attr)
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

void arcan_tui_set_flags(struct tui_context* c, enum tui_flags flags)
{
	if (c){
		if ((c->cursor_hard_off && !(flags & TUI_HIDE_CURSOR)) ||
			(!c->cursor_hard_off && (flags & TUI_HIDE_CURSOR))){
			c->cursor_hard_off = !c->cursor_hard_off;
			flag_cursor(c);
		}

		tsm_screen_set_flags(c->screen, flags);
	}
}

void arcan_tui_reset_flags(struct tui_context* c, enum tui_flags flags)
{
	if (c){
		c->cursor_hard_off = (flags & TUI_HIDE_CURSOR) > 0;
		flag_cursor(c);
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
	if (c){
		flag_cursor(c);
		tsm_screen_scroll_up(c->screen, n);
	}
}

void arcan_tui_scroll_down(struct tui_context* c, size_t n)
{
	if (c){
		flag_cursor(c);
		tsm_screen_scroll_down(c->screen, n);
	}
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
	if (c){
		flag_cursor(c);
		tsm_screen_move_down(c->screen, n, scroll);
	}
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
	if (c){
		flag_cursor(c);
		tsm_screen_newline(c->screen);
	}
}

int arcan_tui_set_margins(struct tui_context* c, size_t top, size_t bottom)
{
	if (c)
		return tsm_screen_set_margins(c->screen, top, bottom);
	return -EINVAL;
}
