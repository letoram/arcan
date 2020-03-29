/*
 * Arcan Text-Oriented User Interface Library, Extensions
 * Copyright: 2019-2020, Bjorn Stahl
 * License: 3-clause BSD
 * Description: Implementation of a readline/linenoise replacement.
 * Missing:
 *  Vim/Emacs toggle/ controls
 *  Search Through History
 *  Multiline support
 *  Completion popup
 *  Respect geohint
 *  Accessibility subwindow
 *  Config through readline commands (vim/emacs, ...)
 *  State/Preference persistance?
 */
#include <unistd.h>
#include <fcntl.h>

#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../../arcan_tui_readline.h"

#define READLINE_MAGIC 0xfefef00d

struct readline_meta {
	uint32_t magic;
	struct tui_readline_opts opts;

/* re-built on resize */
	size_t start_col, stop_col, start_row, stop_row;

/* current working / presentation step, internal representation
 * is UCS-4, and conversion to UTF-8 for external interfaces */
	uint32_t* work;

/* one level of undo should suffice for now */
	uint32_t* undo;

/*  provided by callback in opts or through setter functions */
	uint32_t* autocomplete;
	const struct tui_cell* prompt;

	bool finished;

/* restore on release */
	struct tui_cbcfg old_handlers;
	int old_flags;
};

static void refresh(struct tui_context* T, struct readline_meta* M)
{
/* x1,y1,x1,y2 are calculated using the margin_left, margin_right, anchor */

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


bool arcan_tui_readline_input_utf8(
	struct tui_context* T, const char* u8, size_t len, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return false;
/*
 * regular text input, just addch and possibly fill with suggested completion
 * especially for \t or \n depending if those are desired or note
 */

/* convert to UCS4, iterate and feed as normal UTF8 keys except for double-
 * linefeed in multiline mode (don't want the commit to apply from an accidental
 * paste) */

/* also set a copy of the working buffer as a possible undo */

/* update if we are in controlled mode */
	refresh(T, M);
	return true;
}

static void arcan_tui_readline_input_key(struct tui_context* T,
	uint32_t symest, uint8_t scancode, uint8_t mods, uint16_t subid, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

/* handle the other bits, i.e. show completion history / popup */

/* translate into the libreadline defaults */
}

static void arcan_tui_readline_mouse_button(struct tui_context* T,
	int x, int y, int button, bool active, int modifiers, void* tag)
{
	struct readline_meta* M;
	if (!validate_context(T, &M) || !active)
		return;

	if (!(
		x >= M->start_col && x <= M->stop_col &&
		y >= M->start_row && y <= M->stop_row)){
		return;
	}
/* warp cursor if within region */
}

static void arcan_tui_readline_region(
	struct tui_context* T, size_t x1, size_t y1, size_t x2, size_t y2)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	M->start_col = M->opts.margin_left + x1;
	M->stop_col = x2 - M->opts.margin_right;
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

/*
 * set prefix/prompt that will be drawn (assuming there is enough
 * space for it to fit, or it will be truncated).
 */
void arcan_tui_set_prompt(struct tui_context* T, const struct tui_cell* prompt)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	M->prompt = prompt;
	refresh(T, M);
}

void arcan_tui_readline_setup(
	struct tui_context* T, struct tui_readline_opts* opts, size_t opt_sz)
{
	struct readline_meta* meta = malloc(sizeof(struct readline_meta));
	if (!meta)
		return;

	*meta = (struct readline_meta){
		.magic = READLINE_MAGIC,
	};

	struct tui_cbcfg cbcfg = {
		.input_key = arcan_tui_readline_input_key,
		.input_mouse_button = arcan_tui_readline_mouse_button,
		.recolor = on_recolor,
/* query_label - absorb, expose input controls and defaults */
/* input_label - match to inputs */
/* input_alabel - block */
/* input_mouse_motion - block */
/* input_mouse_button - handle, use to indicate finished state */
/* input_utf8 - handle, add to buffer */
/* input_key - handle, use in place of input_label */
/* input_misc - block */
/* state - block */
/* bchunk - block */
/* vpaste - block */
/* apaste - block */
/* tick - block */
/* utf8 - treat as multiple input_text calls */
/* resized - forward */
/* reset - trigger recolor */
/* geohint - forward */
/* subwindow - check if it is our popup, otherwise forward */
/* substitute - block */
/* resize - forward */
/* visibility - forward */
/* exec_state - forward */
	};

/* two possible approach to this, one is fully self contains and works like all the
 * other widgets, the other is a _setup and then continously call readline_at */
	arcan_tui_update_handlers(T, &cbcfg, &meta->old_handlers, sizeof(struct tui_cbcfg));
}

void arcan_tui_readline_release(struct tui_context* T)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return;

	M->magic = 0xdeadbeef;
	free(M->work);
	arcan_tui_update_handlers(T, &M->old_handlers, NULL, sizeof(struct tui_cbcfg));
	free(M);
}

bool arcan_tui_readline_finished(struct tui_context* T, char** buffer)
{
	struct readline_meta* M;
	if (!validate_context(T, &M))
		return false;

	if(M->finished){
		if (buffer){
			*buffer = M->work;
		}
		return true;
	}

	return false;
}

#ifdef EXAMPLE

int main(int argc, char** argv)
{
	struct tui_cbcfg cbcfg = {
		resized = on_resize
	};
	arcan_tui_conn* conn = arcan_tui_open_display("test", "");
	struct tui_context* tui = arcan_tui_setup(conn, NULL, &cbcfg, sizeof(cbcfg));

/* basic 'just fill with blue' and have the default-attribute for the text field */

	return EXIT_SUCCESS;
}
#endif
