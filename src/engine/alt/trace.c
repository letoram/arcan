/*
 * Copyright: Björn Ståhl
 * License: BSDv3, see COPYING file in arcan source repsitory.
 * Reference: https://arcan-fe.com
 * Description: Interfacing the engine tracing layer with corresponding
 * Lua stage, mainly for automated analysis and report generation.
 */
#include <stdint.h>
#include <stdlib.h>
#include <inttypes.h>
#include <stdbool.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <string.h>

typedef struct arcan_vobject arcan_vobject;

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_mem.h"
#include "alt/support.h"
#include "alt/trace.h"
#include "alt/types.h"

static bool got_trace_buffer;
static uint8_t* trace_buffer;
static size_t trace_buffer_sz;
static intptr_t trace_cb;

static char* crash_source;

extern void arcan_conductor_toggle_watchdog();

char* alt_trace_crash_source()
{
	return crash_source;
}

void alt_trace_set_crash_source(const char* msg)
{
	free(crash_source);
	crash_source = NULL;
	if (msg)
		crash_source = strdup(msg);
}

void alt_trace_callstack(lua_State* L, FILE* out)
{
/*
 * we can't trust debug.traceback to be present or in an intact state,
 * the user script might try to hide something from us -- so reset
 * the lua namespace then re-apply the restrictions.
 */
	char* res = NULL;
	luaL_openlibs(L);

	lua_settop(L, -2);
	lua_getfield(L, LUA_GLOBALSINDEX, "debug");
	if (!lua_istable(L, -1))
		lua_pop(L, 1);
	else {
		lua_getfield(L, -1, "traceback");
		if (!lua_isfunction(L, -1))
			lua_pop(L, 2);
		else {
			lua_call(L, 0, 1);
			const char* str = lua_tostring(L, -1);
			fprintf(out, "%s\n", str);
		}
	}

	alt_apply_ban(L);
}

bool alt_trace_start(lua_State* L, intptr_t cb, size_t sz)
{
	uint8_t* interim =
		arcan_alloc_mem(sz,
			ARCAN_MEM_EXTSTRUCT,
			ARCAN_MEM_BZERO | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_NATURAL
		);

	if (!interim){
		luaL_unref(L, LUA_REGISTRYINDEX, cb);
		return false;
	}

	arcan_trace_setbuffer(interim, sz, &got_trace_buffer);
	trace_buffer = interim;
	trace_buffer_sz = sz;
	trace_cb = cb;

	return true;
}

void alt_trace_finish(lua_State* L)
{
	if (!got_trace_buffer)
		return;

	lua_rawgeti(L, LUA_REGISTRYINDEX, trace_cb);
	lua_newtable(L);
	int ttop = lua_gettop(L);

	char* buf = (char*)trace_buffer;
	size_t pos = 0;

	size_t ind = 1;
	while (trace_buffer[pos++] == 0xff){
		lua_pushnumber(L, ind++);
		lua_newtable(L);
		int top = lua_gettop(L);

/* timestamp */
		uint64_t ts;
		memcpy(&ts, &buf[pos], sizeof(ts));
		pos += 8;
		tblnum(L, "timestamp", ts, top);

/* system */
		size_t nb = strlen(&buf[pos]);
		lua_pushliteral(L, "system");
		lua_pushlstring(L, &buf[pos], nb);
		lua_rawset(L, top);
		pos += nb + 1;

/* subsystem */
		nb = strlen(&buf[pos]);
		lua_pushliteral(L, "subsystem");
		lua_pushlstring(L, &buf[pos], nb);
		lua_rawset(L, top);
		pos += nb + 1;

/* trigger */
		uint8_t inb = trace_buffer[pos++];
		tblnum(L, "trigger", inb, top);

/* tracelevel */
		inb = trace_buffer[pos++];
		switch (inb){
		case TRACE_SYS_DEFAULT:
			tblstr(L, "path", "default", top);
		break;
		case TRACE_SYS_SLOW:
			tblstr(L, "path", "slow", top);
		break;
		case TRACE_SYS_WARN:
			tblstr(L, "path", "warning", top);
		break;
		case TRACE_SYS_FAST:
			tblstr(L, "path", "fast", top);
		break;
		case TRACE_SYS_ERROR:
			tblstr(L, "path", "error", top);
		break;
		default:
			tblstr(L, "path", "broken", top);
		break;
		}

/* identifier */
		uint64_t ident;
		memcpy(&ident, &buf[pos], 8);
		pos += 8;
		tblnum(L, "identifier", ident, top);

/* quantifier */
		uint32_t quant;
		memcpy(&quant, &buf[pos], 4);
		pos += 4;
		tblnum(L, "quantity", quant, top);

/* caller message */
		nb = strlen(&buf[pos]);
		lua_pushliteral(L, "message");
		lua_pushlstring(L, &buf[pos], nb);
		lua_rawset(L, top);
		pos += nb + 1;

/* step outer table */
		lua_rawset(L, ttop);
	}

/* process and repack - format is described in arcan_trace.c,
 * free first so that we can call ourselves even from the fatal handler */
	free(trace_buffer);
	arcan_trace_setbuffer(NULL, 0, NULL);
	trace_buffer = NULL;
	trace_buffer_sz = 0;
	got_trace_buffer = false;

/* this might incur some heavy processing, so the tradeoff with the
 * watchdog might hurt a bit too much and the data itself is more
 * important so disable it (should it be enabled) */
	arcan_conductor_toggle_watchdog();
		alt_call(L, CB_SOURCE_NONE, 0, 1, 0, LINE_TAG":trace");
	arcan_conductor_toggle_watchdog();
	luaL_unref(L, LUA_REGISTRYINDEX, trace_cb);
}
