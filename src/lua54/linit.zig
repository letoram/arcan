// Lua 5.4 standard library initialization — opens all standard libs.
// Cleaned from translate-c output of linit.c.

const lua_State = opaque {};
const lua_CFunction = ?*const fn (?*lua_State) callconv(.c) c_int;

// `name` must be nullable — luaL_setfuncs iterates until name == NULL,
// and leaving the default as `undefined` gives every sentinel row a
// 0xAA-filled pointer in Zig safe mode, which strcmp then dereferences.
const luaL_Reg = extern struct {
    name: ?[*:0]const u8 = null,
    func: lua_CFunction = null,
};

extern fn luaL_requiref(L: ?*lua_State, modname: [*:0]const u8, openf: lua_CFunction, glb: c_int) void;
extern fn lua_settop(L: ?*lua_State, idx: c_int) void;

extern fn luaopen_base(L: ?*lua_State) c_int;
extern fn luaopen_package(L: ?*lua_State) c_int;
extern fn luaopen_coroutine(L: ?*lua_State) c_int;
extern fn luaopen_table(L: ?*lua_State) c_int;
extern fn luaopen_io(L: ?*lua_State) c_int;
extern fn luaopen_os(L: ?*lua_State) c_int;
extern fn luaopen_string(L: ?*lua_State) c_int;
extern fn luaopen_math(L: ?*lua_State) c_int;
extern fn luaopen_utf8(L: ?*lua_State) c_int;
extern fn luaopen_debug(L: ?*lua_State) c_int;

pub export fn luaL_openlibs(L: ?*lua_State) callconv(.c) void {
    for (&loadedlibs) |*lib| {
        const name = lib.name orelse break; // sentinel
        if (lib.func) |_| {
            luaL_requiref(L, name, lib.func, 1);
            lua_settop(L, -2);
        }
    }
}

const loadedlibs = [_]luaL_Reg{
    .{ .name = "_G", .func = &luaopen_base },
    // Skip libraries that may trigger errors or need OS support:
    // .{ .name = "package", .func = &luaopen_package },  // needs require/searchpath
    .{ .name = "coroutine", .func = &luaopen_coroutine },
    .{ .name = "table", .func = &luaopen_table },
    // io is intentionally still skipped — we don't ship a filesystem layer.
    // os is needed by arcan_bootstrap.lua's whitelist (os.clock/time/date/
    // difftime). Without it, durden's bootstrap fails with
    //   "attempt to index a nil value (global 'os')"
    // at the whitelist construction in arcan_bootstrap.lua:~90.
    .{ .name = "os", .func = &luaopen_os },
    .{ .name = "string", .func = &luaopen_string },
    .{ .name = "math", .func = &luaopen_math },
    .{ .name = "utf8", .func = &luaopen_utf8 },
    .{ .name = "debug", .func = &luaopen_debug },
    // Sentinel — see lutf8lib.zig. Must be explicit null.
    .{ .name = null, .func = null },
};
