// Zig port of libretro.c -- libretro core integration for afsrv_game
// Copyright 2012-2016, Bjorn Stahl
// License: GPLv2, see COPYING file in arcan source repository.
// Reference: http://www.libretro.com
//
// This port loads a libretro .so via dlopen, sets up the callback bridge,
// and pumps audio/video through shmif. NTSC post-filtering and 3D/GL
// support are stubbed out for the initial port.

const std = @import("std");
const c = @import("shmif_types");

// shmif functions declared as extern (not all are in shmif_types)
extern "c" fn arcan_shmif_signal(ctx: ?*c.struct_arcan_shmif_cont, mask: c_int) c_uint;
extern "c" fn arcan_shmif_resize(ctx: ?*c.struct_arcan_shmif_cont, w: c_uint, h: c_uint) bool;
extern "c" fn arcan_shmif_drop(ctx: ?*c.struct_arcan_shmif_cont) void;
extern "c" fn arcan_timemillis() c_longlong;
extern "c" fn arcan_timesleep(ms: c_ulong) void;

extern "c" var stdout: *anyopaque;
extern "c" var stderr: *anyopaque;

// Libretro API constants

const RETRO_API_VERSION: c_uint = 1;

// Environment commands
const RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: c_uint = 10;
const RETRO_ENVIRONMENT_GET_CAN_DUPE: c_uint = 3;
const RETRO_ENVIRONMENT_SHUTDOWN: c_uint = 7;
const RETRO_ENVIRONMENT_SET_VARIABLES: c_uint = 16;
const RETRO_ENVIRONMENT_GET_VARIABLE: c_uint = 15;
const RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL: c_uint = 8;
const RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: c_uint = 17;
const RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: c_uint = 9;
const RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK: c_uint = 21;
const RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE: c_uint = 23;
const RETRO_ENVIRONMENT_GET_PERF_INTERFACE: c_uint = 28;
const RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME: c_uint = 18;
const RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK: c_uint = 12;
const RETRO_ENVIRONMENT_GET_LOG_INTERFACE: c_uint = 27;
const RETRO_ENVIRONMENT_GET_USERNAME: c_uint = 38;
const RETRO_ENVIRONMENT_GET_LANGUAGE: c_uint = 39;
const RETRO_ENVIRONMENT_SET_HW_RENDER: c_uint = 14;
const RETRO_ENVIRONMENT_EXPERIMENTAL: c_uint = 0x10000;

// Pixel formats
const RETRO_PIXEL_FORMAT_0RGB1555: c_uint = 0;
const RETRO_PIXEL_FORMAT_XRGB8888: c_uint = 1;
const RETRO_PIXEL_FORMAT_RGB565: c_uint = 2;

// Device types
const RETRO_DEVICE_JOYPAD: c_uint = 1;
const RETRO_DEVICE_MOUSE: c_uint = 2;
const RETRO_DEVICE_KEYBOARD: c_uint = 3;
const RETRO_DEVICE_LIGHTGUN: c_uint = 4;
const RETRO_DEVICE_ANALOG: c_uint = 5;

// Joypad button IDs
const RETRO_DEVICE_ID_JOYPAD_B: c_uint = 0;
const RETRO_DEVICE_ID_JOYPAD_Y: c_uint = 1;
const RETRO_DEVICE_ID_JOYPAD_SELECT: c_uint = 2;
const RETRO_DEVICE_ID_JOYPAD_START: c_uint = 3;
const RETRO_DEVICE_ID_JOYPAD_UP: c_uint = 4;
const RETRO_DEVICE_ID_JOYPAD_DOWN: c_uint = 5;
const RETRO_DEVICE_ID_JOYPAD_LEFT: c_uint = 6;
const RETRO_DEVICE_ID_JOYPAD_RIGHT: c_uint = 7;
const RETRO_DEVICE_ID_JOYPAD_A: c_uint = 8;
const RETRO_DEVICE_ID_JOYPAD_X: c_uint = 9;
const RETRO_DEVICE_ID_JOYPAD_L: c_uint = 10;
const RETRO_DEVICE_ID_JOYPAD_R: c_uint = 11;
const RETRO_DEVICE_ID_JOYPAD_L2: c_uint = 12;
const RETRO_DEVICE_ID_JOYPAD_R2: c_uint = 13;
const RETRO_DEVICE_ID_JOYPAD_L3: c_uint = 14;
const RETRO_DEVICE_ID_JOYPAD_R3: c_uint = 15;

// Mouse IDs
const RETRO_DEVICE_ID_MOUSE_X: c_uint = 0;
const RETRO_DEVICE_ID_MOUSE_Y: c_uint = 1;
const RETRO_DEVICE_ID_MOUSE_LEFT: c_uint = 2;
const RETRO_DEVICE_ID_MOUSE_RIGHT: c_uint = 3;

