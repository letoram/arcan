/*
 * Arcan Text-Oriented User Interface Library, Extensions
 * Copyright: Bjorn Stahl
 * License: 3-clause BSD
 * Description: Implementation of a readline/linenoise replacement.
 *
 * Incomplete:
 *  Multiline support
 *  Mouse selection
 *  Native popup
 *  Extended suggestion form (with formatting lines and cursor control)
 *
 * Unknowns:
 *  Geohint (LTR, RTL, double-width)
 *  Accessibility?
 *  .readline rc file?
 */
#include <unistd.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <ctype.h>

#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../../arcan_tui_readline.h"
#include "../../tui/tui_int.h"

#define READLINE_MAGIC 0xfefef00d

struct readline_meta {
	uint32_t magic;
	struct tui_readline_opts opts;
	bool in_refresh;

/* re-built on resize */
	size_t start_col, stop_col, start_row, stop_row;

	char* work;        /* UTF-8 */
	size_t work_ofs;   /* in bytes, code-point boundary aligned */
	size_t work_len;   /* in code-points */
	size_t work_sz;    /* in bytes */
	size_t cursor;     /* offset in bytes from start to cursor */

/* -1 as ok, modified by verify callback */
	ssize_t broken_offset;

/* suggestion && tab completion feature (externally managed) */
	const char* current_suggestion;
	bool show_completion;
	const char** completion;
	char* suggest_prefix;
	size_t suggest_prefix_sz;
	char* suggest_suffix;
	size_t suggest_suffix_sz;
	size_t completion_sz;
	size_t completion_width;
	size_t completion_mode;
	size_t completion_pos;
	int completion_hint;

/* used to colorize the data part when drawing, offsets are in codepoints */
	struct tui_screen_attr* line_format;
	size_t* line_format_ofs;
	size_t line_format_sz;

/* if we overfit-, this might be drawn with middle truncated to 2/3 of capacity */
	const struct tui_cell* prompt;
	size_t prompt_len;
	int finished;

/* history feature (externally managed) */
	const char** history;
	char* in_history;
	size_t history_sz;
	size_t history_pos;

/* restore on release */
	struct tui_cbcfg old_handlers;
	int old_flags;
};

/* generic 'insert at cursor' */
static void add_input(struct tui_context* T,
	struct readline_meta* M, const char* u8, size_t len, bool noverify);

static void synch_completion(struct tui_context* T, struct readline_meta* M);
static void delete_last_word(struct tui_context* T, struct readline_meta* M);

static void replace_str(
	struct tui_context* T, struct readline_meta* M, const char* str, size_t len);

static void release_line_format(struct readline_meta* M)
{
	if (!M->line_format)
		return;

	free(M->line_format);
	free(M->line_format_ofs);
	M->line_format = NULL;
	M->line_format_ofs = NULL;
	M->line_format_sz = 0;
}

static size_t utf8len(size_t end, const char* msg)
{
	size_t pos = 0;
	size_t len = 0;

	while (pos < end){
		if ((msg[pos++] & 0xc0) != 0x80)
			len++;
	}
	return len;
}

static size_t utf8fwd(size_t pos, const char* msg, size_t max)
{
	if (pos == max)
		return max;

	pos++;
	while (msg[pos] && (msg[pos] & 0xc0) == 0x80){
		pos++;
	}

	return pos;
}

static size_t utf8back(size_t pos, const char* msg)
{
	if (!pos)
		return pos;

	pos--;
	while (pos && (msg[pos] & 0xc0) == 0x80){
		pos--;
	}

	return pos;
}

static void reset(struct readline_meta* M)
{
	M->finished = 0;
	M->work[0] = 0;
	M->work_ofs = 0;
	M->work_len = 0;
	M->cursor = 0;
	M->history = NULL;
	M->history_sz = 0;
	M->in_history = NULL;
}

static void verify(struct tui_context* T, struct readline_meta* M)
{
	if (!M->opts.verify)
		return;

	M->broken_offset = M->opts.verify(
		(const char*)M->work, M->cursor, M->show_completion, M->old_handlers.tag);
}

static void drop_completion(
	struct tui_context* T, struct readline_meta* M, bool run)
{
	if (!M->show_completion)
		return;

	if (!M->completion){
		return;
	}

/* this looks like nop, but helped debugging to have the same entry-point for
 * all ways completion can be activated or not for easy access breakpoint */
	if (!run)
		return;

	const char* msg = M->completion[M->completion_pos];

	switch (M->completion_mode){
/* Delete the word first, but only if we are actually 'on' a word. This needs
 * to cover the edge cases of just having added a space and starting on a new
 * word either through cursor- stepping (1) or inserting at the end. (2) */
		case READLINE_SUGGEST_WORD:
			if (
					(M->work[M->cursor] && !isspace(M->work[M->cursor])) || /* (1) */
					(!M->work[M->cursor] && M->cursor && !isspace(M->work[M->cursor-1]))){ /* (2) */
				delete_last_word(T, M);
				if (M->cursor)
					add_input(T, M, " ", 1, true);
			}
		break;

		case READLINE_SUGGEST_INSERT:
		break;

		case READLINE_SUGGEST_SUBSTITUTE:
			M->work[0] = 0;
			M->work_ofs = 0;
			M->work_len = 0;
			M->cursor = 0;
		break;
	}

	if (M->suggest_prefix)
		add_input(T, M, M->suggest_prefix, M->suggest_prefix_sz, true);

	while (*msg){
		uint32_t ch;
		ssize_t step = arcan_tui_utf8ucs4(msg, &ch);
		if (step <= 0)
			break;
		add_input(T, M, msg, step, true);
		msg += step;
	}

