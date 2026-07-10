// Zig port of a12/net/session.c — arcan-net-session binary
// Handles spawning source clients, key authentication, managing client
// connections via threads, and the main event loop on a parent shmif connection.
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING in arcan source repository.

const std = @import("std");
const posix = std.posix;

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. Each alias routes to the appropriate hand-written replacement module
// (zero `@cImport` left). The `c.X` spellings at call sites below are unchanged.
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // ── libc (posix + stdio) ────────────────────────────────────────────────
    pub const O_CLOEXEC = libc.O_CLOEXEC;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const PTHREAD_CREATE_DETACHED = libc.PTHREAD_CREATE_DETACHED;
    pub const SHUT_RDWR = libc.SHUT_RDWR;
    pub const close = libc.close;
    pub const fopen = libc.fopen;
    pub const fprintf = libc.fprintf;
    pub const free = libc.free;
    pub const getpid = libc.getpid;
    pub const getppid = libc.getppid;
    pub const malloc = libc.malloc;
    pub const open = libc.open;
    pub const pipe = libc.pipe;
    pub const pthread_attr_init = libc.pthread_attr_init;
    pub const pthread_attr_setdetachstate = libc.pthread_attr_setdetachstate;
    pub const pthread_attr_t = libc.pthread_attr_t;
    pub const pthread_create = libc.pthread_create;
    pub const pthread_mutex_lock = libc.pthread_mutex_lock;
    pub const pthread_mutex_t = libc.pthread_mutex_t;
    pub const pthread_mutex_unlock = libc.pthread_mutex_unlock;
    pub const pthread_t = libc.pthread_t;
    pub const read = libc.read;
    pub const recv = libc.recv;
    pub const shutdown = libc.shutdown;
    // stderr is `extern "c" var` in libc; aliasing via `pub const` triggers
    // a comptime-value error when used at runtime. Re-declare directly.
    pub extern "c" var stderr: *libc.FILE;
    pub const unsetenv = libc.unsetenv;
    pub const write = libc.write;

    // ── shmif (arcan_shmif.h / arcan_shmif_server.h) ────────────────────────
    pub const SEGID_AUDIO = shmif.SEGID_AUDIO;
    pub const SEGID_BRIDGE_ALLOCATOR = shmif.SEGID_BRIDGE_ALLOCATOR;
    pub const SEGID_BRIDGE_WAYLAND = shmif.SEGID_BRIDGE_WAYLAND;
    pub const SEGID_BRIDGE_X11 = shmif.SEGID_BRIDGE_X11;
    pub const SHMIF_ACQUIRE_FATALFAIL = shmif.SHMIF_ACQUIRE_FATALFAIL;
    pub const SHMIF_NOAUTO_RECONNECT = shmif.SHMIF_NOAUTO_RECONNECT;
    pub const SHMIF_NOREGISTER = shmif.SHMIF_NOREGISTER;
    pub const SHMIF_SOCKET_PINGEVENT = shmif.SHMIF_SOCKET_PINGEVENT;
    pub const arcan_shmif_dupfd = shmif.arcan_shmif_dupfd;
    pub const arcan_shmif_eventstr = shmif.arcan_shmif_eventstr;
    pub const arcan_shmif_open = shmif.arcan_shmif_open;
    pub const arcan_shmif_wait = shmif.arcan_shmif_wait;
    pub const arg_cleanup = shmif.arg_cleanup;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arg_unpack = shmif.arg_unpack;
    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_shmifsrv_client = shmif.struct_shmifsrv_client;
    pub const struct_shmifsrv_envp = shmif.struct_shmifsrv_envp;
    pub const struct_shmifsrv_vbuffer = shmif.struct_shmifsrv_vbuffer;

    // ── a12 (a12.h / a12_int.h, incl. shmifsrv + constants) ─────────────────
    pub const A12_TRACE_SYSTEM = a12.A12_TRACE_SYSTEM;
    pub const CLIENT_DEAD = a12.CLIENT_DEAD;
    pub const EVENT_EXTERNAL = a12.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_REGISTER = a12.EVENT_EXTERNAL_REGISTER;
    pub const EVENT_TARGET = a12.EVENT_TARGET;
    pub const FRAME_RAW_SHMIFSRV_VBUFFER = a12.FRAME_RAW_SHMIFSRV_VBUFFER;
    pub const ROLE_PROBE = a12.ROLE_PROBE;
    pub const ROLE_SOURCE = a12.ROLE_SOURCE;
    pub const SEGID_GAME = a12.SEGID_GAME;
    pub const SEGID_LWA = a12.SEGID_LWA;
    pub const SEGID_MEDIA = a12.SEGID_MEDIA;
    pub const SEGID_NETWORK_SERVER = a12.SEGID_NETWORK_SERVER;
    pub const SHMIFSRV_FREE_NO_DMS = a12.SHMIFSRV_FREE_NO_DMS;
    pub const SHMIF_NOACTIVATE = a12.SHMIF_NOACTIVATE;
    pub const TARGET_COMMAND_ACTIVATE = a12.TARGET_COMMAND_ACTIVATE;
    pub const TARGET_COMMAND_BCHUNK_IN = a12.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = a12.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_DISPLAYHINT = a12.TARGET_COMMAND_DISPLAYHINT;
    pub const TARGET_COMMAND_MESSAGE = a12.TARGET_COMMAND_MESSAGE;
    pub const TARGET_COMMAND_RESET = a12.TARGET_COMMAND_RESET;
    pub const VFRAME_BIAS_BALANCED = a12.VFRAME_BIAS_BALANCED;
    pub const VFRAME_BIAS_LATENCY = a12.VFRAME_BIAS_LATENCY;
    pub const VFRAME_BIAS_QUALITY = a12.VFRAME_BIAS_QUALITY;
    pub const VFRAME_METHOD_DZSTD = a12.VFRAME_METHOD_DZSTD;
    pub const VFRAME_METHOD_H264 = a12.VFRAME_METHOD_H264;
    pub const VFRAME_METHOD_RAW_NOALPHA = a12.VFRAME_METHOD_RAW_NOALPHA;
    pub const VFRAME_METHOD_TPACK_ZSTD = a12.VFRAME_METHOD_TPACK_ZSTD;
    pub const a12_channel_enqueue = a12.a12_channel_enqueue;
    pub const a12_channel_vframe = a12.a12_channel_vframe;
    pub const a12_flush = a12.a12_flush;
    pub const a12_free = a12.a12_free;
    pub const a12_server = a12.a12_server;
    pub const a12_set_session = a12.a12_set_session;
    pub const a12_set_trace_level = a12.a12_set_trace_level;
    pub const a12_unpack = a12.a12_unpack;
    pub const shmifsrv_client_type = a12.shmifsrv_client_type;
    pub const shmifsrv_enqueue_event = a12.shmifsrv_enqueue_event;
    pub const shmifsrv_free = a12.shmifsrv_free;
    pub const shmifsrv_poll = a12.shmifsrv_poll;
    pub const shmifsrv_spawn_client = a12.shmifsrv_spawn_client;
    pub const struct_a12_context_options = a12.struct_a12_context_options;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_a12_vframe_opts = a12.struct_a12_vframe_opts;
    pub const struct_pk_response = a12.struct_pk_response;

    // ── anet (anet_helper.h / a12_helper.h + hashmap.h) ─────────────────────
    pub const A12HELPER_PROVIDER_BASEDIR = anet.A12HELPER_PROVIDER_BASEDIR;
    pub const a12helper_a12cl_shmifsrv = anet.a12helper_a12cl_shmifsrv;
    pub const a12helper_alloc_cache = anet.a12helper_alloc_cache;
    pub const a12helper_fromb64 = anet.a12helper_fromb64;
    pub const a12helper_keystore_accept = anet.a12helper_keystore_accept;
    pub const a12helper_keystore_accepted = anet.a12helper_keystore_accepted;
    pub const a12helper_keystore_hostkey = anet.a12helper_keystore_hostkey;
    pub const a12helper_keystore_open = anet.a12helper_keystore_open;
    pub const a12helper_query_untrusted_key = anet.a12helper_query_untrusted_key;
    pub const a12helper_tob64 = anet.a12helper_tob64;
    pub const a12helper_tpack_dimensions = anet.a12helper_tpack_dimensions;
    pub const a12helper_vbuffer_add_listener = anet.a12helper_vbuffer_add_listener;
    pub const a12helper_vbuffer_drop_listener = anet.a12helper_vbuffer_drop_listener;
    pub const a12helper_vbuffer_size_hints = anet.a12helper_vbuffer_size_hints;
    pub const a12helper_vbuffer_type = anet.a12helper_vbuffer_type;
    pub const anet_authenticate = anet.anet_authenticate;
    pub const hashmap_create = anet.hashmap_create;
    pub const hashmap_get = anet.hashmap_get;
    pub const hashmap_put = anet.hashmap_put;
    pub const hashmap_remove = anet.hashmap_remove;
    pub const struct_a12helper_opts = anet.struct_a12helper_opts;
    pub const struct_hashmap_s = anet.struct_hashmap_s;
    pub const struct_keystore_provider = anet.struct_keystore_provider;
};

