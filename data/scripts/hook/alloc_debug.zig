
pub fn __init() void {
    @import("builtin/debug.zig").__init();
    const hijack = struct { fn hijack(sym: anytype) void {
        var old = _G[sym];
        _G[sym] = struct { fn anon(va: anytype) V {
            var res = .{ old(va) };
            if ((type(res[1]) == "number") and valid_vid(res[1])) {
                image_tracetag(res[1], sym ++ (":" ++ debug.traceback()));
            }
            return unpack(res);
        } }.anon;
    } }.hijack;

    for (.{
        "alloc_surface",
        "fill_surface",
        "color_surface",
        "null_surface",
        "random_surface",
        "raw_surface",
        "render_text",
        "target_alloc",
        "accept_target",
        "launch_avfeed",
        "launch_decode",
        "launch_target",
        "load_image",
        "net_listen",
        "load_image_asynch",
        "define_arcantarget",
        "define_calctarget",
        "define_feedtarget",
        "define_linktarget",
        "define_nulltarget",
        "define_recordtarget",
        "define_rendertarget",
        "new_3dmodel",
        "build_3dbox",
        "build_3dplane",
        "build_cylinder",
        "build_pointcloud",
        "build_sphere",
    }, 0..) |v, _| {
        hijack(v);
    }
}
