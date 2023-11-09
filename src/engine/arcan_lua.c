/*
 * Copyright: Björn Ståhl
 * License: GPLv2+, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * LWA changes:
 *  1. split target_message into a special form for LWA
 *  2. add an target_updatehandler for WORLDID that tracks a callback
 *     handler for the subseg_ev implementation.
 *  3. map in the BCHUNK hints at least
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

#define arcan_luactx lua_State
#include "arcan_hmeta.h"
#include <lualib.h>
#include <lauxlib.h>

#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

#include "arcan_lua.h"
#include "alt/types.h"
#include "alt/support.h"
#include "alt/nbio.h"
#include "alt/trace.h"

/*
 * tradeoff (extra branch + loss in precision vs. assymetry and UB)
 */
#define abs( x ) ( abs( (x) == INT_MIN ? ((x)+1) : x ) )

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
#define arcan_fatal(...) do { alt_fatal( __VA_ARGS__); } while(0)

/*
 * ETRACE is used in stead of a normal return and is used to both track
 * non-fatal non-warning script invocation errors and to check for
 * unbalanced stacks.
 * Example:
 * static int lasttop = 0;
 * define LUA_TRACE(fsym) lasttop = lua_gettop(ctx);
 * define LUA_ETRACE(fsym, reason, argc){fprintf(stdout, "%s, %d\n",
		fsym, (int)(lasttop - lua_gettop(ctx) + argc)); return argc;}
 *
 * Other example is measuring calls that are particularly slow to find
 * blocking issues:
 * #define LUA_TRACE(fsym) long long ts_in = arcan_timemillis();
 * #define LUA_ETRACE(fsym, reason, argc){\
 *  if (arcan_timemillis() - ts_in > 2){\
 *    fprintf(stderr, "slow: %s, %lld\n", fsym, arcan_timemillis() - ts_in);\
 *  return argc;\
 * }
 */
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

#ifndef CONST_DISCOVER_PASSIVE
#define CONST_DISCOVER_PASSIVE 1
#endif

#ifndef CONST_DISCOVER_SWEEP
#define CONST_DISCOVER_SWEEP 2
#endif

#ifndef CONST_DISCOVER_BROADCAST
#define CONST_DISCOVER_BROADCAST 3
#endif

#ifndef CONST_DISCOVER_DIRECTORY
#define CONST_DISCOVER_DIRECTORY 4
#endif

#ifndef CONST_DISCOVER_TEST
#define CONST_DISCOVER_TEST 8
#endif

#ifndef CONST_TRUST_KNOWN
#define CONST_TRUST_KNOWN 11
#endif

#ifndef CONST_TRUST_PERMIT_UNKNOWN
#define CONST_TRUST_PERMIT_UNKNOWN 12
#endif

#ifndef CONST_TRUST_TRANSITIVE
#define CONST_TRUST_TRANSITIVE 13
#endif

#ifndef CONST_ANCHORHINT_SEGMENT
#define CONST_ANCHORHINT_SEGMENT 10
#endif

#ifndef CONST_ANCHORHINT_EXTERNAL
#define CONST_ANCHORHINT_EXTERNAL 11
#endif

#ifndef CONST_ANCHORHINT_PROXY
#define CONST_ANCHORHINT_PROXY 12
#endif

#ifndef CONST_ANCHORHINT_PROXY_EXTERNAL
#define CONST_ANCHORHINT_PROXY_EXTERNAL 13
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
static const int ANCHORHINT_SEGMENT = CONST_ANCHORHINT_SEGMENT;
static const int ANCHORHINT_EXTERNAL = CONST_ANCHORHINT_EXTERNAL;
static const int ANCHORHINT_PROXY = CONST_ANCHORHINT_PROXY;
static const int ANCHORHINT_PROXY_EXTERNAL = CONST_ANCHORHINT_PROXY_EXTERNAL;

#define DBHANDLE arcan_db_get_shared(NULL)

static struct {
	struct nonblock_io rawres;

	unsigned char grab;

/* limits themename + identifier to this length
 * will be modified in when calling into lua */
	char* prefix_buf;
	size_t prefix_ofs;

	struct arcan_extevent* last_segreq;
	char* pending_socket_label;
	int pending_socket_descr;

	const char** last_argv;
	lua_State* last_ctx;
	void (*error_hook)(lua_State*, lua_Debug*);

/* used by arcan_lwa to attach a handler for WORLDID display events */
	intptr_t worldid_tag;

	size_t last_clock;

} luactx = {0};

extern char* _n_strdup(const char* instr, const char* alt);
static const char* fsrvtos(enum ARCAN_SEGID ink);
static bool tgtevent(arcan_vobj_id dst, arcan_event ev);
static int alua_exposefuncs(lua_State* ctx, unsigned char debugfuncs);
static bool stack_to_uiarray(lua_State* ctx,
	int memtype, unsigned** dst, size_t* n, size_t count);
static bool stack_to_farray(lua_State* ctx,
	int memtype, float** dst, size_t* n, size_t count);

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

/* slightly more flexible argument management, just find the first callback */
static intptr_t find_lua_callback(lua_State* ctx)
{
	int nargs = lua_gettop(ctx);

	for (size_t i = 1; i <= nargs; i++)
		if (lua_isfunction(ctx, i) && !lua_iscfunction(ctx, i)){
			lua_pushvalue(ctx, i);
			intptr_t ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
			return ref;
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
	if (lua_debug_level > 2)
		arcan_warning("\x1b[1m %s: alloc(%s) => %"PRIxVOBJ")\x1b[39m\x1b[0m\n",
			luaL_lastcaller(ctx), sym, id + lua_vid_base);
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
		char* fname = arcan_expand_resource("arcan.coverage", RESOURCE_SYS_DEBUG);

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

const char* arcan_lua_crash_source(struct arcan_luactx* ctx)
{
	return alt_trace_crash_source(NULL);
}

static arcan_vobj_id luaL_checkaid(lua_State* ctx, int num)
{
	return luaL_checknumber(ctx, num);
}

static void lua_pushvid(lua_State* ctx, arcan_vobj_id id)
{
	if (id != ARCAN_EID && id != ARCAN_VIDEO_WORLDID)
		id += lua_vid_base;

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

/* The places in _lua.c that calls this function should probably have a better
 * handover as this incurs additional and almost always unnecessary strlen
 * calls. To do that:
 *
 * lua_pushlstring(L, field, fsz),
 * lua_rawget(L, ind)
 */
static const char* intblstr_sz(
	lua_State* ctx, int ind, const char* field, size_t fsz)
{
	lua_getfield(ctx, ind, field);
	const char* rv = lua_tostring(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}
#define intblstr(L, I, F) intblstr_sz(L, (I), (F), (sizeof(F)/sizeof(char))-1)

static float intblfloat_sz(lua_State* ctx, int ind, const char* field, size_t fsz)
{
	lua_getfield(ctx, ind, field);
	float rv = lua_tonumber(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}
#define intblfloat(L, I, F) intblfloat_sz(L, (I), (F), (sizeof(F)/sizeof(char))-1)

static int intblint_sz(lua_State* ctx, int ind, const char* field, size_t fsz)
{
	lua_getfield(ctx, ind, field);
	int rv = lua_tointeger(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}
#define intblint(L, I, F) intblint_sz(L, (I), (F), (sizeof(F)/sizeof(char))-1)

static bool intblbool_sz(lua_State* ctx, int ind, const char* field, size_t fsz)
{
	lua_getfield(ctx, ind, field);
	bool rv = lua_toboolean(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}
#define intblbool(L, I, F) intblbool_sz(L, (I), (F), (sizeof(F)/sizeof(char))-1)

static char* findresource(
	const char* arg, enum arcan_namespaces space, enum resource_type type)
{
	char* res = arcan_find_resource(arg, space, type, NULL);
/* since this is invoked extremely frequently and is involved in file-system
 * related stalls, maybe a sort of caching mechanism should be implemented
 * (invalidate / refill every N ticks or have a flag to side-step it -- as a lot
 * of resources are quite static and the rest of the API have to handle missing
 * or bad resources anyhow, we also know which subdirectories to attach
 * to OS specific event monitoring effects */

	if (lua_debug_level){
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
	if (!nticks)
		return;

	arcan_lua_setglobalint(ctx, "CLOCK", global);
	luactx.last_clock = global;

/* Many applications misused the callback handler, ignoring the nticks and
 * global fields causing timed tasks to drift more than desired. Switch to
 * have one preferred 'batched' and then one where we emit each tick */
	if (alt_lookup_entry(ctx, "clock_pulse_batch", 17)){
		TRACE_MARK_ENTER("scripting", "clock-pulse", TRACE_SYS_DEFAULT, global, nticks, "digital");
			lua_pushnumber(ctx, global);
			lua_pushnumber(ctx, nticks);
			alt_call(ctx, CB_SOURCE_NONE, 0, 2, 0, LINE_TAG":clock_pulse_batch");
		TRACE_MARK_EXIT("scripting", "clock-pulse", TRACE_SYS_DEFAULT, global, nticks, "digital");
		return;
	}

	while (nticks){
		nticks--;
		if (!alt_lookup_entry(ctx, "clock_pulse", 11))
			break;

		TRACE_MARK_ENTER("scripting", "clock-pulse", TRACE_SYS_DEFAULT, global, 0, "digital");
			lua_pushnumber(ctx, global);
			lua_pushnumber(ctx, 1);
			alt_call(ctx, CB_SOURCE_NONE, 0, 2, 0, LINE_TAG":clock_pulse");
		TRACE_MARK_EXIT("scripting", "clock-pulse", TRACE_SYS_DEFAULT, global, 0, "digital");
	}

/* trace job finished? unpack into table of tables */
	alt_trace_finish(ctx);
}

char* arcan_lua_main(lua_State* ctx, const char* inp, bool file)
{
	bool fail = false;

	if (file){
		fail = alua_doresolve(ctx, inp) != 0;
	}
	else
		fail = luaL_dofile(ctx, inp) == 1;

	if (fail){
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

	if (!alt_lookup_entry(ctx, "adopt", sizeof("adopt")-1)){
		arcan_warning("target appl lacks an _adopt handler\n");
		return false;
	}

	struct arcan_frameserver* res =
		platform_launch_listen_external(cp,
		key, -1, ARCAN_SHM_UMASK, 32, 32, LUA_NOREF
	);

	if (!res){
		arcan_warning("couldn't listen on connection point (%s)\n", cp);
		return false;
	}

	lua_pushvid(ctx, res->vid);
	lua_pushliteral(ctx, "_stdin");
	lua_pushliteral(ctx, "");
	lua_pushvid(ctx, ARCAN_EID);
	lua_pushboolean(ctx, true);

	alt_call(ctx, CB_SOURCE_NONE, 0, 5, 1, LINE_TAG":adopt");
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
	int tc = arcan_conductor_reset_count(false);

/* three: forward to adopt function (or delete) */
	for (count = 0; count < n_fsrv; count++){
		arcan_vobject* vobj = arcan_video_getobject(ids[count]);
		if (!vobj || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			continue;

		arcan_frameserver* fsrv = vobj->feed.state.ptr;
		fsrv->tag = LUA_NOREF;

		bool delete = true;

/* use this to determine if the frameserver was created in the appl entry
 * and thus should not be exposed as an adopt handler */
		if (fsrv->desc.recovery_tick == tc)
			continue;

		if (alt_lookup_entry(ctx, "adopt", sizeof("adopt") - 1) &&
			arcan_video_getobject(ids[count]) != NULL){
			lua_pushvid(ctx, vobj->cellid);
			lua_pushstring(ctx, fsrvtos(fsrv->segid));
			lua_pushstring(ctx, fsrv->title);
			lua_pushvid(ctx, fsrv->parent.vid);
			lua_pushboolean(ctx, count < n_fsrv-1);

			alt_call(ctx, CB_SOURCE_NONE, 0, 5, 1, LINE_TAG":adopt");

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
					.fsrv.fmt_fl =
						(fsrv->desc.hints & SHMIF_RHINT_ORIGO_LL) |
						(fsrv->desc.hints & SHMIF_RHINT_TPACK)
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

static bool validblendmode(int m)
{
	return
		m == BLEND_NONE || m == BLEND_ADD || m == BLEND_SUB ||
		m == BLEND_MULTIPLY || m == BLEND_NORMAL || m == BLEND_FORCE ||
		m == BLEND_PREMUL;
}

static int zapresource(lua_State* ctx)
{
	LUA_TRACE("zap_resource");

	const char* srcpath = luaL_checkstring(ctx, 1);
	char* path = findresource(srcpath,
		RESOURCE_APPL_TEMP | RESOURCE_NS_USER, ARES_FILE);

	if (path && unlink(path) != -1)
		lua_pushboolean(ctx, true);
	else
		lua_pushboolean(ctx, false);

	arcan_mem_free(path);

	LUA_ETRACE("zap_resource", NULL, 1);
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
		luactx.rawres.eofm = false;
	}

	char* path = findresource(
		luaL_checkstring(ctx, 1), DEFAULT_USERMASK, ARES_FILE | ARES_RDONLY);

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

	luactx.rawres.lfstrip = true;
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

static int funtable(lua_State* ctx, uint32_t kind)
{
	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	lua_pushliteral(ctx, "kind");
	lua_pushnumber(ctx, kind);
	lua_rawset(ctx, top);

	return top;
}

static const char flt_alpha[] = "abcdefghijklmnopqrstuvwxyz-_";
static const char flt_chunkfn[] = "abcdefghijklmnopqrstuvwxyz1234567890;*";
static const char flt_alphanum[] = "abcdefghijklmnopqrstuvxwyz-0123456789-_";
static const char flt_Alphanum[] = "abcdefghijklmnopqrstuvxwyz-0123456789-_"
	"ABCDEFGHIJKLMNOPQRSTUVWXYZ";
static const char flt_Alpha[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
	"abcdefghijklmnopqrstuvwxyz";
static const char flt_num[] = "0123456789_-";
static const char flt_chint[] = "abcdefhijklmnopqrstuvwyz:1234567890";

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

	for (; inmsg[i] != '\0' && i < ulim; i++){
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

static int readrawresource(lua_State* ctx)
{
	LUA_TRACE("read_rawresource");

	if (luactx.rawres.eofm){
		LUA_ETRACE("read_rawresource", NULL, 0);
	}

	if (luactx.rawres.fd <= 0){
		LUA_ETRACE("read_rawresource", "no open file", 0);
	}

	int n = alt_nbio_process_read(ctx, &luactx.rawres, false);
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
		luactx.rawres.eofm = false;
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

static int loadimage(lua_State* ctx)
{
	LUA_TRACE("load_image");

	arcan_vobj_id id = ARCAN_EID;
	const char* srcstr = luaL_checkstring(ctx, 1);
	char* path = findresource(srcstr,
		DEFAULT_USERMASK, ARES_FILE | ARES_RDONLY);

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

	const char* srcstr = luaL_checkstring(ctx, 1);
	char* path = findresource(srcstr,
		DEFAULT_USERMASK, ARES_FILE | ARES_RDONLY);

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
	LUA_TRACE("image_loaded");
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);

	lua_pushnumber(ctx, vobj->feed.state.tag == ARCAN_TAG_IMAGE);
	LUA_ETRACE("image_loaded", NULL, 1);
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
	unsigned left[4];
	int mask = luaL_optnumber(ctx, 2, 0);

	arcan_video_zaptransform(id, mask, left);
	lua_pushnumber(ctx, left[0]);
	lua_pushnumber(ctx, left[1]);
	lua_pushnumber(ctx, left[2]);
	lua_pushnumber(ctx, left[3]);
	LUA_ETRACE("reset_image_transform", NULL, 4);
}

static int instanttransform(lua_State* ctx)
{
	LUA_TRACE("instant_image_transform");
	arcan_vobj_id id = luaL_checkvid(ctx, 1, NULL);

	int mask = 0;
	bool last = false;
	bool all = false;

	if (lua_isnumber(ctx, 2))
		mask = lua_tonumber(ctx, 2);

/* this is an extreme corner case mostly to be avoided except for really rare
 * circumstances - and the API mapping is subsequently legacy/hack and the
 * preferred form is
 *  [vid, num]
 */
	else if (lua_isboolean(ctx, 2)){
		last = lua_toboolean(ctx, 2);
		all = luaL_optbnumber(ctx, 3, false);
	}

	int method = TAG_TRANSFORM_SKIP;
	if (last)
		method = TAG_TRANSFORM_LAST;
	if (all)
		method = TAG_TRANSFORM_ALL;

	arcan_video_instanttransform(id, mask, method);
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
	bool nosynch = false;

	arcan_vobj_id did = lua_type(ctx, 5) ==
		LUA_TNUMBER ? luaL_checkvid(ctx, 5, NULL) : ARCAN_EID;

	if (lua_type(ctx, 5) == LUA_TBOOLEAN)
		nosynch = lua_toboolean(ctx, 5);
	else if (lua_type(ctx, 6) == LUA_TBOOLEAN)
		nosynch = lua_toboolean(ctx, 6);

	if (width == 0 || width > MAX_SURFACEW || height == 0|| height > MAX_SURFACEH)
		arcan_fatal("resample_image(), illegal dimensions"
			" requested (%d:%d x %d:%d)\n",
			width, MAX_SURFACEW, height, MAX_SURFACEH
		);

	agp_shader_id osh = vobj->program;
	if (ARCAN_OK != arcan_video_setprogram(sid, shid))
		arcan_warning("arcan_video_setprogram(%d, %d) -- couldn't set shader,"
			"invalid vobj or shader id specified.\n", sid, shid);
	else {
		arcan_video_resampleobject(sid, did, width, height, shid, nosynch);
		vobj->program = osh;
	}

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

		ssize_t view_w = luaL_optnumber(ctx, 4, w);
		ssize_t view_h = luaL_optnumber(ctx, 5, h);
		ssize_t x = luaL_optnumber(ctx, 6, 0);
		ssize_t y = luaL_optnumber(ctx, 7, 0);

		if (!rtgt->inv_y)
			build_orthographic_matrix(rtgt->projection, x, w, y, h, 0, 1);
		else
			build_orthographic_matrix(rtgt->projection, x, w, h, y, 0, 1);

		agp_rendertarget_viewport(rtgt->art, x, y, x+view_w, y+view_h);
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
		rtgt -= lua_vid_base;

	uint16_t rv = 0;
	arcan_video_maxorder(rtgt, &rv);
	lua_pushnumber(ctx, rv);
	LUA_ETRACE("max_current_image_order", NULL, 1);
}

static void massopacity(
	lua_State* ctx, float val, const char* caller)
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

	enum arcan_blendfunc mode =
		abs((int)luaL_optnumber(ctx, 2, BLEND_FORCE));

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

	intptr_t ref = find_lua_callback(ctx);

	if (lua_isnumber(ctx, 2))
		arcan_audio_play(id, true, luaL_checknumber(ctx, 2), ref);
	else
		arcan_audio_play(id, false, 0.0, ref);

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

	if (lua_type(ctx, -1) == LUA_TTABLE){
/* table to buffer */
		float* buf;
		int n_ch = 2;
		int ofs = 1;
		const char* fmt = "stereo";
		int rate = 48000;

		if (lua_type(ctx, ofs) == LUA_TNUMBER){
			n_ch = lua_tonumber(ctx, ofs++);
		}
		if (lua_type(ctx, ofs) == LUA_TNUMBER){
			rate = lua_tonumber(ctx, ofs++);
		}
		if (lua_type(ctx, ofs) == LUA_TSTRING){
			fmt = lua_tostring(ctx, ofs++);
		}

		size_t n = 0;
		if (!stack_to_farray(ctx, ARCAN_MEM_ABUFFER, &buf, &n, 0)){
			lua_pushaid(ctx, ARCAN_EID);
		}
		else
			lua_pushaid(ctx,
				arcan_audio_sample_buffer(buf, n, n_ch, rate, fmt));

		LUA_ETRACE("load_asample", NULL, 1);
	}

	const char* rname = luaL_checkstring(ctx, 1);
	char* resource = findresource(rname,
		DEFAULT_USERMASK, ARES_FILE | ARES_RDONLY);
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

	const char* vprog = luaL_optstring(ctx, 1, NULL);
	const char* fprog = luaL_optstring(ctx, 2, NULL);
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
		lua_pushliteral(ctx, "static");
	else
		switch(state->tag){
		case ARCAN_TAG_FRAMESERV:
			lua_pushliteral(ctx, "frameserver");
		break;

		case ARCAN_TAG_3DOBJ:
			lua_pushliteral(ctx, "3d object");
		break;

		case ARCAN_TAG_ASYNCIMGLD:
		case ARCAN_TAG_ASYNCIMGRD:
			lua_pushliteral(ctx, "asynchronous state");
		break;

		case ARCAN_TAG_3DCAMERA:
			lua_pushliteral(ctx, "3d camera");
		break;

		default:
			lua_pushliteral(ctx, "unknown");
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

	if (lua_gettop(ctx) == 1){
		lua_pushnumber(ctx, oldshid);
		LUA_ETRACE("image_shader", NULL, 1);
	}

/* identifier can either be a number or shared name */
	agp_shader_id shid =
		lua_type(ctx, 2) == LUA_TSTRING ?
			agp_shader_lookup(luaL_checkstring(ctx, 2)) :
			luaL_checknumber(ctx, 2);

	if (!agp_shader_valid(shid)){
		lua_pushnumber(ctx, oldshid);
		LUA_ETRACE("image_shader", "shader-id is not a valid shader", 1);
	}

	if (lua_type(ctx, 3) != LUA_TNUMBER){
		lua_pushnumber(ctx, oldshid);
		arcan_video_setprogram(id, shid);
		LUA_ETRACE("image_shader", NULL, 1);
	}

/* long form, use attribute to modify rendertarget shader state */
	int num = luaL_checkint(ctx, 3);
	struct rendertarget* rtgt = arcan_vint_findrt(vobj);

/* this is somewhat dangerous as the third argument form was added rather late
 * and might trigger code that has previously (and erroneously) used extra
 * arguments but better to rip the band-aid */
	if (!rtgt)
		arcan_fatal(
			"image_shader(%"PRIxVOBJ") -- vid does not refer to a rendertarget\n", id);

	rtgt->force_shid = false;
	lua_pushnumber(ctx, rtgt->shid);

	if (num == 1){
		rtgt->shid = shid;
	}
	else if (num == 2){
		rtgt->force_shid = true;
		rtgt->shid = shid;
	}
	else{
		LUA_ETRACE("image_shader", "invalid attribute value", 1);
	}

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
	int clipm = luaL_optint(ctx, 2, ARCAN_CLIP_ON);
	if (clipm != ARCAN_CLIP_ON && clipm != ARCAN_CLIP_SHALLOW){
		arcan_fatal("image_clip_on() - invalid clipping mode (%d)\n", clipm);
	}
	arcan_video_setclip(id, clipm);

	if (lua_type(ctx, 3) == LUA_TNUMBER){
		arcan_vobj_id did = luaL_checkvid(ctx, 3, NULL);
		arcan_video_clipto(id, did);
	}

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
		res -= lua_vid_base;

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
		int card = luaL_optnumber(ctx, 2, -1);
		int swap = luaL_optbnumber(ctx, 3, 0);
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
			if (lua_debug_level)
				arcan_verify_namespaces(true);

			arcan_fatal("system_collapse(), "
				"failed to load appl (%s), reason: %s\n", switch_appl, errmsg);
		}
#define arcan_fatal(...) do { alt_fatal( __VA_ARGS__); } while(0)
	}

/*
 * defined in engine/arcan_main.c, rather than terminating directly
 * we'll longjmp to this and hopefully the engine can switch scripts
 * or take similar user-defined action.
 */
	extern jmp_buf arcanmain_recover_state;

	longjmp(arcanmain_recover_state,
		luaL_optbnumber(ctx, 2, 0) ?
		ARCAN_LUA_SWITCH_APPL_NOADOPT : ARCAN_LUA_SWITCH_APPL
	);

	LUA_ETRACE("system_collapse", NULL, 0);
}

static int syssnap(lua_State* ctx)
{
	LUA_TRACE("system_snapshot");

	const char* instr = luaL_checkstring(ctx, 1);
	char* fname = findresource(instr, RESOURCE_APPL_TEMP, O_WRONLY);

	if (fname){
		arcan_warning("system_statesnap(), "
		"refuses to overwrite existing file (%s));\n", fname);
		arcan_mem_free(fname);

		LUA_ETRACE("system_snapshot", "file exists", 0);
	}

	fname = arcan_expand_resource(
		luaL_checkstring(ctx, 1), RESOURCE_APPL_TEMP);
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
		char* fname = findresource(
			workbuf, MODULE_USERMASK, ARES_FILE | ARES_RDONLY);
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

	char* fname = findresource(instr,
		CAREFUL_USERMASK, ARES_RDONLY | ARES_FILE);
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

/* this means that target-lock is blocked in the preroll stage */
	if (!fsrv->flags.activated){
		fsrv->flags.activated = 2;
		LUA_ETRACE("suspend_target", NULL, 0);
	}

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

	if (fsrv->flags.activated == 2){
		ev.tgt.kind = TARGET_COMMAND_ACTIVATE;
		fsrv->flags.activated = 1;
	}
	else if (!rsusp)
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
		lua_pushvid(ctx, ARCAN_EID);
		lua_pushaid(ctx, ARCAN_EID);
		LUA_ETRACE("launch_aveed", "invalid mode", 2);
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

	lua_pushnumber(ctx, mvctx->cookie);
	LUA_ETRACE("launch_avfeed", NULL, 4);
}

static int launchdecode(lua_State* ctx)
{
	LUA_TRACE("launch_decode");

	char* fname = NULL;
	struct arcan_frameserver* mvctx;
	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = "decode"
	};

	if (!fsrv_ok){
		LUA_ETRACE("launch_decode", "frameservers build-time blocked", 0);
	}

	intptr_t ref = find_lua_callback(ctx);

/* Change >= 0.6 - nil first argument is now permitted in order to
 * deal with the proto=... options. Next change here would be to move
 * the argument to require a url like scheme for the special resources */
	if (lua_type(ctx, 1) == LUA_TNIL){
		args.args.builtin.resource = luaL_checkstring(ctx, 2);
		goto finish;
	}

	const char* resource = luaL_checkstring(ctx, 1);
	const char* optarg = "";
	if (lua_type(ctx, 2) == LUA_TSTRING){
		optarg = lua_tostring(ctx, 2);
	}

	if (is_special_res(resource))
		fname = strdup(resource);
/* resolve in the resource namespace unless some special pattern */
	else {
		fname = findresource(resource, DEFAULT_USERMASK, ARES_FILE | ARES_RDONLY);
		if (!fname)
			LUA_ETRACE("launch_decode", "couldn't resolve resource", 0);

/* ugly legacy, swap : to \t - also need a scratch string for conc. */
		colon_escape(fname);

/* prepend option string */
		size_t flen = strlen(fname);
		size_t optlen = strlen(optarg);
		size_t maxlen = flen + optlen + 6 + 1;
		char* ol = arcan_alloc_mem(
			maxlen, ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);
		snprintf(ol, maxlen,
			"%s%sfile=%s", optarg, optlen > 0 ? ":" : "", fname);
		arcan_mem_free(fname);
		fname = ol;
	}
	args.args.builtin.resource = fname;

finish:
	mvctx = platform_launch_fork(&args, ref);
	arcan_vobj_id vid = ARCAN_EID;
	arcan_aobj_id aid = ARCAN_EID;

	if (mvctx){
		arcan_video_objectopacity(mvctx->vid, 0.0, 0);
		vid = mvctx->vid;
		aid = mvctx->aid;
	}

	lua_pushvid(ctx, vid);
	lua_pushaid(ctx, aid);
	trace_allocation(ctx, "launch_decode", mvctx->vid);
	arcan_mem_free(fname);

	LUA_ETRACE("launch_decode", NULL, 2);
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

	lua_pushliteral(ctx, "distortion");
	lua_createtable(ctx, 0, 4);
	int ttop = lua_gettop(ctx);
	for (size_t i = 0; i < 4; i++){
		lua_pushnumber(ctx, i+1);
		lua_pushnumber(ctx, md.distortion[i]);
		lua_rawset(ctx, ttop);
	}
	lua_rawset(ctx, top);

	lua_pushliteral(ctx, "abberation");
	lua_createtable(ctx, 0, 4);
	ttop = lua_gettop(ctx);
	for (size_t i = 0; i < 4; i++){
		lua_pushnumber(ctx, i+1);
		lua_pushnumber(ctx, md.abberation[i]);
		lua_rawset(ctx, ttop);
	}
	lua_rawset(ctx, top);

	lua_pushliteral(ctx, "projection_left");
	lua_createtable(ctx, 0, 16);
	ttop = lua_gettop(ctx);
	for (size_t i = 0; i < 16; i++){
		lua_pushnumber(ctx, i+1);
		lua_pushnumber(ctx, md.projection_left[i]);
		lua_rawset(ctx, ttop);
	}
	lua_rawset(ctx, top);

	lua_pushliteral(ctx, "projection_right");
	lua_createtable(ctx, 0, 16);
	ttop = lua_gettop(ctx);
	for (size_t i = 0; i < 16; i++){
		lua_pushnumber(ctx, i+1);
		lua_pushnumber(ctx, md.projection_right[i]);
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

static void get_utf8(const char* instr, uint8_t dst[5])
{
	if (!instr){
		dst[0] = dst[1] = dst[2] = dst[3] = dst[4] = 0;
		return;
	}

	size_t len = strlen(instr);
	memcpy(dst, instr, len <= 4 ? len : 4);
}

#ifdef ARCAN_LWA
static int lwamessage(
	lua_State* ctx, size_t len, const char* msg, struct subseg_output* sseg)
{
	arcan_event ev =
	{
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_MESSAGE
	};

	uint32_t state = 0, codepoint = 0;
	const char* outs = msg;
	size_t maxlen = sizeof(ev.ext.message.data) - 1;

/* utf8- point aligned against block size */
	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i <= maxlen - 1; i++){
			if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(msg[i])))
				lastok = i;

			if (i != lastok){
				if (0 == i)
					return false;
			}
		}

		memcpy(ev.ext.message.data, outs, lastok);
		ev.ext.message.data[lastok] = '\0';
		len -= lastok;
		outs += lastok;
		if (len)
			ev.ext.message.multipart = 1;
		else
			ev.ext.message.multipart = 0;
		platform_lwa_targetevent(sseg, &ev);
	}

/* flush remaining */
	if (len){
		snprintf((char*)ev.ext.message.data, maxlen, "%s", outs);
		ev.ext.message.multipart = 0;
		platform_lwa_targetevent(sseg, &ev);
	}
	return 0;
}
#endif

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
	arcan_frameserver* fsrv = NULL;

	size_t len = 0;
	const char* msg = luaL_checklstring(ctx, tblind, &len);

/* LWA needs to use the other direction, i.e. EVENT_EXTERNAL */
#ifdef ARCAN_LWA
	struct subseg_output* sseg = NULL;
	if (vid == ARCAN_VIDEO_WORLDID){
		return lwamessage(ctx, len, msg, NULL);
	}
	else if (vstate && vstate->tag == ARCAN_TAG_LWA){
		return lwamessage(ctx, len, msg, vstate->ptr);
	}
#endif

	if (vstate && vstate->tag == ARCAN_TAG_FRAMESERV){
		fsrv = vstate->ptr;
	}

	if (!fsrv){
		lua_pushnumber(ctx, -1);
		LUA_ETRACE("message_target", "dst not a frameserver", 1);
	}

/* "strlen" + validate the entire message */
	uint32_t state = 0, codepoint = 0;
	while(msg[len])
		if (UTF8_REJECT == utf8_decode(&state, &codepoint,(uint8_t)(msg[len++]))){
			lua_pushnumber(ctx, -1);
			LUA_ETRACE("message_target", "invalid utf-8", 1);
		}

	if (state != UTF8_ACCEPT){
		lua_pushnumber(ctx, -1);
		LUA_ETRACE("message_trarget", "truncated utf-8", 1);
	}

	struct arcan_event ev =
	{
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_MESSAGE
	};
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

/* mark multipart */
		if (len - i){
			ev.tgt.ioevs[0].iv = 1;
		}

		if (ARCAN_OK != platform_fsrv_pushevent(fsrv, &ev)){
			lua_pushnumber(ctx, len);
			LUA_ETRACE("message_target", "truncation", 1);
		}

/* and step forward in our buffer */
		len -= i;
		msg += i;
	}

	ev.tgt.ioevs[0].iv = 0;
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

	struct arcan_frameserver* fsrv = vstate->ptr;

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

	if (intblbool(ctx, tblind, "eyes"))
		goto eyes;

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
	else if (strcmp(kindlbl, "eyes") == 0){
eyes:
		ev.io.kind = EVENT_IO_EYES;
		ev.io.devkind = EVENT_IDEVKIND_EYETRACKER;
		ev.io.datatype = EVENT_IDATATYPE_EYES;
		ev.io.input.eyes.head_pos[0] = intblfloat(ctx, tblind, "head_x");
		ev.io.input.eyes.head_pos[1] = intblfloat(ctx, tblind, "head_y");
		ev.io.input.eyes.head_pos[2] = intblfloat(ctx, tblind, "head_z");
		ev.io.input.eyes.head_ang[0] = intblfloat(ctx, tblind, "head_rx");
		ev.io.input.eyes.head_ang[1] = intblfloat(ctx, tblind, "head_ry");
		ev.io.input.eyes.head_ang[2] = intblfloat(ctx, tblind, "head_rz");
		ev.io.input.eyes.present = intblbool(ctx, tblind, "present");
		ev.io.input.eyes.gaze_x1 = intblfloat(ctx, tblind, "x1");
		ev.io.input.eyes.gaze_y1 = intblfloat(ctx, tblind, "y1");
		ev.io.input.eyes.gaze_x2 = intblfloat(ctx, tblind, "x2");
		ev.io.input.eyes.gaze_y2 = intblfloat(ctx, tblind, "y2");
		ev.io.input.eyes.blink_left = intblbool(ctx, tblind, "blink_left");
		ev.io.input.eyes.blink_right = intblbool(ctx, tblind, "blink_right");
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
			ev.io.input.digital.active = intblbool(ctx, tblind, "active");
			TRACE_MARK_ONESHOT("scripting", "target_input",
				TRACE_SYS_DEFAULT, fsrv->vid, ev.io.subid, "digital");
		}
	}
	else {
kinderr:
		arcan_warning("Script Warning: target_input(), unknown \"kind\""
			" field in table.\n");
		lua_pushnumber(ctx, false);
		return 1;
	}

/* There are more relevant error codes here that might be considered, such as
 * if it is a bad/broken client, the queue is full or the input type is being
 * masked as not being interesting. */
	lua_pushnumber(ctx, ARCAN_OK == platform_fsrv_pushevent( fsrv, &ev));
	LUA_ETRACE("target_input/input_target", NULL, 1);
}

static ssize_t lookup_idatatype_str(const char* str)
{
	if (strcmp(str, "analog") == 0)
		return EVENT_IDATATYPE_ANALOG;

	if (strcmp(str, "digital")  == 0)
		return EVENT_IDATATYPE_DIGITAL;

	if (strcmp(str, "translated")  == 0)
		return EVENT_IDATATYPE_TRANSLATED;

	if (strcmp(str, "touch")  == 0)
		return EVENT_IDATATYPE_TOUCH;

	if (strcmp(str, "eyes")  == 0)
		return EVENT_IDATATYPE_EYES;

	return -1;
}

static const char* lookup_idatatype(int type)
{
	switch(type){
		case EVENT_IDATATYPE_ANALOG:
			return "analog";
		case EVENT_IDATATYPE_DIGITAL:
			return "digital";
		case EVENT_IDATATYPE_TRANSLATED:
			return "translated";
		case EVENT_IDATATYPE_TOUCH:
			return "touch";
		case EVENT_IDATATYPE_EYES:
			return "eyes";
	default:
	break;
	}

	return NULL;
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

		lua_pushliteral(ctx, "cardid");
		lua_pushnumber(ctx, 0);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "displayid");
		lua_pushnumber(ctx, id);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "phy_width_mm");
		lua_pushnumber(ctx, modes[j].phy_width);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "phy_height_mm");
		lua_pushnumber(ctx, modes[j].phy_height);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "subpixel_layout");
		lua_pushstring(ctx, modes[j].subpixel ? modes[j].subpixel : "unknown");
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "dynamic");
		lua_pushboolean(ctx, modes[j].dynamic);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "primary");
		lua_pushboolean(ctx, modes[j].primary);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "modeid");
		lua_pushnumber(ctx, modes[j].id);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "width");
		lua_pushnumber(ctx, modes[j].width);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "height");
		lua_pushnumber(ctx, modes[j].height);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "refresh");
		lua_pushnumber(ctx, modes[j].refresh);
		lua_rawset(ctx, jtop);

		lua_pushliteral(ctx, "depth");
		lua_pushnumber(ctx, modes[j].depth);
		lua_rawset(ctx, jtop);

		lua_rawset(ctx, dtop); /* add to previously existing table */
	}
}

