// Zig port of posix/fdpassing.c (NONBLOCK_RECV version)
// Unix domain socket fd passing: send/receive file descriptors via SCM_RIGHTS.
//
// Exports: arcan_send_fds, arcan_receive_fds, arcan_pushhandle, arcan_fetchhandle
//
// This is the compositor/platform version compiled with -DNONBLOCK_RECV.
// It is different from src/shmif/platform/fdpassing.zig which is the shmif
// library version with different function names.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const BADFD: c_int = -1;

// --- libc types and externs ---

const msghdr = if (@import("builtin").os.tag.isDarwin()) extern struct {
    msg_name: ?*anyopaque,
    msg_namelen: c_uint,
    msg_iov: [*]iovec,
    msg_iovlen: c_int,
    msg_control: ?*anyopaque,
    msg_controllen: c_uint,
    msg_flags: c_int,
} else extern struct {
    msg_name: ?*anyopaque,
    msg_namelen: c_uint,
    msg_iov: [*]iovec,
    msg_iovlen: usize,
    msg_control: ?*anyopaque,
    msg_controllen: usize,
    msg_flags: c_int,
};

const cmsghdr = if (@import("builtin").os.tag.isDarwin()) extern struct {
    cmsg_len: c_uint,
    cmsg_level: c_int,
    cmsg_type: c_int,
    // followed by payload data
} else extern struct {
    cmsg_len: usize,
    cmsg_level: c_int,
    cmsg_type: c_int,
    // followed by payload data
};

const iovec = extern struct {
    iov_base: ?*anyopaque,
    iov_len: usize,
};

const libc = if (is_freestanding) struct {
    fn sendmsg(_: c_int, _: *const msghdr, _: c_int) isize { return -1; }
    fn recvmsg(_: c_int, _: *msghdr, _: c_int) isize { return -1; }
    fn fcntl(_: c_int, _: c_int, _: c_int) c_int { return -1; }
    fn getsockopt(_: c_int, _: c_int, _: c_int, _: ?*anyopaque, _: *c_uint) c_int { return -1; }
    fn ioctl(_: c_int, _: c_ulong, _: *c_int) c_int { return -1; }
} else struct {
    extern "c" fn sendmsg(fd: c_int, msg: *const msghdr, flags: c_int) isize;
    extern "c" fn recvmsg(fd: c_int, msg: *msghdr, flags: c_int) isize;
    extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
    extern "c" fn getsockopt(fd: c_int, level: c_int, optname: c_int, optval: ?*anyopaque, optlen: *c_uint) c_int;
    extern "c" fn ioctl(fd: c_int, request: c_ulong, out: *c_int) c_int;
};
const sendmsg = libc.sendmsg;
const recvmsg = libc.recvmsg;
const fcntl = libc.fcntl;
const c_getsockopt = libc.getsockopt;
const c_ioctl = libc.ioctl;

// Telemetry counters (Piece 2 of the fd-pass instrumentation plan).
// Atomic so a future multi-threaded caller can't corrupt them. Process-wide
// scope is fine — one pushhandle stream serves all frameservers and we want
// a monotonic count to see how far apart EAGAINs are.
var total_pushhandle: u64 = 0;
var total_eagain: u64 = 0;

// Linux-specific: SIOCOUTQ reports bytes currently queued in the socket send
// buffer. Works for AF_UNIX SOCK_STREAM. Value 0x5411 on aarch64 + x86.
const SIOCOUTQ: c_ulong = 0x5411;
const SO_SNDBUF: c_int = if (@import("builtin").os.tag.isDarwin()) 0x1001 else 7;

// --- Constants ---

const SOL_SOCKET: c_int = if (@import("builtin").os.tag.isDarwin()) 0xFFFF else 1;
const SCM_RIGHTS: c_int = 1;
const MSG_DONTWAIT: c_int = if (@import("builtin").os.tag.isDarwin()) 0x80 else 0x40;
// Mac OSX compat — MSG_NOSIGNAL may not exist; on Linux it is 0x4000
// Darwin has no MSG_NOSIGNAL (SIGPIPE suppressed via SO_NOSIGPIPE / ignored handler)
const MSG_NOSIGNAL: c_int = if (@import("builtin").os.tag.isDarwin()) 0 else 0x4000;
const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;

// --- CMSG helpers ---
// These replicate the C CMSG_SPACE / CMSG_LEN / CMSG_FIRSTHDR / CMSG_DATA /
// CMSG_NXTHDR macros for use in Zig.

fn cmsgAlign(len: usize) usize {
    // Darwin's CMSG macros align to 4 (__DARWIN_ALIGN32); Linux to
    // sizeof(size_t). Getting this wrong puts the fd payload at an offset
    // the kernel doesn't read — SCM_RIGHTS sends silently carry nothing.
    const align_to: usize = if (@import("builtin").os.tag.isDarwin()) 4 else @sizeOf(usize);
    return (len + align_to - 1) & ~(align_to - 1);
}

