// Zig port of avfeed.c — test/prototyping frameserver
const std = @import("std");
const c = @import("shmif_types");

// libc externs not covered by shmif_types
extern "c" var stdout: *anyopaque;
extern "c" var stderr: *anyopaque;

// shmif functions not yet in shmif_types
extern "c" fn arcan_shmif_signal(ctx: *c.arcan_shmif_cont, mask: c_int) c_uint;
extern "c" fn arcan_shmif_resize(ctx: *c.arcan_shmif_cont, w: usize, h: usize) bool;
extern "c" fn arcan_shmif_wait(ctx: *c.arcan_shmif_cont, ev: *c.arcan_event) c_int;

var red: u8 = 0;

fn update_frame(shms: *c.arcan_shmif_cont, val: u32) void {
    var cptr: [*c]u32 = shms.unnamed_0.vidp;
    const np: usize = shms.w * shms.h;
    for (0..np) |_| {
        cptr.* = val;
        cptr += 1;
    }
    _ = arcan_shmif_signal(shms, c.SHMIF_SIGVID);
}

fn dump_help() void {
    _ = c.fprintf(stdout, "the avfeed- frameserver is primarily intended" ++
        " for testing and prototyping purposes and is not particularly" ++
        " useful on its own.\n");
}

export fn afsrv_avfeed(con: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) callconv(.c) c_int {
    _ = args;
    const con_ptr = con orelse {
        dump_help();
        return 1;
    };
    var shms: c.arcan_shmif_cont = con_ptr.*;

    if (!arcan_shmif_resize(&shms, 320, 200)) {
        _ = c.fprintf(stderr, "arcan_frameserver(decode) shmpage setup, resize failed\n");
        return 1;
    }

    update_frame(&shms, c.SHMIF_RGBA(0xff, 0xff, 0xff, 0xff));
    var ev: c.arcan_event = undefined;

    while (true) {
        while (arcan_shmif_wait(&shms, &ev) != 0) {
            if (ev.unnamed_0.unnamed_0.category == c.EVENT_TARGET) {
                if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_EXIT) {
                    _ = c.fprintf(stdout, "parent requested termination, leaving.\n");
                    return 0;
                } else {
                    update_frame(&shms, c.SHMIF_RGBA(red, 0x00, 0x00, 0xff));
                    red +%= 1;
                }
            }
        }
    }
}