// Lightgun IDs
const RETRO_DEVICE_ID_LIGHTGUN_X: c_uint = 0;
const RETRO_DEVICE_ID_LIGHTGUN_Y: c_uint = 1;
const RETRO_DEVICE_ID_LIGHTGUN_TRIGGER: c_uint = 2;
const RETRO_DEVICE_ID_LIGHTGUN_CURSOR: c_uint = 3;
const RETRO_DEVICE_ID_LIGHTGUN_TURBO: c_uint = 4;
const RETRO_DEVICE_ID_LIGHTGUN_PAUSE: c_uint = 5;
const RETRO_DEVICE_ID_LIGHTGUN_START: c_uint = 6;

// Language
const RETRO_LANGUAGE_ENGLISH: c_uint = 0;

// Keyboard -- RETROK values match SDL keysyms
const RETROK_LAST: usize = 324;
const RETROK_UP: u32 = 273;
const RETROK_DOWN: u32 = 274;
const RETROK_RIGHT: u32 = 275;
const RETROK_LEFT: u32 = 276;
const RETROK_RETURN: u32 = 13;
const RETROK_RSHIFT: u32 = 303;
const RETROK_z: u32 = 122;
const RETROK_x: u32 = 120;
const RETROK_a: u32 = 97;
const RETROK_s: u32 = 115;

// Libretro C callback types (for dlsym)

const RetroEnvironmentFn = *const fn (c_uint, ?*anyopaque) callconv(.c) bool;
const RetroVideoRefreshFn = *const fn (?*const anyopaque, c_uint, c_uint, usize) callconv(.c) void;
const RetroAudioSampleFn = *const fn (i16, i16) callconv(.c) void;
const RetroAudioSampleBatchFn = *const fn ([*]const i16, usize) callconv(.c) usize;
const RetroInputPollFn = *const fn () callconv(.c) void;
const RetroInputStateFn = *const fn (c_uint, c_uint, c_uint, c_uint) callconv(.c) i16;

// Function pointer types for core functions loaded via dlsym
const RetroRunFn = *const fn () callconv(.c) void;
const RetroResetFn = *const fn () callconv(.c) void;
const RetroInitFn = *const fn () callconv(.c) void;
const RetroDeInitFn = *const fn () callconv(.c) void;
const RetroApiVersionFn = *const fn () callconv(.c) c_uint;
const RetroLoadGameFn = *const fn (?*const RetroGameInfo) callconv(.c) bool;
const RetroSerializeSizeFn = *const fn () callconv(.c) usize;
const RetroSerializeFn = *const fn (?*anyopaque, usize) callconv(.c) bool;
const RetroDeserializeFn = *const fn (?*const anyopaque, usize) callconv(.c) bool;
const RetroSetControllerFn = *const fn (c_uint, c_uint) callconv(.c) void;
const RetroGetSystemInfoFn = *const fn (*RetroSystemInfo) callconv(.c) void;
const RetroGetSystemAvInfoFn = *const fn (*RetroSystemAvInfo) callconv(.c) void;

const RetroSetEnvironmentFn = *const fn (RetroEnvironmentFn) callconv(.c) void;
const RetroSetVideoRefreshFn = *const fn (RetroVideoRefreshFn) callconv(.c) void;
const RetroSetAudioSampleFn = *const fn (RetroAudioSampleFn) callconv(.c) void;
const RetroSetAudioSampleBatchFn = *const fn (RetroAudioSampleBatchFn) callconv(.c) void;
const RetroSetInputPollFn = *const fn (RetroInputPollFn) callconv(.c) void;
const RetroSetInputStateFn = *const fn (RetroInputStateFn) callconv(.c) void;

// Libretro structs (matching the C header layout)

const RetroGameGeometry = extern struct {
    base_width: c_uint = 0,
    base_height: c_uint = 0,
    max_width: c_uint = 0,
    max_height: c_uint = 0,
    aspect_ratio: f32 = 0,
};

const RetroSystemTiming = extern struct {
    fps: f64 = 0,
    sample_rate: f64 = 0,
};

const RetroSystemAvInfo = extern struct {
    geometry: RetroGameGeometry = .{},
    timing: RetroSystemTiming = .{},
};

const RetroSystemInfo = extern struct {
    library_name: ?[*:0]const u8 = null,
    library_version: ?[*:0]const u8 = null,
    valid_extensions: ?[*:0]const u8 = null,
    need_fullpath: bool = false,
    block_extract: bool = false,
};

const RetroGameInfo = extern struct {
    path: ?[*:0]const u8 = null,
    data: ?*const anyopaque = null,
    size: usize = 0,
    meta: ?[*:0]const u8 = null,
};

const RetroVariable = extern struct {
    key: ?[*:0]const u8 = null,
    value: ?[*:0]const u8 = null,
};

