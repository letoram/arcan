// Pure-Zig port of engine/alt/support.h tbldynstr / tblbool helpers.
// Upstream defines these as static inline `set_tbl*` + `#define` macros that
// compute `sizeof(key)-1` at compile time. dir_lua_appl.zig declares them as
// `extern "c" fn tbldynstr/tblbool(L, key, val, top)` — same surface, but
// runtime strlen on the key (the only caller builds keys as literals and
// strlen on a literal is ~free in practice).

const std = @import("std");

const lua_State = opaque {};
extern "c" fn lua_pushlstring(L: *lua_State, s: [*]const u8, sz: usize) [*:0]const u8;
extern "c" fn lua_pushstring(L: *lua_State, s: [*:0]const u8) [*:0]const u8;
extern "c" fn lua_pushboolean(L: *lua_State, b: c_int) void;
extern "c" fn lua_rawset(L: *lua_State, idx: c_int) void;

pub export fn tbldynstr(
    L: ?*lua_State,
    key: [*:0]const u8,
    val: [*:0]const u8,
    top: c_int,
) callconv(.c) void {
    const state = L orelse return;
    const key_sz = std.mem.len(key);
    _ = lua_pushlstring(state, key, key_sz);
    _ = lua_pushstring(state, val);
    lua_rawset(state, top);
}

pub export fn tblbool(
    L: ?*lua_State,
    key: [*:0]const u8,
    val: bool,
    top: c_int,
) callconv(.c) void {
    const state = L orelse return;
    const key_sz = std.mem.len(key);
    _ = lua_pushlstring(state, key, key_sz);
    lua_pushboolean(state, @intFromBool(val));
    lua_rawset(state, top);
}
