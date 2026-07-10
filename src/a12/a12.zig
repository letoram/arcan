// Zig port of a12/a12.c — A12 protocol state machine, main translation unit.
// Maintains connection state, multiplex and demultiplex then routes
// to the corresponding decoding/encode stages.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `const c = @cImport({...})` block
// (arcan_shmif.h / a12.h / a12_int.h). External symbols (shmif helpers,
// libc, crypto, anet, a12 public API) route through the hand-written
// replacement modules below. No cImport in this translation unit.
//
// a12.zig performs extensive field-level access into `struct a12_state`,
// `struct a12_channel`, `struct arcan_event` etc. a12_types.zig and
// shmif_types.zig now carry the full extern-struct layouts for those, so the
// same `c.struct_X.field` / `S.*.keys.real_priv` / `ev.unnamed_0.unnamed_0.*`
// access patterns compile against pure-Zig declarations with no cImport.
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const libc = @import("posix");

const c = struct {
    // ── libc (posix + stdio) ────────────────────────────────────────────────
    pub const __assert_fail = libc.__assert_fail;
    pub const close = libc.close;
    pub const EAGAIN = libc.EAGAIN;
    pub const EINTR = libc.EINTR;
    pub const EOVERFLOW = libc.EOVERFLOW;
    pub const ESPIPE = libc.ESPIPE;
    // EWOULDBLOCK is the same as EAGAIN on Linux; keep the synonym available.
    pub const EWOULDBLOCK = libc.EAGAIN;
    pub const FILE = libc.FILE;
    pub const fprintf = libc.fprintf;
    pub const free = libc.free;
    pub const lseek = libc.lseek;
    pub const malloc = libc.malloc;
    pub const memcmp = libc.memcmp;
    pub const memcpy = libc.memcpy;
    pub const memmove = shmif.memmove;
    pub const memset = libc.memset;
    pub const read = libc.read;
    pub const realloc = shmif.realloc;
    pub const SEEK_END = libc.SEEK_END;
    pub const SEEK_SET = libc.SEEK_SET;
    pub const snprintf = libc.snprintf;
    pub const sprintf = libc.sprintf;
    pub const strdup = libc.strdup;
    pub const strlen = libc.strlen;
    pub const write = libc.write;
    pub const off_t = libc.off_t;

    // ── shmif (arcan_shmif.h constants + event helpers) ─────────────────────
    // Extern fn decls re-declared locally with the shmif_types struct types so
    // call sites don't need casts at each shmif event-helper invocation.
    pub extern fn arcan_shmif_descrevent(ev: [*c]const shmif.struct_arcan_event) bool;
    pub extern fn arcan_shmif_eventpack(ev: [*c]const shmif.struct_arcan_event, buf: [*c]u8, buf_sz: usize) isize;
    pub extern fn arcan_shmif_eventunpack(buf: [*c]const u8, buf_sz: usize, ev: [*c]shmif.struct_arcan_event) isize;
    pub extern fn arcan_shmif_eventstr(ev: [*c]const shmif.struct_arcan_event, dbuf: [*c]u8, dsz: usize) [*c]u8;
    pub extern fn arcan_shmif_signal(cont: ?*shmif.struct_arcan_shmif_cont, mask: c_int) c_uint;
    pub extern fn arcan_shmif_resize(cont: ?*shmif.struct_arcan_shmif_cont, w: c_uint, h: c_uint) bool;
    pub extern fn arcan_shmif_resize_ext(
        cont: ?*shmif.struct_arcan_shmif_cont,
        w: c_uint,
        h: c_uint,
        ext: shmif.struct_shmif_resize_ext,
    ) bool;
    pub const EVENT_EXTERNAL = a12.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = a12.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_EXTERNAL_MESSAGE = a12.EVENT_EXTERNAL_MESSAGE;
    pub const EVENT_EXTERNAL_STREAMSTATUS = a12.EVENT_EXTERNAL_STREAMSTATUS;
    pub const EVENT_IO = a12.EVENT_IO;
    pub const EVENT_TARGET = a12.EVENT_TARGET;
    // RHINT hint bits — translate-c emits these as c_int because they're
    // `#define` macros in arcan_shmif_defs.h. a12_types declares them as u8
    // (matches struct field type). Callers here do `@truncate(i8, VAL)` style
    // casts that expect signed integer input, so pin the type as c_int.
    pub const SHMIF_RHINT_ORIGO_LL: c_int = a12.SHMIF_RHINT_ORIGO_LL;
    pub const SHMIF_RHINT_TPACK: c_int = a12.SHMIF_RHINT_TPACK;
    pub const SHMIF_SIGAUD = a12.SHMIF_SIGAUD;
    pub const TARGET_COMMAND_BCHUNK_IN = a12.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_EXIT = a12.TARGET_COMMAND_EXIT;
    pub const TARGET_COMMAND_NEWSEGMENT = a12.TARGET_COMMAND_NEWSEGMENT;
    pub const TARGET_COMMAND_REQFAIL = a12.TARGET_COMMAND_REQFAIL;
    pub const TARGET_COMMAND_STEPFRAME = a12.TARGET_COMMAND_STEPFRAME;
    pub const shmif_asample = a12.shmif_asample;
    pub const shmif_pixel = a12.shmif_pixel;

    // ── a12 (a12.h / a12_int.h) — extern fns + constants ────────────────────
    pub const A12_BHANDLER_CACHED = a12.A12_BHANDLER_CACHED;
    pub const A12_BHANDLER_CANCELLED = a12.A12_BHANDLER_CANCELLED;
    pub const A12_BHANDLER_COMPLETED = a12.A12_BHANDLER_COMPLETED;
    pub const A12_BHANDLER_DONTWANT = a12.A12_BHANDLER_DONTWANT;
    pub const A12_BHANDLER_INITIALIZE = a12.A12_BHANDLER_INITIALIZE;
    pub const A12_BHANDLER_NEWFD = a12.A12_BHANDLER_NEWFD;
    pub const A12_BTYPE_APPL = a12.A12_BTYPE_APPL;
    pub const A12_BTYPE_APPL_RESOURCE = a12.A12_BTYPE_APPL_RESOURCE;
    pub const A12_BTYPE_BLOB = a12.A12_BTYPE_BLOB;
    pub const A12_BTYPE_FONT = a12.A12_BTYPE_FONT;
    pub const A12_BTYPE_FONT_SUPPL = a12.A12_BTYPE_FONT_SUPPL;
    pub const A12_BTYPE_STATE = a12.A12_BTYPE_STATE;
    pub const a12int_group_tostr = a12.a12int_group_tostr;
    // enum_a12_bstream_type — exposed as c_uint in a12_types.
    pub const enum_a12_bstream_type = a12.enum_a12_bstream_type;

    // blake3_hasher — extern fn declarations re-declared here with the
    // a12_types.blake3_hasher struct so call sites that also reference
    // `S.*.out_mac.counter` resolve to a single Zig type.
    pub const blake3_hasher = a12.blake3_hasher;
    // Use permissive [*c] pointer types so call sites don't need casts
    // between `*const anyopaque` and `?*const anyopaque` etc.
    pub extern fn blake3_hasher_init(self: [*c]a12.blake3_hasher) void;
    pub extern fn blake3_hasher_init_keyed(self: [*c]a12.blake3_hasher, key: [*c]const u8) void;
    pub extern fn blake3_hasher_init_derive_key(self: [*c]a12.blake3_hasher, context: [*c]const u8) void;
    pub extern fn blake3_hasher_update(self: [*c]a12.blake3_hasher, input: ?*const anyopaque, input_len: usize) void;
    pub extern fn blake3_hasher_finalize(self: [*c]const a12.blake3_hasher, out: [*c]u8, out_len: usize) void;
    pub extern fn blake3_hasher_finalize_seek(self: [*c]const a12.blake3_hasher, seek: u64, out: [*c]u8, out_len: usize) void;

    // ── Struct type aliases ─────────────────────────────────────────────────
    // All types now come from pure-Zig a12_types / shmif_types. Field access
    // like `S.*.keys.real_priv`, `ev.unnamed_0.unnamed_0.category`,
    // `S.*.congestion_stats.pending` routes through the expanded extern
    // struct layouts in those modules. Size pinned by comptime @sizeOf
    // assertions so ABI drift from the C side shows up as a build break.
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_a12_channel = a12.struct_a12_channel;
    pub const struct_a12_context_options = a12.struct_a12_context_options;
    pub const struct_a12_unpack_cfg = a12.struct_a12_unpack_cfg;
    pub const struct_a12_bhandler_meta = a12.struct_a12_bhandler_meta;
    pub const struct_a12_bhandler_res = a12.struct_a12_bhandler_res;
    pub const struct_a12_iostat = a12.struct_a12_iostat;
    pub const struct_a12_dynreq = a12.struct_a12_dynreq;
    pub const struct_pk_response = a12.struct_pk_response;
    pub const struct_appl_meta = a12.struct_appl_meta;
    pub const struct_blob_xfer = a12.struct_blob_xfer;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_arcan_shmif_region = shmif.arcan_shmif_region;
    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const struct_arcan_extevent = shmif.arcan_extevent;
    pub const struct_arcan_tgtevent = shmif.arcan_tgtevent;
    pub const struct_shmifsrv_vbuffer = shmif.struct_shmifsrv_vbuffer;
    pub const struct_shmif_resize_ext = shmif.struct_shmif_resize_ext;
    pub const struct_video_frame = a12.struct_video_frame;
    pub const struct_audio_frame = a12.struct_audio_frame;
    pub const struct_binary_frame = a12.struct_binary_frame;
    pub const struct_ZSTD_CCtx_s = a12.ZSTD_CCtx_s;
    pub const struct_ZSTD_DCtx_s = a12.ZSTD_DCtx_s;
    // Plain event-kind aliases used by translate-c'd code without the `struct_` prefix.
    pub const arcan_event = shmif.arcan_event;
    pub const arcan_extevent = shmif.arcan_extevent;
    pub const arcan_tgtevent = shmif.arcan_tgtevent;
};

// Type aliases
// Many types are provided by translate-c declarations later in this file
// (struct_a12_channel_meta, struct_a12_vframe_opts, blake3_hasher,
// A12_TRACE_*, ZSTD_*, chacha_*, a12_trace_targets/dst, arcan_random, etc.)
// Only types NOT defined by translate-c need aliases here.
const struct_ZSTD_CCtx_s = c.struct_ZSTD_CCtx_s;
const struct_ZSTD_DCtx_s = c.struct_ZSTD_DCtx_s;
const FILE = c.FILE;
const struct_a12_state = c.struct_a12_state;
const struct_a12_context_options = c.struct_a12_context_options;
const struct_a12_channel = c.struct_a12_channel;
const struct_a12_unpack_cfg = c.struct_a12_unpack_cfg;
const struct_a12_bhandler_meta = c.struct_a12_bhandler_meta;
const struct_a12_bhandler_res = c.struct_a12_bhandler_res;
const struct_a12_iostat = c.struct_a12_iostat;
const struct_a12_dynreq = c.struct_a12_dynreq;
const struct_pk_response = c.struct_pk_response;
const struct_appl_meta = c.struct_appl_meta;
const struct_blob_xfer = c.struct_blob_xfer;
const struct_arcan_shmif_cont = c.struct_arcan_shmif_cont;
const struct_arcan_event = c.struct_arcan_event;
const struct_shmifsrv_vbuffer = c.struct_shmifsrv_vbuffer;
const shmif_asample = c.shmif_asample;
// struct_chacha_ctx — concrete struct (mirrors chacha.c). cimport has an
// opaque placeholder named like `struct_chacha_ctx_74` because the
// implementation is not part of the cImport'd headers. The a12_state fields
// `enc_state`/`dec_state` are typed as `?*struct_chacha_ctx_74` on the
// cimport side, so the chacha_* wrappers convert via @ptrCast.
const chacha_keystream_union = extern union {
    u32: [16]u32,
    u8: [64]u8,
};
const struct_chacha_ctx = extern struct {
    schedule: [16]u32 = std.mem.zeroes([16]u32),
    keystream: chacha_keystream_union = std.mem.zeroes(chacha_keystream_union),
    iterations: c_int = 0,
    pos: usize = 0,
};
// The cimport-opaque pointer type matching a12_state.{enc,dec}_state.
// @FieldType lets us reference it without knowing the exact numeric suffix.
const cimport_chacha_ptr = @FieldType(c.struct_a12_state, "enc_state");
inline fn chacha_cast(p: cimport_chacha_ptr) [*c]struct_chacha_ctx {
    return @ptrCast(@alignCast(p));
}
inline fn chacha_uncast(p: [*c]struct_chacha_ctx) cimport_chacha_ptr {
    return @ptrCast(@alignCast(p));
}
const struct_arcan_shmif_region = c.struct_arcan_shmif_region;

// libc aliases (used without c. prefix in translate-c pasted code)
const fprintf = c.fprintf;
const memcpy = c.memcpy;
const memcmp = c.memcmp;
const malloc = c.malloc;
const free = c.free;
const memset = c.memset;
const strlen = c.strlen;
const close = c.close;
const snprintf = c.snprintf;
const realloc = c.realloc;
const read = c.read;
const memmove = c.memmove;
const strdup = c.strdup;
const off_t = c.off_t;
const __assert_fail = c.__assert_fail;
// __ctype_b_loc — libc internal not always surfaced by cImport on this target.
// Returns a pointer to a thread-local pointer into the ctype table.
extern fn __ctype_b_loc() callconv(.c) [*c][*c]const c_ushort;

// C symbols pasted translate-c references without the `c.` prefix
const arcan_shmif_eventpack = c.arcan_shmif_eventpack;
const arcan_shmif_eventunpack = c.arcan_shmif_eventunpack;
const arcan_shmif_descrevent = c.arcan_shmif_descrevent;
const arcan_shmif_eventstr = c.arcan_shmif_eventstr;
const arcan_shmif_signal = c.arcan_shmif_signal;
const enum_a12_bstream_type = c.enum_a12_bstream_type;
const arcan_event = c.arcan_event;
const arcan_extevent = c.arcan_extevent;
const A12_BHANDLER_CANCELLED = c.A12_BHANDLER_CANCELLED;
const A12_BHANDLER_DONTWANT = c.A12_BHANDLER_DONTWANT;
const A12_BHANDLER_NEWFD = c.A12_BHANDLER_NEWFD;
const A12_BHANDLER_INITIALIZE = c.A12_BHANDLER_INITIALIZE;
const A12_BHANDLER_CACHED = c.A12_BHANDLER_CACHED;
const arcan_tgtevent = c.arcan_tgtevent;
const SHMIF_RHINT_ORIGO_LL = c.SHMIF_RHINT_ORIGO_LL;
const SHMIF_RHINT_TPACK = c.SHMIF_RHINT_TPACK;
const TARGET_COMMAND_NEWSEGMENT = c.TARGET_COMMAND_NEWSEGMENT;
const arcan_shmif_resize = c.arcan_shmif_resize;
const EVENT_TARGET = c.EVENT_TARGET;
const shmif_pixel = c.shmif_pixel;
const A12_BTYPE_BLOB = c.A12_BTYPE_BLOB;
const A12_BTYPE_STATE = c.A12_BTYPE_STATE;
const A12_BTYPE_FONT = c.A12_BTYPE_FONT;
const A12_BTYPE_FONT_SUPPL = c.A12_BTYPE_FONT_SUPPL;
const TARGET_COMMAND_BCHUNK_IN = c.TARGET_COMMAND_BCHUNK_IN;
const EVENT_IO = c.EVENT_IO;
const sprintf = c.sprintf;
// _ISalnum — glibc ctype.h bit constant. On little-endian targets this equals
// `(1 << 11) >> 8`. cImport doesn't export the enum members reliably here.
const _ISalnum: c_int = 8;
const TARGET_COMMAND_EXIT = c.TARGET_COMMAND_EXIT;
const EVENT_EXTERNAL_MESSAGE = c.EVENT_EXTERNAL_MESSAGE;
const EVENT_EXTERNAL_STREAMSTATUS = c.EVENT_EXTERNAL_STREAMSTATUS;
const SHMIF_SIGAUD = c.SHMIF_SIGAUD;
const arcan_shmif_resize_ext = c.arcan_shmif_resize_ext;
const TARGET_COMMAND_REQFAIL = c.TARGET_COMMAND_REQFAIL;
const struct_shmif_resize_ext = c.struct_shmif_resize_ext;

// Internal a12 state frame types (from a12_int.h, now visible via cImport)
const struct_binary_frame = c.struct_binary_frame;
const struct_audio_frame = c.struct_audio_frame;
const struct_video_frame = c.struct_video_frame;
const EVENT_EXTERNAL_BCHUNKSTATE = c.EVENT_EXTERNAL_BCHUNKSTATE;
const EVENT_EXTERNAL = c.EVENT_EXTERNAL;

// Anonymous struct/union aliases (renumbered by cImport vs translate-c)
// translate-c numbered these per-TU — cImport numbers them differently.
// These unnamed types are file-private (`const`, not `pub`) in cimport.zig,
// so we can't say `c.struct_unnamed_N`; instead we fish them out via
// `@FieldType` or `@TypeOf(@as(Parent, undefined).field)`.
const union_unnamed_9 = @FieldType(c.struct_arcan_event, "unnamed_0");               // outer arcan_event union
const struct_unnamed_10 = @FieldType(union_unnamed_9, "unnamed_0");                    // payload-union + category struct
const union_unnamed_11 = @FieldType(struct_unnamed_10, "unnamed_0");                   // io/vid/aud/sys/tgt/fsrv/ext
const union_unnamed_26 = @FieldType(c.struct_arcan_extevent, "unnamed_0");            // extevent payload union
const struct_unnamed_27 = @FieldType(union_unnamed_26, "message");                     // message payload
const struct_unnamed_31 = @FieldType(union_unnamed_26, "bchunk");                      // bchunk payload
const struct_unnamed_45 = @FieldType(union_unnamed_26, "streamstat");                  // streamstat payload
const union_unnamed_32 = @FieldType(struct_unnamed_31, "unnamed_0");                   // bchunk ns union
const union_unnamed_24 = std.meta.Elem(@FieldType(c.struct_arcan_tgtevent, "ioevs"));  // tgt ioevs element
const union_unnamed_25 = @FieldType(c.struct_arcan_tgtevent, "unnamed_0");            // tgt message/bmessage/timestamp
const union_unnamed_47 = @FieldType(c.struct_arcan_shmif_cont, "unnamed_0");          // shmif vidp/floatp/vidb
const union_unnamed_48 = @FieldType(c.struct_arcan_shmif_cont, "unnamed_1");          // shmif audp/audb
const struct_unnamed_69 = @FieldType(c.struct_appl_meta, "appl");                     // appl_meta name/short_descr
const struct_unnamed_70 = @FieldType(c.struct_a12_state, "congestion_stats");         // congestion stats
const struct_unnamed_71 = @FieldType(c.struct_a12_state, "pending_dynamic");          // pending dynamic resource
const struct_unnamed_75 = @FieldType(c.struct_a12_state, "keys");                     // a12_state.keys

// Memory macros as inline functions
inline fn DYNAMIC_MALLOC(size: usize) ?*anyopaque {
    return std.c.malloc(size);
}
inline fn DYNAMIC_FREE(ptr: ?*anyopaque) void {
    std.c.free(ptr);
}
inline fn DYNAMIC_REALLOC(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    return std.c.realloc(ptr, size);
}

// a12int_trace as Zig function (replaces C variadic macro)
// Uses fprintf for format string compatibility with existing trace calls
fn a12int_trace(S: [*c]struct_a12_state, group: c_int, comptime fmt: []const u8, args: anytype) void {
    if (a12_trace_dst != null and (a12_trace_targets & group) != 0) {
        // For now, use a buffer approach
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        _ = c.fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:%.*s\n",
            &S.*.tracetag, arcan_timemillis(),
            c.a12int_group_tostr(group),
            @as(c_int, @intCast(msg.len)), msg.ptr);
    }
}

