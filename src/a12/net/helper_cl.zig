// Zig port of a12/net/a12_helper_cl.c — A12 client-side shmif bridge.
// Takes an authenticated a12 connection and bridges it to a local arcan
// shmif client. Handles event forwarding, binary transfers, and segment
// management via a per-segment detached thread model.
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const libc = @import("posix");

const c = struct {
    pub const close = libc.close;
    pub const free = libc.free;
    pub const getenv = libc.getenv;
    pub const malloc = libc.malloc;
    pub const pipe = libc.pipe;
    pub const poll = libc.poll;
    pub const POLLERR = libc.POLLERR;
    pub const POLLHUP = libc.POLLHUP;
    pub const POLLIN = libc.POLLIN;
    pub const POLLNVAL = libc.POLLNVAL;
    pub const POLLOUT = libc.POLLOUT;
    pub const pthread_attr_init = libc.pthread_attr_init;
    pub const pthread_attr_setdetachstate = libc.pthread_attr_setdetachstate;
    pub const pthread_attr_setstacksize = libc.pthread_attr_setstacksize;
    pub const pthread_attr_t = libc.pthread_attr_t;
    pub const pthread_create = libc.pthread_create;
    pub const PTHREAD_CREATE_DETACHED = libc.PTHREAD_CREATE_DETACHED;
    pub const pthread_mutex_init = libc.pthread_mutex_init;
    pub const pthread_mutex_lock = libc.pthread_mutex_lock;
    pub const pthread_mutex_t = libc.pthread_mutex_t;
    pub const pthread_mutex_unlock = libc.pthread_mutex_unlock;
    pub const pthread_t = libc.pthread_t;
    pub const read = libc.read;
    pub const recv = libc.recv;
    pub const setenv = libc.setenv;
    pub const struct_pollfd = libc.struct_pollfd;
    pub const write = libc.write;

    pub const arcan_shmif_acquire = shmif.arcan_shmif_acquire;
    pub const arcan_shmif_open = shmif.arcan_shmif_open;
    pub const arcan_shmif_descrevent = shmif.arcan_shmif_descrevent;
    pub const arcan_shmif_drop = shmif.arcan_shmif_drop;
    pub const arcan_shmif_enqueue = shmif.arcan_shmif_enqueue;
    pub const arcan_shmif_poll = shmif.arcan_shmif_poll;
    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_PRIVDROP = shmif.EVENT_EXTERNAL_PRIVDROP;
    pub const EVENT_EXTERNAL_REGISTER = shmif.EVENT_EXTERNAL_REGISTER;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const SEGID_UNKNOWN = shmif.SEGID_UNKNOWN;
    pub const SEGID_TERMINAL = shmif.SEGID_TERMINAL;
    pub const SHMIF_NOACTIVATE = shmif.SHMIF_NOACTIVATE;
    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const TARGET_COMMAND_DEVICE_NODE = shmif.TARGET_COMMAND_DEVICE_NODE;
    pub const TARGET_COMMAND_EXIT = shmif.TARGET_COMMAND_EXIT;
    pub const TARGET_COMMAND_NEWSEGMENT = shmif.TARGET_COMMAND_NEWSEGMENT;

    pub const a12_auth_state = a12.a12_auth_state;
    pub const a12_channel_close = a12.a12_channel_close;
    pub const a12_channel_enqueue = a12.a12_channel_enqueue;
    pub const a12_channel_new = a12.a12_channel_new;
    pub const a12_channel_shutdown = a12.a12_channel_shutdown;
    pub const a12_flush = a12.a12_flush;
    pub const A12_FLUSH_ALL = a12.A12_FLUSH_ALL;
    pub const a12_free = a12.a12_free;
    pub const a12_ok = a12.a12_ok;
    pub const a12_set_channel = a12.a12_set_channel;
    pub const a12_set_destination = a12.a12_set_destination;
    pub const a12_unpack = a12.a12_unpack;
    pub const AUTH_FULL_PK = a12.AUTH_FULL_PK;
    pub const struct_a12_state = a12.struct_a12_state;
};

// Offset-based accessors for opaque a12_state
// a12_state is opaque in Zig's @cImport because shmifsrv_vbuffer has bitfields.
// We access on_auth / auth_tag via the precomputed byte offsets in a12_offsets.
const ofs = @import("a12_offsets");
const A12State = ofs.A12State;

