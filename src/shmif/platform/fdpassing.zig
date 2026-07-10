// Zig reimplementation of platform/fdpassing.c
// Drop-in C-ABI-compatible replacement for fd passing over unix sockets.
//
// Exports: shmif_platform_pushfd, shmif_platform_pullfd (fetchfds),
//          shmif_platform_mem_from_socket, shmif_platform_dupfd_to
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const c = @import("shmif_types");

const BADFD: c_int = -1;

// Mac OSX compat -- MSG_NOSIGNAL may not be defined
const MSG_NOSIGNAL: c_int = if (@hasDecl(c, "MSG_NOSIGNAL")) c.MSG_NOSIGNAL else 0;

// ---- libc externs ----
extern fn sendmsg(sockfd: c_int, msg: *const c.struct_msghdr, flags: c_int) isize;
extern fn recvmsg(sockfd: c_int, msg: *c.struct_msghdr, flags: c_int) isize;
extern fn poll(fds: [*c]c.struct_pollfd, nfds: c.nfds_t, timeout: c_int) c_int;
extern fn dup(oldfd: c_int) c_int;
extern fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern fn close(fd: c_int) c_int;

// ---- helpers ----

fn cmsgData(cmsg: *c.struct_cmsghdr) [*]u8 {
    return @as([*]u8, @ptrCast(cmsg)) + @sizeOf(c.struct_cmsghdr);
}

// Manual CMSG_NXTHDR — avoids musl's __CMSG_LEN type mismatch in translate-c
fn cmsgNxthdr(mhdr: *c.struct_msghdr, cmsg: *c.struct_cmsghdr) ?*c.struct_cmsghdr {
    const cmsg_len = cmsg.cmsg_len;
    if (cmsg_len < @sizeOf(c.struct_cmsghdr)) return null;
    // Align up to @alignOf(c.struct_cmsghdr)
    const align_val = @alignOf(c.struct_cmsghdr);
    const next_off = (cmsg_len + align_val - 1) & ~@as(usize, align_val - 1);
    const cmsg_ptr = @as([*]u8, @ptrCast(cmsg));
    const ctrl_ptr = @as([*]u8, @ptrCast(mhdr.msg_control));
    const ctrl_end = ctrl_ptr + @as(usize, @intCast(mhdr.msg_controllen));
    const next_ptr = cmsg_ptr + next_off;
    if (@intFromPtr(next_ptr) + @sizeOf(c.struct_cmsghdr) > @intFromPtr(ctrl_end)) return null;
    return @ptrCast(@alignCast(next_ptr));
}

fn errno_val() c_int {
    return std.c._errno().*;
}

// ---- shmif_platform_mem_from_socket ----

export fn shmif_platform_mem_from_socket(fd: c_int) c_int {
    if (is_freestanding) return -1;
    var dfd: c_int = undefined;
    _ = shmif_platform_fetchfds(fd, &dfd, 1, true, null, null);
    return dfd;
}

// ---- shmif_platform_dupfd_to ----

export fn shmif_platform_dupfd_to(fd: c_int, dstnum: c_int, fflags: c_int, fdopt: c_int) c_int {
    if (is_freestanding) return -1;
    if (fd == -1)
        return -1;

    var rfd: c_int = -1;

    if (dstnum >= 0) {
        while (true) {
            rfd = dup2(fd, dstnum);
            if (rfd != -1 or errno_val() != c.EINTR) break;
        }
    }

    if (rfd == -1) {
        while (true) {
            rfd = dup(fd);
            if (rfd != -1 or errno_val() != c.EINTR) break;
        }
    }

    if (rfd == -1)
        return -1;

    // unless F_SETLKW, EINTR is not an issue
    var flags = fcntl(rfd, c.F_GETFL);
    if (flags != -1 and fflags != 0)
        _ = fcntl(rfd, c.F_SETFL, flags | fflags);

    flags = fcntl(rfd, c.F_GETFD);
    if (flags != -1 and fdopt != 0)
        _ = fcntl(rfd, c.F_SETFD, flags | fdopt);

    return rfd;
}

// ---- shmif_platform_pushfd ----

