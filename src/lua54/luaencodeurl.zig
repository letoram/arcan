// LuaEncodeUrl — encode a Lua table as a URL string.
// Cleaned from translate-c output of luaencodeurl.c.

const std = @import("std");

const lua_State = opaque {};
const lua_Integer = c_longlong;

extern fn lua_gettop(L: ?*lua_State) c_int;
extern fn lua_settop(L: ?*lua_State, idx: c_int) void;
extern fn lua_type(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_tolstring(L: ?*lua_State, idx: c_int, len: ?*usize) ?[*:0]const u8;
extern fn lua_pushnil(L: ?*lua_State) void;
extern fn lua_pushlstring(L: ?*lua_State, s: [*]const u8, len: usize) ?[*:0]const u8;
extern fn lua_getfield(L: ?*lua_State, idx: c_int, k: [*:0]const u8) c_int;
extern fn lua_geti(L: ?*lua_State, idx: c_int, n: lua_Integer) c_int;
extern fn lua_len(L: ?*lua_State, idx: c_int) void;
extern fn lua_tointegerx(L: ?*lua_State, idx: c_int, isnum: ?*c_int) lua_Integer;
extern fn luaL_checktype(L: ?*lua_State, arg: c_int, t: c_int) void;

const UrlView = extern struct {
    n: usize = 0,
    p: ?[*]u8 = null,
};

const UrlParam = extern struct {
    key: UrlView = .{},
    val: UrlView = .{},
};

const UrlParams = extern struct {
    n: usize = 0,
    p: ?[*]UrlParam = null,
};

const Url = extern struct {
    scheme: UrlView = .{},
    user: UrlView = .{},
    pass: UrlView = .{},
    host: UrlView = .{},
    port: UrlView = .{},
    path: UrlView = .{},
    params: UrlParams = .{},
    fragment: UrlView = .{},
};

extern fn EncodeUrl(url: *Url, size: *usize) ?[*]u8;
extern fn bzero(s: ?*anyopaque, n: usize) void;
extern fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

pub fn LuaEncodeUrl(arg_L: ?*lua_State) c_int {
    const L = arg_L;
    var data: ?[*]u8 = undefined;
    var size: usize = undefined;
    var j: c_int = undefined;
    var n: c_int = undefined;
    var h: Url = undefined;

    if (lua_type(L, 1) != 0) { // not LUA_TNIL
        const i = lua_gettop(L);
        bzero(@ptrCast(&h), @sizeOf(Url));
        luaL_checktype(L, 1, 5); // LUA_TTABLE

        if (lua_getfield(L, 1, "scheme") != 0) {
            h.scheme.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.scheme.n)));
        }
        if (lua_getfield(L, 1, "fragment") != 0) {
            h.fragment.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.fragment.n)));
        }
        if (lua_getfield(L, 1, "user") != 0) {
            h.user.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.user.n)));
        }
        if (lua_getfield(L, 1, "pass") != 0) {
            h.pass.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.pass.n)));
        }
        if (lua_getfield(L, 1, "host") != 0) {
            h.host.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.host.n)));
        }
        if (lua_getfield(L, 1, "port") != 0) {
            h.port.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.port.n)));
        }
        if (lua_getfield(L, 1, "path") != 0) {
            h.path.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.path.n)));
        }

        lua_settop(L, i);

        if (lua_getfield(L, 1, "params") != 0) {
            luaL_checktype(L, -1, 5); // LUA_TTABLE
            lua_len(L, -1);
            n = @intCast(@as(c_int, @truncate(lua_tointegerx(L, -1, null))));
            lua_settop(L, -2); // pop length

            j = 1;
            while (j <= n) : (j += 1) {
                if (lua_geti(L, -1, @intCast(j)) != 0) {
                    luaL_checktype(L, -1, 5); // LUA_TTABLE
                    if (lua_geti(L, -1, 1) != 0) {
                        h.params.p = @ptrCast(@alignCast(realloc(
                            @ptrCast(h.params.p),
                            blk: {
                                h.params.n += 1;
                                break :blk h.params.n * @sizeOf(UrlParam);
                            },
                        )));
                        const idx = h.params.n - 1;
                        h.params.p.?[idx].key.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.params.p.?[idx].key.n)));
                        if (lua_geti(L, -2, 2) != 0) {
                            h.params.p.?[idx].val.p = @constCast(@ptrCast(lua_tolstring(L, -1, &h.params.p.?[idx].val.n)));
                        } else {
                            h.params.p.?[idx].val.p = null;
                            h.params.p.?[idx].val.n = 0;
                        }
                    }
                }
                lua_settop(L, i + 1);
            }
        }

        data = EncodeUrl(&h, &size);
        if (data) |d| {
            _ = lua_pushlstring(L, d, size);
        } else {
            lua_pushnil(L);
        }
        free(@ptrCast(h.params.p));
        free(@ptrCast(data));
    } else {
        lua_pushnil(L);
    }
    return 1;
}