	if (M->suggest_suffix)
		add_input(T, M, M->suggest_suffix, M->suggest_suffix_sz, true);
}

/* find the codepoint that is within the next format offset (if any) ofs is in
 * bytes so linear search (not cheap but small n and only circumstantial use,
 * simple optimization would otherwise be to assume ofs will grow and cache
 * ch+fmt_i between calls */
static struct tui_screen_attr* get_attr_for_ofs(struct readline_meta* M, size_t ofs)
{
	size_t ch = 0;
	size_t fmt_i = 0;

	if (!M->line_format)
		return NULL;

/* invariant: attr applies from 0, ofs to get attr from is also at 0 */
	struct tui_screen_attr* fmt = NULL;
	if (!M->line_format_ofs[0])
		fmt = &M->line_format[0];

	for (size_t i = 0; i < M->work_sz &&
			i <= ofs; i = utf8fwd(i, M->work, M->work_sz)){

		while (M->line_format_ofs[fmt_i] <= ch){
			fmt_i++;
			if (fmt_i >= M->line_format_sz)
				break;

			fmt = &M->line_format[fmt_i];
		}

		ch = ch + 1;
	}

	return fmt;
}

static size_t u8len(const char* buf)
{
	size_t len = 0;
	while (*buf){
		uint32_t ucs4 = 0;
		ssize_t step = arcan_tui_utf8ucs4(buf, &ucs4);
		len++;
		if (step <= 0){
			buf++;
		}
		else
			buf += step;
	}
	return len;
}

/*
 * Whether the completion is in the popup form or in the 'embedded' form we
 * draw it much the same. The popup form simply also hints / reanchors to
 * its parent.
 *
 * Sizing the completion in popup mode is more complex and we defer the
 * decision to the server end and just provide the content dimensions.
 */
static void draw_completion(
	struct tui_context* T, struct readline_meta* M, struct tui_context* P)
{
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);
	size_t cx = 0, cy = 0;
	arcan_tui_cursorpos(T, &cx, &cy);

/* can't really show popup in this format unless we have the 'separate window'
 * form active */
	if (rows < 2)
		return;

/* Based on window dimensions and cursor position, figure out the number of
 * items to draw. If we are closer to the top, position it above - otherwise
 * below. */
	ssize_t step = 1;
	if (rows - cy < (rows >> 1))
		step = -1;

	struct tui_screen_attr attr = arcan_tui_defcattr(T, TUI_COL_UI);

	size_t maxw = 0;
	for (size_t i = 0, j = cy + step;
		!M->opts.completion_compact &&
		i < M->completion_sz && j >= 0 && j < rows; i++, j += step){
		size_t len = 0;
		len += u8len(M->completion[i]);

		if (M->completion_hint & READLINE_SUGGEST_HINT){
			const char* hint = M->completion[i];
			len += u8len(&hint[strlen(hint)] + 1 + 1);
		}

/* leave room for the > */
		len += 3;
		if (len > maxw)
			maxw = len;
	}

/* Other style choice when we draw on canvas like this is if to set the width
 * to match all elements (i.e. find the widests and pad with empty), left-align
 * or right-align vs. cursor. */
	size_t lasty = 0;
	maxw += cx;

	for (ssize_t i = 0, j = cy + step;
		i < M->completion_sz && j >= 0 && j < rows; i++, j += step){
		arcan_tui_move_to(T, cx, j);
		lasty = j;

		if (i == M->completion_pos)
			arcan_tui_writeu8(T, (const uint8_t*) "> ", 2, &attr);

		arcan_tui_writestr(T, M->completion[i], &attr);

/*
 * Alternate intepretation is two tightly packed strings with the second
 * being for presentation only.
 */
		if (M->completion_hint & READLINE_SUGGEST_HINT){
			const char* hint = M->completion[i];
			hint = &hint[strlen(hint)] + 1;
			arcan_tui_write(T, ' ', &attr);
			arcan_tui_writestr(T, hint, &attr);
		}

/*
 * In the non-compact presentation mode pad to the widest visible entry
 */
		size_t tx, ty;
		arcan_tui_cursorpos(T, &tx, &ty);
		for (; !M->opts.completion_compact && tx < maxw; tx++)
			arcan_tui_write(T, ' ', &attr);
	}

/*
 * if a border is desired (requires padding and no popup) walk again and add that flag
 */
	if (!M->opts.completion_compact){
		size_t x1 = cx;
		size_t x2 = maxw - 1;
		size_t y1 = cy + step, y2 = lasty;
		if (lasty < cy + step){
			y1 = lasty;
			y2 = cy + step;
		}
		arcan_tui_write_border(T, attr, x1, y1, x2, y2, 0);
	}

	arcan_tui_move_to(T, cx, cy);
}

