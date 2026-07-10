// Zig port of posix/fdscan.c
// Scans open file descriptors using poll() and returns a list of valid ones.

const std = @import("std");
const c = std.c;

export fn arcan_fdscan(listout: *?[*]c_int) c_int {
    var rlim: c.rlimit = undefined;
    var lim: usize = 512;
    if (c.getrlimit(.NOFILE, &rlim) == 0) {
        lim = @intCast(rlim.cur);
    }

    const set: [*]c.pollfd = @ptrCast(@alignCast(c.malloc(@sizeOf(c.pollfd) * lim) orelse return -1));
    defer c.free(set);

    for (0..lim) |i| {
        set[i] = .{ .fd = @intCast(i), .events = 0, .revents = 0 };
    }

    if (c.poll(set, @intCast(lim), 0) == -1) {
        return -1;
    }

    var count: usize = 0;
    for (0..lim) |i| {
        if (set[i].revents & std.os.linux.POLL.NVAL == 0) {
            count += 1;
        }
    }

    if (count == 0) return -1;
    const buf: [*]c_int = @ptrCast(@alignCast(c.malloc(@sizeOf(c_int) * count) orelse return -1));

    var pos: usize = 0;
    for (0..lim) |i| {
        if (pos >= count) break;
        if (set[i].revents & std.os.linux.POLL.NVAL == 0 or i < 3) {
            buf[pos] = set[i].fd;
            pos += 1;
        }
    }

    listout.* = buf;
    return @intCast(pos);
}