static void display_reset(lua_State* ctx, arcan_event* ev)
{
/* Special handling for LWA and for higher level platforms where there is an
 * outer window managing scheme that needs to resize. Since this is an exception
 * rather than the designed norm, this is something of an ugly afterthought.
 *
 * Have a 'default' implementation that simply tells the platform that we have
 * reset to a different window size, which should cascade. Allow it to be
 * overridden with a magic global.
 *
 * Furthermore send the 'try and reset display layout state' that is slightly
 * more useful in certain contexts (e.g. VT switch) via the normal applname_
 * path.
 */
	if (ev->vid.source == -1){

/* minor protection against bad displays */
		if (ev->vid.vppcm > 18.0){
			arcan_lua_setglobalint(ctx, "VPPCM", ev->vid.vppcm);
			arcan_lua_setglobalint(ctx, "HPPCM", ev->vid.vppcm);
		}

		lua_getglobal(ctx, "VRES_AUTORES");
		if (!lua_isfunction(ctx, -1) && ev->vid.width && ev->vid.height){
			lua_pop(ctx, 1);
			struct monitor_mode mode = {
				.width = ev->vid.width,
				.height = ev->vid.height
			};
			if (platform_video_specify_mode(ev->vid.displayid, mode)){
				arcan_lua_setglobalint(ctx, "VRESW", mode.width);
				arcan_lua_setglobalint(ctx, "VRESH", mode.height);
			}
		}
		else{
			lua_pushnumber(ctx, ev->vid.width);
			lua_pushnumber(ctx, ev->vid.height);
			lua_pushnumber(ctx, ev->vid.vppcm);
			lua_pushnumber(ctx, ev->vid.flags);
			lua_pushnumber(ctx, ev->vid.displayid);
			alt_call(ctx, CB_SOURCE_NONE, 0, 5, 0, LINE_TAG":VRES_AUTORES");
		}
	}
/* Same thing applies to fonts, but this is only really arcan_lwa */
#ifdef ARCAN_LWA
	else if (ev->vid.source == -2){
		lua_getglobal(ctx, "VRES_AUTOFONT");
		if (!lua_isfunction(ctx, -1))
			lua_pop(ctx, 1);
		else{
			lua_pushnumber(ctx, ev->vid.vppcm);
			lua_pushnumber(ctx, ev->vid.width);
			lua_pushnumber(ctx, ev->vid.displayid);
			alt_call(ctx, CB_SOURCE_NONE, 0, 3, 0, LINE_TAG":VRES_AUTOFONT");
		}
	}
#endif

	if (!alt_lookup_entry(ctx, "display_state", sizeof("display_state")-1))
		return;

	lua_pushliteral(ctx, "reset");

	alt_call(ctx, CB_SOURCE_NONE, 0, 1, 0, LINE_TAG":display_state:reset");
}

static void display_added(lua_State* ctx, arcan_event* ev)
{
	if (!alt_lookup_entry(ctx, "display_state", sizeof("display_state")-1))
		return;

	lua_pushliteral(ctx, "added");
	lua_pushnumber(ctx, ev->vid.displayid);

	lua_createtable(ctx, 0, 3);
	int top = lua_gettop(ctx);
	lua_pushliteral(ctx, "ledctrl");
	lua_pushnumber(ctx, ev->vid.ledctrl);
	lua_rawset(ctx, top);
	lua_pushliteral(ctx, "ledind");
	lua_pushnumber(ctx, ev->vid.ledid);
	lua_rawset(ctx, top);
	lua_pushliteral(ctx, "card");
	lua_pushnumber(ctx, ev->vid.cardid);
	lua_rawset(ctx, top);

	alt_call(ctx, CB_SOURCE_NONE, 0, 3, 0, LINE_TAG":display_state:added");
}

static void display_changed(lua_State* ctx, arcan_event* ev)
{
	if (!alt_lookup_entry(ctx, "display_state", sizeof("display_state")-1))
		return;

	lua_pushliteral(ctx, "changed");
	alt_call(ctx, CB_SOURCE_NONE, 0, 1, 0, LINE_TAG":display_state:changed");
}

static void display_removed(lua_State* ctx, arcan_event* ev)
{
	if (!alt_lookup_entry(ctx, "display_state", sizeof("display_state")-1))
		return;

	lua_pushliteral(ctx, "removed");
	lua_pushnumber(ctx, ev->vid.displayid);
	alt_call(ctx, CB_SOURCE_NONE, 0, 2, 0, LINE_TAG":display_state:removed");
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
		tbldynstr(ctx, "segkind", fsrvtos(fsrv->segid), top);
		tblnum(ctx, "source_audio", aid, top);
		alt_call(ctx, CB_SOURCE_PREROLL, vid, 2, 0, LINE_TAG":frameserver:preroll");
	}

/* there is the possiblity of 'deferred' activation so that the WM
 * can control the sequence in which multiple clients are unlocked */
	if (fsrv->flags.activated == 0){
		fsrv->flags.activated = 1;
		tgtevent(vid, (arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_ACTIVATE
		});
	}
}

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

static void push_view(lua_State* ctx,
	struct arcan_extevent* ev, struct arcan_frameserver* fsrv, int top)
{
	tblbool(ctx, "invisible", ev->viewport.invisible != 0, top);
	tblbool(ctx, "focus", ev->viewport.focus != 0, top);
	tblbool(ctx, "anchor_edge", ev->viewport.anchor_edge != 0, top);
	tblbool(ctx, "anchor_pos", ev->viewport.anchor_pos != 0, top);
	tblbool(ctx, "embedded", ev->viewport.embedded != 0, top);
	tblnum(ctx, "rel_order", ev->viewport.order, top);
	tblnum(ctx, "rel_x", ev->viewport.x, top);
	tblnum(ctx, "rel_y", ev->viewport.y, top);
	tblnum(ctx, "anchor_w", ev->viewport.w, top);
	tblnum(ctx, "anchor_h",ev->viewport.h, top);
	tblnum(ctx, "edge", ev->viewport.edge, top);
	tblnum(ctx, "ext_id", ev->viewport.ext_id, top);
	tblbool(ctx, "scaled", ev->viewport.embedded == 2, top);
	tblbool(ctx, "hintfwd", ev->viewport.embedded == 3, top);

	lua_pushliteral(ctx, "border");
	lua_createtable(ctx, 4, 0);
	int top2 = lua_gettop(ctx);
	for (size_t i = 0; i < 4; i++){
		lua_pushnumber(ctx, i+1);
		lua_pushnumber(ctx, ev->viewport.border[i]);
		lua_rawset(ctx, top2);
	}
	lua_rawset(ctx, top);

/* We don't automatically translate the parent - child lookup. A reason
 * for this is that it is a possibly steep magnification (1 event to O(n))
 * lookup, but also that any WM that respects this hint needs the tracking
 * anyhow. */
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
	switch(ev->segreq.dir){
	case 1:
		tblstr(ctx, "split", "left", top);
	break;
	case 2:
		tblstr(ctx, "split", "right", top);
	break;
	case 3:
		tblstr(ctx, "split", "top", top);
	break;
	case 4:
		tblstr(ctx, "split", "bottom", top);
	break;
	case 5:
		tblstr(ctx, "position", "left", top);
	break;
	case 6:
		tblstr(ctx, "position", "right", top);
	break;
	case 7:
		tblstr(ctx, "position", "top", top);
	break;
	case 8:
		tblstr(ctx, "position", "bottom", top);
	break;
	case 9:
		tblstr(ctx, "position", "tab", top);
	break;
	case 10:
		tblstr(ctx, "position", "embed", top);
	break;
	case 11:
		tblstr(ctx, "position", "swallow", top);
	break;
	default:
	break;
	}

