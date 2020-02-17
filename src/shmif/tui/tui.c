/*
 * Copyright 2014-2019, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description:
 *
 * This unit implements the main arcan_tui entrypoints, and mostly maps /
 * translates to internal functions. Some of the _tsm management is also
 * done here until that gets refactored away entirely.
 *
 * input.c       : interactive event response
 * dispatch.c    : incoming event routing, target commands
 * screen.c      : implements drawing and processing loop
 * setup.c       : context creation
 * raster.c      : abstract buffer to pixels translation
 * fontmgmt.c    : font-file resource loading
 * clipboard.c   : cut and paste operations
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

#include "../arcan_shmif.h"
#include "../arcan_tui.h"
#include "screen/utf8.c"

#include "arcan_ttf.h"

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#include "screen/libtsm.h"
#include "screen/libtsm_int.h"
#include "tui_int.h"

char* arcan_tui_statedescr(struct tui_context* tui)
{
	char* ret;
	if (!tui)
		return NULL;

	int tfl = tui->screen->flags;
	int cx = tsm_screen_get_cursor_x(tui->screen);
	int cy = tsm_screen_get_cursor_y(tui->screen);

	if (-1 == asprintf(&ret,
		"frame: %d alpha: %d "
		"scroll-lock: %d "
		"rows: %d cols: %d cell_w: %d cell_h: %d "
		"ppcm: %f font_sz: %f hint: %d "
		"scrollback: %d sbofs: %d inscroll: %d backlog: %d "
		"mods: %d iact: %d "
		"cursor_x: %d cursor_y: %d off: %d hard_off: %d period: %d "
		"(screen)age: %d margin_top: %u margin_bottom: %u "
		"flags: %s%s%s%s%s%s",
		(int) tui->fstamp, (int) tui->alpha,
		(int) tui->scroll_lock,
		tui->rows, tui->cols, tui->cell_w, tui->cell_h,
		tui->ppcm, tui->font_sz, tui->hint,
		tui->scrollback, tui->sbofs, 1, 1,
		tui->modifiers, tui->inact_timer,
		cx, cy,
		tui->cursor_off, tui->cursor_hard_off, tui->cursor_period,
		(int) tui->screen->age, tui->screen->margin_top, tui->screen->margin_bottom,
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

static inline void flag_cursor(struct tui_context* c)
{
	c->cursor_upd = true;
	c->dirty |= DIRTY_CURSOR;
	c->inact_timer = -4;
}

bool arcan_tui_copy(struct tui_context* tui, const char* utf8_msg)
{
	return tui_clipboard_push(tui, utf8_msg, strlen(utf8_msg));
}

struct tui_cell arcan_tui_getxy(
	struct tui_context* tui, size_t x, size_t y, bool fl)
{
	if (y >= tui->rows || x >= tui->cols)
		return (struct tui_cell){};

	return fl ?
		tui->front[y * tui->cols + x] :
		tui->back[y * tui->cols + x];
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
		type = SEGID_TUI;
	break;
	case TUI_WND_POPUP:
		type = SEGID_POPUP;
	break;
	case TUI_WND_DEBUG:
		type = SEGID_DEBUG;
	break;
	case TUI_WND_HANDOVER:
		type = SEGID_HANDOVER;
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

void arcan_tui_request_subwnd_ext(struct tui_context* T,
	unsigned type, uint16_t id, struct tui_subwnd_req req, size_t req_sz)
{
	if (!T || !T->acon.addr)
		return;

	switch (type){
	case TUI_WND_TUI:
	case TUI_WND_POPUP:
	case TUI_WND_DEBUG:
	case TUI_WND_HANDOVER:
	break;
	default:
		return;
	}

	struct arcan_event ev = {
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = type,
		.ext.segreq.id = (uint32_t) id | (1 << 31),
		.ext.segreq.width = T->acon.w,
		.ext.segreq.height = T->acon.h
	};

/* in future revisions, go with offsetof to annotate the new fields */
	if (req_sz == sizeof(struct tui_subwnd_req)){
		ev.ext.segreq.width = req.columns * T->cell_w;
		ev.ext.segreq.height = req.rows * T->cell_h;
		ev.ext.segreq.dir = req.hint;
		return;
	}

	arcan_shmif_enqueue(&T->acon, &ev);
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

