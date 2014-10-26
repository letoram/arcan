/* Arcan-fe, scriptable front-end engine
*
* Arcan-fe is the legal property of its developers, please refer
* to the COPYRIGHT file distributed with this source distribution.
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public License
* as published by the Free Software Foundation; either version 3
* of the License, or (at your option) any later version.

* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with this program; if not, write to the Free Software
* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
*
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
 *   wild relying in the behavior.
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
#include <pthread.h>
#include <ctype.h>
#include <setjmp.h>

#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>

#include <assert.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#ifndef WIN32
#include <poll.h>
#else
/* windows doesn't support non-blocking file I/O as such
 * (no surprise there) ignore for now and get some workaround
 * going. */
#define O_NONBLOCK 0
#endif

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

#ifdef LUA51_JIT
#include <luajit.h>
#endif
#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shdrmgmt.h"
#include "arcan_3dbase.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_db.h"
#include "arcan_frameserver.h"
#include "arcan_shmif.h"

#include GL_HEADERS

#define arcan_luactx lua_State
#include "arcan_lua.h"

#ifndef ARCAN_LUA_LED
#include "arcan_led.h"
#endif

/*
 * namespaces permitted to be searched for regular resource lookups
 */
#ifndef DEFAULT_USERMASK
#define DEFAULT_USERMASK \
	(RESOURCE_APPL | RESOURCE_APPL_SHARED | RESOURCE_APPL_TEMP)
#endif

/*
 * defined in engine/arcan_main.c, rather than terminating directly
 * we'll longjmp to this and hopefully the engine can switch scripts
 * or take similar user-defined action.
 */
extern jmp_buf arcanmain_recover_state;

/*
 * some operations, typically resize, move and rotate suffered a lot from
 * lua floats propagating, meaning that we'd either get subpixel positioning
 * and blurring text etc. as a consequence. For these functions, we now
 * force the type to whatever acoord is specified as (here, signed).
 */
typedef int acoord;

/*
 * arcan_fatal calls in this context are invalid Lua script invocations,
 * these should only forward to arcan_fatal if there's no recovery script
 * set.
 */
#define arcan_fatal(...) { lua_rectrigger( __VA_ARGS__); }

/* this macro is placed in every arcan- specific function callable from the LUA
 * space. By default, it's empty, but can be used to map out stack contents
 * (above will only be LUA context pointer that can be used to devise the
 * calling function, or to output "reasonably" cheap profiling (entry
 * will be either a frameserver/image/etc. callback or the few (_event,
 * _clock_pulse, _frame_pulse etc.) entry-point can be found (with >= 1
 * debug_level in lua_ctx_store.lastsrc and timing data can be gotten
 * from arcan_timemillis()
	example: */
#define LUA_TRACE(fsym)
/*
 * #define LUA_TRACE(fsym) fprintf(stderr, "(%lld:%s)->%s\n", \
		arcan_timemillis(), lua_ctx_store.lastsrc, fsym);
 */

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
#define CONST_MAX_SURFACEW 2048
#endif

#ifndef CONST_MAX_SURFACEH
#define CONST_MAX_SURFACEH 2048
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

/* we map the constants here so that poor or confused
 * debuggers also have a chance to give us symbol resolution */
static const int MOUSE_GRAB_ON  = 20;
static const int MOUSE_GRAB_OFF = 21;

static const int MAX_SURFACEW = CONST_MAX_SURFACEH;
static const int MAX_SURFACEH = CONST_MAX_SURFACEW;

static const int FRAMESET_NODETACH = 11;
static const int FRAMESET_DETACH   = 10;

static const int RENDERTARGET_DETACH   = CONST_RENDERTARGET_DETACH;
static const int RENDERTARGET_NODETACH = CONST_RENDERTARGET_NODETACH;
static const int RENDERTARGET_SCALE    = CONST_RENDERTARGET_SCALE;
static const int RENDERTARGET_NOSCALE  = CONST_RENDERTARGET_NOSCALE;
static const int RENDERFMT_COLOR = RENDERTARGET_COLOR;
static const int RENDERFMT_DEPTH = RENDERTARGET_DEPTH;
static const int RENDERFMT_FULL  = RENDERTARGET_COLOR_DEPTH_STENCIL;

static const int POSTFILTER_NTSC = 100;
static const int POSTFILTER_OFF  = 10;

extern struct arcan_dbh* dbhandle;

enum arcan_cb_source {
	CB_SOURCE_NONE        = 0,
	CB_SOURCE_FRAMESERVER = 1,
	CB_SOURCE_IMAGE       = 2
};

struct nonblock_io {
	char buf[4096];
	off_t ofs;
	int fd;
};

static struct {
	struct nonblock_io rawres;

	const char* lastsrc;

	unsigned char debug;
	unsigned lua_vidbase;
	unsigned char grab;

	enum arcan_cb_source cb_source_kind;
	long long cb_source_tag;

/* limits themename + identifier to this length
 * will be modified in when calling into lua */
	char* prefix_buf;
	size_t prefix_ofs;

	lua_State* last_ctx;
} lua_ctx_store = {0};

extern char* _n_strdup(const char* instr, const char* alt);
static inline const char* fsrvtos(enum ARCAN_SEGID ink);

/*
 * nil out whatever functions / tables the
 * build- system defined that we should not have.
 */
static void luaL_nil_banned(struct arcan_luactx* ctx)
{
	char* work = strdup(LUA_DROPSTR);
	char* cch = strtok(work, " ");

	while (cch){
		lua_pushnil(ctx);
		lua_setglobal(ctx, cch);
		cch = strtok(NULL, " ");
	}

	free(work);
}

static inline void colon_escape(char* instr)
{
	while(*instr){
		if (*instr == ':')
			*instr = '\t';
		instr++;
	}
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
static inline intptr_t find_lua_callback(lua_State* ctx)
{
	int nargs = lua_gettop(ctx);

	for (size_t i = 1; i <= nargs; i++)
		if (lua_isfunction(ctx, i)){
			lua_pushvalue(ctx, i);
			return luaL_ref(ctx, LUA_REGISTRYINDEX);
		}

	return (intptr_t) 0;
}

static inline int find_lua_type(lua_State* ctx, int type, int ofs)
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

static void wraperr(struct arcan_luactx* ctx, int errc, const char* src);

void lua_rectrigger(const char* msg, ...)
{
	va_list args;
	va_start(args, msg);

#ifndef ARCAN_LUA_NOCOLOR
	lua_State* ctx = lua_ctx_store.last_ctx;
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
	arcan_warning("\nHanding over to recovery script "
		"(or shutdown if none present).\n");
	longjmp(arcanmain_recover_state, 2);
}

void arcan_state_dump(const char* key, const char* msg, const char* src)
{
	time_t logtime = time(NULL);
	struct tm* ltime = localtime(&logtime);
	if (!ltime){
		arcan_warning("arcan_state_dump(%s, %s, %s) failed, couldn't get localtime.",
			key, msg, src);
		return;
	}

	const char date_ptn[] = "%m%d_%H%M%S";
	char date_str[ sizeof(date_ptn) * 2 ];
	strftime(date_str, sizeof(date_str), date_ptn, ltime);

	char state_fn[ strlen(key) + sizeof(".lua") + sizeof(date_str) ];
	snprintf(state_fn, sizeof(state_fn), "%s_%s.lua", key, date_str);

	char* fname = arcan_expand_resource(state_fn, RESOURCE_SYS_DEBUG);

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
	arcan_warning("-- stack dump --\n");

	for (size_t i = 1; i <= top; i++) {
		int t = lua_type(ctx, i);

		switch (t) {
			case LUA_TBOOLEAN:
				arcan_warning(lua_toboolean(ctx, i) ? "true" : "false");
				break;
			case LUA_TSTRING:
				arcan_warning("`%s'", lua_tostring(ctx, i));
				break;
			case LUA_TNUMBER:
				arcan_warning("%g", lua_tonumber(ctx, i));
				break;
			default:
				arcan_warning("%s", lua_typename(ctx, t));
				break;
		}
		arcan_warning("  ");
	}

	arcan_warning("\n");
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
		strncpy(lua_ctx_store.prefix_buf +
			lua_ctx_store.prefix_ofs + 1, funame, 32);

		lua_ctx_store.prefix_buf[lua_ctx_store.prefix_ofs] = '_';
		lua_ctx_store.prefix_buf[lua_ctx_store.prefix_ofs + funlen + 1] = '\0';
	}
	else
		lua_ctx_store.prefix_buf[lua_ctx_store.prefix_ofs] = '\0';

	lua_getglobal(ctx, lua_ctx_store.prefix_buf);

	if (!lua_isfunction(ctx, -1)){
		lua_pop(ctx, 1);
		return false;
	}

	return true;
}

static inline char* findresource(const char* arg, enum arcan_namespaces space)
{
	char* res = arcan_find_resource(arg, space);
/* since this is invoked extremely frequently and is involved in file-system
 * related stalls, maybe a sort of caching mechanism should be implemented
 * (invalidate / refill every N ticks or have a flag to side-step it -- as a lot
 * of resources are quite static and the rest of the API have to handle missing
 * or bad resources anyhow, we also know which subdirectories to attach
 * to OS specific event monitoring effects */

	if (lua_ctx_store.debug){
		arcan_warning("Debug, resource lookup for %s, yielded: %s\n", arg, res);
	}

	return res;
}

static int zapresource(lua_State* ctx)
{
	LUA_TRACE("zap_resource");

	char* path = findresource(luaL_checkstring(ctx, 1), RESOURCE_APPL_TEMP);

	if (path && unlink(path) != -1)
		lua_pushboolean(ctx, false);
	else
		lua_pushboolean(ctx, true);

	free(path);
	return 1;
}

static int opennonblock(lua_State* ctx)
{
	LUA_TRACE("open_nonblock");

	char* path = findresource(luaL_checkstring(ctx, 1), DEFAULT_USERMASK);

	if (!path){
		return 0;
	}

	int fd = open(path, O_NONBLOCK | O_CLOEXEC | O_RDONLY);
	free(path);

	if (fd <= 0)
		return 0;

	struct nonblock_io* conn = arcan_alloc_mem(sizeof(struct nonblock_io),
			ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	conn->fd = fd;
	uintptr_t* dp = lua_newuserdata(ctx, sizeof(uintptr_t));
	*dp = (uintptr_t) conn;
	luaL_getmetatable(ctx, "nonblockIO");
	lua_setmetatable(ctx, -2);

	return 1;
}



static int rawresource(lua_State* ctx)
{
	LUA_TRACE("open_rawresource");

/* can't do more than this due to legacy */
	if (lua_ctx_store.rawres.fd > 0){
		arcan_warning("open_rawresource(), open requested while other resource "
			"still open, use close_rawresource first.\n");

		close(lua_ctx_store.rawres.fd);
		lua_ctx_store.rawres.fd = -1;
		lua_ctx_store.rawres.ofs = 0;
	}

	char* path = findresource(luaL_checkstring(ctx, 1), DEFAULT_USERMASK);

	if (!path){
		char* fname = arcan_expand_resource(
			luaL_checkstring(ctx, 1), RESOURCE_APPL_TEMP);

		if (fname){
			lua_ctx_store.rawres.fd = open(fname,
				O_CREAT | O_CLOEXEC | O_RDWR, S_IRUSR | S_IWUSR);
			free(fname);
		}
	}
	else
		lua_ctx_store.rawres.fd = open(path, O_RDONLY | O_CLOEXEC);

	lua_pushboolean(ctx, lua_ctx_store.rawres.fd > 0);
	return 1;
}

static char* chop(char* str)
{
    char* endptr = str + strlen(str) - 1;
    while(isspace(*str)) str++;

    if(!*str) return str;
    while(endptr > str && isspace(*endptr))
        endptr--;

    *(endptr+1) = 0;

    return str;
}

static int push_resstr(lua_State* ctx, struct nonblock_io* ib, off_t ofs)
{
	size_t in_sz = sizeof(lua_ctx_store.rawres.buf )/
		sizeof(lua_ctx_store.rawres.buf[0]);

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

static inline size_t bufcheck(lua_State* ctx, struct nonblock_io* ib)
{
	size_t in_sz = sizeof(lua_ctx_store.rawres.buf )/
		sizeof(lua_ctx_store.rawres.buf[0]);

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
	size_t buf_sz = sizeof(ib->buf) / sizeof(ib->buf[0]);

	if (!ib || ib->fd <= 0)
		return 0;

	size_t bufch = bufcheck(ctx, ib);
	if (bufch)
		return bufch;

	ssize_t nr;
	if ( (nr = read(ib->fd, ib->buf + ib->ofs, buf_sz - ib->ofs - 1)) > 0)
		ib->ofs += nr;

	return bufcheck(ctx, ib);
}

static int nbio_close(lua_State* ctx)
{
	LUA_TRACE("open_nonblock:close");
	struct nonblock_io** ib = luaL_checkudata(ctx, 1, "nonblockIO");
	if (*ib == NULL)
		return 0;

	close((*ib)->fd);
	free(*ib);
	*ib = NULL;

	return 0;
}

static int nbio_read(lua_State* ctx)
{
	LUA_TRACE("open_nonblock:read");
	struct nonblock_io** ib = luaL_checkudata(ctx, 1, "nonblockIO");
	if (*ib == NULL)
		return 0;

	return bufread(ctx, *ib);
}

static int readrawresource(lua_State* ctx)
{
	LUA_TRACE("read_rawresource");

	if (lua_ctx_store.rawres.fd <= 0)
		return 0;

	return bufread(ctx, &lua_ctx_store.rawres);
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

static inline arcan_aobj_id luaaid_toaid(lua_Number innum)
{
	return (arcan_aobj_id) innum;
}

static inline arcan_vobj_id luavid_tovid(lua_Number innum)
{
	arcan_vobj_id res = ARCAN_VIDEO_WORLDID;

	if (innum != ARCAN_EID && innum != ARCAN_VIDEO_WORLDID)
		res = (arcan_vobj_id) innum - lua_ctx_store.lua_vidbase;
	else if (innum != res)
		res = ARCAN_EID;

	return res;
}

static inline lua_Number vid_toluavid(arcan_vobj_id innum)
{
	if (innum != ARCAN_EID && innum != ARCAN_VIDEO_WORLDID)
		innum += lua_ctx_store.lua_vidbase;

	return (double) innum;
}

static inline arcan_vobj_id luaL_checkvid(
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
		abort();

	if (!vobj)
		arcan_fatal("Bad VID requested (%"PRIxVOBJ")\n", lnum);
#endif

	return res;
}

static inline arcan_vobj_id luaL_checkaid(lua_State* ctx, int num)
{
	return luaL_checknumber(ctx, num);
}

static inline void lua_pushvid(lua_State* ctx, arcan_vobj_id id)
{
	if (id != ARCAN_EID && id != ARCAN_VIDEO_WORLDID)
		id += lua_ctx_store.lua_vidbase;

	lua_pushnumber(ctx, (double) id);
}

static inline void lua_pushaid(lua_State* ctx, arcan_aobj_id id)
{
	lua_pushnumber(ctx, id);
}

static int rawclose(lua_State* ctx)
{
	LUA_TRACE("close_rawresource");

	bool res = false;

	if (lua_ctx_store.rawres.fd > 0) {
		close(lua_ctx_store.rawres.fd);
		lua_ctx_store.rawres.fd = -1;
		lua_ctx_store.rawres.ofs = 0;
	}

	lua_pushboolean(ctx, res);
	return 1;
}

static int pushrawstr(lua_State* ctx)
{
	LUA_TRACE("write_rawresource");

	const char* mesg = luaL_checkstring(ctx, 1);
	size_t ntw = strlen(mesg);

	if (ntw && lua_ctx_store.rawres.fd > 0){
		size_t ofs = 0;

		while (ntw) {
			ssize_t nw = write(lua_ctx_store.rawres.fd, mesg + ofs, ntw);
			if (-1 != nw){
				ofs += nw;
				ntw -= nw;
			}
			else if (errno != EAGAIN && errno != EINTR)
				break;
		}
	}

	lua_pushboolean(ctx, ntw == 0);

	return 1;
}

#ifdef _DEBUG
static int freezeimage(lua_State* ctx)
{
	LUA_TRACE("freeze_image");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	FL_SET(vobj, FL_FROZEN);
	return 0;
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

	if (path)
		id = arcan_video_loadimage(path, arcan_video_dimensions(desw, desh), prio);

	free(path);
	lua_pushvid(ctx, id);
	return 1;
}

static int loadimageasynch(lua_State* ctx)
{
	LUA_TRACE("load_image");

	arcan_vobj_id id = ARCAN_EID;
	intptr_t ref = 0;

	char* path = findresource(luaL_checkstring(ctx, 1), DEFAULT_USERMASK);

	if (lua_isfunction(ctx, 2) && !lua_iscfunction(ctx, 2)){
		lua_pushvalue(ctx, 2);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}

	if (path && strlen(path) > 0){
		id = arcan_video_loadimageasynch(path, arcan_video_dimensions(0, 0), ref);
	}
	free(path);

	lua_pushvid(ctx, id);
	return 1;
}

static int imageloaded(lua_State* ctx)
{
	LUA_TRACE("imageloaded");
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);

	lua_pushnumber(ctx, vobj->feed.state.tag == ARCAN_TAG_IMAGE);
	return 1;
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

	return 0;
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

	return 0;
}

static int instanceimage(lua_State* ctx)
{
	LUA_TRACE("instance_image");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id newid = arcan_video_cloneobject(id);

	if (newid != ARCAN_EID){
		enum arcan_transform_mask lmask = MASK_SCALE | MASK_OPACITY
			| MASK_POSITION | MASK_ORIENTATION;
		arcan_video_transformmask(newid, lmask);

		lua_pushvid(ctx, newid);
		return 1;
	}

	return 0;
}

static int resettransform(lua_State* ctx)
{
	LUA_TRACE("reset_image_transform");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	float num = 0;
	arcan_video_zaptransform(id, &num);
	lua_pushnumber(ctx, num);
	return 1;
}

static int instanttransform(lua_State* ctx)
{
	LUA_TRACE("instant_image_transform");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_video_instanttransform(id);

	return 0;
}

static int cycletransform(lua_State* ctx)
{
	LUA_TRACE("image_transform_cycle");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	bool flag = luaL_checknumber(ctx, 2) != 0;

	arcan_video_transformcycle(sid, flag);

	return 0;
}

static int copytransform(lua_State* ctx)
{
	LUA_TRACE("copy_image_transform");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);

	arcan_video_copytransform(sid, did);

	return 0;
}

static int transfertransform(lua_State* ctx)
{
	LUA_TRACE("transfer_image_transform");

	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);

	arcan_video_transfertransform(sid, did);

	return 0;
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

	return 0;
}

static int resampleimage(lua_State* ctx)
{
	LUA_TRACE("resample_image");
	arcan_vobject* vobj;
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, &vobj);
	arcan_shader_id shid = lua_type(ctx, 2) == LUA_TSTRING ?
	arcan_shader_lookup(luaL_checkstring(ctx, 2)) : luaL_checknumber(ctx, 2);
	size_t width = abs(luaL_checknumber(ctx, 3));
	size_t height = abs(luaL_checknumber(ctx, 4));

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

	return 0;
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

	if (neww < EPSILON && newh < EPSILON)
		return 0;

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

	return 2;
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

	return 2;
}

static int orderimage(lua_State* ctx)
{
	LUA_TRACE("order_image");
	unsigned int zv = abs(luaL_checknumber(ctx, 2));

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

	return 0;
}

static int maxorderimage(lua_State* ctx)
{
	LUA_TRACE("max_current_image_order");
	lua_pushnumber(ctx, arcan_video_maxorder());
	return 1;
}

static inline void massopacity(lua_State* ctx,
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
	return 0;
}

static int showimage(lua_State* ctx)
{
	massopacity(ctx, 1.0, "show_image");
	return 0;
}

static int hideimage(lua_State* ctx)
{
	LUA_TRACE("hide_image");

	massopacity(ctx, 0.0, "hide_image");
	return 0;
}

static int forceblend(lua_State* ctx)
{
	LUA_TRACE("force_image_blend");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	enum arcan_blendfunc mode = abs(luaL_optnumber(ctx, 2, BLEND_FORCE));

	if (mode == BLEND_FORCE || mode == BLEND_ADD ||
		mode == BLEND_MULTIPLY || mode == BLEND_NONE || mode == BLEND_NORMAL)
			arcan_video_forceblend(id, mode);

	return 0;
}

static int imagepersist(lua_State* ctx)
{
	LUA_TRACE("persist_image");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	lua_pushboolean(ctx, arcan_video_persistobject(id) == ARCAN_OK);
	return 1;
}

static int dropaudio(lua_State* ctx)
{
	LUA_TRACE("delete_audio");

	arcan_audio_stop( luaL_checkaid(ctx, 1) );
	return 0;
}

static int gain(lua_State* ctx)
{
	LUA_TRACE("audio_gain");

	arcan_aobj_id id = luaL_checkaid(ctx, 1);
	float gain = luaL_checknumber(ctx, 2);
	uint16_t time = luaL_optint(ctx, 3, 0);
	arcan_audio_setgain(id, gain, time);
	return 0;
}

static int playaudio(lua_State* ctx)
{
	LUA_TRACE("play_audio");

	arcan_aobj_id id = luaL_checkaid(ctx, 1);
	if (lua_isnumber(ctx, 2))
		arcan_audio_play(id, true, luaL_checknumber(ctx, 2));
	else
		arcan_audio_play(id, false, 0.0);

	return 0;
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

		return 1;
	}

	return 0;
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

	return 1;
}

