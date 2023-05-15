/*
 * This contains the functions that are slated for deprecation as we
 * factor out / get rid of the last traces of libtsm-screen.
 *
 * Eventually this functionality can then move to afsrv_terminal and
 * if we find a cleaner state machine / just build one in lash, also
 * drop it from there.
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

#include "arcan_shmif.h"
#include "arcan_tui.h"
#include "tui/tui_int.h"

#include "libtsm.h"
#include "libtsm_int.h"
#include "../../../util/utf8.c"

void tuiint_flag_cursor(struct tui_context* c)
{
	c->dirty |= DIRTY_CURSOR;
	c->inact_timer = -4;

	if (c->sbstat.ofs != c->sbofs ||
		c->sbstat.len != c->screen->sb_count){
		c->sbstat.ofs = c->sbofs;
		c->sbstat.len = c->screen->sb_count;
		arcan_tui_content_size(c,
			c->screen->sb_count - c->sbofs, c->screen->sb_count + c->rows, 0, 0);
	}
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

	tui_clipboard_push(tui, sel, len);
	free(sel);
}

#define flag_cursor tuiint_flag_cursor

void arcan_tui_invalidate(struct tui_context* c)
{
	if (!c)
		return;

	c->dirty |= DIRTY_FULL;
}

void arcan_tui_erase_sb(struct tui_context* c)
{
	if (!c)
		tsm_screen_clear_sb(c->screen);
}

void arcan_tui_refinc(struct tui_context* c)
{
	if (c && c->screen)
	tsm_screen_ref(c->screen);
}

void arcan_tui_refdec(struct tui_context* c)
{
	if (c && c->screen)
	tsm_screen_unref(c->screen);
}

void arcan_tui_erase_cursor_to_screen(struct tui_context* c, bool protect)
{
	if (c && c->screen){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_cursor_to_screen(c->screen, protect);
	}
}

void arcan_tui_erase_screen_to_cursor(struct tui_context* c, bool protect)
{
	if (c && c->screen){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_screen_to_cursor(c->screen, protect);
	}
}

void arcan_tui_erase_cursor_to_end(struct tui_context* c, bool protect)
{
	if (c && c->screen){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_cursor_to_end(c->screen, protect);
	}
}

void arcan_tui_erase_home_to_cursor(struct tui_context* c, bool protect)
{
	if (c && c->screen){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_home_to_cursor(c->screen, protect);
	}
}

void arcan_tui_erase_current_line(struct tui_context* c, bool protect)
{
	if (c && c->screen){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_current_line(c->screen, protect);
	}
}

void arcan_tui_erase_chars(struct tui_context* c, size_t num)
{
	if (c && c->screen){
		tsm_screen_inc_age(c->screen);
		tsm_screen_erase_chars(c->screen, num);
	}
}

void arcan_tui_set_tabstop(struct tui_context* c)
{
	if (c && c->screen)
		tsm_screen_set_tabstop(c->screen);
}

void arcan_tui_insert_lines(struct tui_context* c, size_t n)
{
	if (c && c->screen){
		tsm_screen_insert_lines(c->screen, n);
		flag_cursor(c);
	}
}

void arcan_tui_delete_lines(struct tui_context* c, size_t n)
{
	if (c && c->screen)
	tsm_screen_delete_lines(c->screen, n);
}

void arcan_tui_insert_chars(struct tui_context* c, size_t n)
{
	if (c && c->screen){
		flag_cursor(c);
		tsm_screen_insert_chars(c->screen, n);
	}
}

void arcan_tui_delete_chars(struct tui_context* c, size_t n)
{
	if (c && c->screen){
		flag_cursor(c);
		tsm_screen_delete_chars(c->screen, n);
	}
}

void arcan_tui_tab_right(struct tui_context* c, size_t n)
{
	if (c && c->screen){
		tsm_screen_tab_right(c->screen, n);
		flag_cursor(c);
	}
}

void arcan_tui_tab_left(struct tui_context* c, size_t n)
{
	if (c && c->screen){
		flag_cursor(c);
		tsm_screen_tab_left(c->screen, n);
	}
}

void arcan_tui_scroll_up(struct tui_context* c, size_t n)
{
	if (!c || !c->screen || (tsm_screen_get_flags(c->screen) & TUI_ALTERNATE))
		return;

	c->sbofs -= tsm_screen_sb_up(c->screen, n);
	arcan_tui_content_size(c,
		c->screen->sb_count - c->sbofs, c->screen->sb_count + c->rows, 0, 0);

	flag_cursor(c);
}

void arcan_tui_scroll_down(struct tui_context* c, size_t n)
{
	if (!c || !c->screen || (tsm_screen_get_flags(c->screen) & TUI_ALTERNATE))
		return;

	c->sbofs -= tsm_screen_sb_down(c->screen, n);
	c->sbofs = c->sbofs < 0 ? 0 : c->sbofs;

	flag_cursor(c);
}

void arcan_tui_reset_tabstop(struct tui_context* c)
{
	if (c && c->screen)
		tsm_screen_reset_tabstop(c->screen);
}

void arcan_tui_reset_all_tabstops(struct tui_context* c)
{
	if (c && c->screen)
		tsm_screen_reset_all_tabstops(c->screen);
}

void arcan_tui_move_up(struct tui_context* c, size_t n, bool scroll)
{
	if (c && c->screen){
		flag_cursor(c);
		tsm_screen_move_up(c->screen, n, scroll);
	}
}

void arcan_tui_move_down(struct tui_context* c, size_t n, bool scroll)
{
	if (c && c->screen){
		flag_cursor(c);
		int ss = tsm_screen_move_down(c->screen, n, scroll);
		flag_cursor(c);
	}
}

void arcan_tui_move_left(struct tui_context* c, size_t n)
{
	if (c && c->screen){
		flag_cursor(c);
		tsm_screen_move_left(c->screen, n);
	}
}

void arcan_tui_move_right(struct tui_context* c, size_t n)
{
	if (c && c->screen){
		flag_cursor(c);
		tsm_screen_move_right(c->screen, n);
	}
}

void arcan_tui_move_line_end(struct tui_context* c)
{
	if (c && c->screen){
		flag_cursor(c);
		tsm_screen_move_line_end(c->screen);
	}
}

void arcan_tui_move_line_home(struct tui_context* c)
{
	if (c && c->screen){
		flag_cursor(c);
		tsm_screen_move_line_home(c->screen);
	}
}

void arcan_tui_newline(struct tui_context* c)
{
	if (!c || !c->screen)
		return;

	unsigned last = c->screen->sb_count;
	int ss = tsm_screen_newline(c->screen);

/* only send new content hint if the scrollback state changed */
	if (last != c->screen->sb_count){
		arcan_tui_content_size(c,
			c->screen->sb_count - c->sbofs, c->screen->sb_count + c->rows, 0, 0);
	}

	flag_cursor(c);
}