pub export fn a12_sensitive_alloc(nb: usize) ?*anyopaque {
    return arcan_alloc_mem(nb, @as(c_uint, @bitCast(ARCAN_MEM_EXTSTRUCT)), @as(c_uint, @bitCast(ARCAN_MEM_SENSITIVE | ARCAN_MEM_BZERO)), @as(c_uint, @bitCast(ARCAN_MEMALIGN_PAGE)));
}
pub export fn a12_sensitive_free(ptr: ?*anyopaque, buf: usize) void {
    arcan_random(@as([*c]u8, @ptrCast(@alignCast(ptr))), buf);
    arcan_mem_free(ptr);
}
pub export fn a12_client(opt: [*c]struct_a12_context_options) [*c]struct_a12_state {
    if (!(opt != null)) return null;
    a12_init();
    var mode: c_int = 0;
    const S: [*c]struct_a12_state = a12_setup(opt, false);
    if (!(S != null)) return null;
    var empty: [32]u8 = std.mem.zeroes([32]u8);
    var outpk: [32]u8 = undefined;
    if (memcmp(@as(?*const anyopaque, @ptrCast(&empty[0])), @as(?*const anyopaque, @ptrCast(&opt.*.priv_key[0])), 32) == 0) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SECURITY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:no_private_key:generating\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SECURITY), "a12_client");
        }
        x25519_private_key(@as([*c]u8, @ptrCast(@alignCast(&opt.*.priv_key[0]))));
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(&S.*.keys.real_priv[0])), @as(?*const anyopaque, @ptrCast(&opt.*.priv_key[0])), 32);
    if (opt.*.disable_ephemeral_k) {
        mode = HELLO_MODE_REALPK;
        S.*.authentic = AUTH_REAL_HELLO_SENT;
        _ = memset(@as(?*anyopaque, @ptrCast(&opt.*.priv_key[0])), '\x00', 32);
        x25519_public_key(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), @as([*c]u8, @ptrCast(@alignCast(&outpk[0]))));
        trace_crypto_key(S, S.*.server, "cl-priv", @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), 32);
    } else {
        mode = HELLO_MODE_EPHEMPK;
        x25519_private_key(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.ephem_priv[0]))));
        x25519_public_key(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.ephem_priv[0]))), @as([*c]u8, @ptrCast(@alignCast(&outpk[0]))));
        S.*.authentic = AUTH_POLITE_HELLO_SENT;
    }
    var nonce: [8]u8 = undefined;
    arcan_random(@as([*c]u8, @ptrCast(@alignCast(&nonce[0]))), 8);
    trace_crypto_key(S, S.*.server, "hello-pub", @as([*c]u8, @ptrCast(@alignCast(&outpk[0]))), 32);
    send_hello_packet(S, mode, @as([*c]u8, @ptrCast(@alignCast(&outpk[0]))), @as([*c]u8, @ptrCast(@alignCast(&nonce[0]))));
    return S;
}
pub export fn a12_server(opt: [*c]struct_a12_context_options) [*c]struct_a12_state {
    if (!(opt != null)) return null;
    a12_init();
    const res: [*c]struct_a12_state = a12_setup(opt, true);
    if (!(res != null)) return null;
    res.*.state = @as(u8, @bitCast(@as(i8, @truncate(STATE_1STSRV_PACKET))));
    res.*.left = @as(u16, @bitCast(@as(c_short, @truncate(header_sizes[res.*.state]))));
    return res;
}
pub export fn a12_free(S: [*c]struct_a12_state) bool {
    if (!(S != null) or (S.*.cookie != 4277009102)) {
        return false;
    }
    {
        var i: usize = 0;
        while (i < 256) : (i +%= 1) {
            if (S.*.channels[@as(c_uint, @intCast(S.*.out_channel))].active != 0) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:free with channel (%zu) active\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_free", i);
                }
                return false;
            }
        }
    }
    a12int_set_directory(S, null);
    if (S.*.prepend_unpack != null) {
        free(@as(?*anyopaque, @ptrCast(S.*.prepend_unpack)));
        S.*.prepend_unpack = null;
        S.*.prepend_unpack_sz = 0;
    }
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:a12-state machine freed\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "a12_free");
    }
    free(@as(?*anyopaque, @ptrCast(S.*.bufs[0])));
    free(@as(?*anyopaque, @ptrCast(S.*.bufs[1])));
    free(@as(?*anyopaque, @ptrCast(S.*.opts)));
    S.* = struct_a12_state{
        .opts = null,
        .directory = null,
        .directory_clk = std.mem.zeroes(u64),
        .notify_dynamic = false,
        .tracetag = std.mem.zeroes([16]u8),
        .last_mac_in = std.mem.zeroes([16]u8),
        .current_seqnr = std.mem.zeroes(u64),
        .last_seen_seqnr = std.mem.zeroes(u64),
        .out_stream = std.mem.zeroes(u64),
        .shutdown_id = std.mem.zeroes(i64),
        .advenc_broken = false,
        .congestion_stats = std.mem.zeroes(struct_unnamed_70),
        .stats = std.mem.zeroes(struct_a12_iostat),
        .pending_dynamic = std.mem.zeroes(struct_unnamed_71),
        .buf_sz = std.mem.zeroes([2]usize),
        .bufs = std.mem.zeroes([2][*c]u8),
        .buf_ind = std.mem.zeroes(u8),
        .buf_ofs = std.mem.zeroes(usize),
        .pending_out = null,
        .out_req_id = std.mem.zeroes(usize),
        .pending_in = null,
        .in_req_id = std.mem.zeroes(usize),
        .binary_handler = null,
        .binary_handler_tag = null,
        .channels = std.mem.zeroes([256]struct_a12_channel),
        .in_channel = 0,
        .in_stream = std.mem.zeroes(u32),
        .out_channel = 0,
        .on_discover = null,
        .discover_tag = null,
        .on_auth = null,
        .auth_tag = null,
        .decode = std.mem.zeroes([65536]u8),
        .decode_pos = std.mem.zeroes(u16),
        .left = std.mem.zeroes(u16),
        .state = std.mem.zeroes(u8),
        .cookie = std.mem.zeroes(u32),
        .keys = std.mem.zeroes(struct_unnamed_75),
        .server = false,
        .cl_firstout = false,
        .authentic = 0,
        .remote_mode = 0,
        .endpoint = null,
        .auth_latched = false,
        .prepend_unpack_sz = std.mem.zeroes(usize),
        .prepend_unpack = null,
        .out_mac = std.mem.zeroes(blake3_hasher),
        .in_mac = std.mem.zeroes(blake3_hasher),
        .enc_state = null,
        .dec_state = null,
        .state_error_hint = std.mem.zeroes([32]u8),
    };
    S.*.cookie = 3735928559;
    S.*.state = @as(u8, @bitCast(@as(i8, @truncate(STATE_BROKEN))));
    free(@as(?*anyopaque, @ptrCast(S)));
    return true;
}
pub export fn a12_set_session(dst: [*c]struct_pk_response, pubk: [*c]u8, privk: [*c]u8) void {
    x25519_public_key(privk, @as([*c]u8, @ptrCast(@alignCast(&dst.*.key_pub[0]))));
    _ = x25519_shared_secret(@as([*c]u8, @ptrCast(@alignCast(&dst.*.key_session[0]))), privk, pubk);
}
pub export fn a12_set_signing_pair(S: [*c]struct_a12_state, pubk: [*c]u8, privk: [*c]u8) bool {
    if (!(S != null) or (S.*.authentic != AUTH_FULL_PK)) {
        return false;
    }
    var outb: [128]u8 = undefined;
    var chg: [32]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_REKEY)))));
    build_signkey_challenge(S, @as([*c]u8, @ptrCast(@alignCast(&chg[0]))), &outb[8]);
    outb[18] = @as(u8, @bitCast(@as(i8, @truncate(REKEY_MODE_EDSIGN))));
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[19])), @as(?*const anyopaque, @ptrCast(pubk)), 32);
    crypto_ed25519_sign(&outb[19 + 32], privk, @as([*c]u8, @ptrCast(@alignCast(&chg[0]))), 32);
    trace_crypto_key(S, S.*.server, "signing_pair", @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), 32);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    return true;
}
pub export fn a12_get_sign_pubkey(S: [*c]struct_a12_state, outkey: [*c]u8) void {
    _ = memcpy(@as(?*anyopaque, @ptrCast(outkey)), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.sign_pub[0]))))), 32);
}
pub export fn a12_unpack(S: [*c]struct_a12_state, buf: [*c]const u8, buf_sz: usize, tag: ?*anyopaque, on_event: ?*const fn ([*c]struct_arcan_shmif_cont, c_int, [*c]struct_arcan_event, ?*anyopaque) callconv(.c) void) void {
    var buf_sz_ = buf_sz;
    if (@as(c_int, @bitCast(@as(c_uint, S.*.state))) == STATE_BROKEN) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:message=state machine broken\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_unpack");
        }
        fail_state(S, null);
        return;
    }
    if (S.*.prepend_unpack != null) {
        const tmp_buf: [*c]u8 = S.*.prepend_unpack;
        const tmp_sz: usize = S.*.prepend_unpack_sz;
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=prebuf:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_unpack", tmp_sz);
        }
        S.*.prepend_unpack_sz = 0;
        S.*.prepend_unpack = null;
        a12_unpack(S, tmp_buf, tmp_sz, tag, on_event);
        free(@as(?*anyopaque, @ptrCast(tmp_buf)));
    }
    if (@as(c_int, @bitCast(@as(c_uint, S.*.left))) == 0) {
        reset_state(S);
    }
    const ntr: usize = if (buf_sz_ > @as(usize, @bitCast(@as(c_ulong, S.*.left)))) @as(usize, @bitCast(@as(c_ulong, S.*.left))) else buf_sz_;
    _ = memcpy(@as(?*anyopaque, @ptrCast(&S.*.decode[S.*.decode_pos])), @as(?*const anyopaque, @ptrCast(buf)), ntr);
    S.*.left -%= @as(u16, @bitCast(@as(c_ushort, @truncate(ntr))));
    S.*.decode_pos +%= @as(u16, @bitCast(@as(c_ushort, @truncate(ntr))));
    buf_sz_ -%= ntr;
    S.*.stats.b_in +%= ntr;
    if (S.*.left != 0) return;
    while (true) {
        switch (@as(c_int, @bitCast(@as(c_uint, S.*.state)))) {
            6 => {
                process_srvfirst(S);
                break;
            },
            0 => {
                process_nopacket(S);
                break;
            },
            1 => {
                @import("shmif_monitor").emitLuaTag("a12:state=control");
                process_control(S, on_event, tag);
                break;
            },
            2 => {
                @import("shmif_monitor").emitLuaTag("a12:state=event");
                process_event(S, tag, on_event);
                break;
            },
            4 => {
                @import("shmif_monitor").emitLuaTag("a12:state=video");
                process_video(S);
                break;
            },
            3 => {
                @import("shmif_monitor").emitLuaTag("a12:state=audio");
                process_audio(S);
                break;
            },
            5 => {
                @import("shmif_monitor").emitLuaTag("a12:state=blob");
                process_blob(S);
                break;
            },
            else => {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:message=bad command\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_unpack");
                }
                fail_state(S, "bad-command");
                return;
            },
        }
        break;
    }
    if (buf_sz_ != 0) {
        if (!S.*.auth_latched) {
            a12_unpack(S, &buf[ntr], buf_sz_, tag, on_event);
            return;
        }
        S.*.auth_latched = false;
        S.*.prepend_unpack = @as([*c]u8, @ptrCast(@alignCast(malloc(buf_sz_))));
        if (!(S.*.prepend_unpack != null)) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:latch_buffer_sz=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "a12_unpack", buf_sz_);
            }
            fail_state(S, "alloc-fail-buffer-out");
            return;
        }
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=auth_latch:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_unpack", buf_sz_);
        }
        _ = memcpy(@as(?*anyopaque, @ptrCast(S.*.prepend_unpack)), @as(?*const anyopaque, @ptrCast(&buf[ntr])), buf_sz_);
        S.*.prepend_unpack_sz = buf_sz_;
        return;
    }
    if (S.*.auth_latched) {
        S.*.auth_latched = false;
    }
}
pub export fn a12_set_destination(S: [*c]struct_a12_state, wnd: [*c]struct_arcan_shmif_cont, chid: u8) void {
    if (!(S != null)) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DEBUG) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:invalid set_destination call\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DEBUG), "a12_set_destination");
        }
        return;
    }
    if (S.*.channels[chid].active == CHANNEL_RAW) {
        free(@as(?*anyopaque, @ptrCast(S.*.channels[chid].cont)));
        S.*.channels[chid].cont = null;
    }
    S.*.channels[chid].cont = wnd;
    S.*.channels[chid].active = if (wnd != null) CHANNEL_SHMIF else CHANNEL_INACTIVE;
}
pub const struct_a12_channel_meta = extern struct {
    inbound_binary_total: usize = std.mem.zeroes(usize),
    inbound_binary_depth: usize = std.mem.zeroes(usize),
    outbound_binary_total: usize = std.mem.zeroes(usize),
    outbound_binary_depth: usize = std.mem.zeroes(usize),
    video_active: bool = std.mem.zeroes(bool),
    audio_active: bool = std.mem.zeroes(bool),
};
pub export fn a12_channel_bprogress_hook(S: [*c]struct_a12_state, chid: u8, bytecount: usize, on_update: ?*const fn (c_int, usize, usize, usize, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) void {
    S.*.channels[chid].progress.trigger_left = blk: {
        const tmp = bytecount;
        S.*.channels[chid].progress.trigger_count = tmp;
        break :blk tmp;
    };
    S.*.channels[chid].progress.tag = tag;
    S.*.channels[chid].progress.trigger = on_update;
}
pub export fn a12_channel_status(S: [*c]struct_a12_state, chid: u8) struct_a12_channel_meta {
    _ = S;
    _ = chid;
    return struct_a12_channel_meta{
        .inbound_binary_total = 0,
        .inbound_binary_depth = std.mem.zeroes(usize),
        .outbound_binary_total = std.mem.zeroes(usize),
        .outbound_binary_depth = std.mem.zeroes(usize),
        .video_active = false,
        .audio_active = false,
    };
}
pub export fn a12_find_free_channel(S: [*c]struct_a12_state, chid: [*c]u8) bool {
    {
        var i: usize = 0;
        while (i < 256) : (i +%= 1) {
            if (S.*.channels[i].active != 0) continue;
            chid.* = @as(u8, @truncate(i));
            return true;
        }
    }
    return false;
}
pub export fn a12_set_destination_raw(S: [*c]struct_a12_state, chid: u8, cfg: struct_a12_unpack_cfg, cfg_sz: usize) void {
    _ = cfg_sz;
    const ct_sz: usize = @sizeOf(struct_arcan_shmif_cont);
    const fake: [*c]struct_arcan_shmif_cont = @as([*c]struct_arcan_shmif_cont, @ptrCast(@alignCast(malloc(ct_sz))));
    if (!(fake != null)) return;
    fake.* = struct_arcan_shmif_cont{
        .addr = null,
        .unnamed_0 = std.mem.zeroes(union_unnamed_47),
        .unnamed_1 = std.mem.zeroes(union_unnamed_48),
        .oflow_cookie = std.mem.zeroes(i16),
        .abufused = std.mem.zeroes(u16),
        .abufpos = std.mem.zeroes(u16),
        .abufsize = std.mem.zeroes(u16),
        .abufcount = std.mem.zeroes(u16),
        .abuf_cnt = std.mem.zeroes(u8),
        .epipe = 0,
        .shmh = 0,
        .shmsize = std.mem.zeroes(usize),
        .unused = std.mem.zeroes([3]usize),
        .w = std.mem.zeroes(usize),
        .h = std.mem.zeroes(usize),
        .stride = std.mem.zeroes(usize),
        .pitch = std.mem.zeroes(usize),
        .adata = std.mem.zeroes(u32),
        .samplerate = std.mem.zeroes(usize),
        .hints = std.mem.zeroes(u8),
        .dirty = std.mem.zeroes(struct_arcan_shmif_region),
        .cookie = std.mem.zeroes(u64),
        .user = null,
        .priv = null,
        .privext = null,
        .segment_token = std.mem.zeroes(u32),
        .vbufsize = std.mem.zeroes(usize),
    };
    S.*.channels[chid].cont = fake;
    S.*.channels[chid].raw = cfg;
    S.*.channels[chid].active = CHANNEL_RAW;
    S.*.on_discover = cfg.on_discover;
    S.*.discover_tag = cfg.on_discover_tag;
}
pub const A12_FLUSH_NOBLOB: c_int = 0;
pub const A12_FLUSH_CHONLY: c_int = 1;
pub const A12_FLUSH_ALL: c_int = 2;
pub const enum_a12_blob_mode = c_uint;
pub export fn a12_flush(S: [*c]struct_a12_state, buf: [*c][*c]u8, allow_blob: c_int) usize {
    if ((@as(c_int, @bitCast(@as(c_uint, S.*.state))) == STATE_BROKEN) or (S.*.cookie != 4277009102)) return 0;
    if (S.*.buf_ofs == 0) {
        while (((allow_blob > A12_FLUSH_NOBLOB) and (append_blob(S, allow_blob) != 0)) and (S.*.buf_ofs < 128 * 1024)) {}
        if (!(S.*.buf_ofs != 0)) return 0;
    }
    const rv: usize = S.*.buf_ofs;
    {
        const smon = @import("shmif_monitor");
        var buf2: [64]u8 = undefined;
        _ = std.fmt.bufPrintZ(&buf2, "a12:flush:bytes={d}", .{rv}) catch unreachable;
        smon.emitLuaTag(@ptrCast(&buf2));
    }
    const old_ind: c_int = @as(c_int, @bitCast(@as(c_uint, S.*.buf_ind)));
    buf.* = S.*.bufs[S.*.buf_ind];
    S.*.buf_ofs = 0;
    S.*.buf_ind = @as(u8, @bitCast(@as(i8, @truncate(@import("std").zig.c_translation.signedRemainder(@as(c_int, @bitCast(@as(c_uint, S.*.buf_ind))) + 1, 2)))));
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:locked %d, new buffer: %d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "a12_flush", old_ind, @as(c_int, @bitCast(@as(c_uint, S.*.buf_ind))));
    }
    return rv;
}
pub export fn a12_enqueue_bstream(S: [*c]struct_a12_state, fd: c_int, @"type": c_int, id: u32, streaming: bool, sz: usize, extid: [*c]const u8) void {
    {
        const smon = @import("shmif_monitor");
        const snprintf_p = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf_p: [96]u8 = undefined;
        _ = snprintf_p(&buf_p, 96, "a12:coverage:bstream_enqueue:type=%d:fd=%d:sz=%zu:streaming=%d",
            @"type", fd, sz, @as(c_int, @intFromBool(streaming)));
        smon.emitLuaTag(@ptrCast(&buf_p));
    }
    return a12_enqueue_bstream_tagged(S, fd, @"type", id, streaming, sz, extid, null);
}
pub export fn a12_enqueue_blob(S: [*c]struct_a12_state, buf: [*c]const u8, buf_sz: usize, id: u32, @"type": c_int, extid: [*c]const u8) void {
    const next: [*c][*c]struct_blob_xfer = alloc_attach_blob(S, &S.*.pending_out);
    if (!(next != null)) return;
    const nbuf: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(malloc(buf_sz))));
    if (!(nbuf != null)) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=ENOMEM\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_enqueue_blob");
        }
        free(@as(?*anyopaque, @ptrCast(next.*)));
        next.* = null;
        return;
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(nbuf)), @as(?*const anyopaque, @ptrCast(buf)), buf_sz);
    next.*.*.buf = nbuf;
    next.*.*.buf_sz = buf_sz;
    next.*.*.left = buf_sz;
    next.*.*.identifier = id;
    next.*.*.type = @"type";
    next.*.*.streamid = @as(u64, @bitCast(@as(c_ulong, id)));
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&next.*.*.extid[0]))))), @as(?*const anyopaque, @ptrCast(extid)), 16);
    var hash: blake3_hasher = undefined;
    blake3_hasher_init(&hash);
    blake3_hasher_update(&hash, @as(?*const anyopaque, @ptrCast(nbuf)), buf_sz);
    blake3_hasher_finalize(&hash, @as([*c]u8, @ptrCast(@alignCast(&next.*.*.checksum[0]))), 16);
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=added:type=fixed_blob:stream=no:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_enqueue_blob", buf_sz);
    }
}
pub export fn a12_request_file(S: [*c]struct_a12_state, chid: u8, ns: u16, id: u32, name: [*c]const u8) void {
    _ = chid;
    var ev: struct_arcan_event = struct_arcan_event{
        .unnamed_0 = union_unnamed_9{
            .unnamed_0 = struct_unnamed_10{
                .unnamed_0 = union_unnamed_11{
                    .ext = arcan_extevent{
                        .kind = @as(c_uint, @bitCast(EVENT_EXTERNAL_BCHUNKSTATE)),
                        .source = std.mem.zeroes(i64),
                        .unnamed_0 = union_unnamed_26{
                            .bchunk = struct_unnamed_31{
                                .unnamed_0 = union_unnamed_32{
                                    .ns = @as(u64, @bitCast(@as(c_ulong, ns))),
                                },
                                .input = 1,
                                .hint = std.mem.zeroes(u8),
                                .stream = std.mem.zeroes(u8),
                                .extensions = std.mem.zeroes([68]u8),
                                .identifier = id,
                            },
                        },
                        .frame_id = std.mem.zeroes(u64),
                    },
                },
                .category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_EXTERNAL)))),
            },
        },
    };
    _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions[0]))), 68, "%s", name);
    _ = a12_channel_enqueue(S, &ev);
}
pub export fn a12_write_tunnel(S: [*c]struct_a12_state, chid: u8, buf: [*c]const u8, buf_sz: usize) bool {
    var buf_sz_ = buf_sz;
    if (!(buf_sz_ != 0)) return false;
    if (!(S.*.channels[chid].active != 0)) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:write_tunnel:bad_channel=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_write_tunnel", @as(c_int, @bitCast(@as(c_uint, chid))));
        }
        return false;
    }
    var outb: [7]u8 = std.mem.zeroes([7]u8);
    outb[0] = chid;
    var buf_ofs: usize = 0;
    const chunk_cap: usize = 32768;
    while (buf_sz_ > chunk_cap) {
        buf_sz_ -%= chunk_cap;
        pack_u16(@as(u16, @bitCast(@as(c_ushort, @truncate(chunk_cap)))), &outb[5]);
        a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_BLOB_PACKET)))), &buf[buf_ofs], chunk_cap, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @sizeOf([7]u8));
        buf_ofs +%= chunk_cap;
    }
    if (buf_sz_ != 0) {
        pack_u16(@as(u16, @bitCast(@as(c_ushort, @truncate(buf_sz_)))), &outb[5]);
        a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_BLOB_PACKET)))), &buf[buf_ofs], buf_sz_, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @sizeOf([7]u8));
    }
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:write_tunnel:ch=%u:nb=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_write_tunnel", @as(c_int, @bitCast(@as(c_uint, chid))), buf_sz_);
    }
    return true;
}
pub export fn a12_set_tunnel_sink(S: [*c]struct_a12_state, chid: u8, fd: c_int) bool {
    if (S.*.channels[chid].active != 0) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:swap_sink:chid=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "a12_set_tunnel_sink", @as(c_int, @bitCast(@as(c_uint, chid))));
        }
        if (0 < S.*.channels[chid].unpack_state.bframe.tmp_fd) {
            _ = close(S.*.channels[chid].unpack_state.bframe.tmp_fd);
        }
    }
    if (-1 == fd) {
        S.*.channels[chid].active = 0;
        S.*.channels[chid].unpack_state.bframe.tunnel = 0;
        S.*.channels[chid].unpack_state.bframe.tmp_fd = -1;
        return true;
    }
    S.*.channels[chid].active = 1;
    S.*.channels[chid].unpack_state.bframe = struct_binary_frame{
        .tmp_fd = fd,
        .type = 0,
        .active = true,
        .tunnel = 1,
        .size = std.mem.zeroes(u64),
        .identifier = std.mem.zeroes(u32),
        .checksum = std.mem.zeroes([16]u8),
        .streamid = std.mem.zeroes(i64),
        .zstd = null,
    };
    return true;
}
pub export fn a12_alloc_tunnel(S: [*c]struct_a12_state) c_int {
    {
        var chid: usize = 1;
        while (chid < 256) : (chid +%= 1) {
            if (!(S.*.channels[chid].active != 0)) {
                S.*.channels[chid].active = 1;
                S.*.channels[chid].unpack_state.bframe.tunnel = 1;
                S.*.channels[chid].unpack_state.bframe.tmp_fd = -1;
                return @as(c_int, @bitCast(@as(c_uint, @truncate(chid))));
            }
        }
    }
    return -1;
}
pub export fn a12_drop_tunnel(S: [*c]struct_a12_state, id: u8) void {
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_TUNDROP)))));
    outb[18] = id;
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:close_tunnel=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "a12_drop_tunnel", @as(c_int, @bitCast(@as(c_uint, id))));
    }
    S.*.channels[id].active = 0;
    const fd: c_int = S.*.channels[id].unpack_state.bframe.tmp_fd;
    if (0 < fd) {
        _ = close(fd);
        S.*.channels[id].unpack_state.bframe.active = false;
        S.*.channels[id].unpack_state.bframe.tmp_fd = -1;
    }
}
pub export fn a12_tunnel_descriptor(S: [*c]struct_a12_state, chid: u8, ok: [*c]bool) c_int {
    ok.* = true;
    if (S.*.channels[chid].active != 0) {
        ok.* = S.*.channels[chid].unpack_state.bframe.tunnel == 1;
        return S.*.channels[chid].unpack_state.bframe.tmp_fd;
    } else return -1;
    return 0;
}
pub export fn a12_poll(S: [*c]struct_a12_state) c_int {
    // Upstream a12.c:4160 — return -1 iff state IS broken or cookie is bad.
    // A prior translate-c pass flipped the sense of the state check,
    // causing every healthy a12_state to poll as -1 and the client-side
    // auth loop (anet_helper.zig) to exit before its first read.
    if (@as(c_int, @bitCast(@as(c_uint, S.*.state))) == STATE_BROKEN or
        S.*.cookie != 4277009102) return -1;
    return if ((S.*.buf_ofs != 0) or (S.*.pending_out != null)) 1 else 0;
}
pub const AUTH_UNAUTHENTICATED: c_int = 0;
pub const AUTH_SERVER_HBLOCK: c_int = 1;
pub const AUTH_POLITE_HELLO_SENT: c_int = 2;
pub const AUTH_EPHEMERAL_PK: c_int = 3;
pub const AUTH_REAL_HELLO_SENT: c_int = 4;
pub const AUTH_FULL_PK: c_int = 5;
pub const enum_authentic_state = c_uint;
pub const ROLE_NONE: c_int = 0;
pub const ROLE_SOURCE: c_int = 1;
pub const ROLE_SINK: c_int = 2;
pub const ROLE_PROBE: c_int = 3;
pub const ROLE_DIR: c_int = 4;
pub const ROLE_DIRREF: c_int = 5;
pub const enum_self_roles = c_uint;
pub export fn a12_auth_state(S: [*c]struct_a12_state) c_int {
    return S.*.authentic;
}
pub export fn a12_set_channel(S: [*c]struct_a12_state, chid: u8) void {
    if (@as(c_int, @bitCast(@as(c_uint, chid))) != S.*.out_channel) while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:channel_out=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_set_channel", @as(c_int, @bitCast(@as(c_uint, chid))));
        }
        if (!false) break;
    };
    S.*.out_channel = @as(c_int, @bitCast(@as(c_uint, chid)));
}
pub export fn a12_get_channel(S: [*c]struct_a12_state) u8 {
    return @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel))));
}
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
pub const enum_trace_groups = c_uint;
pub export fn a12_set_trace_level(mask: c_int, dst: ?*FILE) void {
    a12_trace_targets = mask;
    a12_trace_dst = dst;
}
pub const VFRAME_METHOD_DEFER: c_int = -1;
pub const VFRAME_METHOD_NORMAL: c_int = 0;
pub const VFRAME_METHOD_RAW_NOALPHA: c_int = 1;
pub const VFRAME_METHOD_RAW_RGB565: c_int = 2;
pub const VFRAME_METHOD_H264: c_int = 5;
pub const VFRAME_METHOD_TPACK_ZSTD: c_int = 7;
pub const VFRAME_METHOD_ZSTD: c_int = 8;
pub const VFRAME_METHOD_DZSTD: c_int = 9;
pub const enum_a12_vframe_method = c_int;
pub const STREAM_TYPE_VIDEO: c_int = 0;
pub const STREAM_TYPE_AUDIO: c_int = 1;
pub const STREAM_TYPE_BINARY: c_int = 2;
pub const enum_a12_stream_types = c_uint;
pub const VFRAME_BIAS_LATENCY: c_int = 0;
pub const VFRAME_BIAS_BALANCED: c_int = 1;
pub const VFRAME_BIAS_QUALITY: c_int = 2;
pub const enum_a12_vframe_compression_bias = c_uint;
pub const VFRAME_POSTPROCESS_SRGB: c_int = 1;
pub const VFRAME_POSTPROCESS_ORIGO_LL: c_int = 2;
pub const enum_a12_vframe_postprocess = c_uint;
pub const struct_a12_vframe_opts = extern struct {
    method: enum_a12_vframe_method = std.mem.zeroes(enum_a12_vframe_method),
    bias: enum_a12_vframe_compression_bias = std.mem.zeroes(enum_a12_vframe_compression_bias),
    postprocess: enum_a12_vframe_postprocess = std.mem.zeroes(enum_a12_vframe_postprocess),
    ratefactor: c_int = std.mem.zeroes(c_int),
    bitrate: usize = std.mem.zeroes(usize),
    force_idr: bool = std.mem.zeroes(bool),
    result_feedback: ?*const fn ([*c]u8, usize, ?*anyopaque) callconv(.c) void = std.mem.zeroes(?*const fn ([*c]u8, usize, ?*anyopaque) callconv(.c) void),
};
pub const AFRAME_METHOD_RAW: c_int = 0;
pub const enum_a12_aframe_method = c_uint;
pub const struct_a12_aframe_opts = extern struct {
    method: enum_a12_aframe_method = std.mem.zeroes(enum_a12_aframe_method),
};
pub const struct_a12_aframe_cfg = extern struct {
    channels: u8 = std.mem.zeroes(u8),
    samplerate: u32 = std.mem.zeroes(u32),
};
pub export fn a12_set_bhandler(S: [*c]struct_a12_state, on_bevent: ?*const fn ([*c]struct_a12_state, struct_a12_bhandler_meta, ?*anyopaque) callconv(.c) struct_a12_bhandler_res, tag: ?*anyopaque) void {
    if (!(S != null)) return;
    S.*.binary_handler = on_bevent;
    S.*.binary_handler_tag = tag;
}
pub export fn a12_channel_enqueue(S: [*c]struct_a12_state, ev: [*c]struct_arcan_event) bool {
    if ((!(S != null) or (S.*.cookie != 4277009102)) or !(ev != null)) return false;
    {
        const smon = @import("shmif_monitor");
        var buf: [64]u8 = undefined;
        const cat = ev.*.unnamed_0.unnamed_0.category;
        const kind: c_int = switch (cat) {
            @as(u8, 16) => @intCast(ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.kind),
            @as(u8, 64) => @intCast(ev.*.unnamed_0.unnamed_0.unnamed_0.ext.kind),
            else => -1,
        };
        _ = std.fmt.bufPrintZ(&buf, "a12:enqueue:cat={d}:kind={d}:chid={d}",
            .{ cat, kind, S.*.out_channel }) catch unreachable;
        smon.emitLuaTag(@ptrCast(&buf));
    }
    var empty_ext: [16]u8 = [1]u8{0} ++ [1]u8{0} ** 15;
    if (arcan_shmif_descrevent(ev)) {
        while (true) {
            switch (ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.kind) {
                @as(c_uint, @bitCast(@as(c_int, 6))) => return a12_enqueue_bstream_in(S, ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, A12_BTYPE_STATE, ev),
                @as(c_uint, @bitCast(@as(c_int, 7))) => return a12_enqueue_bstream_in(S, ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, A12_BTYPE_BLOB, ev),
                @as(c_uint, @bitCast(@as(c_int, 5))) => {
                    a12_enqueue_bstream_tagged(S, ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, A12_BTYPE_STATE, @as(u32, @bitCast(ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv)), true, 0, @as([*c]u8, @ptrCast(@alignCast(&empty_ext[0]))), ev);
                    return true;
                },
                @as(c_uint, @bitCast(@as(c_int, 8))) => {
                    a12_enqueue_bstream_tagged(S, ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, A12_BTYPE_BLOB, @as(u32, @bitCast(ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv)), ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv <= 0, @as(usize, @bitCast(@as(c_long, ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv))), @as([*c]u8, @ptrCast(@alignCast(&empty_ext[0]))), ev);
                    return true;
                },
                @as(c_uint, @bitCast(@as(c_int, 25))) => {
                    a12_enqueue_bstream(S, ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, if (ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv == 1) A12_BTYPE_FONT_SUPPL else A12_BTYPE_FONT, 0, false, 0, @as([*c]u8, @ptrCast(@alignCast(&empty_ext[0]))));
                    break;
                },
                else => {
                    while (true) {
                        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:message=%s\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_channel_enqueue", arcan_shmif_eventstr(ev, null, 0));
                        }
                        if (!false) break;
                    }
                    return true;
                },
            }
            break;
        }
    }
    _ = pack_and_send_event(S, ev);
    return true;
}
pub export fn a12_channel_aframe(S: [*c]struct_a12_state, buf: [*c]shmif_asample, n_samples: usize, cfg: struct_a12_aframe_cfg, opts: struct_a12_aframe_opts) void {
    if ((!(S != null) or (S.*.cookie != 4277009102)) or (@as(c_int, @bitCast(@as(c_uint, S.*.state))) == STATE_BROKEN)) return;
    {
        const smon = @import("shmif_monitor");
        const snprintf_p = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf_p: [96]u8 = undefined;
        _ = snprintf_p(&buf_p, 96, "a12:coverage:aframe_encode:samples=%zu:rate=%u:ch=%u",
            n_samples, cfg.samplerate, @as(c_int, @bitCast(@as(c_uint, cfg.channels))));
        smon.emitLuaTag(@ptrCast(&buf_p));
    }
    const chunk_sz: usize = 16428;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_AUDIO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:encode %zu samples @ %u Hz /%u ch\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_AUDIO), "a12_channel_aframe", n_samples, cfg.samplerate, @as(c_int, @bitCast(@as(c_uint, cfg.channels))));
        }
        if (!false) break;
    }
    a12int_encode_araw(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel)))), buf, @as(u16, @bitCast(@as(c_ushort, @truncate(n_samples / 2)))), cfg, opts, chunk_sz);
}
pub export fn a12_channel_vframe(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts) c_int {
    if ((!(S != null) or (S.*.cookie != 4277009102)) or (@as(c_int, @bitCast(@as(c_uint, S.*.state))) == STATE_BROKEN)) return -1;
    {
        const smon = @import("shmif_monitor");
        const snprintf_p = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf_p: [128]u8 = undefined;
        const vbp = vb orelse return -1;
        _ = snprintf_p(&buf_p, 128, "a12:coverage:vframe_encode:w=%zu:h=%zu:method=%d:tpack=%d",
            @as(usize, @intCast(vbp.w)), @as(usize, @intCast(vbp.h)),
            opts.method, @as(c_int, @intFromBool(vbp.flags.tpack)));
        smon.emitLuaTag(@ptrCast(&buf_p));
    }
    const chunk_sz: usize = 32768;
    var x: usize = 0;
    var y: usize = 0;
    var w: usize = vb.?.*.w;
    var h: usize = vb.?.*.h;
    if (vb.?.*.flags.subregion) {
        x = @as(usize, @bitCast(@as(c_ulong, vb.?.*.region.x1)));
        y = @as(usize, @bitCast(@as(c_ulong, vb.?.*.region.y1)));
        w = @as(usize, @bitCast(@as(c_ulong, vb.?.*.region.x2))) -% x;
        h = @as(usize, @bitCast(@as(c_ulong, vb.?.*.region.y2))) -% y;
    }
    if (!(w != 0) or !(h != 0)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=einval:status=bad dimensions\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_channel_vframe");
            }
            if (!false) break;
        }
        return -1;
    }
    if (((x +% w) > vb.?.*.w) or ((y +% h) > vb.?.*.h)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:client provided bad/broken subregion (%zu+%zu > %zu)(%zu+%zu > %zu)\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_channel_vframe", x, w, vb.?.*.w, y, h, vb.?.*.h);
            }
            if (!false) break;
        }
        x = 0;
        y = 0;
        w = vb.?.*.w;
        h = vb.?.*.h;
    }
    const sid: u32 = @as(u32, @bitCast(@as(c_uint, @truncate(S.*.out_stream))));
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:out vframe: %zu*%zu @%zu,%zu+%zu,%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "a12_channel_vframe", vb.?.*.w, vb.?.*.h, w, h, x, y);
        }
        if (!false) break;
    }
    const now: usize = @as(usize, @bitCast(@as(c_ulong, @truncate(arcan_timemillis()))));
    if (vb.?.*.flags.compressed) {
        a12int_encode_passthrough(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
    } else {
        while (true) {
            switch (opts.method) {
                2 => {
                    a12int_encode_rgb565(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
                    break;
                },
                0 => {
                    if (vb.?.*.flags.ignore_alpha) {
                        a12int_encode_rgb(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
                    } else {
                        a12int_encode_rgba(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
                    }
                    break;
                },
                1 => {
                    a12int_encode_rgb(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
                    break;
                },
                8, 9 => {
                    a12int_encode_dzstd(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
                    break;
                },
                5 => {
                    if (S.*.advenc_broken) {
                        a12int_encode_dzstd(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
                    } else {
                        a12int_encode_h264(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
                    }
                    break;
                },
                7 => {
                    a12int_encode_ztz(S, vb, opts, sid, x, y, w, h, chunk_sz, S.*.out_channel);
                    break;
                },
                else => {
                    while (true) {
                        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:unknown format: %d\n\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_channel_vframe", opts.method);
                        }
                        if (!false) break;
                    }
                    return -1;
                },
            }
            break;
        }
    }
    const then: usize = @as(usize, @bitCast(@as(c_ulong, @truncate(arcan_timemillis()))));
    if (then > now) {
        S.*.stats.ms_vframe = then -% now;
        S.*.stats.ms_vframe_px = @as(f32, @floatFromInt(then -% now)) / @as(f32, @floatFromInt(w *% h));
    }
    return if (S.*.out_stream == @as(u64, @bitCast(@as(c_ulong, sid)))) 0 else 1;
}
pub export fn a12_channel_new(S: [*c]struct_a12_state, chid: u8, segkind: u8, cookie: u32) void {
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_NEWCH)))));
    outb[18] = chid;
    outb[19] = segkind;
    outb[20] = 0;
    pack_u32(cookie, &outb[21]);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub export fn a12_channel_shutdown(S: [*c]struct_a12_state, last_words: [*c]const u8) void {
    if (!(S != null) or (S.*.cookie != 4277009102)) {
        return;
    }
    var outb: [128]u8 = [1]u8{0} ++ [1]u8{0} ** 127;
    step_sequence(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))));
    outb[16] = @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel))));
    outb[17] = @as(u8, @bitCast(@as(i8, @truncate(COMMAND_SHUTDOWN))));
    _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&outb[18]))), @as(c_ulong, @bitCast(@as(c_long, 128 - 19))), "%s", last_words);
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:channel open, add control packet\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_channel_shutdown");
        }
        if (!false) break;
    }
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub export fn a12_channel_close(S: [*c]struct_a12_state) void {
    if (!(S != null) or (S.*.cookie != 4277009102)) {
        return;
    }
    const ch: ?*struct_a12_channel = &S.*.channels[@as(c_uint, @intCast(S.*.out_channel))];
    a12int_encode_drop(S, S.*.out_channel, false);
    a12int_decode_drop(S, S.*.out_channel, false);
    if (ch.?.*.unpack_state.bframe.zstd != null) {
        _ = ZSTD_freeDCtx(ch.?.*.unpack_state.bframe.zstd);
        ch.?.*.unpack_state.bframe.zstd = null;
    }
    if (ch.?.*.active != 0) {
        ch.?.*.cont = null;
        ch.?.*.active = 0;
    }
    if (S.*.out_channel == 0) {
        fail_state(S, "close-bad-channel");
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:closing channel (%d)\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_channel_close", S.*.out_channel);
        }
        if (!false) break;
    }
}
pub export fn a12_stream_cancel(S: [*c]struct_a12_state, channel: u8) void {
    const bframe: [*c]struct_binary_frame = &S.*.channels[channel].unpack_state.bframe;
    if (!bframe.*.active) return;
    build_cancel_packet(S, channel, @as(u32, @bitCast(@as(c_int, @truncate(bframe.*.streamid)))), @as(u8, @bitCast(@as(i8, @truncate(STREAM_TYPE_BINARY)))));
    bframe.*.active = false;
    bframe.*.streamid = -1;
    if (bframe.*.zstd != null) {
        _ = ZSTD_freeDCtx(bframe.*.zstd);
        bframe.*.zstd = null;
    }
    if (S.*.binary_handler != null) {
        const bm: struct_a12_bhandler_meta = struct_a12_bhandler_meta{
            .state = @as(c_uint, @bitCast(A12_BHANDLER_CANCELLED)),
            .type = std.mem.zeroes(enum_a12_bstream_type),
            .checksum = std.mem.zeroes([16]u8),
            .known_size = std.mem.zeroes(u64),
            .streaming = false,
            .channel = channel,
            .streamid = bframe.*.streamid,
            .identifier = std.mem.zeroes(u32),
            .extid = std.mem.zeroes([17]u8),
            .fd = bframe.*.tmp_fd,
            .dcont = null,
        };
        _ = S.*.binary_handler.?(S, bm, S.*.binary_handler_tag);
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=cancelled:ch=%u:stream=%ld\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_stream_cancel", @as(c_int, @bitCast(@as(c_uint, channel))), bframe.*.streamid);
        }
        if (!false) break;
    }
    bframe.*.tmp_fd = -1;
}
pub export fn a12_ok(S: [*c]struct_a12_state) bool {
    return @as(c_int, @bitCast(@as(c_uint, S.*.state))) != STATE_BROKEN;
}
pub export fn a12_remote_mode(S: [*c]struct_a12_state) c_int {
    return S.*.remote_mode;
}
pub const STREAM_CANCEL_DONTWANT: c_int = 0;
pub const STREAM_CANCEL_DECODE_ERROR: c_int = 1;
pub const STREAM_CANCEL_KNOWN: c_int = 2;
pub const enum_stream_cancel = c_uint;
pub export fn a12_vstream_cancel(S: [*c]struct_a12_state, channel: u8, reason: c_int) void {
    var outb: [128]u8 = [1]u8{0} ++ [1]u8{0} ** 127;
    step_sequence(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))));
    const vframe: [*c]struct_video_frame = &S.*.channels[channel].unpack_state.vframe;
    vframe.*.commit = 255;
    outb[16] = channel;
    outb[17] = @as(u8, @bitCast(@as(i8, @truncate(COMMAND_CANCELSTREAM))));
    pack_u32(@as(u32, @bitCast(@as(c_int, 1))), &outb[18]);
    outb[22] = @as(u8, @bitCast(@as(i8, @truncate(reason))));
    outb[23] = @as(u8, @bitCast(@as(i8, @truncate(STREAM_TYPE_VIDEO))));
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub export fn a12_btransfer_outfd(S: [*c]struct_a12_state) c_int {
    if ((!(S != null) or (@as(c_int, @bitCast(@as(c_uint, S.*.state))) == STATE_BROKEN)) or (S.*.cookie != 4277009102)) return -1;
    return if (S.*.pending_out != null) S.*.pending_out.*.fd else -1;
}
pub export fn a12_shutdown_id(S: [*c]struct_a12_state, id: u32) void {
    S.*.shutdown_id = @as(i64, @bitCast(@as(c_ulong, id)));
}
pub export fn a12_get_endpoint(S: [*c]struct_a12_state) [*c]const u8 {
    return if (S != null) S.*.endpoint else null;
}
pub export fn a12_set_endpoint(S: [*c]struct_a12_state, ep: [*c]const u8) void {
    free(@as(?*anyopaque, @ptrCast(S.*.endpoint)));
    S.*.endpoint = if (ep != null) strdup(ep) else null;
}
pub export fn a12_state_iostat(S: [*c]struct_a12_state) struct_a12_iostat {
    return S.*.stats;
}
pub export fn a12_request_dynamic_resource(S: [*c]struct_a12_state, ident_pubk: [*c]u8, prefer_tunnel: bool, request_reply: ?*const fn ([*c]struct_a12_state, struct_a12_dynreq, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) bool {
    if ((@as(c_int, @intFromBool(S.*.pending_dynamic.active)) != 0) or (S.*.remote_mode != ROLE_DIR)) {
        return false;
    }
    S.*.pending_dynamic.active = true;
    S.*.pending_dynamic.closure = request_reply;
    S.*.pending_dynamic.tag = tag;
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.pending_dynamic.req_key[0]))))), @as(?*const anyopaque, @ptrCast(ident_pubk)), 32);
    if (S.*.opts.*.local_role != ROLE_SINK) return true;
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_DIROPEN)))));
    arcan_random(@as([*c]u8, @ptrCast(@alignCast(&S.*.pending_dynamic.priv_key[0]))), 32);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[19])), @as(?*const anyopaque, @ptrCast(ident_pubk)), 32);
    outb[18] = @as(u8, @bitCast(@as(i8, @truncate(if (@as(c_int, @intFromBool(prefer_tunnel)) != 0) @as(c_int, 4) else @as(c_int, 2)))));
    x25519_public_key(@as([*c]u8, @ptrCast(@alignCast(&S.*.pending_dynamic.priv_key[0]))), &outb[52]);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:req_dynamic:mode=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "a12_request_dynamic_resource", @as(c_int, @bitCast(@as(c_uint, outb[18]))));
        }
        if (!false) break;
    }
    return true;
}
pub export fn a12_supply_dynamic_resource(S: [*c]struct_a12_state, r: struct_a12_dynreq) void {
    fill_diropened(S, r);
}
pub export fn a12_error_state(S: [*c]struct_a12_state) [*c]const u8 {
    if (!(S != null) or (@as(c_int, @bitCast(@as(c_uint, S.*.state))) != STATE_BROKEN)) return null;
    return @as([*c]u8, @ptrCast(@alignCast(&S.*.state_error_hint[0])));
}
pub export var a12_trace_targets: c_int = 0;
pub export var a12_trace_dst: ?*FILE = null;
pub export fn a12_trace_tag(S: [*c]struct_a12_state, tag: [*c]const u8) void {
    _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), 16, "%s", tag);
}
pub export fn a12int_group_tostr(group: c_int) [*c]const u8 {
    const ind: c_uint = i_log2(@as(u32, @bitCast(group)));
    if (@as(c_ulong, @bitCast(@as(c_ulong, ind))) >= (@sizeOf([13][*c]const u8) / @sizeOf([*c]const u8))) return "bad" else return groups[ind];
    return null;
}
pub const ptrdiff_t = c_long;
pub const max_align_t = extern struct {
    __clang_max_align_nonce1: c_longlong align(8) = std.mem.zeroes(c_longlong),
    __clang_max_align_nonce2: c_longdouble align(16) = std.mem.zeroes(c_longdouble),
};
// blake3_hasher + friends are now exposed by cImport (a12_int.h pulls them in
// transitively). Alias to the cimport type so pointer conversions succeed.
pub const blake3_hasher = c.blake3_hasher;
pub const blake3_hasher_init = c.blake3_hasher_init;
pub const blake3_hasher_init_keyed = c.blake3_hasher_init_keyed;
pub const blake3_hasher_init_derive_key = c.blake3_hasher_init_derive_key;
pub const blake3_hasher_update = c.blake3_hasher_update;
pub const blake3_hasher_finalize = c.blake3_hasher_finalize;
pub const blake3_hasher_finalize_seek = c.blake3_hasher_finalize_seek;
pub export fn unpack_u64(dst: [*c]u64, inbuf: [*c]u8) callconv(.c) void {
    dst.* = (((((((@as(u64, @bitCast(@as(c_ulong, inbuf[0]))) << @intCast(0)) | (@as(u64, @bitCast(@as(c_ulong, inbuf[1]))) << @intCast(8))) | (@as(u64, @bitCast(@as(c_ulong, inbuf[2]))) << @intCast(16))) | (@as(u64, @bitCast(@as(c_ulong, inbuf[3]))) << @intCast(24))) | (@as(u64, @bitCast(@as(c_ulong, inbuf[4]))) << @intCast(32))) | (@as(u64, @bitCast(@as(c_ulong, inbuf[5]))) << @intCast(40))) | (@as(u64, @bitCast(@as(c_ulong, inbuf[6]))) << @intCast(48))) | (@as(u64, @bitCast(@as(c_ulong, inbuf[7]))) << @intCast(56));
}
pub fn unpack_u32(dst: [*c]u32, inbuf: [*c]u8) callconv(.c) void {
    dst.* = @as(u32, @bitCast(@as(c_uint, @truncate((((@as(u64, @bitCast(@as(c_ulong, inbuf[0]))) << @intCast(0)) | (@as(u64, @bitCast(@as(c_ulong, inbuf[1]))) << @intCast(8))) | (@as(u64, @bitCast(@as(c_ulong, inbuf[2]))) << @intCast(16))) | (@as(u64, @bitCast(@as(c_ulong, inbuf[3]))) << @intCast(24))))));
}
pub fn unpack_u16(dst: [*c]u16, inbuf: [*c]u8) callconv(.c) void {
    dst.* = @as(u16, @bitCast(@as(c_ushort, @truncate((@as(u64, @bitCast(@as(c_ulong, inbuf[0]))) << @intCast(0)) | (@as(u64, @bitCast(@as(c_ulong, inbuf[1]))) << @intCast(8))))));
}
pub fn unpack_s16(dst: [*c]i16, inbuf: [*c]u8) callconv(.c) void {
    dst.* = @as(i16, @bitCast(@as(c_short, @truncate((@as(i64, @bitCast(@as(c_ulong, inbuf[0]))) << @intCast(0)) | (@as(i64, @bitCast(@as(c_ulong, inbuf[1]))) << @intCast(8))))));
}
pub export fn pack_u64(src: u64, outb: [*c]u8) callconv(.c) void {
    outb[0] = @as(u8, @truncate(src >> @intCast(0)));
    outb[1] = @as(u8, @truncate(src >> @intCast(8)));
    outb[2] = @as(u8, @truncate(src >> @intCast(16)));
    outb[3] = @as(u8, @truncate(src >> @intCast(24)));
    outb[4] = @as(u8, @truncate(src >> @intCast(32)));
    outb[5] = @as(u8, @truncate(src >> @intCast(40)));
    outb[6] = @as(u8, @truncate(src >> @intCast(48)));
    outb[7] = @as(u8, @truncate(src >> @intCast(56)));
}
pub fn pack_u32(src: u32, outb: [*c]u8) callconv(.c) void {
    outb[0] = @as(u8, @truncate(src >> @intCast(0)));
    outb[1] = @as(u8, @truncate(src >> @intCast(8)));
    outb[2] = @as(u8, @truncate(src >> @intCast(16)));
    outb[3] = @as(u8, @truncate(src >> @intCast(24)));
}
pub fn pack_u16(src: u16, outb: [*c]u8) callconv(.c) void {
    outb[0] = @as(u8, @truncate(@as(u16, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_uint, src))) >> @intCast(0)))))));
    outb[1] = @as(u8, @truncate(@as(u16, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_uint, src))) >> @intCast(8)))))));
}
pub fn pack_s16(src: i16, outb: [*c]u8) callconv(.c) void {
    outb[0] = @as(u8, @bitCast(@as(i8, @truncate(@as(i16, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_int, src))) >> @intCast(0)))))))));
    outb[1] = @as(u8, @bitCast(@as(i8, @truncate(@as(i16, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_int, src))) >> @intCast(8)))))))));
}
pub extern fn mlkem_keypair_derand(pk: [*c]u8, sk: [*c]u8, coins: [*c]const u8) c_int;
pub extern fn mlkem_keypair(pk: [*c]u8, sk: [*c]u8) c_int;
pub extern fn mlkem_enc_derand(ct: [*c]u8, ss: [*c]u8, pk: [*c]const u8, coins: [*c]const u8) c_int;
pub extern fn mlkem_enc(ct: [*c]u8, ss: [*c]u8, pk: [*c]const u8) c_int;
pub extern fn mlkem_dec(ss: [*c]u8, ct: [*c]const u8, sk: [*c]const u8) c_int;
pub const STATE_NOPACKET: c_int = 0;
pub const STATE_CONTROL_PACKET: c_int = 1;
pub const STATE_EVENT_PACKET: c_int = 2;
pub const STATE_AUDIO_PACKET: c_int = 3;
pub const STATE_VIDEO_PACKET: c_int = 4;
pub const STATE_BLOB_PACKET: c_int = 5;
pub const STATE_1STSRV_PACKET: c_int = 6;
pub const STATE_BROKEN: c_int = 7;
const enum_unnamed_77 = c_uint;
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
pub const enum_control_commands = c_uint;
pub const HELLO_MODE_NOASYM: c_int = 0;
pub const HELLO_MODE_REALPK: c_int = 1;
pub const HELLO_MODE_EPHEMPK: c_int = 2;
pub const enum_hello_mode = c_uint;
pub const CHANNEL_INACTIVE: c_int = 0;
pub const CHANNEL_SHMIF: c_int = 1;
pub const CHANNEL_RAW: c_int = 2;
pub const enum_channel_cfg = c_uint;
pub const POSTPROCESS_VIDEO_RGBA: c_int = 0;
pub const POSTPROCESS_VIDEO_RGB: c_int = 1;
pub const POSTPROCESS_VIDEO_RGB565: c_int = 2;
pub const POSTPROCESS_VIDEO_H264: c_int = 5;
pub const POSTPROCESS_VIDEO_TZSTD: c_int = 7;
pub const POSTPROCESS_VIDEO_DZSTD: c_int = 8;
pub const POSTPROCESS_VIDEO_ZSTD: c_int = 9;
const enum_unnamed_78 = c_uint;
pub export fn a12int_header_size(kind: c_int) usize {
    _ = blk: {
        _ = @sizeOf(c_int);
        break :blk blk_1: {
            break :blk_1 if (@as(c_ulong, @bitCast(@as(c_long, kind))) < ((@sizeOf([8]c_int) / @sizeOf(c_int)) / @as(usize, @intFromBool(!((@sizeOf([8]c_int) % @sizeOf(c_int)) != 0))))) {} else {
                __assert_fail("kind < COUNT_OF(header_sizes)", "src/a12/a12.c", @as(c_uint, @bitCast(@as(c_int, 65))), "size_t a12int_header_size(int)");
            };
        };
    };
    return @as(usize, @bitCast(@as(c_long, header_sizes[@as(c_uint, @intCast(kind))])));
}
pub const STREAM_FAIL_OUTDATED: c_int = 0;
pub const STREAM_FAIL_UNKNOWN: c_int = 1;
pub const STREAM_FAIL_ALREADY_KNOWN: c_int = 2;
const enum_unnamed_79 = c_uint;
pub export fn a12int_stream_fail(S: [*c]struct_a12_state, ch: u8, id: u32, fail: c_int) void {
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_CANCELSTREAM)))));
    outb[16] = ch;
    pack_u32(id, &outb[18]);
    outb[22] = @as(u8, @bitCast(@as(i8, @truncate(fail))));
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub export fn a12int_stream_ack(S: [*c]struct_a12_state, ch: u8, id: u32) void {
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_PING)))));
    outb[16] = ch;
    pack_u32(id, &outb[18]);
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DEBUG) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:ack=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DEBUG), "a12int_stream_ack", id);
        }
        if (!false) break;
    }
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub export fn a12int_append_out(S: [*c]struct_a12_state, @"type": u8, out: [*c]const u8, out_sz: usize, prepend: [*c]u8, prepend_sz: usize) callconv(.c) void {
    if (@as(c_int, @bitCast(@as(c_uint, S.*.state))) == STATE_BROKEN) return;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:type=%d:size=%zu:prepend_size=%zu:ofs=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "a12int_append_out", @as(c_int, @bitCast(@as(c_uint, @"type"))), out_sz, prepend_sz, S.*.buf_ofs);
        }
        if (!false) break;
    }
    const required: usize = (((S.*.buf_ofs +% @as(usize, @bitCast(@as(c_long, header_sizes[STATE_NOPACKET])))) +% out_sz) +% prepend_sz) +% 1;
    S.*.bufs[S.*.buf_ind] = grow_array(S, S.*.bufs[S.*.buf_ind], &S.*.buf_sz[S.*.buf_ind], required, @as(c_int, @bitCast(@as(c_uint, S.*.buf_ind))));
    if (S.*.buf_sz[S.*.buf_ind] < required) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:realloc failed: size (%zu) vs required (%zu)\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12int_append_out", S.*.buf_sz[S.*.buf_ind], required);
            }
            if (!false) break;
        }
        fail_state(S, "buffer-out alloc");
        return;
    }
    const dst: [*c]u8 = S.*.bufs[S.*.buf_ind];
    const mac_pos: usize = S.*.buf_ofs;
    S.*.buf_ofs +%= 16;
    const data_pos: usize = S.*.buf_ofs;
    pack_u64(blk: {
        const ref = &S.*.current_seqnr;
        const tmp = ref.*;
        ref.* +%= 1;
        break :blk tmp;
    }, &dst[S.*.buf_ofs]);
    S.*.buf_ofs +%= 8;
    dst[blk: {
        const ref = &S.*.buf_ofs;
        const tmp = ref.*;
        ref.* +%= 1;
        break :blk tmp;
    }] = @"type";
    if (prepend_sz != 0) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(&dst[S.*.buf_ofs])), @as(?*const anyopaque, @ptrCast(prepend)), prepend_sz);
        S.*.buf_ofs +%= prepend_sz;
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(&dst[S.*.buf_ofs])), @as(?*const anyopaque, @ptrCast(out)), out_sz);
    S.*.buf_ofs +%= out_sz;
    const used: usize = S.*.buf_ofs -% data_pos;
    var mac_sz: usize = 16;
    if (((S.*.authentic != AUTH_FULL_PK) and !S.*.server) and !S.*.cl_firstout) {
        mac_sz >>= @intCast(1);
        arcan_random(&dst[mac_sz], mac_sz);
        S.*.cl_firstout = @as(c_int, 1) != 0;
        chacha_set_nonce(chacha_cast(S.*.dec_state), &dst[mac_sz]);
        chacha_set_nonce(chacha_cast(S.*.enc_state), &dst[mac_sz]);
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=cipher:status=init_nonce\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "a12int_append_out");
            }
            if (!false) break;
        }
        trace_crypto_key(S, S.*.server, "nonce", &dst[mac_sz], mac_sz);
        blake3_hasher_update(&S.*.out_mac, @as(?*const anyopaque, @ptrCast(&dst[mac_sz])), mac_sz);
    }
    chacha_apply(chacha_cast(S.*.enc_state), &dst[data_pos], used);
    blake3_hasher_update(&S.*.out_mac, @as(?*const anyopaque, @ptrCast(&dst[data_pos])), used);
    blake3_hasher_finalize(&S.*.out_mac, &dst[mac_pos], mac_sz);
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=mac_enc:position=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "a12int_append_out", S.*.out_mac.counter);
        }
        if (!false) break;
    }
    trace_crypto_key(S, S.*.server, "mac_enc", &dst[mac_pos], mac_sz);
    S.*.stats.b_out +%= out_sz +% prepend_sz;
    if (S.*.opts.*.sink != null) {
        if (!S.*.opts.*.sink.?(dst, S.*.buf_ofs, S.*.opts.*.sink_tag)) {
            fail_state(S, "no-sink handler");
        }
        S.*.buf_ofs = 0;
    }
    if ((@as(c_int, @intFromBool(S.*.keys.own_rekey)) != 0) and (!S.*.server or ((@as(c_int, @intFromBool(S.*.server)) != 0) and (S.*.keys.rekey_base_count != 0)))) {
        if (S.*.keys.rekey_base_count != 0) {
            if (S.*.keys.rekey_count > (out_sz +% prepend_sz)) {
                S.*.keys.rekey_count -%= out_sz +% prepend_sz;
                return;
            }
        }
        S.*.keys.rekey_count = S.*.keys.rekey_base_count;
        a12int_issue_rekey(S);
    }
}
pub export fn a12int_step_vstream(S: [*c]struct_a12_state, id: u32) callconv(.c) void {
    _ = id;
    const slot: usize = S.*.congestion_stats.pending;
    if (S.*.congestion_stats.pending < 7) {
        S.*.congestion_stats.pending +%= 1;
    }
    S.*.congestion_stats.frame_window[slot] = @as(u32, @bitCast(@as(c_uint, @truncate(blk: {
        const ref = &S.*.out_stream;
        const tmp = ref.*;
        ref.* +%= 1;
        break :blk tmp;
    }))));
}
pub export fn a12int_set_directory(S: [*c]struct_a12_state, M: [*c]struct_appl_meta) callconv(.c) void {
    var cur: [*c]struct_appl_meta = M;
    var updated: bool = false;
    while ((cur != null) and (S.*.directory != null)) {
        const C: [*c]struct_appl_meta = find_entry(S, cur);
        if (!(C != null)) {
            updated = true;
            dirstate_item(S, cur);
        } else if (memcmp(@as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&C.*.hash[0]))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&cur.*.hash[0]))))), 4) != 0) {
            updated = true;
            dirstate_item(S, cur);
        }
        cur = cur.*.next;
    }
    if (updated) {
        var outb: [128]u8 = [1]u8{0} ++ [1]u8{std.mem.zeroes(u8)} ** 127;
        _ = memset(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&outb[0]))))), '\x00', 128);
        build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_DIRSTATE)))));
        a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    }
    var C: [*c]struct_appl_meta = S.*.directory;
    while (C != null) {
        const old: [*c]struct_appl_meta = C;
        free(@as(?*anyopaque, @ptrCast(C.*.buf)));
        C = C.*.next;
        free(@as(?*anyopaque, @ptrCast(old)));
    }
    S.*.directory = M;
}
pub export fn a12int_notify_dynamic_resource(S: [*c]struct_a12_state, petname: [*c]const u8, kpub: [*c]u8, role: u8, addstate: u8, ns: u16) callconv(.c) void {
    if (!S.*.notify_dynamic) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:ignore_no_dynamic\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "a12int_notify_dynamic_resource");
            }
            if (!false) break;
        }
        return;
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:dynamic:forward:name=%s:role=%d:added=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "a12int_notify_dynamic_resource", petname, @as(c_int, @bitCast(@as(c_uint, role))), @as(c_int, @bitCast(@as(c_uint, addstate))));
        }
        if (!false) break;
    }
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_DIRDISCOVER)))));
    outb[18] = role;
    outb[19] = addstate;
    pack_u16(ns, &outb[48]);
    _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&outb[20]))), 16, "%s", petname);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[36])), @as(?*const anyopaque, @ptrCast(kpub)), 32);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub export fn a12int_get_directory(S: [*c]struct_a12_state, clk: [*c]u64) callconv(.c) [*c]struct_appl_meta {
    if (clk != null) {
        clk.* = S.*.directory_clk;
    }
    return S.*.directory;
}
pub export fn a12int_request_dirlist(S: [*c]struct_a12_state, notify: bool) callconv(.c) void {
    if (!(S != null) or (S.*.cookie != @as(c_uint, 4277009102))) {
        return;
    }
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_DIRLIST)))));
    outb[18] = @as(u8, @intFromBool(notify));
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:request_list\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "a12int_request_dirlist");
        }
        if (!false) break;
    }
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub extern fn arcan_timemillis(...) c_ulonglong;
pub extern fn arcan_random(dst: [*c]u8, ntc: usize) void;
pub extern fn a12int_mmap(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fildes: c_int, off: off_t) ?*anyopaque;
pub extern fn a12int_munmap(addr: ?*anyopaque, len: usize) c_int;
pub extern fn a12int_dupfd(fd: c_int) c_int;
pub extern fn a12int_execve(path: [*c]const u8, argv: [*c]const [*c]u8, env: [*c]const [*c]u8) void;
pub extern fn a12int_buffer_format(method: c_int) bool;
pub extern fn a12int_vframe_setup(S: [*c]struct_a12_state, ch: ?*struct_a12_channel, dst: [*c]struct_video_frame, method: c_int) bool;
pub extern fn a12int_decode_drop(S: [*c]struct_a12_state, chid: c_int, failed: bool) void;
pub extern fn a12int_decode_vbuffer(S: [*c]struct_a12_state, ch: ?*struct_a12_channel, [*c]struct_video_frame, [*c]struct_arcan_shmif_cont) void;
pub extern fn a12int_unpack_vbuffer(S: [*c]struct_a12_state, cvf: [*c]struct_video_frame, cont: [*c]struct_arcan_shmif_cont) void;
pub extern fn a12int_encode_rgb565(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_rgb(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_rgba(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_dpng(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_h264(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_tz(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_dzstd(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_ztz(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_passthrough(S: [*c]struct_a12_state, vb: ?*struct_shmifsrv_vbuffer, opts: struct_a12_vframe_opts, sid: u32, x: usize, y: usize, w: usize, h: usize, chunk_sz: usize, chid: c_int) void;
pub extern fn a12int_encode_drop(S: [*c]struct_a12_state, chid: c_int, failed: bool) void;
pub extern fn a12int_encode_araw(S: [*c]struct_a12_state, chid: u8, buf: [*c]shmif_asample, n_samples: u16, cfg: struct_a12_aframe_cfg, opts: struct_a12_aframe_opts, chunk_sz: usize) void;
pub const ARCAN_MEM_VBUFFER: c_int = 1;
pub const ARCAN_MEM_VSTRUCT: c_int = 2;
pub const ARCAN_MEM_EXTSTRUCT: c_int = 3;
pub const ARCAN_MEM_ABUFFER: c_int = 4;
pub const ARCAN_MEM_STRINGBUF: c_int = 5;
pub const ARCAN_MEM_SHARED: c_int = 6;
pub const ARCAN_MEM_VTAG: c_int = 7;
pub const ARCAN_MEM_ATAG: c_int = 8;
pub const ARCAN_MEM_BINDING: c_int = 9;
pub const ARCAN_MEM_MODELDATA: c_int = 10;
pub const ARCAN_MEM_THREADCTX: c_int = 11;
pub const ARCAN_MEM_ENDMARKER: c_int = 12;
pub const enum_arcan_memtypes = c_uint;
pub const ARCAN_MEM_BZERO: c_int = 1;
pub const ARCAN_MEM_TEMPORARY: c_int = 2;
pub const ARCAN_MEM_EXEC: c_int = 4;
pub const ARCAN_MEM_NONFATAL: c_int = 8;
pub const ARCAN_MEM_READONLY: c_int = 16;
pub const ARCAN_MEM_SENSITIVE: c_int = 32;
pub const ARCAN_MEM_LOCKACCESS: c_int = 33;
pub const enum_arcan_memhint = c_uint;
pub const ARCAN_MEMALIGN_NATURAL: c_int = 0;
pub const ARCAN_MEMALIGN_PAGE: c_int = 1;
pub const ARCAN_MEMALIGN_SIMD: c_int = 2;
pub const enum_arcan_memalign = c_uint;
pub extern fn arcan_alloc_mem(usize, enum_arcan_memtypes, enum_arcan_memhint, enum_arcan_memalign) ?*anyopaque;
pub extern fn arcan_mem_init(...) void;
const union_unnamed_80 = extern union {
    data: [*c][*c]u8,
    cdata: [*c]?*anyopaque,
};
pub const struct_arcan_strarr = extern struct {
    count: usize = std.mem.zeroes(usize),
    limit: usize = std.mem.zeroes(usize),
    unnamed_0: union_unnamed_80 = std.mem.zeroes(union_unnamed_80),
};
pub extern fn arcan_mem_growarr([*c]struct_arcan_strarr) void;
pub extern fn arcan_mem_freearr([*c]struct_arcan_strarr) void;
pub extern fn arcan_mem_free(src: ?*anyopaque) void;
pub extern fn arcan_mem_lock(?*anyopaque) void;
pub extern fn arcan_mem_unlock(?*anyopaque) void;
pub extern fn arcan_mem_tick(...) void;
pub extern fn arcan_alloc_fillmem(?*const anyopaque, usize, enum_arcan_memtypes, enum_arcan_memhint, enum_arcan_memalign) ?*anyopaque;
pub const counter_pos: usize = 12;
pub fn chacha_block(ctx: [*c]struct_chacha_ctx, output: [*c]u32) callconv(.c) void {
    const nonce: [*c]u32 = &ctx.*.schedule[counter_pos];
    var i: c_int = ctx.*.iterations;
    _ = memcpy(@as(?*anyopaque, @ptrCast(output)), @as(?*const anyopaque, @ptrCast(@as([*c]u32, @ptrCast(@alignCast(&ctx.*.schedule[0]))))), @sizeOf([16]u32));
    while ((blk: {
        const ref = &i;
        const tmp = ref.*;
        ref.* -= 1;
        break :blk tmp;
    }) != 0) {
        output[0] +%= output[4];
        output[12] = ((output[12] ^ output[0]) << @intCast(16)) | ((output[12] ^ output[0]) >> @intCast(32 - 16));
        output[8] +%= output[12];
        output[4] = ((output[4] ^ output[8]) << @intCast(12)) | ((output[4] ^ output[8]) >> @intCast(32 - 12));
        output[0] +%= output[4];
        output[12] = ((output[12] ^ output[0]) << @intCast(8)) | ((output[12] ^ output[0]) >> @intCast(32 - 8));
        output[8] +%= output[12];
        output[4] = ((output[4] ^ output[8]) << @intCast(7)) | ((output[4] ^ output[8]) >> @intCast(32 - 7));
        output[1] +%= output[5];
        output[13] = ((output[13] ^ output[1]) << @intCast(16)) | ((output[13] ^ output[1]) >> @intCast(32 - 16));
        output[9] +%= output[13];
        output[5] = ((output[5] ^ output[9]) << @intCast(12)) | ((output[5] ^ output[9]) >> @intCast(32 - 12));
        output[1] +%= output[5];
        output[13] = ((output[13] ^ output[1]) << @intCast(8)) | ((output[13] ^ output[1]) >> @intCast(32 - 8));
        output[9] +%= output[13];
        output[5] = ((output[5] ^ output[9]) << @intCast(7)) | ((output[5] ^ output[9]) >> @intCast(32 - 7));
        output[2] +%= output[6];
        output[14] = ((output[14] ^ output[2]) << @intCast(16)) | ((output[14] ^ output[2]) >> @intCast(32 - 16));
        output[10] +%= output[14];
        output[6] = ((output[6] ^ output[10]) << @intCast(12)) | ((output[6] ^ output[10]) >> @intCast(32 - 12));
        output[2] +%= output[6];
        output[14] = ((output[14] ^ output[2]) << @intCast(8)) | ((output[14] ^ output[2]) >> @intCast(32 - 8));
        output[10] +%= output[14];
        output[6] = ((output[6] ^ output[10]) << @intCast(7)) | ((output[6] ^ output[10]) >> @intCast(32 - 7));
        output[3] +%= output[7];
        output[15] = ((output[15] ^ output[3]) << @intCast(16)) | ((output[15] ^ output[3]) >> @intCast(32 - 16));
        output[11] +%= output[15];
        output[7] = ((output[7] ^ output[11]) << @intCast(12)) | ((output[7] ^ output[11]) >> @intCast(32 - 12));
        output[3] +%= output[7];
        output[15] = ((output[15] ^ output[3]) << @intCast(8)) | ((output[15] ^ output[3]) >> @intCast(32 - 8));
        output[11] +%= output[15];
        output[7] = ((output[7] ^ output[11]) << @intCast(7)) | ((output[7] ^ output[11]) >> @intCast(32 - 7));
        output[0] +%= output[5];
        output[15] = ((output[15] ^ output[0]) << @intCast(16)) | ((output[15] ^ output[0]) >> @intCast(32 - 16));
        output[10] +%= output[15];
        output[5] = ((output[5] ^ output[10]) << @intCast(12)) | ((output[5] ^ output[10]) >> @intCast(32 - 12));
        output[0] +%= output[5];
        output[15] = ((output[15] ^ output[0]) << @intCast(8)) | ((output[15] ^ output[0]) >> @intCast(32 - 8));
        output[10] +%= output[15];
        output[5] = ((output[5] ^ output[10]) << @intCast(7)) | ((output[5] ^ output[10]) >> @intCast(32 - 7));
        output[1] +%= output[6];
        output[12] = ((output[12] ^ output[1]) << @intCast(16)) | ((output[12] ^ output[1]) >> @intCast(32 - 16));
        output[11] +%= output[12];
        output[6] = ((output[6] ^ output[11]) << @intCast(12)) | ((output[6] ^ output[11]) >> @intCast(32 - 12));
        output[1] +%= output[6];
        output[12] = ((output[12] ^ output[1]) << @intCast(8)) | ((output[12] ^ output[1]) >> @intCast(32 - 8));
        output[11] +%= output[12];
        output[6] = ((output[6] ^ output[11]) << @intCast(7)) | ((output[6] ^ output[11]) >> @intCast(32 - 7));
        output[2] +%= output[7];
        output[13] = ((output[13] ^ output[2]) << @intCast(16)) | ((output[13] ^ output[2]) >> @intCast(32 - 16));
        output[8] +%= output[13];
        output[7] = ((output[7] ^ output[8]) << @intCast(12)) | ((output[7] ^ output[8]) >> @intCast(32 - 12));
        output[2] +%= output[7];
        output[13] = ((output[13] ^ output[2]) << @intCast(8)) | ((output[13] ^ output[2]) >> @intCast(32 - 8));
        output[8] +%= output[13];
        output[7] = ((output[7] ^ output[8]) << @intCast(7)) | ((output[7] ^ output[8]) >> @intCast(32 - 7));
        output[3] +%= output[4];
        output[14] = ((output[14] ^ output[3]) << @intCast(16)) | ((output[14] ^ output[3]) >> @intCast(32 - 16));
        output[9] +%= output[14];
        output[4] = ((output[4] ^ output[9]) << @intCast(12)) | ((output[4] ^ output[9]) >> @intCast(32 - 12));
        output[3] +%= output[4];
        output[14] = ((output[14] ^ output[3]) << @intCast(8)) | ((output[14] ^ output[3]) >> @intCast(32 - 8));
        output[9] +%= output[14];
        output[4] = ((output[4] ^ output[9]) << @intCast(7)) | ((output[4] ^ output[9]) >> @intCast(32 - 7));
    }
    {
        i = 0;
        while (i < 16) : (i += 1) {
            const result: u32 = (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk output + @as(usize, @intCast(tmp)) else break :blk output - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* +% ctx.*.schedule[@as(c_uint, @intCast(i))];
            @as([*c]u8, @ptrCast(@alignCast(output + @as(usize, @bitCast(@as(isize, @intCast(i)))))))[0] = @as(u8, @truncate(result & 0xFF));
            @as([*c]u8, @ptrCast(@alignCast(output + @as(usize, @bitCast(@as(isize, @intCast(i)))))))[1] = @as(u8, @truncate((result >> @intCast(8)) & 0xFF));
            @as([*c]u8, @ptrCast(@alignCast(output + @as(usize, @bitCast(@as(isize, @intCast(i)))))))[2] = @as(u8, @truncate((result >> @intCast(16)) & 0xFF));
            @as([*c]u8, @ptrCast(@alignCast(output + @as(usize, @bitCast(@as(isize, @intCast(i)))))))[3] = @as(u8, @truncate((result >> @intCast(24)) & 0xFF));
        }
    }
    if ((!((blk: {
        const ref = &nonce[0];
        ref.* +%= 1;
        break :blk ref.*;
    }) != 0) and !((blk: {
        const ref = &nonce[1];
        ref.* +%= 1;
        break :blk ref.*;
    }) != 0)) and !((blk: {
        const ref = &nonce[2];
        ref.* +%= 1;
        break :blk ref.*;
    }) != 0)) {
        nonce[3] +%= 1;
    }
    ctx.*.pos = 0;
}
pub fn chacha_set_nonce(ctx: [*c]struct_chacha_ctx, nonce: [*c]u8) callconv(.c) void {
    ctx.*.schedule[14] = (@as(u32, @bitCast(@as(c_uint, nonce[0]))) | (@as(u32, @bitCast(@as(c_uint, nonce[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, nonce[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, nonce[3]))) << @intCast(24));
    ctx.*.schedule[15] = (@as(u32, @bitCast(@as(c_uint, (nonce + 4)[0]))) | (@as(u32, @bitCast(@as(c_uint, (nonce + 4)[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (nonce + 4)[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (nonce + 4)[3]))) << @intCast(24));
    chacha_block(ctx, @as([*c]u32, @ptrCast(@alignCast(&ctx.*.keystream.u32[0]))));
}
pub fn chacha_setup(ctx: [*c]struct_chacha_ctx, key: [*c]const u8, length: usize, counter: u64, rounds: u8) callconv(.c) void {
    const constants: [*c]const u8 = if (length == 32) "expand 32-byte k" else "expand 16-byte k";
    ctx.*.iterations = @as(c_int, @bitCast(@as(c_uint, rounds))) >> @intCast(1);
    ctx.*.schedule[0] = (@as(u32, @bitCast(@as(c_uint, constants[0]))) | (@as(u32, @bitCast(@as(c_uint, constants[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, constants[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, constants[3]))) << @intCast(24));
    ctx.*.schedule[1] = (@as(u32, @bitCast(@as(c_uint, (constants + 4)[0]))) | (@as(u32, @bitCast(@as(c_uint, (constants + 4)[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (constants + 4)[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (constants + 4)[3]))) << @intCast(24));
    ctx.*.schedule[2] = (@as(u32, @bitCast(@as(c_uint, (constants + 8)[0]))) | (@as(u32, @bitCast(@as(c_uint, (constants + 8)[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (constants + 8)[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (constants + 8)[3]))) << @intCast(24));
    ctx.*.schedule[3] = (@as(u32, @bitCast(@as(c_uint, (constants + 12)[0]))) | (@as(u32, @bitCast(@as(c_uint, (constants + 12)[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (constants + 12)[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (constants + 12)[3]))) << @intCast(24));
    ctx.*.schedule[4] = (@as(u32, @bitCast(@as(c_uint, key[0]))) | (@as(u32, @bitCast(@as(c_uint, key[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, key[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, key[3]))) << @intCast(24));
    ctx.*.schedule[5] = (@as(u32, @bitCast(@as(c_uint, (key + 4)[0]))) | (@as(u32, @bitCast(@as(c_uint, (key + 4)[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (key + 4)[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (key + 4)[3]))) << @intCast(24));
    ctx.*.schedule[6] = (@as(u32, @bitCast(@as(c_uint, (key + 8)[0]))) | (@as(u32, @bitCast(@as(c_uint, (key + 8)[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (key + 8)[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (key + 8)[3]))) << @intCast(24));
    ctx.*.schedule[7] = (@as(u32, @bitCast(@as(c_uint, (key + 12)[0]))) | (@as(u32, @bitCast(@as(c_uint, (key + 12)[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (key + 12)[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (key + 12)[3]))) << @intCast(24));
    ctx.*.schedule[8] = (@as(u32, @bitCast(@as(c_uint, (key + (16 % length))[0]))) | (@as(u32, @bitCast(@as(c_uint, (key + (16 % length))[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (key + (16 % length))[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (key + (16 % length))[3]))) << @intCast(24));
    ctx.*.schedule[9] = (@as(u32, @bitCast(@as(c_uint, (key + (20 % length))[0]))) | (@as(u32, @bitCast(@as(c_uint, (key + (20 % length))[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (key + (20 % length))[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (key + (20 % length))[3]))) << @intCast(24));
    ctx.*.schedule[10] = (@as(u32, @bitCast(@as(c_uint, (key + (24 % length))[0]))) | (@as(u32, @bitCast(@as(c_uint, (key + (24 % length))[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (key + (24 % length))[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (key + (24 % length))[3]))) << @intCast(24));
    ctx.*.schedule[11] = (@as(u32, @bitCast(@as(c_uint, (key + (28 % length))[0]))) | (@as(u32, @bitCast(@as(c_uint, (key + (28 % length))[1]))) << @intCast(8))) | (@as(u32, @bitCast(@as(c_uint, (key + (28 % length))[2]))) << @intCast(16)) | (@as(u32, @bitCast(@as(c_uint, (key + (28 % length))[3]))) << @intCast(24));
    ctx.*.schedule[12] = @as(u32, @bitCast(@as(c_uint, @truncate(counter & 0xFFFFFFFF))));
    ctx.*.schedule[13] = @as(u32, @bitCast(@as(c_uint, @truncate(counter >> @intCast(32)))));
}
pub fn chacha_counter_set(ctx: [*c]struct_chacha_ctx, counter: u64) callconv(.c) void {
    ctx.*.schedule[12] = @as(u32, @bitCast(@as(c_uint, @truncate(counter & 0xFFFFFFFF))));
    ctx.*.schedule[13] = @as(u32, @bitCast(@as(c_uint, @truncate(counter >> @intCast(32)))));
    chacha_block(ctx, @as([*c]u32, @ptrCast(@alignCast(&ctx.*.keystream.u32[0]))));
}
pub fn chacha_apply(ctx: [*c]struct_chacha_ctx, buf: [*c]u8, length: usize) callconv(.c) void {
    if (!(length != 0)) return;
    var ofs: usize = 0;
    while (ofs < length) {
        if (ctx.*.pos == 64) {
            chacha_block(ctx, @as([*c]u32, @ptrCast(@alignCast(&ctx.*.keystream.u32[0]))));
        }
        var nib: usize = 64 -% ctx.*.pos;
        while ((nib != 0) and (ofs < length)) {
            buf[ofs] ^= @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, ctx.*.keystream.u8[blk: {
                const ref = &ctx.*.pos;
                const tmp = ref.*;
                ref.* +%= 1;
                break :blk tmp;
            }])))))));
            _ = blk: {
                nib -%= 1;
                break :blk blk_1: {
                    const ref = &ofs;
                    const tmp = ref.*;
                    ref.* +%= 1;
                    break :blk_1 tmp;
                };
            };
        }
    }
}
pub extern fn x25519_private_key(secret: [*c]u8) void;
pub extern fn x25519_public_key(secret: [*c]const u8, public: [*c]u8) void;
pub extern fn x25519_shared_secret(secret_out: [*c]u8, secret: [*c]const u8, ext_pub: [*c]const u8) c_int;
pub extern fn crypto_verify16(a: [*c]const u8, b: [*c]const u8) c_int;
pub extern fn crypto_verify32(a: [*c]const u8, b: [*c]const u8) c_int;
pub extern fn crypto_verify64(a: [*c]const u8, b: [*c]const u8) c_int;
pub extern fn crypto_wipe(secret: ?*anyopaque, size: usize) void;
pub extern fn crypto_aead_lock(cipher_text: [*c]u8, mac: [*c]u8, key: [*c]const u8, nonce: [*c]const u8, ad: [*c]const u8, ad_size: usize, plain_text: [*c]const u8, text_size: usize) void;
pub extern fn crypto_aead_unlock(plain_text: [*c]u8, mac: [*c]const u8, key: [*c]const u8, nonce: [*c]const u8, ad: [*c]const u8, ad_size: usize, cipher_text: [*c]const u8, text_size: usize) c_int;
pub const crypto_aead_ctx = extern struct {
    counter: u64 = std.mem.zeroes(u64),
    key: [32]u8 = std.mem.zeroes([32]u8),
    nonce: [8]u8 = std.mem.zeroes([8]u8),
};
pub extern fn crypto_aead_init_x(ctx: [*c]crypto_aead_ctx, key: [*c]const u8, nonce: [*c]const u8) void;
pub extern fn crypto_aead_init_djb(ctx: [*c]crypto_aead_ctx, key: [*c]const u8, nonce: [*c]const u8) void;
pub extern fn crypto_aead_init_ietf(ctx: [*c]crypto_aead_ctx, key: [*c]const u8, nonce: [*c]const u8) void;
pub extern fn crypto_aead_write(ctx: [*c]crypto_aead_ctx, cipher_text: [*c]u8, mac: [*c]u8, ad: [*c]const u8, ad_size: usize, plain_text: [*c]const u8, text_size: usize) void;
pub extern fn crypto_aead_read(ctx: [*c]crypto_aead_ctx, plain_text: [*c]u8, mac: [*c]const u8, ad: [*c]const u8, ad_size: usize, cipher_text: [*c]const u8, text_size: usize) c_int;
pub extern fn crypto_blake2b(hash: [*c]u8, hash_size: usize, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_blake2b_keyed(hash: [*c]u8, hash_size: usize, key: [*c]const u8, key_size: usize, message: [*c]const u8, message_size: usize) void;
pub const crypto_blake2b_ctx = extern struct {
    hash: [8]u64 = std.mem.zeroes([8]u64),
    input_offset: [2]u64 = std.mem.zeroes([2]u64),
    input: [16]u64 = std.mem.zeroes([16]u64),
    input_idx: usize = std.mem.zeroes(usize),
    hash_size: usize = std.mem.zeroes(usize),
};
pub extern fn crypto_blake2b_init(ctx: [*c]crypto_blake2b_ctx, hash_size: usize) void;
pub extern fn crypto_blake2b_keyed_init(ctx: [*c]crypto_blake2b_ctx, hash_size: usize, key: [*c]const u8, key_size: usize) void;
pub extern fn crypto_blake2b_update(ctx: [*c]crypto_blake2b_ctx, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_blake2b_final(ctx: [*c]crypto_blake2b_ctx, hash: [*c]u8) void;
pub const crypto_argon2_config = extern struct {
    algorithm: u32 = std.mem.zeroes(u32),
    nb_blocks: u32 = std.mem.zeroes(u32),
    nb_passes: u32 = std.mem.zeroes(u32),
    nb_lanes: u32 = std.mem.zeroes(u32),
};
pub const crypto_argon2_inputs = extern struct {
    pass: [*c]const u8 = std.mem.zeroes([*c]const u8),
    salt: [*c]const u8 = std.mem.zeroes([*c]const u8),
    pass_size: u32 = std.mem.zeroes(u32),
    salt_size: u32 = std.mem.zeroes(u32),
};
pub const crypto_argon2_extras = extern struct {
    key: [*c]const u8 = std.mem.zeroes([*c]const u8),
    ad: [*c]const u8 = std.mem.zeroes([*c]const u8),
    key_size: u32 = std.mem.zeroes(u32),
    ad_size: u32 = std.mem.zeroes(u32),
};
pub extern const crypto_argon2_no_extras: crypto_argon2_extras;
pub extern fn crypto_argon2(hash: [*c]u8, hash_size: u32, work_area: ?*anyopaque, config: crypto_argon2_config, inputs: crypto_argon2_inputs, extras: crypto_argon2_extras) void;
pub extern fn crypto_x25519_public_key(public_key: [*c]u8, secret_key: [*c]const u8) void;
pub extern fn crypto_x25519(raw_shared_secret: [*c]u8, your_secret_key: [*c]const u8, their_public_key: [*c]const u8) void;
pub extern fn crypto_x25519_to_eddsa(eddsa: [*c]u8, x25519: [*c]const u8) void;
pub extern fn crypto_x25519_inverse(blind_salt: [*c]u8, private_key: [*c]const u8, curve_point: [*c]const u8) void;
pub extern fn crypto_x25519_dirty_small(pk: [*c]u8, sk: [*c]const u8) void;
pub extern fn crypto_x25519_dirty_fast(pk: [*c]u8, sk: [*c]const u8) void;
pub extern fn crypto_eddsa_key_pair(secret_key: [*c]u8, public_key: [*c]u8, seed: [*c]u8) void;
pub extern fn crypto_eddsa_sign(signature: [*c]u8, secret_key: [*c]const u8, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_eddsa_check(signature: [*c]const u8, public_key: [*c]const u8, message: [*c]const u8, message_size: usize) c_int;
pub extern fn crypto_eddsa_to_x25519(x25519: [*c]u8, eddsa: [*c]const u8) void;
pub extern fn crypto_eddsa_trim_scalar(out: [*c]u8, in: [*c]const u8) void;
pub extern fn crypto_eddsa_reduce(reduced: [*c]u8, expanded: [*c]const u8) void;
pub extern fn crypto_eddsa_mul_add(r: [*c]u8, a: [*c]const u8, b: [*c]const u8, c: [*c]const u8) void;
pub extern fn crypto_eddsa_scalarbase(point: [*c]u8, scalar: [*c]const u8) void;
pub extern fn crypto_eddsa_check_equation(signature: [*c]const u8, public_key: [*c]const u8, h_ram: [*c]const u8) c_int;
pub extern fn crypto_chacha20_h(out: [*c]u8, key: [*c]const u8, in: [*c]const u8) void;
pub extern fn crypto_chacha20_djb(cipher_text: [*c]u8, plain_text: [*c]const u8, text_size: usize, key: [*c]const u8, nonce: [*c]const u8, ctr: u64) u64;
pub extern fn crypto_chacha20_ietf(cipher_text: [*c]u8, plain_text: [*c]const u8, text_size: usize, key: [*c]const u8, nonce: [*c]const u8, ctr: u32) u32;
pub extern fn crypto_chacha20_x(cipher_text: [*c]u8, plain_text: [*c]const u8, text_size: usize, key: [*c]const u8, nonce: [*c]const u8, ctr: u64) u64;
pub extern fn crypto_poly1305(mac: [*c]u8, message: [*c]const u8, message_size: usize, key: [*c]const u8) void;
pub const crypto_poly1305_ctx = extern struct {
    c: [16]u8 = std.mem.zeroes([16]u8),
    c_idx: usize = std.mem.zeroes(usize),
    r: [4]u32 = std.mem.zeroes([4]u32),
    pad: [4]u32 = std.mem.zeroes([4]u32),
    h: [5]u32 = std.mem.zeroes([5]u32),
};
pub extern fn crypto_poly1305_init(ctx: [*c]crypto_poly1305_ctx, key: [*c]const u8) void;
pub extern fn crypto_poly1305_update(ctx: [*c]crypto_poly1305_ctx, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_poly1305_final(ctx: [*c]crypto_poly1305_ctx, mac: [*c]u8) void;
pub extern fn crypto_elligator_map(curve: [*c]u8, hidden: [*c]const u8) void;
pub extern fn crypto_elligator_rev(hidden: [*c]u8, curve: [*c]const u8, tweak: u8) c_int;
pub extern fn crypto_elligator_key_pair(hidden: [*c]u8, secret_key: [*c]u8, seed: [*c]u8) void;
pub const crypto_sha512_ctx = extern struct {
    hash: [8]u64 = std.mem.zeroes([8]u64),
    input: [16]u64 = std.mem.zeroes([16]u64),
    input_size: [2]u64 = std.mem.zeroes([2]u64),
    input_idx: usize = std.mem.zeroes(usize),
};
pub const crypto_sha512_hmac_ctx = extern struct {
    key: [128]u8 = std.mem.zeroes([128]u8),
    ctx: crypto_sha512_ctx = std.mem.zeroes(crypto_sha512_ctx),
};
pub extern fn crypto_sha512_init(ctx: [*c]crypto_sha512_ctx) void;
pub extern fn crypto_sha512_update(ctx: [*c]crypto_sha512_ctx, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_sha512_final(ctx: [*c]crypto_sha512_ctx, hash: [*c]u8) void;
pub extern fn crypto_sha512(hash: [*c]u8, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_sha512_hmac_init(ctx: [*c]crypto_sha512_hmac_ctx, key: [*c]const u8, key_size: usize) void;
pub extern fn crypto_sha512_hmac_update(ctx: [*c]crypto_sha512_hmac_ctx, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_sha512_hmac_final(ctx: [*c]crypto_sha512_hmac_ctx, hmac: [*c]u8) void;
pub extern fn crypto_sha512_hmac(hmac: [*c]u8, key: [*c]const u8, key_size: usize, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_sha512_hkdf_expand(okm: [*c]u8, okm_size: usize, prk: [*c]const u8, prk_size: usize, info: [*c]const u8, info_size: usize) void;
pub extern fn crypto_sha512_hkdf(okm: [*c]u8, okm_size: usize, ikm: [*c]const u8, ikm_size: usize, salt: [*c]const u8, salt_size: usize, info: [*c]const u8, info_size: usize) void;
pub extern fn crypto_ed25519_key_pair(secret_key: [*c]u8, public_key: [*c]u8, seed: [*c]u8) void;
pub extern fn crypto_ed25519_sign(signature: [*c]u8, secret_key: [*c]const u8, message: [*c]const u8, message_size: usize) void;
pub extern fn crypto_ed25519_check(signature: [*c]const u8, public_key: [*c]const u8, message: [*c]const u8, message_size: usize) c_int;
pub extern fn crypto_ed25519_ph_sign(signature: [*c]u8, secret_key: [*c]const u8, message_hash: [*c]const u8) void;
pub extern fn crypto_ed25519_ph_check(signature: [*c]const u8, public_key: [*c]const u8, message_hash: [*c]const u8) c_int;
pub extern fn __errno_location() [*c]c_int;
pub extern var program_invocation_name: [*c]u8;
pub extern var program_invocation_short_name: [*c]u8;
pub const error_t = c_int;
pub extern fn ZSTD_versionNumber() c_uint;
pub extern fn ZSTD_versionString() [*c]const u8;
pub extern fn ZSTD_compress(dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, srcSize: usize, compressionLevel: c_int) usize;
pub extern fn ZSTD_decompress(dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, compressedSize: usize) usize;
pub extern fn ZSTD_getFrameContentSize(src: ?*const anyopaque, srcSize: usize) c_ulonglong;
pub extern fn ZSTD_getDecompressedSize(src: ?*const anyopaque, srcSize: usize) c_ulonglong;
pub extern fn ZSTD_findFrameCompressedSize(src: ?*const anyopaque, srcSize: usize) usize;
pub extern fn ZSTD_compressBound(srcSize: usize) usize;
pub extern fn ZSTD_isError(code: usize) c_uint;
pub extern fn ZSTD_getErrorName(code: usize) [*c]const u8;
pub extern fn ZSTD_minCLevel() c_int;
pub extern fn ZSTD_maxCLevel() c_int;
pub extern fn ZSTD_defaultCLevel() c_int;
pub const ZSTD_CCtx = struct_ZSTD_CCtx_s;
pub extern fn ZSTD_createCCtx() ?*ZSTD_CCtx;
pub extern fn ZSTD_freeCCtx(cctx: ?*ZSTD_CCtx) usize;
pub extern fn ZSTD_compressCCtx(cctx: ?*ZSTD_CCtx, dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, srcSize: usize, compressionLevel: c_int) usize;
pub const ZSTD_DCtx = struct_ZSTD_DCtx_s;
pub extern fn ZSTD_createDCtx() ?*ZSTD_DCtx;
pub extern fn ZSTD_freeDCtx(dctx: ?*ZSTD_DCtx) usize;
pub extern fn ZSTD_decompressDCtx(dctx: ?*ZSTD_DCtx, dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, srcSize: usize) usize;
pub const ZSTD_fast: c_int = 1;
pub const ZSTD_dfast: c_int = 2;
pub const ZSTD_greedy: c_int = 3;
pub const ZSTD_lazy: c_int = 4;
pub const ZSTD_lazy2: c_int = 5;
pub const ZSTD_btlazy2: c_int = 6;
pub const ZSTD_btopt: c_int = 7;
pub const ZSTD_btultra: c_int = 8;
pub const ZSTD_btultra2: c_int = 9;
pub const ZSTD_strategy = c_uint;
pub const ZSTD_c_compressionLevel: c_int = 100;
pub const ZSTD_c_windowLog: c_int = 101;
pub const ZSTD_c_hashLog: c_int = 102;
pub const ZSTD_c_chainLog: c_int = 103;
pub const ZSTD_c_searchLog: c_int = 104;
pub const ZSTD_c_minMatch: c_int = 105;
pub const ZSTD_c_targetLength: c_int = 106;
pub const ZSTD_c_strategy: c_int = 107;
pub const ZSTD_c_enableLongDistanceMatching: c_int = 160;
pub const ZSTD_c_ldmHashLog: c_int = 161;
pub const ZSTD_c_ldmMinMatch: c_int = 162;
pub const ZSTD_c_ldmBucketSizeLog: c_int = 163;
pub const ZSTD_c_ldmHashRateLog: c_int = 164;
pub const ZSTD_c_contentSizeFlag: c_int = 200;
pub const ZSTD_c_checksumFlag: c_int = 201;
pub const ZSTD_c_dictIDFlag: c_int = 202;
pub const ZSTD_c_nbWorkers: c_int = 400;
pub const ZSTD_c_jobSize: c_int = 401;
pub const ZSTD_c_overlapLog: c_int = 402;
pub const ZSTD_c_experimentalParam1: c_int = 500;
pub const ZSTD_c_experimentalParam2: c_int = 10;
pub const ZSTD_c_experimentalParam3: c_int = 1000;
pub const ZSTD_c_experimentalParam4: c_int = 1001;
pub const ZSTD_c_experimentalParam5: c_int = 1002;
pub const ZSTD_c_experimentalParam6: c_int = 1003;
pub const ZSTD_c_experimentalParam7: c_int = 1004;
pub const ZSTD_c_experimentalParam8: c_int = 1005;
pub const ZSTD_c_experimentalParam9: c_int = 1006;
pub const ZSTD_c_experimentalParam10: c_int = 1007;
pub const ZSTD_c_experimentalParam11: c_int = 1008;
pub const ZSTD_c_experimentalParam12: c_int = 1009;
pub const ZSTD_c_experimentalParam13: c_int = 1010;
pub const ZSTD_c_experimentalParam14: c_int = 1011;
pub const ZSTD_c_experimentalParam15: c_int = 1012;
pub const ZSTD_c_experimentalParam16: c_int = 1013;
pub const ZSTD_c_experimentalParam17: c_int = 1014;
pub const ZSTD_c_experimentalParam18: c_int = 1015;
pub const ZSTD_c_experimentalParam19: c_int = 1016;
pub const ZSTD_cParameter = c_uint;
pub const ZSTD_bounds = extern struct {
    @"error": usize = std.mem.zeroes(usize),
    lowerBound: c_int = std.mem.zeroes(c_int),
    upperBound: c_int = std.mem.zeroes(c_int),
};
pub extern fn ZSTD_cParam_getBounds(cParam: ZSTD_cParameter) ZSTD_bounds;
pub extern fn ZSTD_CCtx_setParameter(cctx: ?*ZSTD_CCtx, param: ZSTD_cParameter, value: c_int) usize;
pub extern fn ZSTD_CCtx_setPledgedSrcSize(cctx: ?*ZSTD_CCtx, pledgedSrcSize: c_ulonglong) usize;
pub const ZSTD_reset_session_only: c_int = 1;
pub const ZSTD_reset_parameters: c_int = 2;
pub const ZSTD_reset_session_and_parameters: c_int = 3;
pub const ZSTD_ResetDirective = c_uint;
pub extern fn ZSTD_CCtx_reset(cctx: ?*ZSTD_CCtx, reset: ZSTD_ResetDirective) usize;
pub extern fn ZSTD_compress2(cctx: ?*ZSTD_CCtx, dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, srcSize: usize) usize;
pub const ZSTD_d_windowLogMax: c_int = 100;
pub const ZSTD_d_experimentalParam1: c_int = 1000;
pub const ZSTD_d_experimentalParam2: c_int = 1001;
pub const ZSTD_d_experimentalParam3: c_int = 1002;
pub const ZSTD_d_experimentalParam4: c_int = 1003;
pub const ZSTD_d_experimentalParam5: c_int = 1004;
pub const ZSTD_d_experimentalParam6: c_int = 1005;
pub const ZSTD_dParameter = c_uint;
pub extern fn ZSTD_dParam_getBounds(dParam: ZSTD_dParameter) ZSTD_bounds;
pub extern fn ZSTD_DCtx_setParameter(dctx: ?*ZSTD_DCtx, param: ZSTD_dParameter, value: c_int) usize;
pub extern fn ZSTD_DCtx_reset(dctx: ?*ZSTD_DCtx, reset: ZSTD_ResetDirective) usize;
pub const struct_ZSTD_inBuffer_s = extern struct {
    src: ?*const anyopaque = std.mem.zeroes(?*const anyopaque),
    size: usize = std.mem.zeroes(usize),
    pos: usize = std.mem.zeroes(usize),
};
pub const ZSTD_inBuffer = struct_ZSTD_inBuffer_s;
pub const struct_ZSTD_outBuffer_s = extern struct {
    dst: ?*anyopaque = std.mem.zeroes(?*anyopaque),
    size: usize = std.mem.zeroes(usize),
    pos: usize = std.mem.zeroes(usize),
};
pub const ZSTD_outBuffer = struct_ZSTD_outBuffer_s;
pub const ZSTD_CStream = ZSTD_CCtx;
pub extern fn ZSTD_createCStream() ?*ZSTD_CStream;
pub extern fn ZSTD_freeCStream(zcs: ?*ZSTD_CStream) usize;
pub const ZSTD_e_continue: c_int = 0;
pub const ZSTD_e_flush: c_int = 1;
pub const ZSTD_e_end: c_int = 2;
pub const ZSTD_EndDirective = c_uint;
pub extern fn ZSTD_compressStream2(cctx: ?*ZSTD_CCtx, output: [*c]ZSTD_outBuffer, input: [*c]ZSTD_inBuffer, endOp: ZSTD_EndDirective) usize;
pub extern fn ZSTD_CStreamInSize() usize;
pub extern fn ZSTD_CStreamOutSize() usize;
pub extern fn ZSTD_initCStream(zcs: ?*ZSTD_CStream, compressionLevel: c_int) usize;
pub extern fn ZSTD_compressStream(zcs: ?*ZSTD_CStream, output: [*c]ZSTD_outBuffer, input: [*c]ZSTD_inBuffer) usize;
pub extern fn ZSTD_flushStream(zcs: ?*ZSTD_CStream, output: [*c]ZSTD_outBuffer) usize;
pub extern fn ZSTD_endStream(zcs: ?*ZSTD_CStream, output: [*c]ZSTD_outBuffer) usize;
pub const ZSTD_DStream = ZSTD_DCtx;
pub extern fn ZSTD_createDStream() ?*ZSTD_DStream;
pub extern fn ZSTD_freeDStream(zds: ?*ZSTD_DStream) usize;
pub extern fn ZSTD_initDStream(zds: ?*ZSTD_DStream) usize;
pub extern fn ZSTD_decompressStream(zds: ?*ZSTD_DStream, output: [*c]ZSTD_outBuffer, input: [*c]ZSTD_inBuffer) usize;
pub extern fn ZSTD_DStreamInSize() usize;
pub extern fn ZSTD_DStreamOutSize() usize;
pub extern fn ZSTD_compress_usingDict(ctx: ?*ZSTD_CCtx, dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, srcSize: usize, dict: ?*const anyopaque, dictSize: usize, compressionLevel: c_int) usize;
pub extern fn ZSTD_decompress_usingDict(dctx: ?*ZSTD_DCtx, dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, srcSize: usize, dict: ?*const anyopaque, dictSize: usize) usize;
pub const struct_ZSTD_CDict_s = opaque {};
pub const ZSTD_CDict = struct_ZSTD_CDict_s;
pub extern fn ZSTD_createCDict(dictBuffer: ?*const anyopaque, dictSize: usize, compressionLevel: c_int) ?*ZSTD_CDict;
pub extern fn ZSTD_freeCDict(CDict: ?*ZSTD_CDict) usize;
pub extern fn ZSTD_compress_usingCDict(cctx: ?*ZSTD_CCtx, dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, srcSize: usize, cdict: ?*const ZSTD_CDict) usize;
pub const struct_ZSTD_DDict_s = opaque {};
pub const ZSTD_DDict = struct_ZSTD_DDict_s;
pub extern fn ZSTD_createDDict(dictBuffer: ?*const anyopaque, dictSize: usize) ?*ZSTD_DDict;
pub extern fn ZSTD_freeDDict(ddict: ?*ZSTD_DDict) usize;
pub extern fn ZSTD_decompress_usingDDict(dctx: ?*ZSTD_DCtx, dst: ?*anyopaque, dstCapacity: usize, src: ?*const anyopaque, srcSize: usize, ddict: ?*const ZSTD_DDict) usize;
pub extern fn ZSTD_getDictID_fromDict(dict: ?*const anyopaque, dictSize: usize) c_uint;
pub extern fn ZSTD_getDictID_fromCDict(cdict: ?*const ZSTD_CDict) c_uint;
pub extern fn ZSTD_getDictID_fromDDict(ddict: ?*const ZSTD_DDict) c_uint;
pub extern fn ZSTD_getDictID_fromFrame(src: ?*const anyopaque, srcSize: usize) c_uint;
pub extern fn ZSTD_CCtx_loadDictionary(cctx: ?*ZSTD_CCtx, dict: ?*const anyopaque, dictSize: usize) usize;
pub extern fn ZSTD_CCtx_refCDict(cctx: ?*ZSTD_CCtx, cdict: ?*const ZSTD_CDict) usize;
pub extern fn ZSTD_CCtx_refPrefix(cctx: ?*ZSTD_CCtx, prefix: ?*const anyopaque, prefixSize: usize) usize;
pub extern fn ZSTD_DCtx_loadDictionary(dctx: ?*ZSTD_DCtx, dict: ?*const anyopaque, dictSize: usize) usize;
pub extern fn ZSTD_DCtx_refDDict(dctx: ?*ZSTD_DCtx, ddict: ?*const ZSTD_DDict) usize;
pub extern fn ZSTD_DCtx_refPrefix(dctx: ?*ZSTD_DCtx, prefix: ?*const anyopaque, prefixSize: usize) usize;
pub extern fn ZSTD_sizeof_CCtx(cctx: ?*const ZSTD_CCtx) usize;
pub extern fn ZSTD_sizeof_DCtx(dctx: ?*const ZSTD_DCtx) usize;
pub extern fn ZSTD_sizeof_CStream(zcs: ?*const ZSTD_CStream) usize;
pub extern fn ZSTD_sizeof_DStream(zds: ?*const ZSTD_DStream) usize;
pub extern fn ZSTD_sizeof_CDict(cdict: ?*const ZSTD_CDict) usize;
pub extern fn ZSTD_sizeof_DDict(ddict: ?*const ZSTD_DDict) usize;
pub var header_sizes: [8]c_int = [8]c_int{
    16 + 8 + 1,
    128,
    0,
    1 + 4 + 2,
    1 + 4 + 2,
    1 + 4 + 2,
    16 + 8 + 1,
    0,
};
pub const REKEY_MODE_RATCHET: c_int = 0;
pub const REKEY_MODE_EDSIGN: c_int = 1;
pub const REKEY_MODE_CHGREPLY: c_int = 3;
pub const REKEY_MODE_KEM768_PUBLIC: c_int = 4;
pub const REKEY_MODE_KEM768_CIPHERTEXT: c_int = 5;
const enum_unnamed_81 = c_uint;
pub fn chunk_and_send_pqc(S: [*c]struct_a12_state, buf_in: [*c]u8, buf_sz_in: usize, mode: u8, outnonce: [*c]u8) callconv(.c) void {
    var buf: [*c]u8 = buf_in;
    var buf_sz: usize = buf_sz_in;
    S.*.keys.rekey_block = true;
    var outb: [128]u8 = undefined;
    const chunk_size: usize = 108;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=pqc_chunk_xfer:size=%zu:mode=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "chunk_and_send_pqc", buf_sz, @as(c_int, @bitCast(@as(c_uint, mode))));
        }
        if (!false) break;
    }
    {
        var i: usize = 0;
        while (i < 10) : (i +%= 1) {
            build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_REKEY)))));
            outb[18] = mode;
            outb[19] = @as(u8, @truncate(i));
            _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[20])), @as(?*const anyopaque, @ptrCast(buf)), chunk_size);
            buf += chunk_size;
            buf_sz -%= chunk_size;
            a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
        }
    }
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_REKEY)))));
    outb[18] = mode;
    outb[19] = 10;
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[20])), @as(?*const anyopaque, @ptrCast(buf)), buf_sz);
    if (outnonce != null) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(outnonce)), @as(?*const anyopaque, @ptrCast(&outb[8])), 8);
    }
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    S.*.keys.rekey_block = false;
}
pub fn unlink_node(S: [*c]struct_a12_state, root: [*c][*c]struct_blob_xfer, node: [*c]struct_blob_xfer) callconv(.c) void {
    if (!(node != null)) return;
    if (node == S.*.pending_out) {
        var ch: ?*struct_a12_channel = &S.*.channels[node.*.chid];
        ch.?.unpack_state.last_bframe_id = node.*.identifier;
    }
    const next: [*c]struct_blob_xfer = node.*.next;
    var dst: [*c][*c]struct_blob_xfer = root;
    while ((dst.* != node) and (dst.* != null)) {
        dst = &dst.*.*.next;
    }
    if (dst.* != node) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:couldn't not unlink node\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "unlink_node");
            }
            if (!false) break;
        }
        return;
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:unlinked:stream=%lu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "unlink_node", node.*.streamid);
        }
        if (!false) break;
    }
    dst.* = next;
    _ = close(node.*.fd);
    node.*.fd = -1;
    if (node.*.tag != null) {
        free(node.*.tag);
        node.*.tag = @as(?*anyopaque, @ptrFromInt(0));
    }
    if (node.*.zstd != null) {
        _ = ZSTD_freeCCtx(node.*.zstd);
        node.*.zstd = null;
    }
    if ((S.*.remote_mode == ROLE_DIR) and (@as(c_int, @bitCast(@as(c_uint, node.*.chid))) != 0)) {
        S.*.channels[node.*.chid].active = 0;
    }
    free(@as(?*anyopaque, @ptrCast(node)));
}
pub fn dirstate_item(S: [*c]struct_a12_state, C: [*c]struct_appl_meta) callconv(.c) void {
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_DIRSTATE)))));
    if (!(C.*.appl.name[0] != 0)) return;
    pack_u16(C.*.identifier, &outb[18]);
    pack_u16(C.*.categories, &outb[20]);
    pack_u16(C.*.permissions, &outb[22]);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[24])), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&C.*.hash[0]))))), 4);
    pack_u64(C.*.buf_sz, &outb[28]);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[36])), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&C.*.appl.name[0]))))), 18);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[55])), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&C.*.appl.short_descr[0]))))), 69);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:send:name=%s\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "dirstate_item", @as([*c]u8, @ptrCast(@alignCast(&C.*.appl.name[0]))));
        }
        if (!false) break;
    }
}
pub fn grow_array(S: [*c]struct_a12_state, dst: [*c]u8, cur_sz: [*c]usize, new_sz_in: usize, ind: c_int) callconv(.c) [*c]u8 {
    var new_sz: usize = new_sz_in;
    if (new_sz < cur_sz.*) return dst;
    var pow_1: usize = 1;
    while (pow_1 < new_sz) {
        pow_1 *%= 2;
    }
    if (pow_1 < new_sz) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:error=grow_array:reason=limit\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "grow_array");
            }
            if (!false) break;
        }
        free(@as(?*anyopaque, @ptrCast(dst)));
        cur_sz.* = 0;
        return null;
    }
    new_sz = pow_1;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:grow=queue:%d:from=%zu:to=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "grow_array", ind, cur_sz.*, new_sz);
        }
        if (!false) break;
    }
    var res: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(realloc(@as(?*anyopaque, @ptrCast(dst)), new_sz))));
    if (!(res != null)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:error=grow_array:reason=malloc_fail\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "grow_array");
            }
            if (!false) break;
        }
        free(@as(?*anyopaque, @ptrCast(dst)));
        cur_sz.* = 0;
        return null;
    }
    _ = memset(@as(?*anyopaque, @ptrCast(&res[cur_sz.*])), '\x00', new_sz -% cur_sz.*);
    cur_sz.* = new_sz;
    return res;
}
pub fn trace_crypto_key(S: [*c]struct_a12_state, srv: bool, domain: [*c]const u8, buf: [*c]u8, sz: usize) callconv(.c) void {
    _ = S;
    _ = srv;
    _ = domain;
    _ = buf;
    _ = sz;
}
pub fn step_sequence(S: [*c]struct_a12_state, outb: [*c]u8) callconv(.c) void {
    pack_u64(S.*.last_seen_seqnr, outb);
}
pub fn fail_state(S: [*c]struct_a12_state, msg: [*c]const u8) callconv(.c) void {
    if ((msg != null) and (msg[0] != 0)) {
        _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&S.*.state_error_hint[0]))), 32, "%s", msg);
    }
    S.*.state = @as(u8, @bitCast(@as(i8, @truncate(STATE_BROKEN))));
}
pub fn build_control_header(S: [*c]struct_a12_state, outb: [*c]u8, cmd: u8) callconv(.c) void {
    _ = memset(@as(?*anyopaque, @ptrCast(outb)), '\x00', 128);
    step_sequence(S, outb);
    arcan_random(&outb[8], 8);
    outb[16] = @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel))));
    outb[17] = cmd;
}
pub fn mark_bstream_progress(S: [*c]struct_a12_state, chid: u8, status: c_int, bytes_in: usize, bytes_out: usize) callconv(.c) void {
    var ch: ?*struct_a12_channel = &S.*.channels[chid];
    if (!(ch.?.progress.trigger != null)) return;
    ch.?.progress.in +%= bytes_in;
    ch.?.progress.out +%= bytes_out;
    if (ch.?.progress.trigger_left > bytes_in) {
        ch.?.progress.trigger_left -%= bytes_in;
    }
    if (status != 0) {
        ch.?.progress.trigger.?(status, ch.?.progress.in, ch.?.progress.out, ch.?.progress.total, ch.?.progress.tag);
        return;
    }
    if (ch.?.progress.trigger_left <= bytes_in) {
        ch.?.progress.trigger_left = ch.?.progress.trigger_count;
        ch.?.progress.trigger.?(status, ch.?.progress.in, ch.?.progress.out, ch.?.progress.total, ch.?.progress.tag);
    }
}
pub fn register_bchunk_name(S: [*c]struct_a12_state, ev: [*c]struct_arcan_event) callconv(.c) void {
    if (S.*.remote_mode != ROLE_DIR) return;
    S.*.out_stream +%= 1;
    var outev: struct_arcan_event = struct_arcan_event{
        .unnamed_0 = union_unnamed_9{
            .unnamed_0 = struct_unnamed_10{
                .unnamed_0 = union_unnamed_11{
                    .ext = arcan_extevent{
                        .kind = @as(c_uint, @bitCast(EVENT_EXTERNAL_BCHUNKSTATE)),
                        .source = std.mem.zeroes(i64),
                        .unnamed_0 = union_unnamed_26{
                            .bchunk = struct_unnamed_31{
                                .unnamed_0 = union_unnamed_32{
                                    .ns = @as(u64, @bitCast(@as(c_ulong, ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv))),
                                },
                                .input = @as(u8, @intFromBool(ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.kind == @as(c_uint, @bitCast(TARGET_COMMAND_BCHUNK_IN)))),
                                .hint = std.mem.zeroes(u8),
                                .stream = std.mem.zeroes(u8),
                                .extensions = std.mem.zeroes([68]u8),
                                .identifier = @as(u32, @bitCast(@as(c_uint, @truncate(S.*.out_stream)))),
                            },
                        },
                        .frame_id = std.mem.zeroes(u64),
                    },
                },
                .category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_EXTERNAL)))),
            },
        },
    };
    _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions[0]))), (@sizeOf([68]u8) / @sizeOf(u8)) / @as(usize, @intFromBool(!((@sizeOf([68]u8) % @sizeOf(u8)) != 0))), "%s", @as([*c]u8, @ptrCast(@alignCast(&ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0]))));
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=register_transfer:name=%s:id=%lu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "register_bchunk_name", @as([*c]u8, @ptrCast(@alignCast(&outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions[0]))), S.*.out_stream);
        }
        if (!false) break;
    }
    _ = a12_channel_enqueue(S, &outev);
}
pub fn a12int_issue_rekey(S: [*c]struct_a12_state) callconv(.c) void {
    {
        const smon = @import("shmif_monitor");
        const snprintf_p = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf_p: [96]u8 = undefined;
        _ = snprintf_p(&buf_p, 96, "a12:coverage:rekey_send:own=%d:pqc=%d",
            @as(c_int, @intFromBool(S.*.keys.own_rekey)),
            @as(c_int, @intFromBool(S.*.opts.*.pqc_rekey)));
        smon.emitLuaTag(@ptrCast(&buf_p));
    }
    if (S.*.keys.rekey_block) return;
    if (!S.*.keys.own_rekey) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:error:issue_rekey:waiting_for_other\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "a12int_issue_rekey");
            }
            if (!false) break;
        }
        fail_state(S, "rekey-issue");
        return;
    }
    if ((@as(c_int, @intFromBool(S.*.opts.*.pqc_rekey)) != 0) and !S.*.keys.pqc_rekey_gotpubk) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:issue_rekey:no_pqc_pubkey:x25519_fallback\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "a12int_issue_rekey");
            }
            if (!false) break;
        }
    } else if (S.*.opts.*.pqc_rekey) {
        var ciphertext: [1088]u8 = undefined;
        var ssecret: [32]u8 = undefined;
        var nonce: [8]u8 = undefined;
        _ = mlkem_enc(@as([*c]u8, @ptrCast(@alignCast(&ciphertext[0]))), @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.pqc_publickey_buffer[0]))));
        chunk_and_send_pqc(S, @as([*c]u8, @ptrCast(@alignCast(&ciphertext[0]))), @sizeOf([1088]u8), @as(u8, @bitCast(@as(i8, @truncate(REKEY_MODE_KEM768_CIPHERTEXT)))), @as([*c]u8, @ptrCast(@alignCast(&nonce[0]))));
        chacha_setup(chacha_cast(S.*.enc_state), @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), 32, 0, 8);
        chacha_set_nonce(chacha_cast(S.*.enc_state), @as([*c]u8, @ptrCast(@alignCast(&nonce[0]))));
        trace_crypto_key(S, S.*.server, "rekey_shared_out", @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), 32);
        var mac_key: [32]u8 = undefined;
        var temp: blake3_hasher = undefined;
        blake3_hasher_init_derive_key(&temp, "arcan-a12 rekey");
        blake3_hasher_update(&temp, @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))))), 32);
        blake3_hasher_finalize(&temp, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))), 32);
        blake3_hasher_init_keyed(&S.*.out_mac, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))));
        trace_crypto_key(S, S.*.server, "rekey_out_mac", @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))), 32);
        S.*.keys.own_rekey = false;
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:rekey_pqc:ciphertext_sent\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "a12int_issue_rekey");
            }
            if (!false) break;
        }
        return;
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:issue_rekey\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "a12int_issue_rekey");
        }
        if (!false) break;
    }
    S.*.keys.own_rekey = false;
    var out_pub: [32]u8 = [1]u8{0} ++ [1]u8{0} ** 31;
    trace_crypto_key(S, S.*.server, "rekey_old", @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), 32);
    x25519_private_key(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))));
    x25519_public_key(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), @as([*c]u8, @ptrCast(@alignCast(&out_pub[0]))));
    trace_crypto_key(S, S.*.server, "rekey_local", @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), 32);
    trace_crypto_key(S, S.*.server, "rekey_new_pub", @as([*c]u8, @ptrCast(@alignCast(&out_pub[0]))), 32);
    var outb: [128]u8 = undefined;
    var nonce: [8]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_REKEY)))));
    outb[18] = @as(u8, @bitCast(@as(i8, @truncate(REKEY_MODE_RATCHET))));
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[19])), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&out_pub[0]))))), 32);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&nonce[0]))))), @as(?*const anyopaque, @ptrCast(&outb[8])), 8);
    trace_crypto_key(S, S.*.server, "rekey_nonce", @as([*c]u8, @ptrCast(@alignCast(&nonce[0]))), 8);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    var ssecret: [32]u8 = undefined;
    _ = x25519_shared_secret(@as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.remote_pub[0]))));
    chacha_setup(chacha_cast(S.*.enc_state), @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), 32, 0, 8);
    chacha_set_nonce(chacha_cast(S.*.enc_state), @as([*c]u8, @ptrCast(@alignCast(&nonce[0]))));
    trace_crypto_key(S, S.*.server, "rekey_shared_out", @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), 32);
    var mac_key: [32]u8 = undefined;
    var temp: blake3_hasher = undefined;
    blake3_hasher_init_derive_key(&temp, "arcan-a12 rekey");
    blake3_hasher_update(&temp, @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))))), 32);
    blake3_hasher_finalize(&temp, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))), 32);
    blake3_hasher_init_keyed(&S.*.out_mac, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))));
    trace_crypto_key(S, S.*.server, "rekey_out_mac", @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))), 32);
}
pub fn find_entry(S: [*c]struct_a12_state, tgt: [*c]struct_appl_meta) callconv(.c) [*c]struct_appl_meta {
    var cur: [*c]struct_appl_meta = S.*.directory;
    while (cur != null) {
        if (@as(c_int, @bitCast(@as(c_uint, cur.*.identifier))) == @as(c_int, @bitCast(@as(c_uint, tgt.*.identifier)))) {
            return cur;
        }
        cur = cur.*.next;
    }
    return null;
}
pub fn send_hello_packet(S: [*c]struct_a12_state, mode: c_int, pubk: [*c]u8, csrnd: [*c]u8) callconv(.c) void {
    var outb: [128]u8 = [1]u8{0} ++ [1]u8{0} ** 127;
    step_sequence(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))));
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[8])), @as(?*const anyopaque, @ptrCast(csrnd)), 8);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[21])), @as(?*const anyopaque, @ptrCast(pubk)), 32);
    if (S.*.opts.*.local_role == ROLE_SOURCE) {
        outb[54] = 1;
    } else if (S.*.opts.*.local_role == ROLE_SINK) {
        outb[54] = 2;
    } else if (S.*.opts.*.local_role == ROLE_PROBE) {
        outb[54] = 3;
    } else if (S.*.opts.*.local_role == ROLE_DIR) {
        outb[54] = 4;
    } else if (S.*.opts.*.local_role == ROLE_DIRREF) {
        outb[54] = 5;
    } else {
        fail_state(S, "unknown-role");
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:unknown_role\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "send_hello_packet");
            }
            if (!false) break;
        }
        return;
    }
    outb[17] = @as(u8, @bitCast(@as(i8, @truncate(COMMAND_HELLO))));
    outb[18] = 0;
    outb[19] = 18;
    outb[20] = @as(u8, @bitCast(@as(i8, @truncate(mode))));
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub fn reset_state(S: [*c]struct_a12_state) callconv(.c) void {
    S.*.left = @as(u16, @bitCast(@as(c_short, @truncate(header_sizes[@as(c_uint, @intCast(STATE_NOPACKET))]))));
    if ((@as(c_int, @bitCast(@as(c_uint, S.*.state))) != STATE_1STSRV_PACKET) and (@as(c_int, @bitCast(@as(c_uint, S.*.state))) != STATE_BROKEN)) {
        S.*.state = @as(u8, @bitCast(@as(i8, @truncate(STATE_NOPACKET))));
    }
    S.*.decode_pos = 0;
    S.*.in_channel = -1;
}
pub fn derive_encdec_key(ssecret: [*c]const u8, secret_len: usize, out_mac: [*c]u8, out_srv: [*c]u8, out_cl: [*c]u8, nonce: [*c]u8) callconv(.c) void {
    var temp: blake3_hasher = undefined;
    blake3_hasher_init_derive_key(&temp, "arcan-a12 init-packet");
    blake3_hasher_update(&temp, @as(?*const anyopaque, @ptrCast(ssecret)), secret_len);
    if (nonce != null) {
        blake3_hasher_update(&temp, @as(?*const anyopaque, @ptrCast(nonce)), 8);
    }
    blake3_hasher_finalize(&temp, out_mac, 32);
    blake3_hasher_update(&temp, @as(?*const anyopaque, @ptrCast(out_mac)), 32);
    blake3_hasher_finalize(&temp, out_cl, 32);
    blake3_hasher_update(&temp, @as(?*const anyopaque, @ptrCast(out_cl)), 32);
    blake3_hasher_finalize(&temp, out_srv, 32);
}
// src/a12/a12.c:659:2: warning: ignoring StaticAssert declaration

