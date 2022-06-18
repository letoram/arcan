/*
 * Copyright 2003-2020, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_LUA
#define _HAVE_ARCAN_LUA

#define LUAAPI_VERSION_MAJOR 0
#define LUAAPI_VERSION_MINOR 13

/* arcan_luactx* is just an intermediary alias for lua_State */
struct arcan_luactx;
struct luaL_Reg;

enum {
	ARCAN_LUA_SWITCH_APPL = 1,
	ARCAN_LUA_SWITCH_APPL_NOADOPT = 2,
	ARCAN_LUA_RECOVERY_SWITCH = 3,
	ARCAN_LUA_RECOVERY_FATAL_IGNORE = 4,
	ARCAN_LUA_KILL_SILENT = 5
};

typedef struct luaL_Reg* (*module_init_prototype)(int, int, int);

/* we separate alloc and mapfunctions to allow partial VM execution
 * BEFORE we have exposed the engine functions. This allows "constants"
 * to be calculated while still enforcing the themename() entrypoint */
struct arcan_luactx* arcan_lua_alloc(void (*watchdog)(lua_State*, lua_Debug*));
void arcan_lua_mapfunctions(
	struct arcan_luactx* dst, int debuglevel);

char* arcan_lua_main(struct arcan_luactx*, const char* input, bool file_in);
void arcan_lua_dostring(struct arcan_luactx*, const char* sbuf, const char* name);

/* cbdrop is part of crash recovery and sweeps all context stacks looking
 * for vobjects with tags that reference any lua context (hence not multi-
 * context safe as is) */
void arcan_lua_cbdrop();
void arcan_lua_shutdown(struct arcan_luactx*);
void arcan_lua_tick(struct arcan_luactx*, size_t, size_t);

/* access the last known crash source, used when a [callvoidfun] has
 * failed and longjumped into the set jump buffer */
const char* arcan_lua_crash_source(struct arcan_luactx*);

/* for initialization, update / push all the global constants used */
void arcan_lua_pushglobalconsts(struct arcan_luactx* ctx);

void arcan_lua_setglobalint(struct arcan_luactx* ctx, const char* key, int val);
void arcan_lua_setglobalstr(struct arcan_luactx* ctx,
	const char* key, const char* val);

/* Forward an event to the related script defined entry point. Returns true
 * if the event was consumed (default) or false when the engine is in a vid
 * blocking state OR (event not input / no input_raw handler).
 *
 * If [ev] is empty it is used as a marker for a completed buffer flush. */
bool arcan_lua_pushevent(struct arcan_luactx* ctx, struct arcan_event* ev);

/* Run the entry-point named [fun], the applname specific prefix will be
 * added internally. Any elements in argv will be added as an integer
 * indexed table and supplied as the argument. Returns false if no such
 * function is defined in the VM state.
 */
bool arcan_lua_callvoidfun(struct arcan_luactx* ctx,
	const char* fun, bool warn, const char** argv);

/* serialize a Lua- parseable snapshot of the various mapped subsystems and
 * resources into the (dst) filestream. If delim is set, we're in streaming
 * mode so a delimiter will be added to account for more snapshots over the
 * same stream */
void arcan_lua_statesnap(FILE* dst, const char* tag, bool delim);

/*
 * will sweep the main rendertarget in the active context and expose running
 * frameserver connections through an applname_adopt handler indended as a
 * continuation of recoveryexternal
 */
void arcan_lua_adopt(struct arcan_luactx* ctx);

/* nonblock/read from (dst) filestream until an #ENDBLOCK\n tag is encountered,
 * parse this and push it into the struct arcan_luactx as the first
 * and only argument to the function pointed out with (dstfun). */
void arcan_lua_stategrab(struct arcan_luactx* ctx, char* dstfun, int infd);

/*
 * create a new external listening endpoint and expose via the _adopt handler,
 * the purpose is to expose a pre-existing connection via _stdin.
 */
bool arcan_lua_launch_cp(
	struct arcan_luactx*, const char* connp, const char* key);

#ifdef ARCAN_LWA
struct subseg_output;
bool platform_lwa_targetevent(struct subseg_output*, struct arcan_event* ev);
bool platform_lwa_allocbind_feed(
	struct arcan_luactx* ctx, arcan_vobj_id rtgt, enum ARCAN_SEGID type, uintptr_t cbtag);
void arcan_lwa_subseg_ev(
	struct arcan_luactx* ctx, arcan_vobj_id src, uintptr_t cb_tag, arcan_event* ev);
#endif

#ifdef LUA_PRIVATE
enum arcan_ffunc_rv arcan_lua_proctarget FFUNC_HEAD;
#endif

#endif

