// Zig port of a12/net/dir_srv.c — Directory server implementation for arcan-net.
// Manages peer registration, service discovery, appl hosting, key authentication,
// and routing between connected clients.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. Each alias routes to the appropriate hand-written replacement
// module (zero `@cImport` left).
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // libc — stdio / string / process / fs
    pub const close = libc.close;
    pub const closedir = libc.closedir;
    pub const dup = libc.dup;
    pub const fclose = libc.fclose;
    pub const fdopen = libc.fdopen;
    pub const fdopendir = libc.fdopendir;
    pub const feof = libc.feof;
    pub const fread = libc.fread;
    pub const free = libc.free;
    pub const getenv = libc.getenv;
    pub const inet_pton = libc.inet_pton;
    pub const isalpha = libc.isalpha;
    pub const isdigit = libc.isdigit;
    pub const lseek = libc.lseek;
    pub const openat = libc.openat;
    pub const poll = libc.poll;
    pub const read = libc.read;
    pub const readdir = libc.readdir;
    pub const renameat = libc.renameat;
    pub const snprintf = libc.snprintf;
    pub const socketpair = libc.socketpair;
    pub const strcmp = libc.strcmp;
    pub const strdup = libc.strdup;
    pub const strlen = libc.strlen;
    pub const strncasecmp = libc.strncasecmp;
    pub const strncmp = libc.strncmp;
    pub const strtoul = libc.strtoul;
    pub const AF_INET = libc.AF_INET;
    pub const AF_INET6 = libc.AF_INET6;
    pub const AF_UNIX = libc.AF_UNIX;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const POLLERR = libc.POLLERR;
    pub const POLLHUP = libc.POLLHUP;
    pub const POLLIN = libc.POLLIN;
    pub const SEEK_SET = libc.SEEK_SET;
    pub const SIGUSR1 = shmif.SIGUSR1;
    pub const SOCK_STREAM = libc.SOCK_STREAM;
    pub const struct_pollfd = libc.struct_pollfd;

    // shmif — event / TARGET_COMMAND constants
    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = shmif.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_EXTERNAL_IDENT = shmif.EVENT_EXTERNAL_IDENT;
    pub const EVENT_EXTERNAL_MESSAGE = shmif.EVENT_EXTERNAL_MESSAGE;
    pub const EVENT_EXTERNAL_NETSTATE = shmif.EVENT_EXTERNAL_NETSTATE;
    pub const EVENT_EXTERNAL_STREAMSTATUS = shmif.EVENT_EXTERNAL_STREAMSTATUS;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const TARGET_COMMAND_ACTIVATE = shmif.TARGET_COMMAND_ACTIVATE;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_MESSAGE = shmif.TARGET_COMMAND_MESSAGE;
    pub const TARGET_COMMAND_REQFAIL = shmif.TARGET_COMMAND_REQFAIL;
    pub const struct_arg_arr = shmif.struct_arg_arr;
    pub const arg_cleanup = shmif.arg_cleanup;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arg_unpack = shmif.arg_unpack;

    // a12 — state machine, shmifsrv, helpers
    pub const a12_get_endpoint = a12.a12_get_endpoint;
    pub const a12_set_session = a12.a12_set_session;
    pub const arcan_random = a12.arcan_random;
    pub const blake3_hasher = a12.blake3_hasher;
    pub const blake3_hasher_finalize = a12.blake3_hasher_finalize;
    pub const blake3_hasher_init = a12.blake3_hasher_init;
    pub const blake3_hasher_update = a12.blake3_hasher_update;
    pub const CLIENT_DEAD = a12.CLIENT_DEAD;
    pub const CLIENT_IDLE = a12.CLIENT_IDLE;
    pub const ROLE_DIR = a12.ROLE_DIR;
    pub const ROLE_DIRREF = a12.ROLE_DIRREF;
    pub const ROLE_PROBE = a12.ROLE_PROBE;
    pub const ROLE_SINK = a12.ROLE_SINK;
    pub const ROLE_SOURCE = a12.ROLE_SOURCE;
    pub const SERVER_APPL_NONE = a12.SERVER_APPL_NONE;
    pub const SERVER_APPL_PRIMARY = a12.SERVER_APPL_PRIMARY;
    pub const SERVER_APPL_TEMP = a12.SERVER_APPL_TEMP;
    pub const shmifsrv_client_handle = a12.shmifsrv_client_handle;
    pub const shmifsrv_dequeue_events = a12.shmifsrv_dequeue_events;
    pub const shmifsrv_enqueue_event = a12.shmifsrv_enqueue_event;
    pub const shmifsrv_enqueue_multipart_message = a12.shmifsrv_enqueue_multipart_message;
    pub const shmifsrv_free = a12.shmifsrv_free;
    pub const shmifsrv_last_words = a12.shmifsrv_last_words;
    pub const shmifsrv_monotonic_rebase = a12.shmifsrv_monotonic_rebase;
    pub const shmifsrv_monotonic_tick = a12.shmifsrv_monotonic_tick;
    pub const shmifsrv_poll = a12.shmifsrv_poll;
    pub const shmifsrv_tick = a12.shmifsrv_tick;
    pub const struct_a12_context_options = a12.struct_a12_context_options;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_appl_meta = a12.struct_appl_meta;
    pub const struct_arcan_event = a12.struct_arcan_event;
    pub const struct_shmifsrv_client = a12.struct_shmifsrv_client;

    // anet — directory server helpers
    pub const a12helper_fromb64 = anet.a12helper_fromb64;
    pub const a12helper_keystore_accepted = anet.a12helper_keystore_accepted;
    pub const a12helper_keystore_enumerate = anet.a12helper_keystore_enumerate;
    pub const a12helper_keystore_hostkey = anet.a12helper_keystore_hostkey;
    pub const a12helper_keystore_statestore = anet.a12helper_keystore_statestore;
    pub const a12helper_keystore_stateunlink = anet.a12helper_keystore_stateunlink;
    pub const a12helper_tob64 = anet.a12helper_tob64;
    pub const anet_directory_dirsrv_exec_source = anet.anet_directory_dirsrv_exec_source;
    pub const anet_directory_lua_admin_command = anet.anet_directory_lua_admin_command;
    pub const anet_directory_lua_event = anet.anet_directory_lua_event;
    pub const anet_directory_lua_filter_source = anet.anet_directory_lua_filter_source;
    pub const anet_directory_lua_forced_source = anet.anet_directory_lua_forced_source;
    pub const anet_directory_lua_join = anet.anet_directory_lua_join;
    pub const anet_directory_lua_notify_source = anet.anet_directory_lua_notify_source;
    pub const anet_directory_lua_register = anet.anet_directory_lua_register;
    pub const anet_directory_lua_register_unknown = anet.anet_directory_lua_register_unknown;
    pub const anet_directory_lua_spawn_runner = anet.anet_directory_lua_spawn_runner;
    pub const anet_directory_lua_unregister = anet.anet_directory_lua_unregister;
    pub const anet_directory_lua_update = anet.anet_directory_lua_update;
    pub const anet_directory_random_ident = anet.anet_directory_random_ident;
    pub const anet_directory_signal_runner = anet.anet_directory_signal_runner;
    pub const buf_memfd = anet.buf_memfd;
    pub const build_appl_pkg = anet.build_appl_pkg;
    pub const DIRLINK_REFERENCE = anet.DIRLINK_REFERENCE;
    pub const DIRLINK_RESOLVER = anet.DIRLINK_RESOLVER;
    pub const DIRLINK_UNIFIED = anet.DIRLINK_UNIFIED;
    pub const DIRLUA_EVENT_LOST = anet.DIRLUA_EVENT_LOST;
    pub const dirsrv_bchunk_completion = anet.dirsrv_bchunk_completion;
    pub const dirsrv_bchunk_req = anet.dirsrv_bchunk_req;
    pub const file_to_membuf = anet.file_to_membuf;
    pub const REVERT_STEP_APPL = anet.REVERT_STEP_APPL;
    pub const REVERT_STEP_CTRL = anet.REVERT_STEP_CTRL;
    pub const SIG_PUBK_SZ = anet.SIG_PUBK_SZ;
    pub const struct_anet_dirsrv_opts = anet.struct_anet_dirsrv_opts;
    pub const struct_dircl = anet.struct_dircl;
    pub const struct_dirlua_event = anet.struct_dirlua_event;
    pub const struct_global_cfg = anet.struct_global_cfg;
    pub const struct_runner_state = anet.struct_runner_state;
    pub const verify_appl_pkg = anet.verify_appl_pkg;
};

