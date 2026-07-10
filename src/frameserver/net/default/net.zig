// Zig port of src/frameserver/net/default/net.c — afsrv_net frameserver
// entry: argument parsing, connection/discovery dispatch for net clients.
// License: 3-Clause BSD (same as upstream)

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, a12_helper.h,
// anet_helper.h, directory.h, frameserver.h, string.h, stdio.h, stdlib.h, unistd.h,
// fcntl.h, signal.h, errno.h })` block. Keeps the `c.X` spellings used below. Each
// alias routes to the appropriate hand-written replacement module (zero `@cImport`
// left).
const shmif_types = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // ── shmif — event types, segment ids, context, commands ────────────────
    pub const arcan_event = shmif_types.arcan_event;
    pub const struct_arcan_shmif_cont = shmif_types.struct_arcan_shmif_cont;
    pub const struct_arg_arr = shmif_types.struct_arg_arr;
    pub const arcan_shmif_acquire = shmif_types.arcan_shmif_acquire;
    pub const arcan_shmif_acquireloop = shmif_types.arcan_shmif_acquireloop;
    pub const arcan_shmif_drop = shmif_types.arcan_shmif_drop;
    pub const arcan_shmif_enqueue = shmif_types.arcan_shmif_enqueue;
    pub const arcan_shmif_eventstr = shmif_types.arcan_shmif_eventstr;
    pub const arcan_shmif_poll = shmif_types.arcan_shmif_poll;
    pub const arcan_shmif_primary = shmif_types.arcan_shmif_primary;
    pub const arcan_shmif_setprimary = shmif_types.arcan_shmif_setprimary;
    pub const EVENT_EXTERNAL = shmif_types.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = shmif_types.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_EXTERNAL_MESSAGE = shmif_types.EVENT_EXTERNAL_MESSAGE;
    pub const EVENT_EXTERNAL_NETSTATE = shmif_types.EVENT_EXTERNAL_NETSTATE;
    pub const EVENT_EXTERNAL_SEGREQ = shmif_types.EVENT_EXTERNAL_SEGREQ;
    pub const EVENT_EXTERNAL_STREAMSTATUS = shmif_types.EVENT_EXTERNAL_STREAMSTATUS;
    pub const EVENT_TARGET = shmif_types.EVENT_TARGET;
    pub const SEGID_HANDOVER = shmif_types.SEGID_HANDOVER;
    pub const SEGID_UNKNOWN = shmif_types.SEGID_UNKNOWN;
    pub const SHMIF_INPUT = shmif_types.SHMIF_INPUT;
    pub const SHMIF_NOACTIVATE = shmif_types.SHMIF_NOACTIVATE;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif_types.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif_types.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_EXIT = shmif_types.TARGET_COMMAND_EXIT;
    pub const TARGET_COMMAND_MESSAGE = shmif_types.TARGET_COMMAND_MESSAGE;
    pub const TARGET_COMMAND_NEWSEGMENT = shmif_types.TARGET_COMMAND_NEWSEGMENT;
    pub const TARGET_COMMAND_REQFAIL = shmif_types.TARGET_COMMAND_REQFAIL;

    // ── a12 — state machine, BTYPE, ROLE, extern fns ───────────────────────
    pub const A12_BTYPE_APPL = a12.A12_BTYPE_APPL;
    pub const A12_BTYPE_STATE = a12.A12_BTYPE_STATE;
    pub const a12_channel_bprogress_hook = a12.a12_channel_bprogress_hook;
    pub const a12_channel_enqueue = a12.a12_channel_enqueue;
    pub const a12_free = a12.a12_free;
    pub const a12_remote_mode = a12.a12_remote_mode;
    pub const a12_request_dynamic_resource = a12.a12_request_dynamic_resource;
    pub const a12_request_file = a12.a12_request_file;
    pub const a12_set_bhandler = a12.a12_set_bhandler;
    pub const a12_set_destination_raw = a12.a12_set_destination_raw;
    pub const a12_set_session = a12.a12_set_session;
    pub const a12int_get_directory = a12.a12int_get_directory;
    pub const a12int_request_dirlist = a12.a12int_request_dirlist;
    pub const ROLE_DIR = a12.ROLE_DIR;
    pub const ROLE_PROBE = a12.ROLE_PROBE;
    pub const ROLE_SINK = a12.ROLE_SINK;
    pub const ROLE_SOURCE = a12.ROLE_SOURCE;
    // bhandler_meta/res — two parallel definitions exist (a12_types and
    // anet_types). We use anet's because dircl_xfer_complete and
    // anet_directory_cl_bhandler (the code's primary consumers) are declared
    // against anet's. a12_set_bhandler takes the a12-typed callback, so the
    // callback pointer is cast at the a12_set_bhandler call site.
    pub const struct_a12_bhandler_meta = anet.struct_a12_bhandler_meta;
    pub const struct_a12_bhandler_res = anet.struct_a12_bhandler_res;
    pub const struct_a12_context_options = a12.struct_a12_context_options;
    pub const struct_a12_dynreq = a12.struct_a12_dynreq;
    pub const struct_a12_state = a12.struct_a12_state;
    // struct_a12_unpack_cfg — anet_types declares this opaque; the real
    // layout lives in a12_types. Use a12's so the literal field init works.
    pub const struct_a12_unpack_cfg = a12.struct_a12_unpack_cfg;
    pub const struct_appl_meta = a12.struct_appl_meta;
    pub const struct_pk_response = a12.struct_pk_response;

    // ── anet / helper — keystore, discover, directory, lua init ────────────
    pub const A12HELPER_PROVIDER_BASEDIR = anet.A12HELPER_PROVIDER_BASEDIR;
    pub const a12helper_a12srv_shmifcl = anet.a12helper_a12srv_shmifcl;
    pub const a12helper_discover_ipcfg = anet.a12helper_discover_ipcfg;
    pub const a12helper_fromb64 = anet.a12helper_fromb64;
    pub const a12helper_keystore_accepted = anet.a12helper_keystore_accepted;
    pub const a12helper_keystore_dirfd = anet.a12helper_keystore_dirfd;
    pub const a12helper_keystore_hostkey = anet.a12helper_keystore_hostkey;
    pub const a12helper_keystore_open = anet.a12helper_keystore_open;
    pub const a12helper_keystore_tags = anet.a12helper_keystore_tags;
    pub const anet_cl_setup = anet.anet_cl_setup;
    pub const anet_client_lua_getpath = anet.anet_client_lua_getpath;
    pub const anet_directory_cl_bhandler = anet.anet_directory_cl_bhandler;
    pub const anet_directory_ioloop = anet.anet_directory_ioloop;
    pub const anet_discover_listen_beacon = anet.anet_discover_listen_beacon;
    pub const anet_discover_send_beacon = anet.anet_discover_send_beacon;
    pub const anet_lua_init = anet.anet_lua_init;
    pub const arg_lookup = shmif_types.arg_lookup;
    pub const arcan_shmif_last_words = shmif_types.arcan_shmif_last_words;
    pub const arcan_shmif_wait = shmif_types.arcan_shmif_wait;
    pub const arcan_shmif_handover_exec_pipe = shmif_types.arcan_shmif_handover_exec_pipe;
    pub const dircl_apphash_cached = anet.dircl_apphash_cached;
    pub const dircl_source_handler = anet.dircl_source_handler;
    pub const dircl_xfer_complete = anet.dircl_xfer_complete;
    pub const struct_anet_cl_connection = anet.struct_anet_cl_connection;
    pub const struct_anet_dircl_opts = anet.struct_anet_dircl_opts;
    pub const struct_anet_discover_opts = anet.struct_anet_discover_opts;
    pub const struct_anet_options = anet.struct_anet_options;
    pub const struct_directory_meta = anet.struct_directory_meta;
    pub const struct_global_cfg = anet.struct_global_cfg;
    pub const struct_ioloop_shared = anet.struct_ioloop_shared;
    pub const struct_keystore_provider = anet.struct_keystore_provider;

    // ── libc — stdio, process, network helpers ─────────────────────────────
    pub const access = libc.access;
    pub const asprintf = libc.asprintf;
    pub const close = libc.close;
    pub const FILE = libc.FILE;
    pub const fdopen = libc.fdopen;
    pub const fprintf = libc.fprintf;
    pub const getenv = libc.getenv;
    pub const memcmp = libc.memcmp;
    pub const memcpy = libc.memcpy;
    pub const open = libc.open;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const O_RDWR = libc.O_RDWR;
    pub const pid_t = libc.pid_t;
    pub const pipe = libc.pipe;
    pub const sleep = libc.sleep;
    pub const snprintf = libc.snprintf;
    pub const strcmp = libc.strcmp;
    pub const strdup = libc.strdup;
    pub const strlen = libc.strlen;
    pub const strncmp = libc.strncmp;
    pub const strsep = libc.strsep;
    pub const strtoul = libc.strtoul;
    // stderr/stdout are runtime `extern "c" var`; redeclare here (linker
    // merges across modules) so `c.stderr` / `c.stdout` work at call sites.
    pub extern "c" var stderr: *libc.FILE;
    pub extern "c" var stdout: *libc.FILE;
    pub const EXIT_FAILURE = libc.EXIT_FAILURE;
    pub const EXIT_SUCCESS = libc.EXIT_SUCCESS;
    pub const SIGCHLD = libc.SIGCHLD;
    pub const SIGPIPE = libc.SIGPIPE;
    pub const X_OK = libc.X_OK;
};

