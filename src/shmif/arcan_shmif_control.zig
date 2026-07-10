// Zig reimplementation of arcan_shmif_control.c
// Drop-in C-ABI-compatible replacement for shmif control functions.
//
// Exports: arcan_shmif_cookie, arcan_shmif_defimpl, arcan_shmif_handle_permitted,
//          arcan_shmif_poll, arcan_shmif_wait, arcan_shmif_wait_timed,
//          arcan_shmif_enqueue, arcan_shmif_tryenqueue, arcan_shmif_unlink,
//          arcan_shmif_segment_key, arcan_shmif_connect,
//          arcan_shmif_resolve_connpath, arcan_shmif_acquire,
//          arcan_shmif_integrity_check, arcan_shmif_args, arcan_shmif_drop,
//          arcan_shmif_resize, arcan_shmif_resize_ext, arcan_shmif_signalhook,
//          arcan_shmif_primary, arcan_shmif_setprimary, arcan_shmif_guid,
//          arcan_shmif_signalstatus, arcan_shmif_lock, arcan_shmif_unlock,
//          arcan_shmif_dupfd, arcan_shmif_last_words, arcan_shmif_initial,
//          arcan_shmif_defer_register, arcan_shmif_open_ext, arcan_shmif_open,
//          arcan_shmif_segkind, arcan_shmif_handover_exec_pipe,
//          arcan_shmif_handover_exec, arcan_shmif_deadline, arcan_shmif_dirty,
//          arcan_shmif_resetfunc, shmif_platform_log_device,
//          shmif_platform_set_log_device
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

// Inline cast helpers for opaque → typed pointers
inline fn castEvctx(raw: *anyopaque) *c.struct_arcan_evctx {
    return @ptrCast(@alignCast(raw));
}
inline fn castEvent(raw: *anyopaque) *c.arcan_event {
    return @ptrCast(@alignCast(raw));
}
inline fn castInitial(raw: *anyopaque) *c.struct_arcan_shmif_initial {
    return @ptrCast(@alignCast(raw));
}

// Extern C declarations

