// Zig port of a12/net/dir_srv_worker.c — directory server per-client worker
// Handles per-client worker processes, IPC with the directory parent,
// and client session lifecycle.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. Keeps the `c.X` spellings used below. Each alias routes to the
// appropriate hand-written replacement module (zero `@cImport` left).
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // libc
    pub const free = libc.free;
    pub const ftruncate = libc.ftruncate;
    pub const setenv = libc.setenv;
    pub const snprintf = libc.snprintf;
    pub const strdup = libc.strdup;
    pub const strncpy = libc.strncpy;

    // shmif — event/shmif-context + constants
    pub const arcan_shmif_descrevent = shmif.arcan_shmif_descrevent;
    pub const arcan_shmif_drop = shmif.arcan_shmif_drop;
    pub const arcan_shmif_dupfd = shmif.arcan_shmif_dupfd;
    pub const arcan_shmif_enqueue = shmif.arcan_shmif_enqueue;
    pub const arcan_shmif_open = shmif.arcan_shmif_open;
    pub const arcan_shmif_poll = shmif.arcan_shmif_poll;
    pub const arcan_shmif_privsep = shmif.arcan_shmif_privsep;
    pub const arcan_shmif_wait = shmif.arcan_shmif_wait;
    pub const arg_cleanup = shmif.arg_cleanup;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arg_unpack = shmif.arg_unpack;
    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = shmif.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_EXTERNAL_IDENT = shmif.EVENT_EXTERNAL_IDENT;
    pub const EVENT_EXTERNAL_MESSAGE = shmif.EVENT_EXTERNAL_MESSAGE;
    pub const EVENT_EXTERNAL_NETSTATE = shmif.EVENT_EXTERNAL_NETSTATE;
    pub const EVENT_EXTERNAL_REGISTER = shmif.EVENT_EXTERNAL_REGISTER;
    pub const EVENT_EXTERNAL_STREAMSTATUS = shmif.EVENT_EXTERNAL_STREAMSTATUS;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const SEGID_NETWORK_CLIENT = shmif.SEGID_NETWORK_CLIENT;
    pub const SEGID_NETWORK_SERVER = shmif.SEGID_NETWORK_SERVER;
    pub const SHMIF_ACQUIRE_FATALFAIL = shmif.SHMIF_ACQUIRE_FATALFAIL;
    pub const SHMIF_NOACTIVATE = shmif.SHMIF_NOACTIVATE;
    pub const SHMIF_NOAUTO_RECONNECT = shmif.SHMIF_NOAUTO_RECONNECT;
    pub const SHMIF_NOREGISTER = shmif.SHMIF_NOREGISTER;
    pub const SHMIF_PLEDGE_PREFIX = shmif.SHMIF_PLEDGE_PREFIX;
    pub const SHMIF_SOCKET_PINGEVENT = shmif.SHMIF_SOCKET_PINGEVENT;
    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_shmif_privsep_node = shmif.struct_shmif_privsep_node;
    pub const TARGET_COMMAND_ACTIVATE = shmif.TARGET_COMMAND_ACTIVATE;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_MESSAGE = shmif.TARGET_COMMAND_MESSAGE;
    pub const TARGET_COMMAND_REQFAIL = shmif.TARGET_COMMAND_REQFAIL;

    // a12 — state machine, extern fns, constants
    pub const a12_alloc_tunnel = a12.a12_alloc_tunnel;
    pub const A12_BHANDLER_CANCELLED = a12.A12_BHANDLER_CANCELLED;
    pub const A12_BHANDLER_COMPLETED = a12.A12_BHANDLER_COMPLETED;
    pub const A12_BHANDLER_DONTWANT = a12.A12_BHANDLER_DONTWANT;
    pub const A12_BHANDLER_INITIALIZE = a12.A12_BHANDLER_INITIALIZE;
    pub const A12_BHANDLER_NEWFD = a12.A12_BHANDLER_NEWFD;
    pub const A12_BTYPE_APPL = a12.A12_BTYPE_APPL;
    pub const A12_BTYPE_APPL_CONTROLLER = a12.A12_BTYPE_APPL_CONTROLLER;
    pub const A12_BTYPE_BLOB = a12.A12_BTYPE_BLOB;
    pub const A12_BTYPE_CRASHDUMP = a12.A12_BTYPE_CRASHDUMP;
    pub const A12_BTYPE_STATE = a12.A12_BTYPE_STATE;
    pub const a12_channel_enqueue = a12.a12_channel_enqueue;
    pub const a12_drop_tunnel = a12.a12_drop_tunnel;
    pub const a12_enqueue_bstream = a12.a12_enqueue_bstream;
    pub const a12_get_sign_pubkey = a12.a12_get_sign_pubkey;
    pub const a12int_notify_dynamic_resource = a12.a12int_notify_dynamic_resource;
    pub const a12int_set_directory = a12.a12int_set_directory;
    pub const a12int_get_directory = a12.a12int_get_directory;
    pub const a12_remote_mode = a12.a12_remote_mode;
    pub const a12_server = a12.a12_server;
    pub const a12_set_bhandler = a12.a12_set_bhandler;
    pub const a12_set_destination_raw = a12.a12_set_destination_raw;
    pub const a12_set_tunnel_sink = a12.a12_set_tunnel_sink;
    pub const a12_supply_dynamic_resource = a12.a12_supply_dynamic_resource;
    pub const a12_trace_tag = a12.a12_trace_tag;
    pub const blake3_hasher = a12.blake3_hasher;
    pub const blake3_hasher_finalize = a12.blake3_hasher_finalize;
    pub const blake3_hasher_init = a12.blake3_hasher_init;
    pub const blake3_hasher_update = a12.blake3_hasher_update;
    pub const ROLE_DIR = a12.ROLE_DIR;
    pub const ROLE_DIRREF = a12.ROLE_DIRREF;
    pub const ROLE_SINK = a12.ROLE_SINK;
    pub const ROLE_SOURCE = a12.ROLE_SOURCE;
    pub const struct_a12_bhandler_meta = a12.struct_a12_bhandler_meta;
    pub const struct_a12_bhandler_res = a12.struct_a12_bhandler_res;
    pub const struct_a12_context_options = a12.struct_a12_context_options;
    pub const struct_a12_dynreq = a12.struct_a12_dynreq;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_a12_unpack_cfg = a12.struct_a12_unpack_cfg;
    pub const struct_appl_meta = a12.struct_appl_meta;
    pub const struct_pk_response = a12.struct_pk_response;

    // anet — directory/worker + helper extern fns, constants
    pub const anet_authenticate = anet.anet_authenticate;
    pub const anet_directory_ioloop = anet.anet_directory_ioloop;
    pub const anet_directory_tunnel_thread = anet.anet_directory_tunnel_thread;
    pub const a12_btransfer_outfd = a12.a12_btransfer_outfd;
    pub const a12helper_fromb64 = anet.a12helper_fromb64;
    pub const a12helper_tob64 = anet.a12helper_tob64;
    pub const BREQ_LOAD = anet.BREQ_LOAD;
    pub const BREQ_STORE = anet.BREQ_STORE;
    pub const dir_block_synch_request = anet.dir_block_synch_request;
    pub const dir_request_resource = anet.dir_request_resource;
    pub const dir_unpack_index = anet.dir_unpack_index;
    pub const struct_anet_dirsrv_opts = anet.struct_anet_dirsrv_opts;
    pub const struct_directory_meta = anet.struct_directory_meta;
    pub const struct_evqueue_entry = anet.struct_evqueue_entry;
    pub const struct_ioloop_shared = anet.struct_ioloop_shared;
    pub const struct_arg_arr = shmif.struct_arg_arr;
};

