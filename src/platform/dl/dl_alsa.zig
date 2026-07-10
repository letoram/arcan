// ALSA runtime-dlopen shim. See dl_drm.zig / dl_openal.zig for the pattern rationale.
//
// Covers the 67 ALSA snd_* functions used by miniaudio's ALSA backend.
// Type aliases: ma_snd_pcm_t (opaque), ma_snd_pcm_hw_params_t (opaque),
// ma_snd_pcm_sw_params_t (opaque), ma_snd_pcm_format_mask_t (opaque),
// ma_snd_pcm_info_t (opaque), ma_snd_pcm_channel_area_t (struct),
// ma_snd_pcm_chmap_t (struct), struct_pollfd (libc struct).
// Integer types: c_int, c_uint, c_ulong, c_long, c_ushort, etc.

const std = @import("std");
const dl = @import("dlopen");

// Type aliases used in proc signatures
pub const ma_snd_pcm_uframes_t = c_ulong;
pub const ma_snd_pcm_sframes_t = c_long;
pub const ma_snd_pcm_stream_t = c_int;
pub const ma_snd_pcm_format_t = c_int;
pub const ma_snd_pcm_access_t = c_int;
pub const ma_snd_pcm_state_t = c_int;
pub const struct_ma_snd_pcm_t = opaque {};
pub const ma_snd_pcm_t = struct_ma_snd_pcm_t;
pub const struct_ma_snd_pcm_hw_params_t = opaque {};
pub const ma_snd_pcm_hw_params_t = struct_ma_snd_pcm_hw_params_t;
pub const struct_ma_snd_pcm_sw_params_t = opaque {};
pub const ma_snd_pcm_sw_params_t = struct_ma_snd_pcm_sw_params_t;
pub const struct_ma_snd_pcm_format_mask_t = opaque {};
pub const ma_snd_pcm_format_mask_t = struct_ma_snd_pcm_format_mask_t;
pub const struct_ma_snd_pcm_info_t = opaque {};
pub const ma_snd_pcm_info_t = struct_ma_snd_pcm_info_t;
pub const ma_snd_pcm_channel_area_t = extern struct {
    addr: ?*anyopaque = std.mem.zeroes(?*anyopaque),
    first: c_uint = std.mem.zeroes(c_uint),
    step: c_uint = std.mem.zeroes(c_uint),
};
pub const ma_snd_pcm_chmap_t = extern struct {
    channels: c_uint = std.mem.zeroes(c_uint),
    pos: [1]c_uint = std.mem.zeroes([1]c_uint),
};
pub const struct_pollfd = extern struct {
    fd: c_int = 0,
    events: c_short = 0,
    revents: c_short = 0,
};

var handle: ?*anyopaque = null;
var init_done: bool = false;