extern "c" fn shutdown(sockfd: c_int, how: c_int) c_int;
const SHUT_RDWR: c_int = 2;

// POSIX SIG_IGN can't be translated by translate-c (it's a macro casting
// an integer to a function pointer). Provide our own.
const SigHandler = ?*align(1) const fn (c_int) callconv(.c) void;
const SIG_IGN: SigHandler = @ptrFromInt(1);
extern "c" fn signal(signo: c_int, handler: SigHandler) SigHandler;

// LOG helper

fn LOG(comptime fmt: [*:0]const u8, args: anytype) void {
    _ = @call(.auto, c.fprintf, .{ c.stderr, @as([*c]const u8, fmt) } ++ args);
}

// enums / constants

const TRUST_KNOWN: c_int = 0;
const TRUST_VERIFY_UNKNOWN: c_int = 1;
const TRUST_TRANSITIVE: c_int = 2;

// Global config — owned by src/a12/net/net.zig when arcan-net is linked
// into the same binary (MAY: `may net`); we share that storage via extern
// to avoid duplicate-symbol link errors.

extern var global: c.struct_global_cfg;

const GlobalPending = struct {
    req_id: usize = 0,
};
var global_pending: GlobalPending = .{};

// Helpers

fn flush_shmif(C: *c.struct_arcan_shmif_cont) bool {
    var rv: c_int = 0;
    var ev: c.arcan_event = undefined;
    while (true) {
        rv = c.arcan_shmif_poll(C, &ev);
        if (rv <= 0) break;
        if (ev.unnamed_0.unnamed_0.category == c.EVENT_TARGET and
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_EXIT)
        {
            return false;
        }
    }
    return rv == 0;
}

fn get_keystore(
    C: *c.struct_arcan_shmif_cont,
    prov: *c.struct_keystore_provider,
) bool {
    const Static = struct {
        var ks: c.struct_keystore_provider = blk: {
            var k = std.mem.zeroes(c.struct_keystore_provider);
            k.unnamed_0.directory.dirfd = -1;
            break :blk k;
        };
    };

    if (Static.ks.unnamed_0.directory.dirfd == -1) {
        Static.ks.type = c.A12HELPER_PROVIDER_BASEDIR;
        var err: [*c]const u8 = null;
        Static.ks.unnamed_0.directory.dirfd = c.a12helper_keystore_dirfd(&err);
        if (Static.ks.unnamed_0.directory.dirfd == -1) {
            c.arcan_shmif_last_words(C, "couldn't open keystore");
            return false;
        }
    }

    prov.* = Static.ks;
    return true;
}

fn key_auth_local(
    S: ?*c.struct_a12_state,
    pk: [*c]u8,
    tag: ?*anyopaque,
) callconv(.c) c.struct_pk_response {
    _ = S;
    _ = tag;
    var auth = std.mem.zeroes(c.struct_pk_response);
    var tmp: [*c]u8 = null;
    var tmpport: u16 = 0;

    const pk_slice: *const [32]u8 = @ptrCast(pk);
    const trusted = c.a12helper_keystore_accepted(pk_slice, global.trust_domain);
    if (trusted != null or global.soft_auth) {
        if (trusted == null) LOG("accept_soft_unknown\n", .{});
        var key_priv: [32]u8 = undefined;
        auth.authentic = true;
        _ = c.a12helper_keystore_hostkey("default", 0, &key_priv, &tmp, &tmpport);
        c.a12_set_session(&auth, pk_slice, &key_priv);
    }

    return auth;
}