// shmif open flags used consistently throughout this worker
const shmifopen_flags: c_int =
    c.SHMIF_ACQUIRE_FATALFAIL |
    c.SHMIF_NOACTIVATE |
    c.SHMIF_NOAUTO_RECONNECT |
    c.SHMIF_NOREGISTER |
    c.SHMIF_SOCKET_PINGEVENT;

// Process-global state
// These mirror the C file-scope statics. Only one worker runs per process, so
// global state is acceptable here just as in the C original.

var shmif_parent_process: c.struct_arcan_shmif_cont = std.mem.zeroes(c.struct_arcan_shmif_cont);
var active_client_state: ?*c.struct_a12_state = null;
var pending_index: ?*c.struct_appl_meta = null;
var ioloop_shared_ptr: ?*c.struct_ioloop_shared = null;

const PendingJoin = struct {
    pending: bool = false,
    used: usize = 0,
    queue: [8]c.struct_arcan_event = std.mem.zeroes([8]c.struct_arcan_event),
};
var pending_join: PendingJoin = .{};

// A dummy state used only for trace calls before real S is available.
// tracetag ("worker") is set at runtime in anet_directory_srv() because
// struct_a12_state is an opaque/large type that @cImport exposes without
// comptime-initializable bitfield members.
var trace_state: c.struct_a12_state = std.mem.zeroes(c.struct_a12_state);

var auth_pub_key: [32]u8 = std.mem.zeroes([32]u8);
var pending_tunnel: u8 = 0;

// Event queue helpers
// Note: parent_worker_event is defined later in this file; Zig resolves all
// top-level declarations regardless of textual order.

fn drop_evqueue_item(rep: ?*c.struct_evqueue_entry) void {
    const r = rep orelse return;
    if (c.arcan_shmif_descrevent(&r.ev) and r.ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv > 0) {
        _ = std.posix.close(@intCast(r.ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv));
    }
    r.next = null;
    std.heap.c_allocator.destroy(r);
}

/// Walk the linked list, dispatching every entry except the last.
/// Returns the last entry (caller must free it).
fn run_evqueue(
    S: *c.struct_a12_state,
    C: *c.struct_arcan_shmif_cont,
    rep: *c.struct_evqueue_entry,
) *c.struct_evqueue_entry {
    var cur_rep = rep;
    while (cur_rep.next) |next| {
        const cur = cur_rep;
        parent_worker_event(S, C, &cur.ev);
        cur_rep = next;
        drop_evqueue_item(cur);
    }
    return cur_rep;
}

fn drop_evqueue(rep: ?*c.struct_evqueue_entry) void {
    var cur = rep;
    while (cur) |entry| {
        const next = entry.next;
        drop_evqueue_item(entry);
        cur = next;
    }
}

// Pending-join flushing

fn flush_pending_join(C: *c.struct_arcan_shmif_cont) void {
    if (!pending_join.pending) return;
    for (pending_join.queue[0..pending_join.used]) |*ev| {
        _ = c.arcan_shmif_enqueue(C, ev);
    }
    pending_join.pending = false;
    pending_join.used = 0;
}

// Resource request helper

/// Ask the parent (via BCHUNKSTATE) for a named resource.
/// Returns a dup'd fd on success or -1 on failure.
fn request_resource(
    S: *c.struct_a12_state,
    C: *c.struct_arcan_shmif_cont,
    ns: c_int,
    res: [*:0]const u8,
    mode: c_int,
) c_int {
    const rep = std.heap.c_allocator.create(c.struct_evqueue_entry) catch return -1;
    rep.* = std.mem.zeroes(c.struct_evqueue_entry);

    if (!c.dir_request_resource(C, @intCast(ns), res, mode, rep)) {
        drop_evqueue(rep);
        return -1;
    }

    const last = run_evqueue(S, C, rep);
    const ev = last.ev;
    var fd: c_int = -1;

    if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind != c.TARGET_COMMAND_REQFAIL) {
        fd = c.arcan_shmif_dupfd(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, true);
    }

    drop_evqueue_item(last);
    return fd;
}

// Binary-chunk request from client

