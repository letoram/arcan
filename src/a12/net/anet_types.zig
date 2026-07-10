// anet_types.zig — Pure Zig type definitions for the arcan-net layer.
// Replaces @cImport of a12_helper.h, anet_helper.h, directory.h.
//
// This module declares every symbol (types, extern fns, constants) that
// arcan-net consumers access through `c.X` after @cImport-ing those three
// headers. Symbols that actually belong to a12.h/a12_int.h are Agent C's
// (a12_types.zig) and provided here only as opaque forward declarations so
// that anet-layer signatures remain self-contained while the parallel refactor
// proceeds.
//
// Hard rules observed:
//  * No @cImport / @cInclude.
//  * extern struct layouts mirror the C definitions byte-for-byte where
//    consumer code reads or writes fields.
//  * Structures used only via opaque pointers are declared `opaque {}`.
//
// Reference style: src/shmif/shmif_types.zig.

const std = @import("std");

// Sibling pure-Zig type modules. Re-exported selectively below so every
// anet-layer consumer sees ABI-identical types through whichever namespace
// they import (`c = @import("anet_types")` / `= @import("shmif_types")`
// / `= @import("a12_types")`). Byte-blob stand-ins get subtle layout drift
// when the dispatch-struct pattern stirs the three modules together, so the
// re-exports here are load-bearing, not decorative.
const shmif = @import("shmif_types");
const a12_mod = @import("a12_types");
const posix_libc = @import("posix");

// ══════════════════════════════════════════════════════════════════════════════
// Section 0 — Upstream forward declarations (a12.h, shmif, posix).
//   Re-exported from sibling modules where the concrete layout is defined.
//   Consumers access the same underlying Zig type regardless of which of the
//   three namespaces (anet_types / shmif_types / a12_types) they import.
// ══════════════════════════════════════════════════════════════════════════════

// ── a12 state machine & context (a12.h / a12_types.zig) ─────────────────────
pub const struct_a12_state = a12_mod.struct_a12_state;
pub const a12_state = struct_a12_state;

// Re-exported from a12_types so consumers that mix anet_types and a12_types
// in one dispatch struct see a single canonical type.
pub const struct_a12_context_options = a12_mod.struct_a12_context_options;
pub const a12_context_options = struct_a12_context_options;

pub const struct_a12_vframe_opts = extern struct {
    method: c_int = 0,
    bias: c_int = 0,
    postprocess: c_int = 0,
    ratefactor: c_int = 0,
    bitrate: usize = 0,
    force_idr: bool = false,
    result_feedback: ?*const anyopaque = null,
};
pub const a12_vframe_opts = struct_a12_vframe_opts;

// Re-exported from a12_types so consumers that mix anet_types and a12_types
// in one dispatch struct see a single canonical type.
pub const struct_a12_dynreq = a12_mod.struct_a12_dynreq;
pub const a12_dynreq = struct_a12_dynreq;

pub const struct_a12_bhandler_meta = extern struct {
    state: c_int = 0,
    type: c_int = 0,
    checksum: [16]u8 = std.mem.zeroes([16]u8),
    known_size: u64 = 0,
    streaming: bool = false,
    channel: u8 = 0,
    streamid: i64 = 0,
    identifier: u32 = 0,
    extid: [17]u8 = std.mem.zeroes([17]u8),
    fd: c_int = 0,
    dcont: ?*struct_arcan_shmif_cont = null,
};
pub const a12_bhandler_meta = struct_a12_bhandler_meta;

pub const struct_a12_bhandler_res = extern struct {
    flag: c_int = 0,
    fd: c_int = 0,
};
pub const a12_bhandler_res = struct_a12_bhandler_res;

// appl_meta — shared with a12_types; re-exported so callers through the
// dispatch-struct pattern see one Zig type regardless of namespace entry.
pub const struct_appl_meta = a12_mod.struct_appl_meta;
pub const appl_meta = a12_mod.appl_meta;

// Re-export a12_types's pk_response so anet-layer callers and the a12 state
// machine see one canonical type. a12_mod's layout adds explicit alignment
// padding after `authentic`; both layouts are 80 bytes ABI-wise.
pub const struct_pk_response = a12_mod.struct_pk_response;
pub const pk_response = a12_mod.pk_response;

// a12_unpack_cfg is opaque here — only referenced as type by channel setup code.
pub const struct_a12_unpack_cfg = opaque {};
pub const a12_unpack_cfg = struct_a12_unpack_cfg;

// ── shmif / arcan forward declarations (shmif_types.zig) ────────────────────
// Re-export the concrete extern-struct types so anet-layer structs that
// embed them by value (struct_ioloop_shared.shmif, struct_directory_meta.
// breq_pending, struct_dircl.petname/endpoint, struct_evqueue_entry.ev) get
// the right layout. Previously declared as opaque/byte-blobs which caused
// dispatch-struct mismatches when callers also touched shmif_types.
pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
pub const arcan_shmif_cont = struct_arcan_shmif_cont;

pub const struct_shmifsrv_client = shmif.struct_shmifsrv_client;
pub const shmifsrv_client = struct_shmifsrv_client;

pub const struct_shmifsrv_vbuffer = shmif.struct_shmifsrv_vbuffer;
pub const shmifsrv_vbuffer = struct_shmifsrv_vbuffer;

pub const struct_arcan_event = shmif.struct_arcan_event;
pub const arcan_event = struct_arcan_event;

pub const struct_arg_arr = shmif.struct_arg_arr;
pub const arg_arr = struct_arg_arr;

pub const struct_arcan_strarr = extern struct {
    count: usize = 0,
    limit: usize = 0,
    cdata: ?*anyopaque = null,
    data: ?[*]?[*:0]u8 = null,
};
pub const arcan_strarr = struct_arcan_strarr;

// pthread_mutex_t — re-exported from posix_libc so consumers that mix
// anet_types and posix_libc in a dispatch struct see one canonical type.
pub const pthread_mutex_t = posix_libc.pthread_mutex_t;