// src/a12/a12.c:660:2: warning: ignoring StaticAssert declaration
pub fn update_keymaterial(S: [*c]struct_a12_state, secret: [*c]u8, len: usize, nonce: [*c]u8) callconv(.c) void {
    var mac_key: [32]u8 = undefined;
    var srv_key: [32]u8 = undefined;
    var cl_key: [32]u8 = undefined;
    derive_encdec_key(secret, len, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))), @as([*c]u8, @ptrCast(@alignCast(&srv_key[0]))), @as([*c]u8, @ptrCast(@alignCast(&cl_key[0]))), nonce);
    blake3_hasher_init_keyed(&S.*.out_mac, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))));
    blake3_hasher_init_keyed(&S.*.in_mac, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))));
    if (!(S.*.dec_state != null)) {
        S.*.dec_state = chacha_uncast(@as([*c]struct_chacha_ctx, @ptrCast(@alignCast(malloc(@sizeOf(struct_chacha_ctx))))));
        if (!(S.*.dec_state != null)) {
            fail_state(S, "alloc-fail");
            return;
        }
    }
    S.*.enc_state = chacha_uncast(@as([*c]struct_chacha_ctx, @ptrCast(@alignCast(malloc(@sizeOf(struct_chacha_ctx))))));
    if (!(S.*.enc_state != null)) {
        free(@as(?*anyopaque, @ptrCast(S.*.dec_state)));
        fail_state(S, "alloc-fail");
        return;
    }
    if (S.*.server) {
        trace_crypto_key(S, S.*.server, "enc_key", @as([*c]u8, @ptrCast(@alignCast(&srv_key[0]))), 32);
        trace_crypto_key(S, S.*.server, "dec_key", @as([*c]u8, @ptrCast(@alignCast(&cl_key[0]))), 32);
        chacha_setup(chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(@alignCast(&cl_key[0]))), 32, 0, 8);
        chacha_setup(chacha_cast(S.*.enc_state), @as([*c]u8, @ptrCast(@alignCast(&srv_key[0]))), 32, 0, 8);
    } else {
        trace_crypto_key(S, S.*.server, "dec_key", @as([*c]u8, @ptrCast(@alignCast(&srv_key[0]))), 32);
        trace_crypto_key(S, S.*.server, "enc_key", @as([*c]u8, @ptrCast(@alignCast(&cl_key[0]))), 32);
        chacha_setup(chacha_cast(S.*.enc_state), @as([*c]u8, @ptrCast(@alignCast(&cl_key[0]))), 32, 0, 8);
        chacha_setup(chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(@alignCast(&srv_key[0]))), 32, 0, 8);
    }
    if (nonce != null) {
        trace_crypto_key(S, S.*.server, "state=set_nonce", nonce, 8);
        chacha_set_nonce(chacha_cast(S.*.enc_state), nonce);
        chacha_set_nonce(chacha_cast(S.*.dec_state), nonce);
    }
}
pub fn a12_setup(opt: [*c]struct_a12_context_options, srv: bool) callconv(.c) [*c]struct_a12_state {
    const res: [*c]struct_a12_state = @as([*c]struct_a12_state, @ptrCast(@alignCast(malloc(@sizeOf(struct_a12_state)))));
    if (!(res != null)) return null;
    res.* = struct_a12_state{
        .opts = null,
        .directory = null,
        .directory_clk = std.mem.zeroes(u64),
        .notify_dynamic = false,
        .tracetag = std.mem.zeroes([16]u8),
        .last_mac_in = std.mem.zeroes([16]u8),
        .current_seqnr = std.mem.zeroes(u64),
        .last_seen_seqnr = std.mem.zeroes(u64),
        .out_stream = std.mem.zeroes(u64),
        .shutdown_id = std.mem.zeroes(i64),
        .advenc_broken = false,
        .congestion_stats = std.mem.zeroes(struct_unnamed_70),
        .stats = std.mem.zeroes(struct_a12_iostat),
        .pending_dynamic = std.mem.zeroes(struct_unnamed_71),
        .buf_sz = std.mem.zeroes([2]usize),
        .bufs = std.mem.zeroes([2][*c]u8),
        .buf_ind = std.mem.zeroes(u8),
        .buf_ofs = std.mem.zeroes(usize),
        .pending_out = null,
        .out_req_id = std.mem.zeroes(usize),
        .pending_in = null,
        .in_req_id = std.mem.zeroes(usize),
        .binary_handler = null,
        .binary_handler_tag = null,
        .channels = std.mem.zeroes([256]struct_a12_channel),
        .in_channel = 0,
        .in_stream = std.mem.zeroes(u32),
        .out_channel = 0,
        .on_discover = null,
        .discover_tag = null,
        .on_auth = null,
        .auth_tag = null,
        .decode = std.mem.zeroes([65536]u8),
        .decode_pos = std.mem.zeroes(u16),
        .left = std.mem.zeroes(u16),
        .state = std.mem.zeroes(u8),
        .cookie = std.mem.zeroes(u32),
        .keys = std.mem.zeroes(struct_unnamed_75),
        .server = srv,
        .cl_firstout = false,
        .authentic = 0,
        .remote_mode = 0,
        .endpoint = null,
        .auth_latched = false,
        .prepend_unpack_sz = std.mem.zeroes(usize),
        .prepend_unpack = null,
        .out_mac = std.mem.zeroes(blake3_hasher),
        .in_mac = std.mem.zeroes(blake3_hasher),
        .enc_state = null,
        .dec_state = null,
        .state_error_hint = std.mem.zeroes([32]u8),
    };
    res.*.shutdown_id = -1;
    {
        var i: usize = 0;
        while (i <= 255) : (i +%= 1) {
            res.*.channels[i].unpack_state.bframe.tmp_fd = -1;
        }
    }
    if (srv) {
        res.*.keys.own_rekey = true;
        res.*.keys.rekey_count = blk: {
            const tmp = opt.*.rekey_bytes;
            res.*.keys.rekey_base_count = tmp;
            break :blk tmp;
        };
    }
    var len: usize = 0;
    res.*.opts = @as([*c]struct_a12_context_options, @ptrCast(@alignCast(malloc(@sizeOf(struct_a12_context_options)))));
    if (!(res.*.opts != null)) {
        free(@as(?*anyopaque, @ptrCast(res)));
        return null;
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(res.*.opts)), @as(?*const anyopaque, @ptrCast(opt)), @sizeOf(struct_a12_context_options));
    if (!(res.*.opts.*.secret[0] != 0)) {
        _ = sprintf(@as([*c]u8, @ptrCast(@alignCast(&res.*.opts.*.secret[0]))), "SETECASTRONOMY");
    }
    len = strlen(@as([*c]u8, @ptrCast(@alignCast(&res.*.opts.*.secret[0]))));
    update_keymaterial(res, @as([*c]u8, @ptrCast(@alignCast(&res.*.opts.*.secret[0]))), len, null);
    res.*.cookie = 4277009102;
    res.*.out_stream = 1;
    res.*.notify_dynamic = true;
    return res;
}
pub fn a12_init() callconv(.c) void {
    const init = struct {
        var static: bool = false;
    };
    if (init.static) return;
    var outb: [512]u8 = undefined;
    const evsz: isize = arcan_shmif_eventpack(&(struct_arcan_event{
        .unnamed_0 = union_unnamed_9{
            .unnamed_0 = struct_unnamed_10{
                .unnamed_0 = std.mem.zeroes(union_unnamed_11),
                .category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_IO)))),
            },
        },
    }), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 512);
    header_sizes[@as(c_uint, @intCast(STATE_EVENT_PACKET))] = @as(c_int, @bitCast(@as(c_int, @truncate((evsz + 8) + 1))));
    init.static = true;
}
pub fn update_mac_and_decrypt(S: [*c]struct_a12_state, source: [*c]const u8, hash: [*c]blake3_hasher, ctx: [*c]struct_chacha_ctx, buf: [*c]u8, sz: usize) callconv(.c) void {
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:src=%s:mac_update=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "update_mac_and_decrypt", source, sz);
        }
        if (!false) break;
    }
    blake3_hasher_update(hash, @as(?*const anyopaque, @ptrCast(buf)), sz);
    if (ctx != null) {
        chacha_apply(ctx, buf, sz);
    }
}
pub fn build_signkey_challenge(S: [*c]struct_a12_state, out_chg: [*c]u8, nonce: [*c]u8) callconv(.c) void {
    var hash: blake3_hasher = undefined;
    blake3_hasher_init(&hash);
    blake3_hasher_update(&hash, @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.auth_csrnd[0]))))), 8);
    blake3_hasher_update(&hash, @as(?*const anyopaque, @ptrCast(nonce)), 8);
    blake3_hasher_finalize(&hash, out_chg, 32);
}
pub fn process_nopacket(S: [*c]struct_a12_state) callconv(.c) void {
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.last_mac_in[0]))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.decode[0]))))), 16);
    trace_crypto_key(S, S.*.server, "ref_mac", @as([*c]u8, @ptrCast(@alignCast(&S.*.last_mac_in[0]))), 16);
    update_mac_and_decrypt(S, "process_nopacket", &S.*.in_mac, chacha_cast(S.*.dec_state), &S.*.decode[16], 9);
    unpack_u64(&S.*.last_seen_seqnr, &S.*.decode[16]);
    if (S.*.last_seen_seqnr <= S.*.current_seqnr) {
        S.*.stats.packets_pending = S.*.current_seqnr -% S.*.last_seen_seqnr;
    }
    const state_id: c_int = @as(c_int, @bitCast(@as(c_uint, S.*.decode[16 + 8])));
    if (state_id >= STATE_BROKEN) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:state=broken:unknown_command=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_nopacket", state_id);
            }
            if (!false) break;
        }
        fail_state(S, "invalid-state-in");
        return;
    }
    S.*.state = @as(u8, @bitCast(@as(i8, @truncate(state_id))));
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_TRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:seq=%lu:left=%u:state=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_TRANSFER), "process_nopacket", S.*.last_seen_seqnr, @as(c_int, @bitCast(@as(c_uint, S.*.left))), @as(c_int, @bitCast(@as(c_uint, S.*.state))));
        }
        if (!false) break;
    }
    S.*.left = @as(u16, @bitCast(@as(c_short, @truncate(header_sizes[S.*.state]))));
    S.*.decode_pos = 0;
}
// src/a12/a12.c:1055:10: warning: unsupported type: 'VariableArray'

