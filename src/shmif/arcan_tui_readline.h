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
 *     The result MUST be provided as a suffix to be appended to message,
 *     not as the full final string.
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

/* Tab is a bit special as some sources do provide this as a keyboard symbols
 * while others might treat it as a '\t' - in that case it would be subject to
 * filter_character callback. */
	bool tab_completion;

/* Check the contents (utf-8, NUL terminated) of [message].
 * [prefix] contains the subset of message up to the current cursor position.
 *
 * return -1 on success or the buffer offset where the content stops being
 * valid.
 *
 * If [suggest] is set, the user has requested that a set of possible
 * options based on the current prefix is added.
 */
	ssize_t (*verify)(
		const char* message, size_t prefix, bool suggest, void* T);

/*
 * Forward mouse events that occur outside of the current readline bounding box
 */
	bool mouse_forward;

/*
 * Chain to default handler on text paste rather than inserting
 */
	bool paste_forward;

/*
 * Disable all default keybindings, any regular readline options have to be
 * implemented by the caller.
 */
	bool block_builtin_bindings;

/*
 * Provide to use a popup window for presenting the completion.
 * This window will be resized/repositioned/anchored during refresh.
 *
 * The popup is expected to be kept alive / allocated during the lifetime of
 * the readline state but the caller retains ownership.
 */
	struct tui_context* popup;

/*
 * (no-op with popup)
 * When completion is drawn the default is to pad to the widest element and
 * annotate with a border. Using this toggle will only draw the actual items.
 */
	bool completion_compact;
};

void arcan_tui_readline_setup(
	struct tui_context*, struct tui_readline_opts*, size_t opt_sz);

/* set the active history buffer that the user can navigate, the caller retains
 * ownership and the contents are assumed to be valid until _readline_release
 * has been called or replaced with another buffer */
void arcan_tui_readline_history(struct tui_context*, const char**, size_t count);

/* explicitly enable / disable the automatic suggestion (tab completion) */
void arcan_tui_readline_autosuggest(struct tui_context*, bool);

/*
 * Set prefix/prompt that will be drawn
 * (assuming there is enough space for it to fit, or it will be drawn truncated).
 *
 * Ownership:
 * Caller retains ownership of prompt, callee retains a reference that may be used
 * until next call to set_prompt or release on the tui context.
 *
 * Note:
 * If the prompt uses custom coloring, set_prompt should be called again on recolor.
 *
 * Note:
 * The length of prompt is NUL terminated based on the .ch field.
 */
void arcan_tui_readline_prompt(struct tui_context* T, const struct tui_cell* prompt);

/*
 * Restore event handler table and cancel any input operation
 */
void arcan_tui_readline_release(struct tui_context*);

/*
 * Set a possible non-authoritative completion suffix that the user can use to
 * automatically fill in the rest of the string.
 */
void arcan_tui_readline_autocomplete(struct tui_context* t, const char* suffix);

/*
 * Update a set of possible strings that can be inserted at the current
 * position. This is most useful through the verify callback when the user
 * has explicitly requested a set of suggestions.
 *
 * The caller retains ownership of [set] and it is expected to be valid until
 * the next call to _suggestion or until readline_release.
 *
 * The mode specifies how activation of a suggestion will be applied and
 * presented.
 *
 * For 'insert' the text will be added at the current cursor position.
 * For 'word' the last word will be removed and swapped for the suggested entry.
 * For 'substitute' the entire input set will be replaced.
 *
 * If the 'hint' bit is set, each string in the set is interpreted as being
 * double (msg \0 hint \0) in order to provide / display an extended hint that
 * will not be part of the final inserted string.
 *
 */
enum tui_readline_suggestion_mode {
	READLINE_SUGGEST_INSERT = 0,
	READLINE_SUGGEST_WORD = 1,
	READLINE_SUGGEST_SUBSTITUTE = 2,
	READLINE_SUGGEST_HINT = 64
/* READLINE_SUGGEST_HINT_PROMPT = 128 */
};
void arcan_tui_readline_suggest(
	struct tui_context* t, int mode, const char** set, size_t set_sz);

/*
 * Set an insertion prefix and/or suffix used with any of the suggestion
 * modes above.
 *
 * [prefix,suffix] will be copied and used internally and freed on the
 * next call to suggest_fix or releasing the context.
 */
void arcan_tui_readline_suggest_fix(
	struct tui_context* t, const char* prefix, const char* suffix);

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

/*
 * If things were setup without an anchor row, reanchoring is a manual process
 * by setting the bounding box for the readline widget using this function.
 */
