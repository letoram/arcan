// Zig port of arcan-upstream/src/a12/net/net.c
// Main entry point for arcan-net binary: argument parsing, connection modes,
// signal handling, and dispatch to subsystems.
// License: 3-Clause BSD (same as upstream)

const std = @import("std");
const posix = std.posix;

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. Keeps the `c.X` spellings used below. Each alias routes to the
// appropriate hand-written replacement module (zero `@cImport` left).
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
// `anet` is used as a local variable name throughout this file
// (struct_anet_cl_connection is frequently shadowed as `anet`), so the
// module is imported as `anet_mod` to avoid shadowing warnings.
const anet_mod = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // libc — process/env/io
    pub const chdir = libc.chdir;
    pub const close = libc.close;
    pub const exit = libc.exit;
    pub const fgets = libc.fgets;
    pub const fclose = libc.fclose;
    pub const FILE = libc.FILE;
    pub const fopen = libc.fopen;
    pub const fork = libc.fork;
    pub const fprintf = libc.fprintf;
    pub const fputs = libc.fputs;
    pub const free = libc.free;
    pub const EXIT_FAILURE = libc.EXIT_FAILURE;
    pub const EXIT_SUCCESS = libc.EXIT_SUCCESS;
    pub const getenv = libc.getenv;
    pub const getpass = libc.getpass;
    pub const isatty = libc.isatty;
    pub const malloc = libc.malloc;
    pub const open = libc.open;
    pub const printf = libc.printf;
    pub const pthread_attr_init = libc.pthread_attr_init;
    pub const pthread_attr_setdetachstate = libc.pthread_attr_setdetachstate;
    pub const pthread_attr_t = libc.pthread_attr_t;
    pub const pthread_create = libc.pthread_create;
    pub const PTHREAD_CREATE_DETACHED = libc.PTHREAD_CREATE_DETACHED;
    pub const pthread_t = libc.pthread_t;
    pub const RLIMIT_STACK = libc.RLIMIT_STACK;
    pub const RLIM_INFINITY = libc.RLIM_INFINITY;
    pub const setrlimit = libc.setrlimit;
    pub const setsid = libc.setsid;
    pub const struct_rlimit = libc.struct_rlimit;
    pub const sleep = libc.sleep;
    pub const snprintf = libc.snprintf;
    // stderr/stdin/stdout are `extern "c" var` — aliasing via `pub const` tries
    // to read the extern's value at comptime. Re-declare the externs here so
    // they resolve to the same libc symbols at link time.
    pub extern "c" var stderr: *libc.FILE;
    pub extern "c" var stdin: *libc.FILE;
    pub extern "c" var stdout: *libc.FILE;
    pub const STDIN_FILENO = libc.STDIN_FILENO;
    pub const strcmp = libc.strcmp;
    pub const strdup = libc.strdup;
    pub const strlen = libc.strlen;
    pub const O_CLOEXEC = libc.O_CLOEXEC;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const S_IRWXU = libc.S_IRWXU;
    pub const struct_stat = libc.struct_stat;

    // string — strncmp/strrchr live in shmif_types
    pub const strncmp = shmif.strncmp;
    pub const strrchr = shmif.strrchr;

    // shmif — shared-memory IPC types, constants, and server API
    pub const arcan_shmif_cookie = shmif.arcan_shmif_cookie;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const struct_shmifsrv_client = shmif.struct_shmifsrv_client;
    pub const struct_shmifsrv_envp = shmif.struct_shmifsrv_envp;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_MESSAGE = shmif.TARGET_COMMAND_MESSAGE;

    // a12 — state machine, extern fns, constants (shmifsrv_* helpers live here)
    pub const a12_channel_close = a12.a12_channel_close;
    pub const a12_free = a12.a12_free;
    pub const a12_remote_mode = a12.a12_remote_mode;
    pub const a12_sensitive_alloc = a12.a12_sensitive_alloc;
    pub const a12_set_session = a12.a12_set_session;
    pub const a12_set_trace_level = a12.a12_set_trace_level;
    pub const a12_set_tunnel_sink = a12.a12_set_tunnel_sink;
    pub const a12_trace_tag = a12.a12_trace_tag;
    // `a12_trace_targets` is `extern "c" var` (read *and* assigned). A `pub const`
    // alias tries to capture the value at comptime; callers need lvalue access,
    // so re-declare the same extern symbol here.
    pub extern var a12_trace_targets: c_int;
    pub const A12_TRACE_DIRECTORY = a12.A12_TRACE_DIRECTORY;
    pub const A12_TRACE_SECURITY = a12.A12_TRACE_SECURITY;
    pub const A12_TRACE_SYSTEM = a12.A12_TRACE_SYSTEM;
    pub const CLIENT_DEAD = a12.CLIENT_DEAD;
    pub const CLIENT_IDLE = a12.CLIENT_IDLE;
    pub const ROLE_DIR = a12.ROLE_DIR;
    pub const ROLE_DIRREF = a12.ROLE_DIRREF;
    pub const ROLE_PROBE = a12.ROLE_PROBE;
    pub const ROLE_SINK = a12.ROLE_SINK;
    pub const ROLE_SOURCE = a12.ROLE_SOURCE;
    pub const SHMIFSRV_FREE_LOCAL = a12.SHMIFSRV_FREE_LOCAL;
    pub const SHMIFSRV_FREE_NO_DMS = a12.SHMIFSRV_FREE_NO_DMS;
    pub const shmifsrv_allocate_connpoint = a12.shmifsrv_allocate_connpoint;
    pub const shmifsrv_client_handle = a12.shmifsrv_client_handle;
    pub const shmifsrv_enqueue_event = a12.shmifsrv_enqueue_event;
    pub const shmifsrv_free = a12.shmifsrv_free;
    pub const shmifsrv_inherit_connection = a12.shmifsrv_inherit_connection;
    pub const shmifsrv_poll = a12.shmifsrv_poll;
    pub const shmifsrv_spawn_client = a12.shmifsrv_spawn_client;
    pub const struct_a12_context_options = a12.struct_a12_context_options;
    pub const struct_a12_dynreq = a12.struct_a12_dynreq;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_pk_response = a12.struct_pk_response;

    // anet — directory/helper/keystore + discovery
    pub const A12HELPER_PROVIDER_BASEDIR = anet_mod.A12HELPER_PROVIDER_BASEDIR;
    pub const a12helper_a12cl_shmifsrv = anet_mod.a12helper_a12cl_shmifsrv;
    pub const a12helper_a12srv_shmifcl = anet_mod.a12helper_a12srv_shmifcl;
    pub const a12helper_discover_ipcfg = anet_mod.a12helper_discover_ipcfg;
    pub const a12helper_fromb64 = anet_mod.a12helper_fromb64;
    pub const a12helper_keystore_accept = anet_mod.a12helper_keystore_accept;
    pub const a12helper_keystore_accepted = anet_mod.a12helper_keystore_accepted;
    pub const a12helper_keystore_dirfd = anet_mod.a12helper_keystore_dirfd;
    pub const a12helper_keystore_gen_sigkey = anet_mod.a12helper_keystore_gen_sigkey;
    pub const a12helper_keystore_hostkey = anet_mod.a12helper_keystore_hostkey;
    pub const a12helper_keystore_open = anet_mod.a12helper_keystore_open;
    pub const a12helper_keystore_register = anet_mod.a12helper_keystore_register;
    pub const a12helper_keystore_release = anet_mod.a12helper_keystore_release;
    pub const a12helper_keystore_statestore = anet_mod.a12helper_keystore_statestore;
    pub const a12helper_query_untrusted_key = anet_mod.a12helper_query_untrusted_key;
    pub const a12helper_tob64 = anet_mod.a12helper_tob64;
    pub const anet_authenticate = anet_mod.anet_authenticate;
    pub const anet_cl_setup = anet_mod.anet_cl_setup;
    pub const anet_connect_to = anet_mod.anet_connect_to;
    pub const anet_directory_appl_runner = anet_mod.anet_directory_appl_runner;
    pub const anet_directory_cl = anet_mod.anet_directory_cl;
    pub const anet_directory_ioloop_current = anet_mod.anet_directory_ioloop_current;
    pub const anet_directory_link = anet_mod.anet_directory_link;
    pub const anet_directory_lua_ready = anet_mod.anet_directory_lua_ready;
    pub const anet_directory_lua_trigger_auto = anet_mod.anet_directory_lua_trigger_auto;
    pub const anet_directory_shmifsrv_set = anet_mod.anet_directory_shmifsrv_set;
    pub const anet_directory_shmifsrv_thread = anet_mod.anet_directory_shmifsrv_thread;
    pub const anet_directory_srv = anet_mod.anet_directory_srv;
    pub const anet_directory_srv_scan = anet_mod.anet_directory_srv_scan;
    pub const anet_directory_tunnel_thread = anet_mod.anet_directory_tunnel_thread;
    pub const anet_discover_listen_beacon = anet_mod.anet_discover_listen_beacon;
    pub const anet_discover_send_beacon = anet_mod.anet_discover_send_beacon;
    pub const anet_listen = anet_mod.anet_listen;
    pub const anet_lua_init = anet_mod.anet_lua_init;
    pub const build_appl_pkg = anet_mod.build_appl_pkg;
    pub const DIRLINK_NONE = anet_mod.DIRLINK_NONE;
    pub const dirsrv_global_lock = anet_mod.dirsrv_global_lock;
    pub const dirsrv_global_unlock = anet_mod.dirsrv_global_unlock;
    pub const MONITOR_ADMIN = anet_mod.MONITOR_ADMIN;
    pub const MONITOR_DEBUGGER = anet_mod.MONITOR_DEBUGGER;
    pub const MONITOR_SIMPLE = anet_mod.MONITOR_SIMPLE;
    pub const struct_anet_cl_connection = anet_mod.struct_anet_cl_connection;
    pub const struct_anet_dirsrv_opts = anet_mod.struct_anet_dirsrv_opts;
    pub const struct_anet_discover_opts = anet_mod.struct_anet_discover_opts;
    pub const struct_anet_options = anet_mod.struct_anet_options;
    pub const struct_dircl_nameent = anet_mod.struct_dircl_nameent;
    pub const struct_global_cfg = anet_mod.struct_global_cfg;
    pub const struct_arg_arr = shmif.struct_arg_arr;
    pub const extract_appl_pkg = anet_mod.extract_appl_pkg;
};

// Provide missing socket-layer externs; including <sys/socket.h> pulls in
// translate-c-unfriendly bitfield headers (musl's struct timespec).
extern "c" fn shutdown(sockfd: c_int, how: c_int) c_int;
const SHUT_RD: c_int = 0;
const SHUT_WR: c_int = 1;
const SHUT_RDWR: c_int = 2;

// a12int_trace is a C variadic macro translate-c can't express — provide it
// via its underlying implementation.
extern "c" fn a12int_trace(mask: c_int, fmt: [*:0]const u8, ...) void;

// sys/wait.h drags in the bitfield timespec chain so we redeclare waitpid.
extern "c" fn waitpid(pid: c_int, status: [*c]c_int, options: c_int) c_int;
extern "c" fn socketpair(domain: c_int, stype: c_int, protocol: c_int, sv: [*c]c_int) c_int;

// Process environment array — equivalent to C's `extern char** environ;`.
// NB: `@extern([*c][*c]u8, …)` returns a *pointer to* the environ slot,
// not environ's value, and the resulting `[*c][*c]u8` is garbage when
// coerced — cost us session-side env propagation for hours. Declare it
// as a Zig `extern var` instead so references read the actual pointer.
extern var environ: [*c][*c]u8;