export fn shmif_platform_pushfd(fd: c_int, sockout: c_int) bool {
    if (is_freestanding) return false;
    var empty: u8 = '!';

    // cmsg buffer large enough for one int, aligned for cmsghdr
    var msgbuf_raw: [c.CMSG_SPACE(@sizeOf(c_int))]u8 align(@alignOf(c.struct_cmsghdr)) = undefined;

    // SH-backend workaround: per-field assignment to dodge struct-literal-init
    // miscompile (same class as BufferImageCopy/TrueType.points.append).
    var nothing_ptr: c.struct_iovec = undefined;
    nothing_ptr.iov_base = @ptrCast(&empty);
    nothing_ptr.iov_len = 1;

    var msg = std.mem.zeroes(c.struct_msghdr);
    msg.msg_iov = &nothing_ptr;
    msg.msg_iovlen = 1;

    if (fd != -1) {
        msg.msg_control = @ptrCast(&msgbuf_raw);
        msg.msg_controllen = @intCast(@sizeOf(@TypeOf(msgbuf_raw)));

        const cmsg: *c.struct_cmsghdr = @ptrCast(@alignCast(c.CMSG_FIRSTHDR(&msg)));
        cmsg.cmsg_len = @intCast(c.CMSG_LEN(@sizeOf(c_int)));
        cmsg.cmsg_level = c.SOL_SOCKET;
        cmsg.cmsg_type = c.SCM_RIGHTS;

        const data_ptr: *c_int = @ptrCast(@alignCast(cmsgData(cmsg)));
        data_ptr.* = fd;
        _ = fcntl(fd, c.F_SETFD, c.FD_CLOEXEC);
    }

    const rv = sendmsg(sockout, &msg, c.MSG_DONTWAIT | MSG_NOSIGNAL);
    return rv >= 0;
}

// ---- shmif_platform_fetchfds (aliased as shmif_platform_pullfd) ----