const RetroLogCallback = extern struct {
    log: ?*const fn (c_uint, [*:0]const u8, ...) callconv(.c) void = null,
};

// Port / input state

const MAX_PORTS = 4;
const MAX_AXES = 32;
const MAX_BUTTONS = 16;

const InputPort = struct {
    buttons: [MAX_BUTTONS]bool = [_]bool{false} ** MAX_BUTTONS,
    axes: [MAX_AXES]i16 = [_]i16{0} ** MAX_AXES,
    cursor_x: usize = 0,
    cursor_y: usize = 1,
    cursor_btns: [5]usize = [_]usize{ 0, 1, 2, 3, 4 },
};

// Core variable cache

const CoreVariable = struct {
    key: ?[*:0]const u8 = null,
    value: ?[*:0]const u8 = null,
    updated: bool = false,
};

// Pixel format converter type

const PixConvFn = enum {
    rgb1555,
    rgb565,
    xrgb8888,
    none,
};

// Main retro state

const RetroState = struct {
    // shmif connection
    shmcont: c.arcan_shmif_cont = std.mem.zeroes(c.arcan_shmif_cont),

    // skipframe flags
    skipframe_a: bool = false,
    skipframe_v: bool = false,
    empty_v: bool = false,

    // timing
    mspf: f64 = 0, // milliseconds per frame
    basetime: c_longlong = 0,

    // frame counters / stats
    aframecount: u64 = 0,
    vframecount: u64 = 0,
    frameskips: u32 = 0,
    transfercost: u32 = 0,
    framecost: u32 = 0,
    rebasecount: u32 = 0,

    // skip / sync mode
    skipmode: c_int = c.TARGET_SKIP_AUTO,
    prewake: c_int = 10,
    preaudiogen: c_int = 1,
    jitterstep: c_int = 0,
    jitterxfer: c_int = 0,

    // colour format
    converter: PixConvFn = .rgb1555,

    // audio / video buffer counts
    abuf_cnt: u8 = 12,
    def_abuf_sz: u16 = 1,
    vbuf_cnt: u8 = 3,

    // libretro system/game info
    sysinfo: RetroSystemInfo = .{},
    gameinfo: RetroGameInfo = .{},
    avinfo: RetroSystemAvInfo = .{},

    // core options
    optdirty: bool = false,
    res_empty: bool = false,

    // input ports
    input_ports: [MAX_PORTS]InputPort = [_]InputPort{.{}} ** MAX_PORTS,
    kbdtbl: [RETROK_LAST]u8 = [_]u8{0} ** RETROK_LAST,

    // rollback state
    dirty_input: bool = false,
    rollback_window: usize = 0,
    rollback_front: usize = 0,
    state_sz: usize = 0,

    // system path
    syspath: ?[*:0]const u8 = null,

    // dlopen handle
    libhandle: ?*anyopaque = null,

    // loaded function pointers
    run_fn: ?RetroRunFn = null,
    reset_fn: ?RetroResetFn = null,
    load_game_fn: ?RetroLoadGameFn = null,
    serialize_fn: ?RetroSerializeFn = null,
    deserialize_fn: ?RetroDeserializeFn = null,
    serialize_size_fn: ?RetroSerializeSizeFn = null,
    set_ioport_fn: ?RetroSetControllerFn = null,
};

// Module-level state (mirrors the C static struct)
var retro = RetroState{};

// dlsym helpers

const DL = struct {
    extern "c" fn dlopen(filename: ?[*:0]const u8, flags: c_int) ?*anyopaque;
    extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
    extern "c" fn dlclose(handle: ?*anyopaque) c_int;
    extern "c" fn dlerror() ?[*:0]const u8;

    const RTLD_LAZY = 0x1;
};

fn requireFun(comptime T: type, sym: [*:0]const u8) ?T {
    const raw = DL.dlsym(retro.libhandle, sym);
    if (raw) |ptr| {
        return @ptrCast(@alignCast(ptr));
    }
    _ = c.fprintf(stderr, "libretro: required symbol '%s' not found\n", sym);
    return null;
}

// Libretro callbacks (called by the core)

fn libretroVideoCb(data: ?*const anyopaque, width: c_uint, height: c_uint, pitch: usize) callconv(.c) void {
    if (data == null or retro.skipframe_v) {
        retro.empty_v = true;
        return;
    }
    retro.empty_v = false;

    const outw: usize = @intCast(width);
    const outh: usize = @intCast(height);

    // resize if dimensions changed
    if (outw != retro.shmcont.w or outh != retro.shmcont.h) {
        if (!arcan_shmif_resize(&retro.shmcont, @intCast(outw), @intCast(outh))) {
            _ = c.fprintf(stderr, "libretro: resize to %ux%u failed\n", width, height);
            return;
        }
    }

    // convert pixels into shmif vidp
    const src: [*]const u8 = @ptrCast(data.?);
    const dst: [*]u32 = retro.shmcont.unnamed_0.vidp;

    switch (retro.converter) {
        .rgb565 => convertRgb565(src, dst, outw, outh, pitch),
        .xrgb8888 => convertXrgb8888(src, dst, outw, outh, pitch),
        .rgb1555 => convertRgb1555(src, dst, outw, outh, pitch),
        .none => {},
    }
}