// Threading strategy
// One main thread drives socket I/O.  One detached thread per shmif segment
// drives the arcan event loop.  A "kill pipe" (pipe_pair) lets segment threads
// signal the main thread that data is ready to flush, and also serves as the
// shutdown signal (closing the write end kills the main poll loop).

// ClState: shared state across all segment threads

const ClState = struct {
    kill_fd: c_int,
    giant_lock: c.pthread_mutex_t,
    // atomic allocation bitmap: alloc[chid] != 0 means the slot is in use
    alloc: [256]u8 align(4),
    n_segments: u8 align(4),

    fn init(kill_write_fd: c_int) ClState {
        // pthread_mutex_t is a C struct with opaque layout; zero-init is valid
        // as a static mutex (equivalent to PTHREAD_MUTEX_INITIALIZER) before
        // pthread_mutex_init / pthread_mutex_lock are called.
        var mutex: c.pthread_mutex_t = std.mem.zeroes(c.pthread_mutex_t);
        _ = c.pthread_mutex_init(&mutex, null);
        return ClState{
            .kill_fd = kill_write_fd,
            .giant_lock = mutex,
            .alloc = std.mem.zeroes([256]u8),
            .n_segments = 0,
        };
    }

    inline fn lock(self: *ClState) void {
        _ = c.pthread_mutex_lock(&self.giant_lock);
    }

    inline fn unlock(self: *ClState) void {
        _ = c.pthread_mutex_unlock(&self.giant_lock);
    }
};

// Per-segment thread data

const ShmifThreadData = struct {
    C: *c.struct_arcan_shmif_cont,
    S: *c.struct_a12_state,
    state: *ClState,
    chid: u8,
};

// Helpers

fn getFreeId(state: *ClState) ?u8 {
    for (state.alloc, 0..) |used, i| {
        if (@atomicLoad(u8, &state.alloc[i], .seq_cst) == 0) {
            _ = used;
            return @intCast(i);
        }
    }
    return null;
}

// Event callback: called from a12_unpack while the giant_lock is held
// Signature must match the C callback type expected by a12_unpack.

fn onClEvent(
    cont: ?*c.struct_arcan_shmif_cont,
    chid: c_int,
    ev: ?*c.struct_arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = tag; // S is available via tag but not used here beyond type assertion
    _ = chid;

    const event = ev orelse return;

    if (cont == null) {
        // No shmif context for this channel yet — event is dropped.
        // (a12int_trace would go here if we had access to S->tracetag)
        return;
    }

    const cont_nn = cont.?;

    // Descriptor-carrying events should not arrive from the remote side;
    // the a12_channel_enqueue path handles those.  Log and ignore.
    if (c.arcan_shmif_descrevent(event)) {
        std.log.warn("helper_cl: incoming descriptor event ignored (EINVAL)", .{});
        return;
    }

    _ = c.arcan_shmif_enqueue(cont_nn, event);

    // bug 133 hypothesis-3 test: disable the post-REGISTER PRIVDROP-networked
    // injection. Durian's Lua may apply policies (suppress event flow,
    // restrict capabilities) to clients flagged networked. If this comment
    // exists in tree, it means the PRIVDROP injection was the suspected
    // cause of the single-DISPLAYHINT-then-stall behavior. Re-enable once
    // bug 133 is properly understood; do NOT ship without it long-term —
    // the WM SHOULD know the segment came over the wire.
    //
    // if (event.unnamed_0.unnamed_0.category == @as(u8, @intCast(c.EVENT_EXTERNAL)) and
    //     event.unnamed_0.unnamed_0.unnamed_0.ext.kind == @as(u8, @intCast(c.EVENT_EXTERNAL_REGISTER)))
    // {
    //     var privdrop = c.struct_arcan_event.zeroes();
    //     privdrop.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
    //     privdrop.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(u8, @intCast(c.EVENT_EXTERNAL_PRIVDROP));
    //     privdrop.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.privdrop.networked = 1;
    //     _ = c.arcan_shmif_enqueue(cont_nn, &privdrop);
    // }
}

// add_segment: open a new shmif sub-segment and spawn its thread
// Called from dispatch_event while the giant_lock is NOT held.