// Use std.c.FILE so this is compatible with posix_libc.FILE; consumers
// that stir both anet_types and posix_libc into one dispatch struct would
// otherwise see two distinct opaque types.
pub const FILE = std.c.FILE;

/// struct hashmap_s — from third-party hashmap.h (sheredom/hashmap.h). The
/// layout is header-provided — consumers may embed it by value (session.zig)
/// as well as pass it by pointer (dir_srv_link.zig). Field order must match
/// the struct in hashmap.h exactly:
///   uint32_t log2_capacity; uint32_t size;
///   hashmap_hasher_t hasher; hashmap_comparer_t comparer;
///   struct hashmap_element_s *data;
pub const struct_hashmap_s = extern struct {
    log2_capacity: u32 = 0,
    size: u32 = 0,
    hasher: ?*const anyopaque = null,
    comparer: ?*const anyopaque = null,
    data: ?*anyopaque = null,
};
pub const hashmap_s = struct_hashmap_s;

pub extern "c" fn hashmap_create(initial_capacity: u32, out_hashmap: *struct_hashmap_s) c_int;
pub extern "c" fn hashmap_put(
    hashmap: *struct_hashmap_s,
    key: ?*const anyopaque,
    len: u32,
    value: ?*anyopaque,
) c_int;
pub extern "c" fn hashmap_get(
    hashmap: *const struct_hashmap_s,
    key: ?*const anyopaque,
    len: u32,
) ?*anyopaque;
pub extern "c" fn hashmap_remove(
    hashmap: *struct_hashmap_s,
    key: ?*const anyopaque,
    len: u32,
) c_int;

// pid_t / PATH_MAX come through posix_libc; redeclared here for the fields
// of struct anet_dircl_opts that embed them inline. The libc module defines
// these identically so TU mixing is fine (compile-time identical).
pub const pid_t = c_int;

// PATH_MAX: 4096 on Linux. Matches <limits.h>.
pub const PATH_MAX: usize = 4096;

// ══════════════════════════════════════════════════════════════════════════════
// Section 1 — a12_helper.h (arcan-net / shmif glue helpers)
// ══════════════════════════════════════════════════════════════════════════════

// Polling state bitmap returned from a12helper_a12srv_shmifcl.
pub const A12HELPER_POLL_SHMIF: c_int = 1;
pub const A12HELPER_WRITE_OUT: c_int = 2;
pub const A12HELPER_DATA_IN: c_int = 4;

pub const enum_a12helper_pollstate = c_uint;

// frame buffer cache types.
pub const FRAME_RAW_SHMIFSRV_VBUFFER: c_int = 0;
pub const FRAME_ENCODED: c_int = 1;
pub const enum_buffer_types = c_uint;

// Tradeoff constant (matches a12_helper.h default).
pub const DIRECTORY_BEACON_MEMBER_SIZE: usize = 32;

// Forward declarations for a12_helper.h types that are only used as pointer
// targets by consumer code; concrete layouts live in the implementation TU.
pub const struct_a12_broadcast_beacon = opaque {};
pub const a12_broadcast_beacon = struct_a12_broadcast_beacon;

pub const struct_ipcfg = opaque {};
pub const ipcfg = struct_ipcfg;

pub const struct_vbuffer_cache = opaque {};
pub const vbuffer_cache = struct_vbuffer_cache;

pub const struct_frame_cache = opaque {};
pub const frame_cache = struct_frame_cache;

// a12helper_opts — passed by value to a12helper_a12cl_shmifsrv / _framecache_sink.
// Consumers construct this literally; byte-accurate layout required.
pub const struct_a12helper_opts = extern struct {
    eval_vcodec: ?*const anyopaque = null, // struct a12_vframe_opts (*)(S, segid, *vbuffer, *tag)
    tag: ?*anyopaque = null,
    vframe_soft_block: usize = 0,
    vframe_block: usize = 0,
    redirect_exit: ?[*:0]const u8 = null,
    devicehint_cp: ?[*:0]const u8 = null,
    bcache_dir: c_int = 0,
    cache: ?*struct_frame_cache = null,
    lock: ?*pthread_mutex_t = null,
};
pub const a12helper_opts = struct_a12helper_opts;

// anet_discover_opts — passed by pointer; consumers read multiple fields.
pub const struct_anet_discover_opts = extern struct {
    limit: c_int = 0,
    timesleep: c_int = 0,
    ipv6: ?[*:0]const u8 = null,
    discover_beacon: ?*const anyopaque = null,
    discover_unknown: ?*const anyopaque = null,
    IP: ?*struct_ipcfg = null,
    on_shmif: ?*const anyopaque = null,
    C: ?*struct_arcan_shmif_cont = null,
};
pub const anet_discover_opts = struct_anet_discover_opts;

// launcher_meta — filled out by anet_client_execargs.
pub const struct_launcher_meta = extern struct {
    bin: ?[*:0]u8 = null,
    env: ?[*]?[*:0]u8 = null,
    argv: ?[*]?[*:0]u8 = null,
    pstdin: [2]c_int = .{ 0, 0 },
    pstdout: [2]c_int = .{ 0, 0 },
};
pub const launcher_meta = struct_launcher_meta;

