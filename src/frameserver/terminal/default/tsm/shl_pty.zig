// SHL - PTY Helpers
//
// Copyright (c) 2011-2014 David Herrmann <dh.herrmann@gmail.com>
// Dedicated to the Public Domain
//
// Zig port of shl-pty.c

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ errno.h, fcntl.h, limits.h,
// pty.h, signal.h, stdlib.h, string.h, sys/ioctl.h, sys/uio.h, termios.h,
// unistd.h, shl-ring.h })` block. Keeps the `c.X` spellings used below. Each
// alias routes to the appropriate hand-written replacement module (zero
// `@cImport` left).
const libc = @import("posix");

// shl_ring — the struct lives in shl_ring.zig (same tsm/ directory).
// Redeclare the layout + extern fns here so shl_pty.zig consumes them
// via the dispatch struct. ABI must match shl_ring.zig's exact layout.
// The extern fns are namespaced under `shl_ring_ns` so they don't collide
// with the aliases inside the dispatch struct `c`.
const shl_ring_ns = struct {
    pub const ShlRing = extern struct {
        buf: ?[*]u8 = null,
        size: usize = 0,
        start: usize = 0,
        used: usize = 0,
    };
    pub extern "c" fn shl_ring_clear(r: *ShlRing) void;
    pub extern "c" fn shl_ring_peek(r: *ShlRing, vec: ?[*]libc.struct_iovec) usize;
    pub extern "c" fn shl_ring_pull(r: *ShlRing, size_arg: usize) void;
    pub extern "c" fn shl_ring_push(r: *ShlRing, u8_ptr: ?*const anyopaque, size: usize) c_int;
};

const c = struct {
    // libc — errno / process / memory / pty / termios / signal / ioctl
    pub const __errno_location = libc.__errno_location;
    pub const calloc = libc.calloc;
    pub const close = libc.close;
    pub const dup2 = libc.dup2;
    pub const exit = libc.exit;
    pub const fcntl = libc.fcntl;
    pub const fork = libc.fork;
    pub const free = libc.free;
    pub const grantpt = libc.grantpt;
    pub const ioctl = libc.ioctl;
    pub const malloc = libc.malloc;
    pub const open = libc.open;
    pub const pipe = libc.pipe;
    pub const pid_t = libc.pid_t;
    pub const posix_openpt = libc.posix_openpt;
    pub const ptsname = libc.ptsname;
    pub const read = libc.read;
    pub const setsid = libc.setsid;
    pub const shl_ring = shl_ring_ns.ShlRing;
    pub const shl_ring_clear = shl_ring_ns.shl_ring_clear;
    pub const shl_ring_peek = shl_ring_ns.shl_ring_peek;
    pub const shl_ring_pull = shl_ring_ns.shl_ring_pull;
    pub const shl_ring_push = shl_ring_ns.shl_ring_push;
    pub const sigemptyset = libc.sigemptyset;
    pub const signal = libc.signal;
    pub const sigprocmask = libc.sigprocmask;
    pub const sigset_t = libc.sigset_t;
    pub const struct_iovec = libc.struct_iovec;
    pub const struct_termios = libc.struct_termios;
    pub const struct_winsize = libc.struct_winsize;
    pub const tcgetattr = libc.tcgetattr;
    pub const tcsetattr = libc.tcsetattr;
    pub const unlockpt = libc.unlockpt;
    pub const write = libc.write;
    pub const writev = libc.writev;

    // Constants
    pub const EAGAIN = libc.EAGAIN;
    pub const ECHILD = libc.ECHILD;
    pub const EINTR = libc.EINTR;
    pub const EINVAL = libc.EINVAL;
    pub const ENODEV = libc.ENODEV;
    pub const ENOMEM = libc.ENOMEM;
    pub const EPIPE = libc.EPIPE;
    pub const FD_CLOEXEC = libc.FD_CLOEXEC;
    pub const F_GETFD = libc.F_GETFD;
    pub const F_SETFD = libc.F_SETFD;
    pub const IUTF8 = libc.IUTF8;
    pub const O_CLOEXEC = libc.O_CLOEXEC;
    pub const O_NOCTTY = libc.O_NOCTTY;
    pub const O_RDWR = libc.O_RDWR;
    pub const SIG_SETMASK = libc.SIG_SETMASK;
    pub const STDERR_FILENO = libc.STDERR_FILENO;
    pub const STDIN_FILENO = libc.STDIN_FILENO;
    pub const STDOUT_FILENO = libc.STDOUT_FILENO;
    pub const TCSANOW = libc.TCSANOW;
    pub const TIOCSCTTY = libc.TIOCSCTTY;
    pub const TIOCSIG = libc.TIOCSIG;
    pub const TIOCSWINSZ = libc.TIOCSWINSZ;
    pub const VERASE = libc.VERASE;
};