static int loadasample(lua_State* ctx)
{
	LUA_TRACE("load_asample");

	const char* rname = luaL_checkstring(ctx, 1);
	char* resource = findresource(rname, DEFAULT_USERMASK);
	float gain = luaL_optnumber(ctx, 2, 1.0);
	arcan_aobj_id sid = arcan_audio_load_sample(resource, gain, NULL);
	free(resource);
	lua_pushaid(ctx, sid);
	return 1;
}

static int pauseaudio(lua_State* ctx)
{
	LUA_DEPRECATE("pause_audio");

	arcan_aobj_id id = luaL_checkaid(ctx, 1);
	arcan_audio_pause(id);
	return 0;
}

static int buildshader(lua_State* ctx)
{
	LUA_TRACE("build_shader");

	extern char* deffprg;
	extern char* defvprg;

	const char* vprog = luaL_optstring(ctx, 1, defvprg);
	const char* fprog = luaL_optstring(ctx, 2, deffprg);
	const char* label = luaL_checkstring(ctx, 3);

	arcan_shader_id rv = arcan_shader_build(label, NULL, vprog, fprog);
	lua_pushnumber(ctx, rv);
	return 1;
}

static int sharestorage(lua_State* ctx)
{
	LUA_TRACE("image_sharestorage");

	arcan_vobj_id src = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id dst = luaL_checkvid(ctx, 2, NULL);

	arcan_errc rv = arcan_video_shareglstore(src, dst);
	lua_pushboolean(ctx, rv == ARCAN_OK);

	return 1;
}

static int cursorstorage(lua_State* ctx)
{
	LUA_TRACE("cursor_setstorage");
	arcan_vobj_id src = luaL_checkvid(ctx, 1, NULL);
	arcan_video_cursorstore(src);
	return 0;
}

static int cursormove(lua_State* ctx)
{
	LUA_TRACE("move_cursor");
	acoord x = luaL_checknumber(ctx, 1);
	acoord y = luaL_checknumber(ctx, 2);
	bool clamp = luaL_optnumber(ctx, 3, 0) == 0;

	if (clamp){
		x = x > arcan_video_display.canvasw ? arcan_video_display.canvasw : x;
		y = y > arcan_video_display.canvash ? arcan_video_display.canvash : y;
		x = x < 0 ? 0 : x;
		y = y < 0 ? 0 : y;
	}

	arcan_video_cursorpos(x, y, true);
	return 0;
}

static int cursornudge(lua_State* ctx)
{
	LUA_TRACE("nudge_cursor");
	acoord x = luaL_checknumber(ctx, 1) + arcan_video_display.cursor.x;
	acoord y = luaL_checknumber(ctx, 2) + arcan_video_display.cursor.y;
	bool clamp = luaL_optnumber(ctx, 3, 0) == 0;

	if (clamp){
		x = x > arcan_video_display.canvasw ? arcan_video_display.canvasw : x;
		y = y > arcan_video_display.canvash ? arcan_video_display.canvash : y;
		x = x < 0 ? 0 : x;
		y = y < 0 ? 0 : y;
	}

	arcan_video_cursorpos(x, y, true);
	return 0;
}

static int cursorposition(lua_State* ctx)
{
	LUA_TRACE("cursor_position");
	lua_pushnumber(ctx, arcan_video_display.cursor.x);
	lua_pushnumber(ctx, arcan_video_display.cursor.y);
	return 2;
}

static int cursorsize(lua_State* ctx)
{
	LUA_TRACE("resize_cursor");
	acoord w = luaL_checknumber(ctx, 1);
	acoord h = luaL_checknumber(ctx, 2);
	arcan_video_cursorsize(w, h);
	return 0;
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

			default:
				lua_pushstring(ctx, "unknown");
		}

	return 1;
}

static int setshader(lua_State* ctx)
{
	LUA_TRACE("image_shader");

	arcan_vobject* vobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);
	arcan_shader_id oldshid = vobj->program;

	if (lua_gettop(ctx) > 1){
		arcan_shader_id shid = lua_type(ctx, 2) == LUA_TSTRING ?
			arcan_shader_lookup(luaL_checkstring(ctx, 2)) : luaL_checknumber(ctx, 2);

		if (ARCAN_OK != arcan_video_setprogram(id, shid))
			arcan_warning("arcan_video_setprogram(%d, %d) -- couldn't set shader,"
				"invalid vobj or shader id specified.\n", id, shid);
	}

	lua_pushnumber(ctx, oldshid);
	return 1;
}

static int setmeshshader(lua_State* ctx)
{
	LUA_TRACE("mesh_shader");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_shader_id shid = luaL_checknumber(ctx, 2);
	int slot = abs ( luaL_checknumber(ctx, 3) );

	arcan_3d_meshshader(id, shid, slot);

	return 0;
}

static int textdimensions(lua_State* ctx)
{
	LUA_TRACE("text_dimensions");

	unsigned int width = 0, height = 0;
	const char* message = luaL_checkstring(ctx, 1);
	int vspacing = luaL_optint(ctx, 2, 4);
	int tspacing = luaL_optint(ctx, 2, 64);

	arcan_video_stringdimensions(message, vspacing, tspacing, NULL,
		&width, &height);

	lua_pushnumber(ctx, width);
	lua_pushnumber(ctx, height);

	return 2;
}

static int rendertext(lua_State* ctx)
{
	LUA_TRACE("render_text");
	arcan_vobj_id id  = ARCAN_EID;

	const char* message = luaL_checkstring(ctx, 1);
	int vspacing = luaL_optint(ctx, 2, 4);
	int tspacing = luaL_optint(ctx, 3, 64);

	unsigned int nlines = 0;
	unsigned int* lineheights = NULL;

	id = arcan_video_renderstring(message, vspacing, tspacing, NULL,
		&nlines, &lineheights);

	lua_pushvid(ctx, id);

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	for (size_t i = 0; i < nlines; i++) {
		lua_pushnumber(ctx, i + 1);
		lua_pushnumber(ctx, lineheights[i]);
		lua_rawset(ctx, top);
	}

	if (lineheights)
		free(lineheights);

	return 2;
}

static int scaletxcos(lua_State* ctx)
{
	LUA_TRACE("image_scale_txcos");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	float txs = luaL_checknumber(ctx, 2);
	float txt = luaL_checknumber(ctx, 3);

	arcan_video_scaletxcos(id, txs, txt);

	return 0;
}

static int settxcos_default(lua_State* ctx)
{
	LUA_TRACE("image_set_txcos_default");
	arcan_vobject* dst;
	luaL_checkvid(ctx, 1, &dst);
	bool mirror = luaL_optinteger(ctx, 2, 0) != 0;

	if (!dst->txcos)
		dst->txcos = arcan_alloc_mem(sizeof(float)*8,
			ARCAN_MEM_VSTRUCT,0,ARCAN_MEMALIGN_SIMD);

	if (dst){
		if (mirror)
			generate_mirror_mapping(dst->txcos, 1.0, 1.0);
		else
			generate_basic_mapping(dst->txcos, 1.0, 1.0);
	}

	return 0;
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
			arcan_warning("Warning: lua_settxcos(), Too few elements in txco tables"
				"(expected 8, got %i)\n", ncords);
			return 0;
		}

		for (size_t i = 0; i < 8; i++){
			lua_rawgeti(ctx, -1, i+1);
			txcos[i] = lua_tonumber(ctx, -1);
			lua_pop(ctx, 1);
		}

		arcan_video_override_mapping(id, txcos);
	}

	return 0;
}

static int gettxcos(lua_State* ctx)
{
	LUA_TRACE("image_get_txcos");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	int rv = 0;
	float txcos[8] = {0};

	if (arcan_video_retrieve_mapping(id, txcos) == ARCAN_OK){
		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		for (size_t i = 0; i < 8; i++){
			lua_pushnumber(ctx, i + 1);
			lua_pushnumber(ctx, txcos[i]);
			lua_rawset(ctx, top);
		}

		rv = 1;
	}

	return rv;
}

static int togglemask(lua_State* ctx)
{
	LUA_TRACE("image_mask_toggle");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	unsigned val = abs(luaL_checknumber(ctx, 2));

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
	if (id){
		arcan_video_transformmask(id, 0);
	}

	return 0;
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
	unsigned val = abs(luaL_checknumber(ctx, 2));

	if ( (val & !(MASK_ALL)) == 0){
		enum arcan_transform_mask mask = arcan_video_getmask(id);
		mask &= ~val;
		arcan_video_transformmask(id, mask);
	}

	return 0;
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
	} else
		arcan_warning("Script Warning: image_mask_set(),"
			"	bad mask specified (%i)\n", val);

	return 0;
}

static int clipon(lua_State* ctx)
{
	LUA_TRACE("image_clip_on");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	char clipm = luaL_optint(ctx, 2, ARCAN_CLIP_ON);

	arcan_video_setclip(id, clipm == ARCAN_CLIP_ON ? ARCAN_CLIP_ON :
		ARCAN_CLIP_SHALLOW);
    return 0;
}

static int clipoff(lua_State* ctx)
{
	LUA_TRACE("image_clip_off");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_video_setclip(id, ARCAN_CLIP_OFF);
    return 0;
}

static int pick(lua_State* ctx)
{
	LUA_TRACE("pick_items");
	int x = luaL_checkint(ctx, 1);
	int y = luaL_checkint(ctx, 2);
	bool reverse = luaL_optint(ctx, 4, 0) != 0;

	unsigned int limit = luaL_optint(ctx, 3, 8);
	static arcan_vobj_id pickbuf[1024];
	if (limit > 1024)
		arcan_fatal("pick_items(), unreasonable pick "
			"buffer size (%d) requested.", limit);

	unsigned int count = reverse ?
		arcan_video_rpick(pickbuf, limit, x, y) :
		arcan_video_pick(pickbuf, limit, x, y);
	unsigned int ofs = 1;

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	while (count--) {
		lua_pushnumber(ctx, ofs);
		lua_pushvid(ctx, pickbuf[ofs-1]);
		lua_rawset(ctx, top);
		ofs++;
	}

	return 1;
}

static int hittest(lua_State* ctx)
{
	LUA_TRACE("image_hit");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	unsigned int x = luaL_checkint(ctx, 2);
	unsigned int y = luaL_checkint(ctx, 3);

	lua_pushboolean(ctx, arcan_video_hittest(id, x, y) != 0);

	return 1;
}

static int deleteimage(lua_State* ctx)
{
	LUA_TRACE("delete_image");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	double srcid = luaL_checknumber(ctx, 1);

	/* possibly long journey,
	 * for a vid with a movie associated (or any feedfunc),
	 * the feedfunc will be invoked with the cleanup cmd
	 * which in the movie cause will trigger a full movie cleanup */
	arcan_errc rv = arcan_video_deleteobject(id);

	if (rv != ARCAN_OK)
		arcan_fatal("Appl tried to delete non-existing object (%.0lf=>%d)", srcid, id);

	return 0;
}

static int setlife(lua_State* ctx)
{
	LUA_TRACE("expire_image");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	int ttl = luaL_checkint(ctx, 2);

	if (ttl <= 0)
		ttl = 1;

	arcan_video_setlife(id, ttl);

	return 0;
}

/* to actually put this into effect, change value and pop the entire stack */
static int systemcontextsize(lua_State* ctx)
{
	LUA_TRACE("system_context_size");

	unsigned newlim = luaL_checkint(ctx, 1);
	if (newlim > 1 && newlim <= VITEM_CONTEXT_LIMIT){
		arcan_video_contextsize(newlim);
	}
	else
		arcan_fatal("system_context_size(), "
			"invalid context size specified (%d)\n", newlim);

	return 0;
}

char* arcan_luaL_main(lua_State* ctx, const char* inp, bool file)
{
/* since we prefix scriptname to functions that we look-up,
 * we need a buffer to expand into with as few read/writes/allocs
 * as possible, arcan_luaL_dofile is only ever invoked when
 * an appl is about to be loaded so here is a decent entrypoint */
	const int suffix_lim = 34;

	luaL_nil_banned(ctx);

	free(lua_ctx_store.prefix_buf);
	lua_ctx_store.prefix_ofs = arcan_appl_id_len();
	lua_ctx_store.prefix_buf = arcan_alloc_mem( arcan_appl_id_len() + suffix_lim,
		ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_SIMD
	);
	memcpy(lua_ctx_store.prefix_buf, arcan_appl_id(), lua_ctx_store.prefix_ofs);

	int code = (file ? luaL_dofile(ctx, inp) : luaL_dostring(ctx, inp));
	if (code == 1){
		const char* msg = lua_tostring(ctx, -1);
		if (msg)
			return strdup(msg);
	}

	return NULL;
}

void arcan_luaL_adopt(arcan_vobj_id id, void* tag)
{
	lua_State* ctx = tag;
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_frameserver* fsrv = NULL;

/* should only be this type at the moment but need to protect ourselves */
	if (vobj->feed.state.tag == ARCAN_TAG_FRAMESERV){
		fsrv = vobj->feed.state.ptr;
		fsrv->tag = (uintptr_t) 0;
	}

	if (!grabapplfunction(ctx, "adopt", sizeof("adopt") - 1))
		return;

	int argc = 1;
	lua_pushvid(ctx, id);
	if (fsrv){
		argc += 2;
		lua_pushstring(ctx, fsrvtos(fsrv->segid));
		if (strlen(fsrv->title) > 0)
			lua_pushstring(ctx, fsrv->title);
		else
			lua_pushstring(ctx, "_untitled");
	}

	wraperr(ctx, lua_pcall(ctx, argc, 0, 0), "adopt");
}

static int syscollapse(lua_State* ctx)
{
	LUA_TRACE("system_collapse");
	const char* switch_appl = luaL_optstring(ctx, 1, NULL);

	if (switch_appl){
		if (strlen(switch_appl) == 0){
			arcan_fatal("system_collapse(), 0-length appl name not permitted.\n");
		}

		for (const char* work = switch_appl; *work; work++)
			if (!isalnum(*work) && *work != '_')
				arcan_fatal("system_collapse(), only aZ_ are permitted in names.\n");

/* lua will free when we destroy the context */
		switch_appl = strdup(switch_appl);
		const char* errmsg;
		arcan_luaL_shutdown(ctx);

/* flush eventqueue to avoid danglers */
		arcan_event_deinit(arcan_event_defaultctx());
		arcan_event_init(arcan_event_defaultctx());

/* we no longer have a context, the Lua specific error reporter should
 * not be used */
#undef arcan_fatal
		if (!arcan_verifyload_appl(switch_appl, &errmsg)){
			if (lua_ctx_store.debug > 0)
				arcan_verify_namespaces(true);

			arcan_fatal("system_collapse(), "
				"failed to load appl (%s), reason: %s\n", switch_appl, errmsg);
		}
#define arcan_fatal(...) { lua_rectrigger( __VA_ARGS__); }

		longjmp(arcanmain_recover_state, 1);
	}
	else{
		int saved, truncated;
		arcan_video_recoverexternal(true, &saved, &truncated,
			arcan_luaL_adopt, ctx);
	}

	return 0;
}

static int syssnap(lua_State* ctx)
{
	LUA_TRACE("system_snapshot");

	const char* instr = luaL_checkstring(ctx, 1);
	char* fname = findresource(instr, RESOURCE_APPL_TEMP);

	if (fname){
		arcan_warning("system_statesnap(), "
		"refuses to overwrite existing file (%s));\n", fname);
		free(fname);

		return 0;
	}

	fname = arcan_expand_resource(luaL_checkstring(ctx, 1), RESOURCE_APPL_TEMP);
	FILE* outf = fopen(fname, "w+");

	if (outf){
		arcan_lua_statesnap(outf, "", false);
		fclose(outf);
	}
	else
		arcan_warning("system_statesnap(), "
			"couldn't open (%s) for writing.\n", fname);

	arcan_mem_free(fname);
	return 0;
}

static int dofile(lua_State* ctx)
{
	LUA_TRACE("system_load");

	const char* instr = luaL_checkstring(ctx, 1);
	bool dieonfail = luaL_optnumber(ctx, 2, 1) != 0;

	char* fname = findresource(instr, DEFAULT_USERMASK);
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

	free(fname);
	return res;
}

static int targetsuspend(lua_State* ctx)
{
	LUA_TRACE("suspend_target");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	vfunc_state* state = arcan_video_feedstate(vid);

	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		arcan_warning("suspend_target(), "
			"referenced object is not connected to a frameserver.\n");
		return 0;
	}
	arcan_frameserver* fsrv = state->ptr;

	arcan_event ev = {
		.kind = TARGET_COMMAND_PAUSE,
		.category = EVENT_TARGET
	};

	arcan_frameserver_pause(fsrv);
	arcan_frameserver_pushevent(fsrv, &ev);

	return 0;
}

static int targetresume(lua_State* ctx)
{
	LUA_TRACE("resume_target");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	vfunc_state* state = arcan_video_feedstate(vid);
	arcan_frameserver* fsrv = state->ptr;

	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !fsrv){
		arcan_fatal("suspend_target(), "
			"referenced object not connected to a frameserver.\n");
	}

	arcan_event ev = {
		.kind = TARGET_COMMAND_UNPAUSE,
		.category = EVENT_TARGET
	};

	arcan_frameserver_resume(fsrv);
	arcan_frameserver_pushevent(fsrv, &ev);

	return 0;
}

static int playmovie(lua_State* ctx)
{
	LUA_DEPRECATE("play_movie");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	vfunc_state* state = arcan_video_feedstate(vid);
	arcan_frameserver* fsrv = state->ptr;

	lua_pushvid(ctx, fsrv->vid);
	lua_pushaid(ctx, fsrv->aid);

	return 2;
}

static bool is_special_res(const char* msg)
{
	return strncmp(msg, "device", 6) == 0 ||
		strncmp(msg, "stream", 6) == 0 ||
		strncmp(msg, "capture", 7) == 0;
}

static int setupavstream(lua_State* ctx)
{
	LUA_TRACE("launch_avfeed");
	const char* argstr = luaL_optstring(ctx, 1, "");
	uintptr_t ref = 0;

	const char* modearg = "avfeed";

	if (argstr != NULL){
		modearg = luaL_optstring(ctx, 2, modearg);
	}

	if (strstr(FRAMESERVER_MODESTRING, modearg) == NULL){
		arcan_warning("launch_avfeed(), requested mode (%s) missing from "
			"build-time frameserver configuration (%s), rejected.\n",
			modearg, FRAMESERVER_MODESTRING);
		return 0;
	}

	ref = find_lua_callback(ctx);
	arcan_frameserver* mvctx = arcan_frameserver_alloc();

	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = modearg,
		.args.builtin.resource = argstr
	};

	if ( arcan_frameserver_spawn_server(mvctx, args) == ARCAN_OK )
	{
		mvctx->tag = ref;

		arcan_video_objectopacity(mvctx->vid, 0.0, 0);
		lua_pushvid(ctx, mvctx->vid);
		lua_pushaid(ctx, mvctx->aid);
	}
	else {
		free(mvctx);
		lua_pushvid(ctx, ARCAN_EID);
		lua_pushvid(ctx, ARCAN_EID);
	}

	return 2;
}

static int loadmovie(lua_State* ctx)
{
	LUA_TRACE("load_movie");

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

/* in order to stay backward compatible API wise,
 * the load_movie with function callback
 * will always need to specify loop condition. */
	if (lua_isfunction(ctx, cbind) && !lua_iscfunction(ctx, cbind)){
		lua_pushvalue(ctx, cbind);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	};

	size_t optlen = strlen(argstr);

	if (!fname){
		arcan_warning("loadmovie() -- unknown resource (%s)"
		"	specified.\n", fname);
		return 0;
	}
	else{
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
	}

	arcan_frameserver* mvctx = arcan_frameserver_alloc();

	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = "decode",
		.args.builtin.resource = fname
	};

	arcan_vobj_id vid = ARCAN_EID;
	arcan_aobj_id aid = ARCAN_EID;

	if ( arcan_frameserver_spawn_server(mvctx, args) == ARCAN_OK )
	{
		mvctx->tag = ref;
		arcan_video_objectopacity(mvctx->vid, 0.0, 0);
		vid = mvctx->vid;
		aid = mvctx->aid;
	}
 	else
		free(mvctx);

	lua_pushvid(ctx, vid);
	lua_pushaid(ctx, aid);

	free(fname);

	return 2;
}

#ifdef ARCAN_LED
static int n_leds(lua_State* ctx)
{
	LUA_TRACE("controller_leds");

	uint8_t id = luaL_checkint(ctx, 1);
	led_capabilities cap = arcan_led_capabilities(id);

	lua_pushnumber(ctx, cap.nleds);
	return 1;
}

static int led_intensity(lua_State* ctx)
{
	LUA_TRACE("led_intensity");

	uint8_t id = luaL_checkint(ctx, 1);
	int8_t led = luaL_checkint(ctx, 2);
	uint8_t intensity = luaL_checkint(ctx, 3);

	lua_pushnumber(ctx,
		arcan_led_intensity(id, led, intensity));

	return 1;
}

static int led_rgb(lua_State* ctx)
{
	LUA_TRACE("set_led_rgb");

	uint8_t id = luaL_checkint(ctx, 1);
	int8_t led = luaL_checkint(ctx, 2);
	uint8_t r  = luaL_checkint(ctx, 3);
	uint8_t g  = luaL_checkint(ctx, 4);
	uint8_t b  = luaL_checkint(ctx, 5);

	lua_pushnumber(ctx, arcan_led_rgb(id, led, r, g, b));
	return 1;
}