// Discovery: broadcast

fn discover_broadcast(
    C: *c.struct_arcan_shmif_cont,
    arg: ?*c.struct_arg_arr,
    trust: c_int,
) c_int {
    _ = trust;
    var ks = std.mem.zeroes(c.struct_keystore_provider);
    ks.unnamed_0.directory.dirfd = -1;

    if (!get_keystore(C, &ks) or !c.a12helper_keystore_open(&ks)) {
        c.arcan_shmif_last_words(C, "couldn't open keystore");
        return c.EXIT_FAILURE;
    }

    var cfg = std.mem.zeroes(c.struct_anet_discover_opts);
    cfg.limit = -1;
    cfg.timesleep = 10;

    var ipv6_str: [*c]const u8 = null;
    _ = c.arg_lookup(arg, "ipv6", 0, &ipv6_str);
    cfg.ipv6 = @ptrCast(ipv6_str);

    const err = c.a12helper_discover_ipcfg(&cfg, true);
    if (err != null) {
        c.arcan_shmif_last_words(C, err);
        LOG("%s", .{err});
        return c.EXIT_FAILURE;
    }

    while (c.anet_discover_send_beacon(&cfg) and flush_shmif(C)) {}
    return c.EXIT_SUCCESS;
}

// Discovery: passive (listen for beacons)

fn on_disc_shmif(C: *c.struct_arcan_shmif_cont) callconv(.c) bool {
    var pv: c_int = 0;
    var ev: c.arcan_event = undefined;
    while (true) {
        pv = c.arcan_shmif_poll(C, &ev);
        if (pv <= 0) break;
        if (ev.unnamed_0.unnamed_0.category == c.EVENT_TARGET and
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_EXIT)
        {
            c.arcan_shmif_drop(C);
            return false;
        }
    }
    if (pv == -1) {
        c.arcan_shmif_drop(C);
        return false;
    }
    return true;
}

fn on_disc_beacon(
    C: *c.struct_arcan_shmif_cont,
    kpub: [*c]const u8,
    nonce: [*c]const u8,
    tag_in: [*c]const u8,
    addr: [*c]u8,
) callconv(.c) bool {
    _ = nonce;
    var nullk = std.mem.zeroes([32]u8);
    if (c.memcmp(kpub, &nullk, 32) == 0) {
        LOG("bad_beacon:source=%s", .{addr});
        return true;
    }

    var ev = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_NETSTATE));
    ev.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 1;

    var tag = tag_in;
    if (tag != null) {
        if (c.strcmp(tag, "outbound") == 0) return true;
        if (c.strncmp(tag, "outbound-", 9) == 0) {
            tag += 9;
        }

        _ = c.snprintf(
            &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name,
            @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name)),
            "%s",
            tag,
        );
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 2;
        _ = c.arcan_shmif_enqueue(C, &ev);
    }

    _ = c.snprintf(
        &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name,
        @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name)),
        "%s",
        addr,
    );
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 1;
    _ = c.arcan_shmif_enqueue(C, &ev);
    return true;
}

fn discover_passive(
    C: *c.struct_arcan_shmif_cont,
    arg: ?*c.struct_arg_arr,
    trust: c_int,
) c_int {
    _ = trust;
    var ks = std.mem.zeroes(c.struct_anet_options);
    ks.keystore.unnamed_0.directory.dirfd = -1;
    if (!get_keystore(C, &ks.keystore) or !c.a12helper_keystore_open(&ks.keystore)) {
        c.arcan_shmif_last_words(C, "couldn't open keystore");
        return c.EXIT_FAILURE;
    }

    var cfg = std.mem.zeroes(c.struct_anet_discover_opts);
    cfg.discover_beacon = @ptrCast(&on_disc_beacon);
    cfg.on_shmif = @ptrCast(&on_disc_shmif);
    cfg.C = C;

    var ipv6_str: [*c]const u8 = null;
    _ = c.arg_lookup(arg, "ipv6", 0, &ipv6_str);
    cfg.ipv6 = @ptrCast(ipv6_str);
    _ = c.a12helper_discover_ipcfg(&cfg, true);

    c.anet_discover_listen_beacon(&cfg);
    return c.EXIT_SUCCESS;
}

// Discovery: sweep (probe known tags)

const Listent = extern struct {
    name: [64]u8 = std.mem.zeroes([64]u8),
    seen: bool = false,
    next: ?*Listent = null,
};

const TagOpt = extern struct {
    C: ?*c.struct_arcan_shmif_cont = null,
    delay: c_int = 0,
    alive: bool = false,
    key: [*c]const u8 = null,
    first: ?*Listent = null,
};

fn reset_seen(head: ?*Listent) void {
    var cur = head;
    while (cur) |n| {
        n.seen = false;
        cur = n.next;
    }
}

fn mark_lost(C: *c.struct_arcan_shmif_cont, first: *?*Listent) void {
    var last: *?*Listent = first;
    var cur_opt = first.*;
    while (cur_opt) |cur| {
        if (!cur.seen) {
            LOG("lost-known: %s\n", .{&cur.name});
            var ev = c.arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_NETSTATE));
            ev.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
            _ = c.snprintf(
                &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name,
                @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name)),
                "%s",
                &cur.name,
            );
            _ = c.arcan_shmif_enqueue(C, &ev);

            last.* = cur.next;
            std.c.free(cur);
            cur_opt = last.*;
        } else {
            last = &cur.next;
            cur_opt = cur.next;
        }
    }
}