// Hand-ported from src/a12/a12.c:1049-1100 (had goto-based early returns; restructured with if/return).
fn process_srvfirst(S: [*c]struct_a12_state) callconv(.c) void {
    if (S.*.authentic > AUTH_REAL_HELLO_SENT) {
        fail_state(S, "authpkt-on-authed");
        return;
    }
    const mac_sz: usize = @as(usize, 16) >> 1;
    const nonce_sz: usize = 8;
    var nonce: [8]u8 = undefined;
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=mac:status=half_block\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "process_srvfirst");
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(&S.*.last_mac_in[0])), @as(?*const anyopaque, @ptrCast(&S.*.decode[0])), mac_sz);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&nonce[0])), @as(?*const anyopaque, @ptrCast(&S.*.decode[mac_sz])), nonce_sz);

    // read the rest of the control packet
    S.*.authentic = AUTH_SERVER_HBLOCK;
    S.*.left = 128;
    S.*.state = @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET))));
    S.*.decode_pos = 0;

    // update MAC calculation with nonce and seqn+command byte
    blake3_hasher_update(&S.*.in_mac, @as(?*const anyopaque, @ptrCast(&nonce[0])), nonce_sz);
    blake3_hasher_update(&S.*.in_mac, @as(?*const anyopaque, @ptrCast(&S.*.decode[mac_sz + nonce_sz])), 8 + 1);

    if (S.*.dec_state == null) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SECURITY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:srvfirst:no_decode\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SECURITY), "process_srvfirst");
        }
        fail_state(S, "auth-bad-state");
        return;
    }

    chacha_set_nonce(chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(&nonce[0])));
    chacha_set_nonce(chacha_cast(S.*.enc_state), @as([*c]u8, @ptrCast(&nonce[0])));

    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=cipher:status=init_nonce\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "process_srvfirst");
    }
    trace_crypto_key(S, S.*.server, "nonce", @as([*c]u8, @ptrCast(&nonce[0])), nonce_sz);

    // decrypt command byte and seqn
    const base: usize = mac_sz + nonce_sz;
    chacha_apply(chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(&S.*.decode[base])), 9);

    if (S.*.decode[base + 8] != @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET))))) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=bad_key_or_nonce\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "process_srvfirst");
        }
        fail_state(S, "auth-bad-key");
        return;
    }
}
pub fn fill_diropened(S: [*c]struct_a12_state, r: struct_a12_dynreq) callconv(.c) void {
    var outb: [128]u8 = undefined;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_DIROPENED)))));
    outb[18] = @as(u8, @bitCast(@as(i8, @truncate(r.proto))));
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[19])), @as(?*const anyopaque, @ptrCast(@as([*c]const u8, @ptrCast(@alignCast(&r.host[0]))))), 46);
    pack_u16(r.port, &outb[65]);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[67])), @as(?*const anyopaque, @ptrCast(@as([*c]const u8, @ptrCast(@alignCast(&r.authk[0]))))), 12);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[79])), @as(?*const anyopaque, @ptrCast(@as([*c]const u8, @ptrCast(@alignCast(&r.pubk[0]))))), 32);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub fn command_diropened(S: [*c]struct_a12_state) callconv(.c) void {
    const oc: ?*const fn ([*c]struct_a12_state, struct_a12_dynreq, ?*anyopaque) callconv(.c) void = S.*.pending_dynamic.closure;
    const tag: ?*anyopaque = S.*.pending_dynamic.tag;
    S.*.pending_dynamic.closure = null;
    S.*.pending_dynamic.tag = @as(?*anyopaque, @ptrFromInt(@as(usize, 0)));
    S.*.pending_dynamic.active = false;
    var rep: struct_a12_dynreq = struct_a12_dynreq{
        .host = std.mem.zeroes([46]u8),
        .pubk = std.mem.zeroes([32]u8),
        .port = std.mem.zeroes(u16),
        .authk = std.mem.zeroes([12]u8),
        .proto = @as(c_int, @bitCast(@as(c_uint, S.*.decode[18]))),
        .local_private_key = std.mem.zeroes([32]u8),
    };
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&rep.local_private_key[0]))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.pending_dynamic.priv_key[0]))))), 32);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&rep.host[0]))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[19])), 46);
    unpack_u16(&rep.port, &S.*.decode[65]);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&rep.authk[0]))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[67])), 12);
    _ = memset(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.pending_dynamic.priv_key[0]))))), '\x00', 32);
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:diropened:status=%u:host=%s:port=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "command_diropened", rep.proto, @as([*c]u8, @ptrCast(@alignCast(&rep.host[0]))), @as(c_int, @bitCast(@as(c_uint, rep.port))));
        }
        if (!false) break;
    }
    var nullk: [32]u8 = [1]u8{0} ++ [1]u8{0} ** 31;
    if (memcmp(@as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&nullk[0]))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[79])), 32) == 0) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&rep.pubk[0]))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.pending_dynamic.req_key[0]))))), 32);
    } else {
        _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&rep.pubk[0]))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[79])), 32);
    }
    oc.?(S, rep, tag);
}
pub fn step_pqc_xfer(S: [*c]struct_a12_state, dst: [*c]u8) callconv(.c) c_int {
    const mode: u8 = S.*.decode[18];
    const ct_ind: u8 = S.*.decode[19];
    if (@as(c_int, @bitCast(@as(c_uint, ct_ind))) != @as(c_int, @bitCast(@as(c_uint, S.*.keys.pqc_xfer_ind)))) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:error:command_rekey:bad_chunk_index=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "step_pqc_xfer", @as(c_int, @bitCast(@as(c_uint, ct_ind))));
            }
            if (!false) break;
        }
        fail_state(S, "rekey-pqc-cipher-badind");
        return -1;
    }
    if (@as(c_int, @bitCast(@as(c_uint, ct_ind))) > 10) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:error:command_rekey:chunk_index_overflow=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "step_pqc_xfer", @as(c_int, @bitCast(@as(c_uint, ct_ind))));
            }
            if (!false) break;
        }
        fail_state(S, "rekey-pqc-cipher-oflow");
        return -1;
    }
    const ofs: usize = @intCast(@as(c_int, @bitCast(@as(c_uint, ct_ind))) * 108);
    if (@as(c_int, @bitCast(@as(c_uint, ct_ind))) == 10) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(&dst[ofs])), @as(?*const anyopaque, @ptrCast(&S.*.decode[20])), @as(c_ulong, @bitCast(@as(c_long, if (@as(c_int, @bitCast(@as(c_uint, mode))) == REKEY_MODE_KEM768_CIPHERTEXT) @as(c_int, 8) else @as(c_int, 104)))));
        S.*.keys.pqc_xfer_ind = 0;
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:status:pqc_xfer_ok\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "step_pqc_xfer");
            }
            if (!false) break;
        }
        return 1;
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(&dst[ofs])), @as(?*const anyopaque, @ptrCast(&S.*.decode[20])), 108);
    S.*.keys.pqc_xfer_ind +%= 1;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:status:pqc_xfer:step_index=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "step_pqc_xfer", @as(c_int, @bitCast(@as(c_uint, S.*.keys.pqc_xfer_ind))));
        }
        if (!false) break;
    }
    return 0;
}
pub fn command_diropen(S: [*c]struct_a12_state, mode: u8, kpub_tgt: [*c]u8) callconv(.c) void {
    const C: [*c]struct_a12_unpack_cfg = &S.*.channels[0].raw;
    if (!(C.*.directory_open != null)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SECURITY) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=warning:diropen_no_handler\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SECURITY), "command_diropen");
            }
            if (!false) break;
        }
        return;
    }
    var out: struct_a12_dynreq = struct_a12_dynreq{
        .host = [1]u8{0} ++ [1]u8{0} ** 45,
        .pubk = std.mem.zeroes([32]u8),
        .port = std.mem.zeroes(u16),
        .authk = std.mem.zeroes([12]u8),
        .proto = 0,
        .local_private_key = std.mem.zeroes([32]u8),
    };
    var outb: [128]u8 = undefined;
    if (C.*.directory_open.?(S, kpub_tgt, mode, &out, C.*.tag)) {
        fill_diropened(S, out);
    } else {
        build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_DIROPENED)))));
        a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    }
}
pub fn command_cancelstream(S: [*c]struct_a12_state, streamid: u32, reason: u8, stype: u8) callconv(.c) void {
    var node: [*c]struct_blob_xfer = S.*.pending_out;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:stream_cancel:%u:%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_cancelstream", streamid, @as(c_int, @bitCast(@as(c_uint, reason))));
        }
        if (!false) break;
    }
    if (@as(c_int, @bitCast(@as(c_uint, stype))) == 0) {
        if (@as(c_int, @bitCast(@as(c_uint, reason))) == STREAM_CANCEL_DECODE_ERROR) {
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=decode_degrade:codec=h264:reason=sink rejected format\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "command_cancelstream");
                }
                if (!false) break;
            }
            S.*.advenc_broken = true;
        }
        return;
    } else if (@as(c_int, @bitCast(@as(c_uint, stype))) == 1) {
        return;
    }
    while (node != null) {
        if (node.*.streamid == @as(u64, @bitCast(@as(c_ulong, streamid)))) {
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=cancelled:stream=%u:source=remote\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "command_cancelstream", streamid);
                }
                if (!false) break;
            }
            if (S.*.binary_handler != null) {
                _ = S.*.binary_handler.?(S, struct_a12_bhandler_meta{
                    .state = @as(c_uint, @bitCast(A12_BHANDLER_CANCELLED)),
                    .type = std.mem.zeroes(enum_a12_bstream_type),
                    .checksum = std.mem.zeroes([16]u8),
                    .known_size = std.mem.zeroes(u64),
                    .streaming = false,
                    .channel = node.*.chid,
                    .streamid = @as(i64, @bitCast(node.*.streamid)),
                    .identifier = std.mem.zeroes(u32),
                    .extid = std.mem.zeroes([17]u8),
                    .fd = node.*.fd,
                    .dcont = null,
                }, S.*.binary_handler_tag);
            }
            unlink_node(S, &S.*.pending_out, node);
            return;
        }
        node = node.*.next;
    }
}
pub fn command_rekey_pqc(S: [*c]struct_a12_state) callconv(.c) void {
    if (@as(c_int, @bitCast(@as(c_uint, S.*.decode[18]))) == REKEY_MODE_KEM768_PUBLIC) {
        if (S.*.keys.pqc_rekey_gotpubk) {
            fail_state(S, "fail-pqc-pubk-rotation");
            return;
        }
        const status: c_int = step_pqc_xfer(S, @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.pqc_publickey_buffer[0]))));
        if (status != 1) return;
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=status:pqc_pk_received\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "command_rekey_pqc");
            }
            if (!false) break;
        }
        S.*.keys.pqc_rekey_gotpubk = true;
        if (((@as(c_int, @intFromBool(S.*.opts.*.pqc_rekey)) != 0) and !S.*.keys.pqc_rekey_initiated) and (@as(c_int, @intFromBool(S.*.keys.own_rekey)) != 0)) {
            a12int_issue_rekey(S);
            S.*.keys.pqc_rekey_initiated = true;
        }
        return;
    }
    if (S.*.keys.own_rekey) {
        fail_state(S, "fail-pqc-rekey-not-theirs");
        return;
    }
    const status: c_int = step_pqc_xfer(S, @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.pqc_ciphertext_buffer[0]))));
    if (status != 1) return;
    var ssecret: [32]u8 = undefined;
    _ = mlkem_dec(@as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.pqc_ciphertext_buffer[0]))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.pqc_private_buffer[0]))));
    chacha_setup(chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), 32, 0, 8);
    chacha_set_nonce(chacha_cast(S.*.dec_state), &S.*.decode[8]);
    trace_crypto_key(S, S.*.server, "rekey_pqc_shared_out", @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), 32);
    var mac_key: [32]u8 = undefined;
    var temp: blake3_hasher = undefined;
    blake3_hasher_init_derive_key(&temp, "arcan-a12 rekey");
    blake3_hasher_update(&temp, @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))))), 32);
    blake3_hasher_finalize(&temp, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))), 32);
    blake3_hasher_init_keyed(&S.*.in_mac, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))));
    trace_crypto_key(S, S.*.server, "rekey_out_mac", @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))), 32);
    S.*.keys.own_rekey = true;
    if (!S.*.keys.pqc_rekey_initiated and (@as(c_int, @intFromBool(S.*.keys.pqc_rekey_gotpubk)) != 0)) {
        a12int_issue_rekey(S);
        S.*.keys.pqc_rekey_initiated = true;
    }
}
pub fn command_rekey_ed25519(S: [*c]struct_a12_state) callconv(.c) void {
    if (!S.*.server) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:error:command_rekey:server_sent_edsign\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "command_rekey_ed25519");
            }
            if (!false) break;
        }
        fail_state(S, "rekey-sign-server");
        return;
    }
    if (S.*.opts.*.local_role != ROLE_DIR) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:error:command_rekey:edsign_role_mismatch\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "command_rekey_ed25519");
            }
            if (!false) break;
        }
        fail_state(S, "rekey-sign-role");
        return;
    }
    var chg: [32]u8 = undefined;
    build_signkey_challenge(S, @as([*c]u8, @ptrCast(@alignCast(&chg[0]))), &S.*.decode[8]);
    if (0 != crypto_ed25519_check(&S.*.decode[19 + 32], &S.*.decode[19], @as([*c]u8, @ptrCast(@alignCast(&chg[0]))), 32)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:error:command_rekey:edsign_bad_signature\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "command_rekey_ed25519");
            }
            if (!false) break;
        }
        fail_state(S, "rekey-sign-invalid");
        return;
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.sign_pub_prev[0]))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.sign_pub[0]))))), 32);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.sign_pub[0]))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[19])), 32);
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:status=signing_key_verified\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "command_rekey_ed25519");
        }
        if (!false) break;
    }
    return;
}
pub fn command_rekey(S: [*c]struct_a12_state) callconv(.c) void {
    {
        const smon = @import("shmif_monitor");
        const snprintf_p = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf_p: [96]u8 = undefined;
        _ = snprintf_p(&buf_p, 96, "a12:coverage:rekey_recv:mode=%u", @as(c_uint, S.*.decode[18]));
        smon.emitLuaTag(@ptrCast(&buf_p));
    }
    if ((@as(c_int, @bitCast(@as(c_uint, S.*.decode[18]))) == REKEY_MODE_KEM768_PUBLIC) or (@as(c_int, @bitCast(@as(c_uint, S.*.decode[18]))) == REKEY_MODE_KEM768_CIPHERTEXT)) {
        return command_rekey_pqc(S);
    }
    if (@as(c_int, @bitCast(@as(c_uint, S.*.decode[18]))) == REKEY_MODE_EDSIGN) {
        return command_rekey_ed25519(S);
    }
    if (S.*.keys.own_rekey) {
        fail_state(S, "rekey-not-theirs");
        return;
    }
    if (@as(c_int, @bitCast(@as(c_uint, S.*.decode[18]))) != REKEY_MODE_RATCHET) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:source=rekey:unknown_rekey_method=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_rekey", @as(c_int, @bitCast(@as(c_uint, S.*.decode[18]))));
            }
            if (!false) break;
        }
        fail_state(S, "rekey-bad-method");
        return;
    }
    var ssecret: [32]u8 = undefined;
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.remote_pub[0]))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[19])), 32);
    trace_crypto_key(S, S.*.server, "rekey_priv", @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), 32);
    trace_crypto_key(S, S.*.server, "rekey_new_pub", @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.remote_pub[0]))), 32);
    _ = x25519_shared_secret(@as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv[0]))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.remote_pub[0]))));
    chacha_setup(chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), 32, 0, 8);
    chacha_set_nonce(chacha_cast(S.*.dec_state), &S.*.decode[8]);
    trace_crypto_key(S, S.*.server, "rekey_nonce", &S.*.decode[8], 8);
    var mac_key: [32]u8 = undefined;
    var temp: blake3_hasher = undefined;
    blake3_hasher_init_derive_key(&temp, "arcan-a12 rekey");
    blake3_hasher_update(&temp, @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))))), 32);
    blake3_hasher_finalize(&temp, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))), 32);
    blake3_hasher_init_keyed(&S.*.out_mac, @as([*c]u8, @ptrCast(@alignCast(&mac_key[0]))));
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:rekey\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "command_rekey");
        }
        if (!false) break;
    }
    trace_crypto_key(S, S.*.server, "rekey_shared_in", @as([*c]u8, @ptrCast(@alignCast(&ssecret[0]))), 32);
    S.*.keys.own_rekey = true;
}
pub fn command_binarystream(S: [*c]struct_a12_state) callconv(.c) void {
    const channel: u8 = S.*.decode[16];
    const bframe: [*c]struct_binary_frame = &S.*.channels[channel].unpack_state.bframe;
    if (bframe.*.active) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:source=binarystream:kind=EEXIST:ch=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_binarystream", @as(c_int, @bitCast(@as(c_uint, channel))));
            }
            if (!false) break;
        }
        a12_stream_cancel(S, channel);
        bframe.*.active = false;
        if (bframe.*.tmp_fd > 0) {
            bframe.*.tmp_fd = -1;
        }
        mark_bstream_progress(S, channel, -1, 0, 0);
        return;
    }
    if (@as(c_int, @bitCast(@as(c_uint, S.*.decode[52]))) == 1) {
        bframe.*.zstd = ZSTD_createDCtx();
        if (!(bframe.*.zstd != null)) {
            a12_stream_cancel(S, channel);
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:source=binarystream:kind=zstd_fail:ch=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_binarystream", @as(c_int, @bitCast(@as(c_uint, channel))));
                }
                if (!false) break;
            }
            return;
        }
    }
    var streamid: u32 = undefined;
    unpack_u32(&streamid, &S.*.decode[18]);
    var swallow: bool = false;
    var sc: c_int = A12_BHANDLER_DONTWANT;
    if ((S.*.pending_in != null) and (S.*.pending_in.*.streamid == @as(u64, @bitCast(@as(c_ulong, streamid))))) {
        bframe.*.tmp_fd = S.*.pending_in.*.fd;
        swallow = true;
        sc = A12_BHANDLER_NEWFD;
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=resolve_queued_bstream:swallow:id=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "command_binarystream", streamid);
            }
            if (!false) break;
        }
    } else {
        bframe.*.tmp_fd = -1;
    }
    bframe.*.streamid = @as(i64, @bitCast(@as(c_ulong, streamid)));
    unpack_u64(&bframe.*.size, &S.*.decode[22]);
    bframe.*.type = @as(c_int, @bitCast(@as(c_uint, S.*.decode[30])));
    unpack_u32(&bframe.*.identifier, &S.*.decode[31]);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&bframe.*.checksum[0]))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[35])), 16);
    bframe.*.active = true;
    S.*.channels[channel].progress.total = bframe.*.size;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=header:stream=%ld:left=%lu:ch=%d:compressed=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "command_binarystream", bframe.*.streamid, bframe.*.size, @as(c_int, @bitCast(@as(c_uint, channel))), @as(c_int, @bitCast(@as(c_uint, S.*.decode[52]))));
        }
        if (!false) break;
    }
    var bm: struct_a12_bhandler_meta = struct_a12_bhandler_meta{
        .state = @as(c_uint, @bitCast(A12_BHANDLER_INITIALIZE)),
        .type = @as(c_uint, @bitCast(bframe.*.type)),
        .checksum = std.mem.zeroes([16]u8),
        .known_size = bframe.*.size,
        .streaming = false,
        .channel = std.mem.zeroes(u8),
        .streamid = bframe.*.streamid,
        .identifier = bframe.*.identifier,
        .extid = std.mem.zeroes([17]u8),
        .fd = -1,
        .dcont = S.*.channels[channel].cont,
    };
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&bm.checksum[0]))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&bframe.*.checksum[0]))))), 16);
    mark_bstream_progress(S, channel, 0, 0, 0);
    if (!swallow and (S.*.binary_handler != null)) {
        const res: struct_a12_bhandler_res = S.*.binary_handler.?(S, bm, S.*.binary_handler_tag);
        bframe.*.tmp_fd = res.fd;
        sc = @as(c_int, @bitCast(res.flag));
    }
    if ((sc == A12_BHANDLER_DONTWANT) or (sc == A12_BHANDLER_CACHED)) {
        a12_stream_cancel(S, channel);
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=reject:stream=%ld:ch=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "command_binarystream", bframe.*.streamid, @as(c_int, @bitCast(@as(c_uint, channel))));
            }
            if (!false) break;
        }
    }
}
pub fn build_cancel_packet(S: [*c]struct_a12_state, channel: u8, id: u32, @"type": u8) callconv(.c) void {
    var outb: [128]u8 = [1]u8{0} ++ [1]u8{0} ** 127;
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_CANCELSTREAM)))));
    outb[16] = channel;
    pack_u32(id, &outb[18]);
    outb[23] = @"type";
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
}
pub fn command_audioframe(S: [*c]struct_a12_state) callconv(.c) void {
    const channel: u8 = S.*.decode[16];
    {
        const smon = @import("shmif_monitor");
        const snprintf_p = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf_p: [96]u8 = undefined;
        _ = snprintf_p(&buf_p, 96, "a12:coverage:audio_decode:ch=%u:fmt=%u",
            @as(c_uint, channel), @as(c_uint, S.*.decode[22]));
        smon.emitLuaTag(@ptrCast(&buf_p));
    }
    const aframe: [*c]struct_audio_frame = &S.*.channels[channel].unpack_state.aframe;
    unpack_u32(&aframe.*.id, &S.*.decode[18]);
    aframe.*.format = S.*.decode[22];
    aframe.*.encoding = S.*.decode[23];
    aframe.*.channels = S.*.decode[22];
    unpack_u16(&aframe.*.nsamples, &S.*.decode[24]);
    unpack_u32(&aframe.*.rate, &S.*.decode[26]);
    S.*.in_channel = -1;
    if (!(S.*.channels[channel].active != 0)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:no segment mapped on channel %d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_audioframe", @as(c_int, @bitCast(@as(c_uint, channel))));
            }
            if (!false) break;
        }
        aframe.*.commit = 255;
        return;
    }
}
// src/a12/a12.c:1646:3: warning: TODO implement translation of stmt class GotoStmtClass

