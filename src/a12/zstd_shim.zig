// Zstd shim: pure-Zig decoder (std.compress.zstd) + translate-c'd extern
// declarations for the five encoder entry points still provided by the linked
// C zstd library.
//
// Scope kept deliberately small — see src/a12/zstd_encoder_subset.h for the
// minimal header fed to `zig translate-c`.

const std = @import("std");
const zstd = std.compress.zstd;

// Encoder stub (musl-static target). The real encoder lives in libzstd,
// which is not statically linkable on this host; rather than vendor the
// full encoder we ship a stub that satisfies link-time refs and signals
// "encoder unavailable" at runtime via ZSTD_isError. Callers in a12.zig
// / a12_encode.zig already check ZSTD_isError after every compression
// call and fall back to the uncompressed path on failure.
//
// To re-enable real encoding (e.g. for arcan-net + video frame shipping
// where uncompressed frames are unworkable), either:
//   (a) link a static libzstd via -Dstatic-musl=false plus a system .a, or
//   (b) port zstd_shim.zig's encoder funcs to dlopen libzstd.so.1 at
//       startup and forward via function pointers (matches the
//       src/platform/zig_dlopen.zig pattern used for xcb/drm/etc.).

pub const struct_ZSTD_CCtx_s = opaque {};
pub const ZSTD_CCtx = struct_ZSTD_CCtx_s;
pub const ZSTD_c_nbWorkers: c_int = 400;
pub const ZSTD_cParameter = c_uint;

// Sentinel value carried in ZSTD_compressCCtx's return. ZSTD's contract:
// (size_t)-code where code is small. We use a non-zero value that's
// recognizably "in the error band" so ZSTD_isError flags it.
const ZSTD_STUB_ERR: usize = @bitCast(@as(isize, -1));

// Minimal heap-backed sentinel handed out so callers' non-null checks
// pass and ZSTD_freeCCtx has something to free. Never dereferenced.
const StubCCtx = struct { _: u8 = 0 };

pub export fn ZSTD_createCCtx() callconv(.c) ?*ZSTD_CCtx {
    const gpa = std.heap.page_allocator;
    const inner = gpa.create(StubCCtx) catch return null;
    inner.* = .{};
    return @ptrCast(inner);
}

pub export fn ZSTD_freeCCtx(cctx: ?*ZSTD_CCtx) callconv(.c) usize {
    if (cctx) |c_| {
        const inner: *StubCCtx = @ptrCast(@alignCast(c_));
        std.heap.page_allocator.destroy(inner);
    }
    return 0;
}

pub export fn ZSTD_compressCCtx(
    cctx: ?*ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    compressionLevel: c_int,
) callconv(.c) usize {
    _ = cctx; _ = dst; _ = dstCapacity; _ = src; _ = srcSize; _ = compressionLevel;
    return ZSTD_STUB_ERR;
}

// Worst-case bound matching upstream's `srcSize + (srcSize >> 8) + 512`.
// Callers allocate this much before encoding; with a stub encoder the
// allocation is wasted, but returning a too-small bound would fault on
// the (never-reached) compress path elsewhere.
pub export fn ZSTD_compressBound(srcSize: usize) callconv(.c) usize {
    return srcSize +% (srcSize >> 8) +% 512;
}

pub export fn ZSTD_CCtx_setParameter(
    cctx: ?*ZSTD_CCtx,
    param: ZSTD_cParameter,
    value: c_int,
) callconv(.c) usize {
    _ = cctx; _ = param; _ = value;
    return 0; // parameter-set is config-only; treat as accepted.
}

pub export fn ZSTD_isError(code: usize) callconv(.c) c_uint {
    // upstream: code > (size_t)(-ZSTD_error_maxCode) ≈ very-high size_t.
    // Conservative: anything in the top quarter of the size_t range.
    const ERR_BAND_LO: usize = @as(usize, std.math.maxInt(usize)) - 0xff;
    return if (code >= ERR_BAND_LO) 1 else 0;
}

pub export fn ZSTD_getErrorName(code: usize) callconv(.c) [*c]const u8 {
    _ = code;
    return "zstd-encoder-stub";
}

// Decoder (pure Zig, exported with zstd C-ABI)

// Sentinels mirroring <zstd.h>.
const ZSTD_CONTENTSIZE_UNKNOWN: u64 = @bitCast(@as(i64, -1));
const ZSTD_CONTENTSIZE_ERROR: u64 = @bitCast(@as(i64, -2));

// Encode an error as the zstd return convention: `(size_t)-n` where n <= 0xFF.
// Our sole caller chain is `isError(rv) != 0` → `getErrorName(rv)`, so any
// unique high value works; we never go through the C-side error names.
const ERR_GENERIC: usize = @bitCast(@as(isize, -1));

pub const ZSTD_DCtx = opaque {};

const DCtxInner = struct {
    gpa: std.mem.Allocator,
};

// Use page_allocator so the handle is independent of call-site.
export fn ZSTD_createDCtx() callconv(.c) ?*ZSTD_DCtx {
    const gpa = std.heap.page_allocator;
    const inner = gpa.create(DCtxInner) catch return null;
    inner.* = .{ .gpa = gpa };
    return @ptrCast(inner);
}

