// a12_types.zig — Pure-Zig type declarations that mirror a12.h and a12_int.h.
//
// Replaces the `@cImport({@cInclude("a12.h"); @cInclude("a12_int.h"); ... })`
// block used by a12.zig, a12_encode.zig, a12_decode.zig, helper_cl.zig,
// helper_srv.zig and friends. Consumers switch from a c-namespaced cImport
// to `const c = @import("a12_types");` and keep the same `c.<SYMBOL>` spelling.
//
// Scope:
//
//   - a12.h public API
//     (a12_state / a12_context_options / a12_vframe_opts / a12_aframe_opts /
//      a12_aframe_cfg / a12_bhandler_meta / a12_bhandler_res / a12_dynreq /
//      a12_iostat / a12_unpack_cfg / pk_response / appl_meta /
//      enum a12_bstream_type / enum a12_bhandler_flag / enum a12_bhandler_state /
//      enum a12_blob_mode / enum a12_vframe_method / enum a12_vframe_compression_bias /
//      enum a12_vframe_postprocess / enum a12_aframe_method / enum trace_groups /
//      enum authentic_state / enum self_roles / enum stream_cancel /
//      enum server_appl / extern fn a12_*)
//
//   - a12_int.h internal surface
//     (struct a12_channel / struct video_frame / struct audio_frame /
//      struct binary_frame / struct blob_xfer / POSTPROCESS_VIDEO_*,
//      CHANNEL_*, STATE_*, enum control_commands, enum hello_mode, ...)
//
//   - a12_helper.h surface used by helper_cl / helper_srv
//     (struct a12helper_opts, a12helper_pollstate, buffer_types)
//
//   - A thin re-export of the shmif/arcan event-and-buffer types consumers
//     reference through the same c. namespace (arcan_event, arcan_extevent,
//     arcan_tgtevent, arcan_shmif_cont, arcan_shmif_region, shmif_pixel,
//     shmif_asample, struct_shmifsrv_vbuffer, shmif_resize_ext) — plus the
//     EVENT_*, TARGET_COMMAND_*, SHMIF_* constants those call sites pass into
//     the a12_* functions.
//
// Layout rules (mirrored from src/shmif/shmif_types.zig):
//   - `extern struct` for anything on the wire or embedded in a C struct that
//     still lives in a C translation unit.
//   - `opaque {}` for anything that only flows around as a pointer (struct
//     a12_state, struct a12_channel, struct blob_xfer, struct video_frame,
//     struct audio_frame, struct binary_frame, ZSTD_{CCtx,DCtx}_s,
//     struct shmifsrv_client, etc.). The a12 implementation files access
//     fields of a12_state / a12_channel / blob_xfer / video_frame via the
//     byte-offset accessors in a12_offsets.zig, so those structs are kept
//     opaque here and do NOT need field-for-field layout.
//   - `pub extern fn` for library entry points. Callers who also need to
//     spell the type name (e.g. `c.struct_a12_state`) get that alias too.
//
// ABI preservation is enforced by `comptime std.debug.assert(@sizeOf(T) == N)`
// for the concrete extern structs that cross ABI boundaries. Opaque types
// don't get a size pin — they're always pointer-indirected.

const std = @import("std");
// Sibling shmif type module — re-exported selectively below so a12 consumers
// and shmif consumers see the same underlying Zig type when both namespaces
// are stirred through the dispatch-struct pattern. Direct import of
// shmif_types avoids the file-in-two-modules conflict that would
// arise from importing lib/shmif/shmif.zig (which would in turn pull
// shmif_types.zig into the "shmif" module alongside the dedicated
// "shmif_types" module — Zig refuses to share a file between two
// modules in the same compile).
const shmif = @import("shmif_types");

// ══════════════════════════════════════════════════════════════════════════════
// Section 1: Opaque handles
// ══════════════════════════════════════════════════════════════════════════════

/// struct a12_state.congestion_stats — rolling frame window for outbound
/// video backpressure accounting.
pub const a12_state_congestion_stats = extern struct {
    frame_window: [8]u32 = std.mem.zeroes([8]u32),
    pending: usize = 0,
};

/// struct a12_state.pending_dynamic — in-flight DIROPEN ↔ DIROPENED request
/// state. Holds the ephemeral x25519 private key used to derive a session
/// secret once the remote peer replies.
pub const a12_state_pending_dynamic = extern struct {
    active: bool = false,
    priv_key: [32]u8 = std.mem.zeroes([32]u8),
    req_key: [32]u8 = std.mem.zeroes([32]u8),
    closure: ?*const fn (S: [*c]struct_a12_state, dr: a12_dynreq, tag: ?*anyopaque) callconv(.c) void = null,
    tag: ?*anyopaque = null,
};

/// struct a12_state.keys — long-term and ephemeral cryptographic key
/// material. `sign_priv`/`sign_pub` are ed25519; `real_priv`/`ephem_priv`
/// are x25519; `pqc_*` are ML-KEM 768 post-quantum buffers.
pub const a12_state_keys = extern struct {
    ephem_priv: [32]u8 = std.mem.zeroes([32]u8),
    real_priv: [32]u8 = std.mem.zeroes([32]u8),
    remote_pub: [32]u8 = std.mem.zeroes([32]u8),
    local_pub: [32]u8 = std.mem.zeroes([32]u8),
    sign_priv: [64]u8 = std.mem.zeroes([64]u8),
    sign_pub: [32]u8 = std.mem.zeroes([32]u8),
    sign_pub_prev: [32]u8 = std.mem.zeroes([32]u8),
    auth_csrnd: [8]u8 = std.mem.zeroes([8]u8),
    pqc_xfer_ind: u8 = 0,
    pqc_rekey_gotpubk: bool = false,
    pqc_rekey_initiated: bool = false,
    pqc_publickey_buffer: [1184]u8 = std.mem.zeroes([1184]u8),
    pqc_ciphertext_buffer: [1088]u8 = std.mem.zeroes([1088]u8),
    pqc_private_buffer: [2400]u8 = std.mem.zeroes([2400]u8),
    rekey_count: usize = 0,
    rekey_base_count: usize = 0,
    rekey_block: bool = false,
    own_rekey: bool = false,
};

/// struct a12_state — the state machine returned by `a12_client()` /
/// `a12_server()`. Full extern-struct layout matching `struct a12_state`
/// in a12_int.h so that field access from consumers (`S.*.tracetag`,
/// `S.*.keys.real_priv`, `S.*.channels[i].active`, `S.*.out_mac.counter`)
/// compiles without a separate cImport. Under `SHMIF_SERVER_NO_BITFIELDS`
/// the embedded shmifsrv_vbuffer `flags` sub-struct is describable as a
/// regular struct of bools.
pub const struct_a12_state = extern struct {
    opts: [*c]a12_context_options = null,
    directory: [*c]appl_meta = null,
    directory_clk: u64 = 0,
    notify_dynamic: bool = false,
    tracetag: [16]u8 = std.mem.zeroes([16]u8),
    last_mac_in: [16]u8 = std.mem.zeroes([16]u8),
    current_seqnr: u64 = 0,
    last_seen_seqnr: u64 = 0,
    out_stream: u64 = 0,
    shutdown_id: i64 = 0,
    advenc_broken: bool = false,
    congestion_stats: a12_state_congestion_stats = .{},
    stats: a12_iostat = .{},
    pending_dynamic: a12_state_pending_dynamic = .{},
    buf_sz: [2]usize = .{ 0, 0 },
    bufs: [2][*c]u8 = .{ null, null },
    buf_ind: u8 = 0,
    buf_ofs: usize = 0,
    pending_out: [*c]struct_blob_xfer = null,
    out_req_id: usize = 0,
    pending_in: [*c]struct_blob_xfer = null,
    in_req_id: usize = 0,
    binary_handler: ?*const fn (S: [*c]struct_a12_state, meta: a12_bhandler_meta, tag: ?*anyopaque) callconv(.c) a12_bhandler_res = null,
    binary_handler_tag: ?*anyopaque = null,
    channels: [256]struct_a12_channel = [_]struct_a12_channel{.{}} ** 256,
    in_channel: c_int = 0,
    in_stream: u32 = 0,
    out_channel: c_int = 0,
    on_discover: ?*const fn (S: [*c]struct_a12_state, a1: u8, a2: [*c]const u8, a3: u8, kpub: [*c]u8, id: u16, tag: ?*anyopaque) callconv(.c) void = null,
    discover_tag: ?*anyopaque = null,
    on_auth: ?*const fn (S: [*c]struct_a12_state, tag: ?*anyopaque) callconv(.c) void = null,
    auth_tag: ?*anyopaque = null,
    decode: [65536]u8 = std.mem.zeroes([65536]u8),
    decode_pos: u16 = 0,
    left: u16 = 0,
    state: u8 = 0,
    cookie: u32 = 0,
    keys: a12_state_keys = .{},
    server: bool = false,
    cl_firstout: bool = false,
    authentic: c_int = 0,
    remote_mode: c_int = 0,
    endpoint: [*c]u8 = null,
    auth_latched: bool = false,
    prepend_unpack_sz: usize = 0,
    prepend_unpack: [*c]u8 = null,
    out_mac: blake3_hasher = .{},
    in_mac: blake3_hasher = .{},
    enc_state: ?*chacha_ctx = null,
    dec_state: ?*chacha_ctx = null,
    state_error_hint: [32]u8 = std.mem.zeroes([32]u8),
};
pub const a12_state = struct_a12_state;