static void refresh(struct tui_context* T, struct readline_meta* M)
{
	size_t rows, cols;

/* have a guard against a recolor handler that triggers the original refresh */
	if (M->in_refresh)
		return;
	M->in_refresh = true;

	arcan_tui_dimensions(T, &rows, &cols);

/* first redraw everything so that we are sure we have synched contents */
	if (M->old_handlers.recolor){
		M->old_handlers.recolor(T, M->old_handlers.tag);
	}

/* these are resolved on resize and calls to update margin */
	size_t x1 = M->start_col;
	size_t x2 = M->stop_col;
	size_t y1 = M->start_row;
	size_t y2 = M->stop_row;

/* can't do nothing if we don't have the space */
	if (x1 > x2 || y1 > y2)
		goto out;

	size_t cx = 0, cy = 0;
	size_t limit = (x2 - x1) + 1;
	if (limit < 3)
		goto out;

	arcan_tui_move_to(T, x1, y1);

/* standard prompt attribute */
/* then error alert if we have a bad offset */
	struct tui_screen_attr alert = {
		.aflags = TUI_ATTR_COLOR_INDEXED,
		.fc[0] = TUI_COL_WARNING,
		.bc[0] = TUI_COL_WARNING
	};

	struct tui_screen_attr hint = alert;

/* reset our reserved range to the default attribute as that might have
 * a different background style in order to indicate 'input' field */
	arcan_tui_erase_region(T, x1, y1, x2, y2, NULL);

/* if we don't need to truncate or slide the edit window,
 * or do multiline, things are 'easy' */
	size_t prompt_len = M->prompt_len;

/* cur allocation down to match ~1/3 of the available space, suffix
 * with ..> */
	size_t ul = limit / 3;
	if (prompt_len > ul && prompt_len + M->work_len > limit){

		if (ul > 2){
			for (size_t i = 0; i < ul - 2 && i < prompt_len; i++, limit--)
				arcan_tui_write(T, M->prompt[i].ch, &M->prompt[i].attr);
		}

		arcan_tui_write(T, '.', NULL);
		arcan_tui_write(T, '.', NULL);
		limit -= 2;
	}
/* draw prompt like normal */
	else {
		for (size_t i = 0; i < M->prompt_len; i++){
			arcan_tui_write(T, M->prompt[i].ch, &M->prompt[i].attr);
		}

		limit = limit - prompt_len;
	}

/* if the core text does not fit, start with the cursor position, scan forwards
 * and backwards until filled - this is prep:ed to be content dependent for
 * double-width etc. later */
	size_t pos = 0;
	size_t pos_cp = 0;

	if (M->work_len > limit){
		pos = M->cursor;
		size_t tail = M->cursor;
		size_t count = limit;

		while(count){
			if (pos){
				while(pos && (M->work[--pos] & 0xc0) == 0x80){}
				count--;
			}

			if (count && tail < M->work_ofs){
				while(tail < M->work_ofs && (M->work[++tail] & 0xc0) == 0x80){}
				count--;
			}
		}
	}

	for (size_t i = 0; i < M->work_len && i < limit; i++){
		uint32_t ch;
		if (pos == M->cursor){
			arcan_tui_cursorpos(T, &cx, &cy);
		}
		ssize_t step = arcan_tui_utf8ucs4((char*) &M->work[pos], &ch);
		if (M->opts.mask_character)
			ch = M->opts.mask_character;

		if (step > 0)
			pos += step;

		struct tui_screen_attr* attr = get_attr_for_ofs(M, pos);
		if (M->broken_offset != -1 && pos >= M->broken_offset)
			arcan_tui_write(T, ch, &alert);
		else
			arcan_tui_write(T, ch, attr);
	}

	if (M->show_completion && M->completion && M->completion_sz){
		draw_completion(T, M, M->opts.popup);
	}
/* toggle the hidden property if not already set */
	else if (M->opts.popup && !M->opts.popup->last_constraints.hide){
		arcan_tui_wndhint(M->opts.popup, T,
			(struct tui_constraints){
				.hide = true
			}
		);
	}

	const char* cs = M->current_suggestion;
	if (cs){
/* writing out the suggestion will move the cursor to a different position if
 * the cursor is at the end, so remember before writing so we can jump back */
		if (!cx)
			arcan_tui_cursorpos(T, &cx, &cy);

		for (size_t i = M->work_len, j = 0; cs[j] && i < limit; i++, j++){
			uint32_t ch;
			ssize_t step = arcan_tui_utf8ucs4((char*) &cs[j], &ch);
			if (step > 0)
				j += step;
			arcan_tui_write(T, ch, &hint);
		}
	}

	if (cx)
		arcan_tui_move_to(T, cx, cy);

out:
	M->in_refresh = false;
}

static bool validate_context(struct tui_context* T, struct readline_meta** M)
{
	if (!T)
		return false;

	struct tui_cbcfg handlers;
	arcan_tui_update_handlers(T, NULL, &handlers, sizeof(struct tui_cbcfg));

	struct readline_meta* ch = handlers.tag;
	if (!ch || ch->magic != READLINE_MAGIC)
		return false;

	*M = ch;
	return true;
}

void arcan_tui_readline_suggest_fix(
	struct tui_context* T, const char* pre, const char* suf)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (M->suggest_prefix){
		free(M->suggest_prefix);
		M->suggest_prefix = NULL;
		M->suggest_prefix_sz = 0;
	}

	if (M->suggest_suffix){
		free(M->suggest_suffix);
		M->suggest_suffix = NULL;
		M->suggest_suffix_sz = 0;
	}

	if (pre){
		size_t nb = strlen(pre);
		char* copy = malloc(nb + 1);
		if (!copy)
			return;

		memcpy(copy, pre, nb);
		copy[nb] = '\0';
		M->suggest_prefix = copy;
		M->suggest_prefix_sz = nb;
	}
	if (suf){
		size_t nb = strlen(suf);
		char* copy = malloc(nb + 1);
		if (!copy)
			return;

		memcpy(copy,suf, nb);
		copy[nb] = '\0';
		M->suggest_suffix = copy;
		M->suggest_suffix_sz = nb;
	}
}

static void step_cursor_left(struct tui_context* T, struct readline_meta* M)
{
	if (!M->cursor)
		return;

	M->cursor = utf8back(M->cursor, M->work);
	refresh(T, M);
}

static void step_cursor_right(struct tui_context* T, struct readline_meta* M)
{
	if (M->cursor < M->work_ofs)
		M->cursor = utf8fwd(M->cursor, M->work, M->work_ofs);

	refresh(T, M);
}