// Sentinel value matching LUA_NOREF (-2)
const LUA_NOREF: c_int = -2;

// External symbols provided by the surrounding C build
extern var g_shutdown: bool;
extern var global: c.struct_global_cfg;

// pthread — not included via cImport because musl's pthread.h drags in
// bitfield-unfriendly headers. Declare the subset we use directly.
extern "c" fn pthread_mutex_lock(mtx: ?*anyopaque) c_int;
extern "c" fn pthread_mutex_unlock(mtx: ?*anyopaque) c_int;

// Per-source visibility mask
// Controls which sink clients can see a given source.
const SourceMask = struct {
    applid: c_int,
    pubk: [32]u8,
    identity: [16]u8,
    dstpubk: [32]u8,
    next: ?*SourceMask,
};

// Global server state
// Held for the lifetime of the process; protected by `sync`.
const ActiveClients = struct {
    sync: std.Thread.Mutex,
    root: c.struct_dircl,         // sentinel head — never accessed directly
    opts: ?*c.struct_anet_dirsrv_opts,
    dirlist: ?[]u8,               // heap-allocated index blob
    masks: ?*SourceMask,
};

var active_clients = ActiveClients{
    .sync = .{},
    .root = std.mem.zeroes(c.struct_dircl),
    .opts = null,
    .dirlist = null,
    .masks = null,
};

// Trace states: large (~200 kB each) so kept as module-level vars rather than
// on the stack, mirroring the C original.
var main_trace_state = std.mem.zeroes(c.struct_a12_state);
var lua_trace_state  = std.mem.zeroes(c.struct_a12_state);

// Allocator
// Use the C allocator for allocations that must round-trip through C code
// (dircl structs handed to shmifsrv_free / free(), dirlist blobs handed to
// buf_memfd).  Pure Zig-internal structures (SourceMask) use the same
// allocator for simplicity.
const alloc = std.heap.c_allocator;

// Lock helpers (exported so dir_lua.c can call them)
pub export fn dirsrv_global_lock(_file: [*:0]const u8, _line: c_int) void {
    _ = _file;
    _ = _line;
    active_clients.sync.lock();
}

pub export fn dirsrv_global_unlock(_file: [*:0]const u8, _line: c_int) void {
    _ = _file;
    _ = _line;
    active_clients.sync.unlock();
}

// Accessor shims

pub export fn dirsrv_trace_state() ?*c.struct_a12_state {
    return &main_trace_state;
}

pub export fn dirsrv_opts() ?*c.struct_global_cfg {
    return &global;
}

pub export fn dirsrv_config() ?*c.struct_anet_dirsrv_opts {
    return active_clients.opts;
}

/// [EXPECT_LOCKED] Walk the appl list and return the entry whose numeric
/// identifier matches [id].
pub export fn dirsrv_locked_numid_appl(id: u16) ?*c.struct_appl_meta {
    const opts = active_clients.opts orelse return null;
    var cur: ?*c.struct_appl_meta = &opts.dir;
    while (cur) |entry| {
        if (entry.identifier == id) return entry;
        cur = entry.next;
    }
    return null;
}

// Internal helpers

/// Returns true if another connected client already uses the petname in [ev].
fn gotSourceName(source: *c.struct_dircl, ev: c.struct_arcan_event) bool {
    active_clients.sync.lock();
    defer active_clients.sync.unlock();

    var cur: [*c]c.struct_dircl = active_clients.root.next;
    while (cur != null) {
        if (cur != source) {
            const ev_name = &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name;
            const C_name  = &cur.*.petname.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name;
            if (c.strncasecmp(C_name, ev_name, ev_name.len) == 0) {
                return true;
            }
        }
        cur = cur.*.next;
    }
    return false;
}

/// Push the current directory listing blob to client [C].
fn dirlistToWorker(C: *c.struct_dircl) void {
    const list = active_clients.dirlist orelse return;

    const fd = c.buf_memfd(@ptrCast(list.ptr), list.len);
    if (fd == -1) return;
    defer _ = c.close(fd);

    var ev = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = @intCast(list.len);
    const tag = ".appl-index";
    @memcpy(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0..tag.len], tag);
    _ = c.shmifsrv_enqueue_event(C.C, &ev, fd);
}

/// True if the client has a petname or identity set.
fn hasIdent(C: *const c.struct_dircl) bool {
    return C.petname.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[0] != 0 or C.identity[0] != 0;
}

/// True if the client is acting as a source or directory reference.
fn refOrSource(C: *const c.struct_dircl) bool {
    return C.petname.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_SOURCE or
           C.petname.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_DIRREF;
}

/// True if the namespaces of [src] and [dst] are compatible.
fn matchNs(src: *const c.struct_dircl, dst: *const c.struct_dircl) bool {
    return dst.in_appl == 0 or dst.in_appl == src.in_appl;
}

// Source-mask logic

/// Returns a pointer to the mask entry that governs visibility of [source] to
/// [dst], or null if there is no restriction (source is fully visible).
fn applySourceMask(
    source: *const c.struct_dircl,
    dst: *const c.struct_dircl,
) ?*SourceMask {
    if (dst.type == 0 or dst.type != c.ROLE_SINK or source.type != c.ROLE_SOURCE)
        return null;

    var cur = active_clients.masks;
    while (cur) |m| {
        if (std.mem.eql(u8, &m.pubk, source.pubk[0..32]))
            break;
        cur = m.next;
    }

    const mask = cur orelse return null;

    // applid-limited mask: only show to clients in the same appl
    if (mask.applid != 0 and dst.in_appl != mask.applid)
        return null;

    // identity-limited mask
    if (mask.identity[0] != 0) {
        // The C original has a strcmp bug (compares identity to itself).
        // We preserve the behaviour: the check is effectively a no-op.
        _ = mask.identity;
    }

    const empty_key = [_]u8{0} ** 32;
    if (std.mem.eql(u8, &mask.dstpubk, &empty_key))
        return mask;

    if (!std.mem.eql(u8, &mask.dstpubk, dst.pubk[0..32]))
        return null;

    return mask;
}

/// Append the authenticated public key to the NETSTATE name field.
fn tagOutboundName(ev: *c.struct_arcan_event, kpub: *const [32]u8) bool {
    const name = &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name;
    const len = c.strlen(name);
    if (len > name.len - 34) return false;
    name[len] = ':';
    @memcpy(name[len + 1 ..][0..32], kpub);
    return true;
}