// extern C functions not easily reached through @cImport

extern "c" fn arcan_random(dst: [*]u8, nb: usize) void;
fn a12int_trace(group: c_int, fmt: [*:0]const u8, ...) callconv(.c) void {
    _ = group;
    _ = fmt;
    // Stub: full tracing path is in the a12 library but not exported as variadic C.
}
extern "c" fn a12_remote_mode(S: *c.struct_a12_state) c_int;

// Global state
//
// G.sync is a pthread_mutex_t so it can be passed to the C helper functions
// (a12helper_a12cl_shmifsrv / a12helper_framecache_sink) via a12helper_opts.lock.

const Global = struct {
    C: c.struct_arcan_shmif_cont,
    sync: c.pthread_mutex_t,
    map_pubk: c.struct_hashmap_s,

    bin: ?[*:0]const u8,
    argv: ?[*]?[*:0]u8,
    soft_auth: bool,
    mirror_cast: bool,
    accept_n_unknown: usize,
    frame_cache: ?*anyopaque,
    use_private_key: bool,
    private_key: [32]u8,
    secret: [32]u8,
    trust_domain: [*:0]const u8,
    copts: c.struct_a12_context_options,
};

var G: Global = .{
    .C = std.mem.zeroes(c.struct_arcan_shmif_cont),
    .sync = std.mem.zeroes(c.pthread_mutex_t),
    .map_pubk = std.mem.zeroes(c.struct_hashmap_s),
    .bin = null,
    .argv = null,
    .soft_auth = false,
    .mirror_cast = false,
    .accept_n_unknown = 0,
    .frame_cache = null,
    .use_private_key = false,
    .private_key = std.mem.zeroes([32]u8),
    .secret = std.mem.zeroes([32]u8),
    .trust_domain = "default",
    .copts = blk: {
        var opts = std.mem.zeroes(c.struct_a12_context_options);
        opts.local_role = c.ROLE_SOURCE;
        break :blk opts;
    },
};