// Extern functions declared in a12_helper.h.
pub extern "c" fn a12helper_alloc_cache(capacity: u32) ?*struct_frame_cache;
pub extern "c" fn a12helper_framecache_sink(
    S: ?*struct_a12_state,
    C: ?*struct_frame_cache,
    fd: c_int,
    opts: struct_a12helper_opts,
) void;
pub extern "c" fn a12helper_vbuffer_append_raw(
    c_: ?*struct_frame_cache,
    vb: ?*struct_shmifsrv_vbuffer,
    channel: u8,
) void;
pub extern "c" fn a12helper_vbuffer_append_encoded(
    c_: ?*struct_frame_cache,
    buf: [*]u8,
    buf_sz: usize,
    channel: u8,
    keyed: bool,
) void;
pub extern "c" fn a12helper_vbuffer_add_listener(
    c_: ?*struct_frame_cache,
    ref: usize,
    raw: bool,
    trigger: ?*const fn (ref: usize, buf: [*]u8, buf_sz: usize, typ: c_int) callconv(.c) void,
) void;
pub extern "c" fn a12helper_vbuffer_size_hints(
    c_: ?*struct_frame_cache,
    ref: usize,
    w: usize,
    h: usize,
) void;
pub extern "c" fn a12helper_tpack_dimensions(
    c_: ?*struct_frame_cache,
    chid: u8,
    rows: *usize,
    cols: *usize,
) bool;
pub extern "c" fn a12helper_vbuffer_type(c_: ?*struct_frame_cache, chid: u8) c_int;
pub extern "c" fn a12helper_vbuffer_drop_listener(c_: ?*struct_frame_cache, ref: usize) void;
pub extern "c" fn a12helper_vbuffer_step_quality(
    c_: ?*struct_frame_cache,
    ref: usize,
    steps: isize,
) void;
pub extern "c" fn a12helper_a12cl_shmifsrv(
    S: ?*struct_a12_state,
    C: ?*struct_shmifsrv_client,
    fd_in: c_int,
    fd_out: c_int,
    opts: struct_a12helper_opts,
) void;
pub extern "c" fn a12helper_listen_beacon(
    C: ?*struct_arcan_shmif_cont,
    O: ?*struct_anet_discover_opts,
    on_beacon: ?*const anyopaque,
    on_unknown: ?*const anyopaque,
    on_shmif: ?*const anyopaque,
) void;
pub extern "c" fn a12helper_build_beacon(
    head: ?*struct_keystore_mask,
    tail: ?*struct_keystore_mask,
    one: *?[*]u8,
    two: *?[*]u8,
    sz: *usize,
) ?*struct_keystore_mask;
pub extern "c" fn anet_discover_listen_beacon(cfg: *struct_anet_discover_opts) void;
pub extern "c" fn anet_discover_send_beacon(cfg: *struct_anet_discover_opts) bool;
pub extern "c" fn a12helper_discover_ipcfg(
    cfg: *struct_anet_discover_opts,
    beacon: bool,
) ?[*:0]const u8;
pub extern "c" fn a12helper_a12srv_shmifcl(
    prealloc: ?*struct_arcan_shmif_cont,
    S: ?*struct_a12_state,
    cp: ?[*:0]const u8,
    fd_in: c_int,
    fd_out: c_int,
) c_int;
pub extern "c" fn a12helper_tob64(data: [*]const u8, inl: usize, outl: *usize) ?[*]u8;
pub extern "c" fn a12helper_fromb64(instr: [*]const u8, lim: usize, outb: [*]u8) bool;
pub extern "c" fn anet_client_execargs(
    name: ?[*:0]const u8,
    meta: *struct_launcher_meta,
    manifest: ?*struct_arg_arr,
) bool;

// ══════════════════════════════════════════════════════════════════════════════
// Section 2 — anet_helper.h (keystore / connect / listen)
// ══════════════════════════════════════════════════════════════════════════════

pub const A12HELPER_PROVIDER_BASEDIR: c_int = 0;
pub const enum_a12helper_providers = c_uint;

// keystore_provider — the union is accessed as `kp.unnamed_0.directory.dirfd/statefd`
// by consumer code (matches translate-c naming).
pub const struct_keystore_provider = extern struct {
    unnamed_0: extern union {
        directory: extern struct {
            dirfd: c_int = 0,
            statefd: c_int = 0,
        },
    } = .{ .directory = .{} },
    type: c_int = 0,
};
pub const keystore_provider = struct_keystore_provider;

pub const struct_anet_options = extern struct {
    cp: ?[*:0]const u8 = null,
    host: ?[*:0]const u8 = null,
    port: ?[*:0]const u8 = null,
    key: ?[*:0]const u8 = null,
    ignore_key_host: bool = false,
    host_tag: ?[*:0]const u8 = null,
    petname: [16]u8 = std.mem.zeroes([16]u8),
    sockfd: c_int = 0,
    mt_mode: c_int = 0,
    mode: c_int = 0,
    allow_n_keys: c_int = 0,
    redirect_exit: ?[*:0]const u8 = null,
    devicehint_cp: ?[*:0]const u8 = null,
    retry_count: isize = 0,
    keystore: struct_keystore_provider = .{},
    // [*c] to match cImport-style C pointer; callers do `o.opts.*.field`.
    opts: [*c]struct_a12_context_options = null,
};
pub const anet_options = struct_anet_options;

pub const struct_anet_cl_connection = extern struct {
    fd: c_int = 0,
    state: ?*struct_a12_state = null,
    errmsg: ?[*:0]u8 = null,
    auth_failed: bool = false,
};
pub const anet_cl_connection = struct_anet_cl_connection;

// keystore_mask — linked list for build_beacon / public_tagset (WANT_KEYSTORE_HASHER).
pub const struct_keystore_mask = extern struct {
    tag: ?[*:0]u8 = null,
    pubk: [32]u8 = std.mem.zeroes([32]u8),
    next: ?*struct_keystore_mask = null,
};
pub const keystore_mask = struct_keystore_mask;

