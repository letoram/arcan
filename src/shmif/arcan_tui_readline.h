/*
 * Arcan Text-Oriented User Interface Library, Extensions
 * Copyright: 2019-2020, Bjorn Stahl
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

struct tui_readline_opts {
 /*-n from bottom of context, clamps to window size
 *  0 don't care, manually position with arcan_tui_readline_region
 *  n from top of context, clamps to window size */
	ssize_t anchor_row;
	size_t n_rows;
	size_t margin_left;
	size_t margin_right;

/* mouse clicks outside the input region or escape will have the _finished
 * status marked as true and cursor moved to the click- point (mouse) or region
 * start (escape) with no message result */
	bool allow_exit;

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
	                     const char** result, const char* last, void* T);

/* Provide a way to mask out certain inputs or length (e.g. input that only
 * accepts visible 7-bit set) or only allowing n- characters.
 *
 * Return true of the character is allowed to be added to the input buffer.
 * Note that the codepoint is expressed in UCS-4 rather than UTF-8.
 */
	bool (*filter_character)(uint32_t, size_t length, void* T);

/* set a character that will be drawn in place of the real buffer, this
 * is useful for password prompt like inputs */
	uint32_t mask_character;

/* line-feeds are accepted into the buffer, and empty */
	bool multiline;

/* check the contents (utf-8, NUL terminated) of [message].
 * return -1 on success or the buffer offset where the content failed */
	ssize_t (*verify)(const char* message, void* T);

/* based on [message] return a sorted list of possible candidates in [set]
 * and the number of elements as function return value */
	size_t (*suggest)(const char* message, const char** set, void* T);
};

void arcan_tui_readline_setup(
	struct tui_context*, struct tui_readline_opts*, size_t opt_sz);

/* set the active history buffer that the user can navigate, the caller retains
 * ownership and the contents are assumed to be valid until _readline_release
 * has been called or replaced with another buffer */
void arcan_tui_readline_history(struct tui_context*, const char**, size_t count);

/*
 * Set prefix/prompt that will be drawn
 * (assuming there is enough space for it to fit, or it will be drawn truncated).
 *
 * Ownership:
 * Caller retains ownership of prompt, callee retains a refrence that may be used
 * until next call to set_prompt or release on the tui context.
 *
 * Note:
 * If the prompt uses custom coloring, set_prompt should be called again on recolor.
 *
 * Note:
 * The length of prompt is NUL terminated based on the .ch field.
 */
void arcan_tui_set_prompt(struct tui_context* T, const struct tui_cell* prompt);

/*
 * Restore event handler table and cancel any input operation
 */
void arcan_tui_readline_release(struct tui_context*);

/*
 * Call as part of normal processing loop to retrieve a reference to the
 * current input buffer.
 *
 * This buffer reference stored in [buffer(!=NULL)] is valid until the next
 * readline_release, _finished or tui_refresh on the context.
 *
 * Values returned are from the set shwon in enum tui_readline_status
 */
enum tui_readline_status {
	READLINE_STATUS_TERMINATE = -2,
	READLINE_STATUS_CANCELLED = -1,
	READLINE_STATUS_EDITED = 0,
	READLINE_STATUS_DONE = 1,
};
int arcan_tui_readline_finished(struct tui_context*, char** buffer);

/*
 * Clear input buffer state (similar to C-l)
 */
void arcan_tui_readline_reset(struct tui_context*);

#else
typedef bool(* PTUIRL_SETUP)(
	struct tui_context*, struct tui_readline_opts*, size_t opt_sz);
typedef bool(* PTUIRL_FINISHED)(struct tui_context*, char** buffer);
typedef void(* PTUIRL_RESET)(struct tui_context*);
typedef void(* PTUIRL_HISTORY)(struct tui_context*, const char**, size_t);
typedef void(* PTUIRL_PROMPT)(struct tui_context*, const struct tui_cell*);

static PTUIRL_SETUP arcan_tui_readline_setup;
static PTUIRL_FINISHED arcan_tui_readline_finished;
static PTUIRL_RESET arcan_tui_readline_reset;
static PTUIRL_HISTORY arcan_tui_readline_history;
static PTUIRL_PROMPT arcan_tui_readline_prompt;

static bool arcan_tui_readline_dynload(
	void*(*lookup)(void*, const char*), void* tag)
{
#define M(TYPE, SYM) if (! (SYM = (TYPE) lookup(tag, #SYM)) ) return false
M(PTUIRL_SETUP, arcan_tui_readline_setup);
M(PTUIRL_FINISHED, arcan_tui_readline_finished);
M(PTUIRL_RESET, arcan_tui_readline_reset);
M(PTUIRL_HISTORY, arcan_tui_readline_history);
M(PTUIRL_PROMPT, arcan_tui_readline_prompt);
#undef M
}

#endif
#endif