	tblnum(ctx, "parent", parent->cookie, top);
	tbldynstr(ctx, "segkind", fsrvtos(ev->segreq.kind), top);

	alt_call(ctx, CB_SOURCE_FRAMESERVER,
		ev->source, 2, 0, LINE_TAG":frameserver:segment_request");

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
	case EVENT_IDEVKIND_EYETRACKER: return "eyetracker";
	case EVENT_IDEVKIND_LEDCTRL: return "led";
	default:
		return "broken";
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

/*
 * Repack an ioevent into a table that will be added to the out stack,
 * primarly used for the normal appl_input callback, but may also come
 * nested from a frameserver.
 */
static void append_iotable(lua_State* ctx, arcan_ioevent* ev)
{
	int top = funtable(ctx, ev->kind);

	lua_pushliteral(ctx, "kind");
	if (ev->label[0] && ev->kind != EVENT_IO_STATUS &&
		ev->label[COUNT_OF(ev->label)-1] == '\0'){
		tbldynstr(ctx, "label", ev->label, top);
	}

	switch (ev->kind){
	case EVENT_IO_TOUCH:
		lua_pushliteral(ctx, "touch");
		lua_rawset(ctx, top);

		tblbool(ctx, "touch", true, top);
		tblnum(ctx, "devid", ev->devid, top);
		tblnum(ctx, "subid", ev->subid, top);
		tblnum(ctx, "pressure", ev->input.touch.pressure, top);
		tblbool(ctx, "active", ev->input.touch.active, top);
		tblnum(ctx, "size", ev->input.touch.size, top);
		tblnum(ctx, "x", ev->input.touch.x, top);
		tblnum(ctx, "y", ev->input.touch.y, top);
	break;

	case EVENT_IO_EYES:
		lua_pushliteral(ctx, "eyes");
		lua_rawset(ctx, top);

		tblbool(ctx, "eyes", true, top);
		tblnum(ctx, "devid", ev->devid, top);
		tblnum(ctx, "subid", ev->subid, top);
		tblnum(ctx, "head_x", ev->input.eyes.head_pos[0], top);
		tblnum(ctx, "head_y", ev->input.eyes.head_pos[1], top);
		tblnum(ctx, "head_z", ev->input.eyes.head_pos[1], top);
		tblnum(ctx, "head_rx", ev->input.eyes.head_ang[0], top);
		tblnum(ctx, "head_ry", ev->input.eyes.head_ang[1], top);
		tblnum(ctx, "head_rz", ev->input.eyes.head_ang[2], top);
		tblnum(ctx, "x1", ev->input.eyes.gaze_x1, top);
		tblnum(ctx, "y1", ev->input.eyes.gaze_y1, top);
		tblnum(ctx, "x2", ev->input.eyes.gaze_x2, top);
		tblnum(ctx, "y2", ev->input.eyes.gaze_y2, top);
		tblbool(ctx, "present", ev->input.eyes.present, top);
		tblbool(ctx, "blink_left", ev->input.eyes.blink_left, top);
		tblbool(ctx, "blink_right", ev->input.eyes.blink_right, top);
	break;

	case EVENT_IO_STATUS:{
		const char* lbl = platform_event_devlabel(ev->devid);
		lua_pushliteral(ctx, "status");
		lua_rawset(ctx, top);
		tblbool(ctx, "status", true, top);
		tblnum(ctx, "devid", ev->devid, top);
		tblnum(ctx, "subid", ev->subid, top);
		if (lbl)
			tbldynstr(ctx, "extlabel", lbl, top);

		tbldynstr(ctx, "devkind", kindstr(ev->input.status.devkind), top);
		tbldynstr(ctx, "label", ev->label, top);
		tblnum(ctx, "devref", ev->input.status.devref, top);
		switch(ev->input.status.domain){
		case 0: tblstr(ctx, "domain", "platform", top); break;
		case 1: tblstr(ctx, "domain", "led", top); break;
		default: tblstr(ctx, "domain", "unknown-report", top); break;
		}
		switch(ev->input.status.action){
		case EVENT_IDEV_ADDED:
			tblstr(ctx, "action", "added", top);
		break;
		case EVENT_IDEV_REMOVED:
			tblstr(ctx, "action", "removed", top);
		break;
		default:
			tblstr(ctx, "action", "blocked", top);
		break;
		}
	}
	break;

	case EVENT_IO_AXIS_MOVE:
		lua_pushliteral(ctx, "analog");
		lua_rawset(ctx, top);
		if (ev->devkind == EVENT_IDEVKIND_MOUSE){
			tblbool(ctx, "mouse", true, top);
			tblstr(ctx, "source", "mouse", top);
		}
		else
			tblstr(ctx, "source", "joystick", top);

		tblnum(ctx, "devid", ev->devid, top);
		tblnum(ctx, "subid", ev->subid, top);
		tblbool(ctx, "active", true, top);
		tblbool(ctx, "analog", true, top);
		tblbool(ctx, "relative", ev->input.analog.gotrel,top);

		lua_pushliteral(ctx, "samples");
		lua_createtable(ctx, ev->input.analog.nvalues, 0);
		int top2 = lua_gettop(ctx);
			for (size_t i = 0; i < ev->input.analog.nvalues; i++){
				lua_pushnumber(ctx, i + 1);
				lua_pushnumber(ctx, ev->input.analog.axisval[i]);
				lua_rawset(ctx, top2);
			}
		lua_rawset(ctx, top);
	break;

	case EVENT_IO_BUTTON:
		lua_pushliteral(ctx, "digital");
		lua_rawset(ctx, top);
		tblbool(ctx, "digital", true, top);

		if (ev->devkind == EVENT_IDEVKIND_KEYBOARD){
			tblbool(ctx, "translated", true, top);
			tblnum(ctx, "number", ev->input.translated.scancode, top);
			tblnum(ctx, "keysym", ev->input.translated.keysym, top);
			tblnum(ctx, "modifiers", ev->input.translated.modifiers, top);
			tblnum(ctx, "devid", ev->devid, top);
			tblnum(ctx, "subid", ev->subid, top);
			tbldynstr(ctx, "utf8", (char*)ev->input.translated.utf8, top);
			tblbool(ctx, "active", ev->input.translated.active, top);
			tblstr(ctx, "device", "translated", top);
			tblbool(ctx, "keyboard", true, top);
		}
		else if (ev->devkind == EVENT_IDEVKIND_MOUSE ||
			ev->devkind == EVENT_IDEVKIND_GAMEDEV){
			if (ev->devkind == EVENT_IDEVKIND_MOUSE){
				tblbool(ctx, "mouse", true, top);
				tblstr(ctx, "source", "mouse", top);
			}
			else {
				tblbool(ctx, "joystick", true, top);
				tblstr(ctx, "source", "joystick", top);
			}
			tblbool(ctx, "translated", false, top);
			tblnum(ctx, "devid", ev->devid, top);
			tblnum(ctx, "subid", ev->subid, top);
 			tblbool(ctx, "active", ev->input.digital.active, top);
		}
		else;
	break;

	default:
		lua_pushliteral(ctx, "unknown");
		lua_rawset(ctx, top);
		arcan_warning("Engine -> Script: "
			"ignoring IO event: %i\n",ev->kind);
	}
}

#ifdef ARCAN_LWA
static bool import_btype(arcan_luactx* L,
	int top, int reset, const char* key, int mode, int fd)
{
	struct nonblock_io* dst;

	tbldynstr(L, "kind", key, top);
	lua_pushstring(L, "io");
	fd = arcan_shmif_dupfd(fd, -1, false);
	if (alt_nbio_import(L, fd, mode, &dst, NULL)){
		lua_rawset(L, top);
		return true;
	}

	lua_settop(L, reset);
	return false;
}

void arcan_lwa_subseg_ev(
	arcan_luactx* ctx, arcan_vobj_id source, uintptr_t cb_tag, arcan_event* ev)
{
	int reset = lua_gettop(ctx);

	if (ev->category != EVENT_TARGET && ev->category != EVENT_IO)
		return;

	if (source == ARCAN_VIDEO_WORLDID)
		cb_tag = luactx.worldid_tag;

	if (cb_tag == LUA_NOREF){
/* if we don't get a callback tag, it is added to the worldid as an 'arcan'
 * entrypoint for those that aren't covered elsewhere */
		lua_settop(ctx, reset);
		return;
	}
	else {
		lua_rawgeti(ctx, LUA_REGISTRYINDEX, cb_tag);
	}

	lua_pushvid(ctx, source);

	if (ev->category == EVENT_IO){
/* re-use the same table mapping as normal */
		append_iotable(ctx, &ev->io);
		alt_call(ctx, CB_SOURCE_NONE, 0, 2, 0, LINE_TAG":event:lwa_io");
		return;
	}

	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	char msgbuf[COUNT_OF(ev->tgt.message) + 1];

	switch (ev->tgt.kind){
/* unfinished */
	case TARGET_COMMAND_STORE:
		if (!import_btype(ctx, top, reset, "store", O_WRONLY, ev->tgt.ioevs[0].iv))
			return;
	case TARGET_COMMAND_RESTORE:
		if (!import_btype(ctx, top, reset, "restore", O_RDONLY, ev->tgt.ioevs[0].iv))
			return;
	case TARGET_COMMAND_BCHUNK_IN:
		if (!import_btype(ctx, top, reset, "bchunk-in", O_RDONLY, ev->tgt.ioevs[0].iv))
			return;
		MSGBUF_UTF8(ev->tgt.message);
		tbldynstr(ctx, "id", msgbuf, top);
	break;
	case TARGET_COMMAND_BCHUNK_OUT:
		if (!import_btype(ctx, top, reset, "bchunk-out", O_WRONLY, ev->tgt.ioevs[0].iv))
			return;
		MSGBUF_UTF8(ev->tgt.message);
		tbldynstr(ctx, "id", msgbuf, top);
	case TARGET_COMMAND_FRAMESKIP:
	case TARGET_COMMAND_STEPFRAME:
	case TARGET_COMMAND_PAUSE:
	case TARGET_COMMAND_UNPAUSE:
	case TARGET_COMMAND_GRAPHMODE:
	case TARGET_COMMAND_ANCHORHINT: /* should probably feed back to know position,
																		 but unclear if _lwa applications should rely
																		 on that */
	case TARGET_COMMAND_RESET: /* handled in platform */
	case TARGET_COMMAND_SEEKCONTENT: /* scrolling */
	case TARGET_COMMAND_COREOPT: /* dynamic key-value */
	case TARGET_COMMAND_SEEKTIME: /* scrolling? */
	case TARGET_COMMAND_ATTENUATE: /* should go directly to audio */
	case TARGET_COMMAND_STREAMSET: /* doesn't apply */
	case TARGET_COMMAND_SETIODEV: /* doesn't apply */
	case TARGET_COMMAND_AUDDELAY: /* should go directly to audio */
	case TARGET_COMMAND_DEVICESTATE: /* doesn't apply */
	case TARGET_COMMAND_GEOHINT: /* should be forwarded */
		lua_settop(ctx, reset);
		return;
	break;
	case TARGET_COMMAND_MESSAGE:{
		tblstr(ctx, "kind", "message", top);
		tblbool(ctx, "multipart", ev->tgt.ioevs[0].iv != 0, top);
		MSGBUF_UTF8(ev->tgt.message);
		tbldynstr(ctx, "message", msgbuf, top);
	}
	break;
	case TARGET_COMMAND_EXIT:
/* map to 'terminated' */
		tblstr(ctx, "kind", "terminated", top);
	break;

/* already handled internally */
	case TARGET_COMMAND_REQFAIL:
	case TARGET_COMMAND_OUTPUTHINT: /* might be useful with more vr bits */
	case TARGET_COMMAND_ACTIVATE: /* shouldn't apply */
	case TARGET_COMMAND_NEWSEGMENT: /* should already be handled */
	case TARGET_COMMAND_DISPLAYHINT: /* should already be handled */
	case TARGET_COMMAND_FONTHINT: /* should already be handled */
	case TARGET_COMMAND_BUFFER_FAIL: /* should already be handled */
	case TARGET_COMMAND_DEVICE_NODE: /* should already be handled */
	case TARGET_COMMAND_LIMIT: /* can't happen */
		lua_settop(ctx, reset);
		return;
	break;
	}

	alt_call(ctx, CB_SOURCE_NONE, 0, 2, 0, LINE_TAG":event:lwa");
}
#endif

/* from shmif_event.h: struct netstate definition */
static char* spacetostr(int space)
{
	switch (space){
	case 0:
		return "tag";
	break;
	case 1:
		return "basename";
	break;
	case 2:
		return "subname";
	break;
	case 3:
		return "ipv4";
	break;
	case 4:
		return "ipv6";
	break;
	case 5:
		return "a12pub";
	break;
	default:
		return "unknown";
	break;
	}
}

bool arcan_lua_pushevent(lua_State* ctx, arcan_event* ev)
{
	bool adopt_check = false;
	char msgbuf[sizeof(arcan_event)+1];
	if (!ev){
		if (alt_lookup_entry(ctx, "input_end", 9)){
			alt_call(ctx, CB_SOURCE_NONE, 0, 0, 0, LINE_TAG":event:input_eob");
		}
		return true;
	}

	if (ev->category == EVENT_IO){
/* try to deliver the raw out-of-loop input, but defer / reinject if the
 * script can't handle it or rejects it */
		if (arcan_conductor_gpus_locked()){
			bool consumed = false;
			if (alt_lookup_entry(ctx, "input_raw", 9)){
				append_iotable(ctx, &ev->io);
				alt_call(ctx, CB_SOURCE_NONE, 0, 1, 1, LINE_TAG":event:input_raw");

				if (lua_type(ctx, -1) == LUA_TBOOLEAN && lua_toboolean(ctx, -1)){
					consumed = true;
				}
				lua_pop(ctx, 1);
			}
			return consumed;
		}

		if (alt_lookup_entry(ctx, "input", 5)){
			append_iotable(ctx, &ev->io);
			alt_call(ctx, CB_SOURCE_NONE, 0, 1, 0, LINE_TAG":event:input");
		}
		return true;
	}

	if (ev->category == EVENT_SYSTEM){
		struct arcan_evctx* evctx = arcan_event_defaultctx();

		if (ev->sys.kind == EVENT_SYSTEM_DATA_IN){
			if (ev->sys.data.otag == LUA_NOREF)
				return true;

			alt_nbio_data_in(ctx, ev->sys.data.otag);
		}
		else if (ev->sys.kind == EVENT_SYSTEM_DATA_OUT){
			if (ev->sys.data.otag == LUA_NOREF)
				return true;

			alt_nbio_data_out(ctx, ev->sys.data.otag);
		}
		return true;
	}

	/* all other events are prohibited while gpus are locked */
	if (arcan_conductor_gpus_locked()){
		return false;
	}

	if (ev->category == EVENT_EXTERNAL){
		bool preroll = false;
/* need to jump through a few hoops to get hold of the possible callback */
		arcan_vobject* vobj = arcan_video_getobject(ev->ext.source);
		if (!vobj || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
			return true;
		}

		int reset = lua_gettop(ctx);
		arcan_frameserver* fsrv = vobj->feed.state.ptr;
		if (fsrv->tag == LUA_NOREF){
			return true;
		}
		lua_rawgeti(ctx, LUA_REGISTRYINDEX, fsrv->tag);
		lua_pushvid(ctx, ev->ext.source);

		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		tblnum(ctx, "frame", ev->ext.frame_id, top);
		switch (ev->ext.kind){
		case EVENT_EXTERNAL_IDENT:
			tblstr(ctx, "kind", "ident", top);
			MSGBUF_UTF8(ev->ext.message.data);
			tbldynstr(ctx, "message", msgbuf, top);
		break;
		case EVENT_EXTERNAL_COREOPT:
			tblstr(ctx, "kind", "coreopt", top);
			tblnum(ctx, "slot", ev->ext.coreopt.index, top);
			MSGBUF_UTF8(ev->ext.message.data);
			tbldynstr(ctx, "argument", msgbuf, top);
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
				return true;
			}
		break;
/* this is handled / managed through _event.c, _conductor.c and _frameserver.c */
		case EVENT_EXTERNAL_CLOCKREQ:
				lua_settop(ctx, reset);
				return true;
		break;
		case EVENT_EXTERNAL_CONTENT:
			tblstr(ctx, "kind", "content_state", top);
			tblnum(ctx, "rel_x", (float)ev->ext.content.x_pos, top);
			tblnum(ctx, "rel_y", (float)ev->ext.content.y_pos, top);
			tblnum(ctx, "wnd_w", (float)ev->ext.content.width, top);
			tblnum(ctx, "wnd_h", (float)ev->ext.content.height, top);
			tblnum(ctx, "x_size", (float)ev->ext.content.x_sz, top);
			tblnum(ctx, "y_size", (float)ev->ext.content.y_sz, top);
			tblnum(ctx, "cell_w", ev->ext.content.cell_w, top);
			tblnum(ctx, "cell_h", ev->ext.content.cell_h, top);
			tblnum(ctx, "min_w", ev->ext.content.min_w, top);
			tblnum(ctx, "min_h", ev->ext.content.min_h, top);
			tblnum(ctx, "max_w", ev->ext.content.max_w, top);
			tblnum(ctx, "max_h", ev->ext.content.max_h, top);
		break;
/* the actual mask state can be queried through input capabilities */
		case EVENT_EXTERNAL_INPUTMASK:
			tblstr(ctx, "kind", "mask_input", top);
		break;
		case EVENT_EXTERNAL_VIEWPORT:
			tblstr(ctx, "kind", "viewport", top);
			push_view(ctx, &ev->ext, fsrv, top);
		break;
		case EVENT_EXTERNAL_CURSORHINT:
			FLTPUSH(ev->ext.message.data, flt_chint, '?');
			tbldynstr(ctx, "cursor", msgbuf, top);
			tblstr(ctx, "kind", "cursorhint", top);
		break;
		case EVENT_EXTERNAL_ALERT:
			tblstr(ctx, "kind", "alert", top);
			if (0)
		case EVENT_EXTERNAL_MESSAGE:
				tblstr(ctx, "kind", "message", top);
			MSGBUF_UTF8(ev->ext.message.data);
			tblbool(ctx, "multipart", ev->ext.message.multipart != 0, top);
			tbldynstr(ctx, "message", msgbuf, top);
		break;
		case EVENT_EXTERNAL_FAILURE:
			tblstr(ctx, "kind", "failure", top);
			MSGBUF_UTF8(ev->ext.message.data);
			tbldynstr(ctx, "message", msgbuf, top);
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
			tbldynstr(ctx, "lang", msgbuf, top);
			tblnum(ctx, "streamid", ev->ext.streaminf.streamid, top);
			tbldynstr(ctx, "type",
				streamtype(ev->ext.streaminf.datakind),top);
		break;
		case EVENT_EXTERNAL_STREAMSTATUS:
			tblstr(ctx, "kind", "streamstatus", top);
			FLTPUSH(ev->ext.streamstat.timestr, flt_num, '?');
			tbldynstr(ctx, "ctime", msgbuf, top);
			FLTPUSH(ev->ext.streamstat.timelim, flt_num, '?');
			tbldynstr(ctx, "endtime", msgbuf, top);
			tblnum(ctx,"completion",ev->ext.streamstat.completion,top);
			tblnum(ctx, "frameno", ev->ext.streamstat.frameno, top);
			tblnum(ctx,"streaming",
				ev->ext.streamstat.streaming!=0,top);
		break;
/* special semantics for segreq */
		case EVENT_EXTERNAL_SEGREQ:
			emit_segreq(ctx, fsrv, &ev->ext);
			return true;
		break;
		case EVENT_EXTERNAL_LABELHINT:{
			const char* idt = lookup_idatatype(ev->ext.labelhint.idatatype);
			if (!idt){
				lua_settop(ctx, reset);
				return true;
			}
			MSGBUF_UTF8(ev->ext.labelhint.descr);
			tbldynstr(ctx, "description", msgbuf, top);
			tblstr(ctx, "kind", "input_label", top);
			FLTPUSH(ev->ext.labelhint.label, flt_Alphanum, '?');
			tbldynstr(ctx, "labelhint", msgbuf, top);
			tblnum(ctx, "initial", ev->ext.labelhint.initial, top);
			tbldynstr(ctx, "datatype", idt, top);
			tblnum(ctx, "modifiers", ev->ext.labelhint.modifiers, top);
			MSGBUF_UTF8(ev->ext.labelhint.vsym);
			tbldynstr(ctx, "vsym", msgbuf, top);
		}
		break;
		case EVENT_EXTERNAL_BCHUNKSTATE:
			tblstr(ctx, "kind", "bchunkstate", top);
			tblbool(ctx, "hint", !((ev->ext.bchunk.hint & 1) > 0), top);
			tblbool(ctx, "multipart", ev->ext.bchunk.hint & 4, top);
			tblnum(ctx, "size", ev->ext.bchunk.size, top);
			tblbool(ctx, "input", ev->ext.bchunk.input, top);
			tblbool(ctx, "stream", ev->ext.bchunk.stream, top);
			tblbool(ctx, "wildcard", ev->ext.bchunk.hint & 2, top);
			tblbool(ctx, "disable", ev->ext.bchunk.extensions[0] == 0, top);
			if (ev->ext.bchunk.extensions[0]){
				FLTPUSH(ev->ext.bchunk.extensions, flt_chunkfn, '\0');
				tbldynstr(ctx, "extensions", msgbuf, top);
			}
		break;
/* This event does not arrive raw, the tracking properties are
 * projected unto the event during queuetransfer */
		case EVENT_EXTERNAL_PRIVDROP:
			tbldynstr(ctx, "kind", "privdrop", top);
			tblbool(ctx, "external", ev->ext.privdrop.external, top);
			tblbool(ctx, "sandboxed", ev->ext.privdrop.external, top);
			tblbool(ctx, "networked", ev->ext.privdrop.external, top);
		break;
		case EVENT_EXTERNAL_STATESIZE:
			tbldynstr(ctx, "kind", "state_size", top);
			tblnum(ctx, "state_size", ev->ext.stateinf.size, top);
			tblnum(ctx, "typeid", ev->ext.stateinf.type, top);
		break;
		case EVENT_EXTERNAL_NETSTATE:
			tbldynstr(ctx, "kind", "state", top);
			tbldynstr(ctx, "namespace", spacetostr(ev->ext.netstate.space), top);
			if (ev->ext.netstate.space == 5){
				MSGBUF_UTF8(ev->ext.netstate.name);
				tbldynstr(ctx, "name", msgbuf, top);
				size_t dsz;
				char* b64 = (char*) arcan_base64_encode(
					(uint8_t*)&ev->ext.netstate.pubk, 32, &dsz, 0);
				tbldynstr(ctx, "pubk", b64, top);
				free(b64);
			}
			else {
				MSGBUF_UTF8(ev->ext.netstate.name);
				tbldynstr(ctx, "name", msgbuf, top);
			}

			if (ev->ext.netstate.state & (1 | 2 | 4)){
				tblbool(ctx, "discovered", true, top);
				tblbool(ctx, "multipart", ev->ext.netstate.state == 2, top);
			}
			else if (ev->ext.netstate.state == 0)
				tblbool(ctx, "lost", true, top);
			else
				tblbool(ctx, "bad", true, top);

			if (ev->ext.netstate.type == 1)
				tblbool(ctx, "source", true, top);
			if (ev->ext.netstate.type == 2)
				tblbool(ctx, "sink", true, top);
			if (ev->ext.netstate.type == 4)
				tblbool(ctx, "directory", true, top);
		break;
		case EVENT_EXTERNAL_REGISTER:{
/* prevent switching types */
			int id = ev->ext.registr.kind;
			if (fsrv->segid != SEGID_UNKNOWN &&
				ev->ext.registr.kind != fsrv->segid){
				id = ev->ext.registr.kind = fsrv->segid;
			}
/* as well as registering protected types */
			else if (fsrv->segid == SEGID_UNKNOWN &&
				(id == SEGID_NETWORK_CLIENT || id == SEGID_NETWORK_SERVER)){
				arcan_warning("client (%d) attempted to register a reserved (%d) "
					"type which is not permitted.\n", fsrv->segid, id);
				lua_settop(ctx, reset);
				return true;
			}
/* update and mark for pre-roll unless protected */
			if (fsrv->segid == SEGID_UNKNOWN){
				fsrv->segid = id;
				preroll = true;
			}
			tblstr(ctx, "kind", "registered", top);
			tbldynstr(ctx, "segkind", fsrvtos(ev->ext.registr.kind), top);
			MSGBUF_UTF8(ev->ext.registr.title);
			snprintf(fsrv->title, COUNT_OF(fsrv->title), "%s", msgbuf);
			tbldynstr(ctx, "title", msgbuf, top);

			size_t dsz;
			char* b64 = (char*) arcan_base64_encode(
				(uint8_t*)&ev->ext.registr.guid[0], 16, &dsz, 0);
			tbldynstr(ctx, "guid", b64, top);
			arcan_mem_free(b64);
		}
		break;
		default:
			tblstr(ctx, "kind", "unknown", top);
			tblnum(ctx, "kind_num", ev->ext.kind, top);
		}

		alt_call(ctx, CB_SOURCE_FRAMESERVER,
			ev->ext.source,	2, 0, LINE_TAG":frameserver:event");
/* special: external connection + connected->registered sequence finished */
		if (preroll)
			do_preroll(ctx, fsrv->tag, fsrv->vid, fsrv->aid);
	}
	else if (ev->category == EVENT_FSRV){
		arcan_vobject* vobj = arcan_video_getobject(ev->fsrv.video);

/* this can happen if the frameserver has died and been enqueued but
 * delete_image was called in between, in that case, we still want to drop the
 * reference. */
		if (!vobj){
			if (ev->fsrv.otag != LUA_NOREF){
				luaL_unref(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
			}
			return true;
		}

/* the backing frameserver is already free:d at this point, hence why we need
 * the reference to stay on the queue so that we can unref accordingly */

		if (ev->fsrv.kind == EVENT_FSRV_TERMINATED){
			if (ev->fsrv.otag == LUA_NOREF)
				return true;

/* function, source, status */
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
			lua_pushvid(ctx, ev->fsrv.video);
			lua_newtable(ctx);

			int top = lua_gettop(ctx);
			tblstr(ctx, "kind", "terminated", top);
			MSGBUF_UTF8(ev->fsrv.message);
			tbldynstr(ctx, "last_words", msgbuf, top);
			alt_call(ctx, CB_SOURCE_FRAMESERVER,
				ev->fsrv.otag, 2, 0, LINE_TAG":frameserver:event");
			luaL_unref(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
			return true;
		}

/*
 * Special case, VR inherits some properties from frameserver,
 * but masks / shields a lot of the default eventloop
 */
		if (vobj->feed.state.tag == ARCAN_TAG_VR){
			if (ev->fsrv.otag == LUA_NOREF)
				return true;

			lua_rawgeti(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
			lua_pushvid(ctx, ev->fsrv.video);
			lua_newtable(ctx);
			int top = lua_gettop(ctx);
			if (ev->fsrv.kind == EVENT_FSRV_ADDVRLIMB){
				tblstr(ctx, "kind", "limb_added", top);
				tblnum(ctx, "id",  ev->fsrv.limb, top);
				tbldynstr(ctx, "name", limb_name(ev->fsrv.limb), top);
			}
			else{
				tblstr(ctx, "kind", "limb_lost", top);
				tblnum(ctx, "id", ev->fsrv.limb, top);
				tbldynstr(ctx, "name", limb_name(ev->fsrv.limb), top);
			}
			alt_call(ctx,
				CB_SOURCE_FRAMESERVER, ev->fsrv.otag, 2, 0, LINE_TAG":frameserver:vr");
			return true;
		}

		if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			return true;

		arcan_frameserver* fsrv = vobj->feed.state.ptr;
		if (LUA_NOREF == fsrv->tag)
			return true;

		if (ev->fsrv.kind == EVENT_FSRV_PREROLL){
			do_preroll(ctx, fsrv->tag, fsrv->vid, fsrv->aid);
			return true;
		}

/* function, source, status */
		lua_rawgeti(ctx, LUA_REGISTRYINDEX, ev->fsrv.otag);
		lua_pushvid(ctx, ev->fsrv.video);
		lua_newtable(ctx);

		int argc = 2;
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
			tblbool(ctx, "hdr", (ev->fsrv.aproto & SHMIF_META_HDR) > 0, top);
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
			tblnum(ctx, "x", ev->fsrv.xofs, top);
			tblnum(ctx, "y", ev->fsrv.yofs, top);
			tblnum(ctx, "width", ev->fsrv.width, top);
			tblnum(ctx, "height", ev->fsrv.height, top);
		break;
		case EVENT_FSRV_IONESTED:
			tblstr(ctx, "kind", "input", top);
			tblnum(ctx, "tgtid", ev->fsrv.input.dst, top);
			append_iotable(ctx, &ev->fsrv.input);
			argc = 3;
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
			tbldynstr(ctx, "key", msgbuf, top);
			luactx.pending_socket_label = strdup(msgbuf);
			luactx.pending_socket_descr = ev->fsrv.descriptor;
			adopt_check = true;
		}
		break;
		case EVENT_FSRV_RESIZED :
			tbldynstr(ctx, "kind", "resized", top);
			tblnum(ctx, "width", ev->fsrv.width, top);
			tblnum(ctx, "height", ev->fsrv.height, top);

/* mirrored is incorrect but can't drop it for legacy reasons */
			tblbool(ctx, "mirrored", ev->fsrv.fmt_fl & SHMIF_RHINT_ORIGO_LL, top);
			tblbool(ctx, "origo_ll", ev->fsrv.fmt_fl & SHMIF_RHINT_ORIGO_LL, top);
			tblbool(ctx, "tpack", ev->fsrv.fmt_fl & SHMIF_RHINT_TPACK, top);
		break;
		default:
		break;
		}

		alt_call(ctx, CB_SOURCE_FRAMESERVER,
			ev->fsrv.video, argc, 0, LINE_TAG":frameserver:event");
	}
	else if (ev->category == EVENT_VIDEO){
		if (ev->vid.kind == EVENT_VIDEO_DISPLAY_ADDED){
			display_added(ctx, ev);
			return true;
		}
		else if (ev->vid.kind == EVENT_VIDEO_DISPLAY_RESET){
			display_reset(ctx, ev);
			return true;
		}
		else if (ev->vid.kind == EVENT_VIDEO_DISPLAY_REMOVED){
			display_removed(ctx, ev);
			return true;
		}
		else if (ev->vid.kind == EVENT_VIDEO_DISPLAY_CHANGED){
			display_changed(ctx, ev);
			return true;
		}

/* terminating conditions: no callback or source vid broken */
		intptr_t dst_cb = (intptr_t) ev->vid.data;
		arcan_vobject* srcobj = arcan_video_getobject(ev->vid.source);
		if (0 == dst_cb || !srcobj)
			return true;

		const char* evmsg = "video_event";

/* add placeholder, if we find an asynch recipient */
		lua_pushnumber(ctx, 0);

		lua_pushvid(ctx, ev->vid.source);
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		int source = CB_SOURCE_NONE;

		switch (ev->vid.kind){
		case EVENT_VIDEO_EXPIRE :
/* not even likely that these get forwarded here */
		break;

		case EVENT_VIDEO_CHAIN_OVER:
			evmsg = "video_event(chain_tag reached), callback";
			source = CB_SOURCE_TRANSFORM;
		break;

		case EVENT_VIDEO_ASYNCHIMAGE_LOADED:
			evmsg = "video_event(asynchimg_loaded), callback";
			source = CB_SOURCE_IMAGE;
			tbldynstr(ctx, "kind", "loaded", top);
/* C trick warning */
			if (0)
		case EVENT_VIDEO_ASYNCHIMAGE_FAILED:
			{
				source = CB_SOURCE_IMAGE;
				evmsg = "video_event(asynchimg_load_fail), callback";
				tblstr(ctx, "kind", "load_failed", top);
			}
			if (srcobj && srcobj->vstore->vinf.text.source)
				tbldynstr(ctx, "resource", srcobj->vstore->vinf.text.source, top);
			else
				tblstr(ctx, "resource", "unknown", top);
			tblnum(ctx, "width", ev->vid.width, top);
			tblnum(ctx, "height", ev->vid.height, top);
		break;

		default:
			arcan_warning("Engine -> Script Warning: arcan_lua_pushevent(),"
			"	unknown video event (%i)\n", ev->vid.kind);
		}

		if (source != CB_SOURCE_NONE){
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
			lua_replace(ctx, 1);
			alt_call(ctx, source, ev->vid.source, 2, 0, evmsg);
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
	}
	else if (ev->category == EVENT_AUDIO){
		if (
			ev->aud.kind == EVENT_AUDIO_PLAYBACK_FINISHED &&
			ev->aud.otag != LUA_NOREF){
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, ev->aud.otag);
			alt_call(ctx, CB_SOURCE_NONE, 0, 0, 0, LINE_TAG":audio:finished");
			luaL_unref(ctx, LUA_REGISTRYINDEX, ev->aud.otag);
		}
	}
	return true;
}
#undef FLTPUSH
#undef MSGBUF_UTF8

static int imageparent(lua_State* ctx)
{
	LUA_TRACE("image_parent");
	arcan_vobject* srcobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &srcobj);
	arcan_vobj_id ref = luavid_tovid(luaL_optnumber(ctx, 2, ARCAN_EID));
	arcan_vobj_id pid = arcan_video_findparent(id, ref);

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
		const char** opts = arcan_conductor_synchopts();
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		size_t count = 0;

/* platform definition requires opts to be [k,d, ... ,NULL,NULL]
 * so allow the table to be dual-indexed */
		while(opts[count*2]){
			lua_pushnumber(ctx, count+1);
			lua_pushstring(ctx, opts[count*2]);
			lua_rawset(ctx, top);
			lua_pushstring(ctx, opts[count*2]);
			lua_pushstring(ctx, opts[count*2+1]);
			lua_rawset(ctx, top);
			count++;
		}