// Minimal poll struct: identical layout to system pollfd.
const pollfd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};
extern "c" fn poll(fds: [*c]pollfd, nfds: c_ulong, timeout: c_int) c_int;
const POLLIN: c_short = 0x001;
const POLLOUT: c_short = 0x004;

// Mode enum

const AnetMode = enum(c_int) {
    none = 0,
    shmif_cl = 1,
    shmif_cl_reverse = 2,
    shmif_srv = 3,
    shmif_srv_inherit = 4,
    shmif_exec = 5,
    shmif_exec_outbound = 6,
    shmif_dirsrv_inherit = 7,
    shmif_srvapp_inherit = 8,
};

// Per-process argv forwarding to session manager

const ArcanNetMeta = struct {
    argc: c_int = 0,
    argv: [*c][*c]u8 = undefined,
    bin: [*c]u8 = null,
};

var argv_output = ArcanNetMeta{};

// Session state (mirrors the C SESSION static)

const SessionState = struct {
    prctl: ?*c.struct_shmifsrv_client = null,
    lock: std.Thread.Mutex = .{},
};
var session = SessionState{};

// Trace group names

const trace_groups = [_][]const u8{
    "video",
    "audio",
    "system",
    "event",
    "transfer",
    "debug",
    "missing",
    "alloc",
    "crypto",
    "vdetail",
    "binary",
    "security",
    "directory",
};

// Global config
// The C upstream defines `global` as a process-wide mutable singleton in
// net.c, referenced from dir_cl.c / dir_srv.c / dir_lua_*.c. Mirror that here:
// this file owns the storage, dir_cl.zig / dir_srv.zig consume via
// `extern var global`. Exported with the C ABI symbol name `global`.

pub export var global: c.struct_global_cfg = blk: {
    var g = std.mem.zeroes(c.struct_global_cfg);
    g.trust_domain = @as([*c]u8, @constCast(@ptrCast("outbound")));
    g.backpressure_soft = 1;
    g.backpressure = 1;
    g.directory = -1;
    g.dircl.source_port = 6681;
    g.dirsrv.allow_tunnel = true;
    g.dirsrv.runner_process = true;
    g.dirsrv.resource_dfd = -1;
    g.dirsrv.appl_server_dfd = -1;
    g.dirsrv.appl_server_datadfd = -1;
    g.dirsrv.appl_server_temp_dfd = -1;
    break :blk g;
};

// Helpers

fn openKeystore(opts: *c.struct_anet_options, err: *[*c]const u8) bool {
    if (opts.keystore.unnamed_0.directory.dirfd < 0) {
        opts.keystore.unnamed_0.directory.dirfd = c.a12helper_keystore_dirfd(err);
        if (opts.keystore.unnamed_0.directory.dirfd == -1)
            return false;
    }
    if (!c.a12helper_keystore_open(&opts.keystore)) {
        err.* = "Couldn't open keystore from basedir (ARCAN_STATEPATH)";
        return false;
    }
    return true;
}

fn tracestrToBitmap(work: []u8) c_int {
    var result: c_int = 0;
    var it = std.mem.splitScalar(u8, work, ',');
    while (it.next()) |tok| {
        for (trace_groups, 0..) |grp, i| {
            if (std.ascii.eqlIgnoreCase(grp, tok)) {
                result |= @as(c_int, 1) << @intCast(i);
                break;
            }
        }
    }
    return result;
}

/// Split "a/b/c" path into dircl_nameent linked list.
fn resnameToDircl(work: []u8, dst: *c.struct_dircl_nameent) bool {
    var count: usize = 0;
    var cur = dst;
    var it = std.mem.splitScalar(u8, work, '/');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (part.len >= @sizeOf(@TypeOf(cur.srvname))) {
            _ = c.fprintf(c.stderr, "too long member (< 16) in resource path\n");
            return false;
        }
        _ = c.snprintf(&cur.srvname, 16, "%.*s", @as(c_int, @intCast(part.len)), part.ptr);
        const next = std.c.malloc(@sizeOf(c.struct_dircl_nameent)) orelse return false;
        const next_ptr: *c.struct_dircl_nameent = @ptrCast(@alignCast(next));
        next_ptr.* = std.mem.zeroes(c.struct_dircl_nameent);
        cur.next = next_ptr;
        cur = next_ptr;
        count += 1;
    }
    return count > 0;
}

fn getBcacheDir() c_int {
    const base = std.c.getenv("A12_CACHE_DIR") orelse return -1;
    return c.open(base, c.O_DIRECTORY | c.O_CLOEXEC);
}

fn setLogTrace(prefix: [*c]const u8) void {
    // Only active in DEBUG builds. In release this is a no-op.
    _ = prefix;
}

// Session manager (shmif-server child)

fn lockSessionManager(M: *ArcanNetMeta) ?*c.struct_shmifsrv_client {
    session.lock.lock();

    // If the previous session manager has exited (afsrv child cascade-died on
    // client disconnect), `session.prctl` holds a stale pointer — shmifsrv_poll
    // returns CLIENT_DEAD. Upstream C left this unchecked and every subsequent
    // accept would return the stale prctl, enqueue into a dead socket, and
    // close(fd) → the client sees FIN-after-ACK and "read fail during
    // authentication". Sweep dead prctls here so the spawn block below re-runs.
    if (session.prctl != null and c.shmifsrv_poll(session.prctl) == c.CLIENT_DEAD) {
        c.shmifsrv_free(session.prctl, 0);
        session.prctl = null;
    }

    if (session.prctl == null) {
        // Build path to arcan-net-session sibling binary.
        // Mirrors upstream net.c:183 — scan path_self backwards from len-1 to
        // find the trailing '/', then keep prefix up to and including it, so
        // we can append "arcan-net-session" to get the sibling binary path.
        const path_self: [*c]const u8 = global.path_self;
        const self_len = c.strlen(path_self);
        var blen: usize = if (self_len > 0) self_len - 1 else 0;
        while (blen > 0) : (blen -= 1) {
            if (path_self[blen] == '/') {
                blen += 1;
                break;
            }
        }

        const suffix = "arcan-net-session";
        const plen = self_len + suffix.len + 1;
        const path = std.c.malloc(plen) orelse return null;
        defer std.c.free(path);
        _ = c.snprintf(@ptrCast(path), plen, "%.*s%s", @as(c_int, @intCast(blen)), path_self, suffix.ptr);

        // Build argv: ["arcan-net-session", "--", ...M.argv..., null]
        var argc: usize = 0;
        while (M.argv[argc] != null) : (argc += 1) {}

        const argv_buf = std.c.malloc((argc + 3) * @sizeOf([*c]u8)) orelse return null;
        defer std.c.free(argv_buf);
        const argv_arr: [*][*c]u8 = @ptrCast(@alignCast(argv_buf));
        argv_arr[0] = @constCast("arcan-net-session");
        argv_arr[1] = @constCast("--");
        for (0..argc) |i| argv_arr[i + 2] = M.argv[i];
        argv_arr[argc + 2] = null;

        const env: c.struct_shmifsrv_envp = .{
            .path = @ptrCast(path),
            .detach = 4 | 8,
            .envv = @ptrCast(environ),
            .argv = @ptrCast(argv_arr),
            .init_w = 0,
            .init_h = 0,
        };

        var errc: c_int = 0;
        var dummy_fd: c_int = 0;
        session.prctl = c.shmifsrv_spawn_client(env, &dummy_fd, &errc, 0);
        if (session.prctl == null) return null;

        // Build and send configuration message events
        var ev = c.struct_arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
        const msg: [*c]u8 = @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message);
        const sz: usize = @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message));

        // Keystore transfer
        if (c.getenv("A12_USEPRIV") == null) {
            var dfd: c_int = -1;
            if (global.meta.keystore.unnamed_0.directory.dirfd > 0)
                dfd = global.meta.keystore.unnamed_0.directory.dirfd
            else if (c.getenv("ARCAN_STATEPATH")) |sp|
                dfd = c.open(sp, c.O_DIRECTORY | c.O_CLOEXEC);

            if (dfd != -1) {
                var bev = c.struct_arcan_event.zeroes();
                bev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
                bev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
                bev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = dfd;
                _ = c.snprintf(@ptrCast(&bev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message), @sizeOf(@TypeOf(bev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)), "keystore");
                _ = c.shmifsrv_enqueue_event(session.prctl, &bev, dfd);
            }
        } else {
            _ = c.snprintf(msg, sz, "key=%s", c.getenv("A12_USEPRIV"));
            _ = c.shmifsrv_enqueue_event(session.prctl, &ev, -1);
        }

        if (c.a12_trace_targets != 0) {
            _ = c.snprintf(msg, sz, "log_level=%d", @as(c_int, @intCast(c.a12_trace_targets)));
            _ = c.shmifsrv_enqueue_event(session.prctl, &ev, -1);
        }
        if (global.soft_auth) {
            _ = c.snprintf(msg, sz, "soft_auth");
            _ = c.shmifsrv_enqueue_event(session.prctl, &ev, -1);
        }
        if (global.accept_n_pk_unknown != 0) {
            _ = c.snprintf(msg, sz, "accept_n_unknown=%zu", global.accept_n_pk_unknown);
            _ = c.shmifsrv_enqueue_event(session.prctl, &ev, -1);
        }
        if (global.meta.opts != null and global.meta.opts.*.pqc_rekey) {
            _ = c.snprintf(msg, sz, "rekey_pqc");
            _ = c.shmifsrv_enqueue_event(session.prctl, &ev, -1);
        }
        if (global.meta.opts != null and global.meta.opts.*.rekey_bytes != 0) {
            _ = c.snprintf(msg, sz, "rekey=%zu", global.meta.opts.*.rekey_bytes);
            _ = c.shmifsrv_enqueue_event(session.prctl, &ev, -1);
        }
        if (global.meta.opts != null and global.meta.opts.*.secret[0] != 0) {
            _ = c.snprintf(msg, sz, "secret=%s", &global.meta.opts.*.secret);
            _ = c.shmifsrv_enqueue_event(session.prctl, &ev, -1);
        }
        if (global.cast) {
            _ = c.snprintf(msg, sz, "cast");
            _ = c.shmifsrv_enqueue_event(session.prctl, &ev, -1);
        }

        // Wait for CLIENT_IDLE or CLIENT_DEAD
        var pv: c_int = c.shmifsrv_poll(session.prctl);
        while (pv != c.CLIENT_DEAD) : (pv = c.shmifsrv_poll(session.prctl)) {
            if (pv == c.CLIENT_IDLE) break;
        }
        if (pv == c.CLIENT_DEAD) {
            c.shmifsrv_free(session.prctl, 0);
            session.prctl = null;
        }
    }

    return session.prctl;
}

fn unlockSessionManager() void {
    session.lock.unlock();
}

// Connection dispatch callbacks

fn launchInboundSink(S: ?*c.struct_a12_state, fd: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    const pid = c.fork();
    if (pid != 0) {
        _ = waitpid(pid, null, 0);
        c.exit(0);
    }
    _ = c.setsid();
    if (c.fork() != 0) {
        _ = c.close(fd);
        return;
    }
    const rc = c.a12helper_a12srv_shmifcl(null, S, null, fd, fd);
    _ = shutdown(fd, SHUT_RDWR);
    _ = c.close(fd);
    c.exit(if (rc < 0) 1 else 0);
}