inline fn gLock() void {
    _ = c.pthread_mutex_lock(&G.sync);
}

inline fn gUnlock() void {
    _ = c.pthread_mutex_unlock(&G.sync);
}

// Client metadata passed to per-connection threads

const ClientMeta = struct {
    fd: c_int,
    secret: [32]u8,
    pubk: [32]u8,
    source: ?*c.struct_shmifsrv_client,
    recovered: bool,
};

// SinkMeta for the framecache sink event handler

const SinkMeta = struct {
    S: *c.struct_a12_state,
    C: *anyopaque,
    activated: bool,
    dh_w: usize,
    dh_h: usize,
    dh_cellw: usize,
    dh_cellh: usize,
    wake: c_int,
};

// Prespawn a shmifsrv_client to cut down on startup latency

// See net.zig for the same pattern — @extern(T, ...) returns a pointer to
// the symbol, not its value. Declaring as `extern var` gives the correct
// char-star-star value that execve expects.
extern var environ: [*c][*c]u8;

fn spawnSource() ?*c.struct_shmifsrv_client {
    const env = c.struct_shmifsrv_envp{
        .init_w = 32,
        .init_h = 32,
        .path = @constCast(G.bin),
        .argv = @ptrCast(G.argv),
        .detach = 32,
        .envv = @ptrCast(environ),
    };
    var socket: c_int = 0;
    var errc: c_int = 0;
    return c.shmifsrv_spawn_client(env, &socket, &errc, 0);
}

// Optional binary-cache directory

fn getBcacheDir() c_int {
    const base_z = posix.getenv("A12_CACHE_DIR") orelse return -1;
    // Convert slice to null-terminated for open()
    var buf: [4096]u8 = undefined;
    if (base_z.len >= buf.len) return -1;
    @memcpy(buf[0..base_z.len], base_z);
    buf[base_z.len] = 0;
    return c.open(@as([*:0]const u8, @ptrCast(&buf)), c.O_RDONLY | c.O_DIRECTORY | c.O_CLOEXEC);
}

// Video codec selection heuristic

