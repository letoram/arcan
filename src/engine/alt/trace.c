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
#include <arcan_shmif.h>

typedef struct arcan_vobject arcan_vobject;

#include "arcan_math.h"
#include "arcan_general.h"
#include "os_platform.h"
#include "arcan_lua.h"
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

static void put_shmif_luastr(const char* msg, FILE* out)
{
	while (msg && *msg){
		if (*msg == '\n'){
			fputc('\\', out);
			fputc('n', out);
			msg++;
			continue;
		}
		if (*msg == '\t')
			fputs("     ", out);
		else if (*msg == ':')
			fputs("\t", out);
		else if (*msg == ',')
			fputc('\\', out);
		else
			fputc(*msg, out);
		msg++;
	}
}

void alt_trace_dumptable_raw(lua_State* L, int ofs, int cap, FILE* out)
{
	if (lua_type(L, -1) != LUA_TTABLE)
		return;

	lua_pushnil(L);
	int ind = 0;

	while (lua_next(L, -2) != 0){
/* simplified lua_type to string to help with UI, index is real reference */
		if (!ofs){
			fprintf(out, "type=table:index=%d:", ind++);
			switch (lua_type(L, -2)){
			case LUA_TNUMBER:
				fprintf(out, "keytype=number:tblkey=%.14g:", lua_tonumber(L, -2));
			break;
			case LUA_TSTRING:
				fputs("keytype=string:tblkey=", out);
				put_shmif_luastr(lua_tostring(L, -2), out);
				fputc(':', out);
			break;
			case LUA_TBOOLEAN:
				fprintf(out, "keytype=bool:tblkey=%s:", lua_toboolean(L, -2) ? "true" : "false");
			break;
			case LUA_TFUNCTION:
				fputs("keytype=function:tblkey=func:", out);
			break;
			case LUA_TTABLE:
				fputs("keytype=table:tblkey=table:", out);
			break;
			default:
				fputs("keytype=unknown:tblkey=unknown:", out);
			break;
			}
			fputs("var", out);
			alt_trace_print_type(L, -1, "\n", out);
		}
		else ofs--;
		lua_pop(L, 1);
		if (cap && cap-- == 1){
			break;
		}
	}
	lua_pop(L, 1);
}

void alt_trace_dumpstack_raw(lua_State* L, FILE* out)
{
	int top = lua_gettop(L);
	while (top > 0){
		fprintf(out, "type=stack:index=%d:name=%d:var", top, top);
		alt_trace_print_type(L, top, "\n", out);
		top--;
	}
}

static struct {
	int maskv;
	const char* keyv;
} ep_map[] =
{
	{EP_TRIGGER_CLOCK, "clock"},
	{EP_TRIGGER_INPUT, "input"},
	{EP_TRIGGER_INPUT_RAW, "input_raw"},
	{EP_TRIGGER_INPUT_END, "input_end"},
	{EP_TRIGGER_PREFRAME, "preframe"},
	{EP_TRIGGER_POSTFRAME, "postframe"},
	{EP_TRIGGER_ADOPT, "adopt"},
	{EP_TRIGGER_AUTORES, "autores"},
	{EP_TRIGGER_AUTOFONT, "autofont"},
	{EP_TRIGGER_DISPLAYSTATE, "display_state"},
	{EP_TRIGGER_DISPLAYRESET, "display_reset"},
	{EP_TRIGGER_FRAMESERVER, "frameserver"},
	{EP_TRIGGER_MESH, "mesh"},
	{EP_TRIGGER_CALCTARGET, "calctarget"},
	{EP_TRIGGER_LWA, "lwa"},
	{EP_TRIGGER_IMAGE, "image"},
	{EP_TRIGGER_AUDIO, "audio"},
	{EP_TRIGGER_MAIN, "main"},
	{EP_TRIGGER_SHUTDOWN, "shutdown"},
	{EP_TRIGGER_NBIO_RD, "nbio_read"},
	{EP_TRIGGER_NBIO_WR, "nbio_write"},
	{EP_TRIGGER_NBIO_DATA, "nbio_data"},
	{EP_TRIGGER_HANDOVER, "handover"},
	{EP_TRIGGER_TRACE, "trace"}
};