fn tagh(name: [*c]const u8, tag_in: ?*anyopaque) callconv(.c) bool {
    const opt: *TagOpt = @ptrCast(@alignCast(tag_in.?));
    var a12opts = std.mem.zeroes(c.struct_a12_context_options);
    a12opts.local_role = c.ROLE_PROBE;
    a12opts.pk_lookup = @ptrCast(&key_auth_local);

    var opts = std.mem.zeroes(c.struct_anet_options);
    opts.key = name;
    opts.opts = &a12opts;

    // null name means end-of-iteration.
    if (name == null) return true;

    LOG("sweep: petname %s\n", .{name});
    if (!get_keystore(opt.C.?, &opts.keystore)) {
        LOG("fail, couldn't access keystore\n", .{});
        return false;
    }

    if (opt.key != null) {
        _ = c.snprintf(&a12opts.secret, @sizeOf(@TypeOf(a12opts.secret)), "%s", opt.key);
        LOG("setting custom secret (****)\n", .{});
    }

    var con = c.anet_cl_setup(&opts);

    if (!flush_shmif(opt.C.?)) {
        opt.alive = false;
        return false;
    }

    if (con.errmsg != null) {
        std.c.free(con.errmsg);
    }

    // connection didn't go through: cleanup and continue
    if (con.fd == -1) {
        cleanup_con(&con, opt.delay);
        return true;
    }

    // already known?
    var cur_pp: *?*Listent = @ptrCast(&opt.first);
    while (cur_pp.*) |entry| {
        if (c.strcmp(&entry.name, name) == 0) {
            _ = c.close(con.fd);
            entry.seen = true;
            LOG("known-seen(%s)\n", .{name});
            cleanup_con_shutdown(&con, opt.delay);
            return true;
        }
        cur_pp = @ptrCast(&entry.next);
    }

    // new entry — record and notify
    const newent: *Listent = @ptrCast(@alignCast(std.c.malloc(@sizeOf(Listent)).?));
    newent.* = .{ .seen = true };
    _ = c.snprintf(&newent.name, 64, "%s", name);
    cur_pp.* = newent;
    LOG("discovered:%s\n", .{name});

    var ev = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_NETSTATE));
    ev.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 1;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type = @intCast(c.a12_remote_mode(con.state));
    _ = c.snprintf(
        &ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name,
        @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name)),
        "%s",
        name,
    );
    _ = c.arcan_shmif_enqueue(opt.C.?, &ev);

    cleanup_con_shutdown(&con, opt.delay);
    return true;
}

fn cleanup_con(con: *c.struct_anet_cl_connection, delay: c_int) void {
    _ = c.a12_free(con.state);
    if (delay != 0) _ = c.sleep(@intCast(delay));
}

fn cleanup_con_shutdown(con: *c.struct_anet_cl_connection, delay: c_int) void {
    if (con.fd != -1) {
        _ = shutdown(con.fd, SHUT_RDWR);
        _ = c.close(con.fd);
    }
    _ = c.a12_free(con.state);
    if (delay != 0) _ = c.sleep(@intCast(delay));
}

fn discover_test(C: *c.struct_arcan_shmif_cont, trust: c_int) c_int {
    _ = trust;
    var step: c_uint = 1;

    const NameArr = @TypeOf(@as(c.arcan_event, undefined).unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name);

    const names = [_][]const u8{ "test_1", "test_2", "test_3", "test_4", "test_3" };
    const types = [_]u8{ 1, 2, 4, 5, 1 | 2 };

    var ev: [5]c.arcan_event = undefined;
    inline for (0..5) |i| {
        ev[i] = c.arcan_event.zeroes();
        ev[i].unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_NETSTATE));
        ev[i].unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 1;
        ev[i].unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type = types[i];
        // zero-init name and copy literal
        var name_buf = std.mem.zeroes(NameArr);
        @memcpy(name_buf[0..names[i].len], names[i]);
        ev[i].unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name = name_buf;
    }

    var found: bool = false;
    while (flush_shmif(C)) {
        _ = c.sleep(step);
        step += 1;
        var i: usize = 0;
        while (i < ev.len) : (i += 1) {
            ev[i].unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = @intFromBool(found);
            _ = c.arcan_shmif_enqueue(C, &ev[i]);
            _ = c.sleep(1);
        }
        found = !found;
    }
    return c.EXIT_SUCCESS;
}

fn discover_sweep(C: *c.struct_arcan_shmif_cont, trust: c_int) c_int {
    _ = trust;
    var tag = TagOpt{ .C = C, .delay = 1, .alive = true };
    const sweep_pause: c_uint = 10;

    var prov: c.struct_keystore_provider = undefined;
    if (!get_keystore(C, &prov)) return c.EXIT_FAILURE;

    if (!c.a12helper_keystore_open(&prov)) {
        c.arcan_shmif_last_words(C, "couldn't open keystore");
        c.arcan_shmif_drop(C);
        return c.EXIT_FAILURE;
    }

    while (flush_shmif(C)) {
        reset_seen(tag.first);
        _ = c.a12helper_keystore_tags(&tagh, @ptrCast(&tag));
        mark_lost(C, @ptrCast(&tag.first));
        _ = c.sleep(sweep_pause);
    }

    c.arcan_shmif_drop(C);
    return c.EXIT_SUCCESS;
}

// Directory client implementation

const DirclMeta = extern struct {
    pending_reqid: c_int = 0,
    pending_reqname: [*c]u8 = null,
    appl: extern struct {
        id: c_int = 0,
        statefd: c_int = 0,
        applfd: c_int = 0,
    } = .{},
    segev: c.arcan_event = c.arcan_event.zeroes(),
};

fn dircl_alloc(
    S: ?*c.struct_a12_state,
    dir: *c.struct_directory_meta,
    name: [*c]const u8,
) callconv(.c) ?*anyopaque {
    _ = S;
    _ = dir;
    _ = name;
    const C = c.arcan_shmif_primary(c.SHMIF_INPUT) orelse return null;

    var req = c.arcan_event.zeroes();
    req.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_SEGREQ));
    req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.segreq.kind = @as(c_uint, @bitCast(c.SEGID_HANDOVER));
    _ = c.arcan_shmif_enqueue(C, &req);

    var acq_event: c.arcan_event = undefined;
    var evpool: [*c]c.arcan_event = null;
    var evpool_sz: isize = 0;

    if (!c.arcan_shmif_acquireloop(C, &acq_event, &evpool, &evpool_sz)) {
        LOG("server rejected allocation\n", .{});
        return null;
    }

    if (evpool_sz != 0) {
        LOG("ignoring_pending:%zu\n", .{evpool_sz});
        std.c.free(evpool);
    }

    const client: *DirclMeta = @ptrCast(@alignCast(C.*.user.?));
    client.segev = acq_event;
    return @ptrCast(client);
}