fn vcodecTuning(
    S: [*c]c.struct_a12_state,
    segid: c_int,
    vb: [*c]c.struct_shmifsrv_vbuffer,
    tag: ?*anyopaque,
) callconv(.c) c.struct_a12_vframe_opts {
    _ = S;
    _ = vb;
    _ = tag;

    var opts = c.struct_a12_vframe_opts{
        .method = c.VFRAME_METHOD_DZSTD,
        .bias = c.VFRAME_BIAS_BALANCED,
    };

    switch (segid) {
        c.SEGID_LWA => {
            opts.method = c.VFRAME_METHOD_H264;
        },
        c.SEGID_GAME => {
            opts.method = c.VFRAME_METHOD_H264;
            opts.bias = c.VFRAME_BIAS_LATENCY;
        },
        c.SEGID_AUDIO => {
            opts.method = c.VFRAME_METHOD_RAW_NOALPHA;
            opts.bias = c.VFRAME_BIAS_LATENCY;
        },
        c.SEGID_MEDIA => {
            opts.method = c.VFRAME_METHOD_H264;
            opts.bias = c.VFRAME_BIAS_QUALITY;
        },
        c.SEGID_BRIDGE_ALLOCATOR => {
            opts.method = c.VFRAME_METHOD_RAW_NOALPHA;
            opts.bias = c.VFRAME_BIAS_LATENCY;
        },
        c.SEGID_BRIDGE_WAYLAND, c.SEGID_BRIDGE_X11 => {
            opts.method = c.VFRAME_METHOD_H264;
            opts.bias = c.VFRAME_BIAS_LATENCY;
        },
        else => {},
    }

    if (opts.method == c.VFRAME_METHOD_H264) {
        // Parse env vars once; statics are safe here because vcodecTuning is
        // called from threads already holding G.sync.
        const Env = struct {
            var got: bool = false;
            var cbr: c_uint = 22;
            var br: c_uint = 1024;
        };
        if (!Env.got) {
            if (posix.getenv("A12_VENC_CRF")) |s| {
                const v = std.fmt.parseInt(c_uint, s, 10) catch 22;
                Env.cbr = if (v > 55) 55 else v;
            }
            if (posix.getenv("A12_VENC_RATE")) |s| {
                const v = std.fmt.parseInt(c_uint, s, 10) catch 1024;
                Env.br = if (@as(u64, v) * 1000 > std.math.maxInt(c_int)) std.math.maxInt(c_int) else v;
            }
            Env.got = true;
        }
        opts.ratefactor = @intCast(Env.cbr);
        opts.bitrate = @intCast(Env.br);
    }

    return opts;
}

// consumeFrame: frame listener callback invoked from source handler thread
// Called while G.sync is already held by a12helper_shmifcl_srv.

fn consumeFrame(
    ref: usize,
    buf: [*c]u8,
    buf_sz: usize,
    frame_type: c_int,
) callconv(.c) void {
    if (frame_type != c.FRAME_RAW_SHMIFSRV_VBUFFER) return;

    const M: *SinkMeta = @ptrFromInt(ref);

    // Copy vbuffer so we don't mutate the shared buffer for other listeners.
    var vb: c.struct_shmifsrv_vbuffer = undefined;
    const copy_sz = @min(buf_sz, @sizeOf(c.struct_shmifsrv_vbuffer));
    @memcpy(std.mem.asBytes(&vb)[0..copy_sz], buf[0..copy_sz]);

    var opts = vcodecTuning(M.S, c.SEGID_MEDIA, &vb, null);

    if (vb.flags.tpack) {
        opts.method = c.VFRAME_METHOD_TPACK_ZSTD;
        var rows: usize = 0;
        var cols: usize = 0;
        if (M.dh_cellw != 0 and c.a12helper_tpack_dimensions(@ptrCast(M.C), 0, &rows, &cols)) {
            vb.w = @intCast(cols * M.dh_cellw);
            vb.h = @intCast(rows * M.dh_cellh);
        }
    }

    _ = c.a12_channel_vframe(M.S, &vb, opts);

    // Wake the poll loop in the sink.
    _ = c.write(M.wake, "\x01", 1);
}

// sinkEvh: event handler for a framecache sink connection

fn sinkEvh(
    cont: ?*c.struct_arcan_shmif_cont,
    chid: c_int,
    ev: ?*c.struct_arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = cont;
    _ = chid;
    const M: *SinkMeta = @ptrCast(@alignCast(tag orelse return));
    const event = ev orelse return;

    const eb = &event.unnamed_0.unnamed_0;
    if (eb.category != c.EVENT_TARGET) return;

    const tgt = &eb.unnamed_0.tgt;
    if (tgt.kind == c.TARGET_COMMAND_ACTIVATE and !M.activated) {
        c.a12helper_vbuffer_add_listener(@ptrCast(M.C),@intFromPtr(M), true, consumeFrame);
        M.activated = true;
        c.a12helper_vbuffer_size_hints(@ptrCast(M.C),@intFromPtr(M), M.dh_w, M.dh_h);
    } else if (tgt.kind == c.TARGET_COMMAND_DISPLAYHINT) {
        if (tgt.ioevs[5].uiv != 0 and tgt.ioevs[6].uiv != 0) {
            M.dh_cellw = tgt.ioevs[5].uiv;
            M.dh_cellh = tgt.ioevs[6].uiv;
        }
        if (tgt.ioevs[0].uiv != 0 and tgt.ioevs[1].uiv != 0) {
            M.dh_w = tgt.ioevs[0].uiv;
            M.dh_h = tgt.ioevs[1].uiv;
            if (M.activated)
                c.a12helper_vbuffer_size_hints(@ptrCast(M.C),@intFromPtr(M), M.dh_w, M.dh_h);
        }
    }
}

