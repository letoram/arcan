// xkbcommon runtime-dlopen shim. See dl_drm.zig for the pattern rationale.
//
// Covers the 11 xkbcommon symbols referenced by src/platform/evdev/event.zig
// (and, transitively, the compositor). All struct arguments are passed by
// pointer, so `?*anyopaque` suffices for register-level ABI match — the
// callers still @cImport / extern "c" the real headers for type info.

const std = @import("std");
const dl = @import("dlopen");

var handle: ?*anyopaque = null;
var init_done: bool = false;

fn ensureLoaded() void {
    if (init_done) return;
    init_done = true;
    handle = dl.zig_dlopen("libxkbcommon.so.0", 1);
}

fn sym(comptime name: [:0]const u8) ?*anyopaque {
    ensureLoaded();
    if (handle == null) return null;
    return dl.zig_dlsym(handle, name.ptr);
}

inline fn resolve(comptime T: type, slot: *?T, comptime name: [:0]const u8) ?T {
    if (slot.*) |f| return f;
    const s = sym(name) orelse return null;
    slot.* = @ptrCast(@alignCast(s));
    return slot.*;
}

/// Call a resolved glibc-linked function under the foreign (glibc) TLS
/// context, then restore the musl TLS context on return. Without this
/// switch, any function in the dlopen'd lib that accesses TLS (e.g.
/// glibc's __ctype_b_loc used internally by xkbcommon) dereferences
/// garbage at a musl-layout TLS offset and segfaults. Mirrors the pattern
/// already used in vk_xcb / vk_shdrmgmt / vk_wsi; the resolver path itself
/// switches TLS inside callForeign (zig_dlopen.zig) so zig_dlsym lookups
/// work — but the RETURNED pointer needs to be invoked under the same
/// switch every time we call it.
fn ReturnOf(comptime T: type) type {
    return @typeInfo(@typeInfo(T).pointer.child).@"fn".return_type.?;
}

inline fn fc(
    comptime T: type,
    slot: *?T,
    comptime name: [:0]const u8,
    args: anytype,
    fallback: ReturnOf(T),
) ReturnOf(T) {
    const f = resolve(T, slot, name) orelse return fallback;
    dl.zig_foreign_begin();
    defer dl.zig_foreign_end();
    return @call(.auto, f, args);
}

inline fn fcv(comptime T: type, slot: *?T, comptime name: [:0]const u8, args: anytype) void {
    const f = resolve(T, slot, name) orelse return;
    dl.zig_foreign_begin();
    defer dl.zig_foreign_end();
    _ = @call(.auto, f, args);
}

const FnCtxNew = *const fn (c_int) callconv(.c) ?*anyopaque;
const FnKeymapNewFromNames = *const fn (?*anyopaque, ?*const anyopaque, c_int) callconv(.c) ?*anyopaque;
const FnKeymapGetAsString = *const fn (?*anyopaque, c_int) callconv(.c) ?[*:0]u8;
const FnKeymapKeyRepeats = *const fn (?*anyopaque, u32) callconv(.c) c_int;
const FnKeymapUnref = *const fn (?*anyopaque) callconv(.c) void;
const FnStateNew = *const fn (?*anyopaque) callconv(.c) ?*anyopaque;
const FnStateUnref = *const fn (?*anyopaque) callconv(.c) void;
const FnStateUpdateKey = *const fn (?*anyopaque, u32, c_int) callconv(.c) c_int;
const FnStateSerializeMods = *const fn (?*anyopaque, c_int) callconv(.c) u32;
const FnStateKeyGetConsumedMods = *const fn (?*anyopaque, u32) callconv(.c) u32;
const FnStateKeyGetUtf8 = *const fn (?*anyopaque, u32, [*c]u8, usize) callconv(.c) c_int;
const FnStateKeyGetUtf32 = *const fn (?*anyopaque, u32) callconv(.c) u32;

