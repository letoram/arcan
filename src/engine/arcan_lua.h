/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_LUA
#define _HAVE_ARCAN_LUA

#define LUAAPI_VERSION_MAJOR 0
#define LUAAPI_VERSION_MINOR 11

/* arcan_luactx* is just an intermediary alias for lua_State */
struct arcan_luactx;
struct luaL_Reg;

typedef struct luaL_Reg* (*module_init_prototype)(int, int, int);

/* we separate alloc and mapfunctions to allow partial VM execution
 * BEFORE we have exposed the engine functions. This allows "constants"
 * to be calculated while still enforcing the themename() entrypoint */
struct arcan_luactx* arcan_lua_alloc();
void arcan_lua_mapfunctions(
	struct arcan_luactx* dst, int debuglevel);

char* arcan_lua_main(struct arcan_luactx*, const char* input, bool file_in);
void arcan_lua_dostring(struct arcan_luactx*, const char* sbuf);

/* cbdrop is part of crash recovery and sweeps all context stacks looking
 * for vobjects with tags that reference any lua context (hence not multi-
 * context safe as is) */
void arcan_lua_cbdrop();
void arcan_lua_shutdown(struct arcan_luactx*);
void arcan_lua_tick(struct arcan_luactx*, size_t, size_t);

/* add a set of wrapper functions exposing arcan_video and friends
 * to the Lua state, debugfuncs corresponds to desired debug level / behavior */
arcan_errc arcan_lua_exposefuncs(struct arcan_luactx* dst,
	unsigned char debugfuncs);

void arcan_lua_setglobalint(struct arcan_luactx* ctx, const char* key, int val);
void arcan_lua_setglobalstr(struct arcan_luactx* ctx,
	const char* key, const char* val);
void arcan_lua_pushevent(struct arcan_luactx* ctx, arcan_event* ev);
bool arcan_lua_callvoidfun(struct arcan_luactx* ctx,
	const char* fun, bool warn, const char** argv);

/* used to implement an interactive shell,
 * iterate the global (_G) table for a matching prefix, yield callback
 * for each hit, with (key, type, tag) as the callback arguments */
void arcan_lua_eachglobal(struct arcan_luactx* ctx, char* prefix,
	int (*callback)(const char*, const char*, void*), void* tag);

/* for initialization, update / push all the global constants used */
void arcan_lua_pushglobalconsts(struct arcan_luactx* ctx);

/* serialize a Lua- parseable snapshot of the various mapped subsystems
 * and resources into the (dst) filestream.
 * If delim is set, we're in streaming mode so a delimiter will be added
 * to account for more snapshots over the same stream */
void arcan_lua_statesnap(FILE* dst, const char* tag, bool delim);

/*
 * will sweep the main rendertarget in the active context and
 * expose running frameserver connections through an applname_adopt handler
 * indended as a continuation of recoveryexternal
 */
void arcan_lua_adopt(struct arcan_luactx* ctx);

/* nonblock/read from (dst) filestream until an #ENDBLOCK\n tag is encountered,
 * parse this and push it into the struct arcan_luactx as the first
 * and only argument to the function pointed out with (dstfun). */
void arcan_lua_stategrab(struct arcan_luactx* ctx, char* dstfun, int fd);

/*
 * create a new external listening endpoint and expose via the _adopt handler,
 * the purpose is to expose a pre-existing connection via _stdin.
 */
bool arcan_lua_launch_cp(
	struct arcan_luactx*, const char* connp, const char* key);

#ifdef LUA_PRIVATE
enum arcan_ffunc_rv arcan_lua_proctarget FFUNC_HEAD;
#endif

#endif