pub extern "c" fn anet_cl_setup(opts: *struct_anet_options) struct_anet_cl_connection;
pub extern "c" fn anet_connect_to(arg: *struct_anet_options) struct_anet_cl_connection;
pub extern "c" fn a12helper_keystore_open(p: *struct_keystore_provider) bool;
pub extern "c" fn a12helper_keystore_release() bool;
pub extern "c" fn a12helper_keystore_hostkey(
    petname: ?[*:0]const u8,
    index: usize,
    privk: *[32]u8,
    outhost: *?[*:0]u8,
    outport: *u16,
) bool;
pub extern "c" fn a12helper_keystore_tags(
    cb: ?*const fn (petname: ?[*:0]const u8, tag: ?*anyopaque) callconv(.c) bool,
    tag: ?*anyopaque,
) bool;
pub extern "c" fn a12helper_keystore_register(
    petname: ?[*:0]const u8,
    host: ?[*:0]const u8,
    port: u16,
    pubk: *[32]u8,
    priv: ?*[32]u8,
) bool;
pub extern "c" fn a12helper_keystore_accepted(
    pubk: *const [32]u8,
    connp: ?[*:0]const u8,
) ?[*:0]const u8;
pub extern "c" fn a12helper_keystore_known_accepted_challenge(
    pubk: *const [32]u8,
    chg: *const [8]u8,
    on_beacon: ?*const anyopaque,
    shmif: ?*struct_arcan_shmif_cont,
    errout: ?[*:0]u8,
) bool;
pub extern "c" fn a12helper_keystore_public_tagset(mask: *struct_keystore_mask) bool;
pub extern "c" fn a12helper_keystore_accept(pubk: *const [32]u8, connp: ?[*:0]const u8) bool;
pub extern "c" fn a12helper_keystore_get_sigkey(
    tag: ?[*:0]const u8,
    pubk: *[32]u8,
    privk: *[64]u8,
) bool;
pub extern "c" fn a12helper_keystore_gen_sigkey(tag: ?[*:0]const u8, overwrite: bool) bool;
pub extern "c" fn a12helper_keystore_accept_ephemeral(
    pubk: *const [32]u8,
    connp: ?[*:0]const u8,
    id: ?[*:0]const u8,
) void;
pub extern "c" fn a12helper_keystore_flush_ephemeral(id: ?[*:0]const u8) void;
pub extern "c" fn anet_clfd(addr: ?*anyopaque) c_int;
pub extern "c" fn anet_authenticate(
    S: ?*struct_a12_state,
    fdin: c_int,
    fdout: c_int,
    err: *?[*:0]u8,
) bool;
pub extern "c" fn a12helper_keystore_statestore(
    pubk: *const [32]u8,
    name: ?[*:0]const u8,
    sz: usize,
    mode: ?[*:0]const u8,
) c_int;
pub extern "c" fn a12helper_keystore_stateunlink(
    pubk: *const [32]u8,
    name: ?[*:0]const u8,
) bool;
pub extern "c" fn a12helper_keystore_enumerate(ref: *usize, pubk: *[32]u8) bool;
pub extern "c" fn a12helper_keystore_dirfd(err: *?[*:0]const u8) c_int;
pub extern "c" fn a12helper_query_untrusted_key(
    trust_domain: ?[*:0]const u8,
    kpub_b64: [*]u8,
    kpub: *const [32]u8,
    out_tag: *?[*:0]u8,
    prefix_ofs: *usize,
) bool;
pub extern "c" fn anet_listen(
    args: *struct_anet_options,
    errmsg: *?[*:0]u8,
    dispatch: ?*const fn (S: ?*struct_a12_state, fd: c_int, tag: ?*anyopaque) callconv(.c) void,
    tag: ?*anyopaque,
) bool;

// ══════════════════════════════════════════════════════════════════════════════
// Section 3 — directory.h (directory server / client types & fns)
// ══════════════════════════════════════════════════════════════════════════════

// Signature sizes.
pub const SIG_PUBK_SZ: usize = 32;
pub const SIG_PRIVK_SZ: usize = 64;
pub const SIG_VAL_SZ: usize = 64;

// monitor_mode enum.
pub const MONITOR_NONE: c_int = 0;
pub const MONITOR_SIMPLE: c_int = 1;
pub const MONITOR_DEBUGGER: c_int = 2;
pub const MONITOR_ADMIN: c_int = 3;
pub const enum_monitor_mode = c_uint;

// link-type enum used by anet_directory_shmifsrv_thread.
pub const DIRLINK_NONE: c_int = 0;
pub const DIRLINK_UNIFIED: c_int = 1;
pub const DIRLINK_REFERENCE: c_int = 2;
pub const DIRLINK_RESOLVER: c_int = 3;

// revert / step dmask bits.
pub const REVERT_STEP_CTRL: c_int = 1;
pub const REVERT_STEP_APPL: c_int = 2;

// BREQ_LOAD / BREQ_STORE — booleans used as enum tags.
pub const BREQ_LOAD: c_int = 0;
pub const BREQ_STORE: c_int = 1;

// dirlua event kinds.
pub const DIRLUA_EVENT_LOST: c_int = 0;

// Entrypoint indices — mirrors dir_lua_support.h EP_TRIGGER_* enum.
pub const EP_TRIGGER_NONE: c_int = 0;
pub const EP_TRIGGER_MAIN: c_int = 1;
pub const EP_TRIGGER_CLOCK: c_int = 2;
pub const EP_TRIGGER_MESSAGE: c_int = 3;
pub const EP_TRIGGER_NBIO_RD: c_int = 4;
pub const EP_TRIGGER_NBIO_WR: c_int = 5;
pub const EP_TRIGGER_NBIO_DATA: c_int = 6;
pub const EP_TRIGGER_TRACE: c_int = 7;
pub const EP_TRIGGER_RESET: c_int = 8;
pub const EP_TRIGGER_JOIN: c_int = 9;
pub const EP_TRIGGER_LEAVE: c_int = 10;
pub const EP_TRIGGER_INDEX: c_int = 11;
pub const EP_TRIGGER_LOAD: c_int = 12;
pub const EP_TRIGGER_STORE: c_int = 13;
pub const EP_TRIGGER_LIMIT: c_int = 14;

// multipart merge errors.
pub const MULTIPART_OOM: c_int = 1;
pub const MULTIPART_BAD_FMT: c_int = 2;
pub const MULTIPART_BAD_MSG: c_int = 3;
pub const MULTIPART_BAD_EVENT: c_int = 4;
pub const enum_multipart_fail = c_uint;