static bool delete_at_cursor(struct tui_context* T, struct readline_meta* M)
{
	if (M->cursor == M->work_ofs)
		return true;

	size_t c_cursor = utf8fwd(M->cursor, M->work, M->work_ofs);
	memmove(&M->work[M->cursor], &M->work[c_cursor], M->work_ofs - c_cursor);
	M->work[M->work_ofs] = '\0';
	M->work_ofs--;
	M->work_len = utf8len(M->work_ofs, M->work);

	refresh(T, M);

	return true;
}

static bool erase_at_cursor(struct tui_context* T, struct readline_meta* M)
{
	if (!M->cursor || !M->work_len)
		return true;

/* sweep to previous utf8 start */
	size_t c_cursor = utf8back(M->cursor, M->work);
	size_t len = M->cursor - c_cursor;

/* and either '0 out' if at end, or slide */
	if (M->cursor == M->work_ofs){
		memset(&M->work[c_cursor], '\0', len);
	}
	else
		memmove(&M->work[c_cursor], &M->work[M->cursor], M->work_ofs - M->cursor);

	M->cursor = c_cursor;
	M->work_len--;
	M->work_ofs -= len;

/* check if we are broken at some offset */
	verify(T, M);
	refresh(T, M);

	return true;
}

static bool add_linefeed(struct tui_context* T, struct readline_meta* M)
{
	if (M->show_completion && M->completion_sz){
		drop_completion(T, M, true);
		verify(T, M);
		refresh(T, M);
	}

	if (!M->opts.multiline){
/* if normal validation has refused it, don't allow commit */
		if (-1 != M->broken_offset){
			return true;
		}
/* treat as commit */
		M->finished = 1;
	}

	return true;
}

static void delete_last_word(struct tui_context* T, struct readline_meta* M)
{
/* 0. early out / no-op */
	if (!M->cursor)
		return;

/* 1. ignore whitespace */
	size_t cursor = M->cursor;
	if (cursor == M->work_ofs)
		cursor--;

	while (cursor && isspace(M->work[cursor]))
		cursor = utf8back(cursor, M->work);

/* 2. find start */
	size_t beg = cursor;
	while (beg && !isspace(M->work[beg]))
		beg = utf8back(beg, M->work);

/* 3. find end */
	size_t end = cursor;
	while (end < M->work_ofs && !isspace(M->work[end])){
		end = utf8fwd(end, M->work, M->work_ofs);
	}
	if (end > M->work_ofs)
		end = M->work_ofs;

	M->cursor = beg;
	size_t ntr = end - beg;
	M->work_ofs -= ntr;
	memmove(&M->work[beg], &M->work[end], M->work_ofs);
	M->work_len = utf8len(M->work_ofs, M->work);

	refresh(T, M);
}

static void cut_to_eol(struct tui_context* T, struct readline_meta* M)
{
	if (!M->work)
		return;

	arcan_tui_copy(T, &M->work[M->cursor]);

	M->work[M->cursor] = '\0';
	M->work_ofs = M->cursor;
	M->work_len = utf8len(M->cursor, M->work);

	verify(T, M);
	refresh(T, M);
}

static void cut_to_sol(struct tui_context* T, struct readline_meta* M)
{
	if (!M->work)
		return;

	memmove(M->work, &M->work[M->cursor], M->work_ofs - M->cursor);
	M->work[M->cursor] = '\0';
	arcan_tui_copy(T, M->work);
	M->work_ofs = M->cursor;
	M->cursor = 0;
	M->work_len = utf8len(M->work_ofs, M->work);

	verify(T, M);
	refresh(T, M);
}

static void on_utf8_paste(
	struct tui_context* T, const uint8_t* u8, size_t len, bool cont, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (M->opts.paste_forward){
		if (M->old_handlers.utf8)
			return M->old_handlers.utf8(T, u8, len, cont, M->old_handlers.tag);
	}

/* temporarily block completion */
	bool old_tc = M->opts.tab_completion;
	M->opts.tab_completion = false;

/* split up into multiple calls based on filter character if needed */
	if (M->opts.filter_character){
		for (size_t i = 0; i < len;){
			uint32_t ch;
			size_t step = arcan_tui_utf8ucs4((char*)&u8[i], &ch);
			if (M->opts.filter_character(ch, M->work_len + 1, M->old_handlers.tag))
				add_input(T, M, (char*)&u8[i], step, false);
			i += step;
		}
	}
	else {
		add_input(T, M, (char*)u8, len, false);
	}
	M->opts.tab_completion = old_tc;

	verify(T, M);
	refresh(T, M);
}

static bool on_utf8_input(
	struct tui_context* T, const char* u8, size_t len, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return true;

/* difference to gnu-readline here is that history is immutable */
	if (M->in_history){
		free(M->in_history);
		M->in_history = NULL;
	}

/* just forward escape in any form */
	if (*u8 == '\033')
		return false;

/* if it is a commit, refuse on validation failure - 0-length should
 * be filtered through filter_character so no reason to forward it here */
	if (*u8 == '\n' || *u8 == '\r')
		return add_linefeed(T, M);

	if (*u8 == '\t' && M->opts.tab_completion){
		synch_completion(T, M);
		return true;
	}

/* backspace */
	else if (*u8 == 0x08)
		return erase_at_cursor(T, M);

/* first filter things out */
	if (M->opts.filter_character){
		uint32_t ch;
		arcan_tui_utf8ucs4(u8, &ch);

		if (!M->opts.filter_character(ch, M->work_len + 1, M->old_handlers.tag)){
			return true;
		}
	}

	add_input(T, M, u8, len, false);

/* missing - if we have a valid suggestion popup, rebuild it with
 * the new filter-set and reset the cursor in the popup to the current position */

	refresh(T, M);
	return true;
}

