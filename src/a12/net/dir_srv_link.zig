// Zig port of a12/net/dir_srv_link.c — directory server link management
// Handles connections between directory server instances (federation),
// link lifecycle, and state synchronisation in unified or referential mode.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    pub const close = libc.close;
    pub const strcmp = libc.strcmp;

    pub const struct_arcan_event = shmif.struct_arcan_event;
    // Prefer the shmif_types definition so field access / assignment from
    // shmif.arcan_shmif_* helpers round-trips through the same nominal type.
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_arg_arr = shmif.struct_arg_arr;
    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = shmif.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_EXTERNAL_NETSTATE = shmif.EVENT_EXTERNAL_NETSTATE;
    pub const EVENT_EXTERNAL_STREAMSTATUS = shmif.EVENT_EXTERNAL_STREAMSTATUS;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const SEGID_NETWORK_SERVER = shmif.SEGID_NETWORK_SERVER;
    pub const SHMIF_PLEDGE_PREFIX = shmif.SHMIF_PLEDGE_PREFIX;
    pub const TARGET_COMMAND_ACTIVATE = shmif.TARGET_COMMAND_ACTIVATE;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_REQFAIL = shmif.TARGET_COMMAND_REQFAIL;
    pub const arcan_shmif_descrevent = shmif.arcan_shmif_descrevent;
    pub const arcan_shmif_drop = shmif.arcan_shmif_drop;
    pub const arcan_shmif_dupfd = shmif.arcan_shmif_dupfd;
    pub const arcan_shmif_enqueue = shmif.arcan_shmif_enqueue;
    pub const arcan_shmif_last_words = shmif.arcan_shmif_last_words;
    pub const arcan_shmif_poll = shmif.arcan_shmif_poll;
    pub const arcan_shmif_privsep = shmif.arcan_shmif_privsep;
    pub const arcan_shmif_wait = shmif.arcan_shmif_wait;

    pub const arcan_shmif_open = shmif.arcan_shmif_open;
    pub const A12_BHANDLER_CANCELLED = a12.A12_BHANDLER_CANCELLED;
    pub const A12_BHANDLER_COMPLETED = a12.A12_BHANDLER_COMPLETED;
    pub const A12_BHANDLER_DONTWANT = a12.A12_BHANDLER_DONTWANT;
    pub const A12_BHANDLER_INITIALIZE = a12.A12_BHANDLER_INITIALIZE;
    pub const A12_BHANDLER_NEWFD = a12.A12_BHANDLER_NEWFD;
    pub const A12_BTYPE_APPL = a12.A12_BTYPE_APPL;
    pub const A12_BTYPE_APPL_CONTROLLER = a12.A12_BTYPE_APPL_CONTROLLER;
    pub const a12_channel_enqueue = a12.a12_channel_enqueue;
    pub const a12_get_endpoint = a12.a12_get_endpoint;
    pub const a12int_request_dirlist = a12.a12int_request_dirlist;
    pub const a12_remote_mode = a12.a12_remote_mode;
    pub const a12_set_bhandler = a12.a12_set_bhandler;
    pub const a12_set_destination_raw = a12.a12_set_destination_raw;
    pub const a12_trace_tag = a12.a12_trace_tag;
    pub const struct_a12_bhandler_meta = a12.struct_a12_bhandler_meta;
    pub const struct_a12_bhandler_res = a12.struct_a12_bhandler_res;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_a12_unpack_cfg = a12.struct_a12_unpack_cfg;
    pub const ROLE_DIR = a12.ROLE_DIR;
    pub const ROLE_DIRREF = a12.ROLE_DIRREF;
    pub const ROLE_PROBE = a12.ROLE_PROBE;
    pub const ROLE_SINK = a12.ROLE_SINK;

    pub const anet_cl_setup = anet.anet_cl_setup;
    pub const anet_directory_ioloop = anet.anet_directory_ioloop;
    pub const BREQ_STORE = anet.BREQ_STORE;
    pub const dir_request_resource = anet.dir_request_resource;
    pub const dir_unpack_index = anet.dir_unpack_index;
    pub const struct_anet_dirsrv_opts = anet.struct_anet_dirsrv_opts;
    pub const struct_anet_options = anet.struct_anet_options;
    pub const struct_appl_meta = anet.struct_appl_meta;
    pub const struct_directory_meta = anet.struct_directory_meta;
    pub const struct_evqueue_entry = anet.struct_evqueue_entry;
    pub const struct_hashmap_s = anet.struct_hashmap_s;
    pub const struct_ioloop_shared = anet.struct_ioloop_shared;
    pub const struct_pk_response = anet.struct_pk_response;
};