fn cmsgSpace(data_len: usize) usize {
    return cmsgAlign(@sizeOf(cmsghdr)) + cmsgAlign(data_len);
}

fn cmsgLen(data_len: usize) usize {
    return cmsgAlign(@sizeOf(cmsghdr)) + data_len;
}

fn cmsgData(cmsg: *cmsghdr) [*]u8 {
    return @as([*]u8, @ptrCast(cmsg)) + cmsgAlign(@sizeOf(cmsghdr));
}

fn cmsgFirstHdr(msg: *const msghdr) ?*cmsghdr {
    if (msg.msg_controllen < @sizeOf(cmsghdr)) return null;
    return @ptrCast(@alignCast(msg.msg_control));
}

fn cmsgNxtHdr(msg: *const msghdr, cmsg: *cmsghdr) ?*cmsghdr {
    const control_start = @intFromPtr(msg.msg_control);
    const control_end = control_start + msg.msg_controllen;
    const next_addr = @intFromPtr(cmsg) + cmsgAlign(cmsg.cmsg_len);
    if (next_addr + @sizeOf(cmsghdr) > control_end) return null;
    return @ptrFromInt(next_addr);
}

// --- arcan_send_fds ---
// Sends multiple file descriptors over a Unix domain socket using SCM_RIGHTS.

export fn arcan_send_fds(sockout_fd: c_int, dfd: [*]c_int, nfd: usize) bool {
    if (sockout_fd == BADFD) return false;

    // Control buffer large enough for up to 12 ints, aligned for cmsghdr
    var msgbuf: [cmsgSpace(12 * @sizeOf(c_int))]u8 align(@alignOf(cmsghdr)) = undefined;

    var empty: u8 = '!';
    // SH-backend: 2-field struct-literal init has been observed to drop one
    // field (same class as BufferImageCopy / TrueType.points.append). Build
    // via per-field assignment — if iov_len dropped to 0, sendmsg/recvmsg
    // succeeds with no data delivered, which exactly matches the
    // afsrv_terminal fetchfds-spin symptom.
    var nothing_ptr: iovec = undefined;
    nothing_ptr.iov_base = @ptrCast(&empty);
    nothing_ptr.iov_len = 1;

    const len = nfd * @sizeOf(c_int);

    var msg = std.mem.zeroes(msghdr);
    msg.msg_iov = @ptrCast(&nothing_ptr);
    msg.msg_iovlen = 1;
    msg.msg_control = @ptrCast(&msgbuf);
    msg.msg_controllen = @intCast(cmsgSpace(len));

    const cmsg: *cmsghdr = cmsgFirstHdr(&msg) orelse return false;

    cmsg.cmsg_len = @intCast(cmsgLen(len));
    cmsg.cmsg_level = SOL_SOCKET;
    cmsg.cmsg_type = SCM_RIGHTS;

    const data_ptr = cmsgData(cmsg);
    @memcpy(data_ptr[0..len], @as([*]const u8, @ptrCast(dfd))[0..len]);

    // Set msg_controllen to the actual cmsg length (as in the C version)
    msg.msg_controllen = cmsg.cmsg_len;

    const rv = sendmsg(sockout_fd, &msg, MSG_DONTWAIT | MSG_NOSIGNAL);
    return rv >= 0;
}

// --- arcan_receive_fds ---
// Receives multiple file descriptors from a Unix domain socket.
// Uses MSG_DONTWAIT (NONBLOCK_RECV). Returns count of fds received, or -1 on error.