extern fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern fn fprintf(stream: *anyopaque, fmt: [*c]const u8, ...) c_int;
// C helper: fprintf to real stderr — avoids Zig GOT double-dereference bug (BUG-S17)
extern fn shmif_log_stderr(fmt: [*c]const u8, ...) void;
extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn strdup(s: [*c]const u8) [*c]u8;
extern fn strtoul(s: [*c]const u8, endptr: ?*[*c]u8, base: c_int) c_ulong;
extern fn strlen(s: [*c]const u8) usize;
extern fn memset(dst: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;
extern fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
extern fn strerror(errnum: c_int) [*c]u8;
extern fn getenv(name: [*c]const u8) [*c]u8;
extern fn exit(status: c_int) noreturn;
extern fn close(fd: c_int) c_int;
extern fn open(path: [*c]const u8, flags: c_int, ...) c_int;
extern fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
extern fn dup(fd: c_int) c_int;

extern fn mmap(addr: ?*anyopaque, length: usize, prot: c_int, flags: c_int, fd: c_int, offset: i64) ?*anyopaque;
extern fn munmap(addr: ?*anyopaque, length: usize) c_int;

extern fn poll(fds: *PollFd, nfds: c_ulong, timeout: c_int) c_int;
extern fn setsockopt(sockfd: c_int, level: c_int, optname: c_int, optval: ?*const anyopaque, optlen: u32) c_int;
extern fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
extern fn connect(sockfd: c_int, addr: ?*const anyopaque, addrlen: u32) c_int;

extern fn pthread_mutex_init(mutex: *c.pthread_mutex_t, attr: ?*const anyopaque) c_int;
extern fn pthread_mutex_lock(mutex: *c.pthread_mutex_t) c_int;
extern fn pthread_mutex_unlock(mutex: *c.pthread_mutex_t) c_int;
extern fn pthread_mutex_destroy(mutex: *c.pthread_mutex_t) c_int;
extern fn pthread_self() c.pthread_t;
extern fn pthread_equal(t1: c.pthread_t, t2: c.pthread_t) c_int;

// musl defines pthread_t as ?*struct___pthread (pointer), glibc as unsigned long (usize).
// These helpers convert between pthread_t and usize for storing in offset-based fields.
fn pthreadToUsize(pt: c.pthread_t) usize {
    return if (@typeInfo(@TypeOf(pt)) == .pointer or @typeInfo(@TypeOf(pt)) == .optional)
        @intFromPtr(pt)
    else
        @intCast(pt);
}

fn usizeToPthread(v: usize) c.pthread_t {
    return if (@typeInfo(c.pthread_t) == .pointer or @typeInfo(c.pthread_t) == .optional)
        @ptrFromInt(v)
    else
        @intCast(v);
}

extern fn shmif_platform_connpath(name: [*c]const u8, dbuf: [*c]u8, dbuf_sz: usize, attempt: c_int) c_int;
extern fn shmif_platform_setevqs(page: ?*anyopaque, sem: ?*anyopaque, inevq: *c.struct_arcan_evctx, outevq: *c.struct_arcan_evctx) void;
extern fn shmif_platform_pushfd(fd: c_int, sockout: c_int) bool;
extern fn shmif_platform_guard(cont: *c.struct_arcan_shmif_cont, cfg: c.struct_watchdog_config) void;
extern fn shmif_platform_guard_lock(cont: *c.struct_arcan_shmif_cont) void;
extern fn shmif_platform_guard_unlock(cont: *c.struct_arcan_shmif_cont) void;
extern fn shmif_platform_guard_resynch(cont: *c.struct_arcan_shmif_cont, parent_pid: c_int, parent_fd: c_int) void;
extern fn shmif_platform_guard_release(cont: *c.struct_arcan_shmif_cont) void;
extern fn shmif_platform_check_alive(cont: *c.struct_arcan_shmif_cont) bool;
extern fn shmif_platform_fallback(cont: *c.struct_arcan_shmif_cont, cp: [*c]const u8, force: bool) c.enum_shmif_migrate_status;
extern fn shmif_platform_sync_mark(page: ?*anyopaque, slot: c_int) void;
extern fn shmif_platform_sync_post(page: ?*anyopaque, slot: c_int) c_int;
extern fn shmif_platform_sync_wait(page: ?*anyopaque, slot: c_int) c_int;
extern fn shmif_platform_sync_trywait(page: ?*anyopaque, slot: c_int) c_int;
extern fn shmif_platform_mem_from_socket(sock: c_int) c_int;
extern fn shmif_platform_dupfd_to(fd: c_int, dstnum: c_int, fflags: c_int, fdopt: c_int) c_int;
extern fn shmif_platform_open_env_connection(flags: c_int) c.struct_shmif_connection;
extern fn shmif_platform_a12addr(addr: [*c]const u8) c.struct_a12addr_info;
extern fn shmif_platform_a12spawn(cont: *c.struct_arcan_shmif_cont, addr: [*c]const u8, dsock: *c_int) [*c]u8;
extern fn shmif_platform_execve(shmif_fd: c_int, mem_fd: c_int, path: [*c]const u8, argv: [*c]const [*c]u8, env: [*c]const [*c]u8, options: c_int, fds: [*c]?*c_int, fds_sz: usize, err: ?*[*c]u8) c.pid_t;

extern fn arcan_timemillis() c_ulonglong;
extern fn arcan_shmif_vbufsz(atype: c_int, hints: u8, w: usize, h: usize, rows: usize, cols: usize) usize;
extern fn arcan_shmif_mapav(page: ?*anyopaque, vbuf: [*c]?*c.shmif_pixel, vbufc: u8, vbufsz: usize, abuf: [*c]?*c.shmif_asample, abufc: u8, abufsz: usize) void;
extern fn arcan_shmif_eventstr(ev: ?*const c.arcan_event, dbuf: ?[*]u8, dsz: usize) [*c]const u8;
extern fn arcan_random(buf: [*c]u8, len: usize) void;
extern fn arg_unpack(resource: [*c]const u8) [*c]c.struct_arg_arr;
extern fn arg_cleanup(arr: [*c]c.struct_arg_arr) void;

fn dbg_write(msg: [*c]const u8) void {
    _ = write(2, msg, strlen(msg));
}

extern fn shmifint_preroll_loop(ctx: *c.struct_arcan_shmif_cont, do_resize: bool) bool;
extern fn shmifint_drop_initial(ctx: *c.struct_arcan_shmif_cont) void;
extern fn shmifint_process_events(ctx: *c.struct_arcan_shmif_cont, ev: *c.arcan_event, block: bool, upret: bool) c_int;
extern fn shmifint_consume_pending(ctx: *c.struct_arcan_shmif_cont) void;

extern fn fcntl(fd: c_int, cmd: c_int, ...) c_int;

// shmif_defimpl.h
extern fn arcan_shmif_debugint_spawn(cont: *c.struct_arcan_shmif_cont, tuitag: ?*anyopaque, res: ?*anyopaque) bool;

// Constants

const BADFD: c_int = -1;
const PROT_READ: c_int = 0x1;
const PROT_WRITE: c_int = 0x2;
const MAP_SHARED: c_int = 0x01;
const MAP_FAILED: usize = @as(usize, @bitCast(@as(isize, -1)));
const O_RDWR: c_int = 0x02;
const O_NONBLOCK: c_int = 0x800;
const FD_CLOEXEC: c_int = 1;
const F_SETFD: c_int = 2;
const F_GETFD: c_int = 1;
const AF_UNIX: c_int = 1;
const SOCK_STREAM: c_int = 1;
const SOL_SOCKET: c_int = 1;
const SO_RCVTIMEO: c_int = 20;
const SO_NOSIGPIPE: c_int = 13;
const STDIN_FILENO: c_int = 0;
const STDOUT_FILENO: c_int = 1;
const STDERR_FILENO: c_int = 2;
const EXIT_FAILURE: c_int = 1;
const POLLIN: c_short = 0x001;
const POLLERR: c_short = 0x008;
const POLLHUP: c_short = 0x010;
const POLLNVAL: c_short = 0x020;

const PollFd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

const Timeval = extern struct {
    tv_sec: c_long,
    tv_usec: c_long,
};

// sockaddr_un layout: family(2) + sun_path(108)
const SockaddrUn = extern struct {
    sun_family: u16,
    sun_path: [108]u8,
};

// Inline helper: FORCE_SYNCH
var force_synch_dummy: u32 = 0;
inline fn FORCE_SYNCH() void {
    asm volatile ("" ::: .{ .memory = true });
    _ = @atomicRmw(u32, &force_synch_dummy, .Add, 0, .seq_cst);
}

// Static/global state

// Atomic log device pointer
var log_device_ptr: usize = 0;

// Per-process primary segment tracking
var primary_input: ?*c.struct_arcan_shmif_cont = null;
var primary_output: ?*c.struct_arcan_shmif_cont = null;
var primary_accessibility: ?*c.struct_arcan_shmif_cont = null;

var g_epoch: u64 = 0;

// shmif_platform_log_device / shmif_platform_set_log_device
//
// BUG-S17: Can't use @extern for glibc's stderr in PIE — LLD's aarch64
// GOT relaxation strips a dereference from any pointer-type symbol.
// shmif_platform_log_device() returns STDERR_SENTINEL when no custom device
// is set. Callers must check for sentinel and use shmif_log_stderr() instead
// of fprintf(). shmif_log_stderr() uses write(2), bypassing stdio entirely.

const STDERR_SENTINEL: usize = 1;

export fn shmif_platform_log_device(_: ?*c.struct_arcan_shmif_cont) *anyopaque {
    const res = @atomicLoad(usize, &log_device_ptr, .seq_cst);
    if (res != 0) {
        return @ptrFromInt(res);
    }
    return @ptrFromInt(STDERR_SENTINEL);
}

/// Log a formatted message to either the custom log device or stderr (fd 2).
/// Replaces the pattern: `const logdev = shmif_platform_log_device(null); fprintf(logdev, ...);`
fn log_fmt(fmt: [*c]const u8, args: anytype) void {
    const res = @atomicLoad(usize, &log_device_ptr, .seq_cst);
    if (res != 0) {
        _ = @call(.auto, fprintf, .{@as(*anyopaque, @ptrFromInt(res)), fmt} ++ args);
    } else {
        @call(.auto, shmif_log_stderr, .{fmt} ++ args);
    }
}

export fn shmif_platform_set_log_device(_: ?*c.struct_arcan_shmif_cont, outdev: *anyopaque) void {
    @atomicStore(usize, &log_device_ptr, @intFromPtr(outdev), .seq_cst);
}

// arcan_shmif_cookie

export fn arcan_shmif_cookie() u64 {
    return off.Page.computeCookie();
}

// arcan_shmif_defimpl

export fn arcan_shmif_defimpl(
    newchild: ?*c.struct_arcan_shmif_cont,
    seg_type: c_int,
    typetag: ?*anyopaque,
) void {
    const child = newchild orelse return;

    // SHMIF_DEBUG_IF is a compile-time define
    if (seg_type == @as(c_int, @intCast(c.SEGID_DEBUG))) {
        if (arcan_shmif_debugint_spawn(child, typetag, null)) {
            return;
        }
    }

    arcan_shmif_drop(child);
}

// arcan_shmif_handle_permitted

export fn arcan_shmif_handle_permitted(ctx: ?*c.struct_arcan_shmif_cont) bool {
    if (is_freestanding) return false;
    const ct = ctx orelse return false;
    const pe = ct.privext orelse return false;
    return pe.*.state_fl != @as(c_int, @intCast(c.STATE_NOACCEL));
}

// arcan_shmif_poll

export fn arcan_shmif_poll(
    C: ?*c.struct_arcan_shmif_cont,
    dst: ?*c.arcan_event,
) c_int {
    const cont = C orelse return -1;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv orelse return -1));
    if (!off.Hidden.getAlive(P)) return -1;
    const d = dst orelse return -1;

    if (off.Hidden.getValidInitial(P))
        shmifint_drop_initial(cont);

    const rv = shmifint_process_events(cont, d, false, false);

    // DEBUG: log every event that arcan_shmif_poll returns to the caller,
    // routed via the shmif_monitor stream (Lua tag channel).
    if (rv > 0) {
        const smon = @import("shmif_monitor");
        const snprintf_ex = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf: [64]u8 = undefined;
        const cat: c_int = @intCast(d.category().*);
        const kind: c_int = switch (@as(u8, @intCast(d.category().*))) {
            16 => @intCast(d.tgt().kind),
            64 => @intCast(d.ext().kind),
            else => -1,
        };
        _ = snprintf_ex(&buf, 64, "shmif_poll:return:cat=%d:kind=%d", cat, kind);
        smon.emitLuaTag(@ptrCast(&buf));
    }

    if (rv > 0 and off.Hidden.getLogEvent(P) != 0) {
        if (d.category().* == c.EVENT_TARGET and
            d.tgt().kind == c.TARGET_COMMAND_STEPFRAME and
            off.Hidden.getLogEvent(P) < 2)
            return rv;

        log_fmt(
            "[%llu:%u] <- %s\n",
            .{ arcan_timemillis() -% g_epoch, cont.cookie, arcan_shmif_eventstr(d, null, 0) },
        );
    }

    return rv;
}

// arcan_shmif_wait_timed

export fn arcan_shmif_wait_timed(
    C: ?*c.struct_arcan_shmif_cont,
    time_ms: ?*c_uint,
    dst: ?*c.arcan_event,
) c_int {
    const cont = C orelse return 0;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv orelse return 0));
    if (!off.Hidden.getAlive(P)) return 0;
    const tms = time_ms orelse return 0;
    const d = dst orelse return 0;

    if (off.Hidden.getValidInitial(P))
        shmifint_drop_initial(cont);

    const beg = arcan_timemillis();
    const timeout: c_int = @intCast(tms.*);

    var pfd = PollFd{
        .fd = cont.epipe,
        .events = POLLIN | POLLERR | POLLHUP | POLLNVAL,
        .revents = 0,
    };

    const rv = poll(&pfd, 1, timeout);
    const now = arcan_timemillis();
    const elapsed: c_int = @intCast(@as(i64, @intCast(now)) - @as(i64, @intCast(beg)));
    if (elapsed < 0 or elapsed > timeout) {
        tms.* = 0;
    } else {
        tms.* = @intCast(timeout - elapsed);
    }

    if (rv == 1) {
        return arcan_shmif_wait(cont, d);
    }

    return 0;
}

// arcan_shmif_wait