static int setled(lua_State* ctx)
{
	LUA_TRACE("set_led");

	int id = luaL_checkint(ctx, 1);
	int num = luaL_checkint(ctx, 2);
	int state = luaL_checkint(ctx, 3);

	lua_pushnumber(ctx, state ? arcan_led_set(id, num):arcan_led_clear(id, num));

	return 1;
}
#endif

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

	return 1;
}

static int popcontext_ext(lua_State* ctx)
{
	LUA_TRACE("storepop_video_context");
	arcan_vobj_id newid = ARCAN_EID;

	lua_pushinteger(ctx, arcan_video_nfreecontexts() > 1 ?
		arcan_video_extpopcontext(&newid) : -1);
	lua_pushvid(ctx, newid);

	return 2;
}

static int pushcontext_ext(lua_State* ctx)
{
	LUA_TRACE("storepush_video_context");
	arcan_vobj_id newid = ARCAN_EID;

	lua_pushinteger(ctx, arcan_video_nfreecontexts() > 1 ?
		arcan_video_extpushcontext(&newid) : -1);
	lua_pushvid(ctx, newid);

	return 2;
}

static int popcontext(lua_State* ctx)
{
	LUA_TRACE("pop_video_context");
	lua_pushinteger(ctx, arcan_video_popcontext());
	return 1;
}

static int contextusage(lua_State* ctx)
{
	LUA_TRACE("current_context_usage");

	unsigned usecount;
	lua_pushinteger(ctx, arcan_video_contextusage(&usecount));
	lua_pushinteger(ctx, usecount);
	return 2;
}

static inline const char* intblstr(lua_State* ctx, int ind, const char* field){
	lua_getfield(ctx, ind, field);
	return lua_tostring(ctx, -1);
}

static inline int intblnum(lua_State* ctx, int ind, const char* field){
	lua_getfield(ctx, ind, field);
	return lua_tointeger(ctx, -1);
}

static inline bool intblbool(lua_State* ctx, int ind, const char* field){
	lua_getfield(ctx, ind, field);
	return lua_toboolean(ctx, -1);
}

/*
 * Next step in the input mess, take a properly formatted table,
 * convert it back into an arcan event, push that to the target_launcher
 * or frameserver. The target_launcher will serialise it to a hijack function
 * which then decodes into a native format (currently most likely SDL).
 * All this hassle (instead of creating a custom Lua object,
 * tag it with the raw event and be done with it) is to allow the appl- to
 * modify or even generate new ones based on in-appl actions.
 */

/* there is a slight API inconsistency here in that we had (iotbl, vid)
 * in the first few versions while other functions tend to lead with vid,
 * which causes some confusion. So we check whethere the table argument is first
 * or second, and extract accordingly, so both will work */
static int targetinput(lua_State* ctx)
{
	LUA_TRACE("target_input/input_target");

	arcan_event ev = {.kind = 0, .category = EVENT_IO };
	int vidind, tblind;

/* swizzle if necessary */
	if (lua_type(ctx, 1) == LUA_TTABLE){
		vidind = 2;
		tblind = 1;
	} else {
		tblind = 2;
		vidind = 1;
	}

	arcan_vobj_id vid = luaL_checkvid(ctx, vidind, NULL);
	luaL_checktype(ctx, tblind, LUA_TTABLE);

	vfunc_state* vstate = arcan_video_feedstate(vid);

	if (!vstate || vstate->tag != ARCAN_TAG_FRAMESERV){
		lua_pushnumber(ctx, false);
		return 1;
	}

/* populate all arguments */
	const char* kindlbl = intblstr(ctx, tblind, "kind");
	if (kindlbl == NULL)
		goto kinderr;

	const char* label = intblstr(ctx, tblind, "label");
	if (label){
		int ul = sizeof(ev.label) / sizeof(ev.label[0]) - 1;
		char* dst = ev.label;

		while (*label != '\0' && ul--)
			*dst++ = *label++;
		*dst = '\0';
	}

	ev.data.io.pts = intblnum(ctx, tblind, "pts");

	if ( strcmp( kindlbl, "analog") == 0 ){
		const char* srcstr = intblstr(ctx, tblind, "source");

		ev.kind = EVENT_IO_AXIS_MOVE;
		ev.data.io.datatype = EVENT_IDATATYPE_ANALOG;
		ev.data.io.devkind = srcstr && strcmp( srcstr, "mouse") == 0 ?
			EVENT_IDEVKIND_MOUSE : EVENT_IDEVKIND_GAMEDEV;
		ev.data.io.input.analog.devid  = intblnum(ctx, tblind, "devid");
		ev.data.io.input.analog.subid  = intblnum(ctx, tblind, "subid");
		ev.data.io.input.analog.gotrel = ev.data.io.devkind == EVENT_IDEVKIND_MOUSE;

	/*  sweep the samples subtable, add as many as present (or possible) */
		lua_getfield(ctx, tblind, "samples");
		size_t naxiss = lua_rawlen(ctx, -1);
		for (size_t i = 0; i < naxiss &&
			i < sizeof(ev.data.io.input.analog.axisval) /
				sizeof(ev.data.io.input.analog.axisval[0]); i++){
			lua_rawgeti(ctx, -1, i+1);
			ev.data.io.input.analog.axisval[i] = lua_tointeger(ctx, -1);
			lua_pop(ctx, 1);
		}
		ev.data.io.input.analog.nvalues = naxiss;
	}
	else if (strcmp(kindlbl, "digital") == 0){
		if (intblbool(ctx, tblind, "translated")){
			ev.data.io.datatype = EVENT_IDATATYPE_TRANSLATED;
			ev.data.io.devkind  = EVENT_IDEVKIND_KEYBOARD;
			ev.data.io.input.translated.active    = intblbool(ctx, tblind, "active");
			ev.data.io.input.translated.scancode  = intblnum(ctx, tblind, "number");
			ev.data.io.input.translated.keysym    = intblnum(ctx, tblind, "keysym");
			ev.data.io.input.translated.modifiers = intblnum(ctx, tblind, "modifiers");
			ev.data.io.input.translated.devid     = intblnum(ctx, tblind, "devid");
			ev.data.io.input.translated.subid     = intblnum(ctx, tblind, "subid");
		}
		else {
			const char* tblsrc = intblstr(ctx, tblind, "source");
			ev.data.io.devkind = tblsrc && strcmp(tblsrc, "mouse") == 0 ?
				EVENT_IDEVKIND_MOUSE : EVENT_IDEVKIND_GAMEDEV;
			ev.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
			ev.data.io.input.digital.active= intblbool(ctx, tblind, "active");
			ev.data.io.input.digital.devid = intblnum(ctx, tblind, "devid");
			ev.data.io.input.digital.subid = intblnum(ctx, tblind, "subid");
		}
	}
	else {
kinderr:
		arcan_warning("Script Warning: target_input(), unkown \"kind\""
			"	field in table.\n");
		lua_pushnumber(ctx, false);
		return 1;
	}

	arcan_frameserver_pushevent( (arcan_frameserver*) vstate->ptr, &ev );
	lua_pushnumber(ctx, true);
	return 1;
}

static inline int funtable(lua_State* ctx, uint32_t kind){
	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	lua_pushstring(ctx, "kind");
	lua_pushnumber(ctx, kind);
	lua_rawset(ctx, top);

	return top;
}

static inline void tblstr(lua_State* ctx, const char* k,
	const char* v, int top){
	lua_pushstring(ctx, k);
	lua_pushstring(ctx, v);
	lua_rawset(ctx, top);
}

static inline void tblnum(lua_State* ctx, char* k, double v, int top){
	lua_pushstring(ctx, k);
	lua_pushnumber(ctx, v);
	lua_rawset(ctx, top);
}

static inline void tblbool(lua_State* ctx, char* k, bool v, int top){
	lua_pushstring(ctx, k);
	lua_pushboolean(ctx, v);
	lua_rawset(ctx, top);
}

static char* to_utf8(uint16_t utf16)
{
	static char utf8buf[6] = {0};
	int count = 1, ofs = 0;
	uint32_t mask = 0x800;

	if (utf16 >= 0x80)
		count++;

	for (size_t i=0; i < 5; i++){
		if ( (uint32_t) utf16 >= mask )
			count++;

		mask <<= 5;
	}

	if (count == 1){
		utf8buf[0] = (char) utf16;
		utf8buf[1] = 0x00;
	} else {
		for (int i = count-1; i >= 0; i--){
			unsigned char ch = ( utf16 >> (6 * i)) & 0x3f;
			ch |= 0x80;
			if (i == count-1)
				ch |= 0xff << (8-count);
			utf8buf[ofs++] = ch;
		}
		utf8buf[ofs++] = 0x00;
	}

	return (char*) utf8buf;
}

static int scale3dverts(lua_State* ctx)
{
	LUA_TRACE("scale_3dvertices");

  arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
  arcan_3d_scalevertices(vid);
  return 0;
}

static void slimpush(char* dst, char ulim, char* inmsg)
{
	ulim--;

	while (*inmsg && ulim--)
		*dst++ = *inmsg++;

	*dst = '\0';
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

/*
 * emit input() call based on a arcan_event, uses a separate format
 * and translation to make it easier for the user to modify. This
 * is a rather ugly and costly step in the whole chain,
 * planned to switch into a more optimized less string- damaged
 * approach around the hardening stage in the shmif- refactor.
 */
void arcan_lua_pushevent(lua_State* ctx, arcan_event* ev)
{
	if (ev->category == EVENT_IO && grabapplfunction(ctx, "input", 5)){
		int top = funtable(ctx, ev->kind);

		lua_pushstring(ctx, "kind");

		switch (ev->kind) {
		case EVENT_IO_TOUCH:
			lua_pushstring(ctx, "touch");
			lua_rawset(ctx, top);

			tblnum(ctx, "devid",    ev->data.io.input.touch.devid,    top);
			tblnum(ctx, "subid",    ev->data.io.input.touch.subid,    top);
			tblnum(ctx, "pressure", ev->data.io.input.touch.pressure, top);
			tblnum(ctx, "size",     ev->data.io.input.touch.size,     top);
			tblnum(ctx, "x",        ev->data.io.input.touch.x,        top);
			tblnum(ctx, "y",        ev->data.io.input.touch.y,        top);
		break;

		case EVENT_IO_AXIS_MOVE:
			lua_pushstring(ctx, "analog");
			lua_rawset(ctx, top);

			tblstr(ctx, "source", ev->data.io.devkind ==
				EVENT_IDEVKIND_MOUSE ? "mouse" : "joystick", top);
			tblnum(ctx, "devid", ev->data.io.input.analog.devid, top);
			tblnum(ctx, "subid", ev->data.io.input.analog.subid, top);
			tblbool(ctx, "active", true, top);
			tblbool(ctx, "relative", ev->data.io.input.analog.gotrel,top);

			lua_pushstring(ctx, "samples");
			lua_newtable(ctx);
				int top2 = lua_gettop(ctx);
				for (size_t i = 0; i < ev->data.io.input.analog.nvalues; i++) {
					lua_pushnumber(ctx, i + 1);
					lua_pushnumber(ctx, ev->data.io.input.analog.axisval[i]);
					lua_rawset(ctx, top2);
				}
			lua_rawset(ctx, top);
		break;

		case EVENT_IO_BUTTON:
			lua_pushstring(ctx, "digital");
			lua_rawset(ctx, top);

			if (ev->data.io.devkind == EVENT_IDEVKIND_KEYBOARD) {
				tblbool(ctx, "translated", true, top);
				tblnum(ctx, "number", ev->data.io.input.translated.scancode, top);
				tblnum(ctx, "keysym", ev->data.io.input.translated.keysym, top);
				tblnum(ctx, "modifiers", ev->data.io.input.translated.modifiers, top);
				tblnum(ctx, "devid", ev->data.io.input.translated.devid, top);
				tblnum(ctx, "subid", ev->data.io.input.translated.subid, top);
				tblstr(ctx, "utf8", to_utf8(ev->data.io.input.translated.subid), top);
				tblbool(ctx, "active", ev->data.io.input.translated.active, top);
				tblstr(ctx, "device", "translated", top);
				tblstr(ctx, "subdevice", "keyboard", top);
			}
			else if (ev->data.io.devkind == EVENT_IDEVKIND_MOUSE ||
				ev->data.io.devkind == EVENT_IDEVKIND_GAMEDEV) {
				tblstr(ctx, "source", ev->data.io.devkind == EVENT_IDEVKIND_MOUSE ?
					"mouse" : "joystick", top);
				tblbool(ctx, "translated", false, top);
				tblnum(ctx, "devid", ev->data.io.input.digital.devid, top);
				tblnum(ctx, "subid", ev->data.io.input.digital.subid, top);
 				tblbool(ctx, "active", ev->data.io.input.digital.active, top);
			}
			else;
		break;

		default:
			lua_pushstring(ctx, "unknown");
			lua_rawset(ctx, top);
			arcan_warning("Engine -> Script: ignoring IO event: %i\n",ev->kind);
		}

		wraperr(ctx, lua_pcall(ctx, 1, 0, 0), "push event( input )");
	}
	else if (ev->category == EVENT_TIMER){
		arcan_lua_setglobalint(ctx, "CLOCK", ev->tickstamp);

		if (grabapplfunction(ctx, "clock_pulse", 11)) {
			lua_pushnumber(ctx, ev->tickstamp);
			lua_pushnumber(ctx, ev->data.timer.pulse_count);
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0),"event loop: clock pulse");
		}
	}
	else if (ev->category == EVENT_NET){
		if (arcan_video_findparent(ev->data.external.source) == ARCAN_EID)
			return;

		arcan_vobject* vobj = arcan_video_getobject(ev->data.network.source);
		arcan_frameserver* fsrv = vobj ? vobj->feed.state.ptr : NULL;

		if (fsrv && fsrv->tag){
			intptr_t dst_cb = fsrv->tag;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
			lua_pushvid(ctx, ev->data.network.source);

			lua_newtable(ctx);
			int top = lua_gettop(ctx);

			switch (ev->kind){
				case EVENT_NET_CONNECTED:
					tblstr(ctx, "kind", "connected", top);
					tblnum(ctx, "id", ev->data.network.connid, top);
					tblstr(ctx, "host", ev->data.network.host.addr, top);
				break;

				case EVENT_NET_DISCONNECTED:
					tblstr(ctx, "kind", "disconnected", top);
					tblnum(ctx, "id", ev->data.network.connid, top);
					tblstr(ctx, "host", ev->data.network.host.addr, top);
				break;

				case EVENT_NET_NORESPONSE:
					tblstr(ctx, "kind", "noresponse", top);
					tblstr(ctx, "host", ev->data.network.host.addr, top);
				break;

				case EVENT_NET_CUSTOMMSG:
					tblstr(ctx, "kind", "message", top);
					ev->data.network.message[ sizeof(ev->data.network.message) - 1] = 0;
					tblstr(ctx, "message", ev->data.network.message, top);
					tblnum(ctx, "id", ev->data.network.connid, top);
				break;

				case EVENT_NET_DISCOVERED:
				tblstr(ctx, "kind", "discovered", top);
				tblstr(ctx, "address", ev->data.network.host.addr, top);
				tblstr(ctx, "ident", ev->data.network.host.ident, top);
				size_t outl;
				uint8_t* strkey = arcan_base64_encode(
					(const uint8_t*) ev->data.network.host.key,
					sizeof(ev->data.network.host.key) / sizeof(ev->data.network.host.key[0]),
					&outl, ARCAN_MEM_SENSITIVE | ARCAN_MEM_NONFATAL);
				if (strkey){
					tblstr(ctx, "key", (const char*) strkey, top);
					free(strkey);
				}
				break;

				case EVENT_NET_INPUTEVENT:
					arcan_warning("pushevent(net_inputevent_not_handled )\n");
				break;

				default:
					arcan_warning("pushevent( net_unknown %d )\n", ev->kind);
			}

			lua_ctx_store.cb_source_tag  = ev->data.external.source;
			lua_ctx_store.cb_source_kind = CB_SOURCE_FRAMESERVER;
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "event_net");

			lua_ctx_store.cb_source_kind = CB_SOURCE_NONE;
		}

	}
	else if (ev->category == EVENT_EXTERNAL){
		char mcbuf[65];
		if (arcan_video_findparent(ev->data.external.source) == ARCAN_EID)
			return;

		int reset = lua_gettop(ctx);

/* need to jump through a few hoops to get hold of the possible callback */
		arcan_vobject* vobj = arcan_video_getobject(ev->data.external.source);

/* edge case, dangling event with frameserver
 * that died during initialization but wasn't pruned from the eventqueue */
		if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			return;

		arcan_frameserver* fsrv = vobj->feed.state.ptr;
		if (fsrv->tag){
			intptr_t dst_cb = fsrv->tag;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
			lua_pushvid(ctx, ev->data.external.source);

			lua_newtable(ctx);
			int top = lua_gettop(ctx);
			switch (ev->kind){
			case EVENT_EXTERNAL_IDENT:
				tblstr(ctx, "kind", "ident", top);
				slimpush(mcbuf, sizeof(ev->data.external.message) /
					sizeof(ev->data.external.message[0]),
					(char*)ev->data.external.message);
				tblstr(ctx, "message", mcbuf, top);
			break;
			case EVENT_EXTERNAL_COREOPT:
				tblstr(ctx, "kind", "coreopt", top);
				slimpush(mcbuf, sizeof(ev->data.external.message) /
					sizeof(ev->data.external.message[0]),
					(char*)ev->data.external.message);
				tblstr(ctx, "argument", mcbuf, top);
			break;
			case EVENT_EXTERNAL_MESSAGE:
				slimpush(mcbuf, sizeof(ev->data.external.message) /
					sizeof(ev->data.external.message[0]),
					(char*)ev->data.external.message);
				tblstr(ctx, "kind", "message", top);
				tblstr(ctx, "message", mcbuf, top);
			break;
			case EVENT_EXTERNAL_FAILURE:
				tblstr(ctx, "kind", "failure", top);
				slimpush(mcbuf, sizeof(ev->data.external.message) /
					sizeof(ev->data.external.message[0]),
					(char*)ev->data.external.message);
				tblstr(ctx, "message", mcbuf, top);
			break;
			case EVENT_EXTERNAL_FRAMESTATUS:
				tblstr(ctx, "kind", "framestatus", top);
				tblnum(ctx, "frame", ev->data.external.framestatus.framenumber, top);
				tblnum(ctx, "pts", ev->data.external.framestatus.pts, top);
				tblnum(ctx, "acquired", ev->data.external.framestatus.acquired, top);
				tblnum(ctx, "fhint", ev->data.external.framestatus.fhint, top);
			break;

			case EVENT_EXTERNAL_STREAMINFO:
				slimpush(mcbuf, sizeof(ev->data.external.streaminf.message) /
					sizeof(ev->data.external.streamstat.timestr[0]),
					(char*)ev->data.external.streamstat.timestr);
				tblstr(ctx, "kind", "streaminfo", top);
				tblstr(ctx, "lang", mcbuf, top);
				tblnum(ctx, "streamid", ev->data.external.streaminf.streamid, top);
				tblstr(ctx, "type",
					streamtype(ev->data.external.streaminf.datakind),top);
			break;

			case EVENT_EXTERNAL_STREAMSTATUS:
				tblstr(ctx, "kind", "streamstatus", top);
					slimpush(mcbuf, sizeof(ev->data.external.streamstat.timestr) /
					sizeof(ev->data.external.streamstat.timestr[0]),
					(char*)ev->data.external.streamstat.timestr);
				tblstr(ctx, "ctime", mcbuf, top);
				slimpush(mcbuf, sizeof(ev->data.external.streamstat.timelim) /
					sizeof(ev->data.external.streamstat.timelim[0]),
					(char*)ev->data.external.streamstat.timelim);
				tblstr(ctx, "endtime", mcbuf, top);
				tblnum(ctx,"completion",ev->data.external.streamstat.completion,top);
				tblnum(ctx, "frameno", ev->data.external.streamstat.frameno, top);
				tblnum(ctx,"streaming",
					ev->data.external.streamstat.streaming!=0,top);
			break;

			case EVENT_EXTERNAL_CURSORINPUT:
				tblstr(ctx, "kind", "cursor_input", top);
				tblnum(ctx, "id", ev->data.external.cursor.id, top);
				tblnum(ctx, "x", ev->data.external.cursor.x, top);
				tblnum(ctx, "y", ev->data.external.cursor.y, top);
				tblbool(ctx, "button_1", ev->data.external.cursor.buttons[0], top);
				tblbool(ctx, "button_2", ev->data.external.cursor.buttons[1], top);
				tblbool(ctx, "button_3", ev->data.external.cursor.buttons[2], top);
				tblbool(ctx, "button_4", ev->data.external.cursor.buttons[3], top);
				tblbool(ctx, "button_5", ev->data.external.cursor.buttons[4], top);
			break;

			case EVENT_EXTERNAL_KEYINPUT:
				tblstr(ctx, "kind", "key_input", top);
				tblnum(ctx, "id", ev->data.external.cursor.id, top);
				tblnum(ctx, "keysym", ev->data.external.key.keysym, top);
				tblbool(ctx, "active", ev->data.external.key.active, top);
			break;

			case EVENT_EXTERNAL_SEGREQ:
				tblstr(ctx, "kind", "segment_request", top);
				tblnum(ctx, "width", ev->data.external.noticereq.width, top);
				tblnum(ctx, "height", ev->data.external.noticereq.height, top);
				tblnum(ctx, "reqid", ev->data.external.noticereq.id, top);
				tblnum(ctx, "type", ev->data.external.noticereq.type, top);
			break;

			case EVENT_EXTERNAL_STATESIZE:
				tblstr(ctx, "kind", "state_size", top);
				tblnum(ctx, "state_size", ev->data.external.state_sz, top);
			break;
			case EVENT_EXTERNAL_RESOURCE:
				tblstr(ctx, "kind", "resource_status", top);
				tblstr(ctx, "message", (char*)ev->data.external.message, top);
			break;
			case EVENT_EXTERNAL_REGISTER:
				if (fsrv->segid != SEGID_UNKNOWN &&
					ev->data.external.registr.kind != fsrv->segid){
					arcan_warning("client attempted to change registry ID/type (%d:%d)"
						"this behavior is not permitted and was ignored.\n", fsrv->segid,
						ev->data.external.registr.kind);
					lua_settop(ctx, reset);
					return;
				}
				else {
					tblstr(ctx, "kind", "registered", top);
					tblstr(ctx, "segkind", fsrvtos(ev->data.external.registr.kind), top);
					slimpush(mcbuf, sizeof(ev->data.external.registr.title) /
						sizeof(ev->data.external.registr.title[0]),
						(char*)ev->data.external.registr.title);
					snprintf(fsrv->title,
						sizeof(fsrv->title) / sizeof(fsrv->title[0]), "%s", mcbuf);
					tblstr(ctx, "title", mcbuf, top);
				}

			break;
			 default:
				tblstr(ctx, "kind", "unknown", top);
				tblnum(ctx, "kind_num", ev->kind, top);
			}

			lua_ctx_store.cb_source_tag  = ev->data.external.source;
			lua_ctx_store.cb_source_kind = CB_SOURCE_FRAMESERVER;
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "event_external");

			lua_ctx_store.cb_source_kind = CB_SOURCE_NONE;
		}
	}
	else if (ev->category == EVENT_FRAMESERVER){
		intptr_t dst_cb = 0;

/*
 * drop frameserver events for which the queue object has died,
 * VID reuse won't actually be a problem unless the user ehrm, allocates/deletes
 * full 32-bit (-context_size) in one go
 */
		if (arcan_video_findparent(ev->data.frameserver.video) == ARCAN_EID)
			return;

/*
 * placeholder slot for adding the callback function reference
 */
		lua_pushnumber(ctx, 0);

		lua_pushvid(ctx, ev->data.frameserver.video);
		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		tblnum(ctx, "source_audio", ev->data.frameserver.audio, top);

		dst_cb = ev->data.frameserver.otag;
		if (0 == dst_cb){
			lua_settop(ctx, 0);
			return;
		}

		switch(ev->kind){
			case EVENT_FRAMESERVER_TERMINATED :
				tblstr(ctx, "kind", "terminated", top);
			break;

			case EVENT_FRAMESERVER_DELIVEREDFRAME :
				tblstr(ctx, "kind", "frame", top);
				tblnum(ctx, "pts", ev->data.frameserver.pts, top);
				tblnum(ctx, "number", ev->data.frameserver.counter, top);
			break;

			case EVENT_FRAMESERVER_DROPPEDFRAME :
				tblstr(ctx, "kind", "dropped_frame", top);
				tblnum(ctx, "pts", ev->data.frameserver.pts, top);
				tblnum(ctx, "number", ev->data.frameserver.counter, top);
			break;

			case EVENT_FRAMESERVER_RESIZED :
				tblstr(ctx, "kind", "resized", top);
				tblnum(ctx, "width", ev->data.frameserver.width, top);
				tblnum(ctx, "height", ev->data.frameserver.height, top);
				tblnum(ctx, "mirrored", ev->data.frameserver.glsource, top);
			break;
		}

		lua_ctx_store.cb_source_tag = ev->data.frameserver.video;
		lua_ctx_store.cb_source_kind = CB_SOURCE_FRAMESERVER;
		lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
		lua_replace(ctx, 1);
		wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "frameserver_event");
		lua_ctx_store.cb_source_kind = CB_SOURCE_NONE;
	}
	else if (ev->category == EVENT_VIDEO){
		intptr_t dst_cb = 0;
		arcan_vobject* srcobj;
		const char* evmsg = "video_event";
		bool gotfun = false;

/* add placeholder, if we find an asynch recipient */
		lua_pushnumber(ctx, 0);

		lua_pushvid(ctx, ev->data.video.source);
		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		switch (ev->kind) {
		case EVENT_VIDEO_EXPIRE : break;
		case EVENT_VIDEO_ASYNCHIMAGE_LOADED:
			evmsg = "video_event(asynchimg_loaded)";
			tblstr(ctx, "kind", "loaded", top);
			tblnum(ctx, "width", ev->data.video.width, top);
			tblnum(ctx, "height", ev->data.video.height, top);
			dst_cb = (intptr_t) ev->data.video.data;

			if (dst_cb){
				evmsg = "video_event(asynchimg_loaded), callback";
				lua_ctx_store.cb_source_kind = CB_SOURCE_IMAGE;
			}
		break;

		case EVENT_VIDEO_ASYNCHIMAGE_FAILED:
			srcobj = arcan_video_getobject(ev->data.video.source);
			evmsg = "video_event(asynchimg_load_fail), callback";
			tblstr(ctx, "kind", "load_failed", top);
			tblstr(ctx, "resource", srcobj && srcobj->vstore->vinf.text.source ?
				srcobj->vstore->vinf.text.source : "unknown", top);
			tblnum(ctx, "width", ev->data.video.width, top);
			tblnum(ctx, "height", ev->data.video.height, top);
			dst_cb = (intptr_t) ev->data.video.data;

			if (dst_cb){
				evmsg = "video_event(asynchimg_load_fail), callback";
				lua_ctx_store.cb_source_kind = CB_SOURCE_IMAGE;
			}
		break;

		default:
			arcan_warning("Engine -> Script Warning: arcan_lua_pushevent(),"
			"	unknown video event (%i)\n", ev->kind);
		}

		if (lua_ctx_store.cb_source_kind != CB_SOURCE_NONE){
			lua_ctx_store.cb_source_tag = ev->data.video.source;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
			lua_replace(ctx, 1);
			gotfun = true;
		}

		if (gotfun)
			wraperr(ctx, lua_pcall(ctx, 2, 0, 0), evmsg);
		else
			lua_settop(ctx, 0);

		lua_ctx_store.cb_source_kind = CB_SOURCE_NONE;
	}
	else if (ev->category == EVENT_AUDIO)
		;
}

