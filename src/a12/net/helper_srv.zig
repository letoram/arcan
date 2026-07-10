// Zig port of a12/net/a12_helper_srv.c — A12 server helper / shmif-server bridge.
// Manages the server side of a12 connections: maps incoming a12 channels to
// shmifsrv clients, forwards video/audio frames, and handles client lifecycle.
// Copyright: 2018-2020, Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const posix = std.posix;
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const libc = @import("posix");

const c = struct {
    pub const close = libc.close;
    pub const free = libc.free;
    pub const ftruncate = libc.ftruncate;
    pub const lseek = libc.lseek;
    pub const malloc = libc.malloc;
    pub const mkstemp = libc.mkstemp;
    pub const openat = libc.openat;
    pub const off_t = libc.off_t;
    pub const O_CREAT = libc.O_CREAT;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const O_RDWR = libc.O_RDWR;
    pub const SEEK_END = libc.SEEK_END;
    pub const SEEK_SET = libc.SEEK_SET;
    pub const unlink = libc.unlink;

    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const shmif_asample = shmif.shmif_asample;
    pub const SHMIF_META_VENC = shmif.SHMIF_META_VENC;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const TARGET_COMMAND_ACTIVATE = shmif.TARGET_COMMAND_ACTIVATE;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_DEVICE_NODE = shmif.TARGET_COMMAND_DEVICE_NODE;
    pub const TARGET_COMMAND_EXIT = shmif.TARGET_COMMAND_EXIT;
    pub const TARGET_COMMAND_FONTHINT = shmif.TARGET_COMMAND_FONTHINT;
    pub const TARGET_COMMAND_NEWSEGMENT = shmif.TARGET_COMMAND_NEWSEGMENT;
    pub const TARGET_COMMAND_RESTORE = shmif.TARGET_COMMAND_RESTORE;
    pub const TARGET_COMMAND_STORE = shmif.TARGET_COMMAND_STORE;
    pub const arcan_shmif_descrevent = shmif.arcan_shmif_descrevent;

    pub const A12_BHANDLER_CACHED = a12.A12_BHANDLER_CACHED;
    pub const A12_BHANDLER_CANCELLED = a12.A12_BHANDLER_CANCELLED;
    pub const A12_BHANDLER_DONTWANT = a12.A12_BHANDLER_DONTWANT;
    pub const A12_BHANDLER_NEWFD = a12.A12_BHANDLER_NEWFD;
    pub const A12_BTYPE_BLOB = a12.A12_BTYPE_BLOB;
    pub const A12_BTYPE_FONT = a12.A12_BTYPE_FONT;
    pub const A12_BTYPE_FONT_SUPPL = a12.A12_BTYPE_FONT_SUPPL;
    pub const A12_BTYPE_STATE = a12.A12_BTYPE_STATE;
    pub const a12_channel_close = a12.a12_channel_close;
    pub const a12_channel_enqueue = a12.a12_channel_enqueue;
    pub const a12_channel_vframe = a12.a12_channel_vframe;
    pub const a12_flush = a12.a12_flush;
    pub const a12_free = a12.a12_free;
    pub const a12_get_channel = a12.a12_get_channel;
    pub const a12_ok = a12.a12_ok;
    pub const a12_set_bhandler = a12.a12_set_bhandler;
    pub const a12_set_channel = a12.a12_set_channel;
    pub const a12_set_destination = a12.a12_set_destination;
    pub const a12_state_iostat = a12.a12_state_iostat;
    pub const a12_unpack = a12.a12_unpack;
    pub const CLIENT_ABUFFER_READY = a12.CLIENT_ABUFFER_READY;
    pub const CLIENT_DEAD = a12.CLIENT_DEAD;
    pub const CLIENT_IDLE = a12.CLIENT_IDLE;
    pub const CLIENT_NOT_READY = a12.CLIENT_NOT_READY;
    pub const CLIENT_VBUFFER_READY = a12.CLIENT_VBUFFER_READY;
    pub const SHMIFSRV_FREE_NO_DMS = a12.SHMIFSRV_FREE_NO_DMS;
    pub const shmifsrv_audio = a12.shmifsrv_audio;
    pub const shmifsrv_client_handle = a12.shmifsrv_client_handle;
    pub const shmifsrv_client_protomask = a12.shmifsrv_client_protomask;
    pub const shmifsrv_client_type = a12.shmifsrv_client_type;
    pub const shmifsrv_dequeue_events = a12.shmifsrv_dequeue_events;
    pub const shmifsrv_enqueue_event = a12.shmifsrv_enqueue_event;
    pub const shmifsrv_free = a12.shmifsrv_free;
    pub const shmifsrv_monotonic_tick = a12.shmifsrv_monotonic_tick;
    pub const shmifsrv_poll = a12.shmifsrv_poll;
    pub const shmifsrv_process_event = a12.shmifsrv_process_event;
    pub const shmifsrv_send_subsegment = a12.shmifsrv_send_subsegment;
    pub const shmifsrv_tick = a12.shmifsrv_tick;
    pub const shmifsrv_video = a12.shmifsrv_video;
    pub const shmifsrv_video_step = a12.shmifsrv_video_step;
    pub const struct_a12_bhandler_meta = a12.struct_a12_bhandler_meta;
    pub const struct_a12_bhandler_res = a12.struct_a12_bhandler_res;
    pub const struct_a12helper_opts = a12.struct_a12helper_opts;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_a12_vframe_opts = a12.struct_a12_vframe_opts;
    pub const struct_shmifsrv_client = a12.struct_shmifsrv_client;
    pub const struct_shmifsrv_vbuffer = a12.struct_shmifsrv_vbuffer;
    pub const VFRAME_BIAS_BALANCED = a12.VFRAME_BIAS_BALANCED;
    pub const VFRAME_METHOD_DZSTD = a12.VFRAME_METHOD_DZSTD;
    pub const VFRAME_METHOD_TPACK_ZSTD = a12.VFRAME_METHOD_TPACK_ZSTD;
};

