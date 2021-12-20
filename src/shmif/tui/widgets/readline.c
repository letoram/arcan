/*
 * Arcan Text-Oriented User Interface Library, Extensions
 * Copyright: 2019-2021, Bjorn Stahl
 * License: 3-clause BSD
 * Description: Implementation of a readline/linenoise replacement.
 * Missing:
 *  Vim mode
 *
 *  Search Through History (if caller sets history buffer)
 *   - temporary override prompt with state, hide cursor, ...
 *
 *  Multiline support
 *  Completion popup
 *   -
 *
 *  Respect geohint (LTR, RTL, double-width)
 *
 *  Undo- buffer
 *   - (just copy on modification into a window of n buffers, undo/redo pick)
 *
 *  Accessibility subwindow
 *
 *  .readline rc file
 *
 *  State/Preference persistance?
 */
#include <unistd.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>

#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../../arcan_tui_readline.h"

#define READLINE_MAGIC 0xfefef00d

struct readline_meta {
	uint32_t magic;
	struct tui_readline_opts opts;

/* re-built on resize */
	size_t start_col, stop_col, start_row, stop_row;

	char* work;        /* UTF-8 */
	size_t work_ofs;   /* in bytes, code-point boundary aligned */
	size_t work_len;   /* in code-points */
	size_t work_sz;    /* in bytes */
	size_t cursor;     /* offset in bytes from start to cursor */

/* -1 as ok, modified by verify callback */
	ssize_t broken_offset;

/* provided by callback in opts or through setter functions */
	uint8_t* autocomplete;

/* if we overfit-, this might be drawn with middle truncated to 2/3 of capacity */
	const struct tui_cell* prompt;
	size_t prompt_len;

	int finished;

	const char** history;
	char* in_history;
	size_t history_sz;
	size_t history_pos;

/* restore on release */
	struct tui_cbcfg old_handlers;
	int old_flags;
};

/* generic 'insert at cursor' */
static void add_input(
	struct tui_context* T, struct readline_meta* M, const char* u8, size_t len);

static void replace_str(
	struct tui_context* T, struct readline_meta* M, const char* str, size_t len);

static void refresh(struct tui_context* T, struct readline_meta* M)
{
	size_t rows, cols;
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
		return;

	size_t cx = 0, cy = 0;
	size_t limit = (x2 - x1) + 1;
	if (limit < 3)
		return;

	arcan_tui_move_to(T, x1, y1);

/* standard prompt attribute */
/* then error alert if we have a bad offset */
	struct tui_screen_attr alert = {
		.aflags = TUI_ATTR_COLOR_INDEXED,
		.fc[0] = TUI_COL_WARNING,
		.bc[0] = TUI_COL_WARNING
	};

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
 * and backwards until filled - this is preped to be content dependent for
 * double-width etc. later */
	size_t pos = 0;
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

		pos += step;
		arcan_tui_write(T, ch,
			M->broken_offset != -1 && pos >= M->broken_offset ? &alert : NULL);
	}

	if (cx)
		arcan_tui_move_to(T, cx, cy);
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

static void step_cursor_left(struct tui_context* T, struct readline_meta* M)
{
	while(M->cursor && M->work && (M->work[--M->cursor] & 0xc0) == 0x80){}
}

static void step_cursor_right(struct tui_context* T, struct readline_meta* M)
{
	while(M->cursor < M->work_ofs && (M->work[++M->cursor] & 0xc0) == 0x80){}
}

static bool delete_at_cursor(struct tui_context* T, struct readline_meta* M)
{
	return true;
}

static bool erase_at_cursor(struct tui_context* T, struct readline_meta* M)
{
	if (!M->cursor || !M->work_len)
		return true;

/* sweep to previous utf8 start */
	size_t c_cursor = M->cursor - 1;
	while (c_cursor && (M->work[c_cursor] & 0xc0) == 0x80)
		c_cursor--;

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
	if (M->opts.verify){
		M->broken_offset = M->opts.verify((const char*)M->work, M->old_handlers.tag);
	}

	refresh(T, M);

	return true;
}

static bool add_linefeed(struct tui_context* T, struct readline_meta* M)
{
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
/* start from current cursor position, find the first non-space, then find the
 * beginning or the next space and memset + memmove from there */
}

static void cut_to_eol(struct tui_context* T, struct readline_meta* M)
{
	if (!M->work)
		return;

	arcan_tui_copy(T, &M->work[M->cursor]);

	M->work[M->cursor] = '\0';
	M->work_ofs = M->cursor;

	M->work_len = 0;
	size_t pos = 0;
	while (pos < M->cursor){
		if ((M->work[pos++] & 0xc0) != 0x80)
			M->work_len++;
	}

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

	M->work_len = 0;
	size_t pos = 0;
	while (pos < M->cursor){
		if ((M->work[pos++] & 0xc0) != 0x80)
			M->work_len++;
	}

	refresh(T, M);
}