void arcan_tui_readline_region(
	struct tui_context*, size_t x1, size_t y1, size_t x2, size_t y2);

/*
 * Clear current input buffer and replace with [msg].
 *
 * This will not trigger any of the assigned callbacks to avoid misuse from
 * being called from within another callback.
 */
void arcan_tui_readline_set(struct tui_context*, const char* msg);

/*
 * Move the cursor to the logical character position [pos] or at the
 * end of string if pos would cause it to overflow. If relative is set
 * to true, pos will nudge the cursor n steps left (< 0) or right ( > 0)
 */
void arcan_tui_readline_set_cursor(
	struct tui_context*, ssize_t pos, bool relative);

/*
 * Assign a set of formatting attributes along with the character offsets from
 * where they should apply. [ofs] and [attr] are assumed to be dynamically
 * allocated and the implementation assumes ownership and will free on the
 * next call to format or when the widget is released.
 */
void arcan_tui_readline_format(struct tui_context*,
	size_t* ofs, struct tui_screen_attr* attr, size_t n);

#else
typedef bool(* PTUIRL_SETUP)(
	struct tui_context*, struct tui_readline_opts*, size_t opt_sz);
typedef bool(* PTUIRL_FINISHED)(struct tui_context*, char** buffer);
typedef void(* PTUIRL_RESET)(struct tui_context*, const char*);
typedef void(* PTUIRL_HISTORY)(struct tui_context*, const char**, size_t);
typedef void(* PTUIRL_PROMPT)(struct tui_context*, const struct tui_cell*);
typedef void(* PTUIRL_SET)(struct tui_context*, const char* msg);
typedef void(* PTUIRL_COMPLETE)(struct tui_context*, const char*);
typedef void(* PTUIRL_SUGGEST)(struct tui_context*, int, const char**, size_t);
typedef void(* PTUIRL_SUGGEST_FIX)(struct tui_context*, const char*, const char*);
typedef void(* PTUIRL_REGION)(struct tui_context*, size_t, size_t, size_t, size_t);
typedef void(* PTUIRL_AUTOSUGGEST)(struct tui_context*, bool);
typedef void(* PTUIRL_SETCURSOR)(struct tui_context*, size_t pos);
typedef void(* PTUIRL_FORMAT)(struct tui_context*, size_t*, struct tui_screen_attr*attr, size_t);

static PTUIRL_SETUP arcan_tui_readline_setup;
static PTUIRL_FINISHED arcan_tui_readline_finished;
static PTUIRL_RESET arcan_tui_readline_reset;
static PTUIRL_HISTORY arcan_tui_readline_history;
static PTUIRL_PROMPT arcan_tui_readline_prompt;
static PTUIRL_SET arcan_tui_readline_set;
static PTUIRL_COMPLETE arcan_tui_readline_complete;
static PTUIRL_SUGGEST arcan_tui_readline_suggest;
static PTUIRL_SUGGEST_FIX arcan_tui_readline_suggest_prefix;
static PTUIRL_REGION arcan_tui_readline_region;
static PTUIRL_AUTOSUGGEST arcan_tui_readline_autosuggest;
static PTUIRL_SETCURSOR arcan_tui_readline_set_cursor;
static PTUIRL_FORMAT arcan_tui_readline_format;

static bool arcan_tui_readline_dynload(
	void*(*lookup)(void*, const char*), void* tag)
{
#define M(TYPE, SYM) if (! (SYM = (TYPE) lookup(tag, #SYM)) ) return false
M(PTUIRL_SETUP, arcan_tui_readline_setup);
M(PTUIRL_FINISHED, arcan_tui_readline_finished);
M(PTUIRL_RESET, arcan_tui_readline_reset);
M(PTUIRL_HISTORY, arcan_tui_readline_history);
M(PTUIRL_PROMPT, arcan_tui_readline_prompt);
M(PTUIRL_SET, arcan_tui_readline_set);
M(PTUIRL_COMPLETE, arcan_tui_readline_complete);
M(PTUIRL_SUGGEST, arcan_tui_readline_suggest);
M(PTUIRL_SUGGEST_FIX, arcan_tui_readline_suggest_fix);
M(PTUIRL_REGION, arcan_tui_readline_region);
M(PTUIRL_AUTOSUGGEST, arcan_tui_readline_autosuggest);
M(PTUIRL_SETCURSOR, arcan_tui_readline_set_cursor);
M(PTUIRL_FORMAT, arcan_tui_readline_format);

#undef M
}

#endif
#endif
