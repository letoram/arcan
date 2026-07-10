// lua54/api.zig — pure-Zig public API surface for the in-tree Lua 5.4 port.
//
// Consumers migrating off LuaJIT's @cImport("lua.h") / @cImport("lauxlib.h")
// import this module instead. It declares the public types and constants of
// the Lua 5.4 C API and extern "c" bindings to the symbols that
// src/lua54/*.zig exports via `pub export fn`.
//
// This file is HEADER-FREE: no @cImport, no @cInclude. All declarations are
// hand-written to match Lua 5.4.6's public surface.
//
// LuaJIT/Lua-5.1 compat shims
// ───────────────────────────
// A small number of legacy names (lua_objlen, luaL_typerror, luaL_register,
// LUA_GLOBALSINDEX) are provided as inline thin wrappers / translations so
// that consumer call-sites can migrate mechanically. New code should prefer
// the native 5.4 equivalents (lua_rawlen, luaL_typeerror, luaL_setfuncs,
// lua_getglobal/lua_setglobal).

const std = @import("std");

// ── Types ───────────────────────────────────────────────────────────────────

pub const lua_State = opaque {};
pub const lua_Number = f64;
pub const lua_Integer = c_longlong;
pub const lua_Unsigned = c_ulonglong;
pub const lua_KContext = isize;
pub const lua_CFunction = ?*const fn (?*lua_State) callconv(.c) c_int;
pub const lua_KFunction = ?*const fn (?*lua_State, c_int, lua_KContext) callconv(.c) c_int;
pub const lua_Reader = ?*const fn (?*lua_State, ?*anyopaque, ?*usize) callconv(.c) [*c]const u8;
pub const lua_Writer = ?*const fn (?*lua_State, ?*const anyopaque, usize, ?*anyopaque) callconv(.c) c_int;
pub const lua_Alloc = ?*const fn (?*anyopaque, ?*anyopaque, usize, usize) callconv(.c) ?*anyopaque;
pub const lua_WarnFunction = ?*const fn (?*anyopaque, [*c]const u8, c_int) callconv(.c) void;

// Lua 5.4 lua_Debug — must match the layout in src/lua54/lauxlib.zig so that
// pointers passed through lua_getinfo / lua_getstack are interpreted the same
// way by the VM and by the consumer.
pub const lua_Debug = extern struct {
    event: c_int = 0,
    name: [*c]const u8 = null,
    namewhat: [*c]const u8 = null,
    what: [*c]const u8 = null,
    source: [*c]const u8 = null,
    srclen: usize = 0,
    currentline: c_int = 0,
    linedefined: c_int = 0,
    lastlinedefined: c_int = 0,
    nups: u8 = 0,
    nparams: u8 = 0,
    isvararg: u8 = 0,
    istailcall: u8 = 0,
    ftransfer: c_ushort = 0,
    ntransfer: c_ushort = 0,
    short_src: [60]u8 = std.mem.zeroes([60]u8),
    i_ci: ?*anyopaque = null,
};

pub const lua_Hook = ?*const fn (?*lua_State, ?*lua_Debug) callconv(.c) void;

pub const luaL_Reg = extern struct {
    name: ?[*:0]const u8 = null,
    func: lua_CFunction = null,
};

// ── Constants ───────────────────────────────────────────────────────────────

pub const LUA_VERSION_NUM: c_int = 504;
pub const LUA_MULTRET: c_int = -1;

pub const LUAI_MAXSTACK: c_int = 1000000;
pub const LUA_REGISTRYINDEX: c_int = -LUAI_MAXSTACK - 1000;

pub const LUA_OK: c_int = 0;
pub const LUA_YIELD: c_int = 1;
pub const LUA_ERRRUN: c_int = 2;
pub const LUA_ERRSYNTAX: c_int = 3;
pub const LUA_ERRMEM: c_int = 4;
pub const LUA_ERRERR: c_int = 5;

pub const LUA_TNONE: c_int = -1;
pub const LUA_TNIL: c_int = 0;
pub const LUA_TBOOLEAN: c_int = 1;
pub const LUA_TLIGHTUSERDATA: c_int = 2;
pub const LUA_TNUMBER: c_int = 3;
pub const LUA_TSTRING: c_int = 4;
pub const LUA_TTABLE: c_int = 5;
pub const LUA_TFUNCTION: c_int = 6;
pub const LUA_TUSERDATA: c_int = 7;
pub const LUA_TTHREAD: c_int = 8;
pub const LUA_NUMTYPES: c_int = 9;

