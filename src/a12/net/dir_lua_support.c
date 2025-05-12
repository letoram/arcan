#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <poll.h>
#include <assert.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>

#include <lualib.h>
#include <lauxlib.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <ctype.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"

#include "dir_lua_support.h"
#include "../../engine/alt/support.h"

/* pull in nbio as it is used in the tui-lua bindings */
#include "../../shmif/tui/lua/nbio.h"

#include "directory.h"
#include "platform_types.h"
#include "os_platform.h"
#include "dir_lua_support.h"

static _Thread_local struct dirlua_monitor_state* monitor;

/* used to prefill applname_entrypoint and track where we entered
 * last for entrypoint- breaks and for trace output */
static _Thread_local struct {
	int last_ep;
	char* prefix_table[ENTRYPOINT_COUNT];
} lua;

static struct {
	int maskv;
	const char* keyv;
} ep_map[] =
{
	{EP_TRIGGER_CLOCK, "clock_pulse"},
	{EP_TRIGGER_MESSAGE, "message"},
	{EP_TRIGGER_TRACE, "trace"},
	{EP_TRIGGER_RESET, "reset"},
	{EP_TRIGGER_JOIN, "join"},
	{EP_TRIGGER_LEAVE, "leave"},
	{EP_TRIGGER_INDEX, "index"},
	{EP_TRIGGER_LOAD, "load"},
	{EP_TRIGGER_STORE, "store"}
};

static const char* ep_lut[ENTRYPOINT_COUNT] =
{
	NULL,
	"",
	"_clock_pulse",
	"_message",
	NULL, /* NBIO_RD */
	NULL, /* NBIO_WR */
	NULL, /* NBIO_DATA */
	NULL, /* TRACE */
	"_reset",
	"_join",
	"_leave",
	"_index",
	"_load",
	"_store"
};

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

void dirlua_dumptable_raw(lua_State* L, int ofs, int cap, FILE* out)
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
			dirlua_print_type(L, -1, "\n", out);
		}
		else ofs--;
		lua_pop(L, 1);
		if (cap && cap-- == 1){
			break;
		}
	}
	lua_pop(L, 1);
}

static bool check_breakpoints(lua_State* L)
{
	lua_Debug ar;
	if (!monitor->n_breakpoints || !lua_getstack(L, 0, &ar)){
		return false;
	}

	lua_getinfo(L, "Snl", &ar);

/* check source and current line against set */
	for (size_t i = 0, c = monitor->n_breakpoints; i < BREAK_LIMIT && c; i++){
		if (monitor->breakpoints[i].bpt.file){
			c--;
			const char* base = ar.source;
			if (base[0] == '@')
				base++;

			size_t line = monitor->breakpoints[i].bpt.line;
			char* source = monitor->breakpoints[i].bpt.file;

			if (ar.currentline != line)
				continue;

			if (strcmp(base, source) == 0){
				fprintf(monitor->out, "#BREAK %s:%zu\n", source, line);
				return true;
			}
		}
	}

	return false;
}

static char* strip_arg_lf(char* arg)
{
/* strip \n */
	size_t len = strlen(arg);
	if (len && arg[len-1] == '\n'){
		arg[len-1] = '\0';
		return &arg[len-1];
	}
	return &arg[len];
}

void dirlua_monitor_panic(lua_State* L, lua_Debug* D)
{
	monitor->dumppause = true;
	monitor->error = true;
	monitor->lock = true;
	dirlua_monitor_watchdog(L, D);
	monitor->stepreq = false;
}

void dirlua_hookmask(uint64_t mask, bool bkpt)
{
	monitor->in_breakpoint_set = bkpt;
	monitor->hook_mask = mask;
}

const char* dirlua_eptostr(uint64_t ep)
{
	for (size_t i = 0; i < COUNT_OF(ep_map); i++){
		if (ep_map[i].maskv == ep)
			return ep_map[i].keyv;
	}
	return "(bad)";
}

uint64_t dirlua_strtoep(const char* ep)
{
	for (size_t i = 0; i < COUNT_OF(ep_map); i++){
		if (strcmp(ep_map[i].keyv, ep) == 0)
			return ep_map[i].maskv;
	}
	return 0;
}

