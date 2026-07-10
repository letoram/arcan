// LuaFormatStack - format Lua stack as string
// Cleaned from translate-c output of cosmopolitan libc Lua 5.4 helpers

const std = @import("std");

// --- Lua 5.4 types ---
pub const struct_lua_State = opaque {};
pub const lua_State = struct_lua_State;

// --- Encoder config ---
pub const struct_EncoderConfig = extern struct {
    maxdepth: c_short = std.mem.zeroes(c_short),
    sorted: bool = std.mem.zeroes(bool),
    pretty: bool = std.mem.zeroes(bool),
    indent: [*c]const u8 = std.mem.zeroes([*c]const u8),
};

// --- Lua API externs ---
pub extern fn lua_gettop(L: ?*lua_State) c_int;

// --- Peer function externs ---
pub extern fn LuaEncodeLuaData(?*lua_State, [*c][*c]u8, c_int, struct_EncoderConfig) c_int;

// --- Exported function ---
pub export fn LuaFormatStack(L: ?*lua_State) [*c]u8 {
    var b: [*c]u8 = null;
    const conf = struct_EncoderConfig{
        .maxdepth = 64,
        .sorted = true,
        .pretty = false,
        .indent = "  ",
    };
    const top = lua_gettop(L);
    var i: c_int = 1;
    while (i <= top) : (i += 1) {
        _ = LuaEncodeLuaData(L, &b, i, conf);
    }
    return b;
}