// Hand-ported from src/a12/a12.c:1649-1672. Original used `goto fail` twice; restructured with flag.
fn update_proxy_vcont(channel: ?*struct_a12_channel, vframe: [*c]struct_video_frame) callconv(.c) void {
    const ch = channel.?;
    const cont: [*c]struct_arcan_shmif_cont = ch.cont;
    var fail: bool = false;
    if (ch.raw.request_raw_buffer == null) {
        fail = true;
    } else {
        cont.*.unnamed_0.vidp = ch.raw.request_raw_buffer.?(
            vframe.*.sw, vframe.*.sh, &ch.cont.*.stride,
            @as(c_int, @bitCast(@as(c_uint, ch.cont.*.hints))), ch.raw.tag);
        cont.*.pitch = ch.cont.*.stride / @sizeOf(shmif_pixel);
        cont.*.w = vframe.*.sw;
        cont.*.h = vframe.*.sh;
        if (cont.*.unnamed_0.vidp == null) {
            fail = true;
        }
    }
    if (fail) {
        cont.*.w = 0;
        cont.*.h = 0;
        vframe.*.commit = 255;
    }
}
// Hand-ported from src/a12/a12.c:1674-1695. Original used `goto fail` twice; restructured with flag.
fn update_proxy_acont(channel: ?*struct_a12_channel, aframe: [*c]struct_audio_frame) callconv(.c) bool {
    const ch = channel.?;
    var fail: bool = false;
    if (ch.raw.request_audio_buffer == null) {
        fail = true;
    } else {
        ch.cont.*.unnamed_1.audp = ch.raw.request_audio_buffer.?(
            @as(usize, aframe.*.channels),
            @as(usize, @bitCast(@as(c_ulong, aframe.*.rate))),
            @sizeOf(shmif_asample) * @as(usize, aframe.*.channels),
            ch.raw.tag);
        if (ch.cont.*.unnamed_1.audp == null) {
            fail = true;
        }
    }
    if (fail) {
        aframe.*.commit = 255;
        return false;
    }
    return true;
}
pub fn command_newchannel(S: [*c]struct_a12_state, on_event: ?*const fn ([*c]struct_arcan_shmif_cont, c_int, [*c]struct_arcan_event, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) callconv(.c) void {
    const channel: u8 = S.*.decode[16];
    const new_channel: u8 = S.*.decode[18];
    const @"type": u8 = S.*.decode[19];
    const direction: u8 = S.*.decode[20];
    var cookie: u32 = undefined;
    unpack_u32(&cookie, &S.*.decode[21]);
    {
        const smon = @import("shmif_monitor");
        const snprintf_p = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf_p: [96]u8 = undefined;
        _ = snprintf_p(&buf_p, 96, "a12:coverage:newchannel:parent=%u:new=%u:kind=%u:dir=%u",
            @as(c_uint, channel), @as(c_uint, new_channel),
            @as(c_uint, @"type"), @as(c_uint, direction));
        smon.emitLuaTag(@ptrCast(&buf_p));
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:new channel: %u => %u, kind: %u, cookie: %u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "command_newchannel", @as(c_int, @bitCast(@as(c_uint, channel))), @as(c_int, @bitCast(@as(c_uint, new_channel))), @as(c_int, @bitCast(@as(c_uint, @"type"))), cookie);
        }
        if (!false) break;
    }
    var ev: struct_arcan_event = struct_arcan_event{
        .unnamed_0 = union_unnamed_9{
            .unnamed_0 = struct_unnamed_10{
                .unnamed_0 = union_unnamed_11{
                    .tgt = arcan_tgtevent{
                        .kind = @as(c_uint, @bitCast(TARGET_COMMAND_NEWSEGMENT)),
                        .ioevs = std.mem.zeroes([8]union_unnamed_24),
                        .code = 0,
                        .unnamed_0 = std.mem.zeroes(union_unnamed_25),
                    },
                },
                .category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_TARGET)))),
            },
        },
    };
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @as(i32, @bitCast(@as(c_uint, new_channel)));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = @intFromBool(@as(c_int, @bitCast(@as(c_uint, direction))) != 0);
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = @as(i32, @bitCast(@as(c_uint, @"type")));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv = cookie;
    on_event.?(S.*.channels[channel].cont, @as(c_int, @bitCast(@as(c_uint, channel))), &ev, tag);
}
pub fn command_videoframe(S: [*c]struct_a12_state) callconv(.c) void {
    const smon = @import("shmif_monitor");
    smon.emitLuaTag("a12:command_videoframe");
    {
        const ch_probe: u8 = S.*.decode[16];
        const method_probe: u8 = S.*.decode[22];
        var sw_probe: u16 = 0;
        var sh_probe: u16 = 0;
        unpack_u16(&sw_probe, &S.*.decode[23]);
        unpack_u16(&sh_probe, &S.*.decode[25]);
        const snprintf_v = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var bufv: [96]u8 = undefined;
        _ = snprintf_v(&bufv, 96, "a12:vframe_hdr:ch=%d:method=%d:sw=%d:sh=%d",
            @as(c_int, ch_probe), @as(c_int, method_probe),
            @as(c_int, sw_probe), @as(c_int, sh_probe));
        smon.emitLuaTag(@ptrCast(&bufv));
    }
    const ch: u8 = S.*.decode[16];
    const method: c_int = @as(c_int, @bitCast(@as(c_uint, S.*.decode[22])));
    const channel: ?*struct_a12_channel = &S.*.channels[ch];
    const vframe: [*c]struct_video_frame = &S.*.channels[ch].unpack_state.vframe;
    if (!a12int_vframe_setup(S, channel, vframe, method)) {
        vframe.*.commit = 255;
        a12int_stream_fail(S, ch, 1, STREAM_FAIL_UNKNOWN);
        // Kick the remote client to redraw — cancelstream tells the server
        // to mark advenc_broken for this codec; a STEPFRAME event wakes the
        // shmif client's main loop so it pushes a new frame, which now uses
        // the fallback codec. Without this, apps that emit only one frame
        // (avfeed, static image viewers) would stall forever after the
        // first rejected H264 frame.
        var kick: struct_arcan_event = struct_arcan_event.zeroes();
        kick.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_TARGET))));
        kick.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_STEPFRAME));
        kick.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = 1;
        kick.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 1;
        const saved_chid = a12_get_channel(S);
        a12_set_channel(S, ch);
        _ = a12_channel_enqueue(S, &kick);
        a12_set_channel(S, saved_chid);
        return;
    }
    unpack_u32(&vframe.*.id, &S.*.decode[18]);
    vframe.*.postprocess = @as(u8, @bitCast(@as(i8, @truncate(method))));
    unpack_u16(&vframe.*.sw, &S.*.decode[23]);
    unpack_u16(&vframe.*.sh, &S.*.decode[25]);
    unpack_u16(&vframe.*.x, &S.*.decode[27]);
    unpack_u16(&vframe.*.y, &S.*.decode[29]);
    unpack_u16(&vframe.*.w, &S.*.decode[31]);
    unpack_u16(&vframe.*.h, &S.*.decode[33]);
    unpack_u32(&vframe.*.inbuf_sz, &S.*.decode[36]);
    unpack_u32(&vframe.*.expanded_sz, &S.*.decode[40]);
    vframe.*.commit = S.*.decode[44];
    S.*.in_channel = -1;
    const cont: [*c]struct_arcan_shmif_cont = channel.?.*.cont;
    if (!(cont != null)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=videoframe_header:status=EINVAL:channel=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_videoframe", @as(c_int, @bitCast(@as(c_uint, ch))));
            }
            if (!false) break;
        }
        vframe.*.commit = 255;
        return;
    }
    var hints_changed: bool = false;
    if ((@as(c_int, @bitCast(@as(c_uint, S.*.decode[35]))) ^ @intFromBool(!!((@as(c_int, @bitCast(@as(c_uint, cont.*.hints))) & SHMIF_RHINT_ORIGO_LL) != 0))) != 0) {
        if (S.*.decode[35] != 0) {
            cont.*.hints = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, cont.*.hints))) | SHMIF_RHINT_ORIGO_LL))));
        } else {
            cont.*.hints = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, cont.*.hints))) & ~SHMIF_RHINT_ORIGO_LL))));
        }
        hints_changed = true;
    }
    if ((@as(c_int, @bitCast(@as(c_uint, vframe.*.postprocess))) == POSTPROCESS_VIDEO_TZSTD) and !((@as(c_int, @bitCast(@as(c_uint, cont.*.hints))) & SHMIF_RHINT_TPACK) != 0)) {
        cont.*.hints |= @as(u8, @bitCast(@as(i8, @truncate(SHMIF_RHINT_TPACK))));
        hints_changed = true;
    } else if (((@as(c_int, @bitCast(@as(c_uint, cont.*.hints))) & SHMIF_RHINT_TPACK) != 0) and (@as(c_int, @bitCast(@as(c_uint, vframe.*.postprocess))) != POSTPROCESS_VIDEO_TZSTD)) {
        cont.*.hints = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, cont.*.hints))) & ~SHMIF_RHINT_TPACK))));
        hints_changed = true;
    }
    if (channel.?.*.active == CHANNEL_RAW) {
        update_proxy_vcont(channel, vframe);
    } else if (((@as(c_int, @intFromBool(hints_changed)) != 0) or (@as(usize, @bitCast(@as(c_ulong, vframe.*.sw))) != cont.*.w)) or (@as(usize, @bitCast(@as(c_ulong, vframe.*.sh))) != cont.*.h)) {
        {
            const smon_a = @import("shmif_monitor");
            const snprintf_a = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
            var buf_a: [96]u8 = undefined;
            _ = snprintf_a(&buf_a, 96, "a12:resize_call:want=%dx%d:cur=%dx%d",
                @as(c_int, vframe.*.sw), @as(c_int, vframe.*.sh),
                @as(c_int, @intCast(cont.*.w)), @as(c_int, @intCast(cont.*.h)));
            smon_a.emitLuaTag(@ptrCast(&buf_a));
        }
        _ = arcan_shmif_resize(cont, @as(c_uint, @bitCast(@as(c_uint, vframe.*.sw))), @as(c_uint, @bitCast(@as(c_uint, vframe.*.sh))));
        {
            const smon_b = @import("shmif_monitor");
            const snprintf_b = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
            var buf_b: [96]u8 = undefined;
            _ = snprintf_b(&buf_b, 96, "a12:resize_done:cont=%dx%d",
                @as(c_int, @intCast(cont.*.w)), @as(c_int, @intCast(cont.*.h)));
            smon_b.emitLuaTag(@ptrCast(&buf_b));
        }
        if ((@as(usize, @bitCast(@as(c_ulong, vframe.*.sw))) != cont.*.w) or (@as(usize, @bitCast(@as(c_ulong, vframe.*.sh))) != cont.*.h)) {
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:parent size rejected\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_videoframe");
                }
                if (!false) break;
            }
            vframe.*.commit = 255;
        } else while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=resized:channel=%d:hints=%d:new_w=%zu:new_h=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "command_videoframe", @as(c_int, @bitCast(@as(c_uint, ch))), @as(c_int, @bitCast(@as(c_uint, cont.*.hints))), @as(usize, @bitCast(@as(c_ulong, vframe.*.sw))), @as(usize, @bitCast(@as(c_ulong, vframe.*.sh))));
            }
            if (!false) break;
        }
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=frame_header:method=%d:source_w=%zu:source_h=%zu:w=%zu:h=%zu:x=%zu,y=%zu:bytes_in=%zu:bytes_out=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "command_videoframe", @as(c_int, @bitCast(@as(c_uint, vframe.*.postprocess))), @as(usize, @bitCast(@as(c_ulong, vframe.*.sw))), @as(usize, @bitCast(@as(c_ulong, vframe.*.sh))), @as(usize, @bitCast(@as(c_ulong, vframe.*.w))), @as(usize, @bitCast(@as(c_ulong, vframe.*.h))), @as(usize, @bitCast(@as(c_ulong, vframe.*.x))), @as(usize, @bitCast(@as(c_ulong, vframe.*.y))), @as(usize, @bitCast(@as(c_ulong, vframe.*.inbuf_sz))), @as(usize, @bitCast(@as(c_ulong, vframe.*.expanded_sz))));
        }
        if (!false) break;
    }
    if ((@as(c_int, @bitCast(@as(c_uint, vframe.*.x))) >= @as(c_int, @bitCast(@as(c_uint, vframe.*.sw)))) or (@as(c_int, @bitCast(@as(c_uint, vframe.*.y))) >= @as(c_int, @bitCast(@as(c_uint, vframe.*.sh))))) {
        vframe.*.commit = 255;
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:x=%zu:y=%zu:w=%zu:h=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_videoframe", @as(usize, @bitCast(@as(c_ulong, vframe.*.x))), @as(usize, @bitCast(@as(c_ulong, vframe.*.y))), @as(usize, @bitCast(@as(c_ulong, vframe.*.w))), @as(usize, @bitCast(@as(c_ulong, vframe.*.h))));
            }
            if (!false) break;
        }
        return;
    }
    if (((@as(c_int, @bitCast(@as(c_uint, vframe.*.postprocess))) == POSTPROCESS_VIDEO_RGBA) or (@as(c_int, @bitCast(@as(c_uint, vframe.*.postprocess))) == POSTPROCESS_VIDEO_RGB565)) or (@as(c_int, @bitCast(@as(c_uint, vframe.*.postprocess))) == POSTPROCESS_VIDEO_RGB)) {
        vframe.*.row_left = @as(usize, @bitCast(@as(c_long, @as(c_int, @bitCast(@as(c_uint, vframe.*.w))) - @as(c_int, @bitCast(@as(c_uint, vframe.*.x))))));
        vframe.*.out_pos = (@as(usize, @bitCast(@as(c_ulong, vframe.*.y))) *% cont.*.pitch) +% @as(usize, @bitCast(@as(c_ulong, vframe.*.x)));
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_TRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:row-length: %zu at buffer pos %u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_TRANSFER), "command_videoframe", vframe.*.row_left, vframe.*.inbuf_pos);
            }
            if (!false) break;
        }
    } else {
        const ulim: usize = @as(c_ulong, @bitCast(@as(c_long, @as(c_int, @bitCast(@as(c_uint, vframe.*.w))) * @as(c_int, @bitCast(@as(c_uint, vframe.*.h)))))) *% @sizeOf(shmif_pixel);
        if (@as(usize, @bitCast(@as(c_ulong, vframe.*.expanded_sz))) > ulim) {
            vframe.*.commit = 255;
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:expanded=%zu:limit=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_videoframe", @as(usize, @bitCast(@as(c_ulong, vframe.*.expanded_sz))), ulim);
                }
                if (!false) break;
            }
            return;
        }
        if (vframe.*.inbuf_sz > (vframe.*.expanded_sz +% 24)) {
            vframe.*.commit = 255;
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:incoming buffer (%u) expands to less than target (%u)\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_videoframe", vframe.*.inbuf_sz, vframe.*.expanded_sz);
                }
                if (!false) break;
            }
            vframe.*.inbuf_pos = 0;
            return;
        }
        vframe.*.out_pos = (@as(usize, @bitCast(@as(c_ulong, vframe.*.y))) *% cont.*.pitch) +% @as(usize, @bitCast(@as(c_ulong, vframe.*.x)));
        vframe.*.inbuf_pos = 0;
        vframe.*.inbuf = @as([*c]u8, @ptrCast(@alignCast(malloc(vframe.*.inbuf_sz))));
        if (vframe.*.inbuf == null) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:couldn't allocate intermediate buffer store\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "command_videoframe");
            }
            return;
        }
        vframe.*.row_left = @as(usize, @bitCast(@as(c_ulong, vframe.*.w)));
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:compressed buffer in (%u) to offset (%zu)\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "command_videoframe", vframe.*.inbuf_sz, vframe.*.out_pos);
        }
    }
}
pub fn alloc_attach_blob(S: [*c]struct_a12_state, parent_arg: [*c][*c]struct_blob_xfer) callconv(.c) [*c][*c]struct_blob_xfer {
    var parent = parent_arg;
    const next: [*c]struct_blob_xfer = @ptrCast(@alignCast(malloc(@sizeOf(struct_blob_xfer))));
    if (next == null) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=ENOMEM\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "alloc_attach_blob");
        }
        return null;
    }
    next.* = struct_blob_xfer{
        .checksum = std.mem.zeroes([16]u8),
        .fd = -1,
        .chid = @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel)))),
        .type = A12_BTYPE_BLOB,
        .identifier = 0,
        .extid = std.mem.zeroes([16]u8),
        .left = 0,
        .buf = null,
        .buf_sz = 0,
        .streaming = true,
        .active = false,
        .uncompressed = false,
        .streamid = 0,
        .rampup_seqnr = 0,
        .tag = null,
        .zstd = null,
        .next = null,
    };
    var n_streaming: usize = 0;
    var n_known: usize = 0;
    while (parent.* != null) {
        if (parent.*.*.streaming) {
            n_streaming +%= 1;
        } else {
            n_known +%= parent.*.*.left;
        }
        parent = &parent.*.*.next;
    }
    parent.* = next;
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=reserve:queue=%zu:total=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "alloc_attach_blob", n_streaming, n_known);
    }
    return parent;
}
// src/a12/a12.c:2013:10: warning: unsupported type: 'VariableArray'

