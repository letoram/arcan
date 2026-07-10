// Zig port of remoting.c — remoting frameserver dispatcher
const std = @import("std");
const shmif = @import("shmif_types");
const libc = @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
    pub const arg_arr = shmif.arg_arr;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arcan_shmif_last_words = shmif.arcan_shmif_last_words;
    pub const fprintf = libc.fprintf;
    // Re-declare extern var (see encode.zig comment).
    pub extern "c" var stderr: *libc.FILE;
};

extern "c" fn run_a12(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) c_int;

export fn afsrv_remoting(con: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) callconv(.c) c_int {
    if (con == null) return 1;

    var protocol: [*c]const u8 = null;
    _ = c.arg_lookup(args, "protocol", 0, &protocol);

    if (protocol == null) {
        c.arcan_shmif_last_words(con, "Arcan was not built with VNC support");
        _ = c.fprintf(c.stderr, "VNC protocol disabled\n");
        return 1;
    }

    const proto = std.mem.span(protocol.?);
    if (std.ascii.eqlIgnoreCase(proto, "vnc")) {
        c.arcan_shmif_last_words(con, "Arcan was not built with VNC support");
        _ = c.fprintf(c.stderr, "VNC protocol disabled\n");
        return 1;
    } else if (std.ascii.eqlIgnoreCase(proto, "a12")) {
        return run_a12(con, args);
    } else {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buf, "Unknown protocol ({s})", .{proto}) catch "Unknown protocol";
        c.arcan_shmif_last_words(con, msg.ptr);
        _ = c.fprintf(c.stderr, "%s", msg.ptr);
        return 1;
    }
}