fn addSegment(S: *c.struct_a12_state, data: *ShmifThreadData, ev: *c.struct_arcan_event) void {
    data.state.lock();
    defer data.state.unlock();

    const chid = getFreeId(data.state) orelse {
        // Hit the 256-segment limit; shmif will clean up the pending request.
        return;
    };

    const segkind: u8 = @intCast(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv);
    const cookie: u32 = @bitCast(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv);

    // Announce the new channel to the remote side before the thread starts,
    // to prevent ordering races (thread preempts and writes before new-channel cmd).
    c.a12_channel_new(S, chid, segkind, cookie);

    var cont = c.arcan_shmif_acquire(data.C, null, @as(c_int, segkind), 0);
    if (cont.addr == null) {
        std.log.warn("helper_cl: add_segment: shmif_acquire failed for chid={}", .{chid});
        c.a12_set_channel(S, chid);
        c.a12_channel_close(S);
        return;
    }

    @atomicStore(u8, &data.state.alloc[chid], 1, .seq_cst);

    if (!spawnThread(S, data.state, &cont, chid)) {
        std.log.warn("helper_cl: add_segment: spawn_thread failed for chid={}", .{chid});
        c.a12_set_channel(S, chid);
        c.a12_channel_close(S);
        _ = c.arcan_shmif_drop(&cont);
        @atomicStore(u8, &data.state.alloc[chid], 0, .seq_cst);
    }
}

// dispatch_event: route one shmif event from a segment thread
// Returns true if the main thread should be woken to flush output.

fn dispatchEvent(data: *ShmifThreadData, ev: *c.struct_arcan_event) bool {
    const cat = ev.unnamed_0.unnamed_0.category;
    const tgt_kind = ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind;

    // DEBUG: every event the clientThread hands to dispatch
    {
        const smon = @import("shmif_monitor");
        const snprintf_ex = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf: [64]u8 = undefined;
        _ = snprintf_ex(&buf, 64, "dispatchEvent:cat=%d:tgt_kind=%d:chid=%d",
            @as(c_int, cat), @as(c_int, @intCast(tgt_kind)), @as(c_int, data.chid));
        smon.emitLuaTag(@ptrCast(&buf));
    }

    // NEWSEGMENT: open a new sub-segment mapped to a new a12 channel.
    if (cat == @as(u8, @intCast(c.EVENT_TARGET)) and
        tgt_kind == @as(u8, @intCast(c.TARGET_COMMAND_NEWSEGMENT)))
    {
        addSegment(data.S, data, ev);
        return true;
    }

    // DEVICE_NODE: mask out device-node hints; let the local shmif-srv handle
    // its own injection/redirection rather than bouncing through the network.
    if (cat == @as(u8, @intCast(c.EVENT_TARGET)) and
        tgt_kind == @as(u8, @intCast(c.TARGET_COMMAND_DEVICE_NODE)))
    {
        return false;
    }

    // EXIT: don't forward — the next poll will return -1 and tear down cleanly.
    if (cat == @as(u8, @intCast(c.EVENT_TARGET)) and
        tgt_kind == @as(u8, @intCast(c.TARGET_COMMAND_EXIT)))
    {
        return false;
    }

    data.state.lock();
    defer data.state.unlock();

    c.a12_set_channel(data.S, data.chid);
    // ev is shmif_types.arcan_event; a12_channel_enqueue wants a12_types
    // nominal. Identical layouts across the boundary.
    _ = c.a12_channel_enqueue(data.S, @ptrCast(ev));

    return true;
}

// clientThread: per-segment event loop (runs in a detached pthread)