const SHL_PTY_BUFSIZE = 16384;

const SIGUNUSED = 31;

pub const shl_pty_input_fn = ?*const fn (
    pty: *shl_pty,
    data: ?*anyopaque,
    u8_buf: [*c]u8,
    len: usize,
) callconv(.c) void;

pub const shl_pty = extern struct {
    ref: c_ulong,
    p2c: c_int,
    c2p: c_int,
    pipe: bool,
    child: c.pid_t,
    in_buf: [SHL_PTY_BUFSIZE]u8,
    out_buf: c.shl_ring,

    fn_input: shl_pty_input_fn,
    fn_input_data: ?*anyopaque,
};

const SHL_PTY_FAILED = 0;
const SHL_PTY_SETUP = 1;

/// Reimplementation of shl_ring_get_size (static inline in shl-ring.h,
/// not available through @cImport).
fn shl_ring_get_size(r: *c.shl_ring) usize {
    return r.used;
}

fn getErrno() c_int {
    return c.__errno_location().*;
}

fn pty_recv(fd: c_int) u8 {
    var d: u8 = undefined;
    while (true) {
        const r = c.read(fd, @as(*anyopaque, @ptrCast(&d)), 1);
        if (r < 0) {
            const err = getErrno();
            if (err == c.EINTR or err == c.EAGAIN) continue;
            return SHL_PTY_FAILED;
        }
        if (r <= 0) return SHL_PTY_FAILED;
        return d;
    }
}

fn pty_send(fd: c_int, d: u8) c_int {
    var buf = [_]u8{d};
    while (true) {
        const r = c.write(fd, @as(*const anyopaque, @ptrCast(&buf)), 1);
        if (r < 0) {
            const err = getErrno();
            if (err == c.EINTR or err == c.EAGAIN) continue;
            return -c.EINVAL;
        }
        return if (r == 1) 0 else -c.EINVAL;
    }
}

fn pty_setup_child(
    slave: c_int,
    term_width: c_ushort,
    term_height: c_ushort,
    stderr_fileno: c_int,
) c_int {
    var attr: c.struct_termios = undefined;

    // get terminal attributes
    if (c.tcgetattr(slave, &attr) < 0)
        return -getErrno();

    // erase character should be normal backspace
    attr.c_cc[c.VERASE] = 0o10;
    // always set UTF8 flag
    attr.c_iflag |= c.IUTF8;

    // set changed terminal attributes
    if (c.tcsetattr(slave, c.TCSANOW, &attr) < 0)
        return -getErrno();

    var ws: c.struct_winsize = std.mem.zeroes(c.struct_winsize);
    ws.ws_col = term_width;
    ws.ws_row = term_height;

    if (c.ioctl(slave, c.TIOCSWINSZ, &ws) < 0)
        return -getErrno();

    // if a stderr fileno is provided, then dup that into the slot
    const stderr_fd = if (stderr_fileno != 0) stderr_fileno else slave;
    if (c.dup2(slave, c.STDIN_FILENO) != c.STDIN_FILENO or
        c.dup2(slave, c.STDOUT_FILENO) != c.STDOUT_FILENO or
        c.dup2(stderr_fd, c.STDERR_FILENO) != c.STDERR_FILENO)
        return -getErrno();

    return 0;
}

