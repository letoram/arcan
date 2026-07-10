// Zig port of posix/resource_io.c
// Open/close resource file descriptors.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const c = if (is_freestanding) struct {} else @import("posix");

const BADFD: c_int = -1;

const off_t = if (is_freestanding) i64 else c.off_t;

// data_source matches C struct in platform_types.h
const data_source = extern struct {
    fd: c_int,
    start: off_t,
    len: off_t,
    source: [*c]u8,
};

export fn arcan_release_resource(sptr: *data_source) void {
    if (is_freestanding) return;
    if (sptr.fd != -1) {
        // close, retrying on EINTR
        while (true) {
            const ret = c.close(sptr.fd);
            if (ret != -1 or c.__errno_location().* != c.EINTR) break;
        }
    }

    c.free(sptr.source);
    sptr.source = null;
    sptr.fd = -1;
    sptr.start = -1;
    sptr.len = -1;
}

export fn arcan_open_resource(url: [*c]const u8) data_source {
    if (is_freestanding)
        return data_source{ .fd = BADFD, .start = 0, .len = 0, .source = null };
    var res = data_source{
        .fd = BADFD,
        .start = 0,
        .len = 0,
        .source = null,
    };
    if (url == null) return res;

    res.fd = c.open(url, c.O_RDONLY);
    if (res.fd != -1) {
        res.start = 0;
        res.source = c.strdup(url);
        res.len = 0; // map_resource can figure it out
        _ = c.fcntl(res.fd, c.F_SETFD, c.FD_CLOEXEC);
    }

    return res;
}