		LUA_ETRACE("video_synchronization", NULL, 1);
	}
	else
		arcan_conductor_setsynch(newstrat);

	LUA_ETRACE("video_synchronization", NULL, 0);
}

static int validvid(lua_State* ctx)
{
	LUA_TRACE("valid_vid");
	arcan_vobj_id res = (arcan_vobj_id) luaL_optnumber(ctx, 1, ARCAN_EID);

	if (res != ARCAN_EID && res != ARCAN_VIDEO_WORLDID)
		res -= lua_vid_base;

	if (res < 0 && res != ARCAN_VIDEO_WORLDID)
		res = ARCAN_EID;

	int type = luaL_optnumber(ctx, 2, -1);
	if (-1 != type){
		arcan_vobject* vobj = arcan_video_getobject(res);
#ifdef ARCAN_LWA
		if (type == ARCAN_TAG_FRAMESERV && res == ARCAN_VIDEO_WORLDID){
			lua_pushboolean(ctx, true);
			LUA_ETRACE("valid_vid", NULL, 1);
		}
#endif
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
	bool depth = true;

/* either num, num, fun or fun - anything else is terminal */
	if (arg1 == LUA_TNUMBER){
		s = luaL_checknumber(ctx, 2);
		t = luaL_checknumber(ctx, 3);
		depth = luaL_optbnumber(ctx, 4, true);
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
		arcan_video_defineshape(sid, s, t, &ms, depth);
		lua_pushboolean(ctx, (ms && ms->verts != NULL) || s == 1 || t == 1);
	}
	else {
		arcan_video_defineshape(sid, s, t, &ms, depth);
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
			alt_call(ctx, CB_SOURCE_NONE, 0, 3, 0, LINE_TAG":tesselate_image");
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

	int sp = luaL_optnumber(ctx, 4, SCALEM_NONE);
	if (sp > SCALEM_ENDM)
		arcan_fatal("link_image() -- invalid scale bias dimension (%d)\n", sp);

	enum arcan_transform_mask smask = arcan_video_getmask(sid);
	smask |= MASK_LIVING;

	arcan_errc rv = arcan_video_linkobjs(sid, did, smask, ap, sp);
	lua_pushboolean(ctx, rv == ARCAN_OK);
	LUA_ETRACE("link_image", NULL, 1);
}

static int relinkimage(lua_State* ctx)
{
	LUA_TRACE("relink_image")

/* setup is just the same as link_image */
	arcan_vobj_id sid = luaL_checkvid(ctx, 1, NULL);
	arcan_vobj_id did = luaL_checkvid(ctx, 2, NULL);
	int ap = luaL_optnumber(ctx, 3, ANCHORP_UL);

	if (ap > ANCHORP_ENDM)
		arcan_fatal("link_image() -- invalid anchor point specified (%d)\n", ap);

	int sp = luaL_optnumber(ctx, 4, SCALEM_NONE);
	if (sp > SCALEM_ENDM)
		arcan_fatal("link_image() -- invalid scale bias dimension (%d)\n", sp);

	enum arcan_transform_mask smask = arcan_video_getmask(sid);
	smask |= MASK_LIVING;

/* resolve to world-space */
	surface_properties pprop = {0};
	if (did != ARCAN_EID && did != ARCAN_VIDEO_WORLDID){
		pprop = arcan_video_resolve_properties(did);
	}
	surface_properties sprop = arcan_video_resolve_properties(sid);

/* will also reset transforms */
	arcan_errc rv = arcan_video_linkobjs(sid, did, smask, ANCHORP_UL, sp);

/* if the re-linking suceeded, we can now apply the world-space delta */
	if (rv == ARCAN_OK){
		float new_x = sprop.position.x - pprop.position.x;
		float new_y = sprop.position.y - pprop.position.y;
		float new_z = sprop.position.z - pprop.position.z;

/* but if the anchor point is different, we first need to resolve what
 * the local anchor delta is, and merge the two translations */
		if (ap != ANCHORP_UL){
			arcan_video_objectmove(sid, 0, 0, 0, 0);
			surface_properties base = arcan_video_resolve_properties(sid);
			arcan_video_linkobjs(sid, did, smask, ap, sp);
			surface_properties anchor = arcan_video_resolve_properties(sid);
			new_x -= anchor.position.x - base.position.x;
			new_y -= anchor.position.y - base.position.y;
			new_z -= anchor.position.z - base.position.z;
		}

		arcan_video_objectmove(sid, new_x, new_y, new_z, 0);
	}

	lua_pushboolean(ctx, rv == ARCAN_OK);
	LUA_ETRACE("relink_image", NULL, 1)
}

static int pushprop(lua_State* ctx,
	surface_properties prop, unsigned short zv)
{
	lua_createtable(ctx, 0, 11);

	lua_pushliteral(ctx, "x");
	lua_pushnumber(ctx, prop.position.x);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "y");
	lua_pushnumber(ctx, prop.position.y);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "z");
	lua_pushnumber(ctx, prop.position.z);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "width");
	lua_pushnumber(ctx, prop.scale.x);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "height");
	lua_pushnumber(ctx, prop.scale.y);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "depth");
	lua_pushnumber(ctx, prop.scale.z);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "angle");
	lua_pushnumber(ctx, prop.rotation.roll);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "roll");
	lua_pushnumber(ctx, prop.rotation.roll);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "pitch");
	lua_pushnumber(ctx, prop.rotation.pitch);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "yaw");
	lua_pushnumber(ctx, prop.rotation.yaw);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "opacity");
	lua_pushnumber(ctx, prop.opa);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "order");
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
	LUA_TRACE("add_3dmesh_rawmesh");
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
	LUA_ETRACE("add_3dmesh_rawmesh", NULL, 1);
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

	char* path = findresource(
		luaL_checkstring(ctx, 2), DEFAULT_USERMASK, ARES_FILE | ARES_RDONLY);
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