// anet_dirsrv_opts — filled by main/config.lua, passed by value in
// anet_directory_srv and by pointer in most other call sites.
pub const struct_anet_dirsrv_opts = extern struct {
    a12_cfg: ?*struct_a12_context_options = null,
    basedir: c_int = 0,
    dir: struct_appl_meta = .{},
    dir_count: usize = 0,

    allow_tunnel: bool = false,
    discover_beacon: bool = false,
    runner_process: bool = false,
    flush_on_report: bool = false,

    allow_src: ?[*:0]u8 = null,
    allow_dir: ?[*:0]u8 = null,
    allow_appl: ?[*:0]u8 = null,
    allow_ctrl: ?[*:0]u8 = null,
    allow_ares: ?[*:0]u8 = null,
    allow_admin: ?[*:0]u8 = null,
    allow_monitor: ?[*:0]u8 = null,
    allow_applhost: ?[*:0]u8 = null,
    allow_install: ?[*:0]u8 = null,
    allow_reference: ?[*:0]u8 = null,

    resource_path: ?[*:0]u8 = null,
    resource_dfd: c_int = 0,

    appl_server_path: ?[*:0]u8 = null,
    appl_server_dfd: c_int = 0,

    appl_server_datapath: ?[*:0]u8 = null,
    appl_server_datadfd: c_int = 0,

    appl_logpath: ?[*:0]u8 = null,
    applhost_path: ?[*:0]u8 = null,

    appl_server_temp_path: ?[*:0]u8 = null,
    appl_server_temp_dfd: c_int = 0,

    appl_logdfd: c_int = 0,
};
pub const anet_dirsrv_opts = struct_anet_dirsrv_opts;

// source_meta — embedded array inside struct runner_state.
pub const struct_source_meta = extern struct {
    pubk: [32]u8 = std.mem.zeroes([32]u8),
    force_ident: [16]u8 = std.mem.zeroes([16]u8),
    ref_id: usize = 0,
};
pub const source_meta = struct_source_meta;

pub const struct_runner_state = extern struct {
    lock: pthread_mutex_t = .{},
    cl: ?*struct_shmifsrv_client = null,
    resolver: ?*struct_dircl = null,
    appl: ?*struct_appl_meta = null,
    alive: bool = false,
    appl_sent: bool = false,
    store_dfd: c_int = 0,
    pending_sources: [8]struct_source_meta = std.mem.zeroes([8]struct_source_meta),
};
pub const runner_state = struct_runner_state;

// dircl_nameent — used inline in anet_dircl_opts for dpath/upload/download.
pub const struct_dircl_nameent = extern struct {
    name: ?[*:0]u8 = null,
    path: ?[*:0]u8 = null,
    srvname: [16]u8 = std.mem.zeroes([16]u8),
    next: ?*struct_dircl_nameent = null,
};
pub const dircl_nameent = struct_dircl_nameent;

// anet_dircl_opts — passed by value to anet_directory_cl; heavy field usage.
pub const struct_anet_dircl_opts = extern struct {
    last_connection: struct_anet_options = .{},

    basedir: c_int = 0,
    basedir_path: [PATH_MAX]u8 = std.mem.zeroes([PATH_MAX]u8),

    dpath: struct_dircl_nameent = .{},

    appl_runner: ?[*:0]u8 = null,
    appl_override: ?[*:0]u8 = null,
    applname: [18]u8 = std.mem.zeroes([18]u8),
    applid: u16 = 0,

    die_on_list: bool = false,
    reload: bool = false,
    block_state: bool = false,
    dump_state: ?[*:0]u8 = null,
    block_log: bool = false,
    stderr_log: bool = false,
    keep_appl: bool = false,
    request_tunnel: bool = false,
    applhost: bool = false,
    reconnect: bool = false,
    monitor_mode: c_int = 0,

    ident: [16]u8 = std.mem.zeroes([16]u8),
    sign_tag: ?[*:0]const u8 = null,

    // void(*)(struct a12_state*, struct a12_dynreq, void*)
    dir_source: ?*const fn (
        *struct_a12_state,
        struct_a12_dynreq,
        ?*anyopaque,
    ) callconv(.c) void = null,
    dir_source_tag: ?*anyopaque = null,
    source_port: u16 = 0,

    outapp: struct_appl_meta = .{},
    outapp_install: bool = false,
    outapp_ctrl: bool = false,
    build_appl: ?[*:0]u8 = null,
    build_appl_dfd: c_int = 0,

    upload: struct_dircl_nameent = .{},
    download: struct_dircl_nameent = .{},

    // void*(*)(struct a12_state*, struct directory_meta*, const char*)
    allocator: ?*const fn (
        ?*struct_a12_state,
        ?*struct_directory_meta,
        ?[*:0]const u8,
    ) callconv(.c) ?*anyopaque = null,
    // pid_t(*)(struct a12_state*, struct directory_meta*,
    //   const char*, void* tag, int* inf, int* outf)
    executor: ?*const fn (
        ?*struct_a12_state,
        ?*struct_directory_meta,
        ?[*:0]const u8,
        ?*anyopaque,
        ?*c_int,
        ?*c_int,
    ) callconv(.c) pid_t = null,
};
pub const anet_dircl_opts = struct_anet_dircl_opts;

// directory_meta — shared per-connection state between worker and directory.
pub const struct_directory_meta = extern struct {
    S: ?*struct_a12_state = null,
    // [*c] pointer so callers can dereference via .* / .*.field matching
    // the legacy @cImport-derived C-pointer semantics used throughout
    // dir_cl.zig and dir_srv_worker.zig.
    clopt: [*c]struct_anet_dircl_opts = null,
    secret: ?[*:0]u8 = null,
    in_transfer: bool = false,
    transfer_id: u32 = 0,
    appl_out: ?*FILE = null,
    appl_out_complete: bool = false,
    appl_hash: [4]u8 = std.mem.zeroes([4]u8),
    state_in: c_int = -1,
    state_in_complete: bool = false,
    breq_pending: struct_arcan_event = .{ .pad = @splat(0) },
    tag: ?*anyopaque = null,
    C: ?*struct_arcan_shmif_cont = null,
};
pub const directory_meta = struct_directory_meta;

