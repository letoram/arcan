// Standalone-arcan-exe stubs for symbols that the single-binary (`may`)
// build provides from outside the engine tree. Built ONLY into the
// standalone compositor exe; NOT linked into single-binary builds.
//
//  * frameserver_dispatch — the in-process frameserver personality entry.
//    Standalone builds ship frameservers as separate afsrv_* binaries, so
//    dispatch degrades to exec'ing the chainloader: platform/posix/launch.zig
//    already shapes argv as [RESOURCE_SYS_BINS path, mode, null], which is
//    exactly the upstream exec contract.
//  * cl_env_warmup — MAY-247 compile-server env warmup; no-op here.
//  * ds4_infer_c — DS4-Flash native inference; unavailable, returns -1.
//  * zcs_deep_* — may.zcs deep-view navigation; the documented
//    "unavailable" sentinels (null view / -1 / false).

const std = @import("std");

extern fn execv(pathname: [*c]const u8, argv: [*c][*c]u8) c_int;

export fn frameserver_dispatch(argc: c_int, argv: [*c][*c]u8) c_int {
    _ = argc;
    if (argv != null and argv[0] != null) {
        _ = execv(argv[0], argv);
    }
    std.debug.print("frameserver_dispatch: exec of {s} failed\n", .{
        if (argv != null and argv[0] != null) std.mem.span(@as([*:0]const u8, @ptrCast(argv[0]))) else "(null)",
    });
    return 1;
}

export fn cl_env_warmup() void {}

export fn ds4_infer_c(prompt_ptr: [*]const u8, prompt_len: usize) c_int {
    _ = prompt_ptr;
    _ = prompt_len;
    std.debug.print("ds4.infer: no inference engine in this build\n", .{});
    return -1;
}

export fn zcs_deep_open(base: usize, meta: ?*const anyopaque) ?*anyopaque {
    _ = base;
    _ = meta;
    return null;
}

export fn zcs_deep_nav_name(view: ?*anyopaque, tid: u32, idx: u32, buf: ?[*]u8, buflen: usize) c_long {
    _ = view;
    _ = tid;
    _ = idx;
    _ = buf;
    _ = buflen;
    return -1;
}

export fn zcs_deep_summary(view: ?*anyopaque, out: ?*anyopaque, meta: ?*const anyopaque) bool {
    _ = view;
    _ = out;
    _ = meta;
    return false;
}

export fn zcs_deep_close(view: ?*anyopaque) void {
    _ = view;
}