// a12helper_framecache_sink: exported — provides the sink loop
// Defined in C as well, but here we reimplement it so the global G.sync is
// used as the coordination lock rather than the C helper's internal one.

pub export fn a12helper_framecache_sink(
    S: *c.struct_a12_state,
    C: *anyopaque,
    fdio: c_int,
    opts: c.struct_a12helper_opts,
) void {
    _ = opts;

    var pipe_pair: [2]c_int = .{ -1, -1 };
    if (c.pipe(&pipe_pair) == -1) return;

    var meta = SinkMeta{
        .S = S,
        .C = C,
        .wake = pipe_pair[1],
        .activated = false,
        .dh_w = 0,
        .dh_h = 0,
        .dh_cellw = 0,
        .dh_cellh = 0,
    };

    const errmask: i16 = std.posix.POLL.ERR | std.posix.POLL.NVAL | std.posix.POLL.HUP;
    var pfds = [2]std.posix.pollfd{
        .{ .fd = fdio, .events = std.posix.POLL.IN | errmask, .revents = 0 },
        .{ .fd = pipe_pair[0], .events = std.posix.POLL.IN, .revents = 0 },
    };

    var outbuf: ?[*]u8 = null;
    var outbuf_sz: usize = 0;

    // Initial unpack + REGISTER + flush
    gLock();
    {
        const frame_type = c.a12helper_vbuffer_type(@ptrCast(C), 0);
        var ev = c.struct_arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
        ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_REGISTER;
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.kind = @intCast(frame_type);

        c.a12_unpack(S, null, 0, &meta, sinkEvh);
        _ = c.a12_channel_enqueue(S, &ev);
        outbuf_sz = c.a12_flush(S, &outbuf, 0);
    }
    gUnlock();

    outer: while (true) {
        if (outbuf_sz != 0)
            pfds[0].events |= std.posix.POLL.OUT
        else
            pfds[0].events &= ~@as(i16, std.posix.POLL.OUT);

        _ = std.posix.poll(&pfds, -1) catch |err| {
            if (err == error.Interrupted) continue;
            break :outer;
        };

        // Drain wakeup pipe
        if (pfds[1].revents & std.posix.POLL.IN != 0) {
            var buf: [256]u8 = undefined;
            _ = c.read(pipe_pair[0], &buf, buf.len);
        }

        // Write pending output
        if (pfds[0].revents & std.posix.POLL.OUT != 0) {
            if (outbuf) |ob| {
                const nw = c.write(fdio, ob, outbuf_sz);
                if (nw > 0) {
                    outbuf = ob + @as(usize, @intCast(nw));
                    outbuf_sz -= @intCast(nw);
                }
            }
        }

        // Process incoming data
        if (pfds[0].revents & std.posix.POLL.IN != 0) {
            var inbuf: [9000]u8 = undefined;
            const nr = c.recv(fdio, &inbuf, inbuf.len, 0);
            if (nr == 0) break :outer;
            if (nr > 0) {
                gLock();
                c.a12_unpack(S, &inbuf, @intCast(nr), &meta, sinkEvh);
                gUnlock();
            }
        }

        // Refill flush buffer when drained
        if (outbuf_sz == 0) {
            gLock();
            outbuf_sz = c.a12_flush(S, &outbuf, 0);
            gUnlock();
        }
    }

    // Cleanup; caller owns fd lifecycle
    gLock();
    c.a12helper_vbuffer_drop_listener(@ptrCast(C), @intFromPtr(&meta));
    _ = c.a12_free(S);
    gUnlock();

    _ = c.close(pipe_pair[0]);
    _ = c.close(pipe_pair[1]);
}

// keyAuth: called from the per-client thread to authenticate a public key

