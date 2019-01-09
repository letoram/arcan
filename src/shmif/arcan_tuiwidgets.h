/*
 Arcan Text-Oriented User Inteface Library, Extensions
 Copyright: 2018-2019, Bjorn Stahl
 License: 3-clause BSD
 Description: This header describes optional support components that
 extend TUI with some common helpers for input. They also server as
 simple examples for how to build similar ones, to lift, patch and
 include in custom projects.
*/

#ifndef HAVE_TUI_EXT
#define HAVE_TUI_EXT

/*
 * This function provides 'readline'- like input behavior for querying a
 * user-provided string. It does not provide rendering unless for an
 * optional popup context used for text completion suggestions. It is
 * up to the caller to render/crop/wrap the line in question and move
 * the cursor accordingly.
 *
 * The [parent] and [on_update] arguments are required, or the function
 * will return NULL. The rest of the arguments are optional.
 *
 * The provided 'on_update' callback will be provided with information on
 * the current context relative position, along with a msg and suggested
 * history-match if that feature is enabled.
 *
 * The provided 'on_completion' callback will be called repeatedly until
 * the callback returns false or the number of returned responses go out
 * of bounds with whatever internal restrictions exist.
 *
 * If popup is also provided, the popup context will be used to provide
 * the completion feedback in, using its input events to update the
 * parent readline 'target' area.
 *
 * and editing similar
 * completion and validation feedback
 */

struct readline_args {
	bool multiline;
};
struct tui_readline* arcan_tui_readline_setup(
	struct tui_context* parent,
	struct tui_context* popup,

/* obligatory status update argument:
 * the ofs_x and ofs_y determines the cursor offset (y is always 0 unless
 * the setup was in multiline mode) along with a reference to the current
 * (read-only) line message.
 *
 * if [msg] is NULL and [DONE] is set, it is indicated that the user
 * wish to cancel whatever input is being provided.
 *
 * [hint_msg] is set to refer to the current 'suggested' commit action,
 * this comes from the history buffer or from the completion buffer.
 * It is provided in order to let the renderer provide a 'dimmed down'
 * resolve result.
 *
 * If [done] is set the user has requested the line to be marked as
 * complete. To acknowledge this, you should explicitly call:
 * arcan_tui_readline_clear() in order to re-use the context for further
 * input.
 */
	void (*on_update)(struct tui_context*,
		size_t ofs_x, size_t ofs_y, const char* msg,
		const char* hint_msg, bool done, void*),

/*
 * the optional completion callback used to provide completion from other
 * sources than any loaded / existing history state.
 */
	bool (*on_completion)(struct tui_context*,
		const char* inmsg, int index,
		char** outmsg, uint8_t* outrgb[3],
		void* tag
	),

	struct readline_args opts,
	void* tag
);

/*
 * Reset the current input buffer, will immediately trigger an on_update
 * call at (0,0, "", (completion resolve), false, tag)
 */
void arcan_tui_readline_clear(struct tui_readline*);

void arcan_tui_readline_free(struct tui_readline*);

/*
 * Append a line to the history buffer that may be used for automated non-
 * callback driven 'history' comletion that is persisted in the state mgmt
 * functions below.
 */
void arcan_tui_readline_addhistory(struct tui_readline*, const char* in);

/*
 * Allocate a state buffer and return its state in the [out, buf_sz] args
 * returning true if the buffer could be allocated and populated.
 *
 * The buffer is in an 'opaque' state from where it can be restored later
 * via the _loadstate function. The primary use for this is to retain the
 * history across executions.
 */
bool arcan_tui_readline_savestate(
	struct tui_readline*, uint8_t** buf, size_t* buf_sz);

/*
 * Restore history from a state buffer provided in [buf, buf_sz] that has
 * previously been created from a call to arcan_tui_readline_savestate.
 */
bool arcan_tui_readline_loadstate(
	struct tui_readline*, uint8_t* buf, size_t buf_sz);

/*
 * Description:
 * This function partially assumes control over a provided window and uses
 * it to present a view into the contents of the provided buffer. It takes
 * care of rendering, layouting, cursor management and text/binary working
 * modes.
 *
 * The caller will still need to manage/poll/process the context, and also
 * to forward input via the related functions. This is done to allow other
 * features the be 'overlaid' on the buffer. Context controls is using the
 * same functions as for other tui context, while input uses the bufferwnd
 * prefix to the related handler callbacks.
 *
 * Arguments:
 * [buf] describes the buffer that will be exposed in the window.
 * [write_enable] Determines if the contents of the buffer are modifiable
 *                or not. Modifications on a write_enabled buffer will be
 *                made clocked event-driven using the _input handlers.
 *
 * Handlers will be overridden and masked, except for:
 * on_label (forward unless consumed internally)
 * on_destroy (chained and forwarded)
 *
 * Returns:
 * An opaque context struct that needs to be forwarded in place of the tag
 * in the normal handlers in order to not collide with pre-existing caller
 * set tags.
 *
 * This context is dynamically allocated, free using _bufferwnd_free.
 */
void arcan_tui_bufferwnd_setup(
	struct tui_context* ctx, uint8_t* buf, size_t buf_sz, bool write_enable);

/*
 * Take a context that has previously been setup via arcan_tui_bufferwnd_setup,
 * and restore its set of handlers/tag (not the contents itself) to the state
 * it was on the initial call. Normal deallocation might happen as part of the
 * on_destroy event handler on the other hand, and in such cases _free should
 * not be called.
 */
void arcan_tui_bufferwnd_free(struct tui_context*);

struct tui_list_entry {
	const char* label; /* user presentable UTF-8 string */
	char shortcut; /* ASCII visible set shortcut key */
	const char* menukey; /* alnum identifier for path references */

/* activated when menu- path is triggered, return a new menu if a submenu
 * is navigated to */
	struct tui_menu_entry**
		(*action)(struct tui_context*, struct tui_menu_entry*);

	uint64_t tag;
};

/*
 * Take control over the context in [src] and use it to present a list/menu.
 * The [list] arguments point to a NULL TERMINATED array of tui_list_entry
 * entries.
 *
 * Pass sizeof(struct tui_list_entry) in the [struct_listent_sz] field,
 * not the amount of elements.
 *
 * Handlers will be overridden and masked, except for:
 * on_destroy
 *
 * which will be chained and forwarded (i.e.:
 *  process -> event -> on_destroy(listwnd) -> on_destroy(owner)
 */
void arcan_tui_listwnd_setup(struct tui_context* src,
	struct tui_list_entry** list, size_t struct_listent_sz);

/*
 * Takes a context that has previously been setup via listwnd_setup and
 * restore its set of handlers/tag (not the contents itself) to the state
 * it was on the initial call.
 */
void arcan_tui_listwnd_restore(struct tui_context* src);

#endif
