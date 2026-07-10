// LuaPushUrlParams — pushes URL parameters as a Lua table.
// Cleaned from translate-c output of luapushurlparams.c.

const lua_State = opaque {};
const lua_Integer = c_longlong;

const UrlView = extern struct {
    n: usize = 0,
    p: [*c]u8 = null,
};

const UrlParam = extern struct {
    key: UrlView = .{},
    val: UrlView = .{},
};

const UrlParams = extern struct {
    n: usize = 0,
    p: [*c]UrlParam = null,
};

extern fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
extern fn lua_pushlstring(L: ?*lua_State, s: [*]const u8, len: usize) [*]const u8;
extern fn lua_seti(L: ?*lua_State, idx: c_int, n: lua_Integer) void;

pub export fn LuaPushUrlParams(L: ?*lua_State, h: *UrlParams) void {
    lua_createtable(L, 0, 0);
    var i: usize = 0;
    while (i < h.n) : (i += 1) {
        lua_createtable(L, 0, 0);
        _ = lua_pushlstring(L, h.p[i].key.p, h.p[i].key.n);
        lua_seti(L, -2, 1);
        if (h.p[i].val.p != null) {
            _ = lua_pushlstring(L, h.p[i].val.p, h.p[i].val.n);
            lua_seti(L, -2, 2);
        }
        lua_seti(L, -2, @intCast(i + 1));
    }
}
