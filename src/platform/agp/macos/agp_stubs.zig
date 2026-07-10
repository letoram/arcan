// Minimal stubs for the engine-util symbols the AGP draw/composite layer
// (vk_shared.zig / vk_shdrmgmt.zig) references, so it links standalone on macOS
// without pulling in the full engine (mem.zig / video.zig / arcan_ttf.zig).
// Real engine provides these; for a hardcoded-scene compositor they're trivial.
const std = @import("std");

export fn arcan_alloc_mem(sz: usize, memtype: c_uint, hint: c_uint, alignment: c_uint) ?*anyopaque {
    _ = memtype;
    _ = hint;
    _ = alignment;
    return std.c.malloc(sz);
}
export fn arcan_mem_free(ptr: ?*anyopaque) void {
    std.c.free(ptr);
}
export fn arcan_timemillis() c_longlong {
    return @intCast(std.time.milliTimestamp());
}
export fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void {
    _ = fmt;
}
// Slug font atlas — stubbed (no text rendering in the bring-up scene).
export fn slug_atlas_get_band_data(out_texels: *u32, out_width: *u32) ?[*]const u16 {
    out_texels.* = 0;
    out_width.* = 0;
    return null;
}
export fn slug_atlas_get_curve_data(out_texels: *u32, out_width: *u32) ?[*]const f32 {
    out_texels.* = 0;
    out_width.* = 0;
    return null;
}
export fn slug_atlas_is_dirty() bool {
    return false;
}
export fn slug_atlas_mark_clean() void {}
// Clear color is driven by our cmdBeginRendering; ignore the engine hook.
export fn vk_platform_set_clear_color(r: f32, g: f32, b: f32, a: f32) void {
    _ = r;
    _ = g;
    _ = b;
    _ = a;
}
