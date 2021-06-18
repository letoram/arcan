#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../tui_int.h"
#include "../screen/libtsm.h"
#include "../screen/libtsm_int.h"
#include "../screen/utf8.c"

#include <stdio.h>
#include <inttypes.h>
#include <math.h>
#include <errno.h>

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

	tui_clipboard_push(tui, sel, len);
	free(sel);
}

static bool page_up(struct tui_context* tui)
{
	if (!tui || (tui->flags & TUI_ALTERNATE))
		return true;

	tui->cursor_upd = true;
	tui->cursor_off = true;
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
	}

	if (tui->sbofs == 0){
		tui->cursor_off = false;
		tui->cursor_upd = true;
	}
	arcan_tui_scroll_down(tui, tui->rows);

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
	return false;
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
		tui->dirty |= DIRTY_PARTIAL;
	}

	tui->in_select = false;
	tui->dirty |= DIRTY_CURSOR;
	return true;
}

static bool select_row(struct tui_context* tui)
{
	tsm_screen_selection_reset(tui->screen);
	int row = tsm_screen_get_cursor_y(tui->screen);
	tsm_screen_selection_start(tui->screen, 0, row);
	tsm_screen_selection_target(tui->screen, tui->cols-1, row);
	select_copy(tui);
	tui->dirty |= DIRTY_PARTIAL;
	tui->dirty |= DIRTY_CURSOR;
	tui->in_select = false;
	return true;
}