fn client_bchunk_request(
    I: *c.struct_ioloop_shared,
    cbt: *c.struct_directory_meta,
    C: *c.struct_arcan_shmif_cont,
    chid: c_int,
    ev: *c.struct_arcan_event,
) void {
    _ = chid;

    // Output direction: save the BCHUNKSTATE and wait for the bstream init.
    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input == 0) {
        cbt.breq_pending = ev.*;
        return;
    }

    const ext_ptr: [*:0]const u8 = @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions);
    const ext = std.mem.span(ext_ptr);

    // Special ".monitor" extension — forward as-is to parent.
    if (std.mem.eql(u8, ext, ".monitor")) {
        _ = c.arcan_shmif_enqueue(C, ev);
        return;
    }

    // ".applhost" — translate to a MESSAGE asking for server-side appl hosting.
    if (std.mem.eql(u8, ext, ".applhost")) {
        var req = c.struct_arcan_event.zeroes();
        req.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
        req.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;
        _ = c.snprintf(
            @ptrCast(&req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data),
            @sizeOf(@TypeOf(req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
            "a12:applhost:applid=%lu",
            @as(c_ulong, ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns),
        );
        _ = c.arcan_shmif_enqueue(C, &req);
        return;
    }

    // Routing rules for other files:
    //   .index - controller (if present),
    //   .*     - parent     (always) to route through external hooks
    //   *      - controller (if present)
    var fd: c_int = -1;
    if (ext.len > 0) {
        var dst: *c.struct_arcan_shmif_cont = C;
        if (ext[0] == '.') {
            if (std.mem.eql(u8, ext, ".index")) {
                if (ioloop_shared_ptr) |ios| {
                    if (ios.shmif.addr != null) dst = &ios.shmif;
                }
            }
        } else {
            if (ioloop_shared_ptr) |ios| {
                if (ios.shmif.addr != null) dst = &ios.shmif;
            }
        }
        fd = request_resource(
            cbt.S.?,
            dst,
            @intCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns),
            ext_ptr,
            c.BREQ_LOAD,
        );
    }
    // Otherwise download the appl.
    else {
        fd = request_resource(
            cbt.S.?,
            C,
            @intCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns),
            ".appl",
            c.BREQ_LOAD,
        );
    }

    if (fd == -1) {
        var fail_ev = c.struct_arcan_event.zeroes();
        fail_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_REQFAIL;
        fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].uiv = ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier;
        _ = c.a12_channel_enqueue(cbt.S, &fail_ev);
        return;
    }

    var empty_ext: [16]u8 = std.mem.zeroes([16]u8);

    if (ext.len > 0) {
        // Named single-stream send.
        var btype: c_int = c.A12_BTYPE_BLOB;
        if (std.mem.eql(u8, ext, ".state")) btype = c.A12_BTYPE_STATE;

        _ = c.a12_enqueue_bstream(
            cbt.S,
            fd,
            btype,
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier,
            false,
            0,
            &empty_ext,
        );
        std.posix.close(@intCast(fd));
        if (ioloop_shared_ptr) |ios| {
            ios.userfd2 = c.a12_btransfer_outfd(I.S);
        }
        return;
    }

    // Appl request: also try to grab state first (backwards compat).
    const state_fd = request_resource(
        cbt.S.?,
        C,
        @intCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns),
        ".state",
        c.BREQ_LOAD,
    );
    if (state_fd != -1) {
        _ = c.a12_enqueue_bstream(
            cbt.S,
            state_fd,
            c.A12_BTYPE_STATE,
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier,
            false,
            0,
            &empty_ext,
        );
        std.posix.close(@intCast(state_fd));
        if (ioloop_shared_ptr) |ios| {
            ios.userfd2 = c.a12_btransfer_outfd(I.S);
        }
    }

    _ = c.a12_enqueue_bstream(
        cbt.S,
        fd,
        c.A12_BTYPE_APPL,
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier,
        false,
        0,
        &empty_ext,
    );
    if (ioloop_shared_ptr) |ios| {
        ios.userfd2 = c.a12_btransfer_outfd(I.S);
    }
    std.posix.close(@intCast(fd));
}

// a12 event callback (called by the ioloop for client-originated events)

pub export fn on_a12srv_event(
    cont: ?*c.struct_arcan_shmif_cont,
    chid: c_int,
    ev: ?*c.struct_arcan_event,
    tag: ?*anyopaque,
) void {
    _ = cont;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag orelse return));
    const cbt: *c.struct_directory_meta = @ptrCast(@alignCast(I.cbt orelse return));
    const C: *c.struct_arcan_shmif_cont = @ptrCast(@alignCast(cbt.C orelse return));
    const event = ev orelse return;

    if (event.unnamed_0.unnamed_0.category != c.EVENT_EXTERNAL) return;

    const kind = event.unnamed_0.unnamed_0.unnamed_0.ext.kind;

    if (kind == c.EVENT_EXTERNAL_BCHUNKSTATE) {
        client_bchunk_request(I, cbt, C, chid, event);
        return;
    }

    if (kind == c.EVENT_EXTERNAL_REGISTER) {
        const mode = c.a12_remote_mode(cbt.S);
        if (mode == c.ROLE_DIR or mode == c.ROLE_DIRREF or
            mode == c.ROLE_SOURCE or mode == c.ROLE_SINK)
        {
            var disc = c.struct_arcan_event.zeroes();
            disc.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
            disc.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;
            disc.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type = @intCast(mode);
            disc.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space = 5;
            _ = c.snprintf(
                @ptrCast(&disc.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name),
                16,
                "%s",
                @as([*:0]const u8, @ptrCast(&event.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.title)),
            );
            _ = c.arcan_shmif_enqueue(C, &disc);
        }
        return;
    }

    if (kind == c.EVENT_EXTERNAL_STREAMSTATUS) {
        if (cbt.in_transfer and
            event.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.identifier == cbt.transfer_id)
        {
            cbt.in_transfer = false;
            cbt.breq_pending = c.struct_arcan_event.zeroes();
            I.userfd2 = c.a12_btransfer_outfd(I.S);
            _ = c.a12_channel_enqueue(cbt.S, event);
        }
        return;
    }

    if (kind == c.EVENT_EXTERNAL_IDENT) {
        pending_join.pending = true;
        pending_join.used = 0;
        _ = c.arcan_shmif_enqueue(C, event);
        return;
    }

    if (kind == c.EVENT_EXTERNAL_MESSAGE) {
        const msg_ptr: [*:0]const u8 = @ptrCast(&event.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data);
        const msg = std.mem.span(msg_ptr);

        var dst: *c.struct_arcan_shmif_cont = C;
        if (ioloop_shared_ptr) |ios| {
            if (ios.shmif.addr != null) dst = &ios.shmif;
        }

        // a12: prefix is always routed to the control channel.
        if (std.mem.startsWith(u8, msg, "a12:")) {
            dst = C;
        } else if (pending_join.pending) {
            if (pending_join.used >= pending_join.queue.len) return;
            pending_join.queue[pending_join.used] = event.*;
            pending_join.used += 1;
            return;
        }

        _ = c.arcan_shmif_enqueue(dst, event);
        return;
    }
}