fn pty_init_child(fd: c_int) c_int {
    var sigset: c.sigset_t = undefined;

    // unlockpt() requires unset signal-handlers
    _ = c.sigemptyset(&sigset);
    const r = c.sigprocmask(c.SIG_SETMASK, &sigset, null);
    if (r < 0)
        return -getErrno();

    {
        var i: c_int = 1;
        while (i < SIGUNUSED) : (i += 1) {
            _ = c.signal(i, null); // SIG_DFL = (void(*)(int))0
        }
    }

    if (c.grantpt(fd) < 0)
        return -getErrno();

    if (c.unlockpt(fd) < 0)
        return -getErrno();

    const slave_name = c.ptsname(fd);
    if (slave_name == null)
        return -getErrno();

    // open slave-TTY
    const slave = c.open(slave_name, c.O_RDWR | c.O_CLOEXEC | c.O_NOCTTY);
    if (slave < 0)
        return -getErrno();

    // open session so we lose our controlling TTY
    const pid = c.setsid();
    if (pid < 0) {
        _ = c.close(slave);
        return -getErrno();
    }

    // set controlling TTY
    if (c.ioctl(slave, c.TIOCSCTTY, @as(c_int, 0)) < 0) {
        _ = c.close(slave);
        return -getErrno();
    }

    return slave;
}

fn pty_write(pty: *shl_pty) c_int {
    var vec: [2]c.struct_iovec = undefined;

    // Edge-triggered: call write() until all data written or EAGAIN.
    // Call twice; if still data left, return -EAGAIN.
    var i: c_uint = 0;
    while (i < 2) : (i += 1) {
        const num = c.shl_ring_peek(&pty.out_buf, &vec);
        if (num == 0)
            return 0;

        const r = c.writev(pty.p2c, &vec, @as(c_int, @intCast(num)));
        if (r < 0) {
            const err = getErrno();
            if (err == c.EAGAIN)
                return 0;
            if (err == c.EINTR)
                return -c.EAGAIN;
            return -err;
        } else if (r == 0) {
            return -c.EPIPE;
        } else {
            c.shl_ring_pull(&pty.out_buf, @as(usize, @intCast(r)));
        }
    }

    return if (shl_ring_get_size(&pty.out_buf) > 0) -c.EAGAIN else 0;
}

fn pty_read(pty: *shl_pty) c_int {
    var nr: usize = 0;

    // Edge-triggered: read whole queue. Read twice; if second still returned
    // data, return -EAGAIN.
    var i: c_uint = 0;
    while (i < 2) : (i += 1) {
        const len = c.read(pty.c2p, @as(*anyopaque, @ptrCast(&pty.in_buf)), SHL_PTY_BUFSIZE - 1);
        if (len < 0) {
            const err = getErrno();
            if (err == c.EAGAIN)
                return 0;
            if (err == c.EINTR)
                return 0;
            return -err;
        } else if (len == 0) {
            return -c.EPIPE;
        } else if (len > 0) {
            if (pty.fn_input) |input_fn| {
                // set terminating zero for debugging safety
                pty.in_buf[@as(usize, @intCast(len))] = 0;
                input_fn(
                    pty,
                    pty.fn_input_data,
                    &pty.in_buf,
                    @as(usize, @intCast(len)),
                );
                nr += @as(usize, @intCast(len));
            }
        }
    }

    return @as(c_int, @intCast(nr));
}

// -- Public exported functions --