var p_xkb_context_new: ?FnCtxNew = null;
var p_xkb_keymap_new_from_names: ?FnKeymapNewFromNames = null;
var p_xkb_keymap_get_as_string: ?FnKeymapGetAsString = null;
var p_xkb_keymap_key_repeats: ?FnKeymapKeyRepeats = null;
var p_xkb_keymap_unref: ?FnKeymapUnref = null;
var p_xkb_state_new: ?FnStateNew = null;
var p_xkb_state_unref: ?FnStateUnref = null;
var p_xkb_state_update_key: ?FnStateUpdateKey = null;
var p_xkb_state_serialize_mods: ?FnStateSerializeMods = null;
var p_xkb_state_key_get_consumed_mods: ?FnStateKeyGetConsumedMods = null;
var p_xkb_state_key_get_utf8: ?FnStateKeyGetUtf8 = null;
var p_xkb_state_key_get_utf32: ?FnStateKeyGetUtf32 = null;

pub export fn xkb_context_new(flags: c_int) callconv(.c) ?*anyopaque {
    return fc(FnCtxNew, &p_xkb_context_new, "xkb_context_new", .{flags}, null);
}
pub export fn xkb_keymap_new_from_names(ctx: ?*anyopaque, names: ?*const anyopaque, flags: c_int) callconv(.c) ?*anyopaque {
    return fc(FnKeymapNewFromNames, &p_xkb_keymap_new_from_names, "xkb_keymap_new_from_names", .{ ctx, names, flags }, null);
}
pub export fn xkb_keymap_get_as_string(keymap: ?*anyopaque, format: c_int) callconv(.c) ?[*:0]u8 {
    return fc(FnKeymapGetAsString, &p_xkb_keymap_get_as_string, "xkb_keymap_get_as_string", .{ keymap, format }, null);
}
pub export fn xkb_keymap_key_repeats(keymap: ?*anyopaque, key: u32) callconv(.c) c_int {
    return fc(FnKeymapKeyRepeats, &p_xkb_keymap_key_repeats, "xkb_keymap_key_repeats", .{ keymap, key }, 0);
}
pub export fn xkb_keymap_unref(keymap: ?*anyopaque) callconv(.c) void {
    fcv(FnKeymapUnref, &p_xkb_keymap_unref, "xkb_keymap_unref", .{keymap});
}
pub export fn xkb_state_new(keymap: ?*anyopaque) callconv(.c) ?*anyopaque {
    return fc(FnStateNew, &p_xkb_state_new, "xkb_state_new", .{keymap}, null);
}
pub export fn xkb_state_unref(state: ?*anyopaque) callconv(.c) void {
    fcv(FnStateUnref, &p_xkb_state_unref, "xkb_state_unref", .{state});
}
pub export fn xkb_state_update_key(state: ?*anyopaque, key: u32, dir: c_int) callconv(.c) c_int {
    return fc(FnStateUpdateKey, &p_xkb_state_update_key, "xkb_state_update_key", .{ state, key, dir }, 0);
}
pub export fn xkb_state_serialize_mods(state: ?*anyopaque, components: c_int) callconv(.c) u32 {
    return fc(FnStateSerializeMods, &p_xkb_state_serialize_mods, "xkb_state_serialize_mods", .{ state, components }, 0);
}
pub export fn xkb_state_key_get_consumed_mods(state: ?*anyopaque, key: u32) callconv(.c) u32 {
    return fc(FnStateKeyGetConsumedMods, &p_xkb_state_key_get_consumed_mods, "xkb_state_key_get_consumed_mods", .{ state, key }, 0);
}
pub export fn xkb_state_key_get_utf8(state: ?*anyopaque, key: u32, buf: [*c]u8, size: usize) callconv(.c) c_int {
    return fc(FnStateKeyGetUtf8, &p_xkb_state_key_get_utf8, "xkb_state_key_get_utf8", .{ state, key, buf, size }, 0);
}
pub export fn xkb_state_key_get_utf32(state: ?*anyopaque, key: u32) callconv(.c) u32 {
    return fc(FnStateKeyGetUtf32, &p_xkb_state_key_get_utf32, "xkb_state_key_get_utf32", .{ state, key }, 0);
}