static void on_utf8_paste(
	struct tui_context* T, const uint8_t* u8, size_t len, bool cont, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

/* split up into multiple calls based on filter character if needed */
	if (M->opts.filter_character){
		for (size_t i = 0; i < len;){
			uint32_t ch;
			size_t step = arcan_tui_utf8ucs4((char*)&u8[i], &ch);
			if (M->opts.filter_character(ch, M->work_len + 1, M->old_handlers.tag))
				add_input(T, M, (char*)&u8[i], step);
			i += step;
		}
	}
	else {
		add_input(T, M, (char*)u8, len);
	}

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
		replace_str(T, M, M->in_history, strlen(M->in_history));
		free(M->in_history);
		M->in_history = NULL;
	}

/* if it is a commit, refuse on validation failure - 0-length should
 * be filtered through filter_character so no reason to forward it here */
	if (*u8 == '\n' || *u8 == '\r')
		return add_linefeed(T, M);

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

	add_input(T, M, u8, len);

/* missing - if we have a valid suggestion popup, rebuild it with
 * the new filter-set and reset the cursor in the popup to the current position */

	refresh(T, M);
	return true;
}

static void step_history(
	struct tui_context* T, struct readline_meta* M, ssize_t step)
{
	if (!M->history_sz)
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
		M->history_pos++;
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

void on_key_input(struct tui_context* T,
	uint32_t keysym, uint8_t scancode, uint8_t mods, uint16_t subid, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	bool meta = mods & (TUIM_LCTRL | TUIM_RCTRL);
	if (meta){
		if (keysym == TUIK_RETURN){
			M->finished = 1;
		}
		else if (keysym == TUIK_L){
			arcan_tui_readline_reset(T);
		}
/* delete at/right of cursor, same as DELETE, if line is empty,
 * as escape with hint to exit */
		else if (keysym == TUIK_D){
		}
/* swap with previous */
		else if (keysym == TUIK_T){
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
/* step previous in history */
		else if (keysym == TUIK_P){
			step_history(T, M, 1);
		}
/* step next in history */
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
		return;
	}

	if (keysym == TUIK_LEFT){
		step_cursor_left(T, M);
		refresh(T, M);
	}

	else if (keysym == TUIK_RIGHT){
		refresh(T, M);
		step_cursor_right(T, M);
	}
	else if (keysym == TUIK_UP){
		step_history(T, M, 1);
	}
	else if (keysym == TUIK_DOWN){
		step_history(T, M, -1);
	}
	else if (keysym == TUIK_ESCAPE && M->opts.allow_exit){
		arcan_tui_readline_reset(T);
		M->finished = -1;
	}

	else if (keysym == TUIK_BACKSPACE)
		erase_at_cursor(T, M);

	else if (keysym == TUIK_DELETE)
		delete_at_cursor(T, M);

/* finish or if multi-line and meta-held, add '\n' */
	else if (keysym == TUIK_RETURN){
		add_linefeed(T, M);
	}
}

static bool ensure_size(
	struct tui_context* T, struct readline_meta* M, size_t sz)
{
	if (sz < M->work_sz)
		return true;

	size_t cols;
	arcan_tui_dimensions(T, NULL, &cols);
	char* new_buf = realloc(M->work, sz);
	if (NULL == new_buf){
		return false;
	}

	M->work = new_buf;
	memset(&M->work[M->work_ofs], '\0', sz - M->work_ofs);
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

	size_t pos = 0;
	size_t count = 0;

	while (pos < len){
		if ((str[pos++] & 0xc0) != 0x80)
			count++;
	}
	M->work_len = count;

	refresh(T, M);
}

static void add_input(
	struct tui_context* T, struct readline_meta* M, const char* u8, size_t len)
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

/* check if we are broken at some offset */
	if (M->opts.verify){
		M->broken_offset = M->opts.verify((const char*)M->work, M->old_handlers.tag);
	}

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

static void on_mouse_button_input(struct tui_context* T,
	int x, int y, int button, bool active, int modifiers, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !active)
		return;

	if (!(
		x >= M->start_col && x <= M->stop_col &&
		y >= M->start_row && y <= M->stop_row)){
		if (M->opts.allow_exit)
			M->finished = -1;
		return;
	}

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

void arcan_tui_readline_reset(struct tui_context* T)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !M->work)
		return;

	M->finished = 0;
	M->work[0] = 0;
	M->work_ofs = 0;
	M->work_len = 0;
	M->cursor = 0;

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

	bool same = M->prompt != NULL;

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
		M->start_row = 0;
		M->stop_row = M->stop_row + M->opts.n_rows - 1;
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
		.opts = *opts,
		.broken_offset = -1
	};

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
/* input_alabel - block */
/* input_mouse_motion - block? or treat as selection for replace */
/* input_misc - block */
/* state - block */
/* bchunk - block / forward */
/* vpaste - block / forward */
/* apaste - block / forward */
/* tick - forward */
/* utf8 - treat as multiple input_text calls */
/* resized - forward */
/* reset - trigger recolor, forward */
/* geohint - forward */
/* substitute - block */
/* visibility - forward */
/* exec_state - forward */
		.tag = meta
	};

/* two possible approach to this, one is fully self contains and works like all the
 * other widgets, the other is a _setup and then continously call readline_at */
	arcan_tui_update_handlers(T, &cbcfg, &meta->old_handlers, sizeof(struct tui_cbcfg));

	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);
	reset_boundaries(T, meta, cols, rows);
	refresh(T, meta);
}

void arcan_tui_readline_release(struct tui_context* T)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

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
	printf("resize\n");
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
