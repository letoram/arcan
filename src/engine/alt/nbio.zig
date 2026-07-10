// Pure Zig port of engine/alt/nbio.c — non-blocking IO for Lua scripting layer.
// Provides open_nonblock userdata with read/write/close/seek/data_handler methods,
// socket and FIFO IPC, write queue management, and Lua registry integration.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

// All types, constants, and function declarations — pure Zig, no @cImport.
// arcan_boot_compat provides: arcan types/constants/extern fns, Lua API,
// and system libc functions. On freestanding, Lua stubs return 0/null.
const c = @import("arcan_boot_compat");

// Constants

const LUACTX_OPEN_FILES = 64;

const LUA_NOREF = c.LUA_NOREF;
const LUA_REGISTRYINDEX = c.LUA_REGISTRYINDEX;
const LUA_TFUNCTION = c.LUA_TFUNCTION;
const LUA_TUSERDATA = c.LUA_TUSERDATA;
const LUA_TNIL = c.LUA_TNIL;
const LUA_TSTRING = c.LUA_TSTRING;
const LUA_TNUMBER = c.LUA_TNUMBER;
const LUA_TTABLE = c.LUA_TTABLE;
const LUA_TBOOLEAN = c.LUA_TBOOLEAN;

const O_RDONLY: c_uint = @intCast(c.O_RDONLY);
const O_WRONLY: c_uint = @intCast(c.O_WRONLY);
const O_RDWR: c_uint = @intCast(c.O_RDWR);
const O_NONBLOCK: c_int = c.O_NONBLOCK;
const O_CLOEXEC: c_int = c.O_CLOEXEC;

const POLLIN: c_short = @intCast(c.POLLIN);
const POLLOUT: c_short = @intCast(c.POLLOUT);
const POLLERR: c_short = @intCast(c.POLLERR);
const POLLHUP: c_short = @intCast(c.POLLHUP);
const POLLNVAL: c_short = @intCast(c.POLLNVAL);

const AF_UNIX = c.AF_UNIX;
const SOCK_STREAM = c.SOCK_STREAM;
const SOCK_DGRAM = c.SOCK_DGRAM;
const F_GETFL = c.F_GETFL;
const F_SETFL = c.F_SETFL;
const F_GETFD = c.F_GETFD;
const F_SETFD = c.F_SETFD;
const FD_CLOEXEC = c.FD_CLOEXEC;
const S_IRWXU = c.S_IRWXU;
const SEEK_SET = c.SEEK_SET;
const SEEK_CUR = c.SEEK_CUR;
const SEEK_END = c.SEEK_END;
const EAGAIN = c.EAGAIN;
const EINTR = c.EINTR;
const EPROTOTYPE = c.EPROTOTYPE;

// Arcan-specific constants from arcan_boot_compat
const RESOURCE_NS_USER = c.RESOURCE_NS_USER;
const RESOURCE_APPL_TEMP = c.RESOURCE_APPL_TEMP;
const ARES_FILE = c.ARES_FILE;
const ARES_CREATE = c.ARES_CREATE;
const ARES_RDONLY = c.ARES_RDONLY;
const DEFAULT_USERMASK = c.DEFAULT_USERMASK;

const ARCAN_MEM_BINDING = c.ARCAN_MEM_BINDING;
const ARCAN_MEM_BZERO = c.ARCAN_MEM_BZERO;
const ARCAN_MEMALIGN_NATURAL = c.ARCAN_MEMALIGN_NATURAL;

const CB_SOURCE_NONE = c.CB_SOURCE_NONE;
const EP_TRIGGER_NBIO_RD: u64 = c.EP_TRIGGER_NBIO_RD;
const EP_TRIGGER_NBIO_WR: u64 = c.EP_TRIGGER_NBIO_WR;
const EP_TRIGGER_NBIO_DATA: u64 = c.EP_TRIGGER_NBIO_DATA;

const ARCAN_OK: c_int = c.ARCAN_OK;

const SHMIF_BGCOPY_PROGRESS = c.SHMIF_BGCOPY_PROGRESS;

const TARGET_COMMAND_BCHUNK_IN = c.TARGET_COMMAND_BCHUNK_IN;
const TARGET_COMMAND_BCHUNK_OUT = c.TARGET_COMMAND_BCHUNK_OUT;
const EVENT_TARGET = c.EVENT_TARGET;

// Types

const lua_State = c.lua_State;
const lua_Number = c.lua_Number;
const mode_t = c.mode_t;

const nonblock_io = c.nonblock_io;
const io_job = extern struct {
    buf: [*c]u8 = null,
    ofs: usize = 0,
    sz: usize = 0,
    next: ?*io_job = null,
};

const pollfd = c.struct_pollfd;
const sockaddr_un = c.struct_sockaddr_un;
// struct_stat from @cImport fails on musl (struct_timespec is opaque).
// Use Zig's Stat from std.posix which handles platform differences.
const stat_t = std.posix.Stat;
extern fn fstat(fd: c_int, buf: *stat_t) c_int;
extern fn stat(path: [*c]const u8, buf: *stat_t) c_int;
extern fn mkfifo(path: [*c]const u8, mode: mode_t) c_int;
extern fn fchmod(fd: c_int, mode: mode_t) c_int;
fn S_ISFIFO(m: std.posix.mode_t) bool {
    return (m & std.posix.S.IFMT) == std.posix.S.IFIFO;
}

// Extern arcan functions (from arcan_boot_compat or linked at link time)

const arcan_timemillis = c.arcan_timemillis;
const arcan_mem_free = c.arcan_mem_free;
const arcan_warning = c.arcan_warning;
const alt_fatal = c.alt_fatal;
const alt_call = c.alt_call;
// Use c_int overloads — call sites pass c_int ns/mode values
extern fn arcan_find_resource(label: [*c]const u8, ns: c_int, rt: c_int, dfd: ?*c_int) [*c]u8;
extern fn arcan_expand_resource(label: [*c]const u8, ns: c_int) [*c]u8;
extern fn arcan_alloc_mem(sz: usize, kind: c_int, flags: c_int, alignment: c_int) ?*anyopaque;
const arcan_conductor_gpus_locked = c.arcan_conductor_gpus_locked;
const arcan_shmif_bgcopy = c.arcan_shmif_bgcopy;
const strdup = c.strdup;

// Arcan-specific types from arcan_boot_compat
const arcan_event = c.arcan_event;
const arcan_vobject = c.arcan_vobject;
const ARCAN_TAG_FRAMESERV: c_int = c.ARCAN_TAG_FRAMESERV;
extern fn luaL_checkvid(L: ?*lua_State, num: c_int, dptr: ?*?*arcan_vobject) i64;

// Use anyopaque for fsrv parameter — the actual struct is opaque due to bitfields
extern fn platform_fsrv_pushfd(fsrv: ?*anyopaque, ev: ?*arcan_event, fd: c_int) c_int;

extern var lua_vid_base: c_uint;
extern var lua_debug_level: c_uint;

// File-scope static state

var open_fds: [LUACTX_OPEN_FILES]nonblock_io = init_open_fds();
fn init_open_fds() [LUACTX_OPEN_FILES]nonblock_io {
    var fds: [LUACTX_OPEN_FILES]nonblock_io = undefined;
    for (&fds) |*fd| {
        fd.* = std.mem.zeroes(nonblock_io);
        fd.data_handler = LUA_NOREF;
        fd.write_handler = LUA_NOREF;
    }
    return fds;
}