// Extern C helpers used by this module

extern "c" fn arcan_timemillis() c_ulonglong;

// Avoid pulling struct_stat from the cImport (translate-c demotes struct
// timespec to opaque in musl). Use lseek(SEEK_END) instead of fstat.
fn fd_size(fd: c_int) i64 {
    const end = c.lseek(fd, 0, c.SEEK_END);
    if (end < 0) return -1;
    _ = c.lseek(fd, 0, c.SEEK_SET);
    return end;
}
extern "c" fn a12helper_tob64(data: [*]const u8, inl: usize, outl: *usize) ?[*]u8;
extern "c" fn a12helper_vbuffer_append_raw(
    cache: ?*anyopaque,
    vb: *c.struct_shmifsrv_vbuffer,
    channel: u8,
) void;

// Thread-shared state

// Giant lock: a12 is not thread-safe across the buffer/channel-state functions.
// A single mutex serialises all entry points that touch S.
// std.Thread.Mutex panics-on-lock when the build forces single_threaded
// (which the SH aarch64 backend does — same caveat as helper_srv:651
// "std.Thread.spawn has a comptime gate against single_threaded"). Wrap a
// libc pthread mutex so the actual pthreads we spawn can acquire it.
const PthreadMutexShim = struct {
    inner: libc.pthread_mutex_t = .{},
    pub fn lock(self: *PthreadMutexShim) void {
        _ = libc.pthread_mutex_lock(&self.inner);
    }
    pub fn unlock(self: *PthreadMutexShim) void {
        _ = libc.pthread_mutex_unlock(&self.inner);
    }
};
var default_mutex = PthreadMutexShim{};
var giant_lock: *PthreadMutexShim = &default_mutex;

// Atomic count of live client segments (primary + subsegments).
var n_segments = std.atomic.Value(u8).init(0);

// Written by client threads when they have data ready; read by the main I/O loop.
var buffer_out = std.atomic.Value(usize).init(0);

// Internal data structures

/// Per-segment state shared between the main loop and a client processing thread.
const ShmifsrvThreadData = struct {
    C: *c.struct_shmifsrv_client,
    S: *c.struct_a12_state,
    /// Fake shmif context used solely as a typed wrapper / tag carrier.
    fake: c.struct_arcan_shmif_cont,
    opts: c.struct_a12helper_opts,
    font_sz: f32,
    /// Write end of the wakeup pipe shared across all segments for this connection.
    kill_fd: posix.fd_t,
    chid: u8,
};

// Video options heuristic