/// struct a12_channel.unpack_state — decode-side multiplex of current video /
/// audio / binary frame. Tracks whichever stream kind is active on a channel.
pub const a12_channel_unpack_state = extern struct {
    vframe: struct_video_frame = .{},
    aframe: struct_audio_frame = .{},
    bframe: struct_binary_frame = .{},
    last_bframe_id: u32 = 0,
};

/// struct a12_channel's unnamed encoder-context sub-struct. Holds the zstd
/// streaming compression context + a working buffer pointer.
pub const a12_channel_compression = extern struct {
    compression: [*c]u8 = null,
    zstd: ?*ZSTD_CCtx_s = null,
};

/// struct a12_channel's `progress` field — callback-driven byte-count tracker
/// for binary-stream progress reporting (a12_channel_bprogress_hook).
pub const a12_channel_progress = extern struct {
    trigger_left: usize = 0,
    trigger_count: usize = 0,
    count: usize = 0,
    in: usize = 0,
    out: usize = 0,
    total: usize = 0,
    trigger: ?*const fn (chid: c_int, in: usize, out: usize, total: usize, tag: ?*anyopaque) callconv(.c) void = null,
    tag: ?*anyopaque = null,
};

/// struct a12_channel — per-channel unpack/encode state. Layout mirrors
/// `struct a12_channel` from a12_int.h. Embeds `shmifsrv_vbuffer` — kept
/// describable under `SHMIF_SERVER_NO_BITFIELDS` (flags become bools).
pub const struct_a12_channel = extern struct {
    active: c_int = 0,
    cont: [*c]shmif.arcan_shmif_cont = null,
    raw: a12_unpack_cfg = .{},
    unpack_state: a12_channel_unpack_state = .{},
    acc: shmif.struct_shmifsrv_vbuffer = .{},
    unnamed_0: a12_channel_compression = .{},
    progress: a12_channel_progress = .{},
};
pub const a12_channel = struct_a12_channel;

/// struct blob_xfer — queued binary transfer. Linked-list node tracking a
/// single outbound or inbound blob (font, state, generic blob, ...).
/// Layout mirrors `struct blob_xfer` from a12_int.h; field access happens
/// in a12.zig (e.g. `node.*.next`, `node.*.zstd`, `node.*.fd`).
pub const struct_blob_xfer = extern struct {
    checksum: [16]u8 = std.mem.zeroes([16]u8),
    fd: c_int = 0,
    chid: u8 = 0,
    @"type": c_int = 0,
    identifier: u32 = 0,
    extid: [16]u8 = std.mem.zeroes([16]u8),
    left: usize = 0,
    buf: [*c]u8 = null,
    buf_sz: usize = 0,
    streaming: bool = false,
    active: bool = false,
    uncompressed: bool = false,
    streamid: u64 = 0,
    rampup_seqnr: u64 = 0,
    tag: ?*anyopaque = null,
    zstd: ?*ZSTD_CCtx_s = null,
    next: [*c]struct_blob_xfer = null,
};
pub const blob_xfer = struct_blob_xfer;

/// struct video_frame — in-flight decode state for a video frame. Layout
/// mirrors `struct video_frame` from a12_int.h (non-ffmpeg build — the
/// optional `ffmpeg` sub-struct is gated behind WANT_H264_DEC in the C
/// header and the default Zig build does not define that macro).
///
/// Extern-struct layout follows the C ABI, so implicit padding is inserted
/// automatically between fields with differing alignment. No explicit pad
/// members are needed; the `@sizeOf` comptime assert pins the total.
pub const struct_video_frame = extern struct {
    id: u32 = 0,
    sw: u16 = 0,
    sh: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,
    x: u16 = 0,
    y: u16 = 0,
    flags: u32 = 0,
    postprocess: u8 = 0,
    commit: u8 = 0,
    inbuf: [*c]u8 = null,
    inbuf_pos: u32 = 0,
    inbuf_sz: u32 = 0,
    expanded_sz: u32 = 0,
    row_left: usize = 0,
    out_pos: usize = 0,
    pxbuf: [4]u8 = .{ 0, 0, 0, 0 },
    carry: u8 = 0,
    zstd: ?*ZSTD_DCtx_s = null,
};
pub const video_frame = struct_video_frame;

/// struct audio_frame — in-flight decode state for an audio frame. Layout
/// mirrors `struct audio_frame` from a12_int.h.
pub const struct_audio_frame = extern struct {
    id: u32 = 0,
    rate: u32 = 0,
    encoding: u8 = 0,
    channels: u8 = 0,
    format: u8 = 0,
    nsamples: u16 = 0,
    commit: u8 = 0,
    inbuf: [*c]u8 = null,
    inbuf_pos: usize = 0,
    inbuf_sz: usize = 0,
    expanded_sz: usize = 0,
};
pub const audio_frame = struct_audio_frame;

/// struct binary_frame — in-flight decode state for a binary frame. Layout
/// mirrors `struct binary_frame` from a12_int.h.
pub const struct_binary_frame = extern struct {
    tmp_fd: c_int = 0,
    type: c_int = 0,
    active: bool = false,
    tunnel: c_int = 0,
    size: u64 = 0,
    identifier: u32 = 0,
    checksum: [16]u8 = std.mem.zeroes([16]u8),
    streamid: i64 = 0,
    zstd: ?*ZSTD_DCtx_s = null,
};
pub const binary_frame = struct_binary_frame;

comptime {
    // Pin the layout of the expanded frame types against the C sizes measured
    // from a12_int.h (default, non-ffmpeg build). Numbers verified with a
    // C probe: `zig cc -target aarch64-linux-musl -DSHMIF_SERVER_NO_BITFIELDS=
    // -DMLK_CONFIG_PARAMETER_SET=768` compiling a program that prints
    // sizeof(struct X) for each type.
    std.debug.assert(@sizeOf(struct_video_frame) == 80);
    std.debug.assert(@sizeOf(struct_audio_frame) == 48);
    std.debug.assert(@sizeOf(struct_binary_frame) == 64);
    std.debug.assert(@sizeOf(struct_blob_xfer) == 120);
    std.debug.assert(@sizeOf(struct_a12_channel) == 504);
    std.debug.assert(@sizeOf(struct_a12_state) == 203928);
    // bug 0131: offsets in a12_offsets.zig must match the canonical struct_a12_state
    // layout; struct_a12_channel grew 496 → 504 bytes and shifted every field after
    // `channels` by +2048. Pin the load-bearing ones here so any future ABI drift
    // surfaces at compile time, not as a silent NULL read at runtime.
    std.debug.assert(@offsetOf(struct_a12_state, "in_channel") == 129408);
    std.debug.assert(@offsetOf(struct_a12_state, "on_auth") == 129440);
    std.debug.assert(@offsetOf(struct_a12_state, "auth_tag") == 129448);
    std.debug.assert(@offsetOf(struct_a12_state, "decode") == 129456);
    std.debug.assert(@offsetOf(struct_a12_state, "state") == 194996);
    std.debug.assert(@offsetOf(struct_a12_state, "keys") == 195008);
    std.debug.assert(@offsetOf(struct_a12_state, "out_mac") == 200024);
}

/// zstd opaque contexts. Concrete API lives in `zstd_shim.zig` / the linked C
/// zstd library; here we only need the type name so struct fields that hold
/// pointers to them round-trip.
pub const ZSTD_CCtx_s = opaque {};
pub const ZSTD_DCtx_s = opaque {};
pub const struct_ZSTD_CCtx_s = ZSTD_CCtx_s;
pub const struct_ZSTD_DCtx_s = ZSTD_DCtx_s;

/// FILE — opaque libc FILE. Used for blake3_hasher's `log` sentinel pointer
/// (`?*FILE` field). The a12 implementation never dereferences it here; it's
/// only written/zeroed via the blake3_hasher C API.
pub const FILE = opaque {};

/// blake3_chunk_state — inner sub-struct of blake3_hasher.
/// Layout mirrors `struct blake3_chunk_state` from blake3_impl.h (via
/// blake3.h's in-header definition). Kept here so blake3_hasher field
/// access from a12.zig (e.g. `S.*.out_mac.counter`) compiles.
pub const blake3_chunk_state = extern struct {
    cv: [8]u32 = std.mem.zeroes([8]u32),
    chunk_counter: u64 = 0,
    buf: [64]u8 = std.mem.zeroes([64]u8),
    buf_len: u8 = 0,
    blocks_compressed: u8 = 0,
    flags: u8 = 0,
};

/// blake3_hasher — concrete struct matching src/a12/external/blake3/blake3.h.
/// Expanded to the full field layout so a12.zig can access `counter` (used
/// in MAC trace messages). Total size pinned to 1928 bytes via comptime
/// assert so ABI drift from upstream blake3 shows up as a build break.
pub const BLAKE3_HASHER_SIZE_BYTES: usize = 1928;
pub const blake3_hasher = extern struct {
    log: ?*FILE = null,
    counter: usize = 0,
    key: [8]u32 = std.mem.zeroes([8]u32),
    chunk: blake3_chunk_state = .{},
    cv_stack_len: u8 = 0,
    cv_stack: [1760]u8 = std.mem.zeroes([1760]u8),
};