var add_job: ?*const fn (c_int, mode_t, isize) callconv(.c) bool = null;
var remove_job: ?*const fn (c_int, mode_t, ?*isize) callconv(.c) bool = null;
var trigger_error: ?*const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void = null;

// Internal helpers

fn lookup_registry(L: ?*lua_State, tag: isize, typ: c_int, src: [*c]const u8) bool {
    _ = c.lua_rawgeti(L, LUA_REGISTRYINDEX, @intCast(tag));
    if (c.lua_type(L, -1) != typ) {
        if (trigger_error) |te| {
            te(L, -1, tag, src);
        }
        c.lua_settop(L, -1 - 1); // lua_pop(L, 1)
        return false;
    }
    return true;
}

fn unref_registry(L: ?*lua_State, tag: isize, typ: c_int, src: [*c]const u8) void {
    // In debug builds, verify the registry entry before unreferencing
    // (matching the #ifdef _DEBUG in C)
    if (@import("builtin").mode == .Debug) {
        if (lookup_registry(L, tag, typ, src)) {
            c.lua_settop(L, -1 - 1);
        } else {
            return;
        }
    }
    c.luaL_unref(L, LUA_REGISTRYINDEX, @intCast(tag));
}

fn cstr(s: [*c]const u8) []const u8 {
    if (s == null) return "";
    return std.mem.sliceTo(s, 0);
}

fn getErrno() c_int {
    return @intCast(std.c._errno().*);
}

// alt_nbio_nonblock_cloexec

export fn alt_nbio_nonblock_cloexec(fd: c_int, is_socket: bool) void {
    if (is_freestanding) return;
    _ = is_socket;
    // __APPLE__ SO_NOSIGPIPE handling omitted — Linux only

    var flags: c_int = c.fcntl(fd, F_GETFL);
    if (flags != -1)
        _ = c.fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    flags = c.fcntl(fd, F_GETFD);
    if (flags != -1)
        _ = c.fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
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

        const poll_rv = c.poll(&pfd, 1, @intCast(timeout));
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

fn connect_trypath(local: [*c]const u8, remote: [*c]const u8, sock_type: c_int) c_int {
    const fd = c.socket(AF_UNIX, sock_type, 0);
    if (fd == -1)
        return fd;

    var addr_local: sockaddr_un = std.mem.zeroes(sockaddr_un);
    addr_local.sun_family = AF_UNIX;
    _ = c.snprintf(&addr_local.sun_path, @sizeOf(@TypeOf(addr_local.sun_path)), "%s", local);

    var addr_remote: sockaddr_un = std.mem.zeroes(sockaddr_un);
    addr_remote.sun_family = AF_UNIX;
    _ = c.snprintf(&addr_remote.sun_path, @sizeOf(@TypeOf(addr_remote.sun_path)), "%s", remote);

    const rv = c.bind(fd, @ptrCast(&addr_local), @sizeOf(sockaddr_un));
    if (rv == -1) {
        _ = c.close(fd);
        return -1;
    }

    alt_nbio_nonblock_cloexec(fd, true);

    if (c.connect(fd, @ptrCast(&addr_remote), @sizeOf(sockaddr_un)) == -1) {
        _ = c.unlink(local);
        _ = c.close(fd);
        return -1;
    }

    return fd;
}

// alt_nbio_socket

export fn alt_nbio_socket(path: [*c]const u8, ns: c_int, out: *[*c]u8) c_int {
    if (is_freestanding) return -1;
    var local_path: [*c]u8 = null;
    var retry: c_int = 3;

    while (local_path == null and retry > 0) {
        retry -= 1;
        var tmpname: [32]u8 = undefined;
        const rnd = c.random();
        _ = c.snprintf(&tmpname, @sizeOf(@TypeOf(tmpname)), "/tmp/_sock%ld_%d", rnd, c.getpid());
        const tmppath: [*c]u8 = arcan_find_resource(&tmpname, ns, ARES_FILE, null);
        if (tmppath == null) {
            local_path = arcan_expand_resource(&tmpname, ns);
        } else {
            c.free(@ptrCast(tmppath));
        }
    }

    if (local_path == null)
        return -1;

    var fd = connect_trypath(local_path, path, SOCK_STREAM);

    if (fd == -1) {
        if (getErrno() == EPROTOTYPE) {
            fd = connect_trypath(local_path, path, SOCK_DGRAM);
        }
        if (fd == -1) {
            _ = c.unlink(local_path);
            arcan_mem_free(@ptrCast(local_path));
        } else {
            // DGRAM — defer unlinking so the other side can respond
            out.* = local_path;
        }
    } else {
        _ = c.unlink(local_path);
        arcan_mem_free(@ptrCast(local_path));
    }

    return fd;
}

// alt_nbio_process_write

export fn alt_nbio_process_write(L: ?*lua_State, ib: *nonblock_io) c_int {
    if (is_freestanding) return 0;
    _ = L;
    var job: ?*io_job = @ptrCast(@alignCast(ib.out_queue));

    while (job) |j| {
        const nw = c.write(ib.fd, j.buf + j.ofs, j.sz - j.ofs);
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
            arcan_mem_free(@ptrCast(j.buf));
            arcan_mem_free(@ptrCast(j));
            job = @ptrCast(@alignCast(ib.out_queue));

            // edge case: all jobs finished, drop tail
            if (job == null)
                ib.out_queue_tail = @ptrCast(&ib.out_queue);
        }
    }

    // when no more jobs, return true -> trigger callback
    return 1;
}

// drop_all_jobs

fn drop_all_jobs(ib: *nonblock_io) void {
    var job: ?*io_job = @ptrCast(@alignCast(ib.out_queue));
    while (job) |j| {
        const next = j.next;
        arcan_mem_free(@ptrCast(j.buf));
        arcan_mem_free(@ptrCast(j));
        job = next;
    }
    ib.out_queue = null;
    ib.out_queue_tail = @ptrCast(&ib.out_queue);
    ib.out_queued = 0;
    ib.out_count = 0;
}

// queue_out

fn queue_out(
    ib: *nonblock_io,
    buf: [*c]const u8,
    len_arg: usize,
    suffix: [*c]const u8,
    suffix_len: usize,
) ?*io_job {
    // attempted overflow check
    if (suffix_len + len_arg < len_arg)
        return null;

    var len = len_arg;

    const res_ptr = c.malloc(@sizeOf(io_job)) orelse return null;
    const res: *io_job = @ptrCast(@alignCast(res_ptr));
    res.* = std.mem.zeroes(io_job);

    const total = len + suffix_len;
    const buf_ptr: [*c]u8 = @ptrCast(c.malloc(total) orelse {
        c.free(res_ptr);
        return null;
    });
    res.buf = buf_ptr;

    // copy so lua can drop the buffer
    @memcpy(res.buf[0..len], buf[0..len]);

    if (suffix_len > 0) {
        @memcpy(res.buf[len..][0..suffix_len], suffix[0..suffix_len]);
        len += suffix_len;
    }

    res.sz = len;
    ib.out_queued += len;

    // remember tail so next queue is faster
    if (ib.out_queue_tail == null) {
        ib.out_queue_tail = @ptrCast(&ib.out_queue);
    }

    // append and step tail -- out_queue_tail is logically **io_job stored as ?*anyopaque
    const tail_pp: *?*anyopaque = @ptrCast(@alignCast(ib.out_queue_tail.?));
    tail_pp.* = @ptrCast(res);
    ib.out_queue_tail = @ptrCast(&res.next);

    return res;
}

