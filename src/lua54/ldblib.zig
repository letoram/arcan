// Lua 5.4 debug library — debug.getinfo, debug.sethook, etc.
// Cleaned from translate-c output of ldblib.c.

const std = @import("std");
const FILE = std.c.FILE;

const lua_State = opaque {};
const lua_Number = f64;
const lua_Integer = c_longlong;
const lua_KContext = isize;
const lua_KFunction = ?*const fn (?*lua_State, c_int, lua_KContext) callconv(.c) c_int;
const lua_CFunction = ?*const fn (?*lua_State) callconv(.c) c_int;

const struct_CallInfo_2 = opaque {};

const lua_Debug = extern struct {
    event: c_int = 0,
    name: ?[*:0]const u8 = null,
    namewhat: ?[*:0]const u8 = null,
    what: ?[*:0]const u8 = null,
    source: ?[*:0]const u8 = null,
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
    i_ci: ?*struct_CallInfo_2 = null,
};

const lua_Hook = ?*const fn (?*lua_State, *lua_Debug) callconv(.c) void;

const luaL_Reg = extern struct {
    name: ?[*:0]const u8 = null,
    func: lua_CFunction = null,
};

// Lua API
extern fn lua_gettop(L: ?*lua_State) c_int;
extern fn lua_settop(L: ?*lua_State, idx: c_int) void;
extern fn lua_pushvalue(L: ?*lua_State, idx: c_int) void;
extern fn lua_rotate(L: ?*lua_State, idx: c_int, n: c_int) void;
extern fn lua_checkstack(L: ?*lua_State, n: c_int) c_int;
extern fn lua_xmove(from: ?*lua_State, to: ?*lua_State, n: c_int) void;
extern fn lua_type(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_typename(L: ?*lua_State, tp: c_int) [*:0]const u8;
extern fn lua_toboolean(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_tolstring(L: ?*lua_State, idx: c_int, len: ?*usize) ?[*:0]const u8;
extern fn lua_tothread(L: ?*lua_State, idx: c_int) ?*lua_State;
extern fn lua_iscfunction(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_compare(L: ?*lua_State, idx1: c_int, idx2: c_int, op: c_int) c_int;
extern fn lua_pushnil(L: ?*lua_State) void;
extern fn lua_pushinteger(L: ?*lua_State, n: lua_Integer) void;
extern fn lua_pushstring(L: ?*lua_State, s: ?[*:0]const u8) ?[*:0]const u8;
extern fn lua_pushlstring(L: ?*lua_State, s: [*]const u8, len: usize) ?[*:0]const u8;
extern fn lua_pushfstring(L: ?*lua_State, fmt: [*:0]const u8, ...) ?[*:0]const u8;
extern fn lua_pushboolean(L: ?*lua_State, b: c_int) void;
extern fn lua_pushlightuserdata(L: ?*lua_State, p: ?*anyopaque) void;
extern fn lua_pushthread(L: ?*lua_State) c_int;
extern fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
extern fn lua_getmetatable(L: ?*lua_State, objindex: c_int) c_int;
extern fn lua_getfield(L: ?*lua_State, idx: c_int, k: [*:0]const u8) c_int;
extern fn lua_rawget(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_rawset(L: ?*lua_State, idx: c_int) void;
extern fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*:0]const u8) void;
extern fn lua_setmetatable(L: ?*lua_State, objindex: c_int) c_int;
extern fn lua_getiuservalue(L: ?*lua_State, idx: c_int, n: c_int) c_int;
extern fn lua_setiuservalue(L: ?*lua_State, idx: c_int, n: c_int) c_int;
extern fn lua_callk(L: ?*lua_State, nargs: c_int, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) void;
extern fn lua_pcallk(L: ?*lua_State, nargs: c_int, nresults: c_int, errfunc: c_int, ctx: lua_KContext, k: lua_KFunction) c_int;
extern fn lua_getstack(L: ?*lua_State, level: c_int, ar: *lua_Debug) c_int;
extern fn lua_getinfo(L: ?*lua_State, what: [*:0]const u8, ar: *lua_Debug) c_int;
extern fn lua_getlocal(L: ?*lua_State, ar: ?*const lua_Debug, n: c_int) ?[*:0]const u8;
extern fn lua_setlocal(L: ?*lua_State, ar: ?*const lua_Debug, n: c_int) ?[*:0]const u8;
extern fn lua_getupvalue(L: ?*lua_State, funcindex: c_int, n: c_int) ?[*:0]const u8;
extern fn lua_setupvalue(L: ?*lua_State, funcindex: c_int, n: c_int) ?[*:0]const u8;
extern fn lua_upvalueid(L: ?*lua_State, fidx: c_int, n: c_int) ?*anyopaque;
extern fn lua_upvaluejoin(L: ?*lua_State, fidx1: c_int, n1: c_int, fidx2: c_int, n2: c_int) void;
extern fn lua_sethook(L: ?*lua_State, func: lua_Hook, mask: c_int, count: c_int) void;
extern fn lua_gethook(L: ?*lua_State) lua_Hook;
extern fn lua_gethookmask(L: ?*lua_State) c_int;
extern fn lua_gethookcount(L: ?*lua_State) c_int;
extern fn lua_setcstacklimit(L: ?*lua_State, limit: c_uint) c_int;

// Auxiliary library
extern fn luaL_checkversion_(L: ?*lua_State, ver: lua_Number, sz: usize) void;
extern fn luaL_argerror(L: ?*lua_State, arg: c_int, extramsg: [*:0]const u8) c_int;
extern fn luaL_typeerror(L: ?*lua_State, arg: c_int, tname: [*:0]const u8) c_int;
extern fn luaL_error(L: ?*lua_State, fmt: [*:0]const u8, ...) c_int;
extern fn luaL_checkinteger(L: ?*lua_State, arg: c_int) lua_Integer;
extern fn luaL_optinteger(L: ?*lua_State, arg: c_int, def: lua_Integer) lua_Integer;
extern fn luaL_checklstring(L: ?*lua_State, arg: c_int, l: ?*usize) [*:0]const u8;
extern fn luaL_optlstring(L: ?*lua_State, arg: c_int, def: ?[*:0]const u8, l: ?*usize) ?[*:0]const u8;
extern fn luaL_checktype(L: ?*lua_State, arg: c_int, t: c_int) void;
extern fn luaL_checkany(L: ?*lua_State, arg: c_int) void;
extern fn luaL_tolstring(L: ?*lua_State, idx: c_int, len: ?*usize) ?[*:0]const u8;
extern fn luaL_setfuncs(L: ?*lua_State, l: [*]const luaL_Reg, nup: c_int) void;
extern fn luaL_getsubtable(L: ?*lua_State, idx: c_int, fname: [*:0]const u8) c_int;
extern fn luaL_traceback(L: ?*lua_State, L1: ?*lua_State, msg: ?[*:0]const u8, level: c_int) void;
extern fn luaL_loadbufferx(L: ?*lua_State, buff: [*]const u8, sz: usize, name: [*:0]const u8, mode: ?[*:0]const u8) c_int;
extern fn luaL_callmeta(L: ?*lua_State, obj: c_int, e: [*:0]const u8) c_int;

// C standard library
extern fn strchr(s: [*:0]const u8, c_2: c_int) ?[*:0]const u8;
extern fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int;
extern fn strlen(s: [*:0]const u8) usize;
extern var stderr: *FILE;
extern var stdin: *FILE;
extern fn fprintf(stream: *FILE, fmt: [*:0]const u8, ...) c_int;
extern fn fflush(stream: *FILE) c_int;
extern fn fgets(s: [*]u8, size: c_int, stream: *FILE) ?[*]u8;

// LUA_REGISTRYINDEX
const LUA_REGISTRYINDEX = -1000000 - 1000;

const HOOKKEY: [*:0]const u8 = "_HOOKKEY";

pub export fn luaopen_debug(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkversion_(L, @floatFromInt(@as(c_int, 504)), @sizeOf(lua_Integer) *% 16 +% @sizeOf(lua_Number));
    lua_createtable(L, 0, @as(c_int, @intCast(dblib.len - 1)));
    luaL_setfuncs(L, &dblib, 0);
    return 1;
}

comptime {
    // asm (".section .yoink\n\tb\t\"lua_notice\"\n\t.previous");
}

fn checkstack(L: ?*lua_State, L1: ?*lua_State, n: c_int) void {
    if (L != L1 and lua_checkstack(L1, n) == 0) {
        _ = luaL_error(L, "stack overflow");
    }
}

fn db_getregistry(L: ?*lua_State) callconv(.c) c_int {
    lua_pushvalue(L, LUA_REGISTRYINDEX);
    return 1;
}

fn db_getmetatable(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkany(L, 1);
    if (lua_getmetatable(L, 1) == 0) {
        lua_pushnil(L);
    }
    return 1;
}

fn db_setmetatable(L: ?*lua_State) callconv(.c) c_int {
    const t = lua_type(L, 2);
    _ = (t == 0 or t == 5) or (luaL_typeerror(L, 2, "nil or table") != 0); // LUA_TNIL or LUA_TTABLE
    lua_settop(L, 2);
    _ = lua_setmetatable(L, 1);
    return 1;
}

fn db_getuservalue(L: ?*lua_State) callconv(.c) c_int {
    const n: c_int = @intCast(@as(c_int, @truncate(luaL_optinteger(L, 2, 1))));
    if (lua_type(L, 1) != 7) { // LUA_TUSERDATA
        lua_pushnil(L);
    } else if (lua_getiuservalue(L, 1, n) != -1) { // LUA_TNONE
        lua_pushboolean(L, 1);
        return 2;
    }
    return 1;
}

fn db_setuservalue(L: ?*lua_State) callconv(.c) c_int {
    const n: c_int = @intCast(@as(c_int, @truncate(luaL_optinteger(L, 3, 1))));
    luaL_checktype(L, 1, 7); // LUA_TUSERDATA
    luaL_checkany(L, 2);
    lua_settop(L, 2);
    if (lua_setiuservalue(L, 1, n) == 0) {
        lua_pushnil(L);
    }
    return 1;
}

fn getthread(L: ?*lua_State, arg: *c_int) ?*lua_State {
    if (lua_type(L, 1) == 8) { // LUA_TTHREAD
        arg.* = 1;
        return lua_tothread(L, 1);
    } else {
        arg.* = 0;
        return L;
    }
}

fn settabss(L: ?*lua_State, k: [*:0]const u8, v: ?[*:0]const u8) void {
    _ = lua_pushstring(L, v);
    lua_setfield(L, -2, k);
}

fn settabsi(L: ?*lua_State, k: [*:0]const u8, v: c_int) void {
    lua_pushinteger(L, @intCast(v));
    lua_setfield(L, -2, k);
}

fn settabsb(L: ?*lua_State, k: [*:0]const u8, v: c_int) void {
    lua_pushboolean(L, v);
    lua_setfield(L, -2, k);
}

fn treatstackoption(L: ?*lua_State, L1: ?*lua_State, fname: [*:0]const u8) void {
    if (L == L1) {
        lua_rotate(L, -2, 1);
    } else {
        lua_xmove(L1, L, 1);
    }
    lua_setfield(L, -2, fname);
}

fn db_getinfo(L: ?*lua_State) callconv(.c) c_int {
    var ar: lua_Debug = undefined;
    var arg: c_int = undefined;
    const L1: ?*lua_State = getthread(L, &arg);
    var options: ?[*:0]const u8 = luaL_optlstring(L, arg + 2, "flnSrtu", null);
    checkstack(L, L1, 3);
    if (options) |opts| {
        _ = (opts[0] != '>') or (luaL_argerror(L, arg + 2, "invalid option '>'") != 0);
    }
    if (lua_type(L, arg + 1) == 6) { // LUA_TFUNCTION
        {
            var fmtbuf: [512]u8 = undefined;
            const result = std.fmt.bufPrintZ(&fmtbuf, ">{s}", .{
                if (options) |o| std.mem.span(o) else "",
            }) catch ">?";
            options = lua_pushstring(L, result);
        }
        lua_pushvalue(L, arg + 1);
        lua_xmove(L, L1, 1);
    } else {
        if (lua_getstack(L1, @intCast(@as(c_int, @truncate(luaL_checkinteger(L, arg + 1)))), &ar) == 0) {
            lua_pushnil(L);
            return 1;
        }
    }
    if (lua_getinfo(L1, options.?, &ar) == 0) return luaL_argerror(L, arg + 2, "invalid option");
    lua_createtable(L, 0, 0);
    if (strchr(options.?, 'S') != null) {
        if (ar.source) |src| {
            _ = lua_pushlstring(L, src, ar.srclen);
        } else {
            lua_pushnil(L);
        }
        lua_setfield(L, -2, "source");
        settabss(L, "short_src", @ptrCast(&ar.short_src));
        settabsi(L, "linedefined", ar.linedefined);
        settabsi(L, "lastlinedefined", ar.lastlinedefined);
        settabss(L, "what", ar.what);
    }
    if (strchr(options.?, 'l') != null) {
        settabsi(L, "currentline", ar.currentline);
    }
    if (strchr(options.?, 'u') != null) {
        settabsi(L, "nups", @intCast(ar.nups));
        settabsi(L, "nparams", @intCast(ar.nparams));
        settabsb(L, "isvararg", @intCast(ar.isvararg));
    }
    if (strchr(options.?, 'n') != null) {
        settabss(L, "name", ar.name);
        settabss(L, "namewhat", ar.namewhat);
    }
    if (strchr(options.?, 'r') != null) {
        settabsi(L, "ftransfer", @intCast(ar.ftransfer));
        settabsi(L, "ntransfer", @intCast(ar.ntransfer));
    }
    if (strchr(options.?, 't') != null) {
        settabsb(L, "istailcall", @intCast(ar.istailcall));
    }
    if (strchr(options.?, 'L') != null) {
        treatstackoption(L, L1, "activelines");
    }
    if (strchr(options.?, 'f') != null) {
        treatstackoption(L, L1, "func");
    }
    return 1;
}

fn db_getlocal(L: ?*lua_State) callconv(.c) c_int {
    var arg: c_int = undefined;
    const L1: ?*lua_State = getthread(L, &arg);
    const nvar: c_int = @intCast(@as(c_int, @truncate(luaL_checkinteger(L, arg + 2))));
    if (lua_type(L, arg + 1) == 6) { // LUA_TFUNCTION
        lua_pushvalue(L, arg + 1);
        _ = lua_pushstring(L, lua_getlocal(L, null, nvar));
        return 1;
    } else {
        var ar: lua_Debug = undefined;
        const level: c_int = @intCast(@as(c_int, @truncate(luaL_checkinteger(L, arg + 1))));
        if (lua_getstack(L1, level, &ar) == 0) return luaL_argerror(L, arg + 1, "level out of range");
        checkstack(L, L1, 1);
        const name = lua_getlocal(L1, &ar, nvar);
        if (name != null) {
            lua_xmove(L1, L, 1);
            _ = lua_pushstring(L, name);
            lua_rotate(L, -2, 1);
            return 2;
        } else {
            lua_pushnil(L);
            return 1;
        }
    }
}

fn db_setlocal(L: ?*lua_State) callconv(.c) c_int {
    var arg: c_int = undefined;
    const L1: ?*lua_State = getthread(L, &arg);
    var ar: lua_Debug = undefined;
    const level: c_int = @intCast(@as(c_int, @truncate(luaL_checkinteger(L, arg + 1))));
    const nvar: c_int = @intCast(@as(c_int, @truncate(luaL_checkinteger(L, arg + 2))));
    if (lua_getstack(L1, level, &ar) == 0) return luaL_argerror(L, arg + 1, "level out of range");
    luaL_checkany(L, arg + 3);
    lua_settop(L, arg + 3);
    checkstack(L, L1, 1);
    lua_xmove(L, L1, 1);
    const name = lua_setlocal(L1, &ar, nvar);
    if (name == null) {
        lua_settop(L1, -2); // pop value
    }
    _ = lua_pushstring(L, name);
    return 1;
}

fn auxupvalue(L: ?*lua_State, get: c_int) c_int {
    const n: c_int = @intCast(@as(c_int, @truncate(luaL_checkinteger(L, 2))));
    luaL_checktype(L, 1, 6); // LUA_TFUNCTION
    const name = if (get != 0) lua_getupvalue(L, 1, n) else lua_setupvalue(L, 1, n);
    if (name == null) return 0;
    _ = lua_pushstring(L, name);
    lua_rotate(L, -(get + 1), 1);
    return get + 1;
}

fn db_getupvalue(L: ?*lua_State) callconv(.c) c_int {
    return auxupvalue(L, 1);
}

fn db_setupvalue(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkany(L, 3);
    return auxupvalue(L, 0);
}

fn checkupval(L: ?*lua_State, argf: c_int, argnup: c_int, pnup: ?*c_int) ?*anyopaque {
    const nup: c_int = @intCast(@as(c_int, @truncate(luaL_checkinteger(L, argnup))));
    luaL_checktype(L, argf, 6); // LUA_TFUNCTION
    const id = lua_upvalueid(L, argf, nup);
    if (pnup) |p| {
        _ = (id != null) or (luaL_argerror(L, argnup, "invalid upvalue index") != 0);
        p.* = nup;
    }
    return id;
}

fn db_upvalueid(L: ?*lua_State) callconv(.c) c_int {
    const id = checkupval(L, 1, 2, null);
    if (id != null) {
        lua_pushlightuserdata(L, id);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

fn db_upvaluejoin(L: ?*lua_State) callconv(.c) c_int {
    var n1: c_int = undefined;
    var n2: c_int = undefined;
    _ = checkupval(L, 1, 2, &n1);
    _ = checkupval(L, 3, 4, &n2);
    _ = (lua_iscfunction(L, 1) == 0) or (luaL_argerror(L, 1, "Lua function expected") != 0);
    _ = (lua_iscfunction(L, 3) == 0) or (luaL_argerror(L, 3, "Lua function expected") != 0);
    lua_upvaluejoin(L, 1, n1, 3, n2);
    return 0;
}

fn hookf(L: ?*lua_State, ar: *lua_Debug) callconv(.c) void {
    const hooknames = [5][*:0]const u8{
        "call",
        "return",
        "line",
        "count",
        "tail call",
    };
    _ = lua_getfield(L, LUA_REGISTRYINDEX, HOOKKEY);
    _ = lua_pushthread(L);
    if (lua_rawget(L, -2) == 6) { // LUA_TFUNCTION
        _ = lua_pushstring(L, hooknames[@intCast(ar.event)]);
        if (ar.currentline >= 0) {
            lua_pushinteger(L, @intCast(ar.currentline));
        } else {
            lua_pushnil(L);
        }
        lua_callk(L, 2, 0, 0, null);
    }
}

fn makemask(smask: [*:0]const u8, count: c_int) c_int {
    var mask: c_int = 0;
    if (strchr(smask, 'c') != null) mask |= 1 << 0; // LUA_MASKCALL
    if (strchr(smask, 'r') != null) mask |= 1 << 1; // LUA_MASKRET
    if (strchr(smask, 'l') != null) mask |= 1 << 2; // LUA_MASKLINE
    if (count > 0) mask |= 1 << 3; // LUA_MASKCOUNT
    return mask;
}

fn unmakemask(mask: c_int, smask: [*]u8) [*]u8 {
    var i: usize = 0;
    if (mask & (1 << 0) != 0) {
        smask[i] = 'c';
        i += 1;
    }
    if (mask & (1 << 1) != 0) {
        smask[i] = 'r';
        i += 1;
    }
    if (mask & (1 << 2) != 0) {
        smask[i] = 'l';
        i += 1;
    }
    smask[i] = 0;
    return smask;
}

fn db_sethook(L: ?*lua_State) callconv(.c) c_int {
    var arg: c_int = undefined;
    var mask: c_int = undefined;
    var count: c_int = undefined;
    var func: lua_Hook = undefined;
    const L1: ?*lua_State = getthread(L, &arg);
    if (lua_type(L, arg + 1) <= 0) { // LUA_TNONE/LUA_TNIL
        lua_settop(L, arg + 1);
        func = null;
        mask = 0;
        count = 0;
    } else {
        const smask = luaL_checklstring(L, arg + 2, null);
        luaL_checktype(L, arg + 1, 6); // LUA_TFUNCTION
        count = @intCast(@as(c_int, @truncate(luaL_optinteger(L, arg + 3, 0))));
        func = &hookf;
        mask = makemask(smask, count);
    }
    if (luaL_getsubtable(L, LUA_REGISTRYINDEX, HOOKKEY) == 0) {
        _ = lua_pushstring(L, "k");
        lua_setfield(L, -2, "__mode");
        lua_pushvalue(L, -1);
        _ = lua_setmetatable(L, -2);
    }
    checkstack(L, L1, 1);
    _ = lua_pushthread(L1);
    lua_xmove(L1, L, 1);
    lua_pushvalue(L, arg + 1);
    lua_rawset(L, -3);
    lua_sethook(L1, func, mask, count);
    return 0;
}

fn db_gethook(L: ?*lua_State) callconv(.c) c_int {
    var arg: c_int = undefined;
    const L1: ?*lua_State = getthread(L, &arg);
    var buff: [5]u8 = undefined;
    const mask = lua_gethookmask(L1);
    const hook = lua_gethook(L1);
    if (hook == null) {
        lua_pushnil(L);
        return 1;
    } else if (hook != &hookf) {
        _ = lua_pushstring(L, "external hook");
    } else {
        _ = lua_getfield(L, LUA_REGISTRYINDEX, HOOKKEY);
        checkstack(L, L1, 1);
        _ = lua_pushthread(L1);
        lua_xmove(L1, L, 1);
        _ = lua_rawget(L, -2);
        // remove HOOKKEY table
        lua_rotate(L, -2, -1);
        lua_settop(L, -2);
    }
    _ = lua_pushstring(L, @ptrCast(unmakemask(mask, &buff)));
    lua_pushinteger(L, @intCast(lua_gethookcount(L1)));
    return 3;
}

fn db_debug(L: ?*lua_State) callconv(.c) c_int {
    while (true) {
        var buffer: [250]u8 = undefined;
        _ = fprintf(stderr, "%s", "lua_debug> ");
        _ = fflush(stderr);
        if (fgets(&buffer, @intCast(@sizeOf([250]u8)), stdin) == null or strcmp(@ptrCast(&buffer), "cont\n") == 0) return 0;
        if (luaL_loadbufferx(L, @ptrCast(&buffer), strlen(@ptrCast(&buffer)), "=(debug command)", null) != 0 or lua_pcallk(L, 0, 0, 0, 0, null) != 0) {
            _ = fprintf(stderr, "%s\n", luaL_tolstring(L, -1, null).?);
            _ = fflush(stderr);
        }
        lua_settop(L, 0);
    }
    return 0;
}

fn db_traceback(L: ?*lua_State) callconv(.c) c_int {
    var arg: c_int = undefined;
    const L1: ?*lua_State = getthread(L, &arg);
    const msg = lua_tolstring(L, arg + 1, null);
    if (msg == null and lua_type(L, arg + 1) > 0) {
        lua_pushvalue(L, arg + 1);
    } else {
        const level: c_int = @intCast(@as(c_int, @truncate(luaL_optinteger(L, arg + 2, if (L == L1) @as(c_int, 1) else 0))));
        luaL_traceback(L, L1, msg, level);
    }
    return 1;
}

fn db_setcstacklimit(L: ?*lua_State) callconv(.c) c_int {
    const limit: c_int = @intCast(@as(c_int, @truncate(luaL_checkinteger(L, 1))));
    const res = lua_setcstacklimit(L, @bitCast(limit));
    lua_pushinteger(L, @intCast(res));
    return 1;
}

const dblib = [_]luaL_Reg{
    .{ .name = "debug", .func = &db_debug },
    .{ .name = "getuservalue", .func = &db_getuservalue },
    .{ .name = "gethook", .func = &db_gethook },
    .{ .name = "getinfo", .func = &db_getinfo },
    .{ .name = "getlocal", .func = &db_getlocal },
    .{ .name = "getregistry", .func = &db_getregistry },
    .{ .name = "getmetatable", .func = &db_getmetatable },
    .{ .name = "getupvalue", .func = &db_getupvalue },
    .{ .name = "upvaluejoin", .func = &db_upvaluejoin },
    .{ .name = "upvalueid", .func = &db_upvalueid },
    .{ .name = "setuservalue", .func = &db_setuservalue },
    .{ .name = "sethook", .func = &db_sethook },
    .{ .name = "setlocal", .func = &db_setlocal },
    .{ .name = "setmetatable", .func = &db_setmetatable },
    .{ .name = "setupvalue", .func = &db_setupvalue },
    .{ .name = "traceback", .func = &db_traceback },
    .{ .name = "setcstacklimit", .func = &db_setcstacklimit },
    .{ .name = null, .func = null }, // sentinel
};