static void step_history(
	struct tui_context* T, struct readline_meta* M, ssize_t step)
{
	if (!M->history || !M->history_sz)
		return;

/* first time stepping, save the current work string */
	if (!M->in_history){
		if (step < 0)
			return;

		M->in_history = strdup(M->work);
		if (!M->in_history)
			return;

		replace_str(T, M,
			M->history[M->history_pos], strlen(M->history[M->history_pos]));
		return;
	}

/* are we stepping back into normal mode? */
	if (!M->history_pos && step < 0){
		replace_str(T, M, M->in_history, strlen(M->in_history));
		free(M->in_history);
		M->in_history = NULL;
		return;
	}

/* step and clamp then update */
	M->history_pos += step > 0 ? 1 : -1;
	if (M->history_pos >= M->history_sz)
		M->history_pos = M->history_sz - 1;

	replace_str(T, M,
		M->history[M->history_pos], strlen(M->history[M->history_pos]));
}

static void synch_completion(struct tui_context* T, struct readline_meta* M)
{
	M->broken_offset = M->opts.verify(
		(const char*)M->work, M->cursor, true, M->old_handlers.tag);

/* just the one option? could just autocomplete - otoh better to let the dev
 * chose with the suggestion form */
	if (M->completion_sz == 1){

	}

/* the call into verify might have defined a completion set, if so, show it. */
	M->show_completion = true;
	if (M->completion)
		refresh(T, M);
}

void on_key_input(struct tui_context* T,
	uint32_t keysym, uint8_t scancode, uint16_t mods, uint16_t subid, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

/* some might want to do this all by themselves */
	if (M->opts.block_builtin_bindings){
		if (M->old_handlers.input_key)
			M->old_handlers.input_key(T,
				keysym, scancode, mods, subid, M->old_handlers.tag);
		return;
	}

	bool meta = mods & (TUIM_LCTRL | TUIM_RCTRL);
	if (meta){
		if (keysym == TUIK_RETURN){
			M->finished = 1;
		}
		else if (keysym == TUIK_L){
			arcan_tui_readline_reset(T);
		}
		else if (keysym == TUIK_D){
			if (!M->work_ofs){
				if (M->opts.allow_exit){
					arcan_tui_readline_reset(T);
					M->finished = -1;
					return;
				}
			}
			else
				delete_at_cursor(T, M);
		}
		else if (keysym == TUIK_T){
/* MISSING: swap with previous */
		}
		else if (keysym == TUIK_B){
			step_cursor_left(T, M);
			refresh(T, M);
		}
		else if (keysym == TUIK_F){
			step_cursor_right(T, M);
			refresh(T, M);
		}
		else if (keysym == TUIK_K){
			cut_to_eol(T, M);
		}
		else if (keysym == TUIK_U){
			cut_to_sol(T, M);
		}
		else if (keysym == TUIK_P){
			step_history(T, M, 1);
		}
		else if (keysym == TUIK_N){
			step_history(T, M, -1);
		}
		else if (keysym == TUIK_A){
/* start of line, same as HOME */
			M->cursor = 0;
			refresh(T, M);
		}
		else if (keysym == TUIK_E){
/* end of line, same as END */
			M->cursor = M->work_ofs;
			refresh(T, M);
		}
		else if (keysym == TUIK_W){
/* delete last word */
			delete_last_word(T, M);
		}
		else if (keysym == TUIK_TAB){
			synch_completion(T, M);
		}
		if (M->old_handlers.input_key){
			M->old_handlers.input_key(T,
				keysym, scancode, mods, subid, M->old_handlers.tag);
		}
		return;
	}

	if (keysym == TUIK_LEFT){
		drop_completion(T, M, false);
		step_cursor_left(T, M);
		verify(T, M);
		refresh(T, M);
	}
	else if (keysym == TUIK_RIGHT){
		drop_completion(T, M, M->cursor == M->work_ofs);
		verify(T, M);
		refresh(T, M);
		step_cursor_right(T, M);
	}
	else if (keysym == TUIK_UP){
		if (M->show_completion && M->completion_sz > 0){
			if (!M->completion_pos)
				M->completion_pos = M->completion_sz - 1;
			else
				M->completion_pos--;
			refresh(T, M);
		}
		else
			step_history(T, M, 1);
	}
	else if (keysym == TUIK_DOWN){
		if (M->show_completion && M->completion_sz > 0){
		 M->completion_pos = (M->completion_pos + 1) % M->completion_sz;
		 refresh(T, M);
		}
		else
			step_history(T, M, -1);
	}
	else if (keysym == TUIK_ESCAPE){
		if (M->show_completion && M->completion){
			M->show_completion = false;
			drop_completion(T, M, false);
			refresh(T, M);
		}
		else if (M->opts.allow_exit){
			arcan_tui_readline_reset(T);
			M->finished = -1;
		}
	}
	else if (keysym == TUIK_BACKSPACE)
		erase_at_cursor(T, M);
	else if (keysym == TUIK_DELETE)
		delete_at_cursor(T, M);
	else if (keysym == TUIK_TAB && M->opts.tab_completion){
		synch_completion(T, M);
	}
/* finish or if multi-line and meta-held, add '\n' */
	else if (keysym == TUIK_RETURN){
		add_linefeed(T, M);
	}
	else if (M->old_handlers.input_key){
		M->old_handlers.input_key(T,
			keysym, scancode, mods, subid, M->old_handlers.tag);
	}
}

