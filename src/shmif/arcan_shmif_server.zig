// Zig reimplementation of arcan_shmif_server.c
// Drop-in C-ABI-compatible replacement for shmif server library.
//
// Exports: shmifsrv_client_handle, shmifsrv_client_type,
//          shmifsrv_send_subsegment, shmifsrv_last_words,
//          shmifsrv_allocate_connpoint, shmifsrv_client_memory_handle,
//          shmifsrv_inherit_connection, shmifsrv_spawn_client,
//          shmifsrv_dequeue_events, shmifsrv_enqueue_event, shmifsrv_poll,
//          shmifsrv_free, shmifsrv_enter, shmifsrv_leave,
//          shmifsrv_client_protomask, shmifsrv_video_step,
//          shmifsrv_video_copy, shmifsrv_video_copy_free,
//          shmifsrv_video, shmifsrv_process_event, shmifsrv_audio,
//          shmifsrv_tick, shmifsrv_monotonic_tick, shmifsrv_monotonic_rebase,
//          shmifsrv_enqueue_multipart_message, shmifsrv_put_video,
//          shmifsrv_merge_multipart_message, shmifsrv_wrap_context
//
const std = @import("std");
const builtin = @import("builtin");
const off = @import("shmif_offsets");
const c = @import("shmif_types");

// Opaque type for struct arcan_frameserver
// (opaque in Zig due to bitfield bool members in flags/clock sub-structs)
const ArcanFrameserver = opaque {};

// Native Zig replacement for struct shmifsrv_vbuffer
// (the C struct is opaque due to bitfield bools in the flags sub-struct)
//
// Consumers (src/a12/a12.zig, src/a12/net/helper_srv.zig, session.zig)
// @cInclude "arcan_shmif_server.h" with SHMIF_SERVER_NO_BITFIELDS
// defined, so they see the `flags` sub-struct as seven distinct `bool`
// fields — not one bitfield byte. If our VbufFlags here were a
// `packed struct(u8)` (1 byte), writing tpack=true on this side would
// silently not survive the round-trip: consumers would read from the
// wrong byte because their struct is 7+ bytes wider.
//
// Keep the layout identical by mirroring NO_BITFIELDS: 7 bools, each
// its own u8, no padding/packing. An extern struct with u8 members
// matches the C `bool foo;` layout on every platform we run.
const VbufFlags = extern struct {
    origo_ll: u8 = 0,
    ignore_alpha: u8 = 0,
    subregion: u8 = 0,
    srgb: u8 = 0,
    hwhandles: u8 = 0,
    tpack: u8 = 0,
    compressed: u8 = 0,
};

const ShmifsrvVbuffer = extern struct {
    state: c_int = 0,
    buffer: ?[*]u8 = null, // union { shmif_pixel* buffer; uint8_t* buffer_bytes; }
    flags: VbufFlags = .{},
    fourcc: [4]u8 = .{ 0, 0, 0, 0 },
    buffer_sz: usize = 0,
    w: usize = 0,
    h: usize = 0,
    pitch: usize = 0,
    stride: usize = 0,
    vpts: u64 = 0,
    region: c.struct_arcan_shmif_region = std.mem.zeroes(c.struct_arcan_shmif_region),
    formats: [4]usize = .{ 0, 0, 0, 0 },
    planes: [4]c_int = .{ 0, 0, 0, 0 },
};

// struct shmifsrv_envp (from arcan_shmif_server.h)
// Defined natively because arcan_shmif_server.h can't be @cInclude'd
// (it pulls in shmifsrv_vbuffer which has bitfields -> opaque).
const ShmifsrvEnvp = extern struct {
    fd_bin: c_int = 0,
    path: [*c]const u8 = null,
    argv: [*c]const [*c]u8 = null,
    envv: [*c]const [*c]u8 = null,
    init_w: usize = 0,
    init_h: usize = 0,
    detach: c_int = 0,
    @"type": c_int = 0,
};

// Constants from arcan_shmif_server.h

// enum shmifsrv_status
const SHMIFSRV_OK: c_int = 1;
const SHMIFSRV_INVALID_ARGUMENT: c_int = -1;
const SHMIFSRV_OUT_OF_MEMORY: c_int = -2;
const SHMIFSRV_EXEC_FAILED: c_int = -3;

// enum shmifsrv_action
const SHMIFSRV_FREE_FULL: c_uint = 0;
const SHMIFSRV_FREE_NO_DMS: c_uint = 1;
const SHMIFSRV_FREE_LOCAL: c_uint = 2;

// enum shmifsrv_client_status
const CLIENT_DEAD: c_int = -1;
const CLIENT_NOT_READY: c_int = 0;
const CLIENT_VBUFFER_READY: c_int = 1;
const CLIENT_ABUFFER_READY: c_int = 2;
const CLIENT_IDLE: c_int = 4;

// enum vbuffer_status
const VBUFFER_OUTPUT: c_int = -1;
const VBUFFER_NODATA: c_int = 0;
const VBUFFER_OKDATA: c_int = 1;
const VBUFFER_HANDLE: c_int = 2;

// Constants from arcan_general.h (not @cInclude'd to avoid frameserver dependency)
const ARCAN_OK: c_int = 0;
const ARCAN_TIMER_TICK: i64 = 25;
const ARCAN_TICK_THRESHOLD: c_int = 100;

// Extern C declarations

extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
extern "c" fn memset(dst: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;
extern "c" fn strlen(s: [*c]const u8) usize;
extern "c" fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn shutdown(sockfd: c_int, how: c_int) c_int;
extern "c" fn sleep(seconds: c_uint) c_uint;
extern "c" fn kill(pid: c.pid_t, sig: c_int) c_int;
extern "c" fn waitpid(pid: c.pid_t, status: ?*c_int, options: c_int) c.pid_t;
extern "c" fn setjmp(env: *anyopaque) c_int;

extern "c" fn pthread_create(thread: *c.pthread_t, attr: ?*const c.pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
extern "c" fn pthread_attr_init(attr: *c.pthread_attr_t) c_int;
extern "c" fn pthread_attr_setdetachstate(attr: *c.pthread_attr_t, detachstate: c_int) c_int;
extern "c" fn pthread_attr_destroy(attr: *c.pthread_attr_t) c_int;

extern "c" fn arcan_shmif_cookie() u64;
extern "c" fn arcan_timemillis() c_ulonglong;
extern "c" fn shmif_platform_sync_post(page: ?*anyopaque, slot: c_int) c_int;
extern "c" fn shmif_platform_pushfd(fd: c_int, sockout: c_int) bool;
extern "c" fn shmif_platform_dupfd_to(fd: c_int, dstnum: c_int, fflags: c_int, fdopt: c_int) c_int;
extern "c" fn shmif_platform_fetchfds(sockin: c_int, fdout: [*c]c_int, cap: usize, blocking: bool, alive_check: ?*const fn (?*anyopaque) callconv(.c) bool, tag: ?*anyopaque) c_int;

// Platform frameserver functions (use ArcanFrameserver opaque)
extern "c" fn platform_fsrv_spawn_subsegment(src: *ArcanFrameserver, segid: c_int, hints: c_int, init_w: usize, init_h: usize, reqid: c_int, idtok: u32) ?*ArcanFrameserver;
extern "c" fn platform_fsrv_lastwords(fsrv: *ArcanFrameserver, outbuf: [*c]u8, outbuf_sz: usize) bool;
extern "c" fn platform_fsrv_listen_external(name: [*c]const u8, key: [*c]const u8, fd: c_int, permission: c.mode_t, w: c_int, h: c_int, flags: c_int) ?*ArcanFrameserver;
extern "c" fn platform_fsrv_preset_server(sockin: c_int, memin: c_int, segid: c_int, w: c_int, h: c_int, flags: c_int) ?*ArcanFrameserver;
extern "c" fn platform_fsrv_spawn_server(segid: c_int, init_w: usize, init_h: usize, flags: c_int, childend: *c_int) ?*ArcanFrameserver;
extern "c" fn platform_fsrv_pushevent(fsrv: *ArcanFrameserver, ev: *const c.arcan_event) c_int;
extern "c" fn platform_fsrv_socketpoll(fsrv: *ArcanFrameserver) c_int;
extern "c" fn platform_fsrv_socketauth(fsrv: *ArcanFrameserver) c_int;
extern "c" fn platform_fsrv_resynch(fsrv: *ArcanFrameserver) c_int;
extern "c" fn platform_fsrv_destroy(fsrv: *ArcanFrameserver) void;
extern "c" fn platform_fsrv_destroy_local(fsrv: *ArcanFrameserver) void;
extern "c" fn platform_fsrv_enter(fsrv: *ArcanFrameserver, tramp: *anyopaque) void;
extern "c" fn platform_fsrv_leave() void;
extern "c" fn shmif_platform_execve(shmif_fd: c_int, mem_fd: c_int, path: [*c]const u8, argv: [*c]const [*c]u8, env: [*c]const [*c]u8, options: c_int, fds: [*c]?*c_int, fds_sz: usize, err: ?*[*c]u8) c.pid_t;
extern "c" fn platform_fsrv_wrapcl(cont: *c.struct_arcan_shmif_cont, tag: usize) ?*ArcanFrameserver;

// (C helper accessors removed — now using off.Fsrv.* from shmif_offsets module)

// Constants

const BADFD: c_int = -1;
const SHUT_RDWR: c_int = 2;
const SIGKILL: c_int = 9;
const WNOHANG: c_int = 1;
const PTHREAD_CREATE_DETACHED: c_int = 1;
const STDIN_FILENO: c_int = 0;
const STDOUT_FILENO: c_int = 1;
const STDERR_FILENO: c_int = 2;
const EBADF: c_int = 9;
const EWOULDBLOCK: c_int = 11;

fn get_errno() c_int {
    return std.c._errno().*;
}

// Connection status

const ConnStatus = enum(c_int) {
    DEAD = -1,
    BROKEN = 0,
    PENDING = 1,
    AUTHENTICATING = 2,
    READY = 3,
};

// shmifsrv_client struct

const ShmifsrvClient = extern struct {
    con: ?*ArcanFrameserver,
    multipart: [4096]u8,
    multipart_ofs: usize,
    status: c_int,
    pid: c.pid_t,
    errors: usize,
    cookie: u64,
};

fn alloc_client() ?*ShmifsrvClient {
    const raw = malloc(@sizeOf(ShmifsrvClient)) orelse return null;
    const res: *ShmifsrvClient = @ptrCast(@alignCast(raw));
    res.* = std.mem.zeroes(ShmifsrvClient);
    res.status = @intFromEnum(ConnStatus.BROKEN);
    res.cookie = arcan_shmif_cookie();
    return res;
}

// Inline helper: FORCE_SYNCH
var force_synch_dummy: u32 = 0;
inline fn FORCE_SYNCH() void {
    asm volatile ("" ::: .{ .memory = true });
    _ = @atomicRmw(u32, &force_synch_dummy, .Add, 0, .seq_cst);
}

// UTF-8 DFA Decoder (from Bjoern Hoehrmann)
const UTF8_ACCEPT: u32 = 0;
const UTF8_REJECT: u32 = 1;

const utf8d = [_]u8{
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,
    7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,
    8,   8,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,
    0xa, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x3, 0x3, 0xb, 0x6, 0x6, 0x6, 0x5, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
    0x0, 0x1, 0x2, 0x3, 0x5, 0x8, 0x7, 0x1, 0x1, 0x1, 0x4, 0x6, 0x1, 0x1, 0x1, 0x1, 1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   0,   1,   1,   1,   1,   1,   0,   1,   0,   1,   1,   1,   1,   1,   1,   1,   2,   1,   1,   1,   1,   1,   2,   1,   2,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   2,   1,   1,   1,   1,   1,   1,   1,   1,   1,   2,   1,   1,   1,   1,   1,   1,   1,   2,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   3,   1,   3,   1,   1,   1,   1,   1,   1,   1,   3,   1,   1,   1,   1,   1,   3,   1,   3,   1,   1,   1,   1,   1,   1,
    1,   3,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
};

fn utf8_decode(state: *u32, codep: *u32, byte: u32) u32 {
    const typ: u32 = utf8d[byte];
    codep.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3f) | (codep.* << 6)
    else
        (@as(u32, 0xff) >> @intCast(typ)) & byte;

    state.* = utf8d[256 + state.* * 16 + typ];
    return state.*;
}

// shmifsrv_client_handle

export fn shmifsrv_client_handle(cl: ?*ShmifsrvClient, pid: ?*c_int) c_int {
    const client = cl orelse return -1;
    if (client.status <= @intFromEnum(ConnStatus.BROKEN)) return -1;

    if (pid) |p| p.* = client.pid;

    return off.Fsrv.getDpipe(@ptrCast(client.con.?));
}

// shmifsrv_client_type

export fn shmifsrv_client_type(cl: ?*ShmifsrvClient) c_int {
    const client = cl orelse return @intCast(c.SEGID_UNKNOWN);
    if (client.con == null) return @intCast(c.SEGID_UNKNOWN);
    return @intCast(off.Fsrv.getSegid(@ptrCast(client.con.?)));
}

// shmifsrv_send_subsegment

export fn shmifsrv_send_subsegment(
    cl: ?*ShmifsrvClient,
    segid: c_int,
    hints: c_int,
    init_w: usize,
    init_h: usize,
    reqid: c_int,
    idtok: u32,
) ?*ShmifsrvClient {
    const client = cl orelse return null;
    if (client.status < @intFromEnum(ConnStatus.READY)) return null;

    const res = alloc_client() orelse return null;

    res.con = platform_fsrv_spawn_subsegment(
        client.con.?,
        segid,
        hints,
        init_w,
        init_h,
        reqid,
        idtok,
    );
    if (res.con == null) {
        free(@as(?*anyopaque, @ptrCast(res)));
        return null;
    }
    res.cookie = arcan_shmif_cookie();
    res.status = @intFromEnum(ConnStatus.READY);

    return res;
}

// shmifsrv_last_words

export fn shmifsrv_last_words(
    cl: ?*ShmifsrvClient,
    outbuf: [*c]u8,
    outbuf_sz: usize,
) void {
    const client = cl orelse return;
    if (!platform_fsrv_lastwords(client.con.?, outbuf, outbuf_sz)) {
        _ = snprintf(outbuf, outbuf_sz, "Couldn't access metadata");
    }
}

// shmifsrv_allocate_connpoint

export fn shmifsrv_allocate_connpoint(
    name: [*c]const u8,
    key: [*c]const u8,
    permission: c.mode_t,
    fd: c_int,
) ?*ShmifsrvClient {
    _ = shmifsrv_monotonic_tick(null);
    const res = alloc_client() orelse return null;

    res.con = platform_fsrv_listen_external(name, key, fd, permission, 32, 32, 0);
    if (res.con == null) {
        free(@as(?*anyopaque, @ptrCast(res)));
        return null;
    }

    res.cookie = arcan_shmif_cookie();
    res.status = @intFromEnum(ConnStatus.PENDING);

    return res;
}

// shmifsrv_client_memory_handle

export fn shmifsrv_client_memory_handle(cl: ?*ShmifsrvClient) c_int {
    const client = cl orelse return -1;
    if (client.con == null) return -1;
    return off.Fsrv.getShmHandle(@ptrCast(client.con.?));
}

// shmifsrv_wrap_context

export fn shmifsrv_wrap_context(in: ?*c.struct_arcan_shmif_cont) ?*ShmifsrvClient {
    const cont = in orelse return null;
    const res = alloc_client() orelse return null;

    res.con = platform_fsrv_wrapcl(cont, 0);
    res.status = @intFromEnum(ConnStatus.READY);

    return res;
}

// shmifsrv_inherit_connection

export fn shmifsrv_inherit_connection(
    sockin: c_int,
    memin: c_int,
    statuscode: ?*c_int,
) ?*ShmifsrvClient {
    if (sockin == -1) {
        if (statuscode) |sc| sc.* = SHMIFSRV_INVALID_ARGUMENT;
        return null;
    }

    const res = alloc_client() orelse {
        _ = shutdown(sockin, SHUT_RDWR);
        _ = close(sockin);
        if (statuscode) |sc| sc.* = SHMIFSRV_OUT_OF_MEMORY;
        return null;
    };

    res.con = platform_fsrv_preset_server(sockin, memin, @intCast(c.SEGID_UNKNOWN), 0, 0, 0);

    if (statuscode) |sc| sc.* = SHMIFSRV_OK;

    res.cookie = arcan_shmif_cookie();
    res.status = @intFromEnum(ConnStatus.AUTHENTICATING);

    return res;
}

// shmifsrv_spawn_client

export fn shmifsrv_spawn_client(
    env: ShmifsrvEnvp,
    clsocket: ?*c_int,
    statuscode: ?*c_int,
    _: u32,
) ?*ShmifsrvClient {
    const clsock = clsocket orelse {
        if (statuscode) |sc| sc.* = SHMIFSRV_INVALID_ARGUMENT;
        return null;
    };

    const res = alloc_client() orelse {
        if (statuscode) |sc| sc.* = SHMIFSRV_OUT_OF_MEMORY;
        return null;
    };

    var childend: c_int = undefined;
    res.con = platform_fsrv_spawn_server(
        if (env.@"type" != 0) env.@"type" else @as(c_int, @intCast(c.SEGID_UNKNOWN)),
        env.init_w,
        env.init_h,
        0,
        &childend,
    );

    if (res.con == null) {
        if (statuscode) |sc| sc.* = SHMIFSRV_OUT_OF_MEMORY;
        shmifsrv_free(res, @intCast(SHMIFSRV_FREE_FULL));
        return null;
    }

    clsock.* = childend;
    res.cookie = arcan_shmif_cookie();
    res.status = @intFromEnum(ConnStatus.READY);
    res.pid = -1;

    if (statuscode) |sc| sc.* = SHMIFSRV_OK;

    var in_fd: c_int = STDIN_FILENO;
    var out_fd: c_int = STDOUT_FILENO;
    var err_fd: c_int = STDERR_FILENO;
    var fds: [3]?*c_int = .{ &in_fd, &out_fd, &err_fd };
    var detach = env.detach;

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

    if (env.path != null) {
        const shmfd = shmif_platform_dupfd_to(off.Fsrv.getShmHandle(@ptrCast(res.con.?)), -1, 0, 0);

        const rpid = shmif_platform_execve(
            childend,
            shmfd,
            env.path,
            env.argv,
            env.envv,
            detach,
            &fds,
            3,
            null,
        );

        _ = close(shmfd);
        _ = close(childend);

        if (rpid == -1) {
            if (statuscode) |sc| sc.* = SHMIFSRV_EXEC_FAILED;
            shmifsrv_free(res, @intCast(SHMIFSRV_FREE_FULL));
            return null;
        }
        res.pid = rpid;
    }

    return res;
}

// shmifsrv_dequeue_events

export fn shmifsrv_dequeue_events(
    cl: ?*ShmifsrvClient,
    newev: [*c]c.arcan_event,
    limit: usize,
) usize {
    const client = cl orelse return 0;
    if (client.status < @intFromEnum(ConnStatus.READY)) return 0;

    if (shmifsrv_enter(client)) {
        const page = off.Fsrv.getShmPtr(@ptrCast(client.con.?)).?;
        var count: usize = 0;
        var front: u8 = off.Page.parentevqFrontRead(page);
        const back: u8 = off.Page.parentevqBackRead(page);

        if (front > c.PP_QUEUE_SZ or back > c.PP_QUEUE_SZ) {
            client.errors += 1;
            shmifsrv_leave(client);
            return 0;
        }

        while (count < limit and front != back) {
            newev[count] = @as(*const c.arcan_event, @ptrCast(@alignCast(off.Page.parentevqEvent(page, front)))).*;
            count += 1;
            front = @intCast((front + 1) % @as(u8, @intCast(c.PP_QUEUE_SZ)));
        }

        FORCE_SYNCH();
        off.Page.parentevqFrontWrite(page, front);
        _ = shmif_platform_sync_post(off.Fsrv.getShmPtr(@ptrCast(client.con.?)), @intCast(c.SYNC_EVENT));
        shmifsrv_leave(client);
        return count;
    } else {
        client.errors += 1;
        return 0;
    }
}

// shmifsrv_enqueue_event

export fn shmifsrv_enqueue_event(
    cl: ?*ShmifsrvClient,
    ev: ?*c.arcan_event,
    fd: c_int,
) bool {
    const client = cl orelse return false;
    if (client.status < @intFromEnum(ConnStatus.READY)) return false;
    const event = ev orelse return false;

    if (event.category().* == c.EVENT_TARGET and
        event.tgt().kind == c.TARGET_COMMAND_EXIT)
    {
        _ = platform_fsrv_pushevent(client.con.?, event);
        if (shmifsrv_enter(client)) {
            off.Page.setDms(off.Fsrv.getShmPtr(@ptrCast(client.con.?)).?, 0);
        }
        client.status = @intFromEnum(ConnStatus.DEAD);
        return true;
    }

    if (fd != -1) {
        if (shmif_platform_pushfd(fd, off.Fsrv.getDpipe(@ptrCast(client.con.?)))) {
            return platform_fsrv_pushevent(client.con.?, event) == ARCAN_OK;
        }
        return false;
    } else {
        return platform_fsrv_pushevent(client.con.?, event) == ARCAN_OK;
    }
}

// shmifsrv_poll

export fn shmifsrv_poll(cl: ?*ShmifsrvClient) c_int {
    const client = cl orelse return CLIENT_DEAD;
    if (client.status <= @intFromEnum(ConnStatus.BROKEN)) {
        client.status = @intFromEnum(ConnStatus.BROKEN);
        return CLIENT_DEAD;
    }

    switch (@as(ConnStatus, @enumFromInt(client.status))) {
        .PENDING => {
            const sc = platform_fsrv_socketpoll(client.con.?);
            if (sc == -1) {
                if (get_errno() == EBADF) {
                    client.status = @intFromEnum(ConnStatus.BROKEN);
                    return CLIENT_DEAD;
                }
                return CLIENT_NOT_READY;
            }
            client.status = @intFromEnum(ConnStatus.AUTHENTICATING);
            // fallthrough to AUTHENTICATING
            return poll_authenticating(client);
        },
        .AUTHENTICATING => {
            return poll_authenticating(client);
        },
        .READY => {
            return poll_ready(client);
        },
        else => return CLIENT_DEAD,
    }
}

fn poll_authenticating(client: *ShmifsrvClient) c_int {
    while (platform_fsrv_socketauth(client.con.?) == -1) {
        if (get_errno() == EBADF) {
            client.status = @intFromEnum(ConnStatus.BROKEN);
            return CLIENT_DEAD;
        } else if (get_errno() == EWOULDBLOCK) {
            return CLIENT_NOT_READY;
        }
    }
    client.status = @intFromEnum(ConnStatus.READY);
    return poll_ready(client);
}

fn poll_ready(client: *ShmifsrvClient) c_int {
    if (shmifsrv_enter(client)) {
        const page = off.Fsrv.getShmPtr(@ptrCast(client.con.?)) orelse {
            client.status = @intFromEnum(ConnStatus.DEAD);
            shmifsrv_leave(client);
            return CLIENT_DEAD;
        };
        if (off.Page.getDms(page) == 0) {
            client.status = @intFromEnum(ConnStatus.DEAD);
            shmifsrv_leave(client);
            return CLIENT_DEAD;
        }

        const sc = platform_fsrv_socketpoll(client.con.?);
        if (sc == -1) {
            if (get_errno() == EBADF) {
                client.status = @intFromEnum(ConnStatus.BROKEN);
                shmifsrv_leave(client);
                return CLIENT_DEAD;
            }
        }

        if (off.Page.getResized(page) != 0) {
            if (platform_fsrv_resynch(client.con.?) == -1) {
                client.status = @intFromEnum(ConnStatus.BROKEN);
                shmifsrv_leave(client);
                return CLIENT_DEAD;
            }
            return CLIENT_NOT_READY;
        }

        const a: c_int = if (off.Page.getAready(page) != 0) 1 else 0;
        const v: c_int = if (off.Page.getVready(page) != 0) 1 else 0;
        shmifsrv_leave(client);
        if (a != 0 or v != 0) {
            return (CLIENT_VBUFFER_READY * v) | (CLIENT_ABUFFER_READY * a);
        }
        return CLIENT_IDLE;
    } else {
        client.status = @intFromEnum(ConnStatus.BROKEN);
    }
    return CLIENT_NOT_READY;
}

// nanny_thread

fn nanny_thread(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const pidptr: *c.pid_t = @ptrCast(@alignCast(arg));
    var counter: c_int = 10;
    while (counter > 0) {
        counter -= 1;
        var statusfl: c_int = undefined;
        const rv = waitpid(pidptr.*, &statusfl, WNOHANG);
        if (rv > 0) break;
        if (counter == 0) {
            _ = kill(pidptr.*, SIGKILL);
            _ = waitpid(pidptr.*, &statusfl, 0);
            break;
        }
        _ = sleep(1);
    }
    free(@as(?*anyopaque, @ptrCast(pidptr)));
    return null;
}

// shmifsrv_free

export fn shmifsrv_free(cl: ?*ShmifsrvClient, mode: c_int) void {
    const client = cl orelse return;

    if (client.status == @intFromEnum(ConnStatus.PENDING))
        off.Fsrv.setDpipe(@ptrCast(client.con.?), BADFD);

    switch (@as(c_uint, @bitCast(mode))) {
        SHMIFSRV_FREE_NO_DMS => {
            off.Fsrv.setFlagsNoDmsFree(@ptrCast(client.con.?), true);
            platform_fsrv_destroy(client.con.?);
        },
        SHMIFSRV_FREE_FULL => {
            platform_fsrv_destroy(client.con.?);
        },
        SHMIFSRV_FREE_LOCAL => {
            platform_fsrv_destroy_local(client.con.?);
        },
        else => {},
    }

    // nanny-kill thread
    if (client.pid != 0) {
        const pidptr_raw = malloc(@sizeOf(c.pid_t)) orelse {
            _ = kill(client.pid, SIGKILL);
            client.status = @intFromEnum(ConnStatus.DEAD);
            free(@as(?*anyopaque, @ptrCast(client)));
            return;
        };
        const pidptr: *c.pid_t = @ptrCast(@alignCast(pidptr_raw));
        pidptr.* = client.pid;

        var nanny_attr: c.pthread_attr_t = undefined;
        _ = pthread_attr_init(&nanny_attr);
        _ = pthread_attr_setdetachstate(&nanny_attr, PTHREAD_CREATE_DETACHED);

        var nanny: c.pthread_t = undefined;
        if (pthread_create(&nanny, &nanny_attr, &nanny_thread, @as(?*anyopaque, @ptrCast(pidptr))) != 0) {
            _ = kill(client.pid, SIGKILL);
        }
        _ = pthread_attr_destroy(&nanny_attr);
    }

    client.status = @intFromEnum(ConnStatus.DEAD);
    free(@as(?*anyopaque, @ptrCast(client)));
}

// shmifsrv_enter

export fn shmifsrv_enter(cl: ?*ShmifsrvClient) bool {
    const client = cl orelse return false;
    // The C version uses setjmp/longjmp for SIGBUS protection.
    // In Zig we call through to the C platform function.
    var tramp: [256]u8 = undefined; // jmp_buf equivalent
    if (setjmp(@ptrCast(&tramp)) != 0)
        return false;

    platform_fsrv_enter(client.con.?, @ptrCast(&tramp));
    return true;
}

// shmifsrv_leave

export fn shmifsrv_leave(_: ?*ShmifsrvClient) void {
    platform_fsrv_leave();
}

// shmifsrv_client_protomask

export fn shmifsrv_client_protomask(cl: ?*ShmifsrvClient, mask: c_uint) void {
    const client = cl orelse return;
    if (client.con == null) return;
    off.Fsrv.setMetamask(@ptrCast(client.con.?), mask);
}

// shmifsrv_video_step

export fn shmifsrv_video_step(cl: ?*ShmifsrvClient) void {
    const client = cl orelse return;
    off.Page.setVready(off.Fsrv.getShmPtr(@ptrCast(client.con.?)).?, 0);
    _ = shmif_platform_sync_post(off.Fsrv.getShmPtr(@ptrCast(client.con.?)), @intCast(c.SYNC_VIDEO));

    if (@as(c_uint, @bitCast(off.Fsrv.getDescHints(@ptrCast(client.con.?)))) & c.SHMIF_RHINT_VSIGNAL_EV != 0) {
        var ev: c.arcan_event = c.arcan_event.zeroes();
        ev.category().* = @intCast(c.EVENT_TARGET);
        ev.tgt().kind = c.TARGET_COMMAND_STEPFRAME;
        ev.tgt().ioevs[0].iv = 1;
        _ = platform_fsrv_pushevent(client.con.?, &ev);
    }
}

// shmifsrv_video_copy

export fn shmifsrv_video_copy(in: ?*ShmifsrvVbuffer) ShmifsrvVbuffer {
    var res: ShmifsrvVbuffer = std.mem.zeroes(ShmifsrvVbuffer);
    const input = in orelse return res;
    if (input.state != VBUFFER_OKDATA) return res;

    const nb = input.stride * input.h;
    res = input.*;
    res.buffer = @ptrCast(@alignCast(malloc(nb) orelse return res));
    _ = memcpy(@as(?*anyopaque, @ptrCast(res.buffer)), @as(?*const anyopaque, @ptrCast(input.buffer)), nb);

    return res;
}

// shmifsrv_video_copy_free

export fn shmifsrv_video_copy_free(in: ?*ShmifsrvVbuffer) void {
    const input = in orelse return;
    if (input.buffer != null) {
        free(@as(?*anyopaque, @ptrCast(input.buffer)));
    }
    input.* = std.mem.zeroes(ShmifsrvVbuffer);
}

// shmifsrv_video

export fn shmifsrv_video(cl: ?*ShmifsrvClient) ShmifsrvVbuffer {
    var res: ShmifsrvVbuffer = std.mem.zeroes(ShmifsrvVbuffer);
    const client = cl orelse return res;
    if (client.status != @intFromEnum(ConnStatus.READY)) return res;

    off.Fsrv.setDescHints(@ptrCast(client.con.?), off.Fsrv.getDescPendingHints(@ptrCast(client.con.?)));
    const hints_u: c_uint = @bitCast(off.Fsrv.getDescHints(@ptrCast(client.con.?)));
    res.flags.origo_ll = @intFromBool((hints_u & c.SHMIF_RHINT_ORIGO_LL) != 0);
    res.flags.ignore_alpha = @intFromBool((hints_u & c.SHMIF_RHINT_IGNORE_ALPHA) != 0);
    res.flags.subregion = @intFromBool((hints_u & c.SHMIF_RHINT_SUBREGION) != 0);
    res.flags.srgb = @intFromBool((hints_u & c.SHMIF_RHINT_CSPACE_SRGB) != 0);
    res.flags.tpack = @intFromBool((hints_u & c.SHMIF_RHINT_TPACK) != 0);
    const vpage = off.Fsrv.getShmPtr(@ptrCast(client.con.?)).?;
    res.vpts = off.Page.getVpts(vpage);
    res.w = off.Fsrv.getDescWidth(@ptrCast(client.con.?));
    res.h = off.Fsrv.getDescHeight(@ptrCast(client.con.?));
    res.stride = res.w * @as(usize, @intCast(c.ARCAN_SHMPAGE_VCHANNELS));
    res.pitch = res.w;

    var vready = off.Page.getVready(vpage);
    vready = if (vready == 0 or vready > @as(u32, @intCast(off.Fsrv.getVbufCnt(@ptrCast(client.con.?))))) 0 else vready - 1;

    res.buffer = @ptrCast(off.Fsrv.getVbufs(@ptrCast(client.con.?), vready));
    res.region = @bitCast(off.Page.getDirtyRaw(vpage));

    if (off.Fsrv.getDescAproto(@ptrCast(client.con.?)) & c.SHMIF_META_VENC != 0) {
        if (off.Fsrv.getDescAextVenc(@ptrCast(client.con.?))) |venc_raw| {
            const venc: *c.struct_arcan_shmif_venc = @ptrCast(@alignCast(venc_raw));
            _ = memcpy(&res.fourcc, &venc.fourcc, 4);
            res.buffer_sz = venc.framesize;
        }
        res.flags.compressed = @intFromBool(res.fourcc[0] != 0);
    }

    return res;
}

// shmifsrv_process_event

export fn shmifsrv_process_event(
    cl: ?*ShmifsrvClient,
    ev: ?*c.arcan_event,
) bool {
    const client = cl orelse return false;
    const event = ev orelse return false;
    if (client.status != @intFromEnum(ConnStatus.READY)) return false;

    if (event.category().* == c.EVENT_EXTERNAL) {
        switch (event.ext().kind) {
            c.EVENT_EXTERNAL_BUFFERSTREAM => {
                var reject_ev: c.arcan_event = c.arcan_event.zeroes();
                reject_ev.category().* = @intCast(c.EVENT_TARGET);
                reject_ev.tgt().kind = c.TARGET_COMMAND_BUFFER_FAIL;
                _ = shmifsrv_enqueue_event(client, &reject_ev, -1);

                var handle: c_int = undefined;
                _ = shmif_platform_fetchfds(off.Fsrv.getDpipe(@ptrCast(client.con.?)), &handle, 1, false, null, null);
                _ = close(handle);
                return true;
            },
            c.EVENT_EXTERNAL_REGISTER => {
                if (off.Fsrv.getSegid(@ptrCast(client.con.?)) == c.SEGID_UNKNOWN) {
                    off.Fsrv.setSegid(@ptrCast(client.con.?), @intCast(event.ext().registr().kind));
                    return false;
                }
            },
            c.EVENT_EXTERNAL_CLOCKREQ => {
                const tgt: *anyopaque = @ptrCast(client.con.?);
                if (event.ext().clock().dynamic == 1) {
                    if (event.ext().clock().rate != 0) {
                        off.Fsrv.setClockPresent(tgt, event.ext().clock().rate);
                        off.Fsrv.setClockMscFeedback(tgt, true);
                    } else {
                        off.Fsrv.setClockMscFeedback(tgt, !off.Fsrv.getClockMscFeedback(tgt));
                    }
                } else if (event.ext().clock().dynamic == 2) {
                    off.Fsrv.setClockVblank(tgt, !off.Fsrv.getClockVblank(tgt));
                } else if (off.Fsrv.getFlagsAutoclock(tgt)) {
                    off.Fsrv.setClockOnce(tgt, event.ext().clock().once != 0);
                    off.Fsrv.setClockFrame(tgt, event.ext().clock().dynamic != 0);
                    off.Fsrv.setClockLeft(tgt, event.ext().clock().rate);
                    off.Fsrv.setClockStart(tgt, event.ext().clock().rate);
                    off.Fsrv.setClockId(tgt, event.ext().clock().id);
                }
                return true;
            },
            else => {},
        }
    }
    return false;
}

// shmifsrv_audio

export fn shmifsrv_audio(
    cl: ?*ShmifsrvClient,
    on_buffer: ?*const fn ([*c]c.shmif_asample, usize, c_uint, c_uint, ?*anyopaque) callconv(.c) void,
    tag: ?*anyopaque,
) bool {
    const client = cl orelse return false;
    const src = off.Fsrv.getShmPtr(@ptrCast(client.con.?)).?;

    const ind: c_int = @as(c_int, @intCast(off.Page.getAready(src))) - 1;
    const amask: c_int = @intCast(off.Page.getApending(src));

    if (ind >= @as(c_int, @intCast(off.Fsrv.getAbufCnt(@ptrCast(client.con.?)))) or ind < 0)
        return false;

    if (amask == 0 or ((@as(c_int, 1) << @intCast(ind)) & amask) == 0) {
        off.Page.setAready(src, 0);
        _ = shmif_platform_sync_post(src, @intCast(c.SYNC_AUDIO));
        return true;
    }

    // find oldest buffer
    var i: c_int = ind;
    var prev: c_int = ind;
    while (true) {
        prev = i;
        i -= 1;
        if (i < 0) i = @as(c_int, @intCast(off.Fsrv.getAbufCnt(@ptrCast(client.con.?)))) - 1;
        if (i == ind or ((@as(c_int, 1) << @intCast(i)) & amask) == 0) break;
    }

    const prev_u: usize = @intCast(prev);
    if (on_buffer) |cb| {
        const used = off.Page.getAbufused(src, prev_u);
        if (used != 0) {
            cb(
                @ptrCast(@alignCast(off.Fsrv.getAbufs(@ptrCast(client.con.?), prev_u))),
                used,
                off.Fsrv.getDescChannels(@ptrCast(client.con.?)),
                off.Fsrv.getDescSamplerate(@ptrCast(client.con.?)),
                tag,
            );
        }
    }

    // mark as consumed
    off.Page.setAbufused(src, prev_u, 0);
    _ = off.Page.fetchAndApending(src, ~(@as(u32, 1) << @intCast(prev)));

    off.Page.setAready(src, 0);
    _ = shmif_platform_sync_post(src, @intCast(c.SYNC_AUDIO));
    return true;
}

// shmifsrv_tick

export fn shmifsrv_tick(cl: ?*ShmifsrvClient) bool {
    const client = cl orelse return true;
    if (client.con == null) return true;

    const tgt = client.con.?;

    const tgt_any: *anyopaque = @ptrCast(tgt);
    if (off.Fsrv.getClockLeft(tgt_any) != 0) {
        off.Fsrv.setClockLeft(tgt_any, off.Fsrv.getClockLeft(tgt_any) - 1);
        if (off.Fsrv.getClockLeft(tgt_any) != 0) return true;

        if (off.Fsrv.getClockOnce(tgt_any)) return true;

        off.Fsrv.setClockLeft(tgt_any, off.Fsrv.getClockStart(tgt_any));
        var ev: c.arcan_event = c.arcan_event.zeroes();
        ev.category().* = @intCast(c.EVENT_TARGET);
        ev.tgt().kind = c.TARGET_COMMAND_STEPFRAME;
        ev.tgt().ioevs[0].iv = 1;
        ev.tgt().ioevs[1].uiv = off.Fsrv.getClockId(tgt_any);
        _ = platform_fsrv_pushevent(tgt, &ev);
    }
    return true;
}

// shmifsrv_monotonic_tick / rebase

threadlocal var timebase: i64 = 0;
threadlocal var c_ticks: i64 = 0;

export fn shmifsrv_monotonic_tick(left: ?*c_int) c_int {
    const now: i64 = @intCast(arcan_timemillis());
    var n_ticks: c_int = 0;

    if (now < timebase)
        timebase = now - (timebase - now);

    const frametime = now - timebase;
    const base = c_ticks * ARCAN_TIMER_TICK;
    const delta = frametime - base;

    if (delta >= ARCAN_TIMER_TICK) {
        n_ticks = @intCast(@divTrunc(delta, ARCAN_TIMER_TICK));

        if (n_ticks > ARCAN_TICK_THRESHOLD) {
            shmifsrv_monotonic_rebase();
            return shmifsrv_monotonic_tick(left);
        }

        c_ticks += n_ticks;
    }

    if (left) |l| {
        l.* = @intCast(ARCAN_TIMER_TICK - delta);
        if (l.* < 0) l.* = 0;
    }

    return n_ticks;
}

export fn shmifsrv_monotonic_rebase() void {
    timebase = @intCast(arcan_timemillis());
    c_ticks = 0;
}

// shmifsrv_enqueue_multipart_message

export fn shmifsrv_enqueue_multipart_message(
    acon: ?*ShmifsrvClient,
    base: ?*c.arcan_event,
    msg: [*c]const u8,
    len_in: usize,
) bool {
    const client = acon orelse return false;
    const ev = base orelse return false;

    var state: u32 = 0;
    var codepoint: u32 = 0;
    var multipart: *u8 = undefined;
    var data: [*c]u8 = undefined;

    if (ev.category().* == c.EVENT_TARGET) {
        data = @ptrCast(ev.tgt().message());
        multipart = &ev.tgt().ioevs[0].cv[0];
    } else if (ev.category().* == c.EVENT_EXTERNAL) {
        multipart = &ev.ext().message().multipart;
        data = @ptrCast(&ev.ext().message().data);
    } else {
        return false;
    }

    const maxlen: usize = 78;
    var outs: [*c]const u8 = msg;
    var remaining = len_in;

    while (remaining > maxlen) {
        var lastok: usize = 0;
        state = 0;
        for (0..maxlen) |i| {
            if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, @as(u32, outs[i])))
                lastok = i;
            if (i != lastok) {
                if (i == 0) return false;
            }
        }

        const copy_len = lastok + 1;
        _ = memcpy(@as(?*anyopaque, @ptrCast(data)), @as(?*const anyopaque, @ptrCast(outs)), copy_len);
        data[copy_len] = 0;
        remaining -= copy_len;
        outs += copy_len;

        multipart.* = if (remaining != 0) 1 else 0;
        _ = platform_fsrv_pushevent(client.con.?, ev);
    }

    if (remaining != 0) {
        const base_sz: usize = 78;
        _ = snprintf(data, base_sz, "%s", outs);
        multipart.* = 0;
        _ = platform_fsrv_pushevent(client.con.?, ev);
    }

    return true;
}