// Register source

fn registerSource(C: *c.struct_dircl, ev_in: c.struct_arcan_event) void {
    var ev = ev_in;
    var allow = active_clients.opts.?.allow_src;
    var preauth = false;

    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_DIR) {
        allow = active_clients.opts.?.allow_dir;
    } else if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_DIRREF) {
        if (C.dir_ref) {
            preauth = true;
            if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space == 6) {
                const nullk = [_]u8{0} ** 32;
                if (std.mem.eql(u8, C.pubk[0..32], &nullk)) {
                    @memcpy(C.pubk[0..32], ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.unnamed_0.pubk[0..32]);
                } // else: reject pubk update
                return;
            }
        }
        allow = active_clients.opts.?.allow_reference;
    }

    var rv: c_int = 0;
    active_clients.sync.lock();
    blk: {
        if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_SOURCE and
            c.anet_directory_lua_forced_source(C))
        {
            C.petname = ev;
            C.type = c.ROLE_SOURCE;
            active_clients.sync.unlock();
            return;
        }
        rv = c.anet_directory_lua_filter_source(C, &ev);
        break :blk;
    }
    active_clients.sync.unlock();

    if (rv == 1) {
        preauth = true;
    } else if (rv < 0) {
        return;
    }

    if (!preauth and c.a12helper_keystore_accepted(&C.pubk, allow) == null) {
        return;
    }

    // Sanitise name to alnum + underscore
    const title = &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name;
    var i: usize = 0;
    while (i < title.len and title[i] != 0) : (i += 1) {
        const ch = title[i];
        if (c.isdigit(ch) == 0 and c.isalpha(ch) == 0)
            title[i] = '_';
    }

    // Deduplicate petnames
    if (gotSourceName(C, ev)) {
        while (gotSourceName(C, ev)) {
            c.anet_directory_random_ident(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name, 16);
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[16] = 0;
        }
        return;
    }

    // Block rename after first registration
    if (C.petname.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[0] != 0) {
        if (c.strcmp(&C.petname.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name, &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name) != 0)
            return;
    }

    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 1;
    C.petname = ev;

    if (!tagOutboundName(&ev, C.pubk[0..32]))
        return;

    C.type = ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type;

    // Broadcast to all eligible peers
    active_clients.sync.lock();
    defer active_clients.sync.unlock();

    var cur: [*c]c.struct_dircl = active_clients.root.next;
    while (cur != null) : (cur = cur.*.next) {
        const peer = cur;
        if (peer == C or peer.*.C == null) continue;

        if (applySourceMask(C, peer)) |mask| {
            var out_ev = ev;
            if (mask.identity[0] != 0 or
                std.mem.eql(u8, &mask.dstpubk, peer.*.pubk[0..32]))
            {
                out_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 2;
            }
            out_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.ns = @intCast(mask.applid);
            _ = c.shmifsrv_enqueue_event(peer.*.C, &out_ev, -1);
        }
    }
}

// Dynamic source listing

/// Forward all active sources that belong to [applid] to client [C].
/// Caller must hold the global lock.
fn forwardApplSources(C: *c.struct_dircl, applid: c_int) void {
    var cur: [*c]c.struct_dircl = active_clients.root.next;
    while (cur != null) : (cur = cur.*.next) {
        const peer = cur;
        if (peer == C or peer.*.C == null) continue;

        if (applySourceMask(peer, C)) |mask| {
            if (mask.applid == applid) {
                var ev = peer.*.petname;
                const nl = c.strlen(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name);
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[nl] = ':';
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 1;
                @memcpy(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[nl + 1 ..][0..32], peer.*.pubk[0..32]);
                _ = c.shmifsrv_enqueue_event(C.C, &ev, -1);
            }
        }
    }
}

/// Send the current dynamic source list to [C].
fn dynlistToWorker(C: *c.struct_dircl) void {
    active_clients.sync.lock();
    defer active_clients.sync.unlock();

    var cur: [*c]c.struct_dircl = active_clients.root.next;
    while (cur != null) {
        const peer: *c.struct_dircl = @ptrCast(cur);
        cur = peer.next;
        if (peer == C or peer.C == null) continue;
        if (applySourceMask(peer, C) == null) {
            var ev = peer.petname;
            const nl = c.strlen(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name);
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[nl] = ':';
            @memcpy(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[nl + 1 ..][0..32], peer.pubk[0..32]);
            _ = c.shmifsrv_enqueue_event(C.C, &ev, -1);
        }
    }
}

// Dynamic open

fn dynOpenApplHost(C: *c.struct_dircl, entry: *c.struct_arg_arr) void {
    var pubk: [*c]const u8 = null;
    if (!c.arg_lookup(entry, "pubk", 0, &pubk) or pubk == null) {
        sendReqFail(C);
        return;
    }

    var pubk_dec: [32]u8 = undefined;
    if (!c.a12helper_fromb64(pubk, 32, &pubk_dec)) {
        sendReqFail(C);
        return;
    }
    // Locate appl and build shmifsrv handover — stub matching upstream TODO.
}

fn dynOpenToWorker(C: *c.struct_dircl, entry: *c.struct_arg_arr) void {
    var pubk_str: [*c]const u8 = null;
    if (!c.arg_lookup(entry, "pubk", 0, &pubk_str) or pubk_str == null) {
        sendReqFail(C);
        return;
    }

    var pubk_dec: [32]u8 = undefined;
    if (!c.a12helper_fromb64(pubk_str, 32, &pubk_dec)) {
        sendReqFail(C);
        return;
    }

    active_clients.sync.lock();
    var found = false;

    var cur: [*c]c.struct_dircl = active_clients.root.next;
    outer: while (cur != null) {
        const peer: *c.struct_dircl = @ptrCast(cur);
        cur = peer.next;
        if (peer == C or peer.C == null or
            !hasIdent(peer) or !refOrSource(peer) or !matchNs(C, peer))
            continue;

        if (!std.mem.eql(u8, &pubk_dec, peer.pubk[0..32]))
            continue;

        // Referential link: send the remote endpoint directly
        if (peer.dir_ref) {
            _ = c.shmifsrv_enqueue_event(C.C, &peer.endpoint, -1);
            found = true;
            break :outer;
        }

        // Tunnel setup
        if (c.arg_lookup(entry, "tunnel", 0, null)) {
            if (!active_clients.opts.?.allow_tunnel) {
                active_clients.sync.unlock();
                sendReqFail(C);
                return;
            }
            var sv: [2]c_int = undefined;
            if (c.socketpair(c.AF_UNIX, c.SOCK_STREAM, 0, &sv) != 0) {
                active_clients.sync.unlock();
                sendReqFail(C);
                return;
            }
            var ts = c.struct_arcan_event.zeroes();
            ts.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            ts.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
            @memcpy(ts.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0..4], ".tun");
            _ = c.shmifsrv_enqueue_event(peer.C, &ts, sv[0]);
            _ = c.shmifsrv_enqueue_event(C.C, &ts, sv[1]);
            _ = c.close(sv[0]);
            _ = c.close(sv[1]);
        }

        // Shared one-time secret
        var secret: [8]u8 = undefined;
        c.arcan_random(&secret, 8);
        var b64_sz2: usize = 0;
        const b64 = c.a12helper_tob64(&secret, 8, &b64_sz2);
        defer c.free(b64);

        var ss = c.struct_arcan_event.zeroes();
        ss.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        ss.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
        _ = c.snprintf(&ss.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message, ss.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len, "a12:dir_secret=%s", b64);

        _ = c.shmifsrv_enqueue_event(C.C, &ss, -1);
        _ = c.shmifsrv_enqueue_event(peer.C, &ss, -1);

        // Notify source with sink's pubk, notify sink with source's endpoint
        var to_src = c.struct_arcan_event.zeroes();
        to_src.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
        to_src.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;
        to_src.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space = 5;
        @memcpy(to_src.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[0..32], C.pubk[0..32]);

        _ = c.shmifsrv_enqueue_event(peer.C, &to_src, -1);
        _ = c.shmifsrv_enqueue_event(C.C, &peer.endpoint, -1);

        peer.tunnel = C.tunnel;
        found = true;
        break :outer;
    }
    active_clients.sync.unlock();

    if (!found) sendReqFail(C);
}