static int imageparent(lua_State* ctx)
{
	LUA_TRACE("image_parent");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id pid = arcan_video_findparent(id);

	lua_pushvid( ctx, pid );
	return 1;
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

		while(*opts){
			lua_pushnumber(ctx, count++);
			lua_pushstring(ctx, *opts);
			lua_rawset(ctx, top);
			count++;
		}

		return 1;
	}
	else
		platform_video_setsynch(newstrat);

	return 0;
}

static int validvid(lua_State* ctx)
{
	LUA_TRACE("valid_vid");
	arcan_vobj_id res = (arcan_vobj_id) luaL_optnumber(ctx, 1, ARCAN_EID);

	if (res != ARCAN_EID && res != ARCAN_VIDEO_WORLDID)
		res -= lua_ctx_store.lua_vidbase;

	if (res < 0)
		res = ARCAN_EID;

	lua_pushboolean(ctx, arcan_video_findparent(res) != ARCAN_EID);
	return 1;
}

static int imagechildren(lua_State* ctx)
{
	LUA_TRACE("image_children");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id child;
	unsigned ofs = 0, count = 1;

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	while( (child = arcan_video_findchild(id, ofs++)) != ARCAN_EID){
		lua_pushnumber(ctx, count++);
		lua_pushvid(ctx, child);
		lua_rawset(ctx, top);
	}

	return 1;
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

	return 0;
}

static int framesetcycle(lua_State* ctx)
{
	LUA_TRACE("image_framecyclemode");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	unsigned num = luaL_optint(ctx, 2, 0);
	arcan_video_framecyclemode(sid, num);
	return 0;
}

static int pushasynch(lua_State* ctx)
{
	LUA_TRACE("image_pushasynch");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_video_pushasynch(sid);
	return 0;
}

static int activeframe(lua_State* ctx)
{
	LUA_TRACE("image_active_frame");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	unsigned num = luaL_checkint(ctx, 2);

	arcan_video_setactiveframe(sid, num);

	return 0;
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

	return 0;
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

	return 0;
}

static int imageasframe(lua_State* ctx)
{
	LUA_TRACE("set_image_as_frame");
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);
	unsigned num = luaL_checkint(ctx, 3);
	unsigned detach = luaL_optint(ctx, 4, FRAMESET_NODETACH);

	if (detach != FRAMESET_DETACH && detach != FRAMESET_NODETACH)
		arcan_fatal("set_image_as_frame() -- invalid 4th argument"
			"	(should be FRAMESET_DETACH or FRAMESET_NODETACH)\n");

	arcan_errc errc;
	arcan_vobj_id vid = arcan_video_setasframe(sid, did, num,
		detach == FRAMESET_DETACH, &errc);

	if (errc == ARCAN_OK)
		lua_pushvid(ctx, vid != sid ? vid : ARCAN_EID);
	else{
		arcan_warning("imageasframe(%d) failed, couldn't set (%d)"
			"	in slot (%d)\n", sid, did, num);
		lua_pushvid(ctx, ARCAN_EID);
	}

	return 1;
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
	return 1;
}

static inline int pushprop(lua_State* ctx,
	surface_properties prop, unsigned short zv)
{
	lua_createtable(ctx, 0, 6);

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

static int loadmesh(lua_State* ctx)
{
	LUA_TRACE("add_3dmesh");

	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	unsigned nmaps = abs(luaL_optnumber(ctx, 3, 1));
	char* path = findresource(luaL_checkstring(ctx, 2), DEFAULT_USERMASK);

	if (path){
			data_source indata = arcan_open_resource(path);
			if (indata.fd != BADFD){
				arcan_errc rv = arcan_3d_addmesh(did, indata, nmaps);
				if (rv != ARCAN_OK)
					arcan_warning("loadmesh(%s) -- "
						"Couldn't add mesh to (%d)\n", path, did);
				arcan_release_resource(&indata);
			}
	}

	free(path);
	return 0;
}

static int attrtag(lua_State* ctx)
{
	LUA_TRACE("attrtag_model");

	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	const char*  attr = luaL_checkstring(ctx, 2);
	int         state =  luaL_checknumber(ctx, 3);

	if (strcmp(attr, "infinite") == 0)
		lua_pushboolean(ctx,
			arcan_3d_infinitemodel(did, state != 0) != ARCAN_OK);
	else
		lua_pushboolean(ctx, false);

	return 1;
}

static int buildmodel(lua_State* ctx)
{
	LUA_TRACE("new_3dmodel");

	arcan_vobj_id id = ARCAN_EID;
	id = arcan_3d_emptymodel();

	if (id != ARCAN_EID)
		arcan_video_objectopacity(id, 0, 0);

	lua_pushvid(ctx, id);
	return 1;
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

	return 0;
}

static int buildplane(lua_State* ctx)
{
	LUA_TRACE("build_3dplane");

	float minx     = luaL_checknumber(ctx, 1);
	float mind     = luaL_checknumber(ctx, 2);
	float endx     = luaL_checknumber(ctx, 3);
	float endd     = luaL_checknumber(ctx, 4);
	float starty   = luaL_checknumber(ctx, 5);
	float hdens    = luaL_checknumber(ctx, 6);
	float ddens    = luaL_checknumber(ctx, 7);
	unsigned nmaps = abs(luaL_optnumber(ctx, 8, 1));

	lua_pushvid(ctx, arcan_3d_buildplane(minx, mind, endx, endd, starty,
		hdens, ddens, nmaps));
	return 1;
}

static int buildbox(lua_State* ctx)
{
	LUA_TRACE("build_3dbox");

	float width = luaL_checknumber(ctx, 1);
	float height = luaL_checknumber(ctx, 2);
	float depth = luaL_checknumber(ctx, 3);

	lua_pushvid(ctx, arcan_3d_buildbox(width, height, depth));

	return 1;
}

static int pointcloud(lua_State* ctx)
{
	LUA_TRACE("build_pointcloud");
	float count = luaL_checknumber(ctx, 1);

	lua_pushvid(ctx, arcan_3d_pointcloud(count));

	return 1;
}

static int swizzlemodel(lua_State* ctx)
{
	LUA_TRACE("swizzle_model");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	arcan_errc rv = arcan_3d_swizzlemodel(id);
	lua_pushboolean(ctx, rv == ARCAN_OK);

	return 1;
}

static int camtag(lua_State* ctx)
{
	LUA_TRACE("camtag_model");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	float w = arcan_video_display.canvasw;
	float h = arcan_video_display.canvash;
	float ar = w / h > 1.0 ? w / h : h / w;

	float nv  = luaL_optnumber(ctx, 2, 0.1);
	float fv  = luaL_optnumber(ctx, 3, 100.0);
	float fov = luaL_optnumber(ctx, 4, 45.0);
	ar = luaL_optnumber(ctx, 5, ar);
	bool front = luaL_optnumber(ctx, 6, true);
	bool back  = luaL_optnumber(ctx, 7, false);

	arcan_errc rv = arcan_3d_camtag(id, nv, fv, ar, fov, front, back);

	lua_pushboolean(ctx, rv == ARCAN_OK);
	return 1;
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

	return pushprop(ctx, prop, arcan_video_getzv(id));
}

static int getimageresolveprop(lua_State* ctx)
{
	LUA_TRACE("image_surface_resolve_properties");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
/* FIXME: resolve_properties does not take dt into account */
	surface_properties prop = arcan_video_resolve_properties(id);

	return pushprop(ctx, prop, arcan_video_getzv(id));
}

static int getimageinitprop(lua_State* ctx)
{
	LUA_TRACE("image_surface_initial_properties");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	surface_properties prop = arcan_video_initial_properties(id);

	return pushprop(ctx, prop, arcan_video_getzv(id));
}

static int getimagestorageprop(lua_State* ctx)
{
	LUA_TRACE("image_storage_properties");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	img_cons cons = arcan_video_storage_properties(id);
	lua_createtable(ctx, 0, 6);

	lua_pushstring(ctx, "bpp");
	lua_pushnumber(ctx, cons.bpp);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "height");
	lua_pushnumber(ctx, cons.h);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "width");
	lua_pushnumber(ctx, cons.w);
	lua_rawset(ctx, -3);

	return 1;
}

static int copyimageprop(lua_State* ctx)
{
	LUA_TRACE("copy_surface_properties");

	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);

	arcan_video_copyprops(sid, did);

	return 0;
}

static bool validate_key(const char* key)
{
	while(*key){
		if (!isalnum(*key) && *key != '_')
			return false;
		key++;
	}

	return true;
}

static int storekey(lua_State* ctx)
{
	LUA_TRACE("store_key");

	if (lua_type(ctx, 1) == LUA_TTABLE){
		union arcan_dbtrans_id tid;
		tid.applname = arcan_appl_id();

		lua_pushnil(ctx);
		arcan_db_begin_transaction(dbhandle, DVT_APPL, tid);

		size_t counter = 0;
		while (lua_next(ctx, 1) != 0){
			counter++;
			const char* key = lua_tostring(ctx, -2);
			if (!validate_key(key)){
				arcan_warning("store_key, key[%d] rejected "
					"(restricted to [a-Z0-9_])\n", counter);
			}
			else {
				const char* val = lua_tostring(ctx, -1);
				arcan_db_add_kvpair(dbhandle, key, val);
			}

			lua_pop(ctx, 1);
		}

		arcan_db_end_transaction(dbhandle);
	}
	else {
		const char* key = luaL_checkstring(ctx, 1);
		const char* name = luaL_checkstring(ctx, 2);
		arcan_db_appl_kv(dbhandle, arcan_appl_id(), key, name);
	}

	return 0;
}