// alt_nbio_close

export fn alt_nbio_close(L: ?*lua_State, ibb: *?*nonblock_io) c_int {
    if (is_freestanding) return 0;
    const ib = ibb.* orelse return 0;
    const fd = ib.fd;
    if (fd > 0)
        _ = c.close(fd);

    if (ib.unlink_fn) |uf| {
        _ = c.unlink(uf);
        arcan_mem_free(@ptrCast(uf));
    }

    c.free(@ptrCast(ib.pending));
    drop_all_jobs(ib);

    if (ib.data_handler != LUA_NOREF) {
        unref_registry(L, ib.data_handler, LUA_TFUNCTION, "nbio_close_dh");
        ib.data_handler = LUA_NOREF;
    }

    if (ib.write_handler != LUA_NOREF) {
        unref_registry(L, ib.write_handler, LUA_TFUNCTION, "nbio_close_wh");
        ib.write_handler = LUA_NOREF;
    }

    // no-op if nothing registered
    var tag: isize = undefined;
    if (remove_job) |rj| {
        if (rj(fd, O_RDONLY, &tag)) {
            unref_registry(L, tag, LUA_TUSERDATA, "nbio_close_rdmeta");
        }
        if (rj(fd, O_WRONLY, &tag)) {
            unref_registry(L, tag, LUA_TUSERDATA, "nbio_close_wrmeta");
        }
    }

    c.free(@ptrCast(ib));
    ibb.* = null;

    // remove the entry from open_fds
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
    const ib: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    if (ib.* == null)
        return 0;

    _ = ensure_flush(L, ib.*.?, 1000);
    _ = alt_nbio_close(L, ib);
    return 0;
}

// nbio_datahandler

fn nbio_datahandler(L: ?*lua_State) callconv(.c) c_int {
    const ib: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const ibv = ib.* orelse return 0;

    // always remove the last known handler refs
    if (ibv.data_handler != LUA_NOREF) {
        unref_registry(L, ibv.data_handler, LUA_TFUNCTION, "nbio-dh-reset");
        ibv.data_handler = LUA_NOREF;
    }

    // tracking to detect nbio_data_in -> cb -> data_handler
    ibv.data_rearmed = true;

    // remove the reference used to tag events
    var out: isize = undefined;
    if (remove_job) |rj| {
        if (rj(ibv.fd, O_RDONLY, &out)) {
            unref_registry(L, out, LUA_TUSERDATA, "nbio-rdonly-meta-reset");
        }
    }

    if (c.lua_type(L, 2) == LUA_TFUNCTION) {
        var ref: isize = @intCast(c.luaL_ref(L, LUA_REGISTRYINDEX));
        ibv.data_handler = ref;

        // get the reference to the userdata and attach to event-source
        ref = @intCast(c.luaL_ref(L, LUA_REGISTRYINDEX));

        // luaL_ pops the stack so rebalance
        c.lua_pushvalue(L, 1);
        c.lua_pushvalue(L, 1);

        // the job can fail if too many read_handler descriptors
        if (add_job) |aj| {
            if (!aj(ibv.fd, O_RDONLY, ref)) {
                unref_registry(L, ref, LUA_TUSERDATA, "nbio-rdonly-meta-fail");
                c.lua_pushboolean(L, 0);
            }
        }

        c.lua_pushboolean(L, 1);
        return 1;
    } else if (c.lua_type(L, 2) == LUA_TNIL) {
        // do nothing
    } else {
        alt_fatal("open_nonblock:data_handler argument error, expected function or nil");
    }

    c.lua_pushboolean(L, 1);
    return 1;
}

// nbio_socketclose

fn nbio_socketclose(L: ?*lua_State) callconv(.c) c_int {
    const ib: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIOs")));
    if (ib.* == null)
        return 0;

    _ = alt_nbio_close(L, ib);
    return 0;
}

// nbio_socketaccept