export fn arcan_shmif_wait(
    C: ?*c.struct_arcan_shmif_cont,
    dst: ?*c.arcan_event,
) c_int {
    const cont = C orelse {
        dbg_write("[wait] cont=null\n");
        return 0;
    };
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv orelse {
        dbg_write("[wait] priv=null\n");
        return 0;
    }));
    if (!off.Hidden.getAlive(P)) {
        dbg_write("[wait] alive=false\n");
        return 0;
    }
    const d = dst orelse return 0;

    if (off.Hidden.getValidInitial(P))
        shmifint_drop_initial(cont);

    const rv = shmifint_process_events(cont, d, true, false);
    if (rv <= 0) {
        dbg_write("[wait] process_events returned <=0\n");
    }
    if (rv > 0 and off.Hidden.getLogEvent(P) != 0) {
        if (d.category().* == c.EVENT_TARGET and
            d.tgt().kind == c.TARGET_COMMAND_STEPFRAME and
            off.Hidden.getLogEvent(P) < 2)
            return @intFromBool(rv > 0);

        log_fmt(
            "(@%lx<-)%s\n",
            .{ @intFromPtr(cont), arcan_shmif_eventstr(d, null, 0) },
        );
    }

    return @intFromBool(rv > 0);
}

// enqueue_internal

fn enqueue_internal(
    C: ?*c.struct_arcan_shmif_cont,
    src: ?*const c.arcan_event,
    try_only: bool,
) c_int {
    const cont = C orelse return -1;
    if (cont.addr == null or cont.priv == null) return -1;
    const ev = src orelse return 0;

    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    // Sending TARGET events is special
    if (ev.category().* == c.EVENT_TARGET) {
        if (ev.tgt().kind == c.TARGET_COMMAND_EXIT) {
            off.Hidden.setAlive(P, false);
            _ = shmif_platform_sync_post(cont.addr, @intCast(c.SYNC_EVENT | c.SYNC_AUDIO | c.SYNC_VIDEO));
            return 1;
        }
        return 0;
    }

    if (!shmif_platform_check_alive(cont) and !try_only) {
        _ = shmif_platform_fallback(cont, off.Hidden.getAltConn(P), true);
        return 0;
    }

    if (off.Hidden.getLogEvent(P) != 0) {
        var outev = ev.*;
        if (outev.category().* == 0) {
            outev.category().* = @intCast(c.EVENT_EXTERNAL);
        }
        if (outev.category().* == c.EVENT_EXTERNAL)
            outev.ext().frame_id = off.Hidden.getVframeId(P);

        log_fmt(
            "(@%lx->)%s\n",
            .{ @intFromPtr(cont), arcan_shmif_eventstr(&outev, null, 0) },
        );
    }

    const ctx = castEvctx(off.Hidden.getOutevPtr(P));

    // paused only set if segment is configured to handle it
    if (off.Hidden.getPaused(P)) {
        var pev: c.arcan_event = undefined;
        _ = shmifint_process_events(cont, &pev, true, true);
    }

    // wait for space in the output queue
    while (shmif_platform_check_alive(cont) and
        ((@as(*volatile u8, @ptrCast(@volatileCast(ctx.back))).* +% 1) % ctx.eventbuf_sz) == @as(*volatile u8, @ptrCast(@volatileCast(ctx.front))).*)
    {
        _ = shmif_platform_sync_wait(cont.addr, @intCast(c.SYNC_EVENT));
    }

    var category = ev.category().*;
    const back_idx = @as(*volatile u8, @ptrCast(@volatileCast(ctx.back))).*;
    ctx.eventbuf[back_idx] = ev.*;
    if (category == 0) {
        ctx.eventbuf[back_idx].category().* = @intCast(c.EVENT_EXTERNAL);
        category = @intCast(c.EVENT_EXTERNAL);
    }

    if (category == c.EVENT_EXTERNAL) {
        ctx.eventbuf[back_idx].ext().frame_id = off.Hidden.getVframeId(P);

        if (ev.ext().kind == c.EVENT_EXTERNAL_REGISTER) {
            if (ev.ext().registr().guid[0] != 0 or
                ev.ext().registr().guid[1] != 0)
            {
                off.Hidden.setGuid(P, 0, ev.ext().registr().guid[0]);
                off.Hidden.setGuid(P, 1, ev.ext().registr().guid[1]);
            }

            if (ev.ext().registr().kind != 0 and off.Hidden.getType(P) == @as(c_int, @intCast(c.SEGID_UNKNOWN)))
                off.Hidden.setType(P, @intCast(ev.ext().registr().kind));
        }
    }

    FORCE_SYNCH();
    @as(*volatile u8, @ptrCast(@volatileCast(ctx.back))).* = @intCast((back_idx +% 1) % ctx.eventbuf_sz);

    if (@as(c_uint, @bitCast(off.Hidden.getFlags(P))) & c.SHMIF_SOCKET_PINGEVENT != 0) {
        const pb: u8 = '1';
        _ = write(cont.epipe, &pb, 1);
    }

    return 1;
}

// arcan_shmif_enqueue

export fn arcan_shmif_enqueue(
    C: ?*c.struct_arcan_shmif_cont,
    src: ?*const c.arcan_event,
) c_int {
    return enqueue_internal(C, src, false);
}

// arcan_shmif_tryenqueue

export fn arcan_shmif_tryenqueue(
    C: ?*c.struct_arcan_shmif_cont,
    src: ?*const c.arcan_event,
) c_int {
    return enqueue_internal(C, src, true);
}

// arcan_shmif_unlink

export fn arcan_shmif_unlink(_: ?*c.struct_arcan_shmif_cont) void {
    // deprecated, not needed anymore
}

// arcan_shmif_segment_key

export fn arcan_shmif_segment_key(_: ?*c.struct_arcan_shmif_cont) [*c]const u8 {
    // deprecated, not needed anymore
    return null;
}

// ensure_stdio

fn ensure_stdio() bool {
    var fd: c_int = 0;
    while (fd < STDERR_FILENO and fd != -1) {
        fd = open("/dev/null", O_RDWR);
    }

    if (fd > STDERR_FILENO)
        _ = close(fd);

    if (fd == -1)
        return false;

    return true;
}

// map_shared

fn map_shared(fd: c_int, dst: *c.struct_arcan_shmif_cont) void {
    if (fd <= STDERR_FILENO) {
        return;
    }

    const mapped = mmap(null, c.ARCAN_SHMPAGE_START_SZ, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    {
        const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
        const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
        const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
        const sc_getpid = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });
        if (sc_open("/tmp/arcan_shm_trace.log", "a")) |f| {
            _ = sc_fprintf(f, "[child pid=%d] map_shared fd=%d mmap=%p\n",
                sc_getpid(), fd, mapped);
            _ = sc_fclose(f);
        }
    }
    dst.addr = @ptrCast(@alignCast(mapped));
    dst.shmh = fd;

    if (@intFromPtr(mapped) == MAP_FAILED) {
        _ = close(fd);
        dst.addr = null;
        return;
    }

    // parent suggested a different size from the start, need to remap
    const seg_sz: usize = off.Page.getSegmentSize(dst.addr.?);
    if (seg_sz != c.ARCAN_SHMPAGE_START_SZ) {
        _ = munmap(dst.addr, c.ARCAN_SHMPAGE_START_SZ);
        const remapped = mmap(null, seg_sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (@intFromPtr(remapped) == MAP_FAILED) {
            dst.addr = null;
            _ = close(fd);
            return;
        }
        dst.addr = @ptrCast(@alignCast(remapped));
    }
}

// arcan_shmif_resolve_connpath

export fn arcan_shmif_resolve_connpath(
    key: [*c]const u8,
    dbuf: [*c]u8,
    dbuf_sz: usize,
) c_int {
    return shmif_platform_connpath(key, dbuf, dbuf_sz, 0);
}

// shmif_exit

fn shmif_exit(_: c_int) callconv(.c) void {
    // guard thread empty
}

// arcan_shmif_connect

export fn arcan_shmif_connect(
    connpath: [*c]const u8,
    _: [*c]const u8,
    conn_ch: ?*c_int,
) [*c]u8 {
    if (connpath == null) return null;
    const ch = conn_ch orelse return null;

    var dst: SockaddrUn = std.mem.zeroes(SockaddrUn);
    dst.sun_family = AF_UNIX;
    const lim = dst.sun_path.len;
    var fdstr: [16]u8 = std.mem.zeroes([16]u8);

    var index: c_int = 0;
    var sock: c_int = -1;

    // retry loop (replaces goto retry)
    while (true) {
        const len = shmif_platform_connpath(connpath, &dst.sun_path, lim, index);
        index += 1;

        if (len < 0) {
            if (sock != -1)
                _ = close(sock);
            return null;
        }

        if (sock == -1)
            sock = socket(AF_UNIX, SOCK_STREAM, 0);

        if (sock == -1) {
            return null;
        }

        if (comptime builtin.os.tag == .macos) {
            var one: c_int = 1;
            _ = setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, @sizeOf(c_int));
        }

        if (connect(sock, @ptrCast(&dst), @sizeOf(SockaddrUn)) != 0) {
            // retry with next address
            continue;
        }

        break;
    }

    // wait for key response
    const memfd = shmif_platform_mem_from_socket(sock);
    if (memfd == -1) {
        _ = close(sock);
        return null;
    }

    // enable timeout
    var tv = Timeval{ .tv_sec = 1, .tv_usec = 0 };
    _ = setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, @sizeOf(Timeval));

    ch.* = sock;
    _ = snprintf(&fdstr, fdstr.len, "%d", memfd);

    return strdup(&fdstr);
}

