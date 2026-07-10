// Zig port of a12/net/nbio.c — non-blocking I/O for arcan-net / TUI context.
// This is the vendored-from-engine variant: WANT_ARCAN_BASE is NOT defined,
// so no frameserver IPC, no bgcopy, no opennonblock_tgt.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. nbio.zig only references `c.mode_t` and `c.off_t` (the rest of the
// POSIX / libc / Lua surface is sourced via std.posix, std.c, direct extern
// "c" decls, or the `lua` import below). Route both typedefs through
// posix_libc.
const libc = @import("posix");

const c = struct {
    pub const mode_t = libc.mode_t;
    pub const off_t = libc.off_t;
};

const lua = @import("lua_api");

// Types

const lua_State = lua.lua_State;
const lua_Number = lua.lua_Number;
const mode_t = c.mode_t;

// Constants

const LUACTX_OPEN_FILES = 64;

const LUA_NOREF: isize = @intCast(lua.LUA_NOREF);
const LUA_REGISTRYINDEX: c_int = lua.LUA_REGISTRYINDEX;
const LUA_TFUNCTION: c_int = lua.LUA_TFUNCTION;
const LUA_TUSERDATA: c_int = lua.LUA_TUSERDATA;
const LUA_TNIL: c_int = lua.LUA_TNIL;
const LUA_TSTRING: c_int = lua.LUA_TSTRING;
const LUA_TNUMBER: c_int = lua.LUA_TNUMBER;
const LUA_TTABLE: c_int = lua.LUA_TTABLE;
const LUA_TBOOLEAN: c_int = lua.LUA_TBOOLEAN;

// O_* access mode flags — POSIX values, same on Linux/musl
const O_RDONLY: c_uint = 0;
const O_WRONLY: c_uint = 1;
const O_RDWR: c_uint = 2;
const O_NONBLOCK: c_int = 0o4000;
const O_CLOEXEC: c_int = 0o2000000;

// poll events
const POLLOUT: c_short = 4;
const POLLERR: c_short = 8;
const POLLHUP: c_short = 16;
const POLLNVAL: c_short = 32;

// socket/fcntl constants
const AF_UNIX: c_int = 1;
const SOCK_STREAM: c_int = 1;
const SOCK_DGRAM: c_int = 2;
const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const F_GETFD: c_int = 1;
const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;
const S_IRWXU: c_uint = 0o700;
const SEEK_SET: c_int = 0;
const SEEK_CUR: c_int = 1;
const SEEK_END: c_int = 2;

// errno values
const EAGAIN: c_int = 11;
const EINTR: c_int = 4;
const EPROTOTYPE: c_int = 91;

// nbio_local.h equivalents
const RESOURCE_APPL_TEMP: c_int = 1;
const RESOURCE_NS_USER: c_int = 2;
const ARES_FILE: c_int = 1;
const ARES_CREATE: c_int = 256;
const DEFAULT_USERMASK: c_int = 2;

// Structs

const io_job = struct {
    buf: ?[*]u8 = null,
    sz: usize = 0,
    ofs: usize = 0,
    next: ?*io_job = null,
};

// nonblock_io matches the layout in nbio.h exactly.
// This must be `extern struct` so its layout is C-compatible for `pub export fn`
// signatures that take *nonblock_io pointers callable from C.
// Field order, sizes and padding must match the C definition in nbio.h.
// bool in C is _Bool (1 byte); off_t is 8 bytes on 64-bit Linux → 6 bytes
// of padding after the two bools before ofs.
const nonblock_io = extern struct {
    eofm: bool = false,
    lfstrip: bool = false,
    ofs: c.off_t = 0, // NOTE: C inserts 6 bytes padding here on aarch64-linux
    lfch: u8 = '\n',
    fd: c_int = -1, // NOTE: C inserts 3 bytes padding before fd
    out_queued: usize = 0,
    out_count: usize = 0,
    out_queue: ?*anyopaque = null, // logically *io_job
    out_queue_tail: ?*anyopaque = null, // logically **io_job
    mode: mode_t = 0,
    unlink_fn: ?[*:0]u8 = null,
    pending: ?[*:0]u8 = null,
    data_rearmed: bool = false,
    data_handler: isize = 0, // initialised to LUA_NOREF at runtime
    write_handler: isize = 0, // initialised to LUA_NOREF at runtime
    buf: [4096]u8 = [_]u8{0} ** 4096,
};

const pollfd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

const sockaddr_un = extern struct {
    sun_family: c_ushort,
    sun_path: [108]u8,
};

const stat_t = std.posix.Stat;

// Extern declarations

extern fn arcan_random(buf: [*]u8, sz: usize) void;
extern fn arcan_timemillis() c_ulonglong;