fn nbio_socketaccept(L: ?*lua_State) callconv(.c) c_int {
    const ib: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIOs")));
    const is = ib.* orelse return 0;

    const newfd = c.accept(is.fd, null, null);
    if (newfd == -1)
        return 0;

    var flags: c_int = c.fcntl(newfd, F_GETFL);
    if (flags != -1)
        _ = c.fcntl(newfd, F_SETFL, flags | O_NONBLOCK);

    flags = c.fcntl(newfd, F_GETFD);
    if (flags != -1)
        _ = c.fcntl(newfd, F_SETFD, flags | FD_CLOEXEC);

    const conn_ptr = arcan_alloc_mem(
        @sizeOf(nonblock_io),
        ARCAN_MEM_BINDING,
        0,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse {
        _ = c.close(newfd);
        return 0;
    };
    const conn: *nonblock_io = @ptrCast(@alignCast(conn_ptr));
    conn.* = std.mem.zeroes(nonblock_io);
    conn.fd = newfd;
    conn.mode = O_RDWR;
    conn.data_handler = LUA_NOREF;
    conn.write_handler = LUA_NOREF;
    conn.lfch = '\n';

    const dp: *usize = @ptrCast(@alignCast(c.lua_newuserdata(L, @sizeOf(usize)) orelse {
        _ = c.close(newfd);
        arcan_mem_free(conn_ptr);
        return 0;
    }));
    dp.* = @intFromPtr(conn);
    c.luaL_getmetatable(L, "nonblockIO");
    _ = c.lua_setmetatable(L, -2);

    return 1;
}

// nbio_writequeue

fn nbio_writequeue(L: ?*lua_State) callconv(.c) c_int {
    const ib: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const iw = ib.* orelse {
        c.lua_pushnumber(L, 0);
        c.lua_pushnumber(L, 0);
        return 2;
    };

    if (iw.out_queue == null) {
        c.lua_pushnumber(L, 0);
        c.lua_pushnumber(L, 0);
    } else {
        c.lua_pushnumber(L, @floatFromInt(iw.out_count));
        c.lua_pushnumber(L, @floatFromInt(iw.out_queued));
    }

    return 2;
}

// nbio_write

fn nbio_write(L: ?*lua_State) callconv(.c) c_int {
    const ud: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const iw = ud.* orelse return 0;

    if (iw.mode == O_RDONLY)
        return 0;

    var len: usize = 0;
    var buf: [*c]const u8 = null;

    if (c.lua_type(L, 2) == LUA_TSTRING) {
        buf = c.luaL_checklstring(L, 2, &len);
        if (len == 0)
            return 0;
    } else if (c.lua_type(L, 2) == LUA_TTABLE) {
        // handled later
    } else {
        alt_fatal("open_nonblock:write(data, cb) unexpected data type (str or tbl)");
    }

    // special case for FIFOs that aren't hooked up on creation
    if (iw.fd == -1 and iw.pending != null) {
        iw.fd = c.open(iw.pending, O_NONBLOCK | O_WRONLY | O_CLOEXEC);

        if (iw.fd != -1) {
            // FIFO sanity check is posix-only; windows has no FIFOs (windows port)
            const not_fifo = if (builtin.os.tag == .windows) false else blk: {
                var fi: stat_t = undefined;
                break :blk (fstat(iw.fd, &fi) != -1 and !S_ISFIFO(fi.mode));
            };
            if (not_fifo) {
                c.lua_pushnumber(L, 0);
                c.lua_pushboolean(L, 0);
                return 2;
            }
        }
    }

    // might be swapping out one handler for another
    if (c.lua_type(L, 3) == LUA_TFUNCTION) {
        if (iw.write_handler != LUA_NOREF) {
            unref_registry(L, iw.write_handler, LUA_TFUNCTION, "nbio-write-cb-chg");
            iw.write_handler = LUA_NOREF;
        }

        c.lua_pushvalue(L, 3);
        iw.write_handler = @intCast(c.luaL_ref(L, LUA_REGISTRYINDEX));
    }

    // table case: iterate and queue each entry
    if (len == 0) {
        _ = c.lua_getfield(L, 2, "suffix");
        var suffix: [*c]u8 = null;
        var suffix_len: usize = 0;
        if (c.lua_type(L, -1) == LUA_TSTRING) {
            suffix = strdup(c.lua_tolstring(L, -1, &suffix_len));
        }
        c.lua_settop(L, -1 - 1); // lua_pop(L, 1)

        const count: isize = @intCast(c.lua_objlen(L, 2));
        var i: isize = 0;
        while (i < count) : (i += 1) {
            _ = c.lua_rawgeti(L, 2, @intCast(i + 1));
            var line_len: usize = 0;
            buf = c.lua_tolstring(L, -1, &line_len);
            if (line_len == 0) {
                if (suffix_len == 0) {
                    c.lua_settop(L, -1 - 1);
                    continue;
                }
                buf = "";
                line_len = 0;
            }

            if (buf == null or queue_out(iw, buf, line_len, suffix, suffix_len) == null) {
                drop_all_jobs(iw);
                c.lua_settop(L, -1 - 1);
                c.lua_pushnumber(L, 0);
                c.lua_pushboolean(L, 0);
                c.free(@ptrCast(suffix));
                return 2;
            }
            c.lua_settop(L, -1 - 1);
        }
    } else {
        if (queue_out(iw, buf, len, null, 0) == null) {
            c.lua_pushnumber(L, 0);
            c.lua_pushboolean(L, 0);
            return 2;
        }
    }

    // replace any existing job reference
    var ref: isize = undefined;
    if (remove_job) |rj| {
        if (rj(iw.fd, O_WRONLY, &ref)) {
            unref_registry(L, ref, LUA_TUSERDATA, "nbio-wrmeta-chg");
        }
    }

    // register the ref and the write mode to some outer dispatch
    c.lua_pushvalue(L, 1);
    ref = @intCast(c.luaL_ref(L, LUA_REGISTRYINDEX));
    if (add_job) |aj| _ = aj(iw.fd, O_WRONLY, ref);

    c.lua_pushnumber(L, @floatFromInt(len));
    c.lua_pushboolean(L, 1);
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
) ?[*c]u8 {
    const ofs: usize = @intCast(ib.ofs);

    // empty input buffer? early out
    if (ofs == 0)
        return null;

    step.* = 0;

    // consume each character in buffer
    for (start..ofs) |i| {
        if (ib.buf[i] == linech) {
            nb.* = if (ib.lfstrip) (i - start) else (i - start) + 1;
            step.* = (i - start) + 1;
            gotline.* = true;
            return &ib.buf[start];
        }
    }

    const buf_len = @as(usize, @sizeOf(@TypeOf(ib.buf)));

    // full without separator or at end-of-source
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

// alt_nbio_process_read

export fn alt_nbio_process_read(
    L: ?*lua_State,
    ib: *nonblock_io,
    nonbuffered: bool,
) c_int {
    if (is_freestanding) return 0;
    const buf_sz: usize = @sizeOf(@TypeOf(ib.buf));

    if (ib.fd < 0)
        return 0;

    var eof = false;
    const ib_ofs: usize = @intCast(ib.ofs);
    const nr = c.read(ib.fd, &ib.buf[@intCast(ib.ofs)], buf_sz - ib_ofs);

    if (nr == 0) {
        eof = true;
    } else if (nr == -1) {
        if (getErrno() == EAGAIN or getErrno() == EINTR) {
            if (ib.ofs == 0) {
                c.lua_pushnil(L);
                c.lua_pushboolean(L, 1);
                if (ib.ofs == 0)
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
        if (cur_ofs > 0)
            c.lua_pushlstring(L, &ib.buf, cur_ofs)
        else
            c.lua_pushnil(L);
        c.lua_pushboolean(L, @intFromBool(!eof or cur_ofs > 0));
        ib.ofs = 0;
        return 2;
    }

    // three different transfer modes based on the top argument:
    // 1. function callback
    // 2. append to table
    // 3. return first string

    var len: usize = 0;
    var step: usize = 0;
    var gotline: bool = false;

    if (c.lua_type(L, -1) == LUA_TFUNCTION) {
        var ci: usize = 0;
        var cancel = false;

        while (!cancel) {
            const ch = nextline(ib, ci, eof, &len, &step, &gotline, @intCast(ib.lfch)) orelse break;
            c.lua_pushvalue(L, -1);
            c.lua_pushlstring(L, ch, len);
            c.lua_pushboolean(L, @intFromBool(eof and !gotline));
            ci += step;
            alt_call(L, CB_SOURCE_NONE, EP_TRIGGER_NBIO_RD, 0, 2, 1, "nbio:read_cb");

            const cur_ofs: usize = @intCast(ib.ofs);
            cancel = (c.lua_toboolean(L, -1) != 0) or (cur_ofs <= ci);
            c.lua_settop(L, -1 - 1);
        }

        // SLIDE
        slide(ib, ci);

        c.lua_pushnil(L);
        c.lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    } else if (c.lua_type(L, -1) == LUA_TTABLE) {
        var ind: usize = @intCast(c.lua_objlen(L, -1) + 1);
        var ci: usize = 0;

        // read_cap field for limiting lines per call
        _ = c.lua_getfield(L, -1, "read_cap");
        var count: usize = @intFromFloat(c.lua_tonumber(L, -1));
        if (count == 0) count = std.math.maxInt(usize);
        c.lua_settop(L, -1 - 1);

        while (count > 0 and ci < @as(usize, @intCast(ib.ofs))) {
            const ch = nextline(ib, ci, eof, &len, &step, &gotline, @intCast(ib.lfch)) orelse break;
            if (eof and len == 0 and step == 0)
                break;

            c.lua_pushinteger(L, @intCast(ind));
            c.lua_pushlstring(L, ch, len);
            c.lua_rawset(L, -3);
            count -= 1;
            ind += 1;

            ci += step;
        }

        // SLIDE
        slide(ib, ci);

        c.lua_pushnil(L);
        c.lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    } else {
        if (nextline(ib, 0, eof, &len, &step, &gotline, @intCast(ib.lfch))) |ch| {
            c.lua_pushlstring(L, ch, len);

            const cur_ofs: usize = @intCast(ib.ofs);
            if (step < cur_ofs) {
                std.mem.copyBackwards(u8, ib.buf[0 .. buf_sz - step], ib.buf[step..buf_sz]);
                ib.ofs -= @intCast(step);
            } else {
                ib.ofs = 0;
            }
        } else {
            c.lua_pushnil(L);
        }

        c.lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    }
}

fn slide(ib: *nonblock_io, ci: usize) void {
    const cur_ofs: usize = @intCast(ib.ofs);
    if (ci <= cur_ofs) {
        const remaining = cur_ofs - ci;
        if (remaining > 0) {
            std.mem.copyBackwards(u8, ib.buf[0..remaining], ib.buf[ci..][0..remaining]);
        }
        ib.ofs -= @intCast(ci);
    }
}

// luaL_optbnumber

export fn luaL_optbnumber(L: ?*lua_State, narg: c_int, opt: lua_Number) bool {
    if (is_freestanding) return false;
    if (c.lua_isnumber(L, narg) != 0)
        return c.lua_tonumber(L, narg) != 0
    else if (c.lua_isboolean(L, narg))
        return c.lua_toboolean(L, narg) != 0
    else
        return opt != 0;
}

// luaL_checkbnumber

export fn luaL_checkbnumber(L: ?*lua_State, narg: c_int) bool {
    if (is_freestanding) return false;
    var d: lua_Number = c.lua_tonumber(L, narg);
    if (d == 0 and c.lua_isnumber(L, narg) == 0) {
        if (!c.lua_isboolean(L, narg)) {
            _ = c.luaL_argerror(L, narg, "number or boolean");
        } else {
            d = @floatFromInt(c.lua_toboolean(L, narg));
        }
    }
    return d != 0;
}

// nbio_lf

fn nbio_lf(L: ?*lua_State) callconv(.c) c_int {
    const ib: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const ir = ib.* orelse return 0;

    ir.lfstrip = luaL_optbnumber(L, 2, 0);

    if (c.lua_type(L, 3) == LUA_TSTRING) {
        const ch_str: [*c]const u8 = c.lua_tolstring(L, 3, null);
        ir.lfch = ch_str[0];
    }

    return 0;
}

// nbio_read

fn nbio_read(L: ?*lua_State) callconv(.c) c_int {
    const ib: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const ir = ib.* orelse return 0;

    if (ir.mode == O_WRONLY)
        return 0;

    const nonbuffered = luaL_optbnumber(L, 2, 0);
    return alt_nbio_process_read(L, ir, nonbuffered);
}

// bgcopy (WANT_ARCAN_BASE)

fn bgcopy(L: ?*lua_State) callconv(.c) c_int {
    const src_ud: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const src = src_ud.* orelse return 0;
    const dst_ud: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 2, "nonblockIO")));
    const dst = dst_ud.* orelse return 0;

    if (src.mode == O_WRONLY)
        alt_fatal("nbio:bgcopy(>src<, dst) - source is not in read-mode");

    if (dst.mode == O_RDONLY)
        alt_fatal("nbio:bgcopy(src, >dst<) - destination is not in write-mode");

    // create a new pipe pair for progress data
    var outp: [2]c_int = undefined;
    if (c.pipe(&outp) == -1) {
        c.lua_pushboolean(L, 0);
        return 1;
    }

    _ = c.fcntl(outp[0], F_SETFD, FD_CLOEXEC);
    _ = c.fcntl(outp[1], F_SETFD, FD_CLOEXEC);

    if (remove_job) |rj| {
        _ = rj(src.fd, src.mode, null);
        _ = rj(dst.fd, dst.mode, null);
    }

    const conn_ptr = arcan_alloc_mem(
        @sizeOf(nonblock_io),
        ARCAN_MEM_BINDING,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse {
        _ = c.close(outp[0]);
        _ = c.close(outp[1]);
        c.lua_pushboolean(L, 0);
        return 1;
    };
    const conn: *nonblock_io = @ptrCast(@alignCast(conn_ptr));
    conn.* = std.mem.zeroes(nonblock_io);
    conn.fd = outp[0];
    conn.mode = O_RDONLY;
    conn.data_handler = LUA_NOREF;
    conn.write_handler = LUA_NOREF;
    conn.lfch = '\n';

    const dp_ptr = c.lua_newuserdata(L, @sizeOf(usize)) orelse {
        _ = c.close(outp[0]);
        _ = c.close(outp[1]);
        c.lua_pushboolean(L, 0);
        return 1;
    };
    const dp: *usize = @ptrCast(@alignCast(dp_ptr));
    dp.* = @intFromPtr(conn);
    c.luaL_getmetatable(L, "nonblockIO");
    _ = c.lua_setmetatable(L, -2);

    arcan_shmif_bgcopy(null, src.fd, dst.fd, outp[1], SHMIF_BGCOPY_PROGRESS);
    src.fd = -1;
    dst.fd = -1;

    return 1;
}

// opennonblock_tgt (WANT_ARCAN_BASE)

fn opennonblock_tgt(L: ?*lua_State) c_int {
    var vobj: ?*arcan_vobject = null;
    _ = luaL_checkvid(L, 1, &vobj);
    const vobj_nn = vobj.?;
    const fsrv: ?*anyopaque = @ptrCast(vobj_nn.feed.state.ptr);

    if (vobj_nn.feed.state.tag != ARCAN_TAG_FRAMESERV)
        alt_fatal("open_nonblock(tgt), target must be a valid frameserver.");

    var wr: c_uint = O_RDONLY;
    var aflag: c_int = 0;

    if (c.lua_type(L, 2) == LUA_TTABLE) {
        _ = c.lua_getfield(L, 2, "write");
        if (c.lua_toboolean(L, -1) != 0)
            wr = O_WRONLY;
        c.lua_settop(L, -1 - 1);

        _ = c.lua_getfield(L, 2, "parallel");
        if (c.lua_toboolean(L, -1) != 0)
            aflag |= 1;
        c.lua_settop(L, -1 - 1);
    } else {
        wr = if (luaL_optbnumber(L, 2, 0)) O_WRONLY else O_RDONLY;
    }

    const type_str: [*c]const u8 = c.luaL_optlstring(L, 3, "stream", null);

    var ev: arcan_event = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @intCast(EVENT_TARGET);

    const type_slice = cstr(type_str);
    var type_offset: [*c]const u8 = type_str;
    if (type_slice.len > 6 and std.mem.eql(u8, type_slice[0..6], "appl:/")) {
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = 1;
        type_offset = type_str + 6;
    }
    _ = c.snprintf(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message, @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)), "%s", type_offset);

    // overloaded form: open_nonblock(vid, r | w, type, nbio_ud)
    if (c.lua_type(L, 4) == LUA_TUSERDATA) {
        const ibb: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 4, "nonblockIO")));
        if (ibb.*) |ib| {
            if (ib.fd > 0) {
                ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = if (ib.mode == O_WRONLY)
                    TARGET_COMMAND_BCHUNK_OUT
                else
                    TARGET_COMMAND_BCHUNK_IN;
                _ = platform_fsrv_pushfd(fsrv, &ev, ib.fd);
                _ = c.close(ib.fd);
                ib.fd = -1;
            }
        }

        return 0;
    }

    // WRITE mode = 'INPUT' in the client space
    var outp: [2]c_int = undefined;
    if (c.pipe(&outp) == -1) {
        arcan_warning("open_nonblock(tgt), pipe-pair creation failed: %d\n", getErrno());
        return 0;
    }

    var dst_fd: c_int = undefined;
    var src_fd: c_int = undefined;
    if (wr != 0) {
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = TARGET_COMMAND_BCHUNK_IN;
        dst_fd = outp[0];
        src_fd = outp[1];
    } else {
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = TARGET_COMMAND_BCHUNK_OUT;
        dst_fd = outp[1];
        src_fd = outp[0];
    }

    alt_nbio_nonblock_cloexec(src_fd, true);
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = aflag;
    if (platform_fsrv_pushfd(fsrv, &ev, dst_fd) != ARCAN_OK) {
        _ = c.close(dst_fd);
        _ = c.close(src_fd);
        return 0;
    }
    _ = c.close(dst_fd);

    const conn_ptr = arcan_alloc_mem(
        @sizeOf(nonblock_io),
        ARCAN_MEM_BINDING,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse {
        _ = c.close(src_fd);
        return 0;
    };
    const conn: *nonblock_io = @ptrCast(@alignCast(conn_ptr));
    conn.* = std.mem.zeroes(nonblock_io);
    conn.mode = if (wr != 0) O_WRONLY else O_RDONLY;
    conn.fd = src_fd;
    conn.pending = null;
    conn.data_handler = LUA_NOREF;
    conn.write_handler = LUA_NOREF;

    const dp: *usize = @ptrCast(@alignCast(c.lua_newuserdata(L, @sizeOf(usize)) orelse {
        _ = c.close(src_fd);
        arcan_mem_free(conn_ptr);
        return 0;
    }));
    dp.* = @intFromPtr(conn);
    c.luaL_getmetatable(L, "nonblockIO");
    _ = c.lua_setmetatable(L, -2);

    return 1;
}