fn clientThread(inarg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const data: *ShmifThreadData = @ptrCast(@alignCast(inarg orelse return null));

    const ERRMASK: c_short = @truncate(c.POLLERR | c.POLLNVAL | c.POLLHUP);
    var fds = [2]c.struct_pollfd{
        .{ .fd = data.C.epipe, .events = @as(c_short, @truncate(c.POLLIN)) | ERRMASK, .revents = 0 },
        .{ .fd = data.state.kill_fd, .events = ERRMASK, .revents = 0 },
    };

    loop: while (true) {
        const rc = c.poll(&fds, 2, -1);
        if (rc == -1) {
            const err = std.posix.errno(rc);
            if (err == .AGAIN or err == .INTR) continue;
            break :loop;
        }

        if ((fds[0].revents & ERRMASK) != 0 or (fds[1].revents & ERRMASK) != 0)
            break :loop;

        var dirty = false;
        var newev: c.struct_arcan_event = undefined;
        var pv: c_int = 0;
        while (true) {
            pv = c.arcan_shmif_poll(data.C, &newev);
            std.log.warn("[bug133] listener clientThread arcan_shmif_poll = {d}", .{pv});
            if (pv <= 0) break;
            // NOTE: Zig `or` is short-circuit — writing `dirty = dirty or
            // dispatchEvent(...)` silently drops every event after the first
            // dispatch that returned true (upstream C uses `|=`, which
            // always evaluates both sides). That bug stalled the a12↔shmif
            // bridge on CZ/ZZ/ZC matrix cells: the first DISPLAYHINT would
            // dispatch but the subsequent ACTIVATE, FONTHINT, etc. were
            // silently swallowed, so the remote end never saw the activation
            // signal and no video frames ever flowed back.
            const consumed = dispatchEvent(data, &newev);
            std.log.warn("[bug133] listener dispatchEvent consumed={any} cat={d} kind={d}", .{ consumed, newev.unnamed_0.unnamed_0.category, newev.unnamed_0.unnamed_0.unnamed_0.tgt.kind });
            if (consumed) dirty = true;
        }

        if (dirty) {
            // Wake the main thread so it flushes outgoing data.
            const chid_byte = [1]u8{data.chid};
            if (c.write(data.state.kill_fd, &chid_byte, 1) == -1)
                break :loop;
        }

        // arcan_shmif_poll returns < 0 when the segment has been torn down.
        if (pv < 0)
            break :loop;
    }

    // Teardown: close the channel, notify main thread, drop resources.
    data.state.lock();
    c.a12_set_channel(data.S, data.chid);
    c.a12_channel_shutdown(data.S, "".ptr);
    const chid_byte = [1]u8{data.chid};
    _ = c.write(data.state.kill_fd, &chid_byte, 1);
    c.a12_channel_close(data.S);
    _ = c.arcan_shmif_drop(data.C);

    // Primary segment dying takes everything down.
    if (data.chid == 0)
        _ = c.close(data.state.kill_fd);

    @atomicStore(u8, &data.state.alloc[data.chid], 0, .seq_cst);
    _ = @atomicRmw(u8, &data.state.n_segments, .Sub, 1, .seq_cst);
    data.state.unlock();

    // Free heap allocations made in spawnThread.
    std.c.free(@ptrCast(data.C));
    std.c.free(@ptrCast(data));

    return null;
}

// spawnThread: allocate thread data on the heap and detach a pthread

fn spawnThread(
    S: *c.struct_a12_state,
    cl: *ClState,
    cont: *c.struct_arcan_shmif_cont,
    chid: u8,
) bool {
    const data_raw = std.c.malloc(@sizeOf(ShmifThreadData)) orelse {
        std.log.warn("helper_cl: spawn_thread: OOM for thread data", .{});
        return false;
    };
    const data_ptr: *ShmifThreadData = @ptrCast(@alignCast(data_raw));

    const cont_raw = std.c.malloc(@sizeOf(c.struct_arcan_shmif_cont)) orelse {
        std.c.free(data_raw);
        std.log.warn("helper_cl: spawn_thread: OOM for cont copy", .{});
        return false;
    };
    const cont_ptr: *c.struct_arcan_shmif_cont = @ptrCast(@alignCast(cont_raw));

    cont_ptr.* = cont.*;
    data_ptr.* = ShmifThreadData{
        .C = cont_ptr,
        .S = S,
        .state = cl,
        .chid = chid,
    };

    // a12.a12_set_destination uses the a12_types view of arcan_shmif_cont;
    // cont_ptr was produced via shmif_types.arcan_shmif_open. The underlying
    // C struct is identical, so cast across the boundary.
    c.a12_set_destination(S, @ptrCast(cont_ptr), chid);

    var pth: c.pthread_t = undefined;
    var pthattr: c.pthread_attr_t = undefined;
    _ = c.pthread_attr_init(&pthattr);
    _ = c.pthread_attr_setdetachstate(&pthattr, c.PTHREAD_CREATE_DETACHED);
    // bug 0130-followup: pin a generous pthread stack to survive the
    // 7.8 MB stack-frame in a12int_append_out (see fossil 308e620ec7).
    // Default pthread stack of 8 MB is exactly at the boundary the
    // probe loop walks past on the first packet.
    _ = c.pthread_attr_setstacksize(&pthattr, 32 * 1024 * 1024);

    _ = @atomicRmw(u8, &cl.n_segments, .Add, 1, .seq_cst);

    if (c.pthread_create(&pth, &pthattr, clientThread, data_ptr) != 0) {
        _ = @atomicRmw(u8, &cl.n_segments, .Sub, 1, .seq_cst);
        c.a12_set_channel(S, chid);
        c.a12_channel_close(S);
        std.log.warn("helper_cl: spawn_thread: pthread_create failed", .{});
        std.c.free(@ptrCast(data_ptr));
        std.c.free(@ptrCast(cont_ptr));
        return false;
    }

    return true;
}