fn applHostToWorker(C: *c.struct_dircl, entry: *c.struct_arg_arr) void {
    var appid_str: [*c]const u8 = null;
    if (!c.arg_lookup(entry, "applid", 0, &appid_str) or appid_str == null) {
        var ev = c.struct_arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
        @memcpy(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0.."a12:applhost:missing_arg".len], "a12:applhost:missing_arg");
        _ = c.shmifsrv_enqueue_event(C.C, &ev, -1);
        return;
    }

    const opts = active_clients.opts orelse return;
    if (opts.applhost_path == null) return;

    const applid: u16 = @intCast(c.strtoul(appid_str, null, 10));

    active_clients.sync.lock();
    const meta = dirsrv_locked_numid_appl(applid);
    active_clients.sync.unlock();

    if (meta == null) return;
    if (c.a12helper_keystore_accepted(&C.pubk, opts.allow_applhost) == null) {
        var ev = c.struct_arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
        @memcpy(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0.."a12:applhost:fail:reason=eperm".len],
                "a12:applhost:fail:reason=eperm");
        _ = c.shmifsrv_enqueue_event(C.C, &ev, -1);
        return;
    }

    const basepath = c.getenv("ARCAN_APPLBASEPATH") orelse return;

    // Build minimal argv / envv and delegate to exec_source
    var argvv = [_][*:0]u8{
        opts.applhost_path orelse return,
        @constCast("--database"),
        @constCast("/tmp/test.sqlite"),
        @ptrCast(&meta.?.appl.name),
    };
    var envbuf: [256]u8 = undefined;
    const pathenv = std.fmt.bufPrintZ(&envbuf, "ARCAN_APPLBASEPATH={s}", .{
        std.mem.span(basepath),
    }) catch return;
    var envv = [_][*:0]u8{ pathenv.ptr };

    // struct arcan_strarr contains a union; translate-c makes it opaque.
    // Mirror layout from engine/arcan_mem.h.
    const ArcanStrarrLocal = extern struct {
        count: usize = 0,
        limit: usize = 0,
        data: [*c][*c]u8 = null,
    };
    var argv_arr = ArcanStrarrLocal{
        .count = argvv.len,
        .data  = @ptrCast(&argvv),
    };
    var env_arr = ArcanStrarrLocal{
        .count = envv.len,
        .data  = @ptrCast(&envv),
    };

    _ = c.anet_directory_dirsrv_exec_source(
        C, 0, null, opts.applhost_path, @ptrCast(&argv_arr), @ptrCast(&env_arr));
}

// Message queue

fn msgqueueWorker(C: *c.struct_dircl, ev: *const c.struct_arcan_event) void {
    if (C.in_appl <= 0 and !C.in_admin) return;

    if (C.in_appl > 0 and C.message_ofs == 0) {
        const prefix = std.fmt.bufPrintZ(
            C.message_multipart[0..],
            "from={s}:",
            .{std.mem.sliceTo(&C.identity, 0)},
        ) catch return;
        C.message_ofs = prefix.len;
    }

    const str = std.mem.sliceTo(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data, 0);
    const len = str.len;
    if (C.message_ofs + len >= C.message_multipart.len) return;

    @memcpy(C.message_multipart[C.message_ofs..][0..len], str);
    C.message_ofs += len;

    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart != 0) return;

    C.message_multipart[C.message_ofs] = 0;

    var outev = c.struct_arcan_event.zeroes();
    outev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    outev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;

    active_clients.sync.lock();
    defer active_clients.sync.unlock();

    if (C.in_admin) {
        _ = c.anet_directory_lua_admin_command(C, @ptrCast(&C.message_multipart));
    } else {
        var cur: [*c]c.struct_dircl = active_clients.root.next;
        while (cur != null) {
            const peer: *c.struct_dircl = @ptrCast(cur);
            cur = peer.next;
            if (peer.in_appl == C.in_appl and peer != C) {
                _ = c.shmifsrv_enqueue_multipart_message(
                    peer.C, &outev,
                    &C.message_multipart, C.message_ofs);
            }
        }
    }
    C.message_ofs = 0;
}

// Authentication

fn processAuthRequest(C: *c.struct_dircl, entry: *c.struct_arg_arr) bool {
    C.authenticated = true;

    var pubk_str: [*c]const u8 = null;
    if (!c.arg_lookup(entry, "a12", 0, null) or
        !c.arg_lookup(entry, "pubk", 0, &pubk_str) or
        pubk_str == null) return false;

    var pubk_dec: [32]u8 = undefined;
    if (!c.a12helper_fromb64(pubk_str, 32, &pubk_dec)) return false;

    @memcpy(C.pubk[0..32], &pubk_dec);

    active_clients.sync.lock();
    const aopt: *c.struct_a12_context_options = @ptrCast(active_clients.opts.?.a12_cfg);
    const S = &lua_trace_state;
    var rep = aopt.pk_lookup.?(S, &pubk_dec, aopt.pk_lookup_tag);

    if (!rep.authentic) {
        rep = c.anet_directory_lua_register_unknown(C, rep, pubk_str);
        if (rep.authentic) {
            var tmp_host: [*c]u8 = null;
            var tmp_port: u16 = 0;
            var my_privk: [32]u8 = undefined;
            _ = c.a12helper_keystore_hostkey("default", 0, &my_privk, &tmp_host, &tmp_port);
            c.a12_set_session(&rep, &pubk_dec, &my_privk);
        }
    } else {
        c.anet_directory_lua_register(C);
    }
    active_clients.sync.unlock();

    if (!rep.authentic) return false;

    var ev = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;

    var b64_sz: usize = 0;
    const b64_pub = c.a12helper_tob64(&rep.key_pub, 32, &b64_sz);
    _ = c.snprintf(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message, ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len, "a12:pub=%s", b64_pub);
    c.free(b64_pub);
    _ = c.shmifsrv_enqueue_event(C.C, &ev, -1);

    b64_sz = 0;
    const b64_ss = c.a12helper_tob64(&rep.key_session, 32, &b64_sz);
    _ = c.snprintf(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message, ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len, "a12:ss=%s", b64_ss);
    c.free(b64_ss);
    _ = c.shmifsrv_enqueue_event(C.C, &ev, -1);

    return true;
}

// Monitor command