// alt_nbio_release

export fn alt_nbio_release() void {
    if (is_freestanding) return;
    for (&open_fds) |*ent| {
        if (ent.fd > 0) {
            if (remove_job) |rj| {
                _ = rj(ent.fd, O_RDONLY, null);
                _ = rj(ent.fd, O_WRONLY, null);
            }
            _ = c.close(ent.fd);
        }
        drop_all_jobs(ent);
        ent.* = std.mem.zeroes(nonblock_io);
        ent.data_handler = LUA_NOREF;
        ent.write_handler = LUA_NOREF;
    }
}

// pathfd

const pathfd = struct {
    path: [*c]u8,
    unlink: [*c]u8,
    err: [*c]const u8,
    metatable: [*c]const u8,
    fd: c_int,
    wrmode: c_uint,
};

// build_fifo_ipc

fn build_fifo_ipc(path: [*c]u8, userns: bool, expect_write: bool) pathfd {
    var res = pathfd{
        .path = null,
        .unlink = null,
        .fd = -1,
        .err = null,
        .metatable = "nonblockIO",
        .wrmode = O_RDONLY,
    };
    const ns: c_int = if (userns) RESOURCE_NS_USER else RESOURCE_APPL_TEMP;

    const workpath: [*c]u8 = arcan_expand_resource(path, ns);
    if (workpath == null) {
        res.err = "Couldn't expand FIFO path";
        return res;
    }

    if (builtin.os.tag == .windows) {
        arcan_mem_free(@ptrCast(workpath));
        res.err = "FIFO (open_nonblock target) unsupported on windows";
        return res;
    }

    var fi: stat_t = undefined;
    if (stat(path, &fi) == -1) {
        if (expect_write) {
            if (mkfifo(workpath, S_IRWXU) == -1) {
                arcan_mem_free(@ptrCast(workpath));
                res.err = "Couldn't build FIFO";
                return res;
            }
            const fd = c.open(workpath, O_RDWR);
            if (fd == -1) {
                arcan_mem_free(@ptrCast(workpath));
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

    const fd = c.open(workpath, if (expect_write) @as(c_int, @bitCast(O_WRONLY)) else @as(c_int, @bitCast(O_RDONLY)));
    arcan_mem_free(@ptrCast(workpath));

    if (fd == -1 or fstat(fd, &fi) == -1 or S_ISFIFO(fi.mode)) {
        _ = c.close(fd);
        res.err = "Couldn't open as FIFO";
        return res;
    }

    var flags: c_int = c.fcntl(fd, F_GETFL);
    if (flags != -1)
        _ = c.fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    flags = c.fcntl(fd, F_GETFD);
    if (flags != -1)
        _ = c.fcntl(fd, F_SETFD, flags | FD_CLOEXEC);

    res.fd = fd;
    return res;
}

// build_socket_ipc

fn build_socket_ipc(pathin: [*c]u8, userns: bool, srv: bool) pathfd {
    var res = pathfd{
        .path = null,
        .unlink = null,
        .fd = -1,
        .err = null,
        .metatable = "nonblockIO",
        .wrmode = O_RDONLY,
    };
    const ns: c_int = if (userns) RESOURCE_NS_USER else RESOURCE_APPL_TEMP;

    if (srv) {
        var workpath: [*c]u8 = arcan_find_resource(pathin, ns, ARES_FILE, null);

        if (workpath != null) {
            res.err = "EINVAL: Couldn't create socket";
            arcan_mem_free(@ptrCast(workpath));
            return res;
        }

        workpath = arcan_expand_resource(pathin, ns);
        if (workpath == null) {
            res.err = "EINVAL: Couldn't build socket file";
            return res;
        }

        var addr: sockaddr_un = std.mem.zeroes(sockaddr_un);
        addr.sun_family = AF_UNIX;
        const lim = @sizeOf(@TypeOf(addr.sun_path));
        if (std.mem.len(workpath) > lim - 1) {
            res.err = "ENAMETOOLONG: expanded socket doesn't fit sockaddr";
            arcan_mem_free(@ptrCast(workpath));
            return res;
        }
        _ = c.snprintf(&addr.sun_path, lim, "%s", workpath);

        res.fd = c.socket(AF_UNIX, SOCK_STREAM, 0);
        if (res.fd == -1) {
            res.err = "EPERM: couldn't allocate socket";
            arcan_mem_free(@ptrCast(workpath));
            return res;
        }
        _ = fchmod(res.fd, S_IRWXU);

        if (c.bind(res.fd, @ptrCast(&addr), @sizeOf(sockaddr_un)) == -1) {
            _ = c.close(res.fd);
            arcan_mem_free(@ptrCast(workpath));
            res.fd = -1;
            res.err = "ESOCKET: couldn't bind socket";
            return res;
        }

        // listen with backlog of 5
        _ = c.listen(res.fd, 5);
        res.unlink = workpath;
        res.metatable = "nonblockIOs";
        res.wrmode = O_RDWR;
    } else {
        const workpath: [*c]u8 = arcan_find_resource(pathin, ns, ARES_FILE, null);

        if (workpath == null) {
            res.err = "EEXIST: Couldn't connect to socket";
            return res;
        }

        res.fd = alt_nbio_socket(workpath, ns, &res.unlink);
        res.wrmode = O_RDWR;
        res.metatable = "nonblockIO";

        if (res.fd == -1) {
            res.err = "EPERM: Couldn't bind to socket";
        }

        arcan_mem_free(@ptrCast(workpath));
    }

    return res;
}

// build_new_file

fn build_new_file(path: [*c]u8, userns: bool) pathfd {
    var res = pathfd{
        .path = null,
        .unlink = null,
        .fd = -1,
        .err = null,
        .metatable = "nonblockIO",
        .wrmode = O_RDWR,
    };
    const ns: c_int = if (userns) RESOURCE_NS_USER else RESOURCE_APPL_TEMP;

    const userpath: [*c]u8 = arcan_find_resource(
        path,
        ns,
        ARES_FILE | ARES_CREATE,
        &res.fd,
    );

    if (lua_debug_level != 0) {
        arcan_warning("find_resource:ns=%d:%s\n", ns, if (path != null) path else @as([*c]const u8, "[null]"));
    }

    if (path == null) {
        res.err = "Couldn't create file in namespace";
    } else {
        arcan_mem_free(@ptrCast(userpath));
    }

    return res;
}

// open_existing_file

fn open_existing_file(path: [*c]u8, userns: bool) pathfd {
    var res = pathfd{
        .path = null,
        .unlink = null,
        .err = null,
        .fd = -1,
        .wrmode = O_RDONLY,
        .metatable = "nonblockIO",
    };

    const ns: c_int = if (userns) RESOURCE_NS_USER else DEFAULT_USERMASK;
    // open_existing_file is only invoked from the read-only branch in
    // alt_nbio_open_real (write path goes to build_new_file). Pass
    // ARES_RDONLY so handle_dynfile uses O_RDONLY — without it, world-
    // readable but root-owned files (e.g. share/.../shaders/*.frag) hit
    // EACCES on the implicit O_RDWR.
    const cpath: [*c]u8 = arcan_find_resource(path, ns, ARES_FILE | ARES_RDONLY, &res.fd);

    if (lua_debug_level != 0) {
        arcan_warning(
            "find_resource:ns=%d:%s=%s\n",
            ns,
            path,
            if (cpath != null) cpath else @as([*c]const u8, "[null]"),
        );
    }

    if (cpath == null) {
        res.err = "Couldn't find file";
    }

    arcan_mem_free(@ptrCast(cpath));
    return res;
}

// alt_nbio_open

export fn alt_nbio_open(L: ?*lua_State) callconv(.c) c_int {
    // The earlier TEMP stub returning nil (commit e272719b5) silently
    // disabled durian's control IPC socket and every open_nonblock()
    // call in Lua. Delegate to the real impl; the original "corrupt L
    // pointer" crash this worked around should be gone with the
    // alt_call + struct ABI fixes that followed.
    return alt_nbio_open_real(L);
}

fn alt_nbio_open_real(L: ?*lua_State) c_int {
    if (is_freestanding) return 0;
    var pfd: pathfd = undefined;
    var userns = false;
    // nonblock-io write to/from an explicit vid (WANT_ARCAN_BASE)
    if (c.lua_type(L, 1) == LUA_TNUMBER) {
        return opennonblock_tgt(L);
    }

    const wrmode: c_uint = if (luaL_optbnumber(L, 2, 0)) O_WRONLY else O_RDONLY;
    const str_raw: [*c]const u8 = c.luaL_checklstring(L, 1, null);
    const str: [*c]u8 = strdup(str_raw);

    // check for user namespace prefix: alnum+ ':/' ...
    var i: usize = 0;
    const str_slice = cstr(str);
    while (i < str_slice.len and std.ascii.isAlphanumeric(str_slice[i])) : (i += 1) {}
    if (i < str_slice.len and str_slice[i] == ':' and i + 1 < str_slice.len and str_slice[i + 1] == '/') {
        userns = true;
    }

    if (str_slice.len > 0 and str_slice[0] == '<')
        pfd = build_fifo_ipc(str + 1, userns, wrmode == O_WRONLY)
    else if (str_slice.len > 0 and str_slice[0] == '=')
        pfd = build_socket_ipc(str + 1, userns, wrmode != O_WRONLY)
    else if (wrmode == O_WRONLY)
        pfd = build_new_file(str, userns)
    else
        pfd = open_existing_file(str, userns);

    c.free(@ptrCast(str));

    if (pfd.err != null) {
        return 0;
    }

    const conn_ptr = arcan_alloc_mem(
        @sizeOf(nonblock_io),
        ARCAN_MEM_BINDING,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return 0;
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

    const dp: *usize = @ptrCast(@alignCast(c.lua_newuserdata(L, @sizeOf(usize)) orelse return 0));
    dp.* = @intFromPtr(conn);

    c.luaL_getmetatable(L, pfd.metatable);
    _ = c.lua_setmetatable(L, -2);

    return 1;
}

// alt_nbio_data_out

export fn alt_nbio_data_out(L: ?*lua_State, tag_arg: isize) void {
    if (is_freestanding) return;
    var tag = tag_arg;
    if (!lookup_registry(L, tag, LUA_TUSERDATA, "data-out"))
        return;

    const ibb: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, -1, "nonblockIO")));
    const ib = ibb.* orelse return;
    c.lua_settop(L, -1 - 1);

    if (ib.out_queue == null)
        return;

    // all pending writes are done, notify and check if there is still a job
    const status = alt_nbio_process_write(L, ib);

    if (status == 0)
        return;

    // no registered handler? ensure empty queue on finish/fail
    if (ib.write_handler == LUA_NOREF) {
        drop_all_jobs(ib);
        return;
    }

    if (!lookup_registry(L, ib.write_handler, LUA_TFUNCTION, "data-out-wh"))
        return;

    c.lua_pushboolean(L, @intFromBool(status == 1));
    c.lua_pushboolean(L, @intFromBool(arcan_conductor_gpus_locked() != 0));
    drop_all_jobs(ib);
    alt_call(L, CB_SOURCE_NONE, EP_TRIGGER_NBIO_WR, 0, 2, 0, "nbio:write_handler_cb");

    // The write_handler may have closed the nbio, which frees ib; reload
    // via the userdata so we don't touch freed memory.
    const ib_live = ibb.* orelse return;

    // Remove the current event-source unless a new handler has already been queued
    if (ib_live.out_queue == null) {
        if (remove_job) |rj| {
            if (rj(ib_live.fd, O_WRONLY, &tag)) {
                unref_registry(L, tag, LUA_TUSERDATA, "nbio-open-wrmeta");
            }
        }
    }
}

// alt_nbio_data_in

export fn alt_nbio_data_in(L: ?*lua_State, tag_arg: isize) void {
    if (is_freestanding) return;
    var tag = tag_arg;
    if (!lookup_registry(L, tag, LUA_TUSERDATA, "data-in"))
        return;

    const ibb: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, -1, "nonblockIO")));
    const ib = ibb.* orelse return;

    c.lua_settop(L, -1 - 1);
    if (!lookup_registry(L, ib.data_handler, LUA_TFUNCTION, "data-in-dh"))
        return;

    const ch = ib.data_handler;
    ib.data_rearmed = false;

    c.lua_pushboolean(L, @intFromBool(arcan_conductor_gpus_locked() != 0));
    alt_call(L, CB_SOURCE_NONE, EP_TRIGGER_NBIO_DATA, 0, 1, 1, "nbio:data_handler_cb");

    // The callback may have closed the nbio (e.g. durian's IPC handler on
    // EOF calls :close()), which frees the backing nonblock_io via
    // alt_nbio_close and nulls ibb.*. Reloading from the userdata lets us
    // bail out instead of dereferencing freed memory.
    const ib_live = ibb.* orelse {
        c.lua_settop(L, -1 - 1);
        return;
    };

    // manually re-armed? do nothing
    if (ib_live.data_rearmed) {
        // already re-armed
    } else if (c.lua_type(L, -1) == LUA_TBOOLEAN and c.lua_toboolean(L, -1) != 0) {
        // automatically re-arm on true- return
        ib_live.data_rearmed = true;
    } else {
        // remove and assume this is no longer wanted
        unref_registry(L, ch, LUA_TFUNCTION, "data-in-dontwant");
        ib_live.data_handler = LUA_NOREF;

        // make sure we don't remove any data-out handler while at it
        if (remove_job) |rj| {
            if (rj(ib_live.fd, O_RDONLY, &tag)) {
                unref_registry(L, tag, LUA_TUSERDATA, "data-in-meta-dontwant");
            }
        }
    }
    c.lua_settop(L, -1 - 1);
}