fn launchDirsrvHandler(S: ?*c.struct_a12_state, fd: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var tmpfd: [32]u8 = undefined;
    var tmptrace: [32]u8 = undefined;
    _ = c.snprintf(&tmpfd, tmpfd.len, "%d", fd);
    _ = c.snprintf(&tmptrace, tmptrace.len, "%d", @as(c_int, @intCast(c.a12_trace_targets)));

    var argv_arr: [8][*c]u8 = .{
        global.path_self,
        @constCast("-d"),
        &tmptrace,
        @constCast("-S"),
        &tmpfd,
        null,
        null,
        null,
    };

    var envarg: [1024]u8 = undefined;
    _ = c.snprintf(
        &envarg,
        envarg.len,
        "ARCAN_ARG=rekey=%zu:checksum_cap=%zu%s",
        global.meta.opts.*.rekey_bytes,
        global.meta.opts.*.checksum_cap_mb,
        @as([*c]const u8, if (global.meta.opts.*.pqc_rekey) ":rekey_pqc" else ""),
    );
    var envv: [2][*c]u8 = .{ &envarg, null };

    const env: c.struct_shmifsrv_envp = .{
        .path = global.path_self,
        .init_w = 32,
        .init_h = 32,
        .envv = @ptrCast(&envv),
        .argv = @ptrCast(&argv_arr),
        .detach = 2 | 4 | 8,
    };

    c.a12_trace_tag(S, "dir_shmif");
    var dummy: c_int = -1;
    const cl = c.shmifsrv_spawn_client(env, &dummy, null, 0);
    if (cl != null) {
        _ = c.anet_directory_shmifsrv_thread(cl, S, c.DIRLINK_NONE);
    }
    c.a12_channel_close(S);
    _ = c.close(fd);
}

fn forwardInboundExec(S: ?*c.struct_a12_state, fd: c_int, tag: ?*anyopaque) callconv(.c) void {
    const M: *ArcanNetMeta = @ptrCast(@alignCast(tag));
    const sm = lockSessionManager(M) orelse {
        a12int_trace(c.A12_TRACE_SYSTEM, "couldn't hand-over to session manager");
        _ = shutdown(fd, SHUT_RDWR);
        _ = c.close(fd);
        return;
    };
    _ = S;

    var conn = c.struct_arcan_event.zeroes();
    conn.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    conn.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
    conn.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0] = 0;
    _ = c.shmifsrv_enqueue_event(sm, &conn, fd);
    _ = c.close(fd);
    unlockSessionManager();
}

// Directory tunnel glue

const DirState = struct {
    fd: c_int,
    aopts: *c.struct_anet_options,
    shmif: ?*c.struct_shmifsrv_client,
    req: c.struct_a12_dynreq,
};

fn dirToShmifsrv(S: ?*c.struct_a12_state, a: c.struct_a12_dynreq, tag: ?*anyopaque) callconv(.c) void {
    a12int_trace(c.A12_TRACE_DIRECTORY, "open_request_negotiated");
    const ds: *DirState = @ptrCast(@alignCast(tag));
    ds.req = a;

    var pre_fd: c_int = -1;
    var sv: [2]c_int = .{ 0, 0 };

    if (a.proto == 4) {
        // AF_UNIX=1, SOCK_STREAM=1 on Linux
        if (socketpair(1, 1, 0, &sv) != 0) {
            a12int_trace(c.A12_TRACE_DIRECTORY, "tunnel_socketpair_fail");
            return;
        }
        _ = c.a12_set_tunnel_sink(S, 1, sv[0]);
        c.anet_directory_tunnel_thread(c.anet_directory_ioloop_current().?, 1);
        pre_fd = sv[1];
    } else {
        a12int_trace(c.A12_TRACE_SYSTEM, "eimpl: only --tunnel supported");
        return;
    }

    const sm = lockSessionManager(&argv_output) orelse return;
    var conn = c.struct_arcan_event.zeroes();
    conn.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    conn.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
    _ = c.snprintf(@ptrCast(&conn.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message), 32, "%s", &a.authk);
    _ = c.shmifsrv_enqueue_event(sm, &conn, pre_fd);
    _ = c.close(pre_fd);
    // Note: we do not unlock here — matches original C behaviour
    // (dirToShmifsrv is called from within the locked section of dir cl)
    unlockSessionManager();
}

// Client dispatch

fn a12clDispatch(
    args: *c.struct_anet_options,
    S: ?*c.struct_a12_state,
    cl: ?*c.struct_shmifsrv_client,
    fd: c_int,
) void {
    // forwardShmifsrvCl can return with a null/freed state if the network
    // connect or auth handshake failed.  Bail before dereferencing.
    // (Defence-in-depth — the caller should already have cleared the
    // pointer per fossil 7c2828e9bd, but keep the guard so future call
    // sites can't reintroduce the bug.)
    if (S == null) {
        if (cl != null) c.shmifsrv_free(cl, c.SHMIFSRV_FREE_NO_DMS);
        if (fd >= 0) _ = c.close(fd);
        return;
    }

    if (global.directory > 0) {
        global.dircl.basedir = global.directory;
        c.a12_trace_tag(S, "dir_cl");
        c.anet_directory_cl(S, global.dircl, fd, fd);
        _ = c.close(fd);
        return;
    }

    if (c.a12_remote_mode(S) == c.ROLE_DIR) {
        const ds = std.c.malloc(@sizeOf(DirState)) orelse {
            _ = c.close(fd);
            return;
        };
        const ds_ptr: *DirState = @ptrCast(@alignCast(ds));
        ds_ptr.* = .{ .fd = fd, .aopts = args, .shmif = cl, .req = std.mem.zeroes(c.struct_a12_dynreq) };

        global.dircl.dir_source = dirToShmifsrv;
        global.dircl.dir_source_tag = ds_ptr;
        c.a12_trace_tag(S, "dir_lnk");
        c.anet_directory_cl(S, global.dircl, fd, fd);
        std.c.free(ds);
    } else {
        c.a12helper_a12cl_shmifsrv(S, cl, fd, fd, .{
            .vframe_block = global.backpressure,
            .redirect_exit = args.redirect_exit,
            .devicehint_cp = args.devicehint_cp,
            .bcache_dir = getBcacheDir(),
        });
    }

    _ = c.close(fd);
}

fn forkA12clDispatch(
    args: *c.struct_anet_options,
    S: ?*c.struct_a12_state,
    cl: ?*c.struct_shmifsrv_client,
    fd: c_int,
) void {
    const fpid = c.fork();
    if (fpid == 0) {
        a12clDispatch(args, S, cl, fd);
        c.exit(0);
    } else if (fpid == -1) {
        _ = c.fprintf(c.stderr, "fork_a12cl() couldn't fork new process, check ulimits\n");
        c.shmifsrv_free(cl, c.SHMIFSRV_FREE_NO_DMS);
        c.a12_channel_close(S);
        _ = shutdown(fd, SHUT_RDWR);
        _ = c.close(fd);
    } else {
        a12int_trace(c.A12_TRACE_SYSTEM, "client handed off to %d", @as(c_int, @intCast(fpid)));
        c.a12_channel_close(S);
        c.shmifsrv_free(cl, c.SHMIFSRV_FREE_LOCAL);
        // bug 0131-followup: do NOT shutdown(fd, SHUT_RDWR) here — shutdown
        // operates on the underlying socket, not the file descriptor, so it
        // tears down the connection for the forked child too. close() alone
        // is correct: it drops the parent's fd reference but leaves the
        // socket alive in the child. Upstream C has the same bug at
        // net.c:508-509 — same behaviour observed in this Zig port until
        // tested 2026-05-02.
        _ = c.close(fd);
    }
}

// Connection establishment

fn findConnection(
    opts: *c.struct_anet_options,
    cl: ?*c.struct_shmifsrv_client,
) c.struct_anet_cl_connection {
    var anet = std.mem.zeroes(c.struct_anet_cl_connection);
    var rc = opts.retry_count;
    var timesleep: c_int = 1;
    var err: [*c]const u8 = null;

    if (global.use_forced_remote_pubk == false) {
        if (!openKeystore(opts, &err))
            _ = c.fprintf(c.stderr, "couldn't open keystore: %s\n", err);
    }

    if (global.trust_domain == null) {
        if (opts.key != null) {
            const klen = c.strlen(opts.key) + @as(usize, "outbound-".len) + 1;
            const tmp = std.c.malloc(klen);
            if (tmp != null) {
                _ = c.snprintf(@ptrCast(tmp), klen, "outbound-%s", opts.key);
                global.trust_domain = @ptrCast(tmp);
            }
        } else {
            global.trust_domain = c.strdup("outbound");
        }
    }

    while (rc != 0 and (cl == null or c.shmifsrv_poll(cl) != c.CLIENT_DEAD)) {
        if (global.use_forced_remote_pubk) {
            if (c.getenv("A12_USEPRIV")) |priv_env| {
                _ = c.a12helper_fromb64(priv_env, 32, &opts.opts.*.priv_key);
            }
            anet = c.anet_connect_to(opts);
        } else {
            anet = c.anet_cl_setup(opts);
        }

        if (anet.state != null) break;

        if (anet.errmsg != null) {
            _ = c.fputs(anet.errmsg.?, c.stderr);
            std.c.free(anet.errmsg);
            anet.errmsg = null;
            if (anet.auth_failed) break;
        }

        if (timesleep < 10) timesleep += 1;
        if (rc > 0) rc -= 1;
        _ = c.sleep(@intCast(timesleep));
    }

    global.dircl.last_connection = opts.*;
    return anet;
}

fn forwardShmifsrvCl(
    cl: ?*c.struct_shmifsrv_client,
    opts: *c.struct_anet_options,
) c.struct_anet_cl_connection {
    var anet = findConnection(opts, cl);

    if (anet.state == null or c.shmifsrv_poll(cl) == c.CLIENT_DEAD) {
        c.shmifsrv_free(cl, c.SHMIFSRV_FREE_NO_DMS);
        if (anet.state != null) {
            _ = c.a12_free(anet.state);
            _ = c.close(anet.fd);
            if (anet.errmsg != null) std.c.free(anet.errmsg);
        }
        return anet;
    }

    var msg: [*c]u8 = null;
    if (!c.anet_authenticate(anet.state, anet.fd, anet.fd, &msg) or
        c.shmifsrv_poll(cl) == c.CLIENT_DEAD)
    {
        if (msg != null)
            a12int_trace(c.A12_TRACE_SYSTEM, "authentication_failed=%s", msg);
        c.shmifsrv_free(cl, c.SHMIFSRV_FREE_NO_DMS);
        if (anet.state != null) {
            _ = c.a12_free(anet.state);
            _ = c.close(anet.fd);
            // Use-after-free guard: caller (a12Connect) passes anet.state
            // straight to dispatch which dereferences it via a12_remote_mode.
            // Clear the freed pointer + sentinel fd so dispatch sees the
            // failure on the null check it should do (and on the fd-cap
            // check downstream).  Without this, the freed state goes back
            // into dispatch and tries to load 200KB of garbage from
            // memcpy → SIGSEGV.  Confirmed in fossil 7c2828e9bd
            // bringup 2026-05-03.
            anet.state = null;
            anet.fd = -1;
        }
        if (anet.errmsg != null) std.c.free(anet.errmsg);
    }

    return anet;
}