// dircl — per-client tracking struct.
pub const struct_dircl = extern struct {
    in_appl: c_int = 0,
    in_monitor: bool = false,
    identity: [16]u8 = std.mem.zeroes([16]u8),
    type: c_int = 0,

    pending_stream: bool = false,
    pending_fd: c_int = 0,
    pending_id: u16 = 0,

    // netstate event used to transfer keys (matches C struct dircl fields).
    petname: struct_arcan_event = .{ .pad = @splat(0) },
    endpoint: struct_arcan_event = .{ .pad = @splat(0) },

    lua_cb: isize = 0,

    pubk: [32]u8 = std.mem.zeroes([32]u8),
    authenticated: bool = false,
    in_admin: bool = false,

    dir_link: bool = false,
    dir_ref: bool = false,
    dir_resolver: bool = false,

    admin_fdout: c_int = 0,

    pubk_sign: [SIG_PUBK_SZ]u8 = std.mem.zeroes([SIG_PUBK_SZ]u8),

    message_multipart: [1024]u8 = std.mem.zeroes([1024]u8),
    message_ofs: usize = 0,
    userdata: ?*anyopaque = null,

    C: ?*struct_shmifsrv_client = null,

    ref_id: usize = 0,

    next: ?*struct_dircl = null,
    prev: ?*struct_dircl = null,
    tunnel: ?*struct_dircl = null,
};
pub const dircl = struct_dircl;

// global_cfg — top-level loaded from config.lua.
pub const struct_global_cfg = extern struct {
    soft_auth: bool = false,
    no_default: bool = false,
    probe_only: bool = false,
    keep_alive: bool = false,
    cast: bool = false,
    discover_synch: bool = false,

    accept_n_pk_unknown: usize = 0,
    backpressure: usize = 0,
    backpressure_soft: usize = 0,
    directory: c_int = 0,
    dirsrv: struct_anet_dirsrv_opts = .{},
    dircl: struct_anet_dircl_opts = .{},
    meta: struct_anet_options = .{},

    use_forced_remote_pubk: bool = false,
    forced_remote_pubk: [32]u8 = std.mem.zeroes([32]u8),

    trust_domain: ?[*:0]u8 = null,
    path_self: ?[*:0]u8 = null,
    outbound_tag: ?[*:0]u8 = null,
    config_file: ?[*:0]u8 = null,
    db_file: ?[*:0]u8 = null,
};
pub const global_cfg = struct_global_cfg;

// dirlua_event.
pub const struct_dirlua_event = extern struct {
    kind: c_int = 0,
    msg: ?[*:0]const u8 = null,
};
pub const dirlua_event = struct_dirlua_event;

// dirlua_monitor_state — matches `struct dirlua_monitor_state` in
// dir_lua_support.h. Members are read/written directly by
// dir_lua_support.zig so the layout must stay in lockstep.
pub const BREAK_LIMIT: usize = 8;
pub const struct_dirlua_monitor_state_breakpoint = extern struct {
    bpt: extern struct {
        line: usize = 0,
        file: ?[*:0]u8 = null,
    } = .{},
    type: c_int = 0,
};
pub const struct_dirlua_monitor_state = extern struct {
    breakpoints: [BREAK_LIMIT]struct_dirlua_monitor_state_breakpoint =
        [_]struct_dirlua_monitor_state_breakpoint{.{}} ** BREAK_LIMIT,
    n_breakpoints: usize = 0,
    in_breakpoint_set: bool = false,
    hook_mask: c_int = 0,
    lock: bool = false,
    stepreq: bool = false,
    dumppause: bool = false,
    @"error": bool = false,
    transaction: bool = false,

    out_buf: ?[*:0]u8 = null,
    out_sz: usize = 0,
    out: ?*FILE = null,
    C: ?*struct_arcan_shmif_cont = null,
};
pub const dirlua_monitor_state = struct_dirlua_monitor_state;

// evqueue_entry — dynamic list of events received while waiting for a bchunk reply.
pub const struct_evqueue_entry = extern struct {
    ev: struct_arcan_event = .{ .pad = @splat(0) },
    next: ?*struct_evqueue_entry = null,
};
pub const evqueue_entry = struct_evqueue_entry;

// ioloop_shared — main event loop driver struct.
pub const struct_ioloop_shared = extern struct {
    fdin: c_int = 0,
    fdout: c_int = 0,
    userfd: c_int = 0,
    userfd2: c_int = 0,
    wakeup: c_int = 0,

    shmif: struct_arcan_shmif_cont = .{},
    handover: ?*struct_arcan_shmif_cont = null,

    lock: pthread_mutex_t = .{},
    S: ?*struct_a12_state = null,
    shutdown: bool = false,
    cbt: ?*struct_directory_meta = null,

    on_event: ?*const anyopaque = null,
    on_directory: ?IoloopDirectoryCb = null,
    on_userfd: ?IoloopFdCb = null,
    on_userfd2: ?IoloopFdCb = null,
    on_shmif: ?IoloopFdCb = null,
    on_disconnected: ?IoloopDisconnectCb = null,
    tag: ?*anyopaque = null,
};
pub const ioloop_shared = struct_ioloop_shared;

/// Callback type for struct_ioloop_shared.on_userfd / on_shmif / on_userfd2.
/// Signature mirrors dir_supp.c: `void (*)(struct ioloop_shared*, bool ok)`.
pub const IoloopFdCb = *const fn (I: *struct_ioloop_shared, ok: bool) callconv(.c) void;
/// Callback type for struct_ioloop_shared.on_directory.
/// Signature: `bool (*)(struct ioloop_shared*, struct appl_meta*)`.
pub const IoloopDirectoryCb = *const fn (I: *struct_ioloop_shared, dir: *struct_appl_meta) callconv(.c) bool;
/// Callback type for struct_ioloop_shared.on_disconnected.
/// Signature: `bool (*)(struct ioloop_shared*)` — returns true to retry connect.
pub const IoloopDisconnectCb = *const fn (I: *struct_ioloop_shared) callconv(.c) bool;