// setup_avbuf

fn setup_avbuf(res: *c.struct_arcan_shmif_cont) void {
    const P: *anyopaque = @ptrCast(@alignCast(res.priv));

    // flush out dangling buffers
    {
        var i: usize = 0;
        while (i < c.ARCAN_SHMIF_VBUFC_LIM) : (i += 1) off.Hidden.setVbuf(P, i, null);
    }
    {
        var i: usize = 0;
        while (i < c.ARCAN_SHMIF_ABUFC_LIM) : (i += 1) off.Hidden.setAbuf(P, i, null);
    }

    const page = res.addr.?;
    res.w = off.Page.getW(page);
    res.h = off.Page.getH(page);

    res.stride = res.w * @as(usize, @intCast(c.ARCAN_SHMPAGE_VCHANNELS));
    res.pitch = res.w;

    off.Hidden.setVbufCnt(P, @intCast(off.Page.getVpending(page)));
    off.Hidden.setAbufCnt(P, @intCast(off.Page.getApending(page)));
    res.segment_token = off.Page.getSegmentToken(page);

    off.Hidden.setAbufInd(P, 0);
    off.Hidden.setVbufInd(P, 0);
    off.Hidden.setVbufNbufActive(P, false);
    off.Page.setVpending(page, 0);
    off.Page.setApending(page, 0);
    res.abufused = 0;
    res.abufpos = 0;

    res.abufsize = @intCast(off.Page.getAbufsize(page));
    res.abufcount = res.abufsize / @sizeOf(c.shmif_asample);
    res.abuf_cnt = off.Hidden.getAbufCnt(P);
    res.samplerate = off.Page.getAudiorate(page);
    if (res.samplerate == 0)
        res.samplerate = @intCast(c.ARCAN_SHMIF_SAMPLERATE);

    res.vbufsize = arcan_shmif_vbufsz(
        off.Hidden.getAtype(P),
        res.hints,
        res.w,
        res.h,
        off.Page.getRows(page),
        off.Page.getCols(page),
    );

    arcan_shmif_mapav(
        res.addr,
        @ptrCast(off.Hidden.getVbufArrayPtr(P)),
        off.Hidden.getVbufCnt(P),
        res.vbufsize,
        @ptrCast(off.Hidden.getAbufArrayPtr(P)),
        off.Hidden.getAbufCnt(P),
        res.abufsize,
    );

    res.unnamed_0.vidp = @ptrCast(@alignCast(off.Hidden.getVbuf(P, 0)));
    res.unnamed_1.audp = @ptrCast(@alignCast(off.Hidden.getAbuf(P, 0)));

    res.dirty.x1 = 0;
    res.dirty.y1 = 0;
    res.dirty.x2 = @intCast(res.w);
    res.dirty.y2 = @intCast(res.h);
}

// shmif_acquire_int
// This is the core acquisition function. Due to va_list complexity,
// we export arcan_shmif_acquire as a direct C-callable wrapper.

fn shmif_acquire_int(
    parent: ?*c.struct_arcan_shmif_cont,
    shmkey: [*c]const u8,
    seg_type: c_int,
    flags: c_int,
    exitf_in: ?*const fn (c_int) callconv(.c) void,
) c.struct_arcan_shmif_cont {
    var res: c.struct_arcan_shmif_cont = std.mem.zeroes(c.struct_arcan_shmif_cont);

    if (shmkey == null and (parent == null or (if (parent) |p| p.priv == null else true))) {
        return res;
    }

    const priv_raw = malloc(off.Hidden.sizeOf()) orelse return res;
    _ = memset(priv_raw, 0, off.Hidden.sizeOf());
    res.priv = @ptrCast(@alignCast(priv_raw));
    const P: *anyopaque = priv_raw;
    off.Hidden.setFlags(P, @bitCast(flags));
    off.Hidden.setPevFd(P, 0, BADFD);
    off.Hidden.setPevFd(P, 1, BADFD);
    off.Hidden.setPsegEpipe(P, BADFD);
    off.Hidden.setDmabufVidpFd(P, BADFD);

    var privps = false;

    if (shmkey == null) {
        const par = parent.?;
        const gs: *anyopaque = @ptrCast(@alignCast(par.priv));
        if (off.Hidden.getPevGotev(gs) and castEvent(off.Hidden.getPevEvPtr(gs)).tgt().kind == c.TARGET_COMMAND_NEWSEGMENT) {
            if (off.Hidden.getPevFd(gs, 0) == BADFD) return res;
            if (off.Hidden.getPevFd(gs, 1) == BADFD) return res;
            off.Hidden.setPsegMemfd(gs, off.Hidden.getPevFd(gs, 1));
            off.Hidden.setPevFd(gs, 1, BADFD);
            off.Hidden.setPsegEpipe(gs, off.Hidden.getPevFd(gs, 0));
            off.Hidden.setPevFd(gs, 0, BADFD);
            off.Hidden.setPevGotev(gs, false);
        } else {
            return res;
        }

        map_shared(off.Hidden.getPsegMemfd(gs), &res);

        if (res.addr == null) {
            _ = close(off.Hidden.getPsegEpipe(gs));
            off.Hidden.setPsegEpipe(gs, BADFD);
        }
        privps = true;
    } else {
        const shmfd: c_int = @intCast(strtoul(shmkey, null, 10));
        map_shared(shmfd, &res);
    }

    if (res.addr == null) {
        free(@as(?*anyopaque, @ptrCast(res.priv)));
        res.priv = null;

        if (@as(c_uint, @bitCast(flags)) & c.SHMIF_ACQUIRE_FATALFAIL != 0)
            exit(EXIT_FAILURE);

        return res;
    }

    // allow the user to hook termination
    var exitf: *const fn (c_int) callconv(.c) void = &shmif_exit;
    if (@as(c_uint, @bitCast(flags)) & c.SHMIF_FATALFAIL_FUNC != 0) {
        if (exitf_in) |ef| {
            exitf = ef;
        }
    }

    // mark the segment as non-extended
    const ext_raw = malloc(@sizeOf(c.struct_shmif_ext_hidden)) orelse return res;
    const ext: *c.struct_shmif_ext_hidden = @ptrCast(@alignCast(ext_raw));
    res.privext = ext;
    ext.* = std.mem.zeroes(c.struct_shmif_ext_hidden);
    ext.active_fd = -1;
    ext.pending_fd = -1;

    off.Hidden.setAlive(P, true);
    const dbgenv = getenv("ARCAN_SHMIF_DEBUG");
    if (dbgenv != null)
        off.Hidden.setLogEvent(P, @intCast(strtoul(dbgenv, null, 10)));

    if ((@as(c_uint, @bitCast(flags)) & c.SHMIF_DISABLE_GUARD == 0) and (getenv("ARCAN_SHMIF_NOGUARD") == null)) {
        var wcfg: c.struct_watchdog_config = std.mem.zeroes(c.struct_watchdog_config);
        wcfg.parent_pid = @intCast(off.Page.getParent(res.addr.?));
        wcfg.parent_fd = -1;
        wcfg.exitf = exitf;
        wcfg.relval = 0;
        shmif_platform_guard(&res, wcfg);
    } else {
        off.Hidden.setGuardLocalDms(P, true);
    }

    if (privps) {
        const pp: *anyopaque = @ptrCast(@alignCast(parent.?.priv));
        res.epipe = off.Hidden.getPsegEpipe(pp);

        if (comptime builtin.os.tag == .macos) {
            var val: c_int = 1;
            _ = setsockopt(res.epipe, SOL_SOCKET, SO_NOSIGPIPE, &val, @sizeOf(c_int));
        }

        var tv = Timeval{ .tv_sec = 1, .tv_usec = 0 };
        _ = setsockopt(res.epipe, SOL_SOCKET, SO_RCVTIMEO, &tv, @sizeOf(Timeval));

        off.Hidden.setPsegEpipe(pp, BADFD);
        shmifint_consume_pending(parent.?);
    }

    shmif_platform_setevqs(res.addr, null, castEvctx(off.Hidden.getInevPtr(P)), castEvctx(off.Hidden.getOutevPtr(P)));

    // forward type, GUID
    if (seg_type != 0 and (@as(c_uint, @bitCast(flags)) & c.SHMIF_NOREGISTER == 0)) {
        arcan_random(@ptrCast(off.Hidden.getGuidPtr(P)), 16);
        var ev: c.arcan_event = c.arcan_event.zeroes();
        ev.category().* = @intCast(c.EVENT_EXTERNAL);
        ev.ext().kind = c.EVENT_EXTERNAL_REGISTER;
        ev.ext().registr().kind = @intCast(seg_type);
        ev.ext().registr().guid[0] = off.Hidden.getGuid(P, 0);
        ev.ext().registr().guid[1] = off.Hidden.getGuid(P, 1);
        _ = arcan_shmif_enqueue(&res, &ev);
    }

    res.shmsize = off.Page.getSegmentSize(res.addr.?);
    res.cookie = arcan_shmif_cookie();
    off.Hidden.setType(P, seg_type);
    setup_avbuf(&res);

    _ = pthread_mutex_init(@ptrCast(@alignCast(off.Hidden.getLockPtr(P))), null);

    if (seg_type == @as(c_int, @intCast(c.SEGID_ENCODER)) or seg_type == @as(c_int, @intCast(c.SEGID_CLIPBOARD_PASTE))) {
        off.Hidden.setOutput(P, true);
    }

    return res;
}