// Hand-ported from src/a12/a12.c:2014-2035. The original used a VLA `uint8_t outb[header_sizes[STATE_EVENT_PACKET]]`.
// header_sizes[STATE_EVENT_PACKET] is computed at a12_init() time; the max is evsz + 8 + 1. Use a generous fixed max.
fn pack_and_send_event_explicit(S: [*c]struct_a12_state, ev: [*c]struct_arcan_event, chid: u8) callconv(.c) bool {
    // Size it to the configured header size; cap at a reasonable ceiling.
    // header_sizes[STATE_EVENT_PACKET] = arcan_shmif_eventpack_sz + 8 + 1 (see a12_init).
    var outb: [1024]u8 = undefined;
    const packet_sz: usize = @as(usize, @intCast(header_sizes[@as(usize, @intCast(STATE_EVENT_PACKET))]));
    const hdr: usize = 8 + 1; // SEQUENCE_NUMBER_SIZE + 1
    outb[8] = chid; // outb[SEQUENCE_NUMBER_SIZE] = chid
    step_sequence(S, @as([*c]u8, @ptrCast(&outb[0])));
    const step: isize = arcan_shmif_eventpack(ev, &outb[hdr], packet_sz - hdr);
    if (step == -1) return false;
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_EVENT_PACKET)))), @as([*c]u8, @ptrCast(&outb[0])), @as(usize, @intCast(step)) + hdr, null, 0);
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_EVENT) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=enqueue:eventstr=%s\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_EVENT), "pack_and_send_event_explicit", arcan_shmif_eventstr(ev, null, 0));
    }
    return true;
}
pub fn pack_and_send_event(S: [*c]struct_a12_state, ev: [*c]struct_arcan_event) callconv(.c) bool {
    return pack_and_send_event_explicit(S, ev, @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel)))));
}
pub fn a12_enqueue_bstream_in(S: [*c]struct_a12_state, fd: c_int, @"type": c_int, ev: [*c]struct_arcan_event) callconv(.c) bool {
    const parent: [*c][*c]struct_blob_xfer = alloc_attach_blob(S, &S.*.pending_in);
    if (parent == null) {
        return false;
    }
    const next: [*c]struct_blob_xfer = parent.*;
    next.*.type = @"type";
    next.*.identifier = ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv;
    next.*.streamid = blk: {
        const ref = &S.*.out_stream;
        const tmp = ref.*;
        ref.* +%= 1;
        break :blk tmp;
    };
    next.*.fd = a12int_dupfd(fd);
    next.*.chid = @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel))));
    var outev: arcan_event = arcan_event{
        .unnamed_0 = union_unnamed_9{
            .unnamed_0 = struct_unnamed_10{
                .unnamed_0 = union_unnamed_11{
                    .ext = arcan_extevent{
                        .kind = @as(c_uint, @bitCast(EVENT_EXTERNAL_BCHUNKSTATE)),
                        .source = 0,
                        .unnamed_0 = union_unnamed_26{
                            .bchunk = struct_unnamed_31{
                                .unnamed_0 = union_unnamed_32{
                                    .ns = @as(u64, @bitCast(@as(c_ulong, ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv))),
                                },
                                .input = 1,
                                .hint = 0,
                                .stream = 0,
                                .extensions = std.mem.zeroes([68]u8),
                                .identifier = @as(u32, @bitCast(@as(c_uint, @truncate(next.*.streamid)))),
                            },
                        },
                        .frame_id = 0,
                    },
                },
                .category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_EXTERNAL)))),
            },
        },
    };
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions)), @as(?*const anyopaque, @ptrCast(&ev.*.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)), @sizeOf([68]u8));
    const copy: [*c]arcan_event = @ptrCast(@alignCast(malloc(@sizeOf(arcan_event))));
    copy.* = outev;
    next.*.tag = @as(?*anyopaque, @ptrCast(copy));
    if (-1 == next.*.fd) {
        parent.* = null;
        free(@as(?*anyopaque, @ptrCast(next)));
        return false;
    }
    S.*.channels[@as(c_uint, @intCast(S.*.out_channel))].active = 1;
    if (!S.*.channels[@as(c_uint, @intCast(S.*.out_channel))].unpack_state.bframe.active) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=empty_queue:request_inbound=%s:id=%ld\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_enqueue_bstream_in", @as([*c]u8, @ptrCast(@alignCast(&outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions))), next.*.streamid);
        }
        _ = pack_and_send_event(S, &outev);
    } else {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=queue_inbound_transfer:name=%s:id=%ld\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_enqueue_bstream_in", @as([*c]u8, @ptrCast(@alignCast(&outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions))), next.*.streamid);
        }
    }
    return true;
}
// Hand-ported from src/a12/a12.c:2103-2254. Original had 3 `goto fail` jumps to a single cleanup label.
// Structured with a labeled `body` block + explicit fail-flag, then cleanup after.
fn a12_enqueue_bstream_tagged(S: [*c]struct_a12_state, fd: c_int, @"type": c_int, id: u32, streaming: bool, sz: usize, extid: [*c]const u8, tag: [*c]arcan_event) callconv(.c) void {
    const parent: [*c][*c]struct_blob_xfer = alloc_attach_blob(S, &S.*.pending_out);
    if (parent == null) return;
    const next: [*c]struct_blob_xfer = parent.*;
    next.*.type = @"type";
    next.*.identifier = id;
    next.*.chid = @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel))));
    next.*.streamid = @as(u64, id);
    S.*.channels[@as(c_uint, @intCast(S.*.out_channel))].active = 1;

    if (tag != null) {
        const copy: [*c]arcan_event = @ptrCast(@alignCast(DYNAMIC_MALLOC(@sizeOf(arcan_event))));
        copy.* = tag.*;
        next.*.tag = @as(?*anyopaque, @ptrCast(copy));
    }

    if (@"type" == c.A12_BTYPE_APPL or @"type" == c.A12_BTYPE_APPL_RESOURCE) {
        _ = snprintf(@as([*c]u8, @ptrCast(&next.*.extid[0])), 16, "%s", extid);
    }

    if (@"type" == A12_BTYPE_FONT_SUPPL or @"type" == A12_BTYPE_FONT) {
        next.*.rampup_seqnr = S.*.current_seqnr + 1;
    }

    var do_fail: bool = false;
    body: {
        next.*.fd = a12int_dupfd(fd);
        if (next.*.fd == -1) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EBADFD\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_enqueue_bstream_tagged");
            }
            do_fail = true;
            break :body;
        }
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=queue_outbound:ch=%u:descriptor=%d:id=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_enqueue_bstream_tagged", @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(@as(i8, @truncate(S.*.out_channel))))))), next.*.fd, id);
        }

        var size_mb: usize = 0;
        if (sz != 0) size_mb = sz / (1024 * 1024);

        if (streaming or size_mb > S.*.opts.*.checksum_cap_mb) {
            next.*.streaming = true;
            next.*.left = sz;
            return;
        }

        // Empty-file edge case: treat as streaming with nothing.
        const fend: off_t = c.lseek(fd, 0, c.SEEK_END);
        if (fend == 0) {
            next.*.streaming = false;
            next.*.left = 0;
            next.*.uncompressed = true;
            return;
        }

        if (fend == -1) {
            const eno: c_int = __errno_location().*;
            if (eno == c.ESPIPE or eno == c.EOVERFLOW) {
                next.*.streaming = true;
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=added:type=%d:stream=yes:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_enqueue_bstream_tagged", @"type", next.*.left);
                }
                return;
            }
            // EINVAL, EBADF, default → log and fall-through to trying lseek SEEK_SET (original does that).
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EBADFD\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_enqueue_bstream_tagged");
            }
        }

        if (c.lseek(fd, 0, c.SEEK_SET) == -1) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=ESEEK\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_enqueue_bstream_tagged");
            }
            do_fail = true;
            break :body;
        }

        if (fend != 0) {
            size_mb = @as(usize, @intCast(fend)) / (1024 * 1024);
            if (size_mb > S.*.opts.*.checksum_cap_mb) {
                next.*.streaming = true;
                next.*.left = @as(usize, @intCast(fend));
                return;
            }
        }

        // A12INT_PROT_READ = 0x1, A12INT_MAP_PRIVATE = 0x2 (see a12_platform.h).
        const map: ?*anyopaque = a12int_mmap(null, @as(usize, @intCast(fend)), 0x1, 0x2, fd, 0);
        if (map == null) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EMMAP\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "a12_enqueue_bstream_tagged");
            }
            do_fail = true;
            break :body;
        }

        var hash: blake3_hasher = undefined;
        blake3_hasher_init(&hash);
        blake3_hasher_update(&hash, @as(?*const anyopaque, @ptrCast(map)), @as(usize, @intCast(fend)));
        blake3_hasher_finalize(&hash, @as([*c]u8, @ptrCast(&next.*.checksum[0])), 16);
        _ = a12int_munmap(map, @as(usize, @intCast(fend)));
        next.*.left = @as(usize, @intCast(fend));
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=added:type=%d:stream=%u:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_enqueue_bstream_tagged", id, @"type", next.*.left);
        }
        return;
    }
    // do_fail cleanup
    if (do_fail) {
        if (next.*.fd != -1) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=fail:close_descriptor=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "a12_enqueue_bstream_tagged", next.*.fd);
            }
            _ = close(next.*.fd);
        }
        parent.* = null;
        DYNAMIC_FREE(@as(?*anyopaque, @ptrCast(next)));
    }
}
pub fn authdec_buffer(src: [*c]const u8, S: [*c]struct_a12_state, block_sz: usize) callconv(.c) bool {
    var mac_size: usize = 16;
    if (S.*.authentic == AUTH_SERVER_HBLOCK) {
        mac_size = 8;
        trace_crypto_key(S, S.*.server, "auth_mac_in", @as([*c]u8, @ptrCast(@alignCast(&S.*.last_mac_in))), mac_size);
    }
    update_mac_and_decrypt(S, "authdec_buffer", &S.*.in_mac, chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(@alignCast(&S.*.decode))), block_sz);
    var ref_mac: [16]u8 = undefined;
    blake3_hasher_finalize(&S.*.in_mac, @as([*c]u8, @ptrCast(@alignCast(&ref_mac))), mac_size);
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=mac_dec:src=%s:pos=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "authdec_buffer", src, S.*.in_mac.counter);
    }
    trace_crypto_key(S, S.*.server, "auth_mac_rf", @as([*c]u8, @ptrCast(@alignCast(&ref_mac))), mac_size);
    const res: bool = memcmp(@as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&ref_mac))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.last_mac_in))))), mac_size) == 0;
    if (!res) {
        trace_crypto_key(S, S.*.server, "bad_mac", @as([*c]u8, @ptrCast(@alignCast(&S.*.last_mac_in))), mac_size);
    }
    return res;
}
pub fn hello_auth_server_hello(S: [*c]struct_a12_state) callconv(.c) void {
    var pubk: [32]u8 = undefined;
    var remote_pubk: [32]u8 = undefined;
    const cfl: c_int = @as(c_int, @bitCast(@as(c_uint, S.*.decode[20])));
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&remote_pubk))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[21])), 32);
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:state=complete:method=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "hello_auth_server_hello", cfl);
    }
    if ((cfl != HELLO_MODE_EPHEMPK) and (cfl != HELLO_MODE_REALPK)) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SECURITY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:unknown_hello\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SECURITY), "hello_auth_server_hello");
        }
        fail_state(S, "bad-auth-mode");
        return;
    }
    if (cfl == HELLO_MODE_EPHEMPK) {
        var ek: [32]u8 = undefined;
        var nonce: [8]u8 = undefined;
        x25519_private_key(@as([*c]u8, @ptrCast(@alignCast(&ek))));
        x25519_public_key(@as([*c]u8, @ptrCast(@alignCast(&ek))), @as([*c]u8, @ptrCast(@alignCast(&pubk))));
        arcan_random(@as([*c]u8, @ptrCast(@alignCast(&nonce))), 8);
        send_hello_packet(S, HELLO_MODE_EPHEMPK, @as([*c]u8, @ptrCast(@alignCast(&pubk))), @as([*c]u8, @ptrCast(@alignCast(&nonce))));
        _ = x25519_shared_secret(@as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), @as([*c]u8, @ptrCast(@alignCast(&ek))), @as([*c]u8, @ptrCast(@alignCast(&remote_pubk))));
        trace_crypto_key(S, S.*.server, "ephem_pub", @as([*c]u8, @ptrCast(@alignCast(&pubk))), 32);
        update_keymaterial(S, @as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), 32, @as([*c]u8, @ptrCast(@alignCast(&nonce))));
        S.*.authentic = AUTH_EPHEMERAL_PK;
        return;
    }
    if (S.*.opts.*.pk_lookup == null) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:state=eimpl:kind=x25519-no-lookup\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "hello_auth_server_hello");
        }
        fail_state(S, "api-no-pk-auth");
        return;
    }
    trace_crypto_key(S, S.*.server, "state=client_pk", @as([*c]u8, @ptrCast(@alignCast(&remote_pubk))), 32);
    var res: struct_pk_response = S.*.opts.*.pk_lookup.?(S, @as([*c]u8, @ptrCast(@alignCast(&remote_pubk))), S.*.opts.*.pk_lookup_tag);
    if (!res.authentic) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:state=eperm:kind=x25519-pk-fail\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "hello_auth_server_hello");
        }
        fail_state(S, "pk-reject-srv");
        return;
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&res.key_session))))), 32);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&pubk))))), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&res.key_pub))))), 32);
    arcan_random(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.auth_csrnd))), 8);
    send_hello_packet(S, HELLO_MODE_REALPK, @as([*c]u8, @ptrCast(@alignCast(&pubk))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.auth_csrnd))));
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.remote_pub))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[21])), 32);
    trace_crypto_key(S, S.*.server, "state=client_pk_ok:respond_pk", @as([*c]u8, @ptrCast(@alignCast(&pubk))), 32);
    trace_crypto_key(S, S.*.server, "state=signing_seed", @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.auth_csrnd))), 8);
    trace_crypto_key(S, S.*.server, "state=server_ssecret", @as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), 32);
    update_keymaterial(S, @as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), 32, @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.auth_csrnd))));
    S.*.authentic = AUTH_FULL_PK;
    if (S.*.opts.*.pqc_rekey) {
        var outbuf: [1184]u8 = undefined;
        _ = mlkem_keypair(@as([*c]u8, @ptrCast(@alignCast(&outbuf))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.pqc_private_buffer))));
        chunk_and_send_pqc(S, @as([*c]u8, @ptrCast(@alignCast(&outbuf))), 1184, @as(u8, @bitCast(@as(i8, @truncate(REKEY_MODE_KEM768_PUBLIC)))), null);
    }
    S.*.auth_latched = true;
    if (S.*.on_auth != null) {
        S.*.on_auth.?(S, S.*.auth_tag);
    }
}
pub fn hello_auth_client_hello(S: [*c]struct_a12_state) callconv(.c) void {
    if (S.*.opts.*.pk_lookup == null) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:state=eimpl:kind=x25519-no-lookup\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "hello_auth_client_hello");
        }
        fail_state(S, "api-no-pk-auth");
        return;
    }
    trace_crypto_key(S, S.*.server, "server_pk", &S.*.decode[21], 32);
    const res: struct_pk_response = S.*.opts.*.pk_lookup.?(S, &S.*.decode[21], S.*.opts.*.pk_lookup_tag);
    if (!res.authentic) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:state=eperm:kind=25519-pk-fail\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "hello_auth_client_hello");
        }
        fail_state(S, "pk-reject-client");
        return;
    }
    _ = x25519_shared_secret(@as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv))), &S.*.decode[21]);
    trace_crypto_key(S, S.*.server, "state=client_ssecret", @as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), 32);
    update_keymaterial(S, @as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), 32, &S.*.decode[8]);
    S.*.authentic = AUTH_FULL_PK;
    S.*.auth_latched = true;
    S.*.remote_mode = @as(c_int, @bitCast(@as(c_uint, S.*.decode[54])));
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.auth_csrnd))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[8])), 8);
    trace_crypto_key(S, S.*.server, "state=signing_seed", @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.auth_csrnd))), 8);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.remote_pub))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[21])), 32);
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:remote_mode=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "hello_auth_client_hello", S.*.remote_mode);
    }
    if (S.*.opts.*.pqc_rekey) {
        var outbuf: [1184]u8 = undefined;
        _ = mlkem_keypair(@as([*c]u8, @ptrCast(@alignCast(&outbuf))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.pqc_private_buffer))));
        chunk_and_send_pqc(S, @as([*c]u8, @ptrCast(@alignCast(&outbuf))), 1184, @as(u8, @bitCast(@as(i8, @truncate(REKEY_MODE_KEM768_PUBLIC)))), null);
    }
    if (S.*.on_auth != null) {
        S.*.on_auth.?(S, S.*.auth_tag);
    }
}
pub fn process_hello_auth(S: [*c]struct_a12_state) callconv(.c) void {
    if (S.*.decode[54] != 0) {
        S.*.remote_mode = ROLE_PROBE;
        if ((S.*.opts.*.local_role == ROLE_SOURCE) and (@as(c_int, @bitCast(@as(c_uint, S.*.decode[54]))) == ROLE_SINK)) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=match:local=source:remote=sink\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
            }
            S.*.remote_mode = ROLE_SINK;
        } else if ((S.*.opts.*.local_role == ROLE_SINK) and (@as(c_int, @bitCast(@as(c_uint, S.*.decode[54]))) == ROLE_SOURCE)) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=match:local=sink:remote=source\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
            }
            S.*.remote_mode = ROLE_SOURCE;
        } else if ((S.*.opts.*.local_role == ROLE_SINK) and (@as(c_int, @bitCast(@as(c_uint, S.*.decode[54]))) == ROLE_SINK)) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=mismatch:local=sink:remote=sink\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
            }
            fail_state(S, "sink-sink-role");
            return;
        } else if (S.*.opts.*.local_role == ROLE_PROBE) {} else if (@as(c_int, @bitCast(@as(c_uint, S.*.decode[54]))) == ROLE_PROBE) {
            if (S.*.opts.*.local_role != ROLE_PROBE) {} else {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:probe\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
                }
                fail_state(S, "probe-probe-role");
                return;
            }
        } else if (@as(c_int, @bitCast(@as(c_uint, S.*.decode[54]))) == ROLE_DIR) {
            S.*.remote_mode = ROLE_DIR;
            if ((S.*.opts.*.local_role != ROLE_SINK) and (S.*.opts.*.local_role != ROLE_SOURCE)) {
                if (!S.*.opts.*.allow_directory_link) {
                    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EPERM:dir2dir\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
                    }
                    fail_state(S, "unified-dir not permitted");
                    return;
                }
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=match:local=dir:remote=dir\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
                }
            } else {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=match:local=source:remote=dir\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
                }
            }
        } else if (@as(c_int, @bitCast(@as(c_uint, S.*.decode[54]))) == ROLE_DIRREF) {
            if (S.*.opts.*.local_role != ROLE_DIR) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:ref2src/sink\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
                }
                fail_state(S, "ref-src/sink invalid");
                return;
            }
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=match:local=dir:remote=reference\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
            }
        } else if (S.*.opts.*.local_role == ROLE_DIR) {
            S.*.remote_mode = @as(c_int, @bitCast(@as(c_uint, S.*.decode[54])));
            if (((S.*.remote_mode != ROLE_SOURCE) and (S.*.remote_mode != ROLE_DIR)) and (S.*.remote_mode != ROLE_SINK)) {
                fail_state(S, "bad-remote-role");
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVALID:local=dir:remote=unknown\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
                }
                return;
            }
            if ((S.*.remote_mode == ROLE_DIR) and !S.*.opts.*.allow_directory_link) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EPERM:local=dir:remote=dir:linking_blocked\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth");
                }
                fail_state(S, "dir-link-blocked");
            }
        } else {
            fail_state(S, "bad-role");
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVALID:hello_kind=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_hello_auth", @as(c_int, @bitCast(@as(c_uint, S.*.decode[64]))));
            }
            return;
        }
    } else {}
    if (S.*.authentic == AUTH_SERVER_HBLOCK) {
        hello_auth_server_hello(S);
        return;
    } else if (S.*.authentic == AUTH_POLITE_HELLO_SENT) {
        var nonce: [8]u8 = undefined;
        trace_crypto_key(S, S.*.server, "ephem-pub-in", &S.*.decode[21], 32);
        _ = x25519_shared_secret(@as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.ephem_priv))), &S.*.decode[21]);
        update_keymaterial(S, @as([*c]u8, @ptrCast(@alignCast(&S.*.opts.*.secret))), 32, &S.*.decode[8]);
        x25519_public_key(@as([*c]u8, @ptrCast(@alignCast(&S.*.keys.real_priv))), @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.local_pub))));
        S.*.authentic = AUTH_REAL_HELLO_SENT;
        arcan_random(@as([*c]u8, @ptrCast(@alignCast(&nonce))), 8);
        send_hello_packet(S, 1, @as([*c]u8, @ptrCast(@alignCast(&S.*.keys.local_pub))), @as([*c]u8, @ptrCast(@alignCast(&nonce))));
    } else if (S.*.authentic == AUTH_EPHEMERAL_PK) {
        hello_auth_server_hello(S);
    } else if (S.*.authentic == AUTH_REAL_HELLO_SENT) {
        hello_auth_client_hello(S);
    } else {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:HELLO after completed authxchg (%d)\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "process_hello_auth", S.*.authentic);
        }
        fail_state(S, "auth-mode-bad");
        return;
    }
}
pub fn command_pingpacket(S: [*c]struct_a12_state, sid: u32) callconv(.c) void {
    if (sid == 0) return;
    if (@as(i64, @bitCast(@as(c_ulong, sid))) == S.*.shutdown_id) {
        S.*.state = @as(u8, @bitCast(@as(i8, @truncate(STATE_BROKEN))));
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:terminal_ping=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "command_pingpacket", sid);
        }
        return;
    }
    var i: usize = undefined;
    const wnd_sz: usize = 8;
    {
        i = 0;
        while (i < wnd_sz) : (i +%= 1) {
            const cid: u32 = S.*.congestion_stats.frame_window[i];
            if (cid == 0) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DEBUG) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:ack-sid %u not in wnd\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DEBUG), "command_pingpacket", sid);
                }
                return;
            }
            if (cid == sid) break;
        }
    }
    if (i >= (wnd_sz -% 1)) {
        const latest: u32 = S.*.congestion_stats.frame_window[wnd_sz -% 1];
        if (sid >= latest) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DEBUG) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:ack-sid %u after wnd\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DEBUG), "command_pingpacket", sid);
            }
            S.*.congestion_stats.pending = 0;
            {
                var i_1: usize = 0;
                while (i_1 < wnd_sz) : (i_1 +%= 1) {
                    S.*.congestion_stats.frame_window[i_1] = 0;
                }
            }
            return;
        }
        if (i < @as(usize, @bitCast(@as(c_ulong, latest)))) {
            i = wnd_sz -% 2;
        }
    }
    const i_start: usize = i +% 1;
    var to_move: usize = 0;
    while (((i_start +% to_move) < wnd_sz) and (S.*.congestion_stats.frame_window[i_start +% to_move] != 0)) {
        to_move +%= 1;
    }
    S.*.congestion_stats.pending = to_move;
    _ = memmove(@as(?*anyopaque, @ptrCast(@as([*c]u32, @ptrCast(@alignCast(&S.*.congestion_stats.frame_window))))), @as(?*const anyopaque, @ptrCast(&S.*.congestion_stats.frame_window[i_start])), to_move *% @sizeOf(u32));
    S.*.stats.vframe_backpressure = to_move +% @as(usize, @bitCast(@as(c_ulong, S.*.congestion_stats.frame_window[0] -% sid)));
    {
        i = to_move;
        while (i < wnd_sz) : (i +%= 1) {
            S.*.congestion_stats.frame_window[i] = 0;
        }
    }
}
pub fn send_dirlist(S: [*c]struct_a12_state) callconv(.c) void {
    var outb: [128]u8 = undefined;
    var C: [*c]struct_appl_meta = S.*.directory;
    var count: usize = 0;
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:send_dirlist_begin\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "send_dirlist");
    }
    while (C != null) {
        dirstate_item(S, C);
        count +%= 1;
        C = C.*.next;
    }
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:send_dirlist_end:count==%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "send_dirlist", count);
    }
    _ = memset(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&outb))))), '\x00', 128);
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_DIRSTATE)))));
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb))), 128, null, 0);
}
pub fn command_dirdiscover(S: [*c]struct_a12_state) callconv(.c) void {
    if (S.*.on_discover == null) return;
    const @"type": u8 = S.*.decode[18];
    const state: u8 = S.*.decode[19];
    const ns: u16 = @as(u16, @bitCast(@as(c_ushort, S.*.decode[48])));
    var petname: [17]u8 = [1]u8{
        0,
    } ++ [1]u8{0} ** 16;
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&petname))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[20])), 16);
    {
        var i: usize = 0;
        while (petname[i] != 0) : (i +%= 1) {
            if (!((@as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = @as(c_int, @bitCast(@as(c_uint, petname[i])));
                if (tmp >= 0) break :blk __ctype_b_loc().* + @as(usize, @intCast(tmp)) else break :blk __ctype_b_loc().* - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))) & @as(c_int, @bitCast(@as(c_uint, @as(c_ushort, @bitCast(@as(c_short, @truncate(_ISalnum)))))))) != 0) and (@as(c_int, @bitCast(@as(c_uint, petname[i]))) != '_')) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SECURITY) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:discover:malformed_petname=%s\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SECURITY), "command_dirdiscover", @as([*c]u8, @ptrCast(@alignCast(&petname))));
                }
                return;
            }
        }
    }
    var pubk: [32]u8 = undefined;
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&pubk))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[36])), 32);
    S.*.on_discover.?(S, @"type", @as([*c]u8, @ptrCast(@alignCast(&petname))), state, @as([*c]u8, @ptrCast(@alignCast(&pubk))), ns, S.*.discover_tag);
}
pub fn add_dirent(S: [*c]struct_a12_state) callconv(.c) void {
    if (@as(c_int, @bitCast(@as(c_uint, S.*.decode[36]))) == '\x00') {
        S.*.directory_clk +%= 1;
        return;
    }
    const new: [*c]struct_appl_meta = @ptrCast(@alignCast(malloc(@sizeOf(struct_appl_meta))));
    if (new == null) return;
    new.* = struct_appl_meta{
        .handle = null,
        .buf = null,
        .buf_sz = 0,
        .server_appl = 0,
        .server_tag = null,
        .next = null,
        .identifier = 0,
        .categories = 0,
        .permissions = 0,
        .hash = std.mem.zeroes([4]u8),
        .sig_pubk = std.mem.zeroes([32]u8),
        .alias_identifier = 0,
        .appl = std.mem.zeroes(struct_unnamed_69),
        .update_ts = 0,
    };
    unpack_u16(&new.*.identifier, &S.*.decode[18]);
    unpack_u16(&new.*.categories, &S.*.decode[20]);
    unpack_u16(&new.*.permissions, &S.*.decode[22]);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&new.*.hash))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[24])), 4);
    unpack_u64(&new.*.buf_sz, &S.*.decode[28]);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&new.*.appl.name))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[36])), 18);
    _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&new.*.appl.short_descr))))), @as(?*const anyopaque, @ptrCast(&S.*.decode[55])), 69);
    new.*.update_ts = @as(u64, @bitCast(@as(c_ulong, @truncate(arcan_timemillis()))));
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:dir_item:id=%u:name=%s\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "add_dirent", @as(c_int, @bitCast(@as(c_uint, new.*.identifier))), @as([*c]u8, @ptrCast(@alignCast(&new.*.appl.name))));
    }
    if (S.*.directory == null) {
        S.*.directory = new;
        return;
    }
    var cur: [*c]struct_appl_meta = S.*.directory;
    var prev: [*c]struct_appl_meta = null;
    while (cur != null) {
        if (@as(c_int, @bitCast(@as(c_uint, cur.*.identifier))) == @as(c_int, @bitCast(@as(c_uint, new.*.identifier)))) {
            new.*.next = cur.*.next;
            if (prev != null) {
                prev.*.next = new;
            } else {
                S.*.directory = new;
            }
            free(@as(?*anyopaque, @ptrCast(cur)));
            return;
        }
        if (cur.*.next == null) {
            cur.*.next = new;
            return;
        }
        prev = cur;
        cur = cur.*.next;
    }
    free(@as(?*anyopaque, @ptrCast(new)));
}
pub fn command_shutdown(S: [*c]struct_a12_state, on_event: ?*const fn ([*c]struct_arcan_shmif_cont, c_int, [*c]struct_arcan_event, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) callconv(.c) void {
    const channel: u8 = S.*.decode[16];
    if ((S.*.remote_mode == ROLE_SINK) and (on_event != null)) {
        var ev: struct_arcan_event = struct_arcan_event{
            .unnamed_0 = union_unnamed_9{
                .unnamed_0 = struct_unnamed_10{
                    .unnamed_0 = union_unnamed_11{
                        .tgt = arcan_tgtevent{
                            .kind = @as(c_uint, @bitCast(TARGET_COMMAND_EXIT)),
                            .ioevs = std.mem.zeroes([8]union_unnamed_24),
                            .code = 0,
                            .unnamed_0 = std.mem.zeroes(union_unnamed_25),
                        },
                    },
                    .category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_TARGET)))),
                },
            },
        };
        on_event.?(S.*.channels[channel].cont, @as(c_int, @bitCast(@as(c_uint, channel))), &ev, tag);
    }
}
pub fn command_dirlist(S: [*c]struct_a12_state, on_event: ?*const fn ([*c]struct_arcan_shmif_cont, c_int, [*c]struct_arcan_event, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) callconv(.c) void {
    S.*.notify_dynamic = S.*.decode[18] != 0;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DIRECTORY) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:dirlist:notify=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DIRECTORY), "command_dirlist", @as(c_int, @intFromBool(S.*.notify_dynamic)));
        }
        if (!false) break;
    }
    send_dirlist(S);
    var dirlist_msg: [78]u8 = std.mem.zeroes([78]u8);
    @memcpy(dirlist_msg[0.."a12:dirlist".len], "a12:dirlist");
    var dirlist_ev: struct_arcan_event = struct_arcan_event{
        .unnamed_0 = union_unnamed_9{
            .unnamed_0 = struct_unnamed_10{
                .unnamed_0 = union_unnamed_11{
                    .ext = arcan_extevent{
                        .kind = @as(c_uint, @bitCast(EVENT_EXTERNAL_MESSAGE)),
                        .source = std.mem.zeroes(i64),
                        .unnamed_0 = union_unnamed_26{
                            .message = struct_unnamed_27{
                                .data = dirlist_msg,
                                .multipart = std.mem.zeroes(u8),
                            },
                        },
                        .frame_id = std.mem.zeroes(u64),
                    },
                },
                .category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_EXTERNAL)))),
            },
        },
    };
    on_event.?(null, 0, &dirlist_ev, tag);
}
pub fn command_tundrop(S: [*c]struct_a12_state, id: u8) callconv(.c) void {
    S.*.channels[id].unpack_state.bframe.tunnel = 2;
}
pub fn progress_pending_in(S: [*c]struct_a12_state, ch: u8, progress: f32) callconv(.c) void {
    const cbf: [*c]struct_binary_frame = &S.*.channels[ch].unpack_state.bframe;
    if (@as(f64, @floatCast(progress)) < 0.0) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:chid=%u:failed\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "progress_pending_in", @as(c_int, @bitCast(@as(c_uint, ch))));
            }
            if (!false) break;
        }
        mark_bstream_progress(S, ch, -1, 0, 0);
        unlink_node(S, &S.*.pending_in, S.*.pending_in);
        if (cbf.*.zstd != null) {
            _ = ZSTD_freeDCtx(cbf.*.zstd);
            cbf.*.zstd = null;
        }
    } else if (@as(f64, @floatCast(progress)) >= 1.0) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:chid=%u:ok\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "progress_pending_in", @as(c_int, @bitCast(@as(c_uint, ch))));
            }
            if (!false) break;
        }
        mark_bstream_progress(S, ch, 1, 0, 0);
        unlink_node(S, &S.*.pending_in, S.*.pending_in);
        if (cbf.*.zstd != null) {
            _ = ZSTD_freeDCtx(cbf.*.zstd);
            cbf.*.zstd = null;
        }
    } else {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:chid=%u:progress=%f\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "progress_pending_in", @as(c_int, @bitCast(@as(c_uint, ch))), @as(f64, @floatCast(progress)));
            }
            if (!false) break;
        }
        return;
    }
    if (S.*.pending_in != null) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:chid=%u:request_next\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "progress_pending_in", @as(c_int, @bitCast(@as(c_uint, ch))));
            }
            if (!false) break;
        }
        _ = pack_and_send_event(S, @as([*c]struct_arcan_event, @ptrCast(@alignCast(S.*.pending_in.*.tag))));
    }
}
pub fn process_control(S: [*c]struct_a12_state, on_event: ?*const fn ([*c]struct_arcan_shmif_cont, c_int, [*c]struct_arcan_event, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) callconv(.c) void {
    if (!authdec_buffer("process_control", S, @as(usize, @bitCast(@as(c_long, header_sizes[S.*.state]))))) {
        fail_state(S, "control-bad-mac");
        return;
    }
    const command: u8 = S.*.decode[17];
    {
        const smon = @import("shmif_monitor");
        var buf: [64]u8 = undefined;
        _ = std.fmt.bufPrintZ(&buf, "a12:process_control:cmd={d}", .{command}) catch unreachable;
        smon.emitLuaTag(@ptrCast(&buf));
    }
    if ((S.*.authentic < AUTH_FULL_PK) and (@as(c_int, @bitCast(@as(c_uint, command))) != COMMAND_HELLO)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:illegal command (%d) on non-auth connection\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "process_control", @as(c_int, @bitCast(@as(c_uint, command))));
            }
            if (!false) break;
        }
        fail_state(S, "control-bad-command");
        return;
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DEBUG) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:cmd=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DEBUG), "process_control", @as(c_int, @bitCast(@as(c_uint, command))));
        }
        if (!false) break;
    }
    while (true) {
        switch (@as(c_int, @bitCast(@as(c_uint, command)))) {
            0 => {
                process_hello_auth(S);
                break;
            },
            1 => {
                command_shutdown(S, on_event, tag);
                break;
            },
            2 => {
                command_newchannel(S, on_event, tag);
                break;
            },
            3 => {
                {
                    var streamid: u32 = undefined;
                    unpack_u32(&streamid, &S.*.decode[18]);
                    command_cancelstream(S, streamid, S.*.decode[22], S.*.decode[23]);
                }
                break;
            },
            12 => {
                {
                    if (S.*.opts.*.local_role == ROLE_DIR) {
                        command_diropen(S, S.*.decode[18], &S.*.decode[19]);
                    } else while (true) {
                        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SECURITY) != 0)) {
                            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:diropen:wrong_role\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SECURITY), "process_control");
                        }
                        if (!false) break;
                    }
                }
                break;
            },
            13 => {
                {
                    if (S.*.pending_dynamic.active) {
                        command_diropened(S);
                    } else while (true) {
                        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SECURITY) != 0)) {
                            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:diropened:no_pending_request\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SECURITY), "process_control");
                        }
                        if (!false) break;
                    }
                }
                break;
            },
            14 => {
                {
                    command_tundrop(S, S.*.decode[18]);
                }
                break;
            },
            7 => {
                {
                    var streamid: u32 = undefined;
                    unpack_u32(&streamid, &S.*.decode[18]);
                    while (true) {
                        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_DEBUG) != 0)) {
                            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:ping=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_DEBUG), "process_control", streamid);
                        }
                        if (!false) break;
                    }
                    command_pingpacket(S, streamid);
                }
                break;
            },
            4 => {
                command_videoframe(S);
                break;
            },
            5 => {
                command_audioframe(S);
                break;
            },
            6 => {
                command_binarystream(S);
                break;
            },
            8 => {
                command_rekey(S);
                break;
            },
            9 => {
                command_dirlist(S, on_event, tag);
                break;
            },
            11 => {
                command_dirdiscover(S);
                break;
            },
            10 => {
                add_dirent(S);
                break;
            },
            else => {
                while (true) {
                    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:Unknown message type: %d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_control", @as(c_int, @bitCast(@as(c_uint, command))));
                    }
                    if (!false) break;
                }
                break;
            },
        }
        break;
    }
    reset_state(S);
}
pub fn process_event(S: [*c]struct_a12_state, tag: ?*anyopaque, on_event: ?*const fn ([*c]struct_arcan_shmif_cont, c_int, [*c]struct_arcan_event, ?*anyopaque) callconv(.c) void) callconv(.c) void {
    if (!authdec_buffer("process_event", S, @as(usize, @bitCast(@as(c_long, header_sizes[S.*.state]))))) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:MAC mismatch on event packet\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "process_event");
            }
            if (!false) break;
        }
        fail_state(S, "control-event-mac");
        return;
    }
    const channel: u8 = S.*.decode[8];
    var aev: struct_arcan_event = undefined;
    unpack_u64(&S.*.last_seen_seqnr, @as([*c]u8, @ptrCast(@alignCast(&S.*.decode[0]))));
    if (@as(isize, @bitCast(@as(c_long, -1))) == arcan_shmif_eventunpack(&S.*.decode[9], @as(usize, @bitCast(@as(c_long, (@as(c_int, @bitCast(@as(c_uint, S.*.decode_pos))) - 8) - 1))), &aev)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:broken event packet received\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_event");
            }
            if (!false) break;
        }
        reset_state(S);
    }
    const forward: bool = true;
    var upid: i64 = S.*.channels[channel].unpack_state.bframe.streamid;
    if (upid <= 0) {
        upid = @as(i64, @bitCast(@as(c_ulong, S.*.channels[channel].unpack_state.last_bframe_id)));
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_EVENT) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:unpack:ch=%u:raw=%s\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_EVENT), "process_event", @as(c_int, @bitCast(@as(c_uint, channel))), arcan_shmif_eventstr(&aev, null, 0));
        }
        if (!false) break;
    }
    if (@as(c_int, @bitCast(@as(c_uint, aev.unnamed_0.unnamed_0.category))) == EVENT_EXTERNAL) {
        const id: i64 = @as(i64, @bitCast(@as(c_ulong, aev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.identifier)));
        if (aev.unnamed_0.unnamed_0.unnamed_0.ext.kind == @as(c_uint, @bitCast(EVENT_EXTERNAL_STREAMSTATUS))) {
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:status:ch=%u:current_id=%ld:unpack_id=%ld\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_event", @as(c_int, @bitCast(@as(c_uint, channel))), id, upid);
                }
                if (!false) break;
            }
            if (upid == id) {
                progress_pending_in(S, channel, aev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.streamstat.completion);
            }
        }
    } else if (@as(c_int, @bitCast(@as(c_uint, aev.unnamed_0.unnamed_0.category))) == EVENT_TARGET) {
        if (aev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == @as(c_uint, @bitCast(TARGET_COMMAND_REQFAIL))) {
            const id: i64 = @as(i64, @bitCast(@as(c_long, aev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv)));
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:reqfail:ch=%u:current_id=%ld:unpack_id=%ld\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_event", @as(c_int, @bitCast(@as(c_uint, channel))), id, upid);
                }
                if (!false) break;
            }
            if (upid == id) {
                progress_pending_in(S, channel, @as(f32, @floatFromInt(-1)));
            }
        }
    }
    if ((@as(c_int, @intFromBool(forward)) != 0) and (on_event != null)) {
        on_event.?(S.*.channels[channel].cont, @as(c_int, @bitCast(@as(c_uint, channel))), &aev, tag);
    }
    reset_state(S);
}
// Shared helper for process_blob "done:" label (transfer-complete path).
// C source invokes this from two places: header-with-zero-payload, and data-packet that drains cbf->size to 0.
fn process_blob_done(S: [*c]struct_a12_state, cbf: [*c]struct_binary_frame, cont: [*c]struct_arcan_shmif_cont) void {
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=completed:ch=%d:stream=%ld\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", S.*.in_channel, cbf.*.streamid);
    }
    cbf.*.active = false;

    var bm: struct_a12_bhandler_meta = std.mem.zeroes(struct_a12_bhandler_meta);
    bm.type = @as(c_uint, @bitCast(cbf.*.type));
    bm.streamid = cbf.*.streamid;
    bm.channel = @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel))));
    bm.identifier = cbf.*.identifier;
    bm.fd = cbf.*.tmp_fd;
    bm.dcont = cont;
    bm.state = @as(c_uint, @bitCast(c.A12_BHANDLER_COMPLETED));
    _ = memcpy(@as(?*anyopaque, @ptrCast(&bm.checksum[0])), @as(?*const anyopaque, @ptrCast(&cbf.*.checksum[0])), 16);

    if (S.*.pending_in != null and S.*.pending_in.*.streamid == @as(u64, @bitCast(cbf.*.streamid))) {
        _ = close(cbf.*.tmp_fd);
        // progress_pending_in will clean up zstd context.
        progress_pending_in(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))), 1.0);
    } else if (S.*.binary_handler != null) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            const exp_id: i64 = if (S.*.pending_in != null) @as(i64, @bitCast(S.*.pending_in.*.streamid)) else -1;
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:completed_unknown:id=%lu:expected=%ld\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", @as(u64, @bitCast(cbf.*.streamid)), exp_id);
        }
        cbf.*.tmp_fd = -1;
        _ = S.*.binary_handler.?(S, bm, S.*.binary_handler_tag);
        if (cbf.*.zstd != null) {
            _ = ZSTD_freeDCtx(cbf.*.zstd);
            cbf.*.zstd = null;
        }
    }

    a12int_stream_ack(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))), cbf.*.identifier);
}