// Extern functions declared in directory.h.
pub extern "c" fn anet_directory_lua_event(C: ?*struct_dircl, ev: *struct_dirlua_event) void;
pub extern "c" fn anet_directory_lua_notify_source(
    A: ?*struct_appl_meta,
    name: [*c]const u8,
    msg: [*c]const u8,
    ref_id: usize,
) void;
pub extern "c" fn anet_directory_srv_scan(opts: *struct_anet_dirsrv_opts) void;
pub extern "c" fn anet_directory_srv_revert(slot: u16, steps: c_int, dmask: c_int) bool;
pub extern "c" fn anet_directory_srv(
    ctx: ?*struct_a12_context_options,
    opts: struct_anet_dirsrv_opts,
    fdin: c_int,
    fdout: c_int,
) void;
pub extern "c" fn anet_directory_shmifsrv_thread(
    cl: ?*struct_shmifsrv_client,
    S: ?*struct_a12_state,
    link_type: c_int,
) ?*struct_dircl;
pub extern "c" fn anet_directory_shmifsrv_set(opts: *struct_anet_dirsrv_opts) void;
pub extern "c" fn anet_directory_cl(
    S: ?*struct_a12_state,
    opts: struct_anet_dircl_opts,
    fdin: c_int,
    fdout: c_int,
) void;
pub extern "c" fn anet_directory_cl_bhandler(
    S: ?*struct_a12_state,
    M: struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) struct_a12_bhandler_res;
pub extern "c" fn dircl_source_handler(
    S: ?*struct_a12_state,
    req: struct_a12_dynreq,
    tag: ?*anyopaque,
) void;
pub extern "c" fn dircl_apphash_cached(
    checksum: *[4]u8,
    prefix: ?[*:0]const u8,
    outname: *?[*:0]u8,
) c_int;
pub extern "c" fn dircl_xfer_complete(
    I: *struct_ioloop_shared,
    M: struct_a12_bhandler_meta,
) void;
pub extern "c" fn verify_appl_pkg(
    buf: [*]u8,
    buf_sz: usize,
    insig_pk: *[SIG_PUBK_SZ]u8,
    outsig_pk: *[SIG_PUBK_SZ]u8,
    errmsg: *?[*:0]const u8,
) ?[*:0]u8;
pub extern "c" fn build_appl_pkg(
    name: ?[*:0]u8,
    dst: *struct_appl_meta,
    dirfd: c_int,
    signtag: ?[*:0]const u8,
) bool;
pub extern "c" fn extract_appl_pkg(
    fin: ?*FILE,
    dirfd: c_int,
    basename: ?[*:0]const u8,
    msg: *?[*:0]const u8,
    manifest: *?*struct_arg_arr,
) bool;
pub extern "c" fn file_to_membuf(applin: ?*FILE, out: *?[*:0]u8, out_sz: *usize) ?*FILE;
pub extern "c" fn anet_directory_random_ident(dst: [*]u8, nb: usize) void;
pub extern "c" fn anet_lua_init(cfg: *struct_global_cfg) bool;
pub extern "c" fn anet_directory_lua_ready(cfg: *struct_global_cfg) void;
pub extern "c" fn anet_directory_lua_update(appl: ?*struct_appl_meta, newappl: c_int) void;
pub extern "c" fn anet_directory_lua_admin_command(C: ?*struct_dircl, msg: ?[*:0]const u8) bool;
pub extern "c" fn anet_directory_appl_runner() void;
pub extern "c" fn anet_directory_lua_unregister(C: ?*struct_dircl) void;
pub extern "c" fn anet_directory_lua_register_unknown(
    C: ?*struct_dircl,
    base: struct_pk_response,
    pubk: ?[*:0]const u8,
) struct_pk_response;
pub extern "c" fn anet_directory_lua_register(C: ?*struct_dircl) void;
pub extern "c" fn anet_directory_lua_spawn_runner(
    appl: ?*struct_appl_meta,
    external: bool,
) bool;
pub extern "c" fn anet_directory_signal_runner(appl: ?*struct_appl_meta, no: c_int) bool;
pub extern "c" fn anet_directory_lua_join(C: ?*struct_dircl, appl: ?*struct_appl_meta) bool;
pub extern "c" fn anet_directory_lua_monitor(C: ?*struct_dircl, appl: ?*struct_appl_meta) bool;
pub extern "c" fn anet_directory_lua_bchunk_completion(C: ?*struct_dircl, ok: bool) void;
pub extern "c" fn anet_directory_lua_filter_source(
    C: ?*struct_dircl,
    ev: ?*struct_arcan_event,
) c_int;
pub extern "c" fn anet_directory_lua_forced_source(C: ?*struct_dircl) bool;
pub extern "c" fn anet_directory_tunnel_thread(ios: *struct_ioloop_shared, chid: u8) void;
pub extern "c" fn anet_directory_ioloop_current() ?*struct_ioloop_shared;
pub extern "c" fn anet_directory_ioloop(S: *struct_ioloop_shared) void;
pub extern "c" fn anet_directory_lua_trigger_auto(appl: ?*struct_appl_meta) void;
pub extern "c" fn dirsrv_global_lock(file: ?[*:0]const u8, line: c_int) void;
pub extern "c" fn dirsrv_global_unlock(file: ?[*:0]const u8, line: c_int) void;
pub extern "c" fn anet_directory_merge_multipart(
    ev: ?*struct_arcan_event,
    out: ?*?*struct_arg_arr,
    outchar: ?*?[*:0]u8,
    err: ?*c_int,
) bool;
pub extern "c" fn anet_directory_link(
    keytag: ?[*:0]const u8,
    netcfg: *struct_anet_options,
    srvcfg: struct_anet_dirsrv_opts,
    ident: ?[*:0]const u8,
    reference: bool,
) c_int;
pub extern "c" fn dir_unpack_index(fd: c_int) ?*struct_appl_meta;
pub extern "c" fn dir_request_resource(
    C: ?*struct_arcan_shmif_cont,
    ns: usize,
    id: ?[*:0]const u8,
    mode: c_int,
    pending: ?*struct_evqueue_entry,
) bool;
pub extern "c" fn dirsrv_find_cl_ident(
    appid: c_int,
    name: ?[*:0]const u8,
    lock: bool,
) ?*struct_dircl;
pub extern "c" fn dir_block_synch_request(
    C: ?*struct_arcan_shmif_cont,
    outev: struct_arcan_event,
    pending: ?*struct_evqueue_entry,
    category_ok: c_int,
    kind_ok: c_int,
    category_fail: c_int,
    kind_fail: c_int,
) bool;
pub extern "c" fn dirsrv_set_source_mask(
    pubk: *[32]u8,
    appid: c_int,
    identity: *[16]u8,
    dstpubk: *[32]u8,
) void;
pub extern "c" fn dirsrv_build_report(appl: ?[*:0]const u8) c_int;
pub extern "c" fn dirsrv_flush_report(appl: ?[*:0]const u8) void;
pub extern "c" fn dirsrv_bchunk_req(
    C: ?*struct_dircl,
    ns: usize,
    ext: ?[*:0]u8,
    input: bool,
) void;
pub extern "c" fn dirsrv_bchunk_completion(C: ?*struct_dircl, ok: bool) void;
pub extern "c" fn dirsrv_opts() ?*struct_global_cfg;
pub extern "c" fn dirsrv_config() ?*struct_anet_dirsrv_opts;
pub extern "c" fn dirsrv_trace_state() ?*struct_a12_state;
pub extern "c" fn dirsrv_locked_numid_appl(id: u16) ?*struct_appl_meta;
pub extern "c" fn buf_memfd(buf: [*c]const u8, buf_sz: usize) c_int;
pub extern "c" fn anet_directory_ephemeral_source(
    id: u16,
    name: ?[*:0]const u8,
    dstname: ?[*:0]const u8,
    refid: usize,
) bool;
pub extern "c" fn anet_directory_dirsrv_exec_source(
    dst: ?*struct_dircl,
    applid: u16,
    ident: ?[*:0]const u8,
    exec: ?[*:0]u8,
    argv: ?*struct_arcan_strarr,
    envv: ?*struct_arcan_strarr,
) bool;
// anet_directory_lua_init — dir_lua.h, exported by dir_lua.zig.
// `L` is `lua_State*` (opaque to this module).
pub extern "c" fn anet_directory_lua_init(cfg: *struct_global_cfg, L: ?*anyopaque) void;
pub extern "c" fn anet_directory_lua_cfg(C: *struct_global_cfg, L: ?*anyopaque) void;
pub extern "c" fn anet_client_lua_cfg(C: *struct_global_cfg, L: ?*anyopaque) void;
pub extern "c" fn anet_client_lua_getpath(key: ?[*:0]const u8) ?[*:0]u8;