// Binary-chunk events from the parent process

fn bchunk_event(
    S: *c.struct_a12_state,
    cbt: ?*c.struct_directory_meta,
    C: *c.struct_arcan_shmif_cont,
    ev: *c.struct_arcan_event,
) void {
    _ = C;
    const msg_ptr: [*:0]const u8 = @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message);
    const msg = std.mem.span(msg_ptr);

    if (std.mem.eql(u8, msg, ".appl-index")) {
        const first: ?*c.struct_appl_meta = c.dir_unpack_index(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
        // If S is the trace_state stub (no real session yet), stash it.
        if (S == &trace_state) {
            pending_index = first;
        } else {
            c.a12int_set_directory(S, first);
        }
        return;
    }

    if (std.mem.eql(u8, msg, ".tun")) {
        pending_tunnel = @intCast(c.a12_alloc_tunnel(S));
        if (pending_tunnel != 0) {
            _ = c.a12_set_tunnel_sink(
                S,
                pending_tunnel,
                c.arcan_shmif_dupfd(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, false),
            );
            if (ioloop_shared_ptr) |ios| {
                c.anet_directory_tunnel_thread(ios, pending_tunnel);
            }
        }
        return;
    }

    // ".appl-<name>" or ".monitor" — open an shmif segment via the descriptor.
    if (std.mem.startsWith(u8, msg, ".appl-") or std.mem.eql(u8, msg, ".monitor")) {
        const ios: *c.struct_ioloop_shared = ioloop_shared_ptr orelse return;

        if (ios.shmif.addr != null) {
            c.arcan_shmif_drop(&ios.shmif);
        }

        const fd = c.arcan_shmif_dupfd(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, true);
        var sockval: [16]u8 = undefined;
        const sockval_len = std.fmt.bufPrint(&sockval, "{d}", .{fd}) catch return;
        sockval[sockval_len.len] = 0;
        _ = c.setenv("ARCAN_SOCKIN_FD", @ptrCast(&sockval), 1);

        ios.shmif = c.arcan_shmif_open(
            c.SEGID_NETWORK_CLIENT,
            @intCast(shmifopen_flags),
            null,
        );

        if (ios.shmif.addr == null) {
            pending_join.pending = false;
            pending_join.used = 0;
            return;
        }

        // For appl join: compute H(kPub | applname) as persistent ctrl id.
        if (std.mem.startsWith(u8, msg, ".appl-")) {
            const applname_ptr: [*:0]const u8 = @ptrCast(msg.ptr + 6);

            if (cbt != null) {
                var joinev = c.struct_arcan_event.zeroes();
                joinev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
                joinev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;

                var hash: c.blake3_hasher = undefined;
                c.blake3_hasher_init(&hash);
                c.blake3_hasher_update(&hash, &auth_pub_key, 32);
                c.blake3_hasher_update(&hash, applname_ptr, std.mem.len(applname_ptr));
                c.blake3_hasher_finalize(&hash, @ptrCast(&joinev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.unnamed_0.pubk), 32);

                _ = c.arcan_shmif_enqueue(&ios.shmif, &joinev);
            }

            flush_pending_join(&ios.shmif);
        }
        return;
    }
}

// wait_for_activation

/// Drain the event queue from the parent shmif connection until ACTIVATE.
/// Also collects .appl-index payloads and the shared secret.
fn wait_for_activation(
    aopt: *c.struct_a12_context_options,
    C: *c.struct_arcan_shmif_cont,
) bool {
    const cbt: ?*c.struct_directory_meta = @ptrCast(@alignCast(C.user));
    var ev: c.struct_arcan_event = undefined;

    while (c.arcan_shmif_wait(C, &ev) != 0) {
        if (ev.unnamed_0.unnamed_0.category != c.EVENT_TARGET) continue;

        if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_BCHUNK_IN) {
            bchunk_event(&trace_state, cbt, C, &ev);
        } else if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_MESSAGE) {
            const stat = c.arg_unpack(@as([*:0]const u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)));
            if (stat == null) continue;
            defer c.arg_cleanup(stat);

            var secret: ?[*:0]const u8 = null;
            if (c.arg_lookup(stat, "secret", 0, @ptrCast(&secret))) {
                if (secret) |s| {
                    _ = c.snprintf(@ptrCast(&aopt.secret), 32, "%s", s);
                }
            }
        } else if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_ACTIVATE) {
            return true;
        }
    }

    return false;
}

// do_external_event

