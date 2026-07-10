// libdrm runtime-dlopen shim.
//
// Exports C-ABI wrappers for every libdrm symbol that arcan references
// (18 entry points across psep_open.zig and vk_gbm_kms.zig). Symbols are
// resolved on first use via zig_dlopen("libdrm.so.2") + zig_dlsym and
// forwarded through the stored function pointer. This lets static-musl
// arcan link without a libdrm .a and load the host's libdrm.so.2 at
// runtime alongside the Vulkan ICD / Mesa, matching the XCB pattern in
// vk_xcb.zig.
//
// All pointer-typed arguments are modelled as ?*anyopaque because the
// callers already got the real struct definitions through their own
// @cImport; register-level ABI compatibility is all we need here.

const std = @import("std");
const dl = @import("dlopen");

var handle: ?*anyopaque = null;
var init_done: bool = false;

fn ensureLoaded() void {
    if (init_done) return;
    init_done = true;
    handle = dl.zig_dlopen("libdrm.so.2", 1);
}

fn sym(comptime name: [:0]const u8) ?*anyopaque {
    ensureLoaded();
    if (handle == null) return null;
    return dl.zig_dlsym(handle, name.ptr);
}

// ── signatures (C ABI) ───────────────────────────────────────────────

const FnIntInt = *const fn (c_int) callconv(.c) c_int;
const FnVoidPtr = *const fn (?*anyopaque) callconv(.c) void;
const FnGetRes = *const fn (c_int) callconv(.c) ?*anyopaque;
const FnGetById = *const fn (c_int, u32) callconv(.c) ?*anyopaque;
const FnPageFlip = *const fn (c_int, u32, u32, u32, ?*anyopaque) callconv(.c) c_int;
const FnAddFB = *const fn (c_int, u32, u32, u8, u8, u32, u32, ?*u32) callconv(.c) c_int;
const FnAddFB2 = *const fn (c_int, u32, u32, u32, *const [4]u32, *const [4]u32, *const [4]u32, *u32, u32) callconv(.c) c_int;
const FnAddFB2WithModifiers = *const fn (c_int, u32, u32, u32, *const [4]u32, *const [4]u32, *const [4]u32, *const [4]u64, *u32, u32) callconv(.c) c_int;
const FnRmFB = *const fn (c_int, u32) callconv(.c) c_int;
const FnSetCrtc = *const fn (c_int, u32, u32, u32, u32, ?*u32, c_int, ?*anyopaque) callconv(.c) c_int;
const FnHandleEvent = *const fn (c_int, ?*anyopaque) callconv(.c) c_int;
const FnPrimeFdToHandle = *const fn (c_int, c_int, ?*u32) callconv(.c) c_int;
const FnObjGetProps = *const fn (c_int, u32, u32) callconv(.c) ?*anyopaque;
const FnConnSetProp = *const fn (c_int, u32, u32, u64) callconv(.c) c_int;

// Function pointer cache. The `?T` nullability lets us check once per call;
// a clean slot means "not yet resolved". First-call cost is one dlsym.
var p_drmSetMaster: ?FnIntInt = null;
var p_drmDropMaster: ?FnIntInt = null;
var p_drmModeGetResources: ?FnGetRes = null;
var p_drmModeFreeResources: ?FnVoidPtr = null;
var p_drmModeGetConnector: ?FnGetById = null;
var p_drmModeFreeConnector: ?FnVoidPtr = null;
var p_drmModeGetEncoder: ?FnGetById = null;
var p_drmModeFreeEncoder: ?FnVoidPtr = null;
var p_drmModeGetCrtc: ?FnGetById = null;
var p_drmModeFreeCrtc: ?FnVoidPtr = null;
var p_drmModeSetCrtc: ?FnSetCrtc = null;
var p_drmModeAddFB: ?FnAddFB = null;
var p_drmModeAddFB2: ?FnAddFB2 = null;
var p_drmModeAddFB2WithModifiers: ?FnAddFB2WithModifiers = null;
var p_drmModeRmFB: ?FnRmFB = null;
var p_drmModePageFlip: ?FnPageFlip = null;
var p_drmHandleEvent: ?FnHandleEvent = null;
var p_drmPrimeFDToHandle: ?FnPrimeFdToHandle = null;
var p_drmModeObjectGetProperties: ?FnObjGetProps = null;
var p_drmModeFreeObjectProperties: ?FnVoidPtr = null;
var p_drmModeGetProperty: ?FnGetById = null;
var p_drmModeFreeProperty: ?FnVoidPtr = null;
var p_drmModeConnectorSetProperty: ?FnConnSetProp = null;