// POSIX syscalls we use directly (not via @cImport to avoid type conflicts)
extern fn socket(domain: c_int, typ: c_int, protocol: c_int) c_int;
extern fn bind(sockfd: c_int, addr: *const anyopaque, addrlen: c_uint) c_int;
extern fn connect(sockfd: c_int, addr: *const anyopaque, addrlen: c_uint) c_int;
extern fn listen(sockfd: c_int, backlog: c_int) c_int;
extern fn accept(sockfd: c_int, addr: ?*anyopaque, addrlen: ?*c_uint) c_int;
extern fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern fn poll(fds: *pollfd, nfds: c_uint, timeout: c_int) c_int;
extern fn unlink(path: [*:0]const u8) c_int;
extern fn close(fd: c_int) c_int;
extern fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern fn read(fd: c_int, buf: *anyopaque, count: usize) isize;
extern fn write(fd: c_int, buf: *const anyopaque, count: usize) isize;
extern fn lseek(fd: c_int, offset: c.off_t, whence: c_int) c.off_t;
extern fn fstat(fd: c_int, buf: *stat_t) c_int;
extern fn stat(path: [*:0]const u8, buf: *stat_t) c_int;
extern fn mkfifo(path: [*:0]const u8, mode: c_uint) c_int;
extern fn fchmod(fd: c_int, mode: c_uint) c_int;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern fn strlen(s: [*:0]const u8) usize;
extern fn memmove(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern fn getpid() c_int;

// nbio_local.h stubs: simplified resource lookup for the a12/net context
extern fn arcan_expand_resource(prefix: [*:0]const u8, ns: c_int) ?[*:0]u8;
extern fn arcan_find_resource(prefix: [*:0]const u8, ns: c_int, kind: c_int, dfd: ?*c_int) ?[*:0]u8;

fn S_ISFIFO(m: std.posix.mode_t) bool {
    return (m & std.posix.S.IFMT) == std.posix.S.IFIFO;
}

fn getErrno() c_int {
    return @intCast(std.c._errno().*);
}

// File-scope state

var open_fds: [LUACTX_OPEN_FILES]nonblock_io = blk: {
    var arr: [LUACTX_OPEN_FILES]nonblock_io = undefined;
    for (&arr) |*fd| {
        fd.* = std.mem.zeroes(nonblock_io);
        fd.data_handler = LUA_NOREF;
        fd.write_handler = LUA_NOREF;
    }
    break :blk arr;
};

var add_job: ?*const fn (c_int, mode_t, isize) callconv(.c) bool = null;
var remove_job: ?*const fn (c_int, mode_t, ?*isize) callconv(.c) bool = null;
var trigger_error: ?*const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void = null;

// Internal helpers

fn lookup_registry(L: ?*lua_State, tag: isize, typ: c_int, src: [*c]const u8) bool {
    _ = lua.lua_rawgeti(L, LUA_REGISTRYINDEX, @intCast(tag));
    if (lua.lua_type(L, -1) != typ) {
        if (trigger_error) |te| te(L, -1, tag, src);
        lua.lua_settop(L, -1 - 1);
        return false;
    }
    return true;
}

fn unref_registry(L: ?*lua_State, tag: isize, typ: c_int, src: [*c]const u8) void {
    if (@import("builtin").mode == .Debug) {
        if (lookup_registry(L, tag, typ, src)) {
            lua.lua_settop(L, -1 - 1);
        } else {
            return;
        }
    }
    lua.luaL_unref(L, LUA_REGISTRYINDEX, @intCast(tag));
}

// alt_nbio_nonblock_cloexec

pub export fn alt_nbio_nonblock_cloexec(fd: c_int, is_socket: bool) void {
    _ = is_socket;
    var flags: c_int = fcntl(fd, F_GETFL);
    if (flags != -1)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    flags = fcntl(fd, F_GETFD);
    if (flags != -1)
        _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

// ensure_flush

fn ensure_flush(L: ?*lua_State, ib: *nonblock_io, timeout_arg: usize) bool {
    var rv = true;
    var pfd = pollfd{
        .fd = ib.fd,
        .events = POLLOUT | POLLERR | POLLHUP | POLLNVAL,
        .revents = 0,
    };

    var current = arcan_timemillis();
    var status: c_int = undefined;
    var timeout = timeout_arg;

    while (true) {
        status = alt_nbio_process_write(L, ib);
        if (status != 0) break;

        if (timeout > 0) {
            const now = arcan_timemillis();
            if (now > current)
                timeout -|= @as(usize, @intCast(now - current));
            current = now;
            if (timeout == 0) {
                rv = false;
                break;
            }
        }

        const poll_rv = poll(&pfd, 1, @intCast(timeout));
        if (poll_rv == -1 and (getErrno() == EAGAIN or getErrno() == EINTR))
            continue;

        if ((pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
            rv = false;
            break;
        }
    }

    if (status < 0)
        rv = false;

    return rv;
}

// connect_trypath

fn connect_trypath(local_path: [*:0]const u8, remote: [*:0]const u8, sock_type: c_int) c_int {
    const fd = socket(AF_UNIX, sock_type, 0);
    if (fd == -1) return fd;

    var addr_local: sockaddr_un = std.mem.zeroes(sockaddr_un);
    addr_local.sun_family = @intCast(AF_UNIX);
    _ = snprintf(&addr_local.sun_path, @sizeOf(@TypeOf(addr_local.sun_path)), "%s", local_path);

    var addr_remote: sockaddr_un = std.mem.zeroes(sockaddr_un);
    addr_remote.sun_family = @intCast(AF_UNIX);
    _ = snprintf(&addr_remote.sun_path, @sizeOf(@TypeOf(addr_remote.sun_path)), "%s", remote);

    if (bind(fd, &addr_local, @sizeOf(sockaddr_un)) == -1) {
        _ = close(fd);
        return -1;
    }

    alt_nbio_nonblock_cloexec(fd, true);

    if (connect(fd, &addr_remote, @sizeOf(sockaddr_un)) == -1) {
        _ = unlink(local_path);
        _ = close(fd);
        return -1;
    }

    return fd;
}

// alt_nbio_socket

pub export fn alt_nbio_socket(path: [*:0]const u8, ns: c_int, out: *?[*:0]u8) c_int {
    var local_path: ?[*:0]u8 = null;
    var retry: c_int = 3;

    while (local_path == null and retry > 0) {
        retry -= 1;
        var rnd: c_long = undefined;
        arcan_random(@ptrCast(&rnd), @sizeOf(c_long));
        var tmpname: [32]u8 = undefined;
        _ = snprintf(&tmpname, @sizeOf(@TypeOf(tmpname)), "/tmp/_sock%ld_%d", rnd, getpid());
        const tmppath = arcan_find_resource(@ptrCast(&tmpname), ns, ARES_FILE, null);
        if (tmppath == null) {
            local_path = arcan_expand_resource(@ptrCast(&tmpname), ns);
        } else {
            free(@ptrCast(tmppath));
        }
    }

    const lp = local_path orelse return -1;

    var fd = connect_trypath(lp, path, SOCK_STREAM);

    if (fd == -1) {
        if (getErrno() == EPROTOTYPE)
            fd = connect_trypath(lp, path, SOCK_DGRAM);

        if (fd == -1) {
            _ = unlink(lp);
            free(@ptrCast(lp));
        } else {
            // DGRAM: defer unlink so the other side can respond
            out.* = lp;
        }
    } else {
        _ = unlink(lp);
        free(@ptrCast(lp));
    }

    return fd;
}

// alt_nbio_process_write

pub export fn alt_nbio_process_write(L: ?*lua_State, ib: *nonblock_io) c_int {
    _ = L;
    var job: ?*io_job = @ptrCast(@alignCast(ib.out_queue));

    while (job) |j| {
        const nw = write(ib.fd, j.buf.? + j.ofs, j.sz - j.ofs);
        if (nw == -1) {
            if (getErrno() == EINTR or getErrno() == EAGAIN)
                return 0;
            return -1;
        }

        j.ofs += @intCast(nw);
        ib.out_count += @intCast(nw);

        // slide on completion
        if (j.ofs == j.sz) {
            ib.out_queued -= j.sz;
            ib.out_queue = @ptrCast(j.next);
            free(@ptrCast(j.buf));
            free(@ptrCast(j));
            job = @ptrCast(@alignCast(ib.out_queue));

            if (job == null)
                ib.out_queue_tail = @ptrCast(&ib.out_queue);
        }
    }

    return 1;
}

// drop_all_jobs

fn drop_all_jobs(ib: *nonblock_io) void {
    var job: ?*io_job = @ptrCast(@alignCast(ib.out_queue));
    while (job) |j| {
        const nxt = j.next;
        free(@ptrCast(j.buf));
        free(@ptrCast(j));
        job = nxt;
    }
    ib.out_queue = null;
    ib.out_queue_tail = @ptrCast(&ib.out_queue);
    ib.out_queued = 0;
    ib.out_count = 0;
}

// queue_out

fn queue_out(ib: *nonblock_io, buf: [*]const u8, len: usize) ?*io_job {
    const res_ptr = malloc(@sizeOf(io_job)) orelse return null;
    const res: *io_job = @ptrCast(@alignCast(res_ptr));
    res.* = std.mem.zeroes(io_job);

    const buf_ptr: [*]u8 = @ptrCast(malloc(len) orelse {
        free(res_ptr);
        return null;
    });
    res.buf = buf_ptr;
    @memcpy(buf_ptr[0..len], buf[0..len]);
    res.sz = len;
    ib.out_queued += len;

    if (ib.out_queue_tail == null)
        ib.out_queue_tail = @ptrCast(&ib.out_queue);

    // out_queue_tail points to the next-pointer slot of the last job (or &out_queue)
    const tail_pp: **?*anyopaque = @ptrCast(@alignCast(ib.out_queue_tail.?));
    tail_pp.* = @ptrCast(res);
    ib.out_queue_tail = @ptrCast(&res.next);

    return res;
}

// alt_nbio_close

pub export fn alt_nbio_close(L: ?*lua_State, ibb: [*c][*c]nonblock_io) c_int {
    // ibb is nonblock_io** — dereference once to get the *nonblock_io, check null
    if (ibb == null) return 0;
    const ptr = ibb[0];
    if (ptr == null) return 0;
    const ib: *nonblock_io = ptr;
    const fd = ib.fd;
    if (fd > 0)
        _ = close(fd);

    if (ib.unlink_fn) |uf| {
        _ = unlink(uf);
        free(@ptrCast(uf));
    }

    if (ib.pending) |p| free(@ptrCast(p));
    drop_all_jobs(ib);

    if (ib.data_handler != LUA_NOREF) {
        unref_registry(L, ib.data_handler, LUA_TFUNCTION, "nbio_close_dh");
        ib.data_handler = LUA_NOREF;
    }

    if (ib.write_handler != LUA_NOREF) {
        unref_registry(L, ib.write_handler, LUA_TFUNCTION, "nbio_close_wh");
        ib.write_handler = LUA_NOREF;
    }

    var tag: isize = undefined;
    if (remove_job) |rj| {
        if (rj(fd, O_RDONLY, &tag))
            unref_registry(L, tag, LUA_TUSERDATA, "nbio_close_rdmeta");
        if (rj(fd, O_WRONLY, &tag))
            unref_registry(L, tag, LUA_TUSERDATA, "nbio_close_wrmeta");
    }

    free(@ptrCast(ib));
    ibb[0] = null;

    for (&open_fds) |*ent| {
        if (ent.fd == fd) {
            ent.* = std.mem.zeroes(nonblock_io);
            ent.data_handler = LUA_NOREF;
            ent.write_handler = LUA_NOREF;
            break;
        }
    }

    return 0;
}

// nbio_closer

fn nbio_closer(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    if (ib == null or ib[0] == null) return 0;

    _ = ensure_flush(L, ib[0], 1000);
    _ = alt_nbio_close(L, ib);
    return 0;
}

// nbio_datahandler

fn nbio_datahandler(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    if (ib == null or ib[0] == null) return 0;
    const ibv: *nonblock_io = ib[0];

    if (ibv.data_handler != LUA_NOREF) {
        unref_registry(L, ibv.data_handler, LUA_TFUNCTION, "nbio-dh-reset");
        ibv.data_handler = LUA_NOREF;
    }

    ibv.data_rearmed = true;

    var out: isize = undefined;
    if (remove_job) |rj| {
        if (rj(ibv.fd, O_RDONLY, &out))
            unref_registry(L, out, LUA_TUSERDATA, "nbio-rdonly-meta-reset");
    }

    if (lua.lua_type(L, 2) == LUA_TFUNCTION) {
        var ref: isize = @intCast(lua.luaL_ref(L, LUA_REGISTRYINDEX));
        ibv.data_handler = ref;

        ref = @intCast(lua.luaL_ref(L, LUA_REGISTRYINDEX));
        lua.lua_pushvalue(L, 1);
        lua.lua_pushvalue(L, 1);

        if (add_job) |aj| {
            if (!aj(ibv.fd, O_RDONLY, ref)) {
                unref_registry(L, ref, LUA_TUSERDATA, "nbio-rdonly-meta-fail");
                lua.lua_pushboolean(L, 0);
            }
        }

        lua.lua_pushboolean(L, 1);
        return 1;
    } else if (lua.lua_type(L, 2) == LUA_TNIL) {
        // do nothing
    } else {
        std.debug.panic("open_nonblock:data_handler argument error, expected function or nil", .{});
    }

    lua.lua_pushboolean(L, 1);
    return 1;
}

// nbio_socketclose

fn nbio_socketclose(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIOs")));
    if (ib == null or ib[0] == null) return 0;
    _ = alt_nbio_close(L, ib);
    return 0;
}

// nbio_socketaccept

fn nbio_socketaccept(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIOs")));
    if (ib == null or ib[0] == null) return 0;
    const is: *nonblock_io = ib[0];

    const newfd = accept(is.fd, null, null);
    if (newfd == -1) return 0;

    var flags: c_int = fcntl(newfd, F_GETFL);
    if (flags != -1)
        _ = fcntl(newfd, F_SETFL, flags | O_NONBLOCK);
    flags = fcntl(newfd, F_GETFD);
    if (flags != -1)
        _ = fcntl(newfd, F_SETFD, flags | FD_CLOEXEC);

    const conn_ptr = malloc(@sizeOf(nonblock_io)) orelse {
        _ = close(newfd);
        return 0;
    };
    const conn: *nonblock_io = @ptrCast(@alignCast(conn_ptr));
    conn.* = std.mem.zeroes(nonblock_io);
    conn.fd = newfd;
    conn.mode = O_RDWR;
    conn.data_handler = LUA_NOREF;
    conn.write_handler = LUA_NOREF;
    conn.lfch = '\n';

    const dp_ptr = lua.lua_newuserdata(L, @sizeOf(usize)) orelse {
        _ = close(newfd);
        free(conn_ptr);
        return 0;
    };
    const dp: *usize = @ptrCast(@alignCast(dp_ptr));
    dp.* = @intFromPtr(conn);
    _ = lua.luaL_getmetatable(L, "nonblockIO");
    _ = lua.lua_setmetatable(L, -2);
    return 1;
}

// nbio_writequeue

fn nbio_writequeue(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    if (ib == null or ib[0] == null) {
        lua.lua_pushnumber(L, 0);
        lua.lua_pushnumber(L, 0);
        return 2;
    }
    const iw: *nonblock_io = ib[0];

    if (iw.out_queue == null) {
        lua.lua_pushnumber(L, 0);
        lua.lua_pushnumber(L, 0);
    } else {
        lua.lua_pushnumber(L, @floatFromInt(iw.out_count));
        lua.lua_pushnumber(L, @floatFromInt(iw.out_queued));
    }
    return 2;
}

// nbio_write

fn nbio_write(L: ?*lua_State) callconv(.c) c_int {
    const ud: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    if (ud == null or ud[0] == null) return 0;
    const iw: *nonblock_io = ud[0];

    if (iw.mode == O_RDONLY) return 0;

    var len: usize = 0;
    var buf: ?[*]const u8 = null;

    if (lua.lua_type(L, 2) == LUA_TSTRING) {
        buf = lua.luaL_checklstring(L, 2, &len);
        if (len == 0) return 0;
    } else if (lua.lua_type(L, 2) == LUA_TTABLE) {
        // handled below
    } else {
        std.debug.panic("open_nonblock:write(data, cb) unexpected data type (str or tbl)", .{});
    }

    // special case: FIFO not yet hooked up
    if (iw.fd == -1 and iw.pending != null) {
        iw.fd = open(iw.pending.?, O_NONBLOCK | @as(c_int, @bitCast(O_WRONLY)) | O_CLOEXEC);
        if (iw.fd != -1) {
            var fi: stat_t = undefined;
            if (fstat(iw.fd, &fi) != -1 and !S_ISFIFO(fi.mode)) {
                lua.lua_pushnumber(L, 0);
                lua.lua_pushboolean(L, 0);
                return 2;
            }
        }
    }

    // optional write-completion callback
    if (lua.lua_type(L, 3) == LUA_TFUNCTION) {
        if (iw.write_handler != LUA_NOREF) {
            unref_registry(L, iw.write_handler, LUA_TFUNCTION, "nbio-write-cb-chg");
            iw.write_handler = LUA_NOREF;
        }
        lua.lua_pushvalue(L, 3);
        iw.write_handler = @intCast(lua.luaL_ref(L, LUA_REGISTRYINDEX));
    }

    // table case: queue each string entry
    if (len == 0) {
        const count: isize = @intCast(lua.lua_objlen(L, 2));
        var i: isize = 0;
        while (i < count) : (i += 1) {
            _ = lua.lua_rawgeti(L, 2, @intCast(i + 1));
            var entry_len: usize = 0;
            const entry_buf = lua.lua_tolstring(L, -1, &entry_len);
            if (entry_len == 0) {
                lua.lua_settop(L, -1 - 1);
                continue;
            }
            if (entry_buf == null or queue_out(iw, entry_buf.?, entry_len) == null) {
                drop_all_jobs(iw);
                lua.lua_settop(L, -1 - 1);
                lua.lua_pushnumber(L, 0);
                lua.lua_pushboolean(L, 0);
                return 2;
            }
            lua.lua_settop(L, -1 - 1);
        }
    } else {
        if (queue_out(iw, buf.?, len) == null) {
            lua.lua_pushnumber(L, 0);
            lua.lua_pushboolean(L, 0);
            return 2;
        }
    }

    var ref: isize = undefined;
    if (remove_job) |rj| {
        if (rj(iw.fd, O_WRONLY, &ref))
            unref_registry(L, ref, LUA_TUSERDATA, "nbio-wrmeta-chg");
    }

    lua.lua_pushvalue(L, 1);
    ref = @intCast(lua.luaL_ref(L, LUA_REGISTRYINDEX));
    if (add_job) |aj| _ = aj(iw.fd, O_WRONLY, ref);

    lua.lua_pushnumber(L, @floatFromInt(len));
    lua.lua_pushboolean(L, 1);
    return 2;
}

// nextline

fn nextline(
    ib: *nonblock_io,
    start: usize,
    eof: bool,
    nb: *usize,
    step: *usize,
    gotline: *bool,
    linech: u8,
) ?[*]u8 {
    const ofs: usize = @intCast(ib.ofs);
    if (ofs == 0) return null;

    step.* = 0;

    for (start..ofs) |i| {
        if (ib.buf[i] == linech) {
            nb.* = if (ib.lfstrip) (i - start) else (i - start) + 1;
            step.* = (i - start) + 1;
            gotline.* = true;
            return @ptrCast(&ib.buf[start]);
        }
    }

    const buf_len = @sizeOf(@TypeOf(ib.buf));
    if (eof or (start == 0 and ofs == buf_len)) {
        gotline.* = false;
        if (ofs < start) {
            nb.* = 0;
            step.* = 0;
            ib.ofs = 0;
        } else {
            nb.* = ofs - start;
            step.* = ofs - start;
        }
        return &ib.buf;
    }

    return null;
}

fn slide(ib: *nonblock_io, ci: usize) void {
    const cur_ofs: usize = @intCast(ib.ofs);
    if (ci <= cur_ofs) {
        const remaining = cur_ofs - ci;
        if (remaining > 0) {
            std.mem.copyForwards(u8, ib.buf[0..remaining], ib.buf[ci..][0..remaining]);
        }
        ib.ofs -= @intCast(ci);
    }
}

// alt_nbio_process_read

pub export fn alt_nbio_process_read(
    L: ?*lua_State,
    ib: *nonblock_io,
    nonbuffered: bool,
) c_int {
    const buf_sz: usize = @sizeOf(@TypeOf(ib.buf));

    if (ib.fd < 0) return 0;

    var eof = false;
    const ib_ofs: usize = @intCast(ib.ofs);
    const nr = read(ib.fd, &ib.buf[ib_ofs], buf_sz - ib_ofs);

    if (nr == 0) {
        eof = true;
    } else if (nr == -1) {
        if (getErrno() == EAGAIN or getErrno() == EINTR) {
            if (ib.ofs == 0) {
                lua.lua_pushnil(L);
                lua.lua_pushboolean(L, 1);
                return 2;
            }
        } else {
            eof = true;
        }
    } else {
        ib.ofs += @intCast(nr);
    }

    if (nonbuffered) {
        const cur_ofs: usize = @intCast(ib.ofs);
        if (cur_ofs > 0) {
            _ = lua.lua_pushlstring(L, &ib.buf, cur_ofs);
        } else {
            lua.lua_pushnil(L);
        }
        lua.lua_pushboolean(L, @intFromBool(!eof or cur_ofs > 0));
        ib.ofs = 0;
        return 2;
    }

    var len: usize = 0;
    var step: usize = 0;
    var gotline: bool = false;

    if (lua.lua_type(L, -1) == LUA_TFUNCTION) {
        var ci: usize = 0;
        var cancel = false;

        while (!cancel) {
            const ch = nextline(ib, ci, eof, &len, &step, &gotline, ib.lfch) orelse break;
            lua.lua_pushvalue(L, -1);
            _ = lua.lua_pushlstring(L, ch, len);
            lua.lua_pushboolean(L, @intFromBool(eof and !gotline));
            ci += step;
            lua.lua_call(L, 2, 1);

            const cur_ofs: usize = @intCast(ib.ofs);
            cancel = (lua.lua_toboolean(L, -1) != 0) or (cur_ofs <= ci);
            lua.lua_settop(L, -1 - 1);
        }

        slide(ib, ci);
        lua.lua_pushnil(L);
        lua.lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    } else if (lua.lua_type(L, -1) == LUA_TTABLE) {
        var ind: usize = @intCast(lua.lua_objlen(L, -1) + 1);
        var ci: usize = 0;

        _ = lua.lua_getfield(L, -1, "read_cap");
        var count: usize = @intFromFloat(lua.lua_tonumber(L, -1));
        if (count == 0) count = std.math.maxInt(usize);
        lua.lua_settop(L, -1 - 1);

        while (count > 0 and ci < @as(usize, @intCast(ib.ofs))) {
            const ch = nextline(ib, ci, eof, &len, &step, &gotline, ib.lfch) orelse break;
            if (eof and len == 0 and step == 0) break;

            lua.lua_pushinteger(L, @intCast(ind));
            _ = lua.lua_pushlstring(L, ch, len);
            lua.lua_rawset(L, -3);
            count -= 1;
            ind += 1;
            ci += step;
        }

        slide(ib, ci);
        lua.lua_pushnil(L);
        lua.lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    } else {
        if (nextline(ib, 0, eof, &len, &step, &gotline, ib.lfch)) |ch| {
            _ = lua.lua_pushlstring(L, ch, len);
            const cur_ofs: usize = @intCast(ib.ofs);
            if (step < cur_ofs) {
                std.mem.copyForwards(u8, ib.buf[0 .. buf_sz - step], ib.buf[step..buf_sz]);
                ib.ofs -= @intCast(step);
            } else {
                ib.ofs = 0;
            }
        } else {
            lua.lua_pushnil(L);
        }
        lua.lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    }
}

// luaL_optbnumber / luaL_checkbnumber

pub export fn luaL_optbnumber(L: ?*lua_State, narg: c_int, opt: lua_Number) lua_Number {
    if (lua.lua_isnumber(L, narg) != 0)
        return lua.lua_tonumber(L, narg)
    else if (lua.lua_type(L, narg) == LUA_TBOOLEAN)
        return @floatFromInt(lua.lua_toboolean(L, narg))
    else
        return opt;
}

pub export fn luaL_checkbnumber(L: ?*lua_State, narg: c_int) lua_Number {
    var d: lua_Number = lua.lua_tonumber(L, narg);
    if (d == 0 and lua.lua_isnumber(L, narg) == 0) {
        if (lua.lua_type(L, narg) != LUA_TBOOLEAN) {
            _ = lua.luaL_argerror(L, narg, "number or boolean");
        } else {
            d = @floatFromInt(lua.lua_toboolean(L, narg));
        }
    }
    return d;
}

// nbio_lf

fn nbio_lf(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    if (ib == null or ib[0] == null) return 0;
    const ir: *nonblock_io = ib[0];

    ir.lfstrip = luaL_optbnumber(L, 2, 0) != 0;
    if (lua.lua_type(L, 3) == LUA_TSTRING) {
        const ch_str: [*c]const u8 = lua.lua_tolstring(L, 3, null);
        ir.lfch = ch_str[0];
    }
    return 0;
}

// nbio_read

fn nbio_read(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    if (ib == null or ib[0] == null) return 0;
    const ir: *nonblock_io = ib[0];

    if (ir.mode == O_WRONLY) return 0;

    const nonbuffered = luaL_optbnumber(L, 2, 0) != 0;
    return alt_nbio_process_read(L, ir, nonbuffered);
}

// nbio_seek

fn nbio_seek(L: ?*lua_State) callconv(.c) c_int {
    const ibb: [*c][*c]nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    if (ibb == null or ibb[0] == null) {
        std.debug.panic("nbio:seek on closed file", .{});
    }
    const ib: *nonblock_io = ibb[0];

    const ofs: c.off_t = @intFromFloat(lua.lua_tonumber(L, 1));
    const pos = lseek(ib.fd, ofs, SEEK_CUR);

    lua.lua_pushboolean(L, @intFromBool(pos != -1));
    lua.lua_pushnumber(L, @floatFromInt(pos));
    return 2;
}

// nbio_position

fn nbio_position(L: ?*lua_State) callconv(.c) c_int {
    const ibb: **?*nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    const ib = ibb.*.* orelse {
        std.debug.panic("nbio:set_position on closed file", .{});
    };

    var pos: lua_Number = lua.lua_tonumber(L, 1);
    if (pos < 0)
        pos = @floatFromInt(lseek(ib.fd, @intFromFloat(-pos), SEEK_END))
    else
        pos = @floatFromInt(lseek(ib.fd, @intFromFloat(pos), SEEK_SET));

    lua.lua_pushboolean(L, @intFromBool(pos != -1));
    lua.lua_pushnumber(L, pos);
    return 2;
}

// nbio_flush

fn nbio_flush(L: ?*lua_State) callconv(.c) c_int {
    const ibb: **?*nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "nonblockIO")));
    const ib = ibb.*.* orelse return 0;
    lua.lua_settop(L, -1 - 1);

    if (ib.write_handler != LUA_NOREF or ib.out_queue == null or ib.fd == -1) {
        lua.lua_pushboolean(L, 0);
        return 1;
    }

    const timeout_raw: isize = @intFromFloat(lua.luaL_optnumber(L, 2, -1));
    const timeout: usize = if (timeout_raw < 0) 0 else @intCast(timeout_raw);
    const rv = ensure_flush(L, ib, timeout);

    lua.lua_pushboolean(L, @intFromBool(rv));
    return 1;
}

