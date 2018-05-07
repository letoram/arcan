/*
 TUI Lua Bindings

 Copyright (c) 2017-2018, Bjorn Stahl
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

/*
 * user-data structures passed as tui-tags
 */
struct tui_lmeta {
	struct tui_context* tui;
	intptr_t href;

/* pending subsegment requests and their respective lua references */
	uint8_t pending_mask;
	intptr_t pending[8];

	const char* last_words;
	lua_State* lua;
};

struct tui_attr {
	struct tui_screen_attr attr;
};

#ifdef ARCAN_LUA_TUI_DYNAMIC
typedef void (* PLTUIEXPOSE)(lua_State*);
static PLTUIEXPOSE tui_lua_expose;

static bool arcan_tui_dynload(void*(*lookup)(void*, const char*), void* tag)
{
	return ( tui_lua_expose = lookup(tag, "tui_lua_expose") ) != NULL;
}

#else

/*
 * apply/add the TUI/Lua bindings to a lua VM context
 */
void tui_lua_expose(lua_State*);
#endif

#endif