pub const LUA_MINSTACK: c_int = 20;
pub const LUA_RIDX_MAINTHREAD: c_int = 1;
pub const LUA_RIDX_GLOBALS: c_int = 2;

pub const LUA_SIGNATURE = "\x1bLua";

// Debug hook masks
pub const LUA_HOOKCALL: c_int = 0;
pub const LUA_HOOKRET: c_int = 1;
pub const LUA_HOOKLINE: c_int = 2;
pub const LUA_HOOKCOUNT: c_int = 3;
pub const LUA_HOOKTAILCALL: c_int = 4;
pub const LUA_MASKCALL: c_int = 1 << LUA_HOOKCALL;
pub const LUA_MASKRET: c_int = 1 << LUA_HOOKRET;
pub const LUA_MASKLINE: c_int = 1 << LUA_HOOKLINE;
pub const LUA_MASKCOUNT: c_int = 1 << LUA_HOOKCOUNT;

// Reference types
pub const LUA_NOREF: c_int = -2;
pub const LUA_REFNIL: c_int = -1;

// GC opcodes (lua_gc)
pub const LUA_GCSTOP: c_int = 0;
pub const LUA_GCRESTART: c_int = 1;
pub const LUA_GCCOLLECT: c_int = 2;
pub const LUA_GCCOUNT: c_int = 3;
pub const LUA_GCCOUNTB: c_int = 4;
pub const LUA_GCSTEP: c_int = 5;
pub const LUA_GCISRUNNING: c_int = 9;
pub const LUA_GCGEN: c_int = 10;
pub const LUA_GCINC: c_int = 11;

// Arithmetic ops (lua_arith)
pub const LUA_OPADD: c_int = 0;
pub const LUA_OPSUB: c_int = 1;
pub const LUA_OPMUL: c_int = 2;
pub const LUA_OPMOD: c_int = 3;
pub const LUA_OPPOW: c_int = 4;
pub const LUA_OPDIV: c_int = 5;
pub const LUA_OPIDIV: c_int = 6;
pub const LUA_OPBAND: c_int = 7;
pub const LUA_OPBOR: c_int = 8;
pub const LUA_OPBXOR: c_int = 9;
pub const LUA_OPSHL: c_int = 10;
pub const LUA_OPSHR: c_int = 11;
pub const LUA_OPUNM: c_int = 12;
pub const LUA_OPBNOT: c_int = 13;

// Comparison ops (lua_compare)
pub const LUA_OPEQ: c_int = 0;
pub const LUA_OPLT: c_int = 1;
pub const LUA_OPLE: c_int = 2;

// ── Core state / thread management ──────────────────────────────────────────

pub extern "c" fn lua_newstate(f: lua_Alloc, ud: ?*anyopaque) ?*lua_State;
pub extern "c" fn lua_close(L: ?*lua_State) void;
pub extern "c" fn lua_newthread(L: ?*lua_State) ?*lua_State;
pub extern "c" fn lua_closethread(L: ?*lua_State, from: ?*lua_State) c_int;
pub extern "c" fn lua_resetthread(L: ?*lua_State) c_int;
pub extern "c" fn lua_atpanic(L: ?*lua_State, panicf: lua_CFunction) lua_CFunction;
pub extern "c" fn lua_version(L: ?*lua_State) lua_Number;

// ── Stack manipulation ─────────────────────────────────────────────────────