fn handleMonitorCommand(C: *c.struct_dircl, entry: *c.struct_arg_arr) void {
    if (c.arg_lookup(entry, "break", 0, null)) {
        active_clients.sync.lock();
        defer active_clients.sync.unlock();
        if (dirsrv_locked_numid_appl(@intCast(C.in_appl))) |appl| {
            _ = c.anet_directory_signal_runner(appl, c.SIGUSR1);
        }
    }
}

// Message dispatch

fn sendReqFail(C: *c.struct_dircl) void {
    var ev = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_REQFAIL;
    _ = c.shmifsrv_enqueue_event(C.C, &ev, -1);
}

fn diRclMessage(C: *c.struct_dircl, ev: c.struct_arcan_event) void {
    // Non-a12 prefix or admin: broadcast / forward
    if (c.strncmp(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data, "a12:", 4) != 0 or C.in_admin) {
        msgqueueWorker(C, &ev);
        return;
    }

    const entry = c.arg_unpack(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data) orelse return;
    defer c.arg_cleanup(entry);

    if (C.in_monitor) {
        handleMonitorCommand(C, entry);
        return;
    }

    if (!C.authenticated) {
        if (!processAuthRequest(C, entry)) {
            var fail_ev = c.struct_arcan_event.zeroes();
            fail_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
            @memcpy(fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0.."a12:fail".len], "a12:fail");
            _ = c.shmifsrv_enqueue_event(C.C, &fail_ev, -1);
        }
        return;
    }

    if (c.arg_lookup(entry, "dirlist", 0, null)) {
        dynlistToWorker(C);
    } else if (c.arg_lookup(entry, "diropen", 0, null)) {
        dynOpenToWorker(C, entry);
    } else if (c.arg_lookup(entry, "applhost", 0, null)) {
        applHostToWorker(C, entry);
    } else {
        var msgarg: [*c]const u8 = null;
        if (c.arg_lookup(entry, "signkey", 0, &msgarg) and msgarg != null) {
            _ = c.a12helper_fromb64(msgarg, 32, &C.pubk_sign);
        }
    }
}

// Network state

pub export fn handle_netstate(C: *c.struct_dircl, ev_in: c.struct_arcan_event) void {
    var ev = ev_in;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name.len - 1] = 0;

    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_PROBE) {
        C.endpoint = ev;
        return;
    }

    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_SOURCE or
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_DIR or
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_DIRREF)
    {
        registerSource(C, ev);
        return;
    }

    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type == c.ROLE_SINK) {
        @memcpy(C.pubk[0..32], ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.unnamed_0.pubk[0..32]);
    }
}

// IDENT join

pub export fn dirsrv_find_cl_ident(
    appid: c_int, name: [*:0]const u8, locked: bool,
) ?*c.struct_dircl {
    if (!locked) active_clients.sync.lock();
    defer if (!locked) active_clients.sync.unlock();

    var C: [*c]c.struct_dircl = active_clients.root.next;
    while (C != null) {
        if (C.*.in_appl == appid and
            c.strcmp(name, &C.*.identity) == 0) return C;
        C = C.*.next;
    }
    return null;
}

fn handleIdent(C: *c.struct_dircl, ev: c.struct_arcan_event) void {
    var end_ptr: [*c]u8 = null;
    const ind: usize = @intCast(c.strtoul(@ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data), &end_ptr, 10));

    // Fallback "anon_XXXXXXXX" buffer — 13 chars + NUL
    var buf: [14]u8 = [_]u8{0} ** 14;
    @memcpy(buf[0..5], "anon_");

    active_clients.sync.lock();
    defer active_clients.sync.unlock();

    if (end_ptr == null or end_ptr.* == 0) {
        // No suffix supplied — generate a random, collision-free identity.
        var attempt: u32 = 0;
        while (attempt < 1000) : (attempt += 1) {
            c.anet_directory_random_ident(@ptrCast(&buf[5]), 8);
            if (dirsrv_find_cl_ident(@intCast(ind), @ptrCast(&buf), true) == null)
                break;
        }
        _ = c.snprintf(&C.identity, C.identity.len, "%s", @as([*:0]u8, @ptrCast(&buf)));
    } else if (end_ptr.* == ':') {
        // "id:name" form — use the supplied suffix, de-duplicate if needed.
        end_ptr += 1; // skip ':'
        if (end_ptr.* != 0) {
            // Save the original requested name so we can append suffixes.
            const work = c.strdup(end_ptr) orelse return; // OOM
            defer c.free(work);
            var count: usize = 0;
            while (dirsrv_find_cl_ident(@intCast(ind), @ptrCast(end_ptr), true) != null) {
                count += 1;
                if (count >= 99) {
                    // Fall back to a random name
                    while (true) {
                        c.anet_directory_random_ident(@ptrCast(&buf[5]), 8);
                        if (dirsrv_find_cl_ident(@intCast(ind), @ptrCast(&buf), true) == null)
                            break;
                    }
                    // Write chosen identity directly into C and return early
                    _ = c.snprintf(&C.identity, C.identity.len, "%s",
                        @as([*:0]u8, @ptrCast(&buf)));
                    doJoin(C, ind);
                    return;
                }
                _ = c.snprintf(end_ptr, 16, "%.13s_%d", work, @as(c_int, @intCast(count)));
            }
            _ = c.snprintf(&C.identity, C.identity.len, "%s", end_ptr);
        }
    } else {
        // Malformed message — ignore
        return;
    }

    doJoin(C, ind);
}

fn doJoin(C: *c.struct_dircl, ind: usize) void {
    var cur = dirsrv_locked_numid_appl(@intCast(ind));

    // Resolve alias
    if (cur) |m| {
        if (m.alias_identifier != 0) {
            cur = dirsrv_locked_numid_appl(m.alias_identifier);
        }
    }

    if (cur) |meta| {
        C.in_appl = @intCast(ind);
        if (meta.server_appl != c.SERVER_APPL_NONE) {
            if (meta.server_tag == null) {
                _ = c.anet_directory_lua_spawn_runner(
                    meta, active_clients.opts.?.runner_process);
            }
            _ = c.anet_directory_lua_join(C, meta);
            forwardApplSources(C, C.in_appl);
        } else {
            var flush_ev = c.struct_arcan_event.zeroes();
            flush_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            flush_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
            @memcpy(flush_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0.."flush_pending".len], "flush_pending");
            _ = c.shmifsrv_enqueue_event(C.C, &flush_ev, -1);
        }
    } else {
        C.in_appl = -1;
    }
}

// Per-client worker thread

