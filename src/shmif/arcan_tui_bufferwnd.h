/*
 Arcan Text-Oriented User Inteface Library, Extensions
 Copyright: 2018-2019, Bjorn Stahl
 License: 3-clause BSD
 Description: This header describes optional support components that
 extend TUI with some common helpers for input. They also server as
 simple examples for how to build similar ones, to lift, patch and
 include in custom projects.
*/

#ifndef HAVE_TUI_EXT_BUFFERWND
#define HAVE_TUI_EXT_BUFFERWND

/*
 * Description:
 * This function partially assumes control over a provided window and uses
 * it to present a view into the contents of the provided buffer. It takes
 * care of rendering, layouting, cursor management and text/binary working
 * modes.
 *
 * The caller is expected to run the normal tui refresh event loop.
 *
 * Arguments:
 * [buf] describes the buffer that will be exposed in the window.
 * [opts | NULL] contains statically controlled settings, versioned
 * with the size of the structure.
 *
 * Handlers/Allocation:
 * This dynamically allocates internally, and replaces the the normal set
 * of handlers. Use _bufferwnd_release to return the context to the state
 * it was before this function was called.
 *
 * The following list of functions will be chained and forwarded:
 * query_label
 * input_label
 *
 * Example:
 * see the #ifdef EXAMPLE block at the bottom of tui_bufferwnd.c
 */

enum bufferwnd_display_modes {
	BUFFERWND_VIEW_ASCII = 0,
	BUFFERWND_VIEW_UTF8 = 1,
	BUFFERWND_VIEW_HEX = 2,
	BUFFERWND_VIEW_HEX_DETAIL = 3,
};

enum bufferwnd_wrap_mode {
	BUFFERWND_WRAP_ALL = 0,
	BUFFERWND_WRAP_ACCEPT_LF,
	BUFFERWND_WRAP_ACCEPT_CR_LF
};

enum bufferwnd_color_mode {
	BUFFERWND_COLOR_NONE = 0,
	BUFFERWND_COLOR_PALETTE = 1,
	BUFFERWND_COLOR_CUSTOM = 2
};

/* these extend HEX_DETAILS with more information,
 * annotate uses a shadow buffer that absorbs key input
 * meta uses a shadow buffer to provide more information,
 */
enum bufferwnd_hex_mode {
	BUFFERWND_HEX_BASIC = 0,
	BUFFERWND_HEX_ASCII = 1,
	BUFFERWND_HEX_ANNOTATE = 2,
	BUFFERWND_HEX_META = 3,
};

/* hook to allow custom (data-dependent) formatting for
 * [bytev] at buffer position [pos], write values into *attr */
typedef void(*attr_lookup_fn)(struct tui_context* T, void* tag,
	uint8_t bytev, size_t pos, uint32_t* ch, struct tui_screen_attr* attr);

typedef bool(*commit_write_fn)(struct tui_context* T,
	void* tag, const uint8_t* buf, size_t nb, size_t ofs);

struct tui_bufferwnd_opts {
/* Disable any editing controls */
	bool read_only;

/* Set to allow finalization controls (commit, cancel) */
	bool allow_exit;

/* All cursor management (moving, selection, ...) is disabled */
	bool hide_cursor;

/* Initial display/wrap_mode, this is still user-changeable */
	int view_mode;
	int wrap_mode;
	int color_mode;
	int hex_mode;

/* Hooks for custom colorization, and a validation / commit function for
 * buffer edits */
	attr_lookup_fn custom_attr;
	commit_write_fn commit;
	void* cbtag;

/* When a buffer position is written out, apply this offset value first */
	uint64_t offset;
};

#ifndef ARCAN_TUI_DYNAMIC
void arcan_tui_bufferwnd_setup(
	struct tui_context* ctx, uint8_t* buf, size_t buf_sz,
	struct tui_bufferwnd_opts*, size_t opts_sz
);

/*
 * Return 1 if OK, 0 if commit-exit is requested, -1 if cancel-exit is requested,
 * this is only useful / valid if the [allow_exit] option has been set.
 * The exit status can be reset by calling bufferwnd_synch.
 */
int arcan_tui_bufferwnd_status(struct tui_context*);

/*
 * Replace the active buffer with another. This may cause delta writes to
 * be synched if the commit write function has been provided.
 */
void arcan_tui_bufferwnd_synch(
	struct tui_context* T, uint8_t* buf, size_t buf_sz, size_t prefix_ofs);

/*
 * Move the cursor to point at a specific offset in the buffer (ofs < buf_sz),
 * this may cause a repagination.
 */
void arcan_tui_bufferwnd_seek(struct tui_context* T, size_t buf_ofs);

/*
 * Retrieve the current cursor buffer offset and (if set) view options
 */
size_t arcan_tui_bufferwnd_tell(
	struct tui_context* T, struct tui_bufferwnd_opts*);

void arcan_tui_bufferwnd_release(struct tui_context* T);

/*
 * Take a context that has previously been setup via arcan_tui_bufferwnd_setup,
 * and restore its set of handlers/tag (not the contents itself) to the state
 * it was on the initial call. Normal deallocation might happen as part of the
 * on_destroy event handler on the other hand, and in such cases _free should
 * not be called.
 */
#else
typedef bool(* PTUIBUFFERWND_SETUP)(
	struct tui_context*, uint8_t*, size_t, struct tui_bufferwnd_opts*, size_t);
typedef void(* PTUIBUFFERWND_RELEASE)(struct tui_context*);
typedef void(* PTUIBUFFERWND_SYNCH)(
	struct tui_context*, uint8_t* buf, size_t, size_t);
typedef void(* PTUIBUFFERWND_SEEK)(struct tui_context*, size_t);
typedef int(* PTUIBUFFERWND_STATUS)(struct tui_context*);
typedef size_t(* PTUIBUFFERWND_TELL)(struct tui_context*, struct tui_bufferwnd_opts*);

static PTUIBUFFERWND_SETUP arcan_tui_bufferwnd_setup;
static PTUIBUFFERWND_RELEASE arcan_tui_bufferwnd_release;
static PTUIBUFFERWND_SYNCH arcan_tui_bufferwnd_synch;
static PTUIBUFFERWND_SEEK arcan_tui_bufferwnd_seek;
static PTUIBUFFERWND_STATUS arcan_tui_bufferwnd_status;
static PTUIBUFFERWND_TELL arcan_tui_bufferwnd_tell;

static bool arcan_tui_bufferwnd_dynload(
	void*(*lookup)(void*, const char*), void* tag)
{
#define M(TYPE, SYM) if (! (SYM = (TYPE) lookup(tag, #SYM)) ) return false
M(PTUIBUFFERWND_SETUP, arcan_tui_bufferwnd_setup);
M(PTUIBUFFERWND_RELEASE, arcan_tui_bufferwnd_release);
M(PTUIBUFFERWND_SYNCH, arcan_tui_bufferwnd_synch);
M(PTUIBUFFERWND_SEEK, arcan_tui_bufferwnd_seek);
M(PTUIBUFFERWND_STATUS, arcan_tui_bufferwnd_status);
M(PTUIBUFFERWND_TELL, arcan_tui_bufferwnd_tell);
return true;
}
#endif
#endif