// alt_nbio_import

pub export fn alt_nbio_import(
    L: ?*lua_State,
    fd: c_int,
    mode: mode_t,
    out: ?*?*nonblock_io,
    unlink_fn: ?*?[*:0]u8,
) bool {
    if (fd == -1) {
        lua.lua_pushnil(L);
        return false;
    }

    if (out) |o| o.* = null;

    const nbio_ptr = malloc(@sizeOf(nonblock_io)) orelse {
        _ = close(fd);
        lua.lua_pushnil(L);
        return false;
    };
    const nbio: *nonblock_io = @ptrCast(@alignCast(nbio_ptr));

    const dp_ptr = lua.lua_newuserdata(L, @sizeOf(usize)) orelse {
        _ = close(fd);
        free(nbio_ptr);
        lua.lua_pushnil(L);
        return false;
    };
    const dp: *usize = @ptrCast(@alignCast(dp_ptr));
    dp.* = @intFromPtr(nbio);

    nbio.* = std.mem.zeroes(nonblock_io);
    nbio.fd = fd;
    nbio.mode = mode;
    nbio.lfch = '\n';
    nbio.unlink_fn = if (unlink_fn) |uf| uf.* else null;
    nbio.write_handler = LUA_NOREF;
    nbio.data_handler = LUA_NOREF;

    if (out) |o| o.* = nbio;

    alt_nbio_nonblock_cloexec(fd, false);
    _ = lua.luaL_getmetatable(L, "nonblockIO");
    _ = lua.lua_setmetatable(L, -2);
    return true;
}