export fn shl_pipe_open(out: *?*shl_pty, alloc: bool) callconv(.c) c.pid_t {
    const fakepty: ?*shl_pty = @ptrCast(@alignCast(c.malloc(@sizeOf(shl_pty))));
    if (fakepty == null)
        return -1;

    const pty = fakepty.?;
    pty.* = std.mem.zeroes(shl_pty);
    pty.p2c = -1;
    pty.c2p = -1;
    pty.pipe = true;

    // just copy and cloexec
    if (!alloc) {
        pty.p2c = c.STDOUT_FILENO;
        pty.c2p = c.STDIN_FILENO;
        out.* = pty;
        return c.fork();
    }

    // build pipe-pair (0 == read_end)
    var fdarg_c2p: [2]c_int = undefined;
    var fdarg_p2c: [2]c_int = undefined;

    // grab the pipe pairs that will be inherited into the child
    if (c.pipe(&fdarg_c2p) == -1) {
        return -1;
    }

    if (c.pipe(&fdarg_p2c) == -1) {
        _ = c.close(fdarg_c2p[0]);
        _ = c.close(fdarg_c2p[1]);
        return -1;
    }

    const res = c.fork();
    if (res == 0) {
        // child
        _ = c.close(fdarg_c2p[0]);
        _ = c.close(fdarg_p2c[1]);
        _ = c.dup2(fdarg_c2p[1], c.STDOUT_FILENO);
        _ = c.dup2(fdarg_p2c[0], c.STDIN_FILENO);
        _ = c.close(fdarg_p2c[1]);
        _ = c.close(fdarg_c2p[0]);
        // call works like fork() from the outside so no more actions here
        return 0;
    } else if (res == -1) {
        _ = c.close(fdarg_c2p[0]);
        _ = c.close(fdarg_c2p[1]);
        _ = c.close(fdarg_p2c[0]);
        _ = c.close(fdarg_p2c[1]);
        return -1;
    }

    // server-end
    pty.c2p = fdarg_c2p[0];
    _ = c.close(fdarg_c2p[1]);
    pty.p2c = fdarg_p2c[1];
    _ = c.close(fdarg_p2c[0]);
    out.* = pty;
    return res;
}

export fn shl_pty_open(
    out: *?*shl_pty,
    fn_input: shl_pty_input_fn,
    fn_input_data: ?*anyopaque,
    term_width: c_ushort,
    term_height: c_ushort,
    stderr_fileno: c_int,
) callconv(.c) c.pid_t {
    // In C, `_shl_pty_unref_` and `_shl_close_` are GCC cleanup attributes.
    // In Zig we handle cleanup explicitly.
    var pty_ptr: ?*shl_pty = null;
    var fd: c_int = -1;

    // cleanup helper — called on every early return path in the parent
    const cleanup = struct {
        fn do_cleanup(p: *?*shl_pty, f: *c_int) void {
            if (f.* >= 0) {
                _ = c.close(f.*);
                f.* = -1;
            }
            if (p.*) |pp| {
                shl_pty_unref(pp);
                p.* = null;
            }
        }
    };

    if (@intFromPtr(out) == 0)
        return -c.EINVAL;

    const raw_ptr = c.calloc(1, @sizeOf(shl_pty));
    if (raw_ptr == null)
        return -c.ENOMEM;
    pty_ptr = @ptrCast(@alignCast(raw_ptr));
    const pty = pty_ptr.?;

    pty.ref = 1;
    pty.p2c = -1;
    pty.c2p = -1;
    pty.fn_input = fn_input;
    pty.fn_input_data = fn_input_data;

    fd = c.posix_openpt(c.O_RDWR | c.O_NOCTTY);
    if (fd < 0) {
        const ret = -getErrno();
        cleanup.do_cleanup(&pty_ptr, &fd);
        return ret;
    }

    _ = c.fcntl(fd, c.F_GETFD);

    var comm: [2]c_int = undefined;
    const r = c.pipe(&comm);
    if (r < 0) {
        const ret = -getErrno();
        cleanup.do_cleanup(&pty_ptr, &fd);
        return ret;
    }

    _ = c.fcntl(comm[0], c.F_SETFD, c.FD_CLOEXEC);
    _ = c.fcntl(comm[1], c.F_SETFD, c.FD_CLOEXEC);

    const pid = c.fork();
    if (pid < 0) {
        // error
        const ret = -getErrno();
        _ = c.close(comm[0]);
        _ = c.close(comm[1]);
        cleanup.do_cleanup(&pty_ptr, &fd);
        return ret;
    } else if (pid == 0) {
        // child
        const slave = pty_init_child(fd);
        if (slave < 0)
            c.exit(1);

        _ = c.close(comm[0]);
        _ = c.close(fd);
        // fd = -1 (local, no cleanup needed in child)
        c.free(@as(*anyopaque, @ptrCast(pty)));
        // pty_ptr = null (local, no cleanup needed in child)

        const setup_r = pty_setup_child(slave, term_width, term_height, stderr_fileno);
        if (setup_r < 0)
            c.exit(1);

        // close slave if it's not one of the std-fds
        if (slave > 2)
            _ = c.close(slave);

        // wake parent
        _ = pty_send(comm[1], SHL_PTY_SETUP);
        _ = c.close(comm[1]);

        out.* = null;
        return pid;
    }

    // parent
    pty.p2c = fd;
    pty.c2p = fd;
    pty.child = pid;

    _ = c.close(comm[1]);
    fd = -1;

    // wait for child setup
    const d = pty_recv(comm[0]);
    _ = c.close(comm[0]);
    if (d != SHL_PTY_SETUP) {
        cleanup.do_cleanup(&pty_ptr, &fd);
        return -c.EINVAL;
    }

    out.* = pty;
    pty_ptr = null; // prevent cleanup from freeing it
    return pid;
}