fn do_external_event(
    cbt: *c.struct_directory_meta,
    S: *c.struct_a12_state,
    C: *c.struct_arcan_shmif_cont,
    ev: *c.struct_arcan_event,
) void {
    _ = C;
    switch (ev.unnamed_0.unnamed_0.unnamed_0.ext.kind) {
        c.EVENT_EXTERNAL_MESSAGE => {
            _ = c.a12_channel_enqueue(cbt.S, ev);
        },
        c.EVENT_EXTERNAL_NETSTATE => {
            if (c.a12_remote_mode(S) == c.ROLE_SOURCE) {
                var dynreq = std.mem.zeroes(c.struct_a12_dynreq);
                if (cbt.secret != null) {
                    _ = c.snprintf(@ptrCast(&dynreq.authk), 12, "%s", cbt.secret);
                }
                @memcpy(dynreq.pubk[0..32], ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[0..32]);

                if (pending_tunnel != 0) {
                    dynreq.proto = 4;
                    _ = c.snprintf(
                        @ptrCast(&dynreq.host),
                        @sizeOf(@TypeOf(dynreq.host)),
                        "%d",
                        @as(c_int, pending_tunnel),
                    );
                    pending_tunnel = 0;
                }

                c.a12_supply_dynamic_resource(S, dynreq);
                return;
            }

            // Find ':' separator in name.
            var name = &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name;
            var i: usize = 0;
            while (i < name.len) : (i += 1) {
                if (name[i] == ':') {
                    name[i] = 0;
                    i += 1;
                    break;
                }
            }

            if (i > name.len - 32) return;

            c.a12int_notify_dynamic_resource(
                S,
                @ptrCast(name),
                @ptrCast(&name[i]),
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type,
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state,
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.ns,
            );
        },
        else => {},
    }
}

// parent_worker_event

fn parent_worker_event(
    S: *c.struct_a12_state,
    C: *c.struct_arcan_shmif_cont,
    ev: *c.struct_arcan_event,
) void {
    const cbt: *c.struct_directory_meta = @ptrCast(@alignCast(C.user orelse return));

    if (ev.unnamed_0.unnamed_0.category == c.EVENT_EXTERNAL) {
        do_external_event(cbt, S, C, ev);
        return;
    }

    if (ev.unnamed_0.unnamed_0.category != c.EVENT_TARGET) return;

    if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_BCHUNK_IN) {
        bchunk_event(S, cbt, C, ev);
        return;
    }

    if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_MESSAGE) {
        const stat = c.arg_unpack(@as([*:0]const u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)));

        // No a12 tag → inject verbatim into a12 channel.
        if (stat == null or !c.arg_lookup(stat, "a12", 0, null)) {
            _ = c.a12_channel_enqueue(S, ev);
            if (stat != null) c.arg_cleanup(stat);
            return;
        }
        defer c.arg_cleanup(stat);

        if (c.arg_lookup(stat, "flush_pending", 0, null)) {
            flush_pending_join(C);
        }

        var tmp: ?[*:0]const u8 = null;
        if (c.arg_lookup(stat, "drop_tunnel", 0, @ptrCast(&tmp))) {
            c.a12_drop_tunnel(S, 1);
        } else if (c.arg_lookup(stat, "dir_secret", 0, @ptrCast(&tmp))) {
            if (tmp) |t| {
                if (cbt.secret != null) {
                    c.free(cbt.secret);
                }
                cbt.secret = c.strdup(t);
            }
        }
    }
}

// ioloop callbacks

/// Called when the appl-controller shmif connection has data.
pub export fn on_appl_shmif(S: ?*c.struct_ioloop_shared, ok: bool) void {
    const ios: *c.struct_ioloop_shared = S orelse return;
    var ev: c.struct_arcan_event = undefined;
    var pv: c_int = undefined;

    while (true) {
        pv = c.arcan_shmif_poll(&ios.shmif, &ev);
        if (pv <= 0) break;
        if (active_client_state) |acs| {
            _ = c.a12_channel_enqueue(acs, &ev);
        }
    }

    if (pv == -1 or !ok) {
        c.arcan_shmif_drop(&ios.shmif);
        ios.shutdown = true;
    }
}

/// Called when the outbound binary-stream fd is ready.
pub export fn on_bstream_out(S: ?*c.struct_ioloop_shared, ok: bool) void {
    _ = ok;
    const ios: *c.struct_ioloop_shared = S orelse return;
    ios.userfd2 = c.a12_btransfer_outfd(ios.S);
}

/// Called when the parent shmif connection has data.
pub export fn on_shmif(S: ?*c.struct_ioloop_shared, ok: bool) void {
    const ios: *c.struct_ioloop_shared = S orelse return;
    const cbt: *c.struct_directory_meta = @ptrCast(@alignCast(ios.cbt orelse return));
    const C: *c.struct_arcan_shmif_cont = @ptrCast(@alignCast(cbt.C orelse return));

    var ev: c.struct_arcan_event = undefined;
    var pv: c_int = undefined;

    while (true) {
        pv = c.arcan_shmif_poll(C, &ev);
        if (pv <= 0) break;
        parent_worker_event(ios.S.?, C, &ev);
    }

    if (pv == -1 or !ok) {
        ios.shutdown = true;
    }
}

// key_auth_worker