/// Listen on a local shmif connection point and forward each client.
fn a12Connect(
    args: *c.struct_anet_options,
    dispatch: *const fn (*c.struct_anet_options, ?*c.struct_a12_state, ?*c.struct_shmifsrv_client, c_int) void,
) c_int {
    var shmif_fd: c_int = -1;

    while (true) {
        const cl = c.shmifsrv_allocate_connpoint(args.cp, null, c.S_IRWXU, shmif_fd) orelse {
            _ = c.fprintf(c.stderr, "couldn't open connection point\n");
            return 1;
        };

        if (shmif_fd == -1)
            shmif_fd = c.shmifsrv_client_handle(cl, null);

        var pfd = pollfd{
            .fd = shmif_fd,
            .events = POLLIN | 0x008 | 0x010, // POLLIN | POLLERR | POLLHUP
            .revents = 0,
        };

        // Wait for a client
        while (true) {
            const pv = poll(&pfd, 1, -1);
            if (pv == -1) {
                const eno = std.posix.errno(@as(c_int, -1));
                if (eno != .INTR and eno != .AGAIN) {
                    c.shmifsrv_free(cl, 1);
                    _ = c.fprintf(c.stderr, "error while waiting for a connection\n");
                    return 1;
                }
                continue;
            }
            if (pv > 0) break;
        }

        _ = c.shmifsrv_poll(cl);

        const anet = forwardShmifsrvCl(cl, args);
        // If forwardShmifsrvCl bailed (network connect failed, auth failed,
        // shmif client died) it already freed `cl` and `anet.state` and
        // cleared anet.{state,fd}. Calling dispatch with the stale `cl`
        // pointer here would double-free in forkA12clDispatch's parent
        // path (shmifsrv_free → __libc_free → SIGSEGV in get_meta).
        // The cl pointer is local to this iteration; just skip dispatch
        // and loop back to allocate a fresh connpoint for the next try.
        // Confirmed root-cause for the bridge bringup retry crashes
        // 2026-05-03 (fossil 7c2828e9bd / bug 133 follow-up).
        if (anet.state == null) {
            a12int_trace(c.A12_TRACE_SYSTEM, "skip dispatch — forwardShmifsrvCl bailed");
            continue;
        }
        a12int_trace(c.A12_TRACE_SYSTEM, "local connection found, forwarding to dispatch");
        dispatch(args, anet.state, cl, anet.fd);
    }

    return 0;
}

/// Inherit a pre-established shmif connection (ARCAN_CONNPATH=a12://...).
fn a12Preauth(
    args: *c.struct_anet_options,
    dispatch: *const fn (*c.struct_anet_options, ?*c.struct_a12_state, ?*c.struct_shmifsrv_client, c_int) void,
) c_int {
    var sc: c_int = 0;
    const cl = c.shmifsrv_inherit_connection(args.sockfd, -1, &sc) orelse {
        _ = c.fprintf(c.stderr, "(shmif::arcan-net) couldn't build connection from socket (%d)\n", sc);
        _ = shutdown(args.sockfd, SHUT_RDWR);
        _ = c.close(args.sockfd);
        return 1;
    };

    if (global.trust_domain == null) {
        if (args.key != null) {
            const klen = c.strlen(args.key) + "outbound-".len + 1;
            const tmp = std.c.malloc(klen);
            if (tmp != null) {
                _ = c.snprintf(@ptrCast(tmp), klen, "outbound-%s", args.key);
                global.trust_domain = @ptrCast(tmp);
            }
        } else {
            global.trust_domain = @constCast("outbound");
        }
    }

    args.opts.*.local_role = c.ROLE_SOURCE;
    const anet = forwardShmifsrvCl(cl, args);
    dispatch(args, anet.state, cl, anet.fd);
    return 0;
}

// Tag parsing

fn tagHost(anet: *c.struct_anet_options, hoststr: [*c]u8, err: *[*c]const u8) bool {
    const toksep = c.strrchr(hoststr, '@') orelse return false;

    if (toksep == hoststr) {
        _ = c.fprintf(c.stderr, "host keystore tag error, %s, did you mean %s@?\n", hoststr, hoststr + 1);
        err.* = "missing tag";
        return true;
    }

    toksep[0] = 0;
    const after: [*c]u8 = toksep + 1;

    anet.key = hoststr;
    if (c.strlen(after) > 0) {
        anet.host = after;
        anet.ignore_key_host = true;
    }

    global.outbound_tag = hoststr;
    anet.keystore.type = c.A12HELPER_PROVIDER_BASEDIR;
    return true;
}

// Usage

fn showUsage(msg: ?[*c]const u8, argv: ?[*c][*c]u8, i: usize) bool {
    _ = c.fprintf(c.stderr,
        \\Usage:
        \\Forward local arcan applications (push):
        \\    arcan-net [-Xtd] -s connpoint [tag@]host port
        \\         (keystore-mode) -s connpoint tag@
        \\         (inherit socket) -S fd_no [tag@]host port
        \\
        \\Serve local arcan application (pull):
        \\         -l port [ip] -- /usr/bin/app arg1 arg2 argn
        \\
        \\Bridge remote inbound arcan applications (to ARCAN_CONNPATH):
        \\    arcan-net [-Xtd] -l port [ip]
        \\
        \\Bridge remote outbound arcan application:
        \\    arcan-net [tag@]host port
        \\
        \\Directory/discovery server:
        \\    arcan-net -c config.lua [ip]
        \\
        \\Directory/discovery client:
        \\    arcan-net [tag@]host port [appl]
        \\
        \\Directory/discovery source-client:
        \\    arcan-net [tag@]host port -- name /usr/bin/app arg1 arg2 argn
        \\
        \\Forward-local options:
        \\    -X                  Disable EXIT-redirect to ARCAN_CONNPATH env (if set)
        \\    -r, --retry n       Limit retry-reconnect attempts to 'n' tries
        \\
        \\Serve-local options:
        \\    --cast              First connection controls, others view
        \\
        \\Authentication:
        \\     --no-ephem-rt      Disable ephemeral keypair roundtrip (outbound only)
        \\    -a, --auth n        Read authentication secret from stdin (maxlen:32)
        \\                        if [n] is provided, n keys added to trusted
        \\     --soft-auth        Permit unknown via authentication secret (password)
        \\     --force-kpub s     Ignore keystore, explicit remote public key b64(s)
        \\    -T, --trust s       Specify trust domain for splitting keystore
        \\     --rekey-kb n       Issue a rekey after n kilobytes of data
        \\     --rekey-pqc        Opt in post-quantum safe encryption
        \\
        \\Options:
        \\    -c, --config fn     Specify configuration script
        \\    -t                  Single-client (no fork/mt - easier troubleshooting)
        \\     --probe-only       (outbound) Authenticate and print server primary state
        \\    -d bitmap           Set trace bitmap (bitmask or key1,key2,...)
        \\    --keystore fd       Use inherited [fd] for keystore root store
        \\    -v, --version       Print build/version information to stdout
        \\
        \\Directory client options:
        \\     --keep-appl        Don't wipe appl after execution
        \\     --block-state      Don't attempt to synch state before/after running appl
        \\     --dump-state s     Don't attempt to synch state, store output state/dump to 's'
        \\     --reload           Re-request the same appl after completion
        \\     --ident name       When attaching as a source or directory, identify as [name]
        \\     --keep-alive       Keep connection alive and print changes to the directory
        \\     --tunnel           Default request tunnelling as source/sink connection
        \\     --block-log        Don't attempt to forward script errors or crash logs
        \\     --stderr-log       Mirror script errors / crash log to stderr
        \\     --host-appl        Request that the directory server host/run the appl
        \\     --sign-tag s       Use [s] as data/appl transfer signing key
        \\     --path s           Traverse [s] as a / separate path of linked directories
        \\     --source-port      When sourcing use this port for listening
        \\
        \\     File stores (ns = .priv OR applname), (name = [a-Z-0-9])
        \\     --get-file ns name file      Retrieve [name] from namespace [ns] (.index = list)
        \\     --put-file ns name file      Store [file] as [name] in namespace [ns]
        \\
        \\Directory developer options:
        \\     --monitor-appl     Don't download/run appl, print received messages to STDOUT
        \\     --debug-appl       Redirect STDIO to appl-controller debug interface
        \\     --admin-ctrl       Redirect STDIO to server admin interface
        \\     --force-appl s     Don't download appl, but join/connect and run from [s]
        \\     --push-appl s      Push [s] from APPLBASE to the server
        \\     --push-ctrl s      Push [s] as server-side controller to appl
        \\
        \\Environment variables:
        \\    ANET_RUNNER         Used to override the default arcan binary for running dirhosted appls
        \\    ARCAN_STATEPATH     Used for keystore and state blobs (sensitive)
        \\    A12_VBP             backpressure maximum cap (0..8)
        \\    A12_VBP_SOFT        backpressure soft (full-frames) cap (< VBP)
        \\    A12_CACHE_DIR       Used for caching binary stores (fonts, ...)
        \\
        \\Local Discovery mode (ignores connection arguments):
        \\    arcan-net discover passive [ff00::/8 eg. ff00::1:6]
        \\    arcan-net discover passive-synch (will update keystore tag host)
        \\    arcan-net discover beacon [ff00::/8 eg. ff00::1:6]
        \\
        \\Keystore mode (ignores connection arguments):
        \\    Add/Append key: arcan-net keystore tagname host [port=6680]
        \\    Show public key: arcan-net keystore-show tagname
        \\                    tag=default is reserved
        \\Package mode (ignores other arguments):
        \\    Extract archive: arcan-net package extract mypackage.fap /destination/path
        \\
        \\Trace groups (stderr):
        \\    video:1      audio:2       system:4    event:8      transfer:16
        \\    debug:32     missing:64    alloc:128   crypto:256   vdetail:512
        \\    binary:1024  security:2048 directory:4096
        \\
        \\
    );

    if (msg != null) {
        if (argv != null) {
            _ = c.fprintf(c.stderr, "[%zu:%s] ", i, argv.?[i]);
        }
        _ = c.fputs(msg.?, c.stderr);
        _ = c.fputs("\n", c.stderr);
    }

    return false;
}

// Command-line parser
// Returns the index of the first unprocessed argument (mirrors the C version).
// Returns 0 on error (show_usage returns false treated as 0 by the caller).