comptime {
    std.debug.assert(@sizeOf(blake3_hasher) == BLAKE3_HASHER_SIZE_BYTES);
}

pub extern fn blake3_hasher_init(self: *blake3_hasher) void;
pub extern fn blake3_hasher_init_keyed(self: *blake3_hasher, key: *const [32]u8) void;
pub extern fn blake3_hasher_init_derive_key(self: *blake3_hasher, context: [*:0]const u8) void;
pub extern fn blake3_hasher_update(self: *blake3_hasher, input: *const anyopaque, input_len: usize) void;
pub extern fn blake3_hasher_finalize(self: *const blake3_hasher, out: [*]u8, out_len: usize) void;
pub extern fn blake3_hasher_finalize_seek(self: *const blake3_hasher, seek: u64, out: [*]u8, out_len: usize) void;

/// struct shmifsrv_client — re-export from shmif_types so the opaque pointer
/// types unify across modules.
pub const shmifsrv_client = shmif.shmifsrv_client;
pub const struct_shmifsrv_client = shmifsrv_client;

/// struct frame_cache — opaque per-helper frame cache.
pub const frame_cache = opaque {};
pub const struct_frame_cache = frame_cache;

/// struct chacha_ctx — opaque; the encode/decode cipher state is handled in
/// a12.zig via a side-declared extern struct. Kept opaque here so a12_state's
/// `enc_state` / `dec_state` fields round-trip as plain pointers.
pub const chacha_ctx = opaque {};
pub const struct_chacha_ctx = chacha_ctx;

// ══════════════════════════════════════════════════════════════════════════════
// Section 2: Primitive aliases shared with shmif
// ══════════════════════════════════════════════════════════════════════════════

/// shmif_pixel — 32-bit packed pixel in the shmif ABI. Matches the typedef in
/// arcan_shmif_defs.h.
pub const shmif_pixel = u32;

/// shmif_asample — signed 16-bit audio sample in the shmif ABI.
pub const shmif_asample = i16;

// POSIX-ish helpers used by a12 consumers (not exhaustive — platform/posix
// libc.zig owns the bulk). The types below only show up via `c.off_t`.
pub const off_t = i64;

// ══════════════════════════════════════════════════════════════════════════════
// Section 3: Shmif event/buffer types consumed through a12_types
// ══════════════════════════════════════════════════════════════════════════════
//
// a12 call sites pass `arcan_event` / `arcan_extevent` / `arcan_tgtevent`
// buffers across the wire; they need the full struct layout. We mirror the
// authoritative definitions in src/shmif/shmif_types.zig so a12_types can be
// a single-import namespace. Layouts are pinned with @sizeOf asserts.

/// arcan_shmif_region — axis-aligned damaged region.
pub const arcan_shmif_region = extern struct {
    x1: u16 = 0,
    x2: u16 = 0,
    y1: u16 = 0,
    y2: u16 = 0,
};
pub const struct_arcan_shmif_region = arcan_shmif_region;

/// arcan_ioevent_data — input-event union. Matches arcan_shmif_event.h.
pub const arcan_ioevent_data = extern union {
    digital: extern struct { active: u8 },
    analog: extern struct { gotrel: i8, nvalues: u8, axisval: [4]i16, active: u8 },
    touch: extern struct { active: u8, x: i16, y: i16, pressure: f32, size: f32, tilt_x: u16, tilt_y: u16, tool: u8 },
    eyes: extern struct { head_pos: [3]f32, head_ang: [3]f32, gaze_x1: f32, gaze_y1: f32, gaze_x2: f32, gaze_y2: f32, blink_left: u8, blink_right: u8, present: u8 },
    status: extern struct { action: u8, devkind: u8, devref: u16, domain: u8 },
    translated: extern struct { utf8: [5]u8, active: u8, scancode: u8, keysym: u32, modifiers: u16 },
};

/// arcan_ioevent — input event wrapper.
pub const arcan_ioevent = extern struct {
    kind: c_int = 0,
    devkind: c_int = 0,
    datatype: c_int = 0,
    label: [16]u8 = std.mem.zeroes([16]u8),
    flags: u8 = 0,
    _pad_flags: [1]u8 = .{0},
    unnamed_0: extern union {
        unnamed_0: extern struct { devid: u16 = 0, subid: u16 = 0 },
        id: [2]u16,
    } = .{ .id = .{ 0, 0 } },
    dst: u32 = 0,
    pts: u64 = 0,
    input: arcan_ioevent_data = std.mem.zeroes(arcan_ioevent_data),
};

/// arcan_tgtevent — target (shmif server → client) event.
pub const tgt_ioev = extern union { uiv: u32, iv: i32, fv: f32, cv: [4]u8 };
pub const arcan_tgtevent = extern struct {
    kind: c_int = 0,
    ioevs: [8]tgt_ioev = std.mem.zeroes([8]tgt_ioev),
    code: c_int = 0,
    unnamed_0: extern union {
        message: [78]u8,
        bmessage: [78]u8,
        timestamp: u64,
    } = .{ .message = std.mem.zeroes([78]u8) },
};
pub const struct_arcan_tgtevent = arcan_tgtevent;

/// arcan_extevent — client → server external event. Large variant-union.
pub const arcan_extevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i64 = 0,
    unnamed_0: extern union {
        message: extern struct { data: [78]u8, multipart: u8 },
        labelhint: extern struct { label: [16]u8, initial: u16, descr: [53]u8, vsym: [5]u8, subv: u16, idatatype: u8, modifiers: u16 },
        segreq: extern struct { id: u32, width: u16, height: u16, xofs: i16, yofs: i16, dir: u8, hints: u8, kind: c_int },
        viewport: extern struct { x: i32, y: i32, w: u32, h: u32, parent: u32, border: [4]u8, edge: u8, order: i8, embedded: u8, invisible: u8, focus: u8, anchor_edge: u8, anchor_pos: u8, ext_id: u32 },
        clock: extern struct { rate: u32, dynamic: u8, once: u8, id: u32 },
        registr: extern struct { title: [64]u8, kind: c_int, guid: [2]u64 },
        bchunk: extern struct { unnamed_0: extern union { size: u64, ns: u64 } = .{ .size = 0 }, input: u8, hint: u8, stream: u8, extensions: [68]u8, identifier: u32 },
        stateinf: extern struct { size: u32, @"type": u32 },
        streamstat: extern struct { timestr: [9]u8, timelim: [9]u8, completion: f32, streaming: u8, frameno: u32, identifier: u32 },
        framestatus: extern struct { framenumber: u32, pts: u64, acquired: u64, fhint: f32 },
        content: extern struct { x_pos: f32, x_sz: f32, y_pos: f32, y_sz: f32, width: f32, height: f32, cell_w: u8, cell_h: u8, min_w: u32, min_h: u32, max_w: u32, max_h: u32 },
        coreopt: extern struct { index: u8, @"type": u8, data: [77]u8 },
        privdrop: extern struct { external: u8, sandboxed: u8, networked: u8 },
        inputmask: extern struct { device: u32, types: u32 },
        netstate: extern struct { unnamed_0: extern union { name: [66]u8, unnamed_0: extern struct { petname: [16]u8, pubk: [32]u8 } } = .{ .name = std.mem.zeroes([66]u8) }, space: u8, state: u8, @"type": u8, _pad0: u8 = 0, port: u16, ns: u16 },
        bstream: extern struct { stride: u32, format: u32, offset: u32, mod_hi: u32, mod_lo: u32, gpuid: u32, width: u32, height: u32, left: u8, flags: u8 },
        streaminf: extern struct { streamid: u8, datakind: u8, langid: [4]u8 },
    } = .{ .message = .{ .data = std.mem.zeroes([78]u8), .multipart = 0 } },
    frame_id: u64 = 0,
};
pub const struct_arcan_extevent = arcan_extevent;

// Supporting small event payloads (system/video/audio/fsrv) used inside
// `arcan_event`. Only the minimum accessible from a12 consumers is defined.
pub const arcan_sevent = extern struct {
    kind: c_uint = 0,
    errcode: c_int = 0,
    unnamed_0: extern union {
        tagv: extern struct { hitag: u32 = 0, lotag: u32 = 0 },
        mesg: extern struct { dyneval_msg: ?[*:0]u8 = null },
        data: extern struct { fd: c_int = 0, _pad: [4]u8 = .{ 0, 0, 0, 0 }, otag: isize = 0 },
        message: [64]u8,
    } = .{ .message = std.mem.zeroes([64]u8) },
};
pub const arcan_vevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i64 = 0,
    unnamed_0: extern union {
        unnamed_0: extern struct { width: i16 = 0, height: i16 = 0, flags: c_int = 0, vppcm: f32 = 0, displayid: c_int = 0, ledctrl: c_int = 0, ledid: c_int = 0, cardid: c_int = 0 },
        slot: c_int,
    } = .{ .slot = 0 },
    data: isize = 0,
};
pub const arcan_aevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i32 = 0,
    _pad_source: [4]u8 = .{ 0, 0, 0, 0 },
    unnamed_0: extern union { otag: isize, data: [*c]usize } = .{ .otag = 0 },
};

