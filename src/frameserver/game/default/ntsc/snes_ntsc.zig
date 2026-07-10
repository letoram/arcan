// Zig port of snes_ntsc.c -- SNES NTSC video filter
// Original: snes_ntsc 0.2.2 by Shay Green
// Copyright (C) 2006-2007 Shay Green (LGPL 2.1)
//
// This is a stub that provides the type definitions and no-op implementations.
// The full NTSC filter math is complex macro-heavy C; for now cores that need
// NTSC filtering will simply get a pass-through.

const std = @import("std");

// Public types matching the C header

pub const snes_ntsc_setup_t = extern struct {
    hue: f64 = 0,
    saturation: f64 = 0,
    contrast: f64 = 0,
    brightness: f64 = 0,
    sharpness: f64 = 0,
    gamma: f64 = 0,
    resolution: f64 = 0,
    artifacts: f64 = 0,
    fringing: f64 = 0,
    bleed: f64 = 0,
    merge_fields: c_int = 0,
    decoder_matrix: ?[*]const f32 = null,
    bsnes_colortbl: ?[*]const c_ulong = null,
};

pub const snes_ntsc_in_chunk: c_int = 3;
pub const snes_ntsc_out_chunk: c_int = 7;
pub const snes_ntsc_black: c_int = 0;
pub const snes_ntsc_burst_count: c_int = 3;

const snes_ntsc_entry_size = 128;
const snes_ntsc_palette_size = 0x2000;
pub const snes_ntsc_rgb_t = c_ulong;
const snes_ntsc_burst_size = snes_ntsc_entry_size / snes_ntsc_burst_count;

pub const snes_ntsc_t = extern struct {
    table: [snes_ntsc_palette_size][snes_ntsc_entry_size]snes_ntsc_rgb_t =
        std.mem.zeroes([snes_ntsc_palette_size][snes_ntsc_entry_size]snes_ntsc_rgb_t),
};

/// Calculate output width from input width
pub inline fn snesNtscOutWidth(in_width: usize) usize {
    return (((in_width -| 1) / @as(usize, @intCast(snes_ntsc_in_chunk)) + 1) *
        @as(usize, @intCast(snes_ntsc_out_chunk)));
}

// Video format presets

pub const snes_ntsc_composite = snes_ntsc_setup_t{};
pub const snes_ntsc_svideo = snes_ntsc_setup_t{ .sharpness = 0.2, .resolution = 0.2, .artifacts = -1, .fringing = -1 };
pub const snes_ntsc_rgb = snes_ntsc_setup_t{ .sharpness = 0.2, .resolution = 0.7, .artifacts = -1, .fringing = -1, .bleed = -1 };
pub const snes_ntsc_monochrome = snes_ntsc_setup_t{ .saturation = -1, .sharpness = 0.2, .resolution = 0.2, .artifacts = -0.2, .fringing = -0.2, .bleed = -1 };

// Stub implementations

/// Initialize / re-initialize the NTSC filter.
/// Stub: does nothing -- NTSC filtering is disabled in this port.
pub fn init(ntsc: ?*snes_ntsc_t, setup: ?*const snes_ntsc_setup_t) void {
    _ = ntsc;
    _ = setup;
}

/// Blit with NTSC filtering applied.
/// Stub: no-op. The caller should fall back to direct pixel copy.
pub fn blit(
    ntsc: ?*const snes_ntsc_t,
    input: ?[*]const u16,
    in_row_width: c_long,
    burst_phase: c_int,
    in_width: c_int,
    in_height: c_int,
    rgb_out: ?*anyopaque,
    out_pitch: c_long,
) void {
    _ = ntsc;
    _ = input;
    _ = in_row_width;
    _ = burst_phase;
    _ = in_width;
    _ = in_height;
    _ = rgb_out;
    _ = out_pitch;
}

/// Update NTSC setup parameters by group.
/// Stub: just updates the destination struct fields.
pub fn updateSetup(
    ntsc: ?*snes_ntsc_t,
    dst: ?*snes_ntsc_setup_t,
    group: c_int,
    v1: f32,
    v2: f32,
    v3: f32,
) void {
    if (dst) |d| {
        switch (group) {
            1 => {
                d.hue = v1;
                d.saturation = v2;
                d.contrast = v3;
            },
            2 => {
                d.brightness = v1;
                d.gamma = v2;
                d.sharpness = v3;
            },
            3 => {
                d.resolution = v1;
                d.artifacts = v2;
                d.bleed = v3;
            },
            4 => {
                d.fringing = v1;
            },
            else => {},
        }
    }
    // re-init with updated params (no-op in stub)
    init(ntsc, dst);
}

// C-compatible exports for any remaining C callers

export fn snes_ntsc_init(ntsc: ?*snes_ntsc_t, setup: ?*const snes_ntsc_setup_t) void {
    init(ntsc, setup);
}

export fn snes_ntsc_blit(
    ntsc: ?*const snes_ntsc_t,
    input: ?[*]const u16,
    in_row_width: c_long,
    burst_phase: c_int,
    in_width: c_int,
    in_height: c_int,
    rgb_out: ?*anyopaque,
    out_pitch: c_long,
) void {
    blit(ntsc, input, in_row_width, burst_phase, in_width, in_height, rgb_out, out_pitch);
}

export fn snes_ntsc_update_setup(
    ntsc: ?*snes_ntsc_t,
    dst: ?*snes_ntsc_setup_t,
    group: c_int,
    v1: f32,
    v2: f32,
    v3: f32,
) void {
    updateSetup(ntsc, dst, group, v1, v2, v3);
}