int arcan_tui_set_margins(struct tui_context* c, size_t top, size_t bottom)
{
	if (c && c->screen)
		return tsm_screen_set_margins(c->screen, top, bottom);
	return -EINVAL;
}

static void tsm_log(void* data, const char* file, int line,
	const char* func, const char* subs, unsigned int sev,
	const char* fmt, va_list arg)
{
	fprintf(stderr, "[%d] %s:%d - %s, %s()\n", sev, file, line, subs, func);
	vfprintf(stderr, fmt, arg);
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

static bool page_up(struct tui_context* tui)
{
	if (!tui || !tui->screen || (tsm_screen_get_flags(tui->screen) & TUI_ALTERNATE))
		return true;

	tui->cursor_off = true;
	arcan_tui_scroll_up(tui, tui->rows);
	return true;
}

static bool page_down(struct tui_context* tui)
{
	if (!tui|| !tui->screen || (tsm_screen_get_flags(tui->screen) & TUI_ALTERNATE))
		return true;

	if (tui->sbofs > 0){
		tui->sbofs -= tui->rows;
		tui->sbofs = tui->sbofs < 0 ? 0 : tui->sbofs;
		tui->cursor_off = true;
	}

	if (tui->sbofs <= 0){
		tui->cursor_off = false;
		tuiint_flag_cursor(tui);
		tsm_screen_sb_reset(tui->screen);
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

static bool scroll_up(struct tui_context* tui)
{
	if (!tui || !tui->screen || (tsm_screen_get_flags(tui->screen) & TUI_ALTERNATE))
		return true;

	int nf = mod_to_scroll(tui->modifiers, tui->rows);
	arcan_tui_scroll_up(tui, nf);
	return true;
}

static bool scroll_down(struct tui_context* tui)
{
	if (!tui || !tui->screen || (tsm_screen_get_flags(tui->screen) & TUI_ALTERNATE))
		return true;

	int nf = mod_to_scroll(tui->modifiers, tui->rows);
	if (tui->sbofs > 0){
		arcan_tui_scroll_down(tui, nf);
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
		tuiint_flag_cursor(tui);
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

static bool forward_mouse(struct tui_context* tui)
{
	bool forward = tui->mouse_forward;
	if (!(tsm_screen_get_flags(tui->screen) & TUI_ALTERNATE) &&
			!(tui->flags & TUI_MOUSE_FULL) &&
			(tui->modifiers & (TUIM_LCTRL | TUIM_RCTRL))){
		return !forward;
	}
	return forward;
}

/*
 * Old version of input.c that uses tsm selection for most mouse actions and scrolling
 */
struct lent {
	const char* lbl;
	const char* descr;
	uint8_t vsym[5];
	bool(*ptr)(struct tui_context*);
	uint16_t initial;
	uint16_t modifiers;
};

static const struct lent labels_alt[] =
{
	{"COPY_AT", "Copy word at cursor", {}, select_at}, /* u+21f8 */
	{"COPY_ROW", "Copy cursor row", {}, select_row}, /* u+21a6 */
	{"MOUSE_FORWARD", "Toggle mouse forwarding", {}, mouse_forward}, /* u+ */
};

static const struct lent labels[] =
{
	{"LINE_UP", "Scroll 1 row up", {}, scroll_up}, /* u+2191 */
	{"LINE_DOWN", "Scroll 1 row down", {}, scroll_down}, /* u+2192 */
	{"PAGE_UP", "Scroll one page up", {0xe2, 0x87, 0x9e}, page_up}, /* u+21de */
	{"PAGE_DOWN", "Scroll one page down", {0xe2, 0x87, 0x9e}, page_down}, /* u+21df */
	{"COPY_AT", "Copy word at cursor", {}, select_at}, /* u+21f8 */
	{"COPY_ROW", "Copy cursor row", {}, select_row}, /* u+21a6 */
	{"MOUSE_FORWARD", "Toggle mouse forwarding", {}, mouse_forward}, /* u+ */
	{"SCROLL_LOCK", "Arrow- keys to pageup/down", {}, scroll_lock, TUIK_SCROLLLOCK}, /* u+ */
	{"UP", "(scroll-lock) page up, UP keysym", {}, move_up}, /* u+ */
	{"DOWN", "(scroll-lock) page down, DOWN keysym", {}, move_down}, /* u+ */
};

bool legacy_consume_label(struct tui_context* tui, const char* label)
{
	size_t cap = COUNT_OF(labels);
	const struct lent* cur = labels;

	if (tsm_screen_get_flags(tui->screen) & TUI_ALTERNATE){
		cap = COUNT_OF(labels_alt);
		cur = labels_alt;
	}

	for (size_t i = 0; i < cap; i++){
		if (strcmp(cur[i].lbl, label) == 0){
			if (cur[i].ptr(tui))
				return true;
			else
				break;
		}
	}

	return false;
}

static void tsm_input_eh(
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

		if (label[0] && tui->handlers.input_label){
			bool res = tui->handlers.input_label(tui, label, true, tui->handlers.tag);

/* also send release if the forward was ok */
			if (res){
				tui->handlers.input_label(tui, label, false, tui->handlers.tag);
				return;
			}
		}

/* modifiers doesn't get set for the symbol itself which is a problem
 * for when we want to forward modifier data to another handler like mbtn */
		if (sym >= 300 && sym <= 314)
			return;

/* reset scrollback on normal input */
		if (oldm == tui->modifiers && tui->sbofs != 0){
			tuiint_flag_cursor(tui);
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
			int x, y;
			if (!arcan_shmif_mousestate_ioev(&tui->acon, tui->mouse_state, ioev, &x, &y))
				return;

			tui->mouse_x = x / tui->cell_w;
			tui->mouse_y = y / tui->cell_h;

			bool upd = false;
			bool dy = false;

			if (tui->mouse_x != tui->lm_x){
				tui->lm_x = tui->mouse_x;
				upd = true;
			}
			if (tui->mouse_y != tui->lm_y){
				tui->lm_y = tui->mouse_y;
				upd = true;
				dy = true;
			}

			if (forward_mouse(tui) && tui->handlers.input_mouse_motion){
				if (upd)
				tui->handlers.input_mouse_motion(tui, false,
					tui->mouse_x, tui->mouse_y, tui->modifiers, tui->handlers.tag);
				return;
			}

			if (!tui->in_select || !upd)
				return;

/* we use the upper / lower regions as triggers for scrollback + selection,
 * with a magnitude based on how far "off" we are - the actual scrolling takes
 * n ticks of inactivity before it starts stepping. */
			if (!tui->mouse_y && dy)
				tui->scrollback = -5;
			else if (tui->mouse_y == tui->rows - 1 && dy)
				tui->scrollback = 5;
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
					if (tsm_screen_get_flags(tui->screen) & TUI_ALTERNATE){
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
					if (tsm_screen_get_flags(tui->screen) & TUI_ALTERNATE){
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

bool legacy_query_label(
	struct tui_context* c, int ind, struct tui_labelent* dst)
{
	size_t cap = COUNT_OF(labels);
	const struct lent* set = labels;

	if (!c || !c->screen || (tsm_screen_get_flags(c->screen) & TUI_ALTERNATE)){
		cap = COUNT_OF(labels_alt);
		set = labels_alt;
	}

	if (ind >= cap)
		return false;

	const struct lent* ent = &set[ind];
	snprintf(dst->label, COUNT_OF(dst->label), "%s", ent->lbl);
	snprintf(dst->descr, COUNT_OF(dst->descr), "%s", ent->descr);
	snprintf((char*)dst->vsym, COUNT_OF(dst->vsym), "%s", ent->vsym);
	dst->initial = ent->initial;
	dst->modifiers = ent->modifiers;

	return true;
}

void tsm_cursor_eh(struct tui_context* c)
{
	if (c->sbstat.ofs != c->sbofs ||
		c->sbstat.len != c->screen->sb_count){
		c->sbstat.ofs = c->sbofs;
		c->sbstat.len = c->screen->sb_count;
		arcan_tui_content_size(c,
			c->screen->sb_count - c->sbofs, c->screen->sb_count + c->rows, 0, 0);
	}
}

static void tsm_reset_eh(struct tui_context* c)
{
}

static void tsm_destroy_eh(struct tui_context* c)
{
	tsm_utf8_mach_free(c->ucsconv);
}

/*
 * This is used to translate from the virtual screen in TSM to our own front/back
 * buffer structure that is then 'rendered' into the packing format used in
 * tui_raster.c
 *
 * Eventually this will be entirely unnecessary and we can rightfully kill off
 * TSM and ust draw into our buffers directly, as the line wrapping / tracking
 * behavior etc. doesn't really match how things are structured anymore
 */
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
		tui->dirty |= DIRTY_PARTIAL;
	}

	return 0;
}

static void tsm_refresh_eh(struct tui_context* tui)
{
/* synch vscreen -> screen buffer
	arcan_tui_set_flags(tui, tsm_screen_get_flags(tui->screen));
 */

/* this will repeatedly call tsm_draw_callback which, in turn, will update
 * the front buffer with new glyphs. */
	tui->age = tsm_screen_draw(tui->screen, tsm_draw_callback, tui);
}

static void tsm_resize_eh(struct tui_context* tui)
{
	tsm_screen_resize(tui->screen, tui->cols, tui->rows);

/* don't redraw while we have an update pending or when we
 * are in an invisible state */
	if (tui->inactive)
		return;

/* dirty will be set from screen resize, fix the pad region */
	if (tui->dirty & DIRTY_FULL){
		if (tui->screen){
			tsm_screen_selection_reset(tui->screen);
		}
	}
	else
/* "always" erase previous cursor, except when cfg->nal screen state explicitly
 * say that cursor drawing should be turned off */
		;
}

static void tsm_cursor_lookup(struct tui_context* c, size_t* x, size_t* y)
{
	*y = tsm_screen_get_cursor_y(c->screen);
	*x = tsm_screen_get_cursor_x(c->screen);
}

void arcan_tui_allow_deprecated(struct tui_context* c)
{
	if (c->screen)
		return;

	if (0 != tsm_utf8_mach_new(&c->ucsconv))
		return;

	c->hooks.reset = tsm_reset_eh;
	c->hooks.cursor_update = tsm_cursor_eh;
	c->hooks.input = tsm_input_eh;
	c->hooks.destroy = tsm_destroy_eh;
	c->hooks.refresh = tsm_refresh_eh;
	c->hooks.resize = tsm_resize_eh;
	c->hooks.cursor_lookup = tsm_cursor_lookup;

	arcan_shmif_mousestate_setup(&c->acon, false, c->mouse_state);
	tsm_screen_new(c, &c->screen, tsm_log, c);
	tsm_screen_set_max_sb(c->screen, 1000);
	c->hooks.resize(c);
}
