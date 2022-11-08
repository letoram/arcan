#include <arcan_shmif.h>
#include "cli.h"
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <arcan_tui.h>
#include <unistd.h>
#include <fcntl.h>
#include "tui_lua.h"

#include "lash.h"

/*
 * notes:
 *
 * ltui_inherit():
 *   register_tuimeta(): (assumes one dst table at -1)
 *    if (unknown(L, TUI_META)) -> new_meta
 *       (set-meta) <-
 *
 *   add .flags
 *   add .colors
 *   add .keys
 *   add .modifiers
 *
 *   register widgetmetas()
 *
 *   new_userdata
 *      new_userdata_copy
 *      <- ref.
 *
 *   set-metatable
 *   (check slot 3?!)
 *   setup-connection (due to tui_open)
 */

static __attribute__((used)) void dump_stack(lua_State* ctx)
{
	int top = lua_gettop(ctx);

	for (size_t i = 1; i <= top; i++){
		int t = lua_type(ctx, i);

		switch (t){
		case LUA_TBOOLEAN:
			fprintf(stderr, lua_toboolean(ctx, i) ? "true" : "false");
		break;
		case LUA_TSTRING:
			fprintf(stderr, "%zu\t'%s'\n", i, lua_tostring(ctx, i));
			break;
		case LUA_TNUMBER:
			fprintf(stderr, "%zu\t%g\n", i, lua_tonumber(ctx, i));
			break;
		case LUA_TUSERDATA:{
				fprintf(stderr, "%zu\tuserdata\n", i);
		}
		break;
		default:
			fprintf(stderr, "%zu\t%s\n", i, lua_typename(ctx, t));
			break;
		}
	}

	fprintf(stderr, "\n");
}

static int emptyf(lua_State* L)
{
	fprintf(stderr, "tui:open() not supported inside arcterm, use tui.root");
	return 0;
}

#include "../../../engine/external/bit.c"
#include "../../../shmif/tui/tui_int.h"

int arcterm_luacli_run(struct arcan_shmif_cont* shmif, struct arg_arr* args)
{
	lua_State* lua = luaL_newstate();
	if (!lua)
		return EXIT_FAILURE;

	long long last = arcan_timemillis();
	luaL_openlibs(lua);
	lua_pop(lua, luaopen_bit(lua));

/* get a table:
 *   require 'arcantui' -> stack */

	lua_newtable(lua);
	struct tui_context* tui =
		ltui_inherit(lua, (arcan_tui_conn*) shmif, NULL);

/* the record option for debugging / easy sharing etc. should be available
 * immediately so we don't miss any frames and we can't do it before as the
 * ltui_inherit calls builds the context we're supposed to use. */
	const char* val;
	if (arg_lookup(args, "record", 0, &val) && val){
		int fd = open(val, O_WRONLY | O_CREAT, 0600);
		if (-1 != fd){
			tui_event_inject(tui, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_BCHUNK_OUT,
				.tgt.ioevs[0] = fd,
				.tgt.message = "tuiani"
			});
			close(fd);
		}
		else{
			LOG("record=%s : couldn't create file for tuiani out\n", val);
		}
	}


/* stack:
 *  -2 table
 *  -1 userdata
 */
	if (!tui){
		arcan_shmif_last_words(shmif, "couldn't setup lua VM");
		arcan_shmif_drop(shmif);
		lua_close(lua);
		return EXIT_FAILURE;
	}

/* stack:
 *  -3 table
 *  -2 userdata
 *  -1 root
 */
	lua_pushliteral(lua, "root");
	lua_pushvalue(lua, -2);

/* stack:
 * -4 table
 * -3 userdata
 * -2 "root"
 * -1 userdata (alias)
 */
	lua_settable(lua, -4);

/* stack:
 * -1 table
 */
	lua_pop(lua, 1);

/* replace open with empty function */
	lua_pushliteral(lua, "open");
	lua_pushcfunction(lua, emptyf);
	lua_settable(lua, -3);

/* and now set
 *   tui = require 'arcantui'
 */
	lua_setglobal(lua, "tui");

/* add a debug-traceback call as the error function */
	lua_getglobal(lua, "debug");
	lua_getfield(lua, -1, "traceback");
	lua_remove(lua, -2);

/* parse-run builtin script */
	if (0 != luaL_loadbuffer(lua, (const char*) lash_lua, lash_lua_len, "lash")){
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

/* pcall into it, dump the trace on error */
	if (0 != lua_pcall(lua, 0, 0, 1)){
		fprintf(stderr, "arcterm[lash] - builtin- loader failed:\n");
		fprintf(stderr, "\nBacktrace:\n%s\n", luaL_optstring(lua, -1, "\tno trace"));
	}

/* this should GC the tui connection should it not already be closed */
	lua_close(lua);

	return EXIT_SUCCESS;
}
