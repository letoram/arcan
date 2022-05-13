/*
 * Copyright: Björn Ståhl
 * License: BSDv3, see COPYING file in arcan source repsitory.
 * Reference: https://arcan-fe.com
 * Description: Lua VM trickery to get script hand-over, crash recovery,
 * debug information and execution/function lookup.
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <setjmp.h>

#include "alt/opaque.h"

#include "platform.h"
#include "arcan_lua.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#include "alt/types.h"
#include "alt/support.h"
#include "alt/trace.h"

/* scratch buffer caching the applname as a prefix, then copying in the name of
 * the entrypoint to lookup and call - this happens frequently enough that
 * having a ref-cache might be faster, though need hooks to detect _G changes
 * to the entrypoints. */
static const size_t prefix_maxlen = 34;
static char prefix_buf[128];
static size_t prefix_len;

/* all of these are simply to track some kind of constant string reference of
 * what current context we are calling into the VM from so that if there is a
 * scripting error, more data can be added to get better logs out.
 */
static void wraperr(lua_State* L, int errc, const char* src);
static int alt_cb_kind;
static lua_Number alt_cb_source;
static lua_State* fatal_context;
unsigned lua_debug_level;

/* crash recovery takes quite a few special hoops, but the one relevant here
 * is that we go from scripting error or VM state inconsistency to
 * fatal/panic, track to prevent against recursion and then longjmp to new
 * set of scripts.*/
static bool in_panic_state;
static bool in_fatal_state;
extern jmp_buf arcanmain_recover_state;

/* dump argument stack, stack trace are shown only when --debug is set */
static void dump_stack(lua_State* L, FILE* dst)
{
	int top = lua_gettop(L);
	fprintf(dst, "-- stack dump (%d)--\n", top);

	for (size_t i = 1; i <= top; i++){
		int t = lua_type(L, i);

		switch (t){
		case LUA_TBOOLEAN:
			arcan_warning(lua_toboolean(L, i) ? "true" : "false");
		break;
		case LUA_TSTRING:
			arcan_warning("%d\t'%s'\n", i, lua_tostring(L, i));
			break;
		case LUA_TNUMBER:
			arcan_warning("%d\t%g\n", i, lua_tonumber(L, i));
			break;
		default:
			arcan_warning("%d\t%s\n", i, lua_typename(L, t));
			break;
		}
	}

	arcan_warning("\n");
}

arcan_vobj_id luaL_checkvid(
		lua_State* L, int num, arcan_vobject** dptr)
{
	arcan_vobj_id lnum = luaL_checknumber(L, num);
	arcan_vobj_id res = luavid_tovid( lnum );

	if (dptr){
		*dptr = arcan_video_getobject(res);
		if (!(*dptr))
			arcan_fatal("invalid VID requested (%"PRIxVOBJ")\n", res);
	}

	return res;
}

/*
 * Arcan to Lua call with a version that provides more detailed stack data on
 * error, this is primarily for the case where we have C->lua->callback and
 * later C->callback->error where stack unwinding clears data.
 *
 * The details are only added on a debug build as this is invoked quite
 * frequently and it is not cheap.
 */
void alt_call(
	struct lua_State* L, int cbkind, uintptr_t source,
	int nargs, int retc, const char* src)
{
	alt_cb_source = vid_toluavid(source);
	alt_cb_kind = cbkind;

/* Safeguard against mismanaged alua_call stack, if the first argument isn't a
 * function - somebody screwed up. The fatal/shutdown action in those cases are
 * "difficult" to say the least" */
	if (lua_type(L, -(nargs+1)) != LUA_TFUNCTION){
		dump_stack(L, stderr);
		lua_settop(L, 0);
		alt_cb_source = 0;
		return;
	}

	int errind = 0;
	errind = lua_gettop(L) - nargs;

/* These should >really< be looked up once during setup and then kept on the
 * stack, this is substantial overhead added to each and every call into the VM
 * (entry-point lookup -> error function lookup). The possible compromise to
 * allow the dynamic behavior still is to have a trigger for _G changing the
 * respective functions, and inject a default _fatal function that returns
 * debug.traceback(). */
	if (alt_lookup_entry(L, "fatal", 5)){
	}
	else{
		lua_getglobal(L, "debug");
		lua_getfield(L, -1, "traceback");
		lua_remove(L, -2);
	}

	lua_insert(L, errind);
	int errc = lua_pcall(L, nargs, retc, errind);

	if (errc != 0){
/* if we have a tracing session going, try to finish that one along
 * with the backtrace we might have received, this should be robust
 * from recursion (scripting error in the callback handler) since
 * the got_trace_buffer trigger is cleared between calls */
		const char* msg = luaL_optstring(L, -1, "no backtrace");
		lua_remove(L, errind);
		TRACE_MARK_ONESHOT("scripting", "crash", TRACE_SYS_ERROR, 0, 0, msg);
		arcan_trace_setbuffer(NULL, 0, NULL);
		alt_trace_finish(L);

		wraperr(L, errc, src);
		return;
	}

	lua_remove(L, errind);
}

