// LuaParseUrl - parse URL and push result table onto Lua stack
// Cleaned from translate-c output of cosmopolitan libc Lua 5.4 helpers

const std = @import("std");

// --- Lua 5.4 types ---
pub const struct_lua_State = opaque {};
pub const lua_State = struct_lua_State;
pub const lua_Integer = c_longlong;

// --- URL types ---
pub const struct_UrlView = extern struct {
    n: usize = std.mem.zeroes(usize),
    p: [*c]u8 = std.mem.zeroes([*c]u8),
};

pub const struct_UrlParam = extern struct {
    key: struct_UrlView = std.mem.zeroes(struct_UrlView),
    val: struct_UrlView = std.mem.zeroes(struct_UrlView),
};

pub const struct_UrlParams = extern struct {
    n: usize = std.mem.zeroes(usize),
    p: [*c]struct_UrlParam = std.mem.zeroes([*c]struct_UrlParam),
};

pub const struct_Url = extern struct {
    scheme: struct_UrlView = std.mem.zeroes(struct_UrlView),
    user: struct_UrlView = std.mem.zeroes(struct_UrlView),
    pass: struct_UrlView = std.mem.zeroes(struct_UrlView),
    host: struct_UrlView = std.mem.zeroes(struct_UrlView),
    port: struct_UrlView = std.mem.zeroes(struct_UrlView),
    path: struct_UrlView = std.mem.zeroes(struct_UrlView),
    params: struct_UrlParams = std.mem.zeroes(struct_UrlParams),
    fragment: struct_UrlView = std.mem.zeroes(struct_UrlView),
};

// --- C library externs ---
pub extern fn free(?*anyopaque) void;

// --- Lua API externs ---
pub extern fn luaL_checklstring(L: ?*lua_State, arg: c_int, l: [*c]usize) [*c]const u8;
pub extern fn luaL_optinteger(L: ?*lua_State, arg: c_int, def: lua_Integer) lua_Integer;
pub extern fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
pub extern fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) void;
pub extern fn lua_pushlstring(L: ?*lua_State, s: [*c]const u8, len: usize) [*c]const u8;
pub extern fn lua_pushnil(L: ?*lua_State) void;

// --- Peer function externs ---
pub extern fn ParseUrl([*c]const u8, usize, [*c]struct_Url, c_int) [*c]u8;
pub extern fn LuaPushUrlParams(?*lua_State, [*c]struct_UrlParams) void;

// --- Helper functions ---
fn LuaPushUrlView(L: ?*lua_State, v: *struct_UrlView) callconv(.c) void {
    if (v.p != null) {
        _ = lua_pushlstring(L, v.p, v.n);
    } else {
        lua_pushnil(L);
    }
}

fn LuaSetUrlView(L: ?*lua_State, v: *struct_UrlView, k: [*c]const u8) callconv(.c) void {
    LuaPushUrlView(L, v);
    lua_setfield(L, -2, k);
}

// --- Exported function ---
pub fn LuaParseUrl(L: ?*lua_State) c_int {
    var n: usize = undefined;
    const p = luaL_checklstring(L, 1, &n);
    const f: c_int = @intCast(@as(i32, @truncate(luaL_optinteger(L, 2, 0))));
    var h: struct_Url = undefined;
    const m: ?*anyopaque = @ptrCast(ParseUrl(p, n, &h, f));
    lua_createtable(L, 0, 0);
    LuaSetUrlView(L, &h.scheme, "scheme");
    LuaSetUrlView(L, &h.user, "user");
    LuaSetUrlView(L, &h.pass, "pass");
    LuaSetUrlView(L, &h.host, "host");
    LuaSetUrlView(L, &h.port, "port");
    LuaSetUrlView(L, &h.path, "path");
    LuaSetUrlView(L, &h.fragment, "fragment");
    LuaPushUrlParams(L, &h.params);
    lua_setfield(L, -2, "params");
    free(@ptrCast(h.params.p));
    free(m);
    return 1;
}

