/*
 TUI Lua Bindings

 Copyright (c) Bjorn Stahl
 All rights reserved.

 Redistribution and use in source and binary forms,
 with or without modification, are permitted provided that the
 following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 THE POSSIBILITY OF SUCH DAMAGE.
*/

#ifndef HAVE_ARCAN_SHMIF_TUI_LUA
#define HAVE_ARCAN_SHMIF_TUI_LUA

/* <= 64, should fit a uint64_t bitmap */
#define SEGMENT_LIMIT 64
struct blobio_meta;

enum tui_builtin_widgets {
	TWND_NORMAL = 0,
	TWND_LISTWND = 1,
	TWND_BUFWND = 2,
	TWND_READLINE = 3,
	TWND_LINEWND = 4
};

struct tui_lmeta;

struct widget_meta {
	struct tui_lmeta* parent;

	int widget_type;
	union {
		struct {
			intptr_t verify;
			intptr_t filter;

			char** history;
			size_t history_sz;

			char** suggest;
			size_t suggest_sz;
		} readline;
		struct {
			struct tui_list_entry* ents;
			size_t n_ents;
		} listview;
		struct {
			uint8_t* buf;
			size_t sz;
		} bufferview;
	};
};

/*
 * User-data structures passed as tui-tags.
 *
 * This represents a window tree of a 'toplevel' window in X11.
 *
 * The 'tag' property of each tui context is used to reference back to
 * tui_lmeta. Running :process on a window will thus cover the window and all
 * its children.
 */
struct tui_lmeta;
struct tui_lmeta {

/* These are squished together to fit arcan_tui_process multiplexing the
 * processing of multiple windows. Modifying subs[n] should match the reference
 * in submeta[refs]. tui->handlers.tag can't be used here as the widget states
 * proxy them with its own state tag. */
	union {
		struct tui_context* tui;
		struct tui_context* subs[SEGMENT_LIMIT];
	};
	struct tui_lmeta* submeta[SEGMENT_LIMIT];
	struct tui_lmeta* parent;
	size_t n_subs;

/* pending subsegment requests and their respective lua references */
	uint8_t pending_mask;
	intptr_t pending[8];

/* reference to the tui context itself, kept for subwindows as they have a
 * reference to the parent internally even if the Lua state does not
 * acknowledge it. */
	intptr_t tui_state;

/* reference to the currently active handler table */
	intptr_t href;

/* one 'tui' connection can be in multiple widget states, and these get
 * discrete 'on-completion' handlers as well their own metatables - the
 * following is used for mapping that */
	int widget_mode;
	intptr_t widget_closure;
	intptr_t widget_state;
	struct widget_meta* widget_meta;

/* linked list of bchunk like processing jobs */
	struct blobio_meta* blobs;

/* process- state that needs to be tracked locally for asio/popen/... */
	char* cwd;
	size_t cwd_sz;
	int cwd_fd;

	lua_State* lua;
};

struct blobio_meta {
	int fd;
	bool closed;
	bool input;

	bool got_buffer;
	char* buf;
	size_t buf_ofs;

	uintptr_t data_cb;

	struct blobio_meta* next;
	struct tui_lmeta* owner;
};

struct tui_context*
ltui_inherit(lua_State* L, arcan_tui_conn*);

int
luaopen_arcantui(lua_State* L);

#endif
