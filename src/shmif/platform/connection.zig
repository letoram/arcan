// Zig reimplementation of platform/connection.c
// Drop-in C-ABI-compatible replacement for connection setup.
//
// Exports: shmif_platform_connpath, shmif_platform_fd_from_socket,
//          shmif_platform_open_env_connection
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const c = @import("shmif_types");

const BADFD: c_int = -1;

// ---- libc externs ----
extern fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern fn strlen(s: [*c]const u8) usize;
extern fn getenv(name: [*c]const u8) [*c]u8;
extern fn strtol(nptr: [*c]const u8, endptr: [*c][*c]u8, base: c_int) c_long;
extern fn strdup(s: [*c]const u8) [*c]u8;
extern fn setsockopt(sockfd: c_int, level: c_int, optname: c_int, optval: ?*const anyopaque, optlen: c.socklen_t) c_int;
extern fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern fn unsetenv(name: [*c]const u8) c_int;
extern fn sleep(seconds: c_uint) c_uint;
extern fn close(fd: c_int) c_int;

// ---- shmif platform externs (defined in other platform .c/.zig files) ----
extern fn shmif_platform_fetchfds(sockin: c_int, fdout: [*c]c_int, cap: usize, blocking: bool, alive_check: ?*const fn (?*anyopaque) callconv(.c) bool, tag: ?*anyopaque) c_int;
extern fn shmif_platform_mem_from_socket(socket: c_int) c_int;
extern fn shmif_platform_a12addr(addr: [*c]const u8) c.struct_a12addr_info;
extern fn shmif_platform_a12spawn(C: ?*c.struct_arcan_shmif_cont, addr: [*c]const u8, dsock: *c_int) [*c]u8;
extern fn arcan_shmif_connect(connpath: [*c]const u8, connkey: [*c]const u8, conn_ch: *c_int) [*c]u8;

// ---- shmif_platform_connpath ----

export fn shmif_platform_connpath(
    key: [*c]const u8,
    dbuf: [*c]u8,
    dbuf_sz: usize,
    attempt: c_int,
) c_int {
    if (is_freestanding) return -1;
    if (key == null or key[0] == 0)
        return -1;

    // 1. If the key is set to an absolute path, that will be respected.
    //    Only try once — retrying the same absolute path is an infinite loop.
    if (key[0] == '/') {
        if (attempt > 0) return -1;
        return snprintf(dbuf, dbuf_sz, "%s", key);
    }

    // 2. Otherwise we check for an XDG_RUNTIME_DIR
    if (attempt == 0) {
        const xdg = getenv("XDG_RUNTIME_DIR");
        if (xdg != null)
            return snprintf(dbuf, dbuf_sz, "%s/%s", xdg, key);
    }

    // 3. Last (before giving up), HOME + prefix
    if (attempt <= 1) {
        const home = getenv("HOME");
        if (home != null)
            return snprintf(dbuf, dbuf_sz, "%s/.%s", home, key);
    }

    // no env no nothing? bad environment
    return -1;
}

// ---- shmif_platform_fd_from_socket ----

export fn shmif_platform_fd_from_socket(sock: c_int) c_int {
    if (is_freestanding) return -1;
    var dfd: c_int = undefined;
    _ = shmif_platform_fetchfds(sock, &dfd, 1, true, null, null);
    return dfd;
}

// ---- shmif_platform_open_env_connection ----

export fn shmif_platform_open_env_connection(flags_in: c_int) c.struct_shmif_connection {
    if (is_freestanding) return std.mem.zeroes(c.struct_shmif_connection);
    var res = std.mem.zeroes(c.struct_shmif_connection);
    res.args = @ptrCast(getenv("ARCAN_ARG"));

    const conn_src = getenv("ARCAN_CONNPATH");
    const conn_fl = getenv("ARCAN_CONNFL");
    res.alternate_cp = @ptrCast(getenv("ARCAN_ALTCONN"));

    if (conn_fl != null)
        res.flags = flags_in | @as(c_int, @intCast(strtol(conn_fl, null, 10)))
    else
        res.flags = flags_in;

    // Inheritance based connection
    const sockin_fd_env = getenv("ARCAN_SOCKIN_FD");
    if (sockin_fd_env != null) {
        res.socket = @as(c_int, @intCast(strtol(sockin_fd_env, null, 10)));

        // set receive timeout
        var tv = std.mem.zeroes(c.struct_timeval);
        tv.tv_sec = 1;
        _ = setsockopt(res.socket, c.SOL_SOCKET, c.SO_RCVTIMEO, @ptrCast(&tv), @sizeOf(c.struct_timeval));

        var memfd: c_int = BADFD;
        const memfd_env = getenv("ARCAN_SOCKIN_MEMFD");
        if (memfd_env != null)
            memfd = @as(c_int, @intCast(strtol(memfd_env, null, 10)))
        else
            memfd = shmif_platform_mem_from_socket(res.socket);

        var wbuf: [8]u8 = undefined;
        _ = snprintf(&wbuf, 8, "%d", memfd);
        res.keyfile = strdup(&wbuf);
        _ = fcntl(memfd, c.F_SETFD, c.FD_CLOEXEC);

        _ = unsetenv("ARCAN_SOCKIN_FD");
        _ = unsetenv("ARCAN_HANDOVER_EXEC");
        _ = unsetenv("ARCAN_SOCKIN_MEMFD");
    } else if (conn_src != null) {
        // connection point based setup
        const a12info = shmif_platform_a12addr(conn_src);
        if (a12info.len != -1) {
            res.keyfile = @ptrCast(shmif_platform_a12spawn(null, conn_src, &res.socket));
            res.networked = true;
        } else {
            var step: u4 = 0;
            while (true) {
                res.keyfile = @ptrCast(arcan_shmif_connect(conn_src, null, &res.socket));
                if (res.keyfile != null) break;
                if ((flags_in & c.SHMIF_CONNECT_LOOP) == 0) break;
                const shift: u5 = if (step > 4) 4 else step;
                _ = sleep(@as(c_uint, 1) << shift);
                if (step <= 4) step += 1;
            }
        }
    } else {
        res.@"error" = "no connection: check ARCAN_CONNPATH";
        return res;
    }

    if (res.keyfile == null or res.socket == -1) {
        res.@"error" = "socket didn't reply with connection data";
        return res;
    }

    _ = fcntl(res.socket, c.F_SETFD, c.FD_CLOEXEC);
    const eflags = fcntl(res.socket, c.F_GETFL);
    if (eflags & c.O_NONBLOCK != 0)
        _ = fcntl(res.socket, c.F_SETFL, eflags & (~@as(c_int, c.O_NONBLOCK)));

    return res;
}
