#include <stdint.h>
#include <stdlib.h>
#include <inttypes.h>
#include <stdbool.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <unistd.h>
#include <fcntl.h>
#include "nbio_local.h"
#include "dir_lua_support.h"

static struct
{
	union {
		struct {
			size_t line;
			char* file;
		} bpt;
	};

/*
 * int type;
 * watchpoint would go here:
 *
 *  read  - tricky as access could be JITed etc.
 *  write - keep hash or value at point it's set, compare on insn/line
 *  expr  - run lua expression, trigger when TBOOLEAN == true return
 */

	int type;
} m_breakpoints[BREAK_LIMIT];
size_t m_n_breakpoints = 0;
static bool in_breakpoint_set = false;
static int hook_mask = 0;
static int entrypoint = EP_TRIGGER_NONE;

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

static struct {
	int maskv;
	const char* keyv;
} ep_map[] =
{
	{EP_TRIGGER_CLOCK, "clock"},
	{EP_TRIGGER_MESSAGE, "message"},
	{EP_TRIGGER_NBIO_RD, "nbio_read"},
	{EP_TRIGGER_NBIO_WR, "nbio_write"},
	{EP_TRIGGER_NBIO_DATA, "nbio_data"},
	{EP_TRIGGER_TRACE, "trace"}
};

void dirlua_hookmask(uint64_t mask, bool bkpt)
{
	in_breakpoint_set = bkpt;
	hook_mask = mask;
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

void dirlua_pcall(lua_State* L, int nargs, int nret, int ep)
{

}

void dirlua_callstack_raw(lua_State* L, lua_Debug* D, int levels, FILE* out)
{
	uint64_t cbk;
	int64_t luavid, vid;
	fprintf(out, "type=entrypoint:kind=%s\n", dirlua_eptostr(entrypoint));
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

static void cmd_source(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_dumpstate(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_reload(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_continue(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_backtrace(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_locals(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_stepnext(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_stepend(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_stepline(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_stepcall(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_stepinstruction(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_dumptable(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_breakpoint(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
}

static void cmd_entrypoint(char* arg, lua_State* L, lua_Debug* D, FILE* out)
{
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

static void cmd_eval(char* argv, lua_State* L, lua_Debug* D, FILE* m_out)
{
	int status = luaL_loadbuffer(L, argv, strlen(argv), "eval");
	if (status){
		const char* msg = lua_tostring(L, -1);
		fprintf(m_out,
			"#BADRESULT\n%s\n#ENDBADRESULT\n", msg ? msg : "(error object is not a string)");
		fflush(m_out);
		lua_pop(L, 1);
		return;
	}

	int base = lua_gettop(L);
	lua_pushcfunction(L, traceback);
	lua_insert(L, base);

	fprintf(m_out, "#BEGINRESULT\n");

	status = lua_pcall(L, 0, LUA_MULTRET, base);
	lua_remove(L, base);

	if (status != 0){
		lua_gc(L, LUA_GCCOLLECT, 0);
		const char* msg = lua_tostring(L, -1);
		if (msg){
			fprintf(m_out, "%s%s\n", msg[0] == '#' ? "\\" : "", msg);
		}
		else
			fprintf(m_out, "(error object is not a string)\n");
	}
/* possible do a real table dump here as with eval we'd want the full one most
 * of the time */
	else if (lua_type(L, -1) != LUA_TNIL){
		dirlua_print_type(L, -1, "", m_out);
		fputc('\n', m_out);
	}

	fprintf(m_out, "#ENDRESULT\n");
	fflush(m_out);
}

static struct {
	const char* word;
	void (*ptr)(char* arg, lua_State*, lua_Debug*, FILE*);
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
bool dirlua_monitor_command(char* cmd, lua_State* L, lua_Debug* D, FILE* out)
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
			cmds[j].ptr(arg, L, D, out);
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
