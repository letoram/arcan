/*
 * Copyright 2003-2017, Björn Ståhl
 * License: GPLv2+, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * Notes regarding LUA use;
 * - There are a few cases that has turned out problematic enough to
 *   warrant some kind of tracking to think about how things should
 *   be developed for the future. Due to the desire (need even) to
 *   support both LUA-jit and the reference lua implementation, some
 *   of the usual annoyances: (global scope being the default,
 *   double pollution, 1 indexing, no ; statement delimiter, no ternary
 *   operator, no aggregate operators, if (true) then return; end type
 *   quickhacks.
 *
 * - Type coersion; the whole "1" can turn into a number makes for a lot
 *   of problems with WORLDID and BADID being common "number-in-string"
 *   values with possibly hard to locate results.
 *
 *   Worse still, true / false vs. nil use is terribly inconsistent,
 *   and some functions where the desire had been to force a boolean type
 *   integer options were temporarily used and now we have scripts in the
 *   wild relying on the behavior.
 *
 * - Double, strings and decimal points; some build-time dependencies pull
 *   in other dependencies where some have the audacity to change radix
 *   point behavior at random points during execution. Varying with window
 *   manager and display server conditions we run into situations where
 *   tonumber() tostring() class functions (and everything that maps to
 *   printf family) will at one time give 12345.6789 and shortly thereafter,
 *   12345,6789
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <stddef.h>
#include <signal.h>
#include <errno.h>
#include <ctype.h>
#include <setjmp.h>
#include <dlfcn.h>
#include <pthread.h>

#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>

#include <assert.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <poll.h>

#ifdef LUA51_JIT
#include <luajit.h>
#else

#endif

#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_shmif_sub.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_renderfun.h"
#include "arcan_3dbase.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_db.h"
#include "arcan_frameserver.h"
#include "arcan_led.h"
#include "arcan_vr.h"
#include "arcan_conductor.h"

#define arcan_luactx lua_State
#include "arcan_lua.h"

/*
 * tradeoff (extra branch + loss in precision vs. assymetry and UB)
 */
#define abs( x ) ( abs( (x) == INT_MIN ? ((x)+1) : x ) )

/*
 * namespaces permitted to be searched for regular resource lookups
 */
#ifndef DEFAULT_USERMASK
#define DEFAULT_USERMASK \
	(RESOURCE_APPL | RESOURCE_APPL_SHARED | RESOURCE_APPL_TEMP)
#endif

#ifndef CAREFUL_USERMASK
#define CAREFUL_USERMASK DEFAULT_USERMASK
#endif

#ifndef MODULE_USERMASK
#define MODULE_USERMASK \
	(RESOURCE_SYS_LIBS)
#endif

/*
 * defined in engine/arcan_main.c, rather than terminating directly
 * we'll longjmp to this and hopefully the engine can switch scripts
 * or take similar user-defined action.
 */
extern jmp_buf arcanmain_recover_state;

/*
 * some operations, typically resize, move and rotate suffered a lot from
 * lua floats propagating, meaning that we'd get subpixel positioning
 * and blurring text etc. as a consequence. For these functions, we now
 * force the type to whatever acoord is specified as (here, signed).
 */
typedef int acoord;

/*
 * arcan_fatal calls in this context are invalid Lua script invocations,
 * these should only forward to arcan_fatal if there's no recovery script
 * set.
 */
#define arcan_fatal(...) do { lua_rectrigger( __VA_ARGS__); } while(0)

/*
 * Each function that crosses the LUA->C barrier has a LUA_TRACE
 * macro reference first to allow quick build-time interception.
 */
#ifdef LUA_TRACE_STDERR
#define LUA_TRACE(fsym) fprintf(stderr, "(%lld:%s)->%s\n", \
	arcan_timemillis(), luactx.lastsrc, fsym);

/*
 * This trace function scans the stack and writes the information about
 * calls to a CSV file (arcan.trace): function;timestamp;type;type
 * This is useful for benchmarking / profiling / test coverage and
 * hardening.
 */
#elif defined(LUA_TRACE_COVERAGE)
#define LUA_TRACE(fsym) trace_coverage(fsym, ctx);

#else
#define LUA_TRACE(fsym)
#endif

/*
 * ETRACE is used in stead of a normal return and is used to both track
 * non-fatal non-warning script invocation errors and to check for unbalanced
 * stacks. Example:
 * static int lasttop = 0;
 * define LUA_TRACE(fsym) top lasttop = lua_gettop(ctx);
 * define LUA_ETRACE(fsym, reason, argc){fprintf(stdout, "%s, %d\n",
		fsym, (int)(lasttop - lua_gettop(ctx) + argc)); return argc;}
 */
#define LUA_ETRACE(fsym,reason, X){ return X; }

#define LUA_DEPRECATE(fsym) \
	arcan_warning("%s, DEPRECATED, discontinue "\
	"the use of this function immediately as it is slated for removal.\n", fsym);

#include "arcan_img.h"
#include "arcan_ttf.h"

/* these take some explaining:
 * to enforce that actual constants are used in LUA scripts and not magic
 * numbers the corresponding binding functions check that the match these
 * global constants (not defines as we want them maintained in debug data
 * as well), but their actual values are set by defines so that they can be
 * swizzled around by the build-system */
#ifndef CONST_ROTATE_RELATIVE
#define CONST_ROTATE_RELATIVE 10
#endif

#ifndef CONST_ROTATE_ABSOLUTE
#define CONST_ROTATE_ABSOLUTE 5
#endif

#ifndef CONST_MAX_SURFACEW
#define CONST_MAX_SURFACEW 8192
#endif

#ifndef CONST_MAX_SURFACEH
#define CONST_MAX_SURFACEH 4096
#endif

#ifndef CONST_RENDERTARGET_DETACH
#define CONST_RENDERTARGET_DETACH 20
#endif

#ifndef CONST_RENDERTARGET_NODETACH
#define CONST_RENDERTARGET_NODETACH 21
#endif

#ifndef CONST_RENDERTARGET_SCALE
#define CONST_RENDERTARGET_SCALE 30
#endif

#ifndef CONST_RENDERTARGET_NOSCALE
#define CONST_RENDERTARGET_NOSCALE 31
#endif

#ifndef CONST_FRAMESERVER_INPUT
#define CONST_FRAMESERVER_INPUT 41
#endif

#ifndef CONST_FRAMESERVER_OUTPUT
#define CONST_FRAMESERVER_OUTPUT 42
#endif

#ifndef CONST_DEVICE_INDIRECT
#define CONST_DEVICE_INDIRECT 1
#endif

#ifndef CONST_DEVICE_DIRECT
#define CONST_DEVICE_DIRECT 2
#endif

#ifndef CONST_DEVICE_LOST
#define CONST_DEVICE_LOST 3
#endif

#ifndef LAUNCH_EXTERNAL
#define LAUNCH_EXTERNAL 0
#endif

#ifndef LAUNCH_INTERNAL
#define LAUNCH_INTERNAL 1
#endif

/*
 * disable support for all builtin frameservers
 * which removes most (launch_target and target_alloc remain)
 * ways of spawning external processes.
 */
static int fsrv_ok =
#ifdef DISABLE_FRAMESERVERS
0
#else
1
#endif
;

#define FATAL_MSG_FRAMESERV "specified destination is not a frameserver.\n"

/* we map the constants here so that poor or confused
 * debuggers also have a chance to give us symbol resolution */
static const int MOUSE_GRAB_ON  = 20;
static const int MOUSE_GRAB_OFF = 21;

static const int MAX_SURFACEH = CONST_MAX_SURFACEH;
static const int MAX_SURFACEW = CONST_MAX_SURFACEW;

static const int FRAMESET_NODETACH = 11;
static const int FRAMESET_DETACH   = 10;

static const int RENDERTARGET_DETACH   = CONST_RENDERTARGET_DETACH;
static const int RENDERTARGET_NODETACH = CONST_RENDERTARGET_NODETACH;
static const int RENDERTARGET_SCALE    = CONST_RENDERTARGET_SCALE;
static const int RENDERTARGET_NOSCALE  = CONST_RENDERTARGET_NOSCALE;
static const int RENDERFMT_COLOR = RENDERTARGET_COLOR;
static const int RENDERFMT_DEPTH = RENDERTARGET_DEPTH;
static const int RENDERFMT_FULL  = RENDERTARGET_COLOR_DEPTH_STENCIL;
static const int RENDERFMT_MSAA = RENDERTARGET_MSAA;
static const int RENDERFMT_RETAIN_ALPHA = RENDERTARGET_RETAIN_ALPHA;
static const int DEVICE_INDIRECT = CONST_DEVICE_INDIRECT;
static const int DEVICE_DIRECT = CONST_DEVICE_DIRECT;
static const int DEVICE_LOST = CONST_DEVICE_LOST;

#define DBHANDLE arcan_db_get_shared(NULL)

enum arcan_cb_source {
	CB_SOURCE_NONE        = 0,
	CB_SOURCE_FRAMESERVER = 1,
	CB_SOURCE_IMAGE       = 2,
	CB_SOURCE_TRANSFORM   = 3,
	CB_SOURCE_PREROLL     = 4
};

struct nonblock_io {
	char buf[4096];
	off_t ofs;
	int fd;
	char* pending;
};

static struct {
	struct nonblock_io rawres;

	const char* lastsrc;

	bool in_panic;
	unsigned char debug;
	unsigned lua_vidbase;
	unsigned char grab;

	enum arcan_cb_source cb_source_kind;
	long long cb_source_tag;

/* limits themename + identifier to this length
 * will be modified in when calling into lua */
	char* prefix_buf;
	size_t prefix_ofs;

	struct arcan_extevent* last_segreq;
	char* pending_socket_label;
	int pending_socket_descr;

	const char* last_crash_source;

	lua_State* last_ctx;
} luactx = {0};

extern char* _n_strdup(const char* instr, const char* alt);
static const char* fsrvtos(enum ARCAN_SEGID ink);
static bool tgtevent(arcan_vobj_id dst, arcan_event ev);

static char* colon_escape(char* in)
{
	char* instr = in;
	while(*instr){
		if (*instr == ':')
			*instr = '\t';
		instr++;
	}
	return in;
}

/*
 * Nil out whatever functions / tables the build- system defined that we should
 * not have. Should possibly replace this with a function that maps a warning
 * about the banned function.
 */
#include "arcan_bootstrap.h"
static void luaL_nil_banned(struct arcan_luactx* ctx)
{
	int rv = luaL_loadbuffer(ctx, (const char*) arcan_bootstrap_lua,
		arcan_bootstrap_lua_len, "bootstrap");

	if (0 != rv){
		arcan_warning("BROKEN BUILD: bootstrap code couldn't be parsed\n");
	}
	else
/* called from err-handler will be ignored as it'll fatal or reload */
		rv = lua_pcall(ctx, 0, 0, 0);
}

static void dump_call_trace(lua_State* ctx)
{
/*
 * we can't trust debug.traceback to be present or in an intact state,
 * the user script might try to hide something from us -- so reset
 * the lua namespace then re-apply the restrictions.
 */
	luaL_openlibs(ctx);

	lua_settop(ctx, -2);
	lua_getfield(ctx, LUA_GLOBALSINDEX, "debug");
	if (!lua_istable(ctx, -1))
		lua_pop(ctx, 1);
	else {
		lua_getfield(ctx, -1, "traceback");
		if (!lua_isfunction(ctx, -1))
			lua_pop(ctx, 2);
		else {
			lua_call(ctx, 0, 1);
			const char* str = lua_tostring(ctx, -1);
			arcan_warning("%s\n", str);
		}
	}

	luaL_nil_banned(ctx);
}

/* slightly more flexible argument management, just find the first callback */
static intptr_t find_lua_callback(lua_State* ctx)
{
	int nargs = lua_gettop(ctx);

	for (size_t i = 1; i <= nargs; i++)
		if (lua_isfunction(ctx, i) && !lua_iscfunction(ctx, i)){
			lua_pushvalue(ctx, i);
			return luaL_ref(ctx, LUA_REGISTRYINDEX);
		}

	return (intptr_t) LUA_NOREF;
}

static int find_lua_type(lua_State* ctx, int type, int ofs)
{
	int nargs = lua_gettop(ctx);

	for (size_t i = 1; i <= nargs; i++){
		int ltype = lua_type(ctx, i);
		if (ltype == type)
			if (ofs-- == 0)
				return i;
	}

	return 0;
}

static const char* luaL_lastcaller(lua_State* ctx)
{
	static char msg[1024];
	msg[1023] = '\0';

	lua_Debug dbg;
	lua_getstack(ctx, 1, &dbg);
	lua_getinfo(ctx, "nlS" ,&dbg);
	snprintf(msg, 1023, "%s:%d", dbg.short_src, dbg.currentline);

	return msg;
}

static void trace_allocation(lua_State* ctx, const char* sym, arcan_vobj_id id)
{
	if (luactx.debug > 2)
		arcan_warning("\x1b[1m %s: alloc(%s) => %"PRIxVOBJ")\x1b[39m\x1b[0m\n",
			luaL_lastcaller(ctx), sym, id + luactx.lua_vidbase);
}

static void trace_coverage(const char* fsym, lua_State* ctx)
{
	static FILE* outf;
	static bool init;

retry:
	if (!outf && init)
		return;

	if (!outf){
		init = true;
		char* fname = arcan_expand_resource(
			"arcan.coverage", RESOURCE_SYS_DEBUG);

		if (!fname)
			return;

		outf = fopen(fname, "w+");
		arcan_mem_free(fname);
		goto retry;
	}

	fprintf(outf, "%lld;%s;", arcan_timemillis(), fsym);

	int top = lua_gettop(ctx);
	for (size_t i = 1; i <= top; i++){
		int t = lua_type(ctx, i);
		switch (t){
		case LUA_TBOOLEAN:
			fputs("bool;", outf);
		break;
		case LUA_TNIL:
			fputs("nil;", outf);
		break;
		case LUA_TLIGHTUSERDATA:
			fputs("lightud;", outf);
		break;
		case LUA_TTABLE:
			fputs("table;", outf);
		break;
		case LUA_TUSERDATA:
			fputs("ud;", outf);
		break;
		case LUA_TTHREAD:
			fputs("thread;", outf);
		break;
		case LUA_TSTRING:
			fputs("str;", outf);
		break;
		case LUA_TNUMBER:
			fputs("num;", outf);
		break;
		case LUA_TFUNCTION:
			fputs("fptr;", outf);
		break;
		default:
			fputs("unt;", outf);
		break;
		}
	}

	fputc('\n', outf);
}

/*
 * version of luaL_checknumber that accepts true/false as numbers
 */
static lua_Number luaL_checkbnumber(lua_State* L, int narg)
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

static lua_Number luaL_optbnumber(lua_State* L, int narg, lua_Number opt)
{
	if (lua_isnumber(L, narg))
		return lua_tonumber(L, narg);
	else if (lua_isboolean(L, narg))
		return lua_toboolean(L, narg);
	else
		return opt;
}

static void wraperr(struct arcan_luactx* ctx, int errc, const char* src);

/*
 * iterate all vobject and drop any known tag-cb associations that
 * are used to map events to lua functions
 */
void arcan_lua_cbdrop()
{
	for (size_t i = 0; i <= vcontext_ind; i++){
		struct arcan_video_context* ctx = &vcontext_stack[i];
		for (size_t j = 0; j < ctx->vitem_limit; j++)
			if (FL_TEST(&ctx->vitems_pool[j], FL_INUSE) &&
				ctx->vitems_pool[j].feed.state.tag == ARCAN_TAG_FRAMESERV){
				arcan_frameserver* fsrv = ctx->vitems_pool[j].feed.state.ptr;
				if (!fsrv)
					continue;

				fsrv->tag = LUA_NOREF;
			}
	}
}

void lua_rectrigger(const char* msg, ...)
{
	va_list args;
	va_start(args, msg);

#ifndef ARCAN_LUA_NOCOLOR
	lua_State* ctx = luactx.last_ctx;
	char msg_buf[256];
	vsnprintf(msg_buf, sizeof(msg_buf), msg, args);

	arcan_warning("\n\x1b[1mImproper API use from Lua script"
		":\n\t\x1b[32m%s\x1b[39m\n", msg_buf);

	dump_call_trace(ctx);

	arcan_warning("\x1b[0m\n");
#else
	arcan_warning(msg, args);
#endif

/* we got redirected here from an arcan_fatal macro- based redirection
 * so expand in order to get access to the actual call */
	va_end(args);

	if (luactx.debug > 2)
		arcan_state_dump("misuse", msg, "");

	arcan_warning("\nHanding over to recovery script "
		"(or shutdown if none present).\n");

	longjmp(arcanmain_recover_state, 3);
}

#ifdef _DEBUG
static void frozen_warning(lua_State* ctx, arcan_vobject* vobj)
{
	arcan_warning("access of frozen object (%s):\n",
		vobj->tracetag? vobj->tracetag : "untagged");
	dump_call_trace(ctx);
}
#endif

static arcan_vobj_id luaL_checkaid(lua_State* ctx, int num)
{
	return luaL_checknumber(ctx, num);
}

static void lua_pushvid(lua_State* ctx, arcan_vobj_id id)
{
	if (id != ARCAN_EID && id != ARCAN_VIDEO_WORLDID)
		id += luactx.lua_vidbase;

	lua_pushnumber(ctx, (double) id);
}

static void lua_pushaid(lua_State* ctx, arcan_aobj_id id)
{
	lua_pushnumber(ctx, id);
}

void arcan_state_dump(const char* key, const char* msg, const char* src)
{
	time_t logtime = time(NULL);
	struct tm* ltime = localtime(&logtime);
	if (!ltime){
		arcan_warning("arcan_state_dump(%s, %s, %s) failed, "
			"couldn't get localtime.", key, msg, src);
		return;
	}

	const char date_ptn[] = "%m%d_%H%M%S";
	char date_str[ sizeof(date_ptn) * 2 ];
	strftime(date_str, sizeof(date_str), date_ptn, ltime);

	char state_fn[ strlen(key) + sizeof(".lua") + sizeof(date_str) ];
	snprintf(state_fn, sizeof(state_fn), "%s_%s.lua", key, date_str);

	char* fname = arcan_expand_resource(state_fn, RESOURCE_SYS_DEBUG);
	if (!fname)
		return;

	FILE* tmpout = fopen(fname, "w+");
	if (tmpout){
		char dbuf[strlen(msg) + strlen(src) + 1];
		snprintf(dbuf, sizeof(dbuf), "%s, %s\n", msg ? msg : "", src ? src : "");

		arcan_lua_statesnap(tmpout, dbuf, false);
		fclose(tmpout);
	}
	else
		arcan_warning("crashdump requested but (%s) is not accessible.\n", fname);

	arcan_mem_free(fname);
}

/* dump argument stack, stack trace are shown only when --debug is set */
static void dump_stack(lua_State* ctx)
{
	int top = lua_gettop(ctx);
	arcan_warning("-- stack dump (%d)--\n", top);

	for (size_t i = 1; i <= top; i++){
		int t = lua_type(ctx, i);

		switch (t){
		case LUA_TBOOLEAN:
			arcan_warning(lua_toboolean(ctx, i) ? "true" : "false");
		break;
		case LUA_TSTRING:
			arcan_warning("%d\t'%s'\n", i, lua_tostring(ctx, i));
			break;
		case LUA_TNUMBER:
			arcan_warning("%d\t%g\n", i, lua_tonumber(ctx, i));
			break;
		default:
			arcan_warning("%d\t%s\n", i, lua_typename(ctx, t));
			break;
		}
	}

	arcan_warning("\n");
}

static arcan_aobj_id luaaid_toaid(lua_Number innum)
{
	return (arcan_aobj_id) innum;
}

static arcan_vobj_id luavid_tovid(lua_Number innum)
{
	arcan_vobj_id res = ARCAN_VIDEO_WORLDID;

	if (innum != ARCAN_EID && innum != ARCAN_VIDEO_WORLDID)
		res = (arcan_vobj_id) innum - luactx.lua_vidbase;
	else if (innum != res)
		res = ARCAN_EID;

	return res;
}

static lua_Number vid_toluavid(arcan_vobj_id innum)
{
	if (innum != ARCAN_EID && innum != ARCAN_VIDEO_WORLDID)
		innum += luactx.lua_vidbase;

	return (double) innum;
}

static arcan_vobj_id luaL_checkvid(
		lua_State* ctx, int num, arcan_vobject** dptr)
{
	arcan_vobj_id lnum = luaL_checknumber(ctx, num);
	arcan_vobj_id res = luavid_tovid( lnum );
	if (dptr){
		*dptr = arcan_video_getobject(res);
		if (!(*dptr))
			arcan_fatal("invalid VID requested (%"PRIxVOBJ")\n", res);
	}

#ifdef _DEBUG
	arcan_vobject* vobj = arcan_video_getobject(res);

	if (vobj && FL_TEST(vobj, FL_FROZEN))
		frozen_warning(ctx, vobj);

	if (!vobj)
		arcan_fatal("Bad VID requested (%"PRIxVOBJ") at index (%d)\n", lnum, num);
#endif

	return res;
}


/*
 * A more optimized approach than this one would be to track when the globals
 * change for C<->LUA related transfer functions and just have
 * cached function pointers.
 */
static bool grabapplfunction(lua_State* ctx,
	const char* funame, size_t funlen)
{
	if (funlen > 0){
		strncpy(luactx.prefix_buf +
			luactx.prefix_ofs + 1, funame, 32);

		luactx.prefix_buf[luactx.prefix_ofs] = '_';
		luactx.prefix_buf[luactx.prefix_ofs + funlen + 1] = '\0';
	}
	else
		luactx.prefix_buf[luactx.prefix_ofs] = '\0';

	lua_getglobal(ctx, luactx.prefix_buf);

	if (!lua_isfunction(ctx, -1)){
		lua_pop(ctx, 1);
		return false;
	}

	return true;
}

/* the places in _lua.c that calls this function should probably have a better
 * handover as this incurs additional and almost always unnecessary strlen
 * calls */
static const char* intblstr(lua_State* ctx, int ind, const char* field)
{
	lua_getfield(ctx, ind, field);
	const char* rv = lua_tostring(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}

static float intblfloat(lua_State* ctx, int ind, const char* field)
{
	lua_getfield(ctx, ind, field);
	float rv = lua_tonumber(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}

static int intblint(lua_State* ctx, int ind, const char* field)
{
	lua_getfield(ctx, ind, field);
	int rv = lua_tointeger(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}

static bool intblbool(lua_State* ctx, int ind, const char* field)
{
	lua_getfield(ctx, ind, field);
	bool rv = lua_toboolean(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}

static char* findresource(const char* arg, enum arcan_namespaces space)
{
	char* res = arcan_find_resource(arg, space, ARES_FILE);
/* since this is invoked extremely frequently and is involved in file-system
 * related stalls, maybe a sort of caching mechanism should be implemented
 * (invalidate / refill every N ticks or have a flag to side-step it -- as a lot
 * of resources are quite static and the rest of the API have to handle missing
 * or bad resources anyhow, we also know which subdirectories to attach
 * to OS specific event monitoring effects */

	if (luactx.debug){
		arcan_warning("Debug, resource lookup for %s, yielded: %s\n", arg, res);
	}

	return res;
}

static int alua_doresolve(lua_State* ctx, const char* inp)
{
	data_source source = arcan_open_resource(inp);
	if (source.fd == BADFD)
		return -1;

	map_region map = arcan_map_resource(&source, false);
	if (!map.ptr){
		arcan_release_resource(&source);
		return -1;
	}

	int rv = luaL_loadbuffer(ctx, map.ptr, map.sz, inp);
	if (0 == rv)
		rv = lua_pcall(ctx, 0, LUA_MULTRET, 0);

	arcan_release_map(map);
	arcan_release_resource(&source);

	return rv;
}

void arcan_lua_tick(lua_State* ctx, size_t nticks, size_t global)
{
	arcan_lua_setglobalint(ctx, "CLOCK", global);

	if (grabapplfunction(ctx, "clock_pulse", 11)){
		lua_pushnumber(ctx, global);
		lua_pushnumber(ctx, nticks);
		wraperr(ctx, lua_pcall(ctx, 2, 0, 0),"event loop: clock pulse");
	}
}

char* arcan_lua_main(lua_State* ctx, const char* inp, bool file)
{
/* since we prefix scriptname to functions that we look-up,
 * we need a buffer to expand into with as few read/writes/allocs
 * as possible, arcan_lua_dofile is only ever invoked when
 * an appl is about to be loaded so here is a decent entrypoint */
	const int suffix_lim = 34;

	free(luactx.prefix_buf);
	luactx.prefix_ofs = arcan_appl_id_len();
	luactx.prefix_buf = arcan_alloc_mem( arcan_appl_id_len() + suffix_lim,
		ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_SIMD
	);
	memcpy(luactx.prefix_buf, arcan_appl_id(), luactx.prefix_ofs);

	if ( (file ? alua_doresolve(ctx, inp) != 0 : luaL_dofile(ctx, inp)) == 1){
		const char* msg = lua_tostring(ctx, -1);
		if (msg)
			return strdup(msg);
	}

	return NULL;
}

/*
 * explicitly call for the allocation and use of a connection-point
 */
bool arcan_lua_launch_cp(
	struct arcan_luactx* ctx, const char* cp, const char* key)
{
	if (!cp || !ctx)
		return false;

	if (!grabapplfunction(ctx, "adopt", sizeof("adopt")-1)){
		arcan_warning("target appl lacks an _adopt handler\n");
		return false;
	}

	struct arcan_frameserver* res =
		platform_launch_listen_external(cp, key, -1, ARCAN_SHM_UMASK, LUA_NOREF);
	if (!res){
		arcan_warning("couldn't listen on connection point (%s)\n", cp);
		return false;
	}

	lua_pushvid(ctx, res->vid);
	lua_pushstring(ctx, "_stdin");
	lua_pushstring(ctx, "");
	lua_pushvid(ctx, ARCAN_EID);
	lua_pushboolean(ctx, true);

	wraperr(ctx, lua_pcall(ctx, 5, 1, 0), "adopt");
	if (lua_type(ctx, -1) == LUA_TBOOLEAN && lua_toboolean(ctx, -1)){
		lua_pop(ctx, 1);
		return true;
	}
	else {
		arcan_warning("target appl rejected _stdin on adopt\n");
		lua_pop(ctx, 1);
		arcan_video_deleteobject(res->vid);
		return false;
	}
}

void arcan_lua_adopt(struct arcan_luactx* ctx)
{
/* works on the idea that the context stack has already been collapsed into
 * 'only-fsrv' related vids left */
	struct arcan_vobject_litem* first = vcontext_stack[0].stdoutp.first;
	struct arcan_vobject_litem* current = first;

	size_t n_fsrv = 0;
/* one: find out how many frameservers are running in the context */
	while(current){
		if (current->elem->feed.state.tag == ARCAN_TAG_FRAMESERV)
			n_fsrv++;
		current = current->next;
	}

	if (n_fsrv == 0)
		return;

/* two: save all the IDs, this tracking is because every call to adopt may
 * possibly change the context and number of frameservers, order losely so that
 * we get primary segments before secondary ones */
	arcan_vobj_id ids[n_fsrv];
	size_t count = 0, lcount = n_fsrv -1;
	current = first;
	while(count < n_fsrv && current){
		if (current->elem->feed.state.tag == ARCAN_TAG_FRAMESERV){
			arcan_frameserver* fsrv = current->elem->feed.state.ptr;
			if (fsrv->parent.vid != ARCAN_EID)
				ids[lcount--] = current->elem->cellid;
			else
				ids[count++] = current->elem->cellid;
		}
		current = current->next;
	}

	arcan_vobj_id delids[n_fsrv];
	size_t delcount = 0;

/* three: forward to adopt function (or delete) */
	for (count = 0; count < n_fsrv; count++){
		arcan_vobject* vobj = arcan_video_getobject(ids[count]);
		if (!vobj || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			continue;

		arcan_frameserver* fsrv = vobj->feed.state.ptr;
		fsrv->tag = LUA_NOREF;

		bool delete = true;
		if (grabapplfunction(ctx, "adopt", sizeof("adopt") - 1) &&
			arcan_video_getobject(ids[count]) != NULL){
			lua_pushvid(ctx, vobj->cellid);
			lua_pushstring(ctx, fsrvtos(fsrv->segid));
			lua_pushstring(ctx, fsrv->title);
			lua_pushvid(ctx, fsrv->parent.vid);
			lua_pushboolean(ctx, count < n_fsrv-1);

			wraperr(ctx, lua_pcall(ctx, 5, 1, 0), "adopt");

/* if we don't get an explicit accept, assume deletion */
			if (lua_type(ctx, -1) == LUA_TBOOLEAN &&
				lua_toboolean(ctx, -1) == true){
				delete = false;
/* send register event again so adoption imposed handler might map
 * to related archetype, then follow up with resized to underlying
 * format. Other state restoration has to be handled by fsrv itself */
				arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
					.category = EVENT_EXTERNAL,
					.ext.kind = EVENT_EXTERNAL_REGISTER,
					.ext.registr.kind = fsrv->segid,
					.ext.registr.guid[0] = fsrv->guid[0],
					.ext.registr.guid[1] = fsrv->guid[1]
				});

/* fake a resize event that corresponds to the last negotiated state */
				arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
					.category = EVENT_FSRV,
					.fsrv.kind = EVENT_FSRV_RESIZED,
					.fsrv.width = fsrv->desc.width,
					.fsrv.height = fsrv->desc.height,
					.fsrv.video = fsrv->vid,
					.fsrv.audio = fsrv->aid,
					.fsrv.otag = fsrv->tag,
					.fsrv.glsource = fsrv->desc.hints & SHMIF_RHINT_ORIGO_LL
				});

/* the RESET event to the affected frameserver, though it could be used as a
 * DoS oracly, there are so many timing channels that are necessary that it
 * doesn't really aid much by hiding the fact, but it can help a cooperative
 * process enough that it is worth the tradeoff */
				platform_fsrv_pushevent(fsrv, &(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_RESET,
					.tgt.ioevs[0].iv = 2
				});
			}

			lua_pop(ctx, 1);
		}

		if (delete)
			delids[delcount++] = ids[count];
	}
/* purge will remove all events that are not external, and those that
 * are external will have its otag reset (as otherwise we'd be calling
 * into a damaged luactx */
	arcan_event_purge();

/* maskall will prevent new events from being added during delete,
 * as we are not in a state of being able to track or interpret */
	arcan_event_maskall(arcan_event_defaultctx());
	for (count = 0; count < delcount; count++)
		arcan_video_deleteobject(delids[count]);
	arcan_event_clearmask(arcan_event_defaultctx());

/* lastly, there might be events that have been tagged to an old callback
 * where we again lack state information enough to track */
}

static int zapresource(lua_State* ctx)
{
	LUA_TRACE("zap_resource");

	char* path = findresource(luaL_checkstring(ctx, 1), RESOURCE_APPL_TEMP);

	if (path && unlink(path) != -1)
		lua_pushboolean(ctx, false);
	else
		lua_pushboolean(ctx, true);

	arcan_mem_free(path);

	LUA_ETRACE("zap_resource", NULL, 1);
}

static int opennonblock_tgt(lua_State* ctx, bool wr)
{
	arcan_vobject* vobj;
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, &vobj);
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("open_nonblock(tgt), target must be a valid frameserver.\n");

	int outp[2];
	if (-1 == pipe(outp)){
		arcan_warning("open_nonblock(tgt), pipe-pair creation failed: %d\n", errno);
		return 0;
	}

/* WRITE mode = 'INPUT' in the client space */
	int dst = wr ? outp[0] : outp[1];
	int src = wr ? outp[1] : outp[0];

/* in any scenario where this would fail, "blocking" behavior is acceptable */
	int flags = fcntl(src, F_GETFL);
	if (-1 != flags)
		fcntl(src, F_SETFL, flags | O_NONBLOCK);

	if (ARCAN_OK != platform_fsrv_pushfd(fsrv, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = wr ? TARGET_COMMAND_BCHUNK_IN : TARGET_COMMAND_BCHUNK_OUT,
		.tgt.message = "stream"}, dst)
	){
		close(dst);
		close(src);
		return 0;
	}
	close(dst);

	struct nonblock_io* conn = arcan_alloc_mem(sizeof(struct nonblock_io),
			ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	if (!conn){
		close(src);
		return 0;
	}

	conn->fd = src;
	conn->pending = NULL;

	uintptr_t* dp = lua_newuserdata(ctx, sizeof(uintptr_t));
	*dp = (uintptr_t) conn;
	luaL_getmetatable(ctx, wr ? "nonblockIOw" : "nonblockIOr");
	lua_setmetatable(ctx, -2);

	return 1;
}

static int opennonblock(lua_State* ctx)
{
	LUA_TRACE("open_nonblock");

	const char* metatable = NULL;
	bool wrmode = luaL_optbnumber(ctx, 2, 0);
	bool fifo = false, ignerr = false;
	char* path;
	int fd;

	if (lua_type(ctx, 1) == LUA_TNUMBER){
		int rv = opennonblock_tgt(ctx, wrmode);
		LUA_ETRACE("open_nonblock(), ", NULL, rv);
	}

	const char* str = luaL_checkstring(ctx, 1);
	if (str[0] == '<'){
		fifo = true;
		str++;
	}

/* note on file-system races: it is an explicit contract that the namespace
 * provided for RESOURCE_APPL_TEMP is single- user (us) only. Anyhow, this
 * code turned out a lot messier than needed, refactor when time permits. */
	if (wrmode){
		struct stat fi;
		metatable = "nonblockIOw";
		path = findresource(str, RESOURCE_APPL_TEMP);

/* we require a zap_resource call if the file already exists, except for in
 * the case of a fifo dst- that we can open in (w) mode */
		bool dst_fifo = (path && -1 != stat(path, &fi) && S_ISFIFO(fi.st_mode));
		if (!dst_fifo && (path || !(path =
			arcan_expand_resource(str, RESOURCE_APPL_TEMP)))){
			arcan_warning("open_nonblock(), refusing to open "
				"existing file for writing\n");
			arcan_mem_free(path);

			LUA_ETRACE("open_nonblock", "write on already existing file", 0);
		}

		int fl = O_NONBLOCK | O_WRONLY | O_CLOEXEC;
		if (fifo){
/* this is susceptible to the normal race conditions, but we also expect
 * APPL_TEMP to be mapped to a 'safe' path */
			if (-1 == mkfifo(path, S_IRWXU)){
				if (errno != EEXIST || -1 == stat(path, &fi) || !S_ISFIFO(fi.st_mode)){
					arcan_warning("open_nonblock(): mkfifo (%s) failed\n", path);
					LUA_ETRACE("open_nonblock", "mkfifo failed", 0);
				}
			}
			ignerr = true;
		}
		else
			fl |= O_CREAT;

/* failure to open fifo can be expected, then opening will be deferred */
		fd = open(path, fl, S_IRWXU);
		if (-1 != fd && fifo && (-1 == fstat(fd, &fi) || !S_ISFIFO(fi.st_mode))){
			close(fd);
			LUA_ETRACE("open_nonblock", "opened file not fifo", 0);
		}
	}
	else{
retryopen:
		path = findresource(str, fifo ? RESOURCE_APPL_TEMP : DEFAULT_USERMASK);
		metatable = "nonblockIOr";

		if (!path){
			if (fifo && (path = arcan_expand_resource(str, RESOURCE_APPL_TEMP))){
				if (-1 == mkfifo(path, S_IRWXU)){
					arcan_warning("open_nonblock(): mkfifo (%s) failed\n", path);
					LUA_ETRACE("open_nonblock", "mkfifo failed", 0);
				}
				goto retryopen;
			}
			else{
				LUA_ETRACE("open_nonblock", "file does not exist", 0);
			}
		}
		else
			fd = open(path, O_NONBLOCK | O_CLOEXEC | O_RDONLY);
		arcan_mem_free(path);
		path = NULL;
	}


	if (fd < 0 && !ignerr){
		LUA_ETRACE("open_nonblock", "couldn't open file", 0);
	}

	struct nonblock_io* conn = arcan_alloc_mem(sizeof(struct nonblock_io),
			ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	conn->fd = fd;
	conn->pending = path;

	uintptr_t* dp = lua_newuserdata(ctx, sizeof(uintptr_t));
	*dp = (uintptr_t) conn;

	luaL_getmetatable(ctx, metatable);
	lua_setmetatable(ctx, -2);

	LUA_ETRACE("open_nonblock", NULL, 1);
}

static int rawresource(lua_State* ctx)
{
	LUA_TRACE("open_rawresource");

/* can't do more than this due to legacy */
	if (luactx.rawres.fd > 0){
		arcan_warning("open_rawresource(), open requested while other resource "
			"still open, use close_rawresource first.\n");

		close(luactx.rawres.fd);
		luactx.rawres.fd = -1;
		luactx.rawres.ofs = 0;
	}

	char* path = findresource(luaL_checkstring(ctx, 1), DEFAULT_USERMASK);

	if (!path){
		char* fname = arcan_expand_resource(
			luaL_checkstring(ctx, 1), RESOURCE_APPL_TEMP);

		if (fname){
			luactx.rawres.fd = open(fname,
				O_CREAT | O_CLOEXEC | O_RDWR, S_IRUSR | S_IWUSR);
			arcan_mem_free(fname);
		}
	}
	else{
		luactx.rawres.fd = open(path, O_RDONLY | O_CLOEXEC);
		arcan_mem_free(path);
	}

	lua_pushboolean(ctx, luactx.rawres.fd > 0);
	LUA_ETRACE("open_rawresource", "", 1);
}

static char* chop(char* str)
{
	char* endptr = str + strlen(str) - 1;
	while(isspace(*str)) str++;

	if(!*str)
		return str;

	while(endptr > str && isspace(*endptr))
		endptr--;

	*(endptr+1) = 0;

	return str;
}

static int funtable(lua_State* ctx, uint32_t kind){
	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	lua_pushstring(ctx, "kind");
	lua_pushnumber(ctx, kind);
	lua_rawset(ctx, top);

	return top;
}

static void tblstr(lua_State* ctx, const char* k,
	const char* v, int top){
	lua_pushstring(ctx, k);
	lua_pushstring(ctx, v);
	lua_rawset(ctx, top);
}

static void tblnum(lua_State* ctx, char* k, double v, int top){
	lua_pushstring(ctx, k);
	lua_pushnumber(ctx, v);
	lua_rawset(ctx, top);
}

static void tblbool(lua_State* ctx, char* k, bool v, int top){
	lua_pushstring(ctx, k);
	lua_pushboolean(ctx, v);
	lua_rawset(ctx, top);
}

static const char flt_alpha[] = "abcdefghijklmnopqrstuvwxyz-_";
static const char flt_chunkfn[] = "abcdefhijklmnopqrstuvwxyz1234567890;";
static const char flt_alphanum[] = "abcdefghijklmnopqrstuvwyz-0123456789-_";
static const char flt_Alphanum[] = "abcdefghijklmnopqrstuvwyz-0123456789-_"
	"ABCDEFGHIJKLMNOPQRSTUVWXYZ";
static const char flt_Alpha[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
	"abcdefghijklmnopqrstuvwxyz";
static const char flt_num[] = "0123456789_-";

static void fltpush(char* dst, char ulim,
	char* inmsg, const char* fltch, char replch)
{
	while (*inmsg && ulim--){
		const char* pos = fltch;
		bool found = false;

		while(*pos){
			if (*pos == *inmsg){
				found = true;
				break;
			}
			pos++;
		}

		if (!found){
			if (replch)
				*dst++ = replch;
		}
		else
			*dst++ = *inmsg;
		inmsg++;
	}

	*dst = '\0';
}


/*
 * Scan and check that the sequence is valid utf-8 and does not exceed the set
 * upper limit. If it does, truncate and return, otherwise copy into dst. Ulim
 * includes the terminating 0.
 */
#include "../frameserver/util/utf8.c"

static void slim_utf8_push(char* dst, int ulim, char* inmsg)
{
	uint32_t state = 0;
	uint32_t codepoint = 0;
	size_t i = 0;

	for (; inmsg[i] != '\0', i < ulim; i++){
		dst[i] = inmsg[i];

		if (utf8_decode(&state, &codepoint, (uint8_t)(inmsg[i])) == UTF8_REJECT)
			goto out;
	}

	if (state == UTF8_ACCEPT){
		dst[i] = '\0';
		return;
	}

/* for broken state, just ignore. The other options would be 'warn' (will spam)
 * or to truncate (might in some cases be prefered). */
out:
	dst[0] = '\0';
}

static char* streamtype(int num)
{
	switch (num){
	case 0: return "audio";
	case 1: return "video";
	case 2: return "text";
	case 3: return "overlay";
	}
	return "broken";
}

static int push_resstr(lua_State* ctx, struct nonblock_io* ib, off_t ofs)
{
	size_t in_sz = COUNT_OF(luactx.rawres.buf);

	lua_pushlstring(ctx, ib->buf, ofs);

/* slide or reset buffering */
	if (ofs >= in_sz - 1){
		ib->ofs = 0;
	}
	else{
		memmove(ib->buf, ib->buf + ofs + 1, ib->ofs - ofs - 1);
		ib->ofs -= ofs + 1;
	}

	return 1;
}

static size_t bufcheck(lua_State* ctx, struct nonblock_io* ib)
{
	size_t in_sz = COUNT_OF(luactx.rawres.buf);

	for (size_t i = 0; i < ib->ofs; i++){
		if (ib->buf[i] == '\n')
			return push_resstr(ctx, ib, i);
	}

	if (in_sz - ib->ofs == 1)
		return push_resstr(ctx, ib, in_sz - 1);

	return 0;
}

static int bufread(lua_State* ctx, struct nonblock_io* ib)
{
	size_t buf_sz = COUNT_OF(ib->buf);

	if (!ib || ib->fd < 0)
		return 0;

	size_t bufch = bufcheck(ctx, ib);
	if (bufch)
		return bufch;

	ssize_t nr;
	if ( (nr = read(ib->fd, ib->buf + ib->ofs, buf_sz - ib->ofs - 1)) > 0)
		ib->ofs += nr;

	return bufcheck(ctx, ib);
}

static int nbio_closer(lua_State* ctx)
{
	LUA_TRACE("open_nonblock:close");
	struct nonblock_io** ib = luaL_checkudata(ctx, 1, "nonblockIOr");
	if (*ib == NULL){
		LUA_ETRACE("open_nonblock:close", "missing updata", 0);
	}

	if (-1 != (*ib)->fd)
		close((*ib)->fd);
	free((*ib)->pending);
	free(*ib);
	*ib = NULL;

	LUA_ETRACE("open_nonblock:close", NULL, 0);
}

static int nbio_closew(lua_State* ctx)
{
	LUA_TRACE("open_nonblock:close_write");
	struct nonblock_io** ib = luaL_checkudata(ctx, 1, "nonblockIOw");
	if (*ib == NULL){
		LUA_ETRACE("open_nonblock:close_write", "missing udata", 0);
	}

	close((*ib)->fd);
	free(*ib);
	*ib = NULL;

	LUA_ETRACE("open_nonblock:close_write", NULL, 0);
}

static int nbio_write(lua_State* ctx)
{
	LUA_TRACE("open_nonblock:write");
	struct nonblock_io** ud = luaL_checkudata(ctx, 1, "nonblockIOw");
	struct nonblock_io* iw = *ud;
	const char* buf = luaL_checkstring(ctx, 2);
	size_t len = strlen(buf);
	off_t of = 0;

/* special case for FIFOs that aren't hooked up on creation */
	if (-1 == iw->fd && iw->pending){
		iw->fd = open(iw->pending, O_NONBLOCK | O_WRONLY | O_CLOEXEC);

/* but still make sure that we actually got a FIFO */
		if (-1 != iw->fd){
			struct stat fi;

/* and if not, don't try to write */
			if (-1 != fstat(iw->fd, &fi) && !S_ISFIFO(fi.st_mode)){
				close(iw->fd);
				iw->fd = -1;
				lua_pushnumber(ctx, 0);
				LUA_ETRACE("open_nonblock:write", NULL, 1);
			}
		}
	}

/* non-block, so don't allow too many attempts, but we push the
 * responsibility of buffering to the caller */
	int retc = 5;
	while (retc && (len - of)){
		size_t nw = write(iw->fd, buf + of, len - of);
		if (-1 == nw){
			if (errno == EAGAIN || errno == EINTR){
				retc--;
				continue;
			}
			else{
				close(iw->fd);
				iw->fd = -1;
			}
				break;
		}
		else
			of += nw;
	}

	lua_pushnumber(ctx, of);
	LUA_ETRACE("open_nonblock:write", NULL, 1);
}

static int nbio_read(lua_State* ctx)
{
	LUA_TRACE("open_nonblock:read");
	struct nonblock_io** ib = luaL_checkudata(ctx, 1, "nonblockIOr");
	if (*ib == NULL)
		LUA_ETRACE("open_nonblock:read", NULL, 0);

	int nr = bufread(ctx, *ib);
	LUA_ETRACE("open_nonblock:read", NULL, nr);
}

static int readrawresource(lua_State* ctx)
{
	LUA_TRACE("read_rawresource");

	if (luactx.rawres.fd < 0){
		LUA_ETRACE("read_rawresource", "no open file", 0);
	}

	int n = bufread(ctx, &luactx.rawres);
	LUA_ETRACE("read_rawresource", NULL, n);
}

void arcan_lua_setglobalstr(lua_State* ctx,
	const char* key, const char* val)
{
	lua_pushstring(ctx, val);
	lua_setglobal(ctx, key);
}

void arcan_lua_setglobalint(lua_State* ctx, const char* key, int val)
{
	lua_pushnumber(ctx, val);
	lua_setglobal(ctx, key);
}

static int rawclose(lua_State* ctx)
{
	LUA_TRACE("close_rawresource");

	bool res = false;

	if (luactx.rawres.fd > 0){
		close(luactx.rawres.fd);
		luactx.rawres.fd = -1;
		luactx.rawres.ofs = 0;
	}

	lua_pushboolean(ctx, res);
	LUA_ETRACE("close_rawresource", NULL, 1);
}

static int pushrawstr(lua_State* ctx)
{
	LUA_TRACE("write_rawresource");

	const char* mesg = luaL_checkstring(ctx, 1);
	size_t ntw = strlen(mesg);

	if (ntw && luactx.rawres.fd > 0){
		size_t ofs = 0;

		while (ntw){
			ssize_t nw = write(luactx.rawres.fd, mesg + ofs, ntw);
			if (-1 != nw){
				ofs += nw;
				ntw -= nw;
			}
			else if (errno != EAGAIN && errno != EINTR)
				break;
		}
	}

	lua_pushboolean(ctx, ntw == 0);
	LUA_ETRACE("write_rawresource", NULL, 1);
}

#ifdef _DEBUG
static int freezeimage(lua_State* ctx)
{
	LUA_TRACE("freeze_image");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	FL_SET(vobj, FL_FROZEN);
	LUA_ETRACE("freeze_image", NULL, 0);
}

static int debugstall(lua_State* ctx)
{
	LUA_TRACE("frameserver_debugstall");
	int tn = luaL_checknumber(ctx, 1);
	if (tn <= 0)
		unsetenv("ARCAN_FRAMESERVER_DEBUGSTALL");
	else{
		char buf[4];
		snprintf(buf, 4, "%4d", tn);
		setenv("ARCAN_FRAMESERVER_DEBUGSTALL", buf, 1);
	}

	LUA_ETRACE("frameserver_debugstall", NULL, 0);
}
#endif

static int loadimage(lua_State* ctx)
{
	LUA_TRACE("load_image");

	arcan_vobj_id id = ARCAN_EID;
	char* path = findresource(luaL_checkstring(ctx, 1), DEFAULT_USERMASK);

	uint8_t prio = luaL_optint(ctx, 2, 0);
	unsigned desw = luaL_optint(ctx, 3, 0);
	unsigned desh = luaL_optint(ctx, 4, 0);

	if (path){
		id = arcan_video_loadimage(
			path, (img_cons){.w = desw, .h = desh}, prio);
		arcan_mem_free(path);
	}

	lua_pushvid(ctx, id);
	trace_allocation(ctx, "load_image", id);
	LUA_ETRACE("load_image", NULL, 1);
}

static int loadimageasynch(lua_State* ctx)
{
	LUA_TRACE("load_image_asynch");

	arcan_vobj_id id = ARCAN_EID;
	intptr_t ref = 0;

	char* path = findresource(luaL_checkstring(ctx, 1), DEFAULT_USERMASK);

	if (lua_isfunction(ctx, 2) && !lua_iscfunction(ctx, 2)){
		lua_pushvalue(ctx, 2);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}

	if (path && strlen(path) > 0){
		id = arcan_video_loadimageasynch(path, (img_cons){}, ref);
	}
	arcan_mem_free(path);

	lua_pushvid(ctx, id);
	trace_allocation(ctx, "load_image_asynch", id);
	LUA_ETRACE("load_image_asynch", NULL, 1);
}

static int imageloaded(lua_State* ctx)
{
	LUA_TRACE("imageloaded");
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);

	lua_pushnumber(ctx, vobj->feed.state.tag == ARCAN_TAG_IMAGE);
	LUA_ETRACE("load_image_asynch", NULL, 1);
}

static int moveimage(lua_State* ctx)
{
	LUA_TRACE("move_image");
	acoord newx = luaL_optnumber(ctx, 2, 0);
	acoord newy = luaL_optnumber(ctx, 3, 0);
	int time = luaL_optint(ctx, 4, 0);
	int interp = luaL_optint(ctx, 5, -1);

	if (time < 0) time = 0;

/* array of VIDs or single VID */
	int argtype = lua_type(ctx, 1);
	if (argtype == LUA_TNUMBER){
		arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
		arcan_video_objectmove(id, newx, newy, 1.0, time);
		if (time > 0 && interp >= 0 && interp < ARCAN_VINTER_ENDMARKER)
			arcan_video_moveinterp(id, interp);
	}
	else if (argtype == LUA_TTABLE){
		int nelems = lua_rawlen(ctx, 1);

		for (size_t i = 0; i < nelems; i++){
			lua_rawgeti(ctx, 1, i+1);
			arcan_vobj_id id = luaL_checkvid(ctx, -1, NULL);
			arcan_video_objectmove(id, newx, newy, 1.0, time);
			if (time > 0 && interp >= 0 && interp < ARCAN_VINTER_ENDMARKER)
				arcan_video_moveinterp(id, interp);

			lua_pop(ctx, 1);
		}
	}
	else
		arcan_fatal("move_image(), invalid argument (1) "
			"expected VID or indexed table of VIDs\n");

	LUA_ETRACE("move_image", NULL, 0);
}

static int nudgeimage(lua_State* ctx)
{
	LUA_TRACE("nudge_image");
	acoord newx = luaL_optnumber(ctx, 2, 0);
	acoord newy = luaL_optnumber(ctx, 3, 0);
	int time = luaL_optint(ctx, 4, 0);
	int interp = luaL_optint(ctx, 5, -1);

	if (time < 0) time = 0;
	bool use_interp = time > 0 && interp >= 0 && interp < ARCAN_VINTER_ENDMARKER;

	int argtype = lua_type(ctx, 1);
	if (argtype == LUA_TNUMBER){
		arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
		surface_properties props = arcan_video_current_properties(id);
		arcan_video_objectmove(id, props.position.x + newx,
			props.position.y + newy, 1.0, time);

		if (use_interp)
			arcan_video_moveinterp(id, interp);
	}
	else if (argtype == LUA_TTABLE){
		int nelems = lua_rawlen(ctx, 1);

		for (size_t i = 0; i < nelems; i++){
			lua_rawgeti(ctx, 1, i+1);
			arcan_vobj_id id = luaL_checkvid(ctx, -1, NULL);
			surface_properties props = arcan_video_current_properties(id);
			arcan_video_objectmove(id, props.position.x + newx,
				props.position.y + newy, 1.0, time);

			if (use_interp)
				arcan_video_moveinterp(id, interp);

			lua_pop(ctx, 1);
		}
	}
	else
		arcan_fatal("nudge_image(), invalid argument (1) "
			"expected VID or indexed table of VIDs\n");

	LUA_ETRACE("nudge_image", NULL, 0);
}

static int resettransform(lua_State* ctx)
{
	LUA_TRACE("reset_image_transform");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	float num = 0;
	arcan_video_zaptransform(id, &num);
	lua_pushnumber(ctx, num);
	LUA_ETRACE("reset_image_transform", NULL, 1);
}

static int instanttransform(lua_State* ctx)
{
	LUA_TRACE("instant_image_transform");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_video_instanttransform(id);
	LUA_ETRACE("instant_image_transform", NULL, 0);
}

static int cycletransform(lua_State* ctx)
{
	LUA_TRACE("image_transform_cycle");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	bool flag = luaL_checkbnumber(ctx, 2);

	arcan_video_transformcycle(sid, flag);
	LUA_ETRACE("image_transform_cycle", NULL, 0);
}

static int copytransform(lua_State* ctx)
{
	LUA_TRACE("copy_image_transform");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);

	arcan_video_copytransform(sid, did);
	LUA_ETRACE("copy_image_transform", NULL, 0);
}

static int transfertransform(lua_State* ctx)
{
	LUA_TRACE("transfer_image_transform");

	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);

	arcan_video_transfertransform(sid, did);
	LUA_ETRACE("transfer_image_transform", NULL, 0);
}

static int rotateimage(lua_State* ctx)
{
	LUA_TRACE("rotate_image");

	acoord ang = luaL_checknumber(ctx, 2);
	int time = luaL_optint(ctx, 3, 0);

	int argtype = lua_type(ctx, 1);
	if (argtype == LUA_TNUMBER){
		arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
		arcan_video_objectrotate(id, ang, time);
	}
	else if (argtype == LUA_TTABLE){
		int nelems = lua_rawlen(ctx, 1);

		for (size_t i = 0; i < nelems; i++){
			lua_rawgeti(ctx, 1, i+1);
			arcan_vobj_id id = luaL_checkvid(ctx, -1, NULL);
			arcan_video_objectrotate(id, ang, time);
			lua_pop(ctx, 1);
		}
	}
	else arcan_fatal("rotate_image(), invalid argument (1) "
		"expected VID or indexed table of VIDs\n");

	LUA_ETRACE("rotate_image", NULL, 0);
}

static int resampleimage(lua_State* ctx)
{
	LUA_TRACE("resample_image");
	arcan_vobject* vobj;
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, &vobj);
	agp_shader_id shid = lua_type(ctx, 2) == LUA_TSTRING ?
	agp_shader_lookup(luaL_checkstring(ctx, 2)) : luaL_checknumber(ctx, 2);
	size_t width = abs((int)luaL_checknumber(ctx, 3));
	size_t height = abs((int)luaL_checknumber(ctx, 4));

	if (width == 0 || width > MAX_SURFACEW || height == 0|| height > MAX_SURFACEH)
		arcan_fatal("resample_image(), illegal dimensions"
			" requested (%d:%d x %d:%d)\n",
			width, MAX_SURFACEW, height, MAX_SURFACEH
		);

	if (ARCAN_OK != arcan_video_setprogram(sid, shid))
		arcan_warning("arcan_video_setprogram(%d, %d) -- couldn't set shader,"
			"invalid vobj or shader id specified.\n", sid, shid);
	else
		arcan_video_resampleobject(sid, width, height, shid);

	LUA_ETRACE("resample_image", NULL, 0);
}

static int imageresizestorage(lua_State* ctx)
{
	LUA_TRACE("image_resize_storage");

	arcan_vobject* vobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);
	size_t w = abs((int)luaL_checknumber(ctx, 2));
	size_t h = abs((int)luaL_checknumber(ctx, 3));
	if (w == 0 || w > MAX_SURFACEW || h == 0 || h > MAX_SURFACEH)
		arcan_fatal("image_resize_storage(), illegal dimensions"
			"	requested (%d:%d x %d:%d)\n", w, MAX_SURFACEW, h, MAX_SURFACEH);

	vobj->origw = w;
	vobj->origh = h;

	struct rendertarget* rtgt = arcan_vint_findrt(vobj);
	if (rtgt){
		agp_resize_rendertarget(rtgt->art, w, h);
		build_orthographic_matrix(rtgt->projection, 0, w, 0, h, 0, 1);
	}
	else
		arcan_video_resizefeed(id, w, h);
	LUA_ETRACE("image_resize_storage", NULL, 0);
}

static int centerimage(lua_State* ctx)
{
	LUA_TRACE("center_image");
	arcan_vobject* sobj;

/*
 * now this is primarily used for centering text on other
 * components and similar UI operations so don't optimize
 * without benchmarks, but there is a few ops that can be
 * saved by checking if src and dst are in same space, if
 * so, then the costly resolve can be skipped.
 */
	arcan_vobj_id src = luaL_checkvid(ctx, 1, &sobj);
	arcan_vobj_id obj = luaL_checkvid(ctx, 2, NULL);
	int al = luaL_optnumber(ctx, 3, ANCHORP_C);
	int xofs = luaL_optnumber(ctx, 4, 0);
	int yofs = luaL_optnumber(ctx, 5, 0);

	surface_properties sprop, dprop;
	sprop = arcan_video_resolve_properties(src);
	dprop = arcan_video_resolve_properties(obj);

/* scale actually contains width, now we move our center
 * the specified anchor point */
	int cp_sx = sprop.position.x + (sprop.scale.x * 0.5);
	int cp_sy = sprop.position.y + (sprop.scale.y * 0.5);

	int ap_x = dprop.position.x;
	int ap_y = dprop.position.y;

	switch(al){
	case ANCHORP_C:
		ap_x += dprop.scale.x * 0.5;
		ap_y += dprop.scale.y * 0.5;
	break;
	case ANCHORP_UC:
		ap_x += dprop.scale.x * 0.5;
	break;
	case ANCHORP_LC:
		ap_x += dprop.scale.x * 0.5;
		ap_y += dprop.scale.y;
	break;
	case ANCHORP_CL:
		ap_y += dprop.scale.y * 0.5;
	break;
	case ANCHORP_CR:
		ap_x += dprop.scale.x;
		ap_y += dprop.scale.y * 0.5;
	break;
	case ANCHORP_UL:
	break;
	case ANCHORP_UR:
		ap_x += dprop.scale.x;
	break;
	case ANCHORP_LL:
		ap_y += dprop.scale.y;
	break;
	case ANCHORP_LR:
		ap_x += dprop.scale.x;
		ap_y += dprop.scale.y;
	break;
	default:
		arcan_fatal("center_image(), unknown anchor point (%d)\n", al);
	break;
	}

/* calculate deltas in world-space, add attachment-point local delta
 * and finally translate to coordinates in src-obj space */

	arcan_video_objectmove(src,
		sobj->current.position.x + ap_x - cp_sx + xofs,
		sobj->current.position.y + ap_y - cp_sy + yofs, 1.0, 0
	);

	LUA_ETRACE("center_image", NULL, 0);
}

static int cropimage(lua_State* ctx)
{
	LUA_TRACE("crop_image");
	arcan_vobject* vobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);
	float w = luaL_checknumber(ctx, 2);
	float h = luaL_checknumber(ctx, 3);

	surface_properties prop = arcan_video_initial_properties(id);
	float ss = 1.0;
	float st = 1.0;
	bool crop_st = false;

	if (prop.scale.x > w){
		ss = w / prop.scale.x;
		crop_st = true;
	}
	if (prop.scale.y > h){
		st = h / prop.scale.y;
		crop_st = true;
	}

	arcan_video_objectscale(id, ss, st, 1.0, 0);
	if (crop_st)
		arcan_video_scaletxcos(id, ss, st);

	LUA_ETRACE("crop_image", NULL, 0);
}

/* Input is absolute values,
 * arcan_video_objectscale takes relative to initial size */
static int scaleimage2(lua_State* ctx)
{
	LUA_TRACE("resize_image");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	float neww = (acoord) luaL_checknumber(ctx, 2);
	float newh = (acoord) luaL_checknumber(ctx, 3);

	int time = luaL_optint(ctx, 4, 0);
	int interp = luaL_optint(ctx, 5, -1);
	bool use_interp = time > 0 && interp >= 0 && interp < ARCAN_VINTER_ENDMARKER;

	if (time < 0) time = 0;

	if (neww < EPSILON && newh < EPSILON){
		LUA_ETRACE("resize_image", "undersized dimensions", 0);
	}

	surface_properties prop = arcan_video_initial_properties(id);
	if (prop.scale.x < EPSILON && prop.scale.y < EPSILON){
		lua_pushnumber(ctx, 0);
		lua_pushnumber(ctx, 0);
	}
	else {
		/* retain aspect ratio in scale */
		if (neww < EPSILON && newh > EPSILON)
			neww = newh * (prop.scale.x / prop.scale.y);
		else
			if (neww > EPSILON && newh < EPSILON)
				newh = neww * (prop.scale.y / prop.scale.x);

		neww = ceilf(neww);
		newh = ceilf(newh);
		arcan_video_objectscale(id, neww / prop.scale.x,
			newh / prop.scale.y, 1.0, time);

		if (use_interp)
			arcan_video_scaleinterp(id, interp);

		lua_pushnumber(ctx, neww);
		lua_pushnumber(ctx, newh);
	}

	LUA_ETRACE("resize_image", NULL, 2);
}

static int scaleimage(lua_State* ctx)
{
	LUA_TRACE("scale_image");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);

	float desw = luaL_checknumber(ctx, 2);
	float desh = luaL_checknumber(ctx, 3);
	int time = luaL_optint(ctx, 4, 0);
	int interp = luaL_optint(ctx, 5, -1);
	if (time < 0) time = 0;
	bool use_interp = time > 0 && interp >= 0 && interp < ARCAN_VINTER_ENDMARKER;

	surface_properties prop = arcan_video_initial_properties(id);

	/* retain aspect ratio in scale */
	if (desw < EPSILON && desh > EPSILON)
		desw = desh * (prop.scale.x / prop.scale.y);
	else
		if (desw > EPSILON && desh < EPSILON)
			desh = desw * (prop.scale.y / prop.scale.x);

	arcan_video_objectscale(id, desw, desh, 1.0, time);
	if (use_interp)
		arcan_video_scaleinterp(id, interp);

	lua_pushnumber(ctx, desw);
	lua_pushnumber(ctx, desh);

	LUA_ETRACE("scale_image", NULL, 2);
}

static int orderimage(lua_State* ctx)
{
	LUA_TRACE("order_image");
	int zv = luaL_checknumber(ctx, 2);

/* array of VIDs or single VID */
	int argtype = lua_type(ctx, 1);
	if (argtype == LUA_TNUMBER){
		arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
		arcan_video_setzv(id, zv);
	}
	else if (argtype == LUA_TTABLE){
		int nelems = lua_rawlen(ctx, 1);

		for (size_t i = 0; i < nelems; i++){
			lua_rawgeti(ctx, 1, i+1);
				arcan_vobj_id id = luaL_checkvid(ctx, -1, NULL);
				arcan_video_setzv(id, zv);
			lua_pop(ctx, 1);
		}
	}
	else
		arcan_fatal("order_image(), invalid argument (1) "
			"expected VID or indexed table of VIDs\n");

	LUA_ETRACE("order_image", NULL, 0);
}

static int maxorderimage(lua_State* ctx)
{
	LUA_TRACE("max_current_image_order");

	arcan_vobj_id rtgt = (arcan_vobj_id)
		luaL_optnumber(ctx, 1, ARCAN_VIDEO_WORLDID);

	if (rtgt != ARCAN_EID && rtgt != ARCAN_VIDEO_WORLDID)
		rtgt -= luactx.lua_vidbase;

	uint16_t rv = 0;
	arcan_video_maxorder(rtgt, &rv);
	lua_pushnumber(ctx, rv);
	LUA_ETRACE("max_current_image_order", NULL, 1);
}

static void massopacity(lua_State* ctx,
	float val, const char* caller)
{
	int time = luaL_optint(ctx, 3, 0);
	int interp = luaL_optint(ctx, 4, -1);

	bool use_interp = time > 0 &&
		interp >= 0 && interp < ARCAN_VINTER_ENDMARKER;

	int argtype = lua_type(ctx, 1);
	if (argtype == LUA_TNUMBER){
		arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
		arcan_video_objectopacity(id, val, time);
		if (use_interp)
			arcan_video_blendinterp(id, interp);
	}
	else if (argtype == LUA_TTABLE){
		int nelems = lua_rawlen(ctx, 1);

		for (size_t i = 0; i < nelems; i++){
			lua_rawgeti(ctx, 1, i+1);
			arcan_vobj_id id = luaL_checkvid(ctx, -1, NULL);
			arcan_video_objectopacity(id, val, time);
			if (use_interp)
				arcan_video_blendinterp(id, interp);
			lua_pop(ctx, 1);
		}
	}
	else
		arcan_fatal("%s(), invalid argument (1) "
			"expected VID or indexed table of VIDs\n", caller);
}

static int imageopacity(lua_State* ctx)
{
	LUA_TRACE("blend_image");

	float val = luaL_checknumber(ctx, 2);
	massopacity(ctx, val, "blend_image");

	LUA_ETRACE("blend_image", NULL, 0);
}

static int showimage(lua_State* ctx)
{
	LUA_TRACE("show_image");
	massopacity(ctx, 1.0, "show_image");
	LUA_ETRACE("show_image", NULL, 0);
}

static int hideimage(lua_State* ctx)
{
	LUA_TRACE("hide_image");
	massopacity(ctx, 0.0, "hide_image");
	LUA_ETRACE("hide_image", NULL, 0);
}

static int forceblend(lua_State* ctx)
{
	LUA_TRACE("force_image_blend");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	enum arcan_blendfunc mode = abs((int)luaL_optnumber(ctx, 2, BLEND_FORCE));

	if (mode == BLEND_FORCE || mode == BLEND_ADD ||
		mode == BLEND_MULTIPLY || mode == BLEND_NONE || mode == BLEND_NORMAL)
			arcan_video_forceblend(id, mode);

	LUA_ETRACE("force_image_blend", NULL, 0);
}

static int imagepersist(lua_State* ctx)
{
	LUA_TRACE("persist_image");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	lua_pushboolean(ctx, arcan_video_persistobject(id) == ARCAN_OK);
	LUA_ETRACE("persist_image", NULL, 1);
}

static int dropaudio(lua_State* ctx)
{
	LUA_TRACE("delete_audio");
	arcan_audio_stop( luaL_checkaid(ctx, 1) );
	LUA_ETRACE("delete_audio", NULL, 0);
}

static int gain(lua_State* ctx)
{
	LUA_TRACE("audio_gain");

	arcan_aobj_id id = luaL_checkaid(ctx, 1);

	if (lua_type(ctx, 2) != LUA_TNIL){
		float gain = luaL_checknumber(ctx, 2);
		uint16_t time = luaL_optint(ctx, 3, 0);
		arcan_audio_setgain(id, gain, time);
	}

	float dgain;
	if (ARCAN_OK == arcan_audio_getgain(id, &dgain)){
		lua_pushnumber(ctx, dgain);
		LUA_ETRACE("audio_gain", NULL, 1);
		return 1;
	}

	LUA_ETRACE("audio_gain", NULL, 0);
	return 0;
}

static int abufsz(lua_State* ctx)
{
	LUA_TRACE("audio_buffer_size");
	size_t new_sz = luaL_checknumber(ctx, 1);
	if (new_sz && new_sz < 1024){
		arcan_warning("audio_buffer_size(), input size too small, forcing 1024\n");
		new_sz = 1024;
	}
	else if (new_sz > 32768){
		arcan_warning("audio_buffer_size(), excessively large buffer, capping"
			"to 32k\n");
		new_sz = 32768;
	}
	else if (new_sz != 0 && new_sz %
		(sizeof(shmif_asample) * ARCAN_SHMIF_ACHANNELS)){
		arcan_warning("audio_buffer_size(%zu), useless size, "
			"growing to align with sample size\n");
		new_sz += new_sz % (sizeof(shmif_asample) * ARCAN_SHMIF_ACHANNELS);
	}

	lua_pushnumber(ctx, platform_fsrv_default_abufsize(new_sz));
	LUA_ETRACE("audio_buffer_size", NULL, 1);
}

static int playaudio(lua_State* ctx)
{
	LUA_TRACE("play_audio");

	arcan_aobj_id id = luaL_checkaid(ctx, 1);
	if (lua_isnumber(ctx, 2))
		arcan_audio_play(id, true, luaL_checknumber(ctx, 2));
	else
		arcan_audio_play(id, false, 0.0);

	LUA_ETRACE("play_audio", NULL, 0);
}

static int captureaudio(lua_State* ctx)
{
	LUA_TRACE("capture_audio");

	char** cptlist = arcan_audio_capturelist();
	const char* luach = luaL_checkstring(ctx, 1);

	bool match = false;
	while (*cptlist && !match)
		match = strcmp(*cptlist++, luach) == 0;

	if (match){
		lua_pushaid(ctx, arcan_audio_capturefeed(luach) );
		LUA_ETRACE("capture_audio", NULL, 1);
	}

	LUA_ETRACE("capture_audio", NULL, 0);
}

static int capturelist(lua_State* ctx)
{
	LUA_TRACE("list_audio_inputs");

	char** cptlist = arcan_audio_capturelist();
	int count = 1;

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	while(*cptlist){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, *cptlist);
		lua_rawset(ctx, top);
		cptlist++;
	}

	LUA_ETRACE("list_audio_inputs", NULL, 1);
}

static int loadasample(lua_State* ctx)
{
	LUA_TRACE("load_asample");

	const char* rname = luaL_checkstring(ctx, 1);
	char* resource = findresource(rname, DEFAULT_USERMASK);
	float gain = luaL_optnumber(ctx, 2, 1.0);
	arcan_aobj_id sid = arcan_audio_load_sample(resource, gain, NULL);
	arcan_mem_free(resource);
	lua_pushaid(ctx, sid);

	LUA_ETRACE("load_asample", NULL, 1);
}

static int buildshader(lua_State* ctx)
{
	LUA_TRACE("build_shader");

	const char* defvprg, (* deffprg);
	agp_shader_source(BASIC_2D, &defvprg, &deffprg);

	const char* vprog = luaL_optstring(ctx, 1, defvprg);
	const char* fprog = luaL_optstring(ctx, 2, deffprg);
	const char* label = luaL_checkstring(ctx, 3);

	agp_shader_id rv = agp_shader_build(label, NULL, vprog, fprog);
	lua_pushnumber(ctx, SHADER_INDEX(rv));

	LUA_ETRACE("build_shader", NULL, 1);
}

static int deleteshader(lua_State* ctx)
{
	LUA_TRACE("delete_shader");
	int sid = abs((int)luaL_checknumber(ctx, 1));
	lua_pushboolean(ctx, agp_shader_destroy(sid));
	LUA_ETRACE("delete_shader", NULL, 1);
}

static int sharestorage(lua_State* ctx)
{
	LUA_TRACE("image_sharestorage");

	arcan_vobj_id src = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id dst = luaL_checkvid(ctx, 2, NULL);

	arcan_errc rv = arcan_video_shareglstore(src, dst);
	lua_pushboolean(ctx, rv == ARCAN_OK);

	LUA_ETRACE("image_sharestorage", NULL, 1);
}

static int matchstorage(lua_State* ctx)
{
	LUA_TRACE("image_matchstorage");

	arcan_vobject* v1, (* v2);
	luaL_checkvid(ctx, 1, &v1);
	luaL_checkvid(ctx, 2, &v2);
	lua_pushboolean(ctx, v1->vstore == v2->vstore);

	LUA_ETRACE("image_matchstorage", NULL, 1);
}

static int cursorstorage(lua_State* ctx)
{
	LUA_TRACE("cursor_setstorage");
	arcan_vobj_id src = luaL_checkvid(ctx, 1, NULL);

	if (lua_type(ctx, 2) == LUA_TTABLE){
		if (lua_rawlen(ctx, -1) != 8){
			arcan_warning("cursor_setstorage(), too few elements in txco tables"
				"(expected 8, got %i)\n", (int) lua_rawlen(ctx, -1));
			return 0;
		}

		for(size_t i = 0; i < 8; i++){
			lua_rawgeti(ctx, -1, i+1);
			arcan_video_display.cursor_txcos[i] = lua_tonumber(ctx, -1);
			lua_pop(ctx, 1);
		}
	}

	arcan_video_cursorstore(src);
	LUA_ETRACE("cursor_setstorage", NULL, 0);
}

static int cursormove(lua_State* ctx)
{
	LUA_TRACE("move_cursor");
	acoord x = luaL_checknumber(ctx, 1);
	acoord y = luaL_checknumber(ctx, 2);
	bool clamp = luaL_optbnumber(ctx, 3, 0);

	struct monitor_mode mmode = platform_video_dimensions();

	if (clamp){
		x = x > mmode.width ? mmode.width : x;
		y = y > mmode.height ? mmode.height : y;
		x = x < 0 ? 0 : x;
		y = y < 0 ? 0 : y;
	}

	arcan_video_cursorpos(x, y, true);
	LUA_ETRACE("move_cursor", NULL, 0);
}

static int cursornudge(lua_State* ctx)
{
	LUA_TRACE("nudge_cursor");
	acoord x = luaL_checknumber(ctx, 1) + arcan_video_display.cursor.x;
	acoord y = luaL_checknumber(ctx, 2) + arcan_video_display.cursor.y;
	bool clamp = luaL_optbnumber(ctx, 3, 0);

	struct monitor_mode mmode = platform_video_dimensions();

	if (clamp){
		x = x > mmode.width ? mmode.width : x;
		y = y > mmode.height ? mmode.height : y;
		x = x < 0 ? 0 : x;
		y = y < 0 ? 0 : y;
	}

	arcan_video_cursorpos(x, y, true);

	LUA_ETRACE("nudge_cursor", NULL, 0);
}

static int cursorposition(lua_State* ctx)
{
	LUA_TRACE("cursor_position");
	lua_pushnumber(ctx, arcan_video_display.cursor.x);
	lua_pushnumber(ctx, arcan_video_display.cursor.y);
	LUA_ETRACE("cursor_position", NULL, 2);
}

static int cursorsize(lua_State* ctx)
{
	LUA_TRACE("resize_cursor");
	acoord w = luaL_checknumber(ctx, 1);
	acoord h = luaL_checknumber(ctx, 2);
	arcan_video_cursorsize(w, h);
	LUA_ETRACE("resize_cursor", NULL, 0);
}

static int imagestate(lua_State* ctx)
{
	LUA_TRACE("image_state");
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);

	vfunc_state* state = arcan_video_feedstate(vid);
	if (!state)
		lua_pushstring(ctx, "static");
	else
		switch(state->tag){
		case ARCAN_TAG_FRAMESERV:
			lua_pushstring(ctx, "frameserver");
		break;

		case ARCAN_TAG_3DOBJ:
			lua_pushstring(ctx, "3d object");
		break;

		case ARCAN_TAG_ASYNCIMGLD:
		case ARCAN_TAG_ASYNCIMGRD:
			lua_pushstring(ctx, "asynchronous state");
		break;

		case ARCAN_TAG_3DCAMERA:
			lua_pushstring(ctx, "3d camera");
		break;

		default:
			lua_pushstring(ctx, "unknown");
		}

	LUA_ETRACE("image_state", NULL, 1);
}

static int tagtransform(lua_State* ctx)
{
	LUA_TRACE("tag_image_transform");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	enum arcan_transform_mask mask = luaL_checknumber(ctx, 2);

	if (mask & ~MASK_TRANSFORMS){
		arcan_warning("tag_image_transform(), unknown mask- bits filtered.\n");
		mask &= MASK_TRANSFORMS;
	}

	intptr_t ref = find_lua_callback(ctx);

	arcan_video_tagtransform(id, ref, mask);

	LUA_ETRACE("tag_image_transform", NULL, 0);
}

static int setshader(lua_State* ctx)
{
	LUA_TRACE("image_shader");

	arcan_vobject* vobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);
	agp_shader_id oldshid = vobj->program;

		if (lua_gettop(ctx) > 1){
		agp_shader_id shid = lua_type(ctx, 2) == LUA_TSTRING ?
			agp_shader_lookup(luaL_checkstring(ctx, 2)) : luaL_checknumber(ctx, 2);

		if (ARCAN_OK != arcan_video_setprogram(id, shid))
			arcan_warning("arcan_video_setprogram(%d, %d) -- couldn't set shader,"
				"invalid vobj or shader id specified.\n", id, shid);
	}

	lua_pushnumber(ctx, oldshid);

	LUA_ETRACE("image_shader", NULL, 1);
}

static int setmeshshader(lua_State* ctx)
{
	LUA_TRACE("mesh_shader");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	agp_shader_id shid = lua_type(ctx, 2) == LUA_TSTRING ?
		agp_shader_lookup(luaL_checkstring(ctx, 2)) : luaL_checknumber(ctx, 2);

	unsigned slot = abs ((int)luaL_checknumber(ctx, 3) );

	arcan_3d_meshshader(id, shid, slot);

	LUA_ETRACE("mesh_shader", NULL, 0);
}

static int textdimensions(lua_State* ctx)
{
	LUA_TRACE("text_dimensions");

	size_t width = 0, height = 0, maxw = 0, maxh = 0;
	int vspacing = luaL_optint(ctx, 2, 0);
	int tspacing = luaL_optint(ctx, 2, 64);

	uint32_t sz;

	int type = lua_type(ctx, 1);
	if (type == LUA_TSTRING){
		const char* message = luaL_checkstring(ctx, 1);
		arcan_renderfun_renderfmtstr(message, ARCAN_EID,
			false, NULL, NULL,
			&width, &height, &sz, &maxw, &maxh, true
		);
	}
	else if (type == LUA_TTABLE){
		int nelems = lua_rawlen(ctx, 1);

		if (0 == nelems)
			goto out;

		char* messages[nelems + 1];
		for (size_t i = 0; i < nelems; i++){
			lua_rawgeti(ctx, 1, i+1);
			messages[i] = strdup(luaL_checkstring(ctx, -1));
			lua_pop(ctx, 1);
		}
		messages[nelems] = NULL;

/* note: the renderfmtstr_extended will free() on messages */
		arcan_renderfun_renderfmtstr_extended((const char**)messages,
			ARCAN_EID, false, NULL, NULL,
			&width, &height, &sz, &maxw, &maxh, true
		);
	}
	else
		arcan_fatal("text_dimensions(), invalid type for argument 1, "
			"accepted string or table\n");

out:
	lua_pushnumber(ctx, width);
	lua_pushnumber(ctx, height);

	LUA_ETRACE("text_dimensions", NULL, 2);
}

static int rendertext(lua_State* ctx)
{
	LUA_TRACE("render_text");
	arcan_vobj_id id = ARCAN_EID;

	int argpos = 1;

	int type = lua_type(ctx, 1);
	if (type == LUA_TNUMBER){
		id = luaL_checkvid(ctx, 1, NULL);
		argpos++;
	}

	type = lua_type(ctx, argpos);
	unsigned int nlines = 0;
	struct renderline_meta* lineheights = NULL;
	arcan_errc errc;

/* old non-escaped, dangerous on user-supplied unfiltered strings */
	if (type == LUA_TSTRING){
		char* message = strdup(luaL_checkstring(ctx, argpos));
		trace_allocation(ctx, "render_text", id);
		id = arcan_video_renderstring(id, (struct arcan_rstrarg){
			.multiple = false, .message = message},
			&nlines, &lineheights, &errc
		);
	}
/* % 2 == 0 entries are treated as formats, % 2 == 1 as regular */
	else if (type == LUA_TTABLE){
		int nelems = lua_rawlen(ctx, argpos);
		if (nelems == 0){
			arcan_warning("render_text(), passed empty table");
			return 0;
		}

		char** messages = arcan_alloc_mem(sizeof(char*) * (nelems + 1),
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);

		for (size_t i = 0; i < nelems; i++){
			lua_rawgeti(ctx, argpos, i+1);
			messages[i] = strdup(luaL_checkstring(ctx, -1));
			lua_pop(ctx, 1);
		}
		messages[nelems] = NULL;

		id = arcan_video_renderstring(id, (struct arcan_rstrarg){
			.multiple = true, .array = messages},
			&nlines, &lineheights, &errc);
	}
	else
		arcan_fatal("render_text(), expected string or table\n");

	lua_pushvid(ctx, id);
	lua_createtable(ctx, nlines, 0);
	int asc = 0;
	int height = 0;
	int top = lua_gettop(ctx);
	for (size_t i = 0; i < nlines; i++){
		lua_pushnumber(ctx, i + 1);
		lua_pushnumber(ctx, lineheights[i].ystart);
/* just grab any ascender */
		if (!asc && lineheights[i].ascent){
			asc = lineheights[i].ascent;
			height = lineheights[i].height;
		}

		lua_rawset(ctx, top);
	}

	if (lineheights)
		arcan_mem_free(lineheights);

	arcan_vobject* vobj = arcan_video_getobject(id);
	if (vobj){
		lua_pushnumber(ctx, vobj->origw);
		lua_pushnumber(ctx, height);
		lua_pushnumber(ctx, asc);
		LUA_ETRACE("render_text", NULL, 5);
	}

	LUA_ETRACE("render_text", NULL, 2);
}

static int scaletxcos(lua_State* ctx)
{
	LUA_TRACE("image_scale_txcos");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	float txs = luaL_checknumber(ctx, 2);
	float txt = luaL_checknumber(ctx, 3);

	arcan_video_scaletxcos(id, txs, txt);

	LUA_ETRACE("image_scale_txcos", NULL, 0);
}

static int settxcos_default(lua_State* ctx)
{
	LUA_TRACE("image_set_txcos_default");

	arcan_vobject* dst;
	luaL_checkvid(ctx, 1, &dst);
	bool mirror = luaL_optbnumber(ctx, 2, 0);

	if (!dst->txcos)
		dst->txcos = arcan_alloc_mem(sizeof(float)*8,
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_SIMD);

	if (dst->txcos){
		if (mirror)
			arcan_vint_mirrormapping(dst->txcos, 1.0, 1.0);
		else
			arcan_vint_defaultmapping(dst->txcos, 1.0, 1.0);
	}

	LUA_ETRACE("image_set_txcos_default", NULL, 0);
}

static int settxcos(lua_State* ctx)
{
	LUA_TRACE("image_set_txcos");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	float txcos[8];

	if (arcan_video_retrieve_mapping(id, txcos) == ARCAN_OK){
		luaL_checktype(ctx, 2, LUA_TTABLE);
		int ncords = lua_rawlen(ctx, -1);
		if (ncords < 8){
			arcan_warning("image_set_txcos(), Too few elements in txco tables"
				"(expected 8, got %i)\n", ncords);
			LUA_ETRACE("image_set_txcos", "bad input table", 0);
		}

		for (size_t i = 0; i < 8; i++){
			lua_rawgeti(ctx, -1, i+1);
			txcos[i] = lua_tonumber(ctx, -1);
			lua_pop(ctx, 1);
		}

		arcan_video_override_mapping(id, txcos);
	}

	LUA_ETRACE("image_set_txcos", NULL, 0);
}

static int gettxcos(lua_State* ctx)
{
	LUA_TRACE("image_get_txcos");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	int rv = 0;
	float txcos[8] = {0};

	if (arcan_video_retrieve_mapping(id, txcos) == ARCAN_OK){
		lua_createtable(ctx, 8, 0);
		int top = lua_gettop(ctx);

		for (size_t i = 0; i < 8; i++){
			lua_pushnumber(ctx, i + 1);
			lua_pushnumber(ctx, txcos[i]);
			lua_rawset(ctx, top);
		}

		rv = 1;
	}

	LUA_ETRACE("image_get_txcos", NULL, rv);
}

static int togglemask(lua_State* ctx)
{
	LUA_TRACE("image_mask_toggle");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	int val = abs((int)luaL_checknumber(ctx, 2));

	if ( (val & !(MASK_ALL)) == 0){
		enum arcan_transform_mask mask = arcan_video_getmask(id);
		mask ^= ~val;
		arcan_video_transformmask(id, mask);
	}

	return 0;
}

static int clearall(lua_State* ctx)
{
	LUA_TRACE("image_mask_clearall");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	if (id)
		arcan_video_transformmask(id, 0);

	LUA_ETRACE("image_mask_clearall", NULL, 0);
}

static char* maskstr(enum arcan_transform_mask mask)
{
	char maskstr[72] = "";

	if ( (mask & MASK_POSITION) > 0)
		strcat(maskstr, "position ");

	if ( (mask & MASK_SCALE) > 0)
		strcat(maskstr, "scale ");

	if ( (mask & MASK_OPACITY) > 0)
		strcat(maskstr, "opacity ");

	if ( (mask & MASK_LIVING) > 0)
		strcat(maskstr, "living ");

	if ( (mask & MASK_ORIENTATION) > 0)
		strcat(maskstr, "orientation ");

	if ( (mask & MASK_UNPICKABLE) > 0)
		strcat(maskstr, "unpickable ");

	if ( (mask & MASK_FRAMESET) > 0)
		strcat(maskstr, "frameset ");

	if ( (mask & MASK_MAPPING) > 0)
		strcat(maskstr, "mapping ");

	return strdup(maskstr);
}

static int clearmask(lua_State* ctx)
{
	LUA_TRACE("image_mask_clear");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	int val = abs((int)luaL_checknumber(ctx, 2));

	if ( (val & !(MASK_ALL)) == 0){
		enum arcan_transform_mask mask = arcan_video_getmask(id);
		mask &= ~val;
		arcan_video_transformmask(id, mask);
	}

	LUA_ETRACE("image_mask_clear", NULL, 0);
}

static int setmask(lua_State* ctx)
{
	LUA_TRACE("image_mask_set");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	enum arcan_transform_mask val = luaL_checknumber(ctx, 2);

	if ( (val & !(MASK_ALL)) == 0){
		enum arcan_transform_mask mask = arcan_video_getmask(id);
		mask |= val;
		arcan_video_transformmask(id, mask);
		LUA_ETRACE("image_mask_set", NULL, 0);
	}
	else{
		arcan_warning("Script Warning: image_mask_set(),"
			"	bad mask specified (%i)\n", val);
		LUA_ETRACE("image_mask_set", "bad mask", 0);
	}
}

static int clipon(lua_State* ctx)
{
	LUA_TRACE("image_clip_on");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	char clipm = luaL_optint(ctx, 2, ARCAN_CLIP_ON);

	arcan_video_setclip(id, clipm == ARCAN_CLIP_ON ? ARCAN_CLIP_ON :
		ARCAN_CLIP_SHALLOW);

	LUA_ETRACE("image_clip_on", NULL, 0);
}

static int clipoff(lua_State* ctx)
{
	LUA_TRACE("image_clip_off");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_video_setclip(id, ARCAN_CLIP_OFF);

	LUA_ETRACE("image_clip_off", NULL, 0);
}

static int pick(lua_State* ctx)
{
	LUA_TRACE("pick_items");

	int x = luaL_checkint(ctx, 1);
	int y = luaL_checkint(ctx, 2);
	bool reverse = luaL_optbnumber(ctx, 4, 0);
	size_t limit = luaL_optint(ctx, 3, 8);
	arcan_vobj_id res = (arcan_vobj_id)
		luaL_optnumber(ctx, 5, ARCAN_VIDEO_WORLDID);

	if (res != ARCAN_EID && res != ARCAN_VIDEO_WORLDID)
		res -= luactx.lua_vidbase;

	static arcan_vobj_id pickbuf[64];
	if (limit > 64)
		arcan_fatal("pick_items(), unreasonable pick "
			"buffer size (%d) requested.", limit);

	size_t count = reverse ?
		arcan_video_rpick(res, pickbuf, limit, x, y) :
		arcan_video_pick(res, pickbuf, limit, x, y);
	unsigned int ofs = 1;

	lua_createtable(ctx, count, 0);
	int top = lua_gettop(ctx);

	while (count--){
		lua_pushnumber(ctx, ofs);
		lua_pushvid(ctx, pickbuf[ofs-1]);
		lua_rawset(ctx, top);
		ofs++;
	}

	LUA_ETRACE("pick_items", NULL, 1);
}

static int hittest(lua_State* ctx)
{
	LUA_TRACE("image_hit");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	unsigned int x = luaL_checkint(ctx, 2);
	unsigned int y = luaL_checkint(ctx, 3);

	lua_pushboolean(ctx, arcan_video_hittest(id, x, y) != 0);

	LUA_ETRACE("image_hit", NULL, 1);
}

static int deleteimage(lua_State* ctx)
{
	LUA_TRACE("delete_image");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	double srcid = luaL_checknumber(ctx, 1);

#ifndef ARCAN_LWA
	if (id == ARCAN_VIDEO_WORLDID){
		arcan_video_disable_worldid();
		LUA_ETRACE("delete_image", NULL, 0);
	}
#endif

/* possibly long journey,
 * for a vid with a movie associated (or any feedfunc),
 * the feedfunc will be invoked with the cleanup cmd
 * which in the movie cause will trigger a full movie cleanup
 */
	arcan_errc rv = arcan_video_deleteobject(id);

	if (rv != ARCAN_OK)
		arcan_fatal("Tried to delete non-existing object (%.0lf=>%d)", srcid, id);

	LUA_ETRACE("delete_image", NULL, 0);
}

static int setlife(lua_State* ctx)
{
	LUA_TRACE("expire_image");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	int ttl = luaL_checkint(ctx, 2);

	if (ttl <= 0)
		ttl = 1;

	arcan_video_setlife(id, ttl);

	LUA_ETRACE("expire_image", NULL, 0);
}

/* to actually put this into effect, change value and pop the entire stack */
static int systemcontextsize(lua_State* ctx)
{
	LUA_TRACE("system_context_size");

	unsigned newlim = luaL_checkint(ctx, 1);

	if (newlim > 1 && newlim <= VITEM_CONTEXT_LIMIT)
		arcan_video_contextsize(newlim);
	else
		arcan_fatal("system_context_size(), "
			"invalid context size specified (%d)\n", newlim);

	LUA_ETRACE("system_context_size", NULL, 0);
}

static int subsys_reset(lua_State* ctx)
{
	LUA_TRACE("subsystem_reset");
	const char* subsys = luaL_checkstring(ctx, 1);
	if (strcmp(subsys, "video") == 0){
		int card = luaL_optnumber(ctx, 1, -1);
		int swap = luaL_optnumber(ctx, 1, 0);
		platform_video_reset(card, swap);
	}
	else
		arcan_fatal("unaccepted subsystem (%s), acceptable: video\n", subsys);

	LUA_ETRACE("subsystem_reset", NULL, 0);
}

static int syscollapse(lua_State* ctx)
{
	LUA_TRACE("system_collapse");
	const char* switch_appl = luaL_optstring(ctx, 1, NULL);

	if (switch_appl){
		if (strlen(switch_appl) == 0)
			arcan_fatal("system_collapse(), 0-length appl name not permitted.\n");

		for (const char* work = switch_appl; *work; work++)
			if (!isalnum(*work) && *work != '_')
				arcan_fatal("system_collapse(), only aZ_ are permitted in names.\n");

/* lua will free when we destroy the context */
		switch_appl = strdup(switch_appl);
		const char* errmsg;

/* we no longer have a context, the Lua specific error reporter should
 * not be used */
#undef arcan_fatal
		if (!arcan_verifyload_appl(switch_appl, &errmsg)){
			if (luactx.debug > 0)
				arcan_verify_namespaces(true);

			arcan_fatal("system_collapse(), "
				"failed to load appl (%s), reason: %s\n", switch_appl, errmsg);
		}
#define arcan_fatal(...) do { lua_rectrigger( __VA_ARGS__); } while(0)
	}

	longjmp(arcanmain_recover_state, luaL_optbnumber(ctx, 2, 0) ? 2 : 1);

	LUA_ETRACE("system_collapse", NULL, 0);
}

static int syssnap(lua_State* ctx)
{
	LUA_TRACE("system_snapshot");

	const char* instr = luaL_checkstring(ctx, 1);
	char* fname = findresource(instr, RESOURCE_APPL_TEMP);

	if (fname){
		arcan_warning("system_statesnap(), "
		"refuses to overwrite existing file (%s));\n", fname);
		arcan_mem_free(fname);

		LUA_ETRACE("system_snapshot", "file exists", 0);
	}

	fname = arcan_expand_resource(luaL_checkstring(ctx, 1), RESOURCE_APPL_TEMP);
	FILE* outf;

	if (fname && (outf = fopen(fname, "w+"))){
		arcan_lua_statesnap(outf, "", false);
		fclose(outf);
		LUA_ETRACE("system_snapshot", NULL, 0);
	}
	else{
		arcan_warning("system_statesnap(), "
			"couldn't open (%s) for writing.\n", instr);
		LUA_ETRACE("system_snapshot", NULL, 0);
	}
}

static int systemload(lua_State* ctx)
{
	LUA_TRACE("system_load");

	const char* instr = luaL_checkstring(ctx, 1);
	bool dieonfail = luaL_optbnumber(ctx, 2, 1);
	char* ext = strrchr(instr, '.');
	if (ext == NULL){
		if (dieonfail)
			arcan_fatal("system_load(), extension missing.");
		else
			arcan_warning("system_load(), extension missing.");
		return 0;
	}

	bool islua = strcmp(ext, ".lua") == 0;
	if (!islua
#ifndef DISABLE_MODULES
	&& strcmp(ext, OS_DYLIB_EXTENSION) != 0
#endif
	){
		if (dieonfail)
			arcan_fatal("system_load(), unsupported extension: %s\n", ext);
		else
			arcan_warning("system_load(), unsupported extension: %s\n", ext);
		return 0;
	}

/* countermeasure 1. can safely assume valid extension at this point */
#ifndef DISABLE_MODULES
	if (!islua){
/* strip the extension */
		*ext = '\0';

		size_t len = strlen(instr) + sizeof(OS_DYLIB_EXTENSION);
		char workbuf[len];
		snprintf(workbuf, len, "%s%s", instr, OS_DYLIB_EXTENSION);

/* countermeasure 2, MODULE_USERMASK namespace => RESOURCE_SYS_LIBS */
		char* fname = findresource(workbuf, MODULE_USERMASK);
		if (!fname){
			const char* msg = "Couldn't find required module: (%s)\n";
			if (dieonfail)
				arcan_fatal(msg, instr);
			else
				arcan_warning(msg, instr);
			return 0;
		}

/* countermeasure 3. fname is resolved to absolute path */
		void* dlh = dlopen(fname,
#ifdef DEBUG
			RTLD_NOW
#else
			RTLD_LAZY
#endif
		);
		if (!dlh){
			const char* msg = "Couldn't open (%s), error: (%s)\n";
			arcan_mem_free(fname);
			if (dieonfail)
				arcan_fatal(msg, fname, dlerror());
			else
				arcan_warning(msg, fname, dlerror());
			return 0;
		}
		arcan_mem_free(fname);

/* countermeasure 4. selected prototypes must exist and accept version */
		module_init_prototype initfn = dlsym(dlh, "arcan_module_init");
		if (!initfn){
			const char* msg = "Couldn't load module (%s), "
				"missing arcan_module_init symbol";

			if (dieonfail)
				arcan_fatal(msg, instr);
			else
				arcan_warning(msg, instr);

			dlclose(dlh);
			return 0;
		}

/* countermeasure 5. map into known table rather than global namespace */
		const luaL_Reg* resfuns = initfn(
			LUAAPI_VERSION_MAJOR, LUAAPI_VERSION_MINOR, LUA_VERSION_NUM);
		if (!resfuns){
			const char* msg = "Module initialization (%s) failed\n";
			if (dieonfail)
				arcan_fatal(msg, instr);
			else
				arcan_warning(msg, instr);
		}

/* countermeasure 6. push into own table/namespace and return it */
		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		while(resfuns->name){
			lua_pushstring(ctx, resfuns->name);
			lua_pushcfunction(ctx, resfuns->func);
			lua_rawset(ctx, top);
			resfuns++;
		}
		return 1;

/* now, code in dlh must be treated as trusted at the moment, with
 * 'lanes' support further down the road, we could fork + drop and map
 * into a lane to both sandbox and reduce work in main thread */
	}
#endif

	char* fname = findresource(instr, CAREFUL_USERMASK);
	int res = 0;

	if (fname){
		int rv = luaL_loadfile(ctx, fname);
		if (rv == 0)
			res = 1;
		else if (dieonfail)
			arcan_fatal("Error parsing lua script (%s)\n", instr);
	}
	else
		arcan_fatal("Invalid script specified for system_load(%s)\n", instr);

	arcan_mem_free(fname);

	LUA_ETRACE("system_load", NULL, res);
}

static int targetsuspend(lua_State* ctx)
{
	LUA_TRACE("suspend_target");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	bool rsusp = luaL_optbnumber(ctx, 2, 0);

	vfunc_state* state = arcan_video_feedstate(vid);

	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		arcan_warning("suspend_target(), "
			"referenced object is not connected to a frameserver.\n");
		LUA_ETRACE("suspend_target", "not a frameserver", 0);
	}
	arcan_frameserver* fsrv = state->ptr;

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_PAUSE
	};

	if (!rsusp)
		arcan_frameserver_pause(fsrv);

	platform_fsrv_pushevent(fsrv, &ev);
	LUA_ETRACE("suspend_target", NULL, 0);
}

static int targetresume(lua_State* ctx)
{
	LUA_TRACE("resume_target");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	bool rsusp = luaL_optbnumber(ctx, 2, 0);

	vfunc_state* state = arcan_video_feedstate(vid);
	arcan_frameserver* fsrv = state->ptr;

	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !fsrv){
		arcan_fatal("suspend_target(), "
			"referenced object not connected to a frameserver.\n");
	}

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_UNPAUSE
	};

	if (!rsusp)
		arcan_frameserver_resume(fsrv);

	platform_fsrv_pushevent(fsrv, &ev);

	LUA_ETRACE("resume_target", NULL, 0);
}

static bool is_special_res(const char* msg)
{
	return strncmp(msg, "device", 6) == 0 ||
		strncmp(msg, "stream", 6) == 0 ||
		strncmp(msg, "capture", 7) == 0;
}

static int launchavfeed(lua_State* ctx)
{
	LUA_TRACE("launch_avfeed");

/* early out if fsrv- support is disabled */
	if (!fsrv_ok){
		LUA_ETRACE("launch_avfeed", NULL, 0);
	}

	const char* argstr = luaL_optstring(ctx, 1, "");
	const char* modearg = "avfeed";
	if (argstr != NULL)
		modearg = luaL_optstring(ctx, 2, modearg);

	const char* modestr = arcan_frameserver_atypes();

/* the argstr can use the [ARCAN_] way of expanding namespaces */
	char* expbuf[2] = {strdup(argstr), NULL};
	arcan_expand_namespaces(expbuf);

/* only permit a certain set of build-time defined modes */
	if (strstr(modestr, modearg) == NULL){
		arcan_warning("launch_avfeed(), requested mode (%s) missing from "
			"detected and allowed frameserver archetypes (%s), rejected.\n",
			modearg, modestr);
		free(expbuf[0]);
		LUA_ETRACE("launch_avfeed", "invalid mode", 0);
	}

	intptr_t ref = find_lua_callback(ctx);

	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = modearg,
		.args.builtin.resource = expbuf[0]
	};

	if (strcmp(modearg, "terminal") == 0)
		args.preserve_env = true;

/* generate some kind of guid as the frameservers don't/shouldn't have
 * that idea themselves, it's just for tracking individual instances in
 * this case */
	struct arcan_frameserver* mvctx = platform_launch_fork(&args, ref);
	arcan_random((uint8_t*)mvctx->guid, 16);
/* internal so no need to free memarr */
	free(expbuf[1]);

	if (!mvctx){
		lua_pushvid(ctx, ARCAN_EID);
		lua_pushaid(ctx, ARCAN_EID);
		LUA_ETRACE("launch_aveed", "failed to launch/fork", 2);
	}

	trace_allocation(ctx, "launch_avfeed", mvctx->vid);
	arcan_video_objectopacity(mvctx->vid, 0.0, 0);
	lua_pushvid(ctx, mvctx->vid);
	lua_pushaid(ctx, mvctx->aid);

/* need to provide the locally generated guid so we have something to associate
 * the recovery with since the avfeed won't trigger a registered, ... event */
	size_t dsz;
	char* b64 = (char*) arcan_base64_encode(
		(uint8_t*)&mvctx->guid[0], 16, &dsz, 0);
		lua_pushstring(ctx, b64);
	arcan_mem_free(b64);

	LUA_ETRACE("launch_avfeed", NULL, 3);
}

static int loadmovie(lua_State* ctx)
{
	LUA_TRACE("load_movie");

	if (!fsrv_ok){
		LUA_ETRACE("load_movie", "frameservers build-time blocked", 0);
	}

	const char* farg = luaL_checkstring(ctx, 1);

	bool special = is_special_res(farg);
	char* fname = special ? strdup(farg) : findresource(farg, DEFAULT_USERMASK);
	intptr_t ref = (intptr_t) 0;

	const char* argstr = "";
	int cbind = 2;

	if (lua_type(ctx, 2) == LUA_TNUMBER){
		arcan_warning("load_movie(), second argument uses deprecated "
			"number argument type.\n");
		cbind++;
	}
	else if (lua_type(ctx, 2) == LUA_TSTRING){
		argstr = luaL_optstring(ctx, 2, "");
		cbind++;
	}

	if (lua_isfunction(ctx, cbind) && !lua_iscfunction(ctx, cbind)){
		lua_pushvalue(ctx, cbind);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	};

	size_t optlen = strlen(argstr);

	if (!fname){
		arcan_warning("loadmovie() -- unknown resource (%s)"
		"	specified.\n", fname);
		LUA_ETRACE("load_movie", "couldn't resolve resource", 0);
	}

	if (!special){
		size_t flen = strlen(fname);
		size_t fnlen = flen + optlen + 8;
		char msg[fnlen];
		msg[fnlen-1] = 0;

		colon_escape(fname);

		if (optlen > 0)
			snprintf(msg, fnlen-1, "%s:file=%s", argstr, fname);
		else
			snprintf(msg, fnlen-1, "file=%s", fname);

		fname = strdup(msg);
	}

	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = "decode",
		.args.builtin.resource = fname
	};

	arcan_vobj_id vid = ARCAN_EID;
	arcan_aobj_id aid = ARCAN_EID;

	struct arcan_frameserver* mvctx = platform_launch_fork(&args, ref);
	if (mvctx){
		arcan_video_objectopacity(mvctx->vid, 0.0, 0);
		vid = mvctx->vid;
		aid = mvctx->aid;
	}

	lua_pushvid(ctx, vid);
	lua_pushaid(ctx, aid);
	trace_allocation(ctx, "load_movie", mvctx->vid);
	arcan_mem_free(fname);

	LUA_ETRACE("load_movie", NULL, 2);
}

static int vr_setup(lua_State* ctx)
{
	LUA_TRACE("vr_setup");
	const char* opts = NULL;

	if (lua_type(ctx, 1) == LUA_TSTRING){
		opts = luaL_checkstring(ctx, 1);
	}

	intptr_t ref = find_lua_callback(ctx);
	if (ref == (intptr_t) LUA_NOREF){
		arcan_fatal("vr_setup(), no event callback handler provided\n");
	}

/* we can ignore the context- here since we run everything from the
 * callback and use it as a normal frameserver when it exposes new VIDs,
 * and those VIDs can be used for shutdown */
	lua_pushboolean(ctx,
		arcan_vr_setup(opts, arcan_event_defaultctx(), ref) != NULL);

	LUA_ETRACE("vr_setup", NULL, 1);
}

static int vr_maplimb(lua_State* ctx)
{
	LUA_TRACE("vr_map_limb");
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	if (!vobj || vobj->feed.state.tag != ARCAN_TAG_VR)
		LUA_ETRACE("vr_map_limb", "invalid map object type", 0);

	arcan_vobj_id vid = luaL_checkvid(ctx, 2, NULL);

	unsigned limb = luaL_checknumber(ctx, 3);

	bool pos = luaL_optbnumber(ctx, 4, true);
	bool or = luaL_optbnumber(ctx, 5, true);

	arcan_vr_maplimb(vobj->feed.state.ptr, limb, vid, pos, or);

	LUA_ETRACE("vr_map_limb", NULL, 0);
}

static int vr_getmeta(lua_State* ctx)
{
	LUA_TRACE("vr_metadata");
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	if (!vobj || vobj->feed.state.tag != ARCAN_TAG_VR)
		LUA_ETRACE("vr_metadata", "invalid source object type", 0);

	struct vr_meta md;
	if (ARCAN_OK != arcan_vr_displaydata(vobj->feed.state.ptr, &md))
		LUA_ETRACE("vr_metadata", "couldn't get metadata", 0);

	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	tblnum(ctx, "width", md.hres, top);
	tblnum(ctx, "height", md.vres, top);
	tblnum(ctx, "center", md.h_center, top);
	tblnum(ctx, "horizontal", md.h_size, top);
	tblnum(ctx, "vertical", md.v_size, top);
	tblnum(ctx, "left_fov", md.left_fov, top);
	tblnum(ctx, "right_fov", md.right_fov, top);
	tblnum(ctx, "left_ar", md.left_ar, top);
	tblnum(ctx, "right_ar", md.right_ar, top);
	tblnum(ctx, "hsep", md.hsep, top);
	tblnum(ctx, "vpos", md.vpos, top);
	tblnum(ctx, "lens_distance", md.lens_distance, top);
	tblnum(ctx, "eye_display", md.eye_display, top);
	tblnum(ctx, "ipd", md.ipd, top);

	lua_pushstring(ctx, "distortion");
	lua_createtable(ctx, 0, 4);
	int ttop = lua_gettop(ctx);
	for (size_t i = 0; i < 4; i++){
		lua_pushnumber(ctx, i+1);
		lua_pushnumber(ctx, md.distortion[i]);
		lua_rawset(ctx, ttop);
	}
	lua_rawset(ctx, top);

	lua_pushstring(ctx, "abberation");
	lua_createtable(ctx, 0, 4);
	ttop = lua_gettop(ctx);
	for (size_t i = 0; i < 4; i++){
		lua_pushnumber(ctx, i+1);
		lua_pushnumber(ctx, md.abberation[i]);
		lua_rawset(ctx, ttop);
	}
	lua_rawset(ctx, top);

	LUA_ETRACE("vr_metadata", NULL, 1);
}

static int n_leds(lua_State* ctx)
{
	LUA_TRACE("controller_leds");

	int id = luaL_optint(ctx, 1, -1);
	if (id == -1){
		uint64_t ccont = arcan_led_controllers();
		lua_pushnumber(ctx, log2(ccont));
		lua_pushnumber(ctx, (ccont & 0x00000000ffffffff) >> 00);
		lua_pushnumber(ctx, (ccont & 0xffffffff00000000) >> 32);
		LUA_ETRACE("controller_leds", NULL, 1);
	}

	struct led_capabilities cap = arcan_led_capabilities((uint8_t)id);

	lua_pushnumber(ctx, cap.nleds);
	lua_pushboolean(ctx, cap.variable_brightness);
	lua_pushboolean(ctx, cap.rgb);
	LUA_ETRACE("controller_leds", NULL, 3);
}

static int led_intensity(lua_State* ctx)
{
	LUA_TRACE("led_intensity");

	uint8_t id = luaL_checkint(ctx, 1);
	int16_t led = luaL_checkint(ctx, 2);
	uint8_t intensity = luaL_checkint(ctx, 3);

	lua_pushnumber(ctx,
		arcan_led_intensity(id, led, intensity));

	LUA_ETRACE("led_intensity", NULL, 1);
}

static int led_rgb(lua_State* ctx)
{
	LUA_TRACE("set_led_rgb");

	uint8_t id = luaL_checkint(ctx, 1);
	int16_t led = luaL_checkint(ctx, 2);
	uint8_t r = luaL_checkint(ctx, 3);
	uint8_t g = luaL_checkint(ctx, 4);
	uint8_t b = luaL_checkint(ctx, 5);
	bool buf = luaL_optbnumber(ctx, 6, false);

	lua_pushnumber(ctx, arcan_led_rgb(id, led, r, g, b, buf));
	LUA_ETRACE("set_led_rgb", NULL, 1);
}

static int setled(lua_State* ctx)
{
	LUA_TRACE("set_led");

	int id = luaL_checkint(ctx, 1);
	int num = luaL_checkint(ctx, 2);
	int state = luaL_optbnumber(ctx, 3, true) ? 255 : 0;
	lua_pushnumber(ctx, arcan_led_intensity(id, num, state));
	LUA_ETRACE("set_led", NULL, 1);
}

/* NOTE: a currently somewhat serious yet unhandled issue concerns what to do
 * with events fires from objects that no longer exist, e.g. the case with
 * events in the queue preceeding a push_context, pop_context,
 * the -- possibly -- safest option would be to completely flush event queues
 * between successful context pops, in such cases, it should be handled in the
 * Lua layer */
static int pushcontext(lua_State* ctx)
{
	LUA_TRACE("push_video_context");
/* make sure that we save one context for launch_external */

	if (arcan_video_nfreecontexts() > 1)
		lua_pushinteger(ctx, arcan_video_pushcontext());
	else
		lua_pushinteger(ctx, -1);

	LUA_ETRACE("push_video_context", NULL, 1);
}

static int popcontext_ext(lua_State* ctx)
{
	LUA_TRACE("storepop_video_context");
	arcan_vobj_id newid = ARCAN_EID;

	lua_pushinteger(ctx, arcan_video_nfreecontexts() > 1 ?
		arcan_video_extpopcontext(&newid) : -1);
	lua_pushvid(ctx, newid);

	LUA_ETRACE("storepop_video_context", NULL, 2);
}

static int pushcontext_ext(lua_State* ctx)
{
	LUA_TRACE("storepush_video_context");
	arcan_vobj_id newid = ARCAN_EID;

	lua_pushinteger(ctx, arcan_video_nfreecontexts() > 1 ?
		arcan_video_extpushcontext(&newid) : -1);
	lua_pushvid(ctx, newid);

	LUA_ETRACE("storepush_video_context", NULL, 2);
}

static int popcontext(lua_State* ctx)
{
	LUA_TRACE("pop_video_context");
	lua_pushinteger(ctx, arcan_video_popcontext());
	LUA_ETRACE("pop_video_context", NULL, 1);
}

static int contextusage(lua_State* ctx)
{
	LUA_TRACE("current_context_usage");

	unsigned usecount;
	lua_pushinteger(ctx, arcan_video_contextusage(&usecount));
	lua_pushinteger(ctx, usecount);

	LUA_ETRACE("current_context_usage", NULL, 2);
}

/*
 * trused -> untrused
 */
static void get_utf8(const char* instr, uint8_t dst[5])
{
	if (!instr){
		dst[0] = dst[1] = dst[2] = dst[3] = dst[4] = 0;
		return;
	}

	size_t len = strlen(instr);
	memcpy(dst, instr, len <= 4 ? len : 4);
}

static int targetmessage(lua_State* ctx)
{
	LUA_TRACE("message_target");
	int vidind, tblind;

/* same ordering issue as target_input, since this function was broken
 * out of it and _input still redirects here based on type */
	if (lua_type(ctx, 1) == LUA_TNUMBER){
		vidind = 1;
		tblind = 2;
	} else {
		tblind = 1;
		vidind = 2;
	}

	arcan_vobj_id vid = luaL_checkvid(ctx, vidind, NULL);
	vfunc_state* vstate = arcan_video_feedstate(vid);

	if (!vstate || vstate->tag != ARCAN_TAG_FRAMESERV){
		lua_pushnumber(ctx, -1);
		LUA_ETRACE("message_target", "dst not a frameserver", 1);
	}
	arcan_frameserver* fsrv = vstate->ptr;

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_MESSAGE
	};

	const char* msg = luaL_checkstring(ctx, tblind);

/* "strlen" + validate the entire message */
	uint32_t state = 0, codepoint = 0, len = 0;
	while(msg[len])
		if (UTF8_REJECT == utf8_decode(&state, &codepoint,(uint8_t)(msg[len++]))){
			lua_pushnumber(ctx, -1);
			LUA_ETRACE("message_target", "invalid utf-8", 1);
		}

	if (state != UTF8_ACCEPT){
		lua_pushnumber(ctx, -1);
		LUA_ETRACE("message_trarget", "truncated utf-8", 1);
	}

/* pack in multipart '\0' */
	size_t msgsz = COUNT_OF(ev.tgt.message) - 1;
	while (len > msgsz){
		size_t i, lastok = 0;
		state = 0;
/* search for the offset */
		for (i = 0; i < msgsz && i < len; i++){
			if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(msg[i])))
				lastok = i;
		}
/* rewind if we split on the wrong point */
		if (i != lastok)
			i = lastok;

/* copy into buffer and forward */
		memcpy(ev.tgt.message, msg, i);
		ev.tgt.message[i] = '\0';
		if (ARCAN_OK != platform_fsrv_pushevent(fsrv, &ev)){
			lua_pushnumber(ctx, len);
			arcan_warning("message truncation\n");
			LUA_ETRACE("message_target", "truncation", 1);
		}

/* and step forward in our buffer */
		len -= i;
		msg += i;
	}

	if (len){
		memcpy(ev.tgt.message, msg, len);
		ev.tgt.message[len] = '\0';
		if (ARCAN_OK != platform_fsrv_pushevent(fsrv, &ev)){
			lua_pushnumber(ctx, len);
			LUA_ETRACE("message_target", "truncation", 1);
		}
	}

	lua_pushnumber(ctx, 0);
	LUA_ETRACE("message_target", NULL, 1);
}

/* there is a slight API inconsistency here in that we had (iotbl, vid) in the
 * first few versions while other functions tend to lead with vid, which causes
 * some confusion. So we check whethere the table argument is first or second,
 * and extract accordingly, so both will work */
static int targetinput(lua_State* ctx)
{
	LUA_TRACE("target_input/input_target");
	int vidind, tblind;

/* swizzle if necessary */
	if (lua_type(ctx, 1) == LUA_TNUMBER){
		vidind = 1;
		tblind = 2;
	} else {
		tblind = 1;
		vidind = 2;
	}

	if (lua_type(ctx, tblind) == LUA_TSTRING)
		return targetmessage(ctx);

	arcan_vobj_id vid = luaL_checkvid(ctx, vidind, NULL);
	vfunc_state* vstate = arcan_video_feedstate(vid);
	if (!vstate || vstate->tag != ARCAN_TAG_FRAMESERV){
		lua_pushnumber(ctx, false);
		LUA_ETRACE("target_input/input_target", "dst not a frameserver", 1);
	}

	luaL_checktype(ctx, tblind, LUA_TTABLE);
	arcan_event ev = {.io.kind = 0, .category = EVENT_IO };

/* NOTE: there's no validation that the label actual match earlier labelhints
 * or, if the gesture flag is set, that it match the defined gestures */
	ev.io.flags = (intblbool(ctx, tblind, "gesture") * 0xff)&ARCAN_IOFL_GESTURE;
	const char* label = intblstr(ctx, tblind, "label");
	if (label){
		int ul = COUNT_OF(ev.io.label) - 1;
		char* dst = ev.io.label;

		while (*label != '\0' && ul--)
			*dst++ = *label++;
		*dst = '\0';
	}
	ev.io.pts = intblint(ctx, tblind, "pts");
	ev.io.devid = intblint(ctx, tblind, "devid");
	ev.io.subid = intblint(ctx, tblind, "subid");

/* The lookup here is complicated both due to the excessive input model
 * and due to legacy / backward compatibility. The approach is to first
 * grab the universal- required/optional field. Then figure out if this
 * should emulate a mouse device or not (if mouse-analog and devid == 0
 * it is safe to just update the mmio- in the shmif instead). Then scan
 * for boolean- flags for type and FALLBACK to string-compare */
	bool mouse = intblbool(ctx, tblind, "mouse");
	if (mouse)
		ev.io.devkind = EVENT_IDEVKIND_MOUSE;

	if (intblbool(ctx, tblind, "analog"))
		goto analog;

	if (intblbool(ctx, tblind, "touch"))
		goto touch;

	if (intblbool(ctx, tblind, "digital"))
		goto digital;

	const char* kindlbl = intblstr(ctx, tblind, "kind");
	if (kindlbl == NULL)
		goto kinderr;

	if ( strcmp( kindlbl, "analog") == 0 ){
analog:
		ev.io.kind = EVENT_IO_AXIS_MOVE;
		if (ev.io.devkind != EVENT_IDEVKIND_MOUSE)
			ev.io.devkind = EVENT_IDEVKIND_GAMEDEV;
		ev.io.input.analog.gotrel = intblbool(ctx, tblind, "relative");
		ev.io.datatype = EVENT_IDATATYPE_ANALOG;

/* sweep the samples subtable, add as many as present (or possible) */
		lua_getfield(ctx, tblind, "samples");
		if (lua_type(ctx, -1) != LUA_TTABLE){
			arcan_warning("target_input(), no samples provided for target input\n");
			lua_pushnumber(ctx, false);
			return 1;
		}

		size_t naxiss = lua_rawlen(ctx, -1);
		for (size_t i = 0; i < naxiss &&
				i < COUNT_OF(ev.io.input.analog.axisval); i++){
				lua_rawgeti(ctx, -1, i+1);
				ev.io.input.analog.axisval[i] = lua_tointeger(ctx, -1);
				lua_pop(ctx, 1);
		}
		ev.io.input.analog.nvalues = naxiss;
	}
	else if (strcmp(kindlbl, "touch") == 0){
touch:
		ev.io.kind = EVENT_IO_TOUCH;
		ev.io.devkind = EVENT_IDEVKIND_TOUCHDISP;
		ev.io.datatype = EVENT_IDATATYPE_TOUCH;
		ev.io.input.touch.active = intblint(ctx, tblind, "active");
		ev.io.input.touch.x = intblint(ctx, tblind, "x");
		ev.io.input.touch.y = intblint(ctx, tblind, "y");
		ev.io.input.touch.pressure = intblfloat(ctx, tblind, "pressure");
		ev.io.input.touch.size = intblfloat(ctx, tblind, "size");
	}
	else if (strcmp(kindlbl, "digital") == 0){
digital:
		if (intblbool(ctx, tblind, "translated")){
			ev.io.kind = EVENT_IO_BUTTON;
			ev.io.devkind = EVENT_IDEVKIND_KEYBOARD;
			ev.io.datatype = EVENT_IDATATYPE_TRANSLATED;
			ev.io.input.translated.active = intblbool(ctx, tblind, "active");
			ev.io.input.translated.scancode = intblint(ctx, tblind, "number");
			ev.io.input.translated.keysym = intblint(ctx, tblind, "keysym");
			ev.io.input.translated.modifiers = intblint(ctx, tblind,"modifiers");
			get_utf8(intblstr(ctx, tblind, "utf8"), ev.io.input.translated.utf8);
		}
		else {
			if (ev.io.devkind != EVENT_IDEVKIND_MOUSE)
				ev.io.devkind = EVENT_IDEVKIND_GAMEDEV;
			ev.io.datatype = EVENT_IDATATYPE_DIGITAL;
			ev.io.kind = EVENT_IO_BUTTON;
			ev.io.input.digital.active= intblbool(ctx, tblind, "active");
		}
	}
	else {
kinderr:
		arcan_warning("Script Warning: target_input(), unkown \"kind\""
			" field in table.\n");
		lua_pushnumber(ctx, false);
		return 1;
	}

	lua_pushnumber(ctx, ARCAN_OK ==
		platform_fsrv_pushevent( (arcan_frameserver*) vstate->ptr, &ev ));
	LUA_ETRACE("target_input/input_target", NULL, 1);
}

static const char* lookup_idatatype(int type)
{
	static const char* idatalut[] = {
		"analog",
		"digital",
		"translated",
		"touch"
	};

	if (type < 0 || type > COUNT_OF(idatalut))
		return NULL;

	return idatalut[type];
}

/*
 * assumes there's a table at the current top of the stack,
 * grab all the display modes available for a specific display
 * and add it to that table. Used by event handler for dynamic
 * display events and for video_displaymodes.
 */
static void push_displaymodes(lua_State* ctx, platform_display_id id)
{
	int dtop = lua_gettop(ctx);
	size_t mcount;
	struct monitor_mode* modes = platform_video_query_modes(id, &mcount);
	if (!modes)
		return;

	for (size_t j = 0; j < mcount; j++){
		lua_pushnumber(ctx, j + 1); /* index in previously existing table */
		lua_createtable(ctx, 0, 12);

		int jtop = lua_gettop(ctx);

		lua_pushstring(ctx, "cardid");
		lua_pushnumber(ctx, 0);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "displayid");
		lua_pushnumber(ctx, id);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "phy_width_mm");
		lua_pushnumber(ctx, modes[j].phy_width);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "phy_height_mm");
		lua_pushnumber(ctx, modes[j].phy_height);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "subpixel_layout");
		lua_pushstring(ctx, modes[j].subpixel ? modes[j].subpixel : "unknown");
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "dynamic");
		lua_pushboolean(ctx, modes[j].dynamic);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "primary");
		lua_pushboolean(ctx, modes[j].primary);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "modeid");
		lua_pushnumber(ctx, modes[j].id);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "width");
		lua_pushnumber(ctx, modes[j].width);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "height");
		lua_pushnumber(ctx, modes[j].height);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "refresh");
		lua_pushnumber(ctx, modes[j].refresh);
		lua_rawset(ctx, jtop);

		lua_pushstring(ctx, "depth");
		lua_pushnumber(ctx, modes[j].depth);
		lua_rawset(ctx, jtop);

		lua_rawset(ctx, dtop); /* add to previously existing table */
	}
}

static void display_reset(lua_State* ctx, arcan_event* ev)
{
/* special handling for LWA receiving DISPLAYHINT to resize or indicate that
 * the default font has changed. For DISPLAYHINT we default to run the builtin
 * autores.or a possible override */
#ifdef ARCAN_LWA
	if (ev->vid.source == -1){
		lua_getglobal(ctx, "VRES_AUTORES");
		if (!lua_isfunction(ctx, -1)){
			lua_pop(ctx, 1);
			platform_video_specify_mode(ev->vid.displayid, (struct monitor_mode){
			.width = ev->vid.width, .height = ev->vid.height});
		}
		else{
			lua_pushnumber(ctx, ev->vid.width);
			lua_pushnumber(ctx, ev->vid.height);
			lua_pushnumber(ctx, ev->vid.vppcm);
			lua_pushnumber(ctx, ev->vid.flags);
			lua_pushnumber(ctx, ev->vid.displayid);
			wraperr(ctx, lua_pcall(ctx, 5, 0, 0), "event loop: lwa-displayhint");
		}
	}
	else if (ev->vid.source == -2){
		lua_getglobal(ctx, "VRES_AUTOFONT");
		if (!lua_isfunction(ctx, -1))
			lua_pop(ctx, 1);
		else{
			lua_pushnumber(ctx, ev->vid.vppcm);
			lua_pushnumber(ctx, ev->vid.width);
			lua_pushnumber(ctx, ev->vid.displayid);
			wraperr(ctx, lua_pcall(ctx, 3, 0, 0), "event loop: lwa-autofont");
		}
	};
#else

	if (!grabapplfunction(ctx, "display_state", sizeof("display_state")-1))
		return;

	LUA_TRACE("_display_state (reset)");
	lua_pushstring(ctx, "reset");

	wraperr(ctx, lua_pcall(ctx, 1, 0, 0), "event loop: display state");
	LUA_TRACE("");
#endif
}

static void display_added(lua_State* ctx, arcan_event* ev)
{
	if (!grabapplfunction(ctx, "display_state", sizeof("display_state")-1))
		return;

	LUA_TRACE("_display_state (add)");
	lua_pushstring(ctx, "added");
	lua_pushnumber(ctx, ev->vid.displayid);

	lua_createtable(ctx, 0, 3);
	int top = lua_gettop(ctx);
	lua_pushstring(ctx, "ledctrl");
	lua_pushnumber(ctx, ev->vid.ledctrl);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "ledind");
	lua_pushnumber(ctx, ev->vid.ledid);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "card");
	lua_pushnumber(ctx, ev->vid.cardid);
	lua_rawset(ctx, top);

	wraperr(ctx, lua_pcall(ctx, 3, 0, 0), "event loop: display state");
	LUA_TRACE("");
}

static void display_changed(lua_State* ctx, arcan_event* ev)
{
	if (!grabapplfunction(ctx, "display_state", sizeof("display_state")-1))
		return;

	LUA_TRACE("_display_state (changed)");
	lua_pushstring(ctx, "changed");
	wraperr(ctx, lua_pcall(ctx, 1, 0, 0), "event loop: display state");
	LUA_TRACE("");
}

static void display_removed(lua_State* ctx, arcan_event* ev)
{
	if (!grabapplfunction(ctx, "display_state", sizeof("display_state")-1))
		return;

	LUA_TRACE("_display_state (remove)");
	lua_pushstring(ctx, "removed");
	lua_pushnumber(ctx, ev->vid.displayid);
	wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "event loop: display state");
	LUA_TRACE("");
}

static void do_preroll(lua_State* ctx, intptr_t ref,
	arcan_vobj_id vid, arcan_aobj_id aid)
{
	vfunc_state* state = arcan_video_feedstate(vid);
	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		arcan_warning("attempt to preroll a bad/non-fsrv backed vid\n");
		return;
	}
	arcan_frameserver* fsrv = state->ptr;

	if (ref != (intptr_t) LUA_NOREF){
		lua_rawgeti(ctx, LUA_REGISTRYINDEX, ref);
		lua_pushvid(ctx, vid);
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		tblstr(ctx, "kind", "preroll", top);
		tblstr(ctx, "segkind", fsrvtos(fsrv->segid), top);
		tblnum(ctx, "source_audio", aid, top);
		luactx.cb_source_tag = vid;
		wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "frameserver_event(preroll)");
		luactx.cb_source_kind = CB_SOURCE_PREROLL;
	}

	tgtevent(vid, (arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_ACTIVATE
	});
}

/*
 * need to intercept and redefine some of the target_ functions
 * to work for _lwa to arcan behavior
 */
#ifdef ARCAN_LWA

void arcan_lwa_subseg_ev(uintptr_t cb_tag, arcan_event* ev)
{
/*
 * translate / map events as per normal
 */
}

struct subseg_output;
bool platform_lwa_targetevent(struct subseg_output*, arcan_event* ev);
#endif
static bool tgtevent(arcan_vobj_id dst, arcan_event ev)
{
	vfunc_state* state = arcan_video_feedstate(dst);

	if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr){
		arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;
		return platform_fsrv_pushevent( fsrv, &ev ) == ARCAN_OK;
	}
#ifdef ARCAN_LWA
	else if (state && state->tag == ARCAN_TAG_LWA && state->ptr){
		return platform_lwa_targetevent(state->ptr, &ev);
	}
#endif

	return false;
}

static void push_view(lua_State* ctx, struct arcan_extevent* ev,
	struct arcan_frameserver* fsrv, int top)
{
	tblbool(ctx, "invisible", ev->viewport.invisible != 0, top);
	tblbool(ctx, "focus", ev->viewport.focus != 0, top);
	tblbool(ctx, "anchor_edge", ev->viewport.anchor_edge != 0, top);
	tblbool(ctx, "anchor_pos", ev->viewport.anchor_pos != 0, top);
	tblnum(ctx, "rel_order", ev->viewport.order, top);
	tblnum(ctx, "rel_x", ev->viewport.x, top);
	tblnum(ctx, "rel_y", ev->viewport.y, top);
	tblnum(ctx, "anchor_w", ev->viewport.w, top);
	tblnum(ctx, "anchor_h",ev->viewport.h, top);
	tblnum(ctx, "edge", ev->viewport.edge, top);

	lua_pushstring(ctx, "border");
	lua_createtable(ctx, 4, 0);
	int top2 = lua_gettop(ctx);
	for (size_t i = 0; i < 4; i++){
		lua_pushnumber(ctx, i+1);
		lua_pushnumber(ctx, ev->viewport.border[i]);
		lua_rawset(ctx, top2);
	}
	lua_rawset(ctx, top);

	uint32_t pid = ev->viewport.parent;
	tblnum(ctx, "parent", pid, top);
}

/*
 * the segment request is treated a little different,
 * we maintain a global state
 */
static void emit_segreq(
	lua_State* ctx, struct arcan_frameserver* parent, struct arcan_extevent* ev)
{
	luactx.last_segreq = ev;
	int top = lua_gettop(ctx);

	if (ev->segreq.kind > SEGID_DEBUG || ev->segreq.kind == 0)
		ev->segreq.kind == SEGID_UNKNOWN;

	tblstr(ctx, "kind", "segment_request", top);
	tblnum(ctx, "width", ev->segreq.width, top);
	tblnum(ctx, "height", ev->segreq.height, top);
	tblnum(ctx, "reqid", ev->segreq.id, top);
	tblnum(ctx, "xofs", ev->segreq.xofs, top);
	tblnum(ctx, "yofs", ev->segreq.yofs, top);
	tblnum(ctx, "parent", parent->cookie, top);
	tblstr(ctx, "segkind", fsrvtos(ev->segreq.kind), top);

	luactx.cb_source_tag = ev->source;
	luactx.cb_source_kind = CB_SOURCE_FRAMESERVER;
	wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "event_external");
	luactx.cb_source_kind = CB_SOURCE_NONE;

/* call into callback, if we have been consumed,
 * do nothing, otherwise a reject */
	if (luactx.last_segreq != NULL){
		arcan_event rev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_REQFAIL,
			.tgt.ioevs[0].iv = ev->segreq.id
		};

		tgtevent(ev->source, rev);
	}

	luactx.last_segreq = NULL;
}

static const char* limb_name(int num)
{
	switch(num){
	case PERSON : return "person";
	case NECK : return "neck";
	case L_EYE : return "eye-left";
	case R_EYE : return "eye-right";
	case L_SHOULDER : return "shoulder-left";
	case R_SHOULDER : return "shoulder-right";
	case L_ELBOW : return "elbow-left";
	case R_ELBOW : return "elbow-right";
	case L_WRIST : return "wrist-left";
	case R_WRIST : return "wrist-right";
	case L_THUMB_PROXIMAL : return "thumb-proximal-left";
	case L_THUMB_MIDDLE : return "thumb-middle-left";
	case L_THUMB_DISTAL : return "thumb-distal-left";
	case L_POINTER_PROXIMAL : return "pointer-proximal-left";
	case L_POINTER_MIDDLE : return "pointer-middle-left";
	case L_POINTER_DISTAL : return "pointer-distal-left";
	case L_MIDDLE_PROXIMAL : return "middle-proximal-left";
	case L_MIDDLE_MIDDLE : return "middle-middle-left";
	case L_MIDDLE_DISTAL : return "middle-distal-left";
	case L_RING_PROXIMAL : return "ring-proximal-left";
	case L_RING_MIDDLE : return "ring-middle-left";
	case L_RING_DISTAL : return "ring-distal-left";
	case L_PINKY_PROXIMAL : return "pinky-proximal-left";
	case L_PINKY_MIDDLE : return "pinky-middle-left";
	case L_PINKY_DISTAL : return "pinky-distal-left";
	case R_THUMB_PROXIMAL : return "thumb-proximal-right";
	case R_THUMB_MIDDLE : return "thumb-middle-right";
	case R_THUMB_DISTAL : return "thumb-distal-right";
	case R_POINTER_PROXIMAL : return "pointer-proximal-right";
	case R_POINTER_MIDDLE : return "pointer-middle-right";
	case R_POINTER_DISTAL : return "pointer-distal-right";
	case R_MIDDLE_PROXIMAL : return "middle-proximal-right";
	case R_MIDDLE_MIDDLE : return "middle-middle-right";
	case R_MIDDLE_DISTAL : return "middle-distal-right";
	case R_RING_PROXIMAL : return "ring-proximal-right";
	case R_RING_MIDDLE : return "ring-middle-right";
	case R_RING_DISTAL : return "ring-distal-right";
	case R_PINKY_PROXIMAL : return "pinky-proximal-right";
	case R_PINKY_MIDDLE : return "pinky-middle-right";
	case R_PINKY_DISTAL : return "pinky-distal-right";
	case L_HIP : return "hip-left";
	case R_HIP : return "hip-right";
	case L_KNEE : return "knee-left";
	case R_KNEE : return "knee-right";
	case L_ANKLE : return "ankle-left";
	case R_ANKLE : return "ankle-right";
	case L_TOOL : return "tool-left";
	case R_TOOL : return "tool-right";
	default: return "broken";
	}
}

static const char* kindstr(int num)
{
	switch(num){
	case EVENT_IDEVKIND_KEYBOARD: return "keyboard";
	case EVENT_IDEVKIND_MOUSE: return "mouse";
	case EVENT_IDEVKIND_GAMEDEV: return "game";
	case EVENT_IDEVKIND_TOUCHDISP: return "touch";
	case EVENT_IDEVKIND_LEDCTRL: return "led";
	default:
		return "broken";
	}
}

static const char* domain_str(int num)
{
	switch(num){
	case 0:	return "platform"; break;
	case 1: return "led"; break;
	default:
	return "unknown-report";
	break;
	}
}

/*
 * emit input() call based on a arcan_event, uses a separate format and
 * translation to make it easier for the user to modify. This is a rather ugly
 * and costly step in the whole chain, planned to switch into a more optimized
 * less string- damaged approach around the hardening stage.
 */
#define MSGBUF_UTF8(X) slim_utf8_push(msgbuf, COUNT_OF((X))-1, (char*)(X))
#define FLTPUSH(X,Y,Z) fltpush(msgbuf, COUNT_OF((X))-1, (char*)((X)), Y, Z)
void arcan_lua_pushevent(lua_State* ctx, arcan_event* ev)
{
	bool adopt_check = false;
	char msgbuf[sizeof(arcan_event)+1];

	if (ev->category == EVENT_IO && grabapplfunction(ctx, "input", 5)){
		int top = funtable(ctx, ev->io.kind);

		lua_pushstring(ctx, "kind");
		if (ev->io.label[0] && ev->io.kind != EVENT_IO_STATUS &&
			ev->io.label[COUNT_OF(ev->io.label)-1] == '\0'){
			tblstr(ctx, "label", ev->io.label, top);
		}

		switch (ev->io.kind){
		case EVENT_IO_TOUCH:
			lua_pushstring(ctx, "touch");
			lua_rawset(ctx, top);

			tblbool(ctx, "touch", true, top);
			tblnum(ctx, "devid", ev->io.devid, top);
			tblnum(ctx, "subid", ev->io.subid, top);
			tblnum(ctx, "pressure", ev->io.input.touch.pressure, top);
			tblbool(ctx, "active", ev->io.input.touch.active, top);
			tblnum(ctx, "size", ev->io.input.touch.size, top);
			tblnum(ctx, "x", ev->io.input.touch.x, top);
			tblnum(ctx, "y", ev->io.input.touch.y, top);
		break;

		case EVENT_IO_STATUS:{
			const char* lbl = platform_event_devlabel(ev->io.devid);
			lua_pushstring(ctx, "status");
			lua_rawset(ctx, top);
			tblbool(ctx, "status", true, top);
			tblnum(ctx, "devid", ev->io.devid, top);
			tblnum(ctx, "subid", ev->io.subid, top);
			if (lbl)
				tblstr(ctx, "extlabel", lbl, top);

			tblstr(ctx, "devkind", kindstr(ev->io.input.status.devkind), top);
			tblstr(ctx, "label", ev->io.label, top);
			tblnum(ctx, "devref", ev->io.input.status.devref, top);
			tblstr(ctx, "domain", domain_str(ev->io.input.status.domain), top);
			tblstr(ctx, "action", (ev->io.input.status.action == EVENT_IDEV_ADDED ?
				"added" : (ev->io.input.status.action == EVENT_IDEV_REMOVED ?
					"removed" : "blocked")), top);
		}
		break;

		case EVENT_IO_AXIS_MOVE:
			lua_pushstring(ctx, "analog");
			lua_rawset(ctx, top);
			if (ev->io.devkind == EVENT_IDEVKIND_MOUSE){
				tblbool(ctx, "mouse", true, top);
				tblstr(ctx, "source", "mouse", top);
			}
			else
				tblstr(ctx, "source", "joystick", top);

			tblnum(ctx, "devid", ev->io.devid, top);
			tblnum(ctx, "subid", ev->io.subid, top);
			tblbool(ctx, "active", true, top);
			tblbool(ctx, "analog", true, top);
			tblbool(ctx, "relative", ev->io.input.analog.gotrel,top);

			lua_pushstring(ctx, "samples");
			lua_createtable(ctx, ev->io.input.analog.nvalues, 0);
				int top2 = lua_gettop(ctx);
				for (size_t i = 0; i < ev->io.input.analog.nvalues; i++){
					lua_pushnumber(ctx, i + 1);
					lua_pushnumber(ctx, ev->io.input.analog.axisval[i]);
					lua_rawset(ctx, top2);
				}
			lua_rawset(ctx, top);
		break;

		case EVENT_IO_BUTTON:
			lua_pushstring(ctx, "digital");
			lua_rawset(ctx, top);
			tblbool(ctx, "digital", true, top);

			if (ev->io.devkind == EVENT_IDEVKIND_KEYBOARD){
				tblbool(ctx, "translated", true, top);
				tblnum(ctx, "number", ev->io.input.translated.scancode, top);
				tblnum(ctx, "keysym", ev->io.input.translated.keysym, top);
				tblnum(ctx, "modifiers", ev->io.input.translated.modifiers, top);
				tblnum(ctx, "devid", ev->io.devid, top);
				tblnum(ctx, "subid", ev->io.subid, top);
				tblstr(ctx, "utf8", (char*)ev->io.input.translated.utf8, top);
				tblbool(ctx, "active", ev->io.input.translated.active, top);
				tblstr(ctx, "device", "translated", top);
				tblbool(ctx, "keyboard", true, top);
			}
			else if (ev->io.devkind == EVENT_IDEVKIND_MOUSE ||
				ev->io.devkind == EVENT_IDEVKIND_GAMEDEV){
				if (ev->io.devkind == EVENT_IDEVKIND_MOUSE){
					tblbool(ctx, "mouse", true, top);
					tblstr(ctx, "source", "mouse", top);
				}
				else {
					tblbool(ctx, "joystick", true, top);
					tblstr(ctx, "source", "joystick", top);
				}
				tblbool(ctx, "translated", false, top);
				tblnum(ctx, "devid", ev->io.devid, top);
				tblnum(ctx, "subid", ev->io.subid, top);
 				tblbool(ctx, "active", ev->io.input.digital.active, top);
			}
			else;
		break;

		default:
			lua_pushstring(ctx, "unknown");
			lua_rawset(ctx, top);
			arcan_warning("Engine -> Script: "
				"ignoring IO event: %i\n",ev->io.kind);
		}

		wraperr(ctx, lua_pcall(ctx, 1, 0, 0), "push event( input )");
	}
	else if (ev->category == EVENT_NET){
		arcan_vobject* vobj = arcan_video_getobject(ev->net.source);
		if (!vobj || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			return;

		arcan_frameserver* fsrv = vobj ? vobj->feed.state.ptr : NULL;

		if (fsrv && fsrv->tag){
			intptr_t dst_cb = fsrv->tag;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
			lua_pushvid(ctx, ev->net.source);

			lua_newtable(ctx);
			int top = lua_gettop(ctx);

			switch (ev->net.kind){
			case EVENT_NET_CONNECTED:
				tblstr(ctx, "kind", "connected", top);
				tblnum(ctx, "id", ev->net.connid, top);
				tblstr(ctx, "host", ev->net.host.addr, top);
			break;

			case EVENT_NET_DISCONNECTED:
				tblstr(ctx, "kind", "disconnected", top);
				tblnum(ctx, "id", ev->net.connid, top);
				tblstr(ctx, "host", ev->net.host.addr, top);
			break;

			case EVENT_NET_NORESPONSE:
				tblstr(ctx, "kind", "noresponse", top);
				tblstr(ctx, "host", ev->net.host.addr, top);
			break;

			case EVENT_NET_CUSTOMMSG:
				tblstr(ctx, "kind", "message", top);
				ev->net.message[ sizeof(ev->net.message) - 1] = 0;
				tblstr(ctx, "message", ev->net.message, top);
				tblnum(ctx, "id", ev->net.connid, top);
			break;

			case EVENT_NET_DISCOVERED:
				tblstr(ctx, "kind", "discovered", top);
				tblstr(ctx, "address", ev->net.host.addr, top);
				tblstr(ctx, "ident", ev->net.host.ident, top);
				size_t outl;
				uint8_t* strkey = arcan_base64_encode(
					(const uint8_t*) ev->net.host.key,
					COUNT_OF(ev->net.host.key),
					&outl, ARCAN_MEM_SENSITIVE | ARCAN_MEM_NONFATAL
				);
				if (strkey){
					tblstr(ctx, "key", (const char*) strkey, top);
					free(strkey);
				}
			break;

			case EVENT_NET_INPUTEVENT:
				arcan_warning("pushevent(net_inputevent_not_handled )\n");
			break;

			default:
				arcan_warning("pushevent( net_unknown %d )\n", ev->net.kind);
			}

			luactx.cb_source_tag  = ev->ext.source;
			luactx.cb_source_kind = CB_SOURCE_FRAMESERVER;
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "event_net");

			luactx.cb_source_kind = CB_SOURCE_NONE;
		}

	}
	else if (ev->category == EVENT_EXTERNAL){
		bool preroll = false;
/* need to jump through a few hoops to get hold of the possible callback */
		arcan_vobject* vobj = arcan_video_getobject(ev->ext.source);
		if (!vobj || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
			return;
		}

		int reset = lua_gettop(ctx);
		arcan_frameserver* fsrv = vobj->feed.state.ptr;
		if (fsrv->tag == LUA_NOREF){
			return;
		}
		intptr_t dst_cb = fsrv->tag;
		lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
		lua_pushvid(ctx, ev->ext.source);

		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		switch (ev->ext.kind){
		case EVENT_EXTERNAL_IDENT:
			tblstr(ctx, "kind", "ident", top);
			MSGBUF_UTF8(ev->ext.message.data);
			tblstr(ctx, "message", msgbuf, top);
		break;
		case EVENT_EXTERNAL_COREOPT:
			tblstr(ctx, "kind", "coreopt", top);
			tblnum(ctx, "slot", ev->ext.coreopt.index, top);
			MSGBUF_UTF8(ev->ext.message.data);
			tblstr(ctx, "argument", msgbuf, top);
			if (ev->ext.coreopt.type == 0)
				tblstr(ctx, "type", "key", top);
			else if (ev->ext.coreopt.type == 1)
				tblstr(ctx, "type", "description", top);
			else if (ev->ext.coreopt.type == 2)
				tblstr(ctx, "type", "value", top);
			else if (ev->ext.coreopt.type == 3)
				tblstr(ctx, "type", "current", top);
			else {
				lua_settop(ctx, reset);
				return;
			}
		break;
		case EVENT_EXTERNAL_CLOCKREQ:
/* check frameserver flags and see if we are set to autoclock, then only
 * forward the once events and have others just update the frameserver
 * statetable */
			tblstr(ctx, "kind", "clock", top);
			tblbool(ctx, "dynamic", ev->ext.clock.dynamic, top);
			tblbool(ctx, "once", ev->ext.clock.once, top);
			tblnum(ctx, "value", ev->ext.clock.rate, top);
			if (ev->ext.clock.once)
				tblnum(ctx, "id", ev->ext.clock.id, top);
		break;
		case EVENT_EXTERNAL_CONTENT:
			tblstr(ctx, "kind", "content_state", top);
			tblnum(ctx, "rel_x", (float)ev->ext.content.x_pos, top);
			tblnum(ctx, "rel_y", (float)ev->ext.content.y_pos, top);
			tblnum(ctx, "x_size", (float)ev->ext.content.x_sz, top);
			tblnum(ctx, "y_size", (float)ev->ext.content.y_sz, top);
		break;
		case EVENT_EXTERNAL_VIEWPORT:
			tblstr(ctx, "kind", "viewport", top);
			push_view(ctx, &ev->ext, fsrv, top);
		break;
		case EVENT_EXTERNAL_CURSORHINT:
			FLTPUSH(ev->ext.message.data, flt_alpha, '?');
			tblstr(ctx, "cursor", msgbuf, top);
			tblstr(ctx, "kind", "cursorhint", top);
		break;
		case EVENT_EXTERNAL_ALERT:
			tblstr(ctx, "kind", "alert", top);
			if (0)
		case EVENT_EXTERNAL_MESSAGE:
				tblstr(ctx, "kind", "message", top);
			MSGBUF_UTF8(ev->ext.message.data);
			tblbool(ctx, "multipart", ev->ext.message.multipart != 0, top);
			tblstr(ctx, "message", msgbuf, top);
		break;
		case EVENT_EXTERNAL_FAILURE:
			tblstr(ctx, "kind", "failure", top);
			MSGBUF_UTF8(ev->ext.message.data);
			tblstr(ctx, "message", msgbuf, top);
		break;
		case EVENT_EXTERNAL_FRAMESTATUS:
			tblstr(ctx, "kind", "framestatus", top);
			tblnum(ctx, "frame", ev->ext.framestatus.framenumber, top);
			tblnum(ctx, "pts", ev->ext.framestatus.pts, top);
			tblnum(ctx, "acquired", ev->ext.framestatus.acquired, top);
			tblnum(ctx, "fhint", ev->ext.framestatus.fhint, top);
		break;
		case EVENT_EXTERNAL_STREAMINFO:
			FLTPUSH(ev->ext.streaminf.langid, flt_Alpha, '?');
			tblstr(ctx, "kind", "streaminfo", top);
			tblstr(ctx, "lang", msgbuf, top);
			tblnum(ctx, "streamid", ev->ext.streaminf.streamid, top);
			tblstr(ctx, "type",
				streamtype(ev->ext.streaminf.datakind),top);
		break;
		case EVENT_EXTERNAL_STREAMSTATUS:
			tblstr(ctx, "kind", "streamstatus", top);
			FLTPUSH(ev->ext.streamstat.timestr, flt_num, '?');
			tblstr(ctx, "ctime", msgbuf, top);
			FLTPUSH(ev->ext.streamstat.timelim, flt_num, '?');
			tblstr(ctx, "endtime", msgbuf, top);
			tblnum(ctx,"completion",ev->ext.streamstat.completion,top);
			tblnum(ctx, "frameno", ev->ext.streamstat.frameno, top);
			tblnum(ctx,"streaming",
				ev->ext.streamstat.streaming!=0,top);
		break;
		case EVENT_EXTERNAL_CURSORINPUT:
			tblstr(ctx, "kind", "cursor_input", top);
			tblnum(ctx, "id", ev->ext.cursor.id, top);
			tblnum(ctx, "x", ev->ext.cursor.x, top);
			tblnum(ctx, "y", ev->ext.cursor.y, top);
			tblbool(ctx, "button_1", ev->ext.cursor.buttons[0], top);
			tblbool(ctx, "button_2", ev->ext.cursor.buttons[1], top);
			tblbool(ctx, "button_3", ev->ext.cursor.buttons[2], top);
			tblbool(ctx, "button_4", ev->ext.cursor.buttons[3], top);
			tblbool(ctx, "button_5", ev->ext.cursor.buttons[4], top);
		break;

		case EVENT_EXTERNAL_KEYINPUT:
			tblstr(ctx, "kind", "key_input", top);
			tblnum(ctx, "id", ev->ext.cursor.id, top);
			tblnum(ctx, "keysym", ev->ext.key.keysym, top);
			tblbool(ctx, "active", ev->ext.key.active, top);
		break;

/* special semantics for segreq */
		case EVENT_EXTERNAL_SEGREQ:
			return emit_segreq(ctx, fsrv, &ev->ext);
		break;
		case EVENT_EXTERNAL_LABELHINT:{
			const char* idt = lookup_idatatype(ev->ext.labelhint.idatatype);
			if (!idt){
				lua_settop(ctx, reset);
				return;
			}
			MSGBUF_UTF8(ev->ext.labelhint.descr);
			tblstr(ctx, "description", msgbuf, top);
			tblstr(ctx, "kind", "input_label", top);
			FLTPUSH(ev->ext.labelhint.label, flt_Alphanum, '?');
			tblstr(ctx, "labelhint", msgbuf, top);
			tblnum(ctx, "initial", ev->ext.labelhint.initial, top);
			tblstr(ctx, "datatype", idt, top);
			tblnum(ctx, "modifiers", ev->ext.labelhint.modifiers, top);
		}
		break;
		case EVENT_EXTERNAL_BCHUNKSTATE:
			tblstr(ctx, "kind", "bchunkstate", top);
			tblbool(ctx, "hint", ev->ext.bchunk.hint != 0, top);
			tblnum(ctx, "size", ev->ext.bchunk.size, top);
			tblbool(ctx, "input", ev->ext.bchunk.input, top);
			tblbool(ctx, "stream", ev->ext.bchunk.stream, top);
			if (ev->ext.bchunk.extensions[0] == 0)
				tblbool(ctx, "disable", true, top);
			else if (ev->ext.bchunk.extensions[0] == '*')
				tblbool(ctx, "wildcard", true, top);
			else{
				FLTPUSH(ev->ext.bchunk.extensions, flt_chunkfn, '\0');
				tblstr(ctx, "extensions", msgbuf, top);
			}
		break;
		case EVENT_EXTERNAL_STATESIZE:
			tblstr(ctx, "kind", "state_size", top);
			tblnum(ctx, "state_size", ev->ext.stateinf.size, top);
			tblnum(ctx, "typeid", ev->ext.stateinf.type, top);
		break;
		case EVENT_EXTERNAL_REGISTER:{
/* prevent switching types */
			int id = ev->ext.registr.kind;
			if (fsrv->segid != SEGID_UNKNOWN &&
				ev->ext.registr.kind != fsrv->segid){
				id = ev->ext.registr.kind = fsrv->segid;
			}
			else if (id == SEGID_NETWORK_CLIENT || id == SEGID_NETWORK_SERVER){
				arcan_warning("client (%d) attempted to register a reserved (%d) "
					"type which is not permitted.\n", fsrv->segid, id);
				lua_settop(ctx, reset);
				return;
			}
/* update and mark for pre-roll unless protected */
			if (fsrv->segid == SEGID_UNKNOWN){
				fsrv->segid = id;
				preroll = true;
			}
			tblstr(ctx, "kind", "registered", top);
			tblstr(ctx, "segkind", fsrvtos(ev->ext.registr.kind), top);
			MSGBUF_UTF8(ev->ext.registr.title);
			snprintf(fsrv->title, COUNT_OF(fsrv->title), "%s", msgbuf);
			tblstr(ctx, "title", msgbuf, top);

			size_t dsz;
			char* b64 = (char*) arcan_base64_encode(
				(uint8_t*)&ev->ext.registr.guid[0], 16, &dsz, 0);
			tblstr(ctx, "guid", b64, top);
			arcan_mem_free(b64);
		}
		break;
		default:
			tblstr(ctx, "kind", "unknown", top);
			tblnum(ctx, "kind_num", ev->ext.kind, top);
		}

		luactx.cb_source_tag  = ev->ext.source;
		luactx.cb_source_kind = CB_SOURCE_FRAMESERVER;
		wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "event_external");
		luactx.cb_source_kind = CB_SOURCE_NONE;
/* special: external connection + connected->registered sequence finished */
		if (preroll)
			do_preroll(ctx, fsrv->tag, ev->ext.source, fsrv->aid);
	}
	else if (ev->category == EVENT_FSRV){
		arcan_vobject* vobj = arcan_video_getobject(ev->fsrv.video);

/* this can happen if the frameserver has died and been enqueued but
 * delete_image was called in between, in that case, we still want tod drop the
 * reference. */
		if (!vobj){
			if (ev->fsrv.otag != LUA_NOREF)
				luaL_unref(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
			return;
		}

/* the backing frameserver is already free:d at this point */
		if (ev->fsrv.kind == EVENT_FSRV_TERMINATED){
			if (ev->fsrv.otag == LUA_NOREF)
				return;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
			lua_pushvid(ctx, ev->fsrv.video);
			lua_newtable(ctx);
			int top = lua_gettop(ctx);
			tblstr(ctx, "kind", "terminated", top);
			MSGBUF_UTF8(ev->fsrv.message);
			tblstr(ctx, "last_words", msgbuf, top);
			luactx.cb_source_kind = CB_SOURCE_FRAMESERVER;
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "frameserver_event");
			luactx.cb_source_kind = CB_SOURCE_NONE;
			luaL_unref(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
			return;
		}

/*
 * Special case, VR inherits some properties from frameserver,
 * but masks / shields a lot of the default eventloop
 */
		if (vobj->feed.state.tag == ARCAN_TAG_VR){
			if (ev->fsrv.otag == LUA_NOREF)
				return;

			lua_rawgeti(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
			lua_pushvid(ctx, ev->fsrv.video);
			lua_newtable(ctx);
			int top = lua_gettop(ctx);
			if (ev->fsrv.kind == EVENT_FSRV_ADDVRLIMB){
				tblstr(ctx, "kind", "limb_added", top);
				tblnum(ctx, "id",  ev->fsrv.limb, top);
				tblstr(ctx, "name", limb_name(ev->fsrv.limb), top);
			}
			else{
				tblstr(ctx, "kind", "limb_lost", top);
				tblnum(ctx, "id", ev->fsrv.limb, top);
				tblstr(ctx, "name", limb_name(ev->fsrv.limb), top);
			}
			luactx.cb_source_kind = CB_SOURCE_FRAMESERVER;
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "frameserver_event");
			luactx.cb_source_kind = CB_SOURCE_NONE;
			return;
		}

		if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			return;

		arcan_frameserver* fsrv = vobj->feed.state.ptr;
		if (LUA_NOREF == fsrv->tag)
			return;

		if (ev->fsrv.kind == EVENT_FSRV_PREROLL){
			do_preroll(ctx, fsrv->tag, fsrv->vid, fsrv->aid);
			return;
		}
/*
 * placeholder slot for adding the callback function reference
 */
		lua_pushnumber(ctx, 0);

		lua_pushvid(ctx, ev->fsrv.video);
		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		tblnum(ctx, "source_audio", ev->fsrv.audio, top);

		switch(ev->fsrv.kind){
		case EVENT_FSRV_TERMINATED :
		break;
		case EVENT_FSRV_PREROLL:
		break;
		case EVENT_FSRV_APROTO:
			tblstr(ctx, "kind", "proto_change", top);
			tblbool(ctx, "cm", (ev->fsrv.aproto & SHMIF_META_CM) > 0, top);
			tblbool(ctx, "hdrf16", (ev->fsrv.aproto & SHMIF_META_HDRF16) > 0, top);
			tblbool(ctx, "ldef", (ev->fsrv.aproto & SHMIF_META_LDEF) > 0, top);
			tblbool(ctx, "vobj", (ev->fsrv.aproto & SHMIF_META_VOBJ) > 0, top);
			tblbool(ctx, "vr", (ev->fsrv.aproto & SHMIF_META_VR) > 0, top);
		break;
		case EVENT_FSRV_GAMMARAMP:
			tblstr(ctx, "kind", "ramp_update", top);
			tblnum(ctx, "index", ev->fsrv.counter, top);
		break;
		case EVENT_FSRV_DELIVEREDFRAME :
			tblstr(ctx, "kind", "frame", top);
			tblnum(ctx, "pts", ev->fsrv.pts, top);
			tblnum(ctx, "number", ev->fsrv.counter, top);
		break;
		case EVENT_FSRV_DROPPEDFRAME :
			tblstr(ctx, "kind", "dropped_frame", top);
			tblnum(ctx, "pts", ev->fsrv.pts, top);
			tblnum(ctx, "number", ev->fsrv.counter, top);
		break;
		case EVENT_FSRV_EXTCONN :{
			char msgbuf[COUNT_OF(ev->fsrv.ident)+1];
			tblstr(ctx, "kind", "connected", top);
			MSGBUF_UTF8(ev->fsrv.ident);
			tblstr(ctx, "key", msgbuf, top);
			luactx.pending_socket_label = strdup(msgbuf);
			luactx.pending_socket_descr = ev->fsrv.descriptor;
			adopt_check = true;
		}
		break;
		case EVENT_FSRV_RESIZED :
			tblstr(ctx, "kind", "resized", top);
			tblnum(ctx, "width", ev->fsrv.width, top);
			tblnum(ctx, "height", ev->fsrv.height, top);

/* mirrored is incorrect but can't drop it for legacy reasons */
			tblbool(ctx, "mirrored", ev->fsrv.glsource, top);
			tblbool(ctx, "origo_ll", ev->fsrv.glsource, top);
		break;
		default:
		break;
		}

		luactx.cb_source_tag = ev->fsrv.video;
		luactx.cb_source_kind = CB_SOURCE_FRAMESERVER;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, fsrv->tag);
			lua_replace(ctx, 1);
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "frameserver_event");
		luactx.cb_source_kind = CB_SOURCE_NONE;
	}
	else if (ev->category == EVENT_VIDEO){
		if (ev->vid.kind == EVENT_VIDEO_DISPLAY_ADDED){
			display_added(ctx, ev);
			return;
		}
		else if (ev->vid.kind == EVENT_VIDEO_DISPLAY_RESET){
			display_reset(ctx, ev);
			return;
		}
		else if (ev->vid.kind == EVENT_VIDEO_DISPLAY_REMOVED){
			display_removed(ctx, ev);
			return;
		}
		else if (ev->vid.kind == EVENT_VIDEO_DISPLAY_CHANGED){
			display_changed(ctx, ev);
			return;
		}

/* terminating conditions: no callback or source vid broken */
		intptr_t dst_cb = (intptr_t) ev->vid.data;
		arcan_vobject* srcobj = arcan_video_getobject(ev->vid.source);
		if (0 == dst_cb || !srcobj)
			return;

		const char* evmsg = "video_event";

/* add placeholder, if we find an asynch recipient */
		lua_pushnumber(ctx, 0);

		lua_pushvid(ctx, ev->vid.source);
		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		switch (ev->vid.kind){
		case EVENT_VIDEO_EXPIRE :
/* not even likely that these get forwarded here */
		break;

		case EVENT_VIDEO_CHAIN_OVER:
			evmsg = "video_event(chain_tag reached), callback";
			luactx.cb_source_kind = CB_SOURCE_TRANSFORM;
		break;

		case EVENT_VIDEO_ASYNCHIMAGE_LOADED:
			evmsg = "video_event(asynchimg_loaded), callback";
			luactx.cb_source_kind = CB_SOURCE_IMAGE;
			tblstr(ctx, "kind", "loaded", top);
/* C trick warning */
			if (0)
		case EVENT_VIDEO_ASYNCHIMAGE_FAILED:
			{
				luactx.cb_source_kind = CB_SOURCE_IMAGE;
				evmsg = "video_event(asynchimg_load_fail), callback";
				tblstr(ctx, "kind", "load_failed", top);
			}
			tblstr(ctx, "resource", srcobj && srcobj->vstore->vinf.text.source ?
				srcobj->vstore->vinf.text.source : "unknown", top);
			tblnum(ctx, "width", ev->vid.width, top);
			tblnum(ctx, "height", ev->vid.height, top);
		break;

		default:
			arcan_warning("Engine -> Script Warning: arcan_lua_pushevent(),"
			"	unknown video event (%i)\n", ev->vid.kind);
		}

		if (luactx.cb_source_kind != CB_SOURCE_NONE){
			luactx.cb_source_tag = ev->vid.source;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
			lua_replace(ctx, 1);
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0), evmsg);
		}
		else
			lua_settop(ctx, 0);

		if (adopt_check){
			if (luactx.pending_socket_label){
				arcan_mem_free(luactx.pending_socket_label);
				close(luactx.pending_socket_descr);
				luactx.pending_socket_descr = -1;
				luactx.pending_socket_label = NULL;
			}
		}

		luactx.cb_source_kind = CB_SOURCE_NONE;
	}
	else if (ev->category == EVENT_AUDIO)
		;
}
#undef FLTPUSH
#undef MSGBUF_UTF8

static int imageparent(lua_State* ctx)
{
	LUA_TRACE("image_parent");
	arcan_vobject* srcobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &srcobj);

	arcan_vobj_id pid = arcan_video_findparent(id);

	lua_pushvid(ctx, pid);
	lua_pushvid(ctx, srcobj->owner ?
		srcobj->owner->color->cellid : ARCAN_VIDEO_WORLDID);
	LUA_ETRACE("image_parent", NULL, 2);
}

static int videosynch(lua_State* ctx)
{
	LUA_TRACE("video_synchronization");
	const char* newstrat = luaL_optstring(ctx, 1, NULL);

	if (!newstrat){
		const char** opts = platform_video_synchopts();
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		size_t count = 0;

/* platform definition requires opts to be [k,d, ... ,NULL,NULL] */
		while(opts[count*2]){
			lua_pushnumber(ctx, count+1);
			lua_pushstring(ctx, opts[count*2]);
			lua_rawset(ctx, top);
			count++;
		}

		LUA_ETRACE("video_synchronization", NULL, 1);
	}
	else
		platform_video_setsynch(newstrat);

	LUA_ETRACE("video_synchronization", NULL, 0);
}

static int validvid(lua_State* ctx)
{
	LUA_TRACE("valid_vid");
	arcan_vobj_id res = (arcan_vobj_id) luaL_optnumber(ctx, 1, ARCAN_EID);

	if (res != ARCAN_EID && res != ARCAN_VIDEO_WORLDID)
		res -= luactx.lua_vidbase;

	if (res < 0)
		res = ARCAN_EID;

	int type = luaL_optnumber(ctx, 2, -1);
	if (-1 != type){
		arcan_vobject* vobj = arcan_video_getobject(res);
		lua_pushboolean(ctx, vobj && vobj->feed.state.tag == type);
	}
	else
		lua_pushboolean(ctx, arcan_video_getobject(res) != NULL);

	LUA_ETRACE("valid_vid", NULL, 1);
}

static int imagechildren(lua_State* ctx)
{
	LUA_TRACE("image_children");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id cid = luavid_tovid(luaL_optnumber(ctx, 2, ARCAN_EID));

	if (cid != ARCAN_EID){
		lua_pushboolean(ctx, arcan_video_isdescendant(id, cid, -1));
		LUA_ETRACE("image_children", NULL, 1);
	}

	arcan_vobj_id child;
	unsigned ofs = 0, count = 1;

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	while( (child = arcan_video_findchild(id, ofs++)) != ARCAN_EID){
		lua_pushnumber(ctx, count++);
		lua_pushvid(ctx, child);
		lua_rawset(ctx, top);
	}

	LUA_ETRACE("image_children", NULL, 1);
}

static int framesetalloc(lua_State* ctx)
{
	LUA_TRACE("image_framesetsize");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	unsigned num = luaL_checkint(ctx, 2);
	unsigned mode = luaL_optint(ctx, 3, ARCAN_FRAMESET_SPLIT);

	if (num < 256){
		arcan_video_allocframes(sid, num, mode);
	}
	else
		arcan_fatal("frameset_alloc() frameset limit (256) exceeded\n");

	LUA_ETRACE("image_framesetsize", NULL, 0);
}

static int framesetcycle(lua_State* ctx)
{
	LUA_TRACE("image_framecyclemode");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	unsigned num = luaL_optint(ctx, 2, 0);
	arcan_video_framecyclemode(sid, num);
	LUA_ETRACE("image_framecyclemode", NULL, 0);
}

static int pushasynch(lua_State* ctx)
{
	LUA_TRACE("image_pushasynch");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_video_pushasynch(sid);
	LUA_ETRACE("image_pushasynch", NULL, 0);
}

static int activeframe(lua_State* ctx)
{
	LUA_TRACE("image_active_frame");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	unsigned num = luaL_checkint(ctx, 2);

	arcan_video_setactiveframe(sid, num);
	LUA_ETRACE("image_active_frame", NULL, 0);
}

static int origoofs(lua_State* ctx)
{
	LUA_TRACE("image_origo_offset");
	arcan_vobject* vobj;
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, &vobj);
	float xv = luaL_checknumber(ctx, 2);
	float yv = luaL_checknumber(ctx, 3);
	float zv = luaL_optnumber(ctx, 4, 0.0);
	int inher = luaL_optnumber(ctx, 5, 0);
	luaL_checkvid(ctx, 1, &vobj);

	arcan_video_origoshift(sid, xv, yv, zv);

	if (inher != 0)
		FL_SET(vobj, FL_ROTOFS);
	else
		FL_CLEAR(vobj, FL_ROTOFS);

	LUA_ETRACE("image_origo_offset", NULL, 0);
}

struct mesh_ud {
	struct agp_mesh_store* mesh;
	arcan_vobject* vobj;
};

static int imagetess(lua_State* ctx)
{
	LUA_TRACE("image_tesselation");
	arcan_vobject* vobj;
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, &vobj);
	int arg1 = lua_type(ctx, 2);
	size_t s = 0;
	size_t t = 0;

/* either num, num, fun or fun - anything else is terminal */
	if (arg1 == LUA_TNUMBER){
		s = luaL_checknumber(ctx, 2);
		t = luaL_checknumber(ctx, 3);
		if (s > MAX_SURFACEW || t > MAX_SURFACEH)
			arcan_fatal("image_tesselation(vid,s,t) illegal s or t value");
	}
	else if (arg1 != LUA_TFUNCTION)
		arcan_fatal("image_tesselation(vid,num,num,*fun*) or (vid, *fun*)");
	else if (lua_iscfunction(ctx, 2))
		arcan_fatal("image_tesselation(fun), fun must be valid lua- function");

	intptr_t ref = find_lua_callback(ctx);

/* user want access? */
	struct agp_mesh_store* ms;
	if (LUA_NOREF == ref){
		arcan_video_defineshape(sid, s, t, &ms);
		lua_pushboolean(ctx, (ms && ms->verts != NULL) || s == 1 || t == 1);
	}
	else {
		arcan_video_defineshape(sid, s, t, &ms);
		lua_pushboolean(ctx, (ms && ms->verts != NULL) || s == 1 || t == 1);
/* invoke callback for ms, when finished, empty the userdata store */
		if (ms && ms->verts){
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, ref);
			struct mesh_ud* ud = lua_newuserdata(ctx, sizeof(struct mesh_ud));
			memset(ud, '\0', sizeof(struct mesh_ud));
			luaL_getmetatable(ctx, "meshAccess");
			lua_setmetatable(ctx, -2);
			lua_pushnumber(ctx, ms->n_vertices);
			lua_pushnumber(ctx, ms->vertex_size);
			ud->mesh = ms;
			ud->vobj = vobj;
			wraperr(ctx, lua_pcall(ctx, 3, 0, 0), "tessimage_cb");
			ud->mesh = NULL;
		}
	}

	LUA_ETRACE("image_tesselation", NULL, 1);
}

static int orderinherit(lua_State* ctx)
{
	LUA_TRACE("image_inherit_order");
	bool origo = lua_toboolean(ctx, 2);

/* array of VIDs or single VID */
	int argtype = lua_type(ctx, 1);
	if (argtype == LUA_TNUMBER){
		arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
		arcan_video_inheritorder(id, origo);
	}
	else if (argtype == LUA_TTABLE){
		int nelems = lua_rawlen(ctx, 1);

		for (size_t i = 0; i < nelems; i++){
			lua_rawgeti(ctx, 1, i+1);
				arcan_vobj_id id = luaL_checkvid(ctx, -1, NULL);
				arcan_video_inheritorder(id, origo);
			lua_pop(ctx, 1);
		}
	}

	LUA_ETRACE("image_inherit_order", NULL, 0);
}

static int imageasframe(lua_State* ctx)
{
	LUA_TRACE("set_image_as_frame");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);
	unsigned num = luaL_checkint(ctx, 3);

	arcan_errc code = arcan_video_setasframe(sid, did, num);
	if (code != ARCAN_OK){
		switch(code){
		case ARCAN_ERRC_UNACCEPTED_STATE:
			arcan_warning("set_image_as_frame(%"PRIxVOBJ":%"PRIxVOBJ") failed, "
				"source not connected to textured backing store.\n", sid, did);
		break;
		case ARCAN_ERRC_NO_SUCH_OBJECT:
		break;
		case ARCAN_ERRC_BAD_ARGUMENT:
			arcan_warning("set_image_as_frame(%"PRIxVOBJ":%"PRIxVOBJ") failed, "
				"dest doesn't have enough frames.\n", sid, did);
		break;
		default:
		arcan_fatal("set_image_as_frame() failed, unknown code: %d\n", (int)code);
		}
	}

	LUA_ETRACE("set_image_as_frame", NULL, 0);
}

static int linkimage(lua_State* ctx)
{
	LUA_TRACE("link_image");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);
	int ap = luaL_optnumber(ctx, 3, ANCHORP_UL);

	if (ap > ANCHORP_ENDM)
		arcan_fatal("link_image() -- invalid anchor point specified (%d)\n", ap);

	enum arcan_transform_mask smask = arcan_video_getmask(sid);
	smask |= MASK_LIVING;

	arcan_errc rv = arcan_video_linkobjs(sid, did, smask, ap);
	lua_pushboolean(ctx, rv == ARCAN_OK);
	LUA_ETRACE("link_image", NULL, 1);
}

static int pushprop(lua_State* ctx,
	surface_properties prop, unsigned short zv)
{
	lua_createtable(ctx, 0, 11);

	lua_pushstring(ctx, "x");
	lua_pushnumber(ctx, prop.position.x);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "y");
	lua_pushnumber(ctx, prop.position.y);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "z");
	lua_pushnumber(ctx, prop.position.z);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "width");
	lua_pushnumber(ctx, prop.scale.x);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "height");
	lua_pushnumber(ctx, prop.scale.y);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "angle");
	lua_pushnumber(ctx, prop.rotation.roll);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "roll");
	lua_pushnumber(ctx, prop.rotation.roll);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "pitch");
	lua_pushnumber(ctx, prop.rotation.pitch);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "yaw");
	lua_pushnumber(ctx, prop.rotation.yaw);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "opacity");
	lua_pushnumber(ctx, prop.opa);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "order");
	lua_pushnumber(ctx, zv);
	lua_rawset(ctx, -3);

	return 1;
}

static int scale3dverts(lua_State* ctx)
{
	LUA_TRACE("scale_3dvertices");
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	arcan_3d_scalevertices(vid);
	LUA_ETRACE("scale_3dvertices", NULL, 0);
}

/*
 * treat the top entry of the stack as an n-indexed array of values that should
 * be converted into a newly allocated/ tightly packed unsigned array
 */
static bool stack_to_uiarray(lua_State* ctx,
	int memtype, unsigned** dst, size_t* n, size_t count)
{
	size_t nval = lua_rawlen(ctx, -1);
	if (0 == nval || (count && nval != count))
		return false;

	*dst = arcan_alloc_mem(
		nval*sizeof(unsigned), memtype, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_NATURAL);

	if (!(*dst))
		return false;

	unsigned* out = *dst;
	for (size_t i = 0; i < nval; i++){
		lua_rawgeti(ctx, -1, i+1);
		*out++ = (unsigned) lua_tointeger(ctx, -1);
		lua_pop(ctx, 1);
	}

	return true;
}

static bool stack_to_farray(lua_State* ctx,
	int memtype, float** dst, size_t* n, size_t count)
{
	size_t nval = lua_rawlen(ctx, -1);
	if (0 == nval || (count && nval != count))
		return false;

	*dst = arcan_alloc_mem(
		nval * sizeof(float), memtype, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_NATURAL);

	if (!(*dst))
		return false;

	float* out = *dst;
	for (size_t i = 0; i < nval; i++){
		lua_rawgeti(ctx, -1, i+1);
		(*dst)[(*n)++] = (float) luaL_checknumber(ctx, -1);
		lua_pop(ctx, 1);
	}

	return (!count || *n == count);
}

static int rawmesh(lua_State* ctx, arcan_vobj_id did, int nmaps)
{
	const char* labels[6] = {
		"normals", "txcos", "txcos_2", "tangents", "colors", "weights"};
	size_t factors[6] = {3, 2, 2, 4, 4};
	float* targets[6] = {NULL};
	size_t sizes[6] = {0};
	size_t n_vertices = 0, n_bones = 0, n_indices = 0;
	float* vertices = NULL;
	union {uint16_t* us; unsigned* u;} bones = {.us = NULL};
	unsigned* indices = NULL;

/*
 * go with vertices, bones and indices separately
 */
	lua_getfield(ctx, 2, "vertices");
	if (lua_type(ctx, -1) != LUA_TTABLE)
		arcan_fatal("add_3dmesh(), required field 'vertices' missing");

	if (!stack_to_farray(ctx, ARCAN_MEM_MODELDATA, &vertices, &n_vertices, 0)){
		lua_pop(ctx, 1);
		goto fail;
	}
	if (n_vertices == 0 || n_vertices % 3 != 0)
		arcan_fatal(
			"add_3dmesh(), invalid number of elements (%3=0) in vertices");

	n_vertices /= 3;

	lua_getfield(ctx, 2, "indices");
	if (lua_type(ctx, -1) == LUA_TTABLE){
		if (!stack_to_uiarray(ctx, ARCAN_MEM_MODELDATA, &indices, &n_indices, 0)){
			arcan_warning("add_3dmesh(), couldn't unpack indices");
			lua_pop(ctx, 1);
			goto fail;
		}
	}
	lua_pop(ctx, 1);

/* hardcoded limit, and repack into other type - just to reuse stack_to */
	lua_getfield(ctx, 2, "bones");
	if (lua_type(ctx, -1) == LUA_TTABLE){
		if (stack_to_uiarray(ctx,
			ARCAN_MEM_MODELDATA, &bones.u, &n_bones, n_vertices * 4)){
			uint16_t tmp[4] = {bones.u[0], bones.u[1], bones.u[2], bones.u[3]};
			memcpy(bones.us, tmp, sizeof(uint16_t) * 4);
		}
	}

/* NOTE: would be better to just allocate one big chunk buffer and
 * map that into the structure etc. revisit this when full glTF2 is
 * evaluated */
	for (size_t i = 0; i < 6; i++){
		lua_getfield(ctx, 2, labels[i]);
		if (lua_type(ctx, -1) == LUA_TTABLE){
			if (!stack_to_farray(ctx,
				ARCAN_MEM_MODELDATA, &targets[i], &sizes[i], factors[i])){
				arcan_warning("add_3dmesh(), couldn't unpack %s", labels[i]);
				lua_pop(ctx, 1);
				goto fail;
			}
		}
		lua_pop(ctx, 1);
	}

	if (ARCAN_OK == arcan_3d_addraw(did, vertices, n_vertices,
			indices, n_indices, targets[0], targets[1], targets[2],
			targets[3], targets[4], bones.us, targets[5], nmaps)){
			lua_pushboolean(ctx, true);
	}
else{
fail:
		for (size_t i = 0; i < 6; i++){
			arcan_mem_free(targets[i]);
		}
		arcan_mem_free(bones.u);
		arcan_mem_free(indices);
		arcan_mem_free(vertices);
		lua_pushboolean(ctx, false);
	}
	LUA_ETRACE("add_3dmesh", NULL, 1);
}

static int loadmesh(lua_State* ctx)
{
	LUA_TRACE("add_3dmesh");

	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	int nmaps = abs((int)luaL_optnumber(ctx, 3, 1));
	if (lua_type(ctx, 2) == LUA_TTABLE)
		return rawmesh(ctx, did, nmaps);
	if (lua_type(ctx, 2) != LUA_TSTRING)
		arcan_fatal("add_3dmesh(), invalid resource type");

	char* path = findresource(luaL_checkstring(ctx, 2), DEFAULT_USERMASK);
	data_source indata = arcan_open_resource(path);
	if (indata.fd != BADFD){
		arcan_errc rv = arcan_3d_addmesh(did, indata, nmaps);
		if (rv != ARCAN_OK)
			arcan_warning("loadmesh(%s) -- "
				"Couldn't add mesh to (%d)\n", path, did);
		arcan_release_resource(&indata);
		lua_pushboolean(ctx, false);
	}
	else
		lua_pushboolean(ctx, true);
	arcan_mem_free(path);

	LUA_ETRACE("add_3dmesh", NULL, 1);
}

static int attrtag(lua_State* ctx)
{
	LUA_TRACE("attrtag_model");

	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	const char* attr = luaL_checkstring(ctx, 2);
	int state = luaL_checkbnumber(ctx, 3);

	if (strcmp(attr, "infinite") == 0)
		lua_pushboolean(ctx,
			arcan_3d_infinitemodel(did, state != 0) != ARCAN_OK);
	else
		lua_pushboolean(ctx, false);

	LUA_ETRACE("attrtag_model", NULL, 1);
}

static int buildmodel(lua_State* ctx)
{
	LUA_TRACE("new_3dmodel");

	arcan_vobj_id id = ARCAN_EID;
	id = arcan_3d_emptymodel();

	if (id != ARCAN_EID)
		arcan_video_objectopacity(id, 0, 0);

	lua_pushvid(ctx, id);
	trace_allocation(ctx, "new_3dmodel", id);
	LUA_ETRACE("new_3dmodel", NULL, 1);
}

static int finalmodel(lua_State* ctx)
{
	LUA_TRACE("finalize_3dmodel");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_errc rv = arcan_3d_finalizemodel(id);
	if (rv == ARCAN_ERRC_UNACCEPTED_STATE){
		arcan_fatal("new_3dmodel(), specified vid"
			"	is not connected to a 3d model.\n");
	}

	LUA_ETRACE("finalize_3dmodel", NULL, 0);
}

static int buildplane(lua_State* ctx)
{
	LUA_TRACE("build_3dplane");

	float minx = luaL_checknumber(ctx, 1);
	float mind = luaL_checknumber(ctx, 2);
	float endx = luaL_checknumber(ctx, 3);
	float endd = luaL_checknumber(ctx, 4);
	float starty = luaL_checknumber(ctx, 5);
	float hdens = luaL_checknumber(ctx, 6);
	float ddens = luaL_checknumber(ctx, 7);
	int nmaps = abs((int)luaL_optnumber(ctx, 8, 1));
	bool vert = luaL_optbnumber(ctx, 9, false);

	arcan_vobj_id id = arcan_3d_buildplane(
		minx, mind, endx, endd, starty, hdens, ddens, nmaps, vert);

	lua_pushvid(ctx, id);
	trace_allocation(ctx, "build_3dplane", id);

	LUA_ETRACE("build_3dplane", NULL, 1);
}

static int buildbox(lua_State* ctx)
{
	LUA_TRACE("build_3dbox");

	float width = luaL_checknumber(ctx, 1);
	float height = luaL_checknumber(ctx, 2);
	float depth = luaL_checknumber(ctx, 3);
	int nmaps = abs((int)luaL_optnumber(ctx, 4, 1));
	bool split = luaL_optbnumber(ctx, 5, false);

	arcan_vobj_id id = arcan_3d_buildbox(width, height, depth, nmaps, split);
	lua_pushvid(ctx, id);
	trace_allocation(ctx, "build_3dbox", id);

	LUA_ETRACE("build_3dbox", NULL, 1);
}

static int pointcloud(lua_State* ctx)
{
	LUA_TRACE("build_pointcloud");
	float count = luaL_checknumber(ctx, 1);
	int nmaps = abs((int)luaL_optnumber(ctx, 2, 1));

	arcan_vobj_id id = arcan_3d_pointcloud(count, nmaps);
	lua_pushvid(ctx, id);
	trace_allocation(ctx, "build_pointcloud", id);

	LUA_ETRACE("build_pointcloud", NULL, 1);
}

static int buildcylinder(lua_State* ctx)
{
	LUA_TRACE("build_cylinder");
	float radius = luaL_checknumber(ctx, 1);
	float halfh = luaL_checknumber(ctx, 2);
	size_t steps = luaL_checknumber(ctx, 3);
	int nmaps = abs((int)luaL_optnumber(ctx, 4, 1));
	const char* caps = luaL_optstring(ctx, 5, NULL);

	int capv = CYLINDER_FILL_FULL;
	if (caps && strcmp(caps, "caps") == 0)
		capv = CYLINDER_FILL_FULL_CAPS;
	else if (caps && strcmp(caps, "half") == 0)
		capv = CYLINDER_FILL_HALF;
	else if (caps && strcmp(caps, "halfcaps") == 0)
		capv = CYLINDER_FILL_HALF_CAPS;

	arcan_vobj_id id = arcan_3d_buildcylinder(radius, halfh, steps, nmaps, capv);
	lua_pushvid(ctx, id);
	trace_allocation(ctx, "build_cylinder", id);
	LUA_ETRACE("build_cylinder", NULL, 1);
}

static int buildsphere(lua_State* ctx)
{
	LUA_TRACE("build_sphere");
	float radius = luaL_checknumber(ctx, 1);
	float lng = luaL_checknumber(ctx, 2);
	float lat = luaL_checknumber(ctx, 3);
	int nmaps = abs((int)luaL_optnumber(ctx, 4, 1));
	bool hemi = luaL_optbnumber(ctx, 5, false);
	arcan_vobj_id id = arcan_3d_buildsphere(radius, lng, lat, hemi, nmaps);
	lua_pushvid(ctx, id);
	trace_allocation(ctx, "build_sphere", id);
	LUA_ETRACE("build_sphere", NULL, 1);
}

static int swizzlemodel(lua_State* ctx)
{
	LUA_TRACE("swizzle_model");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_errc rv = arcan_3d_swizzlemodel(id);
	lua_pushboolean(ctx, rv == ARCAN_OK);

	LUA_ETRACE("swizzle_model", NULL, 1);
}

static int camtag(lua_State* ctx)
{
	LUA_TRACE("camtag_model");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);

	struct monitor_mode mode = platform_video_dimensions();
	float w = mode.width;
	float h = mode.height;

	float ar = w / h > 1.0 ? w / h : h / w;

	float nv  = luaL_optnumber(ctx, 2, 0.1);
	float fv  = luaL_optnumber(ctx, 3, 100.0);
	float fov = luaL_optnumber(ctx, 4, 45.0);
	ar = luaL_optnumber(ctx, 5, ar);
	bool front = luaL_optbnumber(ctx, 6, true);
	bool back  = luaL_optbnumber(ctx, 7, false);
	float linew = luaL_optnumber(ctx, 8, 0.0);

	enum agp_mesh_flags flags = 0;
	if (linew > EPSILON)
		flags |= MESH_FILL_LINE;
	else
		linew = 1.0;

	arcan_vobj_id dst = ARCAN_EID;
	if (lua_type(ctx, 9) == LUA_TNUMBER){
		arcan_vobject* vobj;
		dst = luaL_checkvid(ctx, 9, &vobj);
		if (!arcan_vint_findrt(vobj))
			arcan_fatal("camtag_model(), referenced dst is not a rendertarget\n");
	}

	if (front)
		flags |= MESH_FACING_FRONT;
	if (back)
		flags |= MESH_FACING_BACK;

	arcan_errc rv = arcan_3d_camtag(dst, id, nv, fv, ar, fov, flags, linew);

	lua_pushboolean(ctx, rv == ARCAN_OK);
	LUA_ETRACE("camtag_model", NULL, 1);
}

static int getimageprop(lua_State* ctx)
{
	LUA_TRACE("image_surface_properties");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	long long dt = luaL_optnumber(ctx, 2, 0);
	surface_properties prop;

	if (dt < 0)
		dt = LONG_MAX;

	prop = dt > 0 ?
		arcan_video_properties_at(id, dt) : arcan_video_current_properties(id);

	int n = pushprop(ctx, prop, arcan_video_getzv(id));
	LUA_ETRACE("image_surface_properties", NULL, n);
}

static int getimageresolveprop(lua_State* ctx)
{
	LUA_TRACE("image_surface_resolve_properties");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	surface_properties prop = arcan_video_resolve_properties(id);

	int n = pushprop(ctx, prop, arcan_video_getzv(id));
	LUA_ETRACE("image_surface_resolve_properties", NULL, n);
}

static int getimageinitprop(lua_State* ctx)
{
	LUA_TRACE("image_surface_initial_properties");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	surface_properties prop = arcan_video_initial_properties(id);

	int n = pushprop(ctx, prop, arcan_video_getzv(id));
	LUA_ETRACE("image_surface_initial_properties", NULL, n);
}

static int getimagestorageprop(lua_State* ctx)
{
	LUA_TRACE("image_storage_properties");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	img_cons cons = arcan_video_storage_properties(id);
	lua_createtable(ctx, 0, 3);

	lua_pushstring(ctx, "bpp");
	lua_pushnumber(ctx, cons.bpp);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "height");
	lua_pushnumber(ctx, cons.h);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "width");
	lua_pushnumber(ctx, cons.w);
	lua_rawset(ctx, -3);

	LUA_ETRACE("image_storage_properties", NULL, 1);
}

static int slicestore(lua_State* ctx)
{
	LUA_TRACE("image_storage_slice");
	arcan_vobject* vobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);
	int type = luaL_checknumber(ctx, 2);

	if (type != ARCAN_CUBEMAP && type != ARCAN_3DTEXTURE)
		arcan_fatal("image_storage_slice(), unknown slice type");

	luaL_checktype(ctx, 3, LUA_TTABLE);
	int values = lua_rawlen(ctx, 2);

	if (vobj->vstore->txmapped != TXSTATE_TEX2D)
		arcan_fatal("image_storage_slice(), destination store is not textured");

	arcan_vobj_id slices[values];
	for (size_t i = 0; i < values; i++){
		lua_rawgeti(ctx, 3, i+1);
		arcan_vobj_id setvid = luavid_tovid( lua_tonumber(ctx, -1) );
		arcan_vobject* vobj = arcan_video_getobject(setvid);
		if (!vobj || !vobj->vstore || vobj->vstore->txmapped != TXSTATE_TEX2D)
			arcan_fatal("image_storage_slice(), invalid slice source at index %zu", i+1);
		slices[i] = setvid;
	}

	if (
		ARCAN_OK == arcan_video_sliceobject(id, type, vobj->vstore->w, values) &&
		ARCAN_OK == arcan_video_updateslices(id, values, slices) )
		lua_pushboolean(ctx, true);
	else
		lua_pushboolean(ctx, false);

	LUA_ETRACE("image_storage_slice", NULL, 1);
}

static int copyimageprop(lua_State* ctx)
{
	LUA_TRACE("copy_surface_properties");

	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);

	arcan_video_copyprops(sid, did);
	LUA_ETRACE("copy_surface_properties", NULL, 0);
}

static bool validate_key(const char* key)
{
/* accept 0-9 and base64 valid values */
	while(*key){
		if (!isalnum(*key) && *key != '_'
			&& *key != '+' && *key != '/' && *key != '=')
			return false;
		key++;
	}

	return true;
}

static union arcan_dbtrans_id setup_transaction(lua_State* ctx,
	enum DB_KVTARGET* kvtgt, int ind)
{
	union arcan_dbtrans_id tid;
	tid.applname = arcan_appl_id();
	*kvtgt = DVT_APPL;

	const char* tgt = luaL_optstring(ctx, ind, NULL);
	if (tgt){
		*kvtgt = DVT_TARGET;
		tid.tid = arcan_db_targetid(DBHANDLE, tgt, NULL);
		if (tid.tid == BAD_TARGET){
			*kvtgt = DVT_ENDM;
			return tid;
		}

		const char* cfg = luaL_optstring(ctx, ind+1, NULL);
		if (cfg){
			tid.cid = arcan_db_configid(DBHANDLE, tid.tid, cfg);
			*kvtgt = tid.cid == BAD_CONFIG ? DVT_ENDM : DVT_CONFIG;
		}
	}

	return tid;
}

static int storekey(lua_State* ctx)
{
	LUA_TRACE("store_key");

	enum DB_KVTARGET kvtgt;
	union arcan_dbtrans_id tid = setup_transaction(ctx, &kvtgt,
		lua_type(ctx, 1) == LUA_TTABLE ? 2 : 3);
	if (kvtgt == DVT_ENDM){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("store_key", "missing transaction arguments", 1);
	}

	if (lua_type(ctx, 1) == LUA_TTABLE){
		lua_pushnil(ctx);
		arcan_db_begin_transaction(DBHANDLE, kvtgt, tid);

		size_t counter = 0;
		while (lua_next(ctx, 1) != 0){
			counter++;
			const char* key = lua_tostring(ctx, -2);
			if (!validate_key(key)){
				arcan_warning("store_key, key[%d] rejected "
					"(restricted to [a-Z0-9_+/=])\n", counter);
			}
			else {
				const char* val = lua_tostring(ctx, -1);
				arcan_db_add_kvpair(DBHANDLE, key, val);
			}

			lua_pop(ctx, 1);
		}

		arcan_db_end_transaction(DBHANDLE);
		lua_pushboolean(ctx, true);
		LUA_ETRACE("store_key", NULL, 1);
	}

	const char* keystr = luaL_checkstring(ctx, 1);
	const char* valstr = luaL_checkstring(ctx, 2);
	if (!validate_key(keystr)){
		arcan_warning("store_key, key[%s] rejected "
			"(restricted to [a-Z0-9_])\n", keystr);
		lua_pushboolean(ctx, false);
		LUA_ETRACE("store_key", "invalid key", 1);
	}

	arcan_db_begin_transaction(DBHANDLE, kvtgt, tid);
	arcan_db_add_kvpair(DBHANDLE, keystr, valstr);
	arcan_db_end_transaction(DBHANDLE);

	lua_pushboolean(ctx, true);
	LUA_ETRACE("store_key", NULL, 1);
}

static int push_stringres(lua_State* ctx, struct arcan_strarr* res)
{
	int rv = 0;

	if (res->data){
		char** curr = res->data;
		unsigned int count = 1; /* 1 indexing, seriously LUA ... */

		curr = res->data;

		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		while (*curr){
			lua_pushnumber(ctx, count++);
			lua_pushstring(ctx, *curr++);
			lua_rawset(ctx, top);
		}

		rv = 1;
	}

	return rv;
}

static int matchkeys(lua_State* ctx)
{
	LUA_TRACE("match_keys");
	const char* pattern = luaL_checkstring(ctx, 1);
	int domain = luaL_optnumber(ctx, 2, DVT_APPL);

	if (domain != DVT_TARGET && domain != DVT_CONFIG && domain != DVT_APPL)
		arcan_fatal("match keys(%d) invalid domain specified, "
			"domain must be KEY_TARGET or KEY_CONFIG\n");

	struct arcan_strarr res;
	if (domain == DVT_APPL)
		res = arcan_db_applkeys(DBHANDLE, arcan_appl_id(), pattern);
	else
		res = arcan_db_matchkey(DBHANDLE, domain, pattern);

	int rv = push_stringres(ctx, &res);
	arcan_mem_freearr(&res);

	LUA_ETRACE("match keys", NULL, rv);
}

static int getkeys(lua_State* ctx)
{
	LUA_TRACE("get_keys");
	const char* tgt = luaL_checkstring(ctx, 1);
	const char* cfg = luaL_optstring(ctx, 2, NULL);
	union arcan_dbtrans_id tid, cid;
	tid.tid	= arcan_db_targetid(DBHANDLE, tgt, NULL);

	struct arcan_strarr res;
	if (!cfg){
		res = arcan_db_getkeys(DBHANDLE, DVT_TARGET, tid);
	}
	else {
		cid.cid = arcan_db_configid(DBHANDLE, tid.tid, cfg);
		res = arcan_db_getkeys(DBHANDLE, DVT_CONFIG, cid);
	}

	int rv = push_stringres(ctx, &res);
	arcan_mem_freearr(&res);

	LUA_ETRACE("get_keys", NULL, rv);
}

static int getkey(lua_State* ctx)
{
	LUA_TRACE("get_key");

	const char* key = luaL_checkstring(ctx, 1);
	if (!validate_key(key)){
		arcan_warning("invalid key specified (restricted to [a-Z0-9_])\n");
		lua_pushnil(ctx);
		LUA_ETRACE("get_key", "invalid key", 1);
	}

	const char* opt_target = luaL_optstring(ctx, 2, NULL);

	if (opt_target){
		arcan_targetid tid = arcan_db_targetid(DBHANDLE, opt_target, NULL);

		const char* opt_config = luaL_optstring(ctx, 3, NULL);
		if (opt_config){
			arcan_configid cid = arcan_db_configid(DBHANDLE, tid, opt_config);
			char* val = arcan_db_getvalue(DBHANDLE, DVT_CONFIG, cid, key);
			if (val)
				lua_pushstring(ctx, val);
			else
				lua_pushnil(ctx);
			free(val);
		}
		else{
			arcan_db_getvalue(DBHANDLE, DVT_TARGET, tid, key);
		}
	}
	else {
	char* val = arcan_db_appl_val(DBHANDLE, arcan_appl_id(), key);

	if (val){
		lua_pushstring(ctx, val);
		free(val);
	}
	else
		lua_pushnil(ctx);
	}

	LUA_ETRACE("get_key", NULL, 1);
}

static int kbdrepeat(lua_State* ctx)
{
	LUA_TRACE("kbd_repeat");
	int rperiod = luaL_checknumber(ctx, 1);
	int rdelay = luaL_optnumber(ctx, 2, -1);

	platform_event_keyrepeat(arcan_event_defaultctx(), &rperiod, &rdelay);

	lua_pushnumber(ctx, rperiod);
	lua_pushnumber(ctx, rdelay);

	LUA_ETRACE("kbd_repeat", NULL, 2);
}

static int v3dorder(lua_State* ctx)
{
	LUA_TRACE("video_3dorder");

	arcan_vobj_id rt = ARCAN_EID;
	int nargs = lua_gettop(ctx);
	int order;

	if (nargs == 2){
		rt = luaL_checkvid(ctx, 1, NULL);
		order = luaL_checknumber(ctx, 2);
	}
	else
		order = luaL_checknumber(ctx, 1);

	if (order != ORDER3D_FIRST && order != ORDER3D_LAST && order != ORDER3D_NONE)
		arcan_fatal("3dorder(%d) invalid order specified (%d),"
			"	expected ORDER_FIRST, ORDER_LAST or ORDER_NONE\n");

	arcan_video_3dorder(order, rt);
	LUA_ETRACE("video_3dorder", NULL, 0);
}

static int videocanvasrsz(lua_State* ctx)
{
	LUA_TRACE("resize_video_canvas");

	size_t w = abs((int)luaL_checknumber(ctx, 1));
	size_t h = abs((int)luaL_checknumber(ctx, 2));

	if (!w || !h){
		LUA_ETRACE("resize_video_canvas", NULL, 0);
	}

/*
 * undo the effects of delete_image(WORLDID)
 */
	arcan_video_display.no_stdout = false;

/* note that this actually creates a texture in WORLDID that
 * is larger than the other permitted max surface dimensions,
 * this may need to be restricted ( create -> share storage etc. ) */

#ifdef ARCAN_LWA
	if (!platform_video_specify_mode(0,
		(struct monitor_mode){.width = w, .height = h}))
		LUA_ETRACE("resize_video_canvas", NULL, 0);
#endif

	if (ARCAN_OK == arcan_video_resize_canvas(w, h)){
		arcan_lua_setglobalint(ctx, "VRESW", w);
		arcan_lua_setglobalint(ctx, "VRESH", h);
	}

	LUA_ETRACE("resize_video_canvas", NULL, 0);
}

static bool push_fsrv_ramp(arcan_frameserver* dst, lua_State* src,
	int index, size_t n)
{
	float ramps[SHMIF_CMRAMP_UPLIM] = {0};
	size_t ch_sz[SHMIF_CMRAMP_PLIM] = {0};

	size_t edid_sz = 0;
	uint8_t* edid_buf = NULL;
	size_t i = 0;

/* this format still only accepts one plane, though the limitation is
 * only in lua land and the egl-dri platform at the moment */
	for (; i < n && i < SHMIF_CMRAMP_UPLIM; i++){
		lua_rawgeti(src, 2, i+1);
		ramps[i] = lua_tonumber(src, -1);
		lua_pop(src, 1);
	}

/* setting/forcing/faking edid is still optional */
	lua_getfield(src, 2, "edid");
	edid_buf = (uint8_t*) lua_tolstring(src, -1, &edid_sz);
	lua_pop(src, 1);

/* since we're working with the frameserver- shmpage directly,
 * we need the guard region to handle SIGBUS */
	jmp_buf tramp;
	if (0 != setjmp(tramp)){
		return false;
	}

	ch_sz[0] = i;
	platform_fsrv_enter(dst, tramp);
	bool rv = arcan_frameserver_setramps(dst,
		index, ramps, i, ch_sz, edid_buf, edid_sz);
	platform_fsrv_leave();
	return rv;
}

static int pull_fsrv_ramp(lua_State* dst, arcan_frameserver* src, int ind)
{
	jmp_buf tramp;
	if (0 != setjmp(tramp)){
		return 0;
	}

	size_t ch_pos[SHMIF_CMRAMP_PLIM];
	float tblbuf[SHMIF_CMRAMP_UPLIM];

/* the Lua API currently only handles single planes */
	platform_fsrv_enter(src, tramp);
	bool rv = arcan_frameserver_getramps(src,ind,tblbuf,sizeof(tblbuf),ch_pos);
	platform_fsrv_leave();

	if (rv && ch_pos[0]){
		size_t nr = ch_pos[0] > SHMIF_CMRAMP_UPLIM ? SHMIF_CMRAMP_UPLIM:ch_pos[0];
		lua_createtable(dst, nr, 0);
		int top = lua_gettop(dst);
		for (size_t i = 0; i < nr; i++){
			lua_pushnumber(dst, i + 1);
			lua_pushnumber(dst, tblbuf[i]);
			lua_rawset(dst, top);
		}
		return 1;
	}

	return 0;
}

static int fsrv_gamma(lua_State* ctx, arcan_vobject* fsrv_dst)
{
	if (fsrv_dst->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("video_displaygamma(), tried to set gamma on a vobj with "
			"no valid frameserver backing");

/* fsrv-set? */
	if (lua_type(ctx, 2) == LUA_TTABLE){
		int values = lua_rawlen(ctx, 2);
		if (values <= 0 || values % 3 != 0){
			arcan_fatal("video_displaygamma(), broken ramp table"
				"(%d should be > 0 and divisible by 3)\n", values);
		}

/* separate path for a frameserver destination */
		lua_pushboolean(ctx, push_fsrv_ramp(
			fsrv_dst->feed.state.ptr, ctx, luaL_optint(ctx, 3, 0), values));
		LUA_ETRACE("video_displaygamma", NULL, 1);
	}
/* fsrv get */
	else {
		int rv = pull_fsrv_ramp(ctx,
			fsrv_dst->feed.state.ptr, luaL_optint(ctx, 2, 0));
		LUA_ETRACE("video_displaygamma", NULL, rv);
	}
}

static int videodispgamma(lua_State* ctx)
{
	LUA_TRACE("video_displaygamma");
	arcan_vobject* fsrv_dst = NULL;

/* separate "to frameserver instead of display?" path: */
	int64_t id = luaL_checknumber(ctx, 1);
	if (id != ARCAN_EID && id !=
		ARCAN_VIDEO_WORLDID && id > luactx.lua_vidbase){
		fsrv_dst = arcan_video_getobject(id-luactx.lua_vidbase);
		if (fsrv_dst)
			return fsrv_gamma(ctx, fsrv_dst);
	}

	if (lua_gettop(ctx) > 1){
		luaL_checktype(ctx, 2, LUA_TTABLE);
		int values = lua_rawlen(ctx, 2);
		if (values <= 0 || values % 3 != 0){
			arcan_fatal("video_displaygamma(), broken ramp table"
				"(%d should be > 0 and divisible by 3)\n", values);
		}

		uint16_t* ramps = arcan_alloc_mem(values * sizeof(uint16_t),
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO,
			ARCAN_MEMALIGN_NATURAL
		);

		for (size_t i = 0; i < values; i++){
			lua_rawgeti(ctx, 2, i+1);
			float num = lua_tonumber(ctx, -1);
			lua_pop(ctx, 1);
			ramps[i] = ((num < 0.0 ? 0.0 : num) > 1.0 ? 1.0 : num) * 65535;
		}

		values /= 3;
		lua_pushboolean(ctx, platform_video_set_display_gamma(id,
			values, &ramps[0 * values], &ramps[1 * values], &ramps[2 * values]));

		LUA_ETRACE("video_displaygamma", NULL, 1);
	}
/* get */
	else {
		size_t nramps;
		uint16_t* outb;

		if (!platform_video_get_display_gamma(id, &nramps, &outb))
			LUA_ETRACE("video_displaygamma", NULL, 0);

/* push as planar table of floats */
		lua_createtable(ctx, nramps * 3, 0);
		int top = lua_gettop(ctx);
		for (size_t i = 0; i < nramps * 3; i++){
			lua_pushnumber(ctx, i+1);
			lua_pushnumber(ctx, (float)outb[i] / 65535.0f);
			lua_rawset(ctx, top);
		}

		LUA_ETRACE("video_displaygamma", NULL, 1);
	}

	LUA_ETRACE("video_displaygamma", NULL, 0);
}

static int videodispdescr(lua_State* ctx)
{
	LUA_TRACE("video_displaydescr");
	platform_display_id id = luaL_checknumber(ctx, 1);
	char* buf;
	size_t buf_sz;

	if (platform_video_display_edid(id, &buf, &buf_sz)){
		unsigned long hash = 5381;
		lua_pushlstring(ctx, buf, buf_sz);
		for (size_t i = 0; i < buf_sz; i++)
			hash = ((hash << 5) + hash) + buf[i];

		free(buf);
		lua_pushnumber(ctx, hash);

		LUA_ETRACE("video_displaydescr", NULL, 2);
	}

	LUA_ETRACE("video_displaydescr", "unknown display", 0);
}

static int videodisplay(lua_State* ctx)
{
	LUA_TRACE("video_displaymodes");
	platform_display_id id;

	switch(lua_gettop(ctx)){
	case 0: /* rescan */
		platform_video_query_displays();
	break;

	case 1: /* probe modes */
		id = luaL_checknumber(ctx, 1);
		lua_newtable(ctx);
		push_displaymodes(ctx, id);
		LUA_ETRACE("video_displaymodes", NULL, 1);
	break;

	case 2: /* specify hardcoded mode */
		id = luaL_checknumber(ctx, 1);
		platform_mode_id mode = luaL_checknumber(ctx, 2);
		lua_pushboolean(ctx, platform_video_set_mode(id, mode));
		LUA_ETRACE("video_displaymodes", NULL, 1);
	break;

	case 3: /* specify custom mode */
		id = luaL_checknumber(ctx, 1);
		size_t w = luaL_checknumber(ctx, 2);
		size_t h = luaL_checknumber(ctx, 3);
		struct monitor_mode mmode = {
			.width = w,
			.height = h
		};
		lua_pushboolean(ctx, platform_video_specify_mode(id, mmode));
		LUA_ETRACE("video_displaymodes", NULL, 1);

	default:
		arcan_fatal("video_displaymodes(), invalid number of aguments (%d)\n",
			lua_gettop(ctx));
	}

	LUA_ETRACE("video_displaymodes", NULL, 0);
}

static int videomapping(lua_State* ctx)
{
	LUA_TRACE("map_video_display");

	arcan_vobj_id vid = luavid_tovid( luaL_checknumber(ctx, 1) );
	platform_display_id id = luaL_checknumber(ctx, 2);
	enum blitting_hint hint = luaL_optnumber(ctx, 3, HINT_NONE);

	if (hint < HINT_NONE){
		arcan_fatal("map_video_display(), invalid blitting "
			"hint specified (%d)\n", (int) hint);
	}

	if (vid != ARCAN_VIDEO_WORLDID && vid != ARCAN_EID){
		arcan_vobject* vobj = arcan_video_getobject(vid);
		if (!vobj)
			arcan_fatal("map_video_display(), invalid vid "
				"requested %"PRIxVOBJ" \n", vid);

		if (vobj->vstore->txmapped != TXSTATE_TEX2D){
			arcan_warning("map_video_display(), associated "
				"video object has an invalid backing store (font, color, ...)\n");
			LUA_ETRACE("map_video_display", "invalid backing store", 0);
		}
	}

	lua_pushboolean(ctx, platform_video_map_display(vid, id, hint));
	LUA_ETRACE("map_video_display", NULL, 0);
}

static const char* dpms_to_str(int dpms)
{
	switch (dpms){
	case ADPMS_OFF:
		return "off";
	case ADPMS_SUSPEND:
		return "suspend";
	case ADPMS_STANDBY:
		return "standby";
	case ADPMS_ON:
		return "on";
	default:
		return "bad-display";
	}
}

static int videodpms(lua_State* ctx)
{
	LUA_TRACE("video_display_state");
	int n = lua_gettop(ctx);
	platform_display_id did = luaL_checknumber(ctx, 1);
	if (1 == n)
		;
	else if (2 == n){
		int state = luaL_checknumber(ctx, 2);
		if (strcmp(dpms_to_str(state), "bad-display") == 0)
			arcan_fatal("video_display_state(), invalid DPMS value (valid: "
				"DISPLAY _ON, _OFF, _SUSPEND or _STANDBY) \n");
		platform_video_dpms(did, state);
	}
	else
		arcan_fatal("video_display_state(), 1 or 2 arguments expected, not %d\n",n);

	lua_pushstring(ctx, dpms_to_str(platform_video_dpms(did, ADPMS_IGNORE)));

	LUA_ETRACE("video_display_state", NULL, 1);
}

static int inputbase(lua_State* ctx)
{
	LUA_TRACE("input_samplebase");
	int devid = luaL_checknumber(ctx, 1);
	float xyz[3];
	xyz[0] = luaL_optnumber(ctx, 2, 0);
	xyz[1] = luaL_optnumber(ctx, 3, 0);
	xyz[2] = luaL_optnumber(ctx, 4, 0);
	platform_event_samplebase(devid, xyz);
	LUA_ETRACE("input_samplebase", NULL, 0);
}

static int inputcap(lua_State* ctx)
{
	LUA_TRACE("input_capabilities");
	enum PLATFORM_EVENT_CAPABILITIES pcap = platform_input_capabilities();
	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	tblbool(ctx, "translated", (pcap & ACAP_TRANSLATED) > 0, top);
	tblbool(ctx, "mouse", (pcap & ACAP_MOUSE) > 0, top);
	tblbool(ctx, "gaming", (pcap & ACAP_GAMING) > 0, top);
	tblbool(ctx, "touch", (pcap & ACAP_TOUCH) > 0, top);
	tblbool(ctx, "position", (pcap & ACAP_POSITION) > 0, top);
	tblbool(ctx, "orientation", (pcap & ACAP_ORIENTATION) > 0, top);
	LUA_ETRACE("input_capabilities", NULL, 1);
}

static int mousegrab(lua_State* ctx)
{
	LUA_TRACE("toggle_mouse_grab");
	int mode = luaL_optint( ctx, 1, -1);

	if (mode == -1)
		luactx.grab = !luactx.grab;
	else if (mode == MOUSE_GRAB_ON)
		luactx.grab = true;
	else if (mode == MOUSE_GRAB_OFF)
		luactx.grab = false;

	arcan_device_lock(0, luactx.grab);
	lua_pushboolean(ctx, luactx.grab);

	LUA_ETRACE("toggle_mouse_grab", NULL, 1);
}

static int gettargets(lua_State* ctx)
{
	LUA_TRACE("list_targets");

	int rv = 0;

	struct arcan_strarr res = arcan_db_targets(
		DBHANDLE, luaL_optstring(ctx, 1, NULL));
	rv += push_stringres(ctx, &res);
	arcan_mem_freearr(&res);

	LUA_ETRACE("list_targets", NULL, rv);
}

static int gettags(lua_State* ctx)
{
	LUA_TRACE("list_target_tags");
	struct arcan_strarr res = arcan_db_target_tags(DBHANDLE);
	int rv = push_stringres(ctx, &res);
	LUA_ETRACE("list_target_tags", NULL, rv);
}

static int getconfigs(lua_State* ctx)
{
	LUA_TRACE("target_configurations");
	const char* target = luaL_checkstring(ctx, 1);
	int rv = 0;

	arcan_targetid tid = arcan_db_targetid(DBHANDLE, target, NULL);
	struct arcan_strarr res = arcan_db_configs(DBHANDLE, tid);

	rv += push_stringres(ctx, &res);
	char* tag = arcan_db_targettag(DBHANDLE, tid);
	if (tag){
		lua_pushstring(ctx, tag);
		arcan_mem_free(tag);
		rv++;
	}

	arcan_mem_freearr(&res);

	LUA_ETRACE("target_configurations", NULL, rv);
}

static int allocsurface(lua_State* ctx)
{
	LUA_TRACE("alloc_surface");
	int w = luaL_checknumber(ctx, 1);
	int h = luaL_checknumber(ctx, 2);

	bool noalpha = luaL_optbnumber(ctx, 3, 0);
	int quality = luaL_optnumber(ctx, 4, 0);

	if (w > MAX_SURFACEW || h > MAX_SURFACEH)
		arcan_fatal("alloc_surface(%d, %d) failed, unacceptable "
			"surface dimensions. Compile time restriction (%d,%d)\n",
			w, h, MAX_SURFACEW, MAX_SURFACEH);

	arcan_vobj_id rv;
	arcan_vobject* vobj = arcan_video_newvobject(&rv);
	if (!vobj){
		lua_pushvid(ctx, ARCAN_EID);
		LUA_ETRACE("alloc_surface", "out of vobj-ids", 1);
	}

	struct agp_vstore* ds = vobj->vstore;

/* the quality levels are defined to have the noalpha as + 1 */
	if (noalpha)
		quality++;

	agp_empty_vstoreext(ds, w, h, quality);

	vobj->origw = w;
	vobj->origh = h;
	vobj->order = 0;
	vobj->blendmode = BLEND_NORMAL;
	arcan_vint_attachobject(rv);

	lua_pushvid(ctx, rv);
	trace_allocation(ctx, "alloc_surface", rv);

	LUA_ETRACE("alloc_surface", NULL, 1);
}

static int fillsurface(lua_State* ctx)
{
	LUA_TRACE("fill_surface");
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};

	int desw = luaL_checknumber(ctx, 1);
	int desh = luaL_checknumber(ctx, 2);

	uint8_t r = abs((int)luaL_checknumber(ctx, 3));
	uint8_t g = abs((int)luaL_checknumber(ctx, 4));
	uint8_t b = abs((int)luaL_checknumber(ctx, 5));

	cons.w = abs((int)luaL_optnumber(ctx, 6, 8));
	cons.h = abs((int)luaL_optnumber(ctx, 7, 8));

	if (cons.w > 0 && cons.w <= MAX_SURFACEW &&
		cons.h > 0 && cons.h <= MAX_SURFACEH){

		av_pixel* buf = arcan_alloc_mem(cons.w * cons.h * sizeof(av_pixel),
			ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

		if (!buf)
			goto error;

		av_pixel* cptr = (av_pixel*) buf;

		for (size_t y = 0; y < cons.h; y++)
			for (size_t x = 0; x < cons.w; x++)
				*cptr++ = RGBA(r, g, b, 0xff);

		arcan_vobj_id id = arcan_video_rawobject(buf, cons, desw, desh, 0);

		lua_pushvid(ctx, id);
		trace_allocation(ctx, "fill_surface", id);
		LUA_ETRACE("fill_surface", NULL, 1);
	}
	else {
		arcan_fatal("fillsurface(%d, %d) failed, unacceptable "
			"surface dimensions. Compile time restriction (%d,%d)\n",
			desw, desh, MAX_SURFACEW, MAX_SURFACEH);
	}

error:
	LUA_ETRACE("fill_surface", "couldn't allocate buffer", 0);
}

static int imagemipmap(lua_State* ctx)
{
	LUA_TRACE("image_mipmap");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	bool state = luaL_checkbnumber(ctx, 1);
	arcan_video_mipmapset(id, state);
	LUA_ETRACE("image_mipmap", NULL, 0);
}

static int imagecolor(lua_State* ctx)
{
	LUA_TRACE("image_color");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	uint8_t cred = abs((int)luaL_checknumber(ctx, 2));
	uint8_t cgrn = abs((int)luaL_checknumber(ctx, 3));
	uint8_t cblu = abs((int)luaL_checknumber(ctx, 4));
	uint8_t alpha = abs((int)luaL_optnumber(ctx, 5, 255));

	if (vobj->vstore->txmapped){
		struct rendertarget* rtgt = arcan_vint_findrt(vobj);
		if (rtgt){
			agp_rendertarget_clearcolor(rtgt->art,
				(float)cred / 255.0f, (float)cgrn / 255.0f,
				(float)cblu / 255.0f, (float)alpha / 255.0f);
			lua_pushboolean(ctx, true);
			LUA_ETRACE("image_color", NULL, 1);
		}
		else {
			lua_pushboolean(ctx, false);
			LUA_ETRACE("image_color", "invalid image state", 1);
		}
	}

	vobj->vstore->vinf.col.r = (float)cred / 255.0f;
	vobj->vstore->vinf.col.g = (float)cgrn / 255.0f;
	vobj->vstore->vinf.col.b = (float)cblu / 255.0f;
	FLAG_DIRTY(vobj);

	lua_pushboolean(ctx, true);
	LUA_ETRACE("image_color", NULL, 1);
}

static int colorsurface(lua_State* ctx)
{
	LUA_TRACE("color_surface");

	size_t desw = abs((int)luaL_checknumber(ctx, 1));
	size_t desh = abs((int)luaL_checknumber(ctx, 2));
	uint8_t cred = abs((int)luaL_checknumber(ctx, 3));
	uint8_t cgrn = abs((int)luaL_checknumber(ctx, 4));
	uint8_t cblu = abs((int)luaL_checknumber(ctx, 5));
	int order = abs((int)luaL_optnumber(ctx, 6, 1));

	arcan_vobj_id id = arcan_video_solidcolor(
		desw, desh, cred, cgrn, cblu, order);
	lua_pushvid(ctx, id);
	trace_allocation(ctx, "color_surface", id);

	LUA_ETRACE("color_surface", NULL, 1);
}

static int nullsurface(lua_State* ctx)
{
	LUA_TRACE("null_surface");

	size_t desw = abs((int)luaL_checknumber(ctx, 1));
	size_t desh = abs((int)luaL_checknumber(ctx, 2));
	int order = abs((int)luaL_optnumber(ctx, 3, 1));

	arcan_vobj_id id = arcan_video_nullobject(desw, desh, order);
	lua_pushvid(ctx, id);

	trace_allocation(ctx, "null_surface", id);

	LUA_ETRACE("null_surface", NULL, 1);
}

static int rawsurface(lua_State* ctx)
{
	LUA_TRACE("raw_surface");

	int desw = luaL_checknumber(ctx, 1);
	int desh = luaL_checknumber(ctx, 2);
	int bpp  = luaL_checknumber(ctx, 3);

	const char* dumpstr = luaL_optstring(ctx, 5, NULL);

	if (bpp != 1 && bpp != 3 && bpp != 4)
		arcan_fatal("rawsurface(), invalid source channel count (%d)"
			"	accepted values: 1, 2, 4\n", bpp);

	img_cons cons = {.w = desw, .h = desh, .bpp = sizeof(av_pixel)};

	luaL_checktype(ctx, 4, LUA_TTABLE);
	int nsamples = lua_rawlen(ctx, 4);

	if (nsamples < desw * desh * bpp)
		arcan_fatal("rawsurface(), number of samples (%d) are less than"
			"	the expected length (%d).\n", nsamples, desw * desh * bpp);

	unsigned ofs = 1;

	if (desw < 0 || desh < 0 || desw > MAX_SURFACEW || desh > MAX_SURFACEH)
		arcan_fatal("rawsurface(), desired dimensions (%d x %d) "
			"exceed compile-time limits (%d x %d).\n",
			desw, desh, MAX_SURFACEW, MAX_SURFACEH
		);

	av_pixel* buf = arcan_alloc_mem(desw * desh * sizeof(av_pixel),
		ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

	av_pixel* cptr = (av_pixel*) buf;

	for (size_t y = 0; y < cons.h; y++)
		for (size_t x = 0; x < cons.w; x++){
			unsigned char r, g, b, a;
			switch(bpp){
			case 1:
				lua_rawgeti(ctx, 4, ofs++);
				r = lua_tonumber(ctx, -1);
				lua_pop(ctx, 1);
				*cptr++ = RGBA(r, r, r, 0xff);
			break;

			case 3:
				lua_rawgeti(ctx, 4, ofs++);
				r = lua_tonumber(ctx, -1);
				lua_rawgeti(ctx, 4, ofs++);
				g = lua_tonumber(ctx, -1);
				lua_rawgeti(ctx, 4, ofs++);
				b = lua_tonumber(ctx, -1);
				lua_pop(ctx, 3);
				*cptr++ = RGBA(r, g, b, 0xff);
			break;

			case 4:
				lua_rawgeti(ctx, 4, ofs++);
				r = lua_tonumber(ctx, -1);
				lua_rawgeti(ctx, 4, ofs++);
				g = lua_tonumber(ctx, -1);
				lua_rawgeti(ctx, 4, ofs++);
				b = lua_tonumber(ctx, -1);
				lua_rawgeti(ctx, 4, ofs++);
				a = lua_tonumber(ctx, -1);
				lua_pop(ctx, 4);
				*cptr++ = RGBA(r, g, b, a);
			}
		}

	if (dumpstr){
		char* fname = arcan_find_resource(dumpstr, RESOURCE_APPL_TEMP, ARES_FILE);
		if (fname){
			arcan_warning("rawsurface() -- refusing to "
				"overwrite existing file (%s)\n", fname);
		}
		else if ((fname = arcan_expand_resource(dumpstr, RESOURCE_APPL_TEMP))){
			FILE* fpek = fopen(fname, "wb");
			if (!fpek)
				arcan_warning("rawsurface() - - couldn't open (%s).\n", fname);
			else
				arcan_img_outpng(fpek, buf, desw, desh, 0);
			fclose(fpek);
		}
		arcan_mem_free(fname);
	}

	arcan_vobj_id id = arcan_video_rawobject(buf, cons, desw, desh, 0);

	lua_pushvid(ctx, id);
	trace_allocation(ctx, "raw_surface", id);
	LUA_ETRACE("raw_surface", NULL, 1);
}

#define STB_PERLIN_IMPLEMENTATION
#include "external/stb_perlin.h"
static int randomsurface(lua_State* ctx)
{
	LUA_TRACE("random_surface");

	size_t desw = abs((int)luaL_checknumber(ctx, 1));
	size_t desh = abs((int)luaL_checknumber(ctx, 2));
	img_cons cons = {.w = desw, .h = desh, .bpp = sizeof(av_pixel)};

	const char* method = luaL_optstring(ctx, 3, "normal");

	av_pixel* cptr = arcan_alloc_mem(desw * desh * sizeof(av_pixel),
		ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

	if (strcmp(method, "uniform-3") == 0){
		for (size_t y = 0; y < desh; y++)
			for (size_t x = 0; x < desw; x++){
				uint8_t rgb[3];
				arcan_random(rgb, 3);
				cptr[y * desw + x] = RGBA(rgb[0], rgb[1], rgb[2], 255);
		}
	}
	else if (strcmp(method, "uniform-4") == 0){
		for (size_t y = 0; y < desh; y++)
			for (size_t x = 0; x < desw; x++){
				arcan_random((uint8_t*)cptr, desw * desh * sizeof(av_pixel));
		}
	}
	else if (strcmp(method, "fbm") == 0){
		float lacunarity = luaL_checknumber(ctx, 4);
		float gain = luaL_checknumber(ctx, 5);
		float octaves = luaL_checknumber(ctx, 6);
		float xstart = luaL_checknumber(ctx, 7);
		float ystart = luaL_checknumber(ctx, 8);
		float zv = luaL_checknumber(ctx, 9);

		float sx = 1.0f / (float) desw;
		float sy = 1.0f / (float) desh;

		for (size_t y = 0; y < desh; y++)
			for (size_t x = 0; x < desw; x++){
	/* [-1, 1 -> 0, 1] -> 0..255 */
				float xv = (float)x * sx;
				float yv = (float)y * sy;
				float rv = 1.0 + stb_perlin_fbm_noise3(
					xv, yv, zv, lacunarity, gain, octaves, 0, 0, 0);
				uint8_t iv = rv / 2.0f * 255.0f;
				cptr[y * desw + x] = RGBA(iv, iv, iv, 255);
		}
	}
	else {
		for (size_t y = 0; y < desh; y++)
			for (size_t x = 0; x < desw; x++){
				uint8_t rv;
				arcan_random(&rv, 1);
				cptr[y * desw + x] = RGBA(rv, rv, rv, 255);
		}
	}

	arcan_vobj_id id = arcan_video_rawobject(cptr, cons, desw, desh, 0);
	arcan_video_objectfilter(id, ARCAN_VFILTER_NONE);
	lua_pushvid(ctx, id);

	trace_allocation(ctx, "random", id);
	LUA_ETRACE("random_surface", NULL, 1);
}

static char* filter_text(char* in, size_t* out_sz)
{
/* 1. a-Z, 0-9 + whitespace */
	char* work = in;
	while(*work){
		if (isalnum(*work) || isspace(*work))
			goto step;

		else switch (*work){
		case ',':
		case '.':
		case '!':
		case '/':
		case '\n':
		case '\t':
		case ';':
		case ':':
		case '(':
		case '\'':
		case '<':
		case '>':
		case ')':
		break;

		default:
		*work = ' ';
		break;
		}
step:
		work++;
	}

/* 2. strip leading */
	char* start = in;

	while(*start && isspace(*start))
		start++;

	*out_sz = strlen(start);

	if (*out_sz == 0)
		return start;

/* 3. strip trailing */
	work = start + *out_sz;
	while( (*work == '\0' || isspace(*work)) && *out_sz)
		work--, (*out_sz)--;

	if (*work != '\0')
		*(work+1) = '\0';

	return start;
}

static int warning(lua_State* ctx)
{
	LUA_TRACE("warning");

	size_t len;
	char* msg = (char*) luaL_checkstring(ctx, 1);
	msg = filter_text(msg, &len);

	if (len == 0){
		LUA_ETRACE("warning", "empty warning", 0);
	}

	arcan_warning("\n\x1b[1m(%s)\x1b[32m %s\x1b[0m\n", arcan_appl_id(), msg);

	LUA_ETRACE("warning", NULL, 0);
}

void arcan_lua_shutdown(lua_State* ctx)
{
/* deal with:
 * luactx : rawres, lastsrc, cb_source_kind, db_source_tag, last_segreq,
 * pending_socket_label, pending_socket_descr */
	lua_close(ctx);
}

void arcan_lua_dostring(lua_State* ctx, const char* code)
{
	(void)luaL_dostring(ctx, code);
}

lua_State* arcan_lua_alloc()
{
	lua_State* res = luaL_newstate();

/* in the future, we need a hook here to
 * limit / "null-out" the undesired subset of the LUA API */
	if (res){
		luaL_openlibs(res);
		arcan_lua_pushglobalconsts(res);
	}

	luactx.last_ctx = res;
	return res;
}

void arcan_lua_mapfunctions(lua_State* ctx, int debuglevel)
{
	luaL_nil_banned(ctx);
	arcan_lua_exposefuncs(ctx, debuglevel);
/* update with debuglevel etc. */
	arcan_lua_pushglobalconsts(ctx);
}

/* alua_ namespace due to winsock pollution */
static int alua_shutdown(lua_State *ctx)
{
	LUA_TRACE("shutdown");

	arcan_event ev = {
		.category = EVENT_SYSTEM,
		.sys.kind = EVENT_SYSTEM_EXIT,
		.sys.errcode = luaL_optnumber(ctx, 2, EXIT_SUCCESS)
	};
	arcan_event_enqueue(arcan_event_defaultctx(), &ev);

	size_t tlen;
	const char* str = filter_text((char*)luaL_optstring(ctx, 1, ""), &tlen);
	if (tlen > 0)
		arcan_warning("%s\n", str);

	LUA_ETRACE("shutdown", NULL, 0);
}

static void panic(lua_State* ctx)
{
	luactx.debug = 2;

	if (luactx.cb_source_kind != CB_SOURCE_NONE){
		char vidbuf[64] = {0};
		snprintf(vidbuf, 63, "script error in callback for VID (%"PRIxVOBJ")",
			luactx.lua_vidbase + luactx.cb_source_tag);
		wraperr(ctx, -1, vidbuf);
	} else{
		luactx.in_panic = true;
		wraperr(ctx, -1, "(panic)");
	}

	arcan_warning("LUA VM is in a panic state, "
		"recovery handover might be impossible.\n");

	luactx.last_crash_source = "VM panic";
	longjmp(arcanmain_recover_state, 3);
}

/*
 * never call wraperr with a dynamic src argument, it needs to be
 * available for the lifespan of the program as it us also used to
 * propagate crash information between recovery states
 */
static void wraperr(lua_State* ctx, int errc, const char* src)
{
	if (luactx.debug)
		luactx.lastsrc = src;

	if (errc == 0)
		return;

	const char* mesg = luactx.in_panic ? "Lua VM state broken, panic" :
		luaL_optstring(ctx, -1, "unknown");
/*
 * currently unused, pending refactor of arcan_warning
 * int severity = luaL_optnumber(ctx, 2, 0);
 */

	arcan_state_dump("crash", mesg, src);

	if (luactx.debug){
		arcan_warning("Warning: wraperr((), %s, from %s\n", mesg, src);

		if (luactx.debug >= 1)
			dump_call_trace(ctx);

		if (luactx.debug > 0)
			dump_stack(ctx);

		if (luactx.debug > 2){
			arcan_warning("Fatal error ignored(%s, %s) through high debuglevel,"
				" attempting to continue.\n", mesg, src);
			return;
		}
	}

	arcan_warning("\n\x1b[1mScript failure:\n \x1b[32m %s\n"
		"\x1b[39mC-entry point: \x1b[32m %s \x1b[39m\x1b[0m.\n", mesg, src);

	arcan_warning("\nHanding over to recovery script "
		"(or shutdown if none present).\n");

	luactx.last_crash_source = src;
	longjmp(arcanmain_recover_state, 3);
}

struct globs{
	lua_State* ctx;
	int top;
	int index;
};

static void globcb(char* arg, void* tag)
{
	struct globs* bptr = (struct globs*) tag;

	lua_pushnumber(bptr->ctx, bptr->index++);
	lua_pushstring(bptr->ctx, arg);
	lua_rawset(bptr->ctx, bptr->top);
}

static int globresource(lua_State* ctx)
{
	LUA_TRACE("glob_resource");

	struct globs bptr = {
		.ctx = ctx,
		.index = 1
	};

	char* label = (char*) luaL_checkstring(ctx, 1);
	int mask = luaL_optinteger(ctx, 2, DEFAULT_USERMASK &
		(DEFAULT_USERMASK | RESOURCE_APPL_STATE |
		RESOURCE_SYS_APPLBASE | RESOURCE_SYS_FONT)
	);

	lua_newtable(ctx);
	bptr.top = lua_gettop(ctx);

	arcan_glob(label, mask, globcb, &bptr);

	LUA_ETRACE("glob_resource", NULL, 1);
}

static int resource(lua_State* ctx)
{
	LUA_TRACE("resource");

	const char* label = luaL_checkstring(ctx, 1);
/* can only be used to test for resource so don't & against mask */
	int mask = luaL_optinteger(ctx, 2, DEFAULT_USERMASK);
	char* res = arcan_find_resource(label, mask, ARES_FILE | ARES_FOLDER);
	if (!res){
		lua_pushstring(ctx, res);
		lua_pushstring(ctx, "not found");
	}
	else{
		lua_pushstring(ctx, res);
		lua_pushstring(ctx, arcan_isdir(res) ? "directory" : "file");
		arcan_mem_free(res);
	}

	LUA_ETRACE("resource", NULL, 2);
}

static int screencoord(lua_State* ctx)
{
	LUA_TRACE("image_screen_coordinates");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);

	vector cv[4];
	if (ARCAN_OK == arcan_video_screencoords(id, cv)){
		lua_pushnumber(ctx, cv[0].x);
		lua_pushnumber(ctx, cv[0].y);
		lua_pushnumber(ctx, cv[1].x);
		lua_pushnumber(ctx, cv[1].y);
		lua_pushnumber(ctx, cv[2].x);
		lua_pushnumber(ctx, cv[2].y);
		lua_pushnumber(ctx, cv[3].x);
		lua_pushnumber(ctx, cv[3].y);
		LUA_ETRACE("image_screen_coordinates", NULL, 8);
	}

	LUA_ETRACE("image_screen_coordinates", "couldn't resolve", 0);
}

bool arcan_lua_callvoidfun(lua_State* ctx,
	const char* fun, bool warn, const char** argv)
{
	if ( grabapplfunction(ctx, fun, strlen(fun)) ){
		int argc = 0;
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		while (argv && argv[argc]){
			lua_pushnumber(ctx, argc+1);
			lua_pushstring(ctx, argv[argc++]);
			lua_rawset(ctx, top);
		}

		wraperr(ctx, lua_pcall(ctx, 1, 0, 0), fun);
		return true;
	}
	else if (warn)
		arcan_warning("missing expected symbol ( %s )\n", fun);

	return false;
}

static int targethandler(lua_State* ctx)
{
	LUA_TRACE("target_updatehandler");
	arcan_vobject* vobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);

/* unreference the old one so we don't leak */
	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("target_updatehandler(), specified vid (arg 1) not "
			"associated with a frameserver.");

	arcan_frameserver* fsrv = vobj->feed.state.ptr;
	if (!fsrv)
		arcan_fatal("target_updatehandler(), specified vid (arg 1) is not"
			" associated with a frameserver.");

	if (fsrv->tag != (intptr_t)LUA_NOREF){
		luaL_unref(ctx, LUA_REGISTRYINDEX, fsrv->tag);
	}

	intptr_t ref = find_lua_callback(ctx);

	fsrv->tag = ref;

#ifndef offsetof
#define offsetof(type, member) ((size_t)((char*)&(*(type*)0).member\
 - (char*)&(*(type*)0)))
#endif

	arcan_event dummy;

	assert(sizeof(dummy.fsrv.otag) == sizeof(ref));

/* for the already pending events referring to the specific frameserver,
 * rewrite the otag to match that of the new function */
	arcan_event_repl(arcan_event_defaultctx(), EVENT_FSRV,
		offsetof(arcan_event, fsrv.video),
		sizeof(arcan_vobj_id), &id,
		offsetof(arcan_event, fsrv.otag),
		sizeof(dummy.fsrv.otag),
		&ref
	);

	LUA_ETRACE("target_updatehandler", NULL, 0);
}

static int targetpacify(lua_State* ctx)
{
	LUA_TRACE("pacify_target");
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV || !vobj->feed.state.ptr)
		arcan_fatal("target_pacify(), specified vid (arg 1) not "
			"associated with a frameserver.");

	arcan_frameserver* fsrv = vobj->feed.state.ptr;
/*
 * don't want the event to propagate for terminated here
 */
	fsrv->tag = (intptr_t) LUA_NOREF;

	arcan_frameserver_free(fsrv);
	vobj->feed.state.ptr = NULL;
	vobj->feed.state.tag = ARCAN_TAG_IMAGE;

	LUA_ETRACE("pacify_target", NULL, 0);
}

static int targetportcfg(lua_State* ctx)
{
	LUA_TRACE("target_portconfig");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	unsigned tgtport  = luaL_checkinteger(ctx, 2);
	unsigned tgtkind  = luaL_checkinteger(ctx, 3);

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_SETIODEV
	};

	ev.tgt.ioevs[0].iv = tgtport;
	ev.tgt.ioevs[1].iv = tgtkind;

	tgtevent(tgt, ev);

	LUA_ETRACE("target_portconfig", NULL, 0);
}

static int layout_tonum(const char* layout)
{
	if (!layout || strcmp(layout, "hRGB") == 0)
		return 0;
	else if (strcmp(layout, "hBGR") == 0)
		return 1;
	else if (strcmp(layout, "vRGB") == 0)
		return 2;
	else if (strcmp(layout, "vBGR") == 0)
		return 3;
	return 0;
}

static int targetfonthint(lua_State* ctx)
{
/* (dstfsrv, [fontstr], size (pt), hinting -1 or (0..5), merge */
	LUA_TRACE("target_fonthint");
	arcan_vobject* vobj;
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, &vobj);
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	int numind = 2;
	file_handle fd = BADFD;

	if (!fsrv || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
		arcan_fatal("target_fonthint() -- " FATAL_MSG_FRAMESERV);
	}

/* some cases implies 'change current font size or hinting without
 * changing font', hence why we begin with an optional string arg. */
	if (lua_type(ctx, numind) == LUA_TSTRING){
		const char* instr = luaL_checkstring(ctx, numind);
		numind++;
		if (strcmp(instr, ".default") == 0){
			arcan_video_fontdefaults(&fd, NULL, NULL);
		}
		else{
			char* fname = arcan_expand_resource(instr, RESOURCE_SYS_FONT);
			if (fname && arcan_isfile(fname))
				fd = open(fname, O_RDONLY | O_CLOEXEC);
			arcan_mem_free(fname);
			if (BADFD == fd){
				lua_pushboolean(ctx, false);
				LUA_ETRACE("target_fonthint", "font could not be opened", 1);
			}
		}
	}

	arcan_event outev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_FONTHINT,
		.tgt.ioevs[1].iv = fd != BADFD ? 1 : 0,
		.tgt.ioevs[2].fv = luaL_checknumber(ctx, numind),
		.tgt.ioevs[3].iv = luaL_checknumber(ctx, numind+1),
		.tgt.ioevs[4].iv = luaL_optbnumber(ctx, numind+2, 0)
	};

	if (fd != BADFD){
		lua_pushboolean(ctx, platform_fsrv_pushfd(fsrv, &outev, fd));
		close(fd);
	}
	else{
		lua_pushboolean(ctx, ARCAN_OK == platform_fsrv_pushevent(fsrv, &outev));
	}

	LUA_ETRACE("target_fonthint", NULL, 1);
}

static int xlt_dev(int inv)
{
	switch(inv){
	case CONST_DEVICE_DIRECT:
		return 1;
	case CONST_DEVICE_LOST:
		return 2;
	case CONST_DEVICE_INDIRECT:
	default:
		return 0;
	}
}

static int targetdevhint(lua_State* ctx)
{
	LUA_TRACE("target_devicehint");
	arcan_vobject* vobj;
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, &vobj);
	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("target_devicehint(), vid not connected to a frameserver\n");

	arcan_frameserver* fsrv = (arcan_frameserver*) vobj->feed.state.ptr;

/* 1: node-switch (>0) or render-mode switch (-1) only */
	int type = lua_type(ctx, 2);
	if (type == LUA_TNUMBER){
		int num = luaL_checknumber(ctx, 2);
		if (num < 0){
			platform_fsrv_pushevent(fsrv, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_DEVICE_NODE,
				.tgt.ioevs[0].iv = BADFD,
				.tgt.ioevs[1].iv = 1,
				.tgt.ioevs[2].iv = xlt_dev(luaL_optnumber(ctx, 2, DEVICE_INDIRECT))
			});
		}
		else {
			struct arcan_event ev;
			int method;
			size_t buf_sz;
			uint8_t* buf;
			int fd = platform_video_cardhandle(num, &method, &buf_sz, &buf);
			if (-1 == fd){
				arcan_warning("target_devicehint(), invalid card index specified\n");
				LUA_ETRACE("target_device", "invalid card index", 0);
			}

			if (buf_sz > sizeof(ev.tgt.message)){
				arcan_warning("target_devicehint(). clamping modifier size (%zu)\n");
				buf_sz = sizeof(ev.tgt.message);
			}

			ev = (struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_DEVICE_NODE,
				.tgt.ioevs[1].iv = 1,
				.tgt.ioevs[2].iv = xlt_dev(luaL_optnumber(ctx, 2, DEVICE_INDIRECT)),
				.tgt.ioevs[3].iv = method,
				.tgt.ioevs[4].iv = buf_sz
			};
			memcpy(ev.tgt.message, buf, buf_sz);
			arcan_mem_free(buf);
			platform_fsrv_pushfd(fsrv, &ev, fd);
		}
	}
	else if (type == LUA_TSTRING){
/* empty string is allowed for !force (disable alt-conn) */
		const char* cpath = luaL_checkstring(ctx, 2);
		bool force = luaL_optbnumber(ctx, 3, false);
		struct arcan_event outev = {
			.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_DEVICE_NODE,
			.tgt.ioevs[0].iv = BADFD,
			.tgt.ioevs[1].iv = force ? 2 : 4,
			.tgt.ioevs[2].uiv = (fsrv->guid[0] & 0xffffffff),
			.tgt.ioevs[3].uiv = (fsrv->guid[0] >> 32),
			.tgt.ioevs[4].uiv = (fsrv->guid[1] & 0xffffffff),
			.tgt.ioevs[5].uiv = (fsrv->guid[1] >> 32)
		};
		if (force && strlen(cpath) == 0)
			arcan_fatal("target_devicehint(), forced migration connpath len == 0\n");
		snprintf(outev.tgt.message, COUNT_OF(outev.tgt.message), "%s", cpath);
		platform_fsrv_pushevent(fsrv, &outev);
	}
	else
		arcan_fatal("target_devicehint");

	LUA_ETRACE("target_devicehint", NULL, 0);
}

static int targetdisphint(lua_State* ctx)
{
	LUA_TRACE("target_displayhint");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);

	int width = luaL_checknumber(ctx, 2);
	int height = luaL_checknumber(ctx, 3);
	int cont = luaL_optnumber(ctx, 4, 128);

/* clamp to not have client propagate illegal dimensions */
	width = width > ARCAN_SHMPAGE_MAXW ? ARCAN_SHMPAGE_MAXW : width;
	height = height > ARCAN_SHMPAGE_MAXH ? ARCAN_SHMPAGE_MAXH : height;

/* we support explicit displayhint or just passing a mode table that comes from
 * a monitor / display event (though width/height/flags need to be specified
 * still) */
	int phy_lay = 0;
	float ppcm = 0;

	int type = lua_type(ctx, 5);
	if (type == LUA_TNUMBER && ARCAN_VIDEO_WORLDID == luaL_checknumber(ctx, 5)){
		struct monitor_mode mmode = platform_video_dimensions();
		int lw = mmode.width;
		int phy_w = mmode.phy_width;
		if (lw && phy_w)
			ppcm = 10.0f * ((float)lw / (float)phy_w);
		phy_w = mmode.width;
		phy_lay = layout_tonum(mmode.subpixel);
		tgtevent(tgt, (arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_OUTPUTHINT,
			.tgt.ioevs[0].iv = mmode.width,
			.tgt.ioevs[1].iv = mmode.height,
			.tgt.ioevs[2].iv = mmode.refresh,
			.tgt.ioevs[3].iv = 32,
			.tgt.ioevs[4].iv = 32
		});
	}
	else if (type == LUA_TTABLE){
		float nv = intblfloat(ctx, 5, "ppcm");
		if (nv > 10)
			ppcm = nv;
		else {
			arcan_warning("target_displayhint(), display table provided "
				"but with broken / bad ppcm field, ignoring\n");
		}

		int width = intblint(ctx, 5, "width");
		int height = intblint(ctx, 5, "height");
		int refresh = intblint(ctx, 5, "refresh");
		int minw = intblint(ctx, 5, "min_width");
		int minh = intblint(ctx, 5, "min_height");

		if (-1 == refresh)
			refresh = 60;

		if (-1 == minw)
			minw = 32;

		if (-1 == minh)
			minh = 32;

		if (width > 0 && height > 0){
			tgtevent(tgt, (arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_OUTPUTHINT,
				.tgt.ioevs[0].iv = width,
				.tgt.ioevs[1].iv = height,
				.tgt.ioevs[2].iv = refresh,
				.tgt.ioevs[3].iv = minw,
				.tgt.ioevs[4].iv = minh
			});
		}

		phy_lay = layout_tonum(intblstr(ctx, 5, "subpixel_layout"));
	}
	else
		;

	if (width < 0 || height < 0)
		arcan_fatal("target_disphint(%d, %d), "
			"display dimensions must be >= 0", width, height);

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_DISPLAYHINT,
		.tgt.ioevs[0].iv = width,
		.tgt.ioevs[1].iv = height,
		.tgt.ioevs[2].iv = cont,
		.tgt.ioevs[3].iv = phy_lay,
		.tgt.ioevs[4].fv = ppcm
	};
	tgtevent(tgt, ev);

	LUA_ETRACE("target_displayhint", NULL, 0);
}

static int targetgraph(lua_State* ctx)
{
	LUA_TRACE("target_graphmode");

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_GRAPHMODE,
		.tgt.ioevs[0].iv = luaL_checkinteger(ctx, 2),
		.tgt.ioevs[1].fv = luaL_optnumber(ctx, 3, 0.0),
		.tgt.ioevs[2].fv = luaL_optnumber(ctx, 4, 0.0),
		.tgt.ioevs[3].fv = luaL_optnumber(ctx, 5, 0.0),
		.tgt.ioevs[4].fv = luaL_optnumber(ctx, 6, 0.0)
	};

	tgtevent(luaL_checkvid(ctx, 1, NULL), ev);

	LUA_ETRACE("target_graphmode", NULL, 0);
}

static int targetcoreopt(lua_State* ctx)
{
	LUA_TRACE("target_coreopt");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_COREOPT
	};

	ev.tgt.code = luaL_checknumber(ctx, 2);
	const char* msg = luaL_checkstring(ctx, 3);

	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", msg);
	tgtevent(tgt, ev);

	LUA_ETRACE("target_coreopt", NULL, 0);
}

static int targetparent(lua_State* ctx)
{
	LUA_TRACE("target_parent");
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	vfunc_state* state = arcan_video_feedstate(tgt);

	if (!(state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr)){
		lua_pushvid(ctx, ARCAN_EID);
	}
	else {
		arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;
		lua_pushvid(ctx, fsrv->parent.vid);
	}

	LUA_ETRACE("target_parent", NULL, 1);
}

static int targetseek(lua_State* ctx)
{
	LUA_TRACE("target_seek");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	float val = luaL_checknumber(ctx, 2);
	bool relative = luaL_optbnumber(ctx, 3, true);
	bool time = luaL_optnumber(ctx, 3, true);

	vfunc_state* state = arcan_video_feedstate(tgt);

	if (time){
		arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_SEEKTIME
		};

		ev.tgt.ioevs[0].iv = relative;
		ev.tgt.ioevs[1].fv = val;
		tgtevent(tgt, ev);
	}
	else {
		arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_SEEKCONTENT
		};

		ev.tgt.ioevs[0].iv = relative;
		if (relative){
			ev.tgt.ioevs[1].iv = val;
			ev.tgt.ioevs[2].iv = luaL_optnumber(ctx, 4, 0);
		}
		else {
			ev.tgt.ioevs[1].fv = val;
			ev.tgt.ioevs[2].fv = luaL_optnumber(ctx, 4, -1);
		}
		tgtevent(tgt, ev);
	}

	LUA_ETRACE("target_seek", NULL, 0);
}

enum target_flags {
	TARGET_FLAG_SYNCHRONOUS = 1,
	TARGET_FLAG_NO_ALPHA_UPLOAD,
	TARGET_FLAG_VERBOSE,
	TARGET_FLAG_VSTORE_SYNCH,
	TARGET_FLAG_AUTOCLOCK,
	TARGET_FLAG_NO_BUFFERPASS,
	TARGET_FLAG_ALLOW_CM,
	TARGET_FLAG_ALLOW_HDRF16,
	TARGET_FLAG_ALLOW_LDEF,
	TARGET_FLAG_ALLOW_VOBJ,
	TARGET_FLAG_ALLOW_INPUT,
	TARGET_FLAG_ALLOW_GPUAUTH,
	TARGET_FLAG_LIMIT_SIZE,
	TARGET_FLAG_ENDM
};

static void updateflag(arcan_vobj_id vid, enum target_flags flag, bool toggle)
{
	vfunc_state* state = arcan_video_feedstate(vid);

	if (!(state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr)){
		arcan_warning("updateflag() vid(%"PRIxVOBJ") is not "
			"connected to a frameserver\n", vid);
		return;
	}

	arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;

	switch (flag){
	case TARGET_FLAG_SYNCHRONOUS:
		fsrv->flags.explicit = toggle;
	break;

	case TARGET_FLAG_VERBOSE:
		fsrv->desc.callback_framestate = toggle;
	break;

	case TARGET_FLAG_VSTORE_SYNCH:
		fsrv->flags.local_copy = toggle;
	break;

	case TARGET_FLAG_NO_ALPHA_UPLOAD:
		fsrv->flags.no_alpha_copy = toggle;
	break;

	case TARGET_FLAG_AUTOCLOCK:
		fsrv->flags.autoclock = toggle;
	break;

	case TARGET_FLAG_ALLOW_GPUAUTH:
		fsrv->flags.gpu_auth = toggle;
	break;

	case TARGET_FLAG_NO_BUFFERPASS:
		fsrv->vstream.dead = toggle;
	break;

	case TARGET_FLAG_ALLOW_CM:
		if (toggle)
			fsrv->metamask |= SHMIF_META_CM;
		else
			fsrv->metamask &= ~SHMIF_META_CM;
	break;

	case TARGET_FLAG_ALLOW_HDRF16:
		if (toggle)
			fsrv->metamask |= SHMIF_META_HDRF16;
		else
			fsrv->metamask &= ~SHMIF_META_HDRF16;
	break;

	case TARGET_FLAG_ALLOW_LDEF:
		if (toggle)
			fsrv->metamask |= SHMIF_META_LDEF;
		else
			fsrv->metamask &= ~SHMIF_META_LDEF;
	break;

	case TARGET_FLAG_ALLOW_VOBJ:
		if (toggle)
			fsrv->metamask |= SHMIF_META_VOBJ;
		else
			fsrv->metamask &= ~SHMIF_META_VOBJ;
	break;

	case TARGET_FLAG_ALLOW_INPUT:
		if (toggle)
			fsrv->queue_mask |= EVENT_IO;
		else
			fsrv->queue_mask &= ~EVENT_IO;
	break;

/* handle elsewhere */
	case TARGET_FLAG_LIMIT_SIZE:
	break;

	case TARGET_FLAG_ENDM:
	break;
	}

}

static int targetflags(lua_State* ctx)
{
	LUA_TRACE("target_flags");
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	enum target_flags flag = luaL_checknumber(ctx, 2);
	if (flag < TARGET_FLAG_SYNCHRONOUS || flag >= TARGET_FLAG_ENDM)
		arcan_fatal("target_flags() unknown flag value (%d)\n", flag);

/* Limit size is somewhat special in that it takes dimensions, not a flag size.
 * Using this function for this particular purpose is somewhat odd, but
 * contextually a better fit than display- or output hint as this is not
 * something that will be propagated to the client. */

	if (flag == TARGET_FLAG_LIMIT_SIZE){
		vfunc_state* state = arcan_video_feedstate(tgt);
		size_t max_w = luaL_checknumber(ctx, 3);
		size_t max_h = luaL_checknumber(ctx, 4);
		if (!(state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr)){
			arcan_warning("updateflag() vid(%"PRIxVOBJ") is not "
				"connected to a frameserver\n", tgt);
		}
		else {
			arcan_frameserver* s = (arcan_frameserver*) state->ptr;
			s->max_w = max_w;
			s->max_h = max_h;
		}
	}
	else {
	 	bool toggle = luaL_optbnumber(ctx, 3, 1);
		updateflag(tgt, flag, toggle);
	}
	LUA_ETRACE("target_flags", NULL, 0);
}

static int targetsynchronous(lua_State* ctx)
{
	LUA_TRACE("target_synchronous");
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
 	bool toggle = luaL_optbnumber(ctx, 2, 1);
	updateflag(tgt, TARGET_FLAG_SYNCHRONOUS, toggle);
	LUA_ETRACE("target_synchronous", NULL, 0);
}

static int targetverbose(lua_State* ctx)
{
	LUA_TRACE("target_verbose");
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
 	bool toggle = luaL_optbnumber(ctx, 2, 1);
	updateflag(tgt, TARGET_FLAG_VERBOSE, toggle);
	LUA_ETRACE("target_verbose", NULL, 0);
}

static int targetskipmodecfg(lua_State* ctx)
{
	LUA_TRACE("target_framemode");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	int skipval       = luaL_checkinteger(ctx, 2);
	int skiparg       = luaL_optinteger(ctx, 3, 0);
	int preaud        = luaL_optinteger(ctx, 4, 0);
	int skipdbg1      = luaL_optinteger(ctx, 5, 0);
	int skipdbg2      = luaL_optinteger(ctx, 6, 0);

	if (skipval < -1){
		LUA_ETRACE("target_framemode", "unsupported value for skip", 0);
	}

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_FRAMESKIP
	};

	ev.tgt.ioevs[0].iv = skipval;
	ev.tgt.ioevs[1].iv = skiparg;
	ev.tgt.ioevs[2].iv = preaud;
	ev.tgt.ioevs[3].iv = skipdbg1;
	ev.tgt.ioevs[4].iv = skipdbg2;

	tgtevent(tgt, ev);

	LUA_ETRACE("target_framemode", NULL, 0);
}

static int targetbond(lua_State* ctx)
{
	LUA_TRACE("bond_target");
	arcan_vobject* vobj_a;
	arcan_vobject* vobj_b;

/* a state to b */
	luaL_checkvid(ctx, 1, &vobj_a);
	luaL_checkvid(ctx, 2, &vobj_b);

	if (vobj_a->feed.state.tag != ARCAN_TAG_FRAMESERV ||
		vobj_b->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("bond_target(), both arguments must be valid frameservers.\n");

/* if target_a is net or target_b is net, a possible third argument
 * may be added to specify which domain that should receive the state
 * in question */
	int pair[2];
	if (pipe(pair) == -1){
		arcan_warning("bond_target(), pipe pair failed."
			" Reason: %s\n", strerror(errno));
		LUA_ETRACE("bond_target", "pipe failed", 0);
	}

	arcan_frameserver* fsrv_a = vobj_a->feed.state.ptr;
	arcan_frameserver* fsrv_b = vobj_b->feed.state.ptr;

	arcan_event ev = {.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_STORE};

	platform_fsrv_pushfd(fsrv_a, &ev, pair[0]);

	ev.tgt.kind = TARGET_COMMAND_RESTORE;
	platform_fsrv_pushfd(fsrv_b, &ev, pair[1]);

	close(pair[0]);
	close(pair[1]);

	LUA_ETRACE("bond_target", NULL, 0);
}

static int targetrestore(lua_State* ctx)
{
	LUA_TRACE("restore_target");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	const char* snapkey = luaL_checkstring(ctx, 2);

	vfunc_state* state = arcan_video_feedstate(tgt);
	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("restore_target", "invalid feedstate", 1);
	}

	char* fname = arcan_find_resource(snapkey, RESOURCE_APPL_STATE, ARES_FILE);
	int fd = -1;
	if (fname)
		fd = open(fname, O_CLOEXEC |O_RDONLY);
	free(fname);

	if (-1 == fd){
		arcan_warning("couldn't load / resolve (%s)\n", snapkey);
		lua_pushboolean(ctx, false);
		LUA_ETRACE("restore_target", "could not load file", 1);
	}

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_RESTORE
	};
	arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;
	lua_pushboolean(ctx, ARCAN_OK == platform_fsrv_pushfd(fsrv, &ev, fd));
	close(fd);

	LUA_ETRACE("restore_target", NULL, 1);
}

static int targetstepframe(lua_State* ctx)
{
	LUA_TRACE("stepframe_target");

	arcan_vobject* vobj;
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, &vobj);
	vfunc_state* state = arcan_video_feedstate(tgt);
	struct rendertarget* rtgt = arcan_vint_findrt(vobj);

	bool qev = true;
	int nframes = luaL_optnumber(ctx, 2, 1);

/* cascade / repeat call protection */
	if (rtgt){
		if (!FL_TEST(rtgt, TGTFL_READING)){
			agp_request_readback(rtgt->color->vstore);
			FL_SET(rtgt, TGTFL_READING);
		}

/* for rendertargets, we don't want to rely on the synchronous flag
 * for this behavior, so better to use as an argument */
		if (luaL_optbnumber(ctx, 3, false))
			while (FL_TEST(rtgt, TGTFL_READING))
				arcan_vint_pollreadback(rtgt);
	}

/*
 * Recordtargets are a special case as they have both a frameserver feedstate
 * and the output of a rendertarget.  The actual stepframe event will be set by
 * the ffunc handler (arcan_frameserver_backend.c)
 */
	if (state->tag == ARCAN_TAG_FRAMESERV && !rtgt){
		arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_STEPFRAME
		};
		ev.tgt.ioevs[0].iv = nframes;
		ev.tgt.ioevs[1].iv = luaL_optnumber(ctx, 3, 0);
		tgtevent(tgt, ev);
	}

	LUA_ETRACE("stepframe_target", NULL, 0);
}

static int targetsnapshot(lua_State* ctx)
{
	LUA_TRACE("snapshot_target");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	const char* snapkey = luaL_checkstring(ctx, 2);

	vfunc_state* state = arcan_video_feedstate(tgt);
	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("snapshot_target", "invalid feedstate", 1);
	}
	arcan_frameserver* fsrv = state->ptr;

	char* fname = arcan_expand_resource(snapkey, RESOURCE_APPL_STATE);
	int fd = -1;
	if (fname)
		fd = open(fname, O_CREAT | O_WRONLY |
			O_TRUNC | O_CLOEXEC, S_IRUSR | S_IWUSR);
	arcan_mem_free(fname);

	if (-1 == fd){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("snapshot_target", "couldn't open file", 1);
	}

	arcan_event ev = {
		.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_STORE
	};
	lua_pushboolean(ctx, platform_fsrv_pushfd(fsrv, &ev, fd));
	close(fd);
	LUA_ETRACE("snapshot_target", NULL, 1);
}

static int targetreset(lua_State* ctx)
{
	LUA_TRACE("reset_target");

	arcan_vobject* vobj;
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, &vobj);
	arcan_event ev = {
		.tgt.kind = TARGET_COMMAND_RESET,
		.category = EVENT_TARGET
	};

	if (vobj && vobj->feed.state.tag == ARCAN_TAG_VR){
		arcan_vr_setref(vobj->feed.state.ptr);
	}
	else
		tgtevent(vid, ev);

	LUA_ETRACE("reset_target", NULL, 0);
}

/*
 * Wrapper around the allocation so we behave consistently in all the places
 * that allocates using this function.
 */
static arcan_frameserver* spawn_subsegment(
	struct arcan_frameserver* parent, enum ARCAN_SEGID segid,
	uint32_t reqid, int w, int h)
{
/* clip to limits */
	if (w > ARCAN_SHMPAGE_MAXW)
		w = ARCAN_SHMPAGE_MAXW;
	if (h > ARCAN_SHMPAGE_MAXH)
		h = ARCAN_SHMPAGE_MAXH;

/* first allocate the vobj, note that we need to update when we have the ptr */
	img_cons cons = {.w = w, .h = h, .bpp = ARCAN_SHMPAGE_VCHANNELS};
	vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = NULL};
	arcan_vobj_id newvid = arcan_video_addfobject(FFUNC_VFRAME, state, cons, 0);
	if (newvid == ARCAN_EID){
		return NULL;
	}

	arcan_frameserver* res =
		platform_fsrv_spawn_subsegment(parent, segid, w, h, newvid, reqid);

	if (!res){
		arcan_video_deleteobject(newvid);
		return NULL;
	}

/* now we have a new frameserver reference, add this to our fobject */
	state.ptr = res;
	res->vid = newvid;
	arcan_video_alterfeed(newvid, FFUNC_VFRAME, state);

/* encoder doesn't need a playback or audio control ID, those go via the
 * frameserver-bound recordtarget if mixing weights need to change */
	arcan_errc errc;
	if (segid != SEGID_ENCODER)
		res->aid = arcan_audio_feed((arcan_afunc_cb)
			arcan_frameserver_audioframe_direct, res, &errc);

	arcan_conductor_register_frameserver(res);

	return res;
}

static int targetaccept(lua_State* ctx)
{
	LUA_TRACE("accept_target");

	if (!luactx.last_segreq)
		arcan_fatal("accept_target(), only permitted inside a segment_request.\n");

	uint16_t w = luactx.last_segreq->segreq.width;
	uint16_t h = luactx.last_segreq->segreq.height;

	if (lua_isnumber(ctx, 1))
		w = lua_tonumber(ctx, 1);

	if (lua_isnumber(ctx, 2))
		h = lua_tonumber(ctx, 2);

	enum ARCAN_SEGID segid = luactx.last_segreq->segreq.kind;
	vfunc_state* prev_state = arcan_video_feedstate(luactx.last_segreq->source);
	arcan_frameserver* newref = spawn_subsegment(
		(arcan_frameserver*) prev_state->ptr,
		segid, luactx.last_segreq->segreq.id, w, h
	);

	if (!newref){
		lua_pushvid(ctx, ARCAN_EID);
		lua_pushaid(ctx, ARCAN_EID);
		lua_pushnumber(ctx, 0);
		LUA_ETRACE("accept_target", "couldn't allocate frameserver", 3);
	}
	newref->tag = find_lua_callback(ctx);

/*
 * special handling so that we don't get directly into a negotiated video or
 * encode feed function
 */
	if (segid == SEGID_HANDOVER){
		arcan_video_alterfeed(newref->vid, FFUNC_NULLFRAME, (vfunc_state){
			.tag = ARCAN_TAG_FRAMESERV, .ptr = newref
		});
	}

	lua_pushvid(ctx, newref->vid);
	lua_pushaid(ctx, newref->aid);
	lua_pushnumber(ctx, newref->cookie);
	luactx.last_segreq = NULL;
	trace_allocation(ctx, "subseg", newref->vid);

	LUA_ETRACE("accept_target", NULL, 3);
}

static int targetalloc(lua_State* ctx)
{
	LUA_TRACE("target_alloc");
	int cb_ind = 2;
	char* pw = NULL;

	if (lua_type(ctx, 2) == LUA_TSTRING){
		pw = (char*) luaL_checkstring(ctx, 2);
		size_t pwlen = strlen(pw);
		if (pwlen > PP_SHMPAGE_SHMKEYLIM-1){
			arcan_warning(
				"target_alloc(), requested passkey length (%d) exceeds "
				"built-in threshold (%d characters) and will be truncated .\n",
				pwlen, pw);

			pw[PP_SHMPAGE_SHMKEYLIM-1] = '\0';
		}
		else
			cb_ind = 3;
	}

	luaL_checktype(ctx, cb_ind, LUA_TFUNCTION);
	if (lua_iscfunction(ctx, cb_ind))
		arcan_fatal("target_alloc(), callback to C function forbidden.\n");

	lua_pushvalue(ctx, cb_ind);
	intptr_t ref = luaL_ref(ctx, LUA_REGISTRYINDEX);

	int tag = 0;
	int segid = SEGID_UNKNOWN;

	if (lua_type(ctx, cb_ind+1) == LUA_TNUMBER)
		tag = lua_tonumber(ctx, cb_ind+1);
	else if (lua_type(ctx, cb_ind+1) == LUA_TSTRING){
		const char* msg = lua_tostring(ctx, cb_ind+1);
/* only type explicitly supported now */
		if (strcmp(msg, "debug") == 0)
			segid = SEGID_DEBUG;
		else if (strcmp(msg, "accessibility") == 0)
			segid = SEGID_ACCESSIBILITY;
		else
			arcan_warning("target_alloc(), unaccepted segid "
				"type-string (%s), allowed: debug, accessibility\n", msg);
	}
	else
		;

	arcan_frameserver* newref = NULL;
	const char* key = "";

/*
 * allocate new key or give to preexisting frameserver?
 */
	if (lua_type(ctx, 1) == LUA_TSTRING){
		key = luaL_checkstring(ctx, 1);
		size_t keylen = strlen(key);
		if (0 == keylen || keylen > 30)
			arcan_fatal("target_alloc(), invalid listening key (%s), "
				"length (%d) should be , 0 < n < 31\n", keylen);

/*
 * if we are in the handler of a target_alloc call, and a new one is issued,
 * the connection-point will be re-used without closing / unlinking.
 */
		for (const char* pos = key; *pos; pos++)
			if (!isalnum(*pos) && *pos != '_' && *pos != '-')
				arcan_fatal("target_alloc(%s), only"
					" aZ_ are permitted in names.\n", key);

		if (luactx.pending_socket_label &&
			strcmp(key, luactx.pending_socket_label) == 0){
			newref = platform_launch_listen_external(
				key, pw, luactx.pending_socket_descr, ARCAN_SHM_UMASK, ref);
			arcan_mem_free(luactx.pending_socket_label);
			luactx.pending_socket_label = NULL;
		}
		else
			newref = platform_launch_listen_external(
				key, pw, -1, ARCAN_SHM_UMASK, ref);

		if (!newref){
			LUA_ETRACE("target_alloc", "couldn't listen on external", 0);
		}
	}
	else {
		arcan_vobj_id srcfsrv = luaL_checkvid(ctx, 1, NULL);
		vfunc_state* state = arcan_video_feedstate(srcfsrv);
		if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr){
			newref = spawn_subsegment(
				(arcan_frameserver*) state->ptr, segid, tag, 0, 0);
		}
		else
			arcan_fatal("target_alloc() specified source ID doesn't "
				"contain a frameserver\n.");
		newref->tag = ref;
	}

	if (!newref){
		lua_pushvid(ctx, ARCAN_EID);
		lua_pushaid(ctx, ARCAN_EID);
		LUA_ETRACE("target_alloc", NULL, 2);
	}

	lua_pushvid(ctx, newref->vid);
	lua_pushaid(ctx, newref->aid);
	trace_allocation(ctx, "target", newref->vid);
	LUA_ETRACE("target_alloc", NULL, 2);
}

static int targetlaunch(lua_State* ctx)
{
	LUA_TRACE("launch_target");
	arcan_configid cid = BAD_CONFIG;
	size_t rc = 0;
	int lmode;

	if (!fsrv_ok){
	}

	if (lua_type(ctx, 1) == LUA_TSTRING){
		cid = arcan_db_configid(DBHANDLE, arcan_db_targetid(DBHANDLE,
			luaL_checkstring(ctx, 1), NULL), luaL_optstring(ctx, 2, "default"));
		lmode = luaL_optnumber(ctx, 3, LAUNCH_INTERNAL);
	}
	else
		lmode = luaL_checknumber(ctx, 2);

	if (lmode != LAUNCH_EXTERNAL && lmode != LAUNCH_INTERNAL)
		arcan_fatal("launch_target(), invalid mode -- expected LAUNCH_INTERNAL "
			" or LAUNCH_EXTERNAL ");

	intptr_t ref = find_lua_callback(ctx);

	struct arcan_strarr argv, env, libs = {0};
	enum DB_BFORMAT bfmt;
	argv = env = libs;

	char* exec = arcan_db_targetexec(DBHANDLE, cid,
		&bfmt, &argv, &env, &libs);

/* means strarrs won't be populated */
	if (!exec){
		arcan_warning("launch_target(), failed -- invalid configuration\n");
		LUA_ETRACE("launch_target", "invalid configuration", 0);
	}

/* external launch */
	if (lmode == 0){
		if (bfmt != BFRM_EXTERN){
			arcan_warning("launch_target(), failed -- binary format not suitable "
				" for external launch.");
			goto cleanup;
		}

		int retc = EXIT_FAILURE;
		if (arcan_video_prepare_external() == false){
			arcan_warning("Warning, arcan_target_launch_external(), "
				"couldn't push current context, aborting launch.\n");
			goto cleanup;
		}

		unsigned long tv = arcan_target_launch_external(
			exec, &argv, &env, &libs, &retc);
		lua_pushnumber(ctx, retc);
		lua_pushnumber(ctx, tv);
		rc = 2;
		arcan_video_restore_external();

		goto cleanup;
	}

	arcan_frameserver* intarget = NULL;

	switch (bfmt){
	case BFRM_BIN:
	case BFRM_SHELL:
		intarget = platform_launch_internal(exec, &argv, &env, &libs, ref);
	break;

	case BFRM_LWA:
/* FIXME lookup arcan_lwa binary, and feed that as the executable, this will be
 * more prominent when we have a package format going.  There's also the
 * problem of namespacing, but that could probably be fixed just using the env-
 * */
		arcan_warning("bfrm_lwa() not yet supported\n");
	break;

	case BFRM_RETRO:
		if (lmode != 1){
			arcan_warning("launch_target(), configuration specified game format"
			" which is only possible in internal- mode.");
			goto cleanup;
		}

/* retro want a specific format where core=exec:resource=argv[1] */
		struct frameserver_envp args = {
			.use_builtin = true,
			.args.builtin.mode = "game"
		};

		char* expbuf[] = {colon_escape(strdup(exec)),
			argv.count > 1 ? colon_escape(strdup(argv.data[1])) : NULL,
			argv.count > 2 ? colon_escape(strdup(argv.data[2])) : NULL,
			NULL
		};
		arcan_expand_namespaces(expbuf);

		char* argstr;
		if (-1 == asprintf(&argstr, "core=%s%s%s%s%s", expbuf[0],
			expbuf[1] ? ":resource=" : "", expbuf[1] ? expbuf[1] : "",
			expbuf[1] ? ":syspath=" : "", expbuf[2] ? expbuf[2] : "")
		)
			argstr = NULL;

		args.args.builtin.resource = argstr;
		intarget = platform_launch_fork(&args, ref);
		free(argstr);
		free(expbuf[0]);
		free(expbuf[1]);
	break;

	default:
		arcan_fatal("launch_target(), database inconsistency, unknown "
			"binary format encountered.\n");
	}

/*
 * update accounting, so that it's possible to know if one exec- target
 * is prone to failure (user- visible signs that it is misconfigured)
 */
	arcan_db_launch_status(DBHANDLE, cid, intarget != NULL);

	if (intarget){
		arcan_video_objectopacity(intarget->vid, 0.0, 0);
/* same as with launch_avfeed, invoke the event handler with the
 * preroll event as a means for queueing up initial states */
		lua_pushvid(ctx, intarget->vid);
		lua_pushaid(ctx, intarget->aid);
		trace_allocation(ctx, "launch", intarget->vid);
		rc = 2;
	}

cleanup:
	arcan_mem_freearr(&argv);
	arcan_mem_freearr(&env);
	arcan_mem_freearr(&libs);
	arcan_mem_free(exec);

	LUA_ETRACE("launch_target", NULL, rc);
}

static int rendertargetforce(lua_State* ctx)
{
	LUA_TRACE("rendertarget_forceupdate");

	arcan_vobject* vobj;
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, &vobj);
	struct rendertarget* rtgt = arcan_vint_findrt(vobj);
	if (!rtgt)
		arcan_fatal("rendertarget_forceupdate(), specified vid "
			"does not reference a rendertarget");

	if (lua_isnumber(ctx, 2)){
		rtgt->refresh = luaL_checknumber(ctx, 2);
		rtgt->refreshcnt = abs(rtgt->refresh);
		if (vid == ARCAN_VIDEO_WORLDID){
/* drop the vstore */
			if (rtgt->refresh == 0){
			}
/* rebuild the vstore? */
			else {
			}
		}

		if (lua_isnumber(ctx, 3)){
			rtgt->readback = luaL_checknumber(ctx, 3);
			rtgt->readcnt = abs(rtgt->readback);
		}
	}
	else if (ARCAN_OK != arcan_video_forceupdate(vid))
		arcan_fatal("rendertarget_forceupdate() failed on vid");

	LUA_ETRACE("rendertarget_forceupdate", NULL, 0);
}

static int rendertarget_vids(lua_State* ctx)
{
	LUA_TRACE("rendertarget_vids");
	arcan_vobject* vobj;
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, &vobj);
	struct rendertarget* rtgt = arcan_vint_findrt(vobj);

	if (!rtgt)
		arcan_fatal("rendertarget_vids(), specified vid "
			"does not reference a rendertarget");

/* build a table here, we do not supply a callback function due to the
 * invalidation- cascade tracking that would be needed to guarantee that
 * rendertarget- modifications from callback would be safe */
	lua_newtable(ctx);

	int i = 1, top = lua_gettop(ctx);
	arcan_vobject_litem* current = rtgt->first;
	while(current){
		lua_pushnumber(ctx, i++);
		lua_pushvid(ctx, current->elem->cellid);
		lua_rawset(ctx, top);
		current = current->next;
	}

	LUA_ETRACE("rendertarget_vids", NULL, 1);
}

static int rendernoclear(lua_State* ctx)
{
	LUA_TRACE("rendertarget_noclear");
	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	bool clearfl = luaL_checkbnumber(ctx, 2);

	lua_pushboolean(ctx,
		arcan_video_rendertarget_setnoclear(did, clearfl) == ARCAN_OK);

	LUA_ETRACE("rendertarget_noclear", NULL, 1);
}

static int renderreconf(lua_State* ctx)
{
	LUA_TRACE("rendertarget_reconfigure");
	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	float hppcm = luaL_checknumber(ctx, 2);
	float vppcm = luaL_checknumber(ctx, 3);
	arcan_video_rendertargetdensity(did, vppcm, hppcm, true, true);
	LUA_ETRACE("rendertarget_reconfigure", NULL, 0);
}

static int rendertargetid(lua_State* ctx)
{
	LUA_TRACE("rendertarget_id");
	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	int id;

/* set or only get? */
	if (lua_type(ctx, 2) == LUA_TNUMBER){
		id = luaL_checknumber(ctx, 2);
		arcan_video_rendertargetid(did, &id, NULL);
	}

	if (ARCAN_OK != arcan_video_rendertargetid(did, NULL, &id))
		lua_pushnil(ctx);
	else
		lua_pushnumber(ctx, id);

	LUA_ETRACE("rendertarget_id", NULL, 1);
}

static int renderdetach(lua_State* ctx)
{
	LUA_TRACE("rendertarget_detach");
	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id sid = luaL_checkvid(ctx, 2, NULL);
	arcan_video_detachfromrendertarget(did, sid);
	LUA_ETRACE("rendertarget_detach", NULL, 0);
}

static int setdefattach(lua_State* ctx)
{
	LUA_TRACE("set_context_attachment");
	arcan_vobj_id did = luavid_tovid(luaL_optnumber(ctx, 1, ARCAN_EID));
	if (did != ARCAN_EID)
		arcan_video_defaultattachment(did);

	lua_pushvid(ctx, arcan_video_currentattachment());
	LUA_ETRACE("set_context_attachment", NULL, 1);
}

static int renderattach(lua_State* ctx)
{
	LUA_TRACE("rendertarget_attach");

	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id sid = luaL_checkvid(ctx, 2, NULL);
	int detach = luaL_checkint(ctx, 3);

	if (detach != RENDERTARGET_DETACH && detach != RENDERTARGET_NODETACH){
		arcan_fatal("renderattach(%d) invalid arg 3, expected "
			"RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
	}

/* arcan_video_attachtorendertarget already has pretty aggressive checks */
	arcan_video_attachtorendertarget(did, sid, detach == RENDERTARGET_DETACH);
	LUA_ETRACE("rendertarget_attach", NULL, 0);
}

static int linkset(lua_State* ctx)
{
	LUA_TRACE("define_linktarget");
	arcan_vobject* vobj;
	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id rtgt_id = luaL_checkvid(ctx, 2, &vobj);
	struct rendertarget* rtgt = arcan_vint_findrt(vobj);
	if (!rtgt)
		arcan_fatal("define_linktarget() - referenced vid is not a rendertarget\n");

	int scale = luaL_optint(ctx, 3, RENDERTARGET_NOSCALE);
	int rate = luaL_optint(ctx, 4, -1);
	int format = luaL_optint(ctx, 5, RENDERFMT_COLOR);

	if (scale != RENDERTARGET_SCALE && scale != RENDERTARGET_NOSCALE){
		arcan_fatal("renderset(%d) invalid arg 3, expected "
			"RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
	}

	bool ok = arcan_video_linkrendertarget(
		did, rtgt_id, rate, scale == RENDERTARGET_SCALE, format);

	lua_pushboolean(ctx, ok);
	LUA_ETRACE("define_linktarget", NULL, 1);
}

static int renderset(lua_State* ctx)
{
	LUA_TRACE("define_rendertarget");

	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	int nvids = lua_rawlen(ctx, 2);
	int detach = luaL_optint(ctx, 3, RENDERTARGET_DETACH);
	int scale = luaL_optint(ctx, 4, RENDERTARGET_NOSCALE);
	int rate = luaL_optint(ctx, 5, -1);
	int format = luaL_optint(ctx, 6, RENDERFMT_COLOR);

	if (detach != RENDERTARGET_DETACH && detach != RENDERTARGET_NODETACH){
		arcan_fatal("renderset(%d) invalid arg 3, expected "
			"RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
	}

	if (scale != RENDERTARGET_SCALE && scale != RENDERTARGET_NOSCALE){
		arcan_fatal("renderset(%d) invalid arg 4, expected "
			"RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
	}

	bool ok = arcan_video_setuprendertarget(did,
		0, rate, scale == RENDERTARGET_SCALE, format) == ARCAN_OK;

	if (lua_type(ctx, 7) == LUA_TNUMBER && lua_type(ctx, 8) == LUA_TNUMBER){
		arcan_video_rendertargetdensity(did,
			luaL_checknumber(ctx, 7), luaL_checknumber(ctx, 8), false, false);
	}

	if (nvids > 0){
		for (size_t i = 0; i < nvids; i++){
			lua_rawgeti(ctx, 2, i+1);
			arcan_vobj_id setvid = luavid_tovid( lua_tonumber(ctx, -1) );
			lua_pop(ctx, 1);
			arcan_video_attachtorendertarget(
				did, setvid, detach == RENDERTARGET_DETACH);
		}
	}

	lua_pushboolean(ctx, ok);
	LUA_ETRACE("define_rendertarget", NULL, 1);
}

struct proctarget_src {
	lua_State* ctx;
	uintptr_t cbfun;
};

enum hgram_pack {
	HIST_DIRTY = 0,
	HIST_SPLIT = 1,
	HIST_MERGE,
	HIST_MERGE_NOALPHA
};

struct rn_userdata {
	av_pixel* bufptr;
	int width, height;
	size_t nelem;

	unsigned bins[1024];
	float nf[4];

	bool valid;
	enum hgram_pack packing;
};

static void packing_lut(enum hgram_pack mode, int* dst)
{
	int otbl_separate[4] = {0, 256, 512, 768};
	int otbl_mergeall[4] = {0,   0,   0,   0};
	int otbl_mergergb[4] = {0,   0,   0, 768};
	int* otbl;

/* pick offsets based on desired packing mode */
	switch (mode){
	case HIST_DIRTY:
	case HIST_SPLIT: otbl = otbl_separate; break;
	case HIST_MERGE: otbl = otbl_mergeall; break;
	case HIST_MERGE_NOALPHA:
	default:
		otbl = otbl_mergergb; break;
	}

	memcpy(dst, otbl, sizeof(int) * 4);
}

static void procimage_buildhisto(struct rn_userdata* ud, enum hgram_pack pack)
{
	if (ud->packing == pack)
		return;

	av_pixel* img = ud->bufptr;
	memset(ud->bins, '\0', sizeof(ud->bins));

	int otbl[4];
	packing_lut(pack, otbl);

	ud->packing = pack;

/* populate bins with frequency */
	for (size_t row = 0; row < ud->height; row++)
		for (size_t col = 0; col < ud->width; col++){
			size_t ofs = row * ud->width + col;
			uint8_t rgba[4];
			RGBA_DECOMP(img[ofs], &rgba[0], &rgba[1], &rgba[2], &rgba[3]);
			ud->bins[otbl[0] + rgba[0]]++;
			ud->bins[otbl[1] + rgba[1]]++;
			ud->bins[otbl[2] + rgba[2]]++;
			ud->bins[otbl[3] + rgba[3]]++;
		}

/* update limits for each bin, might be used to normalize */
	float* n = ud->nf;
	for (size_t i = 0; i <256; i++){
		n[0] = n[0] < ud->bins[otbl[0] + i] ? ud->bins[otbl[0] + i] : n[0];
		n[1] = n[1] < ud->bins[otbl[1] + i] ? ud->bins[otbl[1] + i] : n[1];
		n[2] = n[2] < ud->bins[otbl[2] + i] ? ud->bins[otbl[2] + i] : n[2];
		n[3] = n[3] < ud->bins[otbl[3] + i] ? ud->bins[otbl[3] + i] : n[3];
	}
}

static int procimage_lookup(lua_State* ctx)
{
	LUA_TRACE("procimage:frequency");
	struct rn_userdata* ud = luaL_checkudata(ctx, 1, "calcImage");

	ssize_t bin = luaL_checknumber(ctx, 2);
	if (bin < 0 || bin >= 256)
		arcan_fatal("calcImage:frequency, invalid bin %d specified (0..255).\n");

	enum hgram_pack pack = luaL_optnumber(ctx, 3, HIST_SPLIT);
	bool norm = luaL_optbnumber(ctx, 4, true) != 0;

/* we can permit out of scope if we have a valid cached packing scheme */
	if (ud->valid == false)
		arcan_fatal("calcImage:frequency, calctarget object called "
			"out of scope.\n");

	procimage_buildhisto(ud, pack);

	int ofs[4];
	packing_lut(pack, ofs);

	if (norm){
		lua_pushnumber(ctx, (float)ud->bins[ofs[0]+bin] / (ud->nf[0] + EPSILON));
		lua_pushnumber(ctx, (float)ud->bins[ofs[1]+bin] / (ud->nf[1] + EPSILON));
		lua_pushnumber(ctx, (float)ud->bins[ofs[2]+bin] / (ud->nf[2] + EPSILON));
		lua_pushnumber(ctx, (float)ud->bins[ofs[3]+bin] / (ud->nf[3] + EPSILON));
	}
	else {
		lua_pushnumber(ctx, (float)ud->bins[ofs[0]+bin]);
		lua_pushnumber(ctx, (float)ud->bins[ofs[1]+bin]);
		lua_pushnumber(ctx, (float)ud->bins[ofs[2]+bin]);
		lua_pushnumber(ctx, (float)ud->bins[ofs[3]+bin]);
	}
	LUA_ETRACE("procimage:frequency", NULL, 4);
}

static int procimage_histo(lua_State* ctx)
{
	LUA_TRACE("procimage:histogram_impose");
	struct rn_userdata* ud = luaL_checkudata(ctx, 1, "calcImage");

	if (ud->valid == false)
		arcan_fatal("calcImage:histogram_impose, "
			"calctarget object called out of scope\n");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 2, &vobj);

	if (!vobj->vstore || vobj->vstore->txmapped == TXSTATE_OFF ||
		!vobj->vstore->vinf.text.raw)
		arcan_fatal("calcImage:histogram_impose, "
			"destination vstore must have a valid textured backend.\n");

	if (vobj->vstore->w < 256)
		arcan_fatal("calcImage:histogram_impose, "
			"destination vstore width need to be >=256.\n");

/* generate frequency tables, pack, normalize and impose */
	int packing = luaL_optnumber(ctx, 3, HIST_MERGE);
	size_t dst_row = luaL_optnumber(ctx, 4, 0);

	av_pixel* base = (av_pixel*) vobj->vstore->vinf.text.raw;
	if (dst_row > vobj->vstore->h){
		arcan_fatal("calcImage:histogram_impose, "
			"destination vstore row (%zu) need to fit in current height (%zu)\n",
			dst_row, vobj->vstore->h);
	}
	base += dst_row * vobj->vstore->w;

	int lut[4];
	packing_lut(packing, lut);

	float n[4];
	procimage_buildhisto(ud, packing);

	if (luaL_optbnumber(ctx, 4, true)){
		n[0] = ud->nf[0] + EPSILON;
		n[1] = ud->nf[1] + EPSILON;
		n[2] = ud->nf[2] + EPSILON;
		n[3] = ud->nf[3] + EPSILON;
	}
	else{
		n[0] = n[1] = n[2] = n[3] = ud->width * ud->height;
	}

	switch (packing){
	case HIST_SPLIT:
		for (size_t j = 0; j < 256; j++){
			float r = (float)ud->bins[j + lut[0]] / n[0] * 255.0;
			float g = (float)ud->bins[j + lut[1]] / n[1] * 255.0;
			float b = (float)ud->bins[j + lut[2]] / n[2] * 255.0;
			float a = (float)ud->bins[j + lut[3]] / n[3] * 255.0;
			base[j] = RGBA(r,g,b,a);
		}
	break;
	case HIST_MERGE:
	case HIST_MERGE_NOALPHA:
		for (size_t j = 0; j < 256; j++){
			uint8_t val = (float)ud->bins[j] / n[0] * 255.0;
			base[j] = RGBA(val, val, val, 0xff);
		}
	break;
	default:
		arcan_fatal("calcImage:histogram_impose, unknown packing mode. "
			"Allowed: HISTOGRAM_(SPLIT, MERGE, MERGE_NOALPHA)\n");
	}

	agp_update_vstore(vobj->vstore, true);

	LUA_ETRACE("procimage:histogram_impose", NULL, 0);
}

static int procimage_get(lua_State* ctx)
{
	LUA_TRACE("procimage:get");
	struct rn_userdata* ud = luaL_checkudata(ctx, 1, "calcImage");
	if (ud->valid == false)
		arcan_fatal("calcImage:get, calctarget object called out of scope\n");

	int x = luaL_checknumber(ctx, 2);
	int y = luaL_checknumber(ctx, 3);

	if (x >= ud->width || y >= ud->height){
		arcan_fatal("calcImage:get, requested coordinates out of range, "
			"source: %d * %d, requested: %d, %d\n",
			ud->width, ud->height, x, y);
	}

	av_pixel* img = ud->bufptr;
	uint8_t r,g,b,a;
	RGBA_DECOMP(img[y * ud->width + x], &r, &g, &b, &a);

	int nch = luaL_optnumber(ctx, 4, 1);
	if (nch <= 0 || nch > 4)
		arcan_fatal("calcImage:get, invalid number of channels, "
			"requested: %d, valid(1..4)\n", nch);

	if (nch >= 1)
		lua_pushnumber(ctx, r);

	if (nch >= 2)
		lua_pushnumber(ctx, g);

	if (nch >= 3)
		lua_pushnumber(ctx, b);

	if (nch >= 4)
		lua_pushnumber(ctx, a);

	LUA_ETRACE("procimage:get", NULL, nch);
}

static int meshaccess_indices(lua_State* ctx)
{
	LUA_TRACE("meshAccess:indices");
	struct mesh_ud* ud = luaL_checkudata(ctx, 1, "meshAccess");
	size_t ind = luaL_checkint(ctx, 2);

	if (!ud->mesh || !ud->mesh->indices)
		arcan_fatal("meshAccess:indices called outside of valid scope");
	if (ind > ud->mesh->n_indices-1)
		arcan_fatal("meshAccess:indices called with OOB index %zu", ind);

	int nargs = lua_gettop(ctx);
	if (nargs == 2){
		if (ud->mesh->vertex_size == 2){
			lua_pushnumber(ctx, ud->mesh->indices[ind * 6 + 0]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 6 + 1]);

			lua_pushnumber(ctx, ud->mesh->indices[ind * 6 + 2]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 6 + 3]);

			lua_pushnumber(ctx, ud->mesh->indices[ind * 6 + 4]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 6 + 5]);

			LUA_ETRACE("meshAccess:indices", NULL, 6);
		}
		else if (ud->mesh->vertex_size == 3){
			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 0]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 1]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 2]);

			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 3]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 4]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 5]);

			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 6]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 7]);
			lua_pushnumber(ctx, ud->mesh->indices[ind * 9 + 8]);

			LUA_ETRACE("meshAcess:indices", NULL, 6);
		}
	}
	for (size_t i = 0; i < ud->mesh->vertex_size*3; i++){
		ud->mesh->indices[
			ind * ud->mesh->vertex_size * 3  + i] = luaL_checknumber(ctx, 3+i);
	}
	ud->mesh->dirty = true;
	FLAG_DIRTY(ud->vobj);
	LUA_ETRACE("meshAccess:indices", NULL, 0);
}

static int meshaccess_verts(lua_State* ctx)
{
	LUA_TRACE("meshAccess:vertices");
	struct mesh_ud* ud = luaL_checkudata(ctx, 1, "meshAccess");
	size_t ind = luaL_checkint(ctx, 2);

	if (!ud->mesh)
		arcan_fatal("meshAccess:vertices called outside of valid scope");
	if (ind > ud->mesh->n_vertices-1)
		arcan_fatal("meshAccess:vertices called with OOB index %zu", ind);

	int nargs = lua_gettop(ctx);
	if (nargs == 2){
		if (ud->mesh->vertex_size == 2){
			lua_pushnumber(ctx, ud->mesh->verts[ind * 2 + 0]);
			lua_pushnumber(ctx, ud->mesh->verts[ind * 2 + 1]);
			LUA_ETRACE("meshAccess:vertices", NULL, 2);
		}
		else if (ud->mesh->vertex_size == 3){
			lua_pushnumber(ctx, ud->mesh->verts[ind * 3 + 0]);
			lua_pushnumber(ctx, ud->mesh->verts[ind * 3 + 1]);
			lua_pushnumber(ctx, ud->mesh->verts[ind * 3 + 2]);
			LUA_ETRACE("meshAccess:vertices", NULL, 3);
		}
		LUA_ETRACE("meshAccess:vertices", NULL, 0);
	}
	for (size_t i = 0; i < ud->mesh->vertex_size; i++){
		ud->mesh->verts[
			ind * ud->mesh->vertex_size + i] = luaL_checknumber(ctx, 3+i);
	}
	ud->mesh->dirty = true;
	FLAG_DIRTY(ud->vobj);
	LUA_ETRACE("meshAccess:vertices", NULL, 0);
}

static int meshaccess_texcos(lua_State* ctx)
{
	LUA_TRACE("meshAccess:texcos");
	struct mesh_ud* ud = luaL_checkudata(ctx, 1, "meshAccess");
	size_t ind = luaL_checkint(ctx, 2);
	size_t group = luaL_checkint(ctx, 3);

	if (group != 0 && group != 1)
		arcan_fatal("meshAccess:texcos only valid group is 0 or 1");

	if (!ud->mesh)
		arcan_fatal("meshAccess:texcos called outside of valid scope");
	if (ind > ud->mesh->n_vertices-1)
		arcan_fatal("meshAccess:texcos called with OOB index %zu", ind);

	float* dst = NULL;

	if (group == 0){
		if (!ud->mesh->txcos){
			ud->mesh->txcos = arcan_alloc_mem(
				ud->mesh->n_vertices * sizeof(float) * 2, ARCAN_MEM_MODELDATA,
				ARCAN_MEM_NONFATAL | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
			);
			if (!ud->mesh->txcos)
				LUA_ETRACE("meshAccess:texcos", "out of memory", 0);
		}
		dst = ud->mesh->txcos;
	}
	else{
		if (!ud->mesh->txcos2){
			ud->mesh->txcos2 = arcan_alloc_mem(
				ud->mesh->n_vertices * sizeof(float) * 2, ARCAN_MEM_MODELDATA,
				ARCAN_MEM_NONFATAL | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
			);
			if (!ud->mesh->txcos2)
				LUA_ETRACE("meshAccess:texcos", "out of memory", 0);
		}
		dst = ud->mesh->txcos2;
	}

	int nargs = lua_gettop(ctx);
	if (nargs == 3){
		lua_pushnumber(ctx, dst[ind * 2 + 0]);
		lua_pushnumber(ctx, dst[ind * 2 + 1]);
		LUA_ETRACE("meshAccess:texcos", NULL, 2);
	}

	dst[ind * 2 + 0] = luaL_checknumber(ctx, 4);
	dst[ind * 2 + 1] = luaL_checknumber(ctx, 5);
	ud->mesh->dirty = true;
	FLAG_DIRTY(ud->vobj);

	LUA_ETRACE("meshAccess:vertices", NULL, 0);
}

static int meshaccess_colors(lua_State* ctx)
{
	LUA_TRACE("meshAccess:colors")
	struct mesh_ud* ud = luaL_checkudata(ctx, 1, "meshAccess");
	size_t ind = luaL_checkint(ctx, 2);

	if (!ud->mesh)
		arcan_fatal("meshAccess:colors called outside of valid scope");
	if (ind > ud->mesh->n_vertices-1)
		arcan_fatal("meshAccess:colors called with OOB index %zu", ind);

	if (!ud->mesh->colors){
		ud->mesh->colors = arcan_alloc_mem(
			ud->mesh->n_vertices * sizeof(float) * 4, ARCAN_MEM_MODELDATA,
				ARCAN_MEM_NONFATAL | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
			);
		if (!ud->mesh->colors)
			LUA_ETRACE("meshAccess:colors", "out of memory", 0);
	}

	int nargs = lua_gettop(ctx);
	if (nargs == 2){
		lua_pushnumber(ctx, ud->mesh->verts[ind * 4 + 0]);
		lua_pushnumber(ctx, ud->mesh->verts[ind * 4 + 1]);
		lua_pushnumber(ctx, ud->mesh->verts[ind * 4 + 2]);
		lua_pushnumber(ctx, ud->mesh->verts[ind * 4 + 3]);
		LUA_ETRACE("meshAccess:colors", NULL, 4);
	}

	ud->mesh->colors[ind * 4 + 0] = luaL_checknumber(ctx, 3);
	ud->mesh->colors[ind * 4 + 1] = luaL_checknumber(ctx, 4);
	ud->mesh->colors[ind * 4 + 2] = luaL_checknumber(ctx, 5);
	ud->mesh->colors[ind * 4 + 3] = luaL_checknumber(ctx, 6);
	ud->mesh->dirty = true;
	FLAG_DIRTY(ud->vobj);
	LUA_ETRACE("meshAccess:colors", NULL, 0);
}

static int meshaccess_type(lua_State* ctx)
{
	LUA_TRACE("meshAccess:primitive_type");
	struct mesh_ud* ud = luaL_checkudata(ctx, 1, "meshAccess");
	int type = luaL_checkint(ctx, 2);

	if (!ud->mesh)
		arcan_fatal("meshAccess:vertex called outside of valid scope");

	if (type == 0)
		ud->mesh->type = AGP_MESH_TRISOUP;
	else if (type == 1)
		ud->mesh->type = AGP_MESH_POINTCLOUD;
	else
		ud->mesh->type = AGP_MESH_TRISOUP;

	LUA_ETRACE("meshAccess:primitive_type", NULL, 0);
}

enum arcan_ffunc_rv arcan_lua_proctarget FFUNC_HEAD
{
	if (cmd == FFUNC_DESTROY){
		free(state.ptr);
		return 0;
	}

	if (cmd != FFUNC_READBACK)
		return 0;

/*
 * The buffer that comes from proctarget is special (gpu driver
 * maps it into our address space, gdb and friends won't understand.
 * define this if you need the speed-up of one less copy at the
 * expense of delaying mem issue detection.
 */
#ifdef ARCAN_LUA_CALCTARGET_NOSCRAP
	static void* scrapbuf = buf;

#else
	static void* scrapbuf;
	static size_t scrapbuf_sz;

	if (!scrapbuf || scrapbuf_sz < buf_sz){
		arcan_mem_free(scrapbuf);
		scrapbuf = arcan_alloc_mem(buf_sz, ARCAN_MEM_BINDING,
			0, ARCAN_MEMALIGN_PAGE);

		if (scrapbuf)
			scrapbuf_sz = buf_sz;
		else
			return 0;
	}

/*
 * Monitor these calls closely, experienced wild crashes here
 * in the past.
 */
	if ( (uintptr_t)buf % system_page_size != 0 &&
		((uintptr_t)scrapbuf % system_page_size != 0)){
		volatile uint32_t* inbuf = (uint32_t*) buf;
		uint32_t* outbuf = (uint32_t*) scrapbuf;

		for (size_t i = 0; i < width * height; i++)
			outbuf[i] = inbuf[i];
	}
	else {
		memcpy(scrapbuf, buf, buf_sz);
	}
#endif

	struct proctarget_src* src = state.ptr;
	lua_rawgeti(src->ctx, LUA_REGISTRYINDEX, src->cbfun);

	struct rn_userdata* ud = lua_newuserdata(src->ctx,
		sizeof(struct rn_userdata));
	memset(ud, '\0', sizeof(struct rn_userdata));
	luaL_getmetatable(src->ctx, "calcImage");
	lua_setmetatable(src->ctx, -2);

	ud->bufptr = scrapbuf;
	ud->width = width;
	ud->height = height;
	ud->nelem = width * height;
	ud->valid = true;
	ud->packing = HIST_DIRTY;

	luactx.cb_source_kind = CB_SOURCE_IMAGE;

 	lua_pushnumber(src->ctx, width);
	lua_pushnumber(src->ctx, height);
	wraperr(src->ctx, lua_pcall(src->ctx, 3, 0, 0), "proctarget_cb");

/*
 * Even if the lua function maintains a reference to this userdata,
 * we know that it's accessed outside scope and can put a fatal error on it.
 */
	luactx.cb_source_kind = CB_SOURCE_NONE;
	ud->valid = false;

	return 0;
}

static int imagestorage(lua_State* ctx)
{
	LUA_TRACE("image_access_storage");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);

	if (vobj->vstore->txmapped != TXSTATE_TEX2D){
		arcan_warning("image_access_storage(), referenced object "
			"must have a textured backing store.");
		lua_pushboolean(ctx, false);
		LUA_ETRACE("image_access_storage", NULL, 1);
	}

	if (!vobj->vstore->vinf.text.raw){
		arcan_warning("image_access_storage(), referenced object "
			"does not have a valid backing store.");
		lua_pushboolean(ctx, false);
		LUA_ETRACE("image_access_storage", NULL, 1);
	}

	if (lua_isfunction(ctx, 2) && !lua_iscfunction(ctx, 2))
		lua_pushvalue(ctx, 2);
	else
		arcan_fatal("image_access_storage(), must specify a valid "
			"lua function as second argument.");

/*
 * reuse the calctarget_ approach so that we don't have to
 * create the convenience and statistics functions and context
 * again.
 */
	struct rn_userdata* ud = lua_newuserdata(ctx, sizeof(struct rn_userdata));
	memset(ud, '\0', sizeof(struct rn_userdata));
	ud->bufptr = vobj->vstore->vinf.text.raw;
	ud->width = vobj->vstore->w;
	ud->height = vobj->vstore->h;
	ud->nelem = ud->width * ud->height;
	ud->valid = true;
	ud->packing = HIST_DIRTY;
	luaL_getmetatable(ctx, "calcImage");
	lua_setmetatable(ctx, -2);

	lua_pushnumber(ctx, ud->width);
	lua_pushnumber(ctx, ud->height);

	wraperr(ctx, lua_pcall(ctx, 3, 0, 0), "proctarget_cb");

	lua_pushboolean(ctx, true);
	LUA_ETRACE("image_access_storage", NULL, 1);
}

static int spawn_recsubseg(lua_State* ctx,
	arcan_vobj_id did, arcan_vobj_id dfsrv, int naids,
	arcan_aobj_id* aidlocks)
{
	arcan_vobject* vobj = arcan_video_getobject(dfsrv);
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (!fsrv || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
		arcan_fatal("spawn_recsubseg() -- " FATAL_MSG_FRAMESERV);
	}

	arcan_frameserver* rv =
		spawn_subsegment(fsrv, SEGID_ENCODER, 0, 0, 0);

	if(rv){
		vfunc_state fftag = {
			.tag = ARCAN_TAG_FRAMESERV,
			.ptr = rv
		};

		if (lua_isfunction(ctx, 9) && !lua_iscfunction(ctx, 9)){
			lua_pushvalue(ctx, 9);
			rv->tag = luaL_ref(ctx, LUA_REGISTRYINDEX);
		}

/* shmpage prepared, force dimensions based on source object
 * using a single audio/video buffer */
		arcan_vobject* dobj = arcan_video_getobject(did);
		struct arcan_shmif_page* shmpage = rv->shm.ptr;
		shmpage->w = dobj->vstore->w;
		shmpage->h = dobj->vstore->h;
		rv->vbuf_cnt = rv->abuf_cnt = 1;
		arcan_shmif_mapav(shmpage, rv->vbufs, 1, dobj->vstore->w *
			dobj->vstore->h * sizeof(shmif_pixel), rv->abufs, 1, 32768);
		arcan_video_alterfeed(did, FFUNC_AVFEED, fftag);

/* similar restrictions and problems as in spawn_recfsrv */
		rv->alocks = aidlocks;
		arcan_aobj_id* base = aidlocks;
			while(base && *base){
			void* hookfun;
			arcan_audio_hookfeed(*base++, rv, arcan_frameserver_avfeedmon, &hookfun);
		}

		if (naids > 1)
			arcan_frameserver_avfeed_mixer(rv, naids, aidlocks);

		lua_pushvid(ctx, rv->vid);
		trace_allocation(ctx, "encode", rv->vid);
		return 1;
	}

	arcan_warning("spawn_recsubseg() -- operation failed, "
		"couldn't attach output segment.\n");
	return 0;
}

static int spawn_recfsrv(lua_State* ctx,
	arcan_vobj_id did, arcan_vobj_id dfsrv, int naids,
	arcan_aobj_id* aidlocks,
	const char* argl, const char* resf)
{
	if (!fsrv_ok)
		return 0;

	arcan_vobject* dobj = arcan_video_getobject(did);

	intptr_t tag = 0;
	if (lua_isfunction(ctx, 9) && !lua_iscfunction(ctx, 9)){
		lua_pushvalue(ctx, 9);
		tag = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}

	struct frameserver_envp args = {
		.use_builtin = true,
		.custom_feed = did,
		.args.builtin.mode = "encode",
		.args.builtin.resource = argl,
		.init_w = dobj->vstore->w,
		.init_h = dobj->vstore->h
	};

/* we use a special feed function meant to flush audiobuffer +
 * a single video frame for encoding */
	struct arcan_frameserver* mvctx = platform_launch_fork(&args, tag);
	if (!mvctx){
		return 0;
	}

	vfunc_state fftag = {
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = mvctx
	};
	arcan_video_alterfeed(did, FFUNC_AVFEED, fftag);

/* pushing the file descriptor signals the frameserver to start receiving
 * (and use the proper dimensions), it is permitted to close and push another
 * one to the same session, with special treatment for "dumb" resource names
 * or streaming sessions */
	int fd = BADFD;

/* currently we allow null- files and failed lookups to be pushed for legacy
 * reasons as the trigger for the frameserver to started recording was when
 * recieving the fd to work with */
	if (strstr(args.args.builtin.resource,
		"container=stream") != NULL || strlen(resf) == 0)
		fd = open(NULFILE, O_WRONLY | O_CLOEXEC);
	else {
		char* fn = arcan_expand_resource(resf, RESOURCE_APPL_TEMP);

/* it is currently allowed to "record over" an existing file without forcing
 * the caller to use zap_resource first, this should possibly be reconsidered*/
		if (fn && -1 == (fd = open(fn, O_CREAT | O_RDWR, S_IRWXU))){
			arcan_warning("couldn't create output (%s), "
				"recorded data will be lost\n", fn);
			fd = open(NULFILE, O_WRONLY | O_CLOEXEC);
		}

		arcan_mem_free(fn);
	}

	if (fd != BADFD){
		arcan_event ev = {
			.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_STORE
		};
		lua_pushboolean(ctx, platform_fsrv_pushfd(mvctx, &ev, fd));
		close(fd);
	}

	mvctx->alocks = aidlocks;

/*
 * lastly, lock each audio object and forcibly attach the frameserver as a
 * monitor. NOTE that this currently doesn't handle the case where we we set up
 * multiple recording sessions sharing audio objects.
 */
	arcan_aobj_id* base = mvctx->alocks;
	while(base && *base){
		void* hookfun;
		arcan_audio_hookfeed(*base++, mvctx,
			arcan_frameserver_avfeedmon, &hookfun);
	}

/*
 * if we have several input audio sources, we need to set up an intermediate
 * mixing system, that accumulates samples from each audio source monitor,
 * and emitts a mixed buffer. This requires that the audio sources operate at
 * the same rate and buffering will converge on the biggest- buffer audio source
 */
	if (naids > 1)
		arcan_frameserver_avfeed_mixer(mvctx, naids, aidlocks);

	tgtevent(did, (arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_ACTIVATE
	});

	return 0;
}

static int procset(lua_State* ctx)
{
	LUA_TRACE("define_calctarget");

/* similar in setup to renderset,
 * but fewer arguments and takes a processing callback */
	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	luaL_checktype(ctx, 2, LUA_TTABLE);
	int nvids = lua_rawlen(ctx, 2);
	int detach = luaL_checkint(ctx, 3);
	int scale = luaL_checkint(ctx, 4);
	int pollrate = luaL_checkint(ctx, 5);

	if (nvids <= 0)
		arcan_fatal("define_calctarget(), no source VIDs specified, second "
			" argument should be an indexed table with >= 1 valid VIDs.");

	if (detach != RENDERTARGET_DETACH && detach != RENDERTARGET_NODETACH){
		arcan_warning("define_calctarget(%d) invalid arg 3, expected"
			"	RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
		goto cleanup;
	}

	if (scale != RENDERTARGET_SCALE && scale != RENDERTARGET_NOSCALE){
		arcan_warning("define_calctarget(%d) invalid arg 4, "
			"expected RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
		goto cleanup;
	}

	if (ARCAN_OK != (arcan_video_setuprendertarget(did,
		pollrate, pollrate, scale == RENDERTARGET_SCALE, RENDERTARGET_COLOR)))
		arcan_fatal("define_calctarget() couldn't setup rendertarget");

	for (size_t i = 0; i < nvids; i++){
		lua_rawgeti(ctx, 2, i+1);
		arcan_vobj_id setvid = luavid_tovid( lua_tointeger(ctx, -1) );
		lua_pop(ctx, 1);

		if (setvid == ARCAN_VIDEO_WORLDID)
				arcan_fatal("define_calctarget(), WORLDID is not a valid "
					"data source, use null_surface with image_sharestorage.\n");

		arcan_video_attachtorendertarget(
			did, setvid, detach == RENDERTARGET_DETACH);
	}

	struct proctarget_src* cbsrc = arcan_alloc_mem(sizeof(struct proctarget_src),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	cbsrc->ctx = ctx;
	cbsrc->cbfun = 0;

	if (lua_isfunction(ctx, 6) && !lua_iscfunction(ctx, 6)){
		lua_pushvalue(ctx, 6);
		cbsrc->cbfun = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}

	vfunc_state fftag = {
		.tag = ARCAN_TAG_CUSTOMPROC,
		.ptr = (void*) cbsrc
	};
	arcan_video_alterfeed(did, FFUNC_LUA_PROC, fftag);

cleanup:
	LUA_ETRACE("define_calctarget", NULL, 0);
}

static int nulltarget(lua_State* ctx)
{
	LUA_TRACE("define_nulltarget");
	arcan_vobject* dobj;
	arcan_vobj_id did = luaL_checkvid(ctx, 1, &dobj);

	vfunc_state* state = arcan_video_feedstate(did);
	if (state->tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("define_nulltarget(), nulltarget (1) " FATAL_MSG_FRAMESERV);

	arcan_frameserver* rv = spawn_subsegment(
		(arcan_frameserver*) state->ptr, SEGID_ENCODER, 0, 1, 1);

	if (!rv){
		lua_pushvid(ctx, ARCAN_EID);
		LUA_ETRACE("define_nulltarget", "no subsegment", 1);
	}

	vfunc_state fftag = {
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = rv
	};

/* nullframe does not do any audio/video polling but still maintains
 * the event-loop so it can be used to push messages etc. */
	arcan_video_alterfeed(rv->vid, FFUNC_NULLFRAME, fftag);
	rv->tag = find_lua_callback(ctx);
	lua_pushvid(ctx, rv->vid);
	LUA_ETRACE("define_nulltarget", NULL, 1);
}

static int feedtarget(lua_State* ctx)
{
	LUA_TRACE("define_feedtarget");
	arcan_vobject* dobj, (* sobj);
	arcan_vobj_id did = luaL_checkvid(ctx, 1, &dobj);
	arcan_vobj_id sid = luaL_checkvid(ctx, 2, &sobj);

	vfunc_state* state = arcan_video_feedstate(did);
	if (state->tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("define_feedtarget() feedtarget (1) " FATAL_MSG_FRAMESERV);
/*
 * trick here is to set up as a "normal" recordtarget,
 * but where we simply sample one object and use the offline vstore --
 * essentially for when we want to forward the unaltered input of
 * one frameserver as a subsegment to another
 */
	arcan_frameserver* rv = spawn_subsegment(
			(arcan_frameserver*)state->ptr, SEGID_ENCODER,
			0, sobj->vstore->w, sobj->vstore->h);

	if (!rv){
		lua_pushvid(ctx, ARCAN_EID);
		LUA_ETRACE("define_feedtarget", "no subsegment", 1);
	}

	vfunc_state fftag = {
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = rv
	};

/* shmpage prepared, force dimensions based on source object */
	arcan_video_shareglstore(sid, rv->vid);
	arcan_video_alterfeed(rv->vid, FFUNC_FEEDCOPY, fftag);

	rv->tag = find_lua_callback(ctx);

	lua_pushvid(ctx, rv->vid);
	LUA_ETRACE("define_feedtarget", NULL, 1);
}

#ifdef ARCAN_LWA
static const struct{const char* msg; enum ARCAN_SEGID val;} seglut[] = {
	{.msg = "cursor", .val = SEGID_CURSOR},
	{.msg = "popup", .val = SEGID_POPUP},
	{.msg = "icon", .val = SEGID_ICON},
	{.msg = "clipboard", .val = SEGID_CLIPBOARD},
	{.msg = "titlebar", .val = SEGID_TITLEBAR},
	{.msg = "debug", .val = SEGID_DEBUG},
	{.msg = "widget", .val = SEGID_WIDGET},
	{.msg = "accessibility", .val = SEGID_ACCESSIBILITY}
};

enum ARCAN_SEGID str_to_segid(const char* str)
{
	for (size_t i = 0; i < COUNT_OF(seglut); i++)
		if (strcmp(seglut[i].msg, str) == 0)
			return seglut[i].val;

	return SEGID_UNKNOWN;
}

bool platform_lwa_allocbind_feed(arcan_vobj_id rtgt,
	enum ARCAN_SEGID type, uintptr_t cbtag);

static int arcanset(lua_State* ctx)
{
	LUA_TRACE("define_arcantarget");

/* for storage -  will eventually be swapped for the active shmif connection */
	arcan_vobject* dvobj;
	arcan_vobj_id did = luaL_checkvid(ctx, 1, &dvobj);
	if (dvobj->vstore->txmapped != TXSTATE_TEX2D)
		arcan_fatal("define_arcantarget(), first argument "
			"must have a texture- based store.");

/* need to specify purpose, only a subset of IDs are "allowed" though the
 * actual enforcement is in the target_accept (default: not) in the server */
	enum ARCAN_SEGID type = str_to_segid(luaL_checkstring(ctx, 2));
	if (type == SEGID_UNKNOWN)
		arcan_fatal("define_arcantarget(), second argument "
			"(segid) could not be matched.");

/* currently ONLY allow table, we actually want this for static content
 * too though, so in later revisions, accept a version with just [did, type,
 * callback]) */
	luaL_checktype(ctx, 3, LUA_TTABLE);
	int rc = 0;
	int nvids = lua_rawlen(ctx, 3);

	if (nvids <= 0)
		arcan_fatal("define_arcantarget(), sources must "
			"consist of a table with >= 1 valid vids.");

	int pollrate = luaL_checkint(ctx, 4);
	intptr_t ref = find_lua_callback(ctx);
	if (LUA_NOREF == ref)
		arcan_fatal("define_arcantarget(), no event handler provided");

/* bind rt to have something to use as readback / update trigger */
	if (ARCAN_OK != arcan_video_setuprendertarget(did, 0,
		pollrate, false, RENDERTARGET_COLOR))
	{
		arcan_warning("define_recordtarget(), setup rendertarget failed.\n");
		lua_pushboolean(ctx, false);
		LUA_ETRACE("define_arcantarget", NULL, 1);
	}

	for (size_t i = 0; i < nvids; i++){
		lua_rawgeti(ctx, 3, i+1);
		arcan_vobj_id setvid = luavid_tovid( lua_tointeger(ctx, -1) );
		lua_pop(ctx, 1);

		if (setvid == ARCAN_VIDEO_WORLDID)
			arcan_fatal("recordset(), using WORLDID as a direct source is "
				"not permitted, create a null_surface and use image_sharestorage. ");

		arcan_video_attachtorendertarget(did, setvid, true);
	}

	lua_pushboolean(ctx, platform_lwa_allocbind_feed(did, type, ref));
	LUA_ETRACE("define_arcantarget", NULL, 1);
}
#else
static int arcanset(lua_State* ctx)
{
	LUA_TRACE("define_arcantarget");
	arcan_warning("define_arcantarget() is only valid in LWA");
	LUA_ETRACE("define_arcantarget", NULL, 0);
}
#endif

static int recordset(lua_State* ctx)
{
	LUA_TRACE("define_recordtarget");

	arcan_vobject* dvobj;
	arcan_vobj_id did = luaL_checkvid(ctx, 1, &dvobj);

	if (dvobj->vstore->txmapped != TXSTATE_TEX2D)
		arcan_fatal("define_recordtarget(), recordtarget "
			"recipient must have a texture- based store.");

	const char* resf = NULL;
	char* argl = NULL;
	arcan_vobj_id dfsrv = ARCAN_EID;

	if (lua_type(ctx, 2) == LUA_TNUMBER){
		dfsrv = luaL_checkvid(ctx, 2, NULL);
	}
	else {
		resf = luaL_checkstring(ctx, 2);
		argl = strdup( luaL_checkstring(ctx, 3) );
	}

	luaL_checktype(ctx, 4, LUA_TTABLE);
	int rc = 0;
	int nvids = lua_rawlen(ctx, 4);

	if (nvids <= 0)
		arcan_fatal("define_recordtarget(), sources must "
			"consist of a table with >= 1 valid vids.");

	int detach = luaL_checkint(ctx, 6);
	int scale = luaL_checkint(ctx, 7);
	int pollrate = luaL_checkint(ctx, 8);

	int naids = 0;
	bool global_monitor = false;

	if (lua_type(ctx, 5) == LUA_TTABLE)
		naids = lua_rawlen(ctx, 5);

	else if (lua_type(ctx, 5) == LUA_TNUMBER){
		naids = 1;
		arcan_vobj_id did = luaL_checkvid(ctx, 5, NULL);
		if (did != ARCAN_VIDEO_WORLDID){
			arcan_warning("recordset(%d) Unexpected value for audio, "
				"only a table of selected AID streams or single WORLDID "
				"(global monitor) allowed.\n");
			goto cleanup;
		}
		else {
			arcan_warning("recordset() - global monitor support currently "
				"disabled pending refactor.\n");
			naids = 0;
		}
	}

	if (detach != RENDERTARGET_DETACH && detach != RENDERTARGET_NODETACH){
		arcan_warning("recordset(%d) invalid arg 6, expected"
			"	RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
		goto cleanup;
	}

	if (scale != RENDERTARGET_SCALE && scale != RENDERTARGET_NOSCALE){
		arcan_warning("recordset(%d) invalid arg 7, "
			"expected RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
		goto cleanup;
	}

	if (ARCAN_OK != arcan_video_setuprendertarget(did, pollrate,
		pollrate, scale == RENDERTARGET_SCALE, RENDERTARGET_COLOR))
	{
		arcan_warning("define_recordtarget(), setup rendertarget failed.\n");
		goto cleanup;
	}

	for (size_t i = 0; i < nvids; i++){
		lua_rawgeti(ctx, 4, i+1);
		arcan_vobj_id setvid = luavid_tovid( lua_tointeger(ctx, -1) );
		lua_pop(ctx, 1);

		if (setvid == ARCAN_VIDEO_WORLDID)
			arcan_fatal("recordset(), using WORLDID as a direct source is "
				"not permitted, create a null_surface and use image_sharestorage. ");

		arcan_video_attachtorendertarget(did, setvid,
			detach == RENDERTARGET_DETACH);
	}

	arcan_aobj_id* aidlocks = NULL;

	if (naids > 0 && global_monitor == false){
		aidlocks = arcan_alloc_mem(sizeof(arcan_aobj_id) * naids + 1,
			ARCAN_MEM_ATAG, 0, ARCAN_MEMALIGN_NATURAL);

		aidlocks[naids] = 0; /* terminate */

/* can't hook the monitors until we have the frameserver in place */
		for (size_t i = 0; i < naids; i++){
			lua_rawgeti(ctx, 5, i+1);
			arcan_aobj_id setaid = luaaid_toaid( lua_tonumber(ctx, -1) );
			lua_pop(ctx, 1);

			if (arcan_audio_kind(setaid) != AOBJ_STREAM && arcan_audio_kind(setaid)
				!= AOBJ_CAPTUREFEED){
				arcan_warning("recordset(%d), unsupported AID source type,"
					" only STREAMs currently supported. Audio recording disabled.\n");
				free(aidlocks);
				aidlocks = NULL;
				naids = 0;
				char* ol = arcan_alloc_mem(strlen(argl) + sizeof(":noaudio=true"),
					ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);

				sprintf(ol, "%s%s", argl, ":noaudio=true");
				free(argl);
				argl = ol;
				break;
			}

			aidlocks[i] = setaid;
		}
	}

	if (naids == 0 && !strstr(argl, "noaudio=true")){
		char* ol = arcan_alloc_mem(strlen(argl) + sizeof(":noaudio=true"),
			ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);
		sprintf(ol, "%s%s", argl, ":noaudio=true");
		free(argl);
		argl = ol;
	}

	rc = dfsrv != ARCAN_EID ?
		spawn_recsubseg(ctx, did, dfsrv, naids, aidlocks) :
		spawn_recfsrv(ctx, did, dfsrv, naids, aidlocks, argl, resf);

cleanup:
	free(argl);
	LUA_ETRACE("define_recordtarget", NULL, rc);
}

static int recordgain(lua_State* ctx)
{
	LUA_TRACE("recordtarget_gain");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	arcan_frameserver* fsrv = vobj->feed.state.ptr;
	arcan_aobj_id aid = luaL_checkaid(ctx, 2);
	float left = luaL_checknumber(ctx, 3);
	float right = luaL_checknumber(ctx, 4);

	if (!fsrv || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("recordtarget_gain(1), " FATAL_MSG_FRAMESERV);

	arcan_frameserver_update_mixweight(fsrv, aid, left, right);

	LUA_ETRACE("recordtarget_gain", NULL, 0);
}

extern arcan_benchdata benchdata;
static int togglebench(lua_State* ctx)
{
	LUA_TRACE("benchmark_enable");

	int nargs = lua_gettop(ctx);

	if (nargs)
		benchdata.bench_enabled = lua_toboolean(ctx, 1);
	else
		benchdata.bench_enabled = !benchdata.bench_enabled;

	arcan_video_display.ignore_dirty = benchdata.bench_enabled;

/* always reset on data change */
	memset(benchdata.ticktime, '\0', sizeof(benchdata.ticktime));
	memset(benchdata.frametime, '\0', sizeof(benchdata.frametime));
	memset(benchdata.framecost, '\0', sizeof(benchdata.framecost));
	benchdata.tickofs = benchdata.frameofs = benchdata.costofs = 0;
	benchdata.framecount = benchdata.tickcount = benchdata.costcount = 0;

	LUA_ETRACE("benchmark_enable", NULL, 0);
}

static int getbenchvals(lua_State* ctx)
{
	LUA_TRACE("benchmark_data");
	size_t bench_sz = COUNT_OF(benchdata.ticktime);

	lua_pushnumber(ctx, benchdata.tickcount);
	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	int i = (benchdata.tickofs + 1) % bench_sz;
	int count = 0;

	while (i != benchdata.tickofs){
		lua_pushnumber(ctx, count++);
		lua_pushnumber(ctx, benchdata.ticktime[i]);
		lua_rawset(ctx, top);
		i = (i + 1) % bench_sz;
	}

	bench_sz = COUNT_OF(benchdata.frametime);
	i = (benchdata.frameofs + 1) % bench_sz;
	lua_pushnumber(ctx, benchdata.framecount);
	lua_newtable(ctx);
	top = lua_gettop(ctx);
	count = 0;

	while (i != benchdata.frameofs){
		lua_pushnumber(ctx, count++);
		lua_pushnumber(ctx, benchdata.frametime[i]);
		lua_rawset(ctx, top);
		i = (i + 1) % bench_sz;
	}

	bench_sz = COUNT_OF(benchdata.framecost);
	i = (benchdata.costofs + 1) % bench_sz;
	lua_pushnumber(ctx, benchdata.costcount);
	lua_newtable(ctx);
	top = lua_gettop(ctx);
	count = 0;

	while (i != benchdata.costofs){
		lua_pushnumber(ctx, count++);
		lua_pushnumber(ctx, benchdata.framecost[i]);
		lua_rawset(ctx, top);
		i = (i + 1) % bench_sz;
	}

	LUA_ETRACE("benchmark_data", NULL, 6);
}

static int timestamp(lua_State* ctx)
{
	LUA_TRACE("benchmark_timestamp");

	int stratum = luaL_optnumber(ctx, 1, 0);
	switch (stratum){
	case 0:
		lua_pushnumber(ctx, arcan_timemillis());
	break;

	case 1:
		lua_pushnumber(ctx, time(NULL));
	break;

	default:
		arcan_fatal("benchmark_timestamp(), unknown stratum (%d)\n", stratum);
	break;
	}

	LUA_ETRACE("benchmark_timestamp", NULL, 1);
}

struct modent {
	int v;
	const char s[8];
};
static struct modent modtable[] =
{
	{.v = ARKMOD_LSHIFT, .s = "lshift"},
	{.v = ARKMOD_RSHIFT, .s = "rshift"},
	{.v = ARKMOD_LALT,   .s = "lalt"},
	{.v = ARKMOD_RALT,   .s = "ralt"},
	{.v = ARKMOD_LCTRL,  .s = "lctrl"},
	{.v = ARKMOD_RCTRL,  .s = "rctrl"},
	{.v = ARKMOD_LMETA,  .s = "lmeta"},
	{.v = ARKMOD_RMETA,  .s = "rmeta"},
	{.v = ARKMOD_NUM,    .s = "num"},
	{.v = ARKMOD_CAPS,   .s = "caps"},
	{.v = ARKMOD_MODE,   .s = "mode"}
};

static int decodemod(lua_State* ctx)
{
	LUA_TRACE("decode_modifiers");

	int modval = luaL_checkint(ctx, 1);
	if (lua_type(ctx, 2) == LUA_TSTRING){
		char lim[COUNT_OF(modtable) * 9 + 1];
		char* dst = lim;
		char prepch = '_';
		const char* luastr = luaL_checkstring(ctx, 2);
		if (luastr[0])
			prepch = luastr[0];

		bool prep = false;
		for (int i = 0; i < COUNT_OF(modtable); i++){
			if (modval & modtable[i].v){
				if (prep)
					*dst++ = prepch;
				const char* lbl = modtable[i].s;
				while (*lbl)
					*dst++ = *lbl++;
				prep = true;
			}
		}

		*dst = '\0';
		lua_pushstring(ctx, lim);

		LUA_ETRACE("decode_modifiers", NULL, 1);
	}

	lua_createtable(ctx, 10, 0);
	int top = lua_gettop(ctx);
	int count = 1;
	for (int i = 0; i < COUNT_OF(modtable); i++){
		if (modval & modtable[i].v){
			lua_pushnumber(ctx, count++);
			lua_pushstring(ctx, modtable[i].s);
			lua_rawset(ctx, top);
		}
	}

	LUA_ETRACE("decode_modifiers", NULL, 1);
}

static int movemodel(lua_State* ctx)
{
	LUA_TRACE("move3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	float x = luaL_checknumber(ctx, 2);
	float y = luaL_checknumber(ctx, 3);
	float z = luaL_checknumber(ctx, 4);
	unsigned int dt = luaL_optint(ctx, 5, 0);
	int interp = luaL_optint(ctx, 6, ARCAN_VINTER_LINEAR);

	arcan_video_objectmove(vid, x, y, z, dt);
	if (dt && interp < ARCAN_VINTER_ENDMARKER)
		arcan_video_moveinterp(vid, interp);

	LUA_ETRACE("move3d_model", NULL, 0);
}

static int forwardmodel(lua_State* ctx)
{
	LUA_TRACE("forward3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	float mag = luaL_checknumber(ctx, 2);
	unsigned int dt = luaL_optint(ctx, 3, 0);
	bool axismask_x = luaL_optbnumber(ctx, 4, 0);
	bool axismask_y = luaL_optbnumber(ctx, 5, 0);
	bool axismask_z = luaL_optbnumber(ctx, 6, 0);
	int interp = luaL_optint(ctx, 7, ARCAN_VINTER_LINEAR);

	surface_properties prop = arcan_video_current_properties(vid);

	vector view = taitbryan_forwardv(prop.rotation.roll,
		prop.rotation.pitch, prop.rotation.yaw);
	view = mul_vectorf(view, mag);
	vector newpos = add_vector(prop.position, view);

	arcan_video_objectmove(vid,
		axismask_x ? prop.position.x : newpos.x,
		axismask_y ? prop.position.y : newpos.y,
		axismask_z ? prop.position.z : newpos.z, dt);

	if (dt && interp < ARCAN_VINTER_ENDMARKER && interp != ARCAN_VINTER_LINEAR)
		arcan_video_moveinterp(vid, interp);

	LUA_ETRACE("forward3d_model", NULL, 0);
}

static int stepmodel(lua_State* ctx)
{
	LUA_TRACE("step3d_model");
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);

	float mag_fwd = luaL_checknumber(ctx, 2);
	float mag_side = luaL_checknumber(ctx, 3);
	unsigned dt = luaL_optint(ctx, 4, 0);
	bool apply = luaL_optbnumber(ctx, 5, true);
	bool axismask_x = luaL_optbnumber(ctx, 6, 0);
	bool axismask_y = luaL_optbnumber(ctx, 7, 0);
	bool axismask_z = luaL_optbnumber(ctx, 8, 0);
	unsigned interp = luaL_optint(ctx, 9, ARCAN_VINTER_LINEAR);

	surface_properties prop = arcan_video_current_properties(vid);
	vector view = taitbryan_forwardv(
		prop.rotation.roll, prop.rotation.pitch, prop.rotation.yaw);
	vector up = build_vect(0.0, 1.0, 0.0);

/* first strafe */
	if (prop.rotation.pitch > 180 || prop.rotation.pitch < -180)
		mag_side *= -1.0f;
	vector strafeview = norm_vector(crossp_vector(view, up));

	vector newpos = {
		.x = prop.position.x + strafeview.x * mag_side,
		.y = prop.position.y + strafeview.y * mag_side,
		.z = prop.position.z + strafeview.z * mag_side
	};

/* then forward */
	view = mul_vectorf(view, mag_fwd);
	newpos = add_vector(newpos, view);

/* only apply if requested, this is different from other move, ... */
	if (apply){
		arcan_video_objectmove(vid,
			axismask_x ? prop.position.x : newpos.x,
			axismask_y ? prop.position.y : newpos.y,
			axismask_z ? prop.position.z : newpos.z, dt);

		if (dt && interp < ARCAN_VINTER_ENDMARKER && interp != ARCAN_VINTER_LINEAR)
			arcan_video_moveinterp(vid, interp);
	}

/* and actually return the possible new position */
	lua_pushnumber(ctx, newpos.x);
	lua_pushnumber(ctx, newpos.y);
	lua_pushnumber(ctx, newpos.z);

	LUA_ETRACE("step3d_model", NULL, 3);
}

static int strafemodel(lua_State* ctx)
{
	LUA_TRACE("strafe3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	float mag = luaL_checknumber(ctx, 2);
	unsigned int dt = luaL_optint(ctx, 3, 0);
	bool axismask_x = luaL_optbnumber(ctx, 4, 0);
	bool axismask_y = luaL_optbnumber(ctx, 5, 0);
	bool axismask_z = luaL_optbnumber(ctx, 6, 0);
	unsigned interp = luaL_optint(ctx, 7, ARCAN_VINTER_LINEAR);

	surface_properties prop = arcan_video_current_properties(vid);
	vector view = taitbryan_forwardv(prop.rotation.roll,
		prop.rotation.pitch, prop.rotation.yaw);

	vector up = build_vect(0.0, 1.0, 0.0);
	if (prop.rotation.pitch > 180 || prop.rotation.pitch < -180)
		mag *= -1.0f;

	view = norm_vector(crossp_vector(view, up));

	prop.position.x += view.x * mag;
	prop.position.z += view.z * mag;

	arcan_video_objectmove(vid,
		prop.position.x, prop.position.y, prop.position.z, dt);

	if (dt && interp < ARCAN_VINTER_ENDMARKER && interp != ARCAN_VINTER_LINEAR)
		arcan_video_moveinterp(vid, interp);

	LUA_ETRACE("strafe3d_model", NULL, 0);
}

static int scalemodel(lua_State* ctx)
{
	LUA_TRACE("scale3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	float sx = luaL_checknumber(ctx, 2);
	float sy = luaL_checknumber(ctx, 3);
	float sz = luaL_checknumber(ctx, 4);
	unsigned int dt = luaL_optint(ctx, 5, 0);
	unsigned interp = luaL_optint(ctx, 6, ARCAN_VINTER_LINEAR);

	arcan_video_objectscale(vid, sx, sy, sz, dt);

	if (dt && interp < ARCAN_VINTER_ENDMARKER && interp != ARCAN_VINTER_LINEAR)
		arcan_video_scaleinterp(vid, interp);

	LUA_ETRACE("scale3d_model", NULL, 0);
}

static int orientmodel(lua_State* ctx)
{
	LUA_TRACE("orient3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	double roll       = luaL_checknumber(ctx, 2);
	double pitch      = luaL_checknumber(ctx, 3);
	double yaw        = luaL_checknumber(ctx, 4);
	arcan_3d_baseorient(vid, roll, pitch, yaw);

	LUA_ETRACE("orient3d_model", NULL, 0);
}

static int shader_ugroup(lua_State* ctx)
{
	LUA_TRACE("shader_ugroup");
	agp_shader_id shid = lua_type(ctx, 1) == LUA_TSTRING ?
		agp_shader_lookup(luaL_checkstring(ctx, 1)) : luaL_checknumber(ctx, 1);
	agp_shader_id newgrp = agp_shader_addgroup(shid);
	if (BROKEN_SHADER == newgrp){
		LUA_ETRACE("shader_ugroup", NULL, 0);
	}
	else
		lua_pushnumber(ctx, newgrp);
	LUA_ETRACE("shader_ugroup", NULL, 1);
}

/* map a format string to the arcan_shdrmgmt.h different datatypes */
static int shader_uniform(lua_State* ctx)
{
	LUA_TRACE("shader_uniform");

	float fbuf[16];

	int sid = abs((int)luaL_checknumber(ctx, 1));
	const char* label = luaL_checkstring(ctx, 2);
	const char* fmtstr = luaL_checkstring(ctx, 3);

	ssize_t darg = lua_gettop(ctx) - strlen(fmtstr);
	if (darg != 3 && darg != 4)
		arcan_fatal("shader_uniform(), invalid number of arguments (%d) for "
			"format string: %s\n", lua_gettop(ctx), fmtstr);

	size_t abase = darg == 4 ? 5 : 4;

	if (agp_shader_activate(sid) != ARCAN_OK){
		arcan_warning("shader_uniform(), shader (%d) failed"
			"	to activate.\n", sid);

		LUA_ETRACE("shader_uniform", NULL, 0);
	}

	if (!label)
		label = "unknown";

	if (fmtstr[0] == 'b'){
		int fmt = luaL_checkbnumber(ctx, abase) != 0;
		agp_shader_forceunif(label, shdrbool, &fmt);
	} else if (fmtstr[0] == 'i'){
		int fmt = luaL_checknumber(ctx, abase);
		agp_shader_forceunif(label, shdrint, &fmt);
	} else {
		unsigned i = 0;
		while(fmtstr[i] == 'f') i++;
		if (i)
			switch(i){
			case 1:
				fbuf[0] = luaL_checknumber(ctx, abase);
				agp_shader_forceunif(label, shdrfloat, fbuf);
			break;

			case 2:
				fbuf[0] = luaL_checknumber(ctx, abase);
				fbuf[1] = luaL_checknumber(ctx, abase+1);
				agp_shader_forceunif(label, shdrvec2, fbuf);
			break;

			case 3:
				fbuf[0] = luaL_checknumber(ctx, abase);
				fbuf[1] = luaL_checknumber(ctx, abase+1);
				fbuf[2] = luaL_checknumber(ctx, abase+2);
				agp_shader_forceunif(label, shdrvec3, fbuf);
			break;

			case 4:
				fbuf[0] = luaL_checknumber(ctx, abase);
				fbuf[1] = luaL_checknumber(ctx, abase+1);
				fbuf[2] = luaL_checknumber(ctx, abase+2);
				fbuf[3] = luaL_checknumber(ctx, abase+3);
				agp_shader_forceunif(label, shdrvec4, fbuf);
			break;

			case 16:
				while(i--)
					fbuf[i] = luaL_checknumber(ctx, abase + i);
				agp_shader_forceunif(label, shdrmat4x4, fbuf);
			break;
			default:
				arcan_warning("shader_uniform(%s), unsupported format "
					"string accepted f counts are 1..4 and 16\n", label);
		}
		else
			arcan_warning("shader_uniform(%s), unspported format "
				"	string (%s)\n", label, fmtstr);
	}

	/* shdrbool : b
	 *  shdrint : i
	 *shdrfloat : f
	 *shdrvec2  : ff
	 *shdrvec3  : fff
	 *shdrvec4  : ffff
	 *shdrmat4x4: ffff.... */

	/* check for the special ones, b and i */
	/* count number of f:s, map that to the appropriate subtype */

	LUA_ETRACE("shader_uniform", NULL, 0);
}

static int rotatemodel(lua_State* ctx)
{
	LUA_TRACE("rotate3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	double roll       = luaL_checknumber(ctx, 2);
	double pitch      = luaL_checknumber(ctx, 3);
	double yaw        = luaL_checknumber(ctx, 4);
	unsigned int dt   = abs((int)luaL_optnumber(ctx, 5, 0));
	int rotate_rel    = luaL_optnumber(ctx, 6, CONST_ROTATE_ABSOLUTE);

	if (rotate_rel != CONST_ROTATE_RELATIVE && rotate_rel !=CONST_ROTATE_ABSOLUTE)
		arcan_fatal("rotatemodel(%d), invalid rotation base defined, (%d)"
			"	should be ROTATE_ABSOLUTE or ROTATE_RELATIVE\n", rotate_rel);

	surface_properties prop = arcan_video_current_properties(vid);

	if (rotate_rel == CONST_ROTATE_RELATIVE)
		arcan_video_objectrotate3d(vid, prop.rotation.roll + roll,
			prop.rotation.pitch + pitch, prop.rotation.yaw + yaw, dt);
	else
		arcan_video_objectrotate3d(vid, roll, pitch, yaw, dt);

	LUA_ETRACE("rotate3d_model", NULL, 0);
}

static int setimageproc(lua_State* ctx)
{
	LUA_TRACE("switch_default_imageproc");
	int num = luaL_checknumber(ctx, 1);

	if (num == IMAGEPROC_NORMAL || num == IMAGEPROC_FLIPH){
		arcan_video_default_imageprocmode(num);
	} else
		arcan_fatal("setimageproc(%d), invalid image postprocess "
			"specified, expected IMAGEPROC_NORMAL or IMAGEPROC_FLIPH\n", num);

	LUA_ETRACE("switch_default_imageproc", NULL, 0);
}

static int settexfilter(lua_State* ctx)
{
	LUA_TRACE("switch_default_texfilter");

	enum arcan_vfilter_mode mode = luaL_checknumber(ctx, 1);

	if (mode == ARCAN_VFILTER_TRILINEAR ||
			mode == ARCAN_VFILTER_BILINEAR ||
			mode == ARCAN_VFILTER_LINEAR ||
			mode == ARCAN_VFILTER_NONE){
		arcan_video_default_texfilter(mode);
	}

	LUA_ETRACE("switch_default_texfilter", NULL, 0);
}

static int changetexfilter(lua_State* ctx)
{
	LUA_TRACE("image_texfilter");

	enum arcan_vfilter_mode mode = luaL_checknumber(ctx, 2);
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);

	if (mode == ARCAN_VFILTER_TRILINEAR ||
			mode == ARCAN_VFILTER_BILINEAR ||
			mode == ARCAN_VFILTER_LINEAR ||
			mode == ARCAN_VFILTER_NONE){
		arcan_video_objectfilter(vid, mode);
	}
	else
		arcan_fatal("image_texfilter(vid, s) -- unsupported mode (%d), expected:"
			" FILTER_LINEAR, FILTER_BILINEAR or FILTER_TRILINEAR\n", mode);

	LUA_ETRACE("image_texfilter", NULL, 0);
}

static int settexmode(lua_State* ctx)
{
	LUA_TRACE("switch_default_texmode");

	int numa = luaL_checknumber(ctx, 1);
	int numb = luaL_checknumber(ctx, 2);
	long int tmpn = luaL_optnumber(ctx, 3, ARCAN_EID);

	if ( (numa == ARCAN_VTEX_CLAMP || numa == ARCAN_VTEX_REPEAT) &&
		(numb == ARCAN_VTEX_CLAMP || numb == ARCAN_VTEX_REPEAT) ){
		if (tmpn != ARCAN_EID){
			arcan_vobj_id dvid = luaL_checkvid(ctx, 3, NULL);
			arcan_video_objecttexmode(dvid, numa, numb);
		}
		else
			arcan_video_default_texmode(numa, numb);
	}

	LUA_ETRACE("switch_default_texmode", NULL, 0);
}

static int tracetag(lua_State* ctx)
{
	LUA_TRACE("image_tracetag");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	const char* const msg = luaL_optstring(ctx, 2, NULL);
	int rc = 0;

	if (!msg){
		const char* tag = arcan_video_readtag(id);
		lua_pushstring(ctx, tag ? tag : "(no tag)");
		rc = 1;
	}
	else
		arcan_video_tracetag(id, msg);

	LUA_ETRACE("image_tracetag", NULL, rc);
}

static int setscalemode(lua_State* ctx)
{
	LUA_TRACE("switch_default_scalemode");

	int num = luaL_checknumber(ctx, 1);

	if (num == ARCAN_VIMAGE_NOPOW2 || num == ARCAN_VIMAGE_SCALEPOW2){
		arcan_video_default_scalemode(num);
	} else {
		arcan_fatal("setscalemode(%d), invalid scale-mode specified. Expecting:"
		"SCALE_NOPOW2, SCALE_POW2 \n", num);
	}

	LUA_ETRACE("switch_default_scalemode", NULL, 0);
}

/* 0 => 7 bit char,
 * 1 => start of char,
 * 2 => in the middle of char */
static int utf8kind(lua_State* ctx)
{
	LUA_TRACE("utf8kind");
	char num = luaL_checkint(ctx, 1);

	if (num & (1 << 7)){
		lua_pushnumber(ctx, num & (1 << 6) ? 1 : 2);
	} else
		lua_pushnumber(ctx, 0);

	LUA_ETRACE("utf8kind", NULL, 1);
}

static int inputfilteranalog(lua_State* ctx)
{
	LUA_TRACE("inputanalog_filter");

	int joyid = luaL_checknumber(ctx, 1);
	int axisid = luaL_checknumber(ctx, 2);
	int deadzone = luaL_checknumber(ctx, 3);
	int lb = luaL_checknumber(ctx, 4);
	int ub = luaL_checknumber(ctx, 5);
	int buffer_sz = luaL_checknumber(ctx, 6);

	const char* smode = luaL_checkstring(ctx, 7);
	enum ARCAN_ANALOGFILTER_KIND mode = ARCAN_ANALOGFILTER_NONE;

	if (strcmp(smode, "drop") == 0);
	else if (strcmp(smode, "pass") == 0)
		mode = ARCAN_ANALOGFILTER_PASS;
	else if (strcmp(smode, "average") == 0)
		mode = ARCAN_ANALOGFILTER_AVG;
	else if (strcmp(smode, "latest") == 0)
		mode = ARCAN_ANALOGFILTER_ALAST;
	else
		arcan_warning("inputfilteranalog(), unsupported mode (%s)\n", smode);

	platform_event_analogfilter(joyid, axisid,
		lb, ub, deadzone, buffer_sz, mode);

	LUA_ETRACE("inputanalog_filter", NULL, 0);
}

static void tblanalogenum(lua_State* ctx, int ttop,
	enum ARCAN_ANALOGFILTER_KIND mode)
{
	switch (mode){
	case ARCAN_ANALOGFILTER_NONE:
		tblstr(ctx, "mode", "drop", ttop);
	break;
	case ARCAN_ANALOGFILTER_PASS:
		tblstr(ctx, "mode", "pass", ttop);
	break;
	case ARCAN_ANALOGFILTER_AVG:
		tblstr(ctx, "mode", "average", ttop);
	break;
	case ARCAN_ANALOGFILTER_ALAST:
		tblstr(ctx, "mode", "latest", ttop);
	break;
	}
}

static int singlequery(lua_State* ctx, int devid, int axid)
{
	int lbound, ubound, dz, ksz;
	enum ARCAN_ANALOGFILTER_KIND mode;

	arcan_errc errc = platform_event_analogstate(devid, axid,
		&lbound, &ubound, &dz, &ksz, &mode);

	if (errc != ARCAN_OK){
		const char* lbl = platform_event_devlabel(devid);

		if (lbl != NULL){
			lua_newtable(ctx);
			int ttop = lua_gettop(ctx);
			tblstr(ctx, "label", platform_event_devlabel(devid), ttop);
			tblnum(ctx, "devid", devid, ttop);
			return 1;
		}

		return 0;
	}

	lua_newtable(ctx);
	int ttop = lua_gettop(ctx);
	tblnum(ctx, "devid", devid, ttop);
	tblnum(ctx, "subid", axid, ttop);
	tblstr(ctx, "label", platform_event_devlabel(devid), ttop);
	tblnum(ctx, "upper_bound", ubound, ttop);
	tblnum(ctx, "lower_bound", lbound, ttop);
	tblnum(ctx, "deadzone", dz, ttop);
	tblnum(ctx, "kernel_size", ksz, ttop);
	tblanalogenum(ctx, ttop, mode);

	return 1;
}

static int inputanalogquery(lua_State* ctx)
{
	LUA_TRACE("inputanalog_query");

	int devid = 0, resind = 1;
	int devnum = luaL_optnumber(ctx, 1, -1);
	int axnum = abs((int)luaL_optnumber(ctx, 2, 0));
	bool rescan = luaL_optbnumber(ctx, 3, 0);

	if (rescan)
		platform_event_rescan_idev(arcan_event_defaultctx());

	if (devnum != -1){
		int n = singlequery(ctx, devnum, axnum);
		LUA_ETRACE("inputanalog_query", NULL, n);
	}

	lua_newtable(ctx);
	arcan_errc errc = ARCAN_OK;

	while (errc != ARCAN_ERRC_NO_SUCH_OBJECT){
		int axid = 0;

		while (true){
			int lbound, ubound, dz, ksz;
			enum ARCAN_ANALOGFILTER_KIND mode;

			errc = platform_event_analogstate(devid, axid,
				&lbound, &ubound, &dz, &ksz, &mode);

			if (errc != ARCAN_OK)
				break;

			int rawtop = lua_gettop(ctx);
			lua_pushnumber(ctx, resind++);
			lua_newtable(ctx);
			int ttop = lua_gettop(ctx);

			tblnum(ctx, "devid", devid, ttop);
			tblnum(ctx, "subid", axid, ttop);
			tblstr(ctx, "label", platform_event_devlabel(devid), ttop);
			tblnum(ctx, "upper_bound", ubound, ttop);
			tblnum(ctx, "lower_bound", lbound, ttop);
			tblnum(ctx, "deadzone", dz, ttop);
			tblnum(ctx, "kernel_size", ksz, ttop);
			tblanalogenum(ctx, ttop, mode);

			lua_rawset(ctx, rawtop);
			axid++;
		}

		devid++;
	}

	LUA_ETRACE("inputanalog_query", NULL, 1);
}

static int inputanalogtoggle(lua_State* ctx)
{
	LUA_TRACE("inputanalog_toggle");

	bool val = luaL_checkbnumber(ctx, 1);
	bool mouse = luaL_optbnumber(ctx, 2, 0);

	platform_event_analogall(val, mouse);

	LUA_ETRACE("inputanalog_toggle", NULL, 0);
}

enum outfmt_screenshot {
	OUTFMT_PNG,
	OUTFMT_PNG_FLIP,
	OUTFMT_RAW8,
	OUTFMT_RAW24,
	OUTFMT_RAW32
};

static void dump_raw(FILE* dst, av_pixel* buf,
	int w, int h, enum outfmt_screenshot fmt)
{
	size_t sf = 0;

	switch(fmt){
		case OUTFMT_RAW8: sf = 1; break;
		case OUTFMT_RAW24: sf = 3; break;
		case OUTFMT_RAW32: sf = 4; break;

/* won't happen */
	default:
	break;
	}

	uint8_t* interim = arcan_alloc_mem(w * h * sf, ARCAN_MEM_VBUFFER,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_NATURAL);
	uint8_t* work = interim;

	if (!interim)
		return;

	for (int y = h-1; y >= 0; y--)
		for (int x = 0; x < w; x++){
			uint8_t rgba[4];
			RGBA_DECOMP(buf[y * w + x], &rgba[0], &rgba[1], &rgba[2], &rgba[3]);
			switch (fmt){
			case OUTFMT_RAW8:
				*work++ = (int)(rgba[0] + rgba[1] + rgba[2]) / 3;
			break;
			case OUTFMT_RAW24:
				*work++ = rgba[0];
				*work++ = rgba[1];
				*work++ = rgba[2];
			break;
			case OUTFMT_RAW32:
				memcpy(work, rgba, 4);
				work += 4;
			break;
			default:
			break;
			}
		}

	fwrite(interim, w * h * sf, 1, dst);
	arcan_mem_free(interim);
}

struct pthr_imgwr {
	FILE* dst;
	int fmt;
	size_t dw, dh;
	av_pixel* databuf;
};

static void* pthr_imgwr(void* arg)
{
	struct pthr_imgwr* job = arg;
	switch(job->fmt){
	case OUTFMT_PNG:
		arcan_img_outpng(job->dst, job->databuf, job->dw, job->dh, false);
	break;

	case OUTFMT_PNG_FLIP:
		arcan_img_outpng(job->dst, job->databuf, job->dw, job->dh, true);
	break;

/* flip is assumed in the raw formats */
	case OUTFMT_RAW8:
	case OUTFMT_RAW24:
	case OUTFMT_RAW32:
		dump_raw(job->dst, job->databuf, job->dw, job->dh, job->fmt);
	break;
	}

	fclose(job->dst);
	arcan_mem_free(job->databuf);
	arcan_mem_free(job);

	return NULL;
}

static int screenshot(lua_State* ctx)
{
	LUA_TRACE("save_screenshot");

	av_pixel* databuf = NULL;
	struct pthr_imgwr* job = NULL;
	size_t bufs;

	struct monitor_mode mode = platform_video_dimensions();
	int dw = mode.width;
	int dh = mode.height;

	const char* const resstr = luaL_checkstring(ctx, 1);
	arcan_vobj_id sid = ARCAN_EID;

	enum outfmt_screenshot fmt = luaL_optnumber(ctx, 2, OUTFMT_PNG);
	if (fmt != OUTFMT_PNG && fmt != OUTFMT_PNG_FLIP &&
		fmt != OUTFMT_RAW8 && fmt != OUTFMT_RAW24 && fmt != OUTFMT_RAW32)
		arcan_fatal("save_screenshot(), invalid/uknown format: %d\n", fmt);

	bool local = luaL_optbnumber(ctx, 4, false);

	if (luaL_optnumber(ctx, 3, ARCAN_EID) != ARCAN_EID){
		sid = luaL_checkvid(ctx, 3, NULL);
		arcan_video_forceread(sid, local, &databuf, &bufs);

		img_cons com = arcan_video_storage_properties(sid);
		dw = com.w;
		dh = com.h;
	}
	else
		arcan_video_screenshot(&databuf, &bufs);

	if (!databuf){
		arcan_warning("save_screenshot() -- insufficient free memory.\n");
		LUA_ETRACE("save_screenshot", NULL, 0);
	}

/* Note: we assume TOCTU- free APPL_TEMP, done twice here as _find
 * returns nothing if it doesn't exist */
	char* fname = arcan_find_resource(resstr, RESOURCE_APPL_TEMP, ARES_FILE);
	if (fname){
		arcan_warning("save_screeenshot() -- refusing to "
			"overwrite existing file.\n");
		goto cleanup;
	}
	fname = arcan_expand_resource(resstr, RESOURCE_APPL_TEMP);
	if (!fname)
		goto cleanup;

	int infd = open(fname, O_WRONLY | O_CLOEXEC | O_CREAT, S_IRUSR | S_IWUSR);
	if (-1 == infd){
		arcan_warning("save_screenshot(%s) failed, %s.\n", fname, strerror(errno));
		arcan_mem_free(fname);
		goto cleanup;
	}
	arcan_mem_free(fname);

	job = arcan_alloc_mem(sizeof(struct pthr_imgwr), ARCAN_MEM_VSTRUCT,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_NATURAL);

	if (!job){
		close(infd);
		goto cleanup;
	}

/* recall, if fdopen fails -- descriptor is still open */
	job->dst = fdopen(infd, "wb");
	if (!job->dst){
		close(infd);
		goto cleanup;
	}
	job->dw = dw;
	job->dh = dh;
	job->fmt = fmt;
	job->databuf = databuf;

/* detach as we don't want to find / join later */
	pthread_attr_t jattr;
	pthread_t pthr;
	pthread_attr_init(&jattr);
	pthread_attr_setdetachstate(&jattr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pthr, NULL, pthr_imgwr, (void*) job);

	LUA_ETRACE("save_screenshot", "couldn't setup file or thread", 0);

/* otherwise thread cleans up at exit */
cleanup:
		arcan_mem_free(job);
		arcan_mem_free(databuf);

	LUA_ETRACE("save_screenshot", NULL, 0);
}

static bool lua_launch_fsrv(lua_State* ctx,
	struct frameserver_envp* args, intptr_t callback)
{
	if (!fsrv_ok){
		lua_pushvid(ctx, ARCAN_EID);
		return false;
	}

	struct arcan_frameserver* ref = platform_launch_fork(args, callback);
	if (!ref){
		lua_pushvid(ctx, ARCAN_EID);
		return false;
	}

	tgtevent(ref->vid, (arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_ACTIVATE
	});
	lua_pushvid(ctx, ref->vid);
	trace_allocation(ctx, "net", ref->vid);
	return true;
}

static int net_listen(lua_State* ctx)
{
	LUA_TRACE("net_listen");

	intptr_t ref = find_lua_callback(ctx);

	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = "net-srv",
		.args.builtin.resource = "mode=server"
	};
	lua_launch_fsrv(ctx, &args, ref);

	LUA_ETRACE("net_listen", NULL, 1);
}

static int net_discover(lua_State* ctx)
{
	LUA_TRACE("net_discover");

	int ind = find_lua_type(ctx, LUA_TSTRING, 0);
	intptr_t ref = find_lua_callback(ctx);

	if (ind){
		const char* lua_str = luaL_checkstring(ctx, ind);
		char consstr[] = "mode=client:discover:";
		size_t tmplen = strlen(lua_str) + sizeof(consstr);

		char* tmpstr = arcan_alloc_mem(tmplen, ARCAN_MEM_STRINGBUF,
			ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL);

		snprintf(tmpstr, tmplen, "%s%s", consstr, lua_str);

		struct frameserver_envp args = {
			.args.builtin.mode = "net-cl",
			.use_builtin = true,
			.args.builtin.resource = tmpstr
		};

		lua_launch_fsrv(ctx, &args, ref);
		arcan_mem_free(tmpstr);
	}
	else
	{
		struct frameserver_envp args = {
			.args.builtin.mode = "net-cl",
			.use_builtin = true,
			.args.builtin.resource = "mode=client:discover"
		};

		lua_launch_fsrv(ctx, &args, ref);
	}

	LUA_ETRACE("net_discover", NULL, 1);
}

static int net_open(lua_State* ctx)
{
	LUA_TRACE("net_open");

	char* host = lua_isstring(ctx, 1) ?
		(char*) luaL_checkstring(ctx, 1) : NULL;

	intptr_t ref = find_lua_callback(ctx);

/* populate and escape, due to IPv6 addresses etc. actively using :: */
	char* workstr = NULL;
	size_t work_sz = 0;

	if (host)
		colon_escape(host);

	char* instr = arcan_alloc_mem(work_sz + strlen("mode=client:host=") + 1,
		ARCAN_MEM_STRINGBUF, ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL);

	sprintf(instr,"mode=client%s%s", host ? ":host=" : "", workstr ? workstr:"");

	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = "net-cl",
		.args.builtin.resource = instr
	};

	lua_launch_fsrv(ctx, &args, ref);

	free(instr);
	free(workstr);

	LUA_ETRACE("net_open", NULL, 1);
}

static arcan_frameserver* luaL_checknet(lua_State* ctx,
	bool server, arcan_vobject** dvobj, const char* prefix)
{
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (!fsrv || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("%S (1), " FATAL_MSG_FRAMESERV, prefix);

	if (server && fsrv->segid != SEGID_NETWORK_SERVER){
		arcan_fatal("%s -- Frameserver connected to VID is not in server mode "
			"(net_open vs net_listen)\n", prefix);
	}
	else if (!server && fsrv->segid != SEGID_NETWORK_CLIENT)
		arcan_fatal("%s -- Frameserver connected to VID is not in client mode "
			"(net_open vs net_listen)\n", prefix);

	if (fsrv->parent.vid != ARCAN_EID)
		arcan_fatal("%s -- Subsegment argument target not allowed\n", prefix);

	*dvobj = vobj;
	return fsrv;
}

static int net_pushcl(lua_State* ctx)
{
	LUA_TRACE("net_push");
	arcan_vobject* vobj;
	arcan_frameserver* fsrv = luaL_checknet(ctx, false, &vobj, "net_push");

/* arg2 can be (string) => NETMSG, (event) => just push */
	arcan_event outev = {.category = EVENT_NET};

	int t = lua_type(ctx, 2);
	arcan_vobject* dvobj, (* srcvobj);
	luaL_checkvid(ctx, 1, &srcvobj);

	switch(t){
	case LUA_TSTRING:
		outev.net.kind = EVENT_NET_CUSTOMMSG;

		const char* msg = luaL_checkstring(ctx, 2);
		size_t out_sz = COUNT_OF(outev.net.message);
		snprintf(outev.net.message, out_sz, "%s", msg);
	break;

	case LUA_TNUMBER:
		luaL_checkvid(ctx, 2, &dvobj);
		uintptr_t ref = 0;

		if (lua_isfunction(ctx, 3) && !lua_iscfunction(ctx, 3)){
			lua_pushvalue(ctx, 3);
			ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
		}
		else
			arcan_fatal("net_pushcl(), missing callback\n");

		if (dvobj->feed.state.tag == ARCAN_TAG_FRAMESERV){
			arcan_fatal("net_pushcl(), pushing a frameserver needs "
				"separate support use bond_target, define_recordtarget "
				"with the network connection as destination");
		}

		if (!dvobj->vstore->txmapped)
			arcan_fatal("net_pushcl() with an image as source only works for "
				"texture mapped objects.");

		arcan_frameserver* srv = spawn_subsegment(
			srcvobj->feed.state.ptr, false, 0, dvobj->vstore->w, dvobj->vstore->h);

		if (!srv){
			arcan_warning("net_pushcl(), allocating subsegment failed\n");
			LUA_ETRACE("net_push", "subsegment allocation failed", 0);
		}

/* disable "regular" frameserver behavior */
		vfunc_state cstate = *arcan_video_feedstate(srv->vid);
		arcan_video_alterfeed(srv->vid, FFUNC_NULLFRAME, cstate);

/* we can't delete the frameserver immediately as the child might
 * not have mapped the memory yet, so we defer and use a callback */
		memcpy(srv->vbufs[0], dvobj->vstore->vinf.text.raw,
			dvobj->vstore->vinf.text.s_raw);

		srv->shm.ptr->vready = true;
		arcan_sem_post(srv->vsync);

		outev.tgt.kind = TARGET_COMMAND_STEPFRAME;
		platform_fsrv_pushevent(srv, &outev);
		lua_pushvid(ctx, srv->vid);
		trace_allocation(ctx, "net_sub", srv->vid);
		srv->tag = ref;

/* copy state into dvobj, then send event
 * that we're ready for a push
 */
	break;

	default:
		arcan_fatal("net_pushcl() -- unexpected data to push, accepted "
			"(string, VID, evtable)\n");
	break;
	}

/* for *NUX, setup a pipe() pair, push the output end to the client,
 * push the input end to the server, emit FDtransfer messages, flagging that
 * it is going to be used for state-transfer. The last bit is important to be
 * able to support both sending and receiving states, with compression and
 * deltaframes in load/store operations. this also requires that the
 * capabilities of the target actually allows for save-states,
 * by default, they don't. */
	platform_fsrv_pushevent(fsrv, &outev);

	LUA_ETRACE("net_push", NULL, 0);
}

/* similar to push to client, with the added distinction of broadcast / target,
 * and thus a more complicated pushFD etc. behavior */
static int net_pushsrv(lua_State* ctx)
{
	LUA_TRACE("net_push_srv");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	int domain = luaL_optnumber(ctx, 3, 0);

/* arg2 can be (string) => NETMSG, (event) => just push */
	arcan_event outev = {.category = EVENT_NET, .net.connid = domain};
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV || !fsrv)
		arcan_fatal("net_pushsrv() -- bad arg1, VID "
			"is not a frameserver.\n");

	if (fsrv->parent.vid != ARCAN_EID)
		arcan_fatal("net_pushsrv() -- cannot push VID to a subsegment.\n");

	if (!(fsrv->segid == SEGID_NETWORK_CLIENT))
		arcan_fatal("net_pushsrv() -- bad arg1, specified frameserver"
			" is not in client mode (net_open).\n");

/* we clean this as to not expose stack trash */
	size_t out_sz = COUNT_OF(outev.net.message);

	if (lua_isstring(ctx, 2)){
		outev.net.kind = EVENT_NET_CUSTOMMSG;

		const char* msg = luaL_checkstring(ctx, 2);
		snprintf(outev.net.message, out_sz, "%s", msg);
		platform_fsrv_pushevent(fsrv, &outev);
	}
	else
		arcan_fatal("net_pushsrv() -- "
			"unexpected data to push, accepted (string)\n");

	LUA_ETRACE("net_push_srv", NULL, 0);
}

static int net_accept(lua_State* ctx)
{
	LUA_TRACE("net_accept");

	arcan_vobject* dvobj;
	arcan_frameserver* fsrv = luaL_checknet(
		ctx, true, &dvobj, "net_accept(vid, connid)");

	int domain = luaL_checkint(ctx, 2);

	if (domain == 0)
		arcan_fatal("net_accept(vid, connid) -- NET_BROADCAST is not "
			"allowed for accept call\n");

	arcan_event outev = {.category = EVENT_NET, .net.connid = domain};
	platform_fsrv_pushevent(fsrv, &outev);

	LUA_ETRACE("net_accept", NULL, 0);
}

static int net_disconnect(lua_State* ctx)
{
	LUA_TRACE("net_disconnect");

	arcan_vobject* dvobj;
	arcan_frameserver* fsrv = luaL_checknet(
		ctx, true, &dvobj, "net_disconnect(vid, connid)");

	int domain = luaL_checkint(ctx, 2);

	arcan_event outev = {
		.category = EVENT_NET,
		.net.kind = EVENT_NET_DISCONNECT,
		.net.connid = domain
	};

	platform_fsrv_pushevent(fsrv, &outev);

	LUA_ETRACE("net_disconnect", NULL, 0);
}

static int net_authenticate(lua_State* ctx)
{
	LUA_TRACE("net_authenticate");

	arcan_vobject* dvobj;
	arcan_frameserver* fsrv = luaL_checknet(
		ctx, true, &dvobj, "net_authenticate(vid, connid)");

	int domain = luaL_checkint(ctx, 2);
	if (domain == 0)
		arcan_fatal("net_authenticate(vid, connid) -- "
			"NET_BROADCAST is not allowed for accept call\n");

	arcan_event outev = {
		.category = EVENT_NET,
		.net.kind = EVENT_NET_AUTHENTICATE,
		.net.connid = domain
	};
	platform_fsrv_pushevent(fsrv, &outev);

	LUA_ETRACE("net_authenticate", NULL, 0);
}

void arcan_lua_cleanup()
{
}

static void register_tbl(lua_State* ctx, const luaL_Reg* funtbl)
{
	while(funtbl->name != NULL){
		lua_pushstring(ctx, funtbl->name);
		lua_pushcclosure(ctx, funtbl->func, 1);
		lua_setglobal(ctx, funtbl->name);
		funtbl++;
	}
}

static int getidentstr(lua_State* ctx)
{
	LUA_TRACE("system_identstr");
	lua_pushstring(ctx, platform_video_capstr());
	LUA_ETRACE("system_identstr", NULL, 1);
}

static int setdefaultfont(lua_State* ctx)
{
	LUA_TRACE("system_defaultfont");

	const char* fontn = luaL_optstring(ctx, 1, NULL);

	char* fn = arcan_find_resource(fontn, RESOURCE_SYS_FONT, ARES_FILE);
	if (!fn){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("system_defaultfont", "couldn't find font in namespace", 1);
	}

	int fd = open(fn, O_RDONLY);
	free(fn);
	if (BADFD == fd){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("system_defaultfont", "couldn't open fontfile", 1);
	}

	size_t fontsz = luaL_checknumber(ctx, 2);
	int fonth = luaL_checknumber(ctx, 3);
	bool append = luaL_optbnumber(ctx, 4, 0);

	bool res = arcan_video_defaultfont(fontn, fd, fontsz, fonth, append);

	lua_pushboolean(ctx, res);
	LUA_ETRACE("system_defaultfont", res ? NULL : "defaultfont fail", 1);
}

static int base64_encode(lua_State* ctx)
{
	LUA_TRACE("util:base64_encode");

	size_t dsz, dsz2;
	const uint8_t* instr = (const uint8_t*) luaL_checklstring(ctx, 1, &dsz);
	char* outstr = (char*) arcan_base64_encode(instr, dsz, &dsz2, 0);

	lua_pushstring(ctx, outstr);
	arcan_mem_free(outstr);

	LUA_ETRACE("util:base64_encode", NULL, 1);
}

static int base64_decode(lua_State* ctx)
{
	LUA_TRACE("util:base64_encode");

	size_t dsz;
	const uint8_t* instr = (const uint8_t*) luaL_checkstring(ctx, 1);
	char* outstr = (char*) arcan_base64_decode(instr, &dsz, 0);
	lua_pushlstring(ctx, outstr, dsz);
	arcan_mem_free(outstr);

	LUA_ETRACE("util:base64_decode", NULL, 1);
}

static int hash_string(lua_State* ctx)
{
	LUA_TRACE("util:hash");
	const char* str = luaL_checkstring(ctx, 1);
	const char* method = luaL_optstring(ctx, 2, "djb");

	if (strcmp(method, "djb") == 0){
		unsigned long hash = 5381;
		for(; *str != 0; str++)
			hash = ((hash << 5) + hash) + *str;
		lua_pushnumber(ctx, hash);
	}
	else{
		arcan_warning("util:hash(%s), unknown hash method"
			" supported: djb)\n", method);

		LUA_ETRACE("util:hash", "unknown hash function", 0);
	}

	LUA_ETRACE("util:hash", NULL, 1);
}

static void extend_baseapi(lua_State* ctx)
{
	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	lua_pushstring(ctx, "to_base64");
	lua_pushcfunction(ctx, base64_encode);
	lua_rawset(ctx, top);

	lua_pushstring(ctx, "from_base64");
	lua_pushcfunction(ctx, base64_decode);
	lua_rawset(ctx, top);

	lua_pushstring(ctx, "hash");
	lua_pushcfunction(ctx, hash_string);
	lua_rawset(ctx, top);

	lua_setglobal(ctx, "util");
}

#include "external/bit.c"

arcan_errc arcan_lua_exposefuncs(lua_State* ctx, unsigned char debugfuncs)
{
	if (!ctx)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	luactx.debug = debugfuncs;
	lua_atpanic(ctx, (lua_CFunction) panic);

/* this is merely a "don't be dump" protection against someone storing
 * static vid values, getting away with it and causing bugs later on */
	uint32_t rv;
	arcan_random((uint8_t*)&rv, 4);
	luactx.lua_vidbase = 256 + (rv % 32768);
	arcan_renderfun_vidoffset(luactx.lua_vidbase);

/* these defines / tables are also scriptably extracted and
 * mapped to build / documentation / static verification to ensure
 * coverage in the API binding -- so keep this format (down to the
 * whitespacing, simple regexs used. */
#define EXT_MAPTBL_RESOURCE
static const luaL_Reg resfuns[] = {
{"resource",          resource        },
{"glob_resource",     globresource    },
{"zap_resource",      zapresource     },
{"open_nonblock",     opennonblock    },
{"open_rawresource",  rawresource     },
{"close_rawresource", rawclose        },
{"write_rawresource", pushrawstr      },
{"read_rawresource",  readrawresource },
{"save_screenshot",   screenshot      },
{NULL, NULL}
};
#undef EXT_MAPTBL_RESOURCE
	register_tbl(ctx, resfuns);

	luaL_newmetatable(ctx, "nonblockIOr");
	lua_pushvalue(ctx, -1);
	lua_setfield(ctx, -2, "__index");
	lua_pushcfunction(ctx, nbio_read);
	lua_setfield(ctx, -2, "read");
	lua_pushcfunction(ctx, nbio_closer);
	lua_setfield(ctx, -2, "__gc");
	lua_pushcfunction(ctx, nbio_closer);
	lua_setfield(ctx, -2, "close");
	lua_pop(ctx, 1);

	luaL_newmetatable(ctx, "nonblockIOw");
	lua_pushvalue(ctx, -1);
	lua_setfield(ctx, -2, "__index");
	lua_pushcfunction(ctx, nbio_write);
	lua_setfield(ctx, -2, "write");
	lua_pushcfunction(ctx, nbio_closew);
	lua_setfield(ctx, -2, "close");
	lua_pushcfunction(ctx, nbio_closew);
	lua_setfield(ctx, -2, "_gc");
	lua_pop(ctx, 1);

#define EXT_MAPTBL_TARGETCONTROL
static const luaL_Reg tgtfuns[] = {
{"launch_target",              targetlaunch             },
{"target_alloc",               targetalloc              },
{"target_input",               targetinput              },
{"input_target",               targetinput              },
{"suspend_target",             targetsuspend            },
{"resume_target",              targetresume             },
{"message_target",             targetmessage            },
{"accept_target",              targetaccept             },
{"pacify_target",              targetpacify             },
{"stepframe_target",           targetstepframe          },
{"snapshot_target",            targetsnapshot           },
{"restore_target",             targetrestore            },
{"bond_target",                targetbond               },
{"reset_target",               targetreset              },
{"target_portconfig",          targetportcfg            },
{"target_framemode",           targetskipmodecfg        },
{"target_verbose",             targetverbose            },
{"target_synchronous",         targetsynchronous        },
{"target_flags",               targetflags              },
{"target_graphmode",           targetgraph              },
{"target_displayhint",         targetdisphint           },
{"target_devicehint",          targetdevhint            },
{"target_fonthint",            targetfonthint           },
{"target_seek",                targetseek               },
{"target_parent",              targetparent             },
{"target_coreopt",             targetcoreopt            },
{"target_updatehandler",       targethandler            },
{"define_rendertarget",        renderset                },
{"define_linktarget",          linkset                  },
{"define_recordtarget",        recordset                },
{"define_calctarget",          procset                  },
{"define_feedtarget",          feedtarget               },
{"define_nulltarget",          nulltarget               },
{"define_arcantarget",         arcanset                 },
{"rendertarget_forceupdate",   rendertargetforce        },
{"rendertarget_vids",          rendertarget_vids        },
{"recordtarget_gain",          recordgain               },
{"rendertarget_detach",        renderdetach             },
{"rendertarget_attach",        renderattach             },
{"rendertarget_noclear",       rendernoclear            },
{"rendertarget_reconfigure",   renderreconf             },
{"rendertarget_id",            rendertargetid           },
{"load_movie",                 loadmovie                },
{"launch_decode",              loadmovie                },
{"launch_avfeed",              launchavfeed             },
{NULL, NULL}
};
#undef EXT_MAPTBL_TARGETCONTROL
	register_tbl(ctx, tgtfuns);

#define EXT_MAPTBL_DATABASE
static const luaL_Reg dbfuns[] = {
{"store_key",    storekey   },
{"get_key",      getkey     },
{"get_keys",     getkeys    },
{"match_keys",   matchkeys  },
{"list_targets", gettargets },
{"list_target_tags", gettags },
{"target_configurations", getconfigs },
{NULL, NULL}
};
#undef EXT_MAPTBL_DATABASE
	register_tbl(ctx, dbfuns);

/*
 * Personal hacks for internal projects
 */
#define EXT_MAPTBL_CUSTOM
static const luaL_Reg custfuns[] = {
{NULL, NULL}
};
#undef EXT_MAPTBL_CUSTOM
	register_tbl(ctx, custfuns);

#define EXT_MAPTBL_AUDIO
static const luaL_Reg audfuns[] = {
{"play_audio",        playaudio   },
{"delete_audio",      dropaudio   },
{"load_asample",      loadasample },
{"audio_gain",        gain        },
{"audio_buffer_size", abufsz      },
{"capture_audio",     captureaudio},
{"list_audio_inputs", capturelist },
{NULL, NULL}
};
#undef EXT_MAPTBL_AUDIO
	register_tbl(ctx, audfuns);

#define EXT_MAPTBL_IMAGE
static const luaL_Reg imgfuns[] = {
{"load_image",               loadimage          },
{"load_image_asynch",        loadimageasynch    },
{"image_loaded",             imageloaded        },
{"delete_image",             deleteimage        },
{"show_image",               showimage          },
{"hide_image",               hideimage          },
{"move_image",               moveimage          },
{"nudge_image",              nudgeimage         },
{"rotate_image",             rotateimage        },
{"scale_image",              scaleimage         },
{"resize_image",             scaleimage2        },
{"resample_image",           resampleimage      },
{"blend_image",              imageopacity       },
{"crop_image",               cropimage          },
{"persist_image",            imagepersist       },
{"image_parent",             imageparent        },
{"center_image",             centerimage        },
{"image_children",           imagechildren      },
{"order_image",              orderimage         },
{"max_current_image_order",  maxorderimage      },
{"link_image",               linkimage          },
{"set_image_as_frame",       imageasframe       },
{"image_framesetsize",       framesetalloc      },
{"image_framecyclemode",     framesetcycle      },
{"image_pushasynch",         pushasynch         },
{"image_active_frame",       activeframe        },
{"image_origo_offset",       origoofs           },
{"image_inherit_order",      orderinherit       },
{"image_tesselation",        imagetess          },
{"expire_image",             setlife            },
{"reset_image_transform",    resettransform     },
{"instant_image_transform",  instanttransform   },
{"tag_image_transform",      tagtransform       },
{"image_transform_cycle",    cycletransform     },
{"copy_image_transform",     copytransform      },
{"transfer_image_transform", transfertransform  },
{"copy_surface_properties",  copyimageprop      },
{"image_set_txcos",          settxcos           },
{"image_get_txcos",          gettxcos           },
{"image_set_txcos_default",  settxcos_default   },
{"image_texfilter",          changetexfilter    },
{"image_scale_txcos",        scaletxcos         },
{"image_clip_on",            clipon             },
{"image_clip_off",           clipoff            },
{"image_mask_toggle",        togglemask         },
{"image_mask_set",           setmask            },
{"image_screen_coordinates", screencoord        },
{"image_mask_clear",         clearmask          },
{"image_tracetag",           tracetag           },
{"image_mask_clearall",      clearall           },
{"image_shader",             setshader          },
{"image_state",              imagestate         },
{"image_access_storage",     imagestorage       },
{"image_resize_storage",     imageresizestorage },
{"image_sharestorage",       sharestorage       },
{"image_matchstorage",       matchstorage       },
{"cursor_setstorage",        cursorstorage      },
{"cursor_position",          cursorposition     },
{"move_cursor",              cursormove         },
{"nudge_cursor",             cursornudge        },
{"resize_cursor",            cursorsize         },
{"image_color",              imagecolor         },
{"image_mipmap",             imagemipmap        },
{"fill_surface",             fillsurface        },
{"alloc_surface",            allocsurface       },
{"raw_surface",              rawsurface         },
{"color_surface",            colorsurface       },
{"null_surface",             nullsurface        },
{"image_surface_properties", getimageprop       },
{"image_storage_properties", getimagestorageprop},
{"image_storage_slice",      slicestore         },
{"render_text",              rendertext         },
{"text_dimensions",          textdimensions     },
{"random_surface",           randomsurface      },
{"force_image_blend",        forceblend         },
{"image_hit",                hittest            },
{"pick_items",               pick               },
{"image_surface_initial_properties", getimageinitprop   },
{"image_surface_resolve_properties", getimageresolveprop},
{"image_surface_resolve", getimageresolveprop},
{"image_surface_initial", getimageinitprop},
{NULL, NULL}
};
#undef EXT_MAPTBL_IMAGE
	register_tbl(ctx, imgfuns);

#define EXT_MAPTBL_3D
static const luaL_Reg threedfuns[] = {
{"new_3dmodel",      buildmodel   },
{"finalize_3dmodel", finalmodel   },
{"add_3dmesh",       loadmesh     },
{"attrtag_model",    attrtag      },
{"move3d_model",     movemodel    },
{"rotate3d_model",   rotatemodel  },
{"orient3d_model",   orientmodel  },
{"scale3d_model",    scalemodel   },
{"forward3d_model",  forwardmodel },
{"strafe3d_model",   strafemodel  },
{"step3d_model",     stepmodel    },
{"camtag_model",     camtag       },
{"build_3dplane",    buildplane   },
{"build_3dbox",      buildbox     },
{"build_sphere",     buildsphere  },
{"build_cylinder",   buildcylinder},
{"build_pointcloud", pointcloud   },
{"scale_3dvertices", scale3dverts },
{"swizzle_model",    swizzlemodel },
{"mesh_shader",      setmeshshader},
{NULL, NULL}
};
#undef EXT_MAPTBL_3D
	register_tbl(ctx, threedfuns);

#define EXT_MAPTBL_SYSTEM
static const luaL_Reg sysfuns[] = {
{"shutdown",            alua_shutdown    },
{"warning",             warning          },
{"system_load",         systemload       },
{"system_context_size", systemcontextsize},
{"system_snapshot",     syssnap          },
{"system_collapse",     syscollapse      },
{"subsystem_reset",     subsys_reset     },
{"utf8kind",            utf8kind         },
{"decode_modifiers",    decodemod        },
{"benchmark_enable",    togglebench      },
{"benchmark_timestamp", timestamp        },
{"benchmark_data",      getbenchvals     },
{"system_identstr",     getidentstr      },
{"system_defaultfont",  setdefaultfont   },
#ifdef _DEBUG
{"freeze_image",        freezeimage      },
{"frameserver_debugstall", debugstall    },
#endif
#ifdef ARCAN_LWA
{"VRES_AUTORES", videocanvasrsz },
#endif
{NULL, NULL}
};
#undef EXT_MAPTBL_SYSTEM
	register_tbl(ctx, sysfuns);

#define EXT_MAPTBL_IODEV
static const luaL_Reg iofuns[] = {
{"kbd_repeat",          kbdrepeat        },
{"toggle_mouse_grab",   mousegrab        },
{"input_capabilities",  inputcap         },
{"input_samplebase",    inputbase        },
{"set_led",             setled           },
{"led_intensity",       led_intensity    },
{"set_led_rgb",         led_rgb          },
{"controller_leds",     n_leds           },
{"vr_setup",            vr_setup         },
{"vr_map_limb",         vr_maplimb       },
{"vr_metadata",         vr_getmeta       },
{"inputanalog_filter",  inputfilteranalog},
{"inputanalog_query",   inputanalogquery},
{"inputanalog_toggle",  inputanalogtoggle},
{NULL, NULL},
};
#undef EXT_MAPTBL_IODEV
	register_tbl(ctx, iofuns);

#define EXT_MAPTBL_VIDSYS
static const luaL_Reg vidsysfuns[] = {
{"switch_default_scalemode",         setscalemode   },
{"switch_default_texmode",           settexmode     },
{"switch_default_imageproc",         setimageproc   },
{"switch_default_texfilter",         settexfilter   },
{"set_context_attachment",           setdefattach   },
{"resize_video_canvas",              videocanvasrsz },
{"video_displaymodes",               videodisplay   },
{"video_displaydescr",               videodispdescr },
{"video_displaygamma",               videodispgamma },
{"map_video_display",                videomapping   },
{"video_display_state",              videodpms      },
{"video_3dorder",                    v3dorder       },
{"build_shader",                     buildshader    },
{"delete_shader",                    deleteshader   },
{"valid_vid",                        validvid       },
{"video_synchronization",            videosynch     },
{"shader_uniform",                   shader_uniform },
{"shader_ugroup",                    shader_ugroup  },
{"push_video_context",               pushcontext    },
{"storepush_video_context",          pushcontext_ext},
{"storepop_video_context",           popcontext_ext },
{"pop_video_context",                popcontext     },
{"current_context_usage",            contextusage   },
{NULL, NULL},
};
#undef EXT_MAPTBL_VIDSYS
	register_tbl(ctx, vidsysfuns);

#define EXT_MAPTBL_NETWORK
static const luaL_Reg netfuns[] = {
{"net_open",         net_open        },
{"net_push",         net_pushcl      },
{"net_listen",       net_listen      },
{"net_push_srv",     net_pushsrv     },
{"net_disconnect",   net_disconnect  },
{"net_discover",     net_discover    },
{"net_authenticate", net_authenticate},
{"net_accept",       net_accept      },
{NULL, NULL},
};
#undef EXT_MAPTBL_NETWORK
	register_tbl(ctx, netfuns);

/*
 * METATABLE definitions
 *  [calcImage] => used for calctargets
 */
	luaL_newmetatable(ctx, "calcImage");
	lua_pushvalue(ctx, -1);
	lua_setfield(ctx, -2, "__index");
	lua_pushcfunction(ctx, procimage_get);
	lua_setfield(ctx, -2, "get");
	lua_pushcfunction(ctx, procimage_histo);
	lua_setfield(ctx, -2, "histogram_impose");
	lua_pushcfunction(ctx, procimage_lookup);
	lua_setfield(ctx, -2, "frequency");
	lua_pop(ctx, 1);

/* [meshAccess] => used for accessing a mesh_storage */
	luaL_newmetatable(ctx, "meshAccess");
	lua_pushvalue(ctx, -1);
	lua_setfield(ctx, -2, "__index");
	lua_pushcfunction(ctx, meshaccess_verts);
	lua_setfield(ctx, -2, "vertices");
	lua_pushcfunction(ctx, meshaccess_indices);
	lua_setfield(ctx, -2, "indices");
		lua_pushcfunction(ctx, meshaccess_texcos);
	lua_setfield(ctx, -2, "texcos");
	lua_pushcfunction(ctx, meshaccess_texcos);
	lua_setfield(ctx, -2, "texture_coordinates");
	lua_pushcfunction(ctx, meshaccess_colors);
	lua_setfield(ctx, -2, "colors");
	lua_pushcfunction(ctx, meshaccess_type);
	lua_setfield(ctx, -2, "primitive_type");
	lua_pop(ctx, 1);

	int top = lua_gettop(ctx);
	extend_baseapi(ctx);
	luaopen_bit(ctx);
	lua_settop(ctx, top);

	atexit(arcan_lua_cleanup);
	return ARCAN_OK;
}

void arcan_lua_pushglobalconsts(lua_State* ctx){
	struct monitor_mode mode = platform_video_dimensions();

#define EXT_CONSTTBL_GLOBINT
	struct { const char* key; int val; } consttbl[] = {
{"EXIT_SUCCESS", EXIT_SUCCESS},
{"EXIT_FAILURE", EXIT_FAILURE},
/* these two constants are an old left-over from easier times when there was no
 * multi-monitor support, and should be phased out with a support script that
 * uses physical- dimensions (mm) and output display pixel density to calculate
 * sizes */
{"VRESW", mode.width},
{"VRESH", mode.height},
{"MAX_SURFACEW", MAX_SURFACEW},
{"MAX_SURFACEH", MAX_SURFACEH},
{"MAX_TARGETW", ARCAN_SHMPAGE_MAXW},
{"MAX_TARGETH", ARCAN_SHMPAGE_MAXH},
{"STACK_MAXCOUNT", CONTEXT_STACK_LIMIT},
{"FRAMESET_SPLIT", ARCAN_FRAMESET_SPLIT},
{"FRAMESET_MULTITEXTURE", ARCAN_FRAMESET_MULTITEXTURE},
{"FRAMESET_NODETACH", FRAMESET_NODETACH},
{"FRAMESET_DETACH", FRAMESET_DETACH},
{"FRAMESERVER_INPUT", CONST_FRAMESERVER_INPUT},
{"FRAMESERVER_OUTPUT", CONST_FRAMESERVER_OUTPUT},
{"BLEND_NONE", BLEND_NONE},
{"BLEND_ADD", BLEND_ADD},
{"BLEND_MULTIPLY", BLEND_MULTIPLY},
{"BLEND_NORMAL", BLEND_NORMAL},
{"ANCHOR_UL", ANCHORP_UL},
{"ANCHOR_UR", ANCHORP_UR},
{"ANCHOR_LL", ANCHORP_LL},
{"ANCHOR_LR", ANCHORP_LR},
{"ANCHOR_C", ANCHORP_C},
{"ANCHOR_UC", ANCHORP_UC},
{"ANCHOR_LC", ANCHORP_LC},
{"ANCHOR_CL", ANCHORP_CL},
{"ANCHOR_CR", ANCHORP_CR},
{"FRAMESERVER_LOOP", 0},
{"FRAMESERVER_NOLOOP", 1},
{"TYPE_FRAMESERVER", ARCAN_TAG_FRAMESERV},
{"TYPE_3DOBJECT", ARCAN_TAG_3DOBJ},
{"TARGET_SYNCHRONOUS", TARGET_FLAG_SYNCHRONOUS},
{"TARGET_NOALPHA", TARGET_FLAG_NO_ALPHA_UPLOAD},
{"TARGET_VSTORE_SYNCH", TARGET_FLAG_VSTORE_SYNCH},
{"TARGET_VERBOSE", TARGET_FLAG_VERBOSE},
{"TARGET_AUTOCLOCK", TARGET_FLAG_AUTOCLOCK},
{"TARGET_NOBUFFERPASS", TARGET_FLAG_NO_BUFFERPASS},
{"TARGET_ALLOWCM", TARGET_FLAG_ALLOW_CM},
{"TARGET_ALLOWHDR", TARGET_FLAG_ALLOW_HDRF16},
{"TARGET_ALLOWLODEF", TARGET_FLAG_ALLOW_LDEF},
{"TARGET_ALLOWVECTOR", TARGET_FLAG_ALLOW_VOBJ},
{"TARGET_ALLOWINPUT", TARGET_FLAG_ALLOW_INPUT},
{"TARGET_ALLOWGPU", TARGET_FLAG_ALLOW_GPUAUTH},
{"TARGET_LIMITSIZE", TARGET_FLAG_LIMIT_SIZE},
{"DISPLAY_STANDBY", ADPMS_STANDBY},
{"DISPLAY_OFF", ADPMS_OFF},
{"DISPLAY_SUSPEND", ADPMS_SUSPEND},
{"DISPLAY_ON", ADPMS_ON},
{"DEVICE_INDIRECT", DEVICE_INDIRECT},
{"DEVICE_DIRECT", DEVICE_DIRECT},
{"DEVICE_LOST", DEVICE_LOST},
{"RENDERTARGET_NOSCALE", RENDERTARGET_NOSCALE},
{"RENDERTARGET_SCALE", RENDERTARGET_SCALE},
{"RENDERTARGET_NODETACH", RENDERTARGET_NODETACH},
{"RENDERTARGET_DETACH", RENDERTARGET_DETACH},
{"RENDERTARGET_COLOR", RENDERFMT_COLOR},
{"RENDERTARGET_DEPTH", RENDERFMT_DEPTH},
{"RENDERTARGET_MULTISAMPLE", RENDERFMT_MSAA},
{"RENDERTARGET_ALPHA", RENDERFMT_RETAIN_ALPHA},
{"RENDERTARGET_FULL", RENDERFMT_FULL},
{"READBACK_MANUAL", 0},
{"ROTATE_RELATIVE", CONST_ROTATE_RELATIVE},
{"ROTATE_ABSOLUTE", CONST_ROTATE_ABSOLUTE},
{"TEX_REPEAT", ARCAN_VTEX_REPEAT},
{"TEX_CLAMP", ARCAN_VTEX_CLAMP},
{"FILTER_NONE", ARCAN_VFILTER_NONE},
{"FILTER_LINEAR", ARCAN_VFILTER_LINEAR},
{"FILTER_BILINEAR", ARCAN_VFILTER_BILINEAR},
{"FILTER_TRILINEAR", ARCAN_VFILTER_TRILINEAR},
{"INTERP_LINEAR", ARCAN_VINTER_LINEAR},
{"INTERP_SINE", ARCAN_VINTER_SINE},
{"INTERP_EXPIN", ARCAN_VINTER_EXPIN},
{"INTERP_EXPOUT", ARCAN_VINTER_EXPOUT},
{"INTERP_EXPINOUT", ARCAN_VINTER_EXPINOUT},
{"INTERP_SMOOTHSTEP", ARCAN_VINTER_SMOOTHSTEP},
{"SCALE_NOPOW2", ARCAN_VIMAGE_NOPOW2},
{"SCALE_POW2", ARCAN_VIMAGE_SCALEPOW2},
{"IMAGEPROC_NORMAL", IMAGEPROC_NORMAL},
{"IMAGEPROC_FLIPH", IMAGEPROC_FLIPH },
{"WORLDID", ARCAN_VIDEO_WORLDID},
{"CLIP_ON", ARCAN_CLIP_ON},
{"CLIP_OFF", ARCAN_CLIP_OFF},
{"CLIP_SHALLOW", ARCAN_CLIP_SHALLOW},
{"BADID", ARCAN_EID},
{"CLOCKRATE", ARCAN_TIMER_TICK},
{"CLOCK", 0},
{"ALLOC_QUALITY_LOW", VSTORE_HINT_LODEF},
{"ALLOC_QUALITY_NORMAL", VSTORE_HINT_NORMAL},
{"ALLOC_QUALITY_HIGH", VSTORE_HINT_HIDEF},
{"ALLOC_QUALITY_FLOAT16", VSTORE_HINT_F16},
{"ALLOC_QUALITY_FLOAT32", VSTORE_HINT_F32},
{"APPL_RESOURCE", RESOURCE_APPL},
{"APPL_STATE_RESOURCE", RESOURCE_APPL_STATE},
{"APPL_TEMP_RESOURCE",RESOURCE_APPL_TEMP},
{"SHARED_RESOURCE", RESOURCE_APPL_SHARED},
{"SYS_APPL_RESOURCE", RESOURCE_SYS_APPLBASE},
{"SYS_FONT_RESOURCE", RESOURCE_SYS_FONT},
{"ALL_RESOURCES", DEFAULT_USERMASK},
{"API_VERSION_MAJOR", LUAAPI_VERSION_MAJOR},
{"API_VERSION_MINOR", LUAAPI_VERSION_MINOR},
{"HISTOGRAM_SPLIT", HIST_SPLIT},
{"HISTOGRAM_MERGE", HIST_MERGE},
{"HISTOGRAM_MERGE_NOALPHA", HIST_MERGE_NOALPHA},
{"LAUNCH_EXTERNAL", 0},
{"LAUNCH_INTERNAL", 1},
{"HINT_NONE", HINT_NONE},
{"HINT_PRIMARY", HINT_FL_PRIMARY},
{"HINT_FIT", HINT_FIT},
{"HINT_CROP", HINT_CROP},
{"HINT_ROTATE_CW_90", HINT_ROTATE_CW_90},
{"HINT_ROTATE_CCW_90", HINT_ROTATE_CCW_90},
{"HINT_YFLIP", HINT_YFLIP},
{"TD_HINT_CONTINUED", 1},
{"TD_HINT_INVISIBLE", 2},
{"TD_HINT_UNFOCUSED", 4},
{"TD_HINT_MAXIMIZED", 8},
{"TD_HINT_FULLSCREEN", 16},
{"TD_HINT_IGNORE", 128},
{"MASK_LIVING", MASK_LIVING},
{"MASK_ORIENTATION", MASK_ORIENTATION},
{"MASK_OPACITY", MASK_OPACITY},
{"MASK_POSITION", MASK_POSITION},
{"MASK_SCALE", MASK_SCALE},
{"MASK_UNPICKABLE", MASK_UNPICKABLE},
{"MASK_FRAMESET", MASK_FRAMESET},
{"MASK_MAPPING", MASK_MAPPING},
{"FORMAT_PNG", OUTFMT_PNG},
{"FORMAT_PNG_FLIP", OUTFMT_PNG_FLIP},
{"FORMAT_RAW8", OUTFMT_RAW8},
{"FORMAT_RAW24", OUTFMT_RAW24},
{"FORMAT_RAW32", OUTFMT_RAW32},
{"ORDER_FIRST", ORDER3D_FIRST},
{"ORDER_NONE", ORDER3D_NONE},
{"ORDER_LAST", ORDER3D_LAST},
{"ORDER_SKIP", ORDER3D_NONE},
{"MOUSE_GRABON", MOUSE_GRAB_ON},
{"MOUSE_GRABOFF", MOUSE_GRAB_OFF},
{"MOUSE_BTNLEFT", 1},
{"MOUSE_BTNMIDDLE", 2},
{"MOUSE_BTNRIGHT", 3},
/* DEPRECATE */ {"LEDCONTROLLERS", arcan_led_controllers()},
{"KEY_CONFIG", DVT_CONFIG},
{"KEY_TARGET", DVT_TARGET},
{"NOW", 0},
{"NOPERSIST", 0},
{"PERSIST", 1},
{"NET_BROADCAST", 0},
{"DEBUGLEVEL", luactx.debug}
};
#undef EXT_CONSTTBL_GLOBINT

	for (size_t i = 0; i < COUNT_OF(consttbl); i++)
		arcan_lua_setglobalint(ctx, consttbl[i].key, consttbl[i].val);

/* same problem as with VRESW, VRESH */
	float hppcm = mode.width && mode.phy_width ?
		10 * ((float) mode.width / (float)mode.phy_width) : 38.4;
	float vppcm = mode.height && mode.phy_height ?
		10 * ((float) mode.height / (float)mode.phy_height) : 38.4;

	lua_pushnumber(ctx, hppcm);
	lua_setglobal(ctx, "HPPCM");

	lua_pushnumber(ctx, vppcm);
	lua_setglobal(ctx, "VPPCM");

	lua_pushnumber(ctx, 0.352778);
	lua_setglobal(ctx, "FONT_PT_SZ");

	arcan_lua_setglobalstr(ctx, "GL_VERSION", agp_ident());
	arcan_lua_setglobalstr(ctx, "SHADER_LANGUAGE", agp_shader_language());
	arcan_lua_setglobalstr(ctx, "FRAMESERVER_MODES", arcan_frameserver_atypes());
	arcan_lua_setglobalstr(ctx, "APPLID", arcan_appl_id());
	arcan_lua_setglobalstr(ctx, "API_ENGINE_BUILD", ARCAN_BUILDVERSION);

	if (luactx.last_crash_source){
		arcan_lua_setglobalstr(ctx, "CRASH_SOURCE", luactx.last_crash_source);
		luactx.last_crash_source = NULL;
	}
}

/*
 * What follows is just the mass of coded needed to serialize
 * as much of the internal state of the engine as possible
 * over a FILE* stream in a form that can be decoded and used
 * by a monitoring script to help debugging and performance
 * optimizations
 */
static const char* const vobj_flags(arcan_vobject* src)
{
	static char fbuf[sizeof("persist clip noasynch "
		"cycletransform rothier_origo order ")];

	fbuf[0] = '\0';
	if (FL_TEST(src, FL_PRSIST))
		strcat(fbuf, "persist ");
	if (src->clip != ARCAN_CLIP_OFF)
		strcat(fbuf, "clip ");
	if (FL_TEST(src, FL_NASYNC))
		strcat(fbuf, "noasynch ");
	if (FL_TEST(src, FL_TCYCLE))
		strcat(fbuf, "cycletransform ");
	if (FL_TEST(src, FL_ROTOFS))
		strcat(fbuf, "rothier_origo ");
	if (FL_TEST(src, FL_ORDOFS))
		strcat(fbuf, "order ");
	return fbuf;
}

static char* lut_filtermode(enum arcan_vfilter_mode mode)
{
	mode = mode & (~ARCAN_VFILTER_MIPMAP);
	switch(mode){
	case ARCAN_VFILTER_NONE     : return "none";
	case ARCAN_VFILTER_LINEAR   : return "linear";
	case ARCAN_VFILTER_BILINEAR : return "bilinear";
	case ARCAN_VFILTER_TRILINEAR: return "trilinear";
	case ARCAN_VFILTER_MIPMAP:break;
	}
	return "[missing filter]";
}

static char* lut_imageproc(enum arcan_imageproc_mode mode)
{
	switch(mode){
	case IMAGEPROC_NORMAL: return "normal";
	case IMAGEPROC_FLIPH : return "vflip";
	}
	return "[missing proc]";
}

static char* lut_scale(enum arcan_vimage_mode mode)
{
	switch(mode){
	case ARCAN_VIMAGE_NOPOW2    : return "nopow2";
	case ARCAN_VIMAGE_SCALEPOW2 : return "scalepow2";
	}
	return "[missing scale]";
}

static char* lut_framemode(enum arcan_framemode mode)
{
	switch(mode){
	case ARCAN_FRAMESET_SPLIT        : return "split";
	case ARCAN_FRAMESET_MULTITEXTURE : return "multitexture";
	}
	return "[missing framemode]";
}

static char* lut_clipmode(enum arcan_clipmode mode)
{
	switch(mode){
	case ARCAN_CLIP_OFF     : return "disabled";
	case ARCAN_CLIP_ON      : return "stencil deep";
	case ARCAN_CLIP_SHALLOW : return "stencil shallow";
	}
	return "[missing clipmode]";
}

static char* lut_blendmode(enum arcan_blendfunc func)
{
	switch(func){
	case BLEND_NONE     : return "disabled";
	case BLEND_NORMAL   : return "normal";
	case BLEND_FORCE    : return "forceblend";
	case BLEND_ADD      : return "additive";
	case BLEND_MULTIPLY : return "multiply";
	}
	return "[missing blendmode]";
}

/*
 * Ignore LOCALE RADIX settings...
 * Some dependencies actually dynamically change locale
 * affecting float representation during fprintf (nice race there)
 * by defining nan and infinite locally first (see further below)
 * we cover that case, but still need to go through the headache
 * of splitting
 */
static void fprintf_float(FILE* dst,
	const char* pre, float in, const char* post)
{
	float intp, fractp;
 	fractp = modff(in, &intp);

	if (isnan(in))
		fprintf(dst, "%snan%s", pre, post);
	else if (isinf(in))
		fprintf(dst, "%sinf%s", pre, post);
	else
		fprintf(dst, "%s%d.%d%s", pre, (int)intp, abs((int)fractp), post);
}

static char* lut_txmode(int txmode)
{
	switch (txmode){
	case ARCAN_VTEX_REPEAT:
		return "repeat";
	case ARCAN_VTEX_CLAMP:
		return "clamp(edge)";
	default:
		return "unknown(broken)";
	}
}

static char* lut_kind(arcan_vobject* src)
{
	if (src->feed.state.tag == ARCAN_TAG_IMAGE)
		return src->vstore->txmapped ? "textured" : "single color";
	else if (src->feed.state.tag == ARCAN_TAG_FRAMESERV)
		return "frameserver";
	else if (src->feed.state.tag == ARCAN_TAG_ASYNCIMGLD)
		return "textured_loading";
	else if (src->feed.state.tag == ARCAN_TAG_ASYNCIMGRD)
		return "texture_ready";
	else if (src->feed.state.tag == ARCAN_TAG_3DOBJ)
		return "3dobject";
	else
		return "dead";
}

/*
 * Note: currently, all the dump_ functions are used primarily as
 * debugging tools. They are parser- safe in the sense that strings
 * are escaped with Luas rather atrocious [[ [[= [[=== etc.
 *
 * If that is a concern, add an escape routine for all [[%s]] patterns.
 */
static void dump_props(FILE* dst, surface_properties props)
{
	fprintf_float(dst, "props.position = {", props.position.x, ", ");
	fprintf_float(dst, "", props.position.y, ", ");
	fprintf_float(dst, "", props.position.z, "};\n");

	fprintf_float(dst, "props.scale = {", props.scale.x, ", ");
	fprintf_float(dst, "", props.scale.y, ", ");
	fprintf_float(dst, "", props.scale.z, "};\n");

	fprintf_float(dst, "props.rotation = {", props.rotation.roll, ", ");
	fprintf_float(dst, "", props.rotation.pitch, ", ");
	fprintf_float(dst, "", props.rotation.yaw, "};\n");

	fprintf_float(dst, "props.opacity = ", props.opa, ";\n");
}

static int qused(struct arcan_evctx* dq)
{
	return *(dq->front) > *(dq->back) ? dq->eventbuf_sz -
	*(dq->front) + *(dq->back) : *(dq->back) - *(dq->front);
}

static const char* fsrvtos(enum ARCAN_SEGID ink)
{
	switch(ink){
	case SEGID_LWA: return "lightweight arcan";
	case SEGID_MEDIA: return "multimedia";
	case SEGID_NETWORK_SERVER: return "network-server";
	case SEGID_NETWORK_CLIENT: return "network-client";
	case SEGID_CURSOR: return "cursor";
	case SEGID_TERMINAL: return "terminal";
	case SEGID_TUI: return "tui";
	case SEGID_POPUP: return "popup";
	case SEGID_ICON: return "icon";
	case SEGID_REMOTING: return "remoting";
	case SEGID_GAME: return "game";
	case SEGID_HMD_L: return "hmd-l";
	case SEGID_HMD_R: return "hmd-r";
	case SEGID_HMD_SBS: return "hmd-sbs-lr";
	case SEGID_VM: return "vm";
	case SEGID_APPLICATION: return "application";
	case SEGID_CLIPBOARD: return "clipboard";
	case SEGID_BROWSER: return "browser";
	case SEGID_ENCODER: return "encoder";
	case SEGID_TITLEBAR: return "titlebar";
	case SEGID_SENSOR: return "sensor";
	case SEGID_SERVICE: return "service";
	case SEGID_BRIDGE_X11: return "bridge-x11";
	case SEGID_BRIDGE_WAYLAND: return "bridge-wayland";
	case SEGID_DEBUG: return "debug";
	case SEGID_WIDGET: return "widget";
	case SEGID_ACCESSIBILITY: return "accessibility";
	case SEGID_CLIPBOARD_PASTE: return "clipboard-paste";
	case SEGID_HANDOVER: return "handover";
	case SEGID_UNKNOWN: return "unknown";
	case SEGID_LIM: break;
	}
	return "";
}

/*
 * just derived from lstrlib.c, their string.format(%q)
 */
static void fput_luasafe_str(FILE* dst, const char* str)
{
	fputc('"', dst);
	while(*str){
		switch (*str){
		case '"':
		case '\\':
		case '\n':
			fputc('\\', dst);
			fputc(*str, dst);
		break;

		case '\r':
			fputs("\\r", dst);
		break;

		case '\0':
			fputs("\\000", dst);
		break;

		default:
			fputc(*str, dst);
		}
		str++;
	}

	fputc('"', dst);
}

static void dump_vstate(FILE* dst, arcan_vobject* vobj)
{
	if (!vobj->feed.state.ptr || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		return;

	arcan_frameserver* fsrv = vobj->feed.state.ptr;
fprintf(dst,
"vobj.fsrv = {\
\tlastpts = %lld,\
\taudbuf_sz = %d,\
\taudbuf_used = %d,\
\tchild_alive = %d,\
\tinevq_sz = %d,\
\tinevq_used = %d,\
\toutevq_sz = %d,\
\toutevq_used = %d,",
	(long long) fsrv->lastpts,
	(int) fsrv->sz_audb,
	(int) fsrv->ofs_audb,
	(int) fsrv->flags.alive,
	(int) fsrv->inqueue.eventbuf_sz,
	qused(&fsrv->inqueue),
	(int) fsrv->outqueue.eventbuf_sz,
	qused(&fsrv->outqueue));

	fprintf(dst, "\tsource = ");
	fput_luasafe_str(dst, fsrv->source ? fsrv->source : "NULL");
	fprintf(dst, ",\n\tkind = ");
	fput_luasafe_str(dst, fsrvtos(fsrv->segid));
	fprintf(dst, "};\n");
}

static void dump_vobject(FILE* dst, arcan_vobject* src)
{
	char* mask = maskstr(src->mask);

/*
 * note that most strings á glstore_*, scale* etc. are safe in the sense that
 * they are not user-supplied in any way. We ignore last_updated as parameter
 * to remove "useless" values in diffs. Add if needed for debugging cache.
 */
	fprintf(dst,
"vobj = {\n\
\torigw = %d,\n\
\torigh = %d,\n\
\torder = %d,\n\
\tlifetime = %d,\n\
\tcellid = %d,\n\
\tvalid_cache = %d,\n\
\trotate_state = %d,\n\
\tframeset_capacity = %d,\n\
\tframeset_mode = [[%s]],\n\
\tframeset_counter = %d,\n\
\tframeset_current = %d,\n"
#ifdef _DEBUG
"\textrefc_attachments = %d,\n\
\textrefc_links = %d,\n"
#endif
"\tstorage_source = [[%s]],\n\
\tstorage_size = %d,\n\
\tglstore_w = %d,\n\
\tglstore_h = %d,\n\
\tglstore_bpp = %d,\n\
\tglstore_prgid = %d,\n\
\tglstore_txu = [[%s]],\n\
\tglstore_txv = [[%s]],\n\
\tglstore_prg = [[%s]],\n\
\tscalemode  = [[%s]],\n\
\timageproc = [[%s]],\n\
\tblendmode = [[%s]],\n\
\tclipmode  = [[%s]],\n\
\tfiltermode = [[%s]],\n\
\tflags = [[%s]],\n\
\tmask = [[%s]],\n\
\tframeset = {},\n\
\tkind = [[%s]],\n\
",
(int) src->origw,
(int) src->origh,
(int) src->order,
(int) src->lifetime,
(int) src->cellid,
(int) src->valid_cache,
(int) src->rotate_state,
(int) (src->frameset ? src->frameset->n_frames : -1),
src->frameset ? lut_framemode(src->frameset->mode) : "",
(int) (src->frameset ? src->frameset->mctr : -1),
(int) (src->frameset ? src->frameset->ctr : -1),
#ifdef _DEBUG
(int) src->extrefc.attachments,
(int) src->extrefc.links,
#endif
(src->vstore->txmapped && src->vstore->vinf.text.source) ?
	src->vstore->vinf.text.source : "unknown",
(int) src->vstore->vinf.text.s_raw,
(int) src->vstore->w,
(int) src->vstore->h,
(int) src->vstore->bpp,
(int) src->program,
lut_txmode(src->vstore->txu),
lut_txmode(src->vstore->txv),
agp_shader_lookuptag(src->program),
lut_scale(src->vstore->scale),
lut_imageproc(src->vstore->imageproc),
lut_blendmode(src->blendmode),
lut_clipmode(src->clip),
lut_filtermode(src->vstore->filtermode),
vobj_flags(src),
mask,
lut_kind(src));

	fprintf(dst, "tracetag = ");
	fput_luasafe_str(dst, src->tracetag ? src->tracetag : "no tag");
	fputs(",\n", dst);

	fprintf_float(dst, "origoofs = {", src->origo_ofs.x, ", ");
	fprintf_float(dst, "", src->origo_ofs.y, ", ");
	fprintf_float(dst, "", src->origo_ofs.z, "}\n};\n");

	if (src->vstore->txmapped){
		fprintf(dst, "vobj.glstore_glid = %d;\n\
vobj.glstore_refc = %zu;\n", src->vstore->vinf.text.glid,
			src->vstore->refcount);
	} else {
		fprintf_float(dst, "vobj.glstore_col = {", src->vstore->vinf.col.r, ", ");
		fprintf_float(dst, "", src->vstore->vinf.col.g, ", ");
		fprintf_float(dst, "", src->vstore->vinf.col.b, "};\n");
	}

	if (src->frameset)
	for (size_t i = 0; i < src->frameset->ctr; i++)
	{
		fprintf(dst, "vobj.frameset[%zu] = %d\n", i + 1,
			src->frameset->frames[i].frame->vinf.text.glid);
	}

	if (src->children){
		fprintf(dst, "vobj.children = {};\n");
		fprintf(dst, "vobj.childslots = %d;\n", (int) src->childslots);
		for (size_t i = 0; i < src->childslots; i++){
			fprintf(dst, "vobj.children[%zu] = %"PRIxVOBJ";\n", i+1, src->children[i] ?
				src->children[i]->cellid : ARCAN_EID);
		}
	}

	if (src->parent->cellid == ARCAN_VIDEO_WORLDID){
		fprintf(dst, "vobj.parent = \"WORLD\";\n");
	} else {
		fprintf(dst, "vobj.parent = %"PRIxVOBJ";\n", src->parent->cellid);
	}

	dump_vstate(dst, src);
	fprintf(dst, "props = {};\n");
	dump_props(dst, src->current);
	fprintf(dst, "vobj.props = props;\n");

	free(mask);
}

void arcan_lua_statesnap(FILE* dst, const char* tag, bool delim)
{
/*
 * display global settings, wrap to local ptr for shorthand */
/* missing shaders,
 * missing event-queues
 */
	struct arcan_video_display* disp = &arcan_video_display;
	struct monitor_mode mmode = platform_video_dimensions();

fprintf(dst, " do \n\
local nan = 0/0;\n\
local inf = math.huge;\n\
local vobj = {};\n\
local props = {};\n\
local restbl = {\n\
\tdisplay = {\n\
\t\twidth = %d,\n\
\t\theight = %d,\n\
\t\tconservative = %d,\n\
\t\tticks = %lld,\n\
\t\tdefault_vitemlim = %d,\n\
\t\timageproc = %d,\n\
\t\tscalemode = %d,\n\
\t\tfiltermode = %d,\n\
\t};\n\
\tvcontexts = {};\
};\n\
", (int)mmode.width, (int)mmode.height, disp->conservative ? 1 : 0,
	(long long int)disp->c_ticks,
	(int)disp->default_vitemlim,
	(int)disp->imageproc, (int)disp->scalemode, (int)disp->filtermode);

	fprintf(dst, "restbl.message = ");
	fput_luasafe_str(dst, tag ? tag : "");
	fprintf(dst, ";\n");

	int cctx = vcontext_ind;
	while (cctx >= 0){
/* foreach context, header */
fprintf(dst,
"local ctx = {\n\
\tvobjs = {},\n\
\trtargets = {}\n\
};");

	struct arcan_video_context* ctx = &vcontext_stack[cctx];
	fprintf(dst,
"ctx.ind = %d;\n\
ctx.alive = %d;\n\
ctx.limit = %d;\n\
ctx.tickstamp = %lld;\n",
(int) cctx,
(int) ctx->nalive,
(int) ctx->vitem_limit,
(long long int) ctx->last_tickstamp
);

		for (size_t i = 0; i < ctx->vitem_limit; i++){
			if (!FL_TEST(&(ctx->vitems_pool[i]), FL_INUSE))
				continue;

			dump_vobject(dst, ctx->vitems_pool + i);
			fprintf(dst, "\
vobj.cellid_translated = %ld;\n\
ctx.vobjs[vobj.cellid] = vobj;\n", (long int)vid_toluavid(i));
		}

		for (size_t i = 0; i < ctx->n_rtargets; i++){
			struct rendertarget* rtgt = &ctx->rtargets[i];
			fprintf(dst, "\
local rtgt = {\n\
	attached = {");
			struct arcan_vobject_litem* first = rtgt->first;
			while(first){
				fprintf(dst, "%" PRIxVOBJ", ", first->elem->cellid);
				first = first->next;
			}
			fprintf(dst, "},\n\
color_id = %" PRIxVOBJ",\n"
#ifdef _DEBUG
"attach_refc = %d,\n"
#endif
"readback = %d,\n\
readcnt = %d,\n\
refresh = %d,\n\
refreshcnt = %d,\n\
transfc = %zu,\n\
camtag = %"PRIxVOBJ",\n\
flags = %d\n\
};\n\
table.insert(ctx.rtargets, rtgt);\n\
", rtgt->color ? rtgt->color->cellid : ARCAN_EID,
#ifdef _DEBUG
		rtgt->color->extrefc.attachments,
#endif
		rtgt->readback, rtgt->readcnt, rtgt->refresh, rtgt->refreshcnt,
		rtgt->transfc, rtgt->camtag, rtgt->flags
);
		}

		fprintf(dst,"table.insert(restbl.vcontexts, ctx);");
		cctx--;
	}

	if (benchdata.bench_enabled){
		size_t bsz = COUNT_OF(benchdata.ticktime);
		size_t fsz = COUNT_OF(benchdata.frametime);
		size_t csz = COUNT_OF(benchdata.framecost);

		int i = (benchdata.tickofs + 1) % bsz;
		fprintf(dst, "\nrestbl.benchmark = {};\nrestbl.benchmark.ticks = {");
		while (i != benchdata.tickofs){
			fprintf(dst, "%d,", benchdata.ticktime[i]);
			i = (i + 1) % bsz;
		}
		fprintf(dst, "};\nrestbl.benchmark.frames = {");
		i = (benchdata.frameofs + 1) % fsz;
		while (i != benchdata.frameofs){
			fprintf(dst, "%d,", benchdata.frametime[i]);
			i = (i + 1) % fsz;
		}
		fprintf(dst, "};\nrestbl.benchmark.framecost = {");
		i = (benchdata.costofs + 1) % csz;
		while (i != benchdata.costofs){
			fprintf(dst, "%d,", benchdata.framecost[i]);
			i = (i + 1) % csz;
		}
		fprintf(dst, "};\n");

		memset(benchdata.ticktime, '\0', sizeof(benchdata.ticktime));
		memset(benchdata.frametime, '\0', sizeof(benchdata.frametime));
		memset(benchdata.framecost, '\0', sizeof(benchdata.framecost));
		benchdata.tickofs = benchdata.frameofs = benchdata.costofs = 0;
	}

/* foreach context, footer */
	fprintf(dst, "return restbl;\nend\n%s", delim ? "#ENDBLOCK\n" : "");
	fflush(dst);
}

/* this assumes a trusted (src), as injected \0 could make the
 * strstr fail and buffer indefinately
 * (so if this assumption breaks in the future,
 * scan and strip the input dataset for \0s */
void arcan_lua_stategrab(lua_State* ctx, char* dstfun, int src)
{
/* maintaing a growing buffer that is just populated with lines read
 * from (src). When we uncover an endblock, we do a pcall and then
 * push the value to the stack. */
	static char* statebuf;
	static size_t statebuf_sz, statebuf_ofs;
	static struct pollfd inpoll;

/* initial setup */
	if (!statebuf){
		statebuf_sz = 1024;
		statebuf = arcan_alloc_mem(statebuf_sz, ARCAN_MEM_STRINGBUF,
			ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

		inpoll.fd = src;
		inpoll.events = POLLIN;
	}

/* flush read into buffer, parse buffer for \n#ENDBLOCK\n pattern */
	if (poll(&inpoll, 1, 0) > 0){
		int ntr = statebuf_sz - 1 - statebuf_ofs;
		int nr = read(src, statebuf + statebuf_ofs, ntr);

		if (nr > 0){
			statebuf_ofs += nr;
			char* substrp = strstr(statebuf, "\n#ENDBLOCK\n");
/* got one? parse then slide */
			if (substrp){
				substrp[1] = '\0';

/*
 * FILE* outf = fopen("dumpfile", "w+");
 * fwrite(statebuf, 1, strlen(statebuf), outf);
 * fclose(outf);
 */
				lua_getglobal(ctx, "sample");
				if (!lua_isfunction(ctx, -1)){
					lua_pop(ctx, 1);
					arcan_warning("stategrab(), couldn't find "
						"function 'sample' in debugscript. Sample ignored.\n");
				} else {
					int top = lua_gettop(ctx);
					luaL_loadstring(ctx, statebuf);
					lua_call(ctx, 0, LUA_MULTRET);
					int narg = lua_gettop(ctx) - top;
					lua_call(ctx, narg, 0);
				}

/* statebuf:****substrp\n#ENDBLOCK\n(11)****(statebuf_ofs) **** statebufsz-1 \0*/
				substrp += 11;
				int ntm = statebuf_ofs - (substrp - statebuf);
				if (ntm > 0){
					memmove(statebuf, substrp, ntm);
					statebuf_ofs = ntm;
				} else {
					statebuf_ofs = 0;
				}
				memset(statebuf + statebuf_ofs, '\0', statebuf_sz - statebuf_ofs);
			}
/* need more data, buffer or possibly realloc */
		}

		if (statebuf_ofs == statebuf_sz - 1){
			statebuf_sz <<= 1;
			char* newp = realloc(statebuf, statebuf_sz);
			if (newp)
				statebuf = newp;
			else
				statebuf_sz >>= 1;
		}

	}

}