inline fn resolve(comptime T: type, slot: *?T, comptime name: [:0]const u8) ?T {
    if (slot.*) |f| return f;
    const s = sym(name) orelse return null;
    slot.* = @ptrCast(@alignCast(s));
    return slot.*;
}

// TLS-switched call wrappers. libdrm, like xkbcommon and OpenAL, pulls in
// glibc internals that access thread-local state via tpidr_el0. Static-musl
// arcan has its own TLS layout there, so every actual invocation must
// bracket with zig_foreign_begin/end. See dl_xkb.zig for the rationale.
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

// ── exports ──────────────────────────────────────────────────────────

pub export fn drmSetMaster(fd: c_int) callconv(.c) c_int {
    return fc(FnIntInt, &p_drmSetMaster, "drmSetMaster", .{fd}, -1);
}
pub export fn drmDropMaster(fd: c_int) callconv(.c) c_int {
    return fc(FnIntInt, &p_drmDropMaster, "drmDropMaster", .{fd}, -1);
}
pub export fn drmModeGetResources(fd: c_int) callconv(.c) ?*anyopaque {
    return fc(FnGetRes, &p_drmModeGetResources, "drmModeGetResources", .{fd}, null);
}
pub export fn drmModeFreeResources(ptr: ?*anyopaque) callconv(.c) void {
    fcv(FnVoidPtr, &p_drmModeFreeResources, "drmModeFreeResources", .{ptr});
}
pub export fn drmModeGetConnector(fd: c_int, id: u32) callconv(.c) ?*anyopaque {
    return fc(FnGetById, &p_drmModeGetConnector, "drmModeGetConnector", .{ fd, id }, null);
}
pub export fn drmModeFreeConnector(ptr: ?*anyopaque) callconv(.c) void {
    fcv(FnVoidPtr, &p_drmModeFreeConnector, "drmModeFreeConnector", .{ptr});
}
pub export fn drmModeGetEncoder(fd: c_int, id: u32) callconv(.c) ?*anyopaque {
    return fc(FnGetById, &p_drmModeGetEncoder, "drmModeGetEncoder", .{ fd, id }, null);
}
pub export fn drmModeFreeEncoder(ptr: ?*anyopaque) callconv(.c) void {
    fcv(FnVoidPtr, &p_drmModeFreeEncoder, "drmModeFreeEncoder", .{ptr});
}
pub export fn drmModeGetCrtc(fd: c_int, id: u32) callconv(.c) ?*anyopaque {
    return fc(FnGetById, &p_drmModeGetCrtc, "drmModeGetCrtc", .{ fd, id }, null);
}
pub export fn drmModeFreeCrtc(ptr: ?*anyopaque) callconv(.c) void {
    fcv(FnVoidPtr, &p_drmModeFreeCrtc, "drmModeFreeCrtc", .{ptr});
}
pub export fn drmModeSetCrtc(fd: c_int, crtc_id: u32, buffer_id: u32, x: u32, y: u32, connectors: ?*u32, count: c_int, mode: ?*anyopaque) callconv(.c) c_int {
    return fc(FnSetCrtc, &p_drmModeSetCrtc, "drmModeSetCrtc", .{ fd, crtc_id, buffer_id, x, y, connectors, count, mode }, -1);
}
pub export fn drmModeAddFB(fd: c_int, w: u32, h: u32, depth: u8, bpp: u8, pitch: u32, bo_handle: u32, buf_id: ?*u32) callconv(.c) c_int {
    return fc(FnAddFB, &p_drmModeAddFB, "drmModeAddFB", .{ fd, w, h, depth, bpp, pitch, bo_handle, buf_id }, -1);
}
pub export fn drmModeAddFB2(fd: c_int, w: u32, h: u32, pixel_format: u32, bo_handles: *const [4]u32, pitches: *const [4]u32, offsets: *const [4]u32, buf_id: *u32, flags: u32) callconv(.c) c_int {
    return fc(FnAddFB2, &p_drmModeAddFB2, "drmModeAddFB2", .{ fd, w, h, pixel_format, bo_handles, pitches, offsets, buf_id, flags }, -1);
}
pub export fn drmModeAddFB2WithModifiers(fd: c_int, w: u32, h: u32, pixel_format: u32, bo_handles: *const [4]u32, pitches: *const [4]u32, offsets: *const [4]u32, modifier: *const [4]u64, buf_id: *u32, flags: u32) callconv(.c) c_int {
    return fc(FnAddFB2WithModifiers, &p_drmModeAddFB2WithModifiers, "drmModeAddFB2WithModifiers", .{ fd, w, h, pixel_format, bo_handles, pitches, offsets, modifier, buf_id, flags }, -1);
}
pub export fn drmModeRmFB(fd: c_int, buffer_id: u32) callconv(.c) c_int {
    return fc(FnRmFB, &p_drmModeRmFB, "drmModeRmFB", .{ fd, buffer_id }, -1);
}
pub export fn drmModePageFlip(fd: c_int, crtc_id: u32, fb_id: u32, flags: u32, user_data: ?*anyopaque) callconv(.c) c_int {
    return fc(FnPageFlip, &p_drmModePageFlip, "drmModePageFlip", .{ fd, crtc_id, fb_id, flags, user_data }, -1);
}
pub export fn drmHandleEvent(fd: c_int, evctx: ?*anyopaque) callconv(.c) c_int {
    return fc(FnHandleEvent, &p_drmHandleEvent, "drmHandleEvent", .{ fd, evctx }, -1);
}
pub export fn drmPrimeFDToHandle(fd: c_int, prime_fd: c_int, handle_out: ?*u32) callconv(.c) c_int {
    return fc(FnPrimeFdToHandle, &p_drmPrimeFDToHandle, "drmPrimeFDToHandle", .{ fd, prime_fd, handle_out }, -1);
}
pub export fn drmModeObjectGetProperties(fd: c_int, object_id: u32, object_type: u32) callconv(.c) ?*anyopaque {
    return fc(FnObjGetProps, &p_drmModeObjectGetProperties, "drmModeObjectGetProperties", .{ fd, object_id, object_type }, null);
}
pub export fn drmModeFreeObjectProperties(ptr: ?*anyopaque) callconv(.c) void {
    fcv(FnVoidPtr, &p_drmModeFreeObjectProperties, "drmModeFreeObjectProperties", .{ptr});
}
pub export fn drmModeGetProperty(fd: c_int, prop_id: u32) callconv(.c) ?*anyopaque {
    return fc(FnGetById, &p_drmModeGetProperty, "drmModeGetProperty", .{ fd, prop_id }, null);
}
pub export fn drmModeFreeProperty(ptr: ?*anyopaque) callconv(.c) void {
    fcv(FnVoidPtr, &p_drmModeFreeProperty, "drmModeFreeProperty", .{ptr});
}
pub export fn drmModeConnectorSetProperty(fd: c_int, connector_id: u32, property_id: u32, value: u64) callconv(.c) c_int {
    return fc(FnConnSetProp, &p_drmModeConnectorSetProperty, "drmModeConnectorSetProperty", .{ fd, connector_id, property_id, value }, -1);
}