// shmifsrv_put_video

export fn shmifsrv_put_video(
    C: ?*ShmifsrvClient,
    V: ?*ShmifsrvVbuffer,
) c_int {
    const client = C orelse return -1;
    const vbuf = V orelse return -1;

    if (vbuf.flags.compressed != 0) return -2;

    if (shmifsrv_enter(client)) {
        const ppage = off.Fsrv.getShmPtr(@ptrCast(client.con.?)).?;
        if (off.Page.getVready(ppage) != 0) {
            shmifsrv_leave(client);
            return 0;
        }

        const ntc = vbuf.h * vbuf.stride;
        const fflags: c_int = @intCast(@as(c_uint, vbuf.flags.origo_ll) * @as(c_uint, c.SHMIF_RHINT_ORIGO_LL));
        _ = memcpy(off.Fsrv.getVbufs(@ptrCast(client.con.?), 0), @as(?*const anyopaque, @ptrCast(vbuf.buffer)), ntc);

        off.Page.setHints(ppage, @intCast(fflags));
        off.Page.setVready(ppage, 1);
        off.Page.setDirtyRaw(ppage, @bitCast(vbuf.region));

        var ev: c.arcan_event = c.arcan_event.zeroes();
        ev.tgt().kind = c.TARGET_COMMAND_STEPFRAME;
        ev.category().* = @intCast(c.EVENT_TARGET);
        _ = shmifsrv_enqueue_event(client, &ev, -1);

        shmifsrv_leave(client);
        return 1;
    } else {
        return -1;
    }
}

// shmifsrv_merge_multipart_message

export fn shmifsrv_merge_multipart_message(
    P: ?*ShmifsrvClient,
    ev: ?*c.arcan_event,
    out: ?*[*c]u8,
    bad: ?*bool,
) bool {
    const client = P orelse return false;
    const event = ev orelse return false;
    const out_ptr = out orelse return false;
    const bad_ptr = bad orelse return false;

    if (event.category().* != c.EVENT_EXTERNAL or
        event.ext().kind != c.EVENT_EXTERNAL_MESSAGE)
        return false;

    const msglen = strlen(@ptrCast(&event.ext().message().data));

    if (msglen + client.multipart_ofs >= client.multipart.len) {
        bad_ptr.* = true;
        return false;
    }

    _ = memcpy(
        @as(?*anyopaque, @ptrCast(&client.multipart[client.multipart_ofs])),
        @as(?*const anyopaque, @ptrCast(&event.ext().message().data)),
        msglen,
    );
    client.multipart_ofs += msglen;
    client.multipart[client.multipart_ofs] = 0;
    out_ptr.* = @ptrCast(&client.multipart);

    return event.ext().message().multipart == 0;
}