fn applyCommandline(argc: usize, argv: [*c][*c]u8, meta: *ArcanNetMeta) usize {
    const modeerr: [*c]const u8 = "Mixed or multiple -s or -l arguments";
    const opts = &global.meta;
    opts.opts.*.local_role = c.ROLE_SINK;

    // Default-trace security warnings
    c.a12_set_trace_level(2048, c.stderr);

    var i: usize = 1;
    while (i < argc) : (i += 1) {
        const arg: []const u8 = std.mem.span(argv[i]);

        // Non-flag: host or positional
        if (arg[0] != '-') {
            if (opts.host != null or opts.key != null) {
                return i; // host collision — caller will parse rest
            }

            var err: [*c]const u8 = null;
            if (tagHost(opts, argv[i], &err)) {
                if (err != null) {
                    _ = showUsage(err, argv, i);
                    return 0;
                }
                continue;
            }

            opts.host = argv[i];
            i += 1;

            opts.port = "6680";
            if (i < argc) {
                const next: []const u8 = std.mem.span(argv[i]);
                var all_digits = true;
                for (next) |ch| {
                    if (ch < '0' or ch > '9') {
                        all_digits = false;
                        if (ch == '-') {
                            i -= 1;
                        }
                        break;
                    }
                }
                if (all_digits) {
                    opts.port = argv[i];
                } else {
                    // handled above or it's an error
                }
            }
            continue;
        }

        if (std.mem.eql(u8, arg, "--sign-tag")) {
            if (i >= argc - 1) { _ = showUsage("Missing --sign-tag tag", argv, i - 1); return 0; }
            if (global.dircl.sign_tag != null) { _ = showUsage("Multiple --sign-tag arguments", argv, i - 1); return 0; }
            i += 1;
            global.dircl.sign_tag = argv[i];
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            _ = c.fprintf(c.stdout, "shmif-%llu\n", c.arcan_shmif_cookie());
            c.exit(0);
        } else if (std.mem.eql(u8, arg, "-d")) {
            if (i >= argc - 1) { _ = showUsage("Missing trace value argument", argv, i - 1); return 0; }
            i += 1;
            const val_str: []const u8 = std.mem.span(argv[i]);
            const val = std.fmt.parseInt(c_ulong, val_str, 10) catch blk: {
                // not a decimal number — parse as comma-separated trace group names
                const mutable = @constCast(argv[i]);
                break :blk @as(c_ulong, @intCast(tracestrToBitmap(mutable[0..val_str.len])));
            };
            c.a12_set_trace_level(@intCast(val), c.stderr);
        } else if (std.mem.eql(u8, arg, "-s")) {
            if (opts.mode != 0) { _ = showUsage(modeerr, argv, i); return 0; }
            opts.opts.*.local_role = c.ROLE_SOURCE;
            opts.mode = @intFromEnum(AnetMode.shmif_srv);
            if (i >= argc - 1) { _ = showUsage("Missing connpoint argument", argv, i - 1); return 0; }
            i += 1;
            opts.cp = argv[i];
            if (std.mem.span(opts.cp)) |cp_s| {
                for (cp_s) |ch| {
                    if (!std.ascii.isAlphanumeric(ch)) {
                        _ = showUsage("-s: Invalid character in connpoint [a-Z,0-9]", argv, i);
                        return 0;
                    }
                }
            }
        } else if (std.mem.eql(u8, arg, "-S")) {
            if (opts.mode != 0) { _ = showUsage(modeerr, argv, i); return 0; }
            opts.mode = @intFromEnum(AnetMode.shmif_srv_inherit);
            if (i >= argc - 1) { _ = showUsage("Missing socket argument", argv, i); return 0; }
            i += 1;
            opts.sockfd = @intCast(std.fmt.parseInt(c_ulong, std.mem.span(argv[i]), 10) catch 0);

            // std.mem.zeroes(c.struct_stat) breaks with musl's timespec opaque
            // translation; use std.posix.fstat which is architecturally clean.
            const fdstat = std.posix.fstat(opts.sockfd) catch {
                _ = showUsage("Couldn't stat -S descriptor", argv, i);
                return 0;
            };

            if (c.getenv("ARCAN_SOCKIN_FD") != null) {
                opts.mode = @intFromEnum(AnetMode.shmif_dirsrv_inherit);
                opts.opts.*.local_role = c.ROLE_DIR;
                continue;
            }

            if ((fdstat.mode & std.posix.S.IFMT) != std.posix.S.IFSOCK) {
                _ = showUsage("-S descriptor does not point to a socket", argv, i);
                return 0;
            }

            if (i == argc) { _ = showUsage("missing tag or host port", argv, i - 1); return 0; }
            i += 1;

            var err: [*c]const u8 = null;
            if (tagHost(opts, argv[i], &err)) {
                if (err != null) { _ = showUsage(err, argv, i); return 0; }
                continue;
            }

            opts.host = argv[i];
            i += 1;
            if (i == argc) { _ = showUsage("Missing port argument", argv, i - 1); return 0; }
            opts.port = argv[i];
            i += 1;
            if (i < argc) { _ = showUsage("Trailing arguments to -S fd_in host port", argv, i); return 0; }
        } else if (std.mem.eql(u8, arg, "--tunnel")) {
            global.dircl.request_tunnel = true;
        } else if (std.mem.eql(u8, arg, "--keep-alive")) {
            global.keep_alive = true;
        } else if (std.mem.eql(u8, arg, "--force-kpub")) {
            if (i >= argc) { _ = showUsage("Missing b64(kpub)", argv, i - 1); return 0; }
            i += 1;
            global.use_forced_remote_pubk = true;
            if (!c.a12helper_fromb64(argv[i], 32, &global.forced_remote_pubk)) {
                _ = showUsage("--forced-kpub: bad base64 encoded key", argv, i);
                return 0;
            }
            if (c.getenv("A12_USEPRIV") == null) {
                _ = showUsage("--forced-kpub without A12_USEPRIV env set", argv, i);
                return 0;
            }
            var my_private_key: [32]u8 = undefined;
            const usepriv = c.getenv("A12_USEPRIV") orelse {
                _ = showUsage("--forced-kpub without A12_USEPRIV env set", argv, i);
                return 0;
            };
            if (!c.a12helper_fromb64(usepriv, 32, &my_private_key)) {
                _ = showUsage("--forced-kpub A12_USEPRIV env invalid b64(key)", argv, i);
                return 0;
            }
        } else if (std.mem.eql(u8, arg, "--path")) {
            i += 1;
            if (i >= argc) { _ = showUsage("Missing path", argv, i - 1); return 0; }
            if (!resnameToDircl(std.mem.span(argv[i]), &global.dircl.dpath)) {
                _ = showUsage("Invalid path specified", argv, i - 1);
                return 0;
            }
        } else if (std.mem.eql(u8, arg, "--push-appl") or std.mem.eql(u8, arg, "--push-ctrl")) {
            if (std.mem.eql(u8, arg, "--push-ctrl"))
                global.dircl.outapp_ctrl = true;
            i += 1;
            if (i >= argc) { _ = showUsage("Missing applname", argv, i - 1); return 0; }

            const appl_arg: []const u8 = std.mem.span(argv[i]);
            if (appl_arg[0] == '.' or appl_arg[0] == '/') {
                const path = c.strrchr(argv[i], '/') orelse {
                    _ = showUsage("--push*: /path/to/appl: invalid path format", argv, i);
                    return 0;
                };
                path[0] = 0;
                if (c.chdir(argv[i]) == -1) { _ = showUsage("--push*: couldn't reach appl root dir", argv, i); return 0; }
                argv[i] = path + 1;
            } else if (c.getenv("ARCAN_APPLBASEPATH") == null) {
                _ = showUsage("--push*: name should be full path or relative ARCAN_APPLBASEPATH", argv, i);
                return 0;
            } else if (c.chdir(c.getenv("ARCAN_APPLBASEPATH").?) == -1 or c.chdir(argv[i]) == -1) {
                _ = showUsage("--push*: ARCAN_APPLBASEPATH: couldn't chdir to basepath/name", argv, i);
                return 0;
            }

            const dirfd = c.open(".", c.O_RDONLY | c.O_DIRECTORY);
            if (dirfd == -1) { _ = showUsage("--push*: couldn't resolve working directory", argv, i); return 0; }
            if (global.dircl.build_appl != null) { _ = showUsage("multiple --push* arguments provided", argv, i); return 0; }
            global.dircl.build_appl_dfd = dirfd;
            global.dircl.build_appl = argv[i];
        } else if (std.mem.eql(u8, arg, "--get-file")) {
            i += 1;
            if (i >= argc) { _ = showUsage("Missing namespace", argv, i); return 0; }
            if (global.dircl.upload.name != null or global.dircl.upload.srvname[0] != 0 or
                global.dircl.download.name != null or global.dircl.download.srvname[0] != 0)
            { _ = showUsage("only one --get-file or --put-file", argv, i); return 0; }
            _ = c.snprintf(&global.dircl.download.srvname, 16, "%s", argv[i]);
            i += 1;
            if (i >= argc) { _ = showUsage("Missing --get-file name argument", argv, i); return 0; }
            global.dircl.download.name = argv[i];
            if (c.strlen(global.dircl.download.name) > 67) { _ = showUsage("server-side name length too long (> 67b)", argv, i - 1); return 0; }
            i += 1;
            if (i >= argc) { _ = showUsage("Missing --get-file path argument", argv, i); return 0; }
            global.dircl.download.path = argv[i];
        } else if (std.mem.eql(u8, arg, "--put-file")) {
            i += 1;
            if (i >= argc) { _ = showUsage("Missing namespace", argv, i); return 0; }
            if (global.dircl.upload.name != null or global.dircl.upload.srvname[0] != 0 or
                global.dircl.download.name != null or global.dircl.download.srvname[0] != 0)
            { _ = showUsage("only one --get-file or --put-file", argv, i); return 0; }
            _ = c.snprintf(&global.dircl.upload.srvname, 16, "%s", argv[i]);
            i += 1;
            if (i >= argc) { _ = showUsage("Missing --put-file name argument", argv, i); return 0; }
            global.dircl.upload.name = argv[i];
            if (c.strlen(global.dircl.upload.name) > 67) { _ = showUsage("server-side name length too long (> 67b)", argv, i - 1); return 0; }
            i += 1;
            if (i >= argc) { _ = showUsage("Missing --put-file path argument", argv, i); return 0; }
            global.dircl.upload.path = argv[i];
        } else if (std.mem.eql(u8, arg, "--ident")) {
            i += 1;
            if (i == argc) { _ = showUsage("Missing name argument", argv, i); return 0; }
            _ = c.snprintf(&global.dircl.ident, 16, "%s", argv[i]);
        } else if (std.mem.eql(u8, arg, "--soft-auth")) {
            global.soft_auth = true;
        } else if (std.mem.eql(u8, arg, "--no-ephem-rt")) {
            opts.opts.*.disable_ephemeral_k = true;
        } else if (std.mem.eql(u8, arg, "--keystore")) {
            i += 1;
            if (i >= argc - 1) { _ = showUsage("Missing keystore descriptor argument", argv, i); return 0; }
            opts.keystore.unnamed_0.directory.dirfd = @intCast(std.fmt.parseInt(c_ulong, std.mem.span(argv[i]), 10) catch 0);
        } else if (std.mem.eql(u8, arg, "--probe-only")) {
            opts.opts.*.local_role = c.ROLE_PROBE;
            global.probe_only = true;
        } else if (std.mem.eql(u8, arg, "--") or std.mem.eql(u8, arg, "--exec")) {
            i += 1;
            opts.opts.*.local_role = c.ROLE_SOURCE;
            meta.bin = argv[i];
            meta.argv = argv + i;
            opts.mode = @intFromEnum(AnetMode.shmif_exec_outbound);
            return i;
        } else if (std.mem.eql(u8, arg, "-l")) {
            if (opts.mode != 0) { _ = showUsage(modeerr, argv, i); return 0; }
            opts.mode = @intFromEnum(AnetMode.shmif_cl);
            if (i >= argc - 1) { _ = showUsage("Missing port argument", argv, i - 1); return 0; }
            i += 1;
            opts.port = argv[i];
            if (std.mem.span(opts.port)) |port_s| {
                for (port_s) |ch| {
                    if (ch < '0' or ch > '9') { _ = showUsage("Invalid values in port argument", argv, i); return 0; }
                }
            }
            i += 1;
            if (i == argc) return i;

            const next: []const u8 = std.mem.span(argv[i]);
            if (!std.mem.eql(u8, next, "--exec") and !std.mem.eql(u8, next, "--")) {
                opts.host = argv[i];
                i += 1;
                if (i >= argc - 1) return i;
            }

            const next2: []const u8 = std.mem.span(argv[i]);
            if (!std.mem.eql(u8, next2, "--exec") and !std.mem.eql(u8, next2, "--")) {
                _ = showUsage("Unexpected trailing argument, expected --exec or end", argv, i);
                return 0;
            }

            i += 1;
            if (i == argc) { _ = showUsage("Missing exec arguments: bin arg0 .. argn", argv, i - 1); return 0; }
            meta.bin = argv[i];
            meta.argv = argv + i;
            opts.mode = @intFromEnum(AnetMode.shmif_exec);
            opts.opts.*.local_role = c.ROLE_SOURCE;
            return i;
        } else if (std.mem.eql(u8, arg, "-T") or std.mem.eql(u8, arg, "--trust")) {
            i += 1;
            if (i == argc) { _ = showUsage("Missing domain argument", argv, i - 1); return 0; }
            global.trust_domain = argv[i];
        } else if (std.mem.eql(u8, arg, "--rekey-kb")) {
            i += 1;
            if (i == argc) { _ = showUsage("Missing rekey kilobytes arguments", argv, i - 1); return 0; }
            const kb = std.fmt.parseInt(usize, std.mem.span(argv[i]), 10) catch 0;
            opts.opts.*.rekey_bytes = 1024 * kb;
            if (opts.opts.*.rekey_bytes == 0) { _ = showUsage("--rekey-kb n failed, n < 1 or invalid", argv, i); return 0; }
        } else if (std.mem.eql(u8, arg, "--rekey-pqc")) {
            opts.opts.*.pqc_rekey = true;
        } else if (std.mem.eql(u8, arg, "--keep-appl")) {
            global.dircl.keep_appl = true;
        } else if (std.mem.eql(u8, arg, "--block-log")) {
            global.dircl.block_log = true;
        } else if (std.mem.eql(u8, arg, "--stderr-log")) {
            global.dircl.stderr_log = true;
        } else if (std.mem.eql(u8, arg, "--host-appl")) {
            global.dircl.applhost = true;
        } else if (std.mem.eql(u8, arg, "--block-state")) {
            global.dircl.block_state = true;
        } else if (std.mem.eql(u8, arg, "--dump-state")) {
            i += 1;
            if (i == argc) { _ = showUsage("Missing state filename", argv, i - 1); return 0; }
            global.dircl.dump_state = argv[i];
        } else if (std.mem.eql(u8, arg, "--reload")) {
            global.dircl.reload = true;
        } else if (std.mem.eql(u8, arg, "--monitor-appl")) {
            global.dircl.monitor_mode = c.MONITOR_SIMPLE;
        } else if (std.mem.eql(u8, arg, "--admin-ctrl")) {
            global.dircl.monitor_mode = c.MONITOR_ADMIN;
        } else if (std.mem.eql(u8, arg, "--force-appl")) {
            i += 1;
            if (i == argc) { _ = showUsage("Missing appl path", argv, i - 1); return 0; }
            global.dircl.appl_override = argv[i];
        } else if (std.mem.eql(u8, arg, "--debug-appl")) {
            global.dircl.monitor_mode = c.MONITOR_DEBUGGER;
        } else if (std.mem.eql(u8, arg, "--source-port")) {
            i += 1;
            if (i == argc) { _ = showUsage("Missing port argument", argv, i - 1); return 0; }
            const sp = std.fmt.parseInt(u16, std.mem.span(argv[i]), 10) catch 0;
            if (sp == 0) { _ = showUsage("--source-port invalid", argv, i); return 0; }
            global.dircl.source_port = sp;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i == argc) { _ = showUsage("Missing config file argument (/path/to/config.lua", argv, i - 1); return 0; }
            global.config_file = argv[i];
            _ = c.close(c.STDIN_FILENO);
            _ = c.open("/dev/null", c.O_RDONLY);
        } else if (std.mem.eql(u8, arg, "-X")) {
            opts.redirect_exit = null;
            opts.devicehint_cp = null;
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--auth")) {
            var msg: [32]u8 = undefined;
            if (c.isatty(c.STDIN_FILENO) != 0) {
                const pwd = c.getpass("connection password: ");
                _ = c.snprintf(&msg, 32, "%s", pwd);
                var p = pwd;
                while (p[0] != 0) : (p += 1) p[0] = 0;
            } else {
                _ = c.fprintf(c.stdout, "reading passphrase from stdin\n");
                if (c.fgets(&msg, 32, c.stdin) == null) {
                    _ = showUsage("Couldn't read secret from stdin", argv, i);
                    return 0;
                }
            }
            const len = c.strlen(&msg);
            if (len == 0) { _ = showUsage("Zero-length secret not permitted", argv, i); return 0; }
            if (msg[len - 1] == '\n') msg[len - 1] = 0;
            _ = c.snprintf(&opts.opts.*.secret, 32, "%s", &msg);
            global.no_default = true;

            if (i < argc - 1 and std.ascii.isDigit(argv[i + 1][0])) {
                i += 1;
                global.accept_n_pk_unknown = std.fmt.parseInt(usize, std.mem.span(argv[i]), 10) catch 0;
                a12int_trace(c.A12_TRACE_SECURITY, "trust_first=%zu", global.accept_n_pk_unknown);
            }
        } else if (std.mem.eql(u8, arg, "-B")) {
            // bitrate argument — consumed but otherwise ignored here
            if (i == argc - 1) { _ = showUsage("Missing bitrate argument", argv, i - 1); return 0; }
            if (!std.ascii.isDigit(argv[i + 1][0])) { _ = showUsage("Bitrate should be a number", argv, i); return 0; }
        } else if (std.mem.eql(u8, arg, "--cast")) {
            global.cast = true;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--retry")) {
            if (i < argc - 1) {
                i += 1;
                opts.retry_count = std.fmt.parseInt(isize, std.mem.span(argv[i]), 10) catch -1;
            } else {
                _ = showUsage("Missing count argument", argv, i - 1);
                return 0;
            }
        }
        // unknown flags: fall through (C code does the same silently)
    }

    // Handle A12_VBP / A12_VBP_SOFT env overrides after parsing all flags
    if (c.getenv("A12_VBP")) |tmp| {
        const bp = std.fmt.parseInt(usize, std.mem.span(tmp), 10) catch 0;
        if (bp <= 8) global.backpressure = bp;
    }
    if (c.getenv("A12_VBP_SOFT")) |tmp| {
        const bp = std.fmt.parseInt(usize, std.mem.span(tmp), 10) catch 0;
        if (bp <= global.backpressure) global.backpressure_soft = bp;
    }

    return i;
}