fn resolve_path(path_in: [*c]u8, fnname: [*c]const u8) [*c]u8 {
    var buf: [4096]u8 = undefined;
    var path = path_in;
    while (true) {
        const dir_opt = c.strsep(&path, ":");
        if (dir_opt == null) break;
        var dir = dir_opt;
        if (dir.* == 0) {
            dir = @constCast(@ptrCast("."));
        }
        if (c.snprintf(&buf, @sizeOf(@TypeOf(buf)), "%s/%s", dir, fnname) >= @sizeOf(@TypeOf(buf))) continue;
        if (c.access(@ptrCast(&buf), c.X_OK) == 0) return c.strdup(&buf);
    }
    return null;
}

fn dircl_exec(
    S: ?*c.struct_a12_state,
    dir: *c.struct_directory_meta,
    name: [*c]const u8,
    tag: ?*anyopaque,
    inf: *c_int,
    outf: *c_int,
) callconv(.c) c.pid_t {
    _ = S;
    _ = dir;
    _ = tag;
    const C = c.arcan_shmif_primary(c.SHMIF_INPUT) orelse return 0;
    const client: *DirclMeta = @ptrCast(@alignCast(C.*.user.?));

    var path = c.getenv("PATH");
    if (path == null) path = @constCast(@ptrCast("."));
    path = c.strdup(path);

    const lwabin = resolve_path(path, "arcan_lwa");
    std.c.free(path);

    if (lwabin == null) {
        LOG("couldn't locate/access arcan_lwa in PATH\n", .{});
        return 0;
    }
    defer std.c.free(lwabin);

    // "./<name>" — build on the stack with a stack buffer large enough.
    var app_buf: [4096]u8 = undefined;
    _ = c.snprintf(&app_buf, app_buf.len, "./%s", name);

    var pstdin: [2]c_int = undefined;
    var pstdout: [2]c_int = undefined;
    if (c.pipe(&pstdin) == -1 or c.pipe(&pstdout) == -1) {
        LOG("Couldn't setup control pipe in arcan handover\n", .{});
        return 0;
    }

    var logfd_str: [16]u8 = undefined;
    _ = c.snprintf(&logfd_str, 16, "LOGFD:%d", pstdout[1]);

    var argv = [_][*c]u8{
        @constCast(@ptrCast("arcan_lwa")),
        @constCast(@ptrCast("--database")),
        @constCast(@ptrCast(":memory:")),
        @constCast(@ptrCast("--monitor")),
        @constCast(@ptrCast("-1")),
        @constCast(@ptrCast("--monitor-out")),
        @ptrCast(&logfd_str),
        @constCast(@ptrCast("--monitor-ctrl")),
        @constCast(@ptrCast("-")),
        @ptrCast(&app_buf),
        null,
    };

    const keys = [_][*:0]const u8{
        "TERM",              "SHELL",              "ARCAN_LOGPATH",
        "HOME",              "ARCAN_RESOURCEPATH", "ARCAN_STATEPATH",
        "XDG_RUNTIME_DIR",   "PATH",
    };
    var envv: [keys.len + 1][*c]u8 = [_][*c]u8{null} ** (keys.len + 1);

    var j: usize = 0;
    var i_k: usize = 0;
    while (i_k < keys.len) : (i_k += 1) {
        const key = keys[i_k];
        const val = c.getenv(@ptrCast(key));
        if (val == null) continue;
        var dst: [*c]u8 = null;
        if (c.asprintf(&dst, "%s=%s", @as([*c]const u8, @ptrCast(key)), val) != -1) {
            envv[j] = dst;
            j += 1;
        }
    }

    var fds: [4][*c]c_int = .{ &pstdin[0], null, null, &pstdout[1] };
    const res = c.arcan_shmif_handover_exec_pipe(
        C,
        client.segev,
        lwabin,
        @ptrCast(&argv),
        @ptrCast(&envv),
        0,
        @ptrCast(&fds),
        4,
    );

    var k: usize = 0;
    while (k < envv.len and envv[k] != null) : (k += 1) {
        std.c.free(envv[k]);
    }

    _ = c.close(pstdin[0]);
    inf.* = pstdin[1];
    outf.* = pstdout[0];
    _ = c.close(pstdout[1]);

    return res;
}

fn dircl_event(
    C: *c.struct_arcan_shmif_cont,
    chid: c_int,
    ev: *c.arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = C;
    _ = chid;
    LOG("event=%s\n", .{c.arcan_shmif_eventstr(ev, null, 0)});

    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));

    if (ev.unnamed_0.unnamed_0.category == c.EVENT_EXTERNAL and
        ev.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_MESSAGE)
    {
        _ = c.arcan_shmif_enqueue(&I.shmif, ev);
        return;
    }

    if (ev.unnamed_0.unnamed_0.category == c.EVENT_TARGET and
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_REQFAIL and
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].uiv == 0xf00f00f)
    {
        var M = std.mem.zeroes(c.struct_a12_bhandler_meta);
        M.type = @as(c_uint, @bitCast(c.A12_BTYPE_STATE));
        c.dircl_xfer_complete(I, M);
    }
}

fn output_progress(
    status: c_int,
    in: usize,
    out_b: usize,
    total: usize,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = out_b;
    const C: *c.struct_arcan_shmif_cont = @ptrCast(@alignCast(tag.?));
    var ev = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_STREAMSTATUS));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.identifier = @intCast(global_pending.req_id);

    switch (status) {
        -1 => {
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.completion = -1.0;
            _ = c.arcan_shmif_enqueue(C, &ev);
            global_pending.req_id = 0;
        },
        0 => {
            if (total != 0) {
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.completion =
                    @as(f32, @floatFromInt(in)) / @as(f32, @floatFromInt(total));
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.frameno = @intCast(in >> 10);
            } else {
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.streaming = 1;
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.frameno = @intCast(in >> 10);
            }
            _ = c.arcan_shmif_enqueue(C, &ev);
        },
        1 => {
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.streaming = 1;
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.frameno = @intCast(in >> 10);
            _ = c.arcan_shmif_enqueue(C, &ev);
        },
        else => {},
    }
}

