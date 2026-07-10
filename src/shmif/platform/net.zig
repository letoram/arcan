// Zig reimplementation of platform/net.c
// Drop-in C-ABI-compatible replacement for a12 network address handling.
//
// Exports: shmif_platform_a12spawn, shmif_platform_a12addr
//
const std = @import("std");
const off = @import("shmif_offsets");
const c = @import("shmif_types");

// ---- libc externs ----
extern "c" fn strdup(s: [*c]const u8) [*c]u8;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strlen(s: [*c]const u8) usize;
extern "c" fn strncmp(s1: [*c]const u8, s2: [*c]const u8, n: usize) c_int;
extern "c" fn strrchr(s: [*c]const u8, ch: c_int) [*c]u8;
extern "c" fn getenv(name: [*c]const u8) [*c]u8;
extern "c" fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern "c" fn socketpair(domain: c_int, sock_type: c_int, protocol: c_int, sv: *[2]c_int) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn fork() c.pid_t;
extern "c" fn execlp(file: [*c]const u8, arg: [*c]const u8, ...) c_int;
extern "c" fn exit(status: c_int) noreturn;
extern "c" fn shutdown(fd: c_int, how: c_int) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn waitpid(pid: c.pid_t, stat_loc: ?*c_int, options: c_int) c.pid_t;
extern "c" fn uname(buf: *c.struct_utsname) c_int;
extern "c" fn sigaction(sig: c_int, act: ?*const c.struct_sigaction, oact: ?*c.struct_sigaction) c_int;

// ---- shmif platform externs ----
extern "c" fn shmif_platform_mem_from_socket(socket: c_int) c_int;
extern "c" fn shmif_platform_dupfd_to(fd: c_int, dstnum: c_int, fflags: c_int, fdopt: c_int) c_int;
extern "c" fn shmif_platform_log_device(ctx: ?*c.struct_arcan_shmif_cont) *c.FILE;
// BUG-S17: use shmif_log_stderr (write(2)) instead of fprintf(logdev)
extern "c" fn shmif_log_stderr(fmt: [*c]const u8, ...) void;
extern "c" fn arcan_timemillis() c_longlong;


fn errno_val() c_int {
    return std.c._errno().*;
}

// ---- shmif_platform_a12spawn ----