// alt_nbio_release

pub export fn alt_nbio_release() void {
    for (&open_fds) |*ent| {
        if (ent.fd > 0) {
            if (remove_job) |rj| {
                _ = rj(ent.fd, O_RDONLY, null);
                _ = rj(ent.fd, O_WRONLY, null);
            }
            _ = close(ent.fd);
        }
        drop_all_jobs(ent);
        ent.* = std.mem.zeroes(nonblock_io);
        ent.data_handler = LUA_NOREF;
        ent.write_handler = LUA_NOREF;
    }
}

// pathfd

const pathfd = struct {
    path: ?[*:0]u8 = null,
    unlink: ?[*:0]u8 = null,
    err: ?[*:0]const u8 = null,
    metatable: [*:0]const u8 = "nonblockIO",
    fd: c_int = -1,
    wrmode: c_uint = O_RDONLY,
};

// build_fifo_ipc

fn build_fifo_ipc(path: [*:0]u8, userns: bool, expect_write: bool) pathfd {
    var res = pathfd{};
    const ns: c_int = if (userns) RESOURCE_NS_USER else RESOURCE_APPL_TEMP;

    const workpath = arcan_expand_resource(path, ns) orelse {
        res.err = "Couldn't expand FIFO path";
        return res;
    };

    var fi: stat_t = undefined;
    if (stat(path, &fi) == -1) {
        if (expect_write) {
            if (mkfifo(workpath, S_IRWXU) == -1) {
                free(@ptrCast(workpath));
                res.err = "Couldn't build FIFO";
                return res;
            }
            const fd = open(workpath, O_RDWR);
            if (fd == -1) {
                free(@ptrCast(workpath));
                res.err = "Couldn't bind FIFO";
                return res;
            }
            res.unlink = workpath;
            res.fd = fd;
            return res;
        } else {
            res.path = workpath;
            return res;
        }
    }

    const fd = open(workpath, if (expect_write) @as(c_int, @bitCast(O_WRONLY)) else @as(c_int, @bitCast(O_RDONLY)));
    free(@ptrCast(workpath));

    if (fd == -1 or fstat(fd, &fi) == -1 or S_ISFIFO(fi.mode)) {
        if (fd != -1) _ = close(fd);
        res.err = "Couldn't open as FIFO";
        return res;
    }

    var flags: c_int = fcntl(fd, F_GETFL);
    if (flags != -1)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    flags = fcntl(fd, F_GETFD);
    if (flags != -1)
        _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC);

    res.fd = fd;
    return res;
}