// authHandler: called by a12 once authentication is complete
// Signature matches the on_auth function pointer type in a12_state.

fn authHandler(S: *c.struct_a12_state, tag: ?*anyopaque) callconv(.c) void {
    // Clear the callback so it only fires once.
    A12State.writeOnAuth(@ptrCast(S), null);
    A12State.writeAuthTag(@ptrCast(S), null);

    const cont: *c.struct_arcan_shmif_cont = @ptrCast(@alignCast(tag orelse return));
    const cl: *ClState = @ptrCast(@alignCast(cont.user orelse return));
    _ = spawnThread(S, cl, cont, 0);
}

// Public API

/// Take a pre-negotiated A12 connection [S] serialised over [fd_in/fd_out]
/// and bridge it to a local arcan display server via [cp] (or [prealloc]).
///
/// Blocks until the connection is terminated.
/// Returns 0 on clean shutdown, negative errno on error.
pub export fn a12helper_a12srv_shmifcl(
    prealloc: ?*c.struct_arcan_shmif_cont,
    S: *c.struct_a12_state,
    cp_arg: ?[*:0]const u8,
    fd_in: c_int,
    fd_out: c_int,
) c_int {
    // Resolve connection point
    const cp: ?[*:0]const u8 = blk: {
        if (cp_arg) |p| {
            _ = c.setenv("ARCAN_CONNPATH", p, 1);
            break :blk p;
        }
        break :blk c.getenv("ARCAN_CONNPATH");
    };

    if (cp == null and prealloc == null) {
        std.log.err("helper_cl: no connection point specified", .{});
        return -@as(c_int, @intCast(@intFromEnum(std.posix.E.NOENT)));
    }

    // Create or adopt the primary shmif connection.
    var cont: c.struct_arcan_shmif_cont = if (prealloc) |p|
        p.*
    else
        // bug 133: opening as SEGID_TERMINAL (5) gets durian to send full
        // preroll (DISPLAYHINT × 2 + FONTHINT + GRAPHMODE × 30 + OUTPUTHINT
        // + ACTIVATE) where SEGID_UNKNOWN gets only one bare DISPLAYHINT.
        // Confirmed end-to-end on 2026-05-03: afsrv_terminal on st reaches
        // preroll OK and starts pumping back SEGREQ/CLOCKREQ/LABELHINT.
        // Hardcoded to SEGID_TERMINAL — works for terminal frameservers
        // (the most common bridge case) but is wrong for other kinds.
        // Proper fix: defer the arcan_shmif_open until the network's first
        // EXT:REGISTER arrives, so we open with the actual remote-declared
        // segid. Tracked separately as a follow-up to bug 133.
        c.arcan_shmif_open(c.SEGID_TERMINAL, c.SHMIF_NOACTIVATE, null);

    if (cont.addr == null) {
        std.log.err("helper_cl: couldn't connect to an arcan display server", .{});
        return -@as(c_int, @intCast(@intFromEnum(std.posix.E.NOENT)));
    }

    // Set up the kill pipe: write-end is kept in ClState, read-end is polled.
    var pipe_pair: [2]c_int = undefined;
    if (c.pipe(@ptrCast(&pipe_pair)) == -1)
        return -@as(c_int, @intCast(@intFromEnum(std.posix.E.INVAL)));

    var cl = ClState.init(pipe_pair[1]);
    @atomicStore(u8, &cl.alloc[0], 1, .seq_cst);
    cont.user = &cl;

    // Hook auth completion to spawn the primary segment thread, unless we are
    // already fully authenticated (e.g. pre-auth connection passed in).
    if (c.a12_auth_state(S) == c.AUTH_FULL_PK) {
        cl.lock();
        _ = spawnThread(S, &cl, &cont, 0);
        cl.unlock();
    } else {
        // Write on_auth and auth_tag via offset accessors (fields are on the
        // opaque struct that @cImport cannot see due to bitfield members).
        A12State.writeOnAuth(@ptrCast(S), @constCast(@ptrCast(&authHandler)));
        A12State.writeAuthTag(@ptrCast(S), &cont);
    }

    // Flush any leftover data from the authentication handshake.
    cl.lock();
    // a12_unpack takes an UnpackEventFn typed with a12_types.arcan_shmif_cont /
    // a12_types.arcan_event; our callback is typed with shmif_types flavours.
    // Layouts are identical — cast to match the extern prototype.
    c.a12_unpack(S, @as([*c]const u8, null), 0, S, @ptrCast(&onClEvent));
    cl.unlock();

    const ERRMASK: c_short = @truncate(c.POLLERR | c.POLLNVAL | c.POLLHUP);
    const POLLIN_S: c_short = @truncate(c.POLLIN);
    const POLLOUT_S: c_short = @truncate(c.POLLOUT);
    var fds = [3]c.struct_pollfd{
        .{ .fd = fd_in,        .events = POLLIN_S  | ERRMASK, .revents = 0 },
        .{ .fd = pipe_pair[0], .events = POLLIN_S  | ERRMASK, .revents = 0 },
        .{ .fd = fd_out,       .events = POLLOUT_S | ERRMASK, .revents = 0 },
    };

    var inbuf: [9000]u8 = undefined;
    var outbuf: [*c]u8 = null;
    var outbuf_sz: usize = 0;
    var n_fd: usize = 2; // start with only fd_in + kill_pipe; add fd_out when needed

    while (c.a12_ok(S)) {
        const rc = c.poll(&fds, @intCast(n_fd), -1);
        if (rc == -1) {
            const err = std.posix.errno(rc);
            if (err == .AGAIN or err == .INTR) continue;
            std.log.warn("helper_cl: pump exit — poll err={}", .{err});
            break;
        }

        // Any error on the monitored fds is fatal.
        if ((fds[0].revents & ERRMASK) != 0 or
            (fds[1].revents & ERRMASK) != 0 or
            (n_fd == 3 and (fds[2].revents & ERRMASK) != 0))
        {
            std.log.warn("helper_cl: pump exit — pollfd ERR fds[0]={x} fds[1]={x} fds[2]={x} (n_fd={d})", .{ fds[0].revents, fds[1].revents, fds[2].revents, n_fd });
            break;
        }

        // Drain wakeup tokens written by segment threads (chid bytes).
        if (fds[1].revents != 0) {
            _ = c.read(fds[1].fd, &inbuf, inbuf.len);
        }

        // Flush outgoing data when the socket is writable.
        if (n_fd == 3 and (fds[2].revents & POLLOUT_S) != 0 and outbuf_sz > 0) {
            const nw = c.write(fd_out, outbuf, outbuf_sz);
            if (nw > 0) {
                outbuf += @as(usize, @intCast(nw));
                outbuf_sz -= @intCast(nw);
            }
        }

        // Unpack incoming bytes from the remote a12 side.
        if ((fds[0].revents & POLLIN_S) != 0) {
            const nr = c.recv(fd_in, &inbuf, inbuf.len, 0);
            if (nr == -1) {
                const err = std.posix.errno(nr);
                if (err != .AGAIN and err != .INTR) {
                    std.log.warn("helper_cl: pump exit — recv err={}", .{err});
                    break;
                }
            } else if (nr == 0) {
                // Clean half-close from the other side.
                std.log.warn("helper_cl: pump exit — recv returned 0 (peer half-close)", .{});
                break;
            } else {
                cl.lock();
                c.a12_unpack(S, &inbuf, @intCast(nr), S, @ptrCast(&onClEvent));
                cl.unlock();
            }
        }

        // Refill the outgoing buffer from the a12 codec.
        if (outbuf_sz == 0) {
            cl.lock();
            outbuf_sz = c.a12_flush(S, &outbuf, c.A12_FLUSH_ALL);
            cl.unlock();
        }

        n_fd = if (outbuf_sz > 0) 3 else 2;
    }

    std.log.warn("helper_cl: pump loop EXITED — a12_ok={any}", .{c.a12_ok(S)});

    // If we never authenticated, drop the primary context.
    if (A12State.getOnAuth(@ptrCast(S)) != null) {
        _ = c.arcan_shmif_drop(&cont);
    }

    // Wait for all segment threads to exit.
    _ = c.close(pipe_pair[0]);
    while (@atomicLoad(u8, &cl.n_segments, .seq_cst) > 0) {
        // Spin — segment threads decrement n_segments as they exit.
        // The original C code does the same; a condvar would be cleaner but
        // this matches the reference implementation exactly.
        std.atomic.spinLoopHint();
    }

    if (!c.a12_free(S)) {
        std.log.warn("helper_cl: error cleaning up a12 context", .{});
    }

    return 0;
}