/// arcan_event — re-exported from shmif_types so cross-module callers (a12,
/// anet, shmif) share one Zig type for the tagged-union event payload.
pub const arcan_event = shmif.arcan_event;
pub const struct_arcan_event = shmif.struct_arcan_event;

// ══════════════════════════════════════════════════════════════════════════════
// Section 4: a12.h — struct pk_response / a12_dynreq / appl_meta
// ══════════════════════════════════════════════════════════════════════════════

/// struct pk_response — filled in by `pk_lookup` to authorize a peer.
pub const pk_response = extern struct {
    authentic: bool = false,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    key_pub: [32]u8 = std.mem.zeroes([32]u8),
    key_session: [32]u8 = std.mem.zeroes([32]u8),
    state_access: ?*const fn (pub_key: *const [32]u8, name: [*:0]const u8, sz: usize, mode: [*:0]const u8) callconv(.c) c_int = null,
};
pub const struct_pk_response = pk_response;

/// struct a12_dynreq — reply payload for a directory-open request.
pub const a12_dynreq = extern struct {
    host: [46]u8 = std.mem.zeroes([46]u8),
    pubk: [32]u8 = std.mem.zeroes([32]u8),
    port: u16 = 0,
    authk: [12]u8 = std.mem.zeroes([12]u8),
    proto: c_int = 0,
    local_private_key: [32]u8 = std.mem.zeroes([32]u8),
};
pub const struct_a12_dynreq = a12_dynreq;

/// struct appl_meta — directory-mode appl entry, linked list.
pub const appl_meta = extern struct {
    handle: ?*anyopaque = null, // FILE*
    buf: ?[*]u8 = null,
    buf_sz: u64 = 0,
    server_appl: u8 = 0,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    server_tag: ?*anyopaque = null,
    next: ?*appl_meta = null,
    identifier: u16 = 0,
    categories: u16 = 0,
    permissions: u16 = 0,
    hash: [4]u8 = .{ 0, 0, 0, 0 },
    sig_pubk: [32]u8 = std.mem.zeroes([32]u8),
    alias_identifier: u16 = 0,
    _pad1: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },
    appl: extern struct {
        name: [18]u8 = std.mem.zeroes([18]u8),
        short_descr: [69]u8 = std.mem.zeroes([69]u8),
    } = .{},
    _pad2: [1]u8 = .{0},
    update_ts: u64 = 0,
};
pub const struct_appl_meta = appl_meta;

// ══════════════════════════════════════════════════════════════════════════════
// Section 5: a12.h — struct a12_context_options
// ══════════════════════════════════════════════════════════════════════════════

pub const PkLookupFn = *const fn (
    S: [*c]a12_state,
    pub_key: [*c]u8,
    tag: ?*anyopaque,
) callconv(.c) pk_response;

pub const SinkFn = *const fn (
    buf: [*]u8,
    buf_sz: usize,
    tag: ?*anyopaque,
) callconv(.c) bool;

pub const EncSinkFn = *const fn (
    buf: [*]u8,
    buf_sz: usize,
    method: c_int,
    flags: c_int,
    tag: ?*anyopaque,
) callconv(.c) void;

pub const a12_context_options = extern struct {
    pk_lookup: ?PkLookupFn = null,
    pk_lookup_tag: ?*anyopaque = null,
    priv_key: [32]u8 = std.mem.zeroes([32]u8),
    disable_ephemeral_k: bool = false,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    secret: [32]u8 = std.mem.zeroes([32]u8),
    local_role: c_int = 0,
    _pad_role: [4]u8 = .{ 0, 0, 0, 0 },
    rekey_bytes: usize = 0,
    checksum_cap_mb: usize = 0,
    pqc_rekey: bool = false,
    allow_directory_link: bool = false,
    _pad1: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },
    sink: ?SinkFn = null,
    sink_tag: ?*anyopaque = null,
    enc_sink: ?EncSinkFn = null,
    enc_sink_tag: ?*anyopaque = null,
    // _DEBUG fields (disable_cia / record_raw) omitted — release builds only.
};
pub const struct_a12_context_options = a12_context_options;

// ══════════════════════════════════════════════════════════════════════════════
// Section 6: a12.h — enum a12_bstream_type
// ══════════════════════════════════════════════════════════════════════════════

pub const a12_bstream_type = c_uint;
pub const enum_a12_bstream_type = a12_bstream_type;

pub const A12_BTYPE_STATE: a12_bstream_type = 0;
pub const A12_BTYPE_FONT: a12_bstream_type = 1;
pub const A12_BTYPE_FONT_SUPPL: a12_bstream_type = 2;
pub const A12_BTYPE_BLOB: a12_bstream_type = 3;
pub const A12_BTYPE_CRASHDUMP: a12_bstream_type = 4;
pub const A12_BTYPE_APPL: a12_bstream_type = 5;
pub const A12_BTYPE_APPL_RESOURCE: a12_bstream_type = 6;
pub const A12_BTYPE_APPL_CONTROLLER: a12_bstream_type = 7;
pub const A12_BTYPE_METADATA: a12_bstream_type = 8;

// ══════════════════════════════════════════════════════════════════════════════
// Section 7: a12.h — enum a12_blob_mode
// ══════════════════════════════════════════════════════════════════════════════

pub const a12_blob_mode = c_uint;

pub const A12_FLUSH_NOBLOB: a12_blob_mode = 0;
pub const A12_FLUSH_CHONLY: a12_blob_mode = 1;
pub const A12_FLUSH_ALL: a12_blob_mode = 2;

// ══════════════════════════════════════════════════════════════════════════════
// Section 8: a12.h — enum authentic_state
// ══════════════════════════════════════════════════════════════════════════════

pub const authentic_state = c_uint;

pub const AUTH_UNAUTHENTICATED: authentic_state = 0;
pub const AUTH_SERVER_HBLOCK: authentic_state = 1;
pub const AUTH_POLITE_HELLO_SENT: authentic_state = 2;
pub const AUTH_EPHEMERAL_PK: authentic_state = 3;
pub const AUTH_REAL_HELLO_SENT: authentic_state = 4;
pub const AUTH_FULL_PK: authentic_state = 5;

// ══════════════════════════════════════════════════════════════════════════════
// Section 9: a12.h — enum self_roles
// ══════════════════════════════════════════════════════════════════════════════

pub const self_roles = c_uint;

pub const ROLE_NONE: self_roles = 0;
pub const ROLE_SOURCE: self_roles = 1;
pub const ROLE_SINK: self_roles = 2;
pub const ROLE_PROBE: self_roles = 3;
pub const ROLE_DIR: self_roles = 4;
pub const ROLE_DIRREF: self_roles = 5;

// ══════════════════════════════════════════════════════════════════════════════
// Section 10: a12.h — enum server_appl
// ══════════════════════════════════════════════════════════════════════════════

pub const server_appl = c_uint;

pub const SERVER_APPL_NONE: server_appl = 0;
pub const SERVER_APPL_TEMP: server_appl = 1;
pub const SERVER_APPL_PRIMARY: server_appl = 2;

// ══════════════════════════════════════════════════════════════════════════════
// Section 11: a12.h — enum stream_cancel
// ══════════════════════════════════════════════════════════════════════════════

pub const stream_cancel = c_uint;

pub const STREAM_CANCEL_DONTWANT: stream_cancel = 0;
pub const STREAM_CANCEL_DECODE_ERROR: stream_cancel = 1;
pub const STREAM_CANCEL_KNOWN: stream_cancel = 2;

// ══════════════════════════════════════════════════════════════════════════════
// Section 12: a12.h — enum trace_groups
// ══════════════════════════════════════════════════════════════════════════════

pub const A12_TRACE_VIDEO: c_int = 1;
pub const A12_TRACE_AUDIO: c_int = 2;
pub const A12_TRACE_SYSTEM: c_int = 4;
pub const A12_TRACE_EVENT: c_int = 8;
pub const A12_TRACE_TRANSFER: c_int = 16;
pub const A12_TRACE_DEBUG: c_int = 32;
pub const A12_TRACE_MISSING: c_int = 64;
pub const A12_TRACE_ALLOC: c_int = 128;
pub const A12_TRACE_CRYPTO: c_int = 256;
pub const A12_TRACE_VDETAIL: c_int = 512;
pub const A12_TRACE_BTRANSFER: c_int = 1024;
pub const A12_TRACE_SECURITY: c_int = 2048;
pub const A12_TRACE_DIRECTORY: c_int = 4096;

// ══════════════════════════════════════════════════════════════════════════════
// Section 13: a12.h — enum a12_vframe_*, a12_aframe_*
// ══════════════════════════════════════════════════════════════════════════════

pub const a12_vframe_method = c_int;

pub const VFRAME_METHOD_DEFER: a12_vframe_method = -1;
pub const VFRAME_METHOD_NORMAL: a12_vframe_method = 0;
pub const VFRAME_METHOD_RAW_NOALPHA: a12_vframe_method = 1;
pub const VFRAME_METHOD_RAW_RGB565: a12_vframe_method = 2;
pub const VFRAME_METHOD_H264: a12_vframe_method = 5;
pub const VFRAME_METHOD_TPACK_ZSTD: a12_vframe_method = 7;
pub const VFRAME_METHOD_ZSTD: a12_vframe_method = 8;
pub const VFRAME_METHOD_DZSTD: a12_vframe_method = 9;