size_t arcan_tui_ucs4utf8(uint32_t cp, char dst[static 4])
{
/* reject invalid */
	if (
		(cp >= 0xd800 && cp <= 0xdfff) ||
		(cp >= 0xfdd0 && cp <= 0xfdef) ||
		(cp  > 0x10ffff              ) ||
		((cp & 0xffff) == 0xffff     ) ||
		((cp & 0xffff) == 0xfffe     )
	)
		return 0;

/* ascii- range */
	if (cp < (1 << 7)){
		dst[0] = cp & 0x7f;
		return 1;
	}

	if (cp < (1 << 11)){
		dst[0] = 0xc0 | ((cp >> 6) & 0x1f);
		dst[1] = 0x80 | ((cp     ) & 0x3f);
		return 2;
	}

	if (cp < (1 << 16)){
		dst[0] = 0xe0 | ((cp >> 12) & 0x0F);
		dst[1] = 0x80 | ((cp >>  6) & 0x3F);
		dst[2] = 0x80 | ((cp      ) & 0x3F);
		return 3;
	}

	if (cp < (1 << 21)){
		dst[0] = 0xf0 | ((cp >> 18) & 0x07);
		dst[1] = 0x80 | ((cp >> 12) & 0x3f);
		dst[2] = 0x80 | ((cp >>  6) & 0x3f);
		dst[3] = 0x80 | ((cp      ) & 0x3f);
		return 4;
	}

	return 0;
}