static const char* udata_list[] = {
	"nonblockIO",
	"nonblockIOs"
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


void dirlua_print_type(
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

void dirlua_pcall_prefix(struct lua_State* L, const char* name)
{
/* reset the table first */
	for (size_t i = 0; i < ENTRYPOINT_COUNT; i++){
		if (lua.prefix_table[i]){
			free(lua.prefix_table[i]);
			lua.prefix_table[i] = NULL;
		}
	}

	if (!name || !strlen(name))
		return;

	for (size_t i = 0; i < ENTRYPOINT_COUNT; i++){
		if (!ep_lut[i])
			continue;

/* if asprintf fails just empty the slot and it won't get called */
		if (-1 == asprintf(&lua.prefix_table[i], "%s%s", name, ep_lut[i])){
			lua.prefix_table[i] = NULL;
		}
	}
}

bool dirlua_setup_entrypoint(struct lua_State* L, int ep)
{
	if (ep <= 0 || ep > EP_TRIGGER_LIMIT || !lua.prefix_table[ep])
		return false;

	lua_getglobal(L, lua.prefix_table[ep]);
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return false;
	}

	if (monitor && (monitor->hook_mask & ep)){
		lua_sethook(L, dirlua_monitor_watchdog, LUA_MASKLINE, 1);
		monitor->dumppause = true;
	}

	lua.last_ep = ep;
	return true;
}

void dirlua_pcall(
	lua_State* L, int nargs, int nret, int (*panic)(lua_State*))
{
/*
 * This is rather wasteful, panic should always be at the top of the stack
 * so we don't do three stack manipulations per entrypoint
 */
	int errind = lua_gettop(L) - nargs;
	lua_pushcfunction(L, panic);
	lua_insert(L, errind);
	lua_pcall(L, nargs, nret, errind);
	lua_remove(L, errind);
	lua.last_ep = 0;
}

void dirlua_callstack_raw(lua_State* L, lua_Debug* D, int levels, FILE* out)
{
	uint64_t cbk;
	int64_t luavid, vid;
	fprintf(out, "type=entrypoint:kind=%s\n", dirlua_eptostr(lua.last_ep));
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
			dirlua_print_type(L, -1, "", out);
			fputc('\n', out);
			lua_pop(L, 1);
			argi++;
		}

/* varargs function(1, 2, ...) have ... resolved as negative locals, these
 * change around in 5.2+ to have args be a separate query */
		argi = -1;
		while ( (name = lua_getlocal(L,  &ar, argi) ) ){
			fprintf(out, "type=local:index=%d:vararg:name=%s:var", argi, name);
			dirlua_print_type(L, -1, "", out);
			fputc('\n', out);
			lua_pop(L, 1);
			argi--;
		}

/* send the locals as well as it's cheaper than going for a roundtrip */
		level++;
	}
}

static void cmd_source(char* arg, lua_State* L, lua_Debug* D)
{
/* debug protocol might come with explicit file reference, though we
 * treat all of them as such so just strip it away */
	if (arg[0] == '@'){
		arg = &arg[1];
	}

	strip_arg_lf(arg);

/* SECURITY NOTE:
 * --------------
 * Without namespacing or pledge this is an open- primitive, with dev
 * permissions less than admin ones this would allow source access to
 * grab files at will.
 *
 * This is permitted for now as _lua_appl.c is intended to only run in
 * such a limited environment.
 */
	data_source indata = arcan_open_resource(arg);
	map_region reg = arcan_map_resource(&indata, false);
	if (!reg.ptr){
		fprintf(monitor->out, "#ERROR couldn't map Lua source ref: %s\n", arg);
	}
	else {
		fprintf(monitor->out, "#BEGINSOURCE\n");
			fprintf(monitor->out, "%s\n%s\n", arg, reg.ptr);
		fprintf(monitor->out, "#ENDSOURCE\n");
	}

	arcan_release_map(reg);
	arcan_release_resource(&indata);
}

static void cmd_dumpstate(char* arg, lua_State* L, lua_Debug* D)
{
/* this should use the same 'grab all keys' approach as elsewhere and reroute
 * the result descriptor into monitor->out */
	fprintf(monitor->out, "#BEGINKV\n#LASTSOURCE\n#ENDLASTSOURCE\n#ENDKV\n");
}

static void cmd_reload(char* arg, lua_State* L, lua_Debug* D)
{
/* the actual implementation of this is actually just to ask the parent to
 * resend the descriptor and we treat it as an updated set of scripts being
 * pushed */
	struct arcan_event beg = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = "reload"
	};

	arcan_shmif_enqueue(monitor->C, &beg);
}