// arcan_shmif_acquire
// The C version uses va_list for FATALFAIL_FUNC. We provide the
// exported function that always passes null for the exit function
// (the common case). The va_arg path is an advanced/rare feature.

export fn arcan_shmif_acquire(
    parent: ?*c.struct_arcan_shmif_cont,
    shmkey: [*c]const u8,
    seg_type: c_int,
    flags: c_int,
) c.struct_arcan_shmif_cont {
    return shmif_acquire_int(parent, shmkey, seg_type, flags, null);
}

// arcan_shmif_integrity_check

export fn arcan_shmif_integrity_check(cont: ?*c.struct_arcan_shmif_cont) bool {
    const ct = cont orelse return false;
    const shmp = ct.addr orelse return false;

    if (off.Page.getMajor(shmp) != c.ASHMIF_VERSION_MAJOR or
        off.Page.getMinor(shmp) != c.ASHMIF_VERSION_MINOR)
        return false;

    if (off.Page.getCookie(shmp) != ct.cookie)
        return false;

    return true;
}

// arcan_shmif_args

export fn arcan_shmif_args(inctx: ?*c.struct_arcan_shmif_cont) [*c]c.struct_arg_arr {
    const ctx = inctx orelse return null;
    const P: *anyopaque = @ptrCast(@alignCast(ctx.priv orelse return null));
    return @ptrCast(@alignCast(off.Hidden.getArgs(P)));
}

// arcan_shmif_drop

export fn arcan_shmif_drop(C: ?*c.struct_arcan_shmif_cont) void {
    if (is_freestanding) return;
    const cont = C orelse return;
    if (cont.priv == null) return;

    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    if (@as(?*const fn (*c.struct_arcan_shmif_cont, c_int) callconv(.c) void, @ptrCast(@alignCast(off.Hidden.getSupportWindowHook(P))))) |hook| {
        hook(cont, @intCast(c.SUPPORT_EVENT_EXIT));
    }

    _ = pthread_mutex_lock(@ptrCast(@alignCast(off.Hidden.getLockPtr(P))));

    if (off.Hidden.getValidInitial(P))
        shmifint_drop_initial(cont);

    const lw = off.Hidden.getLastWords(P);
    if (lw != null) {
        log_fmt("[shmif:drop] last words: %s\n", .{lw});
        free(@as(?*anyopaque, @ptrCast(lw)));
        off.Hidden.setLastWords(P, null);
    }

    if (cont.addr) |addr| {
        off.Page.setDms(addr, 0);
    }

    if (cont == primary_input)
        primary_input = null;

    if (cont == primary_output)
        primary_output = null;

    if (off.Hidden.getArgs(P) != null)
        arg_cleanup(@ptrCast(@alignCast(off.Hidden.getArgs(P))));

    free(@as(?*anyopaque, @ptrCast(off.Hidden.getAltConn(P))));
    off.Hidden.setAltConn(P, null);

    if (cont.privext) |pe| {
        if (pe.*.cleanup) |cleanup_fn| {
            cleanup_fn(cont);
        }

        if (pe.*.active_fd != -1)
            _ = close(pe.*.active_fd);

        if (pe.*.pending_fd != -1)
            _ = close(pe.*.pending_fd);

        free(@as(?*anyopaque, @ptrCast(pe)));
    }

    // Clean up compositor-allocated DMA-BUF vidp mapping
    const dmabuf_fd = off.Hidden.getDmabufVidpFd(P);
    if (dmabuf_fd >= 0) {
        const dmabuf_ptr = off.Hidden.getDmabufVidpPtr(P);
        const dmabuf_sz = off.Hidden.getDmabufVidpMapSz(P);
        if (dmabuf_ptr != null and dmabuf_sz > 0)
            _ = munmap(dmabuf_ptr, dmabuf_sz);
        _ = close(dmabuf_fd);
        off.Hidden.setDmabufVidpFd(P, -1);
    }

    _ = pthread_mutex_unlock(@ptrCast(@alignCast(off.Hidden.getLockPtr(P))));
    _ = pthread_mutex_destroy(@ptrCast(@alignCast(off.Hidden.getLockPtr(P))));

    shmif_platform_guard_release(cont);

    _ = close(cont.epipe);
    _ = close(cont.shmh);
    _ = munmap(cont.addr, cont.shmsize);

    const cont_bytes: [*]u8 = @ptrCast(cont);
    @memset(cont_bytes[0..@sizeOf(c.struct_arcan_shmif_cont)], 0);
    cont.epipe = -1;
}

// shmif_resize