// build_socket_ipc

fn build_socket_ipc(pathin: [*:0]u8, userns: bool, srv: bool) pathfd {
    var res = pathfd{};
    const ns: c_int = if (userns) RESOURCE_NS_USER else RESOURCE_APPL_TEMP;

    if (srv) {
        const existing = arcan_find_resource(pathin, ns, ARES_FILE, null);
        if (existing != null) {
            res.err = "EINVAL: Couldn't create socket";
            free(@ptrCast(existing));
            return res;
        }

        const workpath = arcan_expand_resource(pathin, ns) orelse {
            res.err = "EINVAL: Couldn't build socket file";
            return res;
        };

        var addr: sockaddr_un = std.mem.zeroes(sockaddr_un);
        addr.sun_family = @intCast(AF_UNIX);
        const lim = @sizeOf(@TypeOf(addr.sun_path));
        if (strlen(workpath) > lim - 1) {
            res.err = "ENAMETOOLONG: expanded socket doesn't fit sockaddr";
            free(@ptrCast(workpath));
            return res;
        }
        _ = snprintf(&addr.sun_path, lim, "%s", workpath);

        res.fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (res.fd == -1) {
            res.err = "EPERM: couldn't allocate socket";
            free(@ptrCast(workpath));
            return res;
        }
        _ = fchmod(res.fd, S_IRWXU);

        if (bind(res.fd, &addr, @sizeOf(sockaddr_un)) == -1) {
            _ = close(res.fd);
            free(@ptrCast(workpath));
            res.fd = -1;
            res.err = "ESOCKET: couldn't bind socket";
            return res;
        }

        _ = listen(res.fd, 5);
        res.unlink = workpath;
        res.metatable = "nonblockIOs";
        res.wrmode = O_RDWR;
    } else {
        const workpath = arcan_find_resource(pathin, ns, ARES_FILE, null) orelse {
            res.err = "EEXIST: Couldn't connect to socket";
            return res;
        };

        res.fd = alt_nbio_socket(workpath, ns, &res.unlink);
        res.wrmode = O_RDWR;
        res.metatable = "nonblockIO";

        if (res.fd == -1)
            res.err = "EPERM: Couldn't bind to socket";

        free(@ptrCast(workpath));
    }

    return res;
}