// nbio_seek

fn nbio_seek(L: ?*lua_State) callconv(.c) c_int {
    const ibb: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const ib = ibb.* orelse {
        alt_fatal("nbio:seek on closed file");
        return 0;
    };

    const ofs: c.off_t = @intFromFloat(c.lua_tonumber(L, 1));
    const relative = luaL_optbnumber(L, 2, 1);
    var pos: c.off_t = undefined;

    if (!relative) {
        pos = c.lseek(ib.fd, ofs, SEEK_SET);
    } else {
        if (ofs < 0) {
            pos = c.lseek(ib.fd, -ofs, SEEK_END);
        } else {
            pos = c.lseek(ib.fd, ofs, SEEK_CUR);
        }
    }

    c.lua_pushboolean(L, @intFromBool(pos != -1));
    c.lua_pushnumber(L, @floatFromInt(pos));
    return 2;
}

// nbio_position

fn nbio_position(L: ?*lua_State) callconv(.c) c_int {
    const ibb: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const ib = ibb.* orelse {
        alt_fatal("nbio:set_position on closed file");
        return 0;
    };

    var pos: lua_Number = c.lua_tonumber(L, 1);
    if (pos < 0)
        pos = @floatFromInt(c.lseek(ib.fd, @intFromFloat(-pos), SEEK_END))
    else
        pos = @floatFromInt(c.lseek(ib.fd, @intFromFloat(pos), SEEK_SET));

    c.lua_pushboolean(L, @intFromBool(pos != -1));
    c.lua_pushnumber(L, pos);
    return 2;
}