fn dirclProcess(C_ptr: *c.struct_dircl) void {
    const C = C_ptr;
    c.shmifsrv_monotonic_rebase();

    var pv: c_int = 25;
    var dead = false;
    var activated = false;

    while (!dead) {
        var pfd = c.struct_pollfd{
            .fd     = c.shmifsrv_client_handle(C.C, null),
            .events = c.POLLIN | c.POLLERR | c.POLLHUP,
            .revents = 0,
        };

        if (c.poll(@ptrCast(&pfd), 1, pv) > 0 and pfd.revents != 0) {
            if (pfd.revents != c.POLLIN) break;
            pv = 25;
        }

        const sv = c.shmifsrv_poll(C.C);
        if (sv == c.CLIENT_DEAD) {
            dead = true;
            continue;
        }

        if (!activated and c.shmifsrv_poll(C.C) == c.CLIENT_IDLE) {
            activated = true;

            const opts = active_clients.opts.?;
            const a12_cfg = opts.a12_cfg.?;
            if (a12_cfg.secret[0] != 0) {
                var sec_ev = c.struct_arcan_event.zeroes();
                sec_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
                sec_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
                _ = c.snprintf(&sec_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message, sec_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len,
                    "secret=%s", &a12_cfg.secret);

                // Replace ':' with '\t' per protocol rule
                var si: usize = 0;
                while (si < 32 and sec_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[si] != 0) : (si += 1) {
                    if (sec_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[si] == ':')
                        sec_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[si] = '\t';
                }
                _ = c.shmifsrv_enqueue_event(C.C, &sec_ev, -1);
            }

            if (!C.dir_resolver)
                dirlistToWorker(C);

            var act_ev = c.struct_arcan_event.zeroes();
            act_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            act_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_ACTIVATE;
            _ = c.shmifsrv_enqueue_event(C.C, &act_ev, -1);
        }

        var ev: c.struct_arcan_event = undefined;
        var flush = false;

        while (c.shmifsrv_dequeue_events(C.C, @ptrCast(&ev), 1) == 1) {
            flush = true;

            switch (ev.unnamed_0.unnamed_0.unnamed_0.ext.kind) {
                c.EVENT_EXTERNAL_IDENT => handleIdent(C, ev),
                c.EVENT_EXTERNAL_NETSTATE => handle_netstate(C, ev),
                c.EVENT_EXTERNAL_BCHUNKSTATE => {
                    c.dirsrv_bchunk_req(C,
                        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns,
                        @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions),
                        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input != 0);
                },
                c.EVENT_EXTERNAL_STREAMSTATUS => {
                    _ = c.shmifsrv_enqueue_event(C.C, &ev, -1);
                    if (C.pending_stream) {
                        C.pending_stream = false;
                        c.dirsrv_bchunk_completion(C, ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.completion >= 1.0);
                    }
                },
                c.EVENT_EXTERNAL_MESSAGE => diRclMessage(C, ev),
                else => {},
            }
        }

        if (flush) {
            var tmp: [256]u8 = undefined;
            _ = c.read(pfd.fd, &tmp, 256);
        }

        var ticks = c.shmifsrv_monotonic_tick(null);
        while (!dead and ticks > 0) : (ticks -= 1) {
            _ = c.shmifsrv_tick(C.C);
        }
    }

    // Teardown
    active_clients.sync.lock();

    if (C.tunnel != null) {
        var drop_ev = c.struct_arcan_event.zeroes();
        drop_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        drop_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
        @memcpy(drop_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0.."a12:drop_tunnel=1".len], "a12:drop_tunnel=1");
        _ = c.shmifsrv_enqueue_event(C.tunnel.?.C, &drop_ev, -1);
        C.tunnel = null;
    }

    // Unlink from list
    if (C.prev) |prev| prev.next = C.next;
    if (C.next) |next| next.prev = C.prev;

    // Source-locked reference leaf
    if (C.ref_id != 0) {
        if (dirsrv_locked_numid_appl(@intCast(C.in_appl))) |appl| {
            if (appl.server_tag) |tag_ptr| {
                const rs: *c.struct_runner_state = @ptrCast(@alignCast(tag_ptr));
                _ = pthread_mutex_lock(&rs.lock);
                c.anet_directory_lua_notify_source(
                    appl, &C.identity, "leave", C.ref_id);
                _ = pthread_mutex_unlock(&rs.lock);
            }
        }
        active_clients.sync.unlock();
        c.shmifsrv_free(C.C, 1);
        _ = alloc.destroy(C);
        return;
    }

    // Broadcast loss
    var loss_ev = C.petname;
    loss_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 0;
    if (loss_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[0] != 0) {
        _ = tagOutboundName(&loss_ev, C.pubk[0..32]);
        var cur: [*c]c.struct_dircl = active_clients.root.next;
        while (cur != null) {
            const peer: *c.struct_dircl = @ptrCast(cur);
            cur = peer.next;
            std.debug.assert(peer != C);
            _ = c.shmifsrv_enqueue_event(peer.C, &loss_ev, -1);
        }
    }

    if (C.lua_cb != LUA_NOREF) {
        var lw: [32:0]u8 = undefined;
        c.shmifsrv_last_words(C.C, &lw, 32);
        var lua_ev = c.struct_dirlua_event{
            .kind = c.DIRLUA_EVENT_LOST,
            .msg  = &lw,
        };
        c.anet_directory_lua_event(C, &lua_ev);
    }

    c.anet_directory_lua_unregister(C);
    active_clients.sync.unlock();

    c.shmifsrv_free(C.C, 1);
    alloc.destroy(C);
}

fn workerThreadFn(C: *c.struct_dircl) void {
    dirclProcess(C);
}

// Index rebuild

fn rebuildIndex() void {
    // Free previous blob
    if (active_clients.dirlist) |old| {
        alloc.free(old);
        active_clients.dirlist = null;
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);

    const opts = active_clients.opts orelse return;
    var cur: ?*c.struct_appl_meta = &opts.dir;

    while (cur) |entry| : (cur = entry.next) {
        if (entry.appl.name[0] == 0) continue;
        const line = std.fmt.allocPrint(alloc,
            "kind=appl:name={s}:id={d}:size={d}" ++
            ":categories={d}:hash={x}{x}{x}{x}" ++
            ":timestamp={d}:description={s}\n",
            .{
                std.mem.sliceTo(&entry.appl.name, 0),
                entry.identifier,
                entry.buf_sz,
                entry.categories,
                entry.hash[0], entry.hash[1], entry.hash[2], entry.hash[3],
                entry.update_ts,
                std.mem.sliceTo(&entry.appl.short_descr, 0),
            },
        ) catch return;
        defer alloc.free(line);
        buf.appendSlice(alloc, line) catch return;
    }

    active_clients.dirlist = buf.toOwnedSlice(alloc) catch return;
}

// Public API

pub export fn anet_directory_shmifsrv_set(opts: *c.struct_anet_dirsrv_opts) void {
    var first = struct { var v: bool = true; }.v;
    active_clients.sync.lock();
    defer active_clients.sync.unlock();

    active_clients.opts = opts;

    if (opts.dir.handle != null or opts.dir.buf != null) {
        rebuildIndex();

        if (!first) {
            var cur: [*c]c.struct_dircl = active_clients.root.next;
            while (cur != null) : (cur = cur.*.next) {
                dirlistToWorker(cur);
            }
        }
        first = false;
    }
}