fn req_id(I: *c.struct_ioloop_shared, M: *c.struct_appl_meta) void {
    const C = c.arcan_shmif_primary(c.SHMIF_INPUT).?;
    const client: *DirclMeta = @ptrCast(@alignCast(C.*.user.?));
    const cbt: *c.struct_directory_meta = @ptrCast(@alignCast(I.cbt));

    global_pending.req_id = M.identifier;

    // Check cache first
    var outname: ?[*:0]u8 = null;
    const cfd = c.dircl_apphash_cached(&M.hash, @ptrCast(&M.appl.name), &outname);
    if (cfd > 0) {
        cbt.appl_out_complete = true;
        cbt.appl_out = c.fdopen(cfd, "r");
        if (cbt.appl_out == null) return;

        if (cbt.clopt.*.block_state) {
            var bh = std.mem.zeroes(c.struct_a12_bhandler_meta);
            bh.type = @as(c_uint, @bitCast(c.A12_BTYPE_APPL));
            c.dircl_xfer_complete(I, bh);
            return;
        }
        c.a12_request_file(I.S, 0, M.identifier, 0xf00f00f, ".state");
        return;
    }

    LOG("shmif:download:%u\n", .{@as(c_uint, M.identifier)});

    c.a12_request_file(I.S, 0, M.identifier, 0xfeedface, "");
    c.a12_channel_bprogress_hook(I.S, 0, 1024 * 1024, &output_progress, @ptrCast(C));

    client.appl.id = M.identifier;
    client.appl.applfd = -1;
    client.appl.statefd = -1;

    _ = c.memcpy(&cbt.appl_hash, &M.hash, 4);
}

fn cl_got_dyn(
    S: ?*c.struct_a12_state,
    dyn_type: u8,
    petname: [*c]const u8,
    state: u8,
    pubk: [*c]u8,
    ns: u16,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = S;
    _ = ns;
    _ = tag;
    const C = c.arcan_shmif_primary(c.SHMIF_INPUT).?;

    var disc = c.arcan_event.zeroes();
    disc.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
    disc.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;
    disc.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type = dyn_type;
    disc.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space = 5;
    disc.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = state;

    _ = c.snprintf(
        &disc.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.unnamed_0.petname,
        16,
        "%s",
        petname,
    );
    _ = c.memcpy(&disc.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.unnamed_0.pubk, pubk, 32);

    _ = c.arcan_shmif_enqueue(C, &disc);
}

fn dircl_dirent(I: *c.struct_ioloop_shared, M_in: [*c]c.struct_appl_meta) callconv(.c) bool {
    const C = c.arcan_shmif_primary(c.SHMIF_INPUT).?;
    const dir: *c.struct_directory_meta = @ptrCast(@alignCast(I.cbt));
    const client: *DirclMeta = @ptrCast(@alignCast(C.*.user.?));

    var M = M_in;
    while (M != null) {
        if (client.pending_reqname != null) {
            if (c.strcmp(&M.*.appl.name, client.pending_reqname) == 0) {
                _ = c.snprintf(&dir.clopt.*.applname, 16, "%s", @as([*c]const u8, @ptrCast(&M.*.appl.name)));
                req_id(I, M);
                break;
            }
        } else {
            var out = c.arcan_event.zeroes();
            out.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_BCHUNKSTATE));
            out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.hint = 1;

            LOG("appl_found:%s", .{&M.*.appl.name});
            _ = c.snprintf(
                &out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions,
                @sizeOf(@TypeOf(out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions)),
                "%s;%d",
                @as([*c]const u8, @ptrCast(&M.*.appl.name)),
                @as(c_int, @intCast(M.*.identifier)),
            );

            if (M.*.next != null) {
                out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.hint |= 4;
            }
            _ = c.arcan_shmif_enqueue(C, &out);
        }

        M = M.*.next;
    }

    return true;
}

fn request_source(I: *c.struct_ioloop_shared, tunnel: bool, msg: [*c]const u8) void {
    var pubk: [32]u8 = undefined;
    if (!c.a12helper_fromb64(msg, 32, &pubk)) {
        LOG("request_source=invalid_pubk:%s\n", .{msg});
        return;
    }

    const C = c.arcan_shmif_primary(c.SHMIF_INPUT).?;
    var req = c.arcan_event.zeroes();
    req.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_SEGREQ));
    req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.segreq.kind = @as(c_uint, @bitCast(c.SEGID_HANDOVER));
    _ = c.arcan_shmif_enqueue(C, &req);

    var acq_event: c.arcan_event = undefined;
    var evpool: [*c]c.arcan_event = null;
    var evpool_sz: isize = 0;
    if (!c.arcan_shmif_acquireloop(C, &acq_event, &evpool, &evpool_sz)) {
        LOG("server rejected allocation", .{});
        return;
    }
    if (evpool_sz != 0) {
        LOG("ignoring_pending:%zu", .{evpool_sz});
        std.c.free(evpool);
        return;
    }

    const handover: *c.struct_arcan_shmif_cont = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c.struct_arcan_shmif_cont)).?));
    handover.* = c.arcan_shmif_acquire(C, null, c.SEGID_UNKNOWN, c.SHMIF_NOACTIVATE);

    I.handover = handover;
    LOG("request_source=%s\n", .{&pubk});
    _ = c.a12_request_dynamic_resource(I.S, &pubk, tunnel, &c.dircl_source_handler, @ptrCast(I));
}

fn switch_dir(I: *c.struct_ioloop_shared, tunnel: bool, name: [*c]const u8) void {
    _ = I;
    _ = tunnel;
    _ = name;
}