// sys/socket.h isn't cImported here; declare the shutdown syscall directly.
extern "c" fn shutdown(sockfd: c_int, how: c_int) c_int;
const SHUT_RDWR: c_int = 2;

// shmif open flags
// Mirror the ARCAN_FLAGS enum values used to open the parent process shmif
// segment.  Values taken from arcan_shmif_control.h.
const SHMIF_ACQUIRE_FATALFAIL: c_int = 4;
const SHMIF_NOACTIVATE: c_int = 512;
const SHMIF_NOAUTO_RECONNECT: c_int = 1024;
const SHMIF_NOREGISTER: c_int = 4096;
const SHMIF_SOCKET_PINGEVENT: c_int = 16384;

const shmif_open_flags: c_int =
    SHMIF_ACQUIRE_FATALFAIL |
    SHMIF_NOACTIVATE |
    SHMIF_NOAUTO_RECONNECT |
    SHMIF_NOREGISTER |
    SHMIF_SOCKET_PINGEVENT;

// Queue item
// Tracks an in-flight binary-transfer request: maps remote stream IDs to
// local application IDs so completion events can be correlated.
const QueueItem = struct {
    remote_id: u16,
    local_id: u16,
    stream_id: u32,
    next: ?*QueueItem = null,
};

// PkLookupFn
// Matches: struct pk_response (*pk_lookup)(struct a12_state* S, uint8_t pub[static 32], void*)
const PkLookupFn = *const fn (
    S: [*c]c.struct_a12_state,
    pub_key: [*c]u8,
    tag: ?*anyopaque,
) callconv(.c) c.struct_pk_response;

// Module-global state
// Mirrors the anonymous static struct `G` in dir_srv_link.c.
const Global = struct {
    shmif_parent_process: c.struct_arcan_shmif_cont,
    active_client_state: ?*c.struct_a12_state,
    local_index: ?*c.struct_appl_meta,
    ioloop_shared: ?*c.struct_ioloop_shared,
    queue: ?*QueueItem,
    map_appid: ?*c.struct_hashmap_s,
    key_auth: ?PkLookupFn,
    reference: bool,
    remote_pub: [32]u8,
};

var G: Global = std.mem.zeroes(Global);

// Trace state
// Used to emit DIRECTORY-group trace messages.  Mirrors `static struct a12_state
// trace_state = {.tracetag = "link"}` in the C source.
var trace_state: c.struct_a12_state = std.mem.zeroes(c.struct_a12_state);

// Event queue helpers

// No-op handler for events received on the parent shmif connection.
// Mirrors the empty parent_worker_event() in C.
fn parentWorkerEvent(_: *c.struct_arcan_event) void {}