static int push_stringres(lua_State* ctx, struct arcan_strarr* res)
{
	int rv = 0;

	if (res->data) {
		char** curr = res->data;
		unsigned int count = 1; /* 1 indexing, seriously LUA ... */

		curr = res->data;

		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		while (*curr) {
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
	const char* pattern = luaL_checkstring(ctx, 1);
	int domain = luaL_checknumber(ctx, 2);

	if (domain != DVT_TARGET && domain != DVT_CONFIG)
		arcan_fatal("match keys(%d) invalid domain specified, "
			"domain must be KEY_TARGET or KEY_CONFIG\n");

	struct arcan_strarr res = arcan_db_matchkey(dbhandle, domain, pattern);
	int rv = push_stringres(ctx, &res);
	arcan_mem_freearr(&res);

	return rv;
}

static int getkey(lua_State* ctx)
{
	LUA_TRACE("get_key");

	const char* key = luaL_checkstring(ctx, 1);
	if (!validate_key(key)){
		arcan_warning("invalid key specified (restricted to [a-Z0-9_])\n");
		lua_pushnil(ctx);
		return 1;
	}

	const char* opt_target = luaL_optstring(ctx, 2, NULL);

	if (opt_target){
		arcan_targetid tid = arcan_db_targetid(dbhandle, opt_target, NULL);

		const char* opt_config = luaL_optstring(ctx, 3, NULL);
		if (opt_config){
			arcan_configid cid = arcan_db_configid(dbhandle, tid, opt_config);
			char* val = arcan_db_getvalue(dbhandle, DVT_CONFIG, cid, key);
			if (val)
				lua_pushstring(ctx, val);
			else
				lua_pushnil(ctx);
			free(val);
		}
		else{
			arcan_db_getvalue(dbhandle, DVT_TARGET, tid, key);
		}
	}
	else {
	char* val = arcan_db_appl_val(dbhandle, arcan_appl_id(), key);

	if (val) {
		lua_pushstring(ctx, val);
		free(val);
	}
	else
		lua_pushnil(ctx);
	}

	return 1;

	lua_pushnil(ctx);
	return 1;
}

static int kbdrepeat(lua_State* ctx)
{
	LUA_TRACE("kbd_repeat");

	unsigned rrate = luaL_checknumber(ctx, 1);
	arcan_event_keyrepeat(arcan_event_defaultctx(), rrate);
	return 0;
}

static int v3dorder(lua_State* ctx)
{
	LUA_TRACE("video_3dorder");
	int order = luaL_checknumber(ctx, 1);

	if (order != ORDER3D_FIRST && order != ORDER3D_LAST && order != ORDER3D_NONE)
		arcan_fatal("3dorder(%d) invalid order specified (%d),"
			"	expected ORDER_FIRST, ORDER_LAST or ORDER_NONE\n");

	arcan_video_3dorder(order);
	return 0;
}

static int videocanvasrsz(lua_State* ctx)
{
	LUA_TRACE("resize_video_canvas");

	size_t w = abs(luaL_checknumber(ctx, 1));
	size_t h = abs(luaL_checknumber(ctx, 2));

/* note that this actually creates a texture in WORLDID that
 * is larger than the other permitted max surface dimensions,
 * this may need to be restricted ( create -> share storage etc. ) */

	if (ARCAN_OK == arcan_video_resize_canvas(w, h)){
		arcan_lua_setglobalint(ctx, "VRESW", w);
		arcan_lua_setglobalint(ctx, "VRESH", h);
	}

	return 0;
}

static int videodisplay(lua_State* ctx)
{
	LUA_TRACE("video_displaymodes");

	if (lua_gettop(ctx) > 0){
		platform_display_id id = luaL_checknumber(ctx, 1);
		platform_mode_id mode = luaL_checknumber(ctx, 2);
		lua_pushboolean(ctx, platform_video_set_mode(id, mode));
		return 1;
	}

	size_t count;
	platform_display_id* disps = platform_video_query_displays(&count);

	lua_newtable(ctx);
	int dtop = lua_gettop(ctx);

	for (size_t i = 0; i < count; i++){
		size_t mcount;
		struct monitor_modes* modes = platform_video_query_modes(disps[i], &mcount);

		for (size_t j = 0; j < mcount; j++){
			lua_pushnumber(ctx, i + 1);
			lua_newtable(ctx);
			int jtop = lua_gettop(ctx);

			lua_pushstring(ctx, "cardid");
			lua_pushnumber(ctx, 0);
			lua_rawset(ctx, jtop);

			lua_pushstring(ctx, "displayid");
			lua_pushnumber(ctx, disps[i]);
			lua_rawset(ctx, jtop);

			lua_pushstring(ctx, "moderef");
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

			lua_rawset(ctx, dtop);
		}
	}

	return 1;
}

static int videomapping(lua_State* ctx)
{
	LUA_TRACE("map_video_display");

	arcan_vobj_id vid = luavid_tovid( luaL_checknumber(ctx, 1) );
	platform_display_id id = luaL_checknumber(ctx, 2);

	if (vid != ARCAN_VIDEO_WORLDID && vid != ARCAN_EID){
		arcan_vobject* vobj = arcan_video_getobject(vid);
		if (!vobj)
			arcan_fatal("map_video_display(), invalid vid "
				"requested %"PRIxVOBJ" \n", vid);
		if (vobj->feed.ffunc)
			arcan_fatal("map_video_display(), display-mapped vobj "
				"cannot be connected to a dynamic handler");
	}

	lua_pushboolean(ctx, platform_video_map_display(id, vid));

	return 0;
}

static int mousegrab(lua_State* ctx)
{
	LUA_TRACE("toggle_mouse_grab");
	int mode = luaL_optint( ctx, 1, -1);

	if (mode == -1)
		lua_ctx_store.grab = !lua_ctx_store.grab;
	else if (mode == MOUSE_GRAB_ON)
		lua_ctx_store.grab = true;
	else if (mode == MOUSE_GRAB_OFF)
		lua_ctx_store.grab = false;

	arcan_device_lock(0, lua_ctx_store.grab);
	lua_pushboolean(ctx, lua_ctx_store.grab);

	return 1;
}

static int gettargets(lua_State* ctx)
{
	LUA_TRACE("list_targets");

	int rv = 0;

	struct arcan_strarr res = arcan_db_targets(dbhandle);
	rv += push_stringres(ctx, &res);
	arcan_mem_freearr(&res);

	return rv;
}

static int getconfigs(lua_State* ctx)
{
	LUA_TRACE("target_configurations");
	const char* target = luaL_checkstring(ctx, 1);
	int rv = 0;

	struct arcan_strarr res = arcan_db_configs(dbhandle,
		arcan_db_targetid(dbhandle, target, NULL));

	rv += push_stringres(ctx, &res);
	arcan_mem_freearr(&res);

	return rv;
}

static int allocsurface(lua_State* ctx)
{
	LUA_TRACE("alloc_surface");
	img_cons cons = {};
	cons.w = luaL_checknumber(ctx, 1);
	cons.h = luaL_checknumber(ctx, 2);
	cons.bpp = GL_PIXEL_BPP;

	if (cons.w > MAX_SURFACEW || cons.h > MAX_SURFACEH)
		arcan_fatal("alloc_surface(%d, %d) failed, unacceptable "
			"surface dimensions. Compile time restriction (%d,%d)\n",
			cons.w, cons.h, MAX_SURFACEW, MAX_SURFACEH);

	av_pixel* buf = arcan_alloc_mem(cons.w * cons.h * GL_PIXEL_BPP,
		ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

	av_pixel* cptr = buf;

	for (size_t y = 0; y < cons.h; y++)
		for (size_t x = 0; x < cons.w; x++)
			*cptr = RGBA(0, 0, 0, 0xff);

	arcan_vobj_id id = arcan_video_rawobject(buf, cons, cons.w, cons.h, 0);

	lua_pushvid(ctx, id);

	return 1;
}

static int fillsurface(lua_State* ctx)
{
	LUA_TRACE("fill_surface");
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};

	int desw = luaL_checknumber(ctx, 1);
	int desh = luaL_checknumber(ctx, 2);

	uint8_t r = abs(luaL_checknumber(ctx, 3));
	uint8_t g = abs(luaL_checknumber(ctx, 4));
	uint8_t b = abs(luaL_checknumber(ctx, 5));

	cons.w = abs(luaL_optnumber(ctx, 6, 8));
	cons.h = abs(luaL_optnumber(ctx, 7, 8));

	if (cons.w > 0 && cons.w <= MAX_SURFACEW &&
		cons.h > 0 && cons.h <= MAX_SURFACEH){

		av_pixel* buf = arcan_alloc_mem(cons.w * cons.h * GL_PIXEL_BPP,
			ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

		if (!buf)
			goto error;

		av_pixel* cptr = (av_pixel*) buf;

		for (size_t y = 0; y < cons.h; y++)
			for (size_t x = 0; x < cons.w; x++)
				*cptr++ = RGBA(r, g, b, 0xff);

		arcan_vobj_id id = arcan_video_rawobject(buf, cons, desw, desh, 0);

		lua_pushvid(ctx, id);
		return 1;
	}
	else {
		arcan_fatal("fillsurface(%d, %d) failed, unacceptable "
			"surface dimensions. Compile time restriction (%d,%d)\n",
			desw, desh, MAX_SURFACEW, MAX_SURFACEH);
	}

error:
	return 0;
}

static int imagemipmap(lua_State* ctx)
{
	LUA_TRACE("image_mipmap");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	bool state = lua_toboolean(ctx, 1);
	arcan_video_mipmapset(id, state);
	return 0;
}

static int imagecolor(lua_State* ctx)
{
	LUA_TRACE("image_color");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	uint8_t cred = abs(luaL_checknumber(ctx, 2));
	uint8_t cgrn = abs(luaL_checknumber(ctx, 3));
	uint8_t cblu = abs(luaL_checknumber(ctx, 4));

	if (!vobj || vobj->vstore->txmapped){
		lua_pushboolean(ctx, false);
		return 1;
	}

	vobj->vstore->vinf.col.r = (float)cred / 255.0f;
	vobj->vstore->vinf.col.g = (float)cgrn / 255.0f;
	vobj->vstore->vinf.col.b = (float)cblu / 255.0f;

	lua_pushboolean(ctx, true);
	return 1;
}

static int colorsurface(lua_State* ctx)
{
	LUA_TRACE("color_surface");

	size_t desw = abs(luaL_checknumber(ctx, 1));
	size_t desh = abs(luaL_checknumber(ctx, 2));
	int cred = abs(luaL_checknumber(ctx, 3));
	int cgrn = abs(luaL_checknumber(ctx, 4));
	int cblu = abs(luaL_checknumber(ctx, 5));
	int order = abs(luaL_optnumber(ctx, 6, 1));

	lua_pushvid(ctx, arcan_video_solidcolor(desw, desh,
		cred, cgrn, cblu, order));
	return 1;
}

static int nullsurface(lua_State* ctx)
{
	LUA_TRACE("null_surface");

	size_t desw = abs(luaL_checknumber(ctx, 1));
	size_t desh = abs(luaL_checknumber(ctx, 2));
	int order = abs(luaL_optnumber(ctx, 3, 1));

	lua_pushvid(ctx, arcan_video_nullobject(desw, desh, order) );
	return 1;
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

	img_cons cons = {.w = desw, .h = desh, .bpp = GL_PIXEL_BPP};

	luaL_checktype(ctx, 4, LUA_TTABLE);
	int nsamples = lua_rawlen(ctx, 4);

	if (nsamples != desw * desh * bpp)
		arcan_fatal("rawsurface(), number of values (%d) doesn't match"
			"	expected length (%d).\n", nsamples, desw * desh * bpp);

	unsigned ofs = 1;

	if (desw < 0 || desh < 0 || desw > MAX_SURFACEW || desh > MAX_SURFACEH)
		arcan_fatal("rawsurface(), desired dimensions (%d x %d) "
			"exceed compile-time limits (%d x %d).\n",
			desw, desh, MAX_SURFACEW, MAX_SURFACEH
		);

	av_pixel* buf = arcan_alloc_mem(desw * desh * GL_PIXEL_BPP,
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
		char* fname = arcan_find_resource(dumpstr, RESOURCE_APPL_TEMP);
		if (fname){
			arcan_warning("rawsurface() -- refusing to "
				"overwrite existing file (%s)\n", fname);
		}
		else{
			fname = arcan_expand_resource(dumpstr, RESOURCE_APPL_TEMP);
			FILE* fpek = fopen(fname, "wb");
			if (!fpek)
				arcan_warning("rawsurface() - - couldn't open (%s).\n", fname);
			else
				arcan_rgba32_pngfile(fpek, (char*)buf, desw, desh, 0);
		}
		arcan_mem_free(fname);
	}

	arcan_vobj_id id = arcan_video_rawobject(buf, cons, desw, desh, 0);

	lua_pushvid(ctx, id);
	return 1;
}

/*
 * not intendend to be used as a low-frequency noise function
 * will be fixed/refactored when the 3d-pipeline gets improved
 * (perlin with controlled number of octaves etc.)
 */
static int randomsurface(lua_State* ctx)
{
	LUA_TRACE("random_surface");

	int desw = abs( luaL_checknumber(ctx, 1) );
	int desh = abs( luaL_checknumber(ctx, 2) );
	img_cons cons = {.w = desw, .h = desh, .bpp = GL_PIXEL_BPP};

	av_pixel* cptr = arcan_alloc_mem(desw * desh * GL_PIXEL_BPP,
		ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

	av_pixel* buf = (av_pixel*) cptr;

	for (size_t y = 0; y < cons.h; y++)
		for (size_t x = 0; x < cons.w; x++){
			unsigned char val = 20 + rand() % 235;
			*cptr++ = RGBA(val, val, val, 0xff);
		}

	arcan_vobj_id id = arcan_video_rawobject(buf, cons, desw, desh, 0);
	arcan_video_objectfilter(id, ARCAN_VFILTER_NONE);
	lua_pushvid(ctx, id);

	return 1;
}

char* filter_text(char* in, size_t* out_sz)
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
	size_t len;
	char* msg = (char*) luaL_checkstring(ctx, 1);
	msg = filter_text(msg, &len);

	if (len == 0)
		return 0;

#ifdef ARCAN_LUA_NOCOLOR
	arcan_warning("(%s) %s\n", arcan_appl_id(), msg);
#else
	arcan_warning("\n\x1b[1m(%s)\x1b[32m %s\x1b[0m\n", arcan_appl_id(), msg);
#endif

	return 0;
}

void arcan_luaL_shutdown(lua_State* ctx)
{
	lua_close(ctx);
}

void arcan_luaL_dostring(lua_State* ctx, const char* code)
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

	lua_ctx_store.last_ctx = res;
	return res;
}

void arcan_lua_mapfunctions(lua_State* ctx, int debuglevel)
{
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
		.kind = EVENT_SYSTEM_EXIT,
		.data.system.errcode = luaL_optnumber(ctx, 2, EXIT_SUCCESS)
	};
	arcan_event_enqueue(arcan_event_defaultctx(), &ev);

	size_t tlen;
	const char* str = filter_text((char*)luaL_optstring(ctx, 1, ""), &tlen);
	if (tlen > 0)
		arcan_warning("%s\n", str);

	return 0;
}

static int switchappl(lua_State *ctx)
{
	LUA_DEPRECATE("switch_appl (use system_collapse instead)");

	arcan_event ev = {.category = EVENT_SYSTEM, .kind = EVENT_SYSTEM_SWITCHAPPL};
	const char* newappl = luaL_optstring(ctx, 1, arcan_appl_id());

	snprintf(ev.data.system.data.message, sizeof(ev.data.system.data.message)
		/ sizeof(ev.data.system.data.message[0]), "%s", newappl);
	arcan_event_enqueue(arcan_event_defaultctx(), &ev);

	return 0;
}

static void panic(lua_State* ctx)
{
	lua_ctx_store.debug = 2;

	if (!lua_ctx_store.cb_source_kind == CB_SOURCE_NONE){
		char vidbuf[64] = {0};
		snprintf(vidbuf, 63, "script error in callback for VID (%"PRIxVOBJ")",
			lua_ctx_store.lua_vidbase + lua_ctx_store.cb_source_tag);
		wraperr(ctx, -1, vidbuf);
	} else
		wraperr(ctx, -1, "(panic)");

	arcan_warning("LUA VM is in a panic state, "
		"recovery handover might be impossible.\n");

	longjmp(arcanmain_recover_state, 2);
}

static void wraperr(lua_State* ctx, int errc, const char* src)
{
	if (lua_ctx_store.debug)
		lua_ctx_store.lastsrc = src;

	if (errc == 0)
		return;

	const char* mesg = luaL_optstring(ctx, 1, "unknown");
/*
 * currently unused, pending refactor of arcan_warning
	int severity = luaL_optnumber(ctx, 2, 0);
 */

	if (lua_ctx_store.debug){
		arcan_warning("Warning: wraperr((), %s, from %s\n", mesg, src);

		if (lua_ctx_store.debug >= 1)
			dump_call_trace(ctx);

		if (lua_ctx_store.debug > 0)
			dump_stack(ctx);

		arcan_state_dump("crash", mesg, src);

		if (lua_ctx_store.debug > 2){
			arcan_warning("Fatal error ignored(%s, %s) through high debuglevel,"
				" attempting to continue.\n", mesg, src);
			return;
		}
	}

#ifdef ARCAN_LUA_NOCOLOR
	arcan_warning("Lua Script failure, %s from %s.\n", mesg, src);
#else
	arcan_warning("\n\x1b[1mScript failure:\n \x1b[32m %s\n"
		"\x1b[39mC-entry point: \x1b[32m %s \x1b[39m\x1b[0m.\n", mesg, src);
#endif
	arcan_warning("\nHanding over to recovery script "
		"(or shutdown if none present).\n");

	longjmp(arcanmain_recover_state, 2);
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
	int mask = luaL_optinteger(
		ctx, 2, DEFAULT_USERMASK) & (DEFAULT_USERMASK | RESOURCE_SYS_APPLBASE);

	lua_newtable(ctx);
	bptr.top = lua_gettop(ctx);

	arcan_glob(label, mask, globcb, &bptr);

	return 1;
}

static int resource(lua_State* ctx)
{
	LUA_TRACE("resource()");

	const char* label = luaL_checkstring(ctx, 1);
	int mask = luaL_optinteger(ctx, 2, DEFAULT_USERMASK) & DEFAULT_USERMASK;
	char* res = findresource(label, mask);
	lua_pushstring(ctx, res);
	free(res);
	return 1;
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
		return 8;
	}

	return 0;
}

bool arcan_lua_callvoidfun(lua_State* ctx, const char* fun, bool warn)
{
	if ( grabapplfunction(ctx, fun, strlen(fun)) ){
		wraperr(ctx, lua_pcall(ctx, 0, 0, 0), fun);
		return true;
	}
	else if (warn)
		arcan_warning("missing expected symbol ( %s )\n", fun);

	return false;
}

static int getqueueopts(lua_State* ctx)
{
	LUA_DEPRECATE("default_movie_queueopts");

	lua_pushnumber(ctx, 0);
	lua_pushnumber(ctx, 0);
	lua_pushnumber(ctx, 0);
	lua_pushnumber(ctx, 0);

	return 4;
}

static int setqueueopts(lua_State* ctx)
{
	LUA_DEPRECATE("default_movie_queueopts_override");

	return 0;
}

static bool use_loader(char* fname)
{
	char* ext = strrchr( fname, '.' );
	if (!ext) return false;

/* there are prettier ways to do this . . . */
	return ((strcasecmp(ext, ".so") == 0) || (strcasecmp(ext, ".dylib") == 0) ||
		(strcasecmp(ext, ".dll") == 0)) ? true : false;
}

static inline bool tgtevent(arcan_vobj_id dst, arcan_event ev)
{
	vfunc_state* state = arcan_video_feedstate(dst);

	if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr){
		arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;
		arcan_frameserver_pushevent( fsrv, &ev );
		return true;
	}

	return false;
}

static int targethandler(lua_State* ctx)
{
	LUA_TRACE("target_updatehandler");
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);

	intptr_t ref = find_lua_callback(ctx);

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV || !vobj->feed.state.ptr)
		arcan_fatal("target_updatehandler(), specified vid (arg 1) not "
			"associated with a frameserver.");

	arcan_frameserver* fsrv = vobj->feed.state.ptr;
	fsrv->tag = ref;

	return 0;
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
	fsrv->tag = (intptr_t) 0;

	arcan_frameserver_free(fsrv);
	vobj->feed.state.ptr = NULL;
	vobj->feed.state.tag = ARCAN_TAG_IMAGE;

	return 0;
}

static int targetreject(lua_State* ctx)
{
	LUA_TRACE("target_reject");
	arcan_event ev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_REQFAIL
	};

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	ev.data.target.ioevs[0].iv = luaL_checkinteger(ctx, 2);

	tgtevent(tgt, ev);

	return 0;
}

static int targetportcfg(lua_State* ctx)
{
	LUA_TRACE("target_portconfig");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	unsigned tgtport  = luaL_checkinteger(ctx, 2);
	unsigned tgtkind  = luaL_checkinteger(ctx, 3);

	arcan_event ev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_SETIODEV};

	ev.data.target.ioevs[0].iv = tgtport;
	ev.data.target.ioevs[1].iv = tgtkind;

	tgtevent(tgt, ev);

	return 0;
}

static int targetgraph(lua_State* ctx)
{
	LUA_TRACE("target_graphmode");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	unsigned ioval = luaL_checkinteger(ctx, 2);

	arcan_event ev = {
		.category = EVENT_TARGET,
		.kind     = TARGET_COMMAND_GRAPHMODE,
		.data.target.ioevs[0].iv = ioval
	};

	tgtevent(tgt, ev);

	return 0;
}

static int targetcoreopt(lua_State* ctx)
{
	LUA_TRACE("target_coreopt");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	arcan_event ev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_COREOPT
	};

	size_t msgsz = sizeof(ev.data.target.message) /
		sizeof(ev.data.target.message[0]);

	ev.data.target.code = luaL_checknumber(ctx, 2);
	const char* msg = luaL_checkstring(ctx, 3);

	strncpy(ev.data.target.message, msg, msgsz - 1);
	tgtevent(tgt, ev);

	return 0;
}

static int targetseek(lua_State* ctx)
{
	LUA_TRACE("target_seek");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	float val         = luaL_checknumber(ctx, 2);
	bool relative     = luaL_optnumber(ctx, 3, 1) != 0;

	vfunc_state* state = arcan_video_feedstate(tgt);

	if (!(state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr)){
		arcan_warning("targetseek() vid(%"PRIxVOBJ") is not "
			"connected to a frameserver\n", tgt);
		return 0;
	}

	arcan_event ev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_SEEKTIME
	};

	if (relative)
		ev.data.target.ioevs[1].iv = (int32_t) val;
	else
		ev.data.target.ioevs[0].fv = val;

	tgtevent(tgt, ev);

	return 0;
}

enum target_flags {
	TARGET_FLAG_SYNCHRONOUS = 0,
	TARGET_FLAG_NO_ALPHA_UPLOAD = 1,
	TARGET_FLAG_VERBOSE = 2
};

static void updateflag(arcan_vobj_id vid, enum target_flags flag, bool toggle)
{
	vfunc_state* state = arcan_video_feedstate(vid);

	if (!(state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr)){
		arcan_warning("targetverbose() vid(%"PRIxVOBJ") is not "
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

	case TARGET_FLAG_NO_ALPHA_UPLOAD:
		fsrv->flags.no_alpha_copy = toggle;
	break;
	}

}

static int targetflags(lua_State* ctx)
{
	LUA_TRACE("target_flags");
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	enum target_flags flag = luaL_checknumber(ctx, 2);
	if (flag < TARGET_FLAG_SYNCHRONOUS || flag > TARGET_FLAG_VERBOSE)
		arcan_fatal("target_flags() unknown flag value (%d)\n", flag);
 	bool toggle = luaL_optnumber(ctx, 3, 1) != 0;
	updateflag(tgt, flag, toggle);

	return 0;
}

static int targetsynchronous(lua_State* ctx)
{
	LUA_TRACE("target_synchronous");
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
 	bool toggle = luaL_optnumber(ctx, 3, 1) == 1;
	updateflag(tgt, TARGET_FLAG_SYNCHRONOUS, toggle);

	return 0;
}

static int targetverbose(lua_State* ctx)
{
	LUA_TRACE("target_verbose");
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
 	bool toggle = luaL_optnumber(ctx, 3, 1) == 1;
	updateflag(tgt, TARGET_FLAG_VERBOSE, toggle);

	return 0;
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

	if (skipval < -1) return 0;

	arcan_event ev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_FRAMESKIP
	};

	ev.data.target.ioevs[0].iv = skipval;
	ev.data.target.ioevs[1].iv = skiparg;
	ev.data.target.ioevs[2].iv = preaud;
	ev.data.target.ioevs[3].iv = skipdbg1;
	ev.data.target.ioevs[4].iv = skipdbg2;

	tgtevent(tgt, ev);

	return 0;
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
#ifndef WIN32
	int pair[2];
	if (pipe(pair) == -1){
		arcan_warning("bond_target(), pipe pair failed. Reason: %s\n", strerror(errno));
		return -1;
	}

	arcan_frameserver* fsrv_a = vobj_a->feed.state.ptr;
	arcan_frameserver* fsrv_b = vobj_b->feed.state.ptr;

	if (ARCAN_OK == arcan_frameserver_pushfd(fsrv_a, pair[1]) &&
		ARCAN_OK == arcan_frameserver_pushfd(fsrv_b, pair[0])){
		arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_STORE
		};

		arcan_frameserver_pushevent(fsrv_a, &ev);

		ev.kind = TARGET_COMMAND_RESTORE;
		arcan_frameserver_pushevent(fsrv_b, &ev);
	}

	close(pair[0]);
	close(pair[1]);

#else
	arcan_warning("bond_target yet to be implemented for WIN32");
#endif


	return 0;
}

static int targetrestore(lua_State* ctx)
{
	LUA_TRACE("restore_target");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	const char* snapkey = luaL_checkstring(ctx, 2);

	vfunc_state* state = arcan_video_feedstate(tgt);
	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		lua_pushboolean(ctx, false);
		return 1;
	}

	char* fname = arcan_find_resource(snapkey, RESOURCE_APPL_STATE);
	int fd = -1;
	if (fname)
		fd = open(fname, O_RDONLY);
	free(fname);

	if (-1 == fd){
		arcan_warning("couldn't load / resolve (%s)\n", snapkey);
		lua_pushboolean(ctx, false);
		return 1;
	}

	arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;
	if ( ARCAN_OK == arcan_frameserver_pushfd( fsrv, fd ) ){
		arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_RESTORE
		};

		arcan_frameserver_pushevent( fsrv, &ev );
		lua_pushboolean(ctx, true);
	}
	else
		lua_pushboolean(ctx, false);
	close(fd);

	return 1;
}