/// Decide encoding parameters based on the segment type and buffer flags.
/// First-pass heuristic; backpressure/bandwidth tuning feeds in later.
fn voptsFromSegment(
    data: *ShmifsrvThreadData,
    vb: *c.struct_shmifsrv_vbuffer,
) c.struct_a12_vframe_opts {
    const S = data.S;

    if (data.opts.cache != null) {
        a12helper_vbuffer_append_raw(@ptrCast(data.opts.cache), vb, c.a12_get_channel(S));
    }

    // tpack streams use their own dedicated codec
    if (vb.flags.tpack) {
        return .{ .method = c.VFRAME_METHOD_TPACK_ZSTD };
    }

    // caller-supplied codec selection
    if (data.opts.eval_vcodec) |eval_fn| {
        return eval_fn(data.S, @intCast(c.shmifsrv_client_type(data.C)), vb, data.opts.tag);
    }

    return .{
        .method = c.VFRAME_METHOD_DZSTD,
        .bias = c.VFRAME_BIAS_BALANCED,
    };
}

// Binary transfer dispatch

/// Forward a completed binary transfer descriptor to the local shmif client.
/// Called from within the critical section (a12 unpack path).
fn dispatchBdata(
    _: ?*c.struct_a12_state,
    fd: c_int,
    btype: c_int,
    D: *ShmifsrvThreadData,
) void {
    const srv_cl = D.C;

    switch (btype) {
        c.A12_BTYPE_STATE => {
            var ev = c.struct_arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_RESTORE;
            _ = c.shmifsrv_enqueue_event(srv_cl, @ptrCast(&ev), fd);
        },
        c.A12_BTYPE_FONT => {
            var ev = c.struct_arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_FONTHINT;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 1;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].fv = D.font_sz;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = -1;
            _ = c.shmifsrv_enqueue_event(srv_cl, @ptrCast(&ev), fd);
        },
        c.A12_BTYPE_FONT_SUPPL => {
            var ev = c.struct_arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_FONTHINT;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 1;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].fv = D.font_sz;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = -1;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = 1;
            _ = c.shmifsrv_enqueue_event(srv_cl, @ptrCast(&ev), fd);
        },
        c.A12_BTYPE_BLOB => {
            var ev = c.struct_arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
            _ = c.shmifsrv_enqueue_event(srv_cl, @ptrCast(&ev), fd);
        },
        else => {},
    }

    _ = c.close(fd);
}

// Incoming binary transfer handler (called from a12_unpack inside critical)