/* second form is to update a camera with a different projection */
	if (lua_type(ctx, 2) == LUA_TTABLE){
		float proj[16];
		int nvals = lua_rawlen(ctx, -1);
		if (nvals != 16){
			lua_pushboolean(ctx, false);
			LUA_ETRACE("camtag_model", "16 elements expected", 1);
		}
		else {
			for (size_t i = 0; i < 16; i++){
				lua_rawgeti(ctx, 2, i+1);
				proj[i] = lua_tonumber(ctx, -1);
				lua_pop(ctx, 1);
			}
			lua_pushboolean(ctx, arcan_3d_camproj(id, proj) == ARCAN_OK);
		}
		LUA_ETRACE("camtag_model", NULL, 1);
	}

	struct monitor_mode mode = platform_video_dimensions();
	float w = mode.width;
	float h = mode.height;

	int base = 6;

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

	arcan_vobject* vobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);
	img_cons cons = arcan_video_storage_properties(id);
	lua_createtable(ctx, 0, 3);

	lua_pushliteral(ctx, "bpp");
	lua_pushnumber(ctx, cons.bpp);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "height");
	lua_pushnumber(ctx, cons.h);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "width");
	lua_pushnumber(ctx, cons.w);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "refc");
	lua_pushnumber(ctx, vobj->vstore->refcount);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "type");
	switch(vobj->vstore->txmapped){
	case TXSTATE_OFF:
		lua_pushliteral(ctx, "color");
	break;
	case TXSTATE_TEX2D:
		lua_pushliteral(ctx, "2d");
	break;
	case TXSTATE_DEPTH:
		lua_pushliteral(ctx, "depth");
	break;
	case TXSTATE_TEX3D:
		lua_pushliteral(ctx, "3d");
	break;
	case TXSTATE_CUBE:
		lua_pushliteral(ctx, "cube");
	break;
	case TXSTATE_TPACK:
		lua_pushliteral(ctx, "tpack");
	break;
	}
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
		unsigned int count = 1;

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
	LUA_TRACE("fsrv_gamma");
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
		ARCAN_VIDEO_WORLDID && id > lua_vid_base){
		fsrv_dst = arcan_video_getobject(id-lua_vid_base);
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
	struct platform_mode_opts opts = {0};

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

		lua_pushboolean(ctx, platform_video_set_mode(id, mode, opts));
		LUA_ETRACE("video_displaymodes", NULL, 1);
	break;

	case 3: /* specify custom mode */
		id = luaL_checknumber(ctx, 1);
/* add options */
		if (lua_type(ctx, 3) == LUA_TTABLE){
			platform_mode_id mode = luaL_checknumber(ctx, 2);
			opts.vrr = intblfloat(ctx, 3, "vrr");
			opts.depth = intblfloat(ctx, 3, "format");

			if
				(opts.depth == VSTORE_HINT_HIDEF || opts.depth == VSTORE_HINT_F16 ||
				 opts.depth == VSTORE_HINT_F32){
					opts.primaries_xy.white[0] = intblfloat(ctx, 3, "whitepoint_x");
					opts.primaries_xy.white[1] = intblfloat(ctx, 3, "whitepoint_y");
					opts.primaries_xy.green[0] = intblfloat(ctx, 3, "primary_green_x");
					opts.primaries_xy.green[1] = intblfloat(ctx, 3, "primary_green_y");
					opts.primaries_xy.red[0] = intblfloat(ctx, 3, "primary_red_x");
					opts.primaries_xy.red[1] = intblfloat(ctx, 3, "primary_red_y");
					opts.primaries_xy.blue[0] = intblfloat(ctx, 3, "primary_blue_x");
					opts.primaries_xy.blue[1] = intblfloat(ctx, 3, "primary_blue_y");
				}

			lua_pushboolean(ctx, platform_video_set_mode(id, mode, opts));
		}
		else {
			size_t h = luaL_checknumber(ctx, 3);
			size_t w = luaL_checknumber(ctx, 2);
			struct monitor_mode mmode = {
				.width = w,
				.height = h
			};
			lua_pushboolean(ctx, platform_video_specify_mode(id, mmode));
		}

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
	int id = luaL_checknumber(ctx, 2);
	if (id < 0)
		arcan_fatal("map_video_display(), invalid target display id (%d)\n", id);

	struct display_layer_cfg layer = {
		.hint = luaL_optnumber(ctx, 3, HINT_NONE),
		.opacity = 1.0
	};

	if (layer.hint < HINT_NONE){
		arcan_fatal("map_video_display(), invalid blitting "
			"hint specified (%d)\n", (int) layer.hint);
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

	size_t layer_ind = luaL_optnumber(ctx, 4, 0);
	if (layer_ind > 0){
		layer.x = luaL_optnumber(ctx, 5, 0);
		layer.y = luaL_optnumber(ctx, 6, 0);
	}

	ssize_t left = platform_video_map_display_layer(vid, id, layer_ind, layer);
	lua_pushboolean(ctx, left >= 0);
	lua_pushnumber(ctx, left);
	LUA_ETRACE("map_video_display", NULL, 2);
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

static int inputremaptranslation(lua_State* ctx)
{
	LUA_TRACE("input_remap_translation")
	int devid = luaL_checknumber(ctx, 1);
	int act = luaL_checknumber(ctx, 2);
	bool getmap = false;
	int ofs = 2;

/* set if we want an iostream to the current (remap) or a desired one */
	if (lua_type(ctx, 3) == LUA_TBOOLEAN || lua_type(ctx, 3) == LUA_TNUMBER){
		getmap = luaL_checkbnumber(ctx, 3);
		ofs++;
	}

	if (
		act != EVENT_TRANSLATION_CLEAR &&
		act != EVENT_TRANSLATION_SET &&
		act != EVENT_TRANSLATION_REMAP){
		arcan_fatal("input_remap_translation() - unknown op: %d\n", act);
	}

	int ttop = lua_gettop(ctx);
	const char* arr[ttop];

	if (ttop - ofs > 0){
		for (size_t i = 0; i < ttop - ofs; i++){
			arr[i] = luaL_checkstring(ctx, i+ofs+1);
		}
		arr[ttop-ofs] = NULL;
	}

	const char* err = "";

	if (getmap){
		int mode = EVENT_TRANSLATION_SERIALIZE_CURRENT;
		if (act == EVENT_TRANSLATION_SET)
			mode = EVENT_TRANSLATION_SERIALIZE_SPEC;

		int fd = platform_event_translation(devid, mode, arr, &err);
		struct nonblock_io* dst;
		alt_nbio_import(ctx, fd, mode, &dst, NULL);
		lua_pushstring(ctx, err);
		LUA_ETRACE("input_remap_translation", NULL, 2);
	}

	int res = platform_event_translation(devid, act, arr, &err);
	lua_pushboolean(ctx, res);
	lua_pushstring(ctx, err);

	LUA_ETRACE("input_remap_translation", NULL, 2)
}

static int inputcap(lua_State* ctx)
{
	LUA_TRACE("input_capabilities");
	const char* pident;
	enum PLATFORM_EVENT_CAPABILITIES pcap = platform_event_capabilities(&pident);

	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	if (lua_type(ctx, 1) == LUA_TNUMBER){
		arcan_vobject* vobj;
		arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);

/* unreference the old one so we don't leak */
		if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			arcan_fatal("input_capabilities(), specified "
				"vid (arg 1) not associated with a frameserver.");

		arcan_frameserver* tgt = vobj->feed.state.ptr;

		tblbool(ctx, "keyboard", tgt->devicemask & EVENT_IDEVKIND_KEYBOARD, top);
		tblbool(ctx, "game", tgt->devicemask & EVENT_IDEVKIND_GAMEDEV, top);
		tblbool(ctx, "mouse", tgt->devicemask & EVENT_IDEVKIND_GAMEDEV, top);
		tblbool(ctx, "touch", tgt->devicemask & EVENT_IDEVKIND_TOUCHDISP, top);
		tblbool(ctx, "led", tgt->devicemask & EVENT_IDEVKIND_LEDCTRL, top);
		tblbool(ctx, "eyetracker", tgt->devicemask & EVENT_IDEVKIND_EYETRACKER, top);
		tblbool(ctx, "analog", tgt->datamask & EVENT_IDATATYPE_ANALOG, top);
		tblbool(ctx, "digital", tgt->datamask & EVENT_IDATATYPE_DIGITAL, top);
		tblbool(ctx, "translated", tgt->datamask & EVENT_IDATATYPE_TRANSLATED, top);
		tblbool(ctx, "touch", tgt->datamask & EVENT_IDATATYPE_TOUCH, top);
		tblbool(ctx, "eyes", tgt->datamask & EVENT_IDATATYPE_EYES, top);
	}
	else {
		tblbool(ctx, "keyboard", (pcap & ACAP_TRANSLATED) > 0, top);
		tblbool(ctx, "mouse", (pcap & ACAP_MOUSE) > 0, top);
		tblbool(ctx, "game", (pcap & ACAP_GAMING) > 0, top);
		tblbool(ctx, "touch", (pcap & ACAP_TOUCH) > 0, top);
		tblbool(ctx, "position", (pcap & ACAP_POSITION) > 0, top);
		tblbool(ctx, "orientation", (pcap & ACAP_ORIENTATION) > 0, top);
		tblbool(ctx, "eyetracker", (pcap & ACAP_EYES) > 0, top);
	}
	lua_pushstring(ctx, pident);
	LUA_ETRACE("input_capabilities", NULL, 2);
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
		int fd;
		char* fname = arcan_find_resource(
			dumpstr, CREATE_USERMASK, ARES_FILE | ARES_CREATE, &fd);
		if (!fname){
			arcan_warning(
				"rawsurface() -- refusing to overwrite existing file (%s)\n", fname);
		}
		else {
			FILE* fpek = fdopen(fd, "wb");
			if (!fpek)
				arcan_warning("rawsurface() - - couldn't open (%s).\n", fname);
			else
				arcan_img_outpng(fpek, buf, desw, desh, 0);
			fclose(fpek);
			arcan_mem_free(fname);
		}
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
				float rv = 1.0 +
					stb_perlin_fbm_noise3(xv, yv, zv, lacunarity, gain, octaves);
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
	TRACE_MARK_ONESHOT("scripting", "shutdown", TRACE_SYS_DEFAULT, 0, 0, "");
	arcan_trace_setbuffer(NULL, 0, NULL);
	alt_trace_finish(ctx);
	alt_nbio_release();

/* and special case the open_rawresource (which would be nice to one day
 * get rid off..) */
	if (luactx.rawres.fd > 0){
		close(luactx.rawres.fd);
		luactx.rawres.fd = -1;
	}

/* only some properties are reset in order for certain state to carry over
 * between system_collapse calls and crash/script error recovery code */
	luactx.rawres = (struct nonblock_io){0};
	luactx.last_segreq = NULL;
	luactx.pending_socket_label = NULL;
	luactx.pending_socket_descr = 0;

	lua_close(ctx);
}

void arcan_lua_dostring(lua_State* ctx, const char* code, const char* name)
{
	luaL_loadbuffer(ctx,
		code, strlen(code), name) || lua_pcall(ctx, 0, LUA_MULTRET, 0);
}

static void error_hook(lua_State* ctx, lua_Debug* ar)
{
/* will longjump into the pcall error handler which will trigger recovery,
 * unless there is another watchdog monitor control set */
	luaL_error(ctx, "ANR - Application Not Responding");
}

static void sig_watchdog(int sig, siginfo_t* info, void* unused)
{
	if (getppid() == info->si_pid){
/* set a hook that we can use to then invoke our error handler path */
		lua_sethook(luactx.last_ctx, luactx.error_hook, LUA_MASKCOUNT, 1);
	}
}

lua_State* arcan_lua_alloc(void (*watchdog)(lua_State*, lua_Debug*))
{
	lua_State* res = luaL_newstate();
	luactx.worldid_tag = LUA_NOREF;

/* in the future, we need a hook here to
 * limit / "null-out" the undesired subset of the LUA API */
	if (res)
		luaL_openlibs(res);

	luactx.error_hook = watchdog;

/* watchdog has triggered with an ANR, continue the bouncy castle towards
 * the 'normal' scripting recovery stage so we get information on where
 * this comes from */
	sigaction(SIGUSR1, &(struct sigaction){
		.sa_sigaction = &sig_watchdog,
		.sa_flags = SA_SIGINFO
	}, NULL);

	luactx.last_ctx = res;
	return res;
}

/*
 * just adapted from lbaselib.c
 */
static int luaB_loadstring (lua_State* ctx) {
  size_t l;
  const char* s = luaL_checklstring(ctx, 1, &l);
  const char* chunkname = luaL_optstring(ctx, 2, s);
	if (0 == luaL_loadbuffer(ctx, s, l, chunkname))
		return 1;
	lua_pushnil(ctx);
	lua_insert(ctx, -2);
	return 2;
}

static bool add_source(int fd, mode_t mode, intptr_t otag)
{
	return
		arcan_event_add_source(
			arcan_event_defaultctx(), fd, mode, otag, false);
}

static bool del_source(int fd, mode_t mode, intptr_t* out)
{
	return
		arcan_event_del_source(arcan_event_defaultctx(), fd, mode, out);
}

static void error_nbio(lua_State* L, int fd, intptr_t tag, const char* src)
{
}

void arcan_lua_mapfunctions(lua_State* ctx, int debuglevel)
{
	alt_setup_context(ctx, arcan_appl_id());
	alua_exposefuncs(ctx, debuglevel);
/* update with debuglevel etc. */
	arcan_lua_pushglobalconsts(ctx);
	alt_nbio_register(ctx, add_source, del_source, error_nbio);

/* only allow eval() style operation in explicit debug modes */
	if (lua_debug_level){
		lua_pushliteral(ctx, "loadstring");
		lua_pushcclosure(ctx, luaB_loadstring, 1);
		lua_setglobal(ctx, "loadstring");
	}
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
	if (tlen > 0){
#ifdef ARCAN_LWA
		struct arcan_shmif_cont* cont = arcan_shmif_primary(SHMIF_INPUT);
		if (cont){
			arcan_shmif_last_words(cont, str);
		}
		else
#endif
			arcan_warning("%s\n", str);
	}

	LUA_ETRACE("shutdown", NULL, 0);
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

static int listns(lua_State* ctx)
{
	LUA_TRACE("list_namespaces");
	struct arcan_strarr ns = arcan_user_namespaces();
	lua_newtable(ctx);
	struct arcan_userns** cn = (struct arcan_userns**) ns.cdata;

	int count = 1;
	while (count <= ns.count && ns.cdata){
		struct arcan_userns* cn = ns.cdata[count-1];
		if (!cn)
			break;

		lua_pushnumber(ctx, count);

		lua_newtable(ctx);
			lua_pushliteral(ctx, "label");
			lua_pushstring(ctx, cn->label);
			lua_rawset(ctx, -3);

			lua_pushliteral(ctx, "name");
			lua_pushstring(ctx, cn->name);
			lua_rawset(ctx, -3);

			lua_pushliteral(ctx, "read");
			lua_pushboolean(ctx, cn->read);
			lua_rawset(ctx, -3);

			lua_pushliteral(ctx, "write");
			lua_pushboolean(ctx, cn->write);
			lua_rawset(ctx, -3);

			lua_pushliteral(ctx, "ipc");
			lua_pushboolean(ctx, cn->ipc);
			lua_rawset(ctx, -3);
		lua_rawset(ctx, -3);

		count++;
	}

	arcan_mem_freearr(&ns);
	LUA_ETRACE("list_namespaces", NULL, 1);
}

static int globresource(lua_State* ctx)
{
	LUA_TRACE("glob_resource");

	struct globs bptr = {
		.ctx = ctx,
		.index = 1
	};

	char* label = strdup(luaL_checkstring(ctx, 1));
	const char* userns = NULL;

	int mask = DEFAULT_USERMASK;

	if (lua_type(ctx, 2) == LUA_TSTRING){
		userns = lua_tostring(ctx, 2);
	}
	else if (lua_type(ctx, 2) == LUA_TNUMBER){
		mask = luaL_checknumber(ctx, 2);
		mask &=
			(
				DEFAULT_USERMASK
				|RESOURCE_APPL_STATE
				|RESOURCE_SYS_APPLBASE
				|RESOURCE_SYS_FONT
			);
	}

	lua_newtable(ctx);
	bptr.top = lua_gettop(ctx);

	if (userns)
		arcan_glob_userns(label, userns, globcb, &bptr);
	else
		arcan_glob(label, mask, globcb, &bptr);

	free(label);

	LUA_ETRACE("glob_resource", NULL, 1);
}

static int resource(lua_State* ctx)
{
	LUA_TRACE("resource");

	const char* label = luaL_checkstring(ctx, 1);
/* can only be used to test for resource so don't & against mask */
	int mask = luaL_optinteger(ctx, 2, DEFAULT_USERMASK);
	char* res = arcan_find_resource(
		label, mask, ARES_FILE | ARES_FOLDER, NULL);

	if (!res){
		lua_pushstring(ctx, res);
		lua_pushliteral(ctx, "not found");
	}
	else{
		lua_pushstring(ctx, res);
		if (arcan_isdir(res))
			lua_pushliteral(ctx, "directory");
		else
			lua_pushliteral(ctx, "file");
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
/* track this for later */
	if (argv)
		luactx.last_argv = argv;

	if ( alt_lookup_entry(ctx, fun, strlen(fun)) ){
		int argc = 0;
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		while (argv && argv[argc]){
			lua_pushnumber(ctx, argc+1);
			lua_pushstring(ctx, argv[argc++]);
			lua_rawset(ctx, top);
		}

		alt_call(ctx, CB_SOURCE_NONE, 0, 1, 0, fun);
		return true;
	}
	else if (warn)
		arcan_warning("missing expected symbol ( %s )\n", fun);

	return false;
}

static int arcantargethint(lua_State* ctx)
{
	LUA_TRACE("arcantarget_hint");
#ifdef ARCAN_LWA
	int tblind = 2;
	if (lua_type(ctx, 1) == LUA_TNUMBER){
		tblind = 3;
	}

	const char* msg = luaL_checkstring(ctx, tblind-1);
	if (lua_type(ctx, tblind) != LUA_TTABLE)
		luaL_typerror(ctx, tblind, "expected argument table");
	else if (strcmp(msg, "state_size") == 0){
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext = EVENT_EXTERNAL_STATESIZE
		};
		int size = intblint(ctx, tblind, "state_size");
		int typeid = intblint(ctx, tblind, "typeid");
		if (size < 0)
			size = 0;
		if (typeid < 0)
			typeid = 0;
		ev.ext.stateinf.size = size;
		ev.ext.stateinf.type = typeid;
		lua_pushboolean(ctx, platform_lwa_targetevent(NULL, &ev));
	}
	else if (strcmp(msg, "input_label") == 0){
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext = EVENT_EXTERNAL_LABELHINT,
		};
		const char* lbl = intblstr(ctx, tblind, "labelhint");
/* obligatory */
		if (!lbl){
			lua_pushboolean(ctx, false);
			LUA_ETRACE("arcantarget_hint", "missing label key in table", 1);
		}
		else {
			snprintf(ev.ext.labelhint.label,
				COUNT_OF(ev.ext.labelhint.label), "%s", lbl);
		};

		int init = intblint(ctx, tblind, "initial");
		if (-1 != init){
			ev.ext.labelhint.initial = init;
		}

		const char* descr = intblstr(ctx, tblind, "description");
		if (descr){
			snprintf(ev.ext.labelhint.descr,
				COUNT_OF(ev.ext.labelhint.descr), "%s", lbl);
		}

		const char* vsym = intblstr(ctx, tblind, "vsym");
		if (vsym){
		}

		int dt = lookup_idatatype_str(intblstr(ctx, tblind, "datatype"));
		if (-1 != dt){
			ev.ext.labelhint.idatatype = dt;
		}
		else
			dt = EVENT_IDATATYPE_DIGITAL;

		int mods = intblint(ctx, tblind, "modifiers");
		if (-1 != mods){
			ev.ext.labelhint.modifiers = mods;
		}

		lua_pushboolean(ctx, platform_lwa_targetevent(NULL, &ev));
	}
	else
#endif
/* possibilities:
 *  MESSAGE (covered by target_input),
 *  COREOPT (coreopt: index, type, data[77])
 *  IDENT (message)
 *  FAILED (ignore for now, uncertain how to map cleanly)
 *  STREAMINFO (ignore for now)
 *  STREAMSTATUS (streamstat: completion and streaming are valid)
 *  CURSORHINT (message, default hidden)
 *  VIEWPORT (ignore for now, full SSD only, but will become more useful)
 *  CONTENT (content: x_pos/x_sz, y_pos/y_sz, min_w, min_h, max_w, max_h)
 *  ALERT (message: notification string)
 *  CLOCKREQ (ignore, we already have a clocking mechanism)
 *  BCHUNKSTATE (platform/arcan/video.c has dibs on .lua though)
 *  PRIVDROP (ignore, privsep for lwa is default)
 *  INPUTMASK (ignore, uncertain if this adds much of value here)
 */
		lua_pushboolean(ctx, false);
	LUA_ETRACE("arcantarget_hint", NULL, 1);
}

static int targethandler(lua_State* ctx)
{
	LUA_TRACE("target_updatehandler");
	arcan_vobject* vobj;
	arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);

/* special handler here to get WM events on WORLDID */
#ifdef ARCAN_LWA
	if (id == ARCAN_VIDEO_WORLDID){
		if (luactx.worldid_tag != LUA_NOREF){
			luaL_unref(ctx, LUA_REGISTRYINDEX, luactx.worldid_tag);
		}
		intptr_t ref = find_lua_callback(ctx);
		luactx.worldid_tag = ref;
		return 0;
	}
#endif

/* unreference the old one so we don't leak */
	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
		arcan_fatal("target_updatehandler(), specified vid (arg 1) not "
			"associated with a frameserver.");
	}

	arcan_frameserver* fsrv = vobj->feed.state.ptr;
	if (!fsrv)
		arcan_fatal("target_updatehandler(), specified vid (arg 1) is not"
			" associated with a frameserver.");

	if (fsrv->tag != (intptr_t)LUA_NOREF){
		luaL_unref(ctx, LUA_REGISTRYINDEX, fsrv->tag);
	}

/* takes care of the type checking or setting an empty ref */
	intptr_t ref = find_lua_callback(ctx);
	fsrv->tag = ref;

#ifndef offsetof
#define offsetof(type, member) ((size_t)((char*)&(*(type*)0).member\
 - (char*)&(*(type*)0)))
#endif

	arcan_event dummy;

	_Static_assert(sizeof(dummy.fsrv.otag) == sizeof(ref), "bad tag sz");

/* for the already pending events referring to the specific frameserver,
 * rewrite the otag to match that of the new function */
	arcan_event_repl(arcan_event_defaultctx(), EVENT_FSRV,
		offsetof(arcan_event, fsrv.video),
		sizeof(arcan_vobj_id), &id,
		offsetof(arcan_event, fsrv.otag),
		sizeof(dummy.fsrv.otag), &ref
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
	bool mask = luaL_optbnumber(ctx, 2, true);
	if (mask){
		fsrv->tag = (intptr_t) LUA_NOREF;

		arcan_frameserver_free(fsrv);
		vobj->feed.ffunc = FFUNC_NULLFRAME;
		vobj->feed.state.ptr = NULL;
		vobj->feed.state.tag = ARCAN_TAG_IMAGE;
	}
	else
		arcan_frameserver_free(fsrv);

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

static int targetgeohint(lua_State* ctx)
{
/* latitude, longitude, elevation, timezone, country, spoken-lang, written-lang */
	LUA_TRACE("target_geohint");

	arcan_vobject* vobj;
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, &vobj);
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	int numind = 2;
	file_handle fd = BADFD;

	if (!fsrv || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
		arcan_fatal("target_geohint() -- " FATAL_MSG_FRAMESERV);
	}

	const char* country = luaL_checkstring(ctx, 4);
	const char* written = luaL_checkstring(ctx, 5);
	const char* spoken = luaL_checkstring(ctx, 6);

	if (strlen(country) != 3)
		arcan_fatal("target_geohint(country) - expected ISO-3166-1-alpha3");

	if (strlen(written) != 3)
		arcan_fatal("target_geohint(written language) - expected ISO-639-2-alpha 3");

	if (strlen(spoken) != 3)
		arcan_fatal("target_geohint(spoken language) - expected ISO-639-2-alpha 3");

	arcan_event outev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_GEOHINT,
		.tgt.ioevs[0].fv = luaL_checknumber(ctx, 1), /* latitude */
		.tgt.ioevs[1].fv = luaL_checknumber(ctx, 2), /* longitude */
		.tgt.ioevs[2].fv = luaL_checknumber(ctx, 3), /* elevation */
		.tgt.ioevs[3].cv = {country[0], country[1], country[2]},
		.tgt.ioevs[4].cv = {spoken[0],   spoken[1],  spoken[2]},
		.tgt.ioevs[5].cv = {written[0], written[1], written[2]},
		.tgt.ioevs[6].iv = luaL_checknumber(ctx, 7) /* gm_offset tz */
	};

	tgtevent(tgt, outev);
	LUA_ETRACE("target_geohint", NULL, 0);
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
			fd = BADFD;
			char* fname = arcan_find_resource(
				instr, RESOURCE_SYS_FONT, ARES_FILE | ARES_RDONLY, &fd);
			arcan_mem_free(fname);
			if (BADFD == fd){
				lua_pushboolean(ctx, false);
				LUA_ETRACE("target_fonthint", "font could not be opened", 1);
			}
		}
	}

	float sz = luaL_checknumber(ctx, numind);
	int hint = luaL_checknumber(ctx, numind+1);
	int slot = luaL_optbnumber(ctx, numind+2, 0);

	arcan_event outev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_FONTHINT,
		.tgt.ioevs[1].iv = fd != BADFD ? 1 : 0,
		.tgt.ioevs[2].fv = sz,
		.tgt.ioevs[3].iv = hint,
		.tgt.ioevs[4].iv = slot
	};

/* update the font reference data inside the frameserver as well, used for
 * segments that draw with TPACK format - this may update the cell size which
 * may in turn cause a DISPLAYHINT to be emitted */
	bool send_dh = slot == 0 && sz != fsrv->desc.text.szmm &&
		fsrv->desc.hint.last.tgt.kind == TARGET_COMMAND_DISPLAYHINT;

/* this may duplicate the fd in order to save for later */
	arcan_frameserver_setfont(fsrv, fd, sz, hint, slot);

	if (send_dh)
		platform_fsrv_pushevent(fsrv, &fsrv->desc.hint.last);

	if (fd != BADFD){
		lua_pushboolean(ctx, platform_fsrv_pushfd(fsrv, &outev, fd));
		close(fd);
	}
	else{
		lua_pushboolean(ctx, ARCAN_OK == platform_fsrv_pushevent(fsrv, &outev));
	}

	lua_pushnumber(ctx, fsrv->desc.text.cellw);
	lua_pushnumber(ctx, fsrv->desc.text.cellh);

	LUA_ETRACE("target_fonthint", NULL, 3);
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

static void* pthr_waiter(void* src)
{
	pid_t* pid = src;
	for(;;){
		int status;
		int rc = waitpid(*pid, &status, 0);
		if (-1 == rc && errno == ECHILD)
			break;

		if (WIFEXITED(status))
			break;
	}
	free(pid);
	return NULL;
}