export fn shmif_platform_a12spawn(
    C: ?*c.struct_arcan_shmif_cont,
    addr: [*c]const u8,
    dsock: *c_int,
) [*c]u8 {
    var P: ?*anyopaque = null;
    if (C) |ctx| {
        P = @ptrCast(@alignCast(ctx.priv));
    }

    // extract components from URL: a12://(keyid)@server(:port)
    const work = strdup(addr);
    if (work == null)
        return null;

    // Quick-workaround, the url format for keyid@ is in conflict with other forms
    // like ident@key@. first fallback to hostname uname and if even that is
    // broken, go just by anon and let the directory deal with the likely collision
    var ident: [*c]const u8 = getenv("A12_IDENT");
    var nam: c.struct_utsname = undefined;

    if (ident == null) {
        if (uname(&nam) == 0) {
            if (nam.nodename[0] != 0) {
                ident = &nam.nodename;
            }
        }
        if (ident == null)
            ident = "anon";
    }

    const a12addr = shmif_platform_a12addr(addr);

    // (:port or ' port' - both are fine)
    var port: [*c]const u8 = "6680";
    if (a12addr.len == 0)
        port = null;

    if (a12addr.len >= 0) {
        var i: usize = @intCast(a12addr.len);
        while (work[i] != 0) : (i += 1) {
            if (work[i] == ':' or work[i] == ' ') {
                work[i] = 0;
                port = work + i + 1;
                break;
            }
        }
    }

    // build socketpair, keep one end for ourself
    var spair: [2]c_int = undefined;
    if (socketpair(c.PF_UNIX, c.SOCK_STREAM, 0, &spair) == -1) {
        free(@ptrCast(work));
        _ = log_print("[shmif::a12::connect] couldn't build IPC socket");
        return null;
    }

    // configure descriptors: non-blocking off, cloexec on [0]
    for (0..2) |si| {
        const i: usize = si;
        var flags = fcntl(spair[i], c.F_GETFL);
        if (flags & c.O_NONBLOCK != 0)
            _ = fcntl(spair[i], c.F_SETFL, flags & (~@as(c_int, c.O_NONBLOCK)));

        if (i == 0) {
            flags = fcntl(spair[i], c.F_GETFD);
            if (flags != -1)
                _ = fcntl(spair[i], c.F_SETFD, flags | c.FD_CLOEXEC);
        }

        if (comptime @hasDecl(c, "SO_NOSIGPIPE")) {
            var val: c_int = 1;
            _ = c.setsockopt(spair[i], c.SOL_SOCKET, c.SO_NOSIGPIPE, @ptrCast(&val), @sizeOf(c_int));
        }
    }
    dsock.* = spair[0];

    var tmpbuf_sp: [8]u8 = undefined;
    _ = snprintf(&tmpbuf_sp, @sizeOf(@TypeOf(tmpbuf_sp)), "%d", spair[1]);

    var ksfdbuf: [8]u8 = .{ '-', '1', 0, 0, 0, 0, 0, 0 };
    var ksfd: c_int = -1;
    if (P) |priv| {
        if (!a12addr.weak_auth and off.Hidden.getKeystateStore(priv) != 0) {
            ksfd = shmif_platform_dupfd_to(off.Hidden.getKeystateStore(priv), -1, 0, 0);
            _ = snprintf(&ksfdbuf, @sizeOf(@TypeOf(ksfdbuf)), "%d", ksfd);
        }
    }

    // Compute the host part pointer: &work[a12addr.len]
    const host_ptr: [*c]const u8 = if (a12addr.len >= 0) work + @as(usize, @intCast(a12addr.len)) else work;

    // spawn the arcan-net process with double-fork strategy
    const pid = fork();
    if (pid == 0) {
        if (fork() == 0) {
            var sa = std.mem.zeroes(c.struct_sigaction);
            _ = sigaction(c.SIGINT, &sa, null);

            if (a12addr.weak_auth) {
                _ = execlp("arcan-net", "arcan-net", "-X", "--ident", ident, "--soft-auth", "-S", @as([*c]const u8, &tmpbuf_sp), host_ptr, port, @as(?*const anyopaque, null));
            } else {
                _ = execlp("arcan-net", "arcan-net", "-X", "--ident", ident, "--keystore", @as([*c]const u8, &ksfdbuf), "-S", @as([*c]const u8, &tmpbuf_sp), host_ptr, port, @as(?*const anyopaque, null));
            }

            _ = shutdown(spair[1], c.SHUT_RDWR);
            exit(c.EXIT_FAILURE);
        }
        exit(c.EXIT_FAILURE);
    }
    _ = close(spair[1]);

    if (pid == -1) {
        _ = log_print("[shmif::a12::connect] fork() failed");
        _ = close(spair[0]);
        return null;
    }

    if (ksfd != -1) {
        _ = close(ksfd);
    }

    // temporary override any existing SIGCHLD handler
    var oldsig: c.struct_sigaction = undefined;
    var empty_sa = std.mem.zeroes(c.struct_sigaction);
    _ = sigaction(c.SIGCHLD, &empty_sa, &oldsig);
    while (waitpid(pid, null, 0) == -1 and errno_val() == c.EINTR) {}
    _ = sigaction(c.SIGCHLD, &oldsig, null);

    // retrieve the memory page
    var wbuf: [8]u8 = undefined;
    const fd = shmif_platform_mem_from_socket(dsock.*);
    if (fd == -1) {
        _ = close(dsock.*);
        return null;
    }
    _ = snprintf(&wbuf, @sizeOf(@TypeOf(wbuf)), "%d", fd);

    return strdup(&wbuf);
}

// ---- shmif_platform_a12addr ----

export fn shmif_platform_a12addr(addr: [*c]const u8) c.struct_a12addr_info {
    var res = std.mem.zeroes(c.struct_a12addr_info);
    const slen = strlen(addr);
    res.len = @intCast(slen);
    if (slen == 0) {
        res.len = -1;
        return res;
    }

    // protocol:// friendly
    if (strncmp(addr, "a12s://", 7) == 0) {
        res.len = @intCast(@as(usize, "a12s://".len));
    } else if (strncmp(addr, "a12://", 6) == 0) {
        res.weak_auth = true;
        res.len = @intCast(@as(usize, "a12://".len));
    } else if (strrchr(addr, '@') != null) {
        // tag@host:port format
        res.len = 0;
    } else {
        res.len = -1;
    }

    return res;
}

// ---- log_print helper (replaces C macro) ----
fn log_print(msg: [*c]const u8) c_int {
    shmif_log_stderr("%s\n", msg);
    return 0;
}