/// Registered with a12_set_bhandler. Returns an fd for the a12 library to
/// write the incoming stream into, or signals that we already have it cached.
fn incomingBhandler(
    S: ?*c.struct_a12_state,
    md: c.struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) callconv(.c) c.struct_a12_bhandler_res {
    const opts: *c.struct_a12helper_opts = @ptrCast(@alignCast(tag orelse return .{
        .fd = -1,
        .flag = c.A12_BHANDLER_DONTWANT,
    }));

    var res = c.struct_a12_bhandler_res{
        .fd = -1,
        .flag = c.A12_BHANDLER_DONTWANT,
    };

    // Completed or cancelled transfer: forward or close the fd
    if (md.fd != -1) {
        if (md.dcont != null and md.dcont.*.user != null and
            md.streaming == false and md.state != c.A12_BHANDLER_CANCELLED)
        {
            const D: *ShmifsrvThreadData = @ptrCast(@alignCast(md.dcont.*.user));
            dispatchBdata(S, md.fd, @intCast(md.type), D);
        } else {
            _ = c.close(md.fd);
        }
        return res;
    }

    // Check for a non-zero checksum
    var got_checksum = false;
    for (md.checksum) |b| {
        if (b != 0) {
            got_checksum = true;
            break;
        }
    }

    // Font cache lookup / creation
    if (got_checksum and opts.bcache_dir != -1 and
        (md.type == c.A12_BTYPE_FONT or md.type == c.A12_BTYPE_FONT_SUPPL))
    {
        var len: usize = 0;
        const fname_ptr = a12helper_tob64(&md.checksum, 16, &len);
        if (fname_ptr) |fname| {
            // Try to open existing cache entry
            const cached_fd = c.openat(opts.bcache_dir, fname, c.O_RDONLY);
            if (cached_fd != -1) {
                const size = fd_size(cached_fd);
                if (size <= 0) {
                    // Truncated / broken entry — re-download
                    res.fd = cached_fd;
                    res.flag = c.A12_BHANDLER_NEWFD;
                    if (md.dcont != null and md.dcont.*.user != null) {
                        const D: *ShmifsrvThreadData = @ptrCast(@alignCast(md.dcont.*.user));
                        dispatchBdata(S, cached_fd, @intCast(md.type), D);
                    }
                } else {
                    res.fd = cached_fd;
                    res.flag = c.A12_BHANDLER_CACHED;
                    if (md.dcont != null and md.dcont.*.user != null) {
                        const D: *ShmifsrvThreadData = @ptrCast(@alignCast(md.dcont.*.user));
                        dispatchBdata(S, cached_fd, @intCast(md.type), D);
                    }
                }
                c.free(@ptrCast(fname));
                return res;
            }

            // Create a new cache entry
            const new_fd = c.openat(
                opts.bcache_dir,
                fname,
                c.O_CREAT | c.O_RDWR,
                @as(c_uint, 0o600),
            );
            if (new_fd != -1) {
                res.fd = new_fd;
                res.flag = c.A12_BHANDLER_NEWFD;
                c.free(@ptrCast(fname));
                return res;
            }
            c.free(@ptrCast(fname));
        }
    }

    // Streaming transfer: use a pipe so we can forward immediately
    if (md.streaming) {
        const pair = posix.pipe() catch return res;
        res.flag = c.A12_BHANDLER_NEWFD;
        res.fd = pair[1];
        if (md.dcont != null and md.dcont.*.user != null) {
            const D: *ShmifsrvThreadData = @ptrCast(@alignCast(md.dcont.*.user));
            dispatchBdata(S, pair[1], @intCast(md.type), D);
        }
        return res;
    }

    // Non-streaming, non-cached: create an anonymous temp file via mkstemp
    var pattern = "/tmp/anetb_XXXXXX".*;
    const tmp_fd = c.mkstemp(&pattern);
    if (tmp_fd == -1) return res;
    _ = c.unlink(&pattern);

    if (c.ftruncate(tmp_fd, @as(c.off_t, @intCast(md.known_size))) == -1) {
        _ = c.close(tmp_fd);
        return res;
    }

    res.fd = tmp_fd;
    res.flag = c.A12_BHANDLER_NEWFD;
    return res;
}

// Descriptor store setup (stub — not yet implemented upstream either)

fn setupDescriptorStore(
    _: *ShmifsrvThreadData,
    _: *c.struct_shmifsrv_client,
    _: *c.struct_arcan_event,
) void {
    // Upstream marks this TODO (a12int_trace MISSING); preserve parity.
}

// EXIT redirection helper

/// When a redirect_exit path is configured, translate EXIT events into
/// DEVICE_NODE migration events so the window is not destroyed.
fn redirectExit(C: *c.struct_shmifsrv_client, level: c_int, path: ?[*:0]const u8) void {
    const p = path orelse return;
    var ev = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = -1;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = level;
    // tgt.unnamed_0.message is [78]char — copy with null-termination, up to 77 chars
    const msg_buf: *[78]u8 = @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message);
    _ = std.fmt.bufPrintZ(msg_buf, "{s}", .{p}) catch {};
    _ = c.shmifsrv_enqueue_event(C, @ptrCast(&ev), -1);
}

// Server-side event handler (invoked from a12_unpack, inside critical)