pub export fn anet_directory_shmifsrv_thread(
    cl: *c.struct_shmifsrv_client,
    S: *c.struct_a12_state,
    linktype: c_int,
) ?*c.struct_dircl {
    const newent = alloc.create(c.struct_dircl) catch return null;
    newent.* = std.mem.zeroes(c.struct_dircl);
    newent.C        = cl;
    newent.in_appl  = 0;
    newent.lua_cb   = LUA_NOREF;
    newent.type     = c.ROLE_SINK;

    // Initialise endpoint event skeleton
    newent.endpoint.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    newent.endpoint.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;

    const endpoint = c.a12_get_endpoint(S);
    if (endpoint) |ep| {
        var tmp: [16]u8 = undefined;
        if (c.inet_pton(c.AF_INET, ep, &tmp) == 1) {
            newent.endpoint.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space = 3;
        } else if (c.inet_pton(c.AF_INET6, ep, &tmp) == 1) {
            newent.endpoint.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space = 4;
        }
        _ = c.snprintf(
            &newent.endpoint.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name,
            newent.endpoint.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name.len,
            "%s", ep);
    }

    active_clients.sync.lock();
    var cur: *c.struct_dircl = &active_clients.root;
    while (cur.next) |nx| cur = nx;
    cur.next   = newent;
    newent.prev = cur;

    newent.dir_link     = linktype == c.DIRLINK_UNIFIED;
    newent.dir_ref      = linktype == c.DIRLINK_REFERENCE;
    newent.dir_resolver = linktype == c.DIRLINK_RESOLVER;
    active_clients.sync.unlock();

    // Route through libc pthread_create directly — std.Thread.spawn has a
    // comptime gate against single_threaded, which the SH aarch64 backend
    // forces on. Honors the 4 MB stack size via pthread_attr_setstacksize.
    var attr: libc.pthread_attr_t = undefined;
    _ = libc.pthread_attr_init(&attr);
    defer _ = libc.pthread_attr_destroy(&attr);
    _ = libc.pthread_attr_setstacksize(&attr, 4 * 1024 * 1024);
    var thread: libc.pthread_t = 0;
    if (libc.pthread_create(&thread, &attr, pthreadWorkerEntry, @ptrCast(newent)) != 0) {
        active_clients.sync.lock();
        cur.next = null;
        active_clients.sync.unlock();
        alloc.destroy(newent);
        return null;
    }
    _ = libc.pthread_detach(thread);

    return newent;
}

fn pthreadWorkerEntry(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    workerThreadFn(@ptrCast(@alignCast(arg.?)));
    return null;
}

// Report helpers

pub export fn dirsrv_flush_report(appl: [*:0]const u8) void {
    var ref: usize = 0;
    var outk: [32]u8 = undefined;
    var fnbuf: [64:0]u8 = undefined;
    _ = c.snprintf(&fnbuf, fnbuf.len, "%s.debug", appl);

    while (c.a12helper_keystore_enumerate(&ref, &outk)) {
        _ = c.a12helper_keystore_stateunlink(&outk, &fnbuf);
    }
}

pub export fn dirsrv_build_report(appl: [*:0]const u8) c_int {
    var ref: usize = 0;
    var outk: [32]u8 = undefined;
    var fnbuf: [64:0]u8 = undefined;
    _ = c.snprintf(&fnbuf, fnbuf.len, "%s.debug", appl);

    var out_buf: std.ArrayList(u8) = .empty;
    defer out_buf.deinit(alloc);

    while (c.a12helper_keystore_enumerate(&ref, &outk)) {
        const fd = c.a12helper_keystore_statestore(&outk, &fnbuf, 0, "r");
        if (fd == -1) continue;

        // Avoid c.struct_stat — musl timespec is opaque in translate-c.
        const sbuf = std.posix.fstat(fd) catch { _ = c.close(fd); continue; };

        const fin = c.fdopen(fd, "r") orelse { _ = c.close(fd); continue; };
        defer _ = c.fclose(fin);

        var b64_report_sz: usize = 0;
        const b64 = c.a12helper_tob64(&outk, 32, &b64_report_sz);
        defer c.free(b64);
        const b64_z: [*:0]u8 = @ptrCast(b64 orelse continue);
        const hdr = std.fmt.allocPrint(alloc, "source={s}:length={d}\n",
            .{ std.mem.span(b64_z), sbuf.size + 1 }) catch return -1;
        defer alloc.free(hdr);
        out_buf.appendSlice(alloc, hdr) catch return -1;

        while (c.feof(fin) == 0) {
            var chunk: [4096]u8 = undefined;
            const nr = c.fread(&chunk, 1, chunk.len, fin);
            if (nr == 0) break;
            out_buf.appendSlice(alloc, chunk[0..nr]) catch return -1;
        }
        out_buf.append(alloc, '\n') catch return -1;
    }

    const owned = out_buf.toOwnedSlice(alloc) catch return -1;
    defer alloc.free(owned);
    return c.buf_memfd(owned.ptr, owned.len);
}

// Source mask

pub export fn dirsrv_set_source_mask(
    pubk: *[32]u8,
    applid: c_int,
    identity: *[16]u8,
    dst_pubk: *[32]u8,
) void {
    const m = alloc.create(SourceMask) catch return;
    m.* = SourceMask{
        .applid  = applid,
        .pubk    = pubk.*,
        .identity = identity.*,
        .dstpubk  = dst_pubk.*,
        .next    = null,
    };

    var cur = &active_clients.masks;
    while (cur.*) |*next| cur = &next.*.next;
    cur.* = m;
}

// Revert

pub export fn anet_directory_srv_revert(id: u16, steps: c_int, mask: c_int) bool {
    _ = steps;
    var rv = false;

    active_clients.sync.lock();

    const appl = dirsrv_locked_numid_appl(id) orelse {
        active_clients.sync.unlock();
        return false;
    };

    // REVERT_STEP_APPL: swap .fap ↔ .fap.old on disk
    if (mask & c.REVERT_STEP_APPL != 0) {
        const name = std.mem.sliceTo(&appl.appl.name, 0);

        var extbuf: [64:0]u8 = undefined;
        var tmpbuf: [64:0]u8 = undefined;
        var basebuf: [64:0]u8 = undefined;

        _ = c.snprintf(&extbuf,  extbuf.len,  "%s.fap.old", name.ptr);
        _ = c.snprintf(&tmpbuf,  tmpbuf.len,  "%s.fap.tmp", name.ptr);
        _ = c.snprintf(&basebuf, basebuf.len, "%s.fap",     name.ptr);

        const dfd = active_clients.opts.?.basedir;
        // Avoid c.struct_stat — musl timespec is opaque in translate-c.
        const sbuf = std.posix.fstatat(dfd, std.mem.span(@as([*:0]const u8, @ptrCast(&extbuf))), 0) catch {
            active_clients.sync.unlock();
            return false;
        };
        _ = sbuf;

        const pfd = c.openat(dfd, &extbuf, c.O_RDONLY);
        if (pfd == -1) {
            active_clients.sync.unlock();
            return false;
        }

        const pfile = c.fdopen(pfd, "r") orelse {
            _ = c.close(pfd);
            active_clients.sync.unlock();
            return false;
        };

        var buf_ptr: [*c]u8 = null;
        var buf_sz: usize = 0;
        const fpek = c.file_to_membuf(pfile, &buf_ptr, &buf_sz);
        _ = c.fclose(pfile);
        if (fpek == null) {
            active_clients.sync.unlock();
            return false;
        }

        // Recalculate transfer hash
        var hasher: c.blake3_hasher = undefined;
        c.blake3_hasher_init(&hasher);
        c.blake3_hasher_update(&hasher, buf_ptr, buf_sz);
        c.blake3_hasher_finalize(&hasher, @ptrCast(&appl.hash), 4);

        c.free(appl.buf);
        appl.buf    = buf_ptr;
        appl.buf_sz = buf_sz;

        // .fap -> .fap.tmp, .fap.old -> .fap, .fap.tmp -> .fap.old
        _ = c.renameat(dfd, &basebuf, dfd, &tmpbuf);
        _ = c.renameat(dfd, &extbuf,  dfd, &basebuf);
        _ = c.renameat(dfd, &tmpbuf,  dfd, &extbuf);

        // Notify clients about changed index (must drop lock around the call)
        active_clients.sync.unlock();
        anet_directory_shmifsrv_set(active_clients.opts.?);
        active_clients.sync.lock();

        rv = true;
    }

    // REVERT_STEP_CTRL: flip TEMP → PRIMARY and notify script VM
    if (mask & c.REVERT_STEP_CTRL != 0) {
        if (appl.server_appl == c.SERVER_APPL_TEMP) {
            appl.server_appl = c.SERVER_APPL_PRIMARY;
            c.anet_directory_lua_update(appl, -1);
            rv = true;
        }
    }

    active_clients.sync.unlock();
    return rv;
}