// dir_*(L) — Lua bindings exported by dir_lua.zig (dir_lua.h). Each accepts
// the Lua state as an opaque pointer; callers cast from lua.lua_State*.
pub extern "c" fn dir_write(L: ?*anyopaque) c_int;
pub extern "c" fn dir_endpoint(L: ?*anyopaque) c_int;
pub extern "c" fn dir_linkdirectory(L: ?*anyopaque) c_int;
pub extern "c" fn dir_refdirectory(L: ?*anyopaque) c_int;
pub extern "c" fn dir_launchtarget(L: ?*anyopaque) c_int;
pub extern "c" fn dir_matchkeys(L: ?*anyopaque) c_int;
pub extern "c" fn dir_storekey(L: ?*anyopaque) c_int;
pub extern "c" fn dir_getkey(L: ?*anyopaque) c_int;
pub extern "c" fn dir_flushreport(L: ?*anyopaque) c_int;
pub extern "c" fn dir_appllist(L: ?*anyopaque) c_int;
pub extern "c" fn dir_applrevert(L: ?*anyopaque) c_int;
pub extern "c" fn dir_ctrlrevert(L: ?*anyopaque) c_int;
pub extern "c" fn dir_launchresolver(L: ?*anyopaque) c_int;
pub extern "c" fn dir_applresolver(L: ?*anyopaque) c_int;
pub extern "c" fn dir_messagealias(L: ?*anyopaque) c_int;
pub extern "c" fn dir_hookresource(L: ?*anyopaque) c_int;

// ══════════════════════════════════════════════════════════════════════════════
// Section 4 — Compile-time layout sanity (best effort).
//   Extern structs whose size we expect from the C headers on x86_64 Linux.
// ══════════════════════════════════════════════════════════════════════════════

comptime {
    // keystore_provider: { int dirfd; int statefd; } anon-union + int type → 12 bytes.
    std.debug.assert(@sizeOf(struct_keystore_provider) == 12);
    // anet_cl_connection: int + ptr + ptr + bool (+pad) → 32 bytes on LP64.
    std.debug.assert(@sizeOf(struct_anet_cl_connection) == 32);
    // a12_dynreq: 46 + 32 + 2 + 12 + 4 + 32 = 128 bytes, with alignment.
    std.debug.assert(@sizeOf(struct_a12_dynreq) == 128);
    // pk_response: bool + 32 + 32 + ptr = 80 bytes.
    std.debug.assert(@sizeOf(struct_pk_response) == 80);
    // source_meta: 32 + 16 + 8 = 56.
    std.debug.assert(@sizeOf(struct_source_meta) == 56);
    // dirlua_event: int + ptr = 16 bytes (with padding).
    std.debug.assert(@sizeOf(struct_dirlua_event) == 16);
    // dircl_nameent: 3 ptrs + 16 = 16*3 bytes on LP64 = 48.
    std.debug.assert(@sizeOf(struct_dircl_nameent) == 40);
}