static bool ensure_size(
	struct tui_context* T, struct readline_meta* M, size_t sz)
{
	if (sz <= M->work_sz)
		return true;

/* pick a larger step size just to cut down on the number of allocations in
 * the common "type/paste" scenario */
	sz += 1024;
	size_t cols;
	arcan_tui_dimensions(T, NULL, &cols);
	char* new_buf = malloc(sz);
	if (!new_buf)
		return false;

	memset(new_buf, '\0', sz);
	memcpy(new_buf, M->work, M->work_ofs);
	free(M->work);
	M->work = new_buf;
	M->work_sz = sz;

	return true;
}

static void replace_str(
	struct tui_context* T, struct readline_meta* M, const char* str, size_t len)
{
	if (!ensure_size(T, M, len+1))
		return;

	memcpy(M->work, str, len);
	M->work[len] = '\0';
	M->work_ofs = len;
	M->cursor = len;
	M->work_len = utf8len(len, str);

	refresh(T, M);
}

static void add_input(struct tui_context* T,
	struct readline_meta* M, const char* u8, size_t len, bool noverify)
{
	if (!ensure_size(T, M, M->work_ofs + len + 1))
		return;

/* add the input, move the cursor if we are at the end */
	if (M->cursor == M->work_ofs){
		M->cursor += len;
		memcpy(&M->work[M->work_ofs], u8, len);
		M->work[M->cursor] = '\0';
	}

/* slide buffer to the right if inserting in the middle */
	else {
		memmove(
			&M->work[M->cursor + len],
			&M->work[M->cursor],
			M->work_ofs - M->cursor
		);

		memcpy(&M->work[M->cursor], u8, len);
		M->cursor += len;
	}

	if (!noverify)
		verify(T, M);

/* number of code points have changed, now we need to convert to logical pos */
	size_t pos = 0;
	size_t count = 0;
	while (pos < len){
		if ((u8[pos++] & 0xc0) != 0x80)
			count++;
	}

	M->work_ofs += len;
	M->work_len += count;
}

static void on_visibility(struct tui_context* T, bool visible, bool focus, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->old_handlers.visibility)
		return;

	M->old_handlers.visibility(T, visible, focus, M->old_handlers.tag);
}

static void on_exec_state(struct tui_context* T, int state, void* tag)
{

	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->old_handlers.exec_state)
		return;

	M->old_handlers.exec_state(T, state, M->old_handlers.tag);
}

static void on_tick(
	struct tui_context* T, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->old_handlers.tick)
		return;

	M->old_handlers.tick(T, M->old_handlers.tag);
}

static void on_bchunk(struct tui_context* T,
	bool input, uint64_t size, int fd, const char* type, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->old_handlers.bchunk)
		return;

	M->old_handlers.bchunk(T, input, size, fd, type, M->old_handlers.tag);
}

static void on_mouse_motion(struct tui_context* T,
	bool relative, int x, int y, int modifiers, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (M->opts.mouse_forward && M->old_handlers.input_mouse_button){
		M->old_handlers.input_mouse_motion(T,
			relative, x, y, modifiers, M->old_handlers.tag);
	}
}

static void on_mouse_button_input(struct tui_context* T,
	int x, int y, int button, bool active, int modifiers, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (!(
		x >= M->start_col && x <= M->stop_col &&
		y >= M->start_row && y <= M->stop_row)){
		if (M->opts.mouse_forward && M->old_handlers.input_mouse_button){
			M->old_handlers.input_mouse_button(T,
				x, y, button, active, modifiers, M->old_handlers.tag);
		}
		else
			if (M->opts.allow_exit)
				M->finished = -1;
		return;
	}

	if (!active)
		return;

	size_t cx, cy;
	arcan_tui_cursorpos(T, &cx, &cy);

	size_t w = M->stop_col - M->start_col;
	size_t c_ofs = (cx - M->start_col) + (cy - M->start_row) * w;
	size_t m_ofs = (x - M->start_col) + (y - M->start_row) * w;

	if (m_ofs == c_ofs){
		return;
	}

	else if (m_ofs > c_ofs){
		for (size_t i = 0; i < m_ofs - c_ofs; i++)
			step_cursor_right(T, M);
	}
	else {
		for (size_t i = 0; i < c_ofs - m_ofs; i++)
			step_cursor_left(T, M);
	}
	refresh(T, M);
}

/*
 * accessor if we are running in manual mode
 */
void arcan_tui_readline_region(
	struct tui_context* T, size_t x1, size_t y1, size_t x2, size_t y2)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	M->start_col = x1;
	M->stop_col = x2;
	M->start_row = y1;
	M->stop_row = y2;
}

static void on_recolor(struct tui_context* T, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (M->old_handlers.recolor)
		M->old_handlers.recolor(T, M->old_handlers.tag);

	refresh(T, M);
}

void arcan_tui_readline_autocomplete(struct tui_context* T, const char* suffix)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->work)
		return;

	M->current_suggestion = suffix;
}

void arcan_tui_readline_suggest(
	struct tui_context* T, int mode, const char** set, size_t sz)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->work)
		return;

	int mask = READLINE_SUGGEST_HINT;

	M->completion = set;
	M->completion_sz = sz;
	M->completion_mode = mode & ~(mask);
	M->completion_hint = mode & mask;
	M->completion_pos = 0;

/* pre-calculate the completion set width so refresh can reposition as needed */
	M->completion_width = 0;
	for (size_t i = 0; i < M->completion_sz; i++){
		size_t len = strlen(M->completion[i]);
		if (len > M->completion_width)
			M->completion_width = len;
	}

	if (M->show_completion){
		refresh(T, M);
	}
}

void arcan_tui_readline_reset(struct tui_context* T)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->work)
		return;

	reset(M);
	verify(T, M);
	refresh(T, M);
}