lua_Number luaL_optbnumber(lua_State* L, int narg, lua_Number opt)
{
	if (lua_isnumber(L, narg))
		return lua_tonumber(L, narg);
	else if (lua_isboolean(L, narg))
		return lua_toboolean(L, narg);
	else
		return opt;
}

lua_Number luaL_checkbnumber(lua_State* L, int narg)
{
	lua_Number d = lua_tonumber(L, narg);
	if (d == 0 && !lua_isnumber(L, narg)){
		if (!lua_isboolean(L, narg))
			luaL_typerror(L, narg, "number or boolean");
		else
			d = lua_toboolean(L, narg);
	}
	return d;
}

static void panic(lua_State* L)
{
	lua_debug_level = 2;

	if (alt_cb_kind != CB_SOURCE_NONE){
		char vidbuf[64] = {0};
		snprintf(vidbuf, 63,
			"script error in callback for VID (%.0lf)", alt_cb_source);
		wraperr(L, -1, vidbuf);
	} else{
		in_panic_state = true;
		wraperr(L, -1, "(panic)");
	}

	arcan_warning("LUA VM is in a panic state, "
		"recovery handover might be impossible.\n");

	alt_trace_set_crash_source("VM panic");
	longjmp(arcanmain_recover_state, ARCAN_LUA_RECOVERY_SWITCH);
}

/*
 * There are four error paths,
 * [wraperr] is called on a lua_pcall() failure, panic or parent watchdog
 * [panic]   is called by the lua VM on an internal failure
 * [alt_fatal] is called on C API functions from Lua with bad arguments
 *              (through arcan_fatal redefinition)
 * [SIGINT-handler] is used by the parent process if we fail to ping the
 *                  watchdog (conductor processing)
 *
 * + the special 'alua_call' wrapper that may forward here with
 * the results from calling either _fatal entry point or debug:traceback
 */
static void fatal_handover(lua_State* L)
{
/* We reach this when the arcan-lua API has been misused, most of the time
 * this should simply be a fatal error, being lenient on this will degrade
 * quality of scripts over time. The exception is when the calls come from
 * an external process, which is part of letting other languages and tools
 * drive the rendering - or when part of automated testing.
 *
 * In those cases we need a way to alert that the client did something bad
 * and is expected to have recovered from the argument errors. For this we
 * use yet another entry point [_fatal_handover]. */
		if (!alt_lookup_entry(L, "fatal_handover", 14) || in_fatal_state){
		in_fatal_state = false;
		return;
	}

/* still check from script error in the error function */
	in_fatal_state = true;
	lua_settop(L, 0);
	alt_lookup_entry(L, "fatal_handover", 14);
	lua_pushstring(L,
		alt_trace_crash_source() ? alt_trace_crash_source() : "");
	alt_call(L, CB_SOURCE_NONE, 0, 1, 1, LINE_TAG":fatal_handover");
	in_fatal_state = false;

	if (lua_type(L, -1) == LUA_TBOOLEAN && lua_toboolean(L, -1)){
		lua_pop(L, 1);
		longjmp(arcanmain_recover_state, ARCAN_LUA_RECOVERY_FATAL_IGNORE);
	}
}