// Free a single evqueue_entry, closing any attached file descriptor.
fn dropEvqueueItem(rep: ?*c.struct_evqueue_entry) void {
    const entry = rep orelse return;
    const ev: *c.struct_arcan_event = @ptrCast(@alignCast(&entry.ev));
    if (c.arcan_shmif_descrevent(ev) and ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv > 0) {
        _ = c.close(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
    }
    entry.next = null;
    std.heap.c_allocator.destroy(entry);
}

// Process all queue entries except the last; return the last entry.
fn runEvqueue(start: *c.struct_evqueue_entry) *c.struct_evqueue_entry {
    var rep = start;
    while (rep.next) |nxt| {
        const cur = rep;
        // rep.ev is a raw [576]u8 blob (arcan_event size); reinterpret for
        // arcan_event-shaped field access.
        parentWorkerEvent(@ptrCast(@alignCast(&rep.ev)));
        rep = nxt;
        dropEvqueueItem(cur);
    }
    return rep;
}

// Drain and free an entire evqueue chain.
fn dropEvqueue(start: ?*c.struct_evqueue_entry) void {
    var cur = start;
    while (cur) |entry| {
        const nxt = entry.next;
        dropEvqueueItem(entry);
        cur = nxt;
    }
}

// Resource request
// Send a BCHUNK request to the parent and synchronously wait for the reply.
// Returns a duplicated file descriptor on success, -1 on failure or rejection.
fn requestResource(ns: c_int, res: [*:0]const u8, mode: c_int) c_int {
    const rep = std.heap.c_allocator.create(c.struct_evqueue_entry) catch return -1;
    rep.* = std.mem.zeroes(c.struct_evqueue_entry);

    const status = c.dir_request_resource(
        @ptrCast(&G.shmif_parent_process),
        @bitCast(@as(c_ulong, @intCast(@as(c_uint, @bitCast(ns))))),
        res,
        mode,
        rep,
    );

    var fd: c_int = -1;

    if (status) {
        const last = runEvqueue(rep);
        // last.ev is [576]u8; reinterpret as arcan_event for field access.
        const ev: *c.struct_arcan_event = @ptrCast(@alignCast(&last.ev));
        if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind != c.TARGET_COMMAND_REQFAIL) {
            fd = c.arcan_shmif_dupfd(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, true);
        }
        dropEvqueueItem(last);
    } else {
        dropEvqueue(rep);
    }

    return fd;
}

// Binary transfer handler
// Callback registered with a12_set_bhandler.  Handles incoming appl / .ctrl
// binary streams from the remote directory.
fn linkBhandler(
    _: ?*c.struct_a12_state,
    M: c.struct_a12_bhandler_meta,
    _: ?*anyopaque,
) callconv(.c) c.struct_a12_bhandler_res {
    var res = c.struct_a12_bhandler_res{
        .fd = -1,
        .flag = c.A12_BHANDLER_DONTWANT,
    };

    switch (M.state) {
        c.A12_BHANDLER_COMPLETED => {
            // Acknowledge completion to the parent shmif segment.
            var sack = c.struct_arcan_event.zeroes();
            sack.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
            sack.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_STREAMSTATUS;
            sack.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.completion = 1.0;
            // correlate with the single channel serial stream
            sack.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.identifier = @intCast(M.streamid);
            _ = c.arcan_shmif_enqueue(&G.shmif_parent_process, &sack);
        },

        // [MISSING: verify a pending request is at the front of the queue]
        c.A12_BHANDLER_INITIALIZE => {
            if (M.type == c.A12_BTYPE_APPL or M.type == c.A12_BTYPE_APPL_CONTROLLER) {
                const restype: [*:0]const u8 =
                    if (M.type == c.A12_BTYPE_APPL) ".appl" else ".ctrl";
                // (uint16_t)-1 wrapped to c_int for the ns parameter
                const got_fd = requestResource(-1, restype, c.BREQ_STORE);
                if (got_fd != -1) {
                    res.fd = got_fd;
                    res.flag = c.A12_BHANDLER_NEWFD;
                }
            }
        },

        // [MISSING: send STREAMSTATUS event on the paired transfer]
        c.A12_BHANDLER_CANCELLED => {},

        else => {},
    }

    return res;
}

// Local directory synchronisation
// Stash the incoming local appl index pointer.  Called once before the remote
// index is available; subsequent calls can detect changed entries.
fn synchLocalDirectory(first: ?*c.struct_appl_meta) void {
    if (G.local_index != null) {
        // local-index updated — scan for new changes and synch upstream
        // (trace emitted by the C side; stub here)
    }
    G.local_index = first;
}