/// Translates incoming a12 events into shmifsrv_enqueue_event calls,
/// intercepts FONTHINT, ACTIVATE, EXIT, and NEWSEGMENT specially.
fn onSrvEvent(
    cont_raw: [*c]c.struct_arcan_shmif_cont,
    chid: c_int,
    ev_raw: [*c]c.struct_arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void {
    // tag is the primary ShmifsrvThreadData (arg) from the outermost a12_unpack call.
    _ = tag;

    if (cont_raw == null or ev_raw == null) return;
    const cont: *c.struct_arcan_shmif_cont = @ptrCast(cont_raw);
    const ev: *c.struct_arcan_event = @ptrCast(ev_raw);

    const data: *ShmifsrvThreadData = @ptrCast(@alignCast(cont.user orelse return));
    const S = data.S;
    const srv_cl = data.C;

    std.log.warn("[bug133] st-push onSrvEvent chid={d} cat={d} kind={d}", .{ chid, ev.unnamed_0.unnamed_0.category, ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind });

    // Cache font size; strip the descriptor slot which arrives via btransfer
    if (ev.unnamed_0.unnamed_0.category == c.EVENT_TARGET and ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_FONTHINT) {
        data.font_sz = ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].fv;
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 0;
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = -1;
        // Suppress continuation-font events entirely
        if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv != 0) return;
    }

    // On ACTIVATE for the primary channel, advertise the alternate connection point
    if (data.opts.devicehint_cp != null and chid == 0 and
        ev.unnamed_0.unnamed_0.category == c.EVENT_TARGET and ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_ACTIVATE)
    {
        var dev_ev = c.struct_arcan_event.zeroes();
        dev_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        dev_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
        dev_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = -1;
        dev_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 4; // fallback level
        const dev_msg_buf: *[78]u8 = @ptrCast(&dev_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message);
        _ = std.fmt.bufPrintZ(dev_msg_buf, "{s}", .{data.opts.devicehint_cp.?}) catch {};
        _ = c.shmifsrv_enqueue_event(srv_cl, @ptrCast(&dev_ev), -1);
    }

    // Intercept EXIT on primary channel: redirect rather than destroy
    if (data.opts.redirect_exit != null and chid == 0 and
        ev.unnamed_0.unnamed_0.category == c.EVENT_TARGET and ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_EXIT)
    {
        redirectExit(srv_cl, 2, data.opts.redirect_exit);
        return;
    }

    // Handle all non-NEWSEGMENT events
    if (ev.unnamed_0.unnamed_0.category != c.EVENT_TARGET or ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind != c.TARGET_COMMAND_NEWSEGMENT) {
        // Descriptor events need special handling for outgoing bchunks
        if (c.arcan_shmif_descrevent(ev)) {
            if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_STORE or
                ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_BCHUNK_OUT)
            {
                setupDescriptorStore(data, srv_cl, ev);
            } else {
                _ = c.shmifsrv_enqueue_event(srv_cl, @ptrCast(ev), ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
            }
        } else {
            _ = c.shmifsrv_enqueue_event(srv_cl, @ptrCast(ev), -1);
        }
        return;
    }

    // NEWSEGMENT: allocate a new per-segment thread data block
    const new_data = @as(*ShmifsrvThreadData, @ptrCast(@alignCast(
        c.malloc(@sizeOf(ShmifsrvThreadData)) orelse {
            c.a12_set_channel(S, @intCast(chid));
            c.a12_channel_close(S);
            return;
        },
    )));
    new_data.* = data.*;
    new_data.chid = @intCast(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
    new_data.C = c.shmifsrv_send_subsegment(
        srv_cl,
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv,
        0,
        32,
        32,
        chid,
        @intCast(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv),
    ) orelse {
        c.free(new_data);
        c.a12_set_channel(S, @intCast(chid));
        c.a12_channel_close(S);
        return;
    };

    // Wire the fake shmif context so event callbacks find the new data block
    new_data.fake.user = new_data;
    c.a12_set_destination(S, @ptrCast(&new_data.fake), new_data.chid);

    if (!spawnThread(new_data)) {
        c.free(new_data);
        c.a12_set_channel(S, @intCast(chid));
        c.a12_channel_close(S);
    }
}

// Audio callback (currently disabled — matches upstream)

fn onAudioCb(
    _: ?*c.struct_shmifsrv_client,
    _: ?[*]c.shmif_asample,
    _: usize,
    _: c_uint,
    _: ?*anyopaque,
) callconv(.c) void {
    // Upstream has a bare `return` before the a12_channel_aframe call.
    // Audio forwarding is stubbed pending proper implementation.
}

// Client processing thread

