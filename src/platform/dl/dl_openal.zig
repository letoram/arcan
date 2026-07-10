// OpenAL runtime-dlopen shim. See dl_drm.zig for the pattern rationale.
//
// Covers the 33 AL / ALC functions referenced by src/platform/audio/openal.zig.
// Primitive types: ALuint→c_uint, ALint/ALenum/ALsizei→c_int, ALfloat→f32,
// ALboolean→u8. ALCdevice/ALCcontext are opaque pointers (?*anyopaque) —
// register-level ABI matches since the caller only passes/receives pointer
// values.

const std = @import("std");
const dl = @import("dlopen");

var handle: ?*anyopaque = null;
var init_done: bool = false;

fn ensureLoaded() void {
    if (init_done) return;
    init_done = true;
    // Try soname first; fall back to unversioned (some distros ship only .so)
    handle = dl.zig_dlopen("libopenal.so.1", 1) orelse
        dl.zig_dlopen("libopenal.so", 1);
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
// its own bracket so any glibc-TLS read inside OpenAL (ALSA/PipeWire
// plug-ins pull in libc internals) lands on the right layout.
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

// ── ALC (device / context management, capture) ───────────────────────

const FnAlcOpenDevice = *const fn ([*c]const u8) callconv(.c) ?*anyopaque;
const FnAlcCreateContext = *const fn (?*anyopaque, [*c]const c_int) callconv(.c) ?*anyopaque;
const FnAlcMakeContextCurrent = *const fn (?*anyopaque) callconv(.c) u8;
const FnAlcDestroyContext = *const fn (?*anyopaque) callconv(.c) void;
const FnAlcGetCurrentContext = *const fn () callconv(.c) ?*anyopaque;
const FnAlcGetIntegerv = *const fn (?*anyopaque, c_int, c_int, [*c]c_int) callconv(.c) void;
const FnAlcGetProcAddress = *const fn (?*anyopaque, [*c]const u8) callconv(.c) ?*anyopaque;
const FnAlcGetString = *const fn (?*anyopaque, c_int) callconv(.c) [*c]const u8;
const FnAlcIsExtensionPresent = *const fn (?*anyopaque, [*c]const u8) callconv(.c) u8;
const FnAlcCaptureOpenDevice = *const fn ([*c]const u8, c_uint, c_int, c_int) callconv(.c) ?*anyopaque;
const FnAlcCaptureCloseDevice = *const fn (?*anyopaque) callconv(.c) u8;
const FnAlcCaptureStart = *const fn (?*anyopaque) callconv(.c) void;
const FnAlcCaptureStop = *const fn (?*anyopaque) callconv(.c) void;
const FnAlcCaptureSamples = *const fn (?*anyopaque, ?*anyopaque, c_int) callconv(.c) void;

var p_alcOpenDevice: ?FnAlcOpenDevice = null;
var p_alcCreateContext: ?FnAlcCreateContext = null;
var p_alcMakeContextCurrent: ?FnAlcMakeContextCurrent = null;
var p_alcDestroyContext: ?FnAlcDestroyContext = null;
var p_alcGetCurrentContext: ?FnAlcGetCurrentContext = null;
var p_alcGetIntegerv: ?FnAlcGetIntegerv = null;
var p_alcGetProcAddress: ?FnAlcGetProcAddress = null;
var p_alcGetString: ?FnAlcGetString = null;
var p_alcIsExtensionPresent: ?FnAlcIsExtensionPresent = null;
var p_alcCaptureOpenDevice: ?FnAlcCaptureOpenDevice = null;
var p_alcCaptureCloseDevice: ?FnAlcCaptureCloseDevice = null;
var p_alcCaptureStart: ?FnAlcCaptureStart = null;
var p_alcCaptureStop: ?FnAlcCaptureStop = null;
var p_alcCaptureSamples: ?FnAlcCaptureSamples = null;

pub export fn alcOpenDevice(name: [*c]const u8) callconv(.c) ?*anyopaque {
    return fc(FnAlcOpenDevice, &p_alcOpenDevice, "alcOpenDevice", .{name}, null);
}
pub export fn alcCreateContext(device: ?*anyopaque, attrs: [*c]const c_int) callconv(.c) ?*anyopaque {
    return fc(FnAlcCreateContext, &p_alcCreateContext, "alcCreateContext", .{ device, attrs }, null);
}
pub export fn alcMakeContextCurrent(ctx: ?*anyopaque) callconv(.c) u8 {
    return fc(FnAlcMakeContextCurrent, &p_alcMakeContextCurrent, "alcMakeContextCurrent", .{ctx}, 0);
}
pub export fn alcDestroyContext(ctx: ?*anyopaque) callconv(.c) void {
    fcv(FnAlcDestroyContext, &p_alcDestroyContext, "alcDestroyContext", .{ctx});
}
pub export fn alcGetCurrentContext() callconv(.c) ?*anyopaque {
    return fc(FnAlcGetCurrentContext, &p_alcGetCurrentContext, "alcGetCurrentContext", .{}, null);
}
pub export fn alcGetIntegerv(device: ?*anyopaque, param: c_int, size: c_int, out: [*c]c_int) callconv(.c) void {
    fcv(FnAlcGetIntegerv, &p_alcGetIntegerv, "alcGetIntegerv", .{ device, param, size, out });
}
pub export fn alcGetProcAddress(device: ?*anyopaque, name: [*c]const u8) callconv(.c) ?*anyopaque {
    return fc(FnAlcGetProcAddress, &p_alcGetProcAddress, "alcGetProcAddress", .{ device, name }, null);
}
pub export fn alcGetString(device: ?*anyopaque, param: c_int) callconv(.c) [*c]const u8 {
    return fc(FnAlcGetString, &p_alcGetString, "alcGetString", .{ device, param }, null);
}
pub export fn alcIsExtensionPresent(device: ?*anyopaque, name: [*c]const u8) callconv(.c) u8 {
    return fc(FnAlcIsExtensionPresent, &p_alcIsExtensionPresent, "alcIsExtensionPresent", .{ device, name }, 0);
}
pub export fn alcCaptureOpenDevice(name: [*c]const u8, freq: c_uint, fmt: c_int, bufsize: c_int) callconv(.c) ?*anyopaque {
    return fc(FnAlcCaptureOpenDevice, &p_alcCaptureOpenDevice, "alcCaptureOpenDevice", .{ name, freq, fmt, bufsize }, null);
}
pub export fn alcCaptureCloseDevice(device: ?*anyopaque) callconv(.c) u8 {
    return fc(FnAlcCaptureCloseDevice, &p_alcCaptureCloseDevice, "alcCaptureCloseDevice", .{device}, 0);
}
pub export fn alcCaptureStart(device: ?*anyopaque) callconv(.c) void {
    fcv(FnAlcCaptureStart, &p_alcCaptureStart, "alcCaptureStart", .{device});
}
pub export fn alcCaptureStop(device: ?*anyopaque) callconv(.c) void {
    fcv(FnAlcCaptureStop, &p_alcCaptureStop, "alcCaptureStop", .{device});
}
pub export fn alcCaptureSamples(device: ?*anyopaque, buf: ?*anyopaque, samples: c_int) callconv(.c) void {
    fcv(FnAlcCaptureSamples, &p_alcCaptureSamples, "alcCaptureSamples", .{ device, buf, samples });
}

// ── AL (buffers, sources, listener) ──────────────────────────────────

const FnAlGenBuffers = *const fn (c_int, [*c]c_uint) callconv(.c) void;
const FnAlDeleteBuffers = *const fn (c_int, [*c]const c_uint) callconv(.c) void;
const FnAlBufferData = *const fn (c_uint, c_int, ?*const anyopaque, c_int, c_int) callconv(.c) void;
const FnAlGenSources = *const fn (c_int, [*c]c_uint) callconv(.c) void;
const FnAlDeleteSources = *const fn (c_int, [*c]const c_uint) callconv(.c) void;
const FnAlSourcei = *const fn (c_uint, c_int, c_int) callconv(.c) void;
const FnAlSourcef = *const fn (c_uint, c_int, f32) callconv(.c) void;
const FnAlSourcefv = *const fn (c_uint, c_int, [*c]const f32) callconv(.c) void;
const FnAlGetSourcei = *const fn (c_uint, c_int, [*c]c_int) callconv(.c) void;
const FnAlSourcePlay = *const fn (c_uint) callconv(.c) void;
const FnAlSourceStop = *const fn (c_uint) callconv(.c) void;
const FnAlSourceQueueBuffers = *const fn (c_uint, c_int, [*c]const c_uint) callconv(.c) void;
const FnAlSourceUnqueueBuffers = *const fn (c_uint, c_int, [*c]c_uint) callconv(.c) void;
const FnAlListenerf = *const fn (c_int, f32) callconv(.c) void;
const FnAlListenerfv = *const fn (c_int, [*c]const f32) callconv(.c) void;
const FnAlListener3f = *const fn (c_int, f32, f32, f32) callconv(.c) void;
const FnAlSource3f = *const fn (c_uint, c_int, f32, f32, f32) callconv(.c) void;
const FnAlGetError = *const fn () callconv(.c) c_int;
const FnAlGetEnumValue = *const fn ([*c]const u8) callconv(.c) c_int;

var p_alGenBuffers: ?FnAlGenBuffers = null;
var p_alDeleteBuffers: ?FnAlDeleteBuffers = null;
var p_alBufferData: ?FnAlBufferData = null;
var p_alGenSources: ?FnAlGenSources = null;
var p_alDeleteSources: ?FnAlDeleteSources = null;
var p_alSourcei: ?FnAlSourcei = null;
var p_alSourcef: ?FnAlSourcef = null;
var p_alSourcefv: ?FnAlSourcefv = null;
var p_alGetSourcei: ?FnAlGetSourcei = null;
var p_alSourcePlay: ?FnAlSourcePlay = null;
var p_alSourceStop: ?FnAlSourceStop = null;
var p_alSourceQueueBuffers: ?FnAlSourceQueueBuffers = null;
var p_alSourceUnqueueBuffers: ?FnAlSourceUnqueueBuffers = null;
var p_alListenerf: ?FnAlListenerf = null;
var p_alListenerfv: ?FnAlListenerfv = null;
var p_alListener3f: ?FnAlListener3f = null;
var p_alSource3f: ?FnAlSource3f = null;
var p_alGetError: ?FnAlGetError = null;
var p_alGetEnumValue: ?FnAlGetEnumValue = null;

pub export fn alGenBuffers(n: c_int, buffers: [*c]c_uint) callconv(.c) void {
    fcv(FnAlGenBuffers, &p_alGenBuffers, "alGenBuffers", .{ n, buffers });
}
pub export fn alDeleteBuffers(n: c_int, buffers: [*c]const c_uint) callconv(.c) void {
    fcv(FnAlDeleteBuffers, &p_alDeleteBuffers, "alDeleteBuffers", .{ n, buffers });
}
pub export fn alBufferData(buf: c_uint, fmt: c_int, data: ?*const anyopaque, size: c_int, srate: c_int) callconv(.c) void {
    fcv(FnAlBufferData, &p_alBufferData, "alBufferData", .{ buf, fmt, data, size, srate });
}
pub export fn alGenSources(n: c_int, sources: [*c]c_uint) callconv(.c) void {
    fcv(FnAlGenSources, &p_alGenSources, "alGenSources", .{ n, sources });
}
pub export fn alDeleteSources(n: c_int, sources: [*c]const c_uint) callconv(.c) void {
    fcv(FnAlDeleteSources, &p_alDeleteSources, "alDeleteSources", .{ n, sources });
}
pub export fn alSourcei(source: c_uint, param: c_int, value: c_int) callconv(.c) void {
    fcv(FnAlSourcei, &p_alSourcei, "alSourcei", .{ source, param, value });
}
pub export fn alSourcef(source: c_uint, param: c_int, value: f32) callconv(.c) void {
    fcv(FnAlSourcef, &p_alSourcef, "alSourcef", .{ source, param, value });
}
pub export fn alSourcefv(source: c_uint, param: c_int, values: [*c]const f32) callconv(.c) void {
    fcv(FnAlSourcefv, &p_alSourcefv, "alSourcefv", .{ source, param, values });
}
pub export fn alGetSourcei(source: c_uint, param: c_int, out: [*c]c_int) callconv(.c) void {
    fcv(FnAlGetSourcei, &p_alGetSourcei, "alGetSourcei", .{ source, param, out });
}
pub export fn alSourcePlay(source: c_uint) callconv(.c) void {
    fcv(FnAlSourcePlay, &p_alSourcePlay, "alSourcePlay", .{source});
}
pub export fn alSourceStop(source: c_uint) callconv(.c) void {
    fcv(FnAlSourceStop, &p_alSourceStop, "alSourceStop", .{source});
}
pub export fn alSourceQueueBuffers(source: c_uint, nb: c_int, buffers: [*c]const c_uint) callconv(.c) void {
    fcv(FnAlSourceQueueBuffers, &p_alSourceQueueBuffers, "alSourceQueueBuffers", .{ source, nb, buffers });
}
pub export fn alSourceUnqueueBuffers(source: c_uint, nb: c_int, buffers: [*c]c_uint) callconv(.c) void {
    fcv(FnAlSourceUnqueueBuffers, &p_alSourceUnqueueBuffers, "alSourceUnqueueBuffers", .{ source, nb, buffers });
}
pub export fn alListenerf(param: c_int, value: f32) callconv(.c) void {
    fcv(FnAlListenerf, &p_alListenerf, "alListenerf", .{ param, value });
}
pub export fn alListenerfv(param: c_int, values: [*c]const f32) callconv(.c) void {
    fcv(FnAlListenerfv, &p_alListenerfv, "alListenerfv", .{ param, values });
}
pub export fn alListener3f(param: c_int, v1: f32, v2: f32, v3: f32) callconv(.c) void {
    fcv(FnAlListener3f, &p_alListener3f, "alListener3f", .{ param, v1, v2, v3 });
}
pub export fn alSource3f(source: c_uint, param: c_int, v1: f32, v2: f32, v3: f32) callconv(.c) void {
    fcv(FnAlSource3f, &p_alSource3f, "alSource3f", .{ source, param, v1, v2, v3 });
}
pub export fn alGetError() callconv(.c) c_int {
    return fc(FnAlGetError, &p_alGetError, "alGetError", .{}, 0);
}
pub export fn alGetEnumValue(name: [*c]const u8) callconv(.c) c_int {
    return fc(FnAlGetEnumValue, &p_alGetEnumValue, "alGetEnumValue", .{name}, 0);
}