// Remote directory event callback
// Called by the ioloop for each decoded a12 event on the remote connection.
// Currently a no-op matching the empty C stub.
fn remoteDirEvent(
    _: ?*c.struct_arcan_shmif_cont,
    _: c_int,
    _: ?*c.struct_arcan_event,
    _: ?*anyopaque,
) callconv(.c) void {}

// Local shmif event pump
// Called by the ioloop when G.shmif_parent_process.epipe is readable.
fn localDirEvent(S: ?*c.struct_ioloop_shared, _: bool) callconv(.c) void {
    const ios = S orelse return;
    var ev: c.struct_arcan_event = undefined;
    var pv = c.arcan_shmif_poll(&G.shmif_parent_process, &ev);
    while (pv > 0) {
        parentWorkerEvent(&ev);
        // BCHUNKSTATE for updating the appl index is the main event here.
        pv = c.arcan_shmif_poll(&G.shmif_parent_process, &ev);
    }
    if (pv == -1) {
        ios.shutdown = true;
    }
}

// Local index lookup
// Linear search through the cached local index for a matching appl name.
fn findLocalMatch(needle: *c.struct_appl_meta) ?*c.struct_appl_meta {
    var hay = G.local_index;
    while (hay) |h| {
        if (c.strcmp(&needle.appl.name, &h.appl.name) == 0) {
            return h;
        }
        hay = h.next;
    }
    return null;
}

// Activation handshake
// Block until TARGET_COMMAND_ACTIVATE is received from the parent.  Any
// BCHUNK_IN(.appl-index) that arrives beforehand populates the local cache.
fn waitForActivation() bool {
    var ev: c.struct_arcan_event = undefined;

    while (c.arcan_shmif_wait(&G.shmif_parent_process, &ev) != 0) {
        if (ev.unnamed_0.unnamed_0.category != c.EVENT_TARGET) continue;

        if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_BCHUNK_IN) {
            if (c.strcmp(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message, ".appl-index") == 0) {
                const first = c.dir_unpack_index(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
                if (first == null) {
                    c.arcan_shmif_last_words(
                        &G.shmif_parent_process,
                        "activation: broken index",
                    );
                    return false;
                }
                synchLocalDirectory(first);
            }
        } else if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_ACTIVATE) {
            return true;
        }
    }

    c.arcan_shmif_last_words(&G.shmif_parent_process, "no activation");
    return false;
}

// Remote directory receive
// Called by the ioloop when the remote sends a complete directory listing.
// Enqueues a BCHUNKSTATE request for each entry not present in the local index.
fn remoteDirectoryReceive(
    I: ?*c.struct_ioloop_shared,
    dir_in: ?*c.struct_appl_meta,
) callconv(.c) bool {
    const ios = I orelse return true;
    var dir = dir_in;

    while (dir) |d| {
        if (findLocalMatch(d) != null) {
            dir = d.next;
            continue;
        }

        // Request the unknown appl from the remote directory.
        var ev = c.struct_arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
        ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input = 1;
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.hint = 0;
        // The ns/size union shares storage; assign via the ns member.
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns = d.identifier;
        _ = c.a12_channel_enqueue(@ptrCast(ios.S), @ptrCast(&ev));

        dir = d.next;
    }

    // Always keep-alive.
    return true;
}

// Remote discover callback
// Registered via a12_set_destination_raw.  Called when a DISCOVER message
// arrives on the remote connection.
fn remoteDirectoryDiscover(
    _: [*c]c.struct_a12_state,
    type_: u8,
    petname: [*c]const u8,
    state: u8,
    _: [*c]u8, // pubk
    _: u16,    // ns
    _: ?*anyopaque,
) callconv(.c) void {
    const found = (state == 1 or state == 2);
    _ = type_;
    _ = petname;
    _ = found;
    // Only tracing at this level; action is deferred to higher layers.
}