// build_new_file

fn build_new_file(path: [*:0]u8, userns: bool) pathfd {
    var res = pathfd{ .metatable = "nonblockIO", .wrmode = O_RDWR };
    const ns: c_int = if (userns) RESOURCE_NS_USER else RESOURCE_APPL_TEMP;

    const userpath = arcan_find_resource(path, ns, ARES_FILE | ARES_CREATE, &res.fd);

    if (userpath == null) {
        res.err = "Couldn't create file in namespace";
    } else {
        free(@ptrCast(userpath));
    }

    return res;
}

// open_existing_file

fn open_existing_file(path: [*:0]u8, userns: bool) pathfd {
    var res = pathfd{ .wrmode = O_RDONLY, .metatable = "nonblockIO" };
    const ns: c_int = if (userns) RESOURCE_NS_USER else DEFAULT_USERMASK;

    const cpath = arcan_find_resource(path, ns, ARES_FILE, &res.fd);
    if (cpath == null)
        res.err = "Couldn't find file";

    free(@ptrCast(cpath));
    return res;
}

// alt_nbio_open

pub export fn alt_nbio_open(L: ?*lua_State) c_int {
    var pfd: pathfd = undefined;
    var userns = false;

    const str_raw: [*:0]const u8 = lua.luaL_checklstring(L, 1, null) orelse return 0;
    const str: [*:0]u8 = strdup(str_raw) orelse return 0;
    defer free(@ptrCast(str));

    const wrmode: c_uint = if (luaL_optbnumber(L, 2, 0) != 0) O_WRONLY else O_RDONLY;

    // check for user namespace prefix: alnum+ ':/' ...
    var i: usize = 0;
    while (str[i] != 0 and std.ascii.isAlphanumeric(str[i])) : (i += 1) {}
    if (str[i] == ':' and str[i + 1] == '/')
        userns = true;

    if (str[0] == '<')
        pfd = build_fifo_ipc(str + 1, userns, wrmode == O_WRONLY)
    else if (str[0] == '=')
        pfd = build_socket_ipc(str + 1, userns, wrmode != O_WRONLY)
    else if (wrmode == O_WRONLY)
        pfd = build_new_file(str, userns)
    else
        pfd = open_existing_file(str, userns);

    if (pfd.err != null) return 0;

    const conn_ptr = malloc(@sizeOf(nonblock_io)) orelse return 0;
    const conn: *nonblock_io = @ptrCast(@alignCast(conn_ptr));
    conn.* = std.mem.zeroes(nonblock_io);
    conn.fd = pfd.fd;
    conn.lfch = '\n';
    alt_nbio_nonblock_cloexec(pfd.fd, true);

    conn.mode = pfd.wrmode;
    conn.pending = pfd.path;
    conn.unlink_fn = pfd.unlink;
    conn.data_handler = LUA_NOREF;
    conn.write_handler = LUA_NOREF;

    const dp_ptr = lua.lua_newuserdata(L, @sizeOf(usize)) orelse {
        free(conn_ptr);
        return 0;
    };
    const dp: *usize = @ptrCast(@alignCast(dp_ptr));
    dp.* = @intFromPtr(conn);

    _ = lua.luaL_getmetatable(L, pfd.metatable);
    _ = lua.lua_setmetatable(L, -2);
    return 1;
}