static int targetlinewidth(lua_State* ctx)
{
	LUA_TRACE("target_linewidth");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	float lsz = luaL_checknumber(ctx, 2);
	arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_VECTOR_LINEWIDTH,
			.data.target.ioevs[0].fv = lsz
	};

	tgtevent(tgt, ev);

	return 0;
}

static int targetpointsize(lua_State* ctx)
{
	LUA_TRACE("target_pointsize");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	float psz = luaL_checknumber(ctx, 2);
	arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_VECTOR_POINTSIZE,
			.data.target.ioevs[0].fv = psz
	};

	tgtevent(tgt, ev);

	return 0;
}

static int targetpostfilter(lua_State* ctx)
{
	LUA_TRACE("target_postfilter");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	int filtertype = luaL_checknumber(ctx, 2);

	if (filtertype != POSTFILTER_NTSC && filtertype != POSTFILTER_OFF)
		arcan_warning("targetpostfilter() -- "
			"unknown filter (%d) specified.\n", filtertype);
	else {
		arcan_event ev = {
			.category    = EVENT_TARGET,
			.kind        = TARGET_COMMAND_NTSCFILTER
		};

		ev.data.target.ioevs[0].iv = filtertype == POSTFILTER_NTSC;
		tgtevent(tgt, ev);
	}

	return 0;
}

static int targetpostfilterargs(lua_State* ctx)
{
	LUA_TRACE("target_postfilter_args");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	int group = luaL_checknumber(ctx, 2);
	float v1  = luaL_optnumber(ctx, 3, 0.0);
	float v2  = luaL_optnumber(ctx, 4, 0.0);
	float v3  = luaL_optnumber(ctx, 5, 0.0);

	arcan_event ev = {
		.category    = EVENT_TARGET,
		.kind        = TARGET_COMMAND_NTSCFILTER_ARGS
	};

	ev.data.target.ioevs[0].iv = group;
	ev.data.target.ioevs[1].fv = v1;
	ev.data.target.ioevs[2].fv = v2;
	ev.data.target.ioevs[3].fv = v3;

	tgtevent(tgt, ev);

	return 0;
}

static int targetstepframe(lua_State* ctx)
{
	LUA_TRACE("stepframe_target");

	arcan_vobject* vobj;
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, &vobj);
	vfunc_state* state = arcan_video_feedstate(tgt);
	struct rendertarget* rtgt = find_rendertarget(vobj);

	bool qev = true;

/*
 * Recordtargets are a special case as they have both
 * a frameserver feedstate and the output of a rendertarget.
 * The actual stepframe event will be set by the ffunc handler
 * (arcan_frameserver_backend.c)
 */

	if (state->tag != ARCAN_TAG_FRAMESERV || rtgt)
		qev = false;

	int nframes = luaL_optnumber(ctx, 2, 1);
	if (nframes <= 0)
		return 0;

	if (rtgt && !rtgt->readreq && arcan_video_display.pbo_support){
		glBindBuffer(GL_PIXEL_PACK_BUFFER, rtgt->pbo);
		struct storage_info_t* dstore = rtgt->color->vstore;
		readback_texture(dstore->vinf.text.glid, dstore->w, dstore->h, 0, 0);
		glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
		rtgt->readreq = true;
	}

	if (qev){
		arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_STEPFRAME
		};
		ev.data.target.ioevs[0].iv = nframes;
		tgtevent(tgt, ev);
	}

	return 0;
}

static int targetsnapshot(lua_State* ctx)
{
	LUA_TRACE("snapshot_target");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	const char* snapkey = luaL_checkstring(ctx, 2);

	vfunc_state* state = arcan_video_feedstate(tgt);
	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		lua_pushboolean(ctx, false);
		return 1;
	}
	arcan_frameserver* fsrv = state->ptr;

	char* fname = arcan_expand_resource(snapkey, RESOURCE_APPL_STATE);
	int fd = -1;
	if (fname)
		fd = open(fname, O_CREAT | O_WRONLY | O_TRUNC, S_IRWXU);
	arcan_mem_free(fname);

	if (-1 == fd){
		lua_pushboolean(ctx, false);
		return 1;
	}

	if (ARCAN_OK == arcan_frameserver_pushfd(fsrv, fd)){
		arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_STORE
		};

		arcan_frameserver_pushevent(fsrv, &ev);
		lua_pushboolean(ctx, true);
	}
	else
		lua_pushboolean(ctx, false);

	return 1;
}

static int targetreset(lua_State* ctx)
{
	LUA_TRACE("reset_target");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	arcan_event ev = {
		.kind = TARGET_COMMAND_RESET,
		.category = EVENT_TARGET
	};

	tgtevent(vid, ev);

	return 0;
}

static int targetalloc(lua_State* ctx)
{
	LUA_TRACE("target_alloc");
	int cb_ind = 2;
	char* pw = NULL;
	size_t pwlen = 0;

	if (lua_type(ctx, 2) == LUA_TSTRING){
		pw = (char*) luaL_checkstring(ctx, 2);
		pwlen = strlen(pw);
		if (pwlen > PP_SHMPAGE_SHMKEYLIM-1){
			arcan_warning(
				"target_alloc(), requested passkey length (%d) exceeds "
				"built-in threshold (%d characters) and will be truncated .\n",
				pwlen, pw);

			pwlen = PP_SHMPAGE_SHMKEYLIM-1;
		}
		else
			cb_ind = 3;
	}

	luaL_checktype(ctx, cb_ind, LUA_TFUNCTION);
	if (lua_iscfunction(ctx, cb_ind))
		arcan_fatal("target_alloc(), callback to C function forbidden.\n");

	lua_pushvalue(ctx, cb_ind);
	intptr_t ref = luaL_ref(ctx, LUA_REGISTRYINDEX);

	int tag = luaL_optint(ctx, cb_ind+1, 0);

	arcan_frameserver* newref = NULL;
	const char* key = "";

/*
 * allocate new key or give to preexisting frameserver?
 */
	if (lua_type(ctx, 1) == LUA_TSTRING){
		key = luaL_checkstring(ctx, 1);
		newref = arcan_frameserver_listen_external(key);
		if (!newref)
			return 0;
	}
	else {
		arcan_vobj_id srcfsrv = luaL_checkvid(ctx, 1, NULL);
		vfunc_state* state = arcan_video_feedstate(srcfsrv);

		if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr)
			newref = arcan_frameserver_spawn_subsegment(
				(arcan_frameserver*) state->ptr, true, 0, 0, tag);
		else
			arcan_fatal("target_alloc() specified source ID doesn't "
				"contain a frameserver\n.");
	}

	newref->tag = ref;
	if (pw)
		memcpy(newref->clientkey, pw, pwlen);

	lua_pushvid(ctx, newref->vid);
	lua_pushaid(ctx, newref->aid);

	return 2;
}

static int targetlaunch(lua_State* ctx)
{
	LUA_TRACE("launch_target");
	arcan_configid cid = BAD_CONFIG;
	size_t rc = 0;
	int lmode;

	if (lua_type(ctx, 1) == LUA_TSTRING){
		cid = arcan_db_configid(dbhandle, arcan_db_targetid(dbhandle,
			luaL_checkstring(ctx, 1), NULL), luaL_checkstring(ctx, 2));
		lmode = luaL_checknumber(ctx, 3);
	}
	else
		lmode = luaL_checknumber(ctx, 2);

	if (lmode != 0 && lmode != 1)
		arcan_fatal("launch_target(), invalid mode -- expected LAUNCH_INTERNAL "
			" or LAUNCH_EXTERNAL ");

	uintptr_t ref = find_lua_callback(ctx);

	struct arcan_strarr argv, env, libs = {0};
	enum DB_BFORMAT bfmt;
	argv = env = libs;

	const char* exec = arcan_db_targetexec(dbhandle, cid,
		&bfmt, &argv, &env, &libs);

	if (!exec){
		arcan_warning("launch_target(), failed -- invalid configuration");
		return 0;
	}

	arcan_frameserver* intarget = NULL;

	switch (bfmt){
	case BFRM_BIN:
	case BFRM_SHELL:
		intarget = arcan_target_launch_internal(exec, &argv, &env, &libs);
	break;

	case BFRM_LWA:
/* FIXME lookup arcan_lwa binary, and feed that as the executable,
 * this will be more prominent when we have a package format going */
	break;

	case BFRM_RETRO:
		if (lmode != 1){
			arcan_warning("launch_target(), configuration specified libretro format"
				" which is only possible in internal- mode.");
			goto cleanup;
		}

		intarget = arcan_frameserver_alloc();
		intarget->tag = ref;
		struct frameserver_envp args = {
			.use_builtin = true,
			.args.builtin.resource = "",
			.args.builtin.mode = "libretro"
		};

		if (arcan_frameserver_spawn_server(intarget, args) != ARCAN_OK){
			arcan_frameserver_free(intarget);
			intarget = NULL;
		}
	break;

	default:
		arcan_fatal("launch_target(), database inconsistency, unknown "
			"binary format encountered.\n");
	}

	if (intarget){
		arcan_video_objectopacity(intarget->vid, 0.0, 0);
		lua_pushvid(ctx, intarget->vid);
		lua_pushaid(ctx, intarget->aid);
		arcan_db_launch_status(dbhandle, cid, true);
		rc = 2;
	}
	else
		arcan_db_launch_status(dbhandle, cid, false);

cleanup:
	arcan_mem_freearr(&argv);
	arcan_mem_freearr(&env);
	arcan_mem_freearr(&libs);
	return rc;
}

static int rendertargetforce(lua_State* ctx)
{
	LUA_TRACE("rendertarget_forceupdate");
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	if (ARCAN_OK != arcan_video_forceupdate(vid))
		arcan_fatal("rendertarget_forceupdate(), specified vid "
			"was not connected to a rendertarget");

	return 0;
}

static int rendernoclear(lua_State* ctx)
{
	LUA_TRACE("rendertarget_noclear");
	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	bool clearfl = lua_toboolean(ctx, 2);

	lua_pushboolean(ctx,
		arcan_video_rendertarget_setnoclear(did, clearfl) == ARCAN_OK);
	return 1;
}

static int renderattach(lua_State* ctx)
{
	LUA_TRACE("rendertarget_attach");

	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id sid = luaL_checkvid(ctx, 2, NULL);
	int detach        = luaL_checkint(ctx, 3);

	if (detach != RENDERTARGET_DETACH && detach != RENDERTARGET_NODETACH){
		arcan_warning("renderattach(%d) invalid arg 3, expected "
			"RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
		return 0;
	}

/* arcan_video_attachtorendertarget already has pretty aggressive checks */
	arcan_video_attachtorendertarget(did, sid, detach == RENDERTARGET_DETACH);
	return 0;
}

static int renderset(lua_State* ctx)
{
	LUA_TRACE("define_rendertarget");

	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	int nvids         = lua_rawlen(ctx, 2);
	int detach        = luaL_checkint(ctx, 3);
	int scale         = luaL_checkint(ctx, 4);
	int format        = luaL_optint(ctx, 5, RENDERFMT_COLOR);

	if (detach != RENDERTARGET_DETACH && detach != RENDERTARGET_NODETACH){
		arcan_warning("renderset(%d) invalid arg 3, expected "
			"RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
		return 0;
	}

	if (scale != RENDERTARGET_SCALE && scale != RENDERTARGET_NOSCALE){
		arcan_warning("renderset(%d) invalid arg 4, expected "
			"RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
		return 0;
	}

	if (nvids > 0){
		arcan_video_setuprendertarget(did, 0,
			scale == RENDERTARGET_SCALE, format);

		for (size_t i = 0; i < nvids; i++){
			lua_rawgeti(ctx, 2, i+1);
			arcan_vobj_id setvid = luavid_tovid( lua_tonumber(ctx, -1) );
			lua_pop(ctx, 1);
			arcan_video_attachtorendertarget(
				did, setvid, detach == RENDERTARGET_DETACH);
		}

	}
	else
		arcan_warning("renderset(%d, %d) - "
		"	refusing to define empty renderset.\n");

	return 0;
}

enum colorspace {
	PROC_RGBA = 0,
	PROC_MONO8 = 1
};

struct proctarget_src {
	lua_State* ctx;
	uintptr_t cbfun;
};

struct rn_userdata {
	void* bufptr;
	int width, height;
	size_t nelem;

	unsigned bins[1024];
	bool valid, dirty;
};

static void procimage_buildhisto(struct rn_userdata* ud, bool reset)
{
	av_pixel* img = ud->bufptr;
	ud->dirty = false;

	if (reset)
		memset(ud->bins, '\0', 1024 * sizeof(unsigned));

/* populate bins with frequency */
	for (size_t row = 0; row < ud->height; row++)
		for (size_t col = 0; col < ud->width; col++){
			size_t ofs = row * ud->width + col;
			uint8_t rgba[4];
			RGBA_DECOMP(img[ofs], &rgba[0], &rgba[1], &rgba[2], &rgba[3]);

			ud->bins[rgba[0]]++;
			ud->bins[256 + rgba[1]]++;
			ud->bins[512 + rgba[2]]++;
			ud->bins[768 + rgba[3]]++;
		}
}

static int procimage_lookup(lua_State* ctx)
{
	struct rn_userdata* ud = luaL_checkudata(ctx, 1, "calcImage");

	if (ud->valid == false && ud->dirty)
		arcan_fatal("calcImage:frequency, calctarget object called "
			"out of scope.\n");

	ssize_t bin = luaL_checknumber(ctx, 2);
	if (256 <= bin || 0 > bin)
		arcan_fatal("calcImage:frequency, invalid bin %d >= 256 specified.\n");

	bool reset = luaL_optnumber(ctx, 3, 0) != 0;

	if (ud->dirty)
		procimage_buildhisto(ud, reset);

	lua_pushnumber(ctx, ud->bins[bin +   0]);
	lua_pushnumber(ctx, ud->bins[bin + 256]);
	lua_pushnumber(ctx, ud->bins[bin + 512]);
	lua_pushnumber(ctx, ud->bins[bin + 768]);

	return 4;
}

static int procimage_histo(lua_State* ctx)
{
	struct rn_userdata* ud = luaL_checkudata(ctx, 1, "calcImage");
	bool reset = luaL_optnumber(ctx, 3, 0) != 0;

	if (ud->valid == false && ud->dirty)
		arcan_fatal("calcImage:histogram_storage, "
			"calctarget object called out of scope\n");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 2, &vobj);

	if (!vobj->vstore || vobj->vstore->txmapped == TXSTATE_OFF ||
		!vobj->vstore->vinf.text.raw)
		arcan_fatal("calcImage:histogram_storage, "
			"destination vstore must have a valid textured backend.\n");

	if (vobj->vstore->w < 256)
		arcan_fatal("calcImage:histogram_storage, "
			"destination vstore width need to be >=256.\n");

	if (ud->dirty)
		procimage_buildhisto(ud, reset);

/* normalize and superimpose into storage */
	float norm = ud->width * ud->height;
	av_pixel* base = (av_pixel*) vobj->vstore->vinf.text.raw;

	for (size_t j = 0; j < 256; j++){
		float r = (float)ud->bins[j+  0] / norm * 255.0;
		float g = (float)ud->bins[j+256] / norm * 255.0;
		float b = (float)ud->bins[j+512] / norm * 255.0;
		float a = (float)ud->bins[j+768] / norm * 255.0;
		base[j] = RGBA(r,g,b,a);
	}
/* forceupdate vobj storage */
	push_globj(vobj, false, false);
	return 0;
}

static int procimage_get(lua_State* ctx)
{
	struct rn_userdata* ud = luaL_checkudata(ctx, 1, "calcImage");
	if (ud->valid == false)
		arcan_fatal("calcImage:get, calctarget object called out of scope\n");

	int x = luaL_checknumber(ctx, 2);
	int y = luaL_checknumber(ctx, 3);

	if (x > ud->width || y > ud->height){
		arcan_fatal("calcImage:get, requested coordinates out of range, "
			"source: %d * %d, requested: %d, %d\n",
			ud->width, ud->height, x, y);
	}

	uint8_t* img = ud->bufptr;
	uint8_t r = img[(y * ud->width + x) * GL_PIXEL_BPP + 0];
	uint8_t g = img[(y * ud->width + x) * GL_PIXEL_BPP + 1];
	uint8_t b = img[(y * ud->width + x) * GL_PIXEL_BPP + 2];

	if (luaL_optnumber(ctx, 4, 0) != 0){
		lua_pushnumber(ctx, (float)(r + g + b) / 3.0);
		return 1;
	}	else {
		lua_pushnumber(ctx, r);
		lua_pushnumber(ctx, g);
		lua_pushnumber(ctx, b);
		return 3;
	}
}

static enum arcan_ffunc_rv proctarget(enum arcan_ffunc_cmd cmd,
	av_pixel* buf, size_t buf_sz, uint16_t width, uint16_t height,
	unsigned mode, vfunc_state state)
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
	ud->dirty = true;

	lua_ctx_store.cb_source_kind = CB_SOURCE_IMAGE;

 	lua_pushnumber(src->ctx, width);
	lua_pushnumber(src->ctx, height);
	wraperr(src->ctx, lua_pcall(src->ctx, 3, 0, 0), "proctarget_cb");

/*
 * Even if the lua function maintains a reference to this userdata,
 * we know that it's accessed outside scope and can put a fatal error on it.
 */
	lua_ctx_store.cb_source_kind = CB_SOURCE_NONE;
	ud->valid = false;

	return 0;
}

static int spawn_recsubseg(lua_State* ctx,
	arcan_vobj_id did, arcan_vobj_id dfsrv, int naids,
	arcan_aobj_id* aidlocks)
{
	arcan_vobject* vobj = arcan_video_getobject(dfsrv);
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (!fsrv || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
		arcan_fatal("spawn_recsubseg() -- specified destination is "
			"not a frameserver.\n");
	}

	arcan_frameserver* rv =
		arcan_frameserver_spawn_subsegment(fsrv, false, 0, 0, 0);

	if(rv){
		vfunc_state fftag = {
			.tag = ARCAN_TAG_FRAMESERV,
			.ptr = rv
		};

		if (lua_isfunction(ctx, 9) && !lua_iscfunction(ctx, 9)){
			lua_pushvalue(ctx, 9);
			rv->tag = luaL_ref(ctx, LUA_REGISTRYINDEX);
		}

/* shmpage prepared, force dimensions based on source object */
		arcan_vobject* dobj = arcan_video_getobject(did);
		struct arcan_shmif_page* shmpage = rv->shm.ptr;
		shmpage->w = dobj->vstore->w;
		shmpage->h = dobj->vstore->h;
		arcan_shmif_calcofs(shmpage, &(rv->vidp), &(rv->audp));
		arcan_video_alterfeed(did, arcan_frameserver_avfeedframe, fftag);

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
	arcan_frameserver* mvctx = arcan_frameserver_alloc();
	arcan_vobject* dobj = arcan_video_getobject(did);

	mvctx->vid  = did;

	/* in order to stay backward compatible API wise,
 * the load_movie with function callback will always need to specify
 * loop condition. (or we can switch to heuristic stack management) */
	if (lua_isfunction(ctx, 9) && !lua_iscfunction(ctx, 9)){
		lua_pushvalue(ctx, 9);
		mvctx->tag = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}

	struct frameserver_envp args = {
		.use_builtin = true,
		.custom_feed = true,
		.args.builtin.mode = "record",
		.args.builtin.resource = argl,
		.init_w = dobj->vstore->w,
		.init_h = dobj->vstore->h
	};

/* we use a special feed function meant to flush audiobuffer +
 * a single video frame for encoding */
	vfunc_state fftag = {
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = mvctx
	};
	arcan_video_alterfeed(did, arcan_frameserver_avfeedframe, fftag);

	if ( arcan_frameserver_spawn_server(mvctx, args) != ARCAN_OK ){
		free(mvctx);
		return 0;
	}

/* we define the size of the recording to be that of the storage
 * of the rendertarget vid, this should be allocated through fill_surface */
	struct arcan_shmif_page* shmpage = mvctx->shm.ptr;
	shmpage->w = dobj->vstore->w;
	shmpage->h = dobj->vstore->h;

	arcan_shmif_calcofs(shmpage, &(mvctx->vidp), &(mvctx->audp));

/* pushing the file descriptor signals the frameserver to start receiving
 * (and use the proper dimensions), it is permitted to close and push another
 * one to the same session, with special treatment for "dumb" resource names
 * or streaming sessions */
	int fd = 0;

/* currently we allow null- files and failed lookups to be pushed
 * for legacy reasons as the trigger for the frameserver to started
 * recording was when recieving the fd to work with */
	if (strstr(args.args.builtin.resource,
		"container=stream") != NULL || strlen(resf) == 0)
		fd = open(NULFILE, O_WRONLY);
	else {
		char* fn = arcan_expand_resource(resf, RESOURCE_APPL_TEMP);

/* it is currently allowed to "record over" an existing file without forcing
 * the caller to use zap_resource first, this should be REFACTORED. */
		fd = open(fn, O_CREAT | O_RDWR, S_IRWXU);
		if (-1 == fd){
			arcan_warning("couldn't create output (%s), "
				"recorded data will be lost\n", fn);
			fd = open(NULFILE, O_WRONLY);
		}

		arcan_mem_free(fn);
	}

	if (fd){
		arcan_frameserver_pushfd( mvctx, fd );
		close(fd);
	}

	mvctx->alocks = aidlocks;

/*
 * lastly, lock each audio object and forcibly attach the frameserver as
 * a monitor. NOTE that this currently doesn't handle the case where we we
 * set up multiple recording sessions sharing audio objects.
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

	if (pollrate == 0){
		arcan_warning("define_calctarget(%d) invalid arg 5, expected "
			"n < 0 (every n frame) or n > 0 (every n tick)\n", pollrate);
		goto cleanup;
	}

	if (ARCAN_OK != (arcan_video_setuprendertarget(did, pollrate,
					scale == RENDERTARGET_SCALE, RENDERTARGET_COLOR)))
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
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = (void*) cbsrc
	};
	arcan_video_alterfeed(did, proctarget, fftag);

cleanup:
	return 0;
}

static int recordset(lua_State* ctx)
{
	LUA_TRACE("define_recordtarget");

	arcan_vobject* dvobj;
	arcan_vobj_id did = luaL_checkvid(ctx, 1, &dvobj);

	if (FL_TEST(dvobj, FL_CLONE))
		arcan_fatal("define_recordtarget(), recordtarget "
			"recipient cannot be a clone.");

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

		global_monitor = true;
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

	if (pollrate == 0){
		arcan_warning("recordset(%d) invalid arg 8, expected "
			"n < 0 (every n frame) or n > 0 (every n tick)\n", pollrate);
		goto cleanup;
	}

	if (ARCAN_OK != arcan_video_setuprendertarget(did, pollrate,
		scale == RENDERTARGET_SCALE, RENDERTARGET_COLOR))
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
				char* ol = arcan_alloc_mem(strlen(argl) + strlen(":noaudio=true") + 1,
					ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);

				sprintf(ol, "%s%s", argl, ":noaudio=true");
				free(argl);
				argl = ol;
				break;
			}

			aidlocks[i] = setaid;
		}
	}

	rc = dfsrv != ARCAN_EID ?
		spawn_recsubseg(ctx, did, dfsrv, naids, aidlocks) :
		spawn_recfsrv(ctx, did, dfsrv, naids, aidlocks, argl, resf);

cleanup:
	free(argl);
	return rc;
}

static int recordgain(lua_State* ctx)
{
	LUA_TRACE("recordtarget_gain");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	arcan_aobj_id aid = luaL_checkaid(ctx, 2);
	float left = luaL_checknumber(ctx, 3);
	float right = luaL_checknumber(ctx, 4);

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV || !vobj->feed.state.ptr)
		arcan_fatal("recordgain() -- bad arg1, "
			"VID is not a frameserver.\n");

	arcan_frameserver* fsrv = vobj->feed.state.ptr;
	arcan_frameserver_update_mixweight(fsrv, aid, left, right);

	return 0;
}

static int borderscan(lua_State* ctx)
{
	LUA_DEPRECATE("image_borderscan");
	int x1, y1, x2, y2;
	x1 = y1 = 0;
	x2 = arcan_video_screenw();
	y2 = arcan_video_screenh();

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);

/* since GLES doesn't support texture readback, the option would be to render
 * then readback pixels as there is limited use for this feature, we'll stick
 * to the cheap route, i.e. assume we don't use memory- conservative mode and
 * just grab the buffer from the cached storage. */
	if (vobj && vobj->vstore->txmapped &&
		vobj->vstore->vinf.text.raw && vobj->vstore->vinf.text.s_raw > 0
		&& vobj->origw > 0 && vobj->origh > 0){

#define sample(x,y) \
	( vobj->vstore->vinf.text.raw[ ((y) * vobj->origw + (x)) * 4 + 3 ] )

		for (x1 = vobj->origw >> 1;
			x1 >= 0 && sample(x1, vobj->origh >> 1) < 128; x1--);
		for (x2 = vobj->origw >> 1;
			x2 < vobj->origw && sample(x2, vobj->origh >> 1) < 128; x2++);
		for (y1 = vobj->origh >> 1;
			y1 >= 0 && sample(vobj->origw >> 1, y1) < 128; y1--);
		for (y2 = vobj->origh >> 1;
			y2 < vobj->origh && sample(vobj->origw >> 1, y2) < 128; y2++);
#undef sample
		}

	lua_pushnumber(ctx, x1);
	lua_pushnumber(ctx, y1);
	lua_pushnumber(ctx, x2);
	lua_pushnumber(ctx, y2);
	return 4;
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
	return 0;
}

static int getbenchvals(lua_State* ctx)
{
	LUA_TRACE("benchmark_data");
	size_t bench_sz = sizeof(benchdata.ticktime) / sizeof(benchdata.ticktime[0]);

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

	bench_sz = sizeof(benchdata.frametime) / sizeof(benchdata.frametime[0]);
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

	bench_sz = sizeof(benchdata.framecost) / sizeof(benchdata.framecost[0]);
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

	return 6;
}

static int timestamp(lua_State* ctx)
{
	LUA_TRACE("benchmark_timestamp");

	lua_pushnumber(ctx, arcan_timemillis());
	return 1;
}

static int decodemod(lua_State* ctx)
{
	LUA_TRACE("decode_modifiers");

	int modval = luaL_checkint(ctx, 1);

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	int count = 1;
	if ((modval & ARKMOD_LSHIFT) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "lshift");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_RSHIFT) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "rshift");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_LALT) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "lalt");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_RALT) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "ralt");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_LCTRL) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "lctrl");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_RCTRL) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "rctrl");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_LMETA) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "lmeta");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_RMETA) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "rmeta");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_NUM) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "num");
		lua_rawset(ctx, top);
	}

	if ((modval & ARKMOD_CAPS) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "caps");
		lua_rawset(ctx, top);
	}

	return 1;
}