fn keyAuth(
    S: [*c]c.struct_a12_state,
    pubk: [*c]u8,
    tag: ?*anyopaque,
) callconv(.c) c.struct_pk_response {
    _ = S;
    const cl: *ClientMeta = @ptrCast(@alignCast(tag orelse {
        return std.mem.zeroes(c.struct_pk_response);
    }));
    var rep = std.mem.zeroes(c.struct_pk_response);

    var my_private_key: [32]u8 = std.mem.zeroes([32]u8);
    var keytag: [*c]u8 = null;
    var tmphost: [*c]u8 = null;
    var tmpport: u16 = 0;
    var ofs: usize = 0;
    var known: bool = false;

    // pubk arrives as a [*c]u8 bare pointer from the translate-c-compatible
    // a12 pk_lookup signature. The keystore helpers want a *const [32]u8; the
    // C side guarantees the buffer is a 32-byte ed25519 public key.
    const pubk32: *const [32]u8 = @ptrCast(pubk);

    var b64_outl: usize = 0;
    const pubk_b64 = c.a12helper_tob64(pubk, 32, &b64_outl);
    defer if (pubk_b64 != null) c.free(pubk_b64);

    // Accept if: pre-auth secret set, key is in trusted keystore, soft-auth
    // enabled, or user approved interactively.
    const has_secret = cl.secret[0] != 0;
    if (!known) {
        if (c.a12helper_keystore_accepted(pubk32, G.trust_domain) != null)
            known = true;
    }
    const interactive = c.a12helper_query_untrusted_key(
        G.trust_domain,
        @ptrCast(pubk_b64),
        pubk32,
        &keytag,
        &ofs,
    );

    if (!has_secret and !known and !G.soft_auth and !interactive) {
        return rep;
    }

    // Interactive: persist the accepted key to keystore
    if (keytag != null and keytag[0] != 0) {
        _ = c.a12helper_keystore_accept(pubk32, keytag);
        known = true;
    }

    // Accept first N unknown keys that used the right initial secret
    if (!known and G.accept_n_unknown > 0) {
        G.accept_n_unknown -= 1;
        _ = c.a12helper_keystore_accept(pubk32, keytag);
    }

    // Pick private key: injected by directory server, or from keystore 'default'
    if (G.use_private_key) {
        @memcpy(&my_private_key, &G.private_key);
    } else {
        _ = c.a12helper_keystore_hostkey("default", 0, &my_private_key, &tmphost, &tmpport);
    }

    c.a12_set_session(&rep, pubk, &my_private_key);
    rep.authentic = true;
    @memcpy(&cl.pubk, pubk32);

    gLock();
    cl.source = @ptrCast(c.hashmap_get(&G.map_pubk, pubk, 32));
    if (cl.source != null) {
        cl.recovered = true;
    } else if (G.frame_cache == null) {
        cl.source = spawnSource();
    }
    gUnlock();

    return rep;
}

// clientHandler: per-connection thread entry point

fn clientHandler(tag: *anyopaque) void {
    const cl: *ClientMeta = @ptrCast(@alignCast(tag));

    var copts = G.copts;
    @memcpy(&copts.secret, &cl.secret);
    copts.pk_lookup = keyAuth;
    copts.pk_lookup_tag = cl;

    const S = c.a12_server(&copts) orelse {
        _ = c.shutdown(cl.fd, c.SHUT_RDWR);
        _ = c.close(cl.fd);
        c.free(cl);
        return;
    };

    // Block on auth handshake
    var msg: ?[*:0]u8 = null;
    if (!c.anet_authenticate(S, cl.fd, cl.fd, @ptrCast(&msg))) {
        a12int_trace(c.A12_TRACE_SYSTEM, "authentication failed: %s", msg orelse @as([*:0]const u8, "(null)"));
        if (msg) |m| c.free(m);
        _ = c.a12_free(S);
        _ = c.shutdown(cl.fd, c.SHUT_RDWR);
        _ = c.close(cl.fd);
        c.free(cl);
        return;
    }

    if (a12_remote_mode(S) == c.ROLE_PROBE) {
        a12int_trace(c.A12_TRACE_SYSTEM, "probed:terminating");
        _ = c.a12_free(S);
        _ = c.shutdown(cl.fd, c.SHUT_RDWR);
        _ = c.close(cl.fd);
        c.free(cl);
        return;
    }

    // Resumption: send RESET to re-synchronise the existing source client
    // and inject a synthetic REGISTER so the remote side reconnects cleanly.
    if (cl.recovered) {
        var reset_ev = c.struct_arcan_event.zeroes();
        reset_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        reset_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_RESET;
        reset_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = 2;
        _ = c.shmifsrv_enqueue_event(cl.source, &reset_ev, -1);

        var reg_ev = c.struct_arcan_event.zeroes();
        reg_ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
        reg_ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_REGISTER;
        reg_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.kind = c.shmifsrv_client_type(cl.source);
        _ = c.a12_channel_enqueue(S, &reg_ev);

        cl.recovered = false;
    }

    if (G.mirror_cast) {
        if (G.frame_cache == null) {
            G.frame_cache = @ptrCast(c.a12helper_alloc_cache(7));
            // Fall through: this becomes the primary source for the frame-cache.
        } else {
            // Attach as a frame-cache consumer via the alternate sink loop.
            a12helper_framecache_sink(
                S,
                G.frame_cache.?,
                cl.fd,
                c.struct_a12helper_opts{
                    .vframe_block = 5,
                    .vframe_soft_block = 2,
                    .eval_vcodec = vcodecTuning,
                    .lock = &G.sync,
                },
            );
            _ = c.shutdown(cl.fd, c.SHUT_RDWR);
            _ = c.close(cl.fd);
            c.free(cl);
            return;
        }
    }

    // Hand off to the main a12 ↔ shmifsrv bridge loop.
    c.a12helper_a12cl_shmifsrv(
        S,
        cl.source,
        cl.fd,
        cl.fd,
        c.struct_a12helper_opts{
            .redirect_exit = null,
            .devicehint_cp = null,
            .vframe_block = 5,
            .vframe_soft_block = 2,
            .eval_vcodec = vcodecTuning,
            .bcache_dir = getBcacheDir(),
            .cache = @ptrCast(G.frame_cache),
            .lock = &G.sync,
        },
    );

    // Update resumption table based on whether the shmif client is still alive.
    gLock();
    if (c.shmifsrv_poll(cl.source) != c.CLIENT_DEAD) {
        _ = c.hashmap_put(&G.map_pubk, &cl.pubk, 32, cl.source);
    } else {
        _ = c.hashmap_remove(&G.map_pubk, &cl.pubk, 32);
        c.shmifsrv_free(cl.source, c.SHMIFSRV_FREE_NO_DMS);
    }
    gUnlock();

    _ = c.shutdown(cl.fd, c.SHUT_RDWR);
    _ = c.close(cl.fd);
    c.free(cl);
}