static int targetdevhint(lua_State* ctx)
{
	LUA_TRACE("target_devicehint");
	arcan_vobject* vobj;
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, &vobj);
	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("target_devicehint(), vid not connected to a frameserver\n");

	arcan_frameserver* fsrv = (arcan_frameserver*) vobj->feed.state.ptr;

	int type = lua_type(ctx, 2);

/* integer- type, switch physical device */
	if (type == LUA_TNUMBER){
		int num = luaL_checknumber(ctx, 2);

/* negative number: just switch mode of operation */
		if (num < 0){
			platform_fsrv_pushevent(fsrv, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_DEVICE_NODE,
				.tgt.ioevs[0].iv = BADFD,
				.tgt.ioevs[1].iv = 1,
				.tgt.ioevs[2].iv = xlt_dev(luaL_optnumber(ctx, 3, DEVICE_INDIRECT))
			});
		}
/* card- reference, extract device handle for the mode in question */
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
				.tgt.ioevs[2].iv = xlt_dev(luaL_optnumber(ctx, 3, DEVICE_INDIRECT)),
				.tgt.ioevs[3].iv = method,
				.tgt.ioevs[4].iv = buf_sz
			};
			memcpy(ev.tgt.message, buf, buf_sz);
			arcan_mem_free(buf);
			platform_fsrv_pushfd(fsrv, &ev, fd);
		}
	}
/* string reference, switch render-node */
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

/* we require a real string for the connection path if forced */
		if (force){
			if (strlen(cpath) == 0)
				arcan_fatal("target_devicehint(), forced migration connpath len == 0\n");

/* Enabling opt-in migration on a non-auth frameserver means disabling the normal
 * processing and checks, otherwise the client can be killed after migration and
 * the shutdown-on-dms event might not get triggered when dpipe dies. BUT! this
 * also means that the subprocess reaping won't be handled should the client die
 * while migrated. Awesome. We basically need to spawn a waitpid- thread for
 * this not to race. */
			if (fsrv->child != BROKEN_PROCESS_HANDLE){
				pthread_attr_t jattr;
				pthread_t pthr;
				pthread_attr_init(&jattr);
				pthread_attr_setdetachstate(&jattr, PTHREAD_CREATE_DETACHED);
				pid_t* pid = malloc(sizeof(pid_t));
				*pid = fsrv->child;
				fsrv->child = BROKEN_PROCESS_HANDLE;
				pthread_create(&pthr, NULL, pthr_waiter, (void*) pid);
			}
		}

/* This is obviously not correct, need a better sanity check and encode as
 * multipart (.tgt.code = 1) chunks, pre-checking the queue for n parts
 * before sending */
		if (strlen(cpath) > COUNT_OF(outev.tgt.message)){
			arcan_warning("address length exceeds boundary, truncated");
		}
		snprintf(outev.tgt.message, COUNT_OF(outev.tgt.message), "%s", cpath);
		platform_fsrv_pushevent(fsrv, &outev);
	}
		else
			arcan_fatal("target_devicehint(), argument misuse");

	LUA_ETRACE("target_devicehint", NULL, 0);
}

static int targetdisphint(lua_State* ctx)
{
	LUA_TRACE("target_displayhint");

	arcan_vobject* vobj;
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, &vobj);

/* non fsrv vid is terminal state */
	struct arcan_frameserver* fsrv = vobj->feed.state.ptr;
	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV || !fsrv){
		arcan_fatal("target_displayhint() - vid is not a frameserver\n");
	}

	int width = luaL_checknumber(ctx, 2);
	int height = luaL_checknumber(ctx, 3);
	int cont = luaL_optnumber(ctx, 4, 128);
	uint32_t cookie = 0;

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
	else if (type == LUA_TNUMBER){
		arcan_vobject* vobj;
		arcan_vobj_id seg = luaL_checkvid(ctx, 5, &vobj);
		if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
			arcan_warning(
				"target_displayhint() - vid reference not connected to frameserver");
		}
		else {
			cookie = ((arcan_frameserver*)vobj->feed.state.ptr)->cookie;
		}
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

/* forward the rendering relevant information to the frameserver, primarily for
 * TPACK, where the actual pixel-size is set by the server-side rasterizer */
	arcan_frameserver_displayhint(fsrv, width, height, ppcm);

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_DISPLAYHINT,
		.tgt.ioevs[0].iv = width,
		.tgt.ioevs[1].iv = height,
		.tgt.ioevs[2].iv = cont,
		.tgt.ioevs[3].iv = phy_lay,
		.tgt.ioevs[4].fv = ppcm,
/* this is kept updated from _displayhint and _fonthint */
		.tgt.ioevs[5].iv = fsrv->desc.text.cellw,
		.tgt.ioevs[6].iv = fsrv->desc.text.cellh,
		.tgt.ioevs[7].uiv = cookie
	};
	fsrv->desc.hint.last = ev;

	ev.tgt.timestamp = arcan_timemillis();
	tgtevent(tgt, ev);

	lua_pushnumber(ctx, fsrv->desc.text.cellw);
	lua_pushnumber(ctx, fsrv->desc.text.cellh);

	LUA_ETRACE("target_displayhint", NULL, 2);
}

static unsigned int get_vid_token(lua_State* ctx, int ind)
{
	arcan_vobject* vobj;
	arcan_vobj_id parent = luaL_checkvid(ctx, ind, &vobj);

	if (parent == ARCAN_VIDEO_WORLDID)
		return 0;

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
		arcan_fatal("target_anchorhint(vid, ANCHORHINT_SEGMENT, "
			">parent<, ...) not connected to a frameserver");
	}
	arcan_frameserver* fsrv = vobj->feed.state.ptr;
	return fsrv->cookie;
}

static int targetanchor(lua_State* ctx)
{

	LUA_TRACE("target_anchorhint");
	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_ANCHORHINT
	};

	arcan_vobject* vobj;
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, &vobj);

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV){
		arcan_fatal("target_anchorhint(>vid<, ...) not connected to a frameserver");
	}

	int type = luaL_checknumber(ctx, 2);
	bool swap_token = false;
	bool want_source = false;
	int coord_ofs = 4;

	switch (type){
	case CONST_ANCHORHINT_SEGMENT:
		ev.tgt.ioevs[4].uiv = get_vid_token(ctx, 3);
	break;
	case CONST_ANCHORHINT_PROXY:
		ev.tgt.ioevs[3].uiv = get_vid_token(ctx, 3);
		ev.tgt.ioevs[4].uiv = get_vid_token(ctx, 4);
	break;
	case CONST_ANCHORHINT_EXTERNAL:
		ev.tgt.ioevs[4].uiv = luaL_checknumber(ctx, 3);
		ev.tgt.ioevs[5].iv = 1;
		coord_ofs = 5;
	break;
	case CONST_ANCHORHINT_PROXY_EXTERNAL:
		ev.tgt.ioevs[3].uiv = luaL_checknumber(ctx, 3);
		ev.tgt.ioevs[4].uiv = luaL_checknumber(ctx, 4);
		ev.tgt.ioevs[5].iv = 1;
		coord_ofs = 5;
	break;
	default:
		arcan_fatal("target_anchorhint(vid, >type<, ..) invalid type value");
	break;
	}

	ev.tgt.ioevs[0].uiv = luaL_checknumber(ctx, coord_ofs + 0);
	ev.tgt.ioevs[1].uiv = luaL_checknumber(ctx, coord_ofs + 1);
	ev.tgt.ioevs[2].uiv = luaL_optnumber(ctx, coord_ofs + 2, 0);

	tgtevent(vid, ev);
	LUA_ETRACE("target_anchorhint", NULL, 0);
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
	bool time = luaL_optbnumber(ctx, 4, true);

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
			ev.tgt.ioevs[2].iv = luaL_optnumber(ctx, 5, 0);
			ev.tgt.ioevs[3].fv = luaL_optnumber(ctx, 6, 0);
		}
		else {
			ev.tgt.ioevs[1].fv = val;
			ev.tgt.ioevs[2].fv = luaL_optnumber(ctx, 5, -1);
			ev.tgt.ioevs[3].fv = luaL_optnumber(ctx, 6, -1);
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
	TARGET_FLAG_ALLOW_HDR,
	TARGET_FLAG_ALLOW_VOBJ,
	TARGET_FLAG_ALLOW_INPUT,
	TARGET_FLAG_ALLOW_GPUAUTH,
	TARGET_FLAG_LIMIT_SIZE,
	TARGET_FLAG_SYNCH_SIZE,
	TARGET_FLAG_NO_ADOPT,
	TARGET_FLAG_DRAIN_QUEUE,
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

	case TARGET_FLAG_NO_ADOPT:
		fsrv->flags.no_adopt = toggle;
	break;

	case TARGET_FLAG_ALLOW_CM:
		if (toggle)
			fsrv->metamask |= SHMIF_META_CM;
		else
			fsrv->metamask &= ~SHMIF_META_CM;
	break;

	case TARGET_FLAG_ALLOW_HDR:
		if (toggle)
			fsrv->metamask |= SHMIF_META_HDR;
		else
			fsrv->metamask &= ~SHMIF_META_HDR;
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

	case TARGET_FLAG_SYNCH_SIZE:
		fsrv->flags.rz_ack = toggle;
	break;

	case TARGET_FLAG_DRAIN_QUEUE:
		if (toggle)
			fsrv->xfer_sat = -1.0;
		else
			fsrv->xfer_sat = 0.5;
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

	bool val = luaL_optbnumber(ctx, 3, false);
	const char* descr_a = luaL_optstring(ctx, 4, "*");
	const char* descr_b = luaL_optstring(ctx, 5, descr_a);

	int pair[2];
	if (pipe(pair) == -1){
		arcan_warning("bond_target(), pipe pair failed."
			" Reason: %s\n", strerror(errno));
		LUA_ETRACE("bond_target", "pipe failed", 0);
	}

	arcan_frameserver* fsrv_a = vobj_a->feed.state.ptr;
	arcan_frameserver* fsrv_b = vobj_b->feed.state.ptr;

	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = val ? TARGET_COMMAND_BCHUNK_OUT : TARGET_COMMAND_STORE
	};
	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", descr_a);

	platform_fsrv_pushfd(fsrv_a, &ev, pair[1]);

	ev.tgt.kind = val ? TARGET_COMMAND_BCHUNK_IN : TARGET_COMMAND_RESTORE;
	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", descr_b);

	platform_fsrv_pushfd(fsrv_b, &ev, pair[0]);

	close(pair[0]);
	close(pair[1]);

	LUA_ETRACE("bond_target", NULL, 0);
}

static int targetrestore(lua_State* ctx)
{
	LUA_TRACE("restore_target");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	const char* snapkey = luaL_checkstring(ctx, 2);
	const char* descr = luaL_optstring(ctx, 4, "octet-stream");

/* namespace controls COMMAND_ form */
	int ns = luaL_optnumber(ctx, 3, RESOURCE_APPL_STATE);
	int command = TARGET_COMMAND_RESTORE;

/* verify it's a frameserver we are sending to */
	vfunc_state* state = arcan_video_feedstate(tgt);
	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("restore_target", "invalid feedstate", 1);
	}

/* verify namespace for reading */
	if (ns != RESOURCE_APPL_STATE){
		command = TARGET_COMMAND_BCHUNK_IN;
	}

/* resolve from requested namespace, only accept files */
	int fd = BADFD;
	char* fname = arcan_find_resource(
		snapkey, ns, ARES_FILE | ARES_RDONLY, &fd);
	free(fname);

	if (BADFD == fd){
		arcan_warning("couldn't load / resolve (%s)\n", snapkey);
		lua_pushboolean(ctx, false);
		LUA_ETRACE("restore_target", "could not load file", 1);
	}

/* send to recipient, close local handle */
	arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;
	arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = command
	};
	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", descr);

	lua_pushboolean(ctx, ARCAN_OK == platform_fsrv_pushfd(fsrv, &ev, fd));
	close(fd);

	LUA_ETRACE("restore_target", NULL, 1);
}

static int targetstepframe(lua_State* ctx)
{
	LUA_TRACE("stepframe_target");

/* three main paths for this function:
 *
 *  - request a fetch (readback) into local store (synch/asynch),
 *    this can be used internally (calctarget, ...)
 *  - forward this fetch to an external client (recordtarget)
 *  - control frame pacing or activation of an external client
 **/

	arcan_vobject* vobj;
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, &vobj);
	vfunc_state* state = arcan_video_feedstate(tgt);
	struct rendertarget* rtgt = arcan_vint_findrt(vobj);
	arcan_frameserver* fsrv =
		(state->tag == ARCAN_TAG_FRAMESERV ? state->ptr : NULL);

	bool force_synch = luaL_optbnumber(ctx, 3, false);
	bool qev = true;
	int nframes = luaL_optnumber(ctx, 2, 1);

/* [control frame and resize pacing] */
	if (fsrv && !rtgt){
		if (fsrv->flags.rz_ack && nframes == 0){
			if (!fsrv->rz_known){
				LUA_ETRACE("stepframe_target", "rz_ack not in rz_known state", 0);
			}

/* force update / upload */
			fsrv->rz_known++;
			arcan_vint_pollfeed(tgt, true);
			LUA_ETRACE("stepframe_target", NULL, 0);
		}

		arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_STEPFRAME
		};
		ev.tgt.ioevs[0].iv = nframes;
		ev.tgt.ioevs[1].iv = luaL_optnumber(ctx, 3, 0);
		tgtevent(tgt, ev);
		lua_pushboolean(ctx, true);
		LUA_ETRACE("stepframe_target", NULL, 1);
	}

/* request readback into a recordtarget, query / update dirty */
	int x = luaL_optnumber(ctx, 4, -1);
	if (fsrv && x > -1){
		fsrv->desc.region_valid = false;
		int y = luaL_optnumber(ctx, 5, -1);
		int w = luaL_optnumber(ctx, 6, -1);
		int h = luaL_optnumber(ctx, 7, -1);
		if (x > fsrv->desc.width)
			x = 0;
		if (y < 0 || y > fsrv->desc.height)
			y = 0;

		if (w <= 0 || x + w > fsrv->desc.width)
			w = fsrv->desc.width - x;

		if (h <= 0 || y + h > fsrv->desc.height)
			h = fsrv->desc.height - y;

		fsrv->desc.region = (struct arcan_shmif_region){
			.x1 = x, .y1 = y,
			.x2 = x + w, .y2 = y + h
		};
		fsrv->desc.region_valid = true;
	}

/* cascade / repeat call protection, only request read if we aren't in that
 * state already - this is for the asynch behavior */
	if (!FL_TEST(rtgt, TGTFL_READING)){
		agp_request_readback(rtgt->color->vstore);
		FL_SET(rtgt, TGTFL_READING);
		rtgt->transfc++;
		lua_pushboolean(ctx, true);
	}
/* need to communicate that we are stuck */
	else {
		lua_pushboolean(ctx, false);
	}

/* and if the user requested this to actually be synchronous, spin on the
 * readback stage, this is rare / unrecommended for the risk of a stall,
 * safeguard this with a stall timeout and a warning */
	if (force_synch){
		long long start = arcan_timemillis();
		long long elapsed;
		while (FL_TEST(rtgt, TGTFL_READING)){
			if (arcan_timemillis() - start > 1000){
				arcan_warning("pollreadback(), synch-readback safety timeout exceed\n");
				break;
			}
			arcan_vint_pollreadback(rtgt);
		}
	}

	LUA_ETRACE("stepframe_target", NULL, 1);
}

static int targetsnapshot(lua_State* ctx)
{
	LUA_TRACE("snapshot_target");

	arcan_vobj_id tgt = luaL_checkvid(ctx, 1, NULL);
	const char* snapkey = luaL_checkstring(ctx, 2);
	const char* descr = luaL_optstring(ctx, 4, "octet-stream");

/* pick command based on the targeted namespace, for db- defined user
 * namespaces, we should differentiate on type here so strings gets
 * resolved against db, e.g. ns_name => {r, w, x /path} */
	int ns = luaL_optnumber(ctx, 3, RESOURCE_APPL_STATE);
	int command = TARGET_COMMAND_STORE;

/* verify that it is a safe namespace for writing */
	if (ns != RESOURCE_APPL_STATE){
		if (ns && CREATE_USERMASK){
			command = TARGET_COMMAND_BCHUNK_OUT;
		}
		else {
			lua_pushboolean(ctx, false);
			LUA_ETRACE("snapshot_target", "invalid namespace", 1);
		}
	}

/* verify that we are targeting a vobj in a frameserver state */
	vfunc_state* state = arcan_video_feedstate(tgt);
	if (!state || state->tag != ARCAN_TAG_FRAMESERV || !state->ptr){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("snapshot_target", "invalid feedstate", 1);
	}
	arcan_frameserver* fsrv = state->ptr;

/* actually resolve the name and grab the descriptor, note that we
 * don't really have a good setup for figuring out when the writing
 * is finished, as otherwise a deferred job or commit- stage would
 * be better so we could atomically CAS rather than trunc-write */
	int fd = -1;
	char* fname = arcan_find_resource(
		snapkey, ns, ARES_FILE | ARES_CREATE, &fd);
	arcan_mem_free(fname);

	if (-1 == fd){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("snapshot_target", "couldn't create file", 1);
	}

	arcan_event ev = {
		.category = EVENT_TARGET, .tgt.kind = command
	};
	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", descr);
	lua_pushboolean(ctx, platform_fsrv_pushfd(fsrv, &ev, fd));
	close(fd);
	LUA_ETRACE("snapshot_target", NULL, 1);
}

static int targetreset(lua_State* ctx)
{
	LUA_TRACE("reset_target");

	arcan_vobject* vobj;
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, &vobj);
	bool hard = luaL_optbnumber(ctx, 2, false) != 0;

	arcan_event ev = {
		.tgt.kind = TARGET_COMMAND_RESET,
		.category = EVENT_TARGET,
		.tgt.ioevs[0].iv = hard ? 1 : 0
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
	struct arcan_frameserver* parent,
	enum ARCAN_SEGID segid, uint8_t hints,
	uint32_t reqid, size_t w, size_t h)
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
		platform_fsrv_spawn_subsegment(parent, segid, hints, w, h, newvid, reqid);

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
		segid, luactx.last_segreq->segreq.hints,
		luactx.last_segreq->segreq.id, w, h
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
/* another fun bit, the monitoring child for internally launched processes
 * is dangerous as the pid itself won't be known, causing the child termination
 * to shut down the parent in some edge cases
 */
		newref->child = -1;
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

/* this should be cleaned up in the platform layer to store the string
 * in the fsrv, then use hash(key | challenge) and send challenge on
 * connect. */
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
		cb_ind = 3;
	}

/* height fields are typically not useful before activation except for the case
 * of a primary with encode type (that can't be dynamically resized). */
	size_t init_w = 32;
	size_t init_h = 32;
	if (lua_type(ctx, cb_ind) == LUA_TNUMBER){
		if (lua_type(ctx, cb_ind+1) != LUA_TNUMBER){
			arcan_fatal(
				"target_alloc(), argument error, expected number (height)\n");
		}
		init_w = luaL_checknumber(ctx, cb_ind+0);
		init_h = luaL_checknumber(ctx, cb_ind+1);
		cb_ind += 2;
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

		if (lua_type(ctx, cb_ind+2) == LUA_TBOOLEAN && lua_toboolean(ctx, cb_ind+2))
			segid |= (1 << 31);
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
			newref = platform_launch_listen_external(key,
				pw, luactx.pending_socket_descr, ARCAN_SHM_UMASK, init_w, init_h, ref);
			arcan_mem_free(luactx.pending_socket_label);
			luactx.pending_socket_label = NULL;
		}
		else
			newref = platform_launch_listen_external(
				key, pw, -1, ARCAN_SHM_UMASK, init_w, init_h, ref);

		if (!newref){
			LUA_ETRACE("target_alloc", "couldn't listen on external", 0);
		}

		arcan_conductor_register_frameserver(newref);
	}
	else {
		arcan_vobj_id srcfsrv = luaL_checkvid(ctx, 1, NULL);
		vfunc_state* state = arcan_video_feedstate(srcfsrv);
		if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr){
			newref = spawn_subsegment(
				(arcan_frameserver*) state->ptr, segid, 0, tag, init_w, init_h);
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
	lua_pushnumber(ctx, newref->cookie);

	trace_allocation(ctx, "target", newref->vid);
	LUA_ETRACE("target_alloc", NULL, 3);
}