static void cmd_continue(char* arg, lua_State* L, lua_Debug* D)
{
	monitor->lock = false;
}

static void cmd_backtrace(char* arg, lua_State* L, lua_Debug* D)
{
	size_t n_levels = 10;
	if (!L)
		return;

	fprintf(monitor->out, "#BEGINBACKTRACE\n");
		dirlua_callstack_raw(L, D, n_levels, monitor->out);
	fprintf(monitor->out, "#ENDBACKTRACE\n");

	fprintf(monitor->out, "#BEGINSTACK\n");
		dirlua_dumpstack_raw(L, monitor->out);
	fprintf(monitor->out, "#ENDSTACK\n");
}

static void cmd_locals(char* arg, lua_State* L, lua_Debug* D)
{
/* this is missing for both engine/monitor and remote one */
}

/*
 * triggered on SIGUSR1, pcall error condition or during lua_sethook
 */
void dirlua_monitor_watchdog(lua_State* L, lua_Debug* D)
{
	if (!monitor)
		return;

/* do we have any trigger condition? */
	if (
		!check_breakpoints(L) &&
		monitor->n_breakpoints &&
		!monitor->stepreq &&
		!monitor->error &&
		!monitor->transaction){
		return;
	}

	if (monitor->dumppause){
		fprintf(monitor->out, "#WAITING\n");
		monitor->dumppause = false;
		cmd_backtrace("", L, D);
	}

	monitor->lock = true;
}

static void cmd_stepend(char* arg, lua_State* L, lua_Debug* D)
{
	if (!L || !D){
		fprintf(monitor->out, "#ERROR no Lua state\n");
		return;
	}

	lua_sethook(L, dirlua_monitor_watchdog, LUA_MASKRET, 1);
	monitor->lock = false;
	monitor->stepreq = true;
	monitor->dumppause = true;
}

static void cmd_stepline(char* arg, lua_State* L, lua_Debug* D)
{
	if (!L || !D){
		fprintf(monitor->out, "#ERROR no Lua state\n");
		return;
	}

	lua_sethook(L, dirlua_monitor_watchdog, LUA_MASKLINE, 1);
	monitor->lock = false;
	monitor->stepreq = true;
	monitor->dumppause = true;
}

static void cmd_stepcall(char* arg, lua_State* L, lua_Debug* D)
{
	lua_sethook(L, dirlua_monitor_watchdog, LUA_MASKRET, 1);
	monitor->lock = false;
	monitor->stepreq = true;
	monitor->dumppause = true;
}

static void cmd_stepinstruction(char* arg, lua_State* L, lua_Debug* D)
{
	if (!L){
		fprintf(monitor->out, "#ERROR No Lua state\n");
		return;
	}

	long count = 1;
	if (arg && strlen(arg)){
		count = strtol(arg, NULL, 10);
	}

/* set lua_tracefunction to line mode */
	lua_sethook(L, dirlua_monitor_watchdog, LUA_MASKCALL, count);
	monitor->lock = false;
	monitor->stepreq = true;
	monitor->dumppause = true;
}

/* part of dumptable, check for LUA_TABLE at top is done there, this just
 * extracts frame number and local number and loads whatever is there */
static void local_to_table(char** tokctx, lua_State* L, FILE* m_out)
{
	char* tok;
	bool gotframe = false;
	long lref;
	lua_Debug ar;

	while ( (tok = strtok_r(NULL, " ", tokctx) ) ){
		char* err = NULL;
		long val = strtoul(tok, &err, 10);
		if (err && *err){
			fprintf(m_out,
				"#ERROR gettable: missing %s reference\n", gotframe ? "local" : "frame");
			return;
		}

		if (!gotframe){
			if (!lua_getstack(L, val, &ar)){
				fprintf(m_out,
					"#ERROR gettable: invalid frame %ld\n", val);
				return;
			}
			gotframe = true;
		}
		else {
			lua_getlocal(L, &ar, val);
			return;
		}
	}
}

/* part of dumptable, check for LUA_TABLE at top is done there, this just
 * reads a value and then leaves the stack reference copied to the top */
static void stack_to_table(char** tokctx, lua_State* L, FILE* out)
{
	char* tok;

	while ( (tok = strtok_r(NULL, " ", tokctx) ) ){
		char* err = NULL;
		unsigned long index = strtoul(tok, &err, 10);
		if (err && *err){
			fprintf(out, "#ERROR gettable: missing stack reference\n");
		}
		else if (lua_type(L, index) == LUA_TTABLE){
			lua_pushvalue(L, index);
		}
		return;
	}
}

