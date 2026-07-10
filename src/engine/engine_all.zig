// engine_all.zig — single-compilation-unit aggregate of the arcan engine for
// the macOS arcan_vk build (mirrors shmif_all.zig / lua_all.zig / plat_all.zig).
// Cross-file linkage inside src/engine is C-ABI (extern fn / export fn), so one
// object holding every engine file resolves internally at link time.
//
// Excluded on purpose:
//   arcan_ttf_test*.zig    — test harness only
//   arcan_main_entry.zig   — C `main` shim; this root provides the Zig entry
//   arcan_bootstrap.zig    — may-dialect appl source (embedded as .lua instead)
//
// Module deps (wired by the build command): arcan, posix, engine_offsets,
// TrueType, arcan_boot_compat, xitdb, shmif_types, shmif_offsets, shmif_monitor.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    _ = @import("arcan_3dbase.zig");
    _ = @import("arcan_audio.zig");
    _ = @import("arcan_conductor.zig");
    _ = @import("arcan_db.zig");
    _ = @import("arcan_event.zig");
    _ = @import("arcan_ffunc_lut.zig");
    _ = @import("arcan_frameserver_helpers.zig");
    _ = @import("arcan_frameserver.zig");
    _ = @import("arcan_img_stb.zig");
    _ = @import("arcan_img.zig");
    _ = @import("arcan_led.zig");
    _ = @import("arcan_lua.zig");
    _ = @import("arcan_main.zig");
    _ = @import("arcan_math.zig");
    _ = @import("arcan_monitor.zig");
    _ = @import("arcan_raster_gpu.zig");
    _ = @import("arcan_raster.zig");
    _ = @import("arcan_renderfun.zig");
    _ = @import("arcan_trace.zig");
    _ = @import("arcan_ttf.zig");
    _ = @import("arcan_video.zig");
    _ = @import("arcan_vr_helpers.zig");
    _ = @import("arcan_vr.zig");
    _ = @import("slug_glyph.zig");
    _ = @import("zig_image_resize.zig");
    _ = @import("alt/types.zig");
    _ = @import("alt/support.zig");
    _ = @import("alt/nbio.zig");
    _ = @import("alt/trace.zig");
    _ = @import("external/stb_image.zig");
    _ = @import("external/stb_perlin.zig");
    _ = @import("external/bit.zig");

    // Platform layers as modules — one compilation unit total, so shared
    // modules (dlopen, posix, shmif_*) emit their exports exactly once.
    _ = @import("platform_video");
    _ = @import("platform_audio");
    _ = @import("platform_posix");
    _ = @import("platform_shmif");
    _ = @import("lua");
    _ = @import("cocoa_window");
    _ = @import("platform_fsrv");
}

extern fn arcan_main(argc: c_int, argv: [*c][*c]u8) c_int;

pub fn main() u8 {
    const argv = std.os.argv;
    return @intCast(arcan_main(@intCast(argv.len), @ptrCast(argv.ptr)));
}