fn convertRgb565(src: [*]const u8, dst: [*]u32, width: usize, height: usize, pitch: usize) void {
    const lut5 = [32]u8{
        0,   8,  16,  25,  33,  41,  49,  58,  66,  74,  82,  90,  99, 107, 115, 123,
        132, 140, 148, 156, 165, 173, 181, 189, 197, 206, 214, 222, 230, 239, 247, 255,
    };
    const lut6 = [64]u8{
        0,   4,   8,  12,  16,  20,  24,  28,  32,  36,  40,  45,  49,  53,  57,  61,
        65,  69,  73,  77,  81,  85,  89,  93,  97, 101, 105, 109, 113, 117, 121, 125,
        130, 134, 138, 142, 146, 150, 154, 158, 162, 166, 170, 174, 178, 182, 186, 190,
        194, 198, 202, 206, 210, 215, 219, 223, 227, 231, 235, 239, 243, 247, 251, 255,
    };
    var y: usize = 0;
    var dst_off: usize = 0;
    while (y < height) : (y += 1) {
        const row: [*]const u16 = @ptrCast(@alignCast(src + y * pitch));
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const val = row[x];
            const r_idx: u5 = @truncate(val >> 11);
            const g_idx: u6 = @truncate(val >> 5);
            const b_idx: u5 = @truncate(val);
            dst[dst_off] = c.SHMIF_RGBA(lut5[r_idx], lut6[g_idx], lut5[b_idx], 0xff);
            dst_off += 1;
        }
    }
}

fn convertXrgb8888(src: [*]const u8, dst: [*]u32, width: usize, height: usize, pitch: usize) void {
    var y: usize = 0;
    var dst_off: usize = 0;
    while (y < height) : (y += 1) {
        const row: [*]const u32 = @ptrCast(@alignCast(src + y * pitch));
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const px = row[x];
            const r: u32 = (px >> 16) & 0xff;
            const g_val: u32 = (px >> 8) & 0xff;
            const b: u32 = px & 0xff;
            dst[dst_off] = c.SHMIF_RGBA(r, g_val, b, 0xff);
            dst_off += 1;
        }
    }
}

fn convertRgb1555(src: [*]const u8, dst: [*]u32, width: usize, height: usize, pitch: usize) void {
    var y: usize = 0;
    var dst_off: usize = 0;
    while (y < height) : (y += 1) {
        const row: [*]const u16 = @ptrCast(@alignCast(src + y * pitch));
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const val = row[x];
            const r: u32 = @as(u32, (val >> 10) & 0x1f) << 3;
            const g_val: u32 = @as(u32, (val >> 5) & 0x1f) << 3;
            const b: u32 = @as(u32, val & 0x1f) << 3;
            dst[dst_off] = c.SHMIF_RGBA(r, g_val, b, 0xff);
            dst_off += 1;
        }
    }
}

fn libretroAudioBatchCb(data: [*]const i16, nframes: usize) callconv(.c) usize {
    if (retro.skipframe_a) return nframes;
    retro.aframecount += nframes;

    // Write samples into shmif audio buffer, flushing when full.
    // Each frame = 2 samples (L+R stereo)
    var left = nframes * 2;
    var src = data;

    while (left > 0) {
        const abufcount: usize = retro.shmcont.abufcount;
        const abufpos: usize = retro.shmcont.abufpos;
        const bfree = abufcount -| abufpos;
        if (bfree == 0) {
            _ = arcan_shmif_signal(&retro.shmcont, @intCast(c.SHMIF_SIGAUD | c.SHMIF_SIGBLK_NONE));
            continue;
        }
        const ntw = @min(left, bfree);
        // Copy audio data into the shmif audio buffer
        const aud_base: [*]u8 = retro.shmcont.unnamed_1.audb;
        const dst_offset = abufpos * 2; // 2 bytes per sample (i16)
        const src_bytes: [*]const u8 = @ptrCast(src);
        @memcpy(aud_base[dst_offset .. dst_offset + ntw * 2], src_bytes[0 .. ntw * 2]);
        left -= ntw;
        src += ntw;
        retro.shmcont.abufpos = @intCast(abufpos + ntw);
        if (retro.shmcont.abufpos >= retro.shmcont.abufcount) {
            _ = arcan_shmif_signal(&retro.shmcont, @intCast(c.SHMIF_SIGAUD | c.SHMIF_SIGBLK_NONE));
        }
    }
    return nframes;
}