export fn arcan_receive_fds(sockin_fd: c_int, dfd: [*]c_int, nfd: usize) c_int {
    // Initialize output fds to BADFD
    for (0..nfd) |i| {
        dfd[i] = BADFD;
    }

    if (sockin_fd == BADFD) return BADFD;

    // Control buffer: 48 bytes of payload (enough for 12 ints) + cmsghdr overhead.
    // Match the C version's struct cmsgbuf layout.
    var msgbuf: [cmsgSpace(48)]u8 align(@alignOf(cmsghdr)) = undefined;

    // Zero the buffer to initialize fd slots to a known state
    @memset(&msgbuf, 0);

    // Pinged with single character because OSX breaks on 0-length iov_len
    var empty: u8 = undefined;
    // SH-backend: 2-field struct-literal init has been observed to drop one
    // field (same class as BufferImageCopy / TrueType.points.append). Build
    // via per-field assignment — if iov_len dropped to 0, sendmsg/recvmsg
    // succeeds with no data delivered, which exactly matches the
    // afsrv_terminal fetchfds-spin symptom.
    var nothing_ptr: iovec = undefined;
    nothing_ptr.iov_base = @ptrCast(&empty);
    nothing_ptr.iov_len = 1;

    var msg = std.mem.zeroes(msghdr);
    msg.msg_iov = @ptrCast(&nothing_ptr);
    msg.msg_iovlen = 1;
    msg.msg_control = @ptrCast(&msgbuf);
    msg.msg_controllen = @sizeOf(@TypeOf(msgbuf));

    if (recvmsg(sockin_fd, &msg, MSG_DONTWAIT | MSG_NOSIGNAL) == -1)
        return -1;

    var nd: c_int = 0;
    var cmsg_opt: ?*cmsghdr = cmsgFirstHdr(&msg);
    while (cmsg_opt) |cmsg| {
        if (cmsg.cmsg_len % @sizeOf(c_int) != 0 or cmsg.cmsg_len <= cmsgLen(0)) {
            // bad cmsg length
            return -1;
        }

        const data_base: [*]c_int = @ptrCast(@alignCast(cmsgData(cmsg)));
        const n_ints = (cmsg.cmsg_len - cmsgLen(0)) / @sizeOf(c_int);
        for (0..n_ints) |i| {
            const idx: usize = @intCast(nd);
            dfd[idx] = data_base[i];
            _ = fcntl(dfd[idx], F_SETFD, FD_CLOEXEC);
            nd += 1;
        }

        cmsg_opt = cmsgNxtHdr(&msg, cmsg);
    }

    return nd;
}

// --- arcan_pushhandle ---
// Sends a single file descriptor over a Unix domain socket.
// If source is -1, sends a message with no ancillary data.

export fn arcan_pushhandle(source: c_int, channel: c_int) bool {
    var empty: u8 = '!';

    // Control buffer for one int
    var msgbuf: [cmsgSpace(@sizeOf(c_int))]u8 align(@alignOf(cmsghdr)) = undefined;

    // SH-backend: 2-field struct-literal init has been observed to drop one
    // field (same class as BufferImageCopy / TrueType.points.append). Build
    // via per-field assignment — if iov_len dropped to 0, sendmsg/recvmsg
    // succeeds with no data delivered, which exactly matches the
    // afsrv_terminal fetchfds-spin symptom.
    var nothing_ptr: iovec = undefined;
    nothing_ptr.iov_base = @ptrCast(&empty);
    nothing_ptr.iov_len = 1;

    // SH-backend: std.mem.zeroes(msghdr) is a nested-init that has dropped
    // middle fields in the same class as BufferImageCopy. Byte-memset the
    // underlying storage AND explicitly write every field so the SH backend
    // can't elide a "we already zeroed it" pattern. This is the same per-field
    // recipe used for iovec — extended to the larger msghdr struct.
    var msg: msghdr = undefined;
    @memset(@as([*]u8, @ptrCast(&msg))[0..@sizeOf(msghdr)], 0);
    msg.msg_name = null;
    msg.msg_namelen = 0;
    msg.msg_iov = @ptrCast(&nothing_ptr);
    msg.msg_iovlen = 1;
    msg.msg_control = null;
    msg.msg_controllen = 0;
    msg.msg_flags = 0;

    if (source != -1) {
        msg.msg_control = @ptrCast(&msgbuf);
        msg.msg_controllen = @intCast(@sizeOf(@TypeOf(msgbuf)));

        const cmsg: *cmsghdr = cmsgFirstHdr(&msg) orelse return false;
        cmsg.cmsg_len = @intCast(cmsgLen(@sizeOf(c_int)));
        cmsg.cmsg_level = SOL_SOCKET;
        cmsg.cmsg_type = SCM_RIGHTS;

        const data_ptr: *c_int = @ptrCast(@alignCast(cmsgData(cmsg)));
        data_ptr.* = source;
        _ = fcntl(source, F_SETFD, FD_CLOEXEC);
    }

    const rv = sendmsg(channel, &msg, MSG_DONTWAIT | MSG_NOSIGNAL);
    const errno_fn = @extern(*const fn () callconv(.c) *c_int, .{ .name = "__errno_location" });
    const errno_after: c_int = if (!is_freestanding) errno_fn().* else 0;
    if (!is_freestanding) {
        // Probe outq immediately — if rv=1 but outq=0, the byte was either
        // never queued or already drained by another reader. If outq>0, the
        // byte is sitting in the kernel and the issue is on the receive side.
        var outq_after: c_int = 0;
        _ = c_ioctl(channel, SIOCOUTQ, &outq_after);
        const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
        const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
        const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
        if (sc_open("/tmp/arcan_lua_trace.log", "a")) |f| {
            _ = sc_fprintf(f, "arcan_pushhandle: channel=%d source_fd=%d rv=%ld errno=%d msg_controllen=%zu iov_base=%p iov_len=%zu outq_after=%d\n",
                channel, source, @as(c_long, rv), errno_after, msg.msg_controllen,
                nothing_ptr.iov_base, nothing_ptr.iov_len, outq_after);
            _ = sc_fclose(f);
        }
    }

    // Per-call tracking, outside the above trace so ping-only sends also
    // count. total_pushhandle advances on every call (regardless of source);
    // total_eagain only on EAGAIN — gives us the density (N calls per EAGAIN)
    // at any point in the trace.
    if (!is_freestanding) {
        _ = @atomicRmw(u64, &total_pushhandle, .Add, 1, .seq_cst);
    }

    if (rv < 0 and !is_freestanding and (errno_after == 11 or errno_after == 35)) {
        // 11 = EAGAIN on Linux, 35 on some BSDs; treat both as "try again".
        _ = @atomicRmw(u64, &total_eagain, .Add, 1, .seq_cst);

        // Attribute every EAGAIN: was the buffer small (SO_SNDBUF clamped?),
        // or legitimately saturated (outq close to sndbuf), or something else
        // (outq low yet EAGAIN — would be surprising, indicates kernel
        // ancillary-slot exhaustion or similar). One line per EAGAIN.
        var sndbuf: c_int = 0;
        var optlen: c_uint = @sizeOf(c_int);
        _ = c_getsockopt(channel, SOL_SOCKET, SO_SNDBUF, @ptrCast(&sndbuf), &optlen);
        var outq: c_int = 0;
        _ = c_ioctl(channel, SIOCOUTQ, &outq);

        const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
        const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
        const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
        if (sc_open("/tmp/arcan_fsrv_debug.log", "a")) |f| {
            _ = sc_fprintf(
                f,
                "pushhandle_eagain: channel=%d fd=%d sndbuf=%d outq=%d total_sent=%llu total_eagain=%llu\n",
                channel,
                source,
                sndbuf,
                outq,
                @atomicLoad(u64, &total_pushhandle, .seq_cst),
                @atomicLoad(u64, &total_eagain, .seq_cst),
            );
            _ = sc_fclose(f);
        }
    }

    // The diagnostics above (ioctl/fopen/fprintf) clobber errno; callers
    // (platform_fsrv_pushevent's peer_gone classification) need sendmsg's
    // errno, not the breadcrumbs' — restore it.
    if (!is_freestanding) errno_fn().* = errno_after;

    return rv >= 0;
}