// alt_nbio_data_out

pub export fn alt_nbio_data_out(L: ?*lua_State, tag_arg: isize) void {
    var tag = tag_arg;
    if (!lookup_registry(L, tag, LUA_TUSERDATA, "data-out")) return;

    const ibb: **?*nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, -1, "nonblockIO")));
    const ib = ibb.*.* orelse return;
    lua.lua_settop(L, -1 - 1);

    if (ib.out_queue == null) return;

    const status = alt_nbio_process_write(L, ib);
    if (status == 0) return;

    if (ib.write_handler == LUA_NOREF) {
        drop_all_jobs(ib);
        return;
    }

    if (!lookup_registry(L, ib.write_handler, LUA_TFUNCTION, "data-out-wh")) return;

    lua.lua_pushboolean(L, @intFromBool(status == 1));
    lua.lua_pushboolean(L, 0); // gpus_locked always false (no WANT_ARCAN_BASE)
    drop_all_jobs(ib);
    lua.lua_call(L, 2, 0);

    if (ib.out_queue == null) {
        if (remove_job) |rj| {
            if (rj(ib.fd, O_WRONLY, &tag))
                unref_registry(L, tag, LUA_TUSERDATA, "nbio-open-wrmeta");
        }
    }
}

// alt_nbio_data_in