static void cmd_dumptable(char* argv, lua_State* L, lua_Debug* D)
{
	strip_arg_lf(argv);

	int argi = 0;
	char* tok, (* tokctx);
	int top = lua_gettop(L);

	while ( (tok = strtok_r(argv, " ", &tokctx) ) ){
		argv = NULL;

/* navigate through the table indices */
		if (argi){
			char* err = NULL;
			unsigned long skip_n = strtoul(tok, &err, 10);
			if (err && *err){
				fprintf(monitor->out, "#ERROR gettable: couldn't parse index\n");
				break;
			}

			if (lua_type(L, -1) != LUA_TTABLE){
				fprintf(monitor->out, "#ERROR gettable: resolved index is not a table\n");
				break;
			}

			lua_pushnil(L);
			while (lua_next(L, -2) != 0 && skip_n){
				lua_pop(L, 1);
				skip_n--;
			}

/* remove iteration key */
			lua_remove(L, -2);
		}

/* domain selector: */
		if (argi == 0){
			switch (tok[0]){
			case 'g': lua_pushvalue(L, LUA_GLOBALSINDEX); break;
			case 's': stack_to_table(&tokctx, L, monitor->out); break;
			case 'l': local_to_table(&tokctx, L, monitor->out); break;
			default:
				fprintf(monitor->out, "#ERROR gettable: bad domain selector\n");
				return;

			break;
			}
			argi++;
		}
	}

	if (lua_type(L, -1) != LUA_TTABLE){
		fprintf(monitor->out, "#ERROR gettable: resolved index is not a table\n");
	}
/* just dump the entire table, if needed we can support argument for setting
 * starting offset and cap later */
	else {
		fprintf(monitor->out, "#BEGINTABLE\n");
		dirlua_dumptable_raw(L, 0, 0, monitor->out);
		fprintf(monitor->out, "#ENDTABLE\n");
	}

	fflush(monitor->out);
	lua_settop(L, top);
}

static void cmd_breakpoint(char* argv, lua_State* L, lua_Debug* D)
{
	size_t len = strlen(argv);

/* dump current set */
	if (!len || len == 1){
		fprintf(monitor->out, "#BEGINBREAK\n");
		for (size_t i = 0, c = monitor->n_breakpoints; i < BREAK_LIMIT && c; i++){
			if (monitor->breakpoints[i].bpt.file){
				c--;
				fprintf(monitor->out, "file=%s:line=%zu\n",
					monitor->breakpoints[i].bpt.file, monitor->breakpoints[i].bpt.line);
			}
		}
		fprintf(monitor->out, "#ENDBREAK\n");
		return;
	}

/* extract file:line */
	char* endptr = strip_arg_lf(argv);
	unsigned long line = 0;

	while (endptr != argv && *endptr != ':')
		endptr--;

	if (*endptr == ':'){
		*endptr++ = '\0';
		if (!strlen(endptr)){
			fprintf(monitor->out, "#ERROR breakpoint: expected file:line\n");
			return;
		}

		char* err = NULL;
		line = strtoul(endptr, &err, 10);
		if (err && *err){
			fprintf(monitor->out,
				"#ERROR breakpoint: malformed line specifier\n");
			return;
		}
	}

/* if match, remove */
	for (size_t i = 0, c = monitor->n_breakpoints; i < BREAK_LIMIT && c; i++){
		if (!monitor->breakpoints[i].bpt.file)
			continue;
		c--;

		if (monitor->breakpoints[i].bpt.line == line &&
			strcmp(monitor->breakpoints[i].bpt.file, argv) == 0){
			free(monitor->breakpoints[i].bpt.file);
			monitor->breakpoints[i].bpt.file = NULL;
			monitor->n_breakpoints--;
			return;
		}
	}

/* There is the option of better controls here, with lua_getinfo for >L when we
 * have a function on top of the stack, it'll return a list of valid lines to
 * put breakpoints on. */

/* add, unless we are at cap */
	if (monitor->n_breakpoints == BREAK_LIMIT){
		fprintf(monitor->out, "#ERROR breakpoint: limit filled\n");
		return;
	}

	for (size_t i = 0; i < BREAK_LIMIT; i++){
		if (!monitor->breakpoints[i].bpt.file){
			monitor->breakpoints[i].bpt.file = strdup(argv);
			monitor->breakpoints[i].bpt.line = line;

			if (monitor->breakpoints[i].bpt.file)
				monitor->n_breakpoints++;
			else
				fprintf(monitor->out, "#ERROR breakpoint: out of memory\n");
			break;
		}
	}

/* send the set */
	cmd_breakpoint("", NULL, NULL);
}