// pthread trampoline

fn clientHandlerPthread(tag: ?*anyopaque) callconv(.c) ?*anyopaque {
    clientHandler(tag orelse return null);
    return null;
}

// flushParentEvent: process one event from the parent shmif connection

fn flushParentEvent(ev: *c.struct_arcan_event) void {
    const eb = &ev.unnamed_0.unnamed_0;
    const tgt = &eb.unnamed_0.tgt;
    if (eb.category != c.EVENT_TARGET) {
        _ = c.fprintf(c.stderr, "Ignore: %s\n", c.arcan_shmif_eventstr(ev, null, 0));
        return;
    }

    if (tgt.kind == c.TARGET_COMMAND_BCHUNK_IN) {
        const msg: [*:0]const u8 = @ptrCast(&tgt.unnamed_0.message);
        if (std.mem.eql(u8, std.mem.sliceTo(msg, 0), "keystore")) {
            const fd = c.arcan_shmif_dupfd(tgt.ioevs[0].iv, -1, false);
            var provider = c.struct_keystore_provider{
                .unnamed_0 = .{ .directory = .{ .dirfd = fd, .statefd = 0 } },
                .type = c.A12HELPER_PROVIDER_BASEDIR,
            };
            if (!c.a12helper_keystore_open(&provider)) {
                _ = c.fprintf(c.stderr, "Couldn't open keystore\n");
            }
        } else {
            _ = c.fprintf(c.stderr, "Unknown bchunk-in: %s\n", @as([*:0]const u8, @ptrCast(&tgt.unnamed_0.message)));
        }
    } else if (tgt.kind == c.TARGET_COMMAND_BCHUNK_OUT) {
        // Incoming a12 socket — spawn a detached handler thread.
        const fd = c.arcan_shmif_dupfd(tgt.ioevs[0].iv, -1, false);

        const cl: *ClientMeta = @ptrCast(@alignCast(c.malloc(@sizeOf(ClientMeta)) orelse {
            _ = c.close(fd);
            return;
        }));
        cl.* = ClientMeta{
            .fd = fd,
            .secret = std.mem.zeroes([32]u8),
            .pubk = std.mem.zeroes([32]u8),
            .source = null,
            .recovered = false,
        };

        const msg: *const [32]u8 = @ptrCast(&tgt.unnamed_0.message);
        if (msg[0] != 0) {
            @memcpy(&cl.secret, msg);
        } else {
            @memcpy(&cl.secret, &G.secret);
        }

        var pth: c.pthread_t = undefined;
        var pthattr: c.pthread_attr_t = undefined;
        _ = c.pthread_attr_init(&pthattr);
        _ = c.pthread_attr_setdetachstate(&pthattr, c.PTHREAD_CREATE_DETACHED);
        _ = c.pthread_create(&pth, &pthattr, clientHandlerPthread, cl);
    } else if (tgt.kind == c.TARGET_COMMAND_MESSAGE) {
        // Configuration messages arrive from the higher-privilege parent process.
        const msg: [*:0]u8 = @ptrCast(&tgt.unnamed_0.message);
        const entry = c.arg_unpack(msg);
        defer c.arg_cleanup(entry);

        var val: ?[*:0]const u8 = null;

        if (c.arg_lookup(entry, "rekey", 0, @ptrCast(&val)) and val != null) {
            G.copts.rekey_bytes = std.fmt.parseInt(
                usize,
                std.mem.sliceTo(val.?, 0),
                10,
            ) catch 0;
        }

        if (c.arg_lookup(entry, "rekey_pqc", 0, @ptrCast(&val))) {
            G.copts.pqc_rekey = true;
        }

        if (c.arg_lookup(entry, "soft_auth", 0, @ptrCast(&val))) {
            G.soft_auth = true;
        }

        if (c.arg_lookup(entry, "log_level", 0, @ptrCast(&val)) and val != null) {
            const level: c_int = @intCast(
                std.fmt.parseInt(usize, std.mem.sliceTo(val.?, 0), 10) catch 0,
            );
            var fn_buf: [64]u8 = undefined;
            const fn_str = std.fmt.bufPrintZ(
                &fn_buf,
                "anet_session_{d}_{d}",
                .{ c.getpid(), c.getppid() },
            ) catch return;
            const fout = c.fopen(fn_str.ptr, "w+");
            c.a12_set_trace_level(level, fout);
        }

        if (c.arg_lookup(entry, "accept_n_unknown", 0, @ptrCast(&val)) and val != null) {
            G.accept_n_unknown = std.fmt.parseInt(
                usize,
                std.mem.sliceTo(val.?, 0),
                10,
            ) catch 0;
        }

        if (c.arg_lookup(entry, "secret", 0, @ptrCast(&val)) and val != null) {
            const s = std.mem.sliceTo(val.?, 0);
            const n = @min(s.len, G.secret.len - 1);
            @memcpy(G.secret[0..n], s[0..n]);
            G.secret[n] = 0;
        }

        if (c.arg_lookup(entry, "key", 0, @ptrCast(&val)) and val != null) {
            G.use_private_key = true;
            _ = c.a12helper_fromb64(@ptrCast(val.?), 32, &G.private_key);
        }

        if (c.arg_lookup(entry, "cast", 0, @ptrCast(&val))) {
            G.mirror_cast = true;
        }
    }
}