/// Runs once per shmifsrv segment. Polls the shmif client handle plus a
/// wakeup pipe, dequeues events and video/audio buffers, and forwards them
/// over a12 (serialised by the giant lock).
fn clientThread(inarg: ?*anyopaque) void {
    const data: *ShmifsrvThreadData = @ptrCast(@alignCast(inarg orelse return));
    const S = data.S;

    const errmask: i16 = posix.POLL.ERR | posix.POLL.NVAL | posix.POLL.HUP;

    var fds = [2]posix.pollfd{
        .{
            .fd = c.shmifsrv_client_handle(data.C, null),
            .events = posix.POLL.IN | errmask,
            .revents = 0,
        },
        .{
            .fd = data.kill_fd,
            .events = errmask,
            .revents = 0,
        },
    };

    // Enable encoded video passthrough
    _ = c.shmifsrv_client_protomask(data.C, c.SHMIF_META_VENC);

    // Milliseconds between polls — no monitorable trigger for video/audio readiness
    const poll_step: i32 = 4;
    var dirty = false;
    var last_frame_ts: c_ulonglong = 0;

    redirectExit(data.C, 4, data.opts.redirect_exit);

    outer: while (true) {
        // Wake up the I/O thread whenever we produced data
        if (dirty) {
            _ = posix.write(data.kill_fd, &[1]u8{data.chid}) catch {};
            dirty = false;
        }

        _ = posix.poll(&fds, poll_step) catch |err| {
            if (err != error.Interrupted) break;
        };

        // Advance shmif monotonic timer
        var left: c_int = 0;
        var ticks = c.shmifsrv_monotonic_tick(&left);
        while (ticks > 0) : (ticks -= 1) {
            _ = c.shmifsrv_tick(data.C);
        }

        // Error on either fd signals termination
        if ((fds[0].revents & errmask) != 0 or (fds[1].revents & errmask) != 0) break;

        // Data on the shmif socket is unexpected (no BUFFERSTREAM permitted).
        // Drain and continue — warn only in trace builds.
        if ((fds[0].revents & posix.POLL.IN) != 0) {
            var drain_buf: [256]u8 = undefined;
            _ = posix.read(fds[0].fd, &drain_buf) catch {};
        }

        // Dequeue events from the shmif client and forward via a12
        var ev: c.struct_arcan_event = undefined;
        while (c.shmifsrv_dequeue_events(data.C, @ptrCast(&ev), 1) != 0) {
            if (c.arcan_shmif_descrevent(@ptrCast(&ev))) continue;

            giant_lock.lock();
            if (c.shmifsrv_process_event(data.C, @ptrCast(&ev))) {
                // event consumed internally by shmifsrv
                giant_lock.unlock();
            } else {
                c.a12_set_channel(S, @intCast(data.chid));
                _ = c.a12_channel_enqueue(S, @ptrCast(&ev));
                dirty = true;
                giant_lock.unlock();
            }
        }

        // Poll shmif buffer state and handle any ready buffers
        var pv = c.shmifsrv_poll(data.C);
        while (pv != c.CLIENT_NOT_READY and pv != c.CLIENT_IDLE) {
            if (pv == c.CLIENT_DEAD) break :outer;

            if ((pv & c.CLIENT_VBUFFER_READY) != 0) {
                // Backpressure: skip if the output socket is saturated
                if (buffer_out.load(.acquire) > 0) break;

                const stat = c.a12_state_iostat(S);
                var vb = c.shmifsrv_video(data.C);

                if (data.opts.vframe_block != 0 and
                    stat.vframe_backpressure >= data.opts.vframe_soft_block)
                {
                    const px_c: usize = @intCast(vb.w * vb.h);
                    const reg_c: usize = @intCast(
                        (vb.region.x2 - vb.region.x1) *
                            (vb.region.y2 - vb.region.y1),
                    );
                    const allow_soft = vb.flags.subregion and
                        reg_c < px_c and
                        (@as(f32, @floatFromInt(reg_c)) / @as(f32, @floatFromInt(px_c))) <= 0.2;

                    if (stat.vframe_backpressure >= data.opts.vframe_block and !allow_soft) break;
                }

                // Encode and forward the video frame.
                // Retry until the codec emits at least one encoded frame (first-frame
                // bootstrap: the codec may need several inputs before producing output).
                var out: c_int = 0;
                while (true) {
                    giant_lock.lock();
                    c.a12_set_channel(S, @intCast(data.chid));
                    out = c.a12_channel_vframe(S, &vb, voptsFromSegment(data, &vb));
                    dirty = true;
                    giant_lock.unlock();

                    if (out == 0 and last_frame_ts == 0) continue;
                    break;
                }

                last_frame_ts = arcan_timemillis();
                _ = c.shmifsrv_video_step(data.C);
            }

            // Audio: forward regardless of backpressure (less tuning options)
            if ((pv & c.CLIENT_ABUFFER_READY) != 0) {
                giant_lock.lock();
                c.a12_set_channel(S, @intCast(data.chid));
                _ = c.shmifsrv_audio(data.C, onAudioCb, S);
                dirty = true;
                giant_lock.unlock();
            }

            pv = c.shmifsrv_poll(data.C);
        }
    }

    // Segment death: close the a12 channel and wake the I/O loop
    giant_lock.lock();
    c.a12_set_channel(S, @intCast(data.chid));
    c.a12_channel_close(S);
    _ = posix.write(data.kill_fd, &[1]u8{data.chid}) catch {};
    giant_lock.unlock();

    // Only the primary segment closes the wakeup-pipe write-end
    if (data.chid == 0 and data.kill_fd != -1) {
        posix.close(data.kill_fd);
    }

    // Non-primary segments release their shmif client
    if (data.chid != 0) {
        c.shmifsrv_free(data.C, c.SHMIFSRV_FREE_NO_DMS);
    }

    _ = n_segments.fetchSub(1, .release);
    c.free(inarg);
}