pub export fn alt_nbio_data_in(L: ?*lua_State, tag_arg: isize) void {
    var tag = tag_arg;
    if (!lookup_registry(L, tag, LUA_TUSERDATA, "data-in")) return;

    const ibb: **?*nonblock_io = @ptrCast(@alignCast(lua.luaL_checkudata(L, -1, "nonblockIO")));
    const ib = ibb.*.* orelse return;

    lua.lua_settop(L, -1 - 1);
    if (!lookup_registry(L, ib.data_handler, LUA_TFUNCTION, "data-in-dh")) return;

    const ch = ib.data_handler;
    ib.data_rearmed = false;

    lua.lua_pushboolean(L, 0); // gpus_locked always false
    lua.lua_call(L, 1, 1);

    // manually re-armed?
    if (ib.data_rearmed) {
        // keep
    } else if (lua.lua_type(L, -1) == LUA_TBOOLEAN and lua.lua_toboolean(L, -1) != 0) {
        // auto re-arm on true return
    } else {
        unref_registry(L, ch, LUA_TFUNCTION, "data-in-dontwant");
        ib.data_handler = LUA_NOREF;

        if (remove_job) |rj| {
            if (rj(ib.fd, O_RDONLY, &tag))
                unref_registry(L, tag, LUA_TUSERDATA, "data-in-meta-dontwant");
        }
    }
    lua.lua_settop(L, -1 - 1);
}

// alt_nbio_register

pub export fn alt_nbio_register(
    L: ?*lua_State,
    add_fn: *const fn (c_int, mode_t, isize) callconv(.c) bool,
    remove_fn: *const fn (c_int, mode_t, ?*isize) callconv(.c) bool,
    error_fn: *const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void,
) void {
    add_job = add_fn;
    remove_job = remove_fn;
    trigger_error = error_fn;

    // nonblockIO metatable (regular files, pipes, connected sockets)
    _ = lua.luaL_newmetatable(L, "nonblockIO");
    lua.lua_pushvalue(L, -1);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcclosure(L, &nbio_read, 0);
    lua.lua_setfield(L, -2, "read");
    lua.lua_pushcclosure(L, &nbio_write, 0);
    lua.lua_setfield(L, -2, "write");
    lua.lua_pushcclosure(L, &nbio_closer, 0);
    lua.lua_setfield(L, -2, "__gc");
    lua.lua_pushcclosure(L, &nbio_writequeue, 0);
    lua.lua_setfield(L, -2, "outqueue");
    lua.lua_pushcclosure(L, &nbio_datahandler, 0);
    lua.lua_setfield(L, -2, "data_handler");
    lua.lua_pushcclosure(L, &nbio_closer, 0);
    lua.lua_setfield(L, -2, "close");
    lua.lua_pushcclosure(L, &nbio_seek, 0);
    lua.lua_setfield(L, -2, "seek");
    lua.lua_pushcclosure(L, &nbio_position, 0);
    lua.lua_setfield(L, -2, "set_position");
    lua.lua_pushcclosure(L, &nbio_flush, 0);
    lua.lua_setfield(L, -2, "flush");
    lua.lua_pushcclosure(L, &nbio_lf, 0);
    lua.lua_setfield(L, -2, "lf_strip");
    lua.lua_settop(L, -1 - 1);

    // nonblockIOs metatable (listening server sockets)
    _ = lua.luaL_newmetatable(L, "nonblockIOs");
    lua.lua_pushvalue(L, -1);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcclosure(L, &nbio_socketaccept, 0);
    lua.lua_setfield(L, -2, "accept");
    lua.lua_pushcclosure(L, &nbio_socketclose, 0);
    lua.lua_setfield(L, -2, "close");
    lua.lua_pushcclosure(L, &nbio_socketclose, 0);
    lua.lua_setfield(L, -2, "_gc");
    lua.lua_settop(L, -1 - 1);
}