fn shmif_resize(
    C: ?*c.struct_arcan_shmif_cont,
    width_in: c_uint,
    height_in: c_uint,
    ext: c.struct_shmif_resize_ext,
) bool {
    const cont = C orelse return false;
    if (cont.addr == null or !arcan_shmif_integrity_check(cont) or cont.priv == null)
        return false;
    if (width_in > c.PP_SHMPAGE_MAXW or height_in > c.PP_SHMPAGE_MAXH)
        return false;

    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    const abufsz = ext.abuf_sz;
    var vidc: c_int = @intCast(ext.vbuf_cnt);
    var audc: c_int = @intCast(ext.abuf_cnt);
    const samplerate = ext.samplerate;
    const adata = ext.meta;

    // resize on a dead context triggers migration
    if (!shmif_platform_check_alive(cont)) {
        if (@as(?*const fn (c_int, ?*anyopaque) callconv(.c) void, @ptrCast(@alignCast(off.Hidden.getResetHook(P))))) |rh| rh(@as(c_int, @intCast(c.SHMIF_RESET_LOST)), off.Hidden.getResetHookTag(P));
        if (shmif_platform_fallback(cont, off.Hidden.getAltConn(P), true) != c.SHMIF_MIGRATE_OK)
            return false;
    }

    const width = if (width_in < 1) 1 else width_in;
    const height = if (height_in < 1) 1 else height_in;

    vidc = if (vidc < 0) @as(c_int, @intCast(off.Hidden.getVbufCnt(P))) else vidc;
    audc = if (audc < 0) @as(c_int, @intCast(off.Hidden.getAbufCnt(P))) else audc;

    const rpage = cont.addr.?;
    const dimensions_changed = width != cont.w or height != cont.h;
    const bufcnt_changed = vidc != @as(c_int, @intCast(off.Hidden.getVbufCnt(P))) or audc != @as(c_int, @intCast(off.Hidden.getAbufCnt(P)));
    const rpage_hints: u32 = off.Page.getHints(rpage);
    const hints_changed = rpage_hints != @as(u32, @intCast(cont.hints));
    const rpage_abufsize: u32 = off.Page.getAbufsize(rpage);
    const bufsz_changed = abufsz != 0 and rpage_abufsize != abufsz;

    if (cont.unnamed_0.vidp != null and !dimensions_changed and !bufcnt_changed and !hints_changed and !bufsz_changed) {
        if (@as(?*const fn (c_int, ?*anyopaque) callconv(.c) void, @ptrCast(@alignCast(off.Hidden.getResetHook(P))))) |rh| rh(@as(c_int, @intCast(c.SHMIF_RESET_NOCHG)), off.Hidden.getResetHookTag(P));
        return true;
    }

    // cancel pending vsynch
    if (off.Page.getVready(rpage) != 0) {
        off.Page.setVready(rpage, 0);
        if (shmif_platform_sync_trywait(cont.addr, @intCast(c.SYNC_VIDEO)) == 0) {
            _ = shmif_platform_sync_post(cont.addr, @intCast(c.SYNC_VIDEO));
        }
    }

    // audio flush attempt
    if (off.Page.getAready(rpage) != 0) {
        var count: c_int = 10;
        while (off.Page.getAready(rpage) != 0 and
            shmif_platform_check_alive(cont) and count > 0)
        {
            if (shmif_platform_sync_trywait(cont.addr, @intCast(c.SYNC_AUDIO)) == 0)
                count -= 1;
        }
        _ = shmif_platform_sync_post(cont.addr, @intCast(c.SYNC_AUDIO));
    }

    // synchronize hints
    off.Page.setHints(rpage, @intCast(cont.hints));
    off.Page.setApadType(rpage, @intCast(adata));

    if (samplerate < 0)
        off.Page.setAudiorate(rpage, @intCast(cont.samplerate))
    else if (samplerate == 0)
        off.Page.setAudiorate(rpage, @intCast(c.ARCAN_SHMIF_SAMPLERATE))
    else
        off.Page.setAudiorate(rpage, @intCast(samplerate));

    off.Page.setW(rpage, @intCast(width));
    off.Page.setH(rpage, @intCast(height));
    off.Page.setRows(rpage, @intCast(ext.rows));
    off.Page.setCols(rpage, @intCast(ext.cols));
    off.Page.setAbufsize(rpage, @intCast(abufsz));
    off.Page.setApending(rpage, @intCast(audc));
    off.Page.setVpending(rpage, @intCast(vidc));

    FORCE_SYNCH();
    off.Page.setResized(rpage, 1);

    // wait for server to acknowledge resize
    var wait_loops: u32 = 0;
    while (off.Page.getResized(rpage) > 0 and shmif_platform_check_alive(cont)) {
        _ = shmif_platform_sync_trywait(cont.addr, @intCast(c.SYNC_VIDEO));
        wait_loops += 1;
    }

    if (!shmif_platform_check_alive(cont)) {
        if (@as(?*const fn (c_int, ?*anyopaque) callconv(.c) void, @ptrCast(@alignCast(off.Hidden.getResetHook(P))))) |rh| {
            rh(@as(c_int, @intCast(c.SHMIF_RESET_NOCHG)), off.Hidden.getResetHookTag(P));
            rh(@as(c_int, @intCast(c.SHMIF_RESET_LOST)), off.Hidden.getResetHookTag(P));
        }
        _ = shmif_platform_fallback(cont, off.Hidden.getAltConn(P), true);
        return false;
    }

    if (off.Page.getResized(rpage) == -1) {
        off.Page.setResized(rpage, 0);
        if (@as(?*const fn (c_int, ?*anyopaque) callconv(.c) void, @ptrCast(@alignCast(off.Hidden.getResetHook(P))))) |rh| rh(@as(c_int, @intCast(c.SHMIF_RESET_NOCHG)), off.Hidden.getResetHookTag(P));
        return false;
    }

    const old_addr = @intFromPtr(cont.addr);

    if (cont.shmsize != @as(usize, off.Page.getSegmentSize(cont.addr.?))) {
        const new_sz: usize = off.Page.getSegmentSize(cont.addr.?);

        shmif_platform_guard_lock(cont);

        _ = munmap(cont.addr, cont.shmsize);
        cont.shmsize = new_sz;
        cont.addr = @ptrCast(@alignCast(mmap(null, cont.shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, cont.shmh, 0)));

        if (cont.addr == null)
            return false;

        shmif_platform_guard_resynch(cont, @intCast(off.Page.getParent(cont.addr.?)), cont.epipe);
        shmif_platform_guard_unlock(cont);
    }

    shmif_platform_setevqs(cont.addr, null, castEvctx(off.Hidden.getInevPtr(P)), castEvctx(off.Hidden.getOutevPtr(P)));
    setup_avbuf(cont);
    off.Hidden.setMultipartOfs(P, 0);

    if (@as(?*const fn (c_int, ?*anyopaque) callconv(.c) void, @ptrCast(@alignCast(off.Hidden.getResetHook(P))))) |rh| {
        rh(
            if (old_addr != @intFromPtr(cont.addr)) @as(c_int, @intCast(c.SHMIF_RESET_REMAP)) else @as(c_int, @intCast(c.SHMIF_RESET_NOCHG)),
            off.Hidden.getResetHookTag(P),
        );
    }

    return true;
}

// arcan_shmif_resize_ext

export fn arcan_shmif_resize_ext(
    arg: ?*c.struct_arcan_shmif_cont,
    width: c_uint,
    height: c_uint,
    ext: c.struct_shmif_resize_ext,
) bool {
    return shmif_resize(arg, width, height, ext);
}

// arcan_shmif_resize

export fn arcan_shmif_resize(
    arg: ?*c.struct_arcan_shmif_cont,
    width: c_uint,
    height: c_uint,
) bool {
    const cont = arg orelse return false;
    if (cont.addr == null) return false;

    var ext: c.struct_shmif_resize_ext = std.mem.zeroes(c.struct_shmif_resize_ext);
    ext.abuf_sz = off.Page.getAbufsize(cont.addr.?);
    ext.vbuf_cnt = -1;
    ext.abuf_cnt = -1;
    ext.samplerate = -1;

    return shmif_resize(cont, width, height, ext);
}

// arcan_shmif_signalhook

export fn arcan_shmif_signalhook(
    cont: ?*c.struct_arcan_shmif_cont,
    mask: c_int,
    hook: c.shmif_trigger_hook_fptr,
    data: ?*anyopaque,
) c.shmif_trigger_hook_fptr {
    const ct = cont orelse return null;
    const priv: *anyopaque = @ptrCast(@alignCast(ct.priv));
    var rv: c.shmif_trigger_hook_fptr = null;

    const mask_u: c_uint = @bitCast(mask);
    if (mask_u == (c.SHMIF_SIGVID | c.SHMIF_SIGAUD)) {
        // noop for combined mask
    } else if (mask_u == c.SHMIF_SIGVID) {
        rv = @ptrCast(@alignCast(off.Hidden.getVideoHook(priv)));
        off.Hidden.setVideoHook(priv, @constCast(@ptrCast(hook)));
        off.Hidden.setVideoHookData(priv, data);
    } else if (mask_u == c.SHMIF_SIGAUD) {
        rv = @ptrCast(@alignCast(off.Hidden.getAudioHook(priv)));
        off.Hidden.setAudioHook(priv, @constCast(@ptrCast(hook)));
        off.Hidden.setAudioHookData(priv, data);
    }

    return rv;
}

// arcan_shmif_primary

export fn arcan_shmif_primary(seg_type: c_int) ?*c.struct_arcan_shmif_cont {
    const seg_u: c_uint = @bitCast(seg_type);
    if (seg_u == c.SHMIF_INPUT)
        return primary_input
    else if (seg_u == c.SHMIF_ACCESSIBILITY)
        return primary_accessibility
    else
        return primary_output;
}

// arcan_shmif_setprimary

export fn arcan_shmif_setprimary(
    seg_type: c_int,
    seg: ?*c.struct_arcan_shmif_cont,
) void {
    const seg_u: c_uint = @bitCast(seg_type);
    if (seg_u == c.SHMIF_INPUT)
        primary_input = seg
    else if (seg_u == c.SHMIF_ACCESSIBILITY)
        primary_accessibility = seg
    else
        primary_output = seg;
}

// arcan_shmif_guid

export fn arcan_shmif_guid(
    cont: ?*c.struct_arcan_shmif_cont,
    guid: ?*[2]u64,
) void {
    const g = guid orelse return;

    const ct = cont orelse {
        g.*[0] = 0;
        g.*[1] = 0;
        return;
    };
    const P: *anyopaque = @ptrCast(@alignCast(ct.priv orelse {
        g.*[0] = 0;
        g.*[1] = 0;
        return;
    }));

    g.*[0] = off.Hidden.getGuid(P, 0);
    g.*[1] = off.Hidden.getGuid(P, 1);
}

// arcan_shmif_signalstatus

export fn arcan_shmif_signalstatus(C: ?*c.struct_arcan_shmif_cont) c_int {
    const cont = C orelse return -1;
    if (cont.addr == null) return -1;
    if (off.Page.getDms(cont.addr.?) == 0) return -1;

    var result: c_int = 0;
    if (off.Page.getAready(cont.addr.?) != 0)
        result |= 2;
    if (off.Page.getVready(cont.addr.?) != 0)
        result |= 1;

    return result;
}

// arcan_shmif_lock

