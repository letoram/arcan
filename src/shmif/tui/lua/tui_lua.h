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

struct blobio_meta;

enum tui_builtin_widgets {
	TWND_NORMAL = 0,
	TWND_LISTWND = 1,
	TWND_BUFWND = 2,
	TWND_READLINE = 3,
	TWND_LINEWND = 4
};

/*
 * user-data structures passed as tui-tags
 */
struct tui_lmeta {

/* just have a fixed cap of these and compact on free, this is still
 * an absurd amount of subwindows */
	union {
		struct tui_context* tui;
		struct tui_context* subs[64];
	};

	size_t n_subs;
	int widget_mode;
	struct tui_list_entry* tmplist;

	intptr_t href;
	intptr_t widget_closure;

/* pending subsegment requests and their respective lua references */
	uint8_t pending_mask;
	intptr_t pending[8];

/* linked list of bchunk like processing jobs */
	struct blobio_meta* blobs;

	const char* last_words;
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

struct tui_attr {
	struct tui_screen_attr attr;
};

struct tui_context*
ltui_inherit(lua_State* L, arcan_tui_conn*);

int
luaopen_arcantui(lua_State* L);

#endif