uint64_t alt_trace_strtoep(const char* ep)
{
	for (size_t i = 0; i < COUNT_OF(ep_map); i++){
		if (strcmp(ep_map[i].keyv, ep) == 0)
			return ep_map[i].maskv;
	}
	return 0;
}

const char* alt_trace_eptostr(uint64_t ep)
{
	for (size_t i = 0; i < COUNT_OF(ep_map); i++){
		if (ep_map[i].maskv == ep)
			return ep_map[i].keyv;
	}
	return "(bad)";
}

void alt_trace_callstack_raw(lua_State* L, lua_Debug* D, int levels, FILE* out)
{
	uint64_t cbk;
	int64_t luavid, vid;
	alt_trace_cbstate(&cbk, &luavid, &vid);
	fprintf(out,
		"type=entrypoint:kind=%s:vid=%"PRId64":luavid=%"PRIu64"\n",
		alt_trace_eptostr(cbk),
		luavid, vid
	);
	int level = 0;
	lua_Debug ar;

	while (lua_getstack(L, level, &ar) && level < levels){
		lua_getinfo(L, "Slnu", &ar);
		fprintf(out, "type=stacktrace:frame=%d:name=%s:"
			"kind=%s:source=%s:current=%d:start=%d:end=%d:upvalues=%d\n",
			level,
			ar.name ? ar.name : "(null)",
			ar.namewhat ? ar.namewhat : "(null)",
			ar.source,
			ar.currentline, ar.linedefined, ar.lastlinedefined, ar.nups);

		const char* name;
		int argi = 1;
		while ( (name = lua_getlocal(L, &ar, argi) ) ){
/* this is subtle, but print_type appends type=vartype... so for that not
 * to clash with the type key we prefix with var */
			fprintf(out, "type=local:index=%d:name=%s:var", argi, name);
			alt_trace_print_type(L, -1, "", out);
			fputc('\n', out);
			lua_pop(L, 1);
			argi++;
		}

/* varargs function(1, 2, ...) have ... resolved as negative locals, these
 * change around in 5.2+ to have args be a separate query */
		argi = -1;
		while ( (name = lua_getlocal(L,  &ar, argi) ) ){
			fprintf(out, "type=local:index=%d:vararg:name=%s:var", argi, name);
			alt_trace_print_type(L, -1, "", out);
			fputc('\n', out);
			lua_pop(L, 1);
			argi--;
		}

/* send the locals as well as it's cheaper than going for a roundtrip */
		level++;
	}
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
		alt_call(L, CB_SOURCE_NONE,
			EP_TRIGGER_TRACE, 0, 1, 0, LINE_TAG":trace");
	arcan_conductor_toggle_watchdog();
	luaL_unref(L, LUA_REGISTRYINDEX, trace_cb);
}

static const char* udata_list[] = {
	"Arcan TUI",
	"nonblockIO",
	"nonblockIOs",
	"calcImage",
	"meshAccess"
};

static const char* match_udata(lua_State* L, ssize_t pos){
	if (0 == lua_getmetatable(L, pos))
		return NULL;

	for (size_t i = 0; i < COUNT_OF(udata_list); i++){
		luaL_getmetatable(L, udata_list[i]);
		if (lua_rawequal(L, -1, -2)){
			lua_pop(L, 2);
			return udata_list[i];
		}
		lua_pop(L, 1);
	}

	lua_pop(L, 1);
	return "(unknown)";
}

