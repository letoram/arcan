// Zig port of stub.c — shmif_ext platform stubs for headless builds
// DMA-BUF signal_planes is implemented (no EGL needed — just fd pushing + events).
// DMA-BUF acceleration: allocate via /dev/dma_heap/system, signal via BUFFERSTREAM.
// Note: arcan_shmifext_signal (varargs) remains in stub_signal.c
const std = @import("std");
const shmif = @import("shmif_types");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
    pub const arcan_event = shmif.arcan_event;
    pub const arcan_shmif_enqueue = shmif.arcan_shmif_enqueue;
    pub const arcan_shmif_signal = shmif.arcan_shmif_signal;
    pub const struct_arcan_shmifext_setup = shmif.struct_arcan_shmifext_setup;
    pub const struct_shmifext_buffer_plane = shmif.struct_shmifext_buffer_plane;
    pub const struct_shmifext_color_buffer = shmif.struct_shmifext_color_buffer;
    pub const struct_agp_fenv = shmif.struct_agp_fenv;
    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BUFFERSTREAM = shmif.EVENT_EXTERNAL_BUFFERSTREAM;
    pub const SHMIFEXT_OK = shmif.SHMIFEXT_OK;
    pub const SHMIFEXT_NO_API = shmif.SHMIFEXT_NO_API;
};

// Track whether shmifext_setup(no_context) has been called
var ext_setup_done: bool = false;

// DRM_FORMAT_ARGB8888 — matches shmif's av_pixel (BGRA in memory on LE)
const DRM_FORMAT_ARGB8888: u32 = 0x34325241;

export fn platform_video_map_buffer(
    vs: ?*anyopaque,
    planes: ?*anyopaque,
    n: usize,
) callconv(.c) bool {
    _ = .{ vs, planes, n };
    return false;
}

export fn arcan_shmifext_defaults(con: ?*c.arcan_shmif_cont) callconv(.c) c.struct_arcan_shmifext_setup {
    _ = con;
    return @import("std").mem.zeroes(c.struct_arcan_shmifext_setup);
}

export fn arcan_shmifext_setup(
    con: ?*c.arcan_shmif_cont,
    arg: c.struct_arcan_shmifext_setup,
) callconv(.c) c_int {
    // Support no_context mode for Vulkan DMA-BUF signaling (no EGL needed)
    if (arg.no_context != 0) {
        if (con) |ct| {
            if (ct.privext) |pe| {
                // Clear STATE_NOACCEL to permit handle passing
                pe.*.state_fl = 0;
            }
        }
        ext_setup_done = true;
        return c.SHMIFEXT_OK;
    }
    return c.SHMIFEXT_NO_API;
}

export fn arcan_shmifext_isext(con: ?*c.arcan_shmif_cont) callconv(.c) c_int {
    _ = con;
    return if (ext_setup_done) @as(c_int, 1) else @as(c_int, 0);
}

export fn arcan_shmifext_dev(
    con: ?*c.arcan_shmif_cont,
    dev: ?*usize,
    clone: bool,
) callconv(.c) c_int {
    _ = .{ con, clone };
    if (dev) |d| d.* = 0;
    return -1;
}

export fn arcan_shmifext_free_color(
    con: ?*c.arcan_shmif_cont,
    out: ?*c.struct_shmifext_color_buffer,
) callconv(.c) void {
    _ = .{ con, out };
}

export fn arcan_shmifext_alloc_color(
    con: ?*c.arcan_shmif_cont,
    out: ?*c.struct_shmifext_color_buffer,
) callconv(.c) bool {
    _ = .{ con, out };
    return false;
}

// Real DMA-BUF signal_planes: push fd over socket, send BUFFERSTREAM event, signal.
// No EGL/GL needed — just shmif primitives.
extern fn shmif_platform_pushfd(fd: c_int, epipe: c_int) bool;

export fn arcan_shmifext_signal_planes(
    conn: ?*c.arcan_shmif_cont,
    mask: c_int,
    n_planes: usize,
    planes: ?*c.struct_shmifext_buffer_plane,
) callconv(.c) usize {
    const ct = conn orelse return 0;
    if (n_planes == 0) return 0;
    const p = planes orelse return 0;

    var ev = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @intCast(c.EVENT_EXTERNAL);
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_BUFFERSTREAM;

    for (0..n_planes) |i| {
        const plane = @as([*]c.struct_shmifext_buffer_plane, @ptrCast(p))[i];

        // Push the DMA-BUF fd over the control pipe
        if (!shmif_platform_pushfd(plane.fd, ct.epipe))
            return i;

        // Push fence fd if present
        if (plane.fence > 0) {
            if (shmif_platform_pushfd(plane.fence, ct.epipe)) {
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.flags |= 1;
                _ = std.c.close(plane.fence);
            }
        }

        _ = std.c.close(plane.fd);

        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.stride = @intCast(plane.unnamed_0.gbm.stride);
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.format = @intCast(plane.unnamed_0.gbm.format);
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.mod_lo = @intCast(plane.unnamed_0.gbm.mod_lo);
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.mod_hi = @intCast(plane.unnamed_0.gbm.mod_hi);
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.offset = @intCast(plane.unnamed_0.gbm.offset);
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.width = @intCast(plane.w);
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.height = @intCast(plane.h);
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bstream.left = @intCast(n_planes - i - 1);

        _ = c.arcan_shmif_enqueue(conn, &ev);
    }

    _ = c.arcan_shmif_signal(conn, mask);
    return n_planes;
}

