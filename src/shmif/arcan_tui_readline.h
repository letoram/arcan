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
 /*-1 from bottom of context
 *  0 don't care
 *  1 from top of context */
	ssize_t anchor_row;
	size_t n_rows;
	size_t margin_left;
	size_t margin_right;

/* mouse clicks outside the input region or escape will have the _finished
 * status marked as true and cursor moved to the click- point (mouse) or region
 * start (escape) with no message result */
	bool cancellable;

/* provide to suggest an auto-completion string
 *
 * set [result] to point to the completion (if one exists)
 *     you retain overship of [result] and is expected to be alive until
 *     the context is released or the next call to autocomplete, the last
 *     pointer will be provided in return.
 *
 * return true if [result] was set.
 */
	bool (*autocomplete)(const char* message,
	                     const char** result, const char* last);

/* Provide a way to mask out certain inputs, when context does not need
 * to be considered (e.g. input that only accepts visible 7-bit set).
 *
 * Return true of the character is allowed to be added to the input buffer.
 * Note that the codepoint is expressed in UCS-4 rather than UTF-8.
 */
	bool (*filter_character)(uint32_t);

/* set a character that will be drawn in place of the real buffer */
	uint32_t mask_character;

/* restrict the number of character that can be added */
	size_t limit;

/* modifier+line-feed is added as \n in the target buffer */
	bool multiline;

/* verify the current buffer and give feedback on where the buffer
 * fails to pass validation or at which offset the input fails */
	ssize_t (*validate)(const char* message);
};

void arcan_tui_readline_setup(
	struct tui_context*, struct tui_readline_opts*, size_t opt_sz);

/* set the active history buffer that the user can navigate, the caller retains
 * ownership and the contents are assumed to be valid until _readline_release
 * has been called. */
void arcan_tui_readline_history(struct tui_context*, const char**);

/*
 * set prefix/prompt that will be drawn (assuming there is enough space for it
 * to fit, or it will be truncated). Caller retains ownership of prompt. If the
 * prompt uses custom coloring, set_prompt should be called again on recolor.
 */
void arcan_tui_set_prompt(struct tui_context* T, const struct tui_cell* prompt);

/*
 * Restore event handler table and cancel any input operation
 */
void arcan_tui_readline_release(struct tui_context*);

/*
 * Call as part of normal processing look to retrieve a reference
 * to the current input buffer. This buffer reference stored in
 * [buffer(!=NULL] is valid until the next process/refresh call
 * or until readline_release.
 */
bool arcan_tui_readline_finished(struct tui_context*, char** buffer);

#else

#endif

#endif