export fn shmif_platform_fetchfds(
    sockin_fd: c_int,
    dfd: [*c]c_int,
    nfd: usize,
    blocking: bool,
    alive_check: ?*const fn (?*anyopaque) callconv(.c) bool,
    tag: ?*anyopaque,
) c_int {
    if (is_freestanding) return -1;
    // initialize output fds to BADFD
    for (0..nfd) |i| {
        dfd[i] = BADFD;
    }

    if (sockin_fd == BADFD)
        return BADFD;

    // nfd here will be, at most, 4 * 3 * sizeof(int) for transfer of 4-plane image
    // + release and acquire fences
    // CMSG_SPACE(48) to match the C version
    var msgbuf_raw: [c.CMSG_SPACE(48)]u8 align(@alignOf(c.struct_cmsghdr)) = undefined;

    // pinged with single character because OSX breaking on 0- iov_len
    var empty: u8 = undefined;
    // SH-backend workaround: per-field assignment to dodge struct-literal-init
    // miscompile (same class as BufferImageCopy/TrueType.points.append).
    var nothing_ptr: c.struct_iovec = undefined;
    nothing_ptr.iov_base = @ptrCast(&empty);
    nothing_ptr.iov_len = 1;

    // SH-backend: std.mem.zeroes(msghdr) is a nested-init that has dropped
    // middle fields in the same class as BufferImageCopy. Byte-memset AND
    // explicit per-field writes so SH can't elide either step.
    var msg: c.struct_msghdr = undefined;
    @memset(@as([*]u8, @ptrCast(&msg))[0..@sizeOf(c.struct_msghdr)], 0);
    msg.msg_name = null;
    msg.msg_namelen = 0;
    msg.msg_iov = &nothing_ptr;
    msg.msg_iovlen = 1;
    msg.msg_control = @ptrCast(&msgbuf_raw);
    msg.msg_controllen = @intCast(@sizeOf(@TypeOf(msgbuf_raw)));
    msg.msg_flags = 0;

    // spin until we get something over the socket or the aliveness check fails
    if (blocking) {
        var spin_count: u32 = 0;
        // Piece 5 instrumentation: how long did the child actually sit in
        // this loop before the parent's fd finally arrived? If the parent
        // is dropping sends due to SO_SNDBUF pressure, we'd expect the
        // child to wait a long time here. Emit one line when we exit the
        // loop IF we actually waited; silent on the fast path.
        const wait_start_ns = std.time.nanoTimestamp();
        while (true) {
            const rrv = recvmsg(sockin_fd, &msg, MSG_NOSIGNAL | c.MSG_DONTWAIT);
            // recvmsg == 0 on a SOCK_STREAM means the peer's write side is
            // closed. Without this branch the loop reads "no error" and
            // spins on poll → recvmsg → 0 forever, burning a CPU. Treat EOF
            // as fatal so the caller (preroll loop, etc.) propagates the
            // failure and the process exits cleanly.
            if (rrv == 0) return -1;
            if (rrv != -1) {
                const wait_ns = std.time.nanoTimestamp() - wait_start_ns;
                const wait_ms: i64 = @intCast(@divTrunc(wait_ns, 1_000_000));
                if (wait_ms >= 50) {
                    const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
                    const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
                    const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
                    const sc_getpid = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });
                    if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
                        _ = sc_fprintf(f, "[%d] fetchfds: wait_ms=%ld spins=%u sockin_fd=%d\n",
                            sc_getpid(), @as(c_longlong, wait_ms), spin_count, sockin_fd);
                        _ = sc_fclose(f);
                    }
                }
                // Previously had a Debug-only `assert(wait_ms < 2000)` here
                // meant to surface local-IPC wakeup drops. For a12-bridged
                // connections the fd hop is: child → local arcan-net →
                // TCP a12 → remote arcan-net → shmifsrv → fd-pass back.
                // That round-trip routinely exceeds 2s during startup;
                // the assert was panicking afsrv_* clients mid-preroll and
                // showing up as interop matrix FAILs unrelated to protocol
                // correctness. The 50ms+ fprintf trace above is sufficient
                // for the diagnostic it was trying to provide.
                break;
            }

            // log spin - every 100 iterations, with errno + receive-queue probe
            spin_count += 1;
            if (spin_count % 100 == 1) {
                const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
                const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
                const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
                const sc_getpid = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });
                const sc_ioctl = @extern(*const fn (c_int, c_ulong, *c_int) callconv(.c) c_int, .{ .name = "ioctl" });
                const sc_errno = @extern(*const fn () callconv(.c) *c_int, .{ .name = "__errno_location" });
                const errno_now = sc_errno().*;
                var inq_now: c_int = 0;
                _ = sc_ioctl(sockin_fd, 0x541B, &inq_now);  // SIOCINQ
                if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
                    _ = sc_fprintf(f, "[%d] fetchfds SPIN sockin_fd=%d count=%u errno=%d inq=%d iov_base=%p iov_len=%zu cl=%zu\n",
                        sc_getpid(), sockin_fd, spin_count, errno_now, inq_now,
                        nothing_ptr.iov_base, nothing_ptr.iov_len, msg.msg_controllen);
                    _ = sc_fclose(f);
                }
            }

            // SH-backend workaround: per-field assignment for the same
            // struct-literal-init miscompile class.
            var pfd: c.struct_pollfd = undefined;
            pfd.fd = sockin_fd;
            pfd.events = c.POLLIN | c.POLLHUP;
            pfd.revents = 0;
            _ = poll(&pfd, 1, 1000);

            if (alive_check) |check| {
                if (!check(tag))
                    return -1;
            }
        }
    } else {
        const nb_rv = recvmsg(sockin_fd, &msg, c.MSG_DONTWAIT | MSG_NOSIGNAL);
        // EOF (rv==0) — peer closed write side; propagate as failure rather
        // than returning 0 fds and letting the caller assume success.
        if (nb_rv == -1 or nb_rv == 0)
            return -1;
    }

    var nd: c_int = 0;
    var cmsg_opt: ?*c.struct_cmsghdr = @ptrCast(@alignCast(c.CMSG_FIRSTHDR(&msg)));
    while (cmsg_opt) |cmsg| {
        if (cmsg.cmsg_len % @sizeOf(c_int) != 0 or cmsg.cmsg_len <= c.CMSG_LEN(0)) {
            // bad cmsg length
            return -1;
        }

        const data_base: [*c]c_int = @ptrCast(@alignCast(cmsgData(cmsg)));
        const n_ints = (cmsg.cmsg_len - c.CMSG_LEN(0)) / @sizeOf(c_int);
        {
            const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
            const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
            const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
            const sc_getpid = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });
            if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
                _ = sc_fprintf(f, "[%d] fetchfds GOT sockin_fd=%d n_ints=%zu fd0=%d\n",
                    sc_getpid(), sockin_fd, n_ints,
                    if (n_ints > 0) data_base[0] else -99);
                _ = sc_fclose(f);
            }
        }
        for (0..n_ints) |i| {
            const idx: usize = @intCast(nd);
            dfd[idx] = data_base[i];
            _ = fcntl(dfd[idx], c.F_SETFD, c.FD_CLOEXEC);
            nd += 1;
        }

        cmsg_opt = cmsgNxthdr(&msg, cmsg);
    }

    return nd;
}