void alt_fatal(const char* msg, ...)
{
	va_list args;

	lua_State* L = fatal_context;

	char* buf;
	size_t buf_sz;
	FILE* stream = open_memstream(&buf, &buf_sz);
	if (stream){
		va_start(args, msg);

/* with LWA we shouldn't format the crash source as it will go to last_words
 * first, and arcan will treat the message as garbage */
#ifndef ARCAN_LWA
			fprintf(stream, "\x1b[0m\n");
#endif
			vfprintf(stream, msg, args);
			fprintf(stream, "\n");
			alt_trace_callstack(L, stream);
			alt_trace_set_crash_source(buf);
			fclose(stream);
		va_end(args);
	}
	else
		alt_trace_set_crash_source("couldn't build stream");

	fatal_handover(L);

	if (lua_debug_level > 2)
		arcan_state_dump("misuse", alt_trace_crash_source(), "");

	longjmp(arcanmain_recover_state, ARCAN_LUA_RECOVERY_SWITCH);
}

static void wraperr(lua_State* L, int errc, const char* src)
{
/*
 * if (lua_debug_level)
		luaL.lastsrc = src;
 */

	const char* mesg = in_panic_state ?
		"Lua VM state broken, panic" :
		luaL_optstring(L, -1, "unknown");

/*
 * currently unused, pending refactor of arcan_warning/arcan_fatal
 * int severity = luaL_optnumber(L, 2, 0);
 */
	arcan_state_dump("crash", mesg, src);
	char* buf;
	size_t buf_sz;
	FILE* stream = open_memstream(&buf, &buf_sz);

	if (stream){
		if (lua_debug_level){
			fprintf(stream, "Warning: wraperr((), %s, from %s\n", mesg, src);
			alt_trace_callstack(L, stream);
			dump_stack(L, stream);
		}

		fprintf(stream, "\n\x1b[1mScript failure:\n \x1b[32m %s\n"
		"\x1b[39mC-entry point: \x1b[32m %s \x1b[39m\x1b[0m.\n", mesg, src);

		fprintf(stream,
			"\nHanding over to recovery script (or shutdown if none present).\n");

		fclose(stream);
		alt_trace_set_crash_source(buf);
	}
	else
		alt_trace_set_crash_source(mesg);

/* first try cooperative script error recovery */
	fatal_handover(L);

/* if that fails, well switch to a recovery script */
	longjmp(arcanmain_recover_state, ARCAN_LUA_RECOVERY_SWITCH);
}

/*
 * Nil out whatever functions / tables the build- system defined that we should
 * not have. Should possibly replace this with a function that maps a warning
 * about the banned function.
 */
#include "arcan_bootstrap.h"
void alt_apply_ban(lua_State* L)
{
	int rv = luaL_loadbuffer(L,
		(const char*) arcan_bootstrap_lua,
		arcan_bootstrap_lua_len, "bootstrap"
	);

	if (0 != rv){
		arcan_warning("BROKEN BUILD: bootstrap code couldn't be parsed\n");
	}
	else
/* called from err-handler will be ignored as it'll fatal or reload */
		rv = lua_pcall(L, 0, 0, 0);
}

void alt_setup_context(lua_State* L, const char* applname)
{
	lua_atpanic(L, (lua_CFunction) panic);
	fatal_context = L;

/* write / cache the prefix length (myapplname) that we will then scratch/
 * append _entry_point for each specific alua call to a named appl function */
	prefix_len = strlen(applname);

	if (prefix_len + prefix_maxlen >= sizeof(prefix_buf)){
		arcan_fatal("applname exceeds prefix-limit");
	}

	memcpy(prefix_buf, applname, prefix_len);
}

bool alt_lookup_entry(lua_State* L, const char* ep, size_t len)
{
	if (!len){
		prefix_buf[prefix_len] = '\0';
	}
	else {
		prefix_buf[prefix_len] = '_';
		memcpy(&prefix_buf[prefix_len+1], ep, len);
		prefix_buf[prefix_len+len+1] = '\0';
	}
	lua_getglobal(L, prefix_buf);

	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return false;
	}

	return true;
}