// Discovery

fn discoverBeacon(
    cont: ?*c.struct_arcan_shmif_cont,
    kpub: [*c]const u8,
    nonce: [*c]const u8,
    tag: [*c]const u8,
    addr: [*c]u8,
) callconv(.c) bool {
    _ = cont;
    _ = nonce;
    const nullk = [_]u8{0} ** 32;
    if (std.mem.eql(u8, kpub[0..32], &nullk)) {
        _ = c.fprintf(c.stderr, "bad_beacon:source=%s\n", addr);
        return true;
    }
    var outl: usize = 0;
    const b64 = c.a12helper_tob64(kpub, 32, &outl);
    _ = c.fprintf(c.stdout, "beacon:kpub=%s:tag=%s:source=%s\n", b64, if (tag != null) tag else @as([*c]const u8, "not_found"), addr);

    if (tag != null and global.discover_synch) {
        var privk: [32]u8 = undefined;
        var outhost: [*c]u8 = null;
        var outport: u16 = 0;
        var i: usize = 0;
        while (c.a12helper_keystore_hostkey(tag, @intCast(i), &privk, &outhost, &outport)) : (i += 1) {
            if (c.strcmp(outhost, addr) == 0) {
                std.c.free(outhost);
                break;
            }
            std.c.free(outhost);
        }
    }

    std.c.free(b64);
    return true;
}

fn discoverUnknown(name: [*c]u8) callconv(.c) void {
    _ = c.fprintf(c.stderr, "unknown_beacon:source=%s\n", name);
}

fn sendBeacon(ipv6_ptr: ?*anyopaque) callconv(.c) ?*anyopaque {
    const ipv6: [*c]u8 = if (ipv6_ptr != null) @ptrCast(@alignCast(ipv6_ptr)) else null;
    var cfg = std.mem.zeroes(c.struct_anet_discover_opts);
    cfg.limit = -1;
    cfg.timesleep = 10;
    cfg.ipv6 = ipv6;

    var opts = std.mem.zeroes(c.struct_anet_options);
    opts.keystore.unnamed_0.directory.dirfd = -1;

    var err: [*c]const u8 = null;
    if (!openKeystore(&opts, &err)) {
        _ = c.fprintf(c.stderr, "couldn't open keystore: %s\n", err);
        return null;
    }

    const cerr = c.a12helper_discover_ipcfg(&cfg, true);
    if (cerr != null) {
        _ = c.fprintf(c.stderr, "discover setup failed: %s\n", cerr);
        return null;
    }

    while (c.anet_discover_send_beacon(&cfg)) {}
    return null;
}

fn sendDirsrvBeacon(ipv6_ptr: ?*anyopaque) callconv(.c) ?*anyopaque {
    const ipv6: [*c]u8 = if (ipv6_ptr != null) @ptrCast(@alignCast(ipv6_ptr)) else null;
    var cfg = std.mem.zeroes(c.struct_anet_discover_opts);
    cfg.limit = -1;
    cfg.timesleep = 10;
    cfg.ipv6 = ipv6;

    const cerr = c.a12helper_discover_ipcfg(&cfg, true);
    if (cerr != null) {
        _ = c.fprintf(c.stderr, "discover setup failed: %s\n", cerr);
        return null;
    }
    while (c.anet_discover_send_beacon(&cfg)) {}
    return null;
}

fn runDiscoverCommand(argc: usize, argv: [*c][*c]u8) c_int {
    var ipv6: [*c]u8 = null;

    if (argc > 3) {
        const last: []const u8 = std.mem.span(argv[argc - 1]);
        if (!std.mem.eql(u8, last, "passive") and
            !std.mem.eql(u8, last, "passive-synch") and
            !std.mem.eql(u8, last, "beacon"))
        {
            ipv6 = argv[argc - 1];
        }
    }

    const mode2: []const u8 = if (argc > 2) std.mem.span(argv[2]) else "";
    if (argc <= 2 or (!std.mem.eql(u8, mode2, "passive") and !std.mem.eql(u8, mode2, "passive-synch"))) {
        var pth: c.pthread_t = undefined;
        var pthattr: c.pthread_attr_t = undefined;
        _ = c.pthread_attr_init(&pthattr);
        _ = c.pthread_attr_setdetachstate(&pthattr, c.PTHREAD_CREATE_DETACHED);

        if (argc <= 2 or !std.mem.eql(u8, mode2, "beacon")) {
            _ = c.pthread_create(&pth, &pthattr, sendBeacon, ipv6);
        } else {
            _ = sendBeacon(ipv6);
            return 0;
        }
    }

    var cfg = std.mem.zeroes(c.struct_anet_discover_opts);
    cfg.discover_beacon = discoverBeacon;
    cfg.discover_unknown = discoverUnknown;
    cfg.ipv6 = ipv6;

    global.discover_synch = (argc > 2 and std.mem.eql(u8, mode2, "passive-synch"));

    var opts = std.mem.zeroes(c.struct_anet_options);
    opts.keystore.unnamed_0.directory.dirfd = -1;
    var err: [*c]const u8 = null;
    if (!openKeystore(&opts, &err)) {
        _ = c.fprintf(c.stderr, "couldn't open keystore: %s\n", err);
        return 1;
    }

    const cerr = c.a12helper_discover_ipcfg(&cfg, true);
    if (cerr != null) {
        _ = c.fprintf(c.stderr, "couldn't setup discover: %s\n", cerr);
        return 1;
    }

    c.anet_discover_listen_beacon(&cfg);
    return 0;
}

// Keystore commands