fn ensureLoaded() void {
    if (init_done) return;
    init_done = true;
    // Try soname first; fall back to unversioned (some distros ship only .so)
    handle = dl.zig_dlopen("libasound.so.2", 1) orelse
        dl.zig_dlopen("libasound.so", 1);
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

// TLS-switched call wrappers. Matches the dl_xkb / dl_drm pattern: the
// resolve path goes through zig_dlsym (already TLS-switched by
// callForeign), but the actual invocation of the returned pointer needs
// its own bracket so any glibc-TLS read inside ALSA lands on the right layout.
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

// ── ALSA PCM / HW Params / SW Params ─────────────────────────────────

const Fn_snd_pcm_open = *const fn ([*c]?*ma_snd_pcm_t, [*c]const u8, ma_snd_pcm_stream_t, c_int) callconv(.c) c_int;
const Fn_snd_pcm_close = *const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_sizeof = *const fn () callconv(.c) usize;
const Fn_snd_pcm_hw_params_any = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_format = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, ma_snd_pcm_format_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_format_first = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_format_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_format_mask = *const fn (?*ma_snd_pcm_hw_params_t, ?*ma_snd_pcm_format_mask_t) callconv(.c) void;
const Fn_snd_pcm_hw_params_set_channels = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_channels_near = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_channels_minmax = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_uint) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_rate_resample = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_rate = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint, c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_rate_near = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_rate_minmax = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_buffer_size_near = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_periods_near = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_set_access = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, ma_snd_pcm_access_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_format = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_format_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_channels = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_channels_min = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_channels_max = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_rate = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_rate_min = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_rate_max = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_buffer_size = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_periods = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_get_access = *const fn (?*const ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_access_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_test_format = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, ma_snd_pcm_format_t) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_test_channels = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint) callconv(.c) c_int;
const Fn_snd_pcm_hw_params_test_rate = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint, c_int) callconv(.c) c_int;
const Fn_snd_pcm_hw_params = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t) callconv(.c) c_int;
const Fn_snd_pcm_sw_params_sizeof = *const fn () callconv(.c) usize;
const Fn_snd_pcm_sw_params_current = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t) callconv(.c) c_int;
const Fn_snd_pcm_sw_params_get_boundary = *const fn (?*const ma_snd_pcm_sw_params_t, [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int;
const Fn_snd_pcm_sw_params_set_avail_min = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t, ma_snd_pcm_uframes_t) callconv(.c) c_int;
const Fn_snd_pcm_sw_params_set_start_threshold = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t, ma_snd_pcm_uframes_t) callconv(.c) c_int;
const Fn_snd_pcm_sw_params_set_stop_threshold = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t, ma_snd_pcm_uframes_t) callconv(.c) c_int;
const Fn_snd_pcm_sw_params = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t) callconv(.c) c_int;
const Fn_snd_pcm_format_mask_sizeof = *const fn () callconv(.c) usize;
const Fn_snd_pcm_format_mask_test = *const fn (?*const ma_snd_pcm_format_mask_t, ma_snd_pcm_format_t) callconv(.c) c_int;
const Fn_snd_pcm_get_chmap = *const fn (?*ma_snd_pcm_t) callconv(.c) [*c]ma_snd_pcm_chmap_t;
const Fn_snd_pcm_state = *const fn (?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_state_t;
const Fn_snd_pcm_prepare = *const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
const Fn_snd_pcm_start = *const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
const Fn_snd_pcm_drop = *const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
const Fn_snd_pcm_drain = *const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
const Fn_snd_pcm_reset = *const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
const Fn_snd_device_name_hint = *const fn (c_int, [*c]const u8, [*c][*c]?*anyopaque) callconv(.c) c_int;
const Fn_snd_device_name_get_hint = *const fn (?*const anyopaque, [*c]const u8) callconv(.c) [*c]u8;
const Fn_snd_card_get_index = *const fn ([*c]const u8) callconv(.c) c_int;
const Fn_snd_device_name_free_hint = *const fn ([*c]?*anyopaque) callconv(.c) c_int;
const Fn_snd_pcm_mmap_begin = *const fn (?*ma_snd_pcm_t, [*c][*c]const ma_snd_pcm_channel_area_t, [*c]ma_snd_pcm_uframes_t, [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int;
const Fn_snd_pcm_mmap_commit = *const fn (?*ma_snd_pcm_t, ma_snd_pcm_uframes_t, ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t;
const Fn_snd_pcm_recover = *const fn (?*ma_snd_pcm_t, c_int, c_int) callconv(.c) c_int;
const Fn_snd_pcm_readi = *const fn (?*ma_snd_pcm_t, ?*anyopaque, ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t;
const Fn_snd_pcm_writei = *const fn (?*ma_snd_pcm_t, ?*const anyopaque, ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t;
const Fn_snd_pcm_avail = *const fn (?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_sframes_t;
const Fn_snd_pcm_avail_update = *const fn (?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_sframes_t;
const Fn_snd_pcm_wait = *const fn (?*ma_snd_pcm_t, c_int) callconv(.c) c_int;
const Fn_snd_pcm_nonblock = *const fn (?*ma_snd_pcm_t, c_int) callconv(.c) c_int;
const Fn_snd_pcm_info = *const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_info_t) callconv(.c) c_int;
const Fn_snd_pcm_info_sizeof = *const fn () callconv(.c) usize;
const Fn_snd_pcm_info_get_name = *const fn (?*const ma_snd_pcm_info_t) callconv(.c) [*c]const u8;
const Fn_snd_pcm_poll_descriptors = *const fn (?*ma_snd_pcm_t, [*c]struct_pollfd, c_uint) callconv(.c) c_int;
const Fn_snd_pcm_poll_descriptors_count = *const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
const Fn_snd_pcm_poll_descriptors_revents = *const fn (?*ma_snd_pcm_t, [*c]struct_pollfd, c_uint, [*c]c_ushort) callconv(.c) c_int;
const Fn_snd_config_update_free_global = *const fn () callconv(.c) c_int;
const Fn_snd_pcm_set_params = *const fn (?*ma_snd_pcm_t, ma_snd_pcm_format_t, c_int, c_uint, c_uint, c_int, c_uint) callconv(.c) c_int;

var p_snd_pcm_open: ?Fn_snd_pcm_open = null;
var p_snd_pcm_close: ?Fn_snd_pcm_close = null;
var p_snd_pcm_hw_params_sizeof: ?Fn_snd_pcm_hw_params_sizeof = null;
var p_snd_pcm_hw_params_any: ?Fn_snd_pcm_hw_params_any = null;
var p_snd_pcm_hw_params_set_format: ?Fn_snd_pcm_hw_params_set_format = null;
var p_snd_pcm_hw_params_set_format_first: ?Fn_snd_pcm_hw_params_set_format_first = null;
var p_snd_pcm_hw_params_get_format_mask: ?Fn_snd_pcm_hw_params_get_format_mask = null;
var p_snd_pcm_hw_params_set_channels: ?Fn_snd_pcm_hw_params_set_channels = null;
var p_snd_pcm_hw_params_set_channels_near: ?Fn_snd_pcm_hw_params_set_channels_near = null;
var p_snd_pcm_hw_params_set_channels_minmax: ?Fn_snd_pcm_hw_params_set_channels_minmax = null;
var p_snd_pcm_hw_params_set_rate_resample: ?Fn_snd_pcm_hw_params_set_rate_resample = null;
var p_snd_pcm_hw_params_set_rate: ?Fn_snd_pcm_hw_params_set_rate = null;
var p_snd_pcm_hw_params_set_rate_near: ?Fn_snd_pcm_hw_params_set_rate_near = null;
var p_snd_pcm_hw_params_set_rate_minmax: ?Fn_snd_pcm_hw_params_set_rate_minmax = null;
var p_snd_pcm_hw_params_set_buffer_size_near: ?Fn_snd_pcm_hw_params_set_buffer_size_near = null;
var p_snd_pcm_hw_params_set_periods_near: ?Fn_snd_pcm_hw_params_set_periods_near = null;
var p_snd_pcm_hw_params_set_access: ?Fn_snd_pcm_hw_params_set_access = null;
var p_snd_pcm_hw_params_get_format: ?Fn_snd_pcm_hw_params_get_format = null;
var p_snd_pcm_hw_params_get_channels: ?Fn_snd_pcm_hw_params_get_channels = null;
var p_snd_pcm_hw_params_get_channels_min: ?Fn_snd_pcm_hw_params_get_channels_min = null;
var p_snd_pcm_hw_params_get_channels_max: ?Fn_snd_pcm_hw_params_get_channels_max = null;
var p_snd_pcm_hw_params_get_rate: ?Fn_snd_pcm_hw_params_get_rate = null;
var p_snd_pcm_hw_params_get_rate_min: ?Fn_snd_pcm_hw_params_get_rate_min = null;
var p_snd_pcm_hw_params_get_rate_max: ?Fn_snd_pcm_hw_params_get_rate_max = null;
var p_snd_pcm_hw_params_get_buffer_size: ?Fn_snd_pcm_hw_params_get_buffer_size = null;
var p_snd_pcm_hw_params_get_periods: ?Fn_snd_pcm_hw_params_get_periods = null;
var p_snd_pcm_hw_params_get_access: ?Fn_snd_pcm_hw_params_get_access = null;
var p_snd_pcm_hw_params_test_format: ?Fn_snd_pcm_hw_params_test_format = null;
var p_snd_pcm_hw_params_test_channels: ?Fn_snd_pcm_hw_params_test_channels = null;
var p_snd_pcm_hw_params_test_rate: ?Fn_snd_pcm_hw_params_test_rate = null;
var p_snd_pcm_hw_params: ?Fn_snd_pcm_hw_params = null;
var p_snd_pcm_sw_params_sizeof: ?Fn_snd_pcm_sw_params_sizeof = null;
var p_snd_pcm_sw_params_current: ?Fn_snd_pcm_sw_params_current = null;
var p_snd_pcm_sw_params_get_boundary: ?Fn_snd_pcm_sw_params_get_boundary = null;
var p_snd_pcm_sw_params_set_avail_min: ?Fn_snd_pcm_sw_params_set_avail_min = null;
var p_snd_pcm_sw_params_set_start_threshold: ?Fn_snd_pcm_sw_params_set_start_threshold = null;
var p_snd_pcm_sw_params_set_stop_threshold: ?Fn_snd_pcm_sw_params_set_stop_threshold = null;
var p_snd_pcm_sw_params: ?Fn_snd_pcm_sw_params = null;
var p_snd_pcm_format_mask_sizeof: ?Fn_snd_pcm_format_mask_sizeof = null;
var p_snd_pcm_format_mask_test: ?Fn_snd_pcm_format_mask_test = null;
var p_snd_pcm_get_chmap: ?Fn_snd_pcm_get_chmap = null;
var p_snd_pcm_state: ?Fn_snd_pcm_state = null;
var p_snd_pcm_prepare: ?Fn_snd_pcm_prepare = null;
var p_snd_pcm_start: ?Fn_snd_pcm_start = null;
var p_snd_pcm_drop: ?Fn_snd_pcm_drop = null;
var p_snd_pcm_drain: ?Fn_snd_pcm_drain = null;
var p_snd_pcm_reset: ?Fn_snd_pcm_reset = null;
var p_snd_device_name_hint: ?Fn_snd_device_name_hint = null;
var p_snd_device_name_get_hint: ?Fn_snd_device_name_get_hint = null;
var p_snd_card_get_index: ?Fn_snd_card_get_index = null;
var p_snd_device_name_free_hint: ?Fn_snd_device_name_free_hint = null;
var p_snd_pcm_mmap_begin: ?Fn_snd_pcm_mmap_begin = null;
var p_snd_pcm_mmap_commit: ?Fn_snd_pcm_mmap_commit = null;
var p_snd_pcm_recover: ?Fn_snd_pcm_recover = null;
var p_snd_pcm_readi: ?Fn_snd_pcm_readi = null;
var p_snd_pcm_writei: ?Fn_snd_pcm_writei = null;
var p_snd_pcm_avail: ?Fn_snd_pcm_avail = null;
var p_snd_pcm_avail_update: ?Fn_snd_pcm_avail_update = null;
var p_snd_pcm_wait: ?Fn_snd_pcm_wait = null;
var p_snd_pcm_nonblock: ?Fn_snd_pcm_nonblock = null;
var p_snd_pcm_info: ?Fn_snd_pcm_info = null;
var p_snd_pcm_info_sizeof: ?Fn_snd_pcm_info_sizeof = null;
var p_snd_pcm_info_get_name: ?Fn_snd_pcm_info_get_name = null;
var p_snd_pcm_poll_descriptors: ?Fn_snd_pcm_poll_descriptors = null;
var p_snd_pcm_poll_descriptors_count: ?Fn_snd_pcm_poll_descriptors_count = null;
var p_snd_pcm_poll_descriptors_revents: ?Fn_snd_pcm_poll_descriptors_revents = null;
var p_snd_config_update_free_global: ?Fn_snd_config_update_free_global = null;
var p_snd_pcm_set_params: ?Fn_snd_pcm_set_params = null;

pub export fn snd_pcm_open(pcmp: [*c]?*ma_snd_pcm_t, name: [*c]const u8, stream: ma_snd_pcm_stream_t, mode: c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_open, &p_snd_pcm_open, "snd_pcm_open", .{ pcmp, name, stream, mode }, -1);
}
pub export fn snd_pcm_close(pcm: ?*ma_snd_pcm_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_close, &p_snd_pcm_close, "snd_pcm_close", .{pcm}, -1);
}
pub export fn snd_pcm_hw_params_sizeof() callconv(.c) usize {
    return fc(Fn_snd_pcm_hw_params_sizeof, &p_snd_pcm_hw_params_sizeof, "snd_pcm_hw_params_sizeof", .{}, 0);
}
pub export fn snd_pcm_hw_params_any(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_any, &p_snd_pcm_hw_params_any, "snd_pcm_hw_params_any", .{ pcm, params }, -1);
}
pub export fn snd_pcm_hw_params_set_format(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, fmt: ma_snd_pcm_format_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_format, &p_snd_pcm_hw_params_set_format, "snd_pcm_hw_params_set_format", .{ pcm, params, fmt }, -1);
}
pub export fn snd_pcm_hw_params_set_format_first(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, fmt: [*c]ma_snd_pcm_format_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_format_first, &p_snd_pcm_hw_params_set_format_first, "snd_pcm_hw_params_set_format_first", .{ pcm, params, fmt }, -1);
}
pub export fn snd_pcm_hw_params_get_format_mask(params: ?*ma_snd_pcm_hw_params_t, mask: ?*ma_snd_pcm_format_mask_t) callconv(.c) void {
    fcv(Fn_snd_pcm_hw_params_get_format_mask, &p_snd_pcm_hw_params_get_format_mask, "snd_pcm_hw_params_get_format_mask", .{ params, mask });
}
pub export fn snd_pcm_hw_params_set_channels(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, channels: c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_channels, &p_snd_pcm_hw_params_set_channels, "snd_pcm_hw_params_set_channels", .{ pcm, params, channels }, -1);
}
pub export fn snd_pcm_hw_params_set_channels_near(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, val: [*c]c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_channels_near, &p_snd_pcm_hw_params_set_channels_near, "snd_pcm_hw_params_set_channels_near", .{ pcm, params, val }, -1);
}
pub export fn snd_pcm_hw_params_set_channels_minmax(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, min: [*c]c_uint, max: [*c]c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_channels_minmax, &p_snd_pcm_hw_params_set_channels_minmax, "snd_pcm_hw_params_set_channels_minmax", .{ pcm, params, min, max }, -1);
}
pub export fn snd_pcm_hw_params_set_rate_resample(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, val: c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_rate_resample, &p_snd_pcm_hw_params_set_rate_resample, "snd_pcm_hw_params_set_rate_resample", .{ pcm, params, val }, -1);
}
pub export fn snd_pcm_hw_params_set_rate(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, val: c_uint, dir: c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_rate, &p_snd_pcm_hw_params_set_rate, "snd_pcm_hw_params_set_rate", .{ pcm, params, val, dir }, -1);
}
pub export fn snd_pcm_hw_params_set_rate_near(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, val: [*c]c_uint, dir: [*c]c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_rate_near, &p_snd_pcm_hw_params_set_rate_near, "snd_pcm_hw_params_set_rate_near", .{ pcm, params, val, dir }, -1);
}
pub export fn snd_pcm_hw_params_set_rate_minmax(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, minval: [*c]c_uint, mindir: [*c]c_int, maxval: [*c]c_uint, maxdir: [*c]c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_rate_minmax, &p_snd_pcm_hw_params_set_rate_minmax, "snd_pcm_hw_params_set_rate_minmax", .{ pcm, params, minval, mindir, maxval, maxdir }, -1);
}
pub export fn snd_pcm_hw_params_set_buffer_size_near(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, val: [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_buffer_size_near, &p_snd_pcm_hw_params_set_buffer_size_near, "snd_pcm_hw_params_set_buffer_size_near", .{ pcm, params, val }, -1);
}
pub export fn snd_pcm_hw_params_set_periods_near(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, val: [*c]c_uint, dir: [*c]c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_periods_near, &p_snd_pcm_hw_params_set_periods_near, "snd_pcm_hw_params_set_periods_near", .{ pcm, params, val, dir }, -1);
}
pub export fn snd_pcm_hw_params_set_access(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, access: ma_snd_pcm_access_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_set_access, &p_snd_pcm_hw_params_set_access, "snd_pcm_hw_params_set_access", .{ pcm, params, access }, -1);
}
pub export fn snd_pcm_hw_params_get_format(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]ma_snd_pcm_format_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_format, &p_snd_pcm_hw_params_get_format, "snd_pcm_hw_params_get_format", .{ params, val }, -1);
}
pub export fn snd_pcm_hw_params_get_channels(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_channels, &p_snd_pcm_hw_params_get_channels, "snd_pcm_hw_params_get_channels", .{ params, val }, -1);
}
pub export fn snd_pcm_hw_params_get_channels_min(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_channels_min, &p_snd_pcm_hw_params_get_channels_min, "snd_pcm_hw_params_get_channels_min", .{ params, val }, -1);
}
pub export fn snd_pcm_hw_params_get_channels_max(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_channels_max, &p_snd_pcm_hw_params_get_channels_max, "snd_pcm_hw_params_get_channels_max", .{ params, val }, -1);
}
pub export fn snd_pcm_hw_params_get_rate(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]c_uint, dir: [*c]c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_rate, &p_snd_pcm_hw_params_get_rate, "snd_pcm_hw_params_get_rate", .{ params, val, dir }, -1);
}
pub export fn snd_pcm_hw_params_get_rate_min(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]c_uint, dir: [*c]c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_rate_min, &p_snd_pcm_hw_params_get_rate_min, "snd_pcm_hw_params_get_rate_min", .{ params, val, dir }, -1);
}
pub export fn snd_pcm_hw_params_get_rate_max(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]c_uint, dir: [*c]c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_rate_max, &p_snd_pcm_hw_params_get_rate_max, "snd_pcm_hw_params_get_rate_max", .{ params, val, dir }, -1);
}
pub export fn snd_pcm_hw_params_get_buffer_size(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_buffer_size, &p_snd_pcm_hw_params_get_buffer_size, "snd_pcm_hw_params_get_buffer_size", .{ params, val }, -1);
}
pub export fn snd_pcm_hw_params_get_periods(params: ?*const ma_snd_pcm_hw_params_t, val: [*c]c_uint, dir: [*c]c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_periods, &p_snd_pcm_hw_params_get_periods, "snd_pcm_hw_params_get_periods", .{ params, val, dir }, -1);
}
pub export fn snd_pcm_hw_params_get_access(params: ?*const ma_snd_pcm_hw_params_t, access: [*c]ma_snd_pcm_access_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_get_access, &p_snd_pcm_hw_params_get_access, "snd_pcm_hw_params_get_access", .{ params, access }, -1);
}
pub export fn snd_pcm_hw_params_test_format(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, fmt: ma_snd_pcm_format_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_test_format, &p_snd_pcm_hw_params_test_format, "snd_pcm_hw_params_test_format", .{ pcm, params, fmt }, -1);
}
pub export fn snd_pcm_hw_params_test_channels(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, channels: c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_test_channels, &p_snd_pcm_hw_params_test_channels, "snd_pcm_hw_params_test_channels", .{ pcm, params, channels }, -1);
}
pub export fn snd_pcm_hw_params_test_rate(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t, val: c_uint, dir: c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params_test_rate, &p_snd_pcm_hw_params_test_rate, "snd_pcm_hw_params_test_rate", .{ pcm, params, val, dir }, -1);
}
pub export fn snd_pcm_hw_params(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_hw_params_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_hw_params, &p_snd_pcm_hw_params, "snd_pcm_hw_params", .{ pcm, params }, -1);
}
pub export fn snd_pcm_sw_params_sizeof() callconv(.c) usize {
    return fc(Fn_snd_pcm_sw_params_sizeof, &p_snd_pcm_sw_params_sizeof, "snd_pcm_sw_params_sizeof", .{}, 0);
}
pub export fn snd_pcm_sw_params_current(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_sw_params_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_sw_params_current, &p_snd_pcm_sw_params_current, "snd_pcm_sw_params_current", .{ pcm, params }, -1);
}
pub export fn snd_pcm_sw_params_get_boundary(params: ?*const ma_snd_pcm_sw_params_t, val: [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_sw_params_get_boundary, &p_snd_pcm_sw_params_get_boundary, "snd_pcm_sw_params_get_boundary", .{ params, val }, -1);
}
pub export fn snd_pcm_sw_params_set_avail_min(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_sw_params_t, val: ma_snd_pcm_uframes_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_sw_params_set_avail_min, &p_snd_pcm_sw_params_set_avail_min, "snd_pcm_sw_params_set_avail_min", .{ pcm, params, val }, -1);
}
pub export fn snd_pcm_sw_params_set_start_threshold(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_sw_params_t, val: ma_snd_pcm_uframes_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_sw_params_set_start_threshold, &p_snd_pcm_sw_params_set_start_threshold, "snd_pcm_sw_params_set_start_threshold", .{ pcm, params, val }, -1);
}
pub export fn snd_pcm_sw_params_set_stop_threshold(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_sw_params_t, val: ma_snd_pcm_uframes_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_sw_params_set_stop_threshold, &p_snd_pcm_sw_params_set_stop_threshold, "snd_pcm_sw_params_set_stop_threshold", .{ pcm, params, val }, -1);
}
pub export fn snd_pcm_sw_params(pcm: ?*ma_snd_pcm_t, params: ?*ma_snd_pcm_sw_params_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_sw_params, &p_snd_pcm_sw_params, "snd_pcm_sw_params", .{ pcm, params }, -1);
}
pub export fn snd_pcm_format_mask_sizeof() callconv(.c) usize {
    return fc(Fn_snd_pcm_format_mask_sizeof, &p_snd_pcm_format_mask_sizeof, "snd_pcm_format_mask_sizeof", .{}, 0);
}
pub export fn snd_pcm_format_mask_test(mask: ?*const ma_snd_pcm_format_mask_t, fmt: ma_snd_pcm_format_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_format_mask_test, &p_snd_pcm_format_mask_test, "snd_pcm_format_mask_test", .{ mask, fmt }, 0);
}
pub export fn snd_pcm_get_chmap(pcm: ?*ma_snd_pcm_t) callconv(.c) [*c]ma_snd_pcm_chmap_t {
    return fc(Fn_snd_pcm_get_chmap, &p_snd_pcm_get_chmap, "snd_pcm_get_chmap", .{pcm}, null);
}
pub export fn snd_pcm_state(pcm: ?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_state_t {
    return fc(Fn_snd_pcm_state, &p_snd_pcm_state, "snd_pcm_state", .{pcm}, 0);
}
pub export fn snd_pcm_prepare(pcm: ?*ma_snd_pcm_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_prepare, &p_snd_pcm_prepare, "snd_pcm_prepare", .{pcm}, -1);
}
pub export fn snd_pcm_start(pcm: ?*ma_snd_pcm_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_start, &p_snd_pcm_start, "snd_pcm_start", .{pcm}, -1);
}
pub export fn snd_pcm_drop(pcm: ?*ma_snd_pcm_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_drop, &p_snd_pcm_drop, "snd_pcm_drop", .{pcm}, -1);
}
pub export fn snd_pcm_drain(pcm: ?*ma_snd_pcm_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_drain, &p_snd_pcm_drain, "snd_pcm_drain", .{pcm}, -1);
}
pub export fn snd_pcm_reset(pcm: ?*ma_snd_pcm_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_reset, &p_snd_pcm_reset, "snd_pcm_reset", .{pcm}, -1);
}
pub export fn snd_device_name_hint(card: c_int, iface: [*c]const u8, hints: [*c][*c]?*anyopaque) callconv(.c) c_int {
    return fc(Fn_snd_device_name_hint, &p_snd_device_name_hint, "snd_device_name_hint", .{ card, iface, hints }, -1);
}
pub export fn snd_device_name_get_hint(hint: ?*const anyopaque, id: [*c]const u8) callconv(.c) [*c]u8 {
    return fc(Fn_snd_device_name_get_hint, &p_snd_device_name_get_hint, "snd_device_name_get_hint", .{ hint, id }, null);
}
pub export fn snd_card_get_index(name: [*c]const u8) callconv(.c) c_int {
    return fc(Fn_snd_card_get_index, &p_snd_card_get_index, "snd_card_get_index", .{name}, -1);
}
pub export fn snd_device_name_free_hint(hints: [*c]?*anyopaque) callconv(.c) c_int {
    return fc(Fn_snd_device_name_free_hint, &p_snd_device_name_free_hint, "snd_device_name_free_hint", .{hints}, 0);
}
pub export fn snd_pcm_mmap_begin(pcm: ?*ma_snd_pcm_t, areas: [*c][*c]const ma_snd_pcm_channel_area_t, offset: [*c]ma_snd_pcm_uframes_t, frames: [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_mmap_begin, &p_snd_pcm_mmap_begin, "snd_pcm_mmap_begin", .{ pcm, areas, offset, frames }, -1);
}
pub export fn snd_pcm_mmap_commit(pcm: ?*ma_snd_pcm_t, offset: ma_snd_pcm_uframes_t, frames: ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t {
    return fc(Fn_snd_pcm_mmap_commit, &p_snd_pcm_mmap_commit, "snd_pcm_mmap_commit", .{ pcm, offset, frames }, 0);
}
pub export fn snd_pcm_recover(pcm: ?*ma_snd_pcm_t, err: c_int, silent: c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_recover, &p_snd_pcm_recover, "snd_pcm_recover", .{ pcm, err, silent }, -1);
}
pub export fn snd_pcm_readi(pcm: ?*ma_snd_pcm_t, buffer: ?*anyopaque, size: ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t {
    return fc(Fn_snd_pcm_readi, &p_snd_pcm_readi, "snd_pcm_readi", .{ pcm, buffer, size }, 0);
}
pub export fn snd_pcm_writei(pcm: ?*ma_snd_pcm_t, buffer: ?*const anyopaque, size: ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t {
    return fc(Fn_snd_pcm_writei, &p_snd_pcm_writei, "snd_pcm_writei", .{ pcm, buffer, size }, 0);
}
pub export fn snd_pcm_avail(pcm: ?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_sframes_t {
    return fc(Fn_snd_pcm_avail, &p_snd_pcm_avail, "snd_pcm_avail", .{pcm}, 0);
}
pub export fn snd_pcm_avail_update(pcm: ?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_sframes_t {
    return fc(Fn_snd_pcm_avail_update, &p_snd_pcm_avail_update, "snd_pcm_avail_update", .{pcm}, 0);
}
pub export fn snd_pcm_wait(pcm: ?*ma_snd_pcm_t, timeout: c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_wait, &p_snd_pcm_wait, "snd_pcm_wait", .{ pcm, timeout }, 0);
}
pub export fn snd_pcm_nonblock(pcm: ?*ma_snd_pcm_t, nonblock: c_int) callconv(.c) c_int {
    return fc(Fn_snd_pcm_nonblock, &p_snd_pcm_nonblock, "snd_pcm_nonblock", .{ pcm, nonblock }, -1);
}
pub export fn snd_pcm_info(pcm: ?*ma_snd_pcm_t, info: ?*ma_snd_pcm_info_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_info, &p_snd_pcm_info, "snd_pcm_info", .{ pcm, info }, -1);
}
pub export fn snd_pcm_info_sizeof() callconv(.c) usize {
    return fc(Fn_snd_pcm_info_sizeof, &p_snd_pcm_info_sizeof, "snd_pcm_info_sizeof", .{}, 0);
}
pub export fn snd_pcm_info_get_name(info: ?*const ma_snd_pcm_info_t) callconv(.c) [*c]const u8 {
    return fc(Fn_snd_pcm_info_get_name, &p_snd_pcm_info_get_name, "snd_pcm_info_get_name", .{info}, null);
}
pub export fn snd_pcm_poll_descriptors(pcm: ?*ma_snd_pcm_t, pfds: [*c]struct_pollfd, space: c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_poll_descriptors, &p_snd_pcm_poll_descriptors, "snd_pcm_poll_descriptors", .{ pcm, pfds, space }, 0);
}
pub export fn snd_pcm_poll_descriptors_count(pcm: ?*ma_snd_pcm_t) callconv(.c) c_int {
    return fc(Fn_snd_pcm_poll_descriptors_count, &p_snd_pcm_poll_descriptors_count, "snd_pcm_poll_descriptors_count", .{pcm}, 0);
}
pub export fn snd_pcm_poll_descriptors_revents(pcm: ?*ma_snd_pcm_t, pfds: [*c]struct_pollfd, nfds: c_uint, revents: [*c]c_ushort) callconv(.c) c_int {
    return fc(Fn_snd_pcm_poll_descriptors_revents, &p_snd_pcm_poll_descriptors_revents, "snd_pcm_poll_descriptors_revents", .{ pcm, pfds, nfds, revents }, -1);
}
pub export fn snd_config_update_free_global() callconv(.c) c_int {
    return fc(Fn_snd_config_update_free_global, &p_snd_config_update_free_global, "snd_config_update_free_global", .{}, 0);
}
pub export fn snd_pcm_set_params(pcm: ?*ma_snd_pcm_t, format: ma_snd_pcm_format_t, access: c_int, channels: c_uint, rate: c_uint, soft_resample: c_int, latency: c_uint) callconv(.c) c_int {
    return fc(Fn_snd_pcm_set_params, &p_snd_pcm_set_params, "snd_pcm_set_params", .{ pcm, format, access, channels, rate, soft_resample, latency }, -1);
}

// Symbol lookup function for dynamic function resolution
pub export fn dl_alsa_shim_lookup(name_c: [*:0]const u8) callconv(.c) ?*anyopaque {
    const n = std.mem.span(name_c);
    if (std.mem.eql(u8, n, "snd_pcm_open")) return @ptrCast(@constCast(&snd_pcm_open));
    if (std.mem.eql(u8, n, "snd_pcm_close")) return @ptrCast(@constCast(&snd_pcm_close));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_sizeof")) return @ptrCast(@constCast(&snd_pcm_hw_params_sizeof));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_any")) return @ptrCast(@constCast(&snd_pcm_hw_params_any));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_format")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_format));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_format_first")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_format_first));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_format_mask")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_format_mask));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_channels")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_channels));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_channels_near")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_channels_near));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_channels_minmax")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_channels_minmax));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_rate_resample")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_rate_resample));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_rate")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_rate));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_rate_near")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_rate_near));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_rate_minmax")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_rate_minmax));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_buffer_size_near")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_buffer_size_near));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_periods_near")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_periods_near));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_set_access")) return @ptrCast(@constCast(&snd_pcm_hw_params_set_access));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_format")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_format));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_channels")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_channels));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_channels_min")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_channels_min));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_channels_max")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_channels_max));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_rate")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_rate));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_rate_min")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_rate_min));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_rate_max")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_rate_max));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_buffer_size")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_buffer_size));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_periods")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_periods));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_get_access")) return @ptrCast(@constCast(&snd_pcm_hw_params_get_access));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_test_format")) return @ptrCast(@constCast(&snd_pcm_hw_params_test_format));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_test_channels")) return @ptrCast(@constCast(&snd_pcm_hw_params_test_channels));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params_test_rate")) return @ptrCast(@constCast(&snd_pcm_hw_params_test_rate));
    if (std.mem.eql(u8, n, "snd_pcm_hw_params")) return @ptrCast(@constCast(&snd_pcm_hw_params));
    if (std.mem.eql(u8, n, "snd_pcm_sw_params_sizeof")) return @ptrCast(@constCast(&snd_pcm_sw_params_sizeof));
    if (std.mem.eql(u8, n, "snd_pcm_sw_params_current")) return @ptrCast(@constCast(&snd_pcm_sw_params_current));
    if (std.mem.eql(u8, n, "snd_pcm_sw_params_get_boundary")) return @ptrCast(@constCast(&snd_pcm_sw_params_get_boundary));
    if (std.mem.eql(u8, n, "snd_pcm_sw_params_set_avail_min")) return @ptrCast(@constCast(&snd_pcm_sw_params_set_avail_min));
    if (std.mem.eql(u8, n, "snd_pcm_sw_params_set_start_threshold")) return @ptrCast(@constCast(&snd_pcm_sw_params_set_start_threshold));
    if (std.mem.eql(u8, n, "snd_pcm_sw_params_set_stop_threshold")) return @ptrCast(@constCast(&snd_pcm_sw_params_set_stop_threshold));
    if (std.mem.eql(u8, n, "snd_pcm_sw_params")) return @ptrCast(@constCast(&snd_pcm_sw_params));
    if (std.mem.eql(u8, n, "snd_pcm_format_mask_sizeof")) return @ptrCast(@constCast(&snd_pcm_format_mask_sizeof));
    if (std.mem.eql(u8, n, "snd_pcm_format_mask_test")) return @ptrCast(@constCast(&snd_pcm_format_mask_test));
    if (std.mem.eql(u8, n, "snd_pcm_get_chmap")) return @ptrCast(@constCast(&snd_pcm_get_chmap));
    if (std.mem.eql(u8, n, "snd_pcm_state")) return @ptrCast(@constCast(&snd_pcm_state));
    if (std.mem.eql(u8, n, "snd_pcm_prepare")) return @ptrCast(@constCast(&snd_pcm_prepare));
    if (std.mem.eql(u8, n, "snd_pcm_start")) return @ptrCast(@constCast(&snd_pcm_start));
    if (std.mem.eql(u8, n, "snd_pcm_drop")) return @ptrCast(@constCast(&snd_pcm_drop));
    if (std.mem.eql(u8, n, "snd_pcm_drain")) return @ptrCast(@constCast(&snd_pcm_drain));
    if (std.mem.eql(u8, n, "snd_pcm_reset")) return @ptrCast(@constCast(&snd_pcm_reset));
    if (std.mem.eql(u8, n, "snd_device_name_hint")) return @ptrCast(@constCast(&snd_device_name_hint));
    if (std.mem.eql(u8, n, "snd_device_name_get_hint")) return @ptrCast(@constCast(&snd_device_name_get_hint));
    if (std.mem.eql(u8, n, "snd_card_get_index")) return @ptrCast(@constCast(&snd_card_get_index));
    if (std.mem.eql(u8, n, "snd_device_name_free_hint")) return @ptrCast(@constCast(&snd_device_name_free_hint));
    if (std.mem.eql(u8, n, "snd_pcm_mmap_begin")) return @ptrCast(@constCast(&snd_pcm_mmap_begin));
    if (std.mem.eql(u8, n, "snd_pcm_mmap_commit")) return @ptrCast(@constCast(&snd_pcm_mmap_commit));
    if (std.mem.eql(u8, n, "snd_pcm_recover")) return @ptrCast(@constCast(&snd_pcm_recover));
    if (std.mem.eql(u8, n, "snd_pcm_readi")) return @ptrCast(@constCast(&snd_pcm_readi));
    if (std.mem.eql(u8, n, "snd_pcm_writei")) return @ptrCast(@constCast(&snd_pcm_writei));
    if (std.mem.eql(u8, n, "snd_pcm_avail")) return @ptrCast(@constCast(&snd_pcm_avail));
    if (std.mem.eql(u8, n, "snd_pcm_avail_update")) return @ptrCast(@constCast(&snd_pcm_avail_update));
    if (std.mem.eql(u8, n, "snd_pcm_wait")) return @ptrCast(@constCast(&snd_pcm_wait));
    if (std.mem.eql(u8, n, "snd_pcm_nonblock")) return @ptrCast(@constCast(&snd_pcm_nonblock));
    if (std.mem.eql(u8, n, "snd_pcm_info")) return @ptrCast(@constCast(&snd_pcm_info));
    if (std.mem.eql(u8, n, "snd_pcm_info_sizeof")) return @ptrCast(@constCast(&snd_pcm_info_sizeof));
    if (std.mem.eql(u8, n, "snd_pcm_info_get_name")) return @ptrCast(@constCast(&snd_pcm_info_get_name));
    if (std.mem.eql(u8, n, "snd_pcm_poll_descriptors")) return @ptrCast(@constCast(&snd_pcm_poll_descriptors));
    if (std.mem.eql(u8, n, "snd_pcm_poll_descriptors_count")) return @ptrCast(@constCast(&snd_pcm_poll_descriptors_count));
    if (std.mem.eql(u8, n, "snd_pcm_poll_descriptors_revents")) return @ptrCast(@constCast(&snd_pcm_poll_descriptors_revents));
    if (std.mem.eql(u8, n, "snd_config_update_free_global")) return @ptrCast(@constCast(&snd_config_update_free_global));
    if (std.mem.eql(u8, n, "snd_pcm_set_params")) return @ptrCast(@constCast(&snd_pcm_set_params));
    return null;
}