static void cmd_entrypoint(char* arg, lua_State* L, lua_Debug* D)
{
	uint64_t mask_kind = 0;
	char* tok;
	char* tokctx;

	strip_arg_lf(arg);

	while ( (tok = strtok_r(arg, " ", &tokctx) ) ){
		arg = NULL;
		mask_kind |= dirlua_strtoep(tok);
	}

	monitor->hook_mask = mask_kind;
}

/* Same as used in lua.c and alt/trace.c - there is a better version in LuaJIT
 * and in Lua5.3+ but relies on function and access that we lack. In difference
 * to alt/trace.c though, we don't force-load from lualibs so there might be an
 * option of someone maliciously replacing it. */
static int traceback (lua_State *L) {
  if (!lua_isstring(L, 1))  /* 'message' not a string? */
    return 1;  /* keep it intact */
  lua_getfield(L, LUA_GLOBALSINDEX, "debug");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    return 1;
  }
  lua_getfield(L, -1, "traceback");
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 2);
    return 1;
  }
  lua_pushvalue(L, 1);  /* pass error message */
  lua_pushinteger(L, 2);  /* skip this function and traceback */
  lua_call(L, 2, 1);  /* call debug.traceback */
  return 1;
}

static void cmd_eval(char* argv, lua_State* L, lua_Debug* D)
{
	int status = luaL_loadbuffer(L, argv, strlen(argv), "eval");
	if (status){
		const char* msg = lua_tostring(L, -1);
		fprintf(monitor->out,
			"#BADRESULT\n%s\n#ENDBADRESULT\n", msg ? msg : "(error object is not a string)");
		fflush(monitor->out);
		lua_pop(L, 1);
		return;
	}

	int base = lua_gettop(L);
	lua_pushcfunction(L, traceback);
	lua_insert(L, base);

	fprintf(monitor->out, "#BEGINRESULT\n");

	status = lua_pcall(L, 0, LUA_MULTRET, base);
	lua_remove(L, base);

	if (status != 0){
		lua_gc(L, LUA_GCCOLLECT, 0);
		const char* msg = lua_tostring(L, -1);
		if (msg){
			fprintf(monitor->out, "%s%s\n", msg[0] == '#' ? "\\" : "", msg);
		}
		else
			fprintf(monitor->out, "(error object is not a string)\n");
	}
/* possible do a real table dump here as with eval we'd want the full one most
 * of the time */
	else if (lua_type(L, -1) != LUA_TNIL){
		dirlua_print_type(L, -1, "", monitor->out);
		fputc('\n', monitor->out);
	}

	fprintf(monitor->out, "#ENDRESULT\n");
	fflush(monitor->out);
}

static struct {
	const char* word;
	void (*ptr)(char* arg, lua_State*, lua_Debug*);
} cmds[] =
{
	{"continue", cmd_continue},
	{"dumpstate", cmd_dumpstate},
	{"reload", cmd_reload},
	{"backtrace", cmd_backtrace},
	{"eval", cmd_eval},
	{"locals", cmd_locals},
	{"stepnext", cmd_stepline},
	{"stepend", cmd_stepend},
	{"stepcall", cmd_stepcall},
	{"stepinstruction", cmd_stepinstruction},
	{"table", cmd_dumptable},
	{"source", cmd_source},
	{"breakpoint", cmd_breakpoint},
	{"entrypoint", cmd_entrypoint},
};

/*
 * since we just re-use the format in engine/monitor, just break cmd\sargument
 */
bool dirlua_monitor_command(char* cmd, lua_State* L, lua_Debug* D)
{
	size_t i = 0;
	while (cmd[i] && cmd[i] != '\n' && cmd[i] != ' ') i++;

	char* arg = &cmd[i];
	if (cmd[i]){
		if (cmd[i] != '\n')
			arg++;
		cmd[i] = '\0';
	}

	for (size_t j = 0; j < COUNT_OF(cmds); j++){
		if (strcasecmp(cmd, cmds[j].word) == 0){
			cmds[j].ptr(arg, L, D);
			return true;
		}
	}

	return false;
}