fn applyKeystoreShowCommand(argc: usize, argv: [*c][*c]u8) c_int {
    var opts = std.mem.zeroes(c.struct_anet_options);
    opts.keystore.unnamed_0.directory.dirfd = -1;
    var err: [*c]const u8 = null;

    if (!openKeystore(&opts, &err)) {
        _ = showUsage(err, null, 0);
        return 1;
    }

    const name: [*c]const u8 = if (argc > 2) argv[2] else "default";
    var private: [32]u8 = undefined;
    var public: [32]u8 = undefined;
    var tmp: [*c]u8 = null;
    var tmpport: u16 = 0;

    if (!c.a12helper_keystore_hostkey(argv[2], 0, &private, &tmp, &tmpport)) {
        _ = c.fprintf(c.stderr, "no key matching '%s'\n", name);
        return 1;
    }

    // Derive public key using std.crypto.dh.X25519
    const kp = std.crypto.dh.X25519.KeyPair.generateDeterministic(private) catch {
        _ = c.fprintf(c.stderr, "key derivation failed\n");
        return 1;
    };
    public = kp.public_key;

    var outl: usize = 0;
    const b64 = c.a12helper_tob64(&public, 32, &outl);
    _ = c.fprintf(c.stdout, "public key for '%s':\n%s\n", name, b64);
    std.c.free(b64);

    return 0;
}

fn runPackageCommand(argc: usize, argv: [*c][*c]u8) c_int {
    if (argc <= 0 or c.strcmp(argv[0], "extract") != 0)
        return c.EXIT_FAILURE;

    if (argc != 3) {
        _ = c.fprintf(c.stderr, "extract: invalid argument count (%d).\n", @as(c_int, @intCast(argc)));
        return c.EXIT_FAILURE;
    }

    const fpek = c.fopen(argv[1], "r") orelse {
        _ = c.fprintf(c.stderr, "extract: couldn't open %s\n", argv[1]);
        return c.EXIT_FAILURE;
    };

    const dfd = c.open(argv[2], c.O_DIRECTORY);
    if (dfd == -1) {
        _ = c.fprintf(c.stderr, "extract: couldn't open destination root %s\n", argv[2]);
        _ = c.fclose(fpek);
        return c.EXIT_FAILURE;
    }

    // Strip extension from src to use as basename.
    const src_len = c.strlen(argv[1]);
    if (src_len > 0) {
        var i: isize = @intCast(src_len - 1);
        while (i >= 0) : (i -= 1) {
            if (argv[1][@intCast(i)] == '.') {
                argv[1][@intCast(i)] = 0;
                break;
            }
        }
    }

    var msg: ?[*:0]const u8 = null;
    var arr: ?*c.struct_arg_arr = null;
    if (!c.extract_appl_pkg(fpek, dfd, @ptrCast(argv[1]), &msg, &arr)) {
        _ = c.fprintf(c.stderr, " extract failed: %s\n", msg orelse "(unknown)");
        _ = c.fclose(fpek);
        _ = c.close(dfd);
        return c.EXIT_FAILURE;
    }

    _ = c.printf("Package extraction successful.\nmanifest:\n");
    if (arr) |a| {
        const entries: [*]c.struct_arg_arr = @ptrCast(a);
        var i: usize = 0;
        while (entries[i].key != null) : (i += 1) {
            const val: [*:0]const u8 = if (entries[i].value) |v| v else "[set]";
            _ = c.printf("\t%s = %s\n", entries[i].key, val);
        }
    }

    _ = c.fclose(fpek);
    _ = c.close(dfd);
    return c.EXIT_SUCCESS;
}

fn applyKeystoreCommand(argc: usize, argv: [*c][*c]u8) c_int {
    var opts = std.mem.zeroes(c.struct_anet_options);
    opts.keystore.unnamed_0.directory.dirfd = -1;
    var err: [*c]const u8 = null;

    if (!openKeystore(&opts, &err)) {
        _ = showUsage(err, null, 0);
        return 1;
    }

    if (argc < 4) {
        _ = c.a12helper_keystore_release();
        _ = showUsage("Keystore: Missing tag / host arguments", null, 0);
        return 1;
    }

    const tag = argv[2];
    const host = argv[3];
    var port: c_ulong = 6680;

    if (argc > 4) {
        port = std.fmt.parseInt(c_ulong, std.mem.span(argv[4]), 10) catch 0;
        if (port == 0 or port > 65535) {
            _ = c.a12helper_keystore_release();
            _ = showUsage("Port argument is invalid or out of range", argv, 4);
            return 1;
        }
    }

    var outpub: [32]u8 = undefined;
    if (!c.a12helper_keystore_register(tag, host, @intCast(port), &outpub, null)) {
        _ = showUsage("Couldn't add/create tag in keystore", null, 0);
        return 1;
    }

    var outl: usize = 0;
    const b64 = c.a12helper_tob64(&outpub, 32, &outl);
    _ = c.fprintf(c.stdout, "add a12/accepted/(filename) in remote keystore:\n* %s\n", b64);
    std.c.free(b64);
    _ = c.a12helper_keystore_release();

    return 0;
}

// Key authentication callback

fn keyAuthLocal(
    S: [*c]c.struct_a12_state,
    pk: [*c]u8,
    tag: ?*anyopaque,
) callconv(.c) c.struct_pk_response {
    _ = tag;
    var auth = std.mem.zeroes(c.struct_pk_response);
    var my_private_key: [32]u8 = undefined;
    var tmp: [*c]u8 = null;
    var tmpport: u16 = 0;
    var outl: usize = 0;

    if (global.use_forced_remote_pubk) {
        if (!std.mem.eql(u8, pk[0..32], global.forced_remote_pubk[0..32]))
            return auth;

        a12int_trace(c.A12_TRACE_SECURITY, "accept_forced=true");
        const force_priv = c.getenv("A12_USEPRIV");
        if (force_priv != null and c.a12helper_fromb64(force_priv.?, 32, &my_private_key)) {
            auth.authentic = true;
            c.a12_set_session(&auth, pk, &my_private_key);
        } else if (force_priv == null) {
            auth.authentic = true;
            _ = c.a12helper_keystore_hostkey("default", 0, &my_private_key, &tmp, &tmpport);
            c.a12_set_session(&auth, pk, &my_private_key);
        } else {
            a12int_trace(c.A12_TRACE_SECURITY, "a12_usepriv:error=b64decode_fail");
            auth.authentic = false;
        }
        return auth;
    }

    const out = c.a12helper_tob64(pk, 32, &outl);
    defer std.c.free(out);

    if (c.a12helper_keystore_accepted(pk[0..32], if (global.directory != -1) @constCast("*") else global.trust_domain) != null) {
        auth.authentic = true;
        a12int_trace(c.A12_TRACE_SECURITY, "accept=%s", out);
        _ = c.a12helper_keystore_hostkey("default", 0, &my_private_key, &tmp, &tmpport);
        c.a12_set_session(&auth, pk, &my_private_key);
    } else if (global.soft_auth) {
        auth.authentic = true;
        _ = c.a12helper_keystore_hostkey("default", 0, &my_private_key, &tmp, &tmpport);
        c.a12_set_session(&auth, pk, &my_private_key);
        a12int_trace(c.A12_TRACE_SECURITY, "soft-auth-trust=%s", out);
    } else if (global.accept_n_pk_unknown != 0) {
        auth.authentic = true;
        global.accept_n_pk_unknown -= 1;
        a12int_trace(c.A12_TRACE_SECURITY, "left=%zu:accept-unknown=%s", global.accept_n_pk_unknown, out);
        _ = c.a12helper_keystore_accept(pk[0..32], global.trust_domain);
        _ = c.a12helper_keystore_hostkey("default", 0, &my_private_key, &tmp, &tmpport);
        c.a12_set_session(&auth, pk, &my_private_key);
    } else if (!auth.authentic) {
        var tag_buf: [*c]u8 = null;
        var ofs: usize = 0;

        if (c.a12helper_query_untrusted_key(global.trust_domain, @ptrCast(out), pk[0..32], &tag_buf, &ofs)) {
            auth.authentic = true;
            _ = c.a12helper_keystore_hostkey("default", 0, &my_private_key, &tmp, &tmpport);
            c.a12_set_session(&auth, pk, &my_private_key);
            a12int_trace(c.A12_TRACE_SECURITY, "interactive-soft-auth=%s", out);

            if (tag_buf[0] != 0) {
                a12int_trace(c.A12_TRACE_SECURITY, "interactive-add-trust=%s:tag=%s", out, tag_buf);
                _ = c.a12helper_keystore_accept(pk[0..32], tag_buf);

                if (ofs != 0 and global.meta.host != null) {
                    var pubk: [32]u8 = undefined;
                    const port_s = std.mem.span(global.meta.port) orelse "";
                    const port = std.fmt.parseInt(c_ulong, port_s, 10) catch 0;
                    _ = c.a12helper_keystore_register(tag_buf + ofs, global.meta.host, @intCast(port), &pubk, &my_private_key);
                    a12int_trace(c.A12_TRACE_SECURITY, "store-hostkey-tag=%s", tag_buf + ofs);
                }
            }
            std.c.free(tag_buf);
        } else {
            a12int_trace(c.A12_TRACE_SECURITY, "reject-untrusted-remote=%s", out);
        }
    }

    if (auth.authentic and global.directory != -1)
        auth.state_access = c.a12helper_keystore_statestore;

    _ = S;
    return auth;
}

// main

