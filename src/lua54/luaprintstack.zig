// LuaPrintStack - print Lua stack to stderr
// Cleaned from translate-c output of cosmopolitan libc Lua 5.4 helpers

const std = @import("std");

// --- Lua 5.4 types ---
pub const struct_lua_State = opaque {};
pub const lua_State = struct_lua_State;

// --- C library externs ---
pub const struct_FILE = opaque {};
pub const FILE = struct_FILE;
pub extern var stderr: ?*FILE;
pub extern fn fputs([*c]const u8, ?*FILE) c_int;
pub extern fn fputc(c_int, ?*FILE) c_int;
pub extern fn free(?*anyopaque) void;

// --- Peer function externs ---
pub extern fn LuaFormatStack(?*lua_State) [*c]u8;

// --- Exported function ---
pub export fn LuaPrintStack(L: ?*lua_State) void {
    const s: [*c]u8 = LuaFormatStack(L);
    _ = fputs(s, stderr);
    _ = fputc('\n', stderr);
    free(@ptrCast(s));
}