void dirlua_dumpstack_raw(lua_State* L, FILE* out)
{
	int top = lua_gettop(L);
	while (top > 0){
		fprintf(out, "type=stack:index=%d:name=%d:var", top, top);
		dirlua_print_type(L, top, "\n", out);
		top--;
	}
}

struct dirlua_monitor_state* dirlua_monitor_getstate()
{
	return monitor;
}

size_t dirlua_monitor_flush(char** out_buf)
{
	if (!monitor)
		return 0;

	fflush(monitor->out);
	*out_buf = monitor->out_buf;
	return monitor->out_sz;
}

void dirlua_monitor_releasestate(lua_State* L)
{
	if (!monitor)
		return;

	fclose(monitor->out);
	free(monitor->out_buf);

	lua_sethook(L, NULL, LUA_MASKLINE, 1);
	lua_sethook(L, NULL, LUA_MASKRET, 1);
	lua_sethook(L, NULL, LUA_MASKCALL, 1);

	free(monitor);
	monitor = NULL;
}

void dirlua_monitor_allocstate(struct arcan_shmif_cont* C)
{
	monitor = malloc(sizeof(struct dirlua_monitor_state));
	memset(monitor, '\0', sizeof(struct dirlua_monitor_state));
	monitor->C = C;
	monitor->lock = true;
	monitor->out = open_memstream(&monitor->out_buf, &monitor->out_sz);
}

/*
 * Same vendored lua_loadfile as used in alt/support.c but modified to
 * reference through dirfd.
 */
typedef struct LoadF {
  int extraline;
  FILE *f;
  char buff[LUAL_BUFFERSIZE];
} LoadF;

static const char *getF (lua_State *L, void *ud, size_t *size) {
  LoadF *lf = (LoadF *)ud;
  (void)L;
  if (lf->extraline) {
    lf->extraline = 0;
    *size = 1;
    return "\n";
  }
  if (feof(lf->f)) return NULL;
  *size = fread(lf->buff, 1, sizeof(lf->buff), lf->f);
  return (*size > 0) ? lf->buff : NULL;
}

int dirlua_loadfile(lua_State *L, int dfd, const char *filename, bool dieonfail)
{
  LoadF lf;
  int status, readstatus;
  int c;
  int fnameindex = lua_gettop(L) + 1;  /* index of filename on the stack */
  lf.extraline = 0;

	int fd = openat(dfd, filename, O_RDONLY);
	if (-1 == fd){
		if (dieonfail)
			luaL_error(L, "system_load(%s) can't be opened", filename);
		lua_pushboolean(L, false);
		return 1;
	}

	lua_pushfstring(L, "@%s", filename);
	lf.f = fdopen(fd, "r");

	if (lf.f == NULL){
		if (dieonfail)
			luaL_error(L, "system_load:fdopen(%d) failed", fd);
		lua_pushboolean(L, false);
		return 1;
	}

  c = getc(lf.f);
  if (c == '#') {  /* Unix exec. file? */
    lf.extraline = 1;
    while ((c = getc(lf.f)) != EOF && c != '\n') ;  /* skip first line */
    if (c == '\n') c = getc(lf.f);
  }

	if (c == LUA_SIGNATURE[0]){
		fclose(lf.f);
		if (dieonfail)
			luaL_error(L, "system_load(%s) - bytecode forbidden", filename);
		lua_pushboolean(L, false);
		return 1;
	}

  ungetc(c, lf.f);
  status = lua_load(L, getF, &lf, lua_tostring(L, -1));
	if (status != LUA_OK){
	  fclose(lf.f);
 		if (dieonfail)
			luaL_error(L, "system_load(%s):%s\n", lua_tostring(L, -1));
    lua_settop(L, fnameindex);  /* ignore results from `lua_load' */
		lua_pushboolean(L, false);
		return false;
	}

  readstatus = ferror(lf.f);
  fclose(lf.f);  /* close file (even in case of errors) */
  if (readstatus) {
    lua_settop(L, fnameindex);  /* ignore results from `lua_load' */
		if (dieonfail)
			luaL_error(L, "system_load(%s):lua_load failed", filename);
		return 1;
  }
  lua_remove(L, fnameindex);
  return 1;
}