fn libretroAudioSingleCb(left: i16, right: i16) callconv(.c) void {
    if (retro.skipframe_a) return;
    retro.aframecount += 1;

    const aud_base: [*]i16 = @ptrCast(@alignCast(retro.shmcont.unnamed_1.audb));
    const pos: usize = retro.shmcont.abufpos;
    aud_base[pos] = left;
    aud_base[pos + 1] = right;
    retro.shmcont.abufpos = @intCast(pos + 2);
    if (retro.shmcont.abufpos >= retro.shmcont.abufcount) {
        _ = arcan_shmif_signal(&retro.shmcont, @intCast(c.SHMIF_SIGAUD | c.SHMIF_SIGBLK_NONE));
    }
}

fn libretroPollCb() callconv(.c) void {
    // no-op: input is polled in the main loop via flush_eventq
}

fn libretroInputStateCb(port: c_uint, dev: c_uint, ind: c_uint, id: c_uint) callconv(.c) i16 {
    if (port >= MAX_PORTS) return 0;
    if (id >= MAX_BUTTONS) return 0;

    const p = &retro.input_ports[@intCast(port)];

    switch (dev) {
        RETRO_DEVICE_JOYPAD => {
            if (id < MAX_BUTTONS) return if (p.buttons[@intCast(id)]) @as(i16, 1) else 0;
        },
        RETRO_DEVICE_KEYBOARD => {
            if (id < RETROK_LAST) return @intCast(retro.kbdtbl[@intCast(id)]);
        },
        RETRO_DEVICE_ANALOG => {
            const axis_idx: usize = @as(usize, @intCast(ind)) * 2 + @as(usize, @intCast(id));
            if (axis_idx < MAX_AXES) return p.axes[axis_idx];
        },
        RETRO_DEVICE_MOUSE => {
            switch (id) {
                RETRO_DEVICE_ID_MOUSE_LEFT => return if (p.buttons[p.cursor_btns[0]]) @as(i16, 1) else 0,
                RETRO_DEVICE_ID_MOUSE_RIGHT => return if (p.buttons[p.cursor_btns[2]]) @as(i16, 1) else 0,
                RETRO_DEVICE_ID_MOUSE_X => {
                    const rv = p.axes[p.cursor_x];
                    retro.input_ports[@intCast(port)].axes[p.cursor_x] = 0;
                    return rv;
                },
                RETRO_DEVICE_ID_MOUSE_Y => {
                    const rv = p.axes[p.cursor_y];
                    retro.input_ports[@intCast(port)].axes[p.cursor_y] = 0;
                    return rv;
                },
                else => {},
            }
        },
        else => {},
    }
    return 0;
}

// Environment callback

fn libretroSetenv(cmd: c_uint, data: ?*anyopaque) callconv(.c) bool {
    switch (cmd) {
        RETRO_ENVIRONMENT_SET_PIXEL_FORMAT => {
            if (data) |d| {
                const fmt: *const c_uint = @ptrCast(@alignCast(d));
                switch (fmt.*) {
                    RETRO_PIXEL_FORMAT_0RGB1555 => retro.converter = .rgb1555,
                    RETRO_PIXEL_FORMAT_RGB565 => retro.converter = .rgb565,
                    RETRO_PIXEL_FORMAT_XRGB8888 => retro.converter = .xrgb8888,
                    else => retro.converter = .none,
                }
            }
            return true;
        },
        RETRO_ENVIRONMENT_GET_CAN_DUPE => {
            if (data) |d| {
                const bp: *bool = @ptrCast(@alignCast(d));
                bp.* = true;
            }
            return true;
        },
        RETRO_ENVIRONMENT_SHUTDOWN => {
            arcan_shmif_drop(&retro.shmcont);
            std.process.exit(0);
        },
        RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME => {
            retro.res_empty = true;
            return true;
        },
        RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY => {
            if (data) |d| {
                const pp: *?[*:0]const u8 = @ptrCast(@alignCast(d));
                pp.* = retro.syspath;
            }
            return retro.syspath != null;
        },
        RETRO_ENVIRONMENT_GET_LOG_INTERFACE => {
            // provide a no-op log callback
            if (data) |d| {
                const lcb: *RetroLogCallback = @ptrCast(@alignCast(d));
                lcb.log = null; // cores should handle null gracefully
            }
            return true;
        },
        RETRO_ENVIRONMENT_GET_USERNAME => {
            if (data) |d| {
                const pp: *?[*:0]const u8 = @ptrCast(@alignCast(d));
                pp.* = "arcan";
            }
            return true;
        },
        RETRO_ENVIRONMENT_GET_LANGUAGE => {
            if (data) |d| {
                const up: *c_uint = @ptrCast(@alignCast(d));
                up.* = RETRO_LANGUAGE_ENGLISH;
            }
            return true;
        },
        RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE => {
            if (data) |d| {
                const bp: *bool = @ptrCast(@alignCast(d));
                bp.* = retro.optdirty;
            }
            retro.optdirty = false;
            return retro.optdirty;
        },
        RETRO_ENVIRONMENT_SET_VARIABLES,
        RETRO_ENVIRONMENT_GET_VARIABLE,
        RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL,
        RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK,
        RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE,
        RETRO_ENVIRONMENT_GET_PERF_INTERFACE,
        RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK,
        => return false,
        else => return false,
    }
}