static bool scroll_lock(struct tui_context* tui)
{
	tui->scroll_lock = !tui->scroll_lock;
	if (!tui->scroll_lock){
		tui->sbofs = 0;
		tsm_screen_sb_reset(tui->screen);
		tui->cursor_upd = true;
		tui->cursor_off = false;
		tui->dirty |= DIRTY_PARTIAL;
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

struct lent {
	int ctx;
	const char* lbl;
	const char* descr;
	uint8_t vsym[5];
	bool(*ptr)(struct tui_context*);
	uint16_t initial;
	uint16_t modifiers;
};

#ifdef _DEBUG
#include <stdio.h>
static bool dump_dbg(struct tui_context* tui)
{
/* dump front-delta, front, back to different files */
	uint8_t* rbuf = NULL;
	size_t rbuf_sz = 0;
	tui_screen_tpack(tui,
		(struct tpack_gen_opts){.full = true, .synch = false}, &rbuf, &rbuf_sz);

	char buf[64];
	snprintf(buf, 64, "/tmp/tui.%d.delta.front.tpack", getpid());
	FILE* fout = fopen(buf, "w");
	if (fout){
		fwrite(rbuf, rbuf_sz, 1, fout);
		fclose(fout);
	}

	tui_screen_tpack(tui,
		(struct tpack_gen_opts){.full = true, .back = true}, &rbuf, &rbuf_sz);
	snprintf(buf, 64, "/tmp/tui.%d.full.back.tpack", getpid());
	fout = fopen(buf, "w");
	if (fout){
		fwrite(rbuf, rbuf_sz, 1, fout);
		fclose(fout);
	}

	tui_screen_tpack(tui,
		(struct tpack_gen_opts){0}, &rbuf, &rbuf_sz);
	snprintf(buf, 64, "/tmp/tui.%d.full.front.tpack", getpid());
	fout = fopen(buf, "w");
	if (fout){
		fwrite(rbuf, rbuf_sz, 1, fout);
		fclose(fout);
	}

	return true;
}
#endif

static const struct lent labels[] = {
	{1, "LINE_UP", "Scroll 1 row up", {}, scroll_up}, /* u+2191 */
	{1, "LINE_DOWN", "Scroll 1 row down", {}, scroll_down}, /* u+2192 */
	{1, "PAGE_UP", "Scroll one page up", {0xe2, 0x87, 0x9e}, page_up}, /* u+21de */
	{1, "PAGE_DOWN", "Scroll one page down", {0xe2, 0x87, 0x9e}, page_down}, /* u+21df */
	{0, "COPY_AT", "Copy word at cursor", {}, select_at}, /* u+21f8 */
	{0, "COPY_ROW", "Copy cursor row", {}, select_row}, /* u+21a6 */
	{0, "MOUSE_FORWARD", "Toggle mouse forwarding", {}, mouse_forward}, /* u+ */
	{1, "SCROLL_LOCK", "Arrow- keys to pageup/down", {}, scroll_lock, TUIK_SCROLLLOCK}, /* u+ */
	{1, "UP", "(scroll-lock) page up, UP keysym", {}, move_up}, /* u+ */
	{1, "DOWN", "(scroll-lock) page down, DOWN keysym", {}, move_down}, /* u+ */
	{0, "COPY_WND", "Copy window and scrollback", {}, copy_window}, /* u+ */
	{2, "SELECT_TOGGLE", "Switch select destination (wnd, clipboard)", {}, sel_sw}, /* u+ */
#ifdef _DEBUG
	{1, "DUMP", "Create a buffer/raster snapshot (/tmp/tui.pid.xxx)", {}, dump_dbg},
#endif
	{0}
};

void tui_expose_labels(struct tui_context* tui)
{
	const struct lent* cur = labels;
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(LABELHINT),
		.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
	};

/* send an empty label first as a reset */
	arcan_shmif_enqueue(&tui->acon, &ev);

/* then forward to a possible callback handler */
	size_t ind = 0;
	if (tui->handlers.query_label){
		while (true){
			struct tui_labelent dstlbl = {};
			if (!tui->handlers.query_label(tui,
			ind++, "ENG", "ENG", &dstlbl, tui->handlers.tag))
				break;

			snprintf(ev.ext.labelhint.label,
				COUNT_OF(ev.ext.labelhint.label), "%s", dstlbl.label);
			snprintf(ev.ext.labelhint.descr,
				COUNT_OF(ev.ext.labelhint.descr), "%s", dstlbl.descr);
			ev.ext.labelhint.subv = dstlbl.subv;
			ev.ext.labelhint.idatatype = dstlbl.idatatype ? dstlbl.idatatype : EVENT_IDATATYPE_DIGITAL;
			ev.ext.labelhint.modifiers = dstlbl.modifiers;
			ev.ext.labelhint.initial = dstlbl.initial;
			snprintf((char*)ev.ext.labelhint.vsym,
				COUNT_OF(ev.ext.labelhint.vsym), "%s", dstlbl.vsym);
			arcan_shmif_enqueue(&tui->acon, &ev);
		}
	}

/* expose a set of basic built-in controls shared by all users, and this is
 * dependent, for now, on the mode of the context.  The reason is that 'line-'
 * oriented mode with it's special scrolling, selection etc. complexity should
 * be refactored and pushed to a separate layer. */
	while(cur->lbl){
		switch(cur->ctx){
		case 0:
/* all */
		break;
		case 1:
/* not in 'alternate' */
			if (tui->flags & TUI_ALTERNATE){
				cur++;
				continue;
			}
		break;
		case 2:
/* only when not in copywnd */
			if (!tui->subseg){
				cur++;
				continue;
			}
		break;
		}

		snprintf(ev.ext.labelhint.label,
			COUNT_OF(ev.ext.labelhint.label), "%s", cur->lbl);
		snprintf(ev.ext.labelhint.descr,
			COUNT_OF(ev.ext.labelhint.descr), "%s", cur->descr);
		snprintf((char*)ev.ext.labelhint.vsym,
			COUNT_OF(ev.ext.labelhint.vsym), "%s", cur->vsym);
		cur++;

		ev.ext.labelhint.initial = cur->initial;
		ev.ext.labelhint.modifiers = cur->modifiers;
		arcan_shmif_enqueue(&tui->acon, &ev);
	}
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

static bool consume_label(struct tui_context* tui,
	arcan_ioevent* ioev, const char* label)
{
	const struct lent* cur = labels;

/* priority to our normal label handlers, and if those fail, forward */
	while(cur->lbl){
		if (strcmp(label, cur->lbl) == 0){
			if (cur->ptr(tui))
				return true;
			else
				break;
		}
		cur++;
	}

	bool res = false;
	if (tui->handlers.input_label){
		res |= tui->handlers.input_label(tui, label, true, tui->handlers.tag);

/* also send release if the forward was ok */
		if (res)
			tui->handlers.input_label(tui, label, false, tui->handlers.tag);
	}

	return res;
}

static bool forward_mouse(struct tui_context* tui)
{
	bool forward = tui->mouse_forward;
	if (
			!(tui->flags & TUI_MOUSE_FULL) &&
			(tui->modifiers & (TUIM_LCTRL | TUIM_RCTRL))){
		return !forward;
	}
	return forward;
}

void tui_input_event(
	struct tui_context* tui, arcan_ioevent* ioev, const char* label)
{
	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		bool pressed = ioev->input.translated.active;
		int sym = ioev->input.translated.keysym;
		int oldm = tui->modifiers;
		tui->modifiers = update_mods(tui->modifiers, sym, pressed);

/* note that after this point we always fake 'release' and forward as a
 * press->release on the same label within consume label */
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
			tui->sbofs = 0;
			tsm_screen_sb_reset(tui->screen);
			tui->dirty |= DIRTY_PARTIAL;
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

				if (forward_mouse(tui) && tui->handlers.input_mouse_motion){
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
					tui->dirty |= DIRTY_PARTIAL | DIRTY_CURSOR;
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
			if (forward_mouse(tui) && tui->handlers.input_mouse_button){
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
						tui->dirty |= DIRTY_PARTIAL;
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
							tui->dirty |= DIRTY_PARTIAL | DIRTY_CURSOR;
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
			if (ioev->subid == TUIBTN_WHEEL_UP){
				if (ioev->input.digital.active){

/* normal ALTSCREEN wheel doesn't really make sense, unless in
 * drag-select, map that to stepping selected row up/down?)
 * clients can still switch to manual mouse mode to get the other behavior */
					if ((tui->flags & TUI_ALTERNATE)){
						tui->handlers.input_key(tui,
							((tui->modifiers & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)) ? TUIK_PAGEUP : TUIK_UP),
							ioev->input.translated.scancode,
							0,
							ioev->subid, tui->handlers.tag
						);
					}
					else
						scroll_up(tui);
				}
			}
			else if (ioev->subid == TUIBTN_WHEEL_DOWN){
				if (ioev->input.digital.active){
					if ((tui->flags & TUI_ALTERNATE)){
						tui->handlers.input_key(tui,
							((tui->modifiers & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)) ? TUIK_PAGEDOWN : TUIK_DOWN),
							ioev->input.translated.scancode,
							0,
							ioev->subid, tui->handlers.tag
						);
					}
					else
						scroll_down(tui);
				}
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
				tui->dirty |= DIRTY_PARTIAL | DIRTY_CURSOR;
			}
		}
		else if (tui->handlers.input_misc)
			tui->handlers.input_misc(tui, ioev, tui->handlers.tag);
	}
}
