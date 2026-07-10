// Zig port of posix/psep_open.c
// Privilege-separated device opener for Linux (DRM/TTY).
// Manages a parent process that opens privileged devices on behalf of the child
// (compositor), handles VT switching, netlink hotplug, and watchdog monitoring.

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ ... })` block. Keeps the
// `c.X` spellings used below. libc routes to `posix_libc`; linux-kernel
// UAPI types (linux/kd.h / linux/vt.h / linux/netlink.h / sys/fsuid.h /
// sys/resource.h) are hand-declared inline since no other Zig consumer
// needs them.

const libc = @import("posix");

// linux-kernel + BSD-ish uapi types not in posix_libc.
const psep_uapi = struct {
    // linux/vt.h — VT console control.
    pub const VT_ACKACQ: c_int = 2;
    pub const VT_ACTIVATE: c_ulong = 0x5606;
    pub const VT_RELDISP: c_ulong = 0x5605;
    pub const VT_SETMODE: c_ulong = 0x5602;
    pub const VT_PROCESS: c_char = 1;

    // struct vt_mode — VT_SETMODE payload.
    pub const struct_vt_mode = extern struct {
        mode: c_char = 0,
        waitv: c_char = 0,
        relsig: c_short = 0,
        acqsig: c_short = 0,
        frsig: c_short = 0,
    };

    // linux/kd.h — keyboard / console.
    pub const KDGETLED: c_ulong = 0x4B31;
    pub const KDSETLED: c_ulong = 0x4B32;
    pub const KDGKBMODE: c_ulong = 0x4B44;
    pub const KDSKBMODE: c_ulong = 0x4B45;
    pub const KDGETMODE: c_ulong = 0x4B3B;
    pub const KDSETMODE: c_ulong = 0x4B3A;
    pub const K_OFF: c_ulong = 0x04;
    pub const K_XLATE: c_ulong = 0x01;
    pub const KD_GRAPHICS: c_int = 0x01;
    pub const KD_TEXT: c_int = 0x00;

    // sys/param.h — MAXPATHLEN usually resolves to 4096 on Linux.
    pub const MAXPATHLEN: usize = 4096;

    // signal — typed struct_sigaction the worker can populate directly.
    // The opaque version in posix_libc doesn't expose sa_handler / sa_flags.
    // Layout matches glibc/aarch64 Linux; musl uses a smaller sigset_t but
    // Linux libc accepts the larger struct (reads only header fields it needs).
    pub const sighandler_t = *align(1) const fn (c_int) callconv(.c) void;
    // sa_sigaction handlers in this file are typed `fn(c_int, [*c]siginfo_t, ?*anyopaque)`.
    pub const sigaction_t = *align(1) const fn (c_int, [*c]siginfo_t, ?*anyopaque) callconv(.c) void;
    pub const struct_sigaction = extern struct {
        // union { void (*sa_handler)(int); void (*sa_sigaction)(int, ...); }
        handler: extern union {
            sa_handler: ?sighandler_t,
            sa_sigaction: ?sigaction_t,
            // sentinel slot so SIG_IGN/SIG_DFL (small integers) can fit.
            sentinel: usize,
        } = .{ .sentinel = 0 },
        sa_mask: [128]u8 align(@alignOf(usize)) = std.mem.zeroes([128]u8),
        sa_flags: c_int = 0,
        sa_restorer: ?*const fn () callconv(.c) void = null,
    };

    // signals
    pub const SIGHUP: c_int = 1;
    pub const SIGINT: c_int = 2;
    pub const SIGQUIT: c_int = 3;
    pub const SIGILL: c_int = 4;
    pub const SIGTRAP: c_int = 5;
    pub const SIGABRT: c_int = 6;
    pub const SIGFPE: c_int = 8;
    pub const SIGKILL: c_int = 9;
    pub const SIGUSR1: c_int = 10;
    pub const SIGSEGV: c_int = 11;
    pub const SIGUSR2: c_int = 12;
    pub const SIGPIPE: c_int = 13;
    pub const SIGALRM: c_int = 14;
    pub const SIGTERM: c_int = 15;
    pub const SIGCHLD: c_int = 17;
    pub const SIGCONT: c_int = 18;
    pub const SIGSTOP: c_int = 19;
    pub const SIGTSTP: c_int = 20;
    pub const SIGTTIN: c_int = 21;
    pub const SIGTTOU: c_int = 22;
    pub const SA_SIGINFO: c_int = 4;

    // poll.h extras
    pub const nfds_t = c_ulong;

    pub extern "c" fn sigaction(
        signum: c_int,
        act: ?*const struct_sigaction,
        oldact: ?*struct_sigaction,
    ) c_int;

    // siginfo_t — opaque enough for our use (handlers only read sig/pid/uid).
    pub const siginfo_t = extern struct {
        _data: [128]u8 align(@alignOf(usize)) = std.mem.zeroes([128]u8),
    };

    // unistd / getuid etc.
    pub const uid_t = c_uint;
    pub const gid_t = c_uint;
    pub const pid_t = c_int;

    pub extern "c" fn getuid() uid_t;
    pub extern "c" fn geteuid() uid_t;
    pub extern "c" fn getgid() gid_t;
    pub extern "c" fn getegid() gid_t;
    pub extern "c" fn setuid(uid: uid_t) c_int;
    pub extern "c" fn seteuid(uid: uid_t) c_int;
    pub extern "c" fn setgid(gid: gid_t) c_int;
    pub extern "c" fn setegid(gid: gid_t) c_int;
    pub extern "c" fn setgroups(size: usize, list: [*c]const gid_t) c_int;
    pub extern "c" fn getgroups(size: c_int, list: [*c]gid_t) c_int;
    pub extern "c" fn setfsuid(uid: uid_t) c_int;
    pub extern "c" fn setfsgid(gid: gid_t) c_int;

    // process control
    pub extern "c" fn waitpid(pid: pid_t, wstatus: *c_int, options: c_int) pid_t;
    pub extern "c" fn kill(pid: pid_t, sig: c_int) c_int;
    pub const WNOHANG: c_int = 1;
    pub fn WIFEXITED(status: c_int) bool {
        return (status & 0x7f) == 0;
    }
    pub fn WIFSIGNALED(status: c_int) bool {
        const lo: c_int = @bitCast(@as(c_int, @intCast((@as(u32, @bitCast(status)) & 0x7f) + 1)) >> 1);
        return lo > 0;
    }
    pub fn WEXITSTATUS(status: c_int) c_int {
        return (status & 0xff00) >> 8;
    }

    // sys/resource.h
    pub const PRIO_PROCESS: c_int = 0;
    pub extern "c" fn setpriority(which: c_int, who: c_int, prio: c_int) c_int;

    // ctype
    pub extern "c" fn isprint(ch: c_int) c_int;

    // linux/netlink.h — struct sockaddr_nl + constants used by the hotplug
    // netlink socket.
    pub const AF_NETLINK: c_int = 16;
    pub const SOCK_RAW: c_int = 3;
    pub const NETLINK_KOBJECT_UEVENT: c_int = 15;
    pub const RTMGRP_LINK: c_int = 1;
    pub const RTMGRP_IPV4_IFADDR: c_int = 0x10;

    pub const struct_sockaddr_nl = extern struct {
        nl_family: c_ushort = 0,
        nl_pad: c_ushort = 0,
        nl_pid: u32 = 0,
        nl_groups: u32 = 0,
    };

    // struct ucred — SO_PEERCRED / SCM_CREDENTIALS payload.
    pub const struct_ucred = extern struct {
        pid: pid_t = 0,
        uid: uid_t = 0,
        gid: gid_t = 0,
    };

    // CMSG_SPACE — size of a cmsg carrying `len` bytes of payload. The
    // kernel defines this as ALIGN(cmsghdr) + ALIGN(len); on Linux the
    // alignment is sizeof(size_t).
    pub fn CMSG_SPACE(len: usize) usize {
        const align_sz: usize = @sizeOf(usize);
        const mask: usize = ~(align_sz - 1);
        const header_aligned = (@sizeOf(libc.struct_cmsghdr) + align_sz - 1) & mask;
        const payload_aligned = (len + align_sz - 1) & mask;
        return header_aligned + payload_aligned;
    }

    pub const MSG_TRUNC: c_int = 0x20;

    // socket extras
    pub const AF_LOCAL: c_int = 1;
    pub const PF_UNSPEC: c_int = 0;
    pub const SOCK_STREAM: c_int = 1;

    // stdio
    pub const EXIT_FAILURE: c_int = 1;
    pub const S_IFCHR: c_uint = 0o020000;

    // libdrm entry points
    pub extern "c" fn drmDropMaster(fd: c_int) c_int;
    pub extern "c" fn drmSetMaster(fd: c_int) c_int;

    // string.h extras
    pub extern "c" fn strstr(haystack: [*c]const u8, needle: [*c]const u8) [*c]u8;
};

const c = struct {
    // libc — unistd + fcntl + stdlib.
    pub const close = libc.close;
    pub const fcntl = libc.fcntl;
    pub const read = libc.read;
    pub const write = libc.write;
    pub const open = libc.open;
    pub const poll = libc.poll;
    pub const bind = libc.bind;
    pub const socket = libc.socket;
    pub const socketpair = libc.socketpair;
    pub const ioctl = libc.ioctl;
    pub const fork = libc.fork;
    pub const setsid = libc.setsid;
    pub const _exit = libc._exit;
    pub const getenv = libc.getenv;
    pub const recvmsg = libc.recvmsg;
    pub const strcmp = libc.strcmp;
    pub const strlen = libc.strlen;
    pub const strncmp = libc.strncmp;
    pub const stat = libc.stat;
    pub const struct_stat = libc.struct_stat;
    pub const struct_iovec = libc.struct_iovec;
    pub const struct_msghdr = libc.struct_msghdr;
    pub const struct_cmsghdr = libc.struct_cmsghdr;
    pub const struct_pollfd = libc.struct_pollfd;
    pub const struct_sockaddr = libc.struct_sockaddr;
    pub const _errno = libc.__errno_location;

    pub const F_GETFD = libc.F_GETFD;
    pub const F_SETFD = libc.F_SETFD;
    pub const F_SETFL = libc.F_SETFL;
    pub const FD_CLOEXEC = libc.FD_CLOEXEC;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const O_RDWR = libc.O_RDWR;
    pub const EAGAIN = libc.EAGAIN;
    pub const EINTR = libc.EINTR;
    pub const POLLIN = libc.POLLIN;
    pub const POLLERR = libc.POLLERR;
    pub const POLLHUP = libc.POLLHUP;
    pub const POLLNVAL = libc.POLLNVAL;
    pub const STDOUT_FILENO = libc.STDOUT_FILENO;
    pub const STDERR_FILENO = libc.STDERR_FILENO;

    // uapi / kernel
    pub const VT_ACKACQ = psep_uapi.VT_ACKACQ;
    pub const VT_ACTIVATE = psep_uapi.VT_ACTIVATE;
    pub const VT_RELDISP = psep_uapi.VT_RELDISP;
    pub const VT_SETMODE = psep_uapi.VT_SETMODE;
    pub const VT_PROCESS = psep_uapi.VT_PROCESS;
    pub const struct_vt_mode = psep_uapi.struct_vt_mode;
    pub const KDGETLED = psep_uapi.KDGETLED;
    pub const KDSETLED = psep_uapi.KDSETLED;
    pub const KDGKBMODE = psep_uapi.KDGKBMODE;
    pub const KDSKBMODE = psep_uapi.KDSKBMODE;
    pub const KDGETMODE = psep_uapi.KDGETMODE;
    pub const KDSETMODE = psep_uapi.KDSETMODE;
    pub const K_OFF = psep_uapi.K_OFF;
    pub const K_XLATE = psep_uapi.K_XLATE;
    pub const KD_GRAPHICS = psep_uapi.KD_GRAPHICS;
    pub const KD_TEXT = psep_uapi.KD_TEXT;

    pub const MAXPATHLEN = psep_uapi.MAXPATHLEN;
    pub const EXIT_FAILURE = psep_uapi.EXIT_FAILURE;
    pub const S_IFCHR = psep_uapi.S_IFCHR;

    // signals
    pub const struct_sigaction = psep_uapi.struct_sigaction;
    pub const siginfo_t = psep_uapi.siginfo_t;
    pub const sigaction = psep_uapi.sigaction;
    pub const SA_SIGINFO = psep_uapi.SA_SIGINFO;
    pub const SIGHUP = psep_uapi.SIGHUP;
    pub const SIGINT = psep_uapi.SIGINT;
    pub const SIGQUIT = psep_uapi.SIGQUIT;
    pub const SIGILL = psep_uapi.SIGILL;
    pub const SIGABRT = psep_uapi.SIGABRT;
    pub const SIGFPE = psep_uapi.SIGFPE;
    pub const SIGPIPE = psep_uapi.SIGPIPE;
    pub const SIGALRM = psep_uapi.SIGALRM;
    pub const SIGTERM = psep_uapi.SIGTERM;
    pub const SIGUSR1 = psep_uapi.SIGUSR1;
    pub const SIGUSR2 = psep_uapi.SIGUSR2;
    pub const SIGCHLD = psep_uapi.SIGCHLD;
    pub const SIGCONT = psep_uapi.SIGCONT;
    pub const SIGSTOP = psep_uapi.SIGSTOP;
    pub const SIGTSTP = psep_uapi.SIGTSTP;
    pub const SIGTTIN = psep_uapi.SIGTTIN;
    pub const SIGTTOU = psep_uapi.SIGTTOU;

    // uid/gid/groups + process control
    pub const uid_t = psep_uapi.uid_t;
    pub const gid_t = psep_uapi.gid_t;
    pub const pid_t = psep_uapi.pid_t;
    pub const getuid = psep_uapi.getuid;
    pub const geteuid = psep_uapi.geteuid;
    pub const getgid = psep_uapi.getgid;
    pub const getegid = psep_uapi.getegid;
    pub const setuid = psep_uapi.setuid;
    pub const seteuid = psep_uapi.seteuid;
    pub const setgid = psep_uapi.setgid;
    pub const setegid = psep_uapi.setegid;
    pub const setgroups = psep_uapi.setgroups;
    pub const getgroups = psep_uapi.getgroups;
    pub const setfsuid = psep_uapi.setfsuid;
    pub const setfsgid = psep_uapi.setfsgid;
    pub const waitpid = psep_uapi.waitpid;
    pub const kill = psep_uapi.kill;
    pub const WNOHANG = psep_uapi.WNOHANG;
    pub const WIFEXITED = psep_uapi.WIFEXITED;
    pub const WIFSIGNALED = psep_uapi.WIFSIGNALED;
    pub const WEXITSTATUS = psep_uapi.WEXITSTATUS;
    pub const PRIO_PROCESS = psep_uapi.PRIO_PROCESS;
    pub const setpriority = psep_uapi.setpriority;

    // ctype
    pub const isprint = psep_uapi.isprint;

    // netlink
    pub const AF_NETLINK = psep_uapi.AF_NETLINK;
    pub const SOCK_RAW = psep_uapi.SOCK_RAW;
    pub const NETLINK_KOBJECT_UEVENT = psep_uapi.NETLINK_KOBJECT_UEVENT;
    pub const RTMGRP_LINK = psep_uapi.RTMGRP_LINK;
    pub const RTMGRP_IPV4_IFADDR = psep_uapi.RTMGRP_IPV4_IFADDR;
    pub const struct_sockaddr_nl = psep_uapi.struct_sockaddr_nl;
    pub const struct_ucred = psep_uapi.struct_ucred;
    pub const CMSG_SPACE = psep_uapi.CMSG_SPACE;
    pub const MSG_TRUNC = psep_uapi.MSG_TRUNC;

    pub const AF_LOCAL = psep_uapi.AF_LOCAL;
    pub const PF_UNSPEC = psep_uapi.PF_UNSPEC;
    pub const SOCK_STREAM = psep_uapi.SOCK_STREAM;

    pub const strstr = psep_uapi.strstr;
    pub const drmDropMaster = psep_uapi.drmDropMaster;
    pub const drmSetMaster = psep_uapi.drmSetMaster;

    // nfds_t — poll(2) signature type.
    pub const nfds_t = psep_uapi.nfds_t;
};

// Socket address portability helpers. Our libc.bind takes
// `?*const anyopaque` directly (no glibc transparent union), so the cast
// is always a plain `*const struct_sockaddr` pointer.
fn constSockaddrCast(ptr: anytype) ?*const anyopaque {
    return @ptrCast(@alignCast(ptr));
}

// External C function declarations

extern fn arcan_pushhandle(source: c_int, channel: c_int) bool;
extern fn arcan_fetchhandle(sockin_fd: c_int, block: bool) c_int;
extern fn arcan_process_title(title: [*c]const u8) void;
extern fn arcan_timemillis() c_ulonglong;

// arcan_watchdog_ping is declared as `_Atomic uint64_t* volatile` in C.
// In the Zig engine it's `?*volatile u64`. We use extern to reference it.
extern var arcan_watchdog_ping: ?*volatile u64;

// Constants

const MAXPATHLEN = c.MAXPATHLEN;

const KDSKBMUTE = 0x4851;

// Types

const Command = enum(u8) {
    NO_OP = 0,
    OPEN_DEVICE = 'o',
    RELEASE_DEVICE = 'r',
    OPEN_FAILED = '#',
    NEW_INPUT_DEVICE = 'i',
    DISPLAY_CONNECTOR_STATE = 'd',
    SYSTEM_STATE_RELEASE = '1',
    SYSTEM_STATE_ACQUIRE = '2',
    SYSTEM_STATE_TERMINATE = '3',
};

const Packet = extern struct {
    cmd_ch: Command,
    arg: c_int = 0,
    path: [MAXPATHLEN]u8 = std.mem.zeroes([MAXPATHLEN]u8),
};

const DeviceMode = enum(c_int) {
    MODE_DEFAULT = 0,
    MODE_PREFIX = 1,
    MODE_DRM = 2,
    MODE_TTY = 4,
};

const WhitelistEntry = struct {
    name: [*:0]const u8,
    fd: c_int,
    mode: c_int, // bitmask of DeviceMode values
};

// Device mode bitmask helpers

const MODE_DEFAULT: c_int = 0;
const MODE_PREFIX: c_int = 1;
const MODE_DRM: c_int = 2;
const MODE_TTY: c_int = 4;

// Static state

var watchdog_anr_sent: u64 = 0;
var child_conn: c_int = -1;

var whitelist = [_]WhitelistEntry{
    .{ .name = "/dev/input/", .fd = -1, .mode = MODE_PREFIX },
    .{ .name = "/dev/dri/card0", .fd = -1, .mode = MODE_DRM },
    .{ .name = "/dev/dri/card1", .fd = -1, .mode = MODE_DRM },
    .{ .name = "/dev/dri/card2", .fd = -1, .mode = MODE_DRM },
    .{ .name = "/dev/dri/card3", .fd = -1, .mode = MODE_DRM },
    .{ .name = "/dev/dri/", .fd = -1, .mode = MODE_PREFIX },
    .{ .name = "/sys/class/backlight/", .fd = -1, .mode = MODE_PREFIX },
    .{ .name = "/sys/class/tty/", .fd = -1, .mode = MODE_PREFIX },
    .{ .name = "/sys/devices/", .fd = -1, .mode = MODE_PREFIX },
    .{ .name = "/dev/tty", .fd = -1, .mode = MODE_PREFIX | MODE_TTY },
};

var got_tty: struct {
    active: bool = false,
    kbmode: c_ulong = 0,
    mode: c_int = 0,
    leds: c_int = 0,
    ind: usize = 0,
} = .{};

var psock: c_int = -1;
var pkg_queue: [1]Packet = .{std.mem.zeroes(Packet)};

// Signal handlers

fn sigusr_acq(_: c_int, _: [*c]c.siginfo_t, _: ?*anyopaque) callconv(.c) void {
    var pkt = std.mem.zeroes(Packet);
    pkt.cmd_ch = .SYSTEM_STATE_ACQUIRE;
    _ = std.posix.write(child_conn, std.mem.asBytes(&pkt)) catch {};
}

fn sigusr_rel(_: c_int, _: [*c]c.siginfo_t, _: ?*anyopaque) callconv(.c) void {
    var pkt = std.mem.zeroes(Packet);
    pkt.cmd_ch = .SYSTEM_STATE_RELEASE;
    _ = std.posix.write(child_conn, std.mem.asBytes(&pkt)) catch {};
}

fn sigusr_term(_: c_int) callconv(.c) void {
    var pkt = std.mem.zeroes(Packet);
    pkt.cmd_ch = .SYSTEM_STATE_TERMINATE;
    _ = std.posix.write(child_conn, std.mem.asBytes(&pkt)) catch {};
}

// TTY management

fn set_tty(i_arg: c_int, graphics: bool) void {
    const dfd = whitelist[got_tty.ind].fd;
    if (dfd == -1) return;

    if (graphics) {
        _ = c.ioctl(dfd, c.KDSETMODE, c.KD_GRAPHICS);
        return;
    }

    if (i_arg >= 0) {
        _ = c.ioctl(dfd, c.VT_ACTIVATE, i_arg);
        return;
    }

    // already setup, client just reopened the device
    if (got_tty.active) {
        _ = c.ioctl(dfd, c.VT_ACTIVATE, c.VT_ACKACQ);
        return;
    }
    got_tty.active = true;

    // save current tty state
    _ = c.ioctl(dfd, c.KDGETMODE, &got_tty.mode);
    _ = c.ioctl(dfd, c.KDGETLED, &got_tty.leds);
    _ = c.ioctl(dfd, c.KDGKBMODE, &got_tty.kbmode);
    _ = c.ioctl(dfd, c.KDSETLED, @as(c_int, 0));
    _ = c.ioctl(dfd, KDSKBMUTE, @as(c_int, 1));
    _ = c.ioctl(dfd, c.KDSKBMODE, c.K_OFF);

    // register signal handlers that forward the desired action to the client
    var sa_term: c.struct_sigaction = .{};
    sa_term.handler.sa_handler = sigusr_term;
    _ = c.sigaction(c.SIGTERM, &sa_term, null);

    var sa_acq: c.struct_sigaction = .{};
    sa_acq.handler.sa_sigaction = sigusr_acq;
    sa_acq.sa_flags = c.SA_SIGINFO;
    _ = c.sigaction(c.SIGUSR1, &sa_acq, null);

    var sa_rel: c.struct_sigaction = .{};
    sa_rel.handler.sa_sigaction = sigusr_rel;
    sa_rel.sa_flags = c.SA_SIGINFO;
    _ = c.sigaction(c.SIGUSR2, &sa_rel, null);

    // set tty to VT_PROCESS mode with signal-based acquire/release
    var vtm: c.struct_vt_mode = std.mem.zeroes(c.struct_vt_mode);
    vtm.mode = c.VT_PROCESS;
    vtm.acqsig = c.SIGUSR1;
    vtm.relsig = c.SIGUSR2;
    _ = c.ioctl(dfd, c.VT_SETMODE, &vtm);
}

fn release_device(i: usize, shutdown: bool) void {
    if (whitelist[i].fd == -1) return;

    if (whitelist[i].mode & MODE_DRM != 0) {
        _ = c.drmDropMaster(whitelist[i].fd);
        if (!shutdown) return;
    }

    if (whitelist[i].mode & MODE_TTY != 0) {
        if (shutdown) {
            _ = c.ioctl(whitelist[i].fd, KDSKBMUTE, @as(c_int, 0));
            _ = c.ioctl(whitelist[i].fd, c.KDSETMODE, c.KD_TEXT);
            const kb = if (got_tty.kbmode == c.K_OFF) @as(c_ulong, c.K_XLATE) else got_tty.kbmode;
            _ = c.ioctl(whitelist[i].fd, c.KDSKBMODE, kb);
            _ = c.ioctl(whitelist[i].fd, c.KDSETLED, got_tty.leds);
            if (whitelist[i].fd > 0)
                _ = c.close(whitelist[i].fd);
            whitelist[i].fd = -1;
        } else {
            _ = c.ioctl(whitelist[i].fd, c.VT_RELDISP, @as(c_int, 1));
        }
    }
}

fn release_devices() void {
    for (0..whitelist.len) |i| {
        release_device(i, true);
    }
}

// Device access (parent side)

fn access_device(path_ptr: [*c]const u8, arg: c_int, release: bool, keep: *bool) c_int {
    keep.* = false;
    var path = path_ptr;

    // special case 1: substitute TTY for the active tty device
    if (c.strcmp(path, "TTY") == 0) {
        if (!got_tty.active) return -1;
        path = whitelist[got_tty.ind].name;
        if (release and arg >= 0) {
            set_tty(arg, false);
        }
    }

    // special case 3: activate TTY (GRAPHICS switch)
    if (c.strcmp(path, "TTYGRAPHICS") == 0) {
        if (got_tty.active)
            set_tty(-1, true);
        return -1;
    }

    // safeguard check against whitelist
    for (0..whitelist.len) |ind| {
        if (whitelist[ind].mode & MODE_PREFIX != 0) {
            const name_len = c.strlen(whitelist[ind].name);
            if (c.strncmp(whitelist[ind].name, path, name_len) != 0)
                continue;

            // dumb traversal safeguard: only printable, no '.'
            const path_len = c.strlen(path);
            var safe = true;
            for (0..path_len) |pi| {
                if (c.isprint(path[pi]) == 0 or path[pi] == '.') {
                    safe = false;
                    break;
                }
            }
            if (!safe) return -1;
        } else if (c.strcmp(whitelist[ind].name, path) != 0) {
            continue;
        }

        // only allow character devices, except linux sysfs paths
        if (path[0] == '/') {
            var devst: c.struct_stat = std.mem.zeroes(c.struct_stat);
            if (c.stat(path, &devst) < 0 or
                (c.strncmp(path, "/sys", 4) != 0 and (devst.mode & c.S_IFCHR) == 0))
            {
                return -1;
            }
        }

        // already "open" (drm devices and ttys)
        if (whitelist[ind].fd != -1) {
            if (release) {
                release_device(ind, false);
                return -1;
            }
            keep.* = true;
            if (whitelist[ind].mode & MODE_DRM != 0) {
                if (arcan_watchdog_ping) |ping| {
                    @atomicStore(u64, ping, arcan_timemillis(), .seq_cst);
                }
                _ = c.drmSetMaster(whitelist[ind].fd);
            }
            if (whitelist[ind].mode & MODE_TTY != 0) {
                got_tty.ind = ind;
                set_tty(arg, false);
            }
            return whitelist[ind].fd;
        }

        // recipient will set real flags, including cloexec etc.
        var fd = c.open(path, c.O_RDWR);
        if (fd == -1) {
            fd = c.open(path, c.O_RDONLY);
            if (fd == -1) {
                return -1;
            }
        }

        if (whitelist[ind].fd != -1)
            _ = c.close(whitelist[ind].fd);

        if (whitelist[ind].mode & MODE_TTY != 0) {
            whitelist[ind].fd = fd;
            got_tty.ind = ind;
            set_tty(arg, false);
            keep.* = true;
            return fd;
        }

        if (whitelist[ind].mode & MODE_DRM != 0) {
            _ = c.drmSetMaster(fd);
            whitelist[ind].fd = fd;
            keep.* = true;
            return fd;
        }

        return fd;
    }

    // path is not valid
    return -1;
}

// Parent data handler

fn data_in(_: c.pid_t) c_int {
    var cmd: Packet = undefined;
    const bytes = c.read(child_conn, &cmd, @sizeOf(Packet));
    if (bytes != @as(isize, @intCast(@sizeOf(Packet))))
        return -1;

    if (cmd.cmd_ch != .OPEN_DEVICE and cmd.cmd_ch != .RELEASE_DEVICE)
        return -1;

    var keep: bool = false;
    const release = cmd.cmd_ch == .RELEASE_DEVICE;

    const fd = access_device(&cmd.path, cmd.arg, release, &keep);

    if (!release and fd == -1) {
        cmd.cmd_ch = .OPEN_FAILED;
        _ = c.write(child_conn, &cmd, @sizeOf(Packet));
    } else if (!release) {
        _ = c.write(child_conn, &cmd, @sizeOf(Packet));
        _ = arcan_pushhandle(fd, child_conn);

        if (!keep) {
            _ = c.close(fd);
            return -1;
        }
    }

    return fd;
}

// Netlink hotplug detection

fn check_netlink(_: c.pid_t, netlink: c_int) void {
    var buf: [8192]u8 = undefined;
    var cred: [c.CMSG_SPACE(@sizeOf(c.struct_ucred))]u8 align(@alignOf(c.struct_cmsghdr)) = undefined;

    var iov = c.struct_iovec{
        .iov_base = &buf,
        .iov_len = buf.len,
    };

    var msg = c.struct_msghdr{
        .msg_name = null,
        .msg_namelen = 0,
        .msg_iov = &iov,
        .msg_iovlen = 1,
        .msg_control = &cred,
        .msg_controllen = cred.len,
        .msg_flags = 0,
    };

    const buflen = c.recvmsg(netlink, &msg, 0);
    if (buflen < 0 or (msg.msg_flags & c.MSG_TRUNC) != 0)
        return;

    // buf should contain @/ and changed and drm
    if (c.strstr(&buf, "change@") == null) return;
    if (c.strstr(&buf, "drm/card") == null) return;
    // don't notify on backlight changes
    if (c.strstr(&buf, "backlight") != null) return;

    // now write the notification message
    var pkg = std.mem.zeroes(Packet);
    pkg.cmd_ch = .DISPLAY_CONNECTOR_STATE;
    _ = c.write(child_conn, &pkg, @sizeOf(Packet));
}

// Child process health check

fn check_child(child: c.pid_t, die_arg: bool) void {
    var die = die_arg;
    var st: c_int = 0;

    // child dead?
    if (c.waitpid(child, &st, c.WNOHANG) > 0) {
        if (c.WIFEXITED(st) or c.WIFSIGNALED(st)) {
            die = true;
        }
    } else if (die) {
        // we want the child to soft-die
        _ = c.kill(child, c.SIGTERM);
        release_devices();
        c._exit(c.WEXITSTATUS(st));
    }

    // watchdog: check for ANR (Application Not Responding)
    const ts: u64 = if (arcan_watchdog_ping) |ping|
        @atomicLoad(u64, ping, .seq_cst)
    else
        0;

    if (ts != 0 and arcan_timemillis() -| ts > 5000) {
        // only trigger if there is a drm device open
        var found = false;
        for (0..whitelist.len) |i| {
            if (whitelist[i].fd != -1 and (whitelist[i].mode & MODE_DRM) != 0) {
                found = true;
                break;
            }
        }
        if (!found) return;

        if (watchdog_anr_sent != 0) {
            // second timeout — commented out kill in original C code
        } else {
            _ = c.kill(child, c.SIGUSR1);
            watchdog_anr_sent = arcan_timemillis();
        }
    } else {
        watchdog_anr_sent = 0;
    }
}

// Parent loop (Linux)

fn parent_loop(child: c.pid_t, netlink: c_int) void {
    check_child(child, false);

    var pfd = [2]c.struct_pollfd{
        .{
            .fd = child_conn,
            .events = c.POLLIN | c.POLLERR | c.POLLHUP | c.POLLNVAL,
            .revents = 0,
        },
        .{
            .fd = netlink,
            .events = c.POLLIN | c.POLLERR | c.POLLHUP | c.POLLNVAL,
            .revents = 0,
        },
    };

    const nfds: c.nfds_t = if (netlink == -1) 1 else 2;
    const rv = c.poll(&pfd, nfds, 1000);
    if (rv == -1 and (std.c._errno().* != c.EAGAIN and std.c._errno().* != c.EINTR))
        check_child(child, true);

    if (rv == 0) return;

    if (pfd[0].revents & ~@as(c_short, c.POLLIN) != 0)
        check_child(child, true);

    if (pfd[0].revents & c.POLLIN != 0)
        _ = data_in(child);

    if (netlink == -1 or (pfd[1].revents & c.POLLIN == 0))
        return;

    check_netlink(child, netlink);
}

// Privilege dropping

fn drop_privileges() bool {
    const uid = c.getuid();
    const euid = c.geteuid();
    const gid = c.getgid();

    if (uid == euid) return true;

    // no weird suid, drmMaster needs root so non-root suid is pointless
    if (euid != 0) return false;

    _ = c.setsid();

    // filter out egid from supplementary groups, replace with gid
    const ngroups = c.getgroups(0, null);
    if (ngroups > 0) {
        var groups_buf: [128]c.gid_t = undefined;
        const ng: usize = @intCast(ngroups);
        const groups = groups_buf[0..@min(ng, 128)];
        const egid = c.getegid();
        if (c.getgroups(@intCast(groups.len), groups.ptr) > 0) {
            for (groups) |*g| {
                if (g.* == egid) g.* = gid;
            }
            _ = c.setgroups(@intCast(groups.len), groups.ptr);
        }
    }

    // Linux-specific privilege drop
    if (c.setegid(gid) == -1 or
        c.setgid(gid) == -1 or
        c.setfsgid(gid) == -1 or
        c.setfsuid(uid) == -1 or
        c.seteuid(uid) == -1 or
        c.setuid(uid) == -1)
    {
        return false;
    }

    if (c.geteuid() != uid or c.getegid() != gid)
        return false;

    return true;
}

// PARENT SIDE: platform_device_init

export fn platform_device_init() void {
    // Darwin: no DRM/tty/netlink devices to broker, and the fork would
    // poison XPC in the renderer child (Metal's MTLCompilerService — and
    // every other Mach service — refuses connections in fork children).
    if (comptime @import("builtin").os.tag.isDarwin()) {
        _ = drop_privileges();
        return;
    }
    // If other display servers exist or we are a handover child, drop out
    if (c.getenv("ARCAN_CONNPATH") != null or
        c.getenv("ARCAN_SOCKIN_FD") != null or
        c.getenv("DISPLAY") != null or
        c.getenv("WAYLAND_DISPLAY") != null)
    {
        _ = drop_privileges();
        return;
    }

    var sockets: [2]c_int = undefined;
    if (c.socketpair(c.AF_LOCAL, c.SOCK_STREAM, c.PF_UNSPEC, &sockets) == -1)
        c._exit(c.EXIT_FAILURE);

    const pid = c.fork();
    if (pid < 0) c._exit(c.EXIT_FAILURE);

    if (pid == 0) {
        // CHILD (renderer)
        arcan_process_title("renderer");
        _ = c.setpriority(c.PRIO_PROCESS, 0, -19);

        _ = c.close(sockets[1]);

        if (!drop_privileges()) {
            c._exit(c.EXIT_FAILURE);
        }

        // set FD_CLOEXEC on the privsep socket
        psock = sockets[0];
        const fl = c.fcntl(psock, c.F_GETFD);
        if (fl != -1)
            _ = c.fcntl(psock, c.F_SETFD, fl | c.FD_CLOEXEC);

        // prevent stdout/stderr from cascading to children
        const stdout_flags = c.fcntl(c.STDOUT_FILENO, c.F_GETFD);
        if (stdout_flags != -1)
            _ = c.fcntl(c.STDOUT_FILENO, c.F_SETFD, stdout_flags | c.FD_CLOEXEC);
        const stderr_flags = c.fcntl(c.STDERR_FILENO, c.F_GETFD);
        if (stderr_flags != -1)
            _ = c.fcntl(c.STDERR_FILENO, c.F_SETFD, stderr_flags | c.FD_CLOEXEC);
        return;
    }

    // PARENT (device control)

    // bind netlink for display event detection (Linux)
    var sa: c.struct_sockaddr_nl = std.mem.zeroes(c.struct_sockaddr_nl);
    sa.nl_family = c.AF_NETLINK;
    sa.nl_groups = c.RTMGRP_LINK | c.RTMGRP_IPV4_IFADDR;
    var netlink = c.socket(c.AF_NETLINK, c.SOCK_RAW, c.NETLINK_KOBJECT_UEVENT);
    if (netlink >= 0) {
        if (c.bind(netlink, constSockaddrCast(&sa), @sizeOf(c.struct_sockaddr_nl)) != 0) {
            _ = c.close(netlink);
            netlink = -1;
        }
    }

    _ = c.close(sockets[0]);

    // ignore most signals in the parent
    const sigset = [_]c_int{
        c.SIGHUP,  c.SIGINT,  c.SIGQUIT, c.SIGILL,  c.SIGABRT, c.SIGFPE,
        c.SIGPIPE, c.SIGALRM, c.SIGTERM, c.SIGUSR1, c.SIGUSR2, c.SIGCHLD,
        c.SIGCONT, c.SIGSTOP, c.SIGTSTP, c.SIGTTIN, c.SIGTTOU,
    };
    for (sigset) |sig| {
        var sa_ign: c.struct_sigaction = .{};
        // SIG_IGN = (void(*)(int))1 — unaligned sentinel, stored in the
        // integer slot of the handler union.
        sa_ign.handler = .{ .sentinel = 1 };
        _ = c.sigaction(sig, &sa_ign, null);
    }
    child_conn = sockets[1];

    arcan_process_title("device control");

    while (true) {
        parent_loop(pid, netlink);
    }
}

// CLIENT SIDE FUNCTIONS

export fn platform_device_release(name: [*c]const u8, ind: c_int) void {
    var pkg = std.mem.zeroes(Packet);
    pkg.cmd_ch = .RELEASE_DEVICE;
    pkg.arg = ind;

    // copy name into path (equivalent to snprintf(pkg.path, sizeof(pkg.path), "%s", name))
    if (name != null) {
        const name_len = c.strlen(name);
        const copy_len = @min(name_len, MAXPATHLEN - 1);
        @memcpy(pkg.path[0..copy_len], name[0..copy_len]);
        pkg.path[copy_len] = 0;
    }

    _ = c.write(psock, &pkg, @sizeOf(Packet));
}

export fn platform_device_open(name: [*c]const u8, flags: c_int) c_int {
    var pkg = std.mem.zeroes(Packet);
    pkg.cmd_ch = .OPEN_DEVICE;
    pkg.arg = -1;

    // copy name into path
    if (name != null) {
        const name_len = c.strlen(name);
        const copy_len = @min(name_len, MAXPATHLEN - 1);
        @memcpy(pkg.path[0..copy_len], name[0..copy_len]);
        pkg.path[copy_len] = 0;
    }

    if (c.write(psock, &pkg, @sizeOf(Packet)) == -1)
        return -1;

    while (true) {
        const bytes = c.read(psock, &pkg, @sizeOf(Packet));
        if (bytes != @as(isize, @intCast(@sizeOf(Packet)))) break;

        if (pkg.cmd_ch == .OPEN_FAILED)
            return -1;

        if (pkg.cmd_ch == .OPEN_DEVICE) {
            const fd = arcan_fetchhandle(psock, true);
            if (fd == -1) return -1;
            _ = c.fcntl(fd, c.F_SETFD, c.FD_CLOEXEC);
            _ = c.fcntl(fd, c.F_SETFL, flags);
            return fd;
        }

        if (pkg.cmd_ch == .DISPLAY_CONNECTOR_STATE)
            pkg_queue[0] = pkg;

        // assert: should not get NEW_INPUT_DEVICE here
        if (pkg.cmd_ch == .NEW_INPUT_DEVICE)
            @panic("unexpected NEW_INPUT_DEVICE in platform_device_open");
    }

    return 0;
}

export fn platform_device_pollfd() c_int {
    return psock;
}

export fn platform_device_poll(identifier: [*c][*c]u8) c_int {
    _ = identifier;

    if (pkg_queue[0].cmd_ch == .DISPLAY_CONNECTOR_STATE) {
        pkg_queue[0] = std.mem.zeroes(Packet);
        return 2;
    }

    var pfd_arr = [1]c.struct_pollfd{.{
        .fd = psock,
        .events = c.POLLIN | c.POLLERR | c.POLLHUP | c.POLLNVAL,
        .revents = 0,
    }};
    const pfd: *c.struct_pollfd = &pfd_arr[0];

    if (c.poll(&pfd_arr, 1, 0) <= 0)
        return 0;

    if (pfd.revents & ~@as(c_short, c.POLLIN) != 0)
        return -1;

    // translate from visible command format to internal one
    var pkg: Packet = undefined;
    while (true) {
        const bytes = c.read(psock, &pkg, @sizeOf(Packet));
        if (bytes != @as(isize, @intCast(@sizeOf(Packet)))) break;

        switch (pkg.cmd_ch) {
            .NEW_INPUT_DEVICE => {},
            .DISPLAY_CONNECTOR_STATE => return 2,
            .SYSTEM_STATE_RELEASE => return 3,
            .SYSTEM_STATE_ACQUIRE => return 4,
            .SYSTEM_STATE_TERMINATE => return 5,
            else => return 0,
        }
    }

    return 0;
}