// Input mapping

const remaptbl = [_]c_uint{
    RETRO_DEVICE_ID_JOYPAD_A,
    RETRO_DEVICE_ID_JOYPAD_B,
    RETRO_DEVICE_ID_JOYPAD_X,
    RETRO_DEVICE_ID_JOYPAD_Y,
    RETRO_DEVICE_ID_JOYPAD_L,
    RETRO_DEVICE_ID_JOYPAD_R,
    RETRO_DEVICE_ID_JOYPAD_L2,
    RETRO_DEVICE_ID_JOYPAD_R2,
    RETRO_DEVICE_ID_JOYPAD_L3,
    RETRO_DEVICE_ID_JOYPAD_R3,
};

fn defaultMap(ioev: *const c.arcan_ioevent) void {
    if (ioev.datatype == c.EVENT_IDATATYPE_TRANSLATED) {
        var button: ?c_uint = null;
        const active = ioev.input.translated.active != 0;

        switch (ioev.input.translated.keysym) {
            RETROK_x => button = RETRO_DEVICE_ID_JOYPAD_A,
            RETROK_z => button = RETRO_DEVICE_ID_JOYPAD_B,
            RETROK_a => button = RETRO_DEVICE_ID_JOYPAD_Y,
            RETROK_s => button = RETRO_DEVICE_ID_JOYPAD_X,
            RETROK_RETURN => button = RETRO_DEVICE_ID_JOYPAD_START,
            RETROK_RSHIFT => button = RETRO_DEVICE_ID_JOYPAD_SELECT,
            RETROK_LEFT => button = RETRO_DEVICE_ID_JOYPAD_LEFT,
            RETROK_RIGHT => button = RETRO_DEVICE_ID_JOYPAD_RIGHT,
            RETROK_UP => button = RETRO_DEVICE_ID_JOYPAD_UP,
            RETROK_DOWN => button = RETRO_DEVICE_ID_JOYPAD_DOWN,
            else => {},
        }
        if (button) |btn| {
            if (btn < MAX_BUTTONS) {
                retro.input_ports[0].buttons[@intCast(btn)] = active;
            }
        }
    }
}

// Event queue processing

fn flushEventQ() c_int {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    var ps: c_int = 0;

    while (true) {
        ps = c.arcan_shmif_poll(&retro.shmcont, &ev);
        if (ps <= 0) break;

        if (ev.unnamed_0.unnamed_0.category == c.EVENT_TARGET) {
            const tgt = &ev.unnamed_0.unnamed_0.unnamed_0.tgt;
            switch (tgt.kind) {
                c.TARGET_COMMAND_EXIT => {
                    arcan_shmif_drop(&retro.shmcont);
                    std.process.exit(0);
                },
                c.TARGET_COMMAND_RESET => {
                    if (retro.reset_fn) |reset| reset();
                },
                else => {},
            }
        } else if (ev.unnamed_0.unnamed_0.category == c.EVENT_IO) {
            defaultMap(&ev.unnamed_0.unnamed_0.unnamed_0.io);
        }
    }
    return ps;
}

// Timing / sync

fn resetTiming() void {
    retro.basetime = arcan_timemillis();
    retro.vframecount = 1;
    retro.aframecount = 1;
    retro.frameskips = 0;
}

fn retroSync() bool {
    retro.vframecount += 1;

    if (retro.skipframe_v or retro.empty_v) return true;

    const now = arcan_timemillis() - retro.basetime;
    const next: c_longlong = @intFromFloat(@floor(@as(f64, @floatFromInt(retro.vframecount)) * retro.mspf));
    const left = next - now;

    if (retro.skipmode == c.TARGET_SKIP_AUTO) {
        if (left < -200 or left > 200) {
            resetTiming();
            return true;
        }
        const half_mspf: c_longlong = @intFromFloat(-0.5 * retro.mspf);
        if (left < half_mspf) {
            retro.frameskips += 1;
            return false;
        }
    }

    if (left > retro.prewake) {
        const sleep_ms: c_ulong = @intCast(left - retro.prewake);
        arcan_timesleep(sleep_ms);
    }
    return true;
}

// Map core functions

