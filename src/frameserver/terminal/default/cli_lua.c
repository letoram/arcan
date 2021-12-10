#include <arcan_shmif.h>
#include "cli.h"
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <arcan_tui.h>
#include "tui_lua.h"

/* placeholder:
 *
 * What is needed is a short known 'loader' that pulls in user-config
 * scripts in a safe and recoverable way.
 *
 * eventually the builtin- safe outer should match what we are doing
 * in the normal cli.c so that it can be removed entirely.
 */
const char* hello = "\
local function redraw(wnd)\n\
	print(\"redrawing\")\n\
	wnd:write_to(1, 1, \"hello world\")\n\
end\n\
root:set_handlers({resized = redraw})\n\
\
	print(\"hi\")\n\
while (root:process()) do\n\
	root:refresh()\n\
end\n\
	print(\"done\")\n\
";

/*
 * perhaps useful to share the lexer from pipeworld to process readline
 * or translate the one from cli
 */

/*
 * we need some shell support functions,
 * e.g. fchdir, resolve path, ...
 * handover exec, asynch_popen, log
 *
 * then share some fuctions from the arcan platform, asynch globbing as
 * something that makes sense - though really - just asio_popen find makes more
 * sense in this context where spawning processes is kindof what we do.
 *
 * perhaps abstraction gain some process information that requires
 * proc magic vs sysctl vs.. to not lose portability
 */
int arcterm_luacli_run(struct arcan_shmif_cont* shmif, struct arg_arr* args)
{
	lua_State* lua = luaL_newstate();
	if (!lua)
		return EXIT_FAILURE;

	luaL_openlibs(lua);

	lua_newtable(lua);
	struct tui_context* tui = ltui_inherit(lua, (arcan_tui_conn*) shmif);
	if (!tui){
		arcan_shmif_last_words(shmif, "couldn't setup lua VM");
		arcan_shmif_drop(shmif);
		lua_close(lua);
		return EXIT_FAILURE;
	}

	lua_setglobal(lua, "root");
	lua_setglobal(lua, "tui");

	if (LUA_OK != luaL_dostring(lua, hello)){
		const char* msg = lua_tostring(lua, -1);
		if (isatty(STDOUT_FILENO)){
			fprintf(stdout, "lua_cli failed: %s", msg);
		}
		else{
			LOG("lua_cli failed: %s", msg);
		}
		arcan_tui_destroy(tui, "error running builtin script");
	}

/* should GC the tui context, but verify this at some point to make valgrind
 * and other leak detectors less cranky */
	lua_close(lua);

	return EXIT_SUCCESS;
}