ssize_t arcan_tui_utf8ucs4(const char src[static 4], uint32_t* dst)
{
/* check first byte */
	uint8_t c = (uint8_t) src[0];
/* our of range ascii */
	if (c == 0xC0 || c == 0xC1)
		return -1;
/* single byte, works fine */
	if ((c & 0x80) == 0){
		*dst = c;
		return 1;
	}

/* started at middle of sequence */
	if ((c & 0xC0) == 0x80){
		return -2;
	}

	uint_fast8_t left;
	uint_fast8_t used;

/* figure out length of sequence */
	if ((c & 0xE0) == 0xC0){
		*dst = (c & 0x1F) << 6;
		left = 1;
		used = 2;
	}
	else if ((c & 0xF0) == 0xE0){
		left = 2;
		used = 3;
	}
	else if ((c & 0xF8) == 0xF0){
		left = 3;
		used = 4;
	}
	else
		return -1;

/* and map unto *dst */
	while(left){
		c = (uint8_t) src[used-left];
		if ((c & 0xC0) != 0x80)
			return -1;

		if (left == 3){
			*dst |= (c & 0x3F) << 12;
			left--;
		}
		else if (left == 2){
			*dst |= (c & 0x3F) << 6;
			left--;
		}
		else if (left == 1){
			*dst |= (c & 0x3f);
			left--;
		}
	}

	return used;
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

/* if any of the contexts are in a dirty state, the timeout will be changed */
	for (size_t i = 0; i < n_contexts; i++){
		if (!contexts[i]->acon.addr){
			res.bad |= 1 << i;
		}
		else if (contexts[i]->dirty)
			timeout = 0;
	}

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
				tui_clipboard_check(contexts[nc]);
			else {
				tui_event_poll(contexts[nc]);
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

void arcan_tuiint_set_vsynch(struct tui_context* tui, pthread_mutex_t* mut)
{
	tui->vsynch = mut;
}

int arcan_tuiint_dirty(struct tui_context* tui)
{
	return tui->dirty;
}

int arcan_tui_refresh(struct tui_context* tui)
{
	if (!tui || !tui->acon.addr){
		errno = EINVAL;
		return -1;
	}

	if (tui->dirty){
		return tui_screen_refresh(tui);
	}

	return 0;
}

/* DEPRECATE, should not have any use anymore */
void arcan_tui_invalidate(struct tui_context* tui)
{
	if (!tui)
		return;

	tui->dirty |= DIRTY_FULL;
}

void arcan_tui_wndhint(struct tui_context* C,
	struct tui_context* par, struct tui_constraints cons)
{
	if (!C)
		return;

/* this only deals with anchoring, should really be cached
 * inside the context and reissued on reset etc. */
	struct arcan_event viewport = (struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(VIEWPORT),
		.ext.viewport = {
			.x = cons.anch_col * C->cell_w,
			.y = cons.anch_row * C->cell_h,
			.w = cons.max_cols * C->cell_w,
			.h = cons.max_rows * C->cell_h
		}
	};

	if (par){
		viewport.ext.viewport.parent = par->acon.segment_token;
	}

/* fake-emit a resize regardless even if one might appear later, this might
 * seem uninituitive but helps verify that the event handler is actually hooked
 * up and that the client do handle the case that the viewport is mostly
 * ignored */
	C->last_constraints = cons;
	if (C->handlers.resized){
		C->handlers.resized(C,
			C->acon.w, C->acon.h, C->cols, C->rows, C->handlers.tag);
	}

/* the contenthint for setting scrollbar etc. need to be managed
 * elsewhere, so just save the desired constraints for now */

	arcan_shmif_enqueue(&C->acon, &viewport);
}

void arcan_tui_bgcopy(
	struct tui_context* tui, int fdin, int fdout, int sigfd, int fl)
{
	if (!tui)
		return;
	arcan_shmif_bgcopy(&tui->acon, fdin, fdout, sigfd, fl);
}

void arcan_tui_get_color(
	struct tui_context* tui, int group, uint8_t rgb[3])
{
	if (group <= TUI_COL_INACTIVE && group >= TUI_COL_PRIMARY){
		memcpy(rgb, tui->colors[group].rgb, 3);
	}
}

void arcan_tui_get_bgcolor(
	struct tui_context* tui, int group, uint8_t rgb[3])
{
	switch (group){
/* IF a background has been explicitly set for the color groups,
 * enable it, otherwise fall back to the reference TUI_COL_BG */
	case TUI_COL_TEXT:
	case TUI_COL_HIGHLIGHT:
	case TUI_COL_LABEL:
	case TUI_COL_WARNING:
	case TUI_COL_ERROR:
	case TUI_COL_ALERT:
	case TUI_COL_REFERENCE:
	case TUI_COL_INACTIVE:
	case TUI_COL_UI:
		memcpy(rgb, tui->colors[group].bgset ?
			tui->colors[group].bg : tui->colors[TUI_COL_BG].rgb, 3);
	break;

/* for the reference groups, we always take BG as BG color */
	case TUI_COL_PRIMARY:
	case TUI_COL_SECONDARY:
	case TUI_COL_BG:
	case TUI_COL_CURSOR:
	case TUI_COL_ALTCURSOR:
	default:
		memcpy(rgb, tui->colors[TUI_COL_BG].rgb, 3);
	break;
	}
}

void arcan_tui_set_bgcolor(
	struct tui_context* tui, int group, uint8_t rgb[3])
{
	switch (group){
	case TUI_COL_PRIMARY:
	case TUI_COL_SECONDARY:
	case TUI_COL_ALTCURSOR:
	case TUI_COL_CURSOR:
	break;

	case TUI_COL_BG:
	case TUI_COL_TEXT:
	case TUI_COL_HIGHLIGHT:
	case TUI_COL_LABEL:
	case TUI_COL_WARNING:
	case TUI_COL_ERROR:
	case TUI_COL_ALERT:
	case TUI_COL_REFERENCE:
	case TUI_COL_INACTIVE:
	case TUI_COL_UI:
		memcpy(tui->colors[group].bg, rgb, 3);
		tui->colors[group].bgset = true;
	break;
	default:
	break;
	}
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

void arcan_tui_set_color(
	struct tui_context* tui, int group, uint8_t rgb[3])
{
	if (group <= TUI_COL_INACTIVE && group >= TUI_COL_PRIMARY){
		memcpy(tui->colors[group].rgb, rgb, 3);
	}
}

bool arcan_tui_update_handlers(struct tui_context* tui,
	const struct tui_cbcfg* cbs, struct tui_cbcfg* out, size_t cbs_sz)
{
	if (!tui || cbs_sz > sizeof(struct tui_cbcfg))
		return false;

	if (out)
		memcpy(out, &tui->handlers, cbs_sz);

	if (cbs){
		memcpy(&tui->handlers, cbs, cbs_sz);
	}
	return true;
}

void arcan_tui_statesize(struct tui_context* c, size_t sz)
{
	if (!c)
		return;

	c->last_state_sz = (struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(STATESIZE),
		.ext.stateinf.size = sz
	};
	arcan_shmif_enqueue(&c->acon, &c->last_state_sz);
}

void arcan_tui_announce_io(struct tui_context* c,
	bool immediately, const char* input_descr, const char* output_descr)
{
	if (!c)
		return;

	arcan_event bchunk_in = {
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.category = EVENT_EXTERNAL,
		.ext.bchunk = {
			.input = true,
			.hint = !immediately
		}
	};

	arcan_event bchunk_out = bchunk_in;

	if (input_descr){
		snprintf((char*)bchunk_in.ext.bchunk.extensions,
			COUNT_OF(bchunk_in.ext.bchunk.extensions), "%s", input_descr);
		arcan_shmif_enqueue(&c->acon, &bchunk_in);
	}

	if (output_descr){
		bchunk_out.ext.bchunk.input = false;
		snprintf((char*)bchunk_out.ext.bchunk.extensions,
			COUNT_OF(bchunk_out.ext.bchunk.extensions), "%s", output_descr);
		arcan_shmif_enqueue(&c->acon, &bchunk_out);
	}

	if (!immediately){
		if (input_descr)
			c->last_bchunk_in = bchunk_in;
		if (output_descr)
			c->last_bchunk_out = bchunk_out;
	}
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

void arcan_tui_eraseattr_screen(
	struct tui_context* c, bool protect, struct tui_screen_attr attr)
{
	if (!c)
		return;

	struct tui_screen_attr reset_def = arcan_tui_defattr(c, NULL);
	arcan_tui_defattr(c, &attr);
	tsm_screen_erase_screen(c->screen, protect);
	arcan_tui_defattr(c, &reset_def);
}

void arcan_tui_eraseattr_region(struct tui_context* c,
	size_t x1, size_t y1, size_t x2, size_t y2,
	bool protect, struct tui_screen_attr attr)
{
	if (!c)
		return;

	struct tui_screen_attr reset_def = arcan_tui_defattr(c, NULL);
	arcan_tui_defattr(c, &attr);
	tsm_screen_erase_region(c->screen, x1, y1, x2, y2, protect);
	arcan_tui_defattr(c, &reset_def);
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

struct tui_screen_attr arcan_tui_defcattr(struct tui_context* c, int group)
{
	struct tui_screen_attr out = {};
	if (!c)
		return out;

	out = tsm_screen_get_def_attr(c->screen);
	arcan_tui_get_color(c, group, out.fc);
	arcan_tui_get_bgcolor(c, group, out.bc);

	return out;
}

struct tui_screen_attr
	arcan_tui_defattr(struct tui_context* c, struct tui_screen_attr* attr)
{
	if (!c)
		return (struct tui_screen_attr){};

	struct tui_screen_attr out = tsm_screen_get_def_attr(c->screen);

	if (attr)
		tsm_screen_set_def_attr(c->screen, (struct tui_screen_attr*) attr);

	return out;
}

void arcan_tui_write(struct tui_context* c,
	uint32_t ucode, struct tui_screen_attr* attr)
{
	if (!c)
		return;

	int ss = tsm_screen_write(c->screen, ucode, attr);

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

	size_t pos = 0;
	while (pos < len){
		uint32_t ucs4 = 0;
		ssize_t step = arcan_tui_utf8ucs4((char*) &u8[pos], &ucs4);
/* invalid character, write empty and advance */
		if (step <= 0)
			pos++;
		else
			pos += step;
		arcan_tui_write(c, ucs4, attr);
	}

	return true;
}

bool arcan_tui_hasglyph(struct tui_context* c, uint32_t cp)
{
	return tui_fontmgmt_hasglyph(c, cp);
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

void arcan_tui_reset_labels(struct tui_context* c)
{
	if (!c)
		return;

	tui_expose_labels(c);
}

void arcan_tui_reset(struct tui_context* c)
{
	if (!c)
		return;

	tsm_screen_reset(c->screen);
	flag_cursor(c);
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

	bool in_alternate = !!(c->flags & TUI_ALTERNATE);

	tsm_screen_set_flags(c->screen, flags);
	c->flags = tsm_screen_get_flags(c->screen);

	if (c->flags & TUI_ALTERNATE)
		tsm_screen_sb_reset(c->screen);

	bool want_alternate = !!(c->flags & TUI_ALTERNATE);
	if (in_alternate != want_alternate)
		arcan_tui_reset_labels(c);

	if (flags & TUI_MOUSE)
		c->mouse_forward = true;

	return (int) c->flags;
}

void arcan_tui_reset_flags(struct tui_context* c, int flags)
{
	if (!c)
		return;

	bool in_alternate = !!(c->flags & TUI_ALTERNATE);

	if (flags & TUI_HIDE_CURSOR){
		c->cursor_hard_off = false;
		flag_cursor(c);
	}

	tsm_screen_reset_flags(c->screen, flags);
	c->flags = tsm_screen_get_flags(c->screen);

	bool want_alternate = !!(c->flags & TUI_ALTERNATE);
	if (in_alternate != want_alternate)
		arcan_tui_reset_labels(c);
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

	flag_cursor(c);
}

void arcan_tui_scroll_down(struct tui_context* c, size_t n)
{
	if (!c || (c->flags & TUI_ALTERNATE))
		return;

	tsm_screen_sb_down(c->screen, n);
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

	flag_cursor(c);
}

int arcan_tui_set_margins(struct tui_context* c, size_t top, size_t bottom)
{
	if (c)
		return tsm_screen_set_margins(c->screen, top, bottom);
	return -EINVAL;
}

size_t arcan_tui_printf(struct tui_context* ctx,
	struct tui_screen_attr* attr, const char* msg, ...)
{
	va_list args;
	size_t rows, cols;
	arcan_tui_dimensions(ctx, &rows, &cols);
	char buf[cols];

	va_start(args, msg);
	ssize_t nw = vsnprintf(buf, cols, msg, args);
	if (nw > cols)
		nw = cols;
	va_end(args);

	if (nw <= 0)
		return 0;

	arcan_tui_writeu8(ctx, (uint8_t*) buf, nw, attr);
	return nw;
}

pid_t arcan_tui_handover(struct tui_context* c,
	arcan_tui_conn* conn,
	struct tui_constraints* constraints,
	const char* path, char* const argv[], char* const env[],
	int detach)
{
/* we tag the connection so we can pair the subwindow handler with the
 * event dispatch, as the handover semantics are different from window
 * allocation controls */
	if ((uintptr_t)(void*)conn != (uintptr_t)-1 || !c || !c->got_pending){
		return -1;
	}

/* send an event translating the constraints to a VIEWPORT event that
 * parents the HANDOVER segment to fit the constraints. */
	if (constraints){
/*
 * struct arcan_event viewport = (struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(VIEWPORT),
			.ext.viewport = {
				.x = cons.anch_col * C->cell_w,
				.y = cons.anch_row * C->cell_h,
			},
		};
 */
	}

	return arcan_shmif_handover_exec(
		&c->acon, c->pending_wnd, path, argv, env, detach);
}