fn mapCoreFunctions() bool {
    retro.run_fn = requireFun(RetroRunFn, "retro_run") orelse return false;
    retro.reset_fn = requireFun(RetroResetFn, "retro_reset") orelse return false;
    retro.load_game_fn = requireFun(RetroLoadGameFn, "retro_load_game") orelse return false;
    retro.serialize_fn = requireFun(RetroSerializeFn, "retro_serialize");
    retro.deserialize_fn = requireFun(RetroDeserializeFn, "retro_unserialize");
    retro.serialize_size_fn = requireFun(RetroSerializeSizeFn, "retro_serialize_size");
    retro.set_ioport_fn = requireFun(RetroSetControllerFn, "retro_set_controller_port_device");

    // set callbacks
    const set_video = requireFun(RetroSetVideoRefreshFn, "retro_set_video_refresh") orelse return false;
    set_video(libretroVideoCb);

    const set_audio_batch = requireFun(RetroSetAudioSampleBatchFn, "retro_set_audio_sample_batch") orelse return false;
    set_audio_batch(libretroAudioBatchCb);

    const set_audio = requireFun(RetroSetAudioSampleFn, "retro_set_audio_sample") orelse return false;
    set_audio(libretroAudioSingleCb);

    const set_poll = requireFun(RetroSetInputPollFn, "retro_set_input_poll") orelse return false;
    set_poll(libretroPollCb);

    const set_input = requireFun(RetroSetInputStateFn, "retro_set_input_state") orelse return false;
    set_input(libretroInputStateCb);

    return true;
}

// Help text

fn dumpHelp() void {
    _ = c.fprintf(stdout,
        \\ARCAN_ARG (environment variable, key1=value:key2:key3=value), arguments:
        \\   key        value       description
        \\---------  -----------  -----------------
        \\ core       filename    relative path to libretro core (req)
        \\ info                   load core, print information and quit
        \\ syspath    path        set core system path
        \\ resource   filename    resource file to load with core
        \\ vbufc      num         (1) 1..4 - number of video buffers
        \\ abufc      num         (8) 1..16 - number of audio buffers
        \\---------  -----------  -----------------
        \\
    );
}

// Main entry point