// Key-auth wrapper
// Daisy-chains to the original pk_lookup routine, caching the remote public
// key so it can be included in the NETSTATE announce for referential mode.
fn keyAuthWrap(
    S: [*c]c.struct_a12_state,
    pub_key: [*c]u8,
    tag: ?*anyopaque,
) callconv(.c) c.struct_pk_response {
    const rep = G.key_auth.?(S, pub_key, tag);
    if (rep.authentic) {
        @memcpy(G.remote_pub[0..32], pub_key[0..32]);
    }
    return rep;
}

// Public entry point
/// Establish a directory link to a remote arcan-net directory server.
///
/// `keytag`    – keystore tag for authenticating the outbound connection.
/// `netcfg`    – connection options (retry_count, key, and pk_lookup are
///               modified in-place before the outbound connection is made).
/// `srvcfg`    – directory server options (informational; unused at link level).
/// `ident`     – petname/identifier announced in referential mode.
/// `reference` – true for referential mode, false for unified mode.
///
/// Returns EXIT_SUCCESS (0) or EXIT_FAILURE (1).
pub export fn anet_directory_link(
    keytag: ?[*:0]const u8,
    netcfg: ?*c.struct_anet_options,
    srvcfg: c.struct_anet_dirsrv_opts,
    ident: ?[*:0]const u8,
    reference: bool,
) c_int {
    _ = srvcfg;

    // Open the parent shmif connection first so we can relay failures via
    // arcan_shmif_last_words().
    var args: ?*c.struct_arg_arr = null;
    G.shmif_parent_process = c.arcan_shmif_open(
        c.SEGID_NETWORK_SERVER,
        shmif_open_flags,
        &args,
    );
    G.reference = reference;

    const nc = netcfg orelse {
        c.arcan_shmif_last_words(&G.shmif_parent_process, "null netcfg");
        return 1; // EXIT_FAILURE
    };

    // Configure outbound connection parameters.
    nc.retry_count = 0;
    nc.key = keytag;
    nc.opts.*.allow_directory_link = true;
    G.key_auth = @ptrCast(@alignCast(nc.opts.*.pk_lookup));
    nc.opts.*.pk_lookup = keyAuthWrap;

    const conn = c.anet_cl_setup(nc);
    if (conn.errmsg != null or conn.state == null) {
        c.arcan_shmif_last_words(
            &G.shmif_parent_process,
            conn.errmsg orelse "connection failed",
        );
        return 1;
    }

    // Cross-module opaque: anet_types.struct_a12_state and a12_types.a12_state
    // are distinct opaque types but refer to the same concrete C struct.
    const state_a12: ?*a12.a12_state = @ptrCast(conn.state);
    if (c.a12_remote_mode(state_a12) != c.ROLE_DIR) {
        c.arcan_shmif_last_words(&G.shmif_parent_process, "remote not a directory");
        _ = shutdown(conn.fd, SHUT_RDWR);
        return 1;
    }

    // Privilege separation — unveil paths deferred until directory fd tests pass.
    c.arcan_shmif_privsep(&G.shmif_parent_process, c.SHMIF_PLEDGE_PREFIX, null, 0);

    G.active_client_state = @ptrCast(conn.state);
    c.a12_trace_tag(state_a12, "dir_link");

    if (!waitForActivation()) {
        _ = shutdown(conn.fd, SHUT_RDWR);
        return 1;
    }

    // Referential mode: announce endpoint + pubk + petname to parent
    // We go slightly out of shmif spec here by using netstate.space=1 to set
    // the host before registering as a SINK so the pubk is present in the
    // announce.  See comment in original C source.
    if (reference) {
        // Step 1: probe event carrying the remote endpoint host:port.
        var ep = c.struct_arcan_event.zeroes();
        ep.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
        ep.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;
        ep.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type = c.ROLE_PROBE;
        ep.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space = 1;

        const epstr: [*:0]const u8 = c.a12_get_endpoint(state_a12) orelse {
            c.arcan_shmif_last_words(&G.shmif_parent_process, "bad endpoint in link");
            return 1;
        };
        const ep_slice = std.mem.sliceTo(epstr, 0);
        if (ep_slice.len == 0) {
            c.arcan_shmif_last_words(&G.shmif_parent_process, "bad endpoint in link");
            return 1;
        }

        // Split "host:port" — scan backwards for the last colon.
        var split: usize = ep_slice.len;
        while (split > 0) {
            split -= 1;
            if (ep_slice[split] == ':') break;
        }
        if (split == 0) {
            c.arcan_shmif_last_words(&G.shmif_parent_process, "malformed link endpoint");
            return 1;
        }

        const port_str = ep_slice[split + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch {
            c.arcan_shmif_last_words(&G.shmif_parent_process, "bad port in link endpoint");
            return 1;
        };
        ep.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.port = port;

        // Copy the host portion into name[].
        const host_part = ep_slice[0..split];
        const name_len = @sizeOf(@TypeOf(ep.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name));
        const copy_len = @min(host_part.len, name_len - 1);
        @memcpy(ep.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[0..copy_len], host_part[0..copy_len]);
        ep.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[copy_len] = 0;
        _ = c.arcan_shmif_enqueue(&G.shmif_parent_process, &ep);

        // Step 2: announce the remote directory's public key as a SINK entry.
        var pk_ev = c.struct_arcan_event.zeroes();
        pk_ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
        pk_ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;
        pk_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type = c.ROLE_SINK;
        @memcpy(&pk_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.unnamed_0.pubk, &G.remote_pub);
        _ = c.arcan_shmif_enqueue(&G.shmif_parent_process, &pk_ev);

        // Step 3: register with petname as DIRREF so clients know how to reach us.
        var name_ev = c.struct_arcan_event.zeroes();
        name_ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
        name_ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;
        name_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type = c.ROLE_DIRREF;
        if (ident) |id| {
            const id_slice = std.mem.sliceTo(id, 0);
            const nl = @sizeOf(@TypeOf(name_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name));
            const cl = @min(id_slice.len, nl - 1);
            @memcpy(name_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[0..cl], id_slice[0..cl]);
            name_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[cl] = 0;
        }
        _ = c.arcan_shmif_enqueue(&G.shmif_parent_process, &name_ev);
    }

    // IO loop setup
    var dm = std.mem.zeroes(c.struct_directory_meta);
    dm.S = conn.state;
    // anet_types.struct_arcan_shmif_cont is opaque in anet_types but matches
    // the same C layout as shmif_types.struct_arcan_shmif_cont used above.
    dm.C = @ptrCast(&G.shmif_parent_process);

    // Zero-initialised ioloop_shared — the mutex member is zero-initialised
    // which is equivalent to PTHREAD_MUTEX_INITIALIZER on Linux.
    var ioloop = std.mem.zeroes(c.struct_ioloop_shared);
    ioloop.S = conn.state;
    ioloop.fdin = conn.fd;
    ioloop.fdout = conn.fd;
    ioloop.userfd = G.shmif_parent_process.epipe;
    ioloop.userfd2 = -1;
    ioloop.on_event = remoteDirEvent;
    ioloop.on_userfd = localDirEvent;
    ioloop.on_directory = remoteDirectoryReceive;
    ioloop.cbt = &dm;

    G.shmif_parent_process.user = &dm;

    // Register the discover callback on channel 0.
    var unpack_cfg = std.mem.zeroes(c.struct_a12_unpack_cfg);
    unpack_cfg.on_discover = remoteDirectoryDiscover;
    unpack_cfg.on_discover_tag = &ioloop;
    c.a12_set_destination_raw(
        state_a12,
        0,
        unpack_cfg,
        @sizeOf(c.struct_a12_unpack_cfg),
    );

    // Request the remote directory listing and subscribe to change notifications.
    c.a12int_request_dirlist(state_a12, true);
    c.a12_set_bhandler(state_a12, linkBhandler, &ioloop);

    G.ioloop_shared = &ioloop;
    c.anet_directory_ioloop(&ioloop);

    c.arcan_shmif_drop(&G.shmif_parent_process);

    return 0; // EXIT_SUCCESS
}