// nbio_flush

fn nbio_flush(L: ?*lua_State) callconv(.c) c_int {
    const ibb: *?*nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    const ib = ibb.* orelse return 0;
    c.lua_settop(L, -1 - 1);

    // if we have a write_handler it should be handled through the regular loop
    if (ib.write_handler != LUA_NOREF or ib.out_queue == null or ib.fd == -1) {
        c.lua_pushboolean(L, 0);
        return 1;
    }

    var timeout: isize = @intFromFloat(c.luaL_optnumber(L, 2, -1));
    if (timeout < 0) timeout = 0;
    const rv = ensure_flush(L, ib, @intCast(timeout));

    c.lua_pushboolean(L, @intFromBool(rv));
    return 1;
}

// alt_nbio_import

export fn alt_nbio_import(
    L: ?*lua_State,
    fd: c_int,
    mode: mode_t,
    out: ?*?*nonblock_io,
    unlink_fn: ?*[*c]u8,
) bool {
    if (is_freestanding) return false;
    if (fd == -1) {
        c.lua_pushnil(L);
        return false;
    }

    if (out) |o| o.* = null;

    const nbio_ptr = c.malloc(@sizeOf(nonblock_io));
    if (nbio_ptr == null) {
        _ = c.close(fd);
        c.lua_pushnil(L);
        return false;
    }
    const nbio: *nonblock_io = @ptrCast(@alignCast(nbio_ptr));

    const dp_ptr = c.lua_newuserdata(L, @sizeOf(usize));
    if (dp_ptr == null) {
        _ = c.close(fd);
        c.free(nbio_ptr);
        c.lua_pushnil(L);
        return false;
    }
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

    c.luaL_getmetatable(L, "nonblockIO");
    _ = c.lua_setmetatable(L, -2);
    return true;
}