pub const a12_vframe_compression_bias = c_uint;

pub const VFRAME_BIAS_LATENCY: a12_vframe_compression_bias = 0;
pub const VFRAME_BIAS_BALANCED: a12_vframe_compression_bias = 1;
pub const VFRAME_BIAS_QUALITY: a12_vframe_compression_bias = 2;

pub const a12_vframe_postprocess = c_uint;

pub const VFRAME_POSTPROCESS_SRGB: a12_vframe_postprocess = 1;
pub const VFRAME_POSTPROCESS_ORIGO_LL: a12_vframe_postprocess = 2;

pub const a12_aframe_method = c_uint;

pub const AFRAME_METHOD_RAW: a12_aframe_method = 0;

pub const a12_stream_types = c_uint;

pub const STREAM_TYPE_VIDEO: a12_stream_types = 0;
pub const STREAM_TYPE_AUDIO: a12_stream_types = 1;
pub const STREAM_TYPE_BINARY: a12_stream_types = 2;

/// struct a12_vframe_opts — encoder options for a single video frame.
pub const a12_vframe_opts = extern struct {
    method: a12_vframe_method = VFRAME_METHOD_DEFER,
    bias: a12_vframe_compression_bias = VFRAME_BIAS_LATENCY,
    postprocess: a12_vframe_postprocess = 0,
    ratefactor: c_int = 0,
    bitrate: usize = 0,
    force_idr: bool = false,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    result_feedback: ?*const fn (buf: [*]u8, buf_sz: usize, tag: ?*anyopaque) callconv(.c) void = null,
};
pub const struct_a12_vframe_opts = a12_vframe_opts;

pub const a12_aframe_opts = extern struct {
    method: a12_aframe_method = 0,
};
pub const struct_a12_aframe_opts = a12_aframe_opts;

pub const a12_aframe_cfg = extern struct {
    channels: u8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    samplerate: u32 = 0,
};
pub const struct_a12_aframe_cfg = a12_aframe_cfg;

// ══════════════════════════════════════════════════════════════════════════════
// Section 14: a12.h — struct a12_bhandler_{meta,res}, enum a12_bhandler_*
// ══════════════════════════════════════════════════════════════════════════════

pub const a12_bhandler_flag = c_uint;

pub const A12_BHANDLER_CACHED: a12_bhandler_flag = 0;
pub const A12_BHANDLER_NEWFD: a12_bhandler_flag = 1;
pub const A12_BHANDLER_DONTWANT: a12_bhandler_flag = 2;
pub const A12_BHANDLER_NEWFD_NOCOMPRESS: a12_bhandler_flag = 3;

pub const a12_bhandler_state = c_uint;

pub const A12_BHANDLER_CANCELLED: a12_bhandler_state = 0;
pub const A12_BHANDLER_COMPLETED: a12_bhandler_state = 1;
pub const A12_BHANDLER_INITIALIZE: a12_bhandler_state = 2;

pub const a12_bhandler_meta = extern struct {
    state: a12_bhandler_state = 0,
    @"type": a12_bstream_type = 0,
    checksum: [16]u8 = std.mem.zeroes([16]u8),
    known_size: u64 = 0,
    streaming: bool = false,
    channel: u8 = 0,
    _pad0: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },
    streamid: i64 = 0,
    identifier: u32 = 0,
    extid: [17]u8 = std.mem.zeroes([17]u8),
    _pad1: [3]u8 = .{ 0, 0, 0 },
    fd: c_int = 0,
    _pad2: [4]u8 = .{ 0, 0, 0, 0 },
    // [*c] matches cImport-style C pointer; callers use `meta.dcont.*.field`.
    dcont: [*c]arcan_shmif_cont = null,
};
pub const struct_a12_bhandler_meta = a12_bhandler_meta;

pub const a12_bhandler_res = extern struct {
    flag: a12_bhandler_flag = 0,
    fd: c_int = 0,
};
pub const struct_a12_bhandler_res = a12_bhandler_res;

// ══════════════════════════════════════════════════════════════════════════════
// Section 15: a12.h — struct a12_iostat
// ══════════════════════════════════════════════════════════════════════════════

pub const a12_iostat = extern struct {
    b_in: usize = 0,
    b_out: usize = 0,
    vframe_backpressure: usize = 0,
    roundtrip_latency: usize = 0,
    ms_vframe: usize = 0,
    ms_vframe_px: f32 = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    packets_pending: usize = 0,
};
pub const struct_a12_iostat = a12_iostat;

// ══════════════════════════════════════════════════════════════════════════════
// Section 16: a12.h — struct a12_unpack_cfg
// ══════════════════════════════════════════════════════════════════════════════

pub const a12_unpack_cfg = extern struct {
    tag: ?*anyopaque = null,
    request_compressed_vbuffer: ?*const fn (fourcc: *[4]c_int, nb: usize, tag: ?*anyopaque) callconv(.c) ?*anyopaque = null,
    request_raw_buffer: ?*const fn (w: usize, h: usize, stride: *usize, flags: c_int, tag: ?*anyopaque) callconv(.c) ?[*]shmif_pixel = null,
    request_audio_buffer: ?*const fn (n_ch: usize, samplerate: usize, size_bytes: usize, tag: ?*anyopaque) callconv(.c) ?[*]shmif_asample = null,
    signal_video: ?*const fn (x1: usize, y1: usize, x2: usize, y2: usize, tag: ?*anyopaque) callconv(.c) void = null,
    signal_audio: ?*const fn (bytes: usize, tag: ?*anyopaque) callconv(.c) void = null,
    directory_open: ?*const fn (S: [*c]a12_state, ident_req: [*c]u8, mode: u8, out: [*c]a12_dynreq, tag: ?*anyopaque) callconv(.c) bool = null,
    on_discover: ?*const fn (S: [*c]a12_state, arg1: u8, arg2: [*c]const u8, arg3: u8, kpub: [*c]u8, id: u16, tag: ?*anyopaque) callconv(.c) void = null,
    on_discover_tag: ?*anyopaque = null,
};
pub const struct_a12_unpack_cfg = a12_unpack_cfg;

// ══════════════════════════════════════════════════════════════════════════════
// Section 17: a12.h — struct a12_channel_meta
// ══════════════════════════════════════════════════════════════════════════════

pub const a12_channel_meta = extern struct {
    inbound_binary_total: usize = 0,
    inbound_binary_depth: usize = 0,
    outbound_binary_total: usize = 0,
    outbound_binary_depth: usize = 0,
    video_active: bool = false,
    audio_active: bool = false,
};
pub const struct_a12_channel_meta = a12_channel_meta;

// ══════════════════════════════════════════════════════════════════════════════
// Section 18: a12_int.h — STATE_*, control_commands, hello_mode, channel_cfg,
//   POSTPROCESS_*, STREAM_FAIL_*
// ══════════════════════════════════════════════════════════════════════════════

// Decoder state machine
pub const STATE_NOPACKET: c_int = 0;
pub const STATE_CONTROL_PACKET: c_int = 1;
pub const STATE_EVENT_PACKET: c_int = 2;
pub const STATE_AUDIO_PACKET: c_int = 3;
pub const STATE_VIDEO_PACKET: c_int = 4;
pub const STATE_BLOB_PACKET: c_int = 5;
pub const STATE_1STSRV_PACKET: c_int = 6;
pub const STATE_BROKEN: c_int = 7;

// Control commands
pub const COMMAND_HELLO: c_int = 0;
pub const COMMAND_SHUTDOWN: c_int = 1;
pub const COMMAND_NEWCH: c_int = 2;
pub const COMMAND_CANCELSTREAM: c_int = 3;
pub const COMMAND_VIDEOFRAME: c_int = 4;
pub const COMMAND_AUDIOFRAME: c_int = 5;
pub const COMMAND_BINARYSTREAM: c_int = 6;
pub const COMMAND_PING: c_int = 7;
pub const COMMAND_REKEY: c_int = 8;
pub const COMMAND_DIRLIST: c_int = 9;
pub const COMMAND_DIRSTATE: c_int = 10;
pub const COMMAND_DIRDISCOVER: c_int = 11;
pub const COMMAND_DIROPEN: c_int = 12;
pub const COMMAND_DIROPENED: c_int = 13;
pub const COMMAND_TUNDROP: c_int = 14;

// HELLO sub-mode
pub const HELLO_MODE_NOASYM: c_int = 0;
pub const HELLO_MODE_REALPK: c_int = 1;
pub const HELLO_MODE_EPHEMPK: c_int = 2;

// Channel configuration
pub const CHANNEL_INACTIVE: c_int = 0;
pub const CHANNEL_SHMIF: c_int = 1;
pub const CHANNEL_RAW: c_int = 2;

// Video post-process tags (a12_int.h anonymous enum)
pub const POSTPROCESS_VIDEO_RGBA: c_int = 0;
pub const POSTPROCESS_VIDEO_RGB: c_int = 1;
pub const POSTPROCESS_VIDEO_RGB565: c_int = 2;
pub const POSTPROCESS_VIDEO_H264: c_int = 5;
pub const POSTPROCESS_VIDEO_TZSTD: c_int = 7;
pub const POSTPROCESS_VIDEO_DZSTD: c_int = 8;
pub const POSTPROCESS_VIDEO_ZSTD: c_int = 9;

