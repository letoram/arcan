/*
 * Arcan Text-Oriented User Interface Library, Extensions
 * Copyright: 2019, Bjorn Stahl
 * License: 3-clause BSD
 */

#ifndef HAVE_TUI_READLINE
#define HAVE_TUI_READLINE

#ifndef ARCAN_TUI_DYNAMIC
/*
 * Description:
 * This function partially assumes control over a provided window in
 * order to provide libreadline/liblinenoise like input capabilities.
 *
 * Handlers/Allocations:
 * This function chains/forwards all event handlers.
 *
 * Example:
 * see the #ifdef EXAMPLE block at the bottom of tui_readline.c
 */
enum readline_anchor {
/* caller manually handles reanchoring with calls to readline_region */
	READLINE_AMCHOR_FIXED = 0,

/* anchor_row in _opts is used and relative to the upper left corner
 * of the window, and clipped against bottom */
	READLINE_ANCHOR_UL = 1,

/* anchor_row in _opts are used and clipped against top and bottom */
	READLINE_ANCHOR_LL = 2,
};

struct tui_readline_opts {
/* input region anchor constraints, behavior depends on which anchoring
 * mode presented in readline_anchor */
	int anchor;
	ssize_t anchor_row;

/* visible region for drawing text */
	size_t n_rows;

/* mouse clicks outside the input region or escape will have the
 * _finished status marked as true and cursor moved to the click-
 * point (mouse) or region start (escape) */
	bool cancellable;

/*
 * missing:
 * multiline (_finished always true)
 * masked (substitution character, i.e. password prompt)
 * completion hint (callback yields)
 * input_method hook (callback handles string and cursor modification)
 * history buffer
 */
};

void arcan_tui_readline_setup(
	struct tui_context*, struct tui_readline_opts*, size_t opt_sz);

void arcan_tui_readline_release(struct tui_context*);

/*
 * Call as part of normal processing look to retrieve a reference
 * to the current input buffer. This buffer reference stored in
 * [buffer(!=NULL] is valid until the next process/refresh call
 * or until readline_release.
 */
bool arcan_tui_readline_finished(struct tui_context*, char** buffer);

/*
 * Call to update the readline input region
 */
void arcan_tui_readline_region(
	struct tui_context*, size_t x1, size_t y1, size_t x2, size_t y2);

#else

#endif

#endif