static int targetlaunch(lua_State* ctx)
{
	LUA_TRACE("launch_target");
	size_t rc = 0;
	int ofs = 2;
	int lmode = LAUNCH_INTERNAL;

	const char* tname = luaL_checkstring(ctx, 1);
	const char* cfg = "default";

	if (lua_type(ctx, 2) == LUA_TSTRING){
		cfg = lua_tostring(ctx, 2);
		ofs++;
	}

	arcan_configid cid = arcan_db_configid(DBHANDLE,
		arcan_db_targetid(DBHANDLE, tname, NULL), cfg);

	if (lua_type(ctx, ofs) == LUA_TNUMBER){
		lmode = lua_tonumber(ctx, ofs++);
	}

	if (lmode != LAUNCH_EXTERNAL && lmode != LAUNCH_INTERNAL)
		arcan_fatal("launch_target(), "
			"invalid mode -- expected LAUNCH_INTERNAL or LAUNCH_EXTERNAL ");

	intptr_t ref = find_lua_callback(ctx);

	struct arcan_strarr argv, env, libs = {0};
	enum DB_BFORMAT bfmt;
	argv = env = libs;

	char* exec = arcan_db_targetexec(DBHANDLE, cid, &bfmt, &argv, &env, &libs);

/* means strarrs won't be populated, this is not fatal due to the race potential
 * with external modification of the database TOCTU */
	if (!exec){
		arcan_warning("launch_target(), failed -- invalid configuration\n");
		LUA_ETRACE("launch_target", "invalid configuration", 0);
	}

	if (lmode == LAUNCH_EXTERNAL){
		if (bfmt != BFRM_EXTERN){
			arcan_warning("launch_target(), failed -- binary format not suitable "
				" for external launch.");
			goto cleanup;
		}

		int retc = EXIT_FAILURE;
		if (arcan_video_prepare_external(false) == false){
			arcan_warning("Warning, arcan_target_launch_external(), "
				"couldn't push current context, aborting launch.\n");
			goto cleanup;
		}

		unsigned long tv =
			arcan_target_launch_external(exec, &argv, &env, &libs, &retc);
		lua_pushnumber(ctx, retc);
		lua_pushnumber(ctx, tv);
		rc = 2;
		arcan_video_restore_external(false);

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

	case BFRM_GAME:
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
		lua_pushnumber(ctx, intarget->cookie);
		trace_allocation(ctx, "launch", intarget->vid);
		rc = 3;
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
	bool norm = luaL_optbnumber(ctx, 2, true) != 0;

	struct rendertarget* rtgt = arcan_vint_findrt(vobj);
	if (!rtgt)
		arcan_fatal("rendertarget_forceupdate(), specified vid "
			"does not reference a rendertarget");

/* the second form is used to change the update (and readback) rate */
	if (lua_isnumber(ctx, 2)){
		rtgt->refresh = luaL_checknumber(ctx, 2);
		rtgt->refreshcnt = abs(rtgt->refresh);

		if (lua_isnumber(ctx, 3)){
			rtgt->readback = luaL_checknumber(ctx, 3);
			rtgt->readcnt = abs(rtgt->readback);
		}
	}
/* there are special considerations here if the rendertarget is mapped, as that
 * means its 'dirty' state would be erased when the time comes for the display
 * to be updated - this is delegated to the video-platform implementation and
 * doesn't need to be covered here */
	else {
		bool forcedirty = true;
		if (lua_isboolean(ctx, 2)){
			forcedirty = lua_toboolean(ctx, 2);
		}

		if (ARCAN_OK != arcan_video_forceupdate(vid, forcedirty))
			arcan_fatal("rendertarget_forceupdate() failed on vid");
	}

	LUA_ETRACE("rendertarget_forceupdate", NULL, 0);
}

struct transform_cs {
	size_t blend;
	size_t move;
	size_t rotate;
	size_t scale;
};

static void clock_transform(arcan_vobject* vobj, struct transform_cs* dst)
{
	surface_transform* current = vobj->transform;
	while (current){
		size_t tc = current->blend.endt ? current->blend.endt - luactx.last_clock : 0;
		if (tc > dst->blend)
			dst->blend = tc;

		tc = current->move.endt ? current->move.endt - luactx.last_clock : 0;
		if (tc > dst->move)
			dst->move = tc;

		tc = current->rotate.endt ? current->rotate.endt - luactx.last_clock : 0;
		if (tc > dst->rotate)
			dst->rotate = tc;

		tc = current->scale.endt ? current->scale.endt - luactx.last_clock : 0;
		if (tc > dst->scale)
			dst->scale = tc;

		current = current->next;
	}
}

static int rendertargetmetrics(lua_State* ctx)
{
	LUA_TRACE("rendertarget_metrics");
	arcan_vobject* vobj;
	arcan_vobj_id vid = luaL_checkvid(ctx, 1, &vobj);
	struct rendertarget* rtgt = arcan_vint_findrt(vobj);

	if (!rtgt)
		arcan_fatal("rendertarget_metrics()"
			", specified vid does not reference a rendertarget");

	lua_newtable(ctx);
	lua_pushliteral(ctx, "dirty");
	lua_pushnumber(ctx, rtgt->dirtyc);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "transfers");
	lua_pushnumber(ctx, rtgt->uploadc);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "updates");
	lua_pushnumber(ctx, rtgt->transfc);
	lua_rawset(ctx, -3);

/* get the clock horizon by sweeping all vobjects that attach to the
 * rendertarget and taking the transform with the deepest clock */
	arcan_vobject_litem* current = rtgt->first;
	struct transform_cs cs = {.blend = 0};
	while (current){
		clock_transform(current->elem, &cs);
		current = current->next;
	}

	lua_pushliteral(ctx, "time_move");
	lua_pushnumber(ctx, cs.move);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "time_blend");
	lua_pushnumber(ctx, cs.blend);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "time_scale");
	lua_pushnumber(ctx, cs.scale);
	lua_rawset(ctx, -3);

	lua_pushliteral(ctx, "time_rotate");
	lua_pushnumber(ctx, cs.rotate);
	lua_rawset(ctx, -3);

	LUA_ETRACE("rendertarget_metrics", NULL, 1);
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

/* this is already dangerously low */
	if (hppcm < 18.0)
		hppcm = 18.0;

	if (vppcm < 18.0)
		vppcm = 18.0;

	if (did == ARCAN_VIDEO_WORLDID){
		arcan_lua_setglobalint(ctx, "VPPCM", vppcm);
		arcan_lua_setglobalint(ctx, "HPPCM", hppcm);
	}

	arcan_video_rendertargetdensity(did, vppcm, hppcm, true, true);
	LUA_ETRACE("rendertarget_reconfigure", NULL, 0);
}

static int rendertargetrange(lua_State* ctx)
{
	LUA_TRACE("rendertarget_range");
	arcan_vobj_id did = luaL_checkvid(ctx, 1, NULL);
	ssize_t min = luaL_optnumber(ctx, 2, -1);
	ssize_t max = luaL_optnumber(ctx, 3, -1);
	arcan_video_rendertarget_range(did, min, max);
	LUA_ETRACE("rendertarget_range", NULL, 0);
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
	arcan_vobj_id cattach = arcan_video_currentattachment();

	if (did != ARCAN_EID)
		arcan_video_defaultattachment(did);

	lua_pushvid(ctx, cattach);
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

 	lua_pushnumber(src->ctx, width);
	lua_pushnumber(src->ctx, height);
	alt_call(src->ctx, CB_SOURCE_IMAGE, 0, 3, 0, "calc_target:callback");
	ud->valid = false;

	return 0;
}

static int imagemetadata(lua_State* ctx)
{
	LUA_TRACE("image_metadata");
	arcan_vobject* vobj;
	luaL_checkvid(ctx, 1, &vobj);
	if (vobj->vstore->txmapped != TXSTATE_TEX2D){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("image_metadata", "storage_type mismatch", 1);
	}

	const char* model = luaL_checkstring(ctx, 2);
	if (strcmp(model, "drmv1") != 0){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("image_metadata", "metadata model missing", 1);
	}

	if (lua_type(ctx, 3) != LUA_TTABLE){
		lua_pushboolean(ctx, false);
		arcan_fatal("image_metadata(, , >tbl< ) expected table");
		LUA_ETRACE("image_metadata", "expected table for coordinates", 1);
	}

	int ncords = lua_rawlen(ctx, 3);
	if (ncords < 8){
		arcan_fatal("image_metadata(), wrong coordinate set");
		lua_pushboolean(ctx, false);
		LUA_ETRACE("image_metadata", "expected 10 coordinates (rgb,w)", 1);
	}

	float coords[8];
	for (size_t i = 0; i < 8; i++){
		lua_rawgeti(ctx, 3, i+1);
		coords[i] = lua_tonumber(ctx, -1);
		lua_pop(ctx, 1);
	}

	struct drm_hdr_meta meta = {
		.rx = coords[0],
		.ry = coords[1],
		.gx = coords[2],
		.gy = coords[3],
		.bx = coords[4],
		.by = coords[5],
		.wpx = coords[6],
		.wpy = coords[7]
	};

	meta.master_min = luaL_checknumber(ctx, 4);
	meta.master_max = luaL_checknumber(ctx, 5);
	meta.cll = luaL_checknumber(ctx, 6);
	meta.fll = luaL_checknumber(ctx, 7);

	vobj->vstore->hdr.model = 1;
	vobj->vstore->hdr.drm = meta;

	lua_pushboolean(ctx, true);
	LUA_ETRACE("image_metadata", NULL, 1);
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

	alt_call(ctx, CB_SOURCE_IMAGE, 0, 3, 0, "calctarget:callback");

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
		spawn_subsegment(fsrv, SEGID_ENCODER, 0, 0, 0, 0);

	if (!rv){
		arcan_warning("spawn_recsubseg() -- "
			"operation failed, couldn't attach output segment.\n");
		return 0;
	}

	vfunc_state fftag = {
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = rv
	};

/* grab the requested callback and tag with */
	if (lua_isfunction(ctx, 9) && !lua_iscfunction(ctx, 9)){
		lua_pushvalue(ctx, 9);
		rv->tag = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}

/* shmpage prepared, force dimensions based on source with a single buffer*/
	arcan_vobject* dobj = arcan_video_getobject(did);
	struct arcan_shmif_page* shmpage = rv->shm.ptr;
	shmpage->w = dobj->vstore->w;
	shmpage->h = dobj->vstore->h;
	rv->vbuf_cnt = rv->abuf_cnt = 1;
	arcan_shmif_mapav(shmpage, rv->vbufs, 1, dobj->vstore->w *
		dobj->vstore->h * sizeof(shmif_pixel), rv->abufs, 1, 32768);
	arcan_video_alterfeed(did, FFUNC_AVFEED, fftag);

/* similar restrictions and problems as in spawn_recfsrv with the
 * hooking chicken-and-egg problem */
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
		char* fn = arcan_find_resource(resf,
			CREATE_USERMASK, ARES_FILE | ARES_CREATE, &fd);

/* it is currently allowed to "record over" an existing file without forcing
 * the caller to use zap_resource first, this should possibly be reconsidered*/
		if (!fn){
			arcan_warning(
				"couldn't create output (%s), recorded data will be lost\n", fn);
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

	mvctx->flags.activated = 1;
	tgtevent(did, (arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_ACTIVATE
	});

	return 0;
}

static int renderbind(lua_State* ctx)
{
	LUA_TRACE("rendertarget_bind");
	arcan_vobject* rt_vobj;
	arcan_vobject* fsrv_vobj;

	arcan_vobj_id rt = luaL_checkvid(ctx, 1, &rt_vobj);
	arcan_vobj_id fsrvid = luaL_checkvid(ctx, 2, &fsrv_vobj);

	struct rendertarget* rtgt = arcan_vint_findrt(rt_vobj);
	if (!rtgt)
		arcan_fatal("rendertarget_bind(), 1[src] vid is not a rendertarget\n");

	if (fsrv_vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("rendertarget_bind(), 2[dst] vid is not a frameserver\n");

	struct arcan_frameserver* fsrv = fsrv_vobj->feed.state.ptr;
	if (fsrv->segid != SEGID_ENCODER && fsrv->segid != SEGID_CLIPBOARD_PASTE)
		arcan_fatal("rendertarget_bind(), 2[dst] is not an encoder type\n");

/* synch the src- size with the dst size */
	agp_resize_rendertarget(rtgt->art, fsrv->desc.width, fsrv->desc.height);
	rtgt->readback = rtgt->refresh;
	rtgt->readcnt = abs(rtgt->readcnt);
	fsrv->vid = rt;

/* bind the new rendertarget as recipient */
	arcan_video_alterfeed(rt, FFUNC_AVFEED,
		(vfunc_state){ .tag = ARCAN_TAG_FRAMESERV, .ptr = fsrv});

/* and pacify the source video (can be deleted) */
	arcan_video_alterfeed(fsrvid, FFUNC_NULLFRAME,
		(vfunc_state){ .tag = ARCAN_TAG_IMAGE, .ptr = NULL});

/* rewrite pending events so that they won't get attributed to the source */
	arcan_event dummy;
	arcan_event_repl(arcan_event_defaultctx(), EVENT_EXTERNAL,
		offsetof(arcan_event, ext.source),
		sizeof(dummy.ext.source), &fsrvid,
		offsetof(arcan_event, ext.source),
		sizeof(dummy.ext.source), &rt
	);

	LUA_ETRACE("rendertarget_bind", NULL, 0);
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

	const char* type = "clipboard";
	if (lua_type(ctx, 2) == LUA_TSTRING)
		type = luaL_checkstring(ctx, 2);

	int encoder_type = SEGID_ENCODER;
	if (strcmp(type, "clipboard") == 0)
		encoder_type = SEGID_CLIPBOARD_PASTE;
	else
		arcan_warning("define_nulltarget(), unknown subtype, assuming encoder.\n");

	arcan_frameserver* rv = spawn_subsegment(
		(arcan_frameserver*) state->ptr, encoder_type, 0, 0, 1, 1);

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
			0, 0, sobj->vstore->w, sobj->vstore->h);

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
	{.msg = "media", .val = SEGID_MEDIA},
	{.msg = "accessibility", .val = SEGID_ACCESSIBILITY},
	{.msg = "hmd-l", .val = SEGID_HMD_L},
	{.msg = "hmd-r", .val = SEGID_HMD_R}
};

enum ARCAN_SEGID str_to_segid(const char* str)
{
	for (size_t i = 0; i < COUNT_OF(seglut); i++)
		if (strcmp(seglut[i].msg, str) == 0)
			return seglut[i].val;

	return SEGID_UNKNOWN;
}

static int arcanset(lua_State* ctx)
{
	LUA_TRACE("define_arcantarget");

/* for storage -  will eventually be swapped for the active shmif connection
 * buffer (or well, in some cases) - depending on the context it might make
 * more sense to say, copy+forward if the resource itself is static */
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

	intptr_t ref = find_lua_callback(ctx);
	if (LUA_NOREF == ref)
		arcan_fatal("define_arcantarget(), no event handler provided");

/* setup as a normal rt- then in the platform synch it will be checked for
 * dirty state like any normal rt-, though if handle passing gets disabled for
 * it, it will switch to the readback- like double-buffered setup in the
 * arcan/video.c platform */
	if (ARCAN_OK !=
		arcan_video_setuprendertarget(did, -1, -1, false, RENDERTARGET_COLOR)){
		arcan_warning("define_arcantarget(), setup rendertarget failed.\n");
		lua_pushboolean(ctx, false);
		LUA_ETRACE("define_arcantarget", NULL, 1);
	}

	for (size_t i = 0; i < nvids; i++){
		lua_rawgeti(ctx, 3, i+1);
		arcan_vobj_id setvid = luavid_tovid( lua_tointeger(ctx, -1) );
		lua_pop(ctx, 1);

		if (setvid == ARCAN_VIDEO_WORLDID)
			arcan_fatal("define_arcantarget(), using WORLDID as a direct source is "
				"not permitted, create a null_surface and use image_sharestorage. ");

		arcan_video_attachtorendertarget(did, setvid, true);
	}

	lua_pushboolean(ctx, platform_lwa_allocbind_feed(ctx, did, type, ref));
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

	arcan_vobject* dvobj, (* dfsrv_vobj);
	arcan_vobj_id did = luaL_checkvid(ctx, 1, &dvobj);

	if (dvobj->vstore->txmapped != TXSTATE_TEX2D)
		arcan_fatal("define_recordtarget(), recordtarget "
			"recipient must have a texture- based store.");

	const char* resf = NULL;
	char* argl = NULL;
	arcan_vobj_id dfsrv = ARCAN_EID;

	if (lua_type(ctx, 2) == LUA_TNUMBER){
		dfsrv = luaL_checkvid(ctx, 2, &dfsrv_vobj);
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

			if (arcan_audio_kind(setaid) != AOBJ_STREAM &&
				arcan_audio_kind(setaid) != AOBJ_CAPTUREFEED){
				arcan_warning("recordset(), unsupported AID source type,"
					" only STREAMs currently supported. Audio recording disabled.\n");
				free(aidlocks);
				aidlocks = NULL;
				naids = 0;
				char* ol = arcan_alloc_mem(strlen(argl ? argl : "") + sizeof(
					":noaudio=true"), ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);

				sprintf(ol, "%s%s", argl, ":noaudio=true");
				free(argl);
				argl = ol;
				break;
			}

			aidlocks[i] = setaid;
		}
	}

/* Append the 'no audio sources' string even if it was not provided, this
 * is a workaround for the dated design of this part of the API and noaudio
 * was a common mistake in the encoder stage. Might be reconsidered for 0.7 */
	if (naids == 0 && (!argl || !strstr(argl, "noaudio=true"))){
		char* ol = arcan_alloc_mem(strlen(argl ? argl : "") + sizeof(
			":noaudio=true"), ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);
		sprintf(ol, "%s%s", argl, ":noaudio=true");
		free(argl);
		argl = ol;
	}

/* We are spawning into a vid, meaning to create a new subsegment,
 * bind to the rendertarget and push into the client */
	if (dfsrv != ARCAN_EID){
		rc = spawn_recsubseg(ctx, did, dfsrv, naids, aidlocks);
	}
/* We are not spawning into a vid, meaning that a new encode_ frameserver
 * setup is requeted, similar path like the others, but with the added
 * problem of launching and inheriting */
	else
		rc = spawn_recfsrv(ctx, did, dfsrv, naids, aidlocks, argl, resf);

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

static int benchtracedata(lua_State* ctx)
{
	LUA_TRACE("benchmark_tracedata");
	if (!arcan_trace_enabled)
		LUA_ETRACE("benchmark_tracedata", NULL, 0);

/* str: subsys, message, quantity, trigger, perfpath */
	const char* subsys = luaL_checkstring(ctx, 1);
	const char* message = luaL_checkstring(ctx, 2);

	int ident = luaL_optnumber(ctx, 3, 0);
	int quant = luaL_optnumber(ctx, 4, 1);

	int trigger = luaL_optnumber(ctx, 5, 0);
	if (trigger < 0 || trigger > 2){
		arcan_fatal("benchmark_tracedata, "
			"invalid trigger value (%d) >= 0 <= 2\n", trigger);
	}

	int level = luaL_optnumber(ctx, 6, TRACE_SYS_DEFAULT);
	if (level < 0 || level > TRACE_SYS_ERROR){
		arcan_fatal("benchmark_tracedata, invalid value, "
			"expecting: TRACE_PATH_DEFAULT, SLOW, FAST, WARN or ERROR\n");
	}

	lua_Debug ar;
	lua_getstack(ctx, 2, &ar);
	lua_getinfo(ctx, "nSl", &ar);

	arcan_trace_mark("lua", subsys, trigger, level, ident, quant, message, ar.short_src, ar.name, ar.currentline);

	LUA_ETRACE("benchmark_tracedata", NULL, 0);
}

extern arcan_benchdata benchdata;
static int togglebench(lua_State* ctx)
{
	LUA_TRACE("benchmark_enable");

/* trigger existing */
	arcan_trace_setbuffer(NULL, 0, NULL);
	alt_trace_finish(ctx);

/* callback form? allocate collection buffer and enable tracing */
	intptr_t callback = find_lua_callback(ctx);
	if (lua_type(ctx, 1) == LUA_TNUMBER && callback){
		size_t buf_sz = lua_tonumber(ctx, 1) * 1024;
		if (!alt_trace_start(ctx, callback, buf_sz)){
			LUA_ETRACE("benchmark_enable", "out-of-memory", 0);
		}
		LUA_ETRACE("benchmark_enable", NULL, 0);
	}

/* simple form? normal benchmarking */
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

static int getapplarguments(lua_State* ctx)
{
	LUA_TRACE("appl_arguments");
	const char** argv = luactx.last_argv;
	int argc = 0;
	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	while (argv && argv[argc]){
		lua_pushnumber(ctx, argc+1);
		lua_pushstring(ctx, argv[argc++]);
		lua_rawset(ctx, top);
	}

	LUA_ETRACE("appl_arguments", NULL, 1);
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

	case -1:
		lua_pushnumber(ctx, arcan_timemicros());
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

/* whenever we manually set a uniform, all users of that shader should be
 * marked dirty - but the argument form to flag_dirty does not yet consider
 * type so this will cause a full invalidation */
	FLAG_DIRTY();
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

static int setblendmode(lua_State* ctx)
{
	LUA_TRACE("switch_default_blendmode");
	int num = luaL_checknumber(ctx, 1);

	if (!validblendmode(num))
		arcan_video_default_blendmode(num);
	else
		arcan_fatal("setblendmode(%d): "
			"invalid blend mode specified, expected BLEND_NORMAL or BLEND_FORCE");

	LUA_ETRACE("switch_default_blendmode", NULL, 0);
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
	else if (strcmp(smode, "forget") == 0)
		mode = ARCAN_ANALOGFILTER_FORGET;
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
	case ARCAN_ANALOGFILTER_FORGET:
		tblstr(ctx, "mode", "forget", ttop);
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
			tbldynstr(ctx, "label", platform_event_devlabel(devid), ttop);
			tblnum(ctx, "devid", devid, ttop);
			return 1;
		}

		return 0;
	}

	lua_newtable(ctx);
	int ttop = lua_gettop(ctx);
	tblnum(ctx, "devid", devid, ttop);
	tblnum(ctx, "subid", axid, ttop);
	tbldynstr(ctx, "label", platform_event_devlabel(devid), ttop);
	tblnum(ctx, "upper_bound", ubound, ttop);
	tblnum(ctx, "lower_bound", lbound, ttop);
	tblnum(ctx, "deadzone", dz, ttop);
	tblnum(ctx, "kernel_size", ksz, ttop);
	tblanalogenum(ctx, ttop, mode);

	return 1;
}

static int targetfocus(lua_State* ctx)
{
	LUA_TRACE("focus_target");
	arcan_vobject* vobj;
	arcan_vobj_id checkv = luaL_optnumber(ctx, 1, ARCAN_VIDEO_WORLDID);
	if (checkv == ARCAN_VIDEO_WORLDID){
		arcan_conductor_focus(NULL);
	}
	else {
		arcan_vobj_id id = luaL_checkvid(ctx, 1, &vobj);
		if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV || !vobj->feed.state.ptr)
			arcan_fatal("focus_target(fsrv) fsrv arg. not tied to a frameserver");

		arcan_frameserver* fsrv = vobj->feed.state.ptr;
		arcan_conductor_focus(fsrv);
	}

	LUA_ETRACE("focus_target", NULL, 0);
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
			tbldynstr(ctx, "label", platform_event_devlabel(devid), ttop);
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

	int infd = -1;
	char* fname = arcan_find_resource(
		resstr, CREATE_USERMASK, ARES_FILE | ARES_CREATE, &infd);
	if (!fname){
		arcan_warning(
			"save_screeenshot() -- refusing to overwrite existing file.\n");
		goto cleanup;
	}

	if (!fname)
		goto cleanup;
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
	struct frameserver_envp* args, intptr_t callback,
	struct arcan_frameserver** out)
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
	ref->flags.activated = 1;

	lua_pushvid(ctx, ref->vid);
	trace_allocation(ctx, "net", ref->vid);

	if (out)
		*out = ref;
	return true;
}