void alt_trace_print_type(
	lua_State* L, int i, const char* suffix, FILE* out)
{
	if (lua_type(L, i) == LUA_TNUMBER){
		fprintf(out, "type=number:value=%.14g", lua_tonumber(L, i));
	}
	else if (lua_type(L, i) == LUA_TUSERDATA){
		fprintf(out, "type=userdata:name=%s\n", match_udata(L, i));
	}
	else if (lua_type(L, i) == LUA_TFUNCTION){
		lua_Debug ar;
		lua_pushvalue(L, i);
		lua_getinfo(L, ">Snl", &ar); /* will pop -1 */
		fprintf(out,
			"type=func:name=%s:kind=%s:source=%s:start=%d:end=%d",
			ar.name ? ar.name : "(null)",
			ar.namewhat ? ar.namewhat : "(null)",
			ar.source, ar.linedefined, ar.lastlinedefined);
	}
	else if (lua_type(L, i) == LUA_TSTRING){
		const char* msg = lua_tostring(L, i);
		fputs("type=string:value=", out);
		put_shmif_luastr(msg, out);
	}
	else if (lua_type(L, i) == LUA_TBOOLEAN){
		fputs(lua_toboolean(L, i) ?
			"type=bool:value=true" : "type=bool:value=false", out);
	}
	else if (lua_type(L, i) == LUA_TTABLE){
		size_t n_keys = 0;

#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

		int nelems = lua_rawlen(L, i);

		lua_pushvalue(L, i);
		lua_pushnil(L);

		while (lua_next(L, -2) != 0){
			lua_pop(L, 1);
			n_keys++;
		}
		lua_pop(L, 1);

		fprintf(out, "type=table:length=%d:keys=%zu", nelems, n_keys);
/* open question is if we should just dump the full table recursively? this
 * could get really long, at the same time since we replace print we can't
 * provide an interface for a starting offset to do it over multiple requests,
 * for debugger interface in monitor it is probably best to provide a
 * specialised dump function there and do it flat */
 }
	else if (lua_type(L, i) == LUA_TNIL){
		fputs("type=nil", out);
	}
	fputs(suffix, out);
}

/* this replaces the default print function */
int alt_trace_log(lua_State* L)
{

/* if not tracing then just dump to out, otherwise append prefix and
 * send to trace facility to provide enough marker data to order */
	if (!arcan_trace_enabled){
		int n_args = lua_gettop(L);
		if (n_args){
			for (int i = 1; i < n_args; ++i){
				alt_trace_print_type(L, i, ", ", stdout);
			}
			alt_trace_print_type(L, n_args, "\n", stdout);
		}
		fflush(stdout);
		return 0;
	}

	const char str_prefix[] = "LUA_PRINT: ";

	int n_args = lua_gettop(L);

	int total_len = sizeof(str_prefix) - 1;
	for (int i = 1; i <= n_args; ++i) {
		size_t str_len = 0;
		const char* str = lua_tolstring(L, i, &str_len);
		total_len += str_len + 1;
	}
	total_len += 1;

	char* log_buffer = arcan_alloc_mem(
		total_len,
		ARCAN_MEM_STRINGBUF,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL,
		ARCAN_MEMALIGN_NATURAL
	);
	if (log_buffer == 0) {
		const char oom_msg[] = "Couldn't log trace message: Out of memory\n";
		arcan_trace_log(oom_msg, sizeof(oom_msg));
		return 0;
	}

	int running_len = sizeof(str_prefix) - 1;
	memcpy(&log_buffer[0], str_prefix, running_len);

	for (int i = 1; i <= n_args; ++i) {
		size_t str_len = 0;
		const char* str = lua_tolstring(L, i, &str_len);

		memcpy(&log_buffer[running_len], str, str_len);
		running_len += str_len + 1;
		log_buffer[running_len - 1] = '\t';
	}

	log_buffer[running_len - 1] = '\n';
	log_buffer[running_len] = '\0';

	arcan_trace_log(log_buffer, total_len);

	arcan_mem_free(log_buffer);
	return 0;
}