// Thread spawn helper

fn spawnThread(inarg: *ShmifsrvThreadData) bool {
    _ = n_segments.fetchAdd(1, .release);

    // Route through libc pthread_create directly — std.Thread.spawn has a
    // comptime gate against single_threaded, which the SH aarch64 backend
    // forces on. pthread is linked regardless; we detach for fire-and-forget
    // semantics identical to std.Thread.detach.
    //
    // bug 0130-followup: a12int_append_out's debug-mode stack frame is
    // 7.8 MB (the by-value spill of struct_a12_state — see fossil
    // 308e620ec7). The main thread gets `ulimit -s unlimited` from the
    // launcher, but pthreads default to 8 MB which the probe loop walks
    // straight through. Pin the per-segment thread to a generous 32 MB
    // until the codegen issue is fixed.
    var pthattr: libc.pthread_attr_t = undefined;
    _ = libc.pthread_attr_init(&pthattr);
    defer _ = libc.pthread_attr_destroy(&pthattr);
    _ = libc.pthread_attr_setstacksize(&pthattr, 32 * 1024 * 1024);

    var thread: libc.pthread_t = 0;
    const rc = libc.pthread_create(&thread, &pthattr, pthreadClientEntry, @ptrCast(inarg));
    if (rc != 0) {
        giant_lock.lock();
        _ = n_segments.fetchSub(1, .release);
        c.free(inarg);
        giant_lock.unlock();
        return false;
    }
    _ = libc.pthread_detach(thread);
    return true;
}

fn pthreadClientEntry(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    clientThread(arg);
    return null;
}

// Main exported entry point

