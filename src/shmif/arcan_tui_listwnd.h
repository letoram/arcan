/*
 Arcan Text-Oriented User Interface Library, Extensions
 Copyright: 2018-2019, Bjorn Stahl
 License: 3-clause BSD
 Description: This header describes the 'list' tui widget. It takes a static
 list of selectable items and a tui context, takes temporary control over the
 context and presents a list of entries. The typical use for this is to
 implement a menu structure or a context- like input or non-input enabled
 helper for completion.
*/

#ifndef HAVE_TUI_LISTWND
#define HAVE_TUI_LISTWND

enum tui_list_entity_attributes {
	LIST_CHECKED   =  1, /* indicate in left column  v             */
	LIST_HAS_SUB   =  2, /* indicate in right column >             */
	LIST_SEPARATOR =  4, /* group separator, ---- label ignored    */
	LIST_PASSIVE   =  8, /* mark inactive, can't be set            */
	LIST_LABEL     = 16, /* mark inactive but with high-vis text   */
	LIST_HIDE      = 32  /* mark as invisible                      */
};

struct tui_list_entry {
	char* label;          /* user presentable UTF-8 string */
	char* shortcut;       /* single unicode codepoint (UTF-8) */
	uint8_t attributes;   /* bitmask from kind above */
	uint8_t indent;       /* indentation level */
	uintptr_t tag;        /* index or other reference to pair trigger */
};

/*
 * Description:
 * This function partially assumes control over a provided window and uses
 * it to present a traditional listview.
 *
 * Arguments:
 * [ctx] (!null) references the context to control
 * [entries] (!null) references the list of entries to present
 * [n_entries] (> 0) the number of presentable entries in the lst
 *
 * Returns:
 * true if context was allocated and setup, false on allocation failure or
 * argument errors.
 *
 * Handlers/Allocation:
 * This dynamically allocates internally, and replaces the normal set of
 * handlers. Use _listwnd_restore to return the context to the state it was
 * in before this function was called.
 *
 * Resize and Resized events are forwarded, input labels flushed.
 *
 * The list of entries that is provided will be aliased internally and treated
 * as of static/fixed size, though items can be masked on/off with the
 * list_hide attribute between listwnd_dirty calls as needed. The list will not
 * be freed upon listwnd_restore.
 *
 * Note:
 * 1. After each input pass, check arcan_tui_listwnd_status. If it returns
 * an entry, that entry has been activated. For multiple choice style use,
 * simply reflect this in the flags and call dirty, or restore the context
 * and resume normal use.
 *
 * 2. The context will use whatever size it was returned with, labels are
 * cropped accordingly, possibly scrolling the selected item. Sizing
 * operations and estimates should be done as part of context request /
 * allocation.
 *
 * Example:
 * See the #ifdef EXAMPLE block at the bottom of tui_listwnd.c
 */
#ifndef ARCAN_TUI_DYNAMIC
bool arcan_tui_listwnd_setup(
	struct tui_context*, struct tui_list_entry*, size_t n_entries);

/*
 * Query and flush the active window selection status, returns true if
 * somthing has been activated, and sets a pointer to the item [or NULL
 * on cancel request] into *out.
 */
bool arcan_tui_listwnd_status(
	struct tui_context*, struct tui_list_entry** out);

/*
 * Manually set the currently selected item to n where 0 <= n < n_entries
 */
void arcan_tui_listwnd_setpos(struct tui_context*, size_t n);

/*
 * Retrieve the currently selected index
 */
ssize_t arcan_tui_listwnd_tell(struct tui_context*);

/*
 * Force a reprocess of the list and entries, next refresh/process call
 * will update the render output state. Use when modifying flags field
 * of entries.
 */
void arcan_tui_listwnd_dirty(struct tui_context*);

/*
 * Return the context to its original state. This may invoke multiple
 * handlers, e.g. resize query_labels.
 *
 * The window dimensions, anchoring and constraints will be re-hinted
 * to what they were previous to calling arcan_tui_listwnd_setup, but
 * not any parent- reference.
 */
void arcan_tui_listwnd_release(struct tui_context*);

/*
 * The cases where we want to dynamically load the library as a plugin
 */
#else
typedef bool(* PTUILISTWND_SETUP)(
	struct tui_context*, struct tui_list_entry*, size_t n_entries);
typedef bool(* PTUILISTWND_STATUS)(
	struct tui_context*, struct tui_list_entry** out);
typedef void(* PTUILISTWND_DIRTY)(struct tui_context*);
typedef void(* PTUILISTWND_RELEASE)(struct tui_context*);
typedef void(* PTUILISTWND_SETPOS)(struct tui_context*, size_t);
typedef ssize_t(* PTUILISTWND_TELL)(struct tui_context*);

static PTUILISTWND_SETUP arcan_tui_listwnd_setup;
static PTUILISTWND_STATUS arcan_tui_listwnd_status;
static PTUILISTWND_DIRTY arcan_tui_listwnd_dirty;
static PTUILISTWND_RELEASE arcan_tui_listwnd_release;
static PTUILISTWND_SETPOS arcan_tui_listwnd_setpos;
static PTUILISTWND_TELL arcan_tui_listwnd_tell;

static bool arcan_tui_listwnd_dynload(
	void*(*lookup)(void*, const char*), void* tag)
{
#define M(TYPE, SYM) if (! (SYM = (TYPE) lookup(tag, #SYM)) ) return false
M(PTUILISTWND_SETUP, arcan_tui_listwnd_setup);
M(PTUILISTWND_STATUS, arcan_tui_listwnd_status);
M(PTUILISTWND_DIRTY, arcan_tui_listwnd_dirty);
M(PTUILISTWND_RELEASE, arcan_tui_listwnd_release);
M(PTUILISTWND_SETPOS, arcan_tui_listwnd_setpos);
M(PTUILISTWND_TELL, arcan_tui_listwnd_tell);
return true;
}
#endif
#endif