fn dircl_userfd(I: *c.struct_ioloop_shared, ok: bool) callconv(.c) void {
    _ = ok;
    const C = c.arcan_shmif_primary(c.SHMIF_INPUT).?;
    const cbt: *c.struct_directory_meta = @ptrCast(@alignCast(I.cbt));
    const cm: *DirclMeta = @ptrCast(@alignCast(C.*.user.?));

    if (cm.pending_reqid > 0) return;

    var ev: c.arcan_event = undefined;
    var pv: c_int = 0;

    while (true) {
        pv = c.arcan_shmif_poll(C, &ev);
        if (pv <= 0) break;
        if (ev.unnamed_0.unnamed_0.category != c.EVENT_TARGET) continue;

        switch (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind) {
            c.TARGET_COMMAND_MESSAGE => {
                const msg_ptr: [*c]u8 = @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message);
                LOG("shmif:message=%s", .{msg_ptr});
                var err: [*c]u8 = null;
                var i: usize = 0;
                var tunnel: bool = false;

                if (msg_ptr[0] == '|') {
                    tunnel = true;
                    i += 1;
                }

                if (msg_ptr[i] == '/') {
                    switch_dir(I, tunnel, msg_ptr + i + 1);
                    continue;
                }

                if (msg_ptr[i] == '<') {
                    request_source(I, tunnel, msg_ptr + i + 1);
                    continue;
                }

                const id = c.strtoul(msg_ptr, &err, 10);
                if (err.* != 0 or id > 65535) {
                    LOG("shmif:bad_req_id", .{});
                    return;
                }

                var clk_dummy: u64 = 0;
                var am = c.a12int_get_directory(I.S, &clk_dummy);
                while (am != null) {
                    if (am.?.identifier == @as(u16, @intCast(id))) {
                        _ = c.snprintf(&cbt.clopt.*.applname, 16, "%s", @as([*c]const u8, @ptrCast(&am.?.appl.name)));
                        req_id(I, am.?);
                        return;
                    }
                    am = am.?.next;
                }
                LOG("shmif:unknown_req_id=%d", .{@as(c_int, @intCast(id))});
                return;
            },

            c.TARGET_COMMAND_BCHUNK_IN => {
                ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_BCHUNK_OUT));
                _ = c.a12_channel_enqueue(I.S, &ev);
            },
            c.TARGET_COMMAND_BCHUNK_OUT => {
                ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_BCHUNK_IN));
                _ = c.a12_channel_enqueue(I.S, &ev);
            },
            c.TARGET_COMMAND_NEWSEGMENT => {
                LOG("shmif:newsegment_without_request", .{});
            },
            c.TARGET_COMMAND_REQFAIL => {},
            else => {
                LOG("shmif:event=%s", .{c.arcan_shmif_eventstr(&ev, null, 0)});
            },
        }
    }

    if (pv < 0) {
        I.shutdown = true;
        LOG("shmif:dead", .{});
    }
}

fn dircl_loop(
    C: *c.struct_arcan_shmif_cont,
    A: *c.struct_anet_cl_connection,
    args: ?*c.struct_arg_arr,
) c_int {
    _ = args;
    c.a12int_request_dirlist(A.state, true);
    c.arcan_shmif_setprimary(c.SHMIF_INPUT, C);

    var dmeta: DirclMeta = .{};

    var clcfg = std.mem.zeroes(c.struct_anet_dircl_opts);
    clcfg.allocator = @ptrCast(&dircl_alloc);
    clcfg.executor = @ptrCast(&dircl_exec);
    clcfg.basedir = -1;

    var path = c.anet_client_lua_getpath("unpack_temp");
    if (path == null) {
        path = @constCast(@ptrCast("/tmp"));
    }
    clcfg.basedir = c.open(path.?, c.O_DIRECTORY, @as(c_int, c.O_RDWR));

    var dircfg = std.mem.zeroes(c.struct_directory_meta);
    dircfg.S = A.state;
    dircfg.clopt = &clcfg;
    dircfg.state_in = -1;

    var ioloop = std.mem.zeroes(c.struct_ioloop_shared);
    ioloop.S = A.state;
    ioloop.fdin = A.fd;
    ioloop.fdout = A.fd;
    ioloop.userfd = -1;
    ioloop.userfd2 = C.epipe;
    ioloop.on_event = @ptrCast(&dircl_event);
    ioloop.on_directory = @ptrCast(&dircl_dirent);
    ioloop.on_userfd2 = @ptrCast(&dircl_userfd);
    ioloop.cbt = &dircfg;

    C.user = @ptrCast(&dmeta);

    var unpack_cfg = std.mem.zeroes(c.struct_a12_unpack_cfg);
    unpack_cfg.on_discover = @ptrCast(&cl_got_dyn);
    unpack_cfg.on_discover_tag = @ptrCast(&ioloop);
    c.a12_set_destination_raw(A.state, 0, unpack_cfg, @sizeOf(c.struct_a12_unpack_cfg));

    // anet_directory_cl_bhandler is declared against anet's bhandler_meta/res;
    // a12_set_bhandler wants the a12-typed callback. Cast the pointer.
    c.a12_set_bhandler(A.state, @ptrCast(&c.anet_directory_cl_bhandler), @ptrCast(&ioloop));
    c.anet_directory_ioloop(&ioloop);

    return c.EXIT_SUCCESS;
}