// --- arcan_fetchhandle ---
// Receives a single file descriptor from a Unix domain socket.
// If block is false, uses MSG_DONTWAIT. Returns fd or -1.

export fn arcan_fetchhandle(sockin_fd: c_int, block: bool) c_int {
    if (sockin_fd == -1) return -1;

    var empty: u8 = undefined;

    // Control buffer for one int
    var msgbuf: [cmsgSpace(@sizeOf(c_int))]u8 align(@alignOf(cmsghdr)) = undefined;
    // Initialize so the fd slot starts at -1
    @memset(&msgbuf, 0xFF);

    // SH-backend: 2-field struct-literal init has been observed to drop one
    // field (same class as BufferImageCopy / TrueType.points.append). Build
    // via per-field assignment — if iov_len dropped to 0, sendmsg/recvmsg
    // succeeds with no data delivered, which exactly matches the
    // afsrv_terminal fetchfds-spin symptom.
    var nothing_ptr: iovec = undefined;
    nothing_ptr.iov_base = @ptrCast(&empty);
    nothing_ptr.iov_len = 1;

    var msg = std.mem.zeroes(msghdr);
    msg.msg_iov = @ptrCast(&nothing_ptr);
    msg.msg_iovlen = 1;
    msg.msg_control = @ptrCast(&msgbuf);
    msg.msg_controllen = @sizeOf(@TypeOf(msgbuf));

    const flags: c_int = (if (!block) MSG_DONTWAIT else 0) | MSG_NOSIGNAL;
    if (recvmsg(sockin_fd, &msg, flags) == -1) return -1;

    var nd: c_int = -1;
    const cmsg_opt: ?*cmsghdr = cmsgFirstHdr(&msg);
    if (cmsg_opt) |cmsg| {
        if (cmsg.cmsg_len == cmsgLen(@sizeOf(c_int)) and
            cmsg.cmsg_level == SOL_SOCKET and
            cmsg.cmsg_type == SCM_RIGHTS)
        {
            const data_ptr: *c_int = @ptrCast(@alignCast(cmsgData(cmsg)));
            nd = data_ptr.*;
            if (nd != -1)
                _ = fcntl(nd, F_SETFD, FD_CLOEXEC);
        }
    }

    return nd;
}
