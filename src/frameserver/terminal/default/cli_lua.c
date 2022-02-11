#include <arcan_shmif.h>
#include "cli.h"
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <arcan_tui.h>
#include "tui_lua.h"

#include "lash.h"

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

	if (LUA_OK != luaL_loadbuffer(lua, (const char*) lash_lua, lash_lua_len, "lash")){
		const char* msg = lua_tostring(lua, -1);
		if (isatty(STDOUT_FILENO)){
			fprintf(stdout, "lua_cli failed: %s", msg);
		}
		else{
			LOG("lua_cli failed: %s", msg);
		}
		return EXIT_FAILURE;
		arcan_tui_destroy(tui, "error running builtin script");
	}

	lua_call(lua, 0, 0);

/* should GC the tui context, but verify this at some point to make valgrind
 * and other leak detectors less cranky */
	lua_close(lua);

	return EXIT_SUCCESS;
}