fn connect_to_host(C: *c.struct_arcan_shmif_cont, args: ?*c.struct_arg_arr) c_int {
    var prov: c.struct_keystore_provider = undefined;

    // load / parse config if applicable
    var config_file: [*c]const u8 = null;
    if (c.arg_lookup(args, "config", 0, &config_file) and config_file != null) {
        global.config_file = c.strdup(config_file);
    }
    _ = c.anet_lua_init(&global);

    if (!get_keystore(C, &prov)) return c.EXIT_FAILURE;

    var a12opts = std.mem.zeroes(c.struct_a12_context_options);
    a12opts.local_role = c.ROLE_SINK;
    a12opts.pk_lookup = @ptrCast(&key_auth_local);

    var opts = std.mem.zeroes(c.struct_anet_options);
    opts.opts = &a12opts;
    opts.keystore = prov;

    // This does not respect trust mode currently unless we set a tag.
    global.soft_auth = true;

    var tag: [*c]const u8 = null;
    if (c.arg_lookup(args, "tag", 0, &tag) and tag != null and c.strlen(tag) > 0) {
        if (c.arg_lookup(args, "probe", 0, null)) {
            a12opts.local_role = c.ROLE_PROBE;
            LOG("probe_only\n", .{});
        }

        var buf: [256]u8 = undefined;
        _ = c.snprintf(&buf, buf.len, "outbound-%s", tag);
        global.trust_domain = c.strdup(&buf);
        opts.key = tag;
        global.soft_auth = false;
        LOG("use_tag=%s\n", .{tag});
    }

    var host_name: [*c]const u8 = null;
    if (!c.arg_lookup(args, "host", 0, &host_name) or host_name == null or c.strlen(host_name) == 0) {
        if (tag == null) {
            c.arcan_shmif_last_words(C, "missing host argument");
            return c.EXIT_FAILURE;
        }
    } else {
        opts.ignore_key_host = true;
        opts.host = c.strdup(host_name);
        LOG("use_host=%s\n", .{opts.host});
    }

    var port_str: [*c]const u8 = null;
    if (!c.arg_lookup(args, "port", 0, &port_str) or c.strlen(port_str) == 0) {
        opts.port = @constCast(@ptrCast("6680"));
    } else {
        opts.port = @constCast(port_str);
    }

    var secret: [*c]const u8 = null;
    if (c.arg_lookup(args, "secret", 0, &secret) and secret != null and c.strlen(secret) > 0) {
        _ = c.snprintf(&a12opts.secret, @sizeOf(@TypeOf(a12opts.secret)), "%s", opts.key);
    }

    var con = c.anet_cl_setup(&opts);

    if (con.errmsg != null or con.state == null) {
        const msg: [*c]const u8 = if (con.errmsg != null) con.errmsg else @ptrCast("(unknown)");
        LOG("con_failed=%s\n", .{msg});
        c.arcan_shmif_last_words(C, con.errmsg);
        c.arcan_shmif_drop(C);
        return c.EXIT_FAILURE;
    }
    LOG("authenticated\n", .{});

    if (a12opts.local_role == c.ROLE_PROBE) {
        var ev = c.arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
        ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_MESSAGE));

        const msgdst: [*c]u8 = @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data);
        const msgdst_sz = @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data));

        const mode = c.a12_remote_mode(con.state);
        if (mode == c.ROLE_DIR) {
            _ = c.snprintf(msgdst, msgdst_sz, "directory");
        } else if (mode == c.ROLE_SOURCE) {
            _ = c.snprintf(msgdst, msgdst_sz, "source");
        } else if (mode == c.ROLE_SINK) {
            _ = c.snprintf(msgdst, msgdst_sz, "sink");
        }

        _ = c.arcan_shmif_enqueue(C, &ev);

        var waitev: c.arcan_event = undefined;
        while (c.arcan_shmif_wait(C, &waitev) != 0) {}

        _ = shutdown(con.fd, SHUT_RDWR);
        _ = c.close(con.fd);
        c.arcan_shmif_drop(C);
        return c.EXIT_SUCCESS;
    }

    if (c.a12_remote_mode(con.state) == c.ROLE_DIR) {
        LOG("directory-client", .{});
        return dircl_loop(C, &con, args);
    } else if (c.a12_remote_mode(con.state) == c.ROLE_SINK) {
        c.arcan_shmif_last_words(C, "host-mismatch:role=sink");
        _ = shutdown(con.fd, SHUT_RDWR);
        _ = c.close(con.fd);
        c.arcan_shmif_drop(C);
        return c.EXIT_FAILURE;
    }

    // Source mode: request handover segment and forward to helper
    var req = c.arcan_event.zeroes();
    req.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_SEGREQ));
    req.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.segreq.kind = @as(c_uint, @bitCast(c.SEGID_HANDOVER));
    _ = c.arcan_shmif_enqueue(C, &req);

    var acq_event: c.arcan_event = undefined;
    var evpool: [*c]c.arcan_event = null;
    var evpool_sz: isize = 0;
    if (!c.arcan_shmif_acquireloop(C, &acq_event, &evpool, &evpool_sz)) {
        c.arcan_shmif_last_words(C, "client handover-req failed");
        return c.EXIT_FAILURE;
    }

    var S = c.arcan_shmif_acquire(C, null, c.SEGID_UNKNOWN, c.SHMIF_NOACTIVATE);
    if (S.addr == null) {
        c.arcan_shmif_last_words(C, "couldn't map new segment");
        return c.EXIT_FAILURE;
    }

    _ = c.a12helper_a12srv_shmifcl(&S, con.state, null, con.fd, con.fd);
    c.arcan_shmif_drop(C);
    return c.EXIT_SUCCESS;
}

fn show_help() c_int {
    _ = c.fprintf(c.stdout,
        "Net (client) should be run authoritatively (spawned from arcan)\n" ++
            "Running from the command-line is only intended for developing/debugging\n\n" ++
            "ARCAN_ARG (environment variable, key1=value:key2:key3=value), arguments: \n" ++
            " Outbound connection: \n" ++
            "  key     \t   value   \t   description\n" ++
            "----------\t-----------\t-----------------\n" ++
            " host     \t  dsthost  \t Specify host to connect to\n" ++
            " tag      \t  tag      \t Set tag (and host unless host is set) to connect\n" ++
            " ipv6     \t  group    \t Set IPV6 multicast group address\n" ++
            " config   \t  path     \t Set config.lua profile for sourcing/directory\n" ++
            "\n" ++
            " Discovery:\n " ++
            "  key   \t   value   \t   description\n" ++
            "--------\t-----------\t-----------------\n" ++
            " discover \t  method   \t Set discovery mode (method=sweep,test,passive,\n" ++
            "          \t           \t                     broadcast or directory)\n" ++
            " ipv6     \t  group    \t Set IPV6 multicast group address\n");
    return c.EXIT_FAILURE;
}

// afsrv entrypoints (called by the frameserver framework)

pub export fn afsrv_netcl(
    C: *c.struct_arcan_shmif_cont,
    args: ?*c.struct_arg_arr,
) c_int {
    var dmethod: [*c]const u8 = null;
    _ = signal(c.SIGPIPE, SIG_IGN);
    _ = signal(c.SIGCHLD, SIG_IGN);

    if (c.arg_lookup(args, "help", 0, null)) {
        return show_help();
    }

    if (c.arg_lookup(args, "host", 0, null) or c.arg_lookup(args, "tag", 0, null)) {
        return connect_to_host(C, args);
    } else if (c.arg_lookup(args, "discover", 0, &dmethod)) {
        var trust: [*c]const u8 = null;
        _ = c.arg_lookup(args, "trust", 0, &trust);
        const trustm: c_int = TRUST_KNOWN;

        if (c.strcmp(dmethod, "sweep") == 0) {
            return discover_sweep(C, trustm);
        } else if (c.strcmp(dmethod, "passive") == 0) {
            return discover_passive(C, args, trustm);
        } else if (c.strcmp(dmethod, "broadcast") == 0) {
            return discover_broadcast(C, args, trustm);
        } else if (c.strcmp(dmethod, "test") == 0) {
            return discover_test(C, trustm);
        } else {
            c.arcan_shmif_last_words(C, "unsupported discovery method");
            c.arcan_shmif_drop(C);
            return c.EXIT_FAILURE;
        }
    }

    c.arcan_shmif_last_words(C, "missing connection mode");
    return c.EXIT_FAILURE;
}

pub export fn afsrv_netsrv(
    C: *c.struct_arcan_shmif_cont,
    args: ?*c.struct_arg_arr,
) c_int {
    _ = C;
    _ = args;
    return c.EXIT_FAILURE;
}