export fn arcan_shmif_lock(C: ?*c.struct_arcan_shmif_cont) bool {
    const cont = C orelse return false;
    if (cont.addr == null) return false;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    if (off.Hidden.getInLock(P) and pthread_equal(usizeToPthread(off.Hidden.getLockId(P)), pthread_self()) != 0)
        return false;

    if (pthread_mutex_lock(@ptrCast(@alignCast(off.Hidden.getLockPtr(P)))) != 0)
        return false;

    off.Hidden.setInLock(P, true);
    off.Hidden.setLockId(P, pthreadToUsize(pthread_self()));
    return true;
}

// arcan_shmif_unlock

export fn arcan_shmif_unlock(C: ?*c.struct_arcan_shmif_cont) bool {
    const cont = C orelse return false;
    if (cont.addr == null) return false;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));
    if (!off.Hidden.getInLock(P)) return false;

    if (pthread_equal(usizeToPthread(off.Hidden.getLockId(P)), pthread_self()) == 0)
        return false;

    if (pthread_mutex_unlock(@ptrCast(@alignCast(off.Hidden.getLockPtr(P)))) != 0)
        return false;

    off.Hidden.setInLock(P, false);
    return true;
}

// arcan_shmif_dupfd

export fn arcan_shmif_dupfd(fd: c_int, dstnum: c_int, nonblocking: bool) c_int {
    return shmif_platform_dupfd_to(fd, dstnum, if (nonblocking) O_NONBLOCK else 0, FD_CLOEXEC);
}

// arcan_shmif_last_words

export fn arcan_shmif_last_words(
    cont: ?*c.struct_arcan_shmif_cont,
    msg: [*c]const u8,
) void {
    const ct = cont orelse return;
    if (ct.addr == null) return;
    const P: *anyopaque = @ptrCast(@alignCast(ct.priv));

    const lw = off.Hidden.getLastWords(P);
    if (lw != null) {
        free(@as(?*anyopaque, @ptrCast(lw)));
        off.Hidden.setLastWords(P, null);
    }

    if (msg == null) {
        off.Page.setLastWordsChar(ct.addr.?, 0, 0);
        return;
    }

    off.Hidden.setLastWords(P, strdup(msg));

    // manually write into volatile last_words
    const lim = off.Page.sizeof_last_words;
    var i: usize = 0;
    while (i < lim - 1 and msg[i] != 0 and msg[i] != '\n') : (i += 1) {
        off.Page.setLastWordsChar(ct.addr.?, i, msg[i]);
    }
    off.Page.setLastWordsChar(ct.addr.?, i, 0);
}

// arcan_shmif_initial

export fn arcan_shmif_initial(
    cont: ?*c.struct_arcan_shmif_cont,
    out: ?*?*c.struct_arcan_shmif_initial,
) usize {
    const out_ptr = out orelse return 0;
    const ct = cont orelse return 0;
    const P: *anyopaque = @ptrCast(@alignCast(ct.priv orelse return 0));
    if (!off.Hidden.getValidInitial(P)) return 0;

    out_ptr.* = castInitial(off.Hidden.getInitialPtr(P));
    return @sizeOf(c.struct_arcan_shmif_initial);
}

// apply_ext_options

fn apply_ext_options(
    C: *c.struct_arcan_shmif_cont,
    ext: c.struct_shmif_open_ext,
    _: usize,
) void {
    const priv: *anyopaque = @ptrCast(@alignCast(C.priv));
    if (ext.guid[0] != 0 or ext.guid[1] != 0) {
        off.Hidden.setGuid(priv, 0, ext.guid[0]);
        off.Hidden.setGuid(priv, 1, ext.guid[1]);
    } else {
        arcan_random(@ptrCast(off.Hidden.getGuidPtr(priv)), 16);
    }

    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.category().* = @intCast(c.EVENT_EXTERNAL);
    ev.ext().kind = c.EVENT_EXTERNAL_REGISTER;
    ev.ext().registr().kind = @intCast(ext.type);

    if (ext.title) |title| {
        _ = snprintf(
            @ptrCast(&ev.ext().registr().title),
            @sizeOf(@TypeOf(ev.ext().registr().title)),
            "%s",
            title,
        );
    }

    if (ext.type != c.SEGID_UNKNOWN) {
        _ = arcan_shmif_enqueue(C, &ev);

        if (ext.ident) |ident| {
            ev.ext().kind = c.EVENT_EXTERNAL_IDENT;
            _ = snprintf(
                @ptrCast(&ev.ext().message().data),
                @sizeOf(@TypeOf(ev.ext().message().data)),
                "%s",
                ident,
            );
            _ = arcan_shmif_enqueue(C, &ev);
        }
    }
}

// arcan_shmif_defer_register

export fn arcan_shmif_defer_register(
    C: ?*c.struct_arcan_shmif_cont,
    ev: c.arcan_event,
) bool {
    const cont = C orelse return false;
    var mev = ev;
    _ = arcan_shmif_enqueue(cont, &mev);
    return shmifint_preroll_loop(cont, true);
}

// is_output_segment

fn is_output_segment(segid: c_int) bool {
    return (segid == @as(c_int, @intCast(c.SEGID_ENCODER)) or segid == @as(c_int, @intCast(c.SEGID_CLIPBOARD_PASTE)));
}

// arcan_shmif_open_ext

export fn arcan_shmif_open_ext(
    flags: c_int,
    outarg: ?*[*c]c.struct_arg_arr,
    ext: c.struct_shmif_open_ext,
    ext_sz: usize,
) c.struct_arcan_shmif_cont {
    if (g_epoch == 0)
        g_epoch = arcan_timemillis();

    // Side-channel breadcrumb so we can locate wedges even if stderr is
    // redirected. Writes straight to a known file via fopen.
    const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
    const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
    const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
    const sc_getpid = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });
    if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
        _ = sc_fprintf(f, "[%d] enter open_ext flags=0x%x\n", sc_getpid(), flags);
        _ = sc_fclose(f);
    }

    var ret: c.struct_arcan_shmif_cont = std.mem.zeroes(c.struct_arcan_shmif_cont);
    if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
        _ = sc_fprintf(f, "[%d] pre open_env_connection\n", sc_getpid());
        _ = sc_fclose(f);
    }
    const con = shmif_platform_open_env_connection(flags);
    if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
        _ = sc_fprintf(f, "[%d] post open_env_connection err=%s\n", sc_getpid(),
            if (con.@"error") |e| e else @as([*c]const u8, "(none)"));
        _ = sc_fclose(f);
    }

    if (con.@"error" != null) {
        // goto fail
        dbg_write("[shmif::open_ext] connection error\n");
        if (@as(c_uint, @bitCast(flags)) & c.SHMIF_ACQUIRE_FATALFAIL != 0) {
            log_fmt("[shmif::open_ext], error connecting (%s)\n", .{if (con.@"error") |e| e else @as([*c]const u8, "")});
            exit(EXIT_FAILURE);
        }
        return ret;
    }

    dbg_write("[shmif::open_ext] connection OK\n");

    var cflags = con.flags;
    if (ext_sz > 0)
        cflags |= c.SHMIF_NOREGISTER;

    dbg_write("[shmif::open_ext] calling acquire\n");
    if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
        _ = sc_fprintf(f, "[%d] pre acquire\n", sc_getpid());
        _ = sc_fclose(f);
    }
    ret = arcan_shmif_acquire(null, con.keyfile, @intCast(ext.@"type"), flags | @as(c_int, @bitCast(cflags)));
    if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
        _ = sc_fprintf(f, "[%d] post acquire priv=%p addr=%p\n", sc_getpid(), ret.priv, ret.addr);
        _ = sc_fclose(f);
    }
    if (ret.priv == null) {
        dbg_write("[shmif::open_ext] acquire FAILED (priv=null)\n");
        _ = close(con.socket);
        return ret;
    }
    if (ret.addr == null)
        dbg_write("[shmif::open_ext] acquire OK but addr=NULL\n")
    else
        dbg_write("[shmif::open_ext] acquire OK, addr set\n");

    if (ext_sz > 0)
        apply_ext_options(&ret, ext, ext_sz);

    if (outarg) |oa| {
        oa.* = arg_unpack(if (con.args) |a| a else @as([*c]const u8, ""));
    }
    const P: *anyopaque = @ptrCast(@alignCast(ret.priv));
    off.Hidden.setArgs(P, @ptrCast(@alignCast(arg_unpack(if (con.args) |a| a else @as([*c]const u8, "")))));

    ret.epipe = con.socket;

    // Resynch the watchdog guard with the socket fd so it can use socket
    // liveness checks in addition to kill(pid,0). The guard was started
    // in shmif_acquire_int with parent_fd=-1 because the socket was not
    // yet available at that point.
    if (ret.addr != null and ret.priv != null) {
        shmif_platform_guard_lock(&ret);
        shmif_platform_guard_resynch(&ret, @intCast(off.Page.getParent(ret.addr.?)), ret.epipe);
        shmif_platform_guard_unlock(&ret);
    }

    if (con.alternate_cp != null and !con.networked) {
        off.Hidden.setAltConn(P, strdup(con.alternate_cp));
    }

    free(@as(?*anyopaque, @ptrCast(@constCast(con.keyfile))));

    if (ext.type > 0 and !is_output_segment(@intCast(ext.type)) and (@as(c_uint, @bitCast(flags)) & c.SHMIF_NOACTIVATE == 0)) {
        dbg_write("[shmif::open_ext] entering preroll_loop\n");
        if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
            _ = sc_fprintf(f, "[%d] pre preroll_loop type=%d\n", sc_getpid(), @as(c_int, @intCast(ext.type)));
            _ = sc_fclose(f);
        }
        if (!shmifint_preroll_loop(&ret, (@as(c_uint, @bitCast(flags)) & c.SHMIF_NOACTIVATE_RESIZE) == 0)) {
            dbg_write("[shmif::open_ext] preroll FAILED\n");
            if (@as(c_uint, @bitCast(flags)) & c.SHMIF_ACQUIRE_FATALFAIL != 0) {
                log_fmt("[shmif::open_ext], error connecting (%s)\n", .{if (con.@"error") |e| e else @as([*c]const u8, "")});
                exit(EXIT_FAILURE);
            }
            return ret;
        }
        dbg_write("[shmif::open_ext] preroll OK\n");
        if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
            _ = sc_fprintf(f, "[%d] post preroll_loop OK\n", sc_getpid());
            _ = sc_fclose(f);
        }
    } else {
        dbg_write("[shmif::open_ext] skipping preroll\n");
    }

    if (ret.addr == null)
        dbg_write("[shmif::open_ext] FINAL ret.addr=NULL\n")
    else
        dbg_write("[shmif::open_ext] FINAL ret.addr set\n");
    off.Hidden.setPrimaryId(P, pthreadToUsize(pthread_self()));
    return ret;
}

