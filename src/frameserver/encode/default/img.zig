// Zig port of img.c — PNG stream output mode for encode frameserver
const std = @import("std");
const shmif = @import("shmif_types");
const libc = @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const FILE = libc.FILE;
    pub const arg_arr = shmif.arg_arr;
    pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
    pub const arcan_event = shmif.arcan_event;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arcan_shmif_wait = shmif.arcan_shmif_wait;
    pub const arcan_shmif_signal = shmif.arcan_shmif_signal;
    pub const arcan_shmif_drop = shmif.arcan_shmif_drop;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const TARGET_COMMAND_STEPFRAME = shmif.TARGET_COMMAND_STEPFRAME;
    pub const SHMIF_SIGVID = shmif.SHMIF_SIGVID;
    pub const fopen = libc.fopen;
    pub const fclose = libc.fclose;
    pub const fprintf = libc.fprintf;
    // Re-declare extern var (see encode.zig comment).
    pub extern "c" var stderr: *libc.FILE;
    pub const strtoul = libc.strtoul;
};

extern "c" fn arcan_img_outpng(
    dst: *c.FILE,
    inbuf: [*c]u32,
    inw: usize,
    inh: usize,
    vflip: bool,
) i8;

export fn png_stream_run(args: ?*c.arg_arr, cont: c.arcan_shmif_cont) callconv(.c) void {
    var local = cont;
    var prefix: [*c]const u8 = "./";
    var skip: usize = 0;
    var count: usize = 0;
    var limit: usize = 0;
    var str: [*c]const u8 = null;

    if (c.arg_lookup(args, "prefix", 0, &str) and str != null) {
        prefix = str;
    }
    str = null;
    if (c.arg_lookup(args, "limit", 0, &str) and str != null) {
        limit = c.strtoul(str, null, 10);
    }
    str = null;
    if (c.arg_lookup(args, "skip", 0, &str) and str != null) {
        skip = c.strtoul(str, null, 10);
    }

    var ev: c.arcan_event = undefined;
    loop: while (c.arcan_shmif_wait(&local, &ev) != 0) {
        if (ev.unnamed_0.unnamed_0.category != c.EVENT_TARGET)
            continue;

        switch (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind) {
            c.TARGET_COMMAND_STEPFRAME => {
                if (skip > 0) {
                    _ = c.arcan_shmif_signal(&local, c.SHMIF_SIGVID);
                    skip -= 1;
                    continue;
                }

                count += 1;
                var fnbuf: [4096]u8 = undefined;
                const fname = std.fmt.bufPrintZ(&fnbuf, "{s}{d:0>4}.png", .{
                    std.mem.span(prefix), count,
                }) catch continue;

                const fout = c.fopen(fname.ptr, "w+") orelse {
                    _ = c.fprintf(c.stderr, "(encode-png) couldn't open %s for writing\n", fname.ptr);
                    continue;
                };

                _ = arcan_img_outpng(fout, local.unnamed_0.vidp, local.w, local.h, false);
                _ = c.arcan_shmif_signal(&local, c.SHMIF_SIGVID);
                _ = c.fclose(fout);

                if (limit > 0 and count == limit)
                    break :loop;
            },
            else => {},
        }
    }

    c.arcan_shmif_drop(&local);
}