static int net_listen(lua_State* ctx)
{
	LUA_TRACE("net_listen");

	intptr_t ref = find_lua_callback(ctx);
	if (ref == LUA_NOREF)
		arcan_fatal("net_listen() no handler provided\n");

	const char* name = luaL_checkstring(ctx, 1);
	const char* interface = luaL_optstring(ctx, 2, "");
	size_t port = luaL_optnumber(ctx, 3, 0);
	size_t namelen = strlen(name);

/* same rules as for target_alloc - while the named connection point won't
 * exist in that namespace, it will indirectly through the keystore where the
 * link between the two need to work */
	if (0 == namelen || namelen > 30)
		arcan_fatal("net_listen(), invalid listening name (%s), "
			"length (%zu) should be , 0 < n < 31\n", namelen);

	for (const char* key = name; *key; key++)
		if (!isalnum(*key) && *name != '_' && *key != '-')
			arcan_fatal("net_listen(%s), invalid listening name (%s), "
				" _-a-Z0-9 are permitted in names.\n", key);

	char buf[256];
	snprintf(buf, 256, "name=%s:port=%zu:host=%s", name, port, interface);

/* the resource string won't be aliased but rather copied before exiting
 * launch_fsrv so we will not leave a dangling stack reference behind */
	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = "net-srv",
		.args.builtin.resource = buf
	};

/* no point in exposing the frameserver on script-error migration */
	struct arcan_frameserver* out;
	lua_launch_fsrv(ctx, &args, ref, &out);
	if (out)
		out->flags.no_adopt = true;

	LUA_ETRACE("net_listen", NULL, 1);
}

static int net_discover(lua_State* ctx)
{
	LUA_TRACE("net_discover");

	size_t ofs = 1;
	size_t mode = CONST_DISCOVER_SWEEP;
	size_t trust = CONST_TRUST_KNOWN;
	const char* trustm;
	const char* discm;

	if (lua_type(ctx, ofs) == LUA_TNUMBER){
		mode = lua_tonumber(ctx, ofs);
		ofs++;
	}

	if (lua_type(ctx, ofs) == LUA_TNUMBER){
		trust = lua_tonumber(ctx, ofs);
		ofs++;
	}

	switch (mode){
	case CONST_DISCOVER_SWEEP:
		discm = "sweep";
	break;
	case CONST_DISCOVER_PASSIVE:
		discm = "passive";
	break;
	case CONST_DISCOVER_BROADCAST:
		discm = "broadcast";
	break;
	case CONST_DISCOVER_DIRECTORY:
		discm = "directory";
	break;
	case CONST_DISCOVER_TEST:
		discm = "test";
	break;
	default:
		arcan_fatal("net_discover(): unknown discover mode: %zu", mode);
	}

	switch (trust){
	case CONST_TRUST_KNOWN:
		trustm = "known";
	break;
	case CONST_TRUST_PERMIT_UNKNOWN:
		trustm = "unknown";
	break;
	case CONST_TRUST_TRANSITIVE:
		trustm = "transitive";
	break;
	default:
		arcan_fatal("net_discover(): unknown trust model: %zu", trust);
	break;
	}

	const char* descr = "";
	if (lua_type(ctx, ofs) == LUA_TSTRING){
		descr = lua_tostring(ctx, ofs);
		ofs++;
	}

	intptr_t ref = LUA_NOREF;
	if (lua_isfunction(ctx, ofs) && !lua_iscfunction(ctx, ofs)){
		lua_pushvalue(ctx, ofs);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}
	else
		arcan_fatal("net_discover(): argument error, expected event handler");

	size_t len = sizeof("mode=client:discover=:trust=:opt=") +
		sizeof("directory") + sizeof("transitive") + strlen(descr);

	char* instr =
		arcan_alloc_mem(
			len,
			ARCAN_MEM_STRINGBUF,
			ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL,
			ARCAN_MEMALIGN_NATURAL
		);

	if (!instr){
		lua_pushvid(ctx, ARCAN_EID);
		LUA_ETRACE("net_discover", NULL, 1);
	}

	snprintf(instr, len, "mode=client:discover=%s:trust=%s:opt=%s", discm, trustm, descr);

	struct frameserver_envp args = {
		.args.builtin.mode = "net-cl",
		.use_builtin = true,
		.args.builtin.resource = instr
	};

	lua_launch_fsrv(ctx, &args, ref, NULL);
	arcan_mem_free(instr);

	LUA_ETRACE("net_discover", NULL, 1);
}

static int net_open(lua_State* ctx)
{
	LUA_TRACE("net_open");

	char* host = strdup(luaL_checkstring(ctx, 1));
	intptr_t ref = find_lua_callback(ctx);

/*
 * generate a connection point for the outer monitor to attach to (in order for
 * the types to work), with the parts after : being used to forward identity.
 * A more open question is if this should be recursive, if we net-open an appl
 * over a directory and embed into ourselves, should the communication be routed
 * through the chain or be treated parallel?
 */
 	if (strncmp(host, "@stdin", 6) == 0){
		uint8_t rnd[6];
		char co[13];
		arcan_random(rnd, 6);
		for (size_t i = 0; i < sizeof(rnd); i++){
			co[i*2] = "0123456789abcdef"[rnd[i] >> 4];
			co[i*2+1] = "0123456789abcdef"[rnd[i] & 0x0f];
		}
		co[12] = '\0';

		arcan_frameserver* newref =
			platform_launch_listen_external(co, NULL, -1, ARCAN_SHM_UMASK, 32, 32, ref);
		if (!newref){
			arcan_warning("couldn't listen on connection point (%s)\n", co);
			lua_pushvid(ctx, ARCAN_EID);
			free(host);
			return 1;
		}

/* we need to resolve the full path from within the context here, as the XDG_
 * runtime and similar paths may differ from outer to inner due to LWA having
 * one set of needs, while the cleanup from afsrv_net/arcan-net need another. */
		char path[PATH_MAX];
		if (0 > arcan_shmif_resolve_connpath(co, path, PATH_MAX)){
			arcan_warning("couldn't resolve socket path");
			arcan_frameserver_free(newref);
			lua_pushvid(ctx, ARCAN_EID);
			free(host);
			return 1;
		}

		arcan_conductor_register_frameserver(newref);
		arcan_monitor_fsrvvid(path);
		trace_allocation(ctx, "net_listen", newref->vid);

/* only different thing to regular frameserver setup is that the monitor need to
 * forward the connection information through its established channel. */
		lua_pushvid(ctx, newref->vid);
		free(host);
		return 1;
	}

/* populate and escape, due to IPv6 addresses etc. actively using :: */
	char* workstr = NULL;
	const char prefix[] = "mode=client:host=";
	size_t work_sz = strlen(host) + sizeof(prefix) + 1;
	colon_escape(host);

	char* instr = arcan_alloc_mem(
		work_sz, ARCAN_MEM_STRINGBUF, ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL);

	snprintf(instr, work_sz, "%s%s", prefix, host);
	free(host);

	struct frameserver_envp args = {
		.use_builtin = true,
		.preserve_env = true,
		.args.builtin.mode = "net-cl",
		.args.builtin.resource = instr
	};

	lua_launch_fsrv(ctx, &args, ref, NULL);

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
	int fd = BADFD;

	char* fn = arcan_find_resource(
		fontn, RESOURCE_SYS_FONT, ARES_FILE | ARES_RDONLY, &fd);
	if (!fn){
		lua_pushboolean(ctx, false);
		LUA_ETRACE("system_defaultfont", "couldn't find font in namespace", 1);
	}

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

static int chacha_interval(lua_State* ctx)
{
	LOG("util:random_interval");
	union {
		uint8_t u8[8];
		int64_t b64;
	} buf;

	int64_t low = luaL_checknumber(ctx, 1);
	int64_t high = luaL_checknumber(ctx, 2);
	unsigned long long len = high - low;

	int shift = 64 - __builtin_clzll(len);

	do {
	  arcan_random(buf.u8, 8);
		buf.b64 = buf.b64 >> shift;
	}
	while (buf.b64 >= len);

	lua_pushnumber(ctx, (double) buf.b64);
	return 1;
}

static int chacha_random(lua_State* ctx)
{
	LOG("util:random_bytes");
	size_t count = luaL_checknumber(ctx, 1);
	uint8_t* buf =
		arcan_alloc_mem(count,
			ARCAN_MEM_STRINGBUF,
			ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL,
			ARCAN_MEMALIGN_NATURAL
		);
	if (buf){
		arcan_random(buf, count);
		lua_pushlstring(ctx, (char*) buf, count);
		arcan_mem_free(buf);
		return 1;
	}
	else
		return 0;
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

	lua_pushliteral(ctx, "to_base64");
	lua_pushcfunction(ctx, base64_encode);
	lua_rawset(ctx, top);

	lua_pushliteral(ctx, "from_base64");
	lua_pushcfunction(ctx, base64_decode);
	lua_rawset(ctx, top);

	lua_pushliteral(ctx, "hash");
	lua_pushcfunction(ctx, hash_string);
	lua_rawset(ctx, top);

	lua_pushliteral(ctx, "random_interval");
	lua_pushcfunction(ctx, chacha_interval);
	lua_rawset(ctx, top);

	lua_pushliteral(ctx, "random_bytes");
	lua_pushcfunction(ctx, chacha_random);
	lua_rawset(ctx, top);

	lua_setglobal(ctx, "util");
}

#include "external/bit.c"

static int alua_exposefuncs(lua_State* ctx, unsigned char debugfuncs)
{
	if (!ctx)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	lua_debug_level = debugfuncs;

/* these defines / tables are also scriptably extracted and
 * mapped to build / documentation / static verification to ensure
 * coverage in the API binding -- so keep this format (down to the
 * whitespacing, simple regexs used. */
#define EXT_MAPTBL_RESOURCE
static const luaL_Reg resfuns[] = {
{"resource",          resource        },
{"glob_resource",     globresource    },
{"list_namespaces",   listns          },
{"zap_resource",      zapresource     },
{"open_nonblock",     alt_nbio_open   },
{"open_rawresource",  rawresource     },
{"close_rawresource", rawclose        },
{"write_rawresource", pushrawstr      },
{"read_rawresource",  readrawresource },
{"save_screenshot",   screenshot      },
{NULL, NULL}
};
#undef EXT_MAPTBL_RESOURCE
	register_tbl(ctx, resfuns);

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
{"focus_target",               targetfocus              },
{"target_portconfig",          targetportcfg            },
{"target_framemode",           targetskipmodecfg        },
{"target_verbose",             targetverbose            },
{"target_synchronous",         targetsynchronous        },
{"target_flags",               targetflags              },
{"target_graphmode",           targetgraph              },
{"target_anchorhint",          targetanchor             },
{"target_displayhint",         targetdisphint           },
{"target_devicehint",          targetdevhint            },
{"target_fonthint",            targetfonthint           },
{"target_geohint",             targetgeohint            },
{"target_seek",                targetseek               },
{"target_parent",              targetparent             },
{"target_coreopt",             targetcoreopt            },
{"target_updatehandler",       targethandler            },
{"arcantarget_hint",           arcantargethint          },
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
{"rendertarget_bind",          renderbind               },
{"rendertarget_attach",        renderattach             },
{"rendertarget_noclear",       rendernoclear            },
{"rendertarget_id",            rendertargetid           },
{"rendertarget_range",         rendertargetrange        },
{"rendertarget_metrics",       rendertargetmetrics      },
{"rendertarget_reconfigure",   renderreconf             },
{"launch_decode",              launchdecode             },
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
{"relink_image",             relinkimage        },
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
{"image_metadata",           imagemetadata      },
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
{"benchmark_tracedata", benchtracedata   },
{"benchmark_timestamp", timestamp        },
{"benchmark_data",      getbenchvals     },
{"appl_arguments",      getapplarguments },
{"system_identstr",     getidentstr      },
{"system_defaultfont",  setdefaultfont   },
{"frameserver_debugstall", debugstall    },
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
{"input_remap_translation", inputremaptranslation },
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
{"switch_default_blendmode",         setblendmode   },
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
{"net_discover",     net_discover    },
{"net_listen",       net_listen      },
{NULL, NULL},
};
#undef EXT_MAPTBL_NETWORK
	register_tbl(ctx, netfuns);

/* Override the default print for integration with tracer */
	lua_pushcfunction(ctx, alt_trace_log);
	lua_setglobal(ctx, "print");

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
{"EXIT_SILENT", 256},

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
{"BLEND_SUB", BLEND_SUB},
{"BLEND_MULTIPLY", BLEND_MULTIPLY},
{"BLEND_NORMAL", BLEND_NORMAL},
{"BLEND_FORCE", BLEND_FORCE},
{"BLEND_PREMULTIPLIED", BLEND_PREMUL},
{"ANCHOR_UL", ANCHORP_UL},
{"ANCHOR_UR", ANCHORP_UR},
{"ANCHOR_LL", ANCHORP_LL},
{"ANCHOR_LR", ANCHORP_LR},
{"ANCHOR_C", ANCHORP_C},
{"ANCHOR_UC", ANCHORP_UC},
{"ANCHOR_LC", ANCHORP_LC},
{"ANCHOR_CL", ANCHORP_CL},
{"ANCHOR_CR", ANCHORP_CR},
{"ANCHOR_SCALE_NONE", 0},
{"ANCHOR_SCALE_W", SCALEM_WIDTH},
{"ANCHOR_SCALE_H", SCALEM_HEIGHT},
{"ANCHOR_SCALE_WH", SCALEM_WIDTH_HEIGHT},
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
{"TARGET_ALLOWHDR", TARGET_FLAG_ALLOW_HDR},
{"TARGET_ALLOWLODEF", 0}, /* deprecated */
{"TARGET_ALLOWVECTOR", TARGET_FLAG_ALLOW_VOBJ},
{"TARGET_ALLOWINPUT", TARGET_FLAG_ALLOW_INPUT},
{"TARGET_ALLOWGPU", TARGET_FLAG_ALLOW_GPUAUTH},
{"TARGET_LIMITSIZE", TARGET_FLAG_LIMIT_SIZE},
{"TARGET_SYNCHSIZE", TARGET_FLAG_SYNCH_SIZE},
{"TARGET_BLOCKADOPT", TARGET_FLAG_NO_ADOPT},
{"TARGET_DRAINQUEUE", TARGET_FLAG_DRAIN_QUEUE},
{"DISPLAY_STANDBY", ADPMS_STANDBY},
{"DISPLAY_OFF", ADPMS_OFF},
{"DISPLAY_SUSPEND", ADPMS_SUSPEND},
{"DISPLAY_ON", ADPMS_ON},
{"DEVICE_INDIRECT", DEVICE_INDIRECT},
{"DEVICE_DIRECT", DEVICE_DIRECT},
{"DEVICE_LOST", DEVICE_LOST},
{"ANCHORHINT_SEGMENT", ANCHORHINT_SEGMENT},
{"ANCHORHINT_EXTERNAL", ANCHORHINT_EXTERNAL},
{"ANCHORHINT_PROXY", ANCHORHINT_PROXY},
{"ANCHORHINT_PROXY_EXTERNAL", ANCHORHINT_PROXY_EXTERNAL},
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
{"SHADER_DOMAIN_RENDERTARGET", 1},
{"SHADER_DOMAIN_RENDERTARGET_HARD", 2},
{"ROTATE_RELATIVE", CONST_ROTATE_RELATIVE},
{"ROTATE_ABSOLUTE", CONST_ROTATE_ABSOLUTE},
{"SEEK_RELATIVE", 1},
{"SEEK_ABSOLUTE", 0},
{"SEEK_TIME", 1},
{"SEEK_SPACE", 0},
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
{"TRACE_TRIGGER_ONESHOT", 0},
{"TRACE_TRIGGER_ENTER", 1},
{"TRACE_TRIGGER_EXIT", 2},
{"TRACE_PATH_DEFAULT", TRACE_SYS_DEFAULT},
{"TRACE_PATH_SLOW", TRACE_SYS_SLOW},
{"TRACE_PATH_WARNING", TRACE_SYS_WARN},
{"TRACE_PATH_ERROR", TRACE_SYS_ERROR},
{"TRACE_PATH_FAST", TRACE_SYS_FAST},
{"ALLOC_QUALITY_LOW", VSTORE_HINT_LODEF},
{"ALLOC_QUALITY_NORMAL", VSTORE_HINT_NORMAL},
{"ALLOC_QUALITY_HIGH", VSTORE_HINT_HIDEF},
{"ALLOC_QUALITY_FLOAT16", VSTORE_HINT_F16},
{"ALLOC_QUALITY_FLOAT32", VSTORE_HINT_F32},
{"APPL_RESOURCE", RESOURCE_APPL},
{"APPL_STATE_RESOURCE", RESOURCE_APPL_STATE},
{"APPL_TEMP_RESOURCE",RESOURCE_APPL_TEMP},
{"SHARED_RESOURCE", RESOURCE_APPL_SHARED},
{"SYS_SCRIPT_RESOURCE", RESOURCE_SYS_SCRIPTS},
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
{"HINT_ROTATE_180", HINT_ROTATE_180},
{"HINT_CURSOR", HINT_CURSOR},
{"HINT_DIRECT", HINT_DIRECT},
{"TD_HINT_CONTINUED", 1},
{"TD_HINT_INVISIBLE", 2},
{"TD_HINT_UNFOCUSED", 4},
{"TD_HINT_MAXIMIZED", 8},
{"TD_HINT_FULLSCREEN", 16},
{"TD_HINT_DETACHED", 32},
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
{"SHADER_DOMAIN_RENDERTARGET", 1},
{"SHADER_DOMAIN_RENDERTARGET_HARD", 2},
/* DEPRECATE */ {"LEDCONTROLLERS", arcan_led_controllers()},
{"KEY_CONFIG", DVT_CONFIG},
{"KEY_TARGET", DVT_TARGET},
{"NOW", 0},
{"NOPERSIST", 0},
{"PERSIST", 1},
{"DISCOVER_PASSIVE", CONST_DISCOVER_PASSIVE},
{"DISCOVER_SWEEP", CONST_DISCOVER_SWEEP},
{"DISCOVER_BROADCAST", CONST_DISCOVER_BROADCAST},
{"DISCOVER_DIRECTORY", CONST_DISCOVER_DIRECTORY},
{"DISCOVER_TEST", CONST_DISCOVER_TEST},
{"TRUST_KNOWN", CONST_TRUST_KNOWN},
{"TRUST_PERMIT_UNKNOWN", CONST_TRUST_PERMIT_UNKNOWN},
{"TRUST_TRANSITIVE", CONST_TRUST_TRANSITIVE},
{"TRANSLATION_CLEAR", EVENT_TRANSLATION_CLEAR},
{"TRANSLATION_SET", EVENT_TRANSLATION_SET},
{"TRANSLATION_REMAP", EVENT_TRANSLATION_REMAP},
{"DEBUGLEVEL", lua_debug_level},
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

	arcan_video_rendertargetdensity(ARCAN_VIDEO_WORLDID, hppcm, vppcm, false, false);
	arcan_lua_setglobalstr(ctx, "GL_VERSION", agp_ident());
	arcan_lua_setglobalstr(ctx, "SHADER_LANGUAGE", agp_shader_language());
	arcan_lua_setglobalstr(ctx, "FRAMESERVER_MODES", arcan_frameserver_atypes());
	arcan_lua_setglobalstr(ctx, "APPLID", arcan_appl_id());
	arcan_lua_setglobalstr(ctx, "API_ENGINE_BUILD", ARCAN_BUILDVERSION);

	arcan_process_title(arcan_appl_id());

	if (alt_trace_crash_source()){
		arcan_lua_setglobalstr(ctx, "CRASH_SOURCE", alt_trace_crash_source());
		alt_trace_set_crash_source(NULL);
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
	switch(func & (~BLEND_FORCE)){
	case BLEND_NONE     : return "disabled";
	case BLEND_NORMAL   : return "normal";
	case BLEND_ADD      : return "additive";
	case BLEND_MULTIPLY : return "multiply";
	case BLEND_SUB      : return "subtract";
	case BLEND_PREMUL   : return "premultiplied";
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
	case SEGID_AUDIO: return "audio";
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
src->vstore->txmapped ? (
	src->vstore->vinf.text.kind == STORAGE_IMAGE_URI ?
	src->vstore->vinf.text.source : "text/text-array" )
	: "color",
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
		if (src->vstore->vinf.text.kind == STORAGE_TEXT &&
			src->vstore->vinf.text.source){
			fprintf(dst, "vobj.text = ");
			fput_luasafe_str(dst, src->vstore->vinf.text.source);
		}
		else if (src->vstore->vinf.text.kind == STORAGE_TEXTARRAY){
			fprintf(dst, "vobj.text_array = {\n");
			char** str = src->vstore->vinf.text.source_arr;
			while (str && *str){
				fput_luasafe_str(dst, *str++);
				fputs(",\n", dst);
			}
			fprintf(dst, "};\n");
		}
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

static void dump_rtgt(FILE* dst, struct rendertarget* rtgt)
{
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

void arcan_lua_statesnap(FILE* dst, const char* tag, bool delim)
{
/*
 * display global settings, wrap to local ptr for shorthand */
/* missing shaders,
 * missing event-queues
 */
	struct arcan_video_display* disp = &arcan_video_display;
	struct monitor_mode mmode = platform_video_dimensions();

if (delim)
	fputs("#BEGINSTATE\n", dst);

fprintf(dst, " do \n\
local nan = 0/0;\n\
local inf = math.huge;\n\
local vobj = {};\n\
local props = {};\n\
local restbl = {\n\
\tversion = [[%s]],\n\
\tdisplay = {\n\
\t\twidth = %d,\n\
\t\theight = %d,\n\
\t\tconservative = %d,\n\
\t\tticks = %lld,\n\
\t\tdefault_vitemlim = %d,\n\
\t\timageproc = %d,\n\
\t\tscalemode = %d,\n\
\t\tfiltermode = %d,\n\
\t},\n\
\tvcontexts = {}\
};\n\
",
	ARCAN_BUILDVERSION,
	(int)mmode.width, (int)mmode.height, disp->conservative ? 1 : 0,
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

		dump_rtgt(dst, &ctx->stdoutp);
		for (size_t i = 0; i < ctx->n_rtargets; i++){
			dump_rtgt(dst, &ctx->rtargets[i]);
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
	fprintf(dst, "return restbl;\nend\n%s", delim ? "#ENDSTATE\n" : "");
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