// arcan_shmif_open

export fn arcan_shmif_open(
    seg_type: c_int,
    flags: c_int,
    outarg: ?*[*c]c.struct_arg_arr,
) c.struct_arcan_shmif_cont {
    var ext: c.struct_shmif_open_ext = std.mem.zeroes(c.struct_shmif_open_ext);
    ext.type = @intCast(seg_type);
    return arcan_shmif_open_ext(flags, outarg, ext, 0);
}

// arcan_shmif_segkind

export fn arcan_shmif_segkind(con: ?*c.struct_arcan_shmif_cont) c_int {
    const ct = con orelse return @intCast(c.SEGID_UNKNOWN);
    const P: *anyopaque = @ptrCast(@alignCast(ct.priv orelse return @intCast(c.SEGID_UNKNOWN)));
    return off.Hidden.getType(P);
}

// arcan_shmif_handover_exec_pipe

export fn arcan_shmif_handover_exec_pipe(
    cont: ?*c.struct_arcan_shmif_cont,
    ev: c.arcan_event,
    path: [*c]const u8,
    argv: [*c]const [*c]u8,
    env: [*c]const [*c]u8,
    detach: c_int,
    fds: [*c]?*c_int,
    fdset_sz: usize,
) c.pid_t {
    const ct = cont orelse return -1;
    if (ct.addr == null) return -1;
    if (ev.category().* != c.EVENT_TARGET) return -1;
    if (ev.tgt().kind != c.TARGET_COMMAND_NEWSEGMENT) return -1;
    if (ev.tgt().ioevs[2].iv != @as(i32, @intCast(c.SEGID_HANDOVER))) return -1;

    const P: *anyopaque = @ptrCast(@alignCast(ct.priv));
    if (off.Hidden.getPsegEpipe(P) == BADFD) return -1;

    const dup_socket = dup(ev.tgt().ioevs[0].iv);
    const dup_mem = dup(ev.tgt().ioevs[6].iv);

    off.Hidden.setPsegEpipe(P, BADFD);
    off.Hidden.setPevHandedover(P, true);

    shmifint_consume_pending(ct);

    if (dup_socket == -1) return -1;

    const res = shmif_platform_execve(
        dup_socket,
        dup_mem,
        path,
        argv,
        env,
        detach,
        fds,
        fdset_sz,
        null,
    );

    _ = close(dup_socket);
    _ = close(dup_mem);

    return res;
}

// arcan_shmif_handover_exec

export fn arcan_shmif_handover_exec(
    cont: ?*c.struct_arcan_shmif_cont,
    ev: c.arcan_event,
    path: [*c]const u8,
    argv: [*c]const [*c]u8,
    env: [*c]const [*c]u8,
    detach_in: c_int,
) c.pid_t {
    var in_fd: c_int = STDIN_FILENO;
    var out_fd: c_int = STDOUT_FILENO;
    var err_fd: c_int = STDERR_FILENO;
    var detach = detach_in;

    var fds: [3]?*c_int = .{ &in_fd, &out_fd, &err_fd };

    if (detach & 2 != 0) {
        detach &= ~@as(c_int, 2);
        fds[0] = null;
    }

    if (detach & 4 != 0) {
        detach &= ~@as(c_int, 4);
        fds[1] = null;
    }

    if (detach & 8 != 0) {
        detach &= ~@as(c_int, 8);
        fds[2] = null;
    }

    return arcan_shmif_handover_exec_pipe(
        cont,
        ev,
        path,
        argv,
        env,
        detach,
        &fds,
        3,
    );
}

// arcan_shmif_deadline

export fn arcan_shmif_deadline(
    C: ?*c.struct_arcan_shmif_cont,
    _: c_uint,
    _: ?*c_int,
    _: ?*c_int,
) c_int {
    const cont = C orelse return -1;
    if (cont.addr == null) return -1;

    if (off.Page.getVready(cont.addr.?) != 0)
        return -2;

    return 0;
}

// arcan_shmif_dirty

export fn arcan_shmif_dirty(
    cont: ?*c.struct_arcan_shmif_cont,
    x1_in: usize,
    y1_in: usize,
    x2_in: usize,
    y2_in: usize,
    _: c_int,
) c_int {
    const ct = cont orelse return -1;
    if (ct.addr == null) return -1;

    var x1 = x1_in;
    var y1 = y1_in;
    var x2 = x2_in;
    var y2 = y2_in;

    if (x1 > 0xFFFF) x1 = 0;
    if (x2 > 0xFFFF) x2 = 0xFFFF;
    if (y1 > 0xFFFF) y1 = 0;
    if (y2 > 0xFFFF) y2 = 0xFFFF;

    if (x1 > x2) {
        const tmp = x1;
        x1 = x2;
        x2 = tmp;
    }
    if (y1 > y2) {
        const tmp = y1;
        y1 = y2;
        y2 = tmp;
    }

    if ((ct.hints & @as(u8, @intCast(c.SHMIF_RHINT_SUBREGION))) == 0) {
        ct.hints |= @as(u8, @intCast(c.SHMIF_RHINT_SUBREGION));
        _ = arcan_shmif_resize(ct, @intCast(ct.w), @intCast(ct.h));
    }

    if (x1 < ct.dirty.x1) ct.dirty.x1 = @intCast(x1);
    if (x2 > ct.dirty.x2) ct.dirty.x2 = @intCast(x2);
    if (y1 < ct.dirty.y1) ct.dirty.y1 = @intCast(y1);
    if (y2 > ct.dirty.y2) ct.dirty.y2 = @intCast(y2);

    if (ct.dirty.y2 > @as(u16, @intCast(ct.h)))
        ct.dirty.y2 = @intCast(ct.h);

    if (ct.dirty.x2 > @as(u16, @intCast(ct.w)))
        ct.dirty.x2 = @intCast(ct.w);

    return 0;
}

// arcan_shmif_resetfunc

export fn arcan_shmif_resetfunc(
    C: ?*c.struct_arcan_shmif_cont,
    hook: c.shmif_reset_hook_fptr,
    tag: ?*anyopaque,
) c.shmif_reset_hook_fptr {
    const ct = C orelse return null;
    const hs: *anyopaque = @ptrCast(@alignCast(ct.priv));
    const old_hook: c.shmif_reset_hook_fptr = @ptrCast(@alignCast(off.Hidden.getResetHook(hs)));

    off.Hidden.setResetHook(hs, @constCast(@ptrCast(hook)));
    off.Hidden.setResetHookTag(hs, tag);

    return old_hook;
}
