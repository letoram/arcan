const std = @import("std");
const libc = @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const off_t = libc.off_t;
    pub const mmap = libc.mmap;
    pub const munmap = libc.munmap;
    pub const dup = libc.dup;
    pub const fcntl = libc.fcntl;
    pub const __errno_location = libc.__errno_location;
    pub const EINTR = libc.EINTR;
    pub const F_GETFD = libc.F_GETFD;
    pub const F_SETFD = libc.F_SETFD;
    pub const FD_CLOEXEC = libc.FD_CLOEXEC;
};

export fn a12int_mmap(
    addr: ?*anyopaque,
    len: usize,
    prot: c_int,
    flags: c_int,
    fildes: c_int,
    off: c.off_t,
) ?*anyopaque {
    return c.mmap(addr, len, prot, flags, fildes, off);
}

export fn a12int_munmap(addr: ?*anyopaque, len: usize) c_int {
    return c.munmap(addr, len);
}

export fn a12int_dupfd(fd: c_int) c_int {
    if (fd == -1)
        return -1;

    var rfd: c_int = -1;
    while (true) {
        rfd = c.dup(fd);
        if (rfd != -1) break;
        if (c.__errno_location().* != c.EINTR) break;
    }

    if (rfd == -1)
        return -1;

    const flags = c.fcntl(rfd, c.F_GETFD);
    if (flags != -1) {
        _ = c.fcntl(rfd, c.F_SETFD, @as(c_int, flags | c.FD_CLOEXEC));
    }

    return rfd;
}