// Hand-ported from src/a12/a12.c:3106-3358. Original had a `goto done` jumping to a label inside
// an `if (cbf->size)` block, called from both the header-zero-payload path and after cbf->size drain.
// Restructured by extracting the "done:" body into process_blob_done().
fn process_blob(S: [*c]struct_a12_state) callconv(.c) void {
    var cbf: [*c]struct_binary_frame = undefined;
    var cont: [*c]struct_arcan_shmif_cont = undefined;

    if (S.*.in_channel == -1) {
        update_mac_and_decrypt(S, "process_blob", &S.*.in_mac, chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(&S.*.decode[0])), @as(usize, @intCast(header_sizes[S.*.state])));
        S.*.in_channel = @as(c_int, @bitCast(@as(c_uint, S.*.decode[0])));
        unpack_u32(&S.*.in_stream, &S.*.decode[1]);
        unpack_u16(&S.*.left, &S.*.decode[5]);
        S.*.decode_pos = 0;
        {
            const smon = @import("shmif_monitor");
            const snprintf_p = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
            var buf_p: [96]u8 = undefined;
            _ = snprintf_p(&buf_p, 96, "a12:coverage:blob_recv:ch=%d:stream=%u:size=%u",
                S.*.in_channel, @as(c_uint, @intCast(S.*.in_stream)),
                @as(c_uint, @intCast(S.*.left)));
            smon.emitLuaTag(@ptrCast(&buf_p));
        }
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=header:channel=%d:size=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", S.*.in_channel, @as(c_int, @bitCast(@as(c_uint, S.*.left))));
        }
        cbf = &S.*.channels[@as(c_uint, @intCast(S.*.in_channel))].unpack_state.bframe;
        cont = S.*.channels[@as(c_uint, @intCast(S.*.in_channel))].cont;

        if (S.*.left == 0) {
            process_blob_done(S, cbf, cont);
            return;
        }
        return;
    }

    // data block (after header)
    cbf = &S.*.channels[@as(c_uint, @intCast(S.*.in_channel))].unpack_state.bframe;
    if (!authdec_buffer("process_blob", S, @as(usize, S.*.decode_pos))) {
        fail_state(S, "blob-bad-mac");
        return;
    }

    cont = S.*.channels[@as(c_uint, @intCast(S.*.in_channel))].cont;
    if (cont == null and S.*.binary_handler == null and cbf.*.tunnel == 0) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:ch=%d:message=no segment or bhandler mapped\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_blob", S.*.in_channel);
        }
        reset_state(S);
        return;
    }

    // Data on cancelled/stale stream?
    if (cbf.*.streamid != @as(i64, @intCast(S.*.in_stream)) or cbf.*.streamid == -1) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=notice:ch=%d:src_stream=%u:dst_stream=%ld:message=data on cancelled stream\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", S.*.in_channel, S.*.in_stream, cbf.*.streamid);
        }
        reset_state(S);
        return;
    }

    // Referencing transfer that was not set up?
    if (!cbf.*.active) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=EINVAL:ch=%d:message=blob on inactive channel\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_blob", S.*.in_channel);
        }
        reset_state(S);
        return;
    }

    var ntw: usize = @as(usize, S.*.decode_pos);
    var buf: [*c]u8 = @as([*c]u8, @ptrCast(&S.*.decode[0]));
    var free_buf: bool = false;

    if (cbf.*.zstd != null) {
        const content_sz: c_ulonglong = ZSTD_getFrameContentSize(@as(?*const anyopaque, @ptrCast(&S.*.decode[0])), @as(usize, S.*.decode_pos));
        const ZSTD_CONTENTSIZE_UNKNOWN: c_ulonglong = @as(c_ulonglong, 0) -% 1;
        const ZSTD_CONTENTSIZE_ERROR: c_ulonglong = @as(c_ulonglong, 0) -% 2;
        if (content_sz == ZSTD_CONTENTSIZE_UNKNOWN or content_sz == ZSTD_CONTENTSIZE_ERROR) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=zstd_bad:unknown_size\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_blob");
            }
            a12_stream_cancel(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))));
            reset_state(S);
            return;
        }
        buf = @as([*c]u8, @ptrCast(@alignCast(DYNAMIC_MALLOC(@as(usize, @intCast(content_sz))))));
        ntw = @as(usize, @intCast(content_sz));
        if (buf == null) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=zstd_buffer_fail:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "process_blob", @as(usize, @intCast(content_sz)));
            }
            a12_stream_cancel(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))));
            reset_state(S);
            return;
        }
        const decoded: usize = ZSTD_decompressDCtx(cbf.*.zstd, @as(?*anyopaque, @ptrCast(buf)), @as(usize, @intCast(content_sz)), @as(?*const anyopaque, @ptrCast(&S.*.decode[0])), @as(usize, S.*.decode_pos));
        S.*.decode_pos = 0;
        if (ZSTD_isError(decoded) != 0) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=zstd_fail:code=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_blob", decoded);
            }
            a12_stream_cancel(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))));
            reset_state(S);
            return;
        } else {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=zstd_state:size=%lu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", @as(u64, decoded));
            }
            mark_bstream_progress(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))), 0, ntw, decoded);
        }
        free_buf = true;
    } else {
        mark_bstream_progress(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))), 0, ntw, ntw);
    }

    // Flush to assigned descriptor (potentially blocking).
    if (cbf.*.tmp_fd != -1) {
        var pos: usize = 0;
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=flush:dst=%d:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", cbf.*.tmp_fd, ntw);
        }

        while (pos < ntw) {
            const status: isize = c.write(cbf.*.tmp_fd, @as(?*const anyopaque, @ptrCast(&buf[pos])), ntw - pos);
            if (status == -1) {
                const eno: c_int = __errno_location().*;
                if (eno == c.EAGAIN or eno == c.EWOULDBLOCK or eno == c.EINTR) continue;
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=btransfer_fail:errno=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", eno);
                }
                a12_stream_cancel(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))));
                reset_state(S);
                if (free_buf) DYNAMIC_FREE(@as(?*anyopaque, @ptrCast(buf)));
                return;
            } else {
                pos += @as(usize, @intCast(status));
            }
            if (pos < ntw) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=flush_partial:left=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", ntw);
                }
            }
        }
    }

    if (free_buf) DYNAMIC_FREE(@as(?*anyopaque, @ptrCast(buf)));

    if (S.*.binary_handler == null or cbf.*.tunnel != 0) return;

    // Streaming or known size?
    if (cbf.*.size != 0) {
        if (ntw > cbf.*.size) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=btransfer_overflow:size=%zu:ch=%d:stream=%ld\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_blob", ntw - cbf.*.size, S.*.in_channel, cbf.*.streamid);
            }
            cbf.*.size = 0;
        } else {
            cbf.*.size -= ntw;
        }
        if (cbf.*.size == 0) {
            process_blob_done(S, cbf, cont);
            return;
        }
    }

    // More data coming.
    if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
        _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=data:ch=%d:left:%lu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "process_blob", S.*.in_channel, cbf.*.size);
    }
    reset_state(S);
}
pub fn process_video(S: [*c]struct_a12_state) callconv(.c) void {
    if (S.*.in_channel == -1) {
        var stream: u32 = undefined;
        update_mac_and_decrypt(S, "process_video", &S.*.in_mac, chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(@alignCast(&S.*.decode[0]))), @as(usize, @bitCast(@as(c_ulong, S.*.decode_pos))));
        S.*.in_channel = @as(c_int, @bitCast(@as(c_uint, S.*.decode[0])));
        unpack_u32(&stream, &S.*.decode[1]);
        unpack_u16(&S.*.left, &S.*.decode[5]);
        S.*.decode_pos = 0;
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=header:channel=%d:size=%u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "process_video", S.*.in_channel, @as(c_int, @bitCast(@as(c_uint, S.*.left))));
            }
            if (!false) break;
        }
        return;
    }
    const ch: ?*struct_a12_channel = &S.*.channels[@as(c_uint, @intCast(S.*.in_channel))];
    const cvf: [*c]struct_video_frame = &ch.?.*.unpack_state.vframe;
    if (!authdec_buffer("process_video", S, @as(usize, @bitCast(@as(c_ulong, S.*.decode_pos))))) {
        fail_state(S, "video-bad-mac");
        return;
    } else {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=frame_auth\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "process_video");
            }
            if (!false) break;
        }
    }
    if (@as(c_int, @bitCast(@as(c_uint, cvf.*.commit))) == 255) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=discard\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "process_video");
            }
            if (!false) break;
        }
        reset_state(S);
        return;
    }
    const cont: [*c]struct_arcan_shmif_cont = ch.?.*.cont;
    if (!(cont != null)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:source=video:type=EINVALCH:val=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_video", S.*.in_channel);
            }
            if (!false) break;
        }
        reset_state(S);
        return;
    }
    if (a12int_buffer_format(@as(c_int, @bitCast(@as(c_uint, cvf.*.postprocess))))) {
        var left: usize = @as(usize, @bitCast(@as(c_ulong, cvf.*.inbuf_sz -% cvf.*.inbuf_pos)));
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=decbuf:channel=%d:size=%u:left=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "process_video", S.*.in_channel, @as(c_int, @bitCast(@as(c_uint, S.*.decode_pos))), left);
            }
            if (!false) break;
        }
        if (left >= @as(usize, @bitCast(@as(c_ulong, S.*.decode_pos)))) {
            _ = memcpy(@as(?*anyopaque, @ptrCast(&cvf.*.inbuf[cvf.*.inbuf_pos])), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&S.*.decode[0]))))), @as(c_ulong, @bitCast(@as(c_ulong, S.*.decode_pos))));
            cvf.*.inbuf_pos +%= @as(u32, @bitCast(@as(c_uint, S.*.decode_pos)));
            left -%= @as(usize, @bitCast(@as(c_ulong, S.*.decode_pos)));
        } else if (left != 0) {
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:source=video:channel=%d:type=EOVERFLOW\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_video", S.*.in_channel);
                }
                if (!false) break;
            }
            reset_state(S);
        }
        if ((left == 0) and (@as(c_int, @bitCast(@as(c_uint, cvf.*.commit))) != 255)) {
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_VIDEO) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=decbuf:channel=%d:commit\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_VIDEO), "process_video", S.*.in_channel);
                }
                if (!false) break;
            }
            a12int_decode_vbuffer(S, ch, cvf, cont);
        }
        a12int_stream_ack(S, @as(u8, @bitCast(@as(i8, @truncate(S.*.in_channel)))), cvf.*.id);
        reset_state(S);
        return;
    }
    if (cvf.*.inbuf_sz < @as(u32, @bitCast(@as(c_uint, S.*.decode_pos)))) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:source=video:channel=%d:type=EOVERFLOW\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_video", S.*.in_channel);
            }
            if (!false) break;
        }
        cvf.*.commit = 255;
        reset_state(S);
        return;
    }
    a12int_unpack_vbuffer(S, cvf, cont);
    reset_state(S);
}
pub fn drain_audio(ch: ?*struct_a12_channel) callconv(.c) void {
    const cont: [*c]struct_arcan_shmif_cont = ch.?.*.cont;
    if (ch.?.*.active == CHANNEL_RAW) {
        if (ch.?.*.raw.signal_audio != null) {
            ch.?.*.raw.signal_audio.?(@as(usize, @bitCast(@as(c_ulong, cont.*.abufused))), ch.?.*.raw.tag);
        }
        cont.*.abufused = 0;
        return;
    }
    _ = arcan_shmif_signal(cont, SHMIF_SIGAUD);
}
pub fn process_audio(S: [*c]struct_a12_state) callconv(.c) void {
    if (S.*.in_channel == -1) {
        var stream: u32 = undefined;
        S.*.in_channel = @as(c_int, @bitCast(@as(c_uint, S.*.decode[0])));
        unpack_u32(&stream, &S.*.decode[1]);
        unpack_u16(&S.*.left, &S.*.decode[5]);
        S.*.decode_pos = 0;
        update_mac_and_decrypt(S, "process_audio", &S.*.in_mac, chacha_cast(S.*.dec_state), @as([*c]u8, @ptrCast(@alignCast(&S.*.decode[0]))), @as(usize, @bitCast(@as(c_long, header_sizes[S.*.state]))));
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_AUDIO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:audio[%d:%x], left: %u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_AUDIO), "process_audio", S.*.in_channel, stream, @as(c_int, @bitCast(@as(c_uint, S.*.left))));
            }
            if (!false) break;
        }
        return;
    }
    const channel: ?*struct_a12_channel = &S.*.channels[@as(c_uint, @intCast(S.*.in_channel))];
    const caf: [*c]struct_audio_frame = &channel.?.*.unpack_state.aframe;
    const cont: [*c]struct_arcan_shmif_cont = channel.?.*.cont;
    if (!authdec_buffer("process_audio", S, @as(usize, @bitCast(@as(c_ulong, S.*.decode_pos))))) {
        fail_state(S, "audio-bad-mac");
        return;
    } else {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_CRYPTO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=frame_auth\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_CRYPTO), "process_audio");
            }
            if (!false) break;
        }
    }
    if (!(cont != null)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:audio data on unmapped channel (%d)\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "process_audio", S.*.in_channel);
            }
            if (!false) break;
        }
        reset_state(S);
        return;
    }
    if (channel.?.*.active == CHANNEL_RAW) {
        if (!update_proxy_acont(channel, caf)) return;
    }
    if (!(cont.*.unnamed_1.audp != null)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_AUDIO) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:frame-resize, rate: %u, channels: %u\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_AUDIO), "process_audio", caf.*.rate, @as(c_int, @bitCast(@as(c_uint, caf.*.channels))));
            }
            if (!false) break;
        }
        if (!arcan_shmif_resize_ext(cont, @as(c_uint, @truncate(cont.*.w)), @as(c_uint, @truncate(cont.*.h)), struct_shmif_resize_ext{
            .meta = std.mem.zeroes(u32),
            .abuf_sz = 1024,
            .abuf_cnt = 16,
            .samplerate = @as(isize, @bitCast(@as(c_ulong, caf.*.rate))),
            .vbuf_cnt = 1,
            .rows = std.mem.zeroes(usize),
            .cols = std.mem.zeroes(usize),
            .nops = std.mem.zeroes(usize),
            .op_fm = std.mem.zeroes(usize),
        })) {
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_ALLOC) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:frame-resize failed\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_ALLOC), "process_audio");
                }
                if (!false) break;
            }
            caf.*.commit = 255;
            return;
        }
    }
    var samples_in: usize = @as(usize, @bitCast(@as(c_long, @as(c_int, @bitCast(@as(c_uint, S.*.decode_pos))) >> @intCast(1))));
    var pos: usize = 0;
    while (samples_in > 1) {
        var l: i16 = undefined;
        var r: i16 = undefined;
        unpack_s16(&l, &S.*.decode[pos]);
        pos +%= 2;
        unpack_s16(&r, &S.*.decode[pos]);
        pos +%= 2;
        cont.*.unnamed_1.audp[blk: {
            const ref = &cont.*.abufpos;
            const tmp = ref.*;
            ref.* +%= 1;
            break :blk tmp;
        }] = l;
        cont.*.unnamed_1.audp[blk: {
            const ref = &cont.*.abufpos;
            const tmp = ref.*;
            ref.* +%= 1;
            break :blk tmp;
        }] = r;
        samples_in -%= 2;
        if ((@as(c_int, @bitCast(@as(c_uint, cont.*.abufcount))) - @as(c_int, @bitCast(@as(c_uint, cont.*.abufpos)))) <= 1) {
            while (true) {
                if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_AUDIO) != 0)) {
                    _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:forward %zu samples\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_AUDIO), "process_audio", @as(usize, @bitCast(@as(c_ulong, cont.*.abufpos))));
                }
                if (!false) break;
            }
            drain_audio(channel);
        }
    }
    caf.*.nsamples -%= @as(u16, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_uint, S.*.decode_pos))) >> @intCast(1)))));
    if (!(caf.*.nsamples != 0) and (@as(c_int, @bitCast(@as(c_uint, cont.*.abufused))) != 0)) {
        drain_audio(channel);
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_TRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:audio packet over, samples left: %zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_TRANSFER), "process_audio", @as(usize, @bitCast(@as(c_ulong, caf.*.nsamples))));
        }
        if (!false) break;
    }
    reset_state(S);
}
pub fn read_data(S: [*c]struct_a12_state, fd: c_int, cap_arg: usize, nts: [*c]u16, die: [*c]bool) callconv(.c) ?*anyopaque {
    const cap = cap_arg;
    const buf: ?*anyopaque = malloc(65536);
    nts.* = 0;
    if (!(buf != null)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=error:status=ENOMEM\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "read_data");
            }
            if (!false) break;
        }
        die.* = true;
        return @as(?*anyopaque, @ptrFromInt(0));
    }
    const nr: isize = read(fd, buf, cap);
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=input:read=%zd:descriptor=%d:error=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "read_data", nr, fd, if (nr == @as(isize, @bitCast(@as(c_long, -1)))) __errno_location().* else @as(c_int, 0));
        }
        if (!false) break;
    }
    if (@as(isize, @bitCast(@as(c_long, -1))) == nr) {
        if (((__errno_location().* == 11) or (__errno_location().* == 11)) or (__errno_location().* == 4)) {
            die.* = false;
        } else {
            die.* = true;
        }
        free(buf);
        return @as(?*anyopaque, @ptrFromInt(0));
    }
    die.* = false;
    if (nr == 0) {
        die.* = true;
        free(buf);
        return @as(?*anyopaque, @ptrFromInt(0));
    }
    nts.* = @as(u16, @bitCast(@as(c_short, @truncate(nr))));
    return buf;
}
pub fn queue_node(S: [*c]struct_a12_state, node: [*c]struct_blob_xfer) callconv(.c) usize {
    var nts: u16 = undefined;
    var cap: usize = node.*.left;
    if ((cap == 0) or (cap > 64096)) {
        cap = 64096;
    }
    var die: bool = true;
    var free_buf: bool = true;
    var buf: [*c]u8 = undefined;
    if (!node.*.active) {
        const rampup: usize = begin_bstream(S, node);
        if (rampup < cap) {
            cap = rampup;
        }
    }
    if (node.*.buf != null) {
        buf = &node.*.buf[node.*.buf_sz -% node.*.left];
        nts = @as(u16, @bitCast(@as(c_ushort, @truncate(cap))));
        die = false;
        free_buf = false;
    } else {
        buf = @as([*c]u8, @ptrCast(@alignCast(read_data(S, node.*.fd, cap, &nts, &die))));
    }
    if (!(buf != null) and ((@as(c_int, @intFromBool(die)) != 0) or !(node.*.zstd != null))) {
        if (!(S.*.channels[node.*.chid].progress.out != 0)) {
            _ = flush_uncompressed(S, node, null, 0);
        }
        var ack: struct_arcan_event = struct_arcan_event{
            .unnamed_0 = union_unnamed_9{
                .unnamed_0 = struct_unnamed_10{
                    .unnamed_0 = union_unnamed_11{
                        .ext = arcan_extevent{
                            .kind = @as(c_uint, @bitCast(EVENT_EXTERNAL_STREAMSTATUS)),
                            .source = std.mem.zeroes(i64),
                            .unnamed_0 = union_unnamed_26{
                                .streamstat = struct_unnamed_45{
                                    .timestr = std.mem.zeroes([9]u8),
                                    .timelim = std.mem.zeroes([9]u8),
                                    .completion = @as(f32, @floatCast(1.0)),
                                    .streaming = std.mem.zeroes(u8),
                                    .frameno = std.mem.zeroes(u32),
                                    .identifier = node.*.identifier,
                                },
                            },
                            .frame_id = std.mem.zeroes(u64),
                        },
                    },
                    .category = @as(u8, @bitCast(@as(i8, @truncate(EVENT_EXTERNAL)))),
                },
            },
        };
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:stream_id=%u:send_complete:dead=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "queue_node", node.*.identifier, @as(c_int, @intFromBool(die)));
            }
            if (!false) break;
        }
        _ = a12_channel_enqueue(S, &ack);
        mark_bstream_progress(S, node.*.chid, 1, 0, 0);
        if (die) {
            unlink_node(S, &S.*.pending_out, node);
        }
        return 0;
    }
    if (!(nts != 0)) return @as(usize, @bitCast(@as(c_ulong, nts)));
    if (node.*.zstd != null) {
        die = !flush_compressed(S, node, buf, @as(usize, @bitCast(@as(c_ulong, nts))));
    } else {
        die = !flush_uncompressed(S, node, buf, @as(usize, @bitCast(@as(c_ulong, nts))));
    }
    if (free_buf) {
        free(@as(?*anyopaque, @ptrCast(buf)));
    }
    if (die) {
        unlink_node(S, &S.*.pending_out, node);
    }
    return @as(usize, @bitCast(@as(c_ulong, nts)));
}
pub fn flush_compressed(S: [*c]struct_a12_state, node: [*c]struct_blob_xfer, buf: [*c]u8, nts: usize) callconv(.c) bool {
    var outb: [7]u8 = undefined;
    outb[0] = node.*.chid;
    pack_u32(@as(u32, @bitCast(@as(c_uint, @truncate(node.*.streamid)))), &outb[1]);
    if (!(node.*.left != 0) and !(nts != 0)) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=compressed_stream_over:stream=%zu:ch=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "flush_compressed", @as(usize, @bitCast(node.*.streamid)), @as(c_int, @bitCast(@as(c_uint, node.*.chid))));
            }
            if (!false) break;
        }
        return false;
    }
    const max: usize = ZSTD_compressBound(nts);
    if (max >= 65536) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_SYSTEM) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=compressed_stream_overflow:cap=64k:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_SYSTEM), "flush_compressed", max);
            }
            if (!false) break;
        }
        return false;
    }
    const compressed: ?*anyopaque = malloc(max);
    const out: usize = ZSTD_compressCCtx(node.*.zstd, compressed, max, @as(?*const anyopaque, @ptrCast(buf)), nts, 3);
    pack_u16(@as(u16, @truncate(out)), &outb[5]);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_BLOB_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(compressed))), out, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @sizeOf([7]u8));
    mark_bstream_progress(S, node.*.chid, 0, nts, out);
    free(compressed);
    if (node.*.left != 0) {
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=compressed_block:stream=%lu:ch=%d:size=%zu:base=%zu:left=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "flush_compressed", node.*.streamid, @as(c_int, @bitCast(@as(c_uint, node.*.chid))), out, nts, node.*.left);
            }
            if (!false) break;
        }
        node.*.left -%= nts;
        return node.*.left != 0;
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=compressed_stream=%zu:ch=%d:size=%zu:base=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "flush_compressed", @as(usize, @bitCast(node.*.streamid)), @as(c_int, @bitCast(@as(c_uint, node.*.chid))), out, nts);
        }
        if (!false) break;
    }
    return true;
}
pub fn flush_uncompressed(S: [*c]struct_a12_state, node: [*c]struct_blob_xfer, buf: [*c]u8, nts: usize) callconv(.c) bool {
    var outb: [7]u8 = undefined;
    outb[0] = node.*.chid;
    pack_u32(@as(u32, @truncate(node.*.streamid)), &outb[1]);
    pack_u16(@as(u16, @truncate(nts)), &outb[5]);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_BLOB_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(buf))), nts, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @sizeOf([7]u8));
    mark_bstream_progress(S, node.*.chid, 0, nts, nts);
    if (node.*.left != 0) {
        node.*.left -%= nts;
        while (true) {
            if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
                _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=block:stream=%lu:ch=%d:size=%zu:left=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "flush_uncompressed", node.*.streamid, @as(c_int, @bitCast(@as(c_uint, node.*.chid))), nts, node.*.left);
            }
            if (!false) break;
        }
        return node.*.left != 0;
    }
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=block:stream=%zu:ch=%d:streaming:size=%zu\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "flush_uncompressed", @as(usize, @bitCast(node.*.streamid)), @as(c_int, @bitCast(@as(c_uint, node.*.chid))), nts);
        }
        if (!false) break;
    }
    return nts != 0;
}
pub fn begin_bstream(S: [*c]struct_a12_state, node: [*c]struct_blob_xfer) callconv(.c) usize {
    var outb: [128]u8 = undefined;
    if (node.*.tag != null) {
        register_bchunk_name(S, @as([*c]arcan_event, @ptrCast(@alignCast(node.*.tag))));
    }
    build_control_header(S, @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), @as(u8, @bitCast(@as(i8, @truncate(COMMAND_BINARYSTREAM)))));
    outb[16] = node.*.chid;
    pack_u32(@as(u32, @truncate(node.*.streamid)), &outb[18]);
    pack_u64(node.*.left, &outb[22]);
    outb[30] = @as(u8, @bitCast(@as(i8, @truncate(node.*.type))));
    pack_u32(node.*.identifier, &outb[31]);
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[35])), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&node.*.checksum[0]))))), 16);
    const ch: ?*struct_a12_channel = &S.*.channels[node.*.chid];
    ch.?.*.progress.total = node.*.left;
    ch.?.*.progress.in = blk: {
        const tmp: usize = 0;
        ch.?.*.progress.out = tmp;
        break :blk tmp;
    };
    ch.?.*.progress.trigger_left = ch.?.*.progress.trigger_count;
    if (!node.*.uncompressed) {
        node.*.zstd = ZSTD_createCCtx();
        if (node.*.zstd != null) {
            _ = ZSTD_CCtx_setParameter(node.*.zstd, @as(c_uint, @bitCast(ZSTD_c_nbWorkers)), 0);
            outb[52] = 1;
        }
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(&outb[53])), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&node.*.extid[0]))))), 16);
    a12int_append_out(S, @as(u8, @bitCast(@as(i8, @truncate(STATE_CONTROL_PACKET)))), @as([*c]u8, @ptrCast(@alignCast(&outb[0]))), 128, null, 0);
    node.*.active = true;
    while (true) {
        if ((a12_trace_dst != null) and ((a12_trace_targets & A12_TRACE_BTRANSFER) != 0)) {
            _ = fprintf(a12_trace_dst, "tag=%s:ts=%lld:group=%s:function=%s:kind=created:size=%zu:stream=%lu:ch=%d\n", @as([*c]u8, @ptrCast(@alignCast(&S.*.tracetag[0]))), arcan_timemillis(), a12int_group_tostr(A12_TRACE_BTRANSFER), "begin_bstream", node.*.left, node.*.streamid, @as(c_int, @bitCast(@as(c_uint, node.*.chid))));
        }
        if (!false) break;
    }
    return 16384;
}
pub fn append_blob(S: [*c]struct_a12_state, mode: c_int) callconv(.c) usize {
    if ((mode == A12_FLUSH_NOBLOB) or !(S.*.pending_out != null)) return 0;
    if ((S.*.pending_out.*.rampup_seqnr != 0) and (S.*.last_seen_seqnr < S.*.pending_out.*.rampup_seqnr)) {
        return 0;
    } else if (mode == A12_FLUSH_CHONLY) {
        var parent: [*c]struct_blob_xfer = S.*.pending_out;
        while (parent != null) {
            if (@as(c_int, @bitCast(@as(c_uint, parent.*.chid))) == S.*.out_channel) return queue_node(S, parent);
            parent = parent.*.next;
        }
        return 0;
    }
    return queue_node(S, S.*.pending_out);
}
pub var groups: [13][*c]const u8 = [13][*c]const u8{
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
    "btransfer",
    "security",
    "directory",
};
pub fn i_log2(n: u32) callconv(.c) c_uint {
    var val = n;
    var res: c_uint = 0;
    while ((blk: {
        const ref = &val;
        ref.* >>= @intCast(1);
        break :blk ref.*;
    }) != 0) {
        res +%= 1;
    }
    return res;
}