// main

pub export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    // Coverage probe: records session startup in ARCAN_SHMIF_MONITOR so the
    // matrix harness can tell at a glance that arcan-net-session actually
    // execed through spawnSource (vs silently failing before).
    {
        const smon = @import("shmif_monitor");
        smon.emitLuaTag("a12:coverage:session_start");
    }

    // Find "--" separator indicating the start of the client binary argv.
    var exec_arg: usize = 0;
    var i: usize = 1;
    while (i < @as(usize, @intCast(argc))) : (i += 1) {
        if (std.mem.eql(u8, std.mem.sliceTo(argv[i], 0), "--")) {
            exec_arg = i + 1;
            break;
        }
    }

    if (exec_arg == 0 or exec_arg >= @as(usize, @intCast(argc))) {
        _ = c.fprintf(
            c.stderr,
            "No source to host specified: arcan-net-session -- /path/to/client\n",
        );
        return 1;
    }

    // Remove privilege marker so it doesn't propagate into spawned clients.
    _ = c.unsetenv("A12_USEPRIV");

    // Open parent shmif connection; fatalfail means we exit if this fails.
    const open_flags: c_uint =
        @as(c_uint, @intCast(c.SHMIF_ACQUIRE_FATALFAIL)) |
        @as(c_uint, @intCast(c.SHMIF_NOACTIVATE)) |
        @as(c_uint, @intCast(c.SHMIF_NOAUTO_RECONNECT)) |
        @as(c_uint, @intCast(c.SHMIF_NOREGISTER)) |
        @as(c_uint, @intCast(c.SHMIF_SOCKET_PINGEVENT));

    G.C = c.arcan_shmif_open(c.SEGID_NETWORK_SERVER, open_flags, null);

    G.bin = argv[exec_arg];
    G.argv = @ptrCast(&argv[exec_arg]);
    _ = c.hashmap_create(256, &G.map_pubk);

    // Main loop: block on the parent connection, dispatch each event.
    var ev: c.struct_arcan_event = undefined;
    while (c.arcan_shmif_wait(&G.C, &ev) != 0) {
        flushParentEvent(&ev);
    }

    return 0;
}