void arcan_tui_readline_set(struct tui_context* T, const char* msg)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->work)
		return;

	reset(M);

	while(msg && *msg){
		uint32_t ch;
		ssize_t step = arcan_tui_utf8ucs4(msg, &ch);
		if (step > 0){
			add_input(T, M, msg, step, true);
			msg += step;
		}
		else
			break;
	}

	refresh(T, M);
}

/*
 * set prefix/prompt that will be drawn (assuming there is enough
 * space for it to fit, or it will be truncated) - only cause a refresh
 * if the contents have changed from the last drawn prompt.
 */
void arcan_tui_readline_prompt(struct tui_context* T, const struct tui_cell* prompt)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

/* early out, setting to an empty prompt */
	if (!prompt && M->prompt){
		M->prompt = NULL;
		M->prompt_len = 0;
		refresh(T, M);
		return;
	}

/* both len and cmp */
	size_t len = 0;
	for (; prompt[len].ch; len++){}

	M->prompt = prompt;
	M->prompt_len = len;

	refresh(T, M);
}

static void reset_boundaries(
	struct tui_context* T, struct readline_meta* M, size_t cols, size_t rows)
{
/* align from bottom and clamp */
	if (M->opts.anchor_row < 0 && M->opts.n_rows < rows){
		M->start_row = M->stop_row = 0;

		size_t pad = -(M->opts.anchor_row) + M->opts.n_rows;

		if (rows > pad){
			M->start_row = rows - pad;
			M->stop_row = M->start_row + M->opts.n_rows - 1;
		}
	}
/* align from top */
	else if (M->opts.anchor_row > 0){
		M->start_row = M->opts.anchor_row - 1;
		M->stop_row = M->start_row + M->opts.n_rows - 1;
	}
/* manual mode, ignore */
	else {
		M->start_row = 0;
		M->stop_row = rows - 1;
	}

	if (M->opts.margin_left)
		M->start_col = M->opts.margin_left - 1;
	else
		M->start_col = 0;

	if (M->opts.margin_right && cols > M->opts.margin_right)
		M->stop_col = cols - M->opts.margin_right - 1;
	else
		M->stop_col = cols - 1;

/* safety clamp upper bound,
 * sanity check and early out also happens in the refresh */
	if (M->stop_row >= rows)
		M->stop_row = rows - 1;

	if (M->stop_col >= cols)
		M->stop_col = cols - 1;
}

static void on_state(struct tui_context* T, bool input, int fd, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (M->old_handlers.state)
		M->old_handlers.state(T, input, fd, M->old_handlers.tag);
}

static void on_geohint(
	struct tui_context* T,
	float lat, float lng, float elev,
	const char* a3_c, const char* a3_lang, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (M->old_handlers.geohint)
		M->old_handlers.geohint(
			T, lat, lng, elev, a3_c, a3_lang, M->old_handlers.tag);
}

static void on_resized(struct tui_context* T,
	size_t neww, size_t newh, size_t cols, size_t rows, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (M->old_handlers.resized)
		M->old_handlers.resized(T, neww, newh, cols, rows, M->old_handlers.tag);

	reset_boundaries(T, M, cols, rows);
	refresh(T, M);
}

static bool on_label_input(
	struct tui_context* T, const char* label, bool active, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return false;

	if (M->old_handlers.input_label)
		return M->old_handlers.input_label(T, label, active, M->old_handlers.tag);

	return false;
}

static bool on_subwindow(struct tui_context* T,
	arcan_tui_conn* connection, uint32_t id, uint8_t type, void* tag)
{
/* if it is a popup, that would be ours for hints - otherwise
 * send it onwards to the outer scope */
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return false;

	if (M->old_handlers.subwindow)
		return M->old_handlers.subwindow(T, connection, id, type, M->old_handlers.tag);

	return false;
}

static bool on_label_query(struct tui_context* T,
	size_t index, const char* country, const char* lang,
	struct tui_labelent* dstlbl, void* t)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return false;

/* let the old context also get a chance */
	if (M->old_handlers.query_label)
		return M->old_handlers.query_label(T,
			index - 1, country, lang, dstlbl, M->old_handlers.tag);

/* space to add our own labels, for switching input modes, triggering
 * completion and so on. */
	return false;
}

static void on_reset(struct tui_context* T, int level, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	arcan_tui_readline_reset(T);

	if (M->old_handlers.reset)
		M->old_handlers.reset(T, level, M->old_handlers.tag);
}

void arcan_tui_readline_autosuggest(struct tui_context* T, bool vl)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	M->show_completion = vl;
	refresh(T, M);
}

void arcan_tui_readline_set_cursor(
	struct tui_context* T, ssize_t pos, bool relative)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (!relative)
		M->cursor = 0;

	for (ssize_t i = 0; i < abs((int)pos); i++){
		if (pos < 0){
			M->cursor = utf8back(M->cursor, M->work);
			if (!M->cursor)
				break;
		}
		else{
			if (M->cursor >= M->work_ofs)
				break;
			M->cursor = utf8fwd(M->cursor, M->work, M->work_ofs);
		}
	}
}

void arcan_tui_readline_format(
	struct tui_context* T, size_t* ofs, struct tui_screen_attr* attr, size_t n)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	release_line_format(M);
	M->line_format = attr;
	M->line_format_ofs = ofs;
	M->line_format_sz = 0;
	refresh(T, M);
}

void arcan_tui_readline_setup(
	struct tui_context* T, struct tui_readline_opts* opts, size_t opt_sz)
{
	if (!T || !opts)
		return;

	struct readline_meta* meta = malloc(sizeof(struct readline_meta));
	if (!meta)
		return;

	*meta = (struct readline_meta){
		.magic = READLINE_MAGIC,
		.broken_offset = -1,
	};