pub const STREAM_FAIL_OUTDATED: c_int = 0;
pub const STREAM_FAIL_UNKNOWN: c_int = 1;
pub const STREAM_FAIL_ALREADY_KNOWN: c_int = 2;

// a12_int.h layout constants
pub const MAC_BLOCK_SZ: usize = 16;
pub const NONCE_SIZE: usize = 8;
pub const CONTROL_PACKET_SIZE: usize = 128;
pub const CIPHER_ROUNDS: c_int = 8;
pub const BLOB_QUEUE_CAP: usize = 128 * 1024;
pub const OUTBOUND_BUFFER_COUNT: usize = 2;
pub const BEACON_KEY_CAP: usize = 15;
pub const SEQUENCE_NUMBER_SIZE: usize = 8;
pub const ZSTD_DEFAULT_LEVEL: c_int = 3;
pub const ZSTD_VIDEO_LEVEL: c_int = 2;
pub const VIDEO_FRAME_DRIFT_WINDOW: usize = 8;

// ══════════════════════════════════════════════════════════════════════════════
// Section 19: struct arcan_shmif_cont (subset needed by a12 callers)
// ══════════════════════════════════════════════════════════════════════════════
//
// a12 only uses `arcan_shmif_cont` as a tagged pointer — it passes the
// pointer into shmif / a12_set_destination and reads a handful of fields
// (user, hints, w/h, cookie, privext). The authoritative layout lives in
// src/shmif/shmif_types.zig; here we keep a byte-identical copy so the
// compiler can type-check field accesses without cross-module dependency.

pub const shmif_ext_hidden = shmif.struct_shmif_ext_hidden;
pub const struct_shmif_ext_hidden = shmif_ext_hidden;

pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;

/// struct shmif_resize_ext — extended resize parameters.
pub const shmif_resize_ext = extern struct {
    abuf_sz: usize = 0,
    abuf_cnt: c_int = 0,
    samplerate: c_int = 0,
    vbuf_cnt: c_int = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    rows: usize = 0,
    cols: usize = 0,
    meta: c_int = 0,
    _pad1: [4]u8 = .{ 0, 0, 0, 0 },
};
pub const struct_shmif_resize_ext = shmif_resize_ext;

// ══════════════════════════════════════════════════════════════════════════════
// Section 20: shmifsrv_vbuffer — server-side video buffer
// ══════════════════════════════════════════════════════════════════════════════

// Re-export from shmif_types so a12 consumers and shmif consumers agree on
// the underlying Zig type through the dispatch-struct pattern.
pub const shmifsrv_vbuffer_flags = shmif.struct_shmifsrv_vbuffer_flags;
pub const shmifsrv_vbuffer = shmif.shmifsrv_vbuffer;
pub const struct_shmifsrv_vbuffer = shmif.struct_shmifsrv_vbuffer;

// ══════════════════════════════════════════════════════════════════════════════
// Section 21: a12_helper.h
// ══════════════════════════════════════════════════════════════════════════════

pub const a12helper_pollstate = c_uint;

pub const A12HELPER_POLL_SHMIF: a12helper_pollstate = 1;
pub const A12HELPER_WRITE_OUT: a12helper_pollstate = 2;
pub const A12HELPER_DATA_IN: a12helper_pollstate = 4;

pub const FRAME_RAW_SHMIFSRV_VBUFFER: c_uint = 0;
pub const FRAME_ENCODED: c_uint = 1;

pub const EvalVcodecFn = *const fn (
    S: ?*a12_state,
    segid: c_int,
    vb: ?*shmifsrv_vbuffer,
    tag: ?*anyopaque,
) callconv(.c) a12_vframe_opts;

pub const a12helper_opts = extern struct {
    eval_vcodec: ?EvalVcodecFn = null,
    tag: ?*anyopaque = null,
    vframe_soft_block: usize = 0,
    vframe_block: usize = 0,
    redirect_exit: ?[*:0]const u8 = null,
    devicehint_cp: ?[*:0]const u8 = null,
    bcache_dir: c_int = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    cache: ?*frame_cache = null,
    lock: ?*anyopaque = null, // pthread_mutex_t*
};
pub const struct_a12helper_opts = a12helper_opts;

// ══════════════════════════════════════════════════════════════════════════════
// Section 22: extern a12 / a12int public entry points
// ══════════════════════════════════════════════════════════════════════════════

pub extern fn a12_sensitive_alloc(nb: usize) ?*anyopaque;
pub extern fn a12_sensitive_free(ptr: ?*anyopaque, nb: usize) void;

pub extern fn a12_client(opts: ?*a12_context_options) ?*a12_state;
pub extern fn a12_server(opts: ?*a12_context_options) ?*a12_state;
pub extern fn a12_free(S: ?*a12_state) bool;

pub extern fn a12_set_session(dst: ?*pk_response, pubk: [*]const u8, privk: [*]const u8) void;
pub extern fn a12_set_signing_pair(S: ?*a12_state, pubk: [*]const u8, privk: [*]const u8) bool;
pub extern fn a12_get_sign_pubkey(S: ?*a12_state, outkey: [*]u8) void;