/// Called by the a12 stack when a client public key needs authentication.
/// Forwards the key to the parent shmif process and waits for the derived
/// session key pair or a rejection.
pub export fn key_auth_worker(
    S: [*c]c.struct_a12_state,
    pk: [*c]u8,
    tag: ?*anyopaque,
) callconv(.c) c.struct_pk_response {
    _ = S;
    _ = tag;
    var reply = std.mem.zeroes(c.struct_pk_response);
    const pk_bytes: *const [32]u8 = @ptrCast(pk);

    var req = c.struct_arcan_event.zeroes();
    req.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    req.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;

    var outl: usize = 0;
    const b64: ?[*:0]u8 = @ptrCast(c.a12helper_tob64(pk_bytes, 32, &outl));
    if (b64 == null) return reply;
    _ = c.snprintf(
        @ptrCast(&req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data),
        @sizeOf(@TypeOf(req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
        "a12:pubk=%s",
        b64.?,
    );
    std.heap.c_allocator.free(std.mem.span(b64.?));

    _ = c.arcan_shmif_enqueue(&shmif_parent_process, &req);

    var rep: c.struct_arcan_event = undefined;
    var count: usize = 2;

    while (count > 0 and c.arcan_shmif_wait(&shmif_parent_process, &rep) > 0) {
        if (rep.unnamed_0.unnamed_0.category != c.EVENT_TARGET or
            rep.unnamed_0.unnamed_0.unnamed_0.tgt.kind != c.TARGET_COMMAND_MESSAGE) continue;

        const stat = c.arg_unpack(@as([*:0]const u8, @ptrCast(&rep.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)));
        if (stat == null) break;
        defer c.arg_cleanup(stat);

        if (!c.arg_lookup(stat, "a12", 0, null)) break;
        if (c.arg_lookup(stat, "fail", 0, null)) break;

        var inkey: ?[*:0]const u8 = null;
        if (c.arg_lookup(stat, "pub", 0, @ptrCast(&inkey))) {
            if (inkey) |k| {
                _ = c.a12helper_fromb64(@ptrCast(k), 32, @ptrCast(&reply.key_pub));
            }
            count -= 1;
        } else if (c.arg_lookup(stat, "ss", 0, @ptrCast(&inkey))) {
            if (inkey) |k| {
                _ = c.a12helper_fromb64(@ptrCast(k), 32, @ptrCast(&reply.key_session));
            }
            count -= 1;
        }
    }

    if (count == 0) {
        reply.authentic = true;
        @memcpy(&auth_pub_key, pk_bytes);
    }

    return reply;
}

// dirsrv_req_open

/// Called by the a12 stack when the client requests a directory-open (diropen).
/// Sends the request to the parent and blocks until a reply arrives.
pub export fn dirsrv_req_open(
    S: [*c]c.struct_a12_state,
    ident_req: [*c]u8,
    mode: u8,
    out: [*c]c.struct_a12_dynreq,
    tag: ?*anyopaque,
) callconv(.c) bool {
    if (S == null) return false;
    const state: *c.struct_a12_state = S;
    if (out == null) return false;
    const dynout: *c.struct_a12_dynreq = out;
    const cbt: *c.struct_directory_meta = @ptrCast(@alignCast(tag orelse return false));

    var outl: usize = 0;
    const req_b64: ?[*:0]u8 = @ptrCast(c.a12helper_tob64(ident_req, 32, &outl));
    if (req_b64 == null) return false;
    defer std.heap.c_allocator.free(std.mem.span(req_b64.?));

    var reqmsg = c.struct_arcan_event.zeroes();
    reqmsg.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    reqmsg.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;
    _ = c.snprintf(
        @ptrCast(&reqmsg.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data),
        @sizeOf(@TypeOf(reqmsg.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
        "a12:diropen:%spubk=%s",
        if (mode == 4) @as([*:0]const u8, "tunnel:") else @as([*:0]const u8, ""),
        req_b64.?,
    );
    _ = c.arcan_shmif_enqueue(cbt.C, &reqmsg);

    const rep = std.heap.c_allocator.create(c.struct_evqueue_entry) catch return false;
    rep.* = std.mem.zeroes(c.struct_evqueue_entry);

    var rv: bool = false;

    retry: while (true) {
        const got = c.dir_block_synch_request(
            cbt.C,
            reqmsg,
            rep,
            c.EVENT_EXTERNAL,
            c.EVENT_EXTERNAL_NETSTATE,
            c.EVENT_TARGET,
            c.TARGET_COMMAND_REQFAIL,
        );

        if (got) {
            rv = true;
            const last = run_evqueue(cbt.S.?, cbt.C.?, rep);
            const repev = last.ev;

            // space==5 means a source-register notification; retry.
            if (repev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space == 5) {
                // In the C original this is a goto retry_block, reusing `rep`.
                // Here we simply continue the while loop with a fresh allocation.
                // However because we already consumed `rep` we need to re-enter
                // the loop with the new pointer. Use a nested approach:
                {
                    var inner_rep = std.heap.c_allocator.create(c.struct_evqueue_entry) catch {
                        drop_evqueue_item(last);
                        break :retry;
                    };
                    inner_rep.* = std.mem.zeroes(c.struct_evqueue_entry);
                    drop_evqueue_item(last);

                    // Inner retry loop mirrors the C goto.
                    inner_retry: while (true) {
                        const got2 = c.dir_block_synch_request(
                            cbt.C,
                            reqmsg,
                            inner_rep,
                            c.EVENT_EXTERNAL,
                            c.EVENT_EXTERNAL_NETSTATE,
                            c.EVENT_TARGET,
                            c.TARGET_COMMAND_REQFAIL,
                        );
                        if (!got2) {
                            _ = run_evqueue(cbt.S.?, cbt.C.?, inner_rep);
                            rv = false;
                            break :inner_retry;
                        }
                        const last2 = run_evqueue(cbt.S.?, cbt.C.?, inner_rep);
                        const repev2 = last2.ev;
                        if (repev2.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space == 5) {
                            drop_evqueue_item(last2);
                            inner_rep = std.heap.c_allocator.create(c.struct_evqueue_entry) catch {
                                rv = false;
                                break :inner_retry;
                            };
                            inner_rep.* = std.mem.zeroes(c.struct_evqueue_entry);
                            continue :inner_retry;
                        }
                        // Got real reply.
                        var rq = std.mem.zeroes(c.struct_a12_dynreq);
                        rq.port = 6680;
                        rq.proto = 1;
                        if (repev2.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.port != 0)
                            rq.port = repev2.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.port;
                        if (cbt.secret != null)
                            _ = c.snprintf(@ptrCast(&rq.authk), 12, "%s", cbt.secret);
                        if (pending_tunnel != 0) {
                            rq.proto = 4;
                            _ = c.snprintf(
                                @ptrCast(&rq.host),
                                @sizeOf(@TypeOf(rq.host)),
                                "%d",
                                @as(c_int, pending_tunnel),
                            );
                            pending_tunnel = 0;
                        } else {
                            _ = c.strncpy(@ptrCast(&rq.host), @ptrCast(&repev2.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name), 45);
                        }
                        dynout.* = rq;
                        drop_evqueue_item(last2);
                        break :inner_retry;
                    }
                }
                break :retry;
            }

            // Normal success path.
            var rq = std.mem.zeroes(c.struct_a12_dynreq);
            rq.port = 6680;
            rq.proto = 1;
            if (repev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.port != 0) rq.port = repev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.port;
            if (cbt.secret != null)
                _ = c.snprintf(@ptrCast(&rq.authk), 12, "%s", cbt.secret);

            if (pending_tunnel != 0) {
                rq.proto = 4;
                _ = c.snprintf(
                    @ptrCast(&rq.host),
                    @sizeOf(@TypeOf(rq.host)),
                    "%d",
                    @as(c_int, pending_tunnel),
                );
                pending_tunnel = 0;
                dynout.* = rq;
                drop_evqueue_item(last);
            } else {
                _ = c.strncpy(@ptrCast(&rq.host), @ptrCast(&repev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name), 45);
                dynout.* = rq;
                drop_evqueue_item(last);
            }
        } else {
            // Rejected.
            _ = run_evqueue(cbt.S.?, cbt.C.?, rep);
            drop_evqueue_item(rep);
        }

        break :retry;
    }

    _ = state; // referenced via cbt.S
    return rv;
}

// find_identifier

fn find_identifier(base: ?*c.struct_appl_meta, id: c_uint) ?*c.struct_appl_meta {
    var cur = base;
    while (cur) |m| {
        if (m.identifier == id) return m;
        cur = m.next;
    }
    return null;
}

// pair_enqueue

fn pair_enqueue(
    S: *c.struct_a12_state,
    C: *c.struct_arcan_shmif_cont,
    ev: c.struct_arcan_event,
) void {
    var ev_copy = ev;
    const rep = std.heap.c_allocator.create(c.struct_evqueue_entry) catch {
        _ = c.a12_channel_enqueue(S, &ev_copy);
        return;
    };
    rep.* = std.mem.zeroes(c.struct_evqueue_entry);

    if (c.dir_block_synch_request(
        C,
        ev_copy,
        rep,
        c.EVENT_EXTERNAL,
        c.EVENT_EXTERNAL_STREAMSTATUS,
        c.EVENT_EXTERNAL,
        c.EVENT_EXTERNAL_STREAMSTATUS,
    )) {
        const last = run_evqueue(S, C, rep);
        drop_evqueue_item(last);
    } else {
        drop_evqueue_item(rep);
    }

    _ = c.a12_channel_enqueue(S, &ev_copy);
}

// srv_bevent

/// Called by the a12 stack for binary-transfer lifecycle events.
pub export fn srv_bevent(
    S: ?*c.struct_a12_state,
    M: c.struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) c.struct_a12_bhandler_res {
    var res = c.struct_a12_bhandler_res{
        .fd = -1,
        .flag = c.A12_BHANDLER_DONTWANT,
    };

    const state = S orelse return res;
    const cbt: *c.struct_directory_meta = @ptrCast(@alignCast(tag orelse return res));

    // Validate identifier if non-zero.
    if (M.identifier != 0) {
        var dir_clk: u64 = 0;
        const meta = find_identifier(c.a12int_get_directory(state, &dir_clk), M.identifier);
        if (meta == null and M.identifier != 0xFFFF) return res;
    }

    switch (M.state) {
        c.A12_BHANDLER_COMPLETED => {
            if (cbt.in_transfer and M.identifier == cbt.transfer_id) {
                // Send signing key to parent before completing.
                var skey = c.struct_arcan_event.zeroes();
                skey.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
                skey.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;

                var signkey: [32]u8 = undefined;
                c.a12_get_sign_pubkey(state, &signkey);
                var b64sz: usize = 0;
                const b64: ?[*:0]u8 = @ptrCast(c.a12helper_tob64(&signkey, 32, &b64sz));
                if (b64) |bptr| {
                    _ = c.snprintf(
                        @ptrCast(&skey.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data),
                        @sizeOf(@TypeOf(skey.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
                        "a12:signkey=%s",
                        bptr,
                    );
                    std.heap.c_allocator.free(std.mem.span(bptr));
                }
                _ = c.arcan_shmif_enqueue(cbt.C, &skey);

                var sack = c.struct_arcan_event.zeroes();
                sack.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
                sack.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_STREAMSTATUS;
                sack.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.completion = 1.0;
                sack.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.identifier = @intCast(M.streamid);

                if (cbt.breq_pending.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_BCHUNKSTATE and
                    cbt.breq_pending.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns == M.identifier)
                {
                    cbt.breq_pending = c.struct_arcan_event.zeroes();
                }

                cbt.in_transfer = false;
                pair_enqueue(cbt.S.?, cbt.C.?, sack);
            }
        },
        c.A12_BHANDLER_CANCELLED => {
            if (cbt.in_transfer and M.identifier == cbt.transfer_id) {
                var sack = c.struct_arcan_event.zeroes();
                sack.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
                sack.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_STREAMSTATUS;
                sack.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.completion = -1.0;
                sack.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.identifier = @intCast(M.streamid);

                cbt.in_transfer = false;
                if (cbt.breq_pending.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_BCHUNKSTATE and
                    cbt.breq_pending.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns == M.identifier)
                {
                    cbt.breq_pending = c.struct_arcan_event.zeroes();
                }

                pair_enqueue(cbt.S.?, cbt.C.?, sack);
            }
        },
        c.A12_BHANDLER_INITIALIZE => {
            if (M.type == c.A12_BTYPE_STATE) {
                res.fd = request_resource(state, cbt.C.?, @intCast(M.identifier), ".state", c.BREQ_STORE);
                if (res.fd != -1) {
                    cbt.in_transfer = true;
                    cbt.transfer_id = M.identifier;
                }
            } else if (M.type == c.A12_BTYPE_CRASHDUMP) {
                res.fd = request_resource(state, cbt.C.?, @intCast(M.identifier), ".debug", c.BREQ_STORE);
                if (res.fd != -1) {
                    cbt.in_transfer = true;
                    cbt.transfer_id = M.identifier;
                }
            } else if (M.type == c.A12_BTYPE_BLOB) {
                const req = cbt.breq_pending;
                if (req.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_BCHUNKSTATE and
                    req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns == M.identifier)
                {
                    // Default route: shared shmif (parent) if present, else worker C.
                    var dst: *c.struct_arcan_shmif_cont =
                        if (ioloop_shared_ptr) |ios|
                            if (ios.shmif.addr != null) &ios.shmif else @ptrCast(@alignCast(cbt.C))
                        else
                            @ptrCast(@alignCast(cbt.C));

                    // '.' prefixed extension → force cbt.C unless it's .index.
                    const ext_ptr: [*:0]const u8 = @ptrCast(&req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions);
                    const ext_slice = std.mem.span(ext_ptr);
                    if (ext_slice.len > 0 and ext_slice[0] == '.') {
                        if (!std.mem.eql(u8, ext_slice, ".index")) {
                            dst = @ptrCast(@alignCast(cbt.C));
                        }
                    }

                    // If the client has joined an applgroup with a controller,
                    // it's the responsibility of those scripts to map resources.
                    res.fd = request_resource(
                        state,
                        dst,
                        @intCast(M.identifier),
                        ext_ptr,
                        c.BREQ_STORE,
                    );

                    if (res.fd != -1) {
                        _ = std.c.ftruncate(res.fd, 0);
                        cbt.in_transfer = true;
                        cbt.transfer_id = M.identifier;
                    }
                }
            }
            // STATIC_DIRECTORY_SERVER guards additional types in C;
            // compile-time disabled here by omission (same semantics).
            else if (M.type == c.A12_BTYPE_APPL or M.type == c.A12_BTYPE_APPL_CONTROLLER) {
                const restype: [*:0]const u8 =
                    if (M.type == c.A12_BTYPE_APPL) ".appl" else ".ctrl";
                res.fd = request_resource(state, cbt.C.?, @intCast(M.identifier), restype, c.BREQ_STORE);
                if (res.fd != -1) {
                    cbt.in_transfer = true;
                    cbt.transfer_id = M.identifier;
                }
            }
        },
        else => {},
    }

    if (res.fd != -1) res.flag = c.A12_BHANDLER_NEWFD;
    return res;
}

// anet_directory_srv

/// Main entry point: called once per worker process.  Sets up the shmif
/// connection to the parent, runs the activation handshake, then drives the
/// a12 ioloop until the client disconnects.
pub export fn anet_directory_srv(
    netopts: ?*c.struct_a12_context_options,
    opts: c.struct_anet_dirsrv_opts,
    fdin: c_int,
    fdout: c_int,
) void {
    _ = opts;
    const no = netopts orelse return;

    no.pk_lookup = key_auth_worker;

    var args: ?*c.struct_arg_arr = null;
    shmif_parent_process = c.arcan_shmif_open(
        c.SEGID_NETWORK_SERVER,
        @intCast(shmifopen_flags),
        &args,
    );

    // Parse arguments forwarded from the parent via shmif open.
    if (args != null) {
        var val: ?[*:0]const u8 = null;
        if (c.arg_lookup(args, "rekey", 0, @ptrCast(&val))) {
            if (val) |v| {
                no.rekey_bytes = std.fmt.parseInt(
                    c_ulong,
                    std.mem.span(v),
                    10,
                ) catch 0;
            }
        }
        if (c.arg_lookup(args, "rekey_pqc", 0, null)) {
            no.pqc_rekey = true;
        }
        if (c.arg_lookup(args, "checksum_cap", 0, @ptrCast(&val))) {
            if (val) |v| {
                no.checksum_cap_mb = std.fmt.parseInt(
                    c_ulong,
                    std.mem.span(v),
                    10,
                ) catch 0;
            }
        }
    }

    // Privilege separation: only /tmp needed post-shmif-open.
    var paths = [_]c.struct_shmif_privsep_node{
        .{ .path = "/tmp", .perm = "rwc" },
        .{ .path = null, .perm = null },
    };
    var paths_ptr: [*c]c.struct_shmif_privsep_node = &paths[0];
    c.arcan_shmif_privsep(&shmif_parent_process, c.SHMIF_PLEDGE_PREFIX, @ptrCast(&paths_ptr), 0);

    if (!wait_for_activation(no, &shmif_parent_process)) return;

    // Allow directory links unless compiled with STATIC_DIRECTORY_SERVER.
    no.allow_directory_link = true;

    const S: *c.struct_a12_state = c.a12_server(no) orelse return;
    c.a12_trace_tag(S, "dir_worker");
    active_client_state = S;

    if (pending_index) |pi| {
        c.a12int_set_directory(S, pi);
        pending_index = null;
    }

    var cbt = std.mem.zeroes(c.struct_directory_meta);
    cbt.S = S;
    cbt.C = &shmif_parent_process;
    shmif_parent_process.user = &cbt;

    var msg: [*c]u8 = null;
    _ = c.anet_authenticate(S, fdin, fdout, &msg);

    c.a12_set_bhandler(S, srv_bevent, &cbt);

    var unpack_cfg = std.mem.zeroes(c.struct_a12_unpack_cfg);
    unpack_cfg.directory_open = dirsrv_req_open;
    unpack_cfg.tag = &cbt;
    c.a12_set_destination_raw(S, 0, unpack_cfg, @sizeOf(c.struct_a12_unpack_cfg));

    var ioloop = std.mem.zeroes(c.struct_ioloop_shared);
    ioloop.S = S;
    ioloop.fdin = fdin;
    ioloop.fdout = fdout;
    ioloop.userfd = shmif_parent_process.epipe;
    ioloop.userfd2 = -1;
    ioloop.on_event = on_a12srv_event;
    ioloop.on_userfd = on_shmif;
    ioloop.on_userfd2 = on_bstream_out;
    ioloop.on_shmif = on_appl_shmif;
    ioloop.cbt = &cbt;
    // lock initialised to zero (PTHREAD_MUTEX_INITIALIZER equivalent).

    ioloop_shared_ptr = &ioloop;

    c.anet_directory_ioloop(&ioloop);

    if (ioloop.shmif.addr != null) {
        c.arcan_shmif_drop(&ioloop.shmif);
    }
    c.arcan_shmif_drop(&shmif_parent_process);
}