export fn arcan_shmifext_export_image(
    con: ?*c.arcan_shmif_cont,
    display: usize,
    tex_id: usize,
    plane_limit: usize,
    planes: ?*c.struct_shmifext_buffer_plane,
) callconv(.c) usize {
    _ = .{ con, display, tex_id, plane_limit, planes };
    return 0;
}

export fn arcan_shmifext_import_buffer(
    conn: ?*c.arcan_shmif_cont,
    format: c_int,
    planes: ?*c.struct_shmifext_buffer_plane,
    n_planes: usize,
    buffer_plane_sz: usize,
) callconv(.c) bool {
    _ = .{ conn, format, planes, n_planes, buffer_plane_sz };
    return false;
}

export fn platform_video_map_handle(store: ?*anyopaque, handle: i64) callconv(.c) bool {
    _ = .{ store, handle };
    return false;
}

export fn arcan_shmifext_gl_handles(
    con: ?*c.arcan_shmif_cont,
    frame: ?*usize,
    color: ?*usize,
    depth: ?*usize,
) callconv(.c) bool {
    _ = .{ con, frame, color, depth };
    return false;
}

export fn arcan_shmifext_drop(con: ?*c.arcan_shmif_cont) callconv(.c) bool {
    _ = con;
    return false;
}

export fn arcan_shmifext_drop_context(con: ?*c.arcan_shmif_cont) callconv(.c) bool {
    _ = con;
    return false;
}

export fn arcan_shmifext_lookup(
    con: ?*c.arcan_shmif_cont,
    fun: [*c]const u8,
) callconv(.c) ?*anyopaque {
    _ = .{ con, fun };
    return null;
}

export fn arcan_shmifext_make_current(con: ?*c.arcan_shmif_cont) callconv(.c) bool {
    _ = con;
    return false;
}

export fn arcan_shmifext_egl(
    con: ?*c.arcan_shmif_cont,
    display: ?*?*anyopaque,
    lookupfun: ?*const fn (?*anyopaque, [*c]const u8) callconv(.c) ?*anyopaque,
    tag: ?*anyopaque,
) callconv(.c) bool {
    _ = .{ con, display, lookupfun, tag };
    return false;
}

export fn arcan_shmifext_vk(
    con: ?*c.arcan_shmif_cont,
    display: ?*?*anyopaque,
    lookupfun: ?*const fn (?*anyopaque, [*c]const u8) callconv(.c) ?*anyopaque,
    tag: ?*anyopaque,
) callconv(.c) bool {
    _ = .{ con, display, lookupfun, tag };
    return false;
}

export fn arcan_shmifext_swap_context(
    con: ?*c.arcan_shmif_cont,
    context: c_uint,
) callconv(.c) void {
    _ = .{ con, context };
}

export fn arcan_shmifext_add_context(
    con: ?*c.arcan_shmif_cont,
    arg: c.struct_arcan_shmifext_setup,
) callconv(.c) c_uint {
    _ = .{ con, arg };
    return 0;
}

export fn arcan_shmifext_bufferfail(cont: ?*c.arcan_shmif_cont, fl: bool) callconv(.c) void {
    _ = .{ cont, fl };
}

export fn arcan_shmifext_gltex_handle(
    con: ?*c.arcan_shmif_cont,
    display: usize,
    tex_id: usize,
    dhandle: ?*c_int,
    dstride: ?*usize,
    dfmt: ?*c_int,
) callconv(.c) bool {
    _ = .{ con, display, tex_id, dhandle, dstride, dfmt };
    return false;
}

export fn arcan_shmifext_getfenv(con: ?*c.arcan_shmif_cont) callconv(.c) ?*c.struct_agp_fenv {
    _ = con;
    return null;
}

export fn arcan_shmifext_egl_meta(
    con: ?*c.arcan_shmif_cont,
    display: ?*usize,
    surface: ?*usize,
    context: ?*usize,
) callconv(.c) bool {
    _ = .{ con, display, surface, context };
    return false;
}