	if (opt_sz > sizeof(struct readline_meta))
		return;
	memcpy(&meta->opts, opts, opt_sz);

	size_t sz = sizeof(struct tui_readline_opts);
	memcpy(&meta->opts, opts, opt_sz > sz ? sz : opt_sz);
	if (!meta->opts.n_rows)
		meta->opts.n_rows = 1;

	struct tui_cbcfg cbcfg = {
		.input_key = on_key_input,
		.input_mouse_button = on_mouse_button_input,
		.recolor = on_recolor,
		.input_utf8 = on_utf8_input,
		.utf8 = on_utf8_paste,
		.resized = on_resized,
		.input_label = on_label_input,
		.subwindow = on_subwindow,
		.query_label = on_label_query,
		.reset = on_reset,
		.input_mouse_motion = on_mouse_motion,
		.bchunk = on_bchunk,
		.tick = on_tick,
		.visibility = on_visibility,
		.exec_state = on_exec_state,
		.state = on_state,
		.geohint = on_geohint,
/* input_alabel - block */
/* input_misc - block */
/* vpaste - block / forward */
/* apaste - block / forward */
/* substitute - block */
		.tag = meta
	};

/* two possible approach to this, one is fully self contains and works like all the
 * other widgets, the other is a _setup and then continously call readline_at */
	arcan_tui_update_handlers(T, &cbcfg, &meta->old_handlers, sizeof(struct tui_cbcfg));

	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);
	reset_boundaries(T, meta, cols, rows);
	ensure_size(T, meta, 32);
	refresh(T, meta);
}

void arcan_tui_readline_release(struct tui_context* T)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	if (M->suggest_prefix){
		free(M->suggest_prefix);
		M->suggest_prefix = NULL;
		M->suggest_prefix_sz = 0;
	}

	if (M->suggest_suffix){
		free(M->suggest_suffix);
		M->suggest_suffix = NULL;
		M->suggest_suffix_sz = 0;
	}

	release_line_format(M);

	M->magic = 0xdeadbeef;
	free(M->work);

/* completion buffers etc. are retained by the user so ignore */
	arcan_tui_update_handlers(T, &M->old_handlers, NULL, sizeof(struct tui_cbcfg));
	free(M);
}

int arcan_tui_readline_finished(struct tui_context* T, char** buffer)
{
	struct readline_meta* M;
	if (buffer)
		*buffer = NULL;

	if (!validate_context(T, &M))
		return false;

/* if we have a completion string, return that, otherwise return the work buffer */
	if (buffer)
		*buffer = M->work;

	return M->finished;
}

void arcan_tui_readline_history(struct tui_context* T, const char** buf, size_t count)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	M->history = buf;
	M->history_sz = count;
	M->history_pos = 0;
}

#ifdef EXAMPLE

#include <errno.h>
#include <ctype.h>

static void test_refresh(struct tui_context* T)
{
	arcan_tui_erase_screen(T, false);
/* clear to color,
 * fill with a..z */
}

static void test_resize(struct tui_context* T,
	size_t neww, size_t newh, size_t col, size_t row, void* M)
{
	test_refresh(T);
}

ssize_t test_validate(const char* message, void* T)
{
	for (size_t i = 0; message[i]; i++)
		if (message[i] == 'a')
			return i;

	return -1;
}

static bool no_num(uint32_t ch, size_t length, void* tag)
{
	if (ch >= '0' && ch <= '9')
		return false;

	return true;
}

int main(int argc, char** argv)
{
/* basic 'just fill with blue' and have the default-attribute for the text field */
	struct tui_cbcfg cbcfg = {
		.resized = test_resize
	};

	arcan_tui_conn* conn = arcan_tui_open_display("readline", "test");
	struct tui_context* tui = arcan_tui_setup(conn, NULL, &cbcfg, sizeof(cbcfg));

	struct tui_screen_attr attr = {0};
	arcan_tui_get_color(tui, TUI_COL_TEXT, attr.fc);
	attr.bc[2] = 0xaa;

	arcan_tui_defattr(tui, &attr);

/* show 'a' characters as invalid,
 * don't allow numbers,
 * shutdown on exit */
	arcan_tui_readline_setup(tui,
		&(struct tui_readline_opts){
		.anchor_row = -2,
		.n_rows = 1,
		.margin_left = 20,
		.margin_right = 20,
		.filter_character = no_num,
		.multiline = false,
		.allow_exit = true,
		.verify = test_validate,
		}, sizeof(struct tui_readline_opts)
	);

	struct tui_cell prompt[] = {
		{
			.attr = attr,
			.ch = 'h'
		},
		{
			.attr = attr,
			.ch = 'i',
		},
		{
			.attr = attr,
			.ch = 't',
		},
		{
			.attr = attr,
			.ch = 'h',
		},
		{
			.attr = attr,
			.ch = 'e',
		},
			{
			.attr = attr,
			.ch = 'r',
		},
			{
			.attr = attr,
			.ch = 'e',
		},
		{
			.attr = attr,
			.ch = '>'
		},
		{0}
	};

	arcan_tui_readline_prompt(tui, prompt);

	char* out;
	bool running = true;

	while(running){
		while (!arcan_tui_readline_finished(tui, &out) && running){
			struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
			if (res.errc == TUI_ERRC_OK){
				if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
					running = false;
			}
		}

		if (out && running){
			if (strcmp(out, "exit") == 0)
				break;
			else {
/* set last input as prompt */
				arcan_tui_readline_reset(tui);
			}
		}
	}

	arcan_tui_readline_release(tui);
	arcan_tui_destroy(tui, NULL);

	return EXIT_SUCCESS;
}

#endif