static int movemodel(lua_State* ctx)
{
	LUA_TRACE("move3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	float x = luaL_checknumber(ctx, 2);
	float y = luaL_checknumber(ctx, 3);
	float z = luaL_checknumber(ctx, 4);
	unsigned int dt = luaL_optint(ctx, 5, 0);

	arcan_video_objectmove(vid, x, y, z, dt);
	return 0;
}

static int forwardmodel(lua_State* ctx)
{
	LUA_TRACE("forward3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	float mag = luaL_checknumber(ctx, 2);
	unsigned int dt = luaL_optint(ctx, 3, 0);
	bool axismask_x = luaL_optnumber(ctx, 4, 0) != 0;
	bool axismask_y = luaL_optnumber(ctx, 5, 0) != 0;
	bool axismask_z = luaL_optnumber(ctx, 6, 0) != 0;

	surface_properties prop = arcan_video_current_properties(vid);

	vector view = taitbryan_forwardv(prop.rotation.roll,
		prop.rotation.pitch, prop.rotation.yaw);
	view = mul_vectorf(view, mag);
	vector newpos = add_vector(prop.position, view);

	arcan_video_objectmove(vid,
		axismask_x ? prop.position.x : newpos.x,
		axismask_y ? prop.position.y : newpos.y,
		axismask_z ? prop.position.z : newpos.z, dt);
	return 0;
}

static int strafemodel(lua_State* ctx)
{
	LUA_TRACE("strafe3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	float mag = luaL_checknumber(ctx, 2);
	unsigned int dt = luaL_optint(ctx, 3, 0);

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

	return 0;
}

static int scalemodel(lua_State* ctx)
{
	LUA_TRACE("scale3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	float sx = luaL_checknumber(ctx, 2);
	float sy = luaL_checknumber(ctx, 3);
	float sz = luaL_checknumber(ctx, 4);
	unsigned int dt = luaL_optint(ctx, 5, 0);

	arcan_video_objectscale(vid, sx, sy, sz, dt);
	return 0;
}

static int orientmodel(lua_State* ctx)
{
	LUA_TRACE("orient3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	double roll       = luaL_checknumber(ctx, 2);
	double pitch      = luaL_checknumber(ctx, 3);
	double yaw        = luaL_checknumber(ctx, 4);
	arcan_3d_baseorient(vid, roll, pitch, yaw);
	return 0;
}

/* map a format string to the arcan_shdrmgmt.h different datatypes */
static int shader_uniform(lua_State* ctx)
{
	LUA_TRACE("shader_uniform");

	float fbuf[16];

	int sid = abs(luaL_checknumber(ctx, 1));
	const char* label = luaL_checkstring(ctx, 2);
	const char* fmtstr = luaL_checkstring(ctx, 3);
	bool persist = luaL_checknumber(ctx, 4) != 0;

	if (arcan_shader_activate(sid) != ARCAN_OK){
		arcan_warning("shader_uniform(), shader (%d) failed"
			"	to activate.\n", sid);
		return 0;
	}

	if (!label)
		label = "unknown";

	if (strcmp(label, "ff") == 0){
		abort();
	}

	if (fmtstr[0] == 'b'){
		int fmt = luaL_checknumber(ctx, 5) != 0;
		arcan_shader_forceunif(label, shdrbool, &fmt, persist);
	} else if (fmtstr[0] == 'i'){
		int fmt = luaL_checknumber(ctx, 5);
		arcan_shader_forceunif(label, shdrint, &fmt, persist);
	} else {
		unsigned i = 0;
		while(fmtstr[i] == 'f') i++;
		if (i)
			switch(i){
				case 1:
					fbuf[0] = luaL_checknumber(ctx, 5);
					arcan_shader_forceunif(label, shdrfloat, fbuf, persist);
				break;

				case 2:
					fbuf[0] = luaL_checknumber(ctx, 5);
					fbuf[1] = luaL_checknumber(ctx, 6);
					arcan_shader_forceunif(label, shdrvec2, fbuf, persist);
				break;

				case 3:
					fbuf[0] = luaL_checknumber(ctx, 5);
					fbuf[1] = luaL_checknumber(ctx, 6);
					fbuf[2] = luaL_checknumber(ctx, 7);
					arcan_shader_forceunif(label, shdrvec3, fbuf, persist);
				break;

				case 4:
					fbuf[0] = luaL_checknumber(ctx, 5);
					fbuf[1] = luaL_checknumber(ctx, 6);
					fbuf[2] = luaL_checknumber(ctx, 7);
					fbuf[3] = luaL_checknumber(ctx, 8);
					arcan_shader_forceunif(label, shdrvec4, fbuf, persist);
				break;

				case 16:
						while(i--)
							fbuf[i] = luaL_checknumber(ctx, 5 + i);

						arcan_shader_forceunif(label, shdrmat4x4, fbuf, persist);

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

	return 0;
}

static int rotatemodel(lua_State* ctx)
{
	LUA_TRACE("rotate3d_model");

	arcan_vobj_id vid = luaL_checkvid(ctx, 1, NULL);
	double roll       = luaL_checknumber(ctx, 2);
	double pitch      = luaL_checknumber(ctx, 3);
	double yaw        = luaL_checknumber(ctx, 4);
	unsigned int dt   = abs(luaL_optnumber(ctx, 5, 0));
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

	return 0;
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

	return 0;
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

	return 0;
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
			"	FILTER_LINEAR, FILTER_BILINEAR or FILTER_TRILINEAR\n", mode);

	return 0;
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


	return 0;
}

static int tracetag(lua_State* ctx)
{
	LUA_TRACE("image_tracetag");

	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);
	const char* const msg = luaL_optstring(ctx, 2, NULL);

	if (!msg){
		const char* tag = arcan_video_readtag(id);
		lua_pushstring(ctx, tag ? tag : "(no tag)");
		return 1;
	}
	else
		arcan_video_tracetag(id, msg);

	return 0;
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

	return 0;
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

	return 1;
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

	arcan_event_analogfilter(joyid, axisid,
		lb, ub, deadzone, buffer_sz, mode);

	return 0;
}

static inline void tblanalogenum(lua_State* ctx, int ttop,
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

	arcan_errc errc = arcan_event_analogstate(devid, axid,
		&lbound, &ubound, &dz, &ksz, &mode);

	if (errc != ARCAN_OK){
		const char* lbl = arcan_event_devlabel(devid);

		if (lbl != NULL){
			lua_newtable(ctx);
			int ttop = lua_gettop(ctx);
			tblstr(ctx, "label", arcan_event_devlabel(devid), ttop);
			tblnum(ctx, "devid", devid, ttop);
			return 1;
		}

		return 0;
	}

	lua_newtable(ctx);
	int ttop = lua_gettop(ctx);
	tblnum(ctx, "devid", devid, ttop);
	tblnum(ctx, "subid", axid, ttop);
	tblstr(ctx, "label", arcan_event_devlabel(devid), ttop);
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
	int axnum = abs(luaL_optnumber(ctx, 2, 0));
	bool rescan = luaL_optnumber(ctx, 3, 0) != 0;

 	if (rescan)
		arcan_event_rescan_idev(arcan_event_defaultctx());

	if (devnum != -1)
		return singlequery(ctx, devnum, axnum);

	lua_newtable(ctx);
	arcan_errc errc = ARCAN_OK;

	while (errc != ARCAN_ERRC_NO_SUCH_OBJECT){
		int axid = 0;

		while (true){
			int lbound, ubound, dz, ksz;
			enum ARCAN_ANALOGFILTER_KIND mode;

			errc = arcan_event_analogstate(devid, axid,
				&lbound, &ubound, &dz, &ksz, &mode);

			if (errc != ARCAN_OK)
				break;

			int rawtop = lua_gettop(ctx);
			lua_pushnumber(ctx, resind++);
			lua_newtable(ctx);
			int ttop = lua_gettop(ctx);

			tblnum(ctx, "devid", devid, ttop);
			tblnum(ctx, "subid", axid, ttop);
			tblstr(ctx, "label", arcan_event_devlabel(devid), ttop);
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

	return 1;
}

static int inputanalogtoggle(lua_State* ctx)
{
	LUA_TRACE("inputanalog_toggle");

	bool val = lua_tonumber(ctx, 1) != 0;
	bool mouse = luaL_optnumber(ctx, 2, 0) != 0;

	arcan_event_analogall(val, mouse);
	return 0;
}

static int screenshot(lua_State* ctx)
{
	LUA_TRACE("save_screenshot");

	av_pixel* databuf = NULL;
	size_t bufs;
	int dw = arcan_video_display.canvasw;
	int dh = arcan_video_display.canvash;

	const char* const resstr = luaL_checkstring(ctx, 1);
	arcan_vobj_id sid = ARCAN_EID;

	bool flip = luaL_optnumber(ctx, 2, 0) != 0;

	if (luaL_optnumber(ctx, 3, ARCAN_EID) != ARCAN_EID){
		sid = luaL_checkvid(ctx, 3, NULL);
			arcan_video_forceread(sid, &databuf, &bufs);

		img_cons com = arcan_video_storage_properties(sid);
		dw = com.w;
		dh = com.h;
	}
	else
		arcan_video_screenshot(&databuf, &bufs);

	if (databuf){
		char* fname = arcan_find_resource(resstr, RESOURCE_APPL_TEMP);
		if (fname){
			arcan_warning("screeenshot() -- refusing to overwrite existing file.\n");
			goto cleanup;
		}

		fname = arcan_expand_resource(resstr, RESOURCE_APPL_TEMP);
		FILE* dst = fopen(fname, "wb");

		if (dst)
			arcan_rgba32_pngfile(dst, (void*) databuf, dw, dh, flip);
		else
			arcan_warning("screenshot() -- couldn't save to (%s).\n", fname);

cleanup:
		arcan_mem_free(fname);
		arcan_mem_free(databuf);
	}
	else
		arcan_warning("screenshot() -- insufficient free memory.\n");

	return 0;
}

void arcan_lua_eachglobal(lua_State* ctx, char* prefix,
	int (*callback)(const char*, const char*, void*), void* tag)
{
/* FIXME: incomplete (planned for the sandboxing / hardening release).
 * 1. have a toggle saying that this functionality is desired
 *    (as the overhead is notable),
 * 2. maintain a trie/prefix tree that this functions just maps to
 * 3. populate the tree with a C version of:

	local metatable = {}
		setmetatable(_G,{
    __index    = metatable, -- or a function handling reads
    __newindex = function(t,k,v)
     -- k and v will contain table key and table value respectively.
     rawset(metatable,k, v)
    end})
	}

	this would in essence intercept all global table updates, meaning that we can,
 	at least, use that as a lookup scope for tab completion etc.
*/
}

static bool lua_launch_fsrv(lua_State* ctx,
	struct frameserver_envp* args, intptr_t callback)
{
	arcan_frameserver* intarget = arcan_frameserver_alloc();
	intarget->tag = callback;

	if (arcan_frameserver_spawn_server(intarget, *args) == ARCAN_OK){
		lua_pushvid(ctx, intarget->vid);
		return true;
	}
	else {
		lua_pushvid(ctx, ARCAN_EID);
		free(intarget);
		return false;
	}
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

	return 1;
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

	return 1;
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

	return 1;
}

static inline arcan_frameserver* luaL_checknet(lua_State* ctx,
	bool server, arcan_vobject** dvobj, const char* prefix)
{
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV || !vobj->feed.state.ptr)
		arcan_fatal("%s -- VID is not a frameserver.\n", prefix);

	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (server && fsrv->segid != SEGID_NETWORK_SERVER){
		arcan_fatal("%s -- Frameserver connected to VID is not in server mode "
			"(net_open vs net_listen)\n", prefix);
	}
	else if (!server && fsrv->segid != SEGID_NETWORK_CLIENT)
		arcan_fatal("%s -- Frameserver connected to VID is not in client mode "
			"(net_open vs net_listen)\n", prefix);

	if (fsrv->flags.subsegment)
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
			outev.kind = EVENT_NET_CUSTOMMSG;

			const char* msg = luaL_checkstring(ctx, 2);
			size_t out_sz = sizeof(outev.data.network.message) /
				sizeof(outev.data.network.message[0]);
			snprintf(outev.data.network.message, out_sz, "%s", msg);
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

			arcan_frameserver* srv = arcan_frameserver_spawn_subsegment(
				srcvobj->feed.state.ptr, false, dvobj->vstore->w, dvobj->vstore->h, 0);

			if (!srv){
				arcan_warning("net_pushcl(), allocating subsegment failed\n");
				return 0;
			}

/* disable "regular" frameserver behavior */
			vfunc_state cstate = *arcan_video_feedstate(srv->vid);
			arcan_video_alterfeed(srv->vid, arcan_frameserver_emptyframe, cstate);

/* we can't delete the frameserver immediately as the child might
 * not have mapped the memory yet, so we defer and use a callback */
			memcpy(srv->vidp, dvobj->vstore->vinf.text.raw,
				dvobj->vstore->vinf.text.s_raw);

			srv->shm.ptr->vready = true;
			arcan_sem_post(srv->vsync);

			outev.kind = TARGET_COMMAND_STEPFRAME;
			arcan_frameserver_pushevent(srv, &outev);
			lua_pushvid(ctx, srv->vid);
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
	arcan_frameserver_pushevent(fsrv, &outev);

	return 0;
}

/* similar to push to client, with the added distinction of broadcast / target,
 * and thus a more complicated pushFD etc. behavior */
static int net_pushsrv(lua_State* ctx)
{
	LUA_TRACE("net_push_srv");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	int domain          = luaL_optnumber(ctx, 3, 0);

/* arg2 can be (string) => NETMSG, (event) => just push */
	arcan_event outev = {.category = EVENT_NET, .data.network.connid = domain};
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV || !fsrv)
		arcan_fatal("net_pushsrv() -- bad arg1, VID "
			"is not a frameserver.\n");

	if (fsrv->flags.subsegment)
		arcan_fatal("net_pushsrv() -- cannot push VID to a subsegment.\n");

	if (!fsrv->segid == SEGID_NETWORK_CLIENT)
		arcan_fatal("net_pushsrv() -- bad arg1, specified frameserver"
			" is not in client mode (net_open).\n");

/* we clean this as to not expose stack trash */
	size_t out_sz = sizeof(outev.data.network.message) /
		sizeof(outev.data.network.message[0]);

	if (lua_isstring(ctx, 2)){
		outev.kind = EVENT_NET_CUSTOMMSG;

		const char* msg = luaL_checkstring(ctx, 2);
		snprintf(outev.data.network.message, out_sz, "%s", msg);
		arcan_frameserver_pushevent(fsrv, &outev);
	}
	else
		arcan_fatal("net_pushsrv() -- "
			"unexpected data to push, accepted (string)\n");

	return 0;
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

	arcan_event outev = {.category = EVENT_NET, .data.network.connid = domain};
	arcan_frameserver_pushevent(fsrv, &outev);

	return 0;
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
	 	.kind = EVENT_NET_DISCONNECT,
	 	.data.network.connid = domain
	};

	arcan_frameserver_pushevent(fsrv, &outev);
	return 0;
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
	 	.kind = EVENT_NET_AUTHENTICATE,
	 	.data.network.connid = domain
	};
	arcan_frameserver_pushevent(fsrv, &outev);

	return 0;
}

/*
 * quite expensive pushes and not that everyone has a use-case for this,
 * so we separate it out and if the user wants working graphing,
 * have him or her push refreshes
 */
static int net_refresh(lua_State* ctx)
{
	LUA_TRACE("net_refresh");

	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	arcan_event outev = {.category = EVENT_NET, .kind = EVENT_NET_GRAPHREFRESH};

	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (!fsrv)
		return 0;

	if (!fsrv->segid == SEGID_NETWORK_SERVER)
		arcan_fatal("net_pushsrv() -- bad arg1, specified frameserver "
		"is not in server mode (net_refresh).\n");

	arcan_frameserver_pushevent(fsrv, &outev);

	return 0;
}

void arcan_lua_cleanup()
{
}

void arcan_lua_pushargv(lua_State* ctx, char** argv)
{
	int argc = 0;

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	while(argv[argc]){
		lua_pushnumber(ctx, argc + 1);
		lua_pushstring(ctx, argv[argc]);
		lua_rawset(ctx, top);
		argc++;
	}

	lua_setglobal(ctx, "arguments");
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

/*
 * just experiments, should setup a real
 * hid- lua mapping here
#include <hidapi/hidapi.h>
int turretcmd(lua_State* ctx)
{
	static hid_device* handle;
	if (!handle)
		handle = hid_open_path("/dev/hidraw5");

	if (!handle){
		lua_pushboolean(ctx, false);
		return 1;
	}

	unsigned char dbuf[8] = {0};
	dbuf[0] = lua_tonumber(ctx, 1);
	dbuf[1] = lua_tonumber(ctx, 2);

	hid_write(handle, dbuf, 8);

	lua_pushboolean(ctx, true);
	return 1;
}
*/

int getidentstr(lua_State* ctx)
{
	LUA_TRACE("system_identstr");

/*
 * possibly add more data-sources here, key is that they provide
 * a
 */
	lua_pushstring(ctx, platform_video_capstr());

	return 1;
}

arcan_errc arcan_lua_exposefuncs(lua_State* ctx, unsigned char debugfuncs)
{
	if (!ctx)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	lua_ctx_store.debug = debugfuncs;
	lua_atpanic(ctx, (lua_CFunction) panic);

#ifdef _DEBUG
	lua_ctx_store.lua_vidbase = rand() % 32768;
	arcan_warning("lua_exposefuncs() -- videobase is set to %u\n",
		lua_ctx_store.lua_vidbase);
#endif

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

	luaL_newmetatable(ctx, "nonblockIO");
	lua_pushvalue(ctx, -1);
	lua_setfield(ctx, -2, "__index");
	lua_pushcfunction(ctx, nbio_read);
	lua_setfield(ctx, -2, "read");
	lua_pushcfunction(ctx, nbio_close);
	lua_setfield(ctx, -2, "__gc");
	lua_pushcfunction(ctx, nbio_close);
	lua_setfield(ctx, -2, "close");
	lua_pop(ctx, 1);

#define EXT_MAPTBL_TARGETCONTROL
static const luaL_Reg tgtfuns[] = {
{"launch_target",              targetlaunch             },
{"target_alloc",               targetalloc              },
{"target_input",               targetinput              },
{"input_target",               targetinput              },
{"suspend_target",             targetsuspend            },
{"resume_target",              targetresume             },
{"target_portconfig",          targetportcfg            },
{"target_framemode",           targetskipmodecfg        },
{"target_verbose",             targetverbose            },
{"target_synchronous",         targetsynchronous        },
{"target_flags",               targetflags              },
{"target_pointsize",           targetpointsize          },
{"target_linewidth",           targetlinewidth          },
{"target_postfilter",          targetpostfilter         },
{"target_graphmode",           targetgraph              },
{"target_postfilter_args",     targetpostfilterargs     },
{"target_seek",                targetseek               },
{"target_coreopt",             targetcoreopt            },
{"target_reject",              targetreject             },
{"target_updatehandler",       targethandler            },
{"pacify_target",              targetpacify             },
{"stepframe_target",           targetstepframe          },
{"snapshot_target",            targetsnapshot           },
{"restore_target",             targetrestore            },
{"bond_target",                targetbond               },
{"reset_target",               targetreset              },
{"define_rendertarget",        renderset                },
{"define_recordtarget",        recordset                },
{"define_calctarget",          procset                  },
{"rendertarget_forceupdate",   rendertargetforce        },
{"recordtarget_gain",          recordgain               },
{"rendertarget_attach",        renderattach             },
{"rendertarget_noclear",       rendernoclear            },
{"play_movie",                 playmovie                },
{"load_movie",                 loadmovie                },
{"launch_avfeed",              setupavstream            },
{"pause_movie",                targetsuspend            },
{"resume_movie",               targetresume             },
{NULL, NULL}
};
#undef EXT_MAPTBL_TARGETCONTROL
	register_tbl(ctx, tgtfuns);

#define EXT_MAPTBL_DATABASE
static const luaL_Reg dbfuns[] = {
{"store_key",    storekey   },
{"get_key",      getkey     },
{"list_targets", gettargets },
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
{"pause_audio",       pauseaudio  },
{"delete_audio",      dropaudio   },
{"load_asample",      loadasample },
{"audio_gain",        gain        },
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
{"persist_image",            imagepersist       },
{"image_parent",             imageparent        },
{"image_children",           imagechildren      },
{"order_image",              orderimage         },
{"max_current_image_order",  maxorderimage      },
{"instance_image",           instanceimage      },
{"link_image",               linkimage          },
{"set_image_as_frame",       imageasframe       },
{"image_framesetsize",       framesetalloc      },
{"image_framecyclemode",     framesetcycle      },
{"image_pushasynch",         pushasynch         },
{"image_active_frame",       activeframe        },
{"image_origo_offset",       origoofs           },
{"image_inherit_order",      orderinherit       },
{"expire_image",             setlife            },
{"reset_image_transform",    resettransform     },
{"instant_image_transform",  instanttransform   },
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
{"image_sharestorage",       sharestorage       },
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
{"render_text",              rendertext         },
{"text_dimensions",          textdimensions     },
{"image_borderscan",         borderscan         },
{"random_surface",           randomsurface      },
{"force_image_blend",        forceblend         },
{"image_hit",                hittest            },
{"pick_items",               pick               },
{"image_surface_initial_properties", getimageinitprop   },
{"image_surface_resolve_properties", getimageresolveprop},
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
{"camtag_model",     camtag       },
{"build_3dplane",    buildplane   },
{"build_3dbox",      buildbox     },
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
{"switch_appl",         switchappl       },
{"warning",             warning          },
{"system_load",         dofile           },
{"system_context_size", systemcontextsize},
{"system_snapshot",     syssnap          },
{"system_collapse",     syscollapse      },
{"utf8kind",            utf8kind         },
{"decode_modifiers",    decodemod        },
{"benchmark_enable",    togglebench      },
{"benchmark_timestamp", timestamp        },
{"benchmark_data",      getbenchvals     },
{"system_identstr",     getidentstr      },
#ifdef _DEBUG
{"freeze_image",        freezeimage      },
#endif
{NULL, NULL}
};
#undef EXT_MAPTBL_SYSTEM
	register_tbl(ctx, sysfuns);

#define EXT_MAPTBL_IODEV
static const luaL_Reg iofuns[] = {
{"kbd_repeat",          kbdrepeat        },
{"toggle_mouse_grab",   mousegrab        },
#ifdef ARCAN_LED
{"set_led",             setled           },
{"led_intensity",       led_intensity    },
{"set_led_rgb",         led_rgb          },
{"controller_leds",     n_leds           },
#endif
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
{"resize_video_canvas",              videocanvasrsz },
{"video_displaymodes",               videodisplay   },
{"map_video_display",                videomapping   },
{"video_3dorder",                    v3dorder       },
{"default_movie_queueopts",          getqueueopts   },
{"default_movie_queueopts_override", setqueueopts   },
{"build_shader",                     buildshader    },
{"valid_vid",                        validvid       },
{"video_synchronization",            videosynch     },
{"shader_uniform",                   shader_uniform },
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
{"net_refresh",      net_refresh     },
{NULL, NULL},
};
#undef EXT_MAPTBL_NETWORK
	register_tbl(ctx, netfuns);

/*
 * METATABLE definitions
 *  [image] => used for calctargets
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

	atexit(arcan_lua_cleanup);
	return ARCAN_OK;
}

void arcan_lua_pushglobalconsts(lua_State* ctx){
#define EXT_CONSTTBL_GLOBINT
	struct { const char* key; int val; } consttbl[] = {
{"VRESH", arcan_video_screenh()},
{"VRESW", arcan_video_screenw()},
{"MAX_SURFACEW", MAX_SURFACEW},
{"MAX_SURFACEH", MAX_SURFACEH},
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
{"FRAMESERVER_LOOP", 0},
{"FRAMESERVER_NOLOOP", 1},
{"TARGET_SYNCHRONOUS", TARGET_FLAG_SYNCHRONOUS},
{"TARGET_NOALPHA", TARGET_FLAG_NO_ALPHA_UPLOAD},
{"TARGET_VERBOSE", TARGET_FLAG_VERBOSE},
{"RENDERTARGET_NOSCALE", RENDERTARGET_NOSCALE},
{"RENDERTARGET_SCALE", RENDERTARGET_SCALE},
{"RENDERTARGET_NODETACH", RENDERTARGET_NODETACH},
{"RENDERTARGET_DETACH", RENDERTARGET_DETACH},
{"RENDERTARGET_COLOR", RENDERFMT_COLOR},
{"RENDERTARGET_DEPTH", RENDERFMT_DEPTH},
{"RENDERTARGET_FULL", RENDERFMT_FULL},
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
{"THEME_RESOURCE", RESOURCE_APPL}, /* DEPRECATE */
{"APPL_RESOURCE", RESOURCE_APPL},
{"APPL_TEMP_RESOURCE",RESOURCE_APPL_TEMP},
{"SHARED_RESOURCE", RESOURCE_APPL_SHARED},
{"SYS_APPL_RESOURCE", RESOURCE_SYS_APPLBASE},
{"ALL_RESOURCES", DEFAULT_USERMASK},
{"API_VERSION_MAJOR", 0},
{"API_VERSION_MINOR", 8},
{"LAUNCH_EXTERNAL", 0},
{"LAUNCH_INTERNAL", 1},
{"MASK_LIVING", MASK_LIVING},
{"MASK_ORIENTATION", MASK_ORIENTATION},
{"MASK_OPACITY", MASK_OPACITY},
{"MASK_POSITION", MASK_POSITION},
{"MASK_SCALE", MASK_SCALE},
{"MASK_UNPICKABLE", MASK_UNPICKABLE},
{"MASK_FRAMESET", MASK_FRAMESET},
{"MASK_MAPPING", MASK_MAPPING},
{"ORDER_FIRST", ORDER3D_FIRST},
{"ORDER_NONE", ORDER3D_NONE},
{"ORDER_LAST", ORDER3D_LAST},
{"ORDER_SKIP", ORDER3D_NONE},
{"MOUSE_GRABON", MOUSE_GRAB_ON},
{"MOUSE_GRABOFF", MOUSE_GRAB_OFF},
{"POSTFILTER_NTSC", POSTFILTER_NTSC},
{"POSTFILTER_OFF", POSTFILTER_OFF},
#ifdef ARCAN_LED
{"LEDCONTROLLERS", arcan_led_controllers()},
#else
{"LEDCONTROLLERS", 0},
#endif
{"KEY_CONFIG", DVT_CONFIG},
{"KEY_TARGET", DVT_TARGET},
{"NOW", 0},
{"NOPERSIST", 0},
{"PERSIST", 1},
{"NET_BROADCAST", 0},
{"DEBUGLEVEL", lua_ctx_store.debug}
};
#undef EXT_CONSTTBL_GLOBINT

	for (size_t i = 0; i < sizeof(consttbl) / sizeof(consttbl[0]); i++)
		arcan_lua_setglobalint(ctx, consttbl[i].key, consttbl[i].val);

#if defined(GL_ES_VERSION_2_0)
#if defined(GL_ES_VERSION_3_0)
	arcan_lua_setglobalstr(ctx, "GL_VERSION", "GLES3");
#else
	arcan_lua_setglobalstr(ctx, "GL_VERSION", "GLES2");
#endif
#else
	arcan_lua_setglobalstr(ctx, "GL_VERSION", "GL21");
#endif
	arcan_lua_setglobalstr(ctx, "FRAMESERVER_MODES", FRAMESERVER_MODESTRING );
	arcan_lua_setglobalstr(ctx, "THEMENAME", "deprecated, use APPLID" );
	arcan_lua_setglobalstr(ctx, "APPLID", arcan_appl_id());
	arcan_lua_setglobalstr(ctx, "RESOURCEPATH", "deprecated");
	arcan_lua_setglobalstr(ctx, "THEMEPATH", "deprecated");
	arcan_lua_setglobalstr(ctx, "BINPATH", "deprecated");
	arcan_lua_setglobalstr(ctx, "LIBPATH", "deprecated");
	arcan_lua_setglobalstr(ctx, "INTERNALMODE", "deprecated");
	arcan_lua_setglobalstr(ctx, "API_ENGINE_BUILD", ARCAN_BUILDVERSION);
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
	static char fbuf[sizeof("persist clone clip noasynch "
		"cycletransform rothier_origo order ")];

	fbuf[0] = '\0';
	if (FL_TEST(src, FL_PRSIST))
		strcat(fbuf, "persist ");
	if (FL_TEST(src, FL_CLONE))
		strcat(fbuf, "clone ");
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

static inline char* lut_filtermode(enum arcan_vfilter_mode mode)
{
	switch(mode){
	case ARCAN_VFILTER_NONE     : return "none";
	case ARCAN_VFILTER_LINEAR   : return "linear";
	case ARCAN_VFILTER_BILINEAR : return "bilinear";
	case ARCAN_VFILTER_TRILINEAR: return "trilinear";
	}
	return "[missing filter]";
}

static inline char* lut_imageproc(enum arcan_imageproc_mode mode)
{
	switch(mode){
	case IMAGEPROC_NORMAL: return "normal";
	case IMAGEPROC_FLIPH : return "vflip";
	}
	return "[missing proc]";
}

static inline char* lut_scale(enum arcan_vimage_mode mode)
{
	switch(mode){
	case ARCAN_VIMAGE_NOPOW2    : return "nopow2";
	case ARCAN_VIMAGE_SCALEPOW2 : return "scalepow2";
	}
	return "[missing scale]";
}

static inline char* lut_framemode(enum arcan_framemode mode)
{
	switch(mode){
	case ARCAN_FRAMESET_SPLIT        : return "split";
	case ARCAN_FRAMESET_MULTITEXTURE : return "multitexture";
	}
	return "[missing framemode]";
}

static inline char* lut_clipmode(enum arcan_clipmode mode)
{
	switch(mode){
	case ARCAN_CLIP_OFF     : return "disabled";
	case ARCAN_CLIP_ON      : return "stencil deep";
	case ARCAN_CLIP_SHALLOW : return "stencil shallow";
	}
	return "[missing clipmode]";
}

static inline char* lut_blendmode(enum arcan_blendfunc func)
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
static inline void fprintf_float(FILE* dst,
	const char* pre, float in, const char* post)
{
	float intp, fractp;
 	fractp = modff(in, &intp);

	if (isnan(in))
		fprintf(dst, "%snan%s", pre, post);
	else if (isinf(in))
		fprintf(dst, "%sinf%s", pre, post);
	else
		fprintf(dst, "%s%d.%d%s", pre, (int)intp, abs(fractp), post);
}

static void addquoted (lua_State *L, luaL_Buffer *b, int arg) {
  size_t l;
  const char *s = luaL_checklstring(L, arg, &l);
  luaL_addchar(b, '"');
  while (l--) {
    switch (*s) {
      case '"': case '\\': case '\n': {
        luaL_addchar(b, '\\');
        luaL_addchar(b, *s);
        break;
      }
      case '\r': {
        luaL_addlstring(b, "\\r", 2);
        break;
      }
      case '\0': {
        luaL_addlstring(b, "\\000", 4);
        break;
      }
      default: {
        luaL_addchar(b, *s);
        break;
      }
    }
    s++;
  }
  luaL_addchar(b, '"');
}

static inline char* lut_txmode(int txmode)
{
	switch (txmode){
	case GL_REPEAT:
		return "repeat";
	case GL_CLAMP_TO_EDGE:
		return "clamp(edge)";
	default:
		return "unknown(broken)";
	}
}

static inline char* lut_kind(arcan_vobject* src)
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
static inline void dump_props(FILE* dst, surface_properties props)
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

static inline int qused(struct arcan_evctx* dq)
{
	return *(dq->front) > *(dq->back) ? dq->eventbuf_sz -
	*(dq->front) + *(dq->back) : *(dq->back) - *(dq->front);
}

static inline const char* fsrvtos(enum ARCAN_SEGID ink)
{
	switch(ink){
	case SEGID_LWA: return "lightweight arcan";
	case SEGID_MEDIA: return "multimedia";
	case SEGID_NETWORK_SERVER: return "network-server";
	case SEGID_NETWORK_CLIENT: return "network-client";
	case SEGID_SHELL: return "shell";
	case SEGID_REMOTING: return "remoting";
	case SEGID_GAME: return "game";
	case SEGID_APPLICATION: return "application";
	case SEGID_BROWSER: return "browser";
	case SEGID_ENCODER: return "encoder";
	case SEGID_SENSOR: return "sensor";
	case SEGID_INPUTDEVICE: return "inputdevice";
	case SEGID_DEBUG: return "debug";
	case SEGID_UNKNOWN: return "unknown";
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

static inline void dump_vstate(FILE* dst, arcan_vobject* vobj)
{
	if (!vobj->feed.state.ptr || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		return;

	arcan_frameserver* fsrv = vobj->feed.state.ptr;
fprintf(dst,
"vobj.fsrv = {\
\tlastpts = %lld,\
\tsocksig = %d,\
\tpbo = %d,\
\taudbuf_sz = %d,\
\taudbuf_used = %d,\
\tchild_alive = %d,\
\tinevq_sz = %d,\
\tinevq_used = %d,\
\toutevq_sz = %d,\
\toutevq_used = %d,",
	(long long) fsrv->lastpts,
	(int) fsrv->flags.socksig,
	(int) fsrv->flags.pbo,
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

static inline void dump_vobject(FILE* dst, arcan_vobject* src)
{
	char* mask = maskstr(src->mask);

/*
 * note that most strings á glstore_*, scale* etc. are safe
 * in the sense that they are not user-supplied in any way.
 */
	fprintf(dst,
"vobj = {\n\
\torigw = %d,\n\
\torigh = %d,\n\
\torder = %d,\n\
\tlast_updated = %d,\n\
\tlifetime = %d,\n\
\tcellid = %d,\n\
\tvalid_cache = %d,\n\
\trotate_state = %d,\n\
\tframeset_capacity = %d,\n\
\tframeset_mode = [[%s]],\n\
\tframeset_counter = %d,\n\
\tframeset_current = %d,\n\
\textrefc_framesets = %d,\n\
\textrefc_instances = %d,\n\
\textrefc_attachments = %d,\n\
\textrefc_links = %d,\n\
\tstorage_source = [[%s]],\n\
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
(int) src->last_updated,
(int) src->lifetime,
(int) src->cellid,
(int) src->valid_cache,
(int) src->rotate_state,
(int) src->frameset_meta.capacity,
lut_framemode(src->frameset_meta.mode),
(int) src->frameset_meta.counter,
(int) src->frameset_meta.current,
(int) src->extrefc.framesets,
(int) src->extrefc.instances,
(int) src->extrefc.attachments,
(int) src->extrefc.links,
(src->vstore->txmapped && src->vstore->vinf.text.source) ?
	src->vstore->vinf.text.source : "unknown",
(int) src->vstore->vinf.text.s_raw,
(int) src->vstore->w,
(int) src->vstore->h,
(int) src->vstore->bpp,
(int) src->program,
lut_txmode(src->vstore->txu),
lut_txmode(src->vstore->txv),
arcan_shader_lookuptag(src->program),
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
vobj.glstore_refc = %d;\n", src->vstore->vinf.text.glid,
			src->vstore->refcount);
	} else {
		fprintf_float(dst, "vobj.glstore_col = {", src->vstore->vinf.col.r, ", ");
		fprintf_float(dst, "", src->vstore->vinf.col.g, ", ");
		fprintf_float(dst, "", src->vstore->vinf.col.b, "};\n");
	}

	for (size_t i = 0; i < src->frameset_meta.capacity; i++)
	{
		fprintf(dst, "vobj.frameset[%zu] = %"PRIxVOBJ";\n", i + 1,
			src->frameset[i] ? src->frameset[i]->cellid : ARCAN_EID);
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
\t\tmsasamples = %d,\n\
\t\tticks = %lld,\n\
\t\tdefault_vitemlim = %d,\n\
\t\timageproc = %d,\n\
\t\tscalemode = %d,\n\
\t\tfiltermode = %d,\n\
\t};\n\
\tvcontexts = {};\
};\n\
", disp->width, disp->height, disp->conservative ? 1 : 0,
	(int)disp->msasamples, (long long int)disp->c_ticks,
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
			if (FL_TEST(&(ctx->vitems_pool[i]), FL_INUSE))
				continue;

			dump_vobject(dst, ctx->vitems_pool + i);
			fprintf(dst, "\
vobj.cellid_translated = %ld;\n\
ctx.vobjs[vobj.cellid] = vobj;\n", (long int)vid_toluavid(i));
		}

/* missing, rendertarget dump */
		fprintf(dst,"table.insert(restbl.vcontexts, ctx);");
		cctx--;
	}

	if (benchdata.bench_enabled){
		size_t bsz = sizeof(benchdata.ticktime)  / sizeof(benchdata.ticktime[0]);
		size_t fsz = sizeof(benchdata.frametime) / sizeof(benchdata.frametime[0]);
		size_t csz = sizeof(benchdata.framecost) / sizeof(benchdata.framecost[0]);

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

#ifndef _WIN32
#include <poll.h>
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
#endif