// Directory scan

fn tryApplController(d_name: [*:0]const u8, dfd: c_int) bool {
    if (dfd <= 0) return false;
    const name = std.mem.span(d_name);
    // Build "name/name.lua" relative path
    var pathbuf: [256]u8 = undefined;
    const path = std.fmt.bufPrintZ(&pathbuf, "{s}/{s}.lua", .{ name, name }) catch return false;
    const scriptfd = c.openat(dfd, path.ptr, c.O_RDONLY);
    if (scriptfd != -1) {
        _ = c.close(scriptfd);
        return true;
    }
    return false;
}

pub export fn anet_directory_srv_scan(opts: *c.struct_anet_dirsrv_opts) void {
    active_clients.sync.lock();
    defer active_clients.sync.unlock();

    const dst_root: *c.struct_appl_meta = &opts.dir;
    var dst = dst_root;

    const fd = c.dup(opts.basedir);
    _ = c.lseek(fd, 0, c.SEEK_SET);
    const dir = c.fdopendir(fd) orelse return;
    defer _ = c.closedir(dir);

    opts.dir_count = 0;

    while (true) {
        const ent_ptr = c.readdir(dir) orelse break;
        const ent = ent_ptr.*;
        const d_name = std.mem.span(@as([*:0]const u8, @ptrCast(&ent.d_name)));
        const nlen = d_name.len;

        if (nlen >= 18 or
            std.mem.eql(u8, d_name, "..") or
            std.mem.eql(u8, d_name, ".")) continue;

        // Avoid c.struct_stat — musl timespec is opaque in translate-c.
        const sbuf = std.posix.fstatat(fd, std.mem.span(@as([*:0]const u8, @ptrCast(&ent.d_name))), 0) catch continue;

        if ((sbuf.mode & std.posix.S.IFMT) == std.posix.S.IFDIR) {
            const dfd2 = c.openat(fd, &ent.d_name, c.O_DIRECTORY);
            if (dfd2 == -1) continue;
            defer _ = c.close(dfd2);

            if (!c.build_appl_pkg(@ptrCast(@constCast(&ent.d_name)), dst, dfd2, null)) continue;

            dst.identifier  = @intCast(1 + opts.dir_count);
            opts.dir_count += 1;
            dst.server_appl = c.SERVER_APPL_NONE;

            if (tryApplController(@ptrCast(&ent.d_name), opts.appl_server_temp_dfd)) {
                dst.server_appl = c.SERVER_APPL_TEMP;
            } else if (tryApplController(@ptrCast(&ent.d_name), opts.appl_server_dfd)) {
                dst.server_appl = c.SERVER_APPL_PRIMARY;
            }

            dst = dst.next orelse continue;
            continue;
        }

        if ((sbuf.mode & std.posix.S.IFMT) != std.posix.S.IFREG or nlen < 5) continue;
        if (!std.mem.eql(u8, d_name[nlen - 4 ..], ".fap")) continue;

        const pfd = c.openat(fd, &ent.d_name, c.O_RDONLY);
        if (pfd == -1) continue;
        const pfile = c.fdopen(pfd, "r") orelse { _ = c.close(pfd); continue; };

        var buf_ptr: [*c]u8 = null;
        var buf_sz: usize = 0;
        const fpek = c.file_to_membuf(pfile, &buf_ptr, &buf_sz);
        if (fpek == null) { _ = c.fclose(pfile); continue; }
        defer _ = c.fclose(fpek);
        defer _ = c.fclose(pfile);

        var nullsig = [_]u8{0} ** c.SIG_PUBK_SZ;
        var errmsg: [*c]const u8 = null;
        const name_ptr = c.verify_appl_pkg(buf_ptr, buf_sz, &nullsig, &dst.sig_pubk, &errmsg);
        if (name_ptr == null) continue;

        // Copy name up to '.'
        const name_str = std.mem.span(@as([*:0]const u8, @ptrCast(name_ptr)));
        var ni: usize = 0;
        while (ni < dst.appl.name.len - 1 and ni < name_str.len and name_str[ni] != '.') : (ni += 1) {
            dst.appl.name[ni] = name_str[ni];
        }

        dst.buf_sz     = buf_sz;
        dst.buf        = buf_ptr;
        dst.identifier = @intCast(1 + opts.dir_count);
        opts.dir_count += 1;

        var hasher: c.blake3_hasher = undefined;
        c.blake3_hasher_init(&hasher);
        c.blake3_hasher_update(&hasher, buf_ptr, buf_sz);
        c.blake3_hasher_finalize(&hasher, @ptrCast(&dst.hash), 4);

        if (tryApplController(@ptrCast(&dst.appl.name), opts.appl_server_temp_dfd)) {
            dst.server_appl = c.SERVER_APPL_TEMP;
        } else if (tryApplController(@ptrCast(&dst.appl.name), opts.appl_server_dfd)) {
            dst.server_appl = c.SERVER_APPL_PRIMARY;
        }

        const next = alloc.create(c.struct_appl_meta) catch continue;
        next.* = std.mem.zeroes(c.struct_appl_meta);
        dst.next = next;
        dst = next;
    }
}

// Ephemeral source

pub export fn anet_directory_ephemeral_source(
    id: u16,
    name: [*:0]const u8,
    dstname: [*:0]const u8,
    ref_id: usize,
) bool {
    var rv = false;
    active_clients.sync.lock();

    const C = dirsrv_find_cl_ident(@intCast(id), dstname, true) orelse {
        active_clients.sync.unlock();
        return false;
    };

    const appl = dirsrv_locked_numid_appl(id) orelse {
        active_clients.sync.unlock();
        return false;
    };
    const tag_ptr = appl.server_tag orelse {
        active_clients.sync.unlock();
        return false;
    };

    const cur: *c.struct_runner_state = @ptrCast(@alignCast(tag_ptr));
    _ = pthread_mutex_lock(&cur.lock);

    for (&cur.pending_sources) |*slot| {
        if (std.mem.eql(u8, &slot.pubk, C.pubk[0..32])) {
            c.anet_directory_lua_notify_source(
                appl, @ptrCast(&slot.force_ident), "fail", slot.ref_id);
            _ = c.snprintf(@ptrCast(&slot.force_ident), slot.force_ident.len, "%s", name);
            rv = true;
            _ = pthread_mutex_unlock(&cur.lock);
            active_clients.sync.unlock();
            return rv;
        }
    }

    const nullk = [_]u8{0} ** 32;
    for (&cur.pending_sources) |*slot| {
        if (std.mem.eql(u8, &slot.pubk, &nullk)) {
            @memcpy(slot.pubk[0..32], C.pubk[0..32]);
            _ = c.snprintf(&slot.force_ident, slot.force_ident.len, "%s", name);
            slot.ref_id = ref_id;
            rv = true;
            break;
        }
    }

    _ = pthread_mutex_unlock(&cur.lock);
    active_clients.sync.unlock();
    return rv;
}