// Entry point as a C `int main(int, char**)`. Using the exported form
// (not `pub fn main() void`) bypasses start.zig's comptime `@export`
// wrapper — that wrapper path regresses on the no-LLVM Zig fork,
// silently emitting an object with no `.text` section. C-ABI main
// matches the convention already used by frameserver.zig / arcan_main.zig
// and gives us argc/argv directly, so we can drop the GPA + std.process
// argument collection too.
pub export fn arcan_net_main(argc_c: c_int, argv_c: [*c][*c]u8) callconv(.c) c_int {
    // Ignore SIGPIPE; reap children automatically
    const ignore = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.IGN },
        .mask = std.mem.zeroes(posix.sigset_t),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.PIPE, &ignore, null);
    posix.sigaction(posix.SIG.CHLD, &ignore, null);

    // Workaround for fossil 308e620ec7 / 167: Debug codegen materialises
    // struct_a12_state (204 KB) on the stack of a12int_append_out, producing
    // a 7.8 MB stack frame that overflows the default 8 MB main-thread limit
    // mid-handshake (between process_srvfirst and the recursive
    // process_control → send_hello_packet path). Push gets ulimit -s
    // unlimited from its wrapper script; the listener has no equivalent and
    // SIGSEGVs silently before flushing the next stderr trace, leaving the
    // bridge stalled at "process_srvfirst init_nonce". Lift our own
    // RLIMIT_STACK at startup so every role (listener / push / dir-srv)
    // survives the spilled frame. Complementary to the existing
    // pthread_attr_setstacksize(32 MB) on segment threads in helper_cl /
    // helper_srv — that protects spawned threads, this protects main.
    var rl = c.struct_rlimit{ .rlim_cur = c.RLIM_INFINITY, .rlim_max = c.RLIM_INFINITY };
    _ = c.setrlimit(c.RLIMIT_STACK, &rl);

    const argc: usize = @intCast(argc_c);
    const argv: [*c][*c]u8 = argv_c;

    // Defaults
    global.meta.retry_count = -1;
    global.db_file = c.strdup(":memory:");
    global.outbound_tag = c.strdup("default");
    global.path_self = argv[0];
    global.meta.opts = @ptrCast(@alignCast(c.a12_sensitive_alloc(@sizeOf(c.struct_a12_context_options))));
    global.meta.opts.*.pk_lookup = keyAuthLocal;
    global.meta.keystore.unnamed_0.directory.dirfd = -1;
    global.dirsrv.a12_cfg = global.meta.opts;

    global.meta.redirect_exit = c.getenv("ARCAN_CONNPATH");
    global.meta.devicehint_cp = c.getenv("ARCAN_CONNPATH");

    // Sub-commands
    if (argc > 1 and c.strcmp(argv[1], "keystore") == 0)
        c.exit(applyKeystoreCommand(argc, argv));

    if (argc > 1 and c.strcmp(argv[1], "keystore-show") == 0)
        c.exit(applyKeystoreShowCommand(argc, argv));

    if (argc > 1 and c.strcmp(argv[1], "discover") == 0)
        c.exit(runDiscoverCommand(argc, argv));

    if (argc > 1 and c.strcmp(argv[1], "package") == 0)
        c.exit(runPackageCommand(if (argc >= 2) argc - 2 else 0, &argv[2]));

    if (argc > 1 and c.strncmp(argv[1], "dirappl", 7) == 0) {
        c.anet_directory_appl_runner();
        c.exit(0);
    }

    if (argc > 1 and (c.strcmp(argv[1], "dirlink") == 0 or c.strcmp(argv[1], "dirref") == 0)) {
        var err: [*c]const u8 = null;
        if (argc != 4 or !openKeystore(&global.meta, &err))
            c.exit(1);

        global.meta.opts.*.local_role =
            if (c.strcmp(argv[1], "dirref") == 0) c.ROLE_DIRREF else c.ROLE_DIR;

        const diropts = std.mem.zeroes(c.struct_anet_dirsrv_opts);
        c.a12_trace_targets = 8191;

        const trust_klen = c.strlen(argv[3]) + "outbound-".len + 1;
        const trust_tmp = std.c.malloc(trust_klen) orelse c.exit(1);
        _ = c.snprintf(@ptrCast(trust_tmp), trust_klen, "outbound-%s", argv[3]);
        global.trust_domain = @ptrCast(trust_tmp);
        setLogTrace("link_log");

        c.exit(c.anet_directory_link(
            argv[3],
            &global.meta,
            diropts,
            argv[2],
            c.strcmp(argv[1], "dirlink") != 0,
        ));
    }

    if (argc < 2 or (argc == 2 and
        (c.strcmp(argv[1], "-h") == 0 or c.strcmp(argv[1], "--help") == 0)))
    {
        _ = showUsage(null, null, 0);
        c.exit(1);
    }

    const argi = applyCommandline(argc, argv, &argv_output);

    if (argi == 0 and global.meta.mode != @intFromEnum(AnetMode.shmif_dirsrv_inherit) and global.meta.host == null)
        c.exit(1);

    if (!c.anet_lua_init(&global)) {
        _ = c.fprintf(c.stderr, "Couldn't setup Lua VM state, exiting.\n");
        c.exit(1);
    }

    // No mode set: outbound connection (reverse mode)
    if (global.meta.mode == 0) {
        // dir-client / outbound positional-args path: we act as the source side
        // of the dir-client handshake. Without this, send_hello_packet would
        // emit outb[54]=ROLE_SINK (the apply_commandline default), which the
        // directory server rejects with an immediate FIN at auth.
        if (global.meta.opts.*.local_role == c.ROLE_SINK)
            global.meta.opts.*.local_role = c.ROLE_SOURCE;
        const cl = findConnection(&global.meta, null);
        if (cl.state == null) {
            if (global.meta.key != null)
                _ = c.fprintf(c.stderr, "couldn't connect to any host for key %s\n", global.meta.key)
            else
                _ = c.fprintf(c.stderr, "couldn't connect to %s\n", global.meta.host);
            c.exit(1);
        }

        if (global.probe_only) {
            _ = c.printf("authenticated:remote_mode=%d\n", c.a12_remote_mode(cl.state));
            _ = shutdown(cl.fd, SHUT_RDWR);
            _ = c.close(cl.fd);
            c.exit(0);
        }

        var rc: c_int = 0;
        if (c.a12_remote_mode(cl.state) == c.ROLE_DIR) {
            if (global.dircl.build_appl != null) {
                if (global.dircl.sign_tag != null)
                    _ = c.a12helper_keystore_gen_sigkey(global.dircl.sign_tag, false);

                if (!c.build_appl_pkg(
                    global.dircl.build_appl,
                    &global.dircl.outapp,
                    global.dircl.build_appl_dfd,
                    global.dircl.sign_tag,
                )) {
                    _ = shutdown(cl.fd, SHUT_RDWR);
                    _ = c.close(cl.fd);
                    _ = c.fprintf(c.stderr,
                        "--push-ctrl/--push-appl %s (tag: %s): couldn't build package",
                        global.dircl.build_appl,
                        if (global.dircl.sign_tag != null) global.dircl.sign_tag else @as([*c]const u8, "(no-sign)"),
                    );
                    c.exit(1);
                }
                a12int_trace(c.A12_TRACE_DIRECTORY, "dircl:push_appl:built=%s", global.dircl.build_appl);
                _ = c.close(global.dircl.build_appl_dfd);
            }

            global.dircl.die_on_list = if (global.keep_alive) false else true;
            global.dircl.basedir = global.directory;

            if (global.dircl.upload.name == null and global.dircl.download.name == null) {
                if (c.getenv("XDG_CACHE_HOME")) |xdg|
                    _ = c.chdir(xdg)
                else
                    _ = c.chdir("/tmp");
                c.a12_trace_tag(cl.state, "dir_push");
            }

            if (argi < argc and argv[argi] != null) {
                const trailing: []const u8 = std.mem.span(argv[argi]);
                if (!std.mem.eql(u8, trailing, "--") and !std.mem.eql(u8, trailing, "--exec")) {
                    _ = c.snprintf(
                        &global.dircl.applname,
                        @sizeOf(@TypeOf(global.dircl.applname)),
                        "%s",
                        argv[argi],
                    );
                }
            }

            c.a12_trace_tag(cl.state, "dir_source");
            c.anet_directory_cl(cl.state, global.dircl, cl.fd, cl.fd);
        } else {
            c.a12_trace_tag(cl.state, "dir_client");
            rc = c.a12helper_a12srv_shmifcl(null, cl.state, null, cl.fd, cl.fd);
        }

        _ = shutdown(cl.fd, SHUT_RDWR);
        _ = c.close(cl.fd);
        c.exit(if (rc < 0) 1 else 0);
    }

    // Security mode warnings
    if (global.soft_auth) {
        a12int_trace(c.A12_TRACE_SECURITY, "weak-security=password only");
        if (!global.no_default)
            a12int_trace(c.A12_TRACE_SECURITY, "no-security=default password");
    }

    // Open keystore unless we are a dirsrv inherit child
    var err: [*c]const u8 = null;
    if (global.meta.mode != @intFromEnum(AnetMode.shmif_dirsrv_inherit)) {
        if (!openKeystore(&global.meta, &err) and !global.use_forced_remote_pubk) {
            _ = showUsage(err, null, 0);
            c.exit(1);
        }
        var priv: [32]u8 = undefined;
        var outhost: [*c]u8 = null;
        var outport: u16 = 0;
        if (!c.a12helper_keystore_hostkey("default", 0, &priv, &outhost, &outport)) {
            var outp: [32]u8 = undefined;
            _ = c.a12helper_keystore_register("default", "127.0.0.1", 6680, &outp, null);
            a12int_trace(c.A12_TRACE_SECURITY, "key_added=default");
        }
    }

    var errmsg: [*c]u8 = null;

    // Inbound listen mode
    if (global.meta.mode == @intFromEnum(AnetMode.shmif_cl)) {
        if (global.trust_domain == null)
            global.trust_domain = c.strdup("default");

        if (global.directory != -1) {
            const fd = c.open(argv[0], c.O_RDONLY);
            if (fd == -1) {
                _ = c.fprintf(c.stderr,
                    "environment error: arcan-net --directory requires access to \n" ++
                    "its own valid executable, start with full /path/to/arcan-net\n");
                c.exit(1);
            }
            _ = c.close(fd);

            global.dirsrv.basedir = global.directory;
            c.anet_directory_srv_scan(&global.dirsrv);
            c.anet_directory_shmifsrv_set(&global.dirsrv);

            if (global.dirsrv.discover_beacon) {
                const ipv6: [*c]u8 = null;
                var pth: c.pthread_t = undefined;
                var pthattr: c.pthread_attr_t = undefined;
                _ = c.pthread_attr_init(&pthattr);
                _ = c.pthread_attr_setdetachstate(&pthattr, c.PTHREAD_CREATE_DETACHED);
                _ = c.pthread_create(&pth, &pthattr, sendDirsrvBeacon, ipv6);
            }

            c.dirsrv_global_lock(@src().file, @src().line);
            c.anet_directory_lua_trigger_auto(&global.dirsrv.dir);
            c.anet_directory_lua_ready(&global);
            c.dirsrv_global_unlock(@src().file, @src().line);

            _ = c.anet_listen(&global.meta, &errmsg, launchDirsrvHandler, &argv_output);
        } else {
            _ = c.anet_listen(&global.meta, &errmsg, launchInboundSink, &argv_output);
        }
    }

    // Exec mode: hosted executable
    if (global.meta.mode == @intFromEnum(AnetMode.shmif_exec)) {
        _ = c.anet_listen(&global.meta, &errmsg, forwardInboundExec, &argv_output);
        if (errmsg != null) {
            _ = c.fprintf(c.stderr, "%s", errmsg);
            std.c.free(errmsg);
            c.exit(1);
        }
        c.exit(0);
    }

    // Inherited shmif connection (ARCAN_CONNPATH=a12://...)
    if (global.meta.mode == @intFromEnum(AnetMode.shmif_srv_inherit))
        c.exit(a12Preauth(&global.meta, a12clDispatch));

    // Outbound exec mode (arcan-net -- /usr/bin/app)
    if (global.meta.mode == @intFromEnum(AnetMode.shmif_exec_outbound)) {
        if (global.trust_domain == null)
            global.trust_domain = @constCast("*");

        const cl = findConnection(&global.meta, null);
        if (cl.state == null) {
            if (global.meta.key != null)
                _ = c.fprintf(c.stderr, "couldn't connect to any host for key %s\n", global.meta.key)
            else
                _ = c.fprintf(c.stderr, "couldn't connect to %s port %s\n", global.meta.host, global.meta.port);
            c.exit(1);
        }

        const env = c.struct_shmifsrv_envp{
            .init_w = 32,
            .init_h = 32,
            .path = argv_output.bin,
            .argv = @ptrCast(argv_output.argv),
            .envv = @ptrCast(environ),
        };

        var socket: c_int = 0;
        var errc: c_int = 0;
        const C = c.shmifsrv_spawn_client(env, &socket, &errc, 0);
        if (C == null) {
            _ = shutdown(cl.fd, SHUT_RDWR);
            _ = c.close(cl.fd);
            c.exit(1);
        }

        a12clDispatch(&global.meta, cl.state, C, cl.fd);
        c.exit(0);
    }

    // Directory server inherit mode
    if (global.meta.mode == @intFromEnum(AnetMode.shmif_dirsrv_inherit)) {
        setLogTrace("dir_srv");
        const diropts = std.mem.zeroes(c.struct_anet_dirsrv_opts);
        c.anet_directory_srv(global.meta.opts, diropts, global.meta.sockfd, global.meta.sockfd);
        _ = shutdown(global.meta.sockfd, SHUT_RDWR);
        _ = c.close(global.meta.sockfd);
        c.exit(0);
    }

    // ANET_SHMIF_SRV: listen for shmif connections and forward to a12
    c.exit(a12Connect(&global.meta, forkA12clDispatch));
}