pub extern "c" fn lua_absindex(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_gettop(L: ?*lua_State) c_int;
pub extern "c" fn lua_settop(L: ?*lua_State, idx: c_int) void;
pub extern "c" fn lua_pushvalue(L: ?*lua_State, idx: c_int) void;
pub extern "c" fn lua_rotate(L: ?*lua_State, idx: c_int, n: c_int) void;
pub extern "c" fn lua_copy(L: ?*lua_State, fromidx: c_int, toidx: c_int) void;
pub extern "c" fn lua_checkstack(L: ?*lua_State, n: c_int) c_int;
pub extern "c" fn lua_xmove(from: ?*lua_State, to: ?*lua_State, n: c_int) void;

// ── Access / type checks ───────────────────────────────────────────────────

pub extern "c" fn lua_isnumber(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_isstring(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_iscfunction(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_isinteger(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_isuserdata(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_type(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_typename(L: ?*lua_State, t: c_int) [*c]const u8;

pub extern "c" fn lua_tonumberx(L: ?*lua_State, idx: c_int, pisnum: ?*c_int) lua_Number;
pub extern "c" fn lua_tointegerx(L: ?*lua_State, idx: c_int, pisnum: ?*c_int) lua_Integer;
pub extern "c" fn lua_toboolean(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_tolstring(L: ?*lua_State, idx: c_int, len: ?*usize) [*c]const u8;
pub extern "c" fn lua_rawlen(L: ?*lua_State, idx: c_int) lua_Unsigned;
pub extern "c" fn lua_tocfunction(L: ?*lua_State, idx: c_int) lua_CFunction;
pub extern "c" fn lua_touserdata(L: ?*lua_State, idx: c_int) ?*anyopaque;
pub extern "c" fn lua_tothread(L: ?*lua_State, idx: c_int) ?*lua_State;
pub extern "c" fn lua_topointer(L: ?*lua_State, idx: c_int) ?*const anyopaque;

pub extern "c" fn lua_arith(L: ?*lua_State, op: c_int) void;
pub extern "c" fn lua_rawequal(L: ?*lua_State, index1: c_int, index2: c_int) c_int;
pub extern "c" fn lua_compare(L: ?*lua_State, index1: c_int, index2: c_int, op: c_int) c_int;

// ── Push ────────────────────────────────────────────────────────────────────

pub extern "c" fn lua_pushnil(L: ?*lua_State) void;
pub extern "c" fn lua_pushnumber(L: ?*lua_State, n: lua_Number) void;
pub extern "c" fn lua_pushinteger(L: ?*lua_State, n: lua_Integer) void;
pub extern "c" fn lua_pushlstring(L: ?*lua_State, s: [*c]const u8, len: usize) [*c]const u8;
pub extern "c" fn lua_pushstring(L: ?*lua_State, s: [*c]const u8) [*c]const u8;
pub extern "c" fn lua_pushfstring(L: ?*lua_State, fmt: [*c]const u8, ...) [*c]const u8;
pub extern "c" fn lua_pushcclosure(L: ?*lua_State, f: lua_CFunction, n: c_int) void;
pub extern "c" fn lua_pushboolean(L: ?*lua_State, b: c_int) void;
pub extern "c" fn lua_pushlightuserdata(L: ?*lua_State, p: ?*anyopaque) void;
pub extern "c" fn lua_pushthread(L: ?*lua_State) c_int;

// ── Tables ─────────────────────────────────────────────────────────────────

pub extern "c" fn lua_getglobal(L: ?*lua_State, name: [*c]const u8) c_int;
pub extern "c" fn lua_gettable(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_getfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) c_int;
pub extern "c" fn lua_geti(L: ?*lua_State, idx: c_int, n: lua_Integer) c_int;
pub extern "c" fn lua_rawget(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_rawgeti(L: ?*lua_State, idx: c_int, n: lua_Integer) c_int;
pub extern "c" fn lua_rawgetp(L: ?*lua_State, idx: c_int, p: ?*const anyopaque) c_int;

pub extern "c" fn lua_createtable(L: ?*lua_State, narray: c_int, nrec: c_int) void;
pub extern "c" fn lua_newuserdatauv(L: ?*lua_State, size: usize, nuvalue: c_int) ?*anyopaque;
pub extern "c" fn lua_getmetatable(L: ?*lua_State, objindex: c_int) c_int;
pub extern "c" fn lua_getiuservalue(L: ?*lua_State, idx: c_int, n: c_int) c_int;

pub extern "c" fn lua_setglobal(L: ?*lua_State, name: [*c]const u8) void;
pub extern "c" fn lua_settable(L: ?*lua_State, idx: c_int) void;
pub extern "c" fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) void;
pub extern "c" fn lua_seti(L: ?*lua_State, idx: c_int, n: lua_Integer) void;
pub extern "c" fn lua_rawset(L: ?*lua_State, idx: c_int) void;
pub extern "c" fn lua_rawseti(L: ?*lua_State, idx: c_int, n: lua_Integer) void;
pub extern "c" fn lua_rawsetp(L: ?*lua_State, idx: c_int, p: ?*const anyopaque) void;
pub extern "c" fn lua_setmetatable(L: ?*lua_State, objindex: c_int) c_int;
pub extern "c" fn lua_setiuservalue(L: ?*lua_State, idx: c_int, n: c_int) c_int;

// ── Call / error ───────────────────────────────────────────────────────────

pub extern "c" fn lua_callk(L: ?*lua_State, nargs: c_int, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) void;
pub extern "c" fn lua_pcallk(L: ?*lua_State, nargs: c_int, nresults: c_int, errfunc: c_int, ctx: lua_KContext, k: lua_KFunction) c_int;
pub extern "c" fn lua_pcall(L: ?*lua_State, nargs: c_int, nresults: c_int, errfunc: c_int) c_int;
pub extern "c" fn lua_load(L: ?*lua_State, reader: lua_Reader, data: ?*anyopaque, chunkname: [*c]const u8, mode: [*c]const u8) c_int;
pub extern "c" fn lua_dump(L: ?*lua_State, writer: lua_Writer, data: ?*anyopaque, strip: c_int) c_int;
pub extern "c" fn lua_yieldk(L: ?*lua_State, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) c_int;
pub extern "c" fn lua_resume(L: ?*lua_State, from: ?*lua_State, nargs: c_int, nresults: ?*c_int) c_int;
pub extern "c" fn lua_isyieldable(L: ?*lua_State) c_int;
pub extern "c" fn lua_status(L: ?*lua_State) c_int;
pub extern "c" fn lua_error(L: ?*lua_State) c_int;
pub extern "c" fn lua_next(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_concat(L: ?*lua_State, n: c_int) void;
pub extern "c" fn lua_len(L: ?*lua_State, idx: c_int) void;
pub extern "c" fn lua_stringtonumber(L: ?*lua_State, s: [*c]const u8) usize;
pub extern "c" fn lua_gc(L: ?*lua_State, what: c_int, ...) c_int;

// ── Debug / hooks ──────────────────────────────────────────────────────────

pub extern "c" fn lua_getstack(L: ?*lua_State, level: c_int, ar: ?*lua_Debug) c_int;
pub extern "c" fn lua_getinfo(L: ?*lua_State, what: [*c]const u8, ar: ?*lua_Debug) c_int;
pub extern "c" fn lua_getlocal(L: ?*lua_State, ar: ?*const lua_Debug, n: c_int) [*c]const u8;
pub extern "c" fn lua_setlocal(L: ?*lua_State, ar: ?*const lua_Debug, n: c_int) [*c]const u8;
pub extern "c" fn lua_sethook(L: ?*lua_State, func: lua_Hook, mask: c_int, count: c_int) void;
pub extern "c" fn lua_gethook(L: ?*lua_State) lua_Hook;
pub extern "c" fn lua_gethookmask(L: ?*lua_State) c_int;
pub extern "c" fn lua_gethookcount(L: ?*lua_State) c_int;

// ── Auxiliary library ──────────────────────────────────────────────────────

pub extern "c" fn luaL_newstate() ?*lua_State;
pub extern "c" fn luaL_openlibs(L: ?*lua_State) void;
pub extern "c" fn luaL_checkversion_(L: ?*lua_State, ver: lua_Number, sz: usize) void;

pub extern "c" fn luaL_getmetafield(L: ?*lua_State, obj: c_int, event: [*c]const u8) c_int;
pub extern "c" fn luaL_callmeta(L: ?*lua_State, obj: c_int, event: [*c]const u8) c_int;
pub extern "c" fn luaL_tolstring(L: ?*lua_State, idx: c_int, len: ?*usize) [*c]const u8;

pub extern "c" fn luaL_argerror(L: ?*lua_State, arg: c_int, extramsg: [*c]const u8) c_int;
pub extern "c" fn luaL_typeerror(L: ?*lua_State, arg: c_int, tname: [*c]const u8) c_int;

pub extern "c" fn luaL_checklstring(L: ?*lua_State, arg: c_int, len: ?*usize) [*c]const u8;
pub extern "c" fn luaL_optlstring(L: ?*lua_State, arg: c_int, def: [*c]const u8, len: ?*usize) [*c]const u8;
pub extern "c" fn luaL_checknumber(L: ?*lua_State, arg: c_int) lua_Number;
pub extern "c" fn luaL_optnumber(L: ?*lua_State, arg: c_int, def: lua_Number) lua_Number;
pub extern "c" fn luaL_checkinteger(L: ?*lua_State, arg: c_int) lua_Integer;
pub extern "c" fn luaL_optinteger(L: ?*lua_State, arg: c_int, def: lua_Integer) lua_Integer;
pub extern "c" fn luaL_checkstack(L: ?*lua_State, space: c_int, msg: [*c]const u8) void;
pub extern "c" fn luaL_checktype(L: ?*lua_State, arg: c_int, t: c_int) void;
pub extern "c" fn luaL_checkany(L: ?*lua_State, arg: c_int) void;
pub extern "c" fn luaL_newmetatable(L: ?*lua_State, tname: [*c]const u8) c_int;
pub extern "c" fn luaL_setmetatable(L: ?*lua_State, tname: [*c]const u8) void;
pub extern "c" fn luaL_testudata(L: ?*lua_State, ud: c_int, tname: [*c]const u8) ?*anyopaque;
pub extern "c" fn luaL_checkudata(L: ?*lua_State, ud: c_int, tname: [*c]const u8) ?*anyopaque;

pub extern "c" fn luaL_where(L: ?*lua_State, level: c_int) void;
pub extern "c" fn luaL_error(L: ?*lua_State, fmt: [*c]const u8, ...) c_int;
pub extern "c" fn luaL_checkoption(L: ?*lua_State, arg: c_int, def: [*c]const u8, lst: [*c]const [*c]const u8) c_int;
pub extern "c" fn luaL_fileresult(L: ?*lua_State, stat: c_int, fname: [*c]const u8) c_int;

pub extern "c" fn luaL_ref(L: ?*lua_State, t: c_int) c_int;
pub extern "c" fn luaL_unref(L: ?*lua_State, t: c_int, ref: c_int) void;

pub extern "c" fn luaL_loadfilex(L: ?*lua_State, filename: [*c]const u8, mode: [*c]const u8) c_int;
pub extern "c" fn luaL_loadbufferx(L: ?*lua_State, buff: [*c]const u8, size: usize, name: [*c]const u8, mode: [*c]const u8) c_int;
pub extern "c" fn luaL_loadstring(L: ?*lua_State, s: [*c]const u8) c_int;
pub extern "c" fn luaL_len(L: ?*lua_State, idx: c_int) lua_Integer;
pub extern "c" fn luaL_gsub(L: ?*lua_State, s: [*c]const u8, p: [*c]const u8, r: [*c]const u8) [*c]const u8;
pub extern "c" fn luaL_setfuncs(L: ?*lua_State, l: [*c]const luaL_Reg, nup: c_int) void;
pub extern "c" fn luaL_getsubtable(L: ?*lua_State, idx: c_int, fname: [*c]const u8) c_int;
pub extern "c" fn luaL_traceback(L: ?*lua_State, L1: ?*lua_State, msg: [*c]const u8, level: c_int) void;
pub extern "c" fn luaL_requiref(L: ?*lua_State, modname: [*c]const u8, openf: lua_CFunction, glb: c_int) void;
pub extern "c" fn luaL_dostring(L: ?*lua_State, s: [*c]const u8) c_int;

// ── Inline shims / macros ──────────────────────────────────────────────────

pub inline fn lua_pop(L: ?*lua_State, n: c_int) void {
    lua_settop(L, -n - 1);
}

pub inline fn lua_newtable(L: ?*lua_State) void {
    lua_createtable(L, 0, 0);
}

pub inline fn lua_pushcfunction(L: ?*lua_State, f: lua_CFunction) void {
    lua_pushcclosure(L, f, 0);
}

pub inline fn lua_tonumber(L: ?*lua_State, idx: c_int) lua_Number {
    return lua_tonumberx(L, idx, null);
}

pub inline fn lua_tointeger(L: ?*lua_State, idx: c_int) lua_Integer {
    return lua_tointegerx(L, idx, null);
}

pub inline fn lua_tostring(L: ?*lua_State, idx: c_int) [*c]const u8 {
    return lua_tolstring(L, idx, null);
}

pub inline fn lua_call(L: ?*lua_State, nargs: c_int, nresults: c_int) void {
    lua_callk(L, nargs, nresults, 0, null);
}

pub inline fn lua_isfunction(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TFUNCTION;
}

pub inline fn lua_istable(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TTABLE;
}

pub inline fn lua_isnil(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TNIL;
}

pub inline fn lua_isboolean(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TBOOLEAN;
}

pub inline fn lua_isnone(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TNONE;
}

pub inline fn lua_isnoneornil(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) <= 0;
}

pub inline fn lua_islightuserdata(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TLIGHTUSERDATA;
}

pub inline fn lua_isthread(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TTHREAD;
}

pub inline fn lua_insert(L: ?*lua_State, idx: c_int) void {
    lua_rotate(L, idx, 1);
}

pub inline fn lua_remove(L: ?*lua_State, idx: c_int) void {
    lua_rotate(L, idx, -1);
    lua_pop(L, 1);
}

pub inline fn lua_replace(L: ?*lua_State, idx: c_int) void {
    lua_copy(L, -1, idx);
    lua_pop(L, 1);
}

pub inline fn lua_newuserdata(L: ?*lua_State, size: usize) ?*anyopaque {
    return lua_newuserdatauv(L, size, 1);
}

pub inline fn luaL_loadfile(L: ?*lua_State, filename: [*c]const u8) c_int {
    return luaL_loadfilex(L, filename, null);
}

pub inline fn luaL_loadbuffer(L: ?*lua_State, buff: [*c]const u8, size: usize, name: [*c]const u8) c_int {
    return luaL_loadbufferx(L, buff, size, name, null);
}

pub inline fn luaL_dofile(L: ?*lua_State, filename: [*c]const u8) c_int {
    const r = luaL_loadfilex(L, filename, null);
    if (r != 0) return r;
    return lua_pcall(L, 0, LUA_MULTRET, 0);
}

pub inline fn luaL_getmetatable(L: ?*lua_State, tname: [*c]const u8) c_int {
    return lua_getfield(L, LUA_REGISTRYINDEX, tname);
}

pub inline fn luaL_typename(L: ?*lua_State, idx: c_int) [*c]const u8 {
    return lua_typename(L, lua_type(L, idx));
}

// ── Lua 5.1 / LuaJIT compatibility shims ───────────────────────────────────
//
// These preserve the names used by ported-from-LuaJIT call sites. Internally
// they forward to the corresponding Lua 5.4 primitives.

/// lua_objlen (5.1) → lua_rawlen (5.4)
pub inline fn lua_objlen(L: ?*lua_State, idx: c_int) usize {
    return @intCast(lua_rawlen(L, idx));
}

/// luaL_typerror (5.1) → luaL_typeerror (5.4, renamed)
pub inline fn luaL_typerror(L: ?*lua_State, narg: c_int, tname: [*c]const u8) c_int {
    return luaL_typeerror(L, narg, tname);
}

/// luaL_register (5.1) — creates/populates a named global library table.
/// Lua 5.4 equivalent: luaL_newlib + lua_setglobal, or when libname is null,
/// luaL_setfuncs onto the table already on top of the stack.
pub inline fn luaL_register(L: ?*lua_State, libname: [*c]const u8, l: [*c]const luaL_Reg) void {
    if (libname != null) {
        lua_createtable(L, 0, 0);
        luaL_setfuncs(L, l, 0);
        lua_pushvalue(L, -1);
        lua_setglobal(L, libname);
    } else {
        luaL_setfuncs(L, l, 0);
    }
}

// LUA_GLOBALSINDEX (5.1 pseudo-index) has no direct 5.4 equivalent. Call
// sites must migrate to lua_getglobal / lua_setglobal. This constant is
// NOT provided — attempting to index the global table via the registry is
// a bug waiting to happen.
//
// For the rarer 5.1 idiom `lua_pushvalue(L, LUA_GLOBALSINDEX)` (push the
// globals table on the stack), 5.4 exposes `lua_pushglobaltable` which
// fetches the globals table from the registry.
pub inline fn lua_pushglobaltable(L: ?*lua_State) void {
    _ = lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS);
}