export fn shl_pty_ref(pty: ?*shl_pty) callconv(.c) void {
    if (pty == null) return;
    const p = pty.?;
    if (p.ref == 0) return;
    p.ref += 1;
}

export fn shl_pty_unref(pty: ?*shl_pty) callconv(.c) void {
    if (pty == null) return;
    const p = pty.?;
    if (p.ref == 0) return;
    p.ref -= 1;
    if (p.ref != 0) return;

    shl_pty_close(p);
    c.shl_ring_clear(&p.out_buf);
    c.free(@as(*anyopaque, @ptrCast(p)));
}

export fn shl_pty_close(pty: ?*shl_pty) callconv(.c) void {
    if (pty == null) return;
    const p = pty.?;
    if (p.p2c < 0) return;

    if (p.p2c != -1 and p.p2c > c.STDOUT_FILENO)
        _ = c.close(p.p2c);

    p.p2c = -1;

    if (p.c2p != -1 and p.c2p > c.STDOUT_FILENO)
        _ = c.close(p.c2p);

    p.c2p = -1;
}

export fn shl_pty_is_open(pty: ?*shl_pty) callconv(.c) bool {
    if (pty == null) return false;
    return pty.?.p2c >= 0;
}

export fn shl_pty_get_fd(pty: ?*shl_pty, do_write: bool) callconv(.c) c_int {
    if (pty == null)
        return -c.EINVAL;

    const p = pty.?;
    if (do_write) {
        return if (p.p2c >= 0) p.p2c else -c.EPIPE;
    }
    return if (p.c2p >= 0) p.c2p else -c.EPIPE;
}

export fn shl_pty_get_child(pty: ?*shl_pty) callconv(.c) c.pid_t {
    if (pty == null)
        return -c.EINVAL;

    const p = pty.?;
    return if (p.child > 0) p.child else -c.ECHILD;
}

export fn shl_pty_dispatch(pty: ?*shl_pty) callconv(.c) c_int {
    if (!shl_pty_is_open(pty))
        return -c.ENODEV;

    _ = pty_write(pty.?);
    return 0;
}

export fn shl_pty_write(pty: ?*shl_pty, u8_buf: [*c]const u8, len: usize) callconv(.c) c_int {
    if (!shl_pty_is_open(pty))
        return -c.ENODEV;

    const p = pty.?;
    const rv = c.shl_ring_push(&p.out_buf, @as(*const anyopaque, @ptrCast(u8_buf)), len);
    _ = pty_write(p);
    return rv;
}

export fn shl_pty_signal(pty: ?*shl_pty, sig: c_int) callconv(.c) c_int {
    if (!shl_pty_is_open(pty))
        return -c.ENODEV;

    const p = pty.?;

    // ignore the signal, we have no guarantee that the pid_t owns the fds anymore
    if (p.pipe)
        return 0;

    return if (c.ioctl(p.p2c, c.TIOCSIG, sig) < 0) -getErrno() else 0;
}

export fn shl_pty_resize(
    pty: ?*shl_pty,
    term_width: c_ushort,
    term_height: c_ushort,
) callconv(.c) c_int {
    if (!shl_pty_is_open(pty))
        return -c.ENODEV;

    const p = pty.?;

    if (p.pipe)
        return 0;

    var ws: c.struct_winsize = std.mem.zeroes(c.struct_winsize);
    ws.ws_col = term_width;
    ws.ws_row = term_height;

    // This will send SIGWINCH to the pty slave foreground process group.
    // We will also get one, but we don't need it.
    return if (c.ioctl(p.p2c, c.TIOCSWINSZ, &ws) < 0) -getErrno() else 0;
}