// alt_nbio_register

export fn alt_nbio_register(
    L: ?*lua_State,
    add_fn: *const fn (c_int, mode_t, isize) callconv(.c) bool,
    remove_fn: *const fn (c_int, mode_t, ?*isize) callconv(.c) bool,
    error_fn: *const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void,
) void {
    if (is_freestanding) return;
    add_job = add_fn;
    remove_job = remove_fn;
    trigger_error = error_fn;

    // nonblockIO metatable
    _ = c.luaL_newmetatable(L, "nonblockIO");
    c.lua_pushvalue(L, -1);
    c.lua_setfield(L, -2, "__index");
    c.lua_pushcclosure(L, &nbio_read, 0);
    c.lua_setfield(L, -2, "read");
    c.lua_pushcclosure(L, &nbio_write, 0);
    c.lua_setfield(L, -2, "write");
    c.lua_pushcclosure(L, &nbio_closer, 0);
    c.lua_setfield(L, -2, "__gc");
    c.lua_pushcclosure(L, &nbio_writequeue, 0);
    c.lua_setfield(L, -2, "outqueue");
    c.lua_pushcclosure(L, &nbio_datahandler, 0);
    c.lua_setfield(L, -2, "data_handler");
    c.lua_pushcclosure(L, &nbio_closer, 0);
    c.lua_setfield(L, -2, "close");
    c.lua_pushcclosure(L, &nbio_seek, 0);
    c.lua_setfield(L, -2, "seek");
    c.lua_pushcclosure(L, &nbio_position, 0);
    c.lua_setfield(L, -2, "set_position");
    c.lua_pushcclosure(L, &nbio_flush, 0);
    c.lua_setfield(L, -2, "flush");
    c.lua_pushcclosure(L, &nbio_lf, 0);
    c.lua_setfield(L, -2, "lf_strip");
    // WANT_ARCAN_BASE
    c.lua_pushcclosure(L, &bgcopy, 0);
    c.lua_setfield(L, -2, "bgcopy");
    c.lua_settop(L, -1 - 1); // lua_pop(L, 1)

    // nonblockIOs metatable (server sockets)
    _ = c.luaL_newmetatable(L, "nonblockIOs");
    c.lua_pushvalue(L, -1);
    c.lua_setfield(L, -2, "__index");
    c.lua_pushcclosure(L, &nbio_socketaccept, 0);
    c.lua_setfield(L, -2, "accept");
    c.lua_pushcclosure(L, &nbio_socketclose, 0);
    c.lua_setfield(L, -2, "close");
    c.lua_pushcclosure(L, &nbio_socketclose, 0);
    c.lua_setfield(L, -2, "_gc");
    c.lua_settop(L, -1 - 1); // lua_pop(L, 1)
}