export fn ZSTD_freeDCtx(dctx: ?*ZSTD_DCtx) callconv(.c) usize {
    if (dctx) |d| {
        const inner: *DCtxInner = @ptrCast(@alignCast(d));
        inner.gpa.destroy(inner);
    }
    return 0;
}

// Parse the leading zstd frame header to extract the declared decompressed
// content size. Returns ZSTD_CONTENTSIZE_UNKNOWN / _ERROR per the C contract.
//
// Frame layout (simplified, see RFC 8878 §3.1):
//   [0..4)  magic = 0xFD2FB528
//   [4]     frame_header_descriptor (FHD)
//             bit0-1: dictionary_id_flag
//             bit2:   content_checksum_flag
//             bit3:   reserved (must be 0)
//             bit4:   unused
//             bit5:   single_segment_flag
//             bit6-7: frame_content_size_flag (fcs_flag)
//   [5]?    window_descriptor (only if single_segment_flag == 0)
//   [..]    dictionary_id (0, 1, 2, or 4 bytes per dictionary_id_flag)
//   [..]    frame_content_size (0, 1, 2, 4, or 8 bytes per fcs_flag /
//            single_segment rules)
export fn ZSTD_getFrameContentSize(
    src: ?*const anyopaque,
    src_size: usize,
) callconv(.c) u64 {
    const p = src orelse return ZSTD_CONTENTSIZE_ERROR;
    if (src_size < 5) return ZSTD_CONTENTSIZE_ERROR;
    const bytes: [*]const u8 = @ptrCast(p);

    // Magic check. Skippable-frame magics (0x184D2A50..5F) report unknown.
    const magic = std.mem.readInt(u32, bytes[0..4], .little);
    if (magic >= 0x184D2A50 and magic <= 0x184D2A5F) return ZSTD_CONTENTSIZE_UNKNOWN;
    if (magic != 0xFD2FB528) return ZSTD_CONTENTSIZE_ERROR;

    const fhd = bytes[4];
    if ((fhd & 0x08) != 0) return ZSTD_CONTENTSIZE_ERROR; // reserved bit set
    const single_segment = (fhd & 0x20) != 0;
    const fcs_flag: u2 = @truncate(fhd >> 6);
    const did_flag: u2 = @truncate(fhd & 0x03);

    var ofs: usize = 5;
    if (!single_segment) ofs += 1; // window descriptor
    ofs += switch (did_flag) { 0 => @as(usize, 0), 1 => 1, 2 => 2, 3 => 4 };

    // fcs_flag decoding (RFC 8878 §3.1.1.4):
    //   0 → fcs_field_size = 0 if single_segment==0 else 1
    //   1 → 2 (and the encoded value has +256 bias)
    //   2 → 4
    //   3 → 8
    const fcs_size: usize = switch (fcs_flag) {
        0 => if (single_segment) @as(usize, 1) else 0,
        1 => 2,
        2 => 4,
        3 => 8,
    };
    if (fcs_size == 0) return ZSTD_CONTENTSIZE_UNKNOWN;
    if (ofs + fcs_size > src_size) return ZSTD_CONTENTSIZE_ERROR;

    return switch (fcs_size) {
        1 => @as(u64, bytes[ofs]),
        2 => @as(u64, std.mem.readInt(u16, bytes[ofs..][0..2], .little)) + 256,
        4 => @as(u64, std.mem.readInt(u32, bytes[ofs..][0..4], .little)),
        8 => std.mem.readInt(u64, bytes[ofs..][0..8], .little),
        else => unreachable,
    };
}

export fn ZSTD_decompressDCtx(
    dctx: ?*ZSTD_DCtx,
    dst: ?*anyopaque,
    dst_capacity: usize,
    src: ?*const anyopaque,
    src_size: usize,
) callconv(.c) usize {
    const d = dctx orelse return ERR_GENERIC;
    const inner: *DCtxInner = @ptrCast(@alignCast(d));
    const dst_p = dst orelse return ERR_GENERIC;
    const src_p = src orelse return ERR_GENERIC;

    const src_slice: []const u8 = @as([*]const u8, @ptrCast(src_p))[0..src_size];
    const dst_slice: []u8 = @as([*]u8, @ptrCast(dst_p))[0..dst_capacity];

    // window_len budget: std.compress.zstd.Decompress asserts that the output
    // buffer has window_len + block_size_max bytes. Size a scratch buffer to
    // match, allocated per-call so the decoder is stateless across invocations.
    const window_len: usize = zstd.default_window_len; // 8 MiB
    const scratch_len: usize = window_len + zstd.block_size_max;
    const scratch = inner.gpa.alloc(u8, scratch_len) catch return ERR_GENERIC;
    defer inner.gpa.free(scratch);

    var src_reader: std.Io.Reader = .fixed(src_slice);
    var decomp = zstd.Decompress.init(&src_reader, scratch, .{
        .window_len = window_len,
    });
    var dst_writer: std.Io.Writer = .fixed(dst_slice);
    const n = decomp.reader.streamRemaining(&dst_writer) catch return ERR_GENERIC;
    return n;
}
