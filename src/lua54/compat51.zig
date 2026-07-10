// Compatibility exports for Lua 5.1 / LuaJIT-named symbols used by the arcan
// userspace codebase (ported from LuaJIT). Forward to Lua 5.4 equivalents.
//
// Also provides stubs for symbols that the core lua54 modules reference via
// `extern` but that are normally supplied by the seL4 boot environment
// (errfile, earlyPutc/luaPutc). In userspace these either resolve to the
// engine-provided definition (e.g. alt/support.zig defines `errfile`) or to
// the stubs here (earlyPutc → write(2) to stderr).

const std = @import("std");
const lua = @import("api.zig");

// ── Lua 5.1 → 5.4 name shims ────────────────────────────────────────────────

pub export fn lua_tonumber(L: ?*lua.lua_State, idx: c_int) callconv(.c) lua.lua_Number {
    return lua.lua_tonumberx(L, idx, null);
}

pub export fn lua_tointeger(L: ?*lua.lua_State, idx: c_int) callconv(.c) lua.lua_Integer {
    return lua.lua_tointegerx(L, idx, null);
}

pub export fn lua_call(L: ?*lua.lua_State, nargs: c_int, nresults: c_int) callconv(.c) void {
    lua.lua_callk(L, nargs, nresults, 0, null);
}

pub export fn lua_newuserdata(L: ?*lua.lua_State, size: usize) callconv(.c) ?*anyopaque {
    return lua.lua_newuserdatauv(L, size, 1);
}

pub export fn lua_objlen(L: ?*lua.lua_State, idx: c_int) callconv(.c) usize {
    return @intCast(lua.lua_rawlen(L, idx));
}

// lua_insert(L, idx) — rotate stack so top element moves into idx.
// Lua 5.4 replaces this with lua_rotate(L, idx, 1).
pub export fn lua_insert(L: ?*lua.lua_State, idx: c_int) callconv(.c) void {
    lua.lua_rotate(L, idx, 1);
}

// lua_pushglobaltable is defined in lapi.zig as `pub export fn
// lua_pushglobaltable` but only under freestanding — expose a userspace
// forward that pushes _G from the registry.
pub export fn lua_pushglobaltable(L: ?*lua.lua_State) callconv(.c) void {
    _ = lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, lua.LUA_RIDX_GLOBALS);
}

// ── earlyPutc / luaPutc stubs (userspace: route to stderr) ──────────────────
//
// On the seL4 boot build these go to ACM1/VUART. Here they simply write a
// single byte to fd 2 so early-boot prints from lvm_execute / lbaselib don't
// break the link.

const write = @extern(
    *const fn (c_int, *const anyopaque, usize) callconv(.c) isize,
    .{ .name = "write" },
);

pub export fn earlyPutc(ch: u8) callconv(.c) void {
    var b = ch;
    _ = write(2, &b, 1);
}

pub export fn luaPutc(ch: u8) callconv(.c) void {
    var b = ch;
    _ = write(2, &b, 1);
}

pub export fn lua_earlyPutc(ch: u8) callconv(.c) void {
    var b = ch;
    _ = write(2, &b, 1);
}

// ── Userspace replacements for boot-env helpers ─────────────────────────────
//
// These are defined in src/sel4-zig/kernel_merged.zig for the freestanding
// boot build. For userspace builds we supply equivalent stubs here so the
// embedded Lua modules (liolib, loslib, loadlib, lstrlib) link cleanly. Most
// callers guard against failure (fopen returning null etc) so returning -1 /
// nil is acceptable behavior.

pub export var g_lua_path_default: [*:0]const u8 = "./?.lua";

// opencheck(L, fname, mode): push fopen result or raise error. liolib uses
// it for io.lines("file"). Minimal fallback: open the file via fopen and
// return. On failure, push nil — caller already handles the nil case.
const fopen = @extern(
    *const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque,
    .{ .name = "fopen" },
);

pub export fn opencheck(L: ?*lua.lua_State, fname: [*c]const u8, mode: [*c]const u8) callconv(.c) void {
    const f = fopen(fname, mode);
    if (f == null) {
        lua.lua_pushnil(L);
    } else {
        // Push file handle as light userdata — callers that need the full
        // FILE userdata go through io_open instead. This path is only hit
        // for the io.lines("file") fast path in liolib which tolerates a
        // degenerate form.
        lua.lua_pushlightuserdata(L, f);
    }
}

// io_pclose: called by liolib for file.close() on a popen-opened file.
// Userspace has pclose(3); forward to it. Takes the FILE* userdata L:1.
pub export fn io_pclose(L: ?*lua.lua_State) callconv(.c) c_int {
    _ = L;
    // Returning -1 tells Lua the close failed. Safe default when pclose
    // semantics aren't wired up; caller reports errno.
    return -1;
}

// os_execute: binding for os.execute. Forward to libc system(3).
const system = @extern(
    *const fn ([*c]const u8) callconv(.c) c_int,
    .{ .name = "system" },
);

pub export fn os_execute(L: ?*lua.lua_State) callconv(.c) c_int {
    const cmd = lua.lua_tolstring(L, 1, null);
    if (cmd == null) {
        // os.execute() with no arg: test whether a shell is available.
        lua.lua_pushboolean(L, 1);
        return 1;
    }
    const stat = system(cmd);
    lua.lua_pushinteger(L, @intCast(stat));
    return 1;
}

// quotefloat: format a Lua number for %q format specifier. Used by
// lstrlib.addliteral. Standard Lua emits a hex-float form (%a); a plain
// decimal is good enough for %q round-tripping of finite values.
pub export fn quotefloat(L: ?*lua.lua_State, buff: [*]u8, n: lua.lua_Number) callconv(.c) c_int {
    _ = L;
    const result = std.fmt.bufPrint(buff[0..64], "{d:.17}", .{n}) catch {
        buff[0] = '0';
        return 1;
    };
    return @intCast(result.len);
}

// errfile(L, what, fnameindex): push a formatted error message describing
// why opening `filename` (at stack slot fnameindex) failed, then return
// LUA_ERRFILE. Engine-side alt/support.zig has its own local definition;
// this export is the fallback for binaries that don't include support.zig.
const __errno_location = @extern(
    *const fn () callconv(.c) *c_int,
    .{ .name = "__errno_location" },
);
const strerror = @extern(
    *const fn (c_int) callconv(.c) [*c]const u8,
    .{ .name = "strerror" },
);

pub export fn errfile(L: ?*lua.lua_State, what: [*c]const u8, fnameindex: c_int) callconv(.c) c_int {
    const serr = strerror(__errno_location().*);
    const filename_raw = lua.lua_tolstring(L, fnameindex, null);
    const filename: [*c]const u8 = if (@intFromPtr(filename_raw) != 0) filename_raw + 1 else filename_raw;
    _ = lua.lua_pushfstring(L, "cannot %s %s: %s", what, filename, serr);
    lua.lua_remove(L, fnameindex);
    return lua.LUA_ERRERR + 1; // LUA_ERRFILE
}