export fn afsrv_game(con: ?*c.arcan_shmif_cont, args: [*c]c.arg_arr) callconv(.c) c_int {
    if (con == null) {
        dumpHelp();
        return 1;
    }

    retro.converter = .rgb1555;
    retro.shmcont = con.?.*;

    // Parse arguments
    var libname: ?[*:0]const u8 = null;
    var resname: ?[*:0]const u8 = null;
    var val: [*c]const u8 = undefined;

    if (c.arg_lookup(args, "core", 0, &val)) {
        libname = @ptrCast(val);
    }
    if (c.arg_lookup(args, "resource", 0, &val)) {
        resname = @ptrCast(val);
    }
    if (c.arg_lookup(args, "abufc", 0, &val)) {
        const n = std.fmt.parseInt(u8, std.mem.span(@as([*:0]const u8, @ptrCast(val))), 10) catch 8;
        retro.abuf_cnt = if (n > 0 and n < 16) n else 8;
    }
    if (c.arg_lookup(args, "vbufc", 0, &val)) {
        const n = std.fmt.parseInt(u8, std.mem.span(@as([*:0]const u8, @ptrCast(val))), 10) catch 1;
        retro.vbuf_cnt = if (n > 0 and n <= 4) n else 1;
    }

    // System path
    retro.syspath = blk: {
        var sp: [*c]const u8 = undefined;
        if (c.arg_lookup(args, "syspath", 0, &sp)) {
            break :blk @ptrCast(sp);
        }
        break :blk "./";
    };

    const info_only = c.arg_lookup(args, "info", 0, null);

    if (libname == null) {
        _ = c.fprintf(stderr, "error > No core specified.\n");
        dumpHelp();
        return 1;
    }

    // Open the libretro core
    retro.libhandle = DL.dlopen(libname, DL.RTLD_LAZY);
    if (retro.libhandle == null) {
        _ = c.fprintf(stderr, "couldn't open library, giving up.\n");
        return 1;
    }

    // Initialize the core
    const initf = requireFun(RetroInitFn, "retro_init") orelse return 1;
    const apiver = requireFun(RetroApiVersionFn, "retro_api_version") orelse return 1;

    // Set environment callback before init
    const set_env = requireFun(RetroSetEnvironmentFn, "retro_set_environment") orelse return 1;
    set_env(libretroSetenv);

    // Call retro_init and verify API version
    initf();
    if (apiver() != RETRO_API_VERSION) {
        _ = c.fprintf(stderr, "libretro: API version mismatch\n");
        return 1;
    }

    // Get system info
    const get_sysinfo = requireFun(RetroGetSystemInfoFn, "retro_get_system_info") orelse return 1;
    get_sysinfo(&retro.sysinfo);

    if (info_only) {
        _ = c.fprintf(stdout, "arcan_frameserver(info)\nlibrary:%s\nversion:%s\nextensions:%s\n/arcan_frameserver(info)\n",
            retro.sysinfo.library_name orelse "unknown",
            retro.sysinfo.library_version orelse "unknown",
            retro.sysinfo.valid_extensions orelse "none");
        return 1;
    }

    _ = c.fprintf(stderr, "libretro(%s), version %s loaded. Extensions: %s\n",
        retro.sysinfo.library_name orelse "unknown",
        retro.sysinfo.library_version orelse "unknown",
        retro.sysinfo.valid_extensions orelse "none");

    // Map runtime functions and set callbacks
    if (!mapCoreFunctions()) {
        _ = c.fprintf(stderr, "libretro: failed to resolve core functions\n");
        return 1;
    }

    // Load game resource
    if (resname != null or !retro.res_empty) {
        retro.gameinfo.path = resname;
        retro.gameinfo.data = null;
        retro.gameinfo.size = 0;

        if (!(retro.load_game_fn.?(&retro.gameinfo))) {
            c.arcan_shmif_last_words(&retro.shmcont, "Core couldn't load resource");
            _ = c.fprintf(stderr, "libretro: core rejected the resource\n");
            return 1;
        }
    }

    // Get AV info
    const get_avinfo = requireFun(RetroGetSystemAvInfoFn, "retro_get_system_av_info") orelse return 1;
    get_avinfo(&retro.avinfo);

    if (retro.avinfo.timing.fps > 1) {
        retro.mspf = 1000.0 / retro.avinfo.timing.fps;
    }

    _ = c.fprintf(stderr, "video: %f fps (%f ms), audio: %f Hz\n",
        retro.avinfo.timing.fps, retro.mspf, retro.avinfo.timing.sample_rate);

    // Initial resize to base geometry
    if (!arcan_shmif_resize(&retro.shmcont,
        @intCast(retro.avinfo.geometry.base_width),
        @intCast(retro.avinfo.geometry.base_height))) {
        _ = c.fprintf(stderr, "libretro: initial shmpage resize failed\n");
        return 1;
    }

    // Set up input defaults
    for (&retro.input_ports) |*port| {
        port.cursor_x = 0;
        port.cursor_y = 1;
        port.cursor_btns = [_]usize{ 0, 1, 2, 3, 4 };
    }

    // Serialize size for save states
    if (retro.serialize_size_fn) |ssf| {
        retro.state_sz = ssf();
    }

    // Send IDENT event
    var ident_ev = c.arcan_event.zeroes();
    ident_ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_IDENT;
    ident_ev.unnamed_0.unnamed_0.category = @intCast(c.EVENT_EXTERNAL);
    _ = c.arcan_shmif_enqueue(&retro.shmcont, &ident_ev);

    // Send cursor-hide hint
    var cursor_ev = c.arcan_event.zeroes();
    cursor_ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_CURSORHINT;
    cursor_ev.unnamed_0.unnamed_0.category = @intCast(c.EVENT_EXTERNAL);
    _ = c.arcan_shmif_enqueue(&retro.shmcont, &cursor_ev);

    // Run initial frame (to populate buffers)
    retro.skipframe_v = true;
    retro.skipframe_a = true;
    retro.run_fn.?();
    retro.skipframe_v = false;
    retro.skipframe_a = false;

    // Set base time
    retro.basetime = arcan_timemillis();

    // Main loop
    while (flushEventQ() >= 0) {
        // Fastforward / step modes
        if (retro.skipmode >= c.TARGET_SKIP_FASTFWD) {
            const nframes: usize = @intCast(retro.skipmode - c.TARGET_SKIP_FASTFWD + 1);
            retro.skipframe_v = true;
            retro.skipframe_a = true;
            for (0..nframes) |_| retro.run_fn.?();
            retro.skipframe_v = false;
            retro.skipframe_a = false;
        } else if (retro.skipmode >= c.TARGET_SKIP_STEP) {
            const nframes: usize = @intCast(retro.skipmode - c.TARGET_SKIP_STEP + 1);
            retro.skipframe_v = true;
            for (0..nframes) |_| retro.run_fn.?();
            retro.skipframe_v = false;
        }

        // Normal frame
        const start = arcan_timemillis();
        retro.run_fn.?();
        const stop = arcan_timemillis();
        retro.framecost = @intCast(stop - start);

        // Signal video if we have a frame
        if (!retro.empty_v) {
            const elapsed: c_uint = arcan_shmif_signal(&retro.shmcont,
                @intCast(c.SHMIF_SIGVID | c.SHMIF_SIGBLK_NONE));
            retro.transfercost = elapsed;
        }

        // Sync to framerate
        retro.skipframe_a = false;
        retro.skipframe_v = !retroSync();
    }

    // Clean up
    const deinit = requireFun(RetroDeInitFn, "retro_deinit");
    if (deinit) |d| d();

    if (retro.libhandle) |h| _ = DL.dlclose(h);
    arcan_shmif_drop(&retro.shmcont);

    return 0;
}