/// Take a prenegotiated a12 connection [S] and an accepted shmif client [C],
/// using [fd_in / fd_out] as the bitstream carrier. Blocks until the
/// connection terminates.
pub export fn a12helper_a12cl_shmifsrv(
    S: *c.struct_a12_state,
    C: *c.struct_shmifsrv_client,
    fd_in: c_int,
    fd_out: c_int,
    opts: c.struct_a12helper_opts,
) callconv(.c) void {
    // a12_flush returns a pointer into its internal buffer via an out-param.
    // We track it as a raw C pointer to match the uint8_t** API exactly.
    var outbuf: [*c]u8 = null;
    var outbuf_sz: usize = 0;

    // Caller may supply an external pthread_mutex_t* via opts.lock.
    // We use our own std.Thread.Mutex for idiomatic Zig serialisation;
    // the caller should set opts.lock = null when calling from Zig.
    _ = opts.lock;

    // Set up the fake shmif context as channel-0 destination.
    // a12.a12_set_destination is typed against a12_types.arcan_shmif_cont;
    // layout identical to shmif's.
    var fake = std.mem.zeroes(c.struct_arcan_shmif_cont);
    c.a12_set_destination(S, @ptrCast(&fake), 0);
    c.a12_set_bhandler(S, incomingBhandler, @constCast(&opts));

    // Wakeup pipe: written by client threads, read by main I/O loop
    var pipe_pair: [2]posix.fd_t = .{ -1, -1 };
    if (posix.pipe() catch null) |pp| {
        pipe_pair = .{ pp[0], pp[1] };
    } else return;

    const arg = @as(*ShmifsrvThreadData, @ptrCast(@alignCast(
        c.malloc(@sizeOf(ShmifsrvThreadData)) orelse {
            posix.close(pipe_pair[0]);
            posix.close(pipe_pair[1]);
            return;
        },
    )));
    arg.* = .{
        .C = C,
        .S = S,
        .fake = fake,
        .opts = opts,
        .font_sz = 0.0,
        .kill_fd = pipe_pair[1],
        .chid = 0,
    };

    if (!spawnThread(arg)) {
        posix.close(pipe_pair[0]);
        posix.close(pipe_pair[1]);
        return;
    }
    // After spawn the thread owns arg, but we tie the fake context's user pointer
    // now so that the initial a12_unpack flush can resolve it.
    fake.user = arg;

    // Main I/O poll: [0]=network-in, [1]=wakeup-pipe, [2]=network-out (added on demand)
    const errmask: i16 = posix.POLL.ERR | posix.POLL.NVAL | posix.POLL.HUP;
    var fds = [3]posix.pollfd{
        .{ .fd = fd_in, .events = posix.POLL.IN | errmask, .revents = 0 },
        .{ .fd = pipe_pair[0], .events = posix.POLL.IN | errmask, .revents = 0 },
        .{ .fd = fd_out, .events = posix.POLL.OUT | errmask, .revents = 0 },
    };
    var n_fd: usize = 2;

    // Flush any buffered data left over from authentication
    giant_lock.lock();
    c.a12_unpack(S, null, 0, arg, @ptrCast(&onSrvEvent));
    giant_lock.unlock();

    var inbuf: [9000]u8 = undefined;

    while (c.a12_ok(S)) {
        _ = posix.poll(fds[0..n_fd], -1) catch |err| {
            if (err != error.Interrupted) {
                std.log.warn("[bug133] helper_srv pump exit — poll err {any}", .{err});
                break;
            }
            continue;
        };

        // Any error on any monitored fd terminates the connection
        if ((fds[0].revents & errmask) != 0 or
            (fds[1].revents & errmask) != 0 or
            (n_fd == 3 and (fds[2].revents & errmask) != 0))
        {
            std.log.warn("[bug133] helper_srv pump exit — pollfd ERR fds[0]={x} fds[1]={x} fds[2]={x} (n_fd={d})", .{ fds[0].revents, fds[1].revents, fds[2].revents, n_fd });
            break;
        }

        // Drain wakeup bytes written by client threads
        if (fds[1].revents != 0) {
            _ = posix.read(pipe_pair[0], &inbuf) catch {};
        }

        // Flush pending output buffer to the network
        if (n_fd == 3 and (fds[2].revents & posix.POLL.OUT) != 0 and outbuf_sz > 0) {
            const nw = posix.write(fd_out, outbuf[0..outbuf_sz]) catch break;
            if (nw > 0) {
                outbuf += nw;
                outbuf_sz -= nw;
            }
        }

        // Read and unpack incoming network data
        if ((fds[0].revents & posix.POLL.IN) != 0) {
            const nr = posix.recv(fd_in, &inbuf, 0) catch |err| {
                if (err != error.WouldBlock and err != error.Interrupted) {
                    std.log.warn("[bug133] helper_srv pump exit — recv err {any}", .{err});
                    break;
                }
                continue;
            };
            if (nr == 0) {
                std.log.warn("[bug133] helper_srv pump exit — recv returned 0 (peer half-close)", .{});
                break;
            } // remote closed connection

            giant_lock.lock();
            c.a12_unpack(S, &inbuf, nr, arg, @ptrCast(&onSrvEvent));
            giant_lock.unlock();
        }

        // Grab the next output chunk from the a12 state machine
        if (outbuf_sz == 0) {
            giant_lock.lock();
            outbuf_sz = c.a12_flush(S, &outbuf, 0);
            giant_lock.unlock();
        }
        n_fd = if (outbuf_sz > 0) 3 else 2;
    }

    std.log.warn("[bug133] helper_srv pump LOOP EXITED — a12_ok={any}", .{c.a12_ok(S)});

    // Cleanup
    if (opts.bcache_dir > 0) posix.close(opts.bcache_dir);
    posix.close(pipe_pair[0]);

    // Wait for all segment threads to exit before freeing the a12 state
    while (n_segments.load(.acquire) > 0) {
        std.atomic.spinLoopHint();
    }

    _ = c.a12_free(S);

    // Attempt to migrate the primary segment to a local connection point
    redirectExit(C, 2, opts.redirect_exit);
}
