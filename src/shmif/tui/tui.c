/*
 * Copyright: Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description:
 *
 * This unit implements the main arcan_tui entrypoints, and mostly maps /
 * translates to internal functions.
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
#include <stdarg.h>
_Static_assert(PIPE_BUF >= 4, "pipe atomic write should be >= 4");

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "../arcan_shmif.h"
#include "../arcan_tui.h"

#include "arcan_ttf.h"
#include "tui_int.h"

static inline void flag_cursor(struct tui_context* c)
{
	c->dirty |= DIRTY_CURSOR;
	c->inact_timer = -4;

	if (c->hooks.cursor_update){
		c->hooks.cursor_update(c);
	}
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
	arcan_tui_request_subwnd_ext(tui,
		type, id, (struct tui_subwnd_req){0}, sizeof(struct tui_subwnd_req));
}

void arcan_tui_request_subwnd_ext(struct tui_context* T,
	unsigned type, uint16_t id, struct tui_subwnd_req req, size_t req_sz)
{
	if (!T || !T->acon.addr)
		return;

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

	struct arcan_event ev = {
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = type,
		.ext.segreq.id = (uint32_t) id | (1 << 31),
		.ext.segreq.width = T->acon.w,
		.ext.segreq.height = T->acon.h
	};

/* in future revisions, go with offsetof to annotate the new fields */
	if (req_sz == sizeof(struct tui_subwnd_req)){
		if (req.cols)
			ev.ext.segreq.width = req.cols * T->cell_w;
		if (req.rows)
			ev.ext.segreq.height = req.rows * T->cell_h;
		ev.ext.segreq.dir = req.hint;
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

static void write_front_checked(struct tui_context* c,
	size_t x, size_t y, uint32_t uc, const struct tui_screen_attr* attr)
{
	struct tui_cell* data = &c->front[c->cy * c->cols + c->cx];
	data->fstamp = c->fstamp;
	data->draw_ch = data->ch = uc;
	if (attr)
		data->attr = *attr;
	c->dirty |= DIRTY_PARTIAL;
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

size_t arcan_tui_ucs4utf8_s(uint32_t cp, char dst[static 5])
{
	size_t nc = arcan_tui_ucs4utf8(cp, dst);
	dst[nc] = '\0';
	return nc;
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
		*dst = (c & 0x0f) << 12;
		left = 2;
		used = 3;
	}
	else if ((c & 0xF8) == 0xF0){
		*dst = (c & 0x07) << 18;
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
		res.errc = TUI_ERRC_BAD_CTX;
		return res;
	}

/* From each context, we need the relevant tui->acon.epipe to poll on, along
 * with the entries from the fdset that would require us to mask- populate and
 * return. This structure is not entirely cheap to set up so there might be
 * value in caching it somewhere between runs */
	short pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[fdset_sz + (n_contexts * 2)];
	memset(fds, '\0', sizeof(fds));

	size_t ofs = 0;
	for (size_t i = 0; i < n_contexts; i++){
		fds[ofs++] = (struct pollfd){
			.events = pollev,
			.fd = contexts[i]->clip_in.epipe ?
				contexts[i]->clip_in.epipe : -1
		};

		fds[ofs++] = (struct pollfd){
			.fd = contexts[i]->acon.epipe,
			.events = pollev
		};
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
	for (size_t ci = 0; ci < n_contexts && sv; ci++){
		if (fds[ci * 2].revents){
			tui_clipboard_check(contexts[ci]);
			sv--;
		}
		if (fds[ci * 2 + 1].revents){
			tui_event_poll(contexts[ci]);
			sv--;
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
	if (res.bad)
		res.errc = TUI_ERRC_BAD_FD;

	return res;
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

	if (tui->sbstat.dirty){
		arcan_shmif_enqueue(&tui->acon, &tui->sbstat.hint);
		tui->sbstat.dirty = false;
	}

	if (tui->dirty){
		return tui_screen_refresh(tui);
	}

	return 0;
}

void arcan_tui_wndhint(struct tui_context* C,
	struct tui_context* par, struct tui_constraints cons)
{
	if (!C)
		return;

	int cols = cons.max_cols ? cons.max_cols : cons.min_cols;
	int rows = cons.max_rows ? cons.max_rows : cons.min_rows;

/* special case, detached window so inject as displayhint */
	if (!C->acon.addr && (cols > 0 || rows > 0)){
		C->last_constraints = cons;

		if (cols <= 0)
			cols = C->cols;

		if (rows <= 0)
			rows = C->rows;

		if (cols){
			C->acon.w = C->cell_w * cols;
		}

		if (rows){
			C->acon.h = C->cell_h * rows;
		}

		tui_screen_resized(C);
	}
/* first send any sizing constraints */
	if (cols > 0 || rows > 0){
		struct arcan_event content = (struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(CONTENT),
			.ext.content = {
				.min_w = cons.min_cols * C->cell_w,
				.min_h = cons.min_rows * C->cell_h,
				.max_w = cons.max_cols * C->cell_w,
				.max_h = cons.max_rows * C->cell_h,
				.cell_w = C->cell_w,
				.cell_h = C->cell_h
			}
		};

		if (C->acon.addr)
			arcan_shmif_enqueue(&C->acon, &content);
	}

/* and if we want anchoring, add that */
	if (par){
		struct arcan_event viewport =
			(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(VIEWPORT),
			.ext.viewport.parent = par->acon.segment_token,
			.ext.viewport.x = cons.anch_col * C->cell_w,
			.ext.viewport.y = cons.anch_row * C->cell_h,
			.ext.viewport.w = cons.max_cols * C->cell_w,
			.ext.viewport.h = cons.max_rows * C->cell_h,
			.ext.viewport.invisible = cons.hide
		};

		if (C->viewport_proxy){
			viewport.ext.viewport.embedded = cons.embed;
			viewport.ext.viewport.parent = C->viewport_proxy;
			viewport.ext.viewport.order = -1;
			if (par->acon.addr)
				arcan_shmif_enqueue(&par->acon, &viewport);
		}
		else if (C->acon.addr)
			arcan_shmif_enqueue(&C->acon, &viewport);
	}

	C->last_constraints = cons;
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
	if (group < TUI_COL_LIMIT && group >= TUI_COL_PRIMARY){
		memcpy(rgb, tui->colors[group].rgb, 3);
	}
}

void arcan_tui_get_bgcolor(
	struct tui_context* tui, int group, uint8_t rgb[3])
{
	switch (group){
/* IF a background has been explicitly set for the color groups,
 * enable it, otherwise fall back to the reference TUI_COL_BG */
	case 1:
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
	if (group < TUI_COL_LIMIT && group >= TUI_COL_PRIMARY){
		memcpy(tui->colors[group].rgb, rgb, 3);

		if (group >= TUI_COL_TBASE){
			memcpy(tui->colors[group].rgb, rgb, 3);
			memcpy(tui->colors[group].bg, rgb, 3);
		}
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

static void add_to_event(struct tui_context* c, bool more,
	struct arcan_event* ev, size_t* ofs, const char* msg, size_t nb)
{
	size_t lim = COUNT_OF(ev->ext.bchunk.extensions);

/* if there isn't enough room, enable multipart and flush */
	if (nb + *ofs > lim - 1){
/* toggle multipart bit if needed */
		if (more){
			ev->ext.bchunk.hint |= 4;
		}
		else {
			ev->ext.bchunk.hint &= ~4;
		}

/* remove separator */
		ev->ext.bchunk.extensions[*ofs-1] = '\0';
		arcan_shmif_enqueue(&c->acon, ev);
		memset(ev->ext.bchunk.extensions, '\0', lim);
		*ofs = 0;
	}

/* append and continue */
	memcpy(&ev->ext.bchunk.extensions[*ofs], msg, nb);
	*ofs += nb;

	if (!more){
		arcan_shmif_enqueue(&c->acon, ev);
		ev->ext.bchunk.hint &= ~4;
		memset(&ev->ext.bchunk.extensions, '\0', lim);
	}
}

/* split list up into multiple messages if needed */
static void send_list(struct tui_context* c,
	struct arcan_event ev, const char* suffix, const char* list)
{
	const char* start = list;
	const char* end = start;
	size_t ofs = 0;

	while (*end){
		if (*end == '*'){
			ev.ext.bchunk.hint |= 2;
			end++;
			start = end;
			continue;
		}

/* ; is delimiter */
		if (*end != ';'){
			end++;
			continue;
		}

/* ignore empty */
		if (end == start){
			start = ++end;
			continue;
		}

/* we add in the delimiter as well */
		size_t nb = end - start + 1;

/* if the entry exceeds permitted length, skip it */
		if (nb > 64){
			start = end;
			continue;
		}

		add_to_event(c, (*end+1) || suffix, &ev, &ofs, start, nb);
		end++;
		start = end;
	}

/* any leftovers? send that but don't add the last character (\0 or ;) */
	if (start != end){
		add_to_event(c, suffix != NULL, &ev, &ofs, start, end - start);
	}

	if (suffix){
		add_to_event(c, false, &ev, &ofs, suffix, strlen(suffix));
	}

/* multipart to terminate? */
	if (ev.ext.bchunk.hint & 4){
		ev.ext.bchunk.hint &= ~4;
		arcan_shmif_enqueue(&c->acon, &ev);
	}
}

void arcan_tui_announce_cursor_io(struct tui_context* c, const char* descr)
{
	if (!c)
		return;

	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.category = EVENT_EXTERNAL,
		.ext.bchunk = {
			.input = false,
			.hint = 8
		}
	};

	send_list(c, ev, "", descr);
}

void arcan_tui_announce_io(struct tui_context* c,
	bool immediately, const char* input_descr, const char* output_descr)
{
	if (!c)
		return;

	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.category = EVENT_EXTERNAL,
		.ext.bchunk = {
			.input = true,
			.hint = (immediately * 1),
		}
	};

/* for the hints we append [tuiraw, stdio] but for direct-req only the
 * caller provided extensions will be used */
	if (immediately){
		if (input_descr){
			if (strlen(input_descr) == 0){
				ev.ext.bchunk.hint |= 2; /* wildcard */
				arcan_shmif_enqueue(&c->acon, &ev);
			}
			else {
				send_list(c, ev, "", input_descr);
			}
		}

		if (output_descr){
			ev.ext.bchunk.hint = 0;
			ev.ext.bchunk.input = false;
			if (strlen(output_descr) == 0){
				ev.ext.bchunk.hint |= 2; /* wildcard */
				arcan_shmif_enqueue(&c->acon, &ev);
			}
			else
				send_list(c, ev, "", output_descr);
		}

		return;
	}

	if (input_descr){
		const char* suffix = ";stdin";
		if (strlen(input_descr) == 0){
			suffix = "stdin";
		}
		send_list(c, ev, suffix, input_descr);
	}

	if (output_descr){
		ev.ext.bchunk.input = false;
		const char* suffix =  ";tuiraw;stdout;stderr";

/* request to flush? then re-announce tuiraw */
		if (strlen(output_descr) == 0){
			suffix = "tuiraw;stdout;stderr";
		}
		send_list(c, ev, suffix, output_descr);
	}
}

/*
 * context- unwrap to screen and forward to tsm_screen
 */
void arcan_tui_erase_screen(struct tui_context* c, bool protect)
{
	if (!c)
		return;

	struct tui_screen_attr def = arcan_tui_defattr(c, NULL);
	arcan_tui_eraseattr_screen(c, protect, def);
}

void arcan_tui_eraseattr_screen(
	struct tui_context* c, bool protect, struct tui_screen_attr attr)
{
	if (!c)
		return;

	arcan_tui_eraseattr_region(c, 0, 0, c->cols-1, c->rows-1, protect, attr);
}

void arcan_tui_eraseattr_region(struct tui_context* c,
	size_t x1, size_t y1, size_t x2, size_t y2,
	bool protect, struct tui_screen_attr attr)
{
	if (!c)
		return;

	for (size_t y = y1; y < c->rows && y <= y2; y++)
		for (size_t x = x1; x < c->cols && x <= x2; x++){
			struct tui_cell* data = &c->front[y * c->cols + x];
			if (!protect || (data->attr.aflags & TUI_ATTR_PROTECT) == 0){
				data->ch = data->draw_ch = 0;
				data->attr = attr;
				data->fstamp = c->fstamp;
			}
		}
}

void arcan_tui_erase_region(struct tui_context* c,
	size_t x1, size_t y1, size_t x2, size_t y2, bool protect)
{
	if (!c)
		return;

	struct tui_screen_attr def = arcan_tui_defattr(c, NULL);
	arcan_tui_eraseattr_region(c, x1, y1, x2, y2, protect, def);
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

struct tui_screen_attr arcan_tui_defcattr(struct tui_context* c, int group)
{
	struct tui_screen_attr out = {};
	if (!c)
		return out;

	out = c->defattr;
	arcan_tui_get_color(c, group, out.fc);
	arcan_tui_get_bgcolor(c, group, out.bc);
	out.aflags &= ~TUI_ATTR_COLOR_INDEXED;

	return out;
}

struct tui_screen_attr
	arcan_tui_defattr(struct tui_context* c, struct tui_screen_attr* attr)
{
	if (!c)
		return (struct tui_screen_attr){};

	struct tui_screen_attr out = c->defattr;
	if (attr)
		c->defattr = *attr;

	return out;
}

void arcan_tui_write(struct tui_context* c,
	uint32_t ucode, const struct tui_screen_attr* attr)
{
	if (!c)
		return;

/* write + advance */
	write_front_checked(c, c->cx, c->cy, ucode, attr ? attr : &c->defattr);

/* advance and wrap or clamp */
	c->cx = c->cx + 1;
	if (c->cx > c->cols-1){
		if (c->flags & TUI_AUTO_WRAP){
			c->cx = 0;
			if (c->cy < c->rows-1)
				c->cy++;
		}
		else
			c->cx = c->cols-1;
	}

	flag_cursor(c);
}

void arcan_tui_writeattr_at(struct tui_context* c,
	const struct tui_screen_attr *attr, size_t x, size_t y)
{
	if (!c || !attr)
		return;

	assert(c->screen == NULL);
	if (x < c->cols && y < c->rows){
		c->front[y * c->cols + x].attr = *attr;
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

	assert(c->screen == NULL);

	if (x)
		*x = c->cx;

	if (y)
		*y = c->cy;
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

	if (c->hooks.reset){
		c->hooks.reset(c);
		return;
	}

	c->flags = TUI_ALTERNATE;
	c->defattr = (struct tui_screen_attr){
		.fc = TUI_COL_TEXT,
		.bc = TUI_COL_TEXT,
		.aflags = TUI_ATTR_COLOR_INDEXED
	};

	arcan_tui_eraseattr_screen(c, false, c->defattr);
	flag_cursor(c);
}

void arcan_tui_dimensions(struct tui_context* c, size_t* rows, size_t* cols)
{
	if (rows)
		*rows = c->rows;

	if (cols)
		*cols = c->cols;
}

void arcan_tui_progress(struct tui_context* c, int type, float status)
{
	if (!c || type < TUI_PROGRESS_INTERNAL || type > TUI_PROGRESS_STATE_OUT)
		return;

	if (status > 1.0)
		status = 1.0;

/* clamp this slightly about 0, fewer bad shells writing div-zero that way */
	if (status < 0.0001)
		status = 0.0001;

/* using the timestr/timelim fields here for more detailed progress would
 * be possible, but wait and see how the feature plays out first */
	arcan_shmif_enqueue(&c->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(STREAMSTATUS),
		.ext.streamstat = {
			.completion = status,
			.streaming = type,
		}
	});
}

int arcan_tui_set_flags(struct tui_context* c, int flags)
{
	if (!c)
		return -1;

	int old_flags = c->flags;
	c->flags = flags;
	c->cursor_hard_off = flags & TUI_HIDE_CURSOR;

	if (old_flags != flags)
		flag_cursor(c);

	if (flags & (TUI_MOUSE | TUI_MOUSE_FULL))
		c->mouse_forward = true;

	return old_flags;
}

void arcan_tui_move_to(struct tui_context* c, size_t x, size_t y)
{
	if (!c)
		return;

	if (x != c->cx || y != c->cy){
		c->cx = x;
		c->cy = y;
		flag_cursor(c);
	}
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

void arcan_tui_message(
	struct tui_context* c, int target, const char* msg)
{
	if (!c)
		return;

	struct arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_MESSAGE,
	};

	size_t len = strlen(msg);

	if (target == TUI_MESSAGE_PROMPT){
	}
/* should also have failure here */
	else if (target == TUI_MESSAGE_ALERT){
		outev.ext.kind = EVENT_EXTERNAL_ALERT;
	}
	else if (target == TUI_MESSAGE_FAILURE){
		outev.ext.kind = EVENT_EXTERNAL_FAILURE;
	}
/* reserved first > for prompt */
	else if (target == TUI_MESSAGE_NOTIFICATION){
		char* workstr = malloc(len + 2);
		if (!workstr)
			return;

		workstr[0] = '>';
		memcpy(&workstr[1], msg, len);
		workstr[len+1] = '\0';
		arcan_shmif_pushutf8(&c->acon, &outev, msg, len);
		free(workstr);
		return;
	}
	else
		return;

	arcan_shmif_pushutf8(&c->acon, &outev, msg, len);
}

pid_t arcan_tui_handover(
	struct tui_context* c,
	arcan_tui_conn* conn,
	const char* path, char* const argv[], char* const env[],
	int flags)
{
	return arcan_shmif_handover_exec(
		&c->acon, c->pending_wnd, path, argv, env, flags);
}

pid_t arcan_tui_handover_pipe(
	struct tui_context* c,
	arcan_tui_conn* conn,
	const char* path, char* const argv[], char* const env[],
	int* fds[], size_t fds_sz)
{
	return arcan_shmif_handover_exec_pipe(
		&c->acon, c->pending_wnd, path, argv, env, 0, fds, fds_sz);
}

void arcan_tui_content_size(struct tui_context* c,
	size_t row_ofs, size_t row_tot, size_t col_ofs, size_t col_tot)
{
	if (!c)
		return;

	struct arcan_event ev = (struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(CONTENT),
			.ext.content = {
				.x_sz = 1.0,
				.y_sz = 1.0
			}
	};

/* note, OOB (1.0 - x_pos < 0.0 is possible and would indicate that we are
 * panning outside the valuable contents range - judgement call if this is
 * wise or not but can defer that to the caller. */
	if (col_tot > c->cols && col_ofs < col_tot){
		ev.ext.content.x_sz = (float)c->cols / (float)col_tot;
		ev.ext.content.x_pos = (float)col_ofs / (float)col_tot;
		ev.ext.content.width = 1.0 / (col_tot - c->cols);
	}

	if (row_tot > c->rows && row_ofs < row_tot){
		ev.ext.content.y_sz = (float)c->rows / (float)row_tot;
		ev.ext.content.y_pos = (float)row_ofs / (float)row_tot;
		ev.ext.content.height = 1.0 / (row_tot - c->rows);
	}

	c->sbstat.dirty = true;
	c->sbstat.hint = ev;
}

bool arcan_tui_tpack(struct tui_context* tui, uint8_t** rbuf, size_t* rbuf_sz)
{
	if (!rbuf || !rbuf_sz)
		return false;

	size_t cap = tui_screen_tpack_sz(tui);
	*rbuf = malloc(cap);
	if (!*rbuf)
		return false;

	*rbuf_sz = tui_screen_tpack(tui,
		(struct tpack_gen_opts){.full = true}, *rbuf, cap);

	return true;
}

bool arcan_tui_tunpack(struct tui_context* tui,
	uint8_t* buf, size_t buf_sz,  size_t x, size_t y, size_t w, size_t h)
{
	return tui_tpack_unpack(tui, buf, buf_sz, x, y, w, h) >= 0;
}

int arcan_tui_cursor_style(
	struct tui_context* tui, int fl, const uint8_t* const col)
{
	if (!col)
		tui->cursor_color_override = false;

	if (!fl && !col){
		return tui->cursor;
	}

	if (fl)
		tui->cursor = fl;

	if (col){
		tui->cursor_color[0] = col[0];
		tui->cursor_color[1] = col[1];
		tui->cursor_color[2] = col[2];
		tui->cursor_color_override = true;
	}

	return 0;
}

void arcan_tui_screencopy(
	struct tui_context* src, struct tui_context* dst,
	size_t s_x1, size_t s_y1,
	size_t s_x2, size_t s_y2,
	size_t d_x1, size_t d_y1
)
{
	if (!src || !dst || s_x1 > s_x2 || s_y1 > s_y2)
		return;

	size_t d_x2 = dst->cols;
	size_t d_y2 = dst->rows;
	if (s_x2 > src->cols)
		s_x2 = src->cols;

	if (s_y2 > src->rows)
		s_y2 = src->rows;

	for (size_t cy = s_y1, dy = d_y1; cy < s_y2, dy < d_y2; cy++, dy++){
		for (size_t cx = s_x1, dx = d_x1; cx < s_x2, dx < d_x2; cx++, dx++){
			struct tui_cell data = src->front[cy * src->cols + cx];
			dst->front[dy * dst->cols + dx] = data;
		}
	}

	dst->dirty = true;
}

void arcan_tui_write_border(
	struct tui_context* T, struct tui_screen_attr attr,
	size_t x1, size_t y1, size_t x2, size_t y2, int fl)
{
	if (!T || x1 > x2 || y1 > y2)
		return;

/* edge-case: 1xn or nx1 would have the normal TLDR+corner walk overwrite */
	attr.aflags = TUI_ATTR_BORDER_TOP | TUI_ATTR_BORDER_LEFT;
	if (y2 - y1 == 0)
		attr.aflags |= TUI_ATTR_BORDER_DOWN;
	if (x2 - x1 == 0)
		attr.aflags |= TUI_ATTR_BORDER_RIGHT;
	arcan_tui_writeattr_at(T, &attr, x1, y1);

	attr.aflags = TUI_ATTR_BORDER_TOP;
	if (y2 - y1 == 0)
		attr.aflags |= TUI_ATTR_BORDER_DOWN;
	for (size_t i = x1 + 1; i < x2; i++)
		arcan_tui_writeattr_at(T, &attr, i, y1);

	if (x2 - x1 > 0){
		attr.aflags = TUI_ATTR_BORDER_TOP | TUI_ATTR_BORDER_RIGHT;
		if (y2 - y1 == 0)
			attr.aflags |= TUI_ATTR_BORDER_DOWN;
		arcan_tui_writeattr_at(T, &attr, x2, y1);
	}

	attr.aflags = TUI_ATTR_BORDER_LEFT;
	if (x2 - x1 == 0)
		attr.aflags |= TUI_ATTR_BORDER_RIGHT;
	for (size_t i = y1 + 1; i < y2; i++)
		arcan_tui_writeattr_at(T, &attr, x1, i);

	if (x2 - x1 > 0){
		attr.aflags = TUI_ATTR_BORDER_RIGHT;
		for (size_t i = y1 + 1; i < y2; i++)
			arcan_tui_writeattr_at(T, &attr, x2, i);
	}

	if (y2 - y1 == 0)
		return;

	attr.aflags = TUI_ATTR_BORDER_DOWN | TUI_ATTR_BORDER_LEFT;
	arcan_tui_writeattr_at(T, &attr, x1, y2);

	attr.aflags = TUI_ATTR_BORDER_DOWN;

	for (size_t i = x1 + 1; i < x2; i++)
		arcan_tui_writeattr_at(T, &attr, i, y2);

	attr.aflags = TUI_ATTR_BORDER_DOWN | TUI_ATTR_BORDER_RIGHT;
	arcan_tui_writeattr_at(T, &attr, x2, y2);
}

void arcan_tui_send_key(struct tui_context* C,
	uint8_t utf8[static 4], const char* lbl,
	uint32_t keysym, uint8_t scancode, uint16_t mods, uint16_t subid)
{
	if (!C)
		return;

/* with the proxy mode we can pack devid/subid to match the segment_cookie of
 * the proxy window */
	arcan_event ev =
	{
		.category = EVENT_IO,
		.io = {
			.datatype = EVENT_IDATATYPE_TRANSLATED,
			.devkind = EVENT_IDEVKIND_KEYBOARD,
			.kind = EVENT_IO_BUTTON,
			.subid = subid,
			.input = {
				.translated = {
					.active = true,
					.keysym = keysym,
					.scancode = scancode,
					.modifiers = mods
				}
			}
		}
	};
	if (lbl){
		snprintf(ev.io.label, COUNT_OF(ev.io.label), "%s", lbl);
	}
	memcpy(ev.io.input.translated.utf8, utf8, 4);

	if (C->viewport_proxy){
		ev.io.dst = C->viewport_proxy;
		if (C->acon.addr){
			arcan_shmif_enqueue(&C->acon, &ev);
			ev.io.input.translated.active = false;
			arcan_shmif_enqueue(&C->acon, &ev);
		}
		return;
	}

	tui_input_event(C, &ev.io, ev.io.label);
	ev.io.input.translated.active = false;
	tui_input_event(C, &ev.io, ev.io.label);
}