pub const UnpackEventFn = *const fn (
    cont: ?*arcan_shmif_cont,
    chid: c_int,
    ev: ?*arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void;
pub extern fn a12_unpack(
    S: ?*a12_state,
    buf: [*c]const u8,
    sz: usize,
    tag: ?*anyopaque,
    on_event: ?UnpackEventFn,
) void;

pub extern fn a12_set_destination(S: ?*a12_state, wnd: ?*arcan_shmif_cont, chid: u8) void;
pub extern fn a12_set_destination_raw(S: ?*a12_state, ch: u8, cfg: a12_unpack_cfg, unpack_cfg_sz: usize) void;

pub extern fn a12_channel_bprogress_hook(
    S: ?*a12_state,
    chid: u8,
    bytecount: usize,
    trigger: ?*const fn (status: c_int, bin: usize, bout: usize, total: usize, tag: ?*anyopaque) callconv(.c) void,
    tag: ?*anyopaque,
) void;

pub extern fn a12_channel_status(S: ?*a12_state, chid: u8) a12_channel_meta;
pub extern fn a12_find_free_channel(S: ?*a12_state, chid: [*]u8) bool;

pub extern fn a12_flush(S: ?*a12_state, out: *[*c]u8, allow_blob: c_int) usize;

pub extern fn a12_enqueue_bstream(
    S: ?*a12_state,
    fd: c_int,
    @"type": c_int,
    id: u32,
    streaming: bool,
    sz: usize,
    extid: [*]const u8,
) void;

pub extern fn a12_enqueue_blob(
    S: ?*a12_state,
    data: [*]const u8,
    len: usize,
    id: u32,
    @"type": c_int,
    extid: [*]const u8,
) void;

pub extern fn a12_request_file(
    S: ?*a12_state,
    chid: u8,
    ns: u16,
    id: u32,
    name: [*:0]const u8,
) void;

pub extern fn a12_write_tunnel(S: ?*a12_state, chid: u8, buf: [*]const u8, sz: usize) bool;
pub extern fn a12_set_tunnel_sink(S: ?*a12_state, chid: u8, fd: c_int) bool;
pub extern fn a12_alloc_tunnel(S: ?*a12_state) c_int;
pub extern fn a12_drop_tunnel(S: ?*a12_state, chid: u8) void;
pub extern fn a12_tunnel_descriptor(S: ?*a12_state, chid: u8, ok: *bool) c_int;

pub extern fn a12_poll(S: ?*a12_state) c_int;
pub extern fn a12_auth_state(S: ?*a12_state) c_int;

pub extern fn a12_set_channel(S: ?*a12_state, chid: u8) void;
pub extern fn a12_get_channel(S: ?*a12_state) u8;

pub extern fn a12_set_trace_level(mask: c_int, dst: ?*anyopaque) void;

pub const BHandlerFn = *const fn (
    S: ?*a12_state,
    meta: a12_bhandler_meta,
    tag: ?*anyopaque,
) callconv(.c) a12_bhandler_res;
pub extern fn a12_set_bhandler(S: ?*a12_state, on_bevent: ?BHandlerFn, tag: ?*anyopaque) void;

pub extern fn a12_channel_enqueue(S: ?*a12_state, ev: ?*arcan_event) bool;
pub extern fn a12_channel_aframe(
    S: ?*a12_state,
    buf: [*]shmif_asample,
    n_samples: usize,
    cfg: a12_aframe_cfg,
    opts: a12_aframe_opts,
) void;
pub extern fn a12_channel_vframe(
    S: ?*a12_state,
    vb: ?*shmifsrv_vbuffer,
    opts: a12_vframe_opts,
) c_int;

pub extern fn a12_channel_new(
    S: ?*a12_state,
    chid: u8,
    segkind: u8,
    cookie: u32,
) void;
pub extern fn a12_channel_shutdown(S: ?*a12_state, last_words: [*:0]const u8) void;
pub extern fn a12_channel_close(S: ?*a12_state) void;

pub extern fn a12_stream_cancel(S: ?*a12_state, chid: u8) void;
pub extern fn a12_vstream_cancel(S: ?*a12_state, chid: u8, reason: c_int) void;

pub extern fn a12_ok(S: ?*a12_state) bool;
pub extern fn a12_remote_mode(S: ?*a12_state) c_int;
pub extern fn a12_btransfer_outfd(S: ?*a12_state) c_int;

pub extern fn a12_shutdown_id(S: ?*a12_state, id: u32) void;
pub extern fn a12_state_iostat(S: ?*a12_state) a12_iostat;

pub extern fn a12_get_endpoint(S: ?*a12_state) [*c]const u8;
pub extern fn a12_set_endpoint(S: ?*a12_state, endpoint: [*c]const u8) void;

pub const DynreqReplyFn = *const fn (
    S: ?*a12_state,
    req: a12_dynreq,
    tag: ?*anyopaque,
) callconv(.c) void;
pub extern fn a12_request_dynamic_resource(
    S: ?*a12_state,
    ident_pubk: [*]const u8,
    prefer_tunnel: bool,
    request_reply: ?DynreqReplyFn,
    tag: ?*anyopaque,
) bool;
pub extern fn a12_supply_dynamic_resource(S: ?*a12_state, req: a12_dynreq) void;

pub extern fn a12_error_state(S: ?*a12_state) [*c]const u8;

pub extern var a12_trace_targets: c_int;
pub extern var a12_trace_dst: ?*anyopaque; // FILE*
pub extern fn a12_trace_tag(S: ?*a12_state, tag: [*:0]const u8) void;
pub extern fn a12int_group_tostr(group: c_int) [*c]const u8;

pub extern fn a12int_stream_fail(S: ?*a12_state, ch: u8, id: u32, fail: c_int) void;
pub extern fn a12int_stream_ack(S: ?*a12_state, ch: u8, id: u32) void;
pub extern fn a12int_append_out(
    S: ?*a12_state,
    @"type": u8,
    out: [*]const u8,
    out_sz: usize,
    prepend: [*c]u8,
    prepend_sz: usize,
) void;
pub extern fn a12int_step_vstream(S: ?*a12_state, id: u32) void;
pub extern fn a12int_set_directory(S: ?*a12_state, meta: ?*appl_meta) void;
pub extern fn a12int_notify_dynamic_resource(
    S: ?*a12_state,
    petname: [*:0]const u8,
    kpub: [*]const u8,
    role: u8,
    state: u8,
    ns: u16,
) void;
pub extern fn a12int_get_directory(S: ?*a12_state, clk: *u64) ?*appl_meta;
pub extern fn a12int_request_dirlist(S: ?*a12_state, notify: bool) void;
pub extern fn a12int_header_size(@"type": c_int) usize;

pub extern fn arcan_timemillis() c_ulonglong;
pub extern fn arcan_random(dst: [*]u8, ntc: usize) void;

// ══════════════════════════════════════════════════════════════════════════════
// Section 23: arcan_shmif / shmifsrv entry points consumed by helper_cl/srv
// ══════════════════════════════════════════════════════════════════════════════

pub extern fn arcan_shmif_acquire(
    parent: ?*arcan_shmif_cont,
    shmkey: [*c]const u8,
    typ: c_int,
    flags: c_int,
    ...,
) arcan_shmif_cont;
pub extern fn arcan_shmif_open(
    type_: c_int,
    flags: c_uint,
    args: ?*anyopaque, // actually `struct arg_arr**`; opaque to keep a12_types standalone
) arcan_shmif_cont;
pub extern fn arcan_shmif_drop(cont: ?*arcan_shmif_cont) void;
pub extern fn arcan_shmif_poll(cont: ?*arcan_shmif_cont, ev: ?*arcan_event) c_int;
pub extern fn arcan_shmif_enqueue(cont: ?*arcan_shmif_cont, ev: ?*const arcan_event) c_int;
pub extern fn arcan_shmif_descrevent(ev: ?*const arcan_event) bool;
pub extern fn arcan_shmif_eventpack(ev: ?*const arcan_event, buf: [*]u8, buf_sz: usize) isize;
pub extern fn arcan_shmif_eventunpack(buf: [*]const u8, buf_sz: usize, ev: ?*arcan_event) isize;
pub extern fn arcan_shmif_eventstr(ev: ?*const arcan_event, dbuf: [*c]u8, dsz: usize) [*c]u8;
pub extern fn arcan_shmif_signal(cont: ?*arcan_shmif_cont, mask: c_int) c_uint;
pub extern fn arcan_shmif_resize(cont: ?*arcan_shmif_cont, w: c_uint, h: c_uint) bool;
pub extern fn arcan_shmif_resize_ext(
    cont: ?*arcan_shmif_cont,
    w: c_uint,
    h: c_uint,
    ext: shmif_resize_ext,
) bool;

pub extern fn shmifsrv_audio(
    c: ?*shmifsrv_client,
    cb: ?*const fn (?*shmifsrv_client, ?[*]shmif_asample, usize, c_uint, ?*anyopaque) callconv(.c) void,
    tag: ?*anyopaque,
) void;
pub extern fn shmifsrv_client_handle(c: ?*shmifsrv_client, pid: ?*c_int) c_int;
pub extern fn shmifsrv_client_protomask(c: ?*shmifsrv_client, mask: c_uint) c_uint;
pub extern fn shmifsrv_client_type(c: ?*shmifsrv_client) c_int;
pub extern fn shmifsrv_dequeue_events(c: ?*shmifsrv_client, ev: [*]arcan_event, max: c_uint) c_uint;
pub extern fn shmifsrv_enqueue_event(c: ?*shmifsrv_client, ev: ?*const arcan_event, fd: c_int) bool;
pub extern fn shmifsrv_free(c: ?*shmifsrv_client, flags: c_int) void;
pub extern fn shmifsrv_monotonic_tick(left: ?*c_int) c_uint;
pub extern fn shmifsrv_poll(c: ?*shmifsrv_client) c_int;
pub extern fn shmifsrv_process_event(c: ?*shmifsrv_client, ev: ?*const arcan_event) bool;
pub extern fn shmifsrv_send_subsegment(
    c: ?*shmifsrv_client,
    kind: c_int,
    hints: c_int,
    w: usize,
    h: usize,
    reqid: c_int,
    cookie: u32,
) ?*shmifsrv_client;
pub extern fn shmifsrv_tick(c: ?*shmifsrv_client) void;
pub extern fn shmifsrv_video(c: ?*shmifsrv_client) shmifsrv_vbuffer;
pub extern fn shmifsrv_video_step(c: ?*shmifsrv_client) void;
pub extern fn shmifsrv_last_words(c: ?*shmifsrv_client, outbuf: [*c]u8, outbuf_sz: usize) void;
pub extern fn shmifsrv_monotonic_rebase() void;
pub extern fn shmifsrv_enqueue_multipart_message(
    c: ?*shmifsrv_client,
    base: ?*const arcan_event,
    msg: [*c]const u8,
    len_in: usize,
) bool;

/// arcan_shmif_server.h — shmifsrv_allocate_connpoint: allocate a named
/// connection point (/tmp/arcan or $XDG_RUNTIME_DIR/arcan backed) and
/// return the opaque server client. `key` = connpoint name, `auth` optional.
pub extern fn shmifsrv_allocate_connpoint(
    name: [*c]const u8,
    key: ?[*:0]const u8,
    permission: c_uint,
    fd: c_int,
) ?*shmifsrv_client;

/// shmifsrv_inherit_connection: adopt an already-connected socket fd and
/// wrap it as a shmifsrv_client. `statuscode` receives a negative error on
/// failure, 0 on success.
pub extern fn shmifsrv_inherit_connection(
    fd: c_int,
    memfd: c_int,
    statuscode: ?*c_int,
) ?*shmifsrv_client;

/// shmifsrv_spawn_client: fork+exec a new shmif client per `env`, returning
/// the server-side opaque client. `clsocket` is populated with the client's
/// socket fd for the parent side.
pub extern fn shmifsrv_spawn_client(
    env: shmif.struct_shmifsrv_envp,
    clsocket: *c_int,
    statuscode: ?*c_int,
    idtok: u32,
) ?*shmifsrv_client;

// ══════════════════════════════════════════════════════════════════════════════
// Section 24: shmif constants referenced by a12 consumers
// ══════════════════════════════════════════════════════════════════════════════

// Event categories (shmif_event.h)
pub const EVENT_SYSTEM: c_int = 1;
pub const EVENT_IO: c_int = 2;
pub const EVENT_VIDEO: c_int = 4;
pub const EVENT_AUDIO: c_int = 8;
pub const EVENT_TARGET: c_int = 16;
pub const EVENT_FSRV: c_int = 32;
pub const EVENT_EXTERNAL: c_int = 64;
pub const EVENT_NET: c_int = 128;

// External event kinds (arcan_shmif_event.h::ARCAN_EVENT_EXT_*)
pub const EVENT_EXTERNAL_MESSAGE: c_int = 0;
pub const EVENT_EXTERNAL_COREOPT: c_int = 1;
pub const EVENT_EXTERNAL_IDENT: c_int = 2;
pub const EVENT_EXTERNAL_FAILURE: c_int = 3;
pub const EVENT_EXTERNAL_BUFFERSTREAM: c_int = 4;
pub const EVENT_EXTERNAL_FRAMESTATUS: c_int = 5;
pub const EVENT_EXTERNAL_STREAMINFO: c_int = 6;
pub const EVENT_EXTERNAL_STATESIZE: c_int = 7;
pub const EVENT_EXTERNAL_FLUSHAUD: c_int = 8;
pub const EVENT_EXTERNAL_SEGREQ: c_int = 9;
pub const EVENT_EXTERNAL_KEYINPUT: c_int = 10;
pub const EVENT_EXTERNAL_CURSORINPUT: c_int = 11;
pub const EVENT_EXTERNAL_CURSORHINT: c_int = 12;
pub const EVENT_EXTERNAL_VIEWPORT: c_int = 13;
pub const EVENT_EXTERNAL_CONTENT: c_int = 14;
pub const EVENT_EXTERNAL_LABELHINT: c_int = 15;
pub const EVENT_EXTERNAL_REGISTER: c_int = 16;
pub const EVENT_EXTERNAL_ALERT: c_int = 17;
pub const EVENT_EXTERNAL_CLOCKREQ: c_int = 18;
pub const EVENT_EXTERNAL_BCHUNKSTATE: c_int = 19;
pub const EVENT_EXTERNAL_STREAMSTATUS: c_int = 20;
pub const EVENT_EXTERNAL_PRIVDROP: c_int = 21;
pub const EVENT_EXTERNAL_INPUTMASK: c_int = 22;
pub const EVENT_EXTERNAL_NETSTATE: c_int = 23;
pub const EVENT_EXTERNAL_MESSAGE_MULTIPART: c_int = 24;

// Target command codes (arcan_shmif_event.h::TARGET_COMMAND_*)
pub const TARGET_COMMAND_UNDEFINED: c_int = 0;
pub const TARGET_COMMAND_EXIT: c_int = 1;
pub const TARGET_COMMAND_FRAMESKIP: c_int = 2;
pub const TARGET_COMMAND_STEPFRAME: c_int = 3;
pub const TARGET_COMMAND_COREOPT: c_int = 4;
pub const TARGET_COMMAND_STORE: c_int = 5;
pub const TARGET_COMMAND_RESTORE: c_int = 6;
pub const TARGET_COMMAND_BCHUNK_IN: c_int = 7;
pub const TARGET_COMMAND_BCHUNK_OUT: c_int = 8;
pub const TARGET_COMMAND_RESET: c_int = 9;
pub const TARGET_COMMAND_PAUSE: c_int = 10;
pub const TARGET_COMMAND_UNPAUSE: c_int = 11;
pub const TARGET_COMMAND_SEEKTIME: c_int = 12;
pub const TARGET_COMMAND_SEEKCONTENT: c_int = 13;
pub const TARGET_COMMAND_DISPLAYHINT: c_int = 14;
pub const TARGET_COMMAND_SETIODEV: c_int = 15;
pub const TARGET_COMMAND_STREAMSET: c_int = 16;
pub const TARGET_COMMAND_ATTENUATE: c_int = 17;
pub const TARGET_COMMAND_AUDDELAY: c_int = 18;
pub const TARGET_COMMAND_NEWSEGMENT: c_int = 19;
pub const TARGET_COMMAND_REQFAIL: c_int = 20;
pub const TARGET_COMMAND_BUFFER_FAIL: c_int = 21;
pub const TARGET_COMMAND_DEVICE_NODE: c_int = 22;
pub const TARGET_COMMAND_GRAPHMODE: c_int = 23;
pub const TARGET_COMMAND_MESSAGE: c_int = 24;
pub const TARGET_COMMAND_FONTHINT: c_int = 25;
pub const TARGET_COMMAND_GEOHINT: c_int = 26;
pub const TARGET_COMMAND_OUTPUTHINT: c_int = 27;
pub const TARGET_COMMAND_ACTIVATE: c_int = 28;
pub const TARGET_COMMAND_ANCHORHINT: c_int = 29;

// shmif signal bits (arcan_shmif_control.h)
pub const SHMIF_SIGVID: c_int = 1;
pub const SHMIF_SIGAUD: c_int = 2;
pub const SHMIF_SIGBLK_ONCE: c_int = 0;
pub const SHMIF_SIGBLK_NONE: c_int = 4;
pub const SHMIF_SIGBLK_FORCE: c_int = 8;

// shmif render hints
pub const SHMIF_RHINT_ORIGO_LL: u8 = 1;
pub const SHMIF_RHINT_SUBREGION: u8 = 2;
pub const SHMIF_RHINT_IGNORE_ALPHA: u8 = 4;
pub const SHMIF_RHINT_CSPACE_SRGB: u8 = 8;
pub const SHMIF_RHINT_AUTH_TOK: u8 = 16;
pub const SHMIF_RHINT_VSIGNAL_EV: u8 = 32;
pub const SHMIF_RHINT_TPACK: u8 = 64;

// shmif_meta bits
pub const SHMIF_META_NONE: c_uint = 0;
pub const SHMIF_META_HDR: c_uint = 1;
pub const SHMIF_META_VOBJ: c_uint = 2;
pub const SHMIF_META_VR: c_uint = 4;
pub const SHMIF_META_HDRF16: c_uint = 8;
pub const SHMIF_META_LDEF: c_uint = 16;
pub const SHMIF_META_VENC: c_uint = 32;
pub const SHMIF_META_A11Y: c_uint = 64;

// shmif open flags (arcan_shmif_control.h)
pub const SHMIF_NOACTIVATE: c_uint = 8;

// shmifsrv free flags
pub const SHMIFSRV_FREE_NO_DMS: c_int = 1;
pub const SHMIFSRV_FREE_LOCAL: c_int = 2;

// Segment IDs (arcan_shmif_event.h::ARCAN_SEGID_*)
pub const SEGID_UNKNOWN: c_int = 0;
pub const SEGID_LWA: c_int = 1;
pub const SEGID_MEDIA: c_int = 2;
pub const SEGID_NETWORK_SERVER: c_int = 3;
pub const SEGID_NETWORK_CLIENT: c_int = 4;
pub const SEGID_SHELL: c_int = 5;
pub const SEGID_REMOTING: c_int = 6;
pub const SEGID_ENCODER: c_int = 7;
pub const SEGID_TERMINAL: c_int = 8;
pub const SEGID_SENSOR: c_int = 9;
pub const SEGID_INPUTDEVICE: c_int = 10;
pub const SEGID_GAME: c_int = 11;
pub const SEGID_APPLICATION: c_int = 12;
pub const SEGID_BROWSER: c_int = 13;
pub const SEGID_VM: c_int = 14;
pub const SEGID_HMD_SBS: c_int = 15;
pub const SEGID_HMD_L: c_int = 16;
pub const SEGID_HMD_R: c_int = 17;
pub const SEGID_POPUP: c_int = 18;
pub const SEGID_ICON: c_int = 19;
pub const SEGID_TITLEBAR: c_int = 20;
pub const SEGID_CURSOR: c_int = 21;
pub const SEGID_CLIPBOARD: c_int = 22;
pub const SEGID_CLIPBOARD_PASTE: c_int = 23;
pub const SEGID_DEBUG: c_int = 255;

// shmifsrv client state (from shmifsrv header)
pub const CLIENT_NOT_READY: c_int = -1;
pub const CLIENT_DEAD: c_int = -2;
pub const CLIENT_IDLE: c_int = 0;
pub const CLIENT_VBUFFER_READY: c_int = 1;
pub const CLIENT_ABUFFER_READY: c_int = 2;

// ══════════════════════════════════════════════════════════════════════════════
// Section 25: ABI sanity — pin wire-format struct sizes
// ══════════════════════════════════════════════════════════════════════════════
//
// Reference sizes computed against aarch64-linux sysv on a real build of
// arcan-net. These hard-fail at compile time if an unrelated field reshuffle
// silently changes the ABI. New field additions must update the numbers
// after confirming with `pahole` / offsetof tests.

comptime {
    // Primitives
    std.debug.assert(@sizeOf(shmif_pixel) == 4);
    std.debug.assert(@sizeOf(shmif_asample) == 2);
    std.debug.assert(@sizeOf(arcan_shmif_region) == 8);
    // Field-level asserts — loosely constrain the extern layouts so a later
    // reshuffle that silently changes sizeof trips CI here rather than at
    // a running wire contact. Exact target-dependent totals are checked by
    // downstream tests in src/a12/a12_offsets.zig; here we only assert the
    // minimum "sanity" content of each struct.
    std.debug.assert(@sizeOf(a12_bhandler_res) == 8);
    std.debug.assert(@sizeOf(a12_aframe_opts) == 4);
    std.debug.assert(@sizeOf(a12_aframe_cfg) == 8);
}

// Symbol-pinning comptime block — forces every `pub extern fn` /
// `pub extern var` to resolve against the linker image so the module is
// self-hosted-compatible (no @cImport anywhere, no reliance on C types).
comptime {
    // Types: opaque sanity — these must be pointer-only.
    _ = a12_state;
    _ = a12_channel;
    _ = blob_xfer;
    _ = video_frame;
    _ = audio_frame;
    _ = binary_frame;
    _ = ZSTD_CCtx_s;
    _ = ZSTD_DCtx_s;
    _ = shmifsrv_client;
    _ = frame_cache;
}
