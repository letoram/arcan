/*
 Arcan Text-Oriented User Interface Library, Extensions
 Copyright: 2018-2019, Bjorn Stahl
 License: 3-clause BSD
 Description: This widget adds support for transforming a tui context
 into a line oriented window with scrollback.
*/

#ifndef HAVE_TUI_LINEWND
#define HAVE_TUI_LINEWND


/*
 * Description:
 *
 * Arguments:
 * [ctx] (!null) references the context to control
 *
 * Returns:
 * true if context was allocated and setup, false on allocation failure or
 * argument errors.
 *
 * Handlers/Allocation:
 * This dynamically allocates internally, and replaces the normal set of
 * handlers. Use _linewnd_restore to return the context to the state it was
 * in before this function was called.
 *
 * This hooks and forwards all the normal table handlers, it is only in the
 * context of scrollback state where events gets masked and so on.
 *
 * Example:
 * See the #ifdef EXAMPLE block at the bottom of tui_linewnd.c
 */

struct tui_linewnd_line;
struct tui_linewnd_line {
	size_t n_cells;
	struct tui_cell* cells;
};

#ifndef ARCAN_TUI_DYNAMIC
bool arcan_tui_linewnd_setup(
	struct tui_context*, struct tui_constraints* cons);

/*
 * Layout / render function, this can be used on a non-linewnd context
 * as well in order to get consistent wrapping modes, in other widgets.
 *
 * If [start_row] or [start_col] is out-of-bounds, 0 will be returned and
 * no drawing will be performed.
 *
 * If [end_row, end_col] is out-of-bounds or less than [start_row, start_col]
 * it will be set to the context dimensions.
 *
 * Returns the row-advance after processing the line buffer
 *   if > n_lines wrapping was applied on long lines.
 *   if < n_lines rendering was cancelled due to reaching the end of the screen.
 */

enum linewnd_render_flags {
	LINEWND_RENDER_NOTAB = 1,
	LINEWND_RENDER_WRAP = 2
};

size_t arcan_tui_linewnd_render(struct tui_context*,
	struct tui_linewnd_line*, size_t n_lines,
	size_t start_row, size_t start_col,
	size_t end_row, size_t end_col,
	size_t* tabs, size_t n_tabs,
	int flags
);

/*
 * Replace the current history buffer with a new one
 */
void arcan_tui_linewnd_set_buffer(
	struct tui_context*, struct tui_linewnd_line*, size_t n_lines);

/*
 * Retrieve a snapshot of the last n_lines of the history buffer,
 * returns the actual number of lines in the buffer.
 */
size_t arcan_tui_linewnd_get_buffer(
	struct tui_context*, struct tui_linewnd_line*, size_t n_lines);

/*
 * Commit the set line(s) to the currently active buffer,
 * this will create an internal copy as part of the buffer management
 */
void arcan_tui_linewnd_add_line(
	struct tui_context*, const struct tui_linewnd_line*);

/*
 * Return handler set to the state it was before the linewindow was
 * setup.
 */
void arcan_tui_linewnd_release(struct tui_context*);

/*
 * The cases where we want to dynamically load the library as a plugin
 */
#else
typedef size_t(* PTUILINEWND_RENDER)(
	struct tui_context*, struct tui_linewnd_line*, size_t n_line,
	size_t start_row, size_t start_col, size_t end_row, size_t end_col,
	size_t* tabs, size_t n_tabs, int flags);
typedef bool(* PTUILINEWND_SETUP)(
	struct tui_context*, struct tui_list_entry*, size_t n_entries);
typedef void(* PTUILINEWND_SETBUFFER)(
	struct tui_context*, struct tui_linewnd_line*, size_t n_lines);
typedef void(* PTUILINEWND_RELEASE)(struct tui_context*);

static PTUILINEWND_RENDER arcan_tui_linewnd_render;
static PTUILINEWND_SETUP arcan_tui_linewnd_setup;
static PTUILINEWND_SETBUFFER arcan_tui_linewnd_set_buffer;
static PTUILINEWND_ADDLINE arcan_tui_linewnd_add_line;
static PTUILINEWND_RELEASE arcan_tui_linewnd_release;

static bool arcan_tui_linewnd_dynload(
	void*(*lookup)(void*, const char*), void* tag)
{
#define M(TYPE, SYM) if (! (SYM = (TYPE) lookup(tag, #SYM)) ) return false
M(PTUILINEWND_SETUP, arcan_tui_linewnd_setup);
M(PTUILINEWND_SETBUFFER, arcan_tui_linewnd_set_buffer);
M(PTUILINEWND_ADDLINE, arcan_tui_linewnd_add_line);
M(PTUILINEWND_RELEASE, arcan_tui_linewnd_release);
M(PTUILINEWND_RENDER, arcan_tui_linewnd_render);
#undef M
return true;
}
#endif
#endif
