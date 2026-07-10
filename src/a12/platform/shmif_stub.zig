// Zig port of shmif-stub.c — stub implementations when building a12 without shmif
// Uses @cVaStart — requires use_llvm=false (addShmifZigSourceNoLlvm) on Zig 0.15.
const std = @import("std");

const shmif = @import("shmif_types");
const libc = @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
    pub const arcan_event = shmif.arcan_event;
    pub const struct_shmif_resize_ext = shmif.struct_shmif_resize_ext;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const TARGET_COMMAND_STORE = shmif.TARGET_COMMAND_STORE;
    pub const TARGET_COMMAND_RESTORE = shmif.TARGET_COMMAND_RESTORE;
    pub const TARGET_COMMAND_DEVICE_NODE = shmif.TARGET_COMMAND_DEVICE_NODE;
    pub const TARGET_COMMAND_FONTHINT = shmif.TARGET_COMMAND_FONTHINT;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_NEWSEGMENT = shmif.TARGET_COMMAND_NEWSEGMENT;
    pub const stderr = libc.stderr;
    pub const fprintf = libc.fprintf;
    pub const exit = libc.exit;
};

const BADFD: c_int = -1;

const VaList = std.builtin.VaList;
extern "c" fn vfprintf(stream: *anyopaque, fmt: [*:0]const u8, ap: VaList) c_int;

fn stub_fail() noreturn {
    @export(arcan_fatal, .{ .name = "arcan_fatal" });
    arcan_fatal("Shmif-less build must use a12_set_destination_raw instead of a12_set_destination");
    unreachable;
}

fn arcan_fatal(msg: [*:0]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    _ = vfprintf(c.stderr, msg, ap);
    _ = c.fprintf(c.stderr, "\n");
    c.exit(1);
}

export fn arcan_shmif_resize_ext(
    cont: ?*c.arcan_shmif_cont,
    width: c_uint,
    height: c_uint,
    ext: c.struct_shmif_resize_ext,
) callconv(.c) bool {
    _ = .{ cont, width, height, ext };
    stub_fail();
}

export fn arcan_shmif_resize(
    cont: ?*c.arcan_shmif_cont,
    width: c_uint,
    height: c_uint,
) callconv(.c) bool {
    _ = .{ cont, width, height };
    stub_fail();
}

export fn arcan_shmif_signal(cont: ?*c.arcan_shmif_cont, x: c_int) callconv(.c) c_uint {
    _ = .{ cont, x };
    stub_fail();
}

export fn arcan_shmif_descrevent(ev: ?*c.arcan_event) callconv(.c) bool {
    const e = ev orelse return false;
    if (e.unnamed_0.unnamed_0.category != c.EVENT_TARGET)
        return false;

    const list = [_]c_uint{
        c.TARGET_COMMAND_STORE,
        c.TARGET_COMMAND_RESTORE,
        c.TARGET_COMMAND_DEVICE_NODE,
        c.TARGET_COMMAND_FONTHINT,
        c.TARGET_COMMAND_BCHUNK_IN,
        c.TARGET_COMMAND_BCHUNK_OUT,
        c.TARGET_COMMAND_NEWSEGMENT,
    };

    for (list) |cmd| {
        if (e.unnamed_0.unnamed_0.unnamed_0.tgt.kind == @as(c_int, @intCast(cmd)) and
            e.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv != BADFD)
            return true;
    }

    return false;
}
