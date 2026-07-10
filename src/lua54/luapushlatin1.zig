// LuaPushLatin1 - decode Latin-1 string and push onto Lua stack
// Cleaned from translate-c output of cosmopolitan libc Lua 5.4 helpers

const std = @import("std");

// --- Lua 5.4 types ---
pub const struct_lua_State = opaque {};
pub const lua_State = struct_lua_State;

// --- C library externs ---
pub extern fn free(?*anyopaque) void;

// --- Lua API externs ---
pub extern fn lua_pushlstring(L: ?*lua_State, s: [*c]const u8, len: usize) [*c]const u8;

// --- Peer function externs ---
pub extern fn DecodeLatin1([*c]const u8, usize, [*c]usize) [*c]u8;

// --- Exported function ---
pub export fn LuaPushLatin1(L: ?*lua_State, s: [*c]const u8, n: usize) void {
    var m: usize = undefined;
    const t: [*c]u8 = DecodeLatin1(s, n, &m);
    _ = lua_pushlstring(L, t, m);
    free(@ptrCast(t));
}
