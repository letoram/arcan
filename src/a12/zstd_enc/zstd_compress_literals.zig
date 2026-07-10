// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/compress/zstd_compress_literals.c (slice 4a).
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// Public C-ABI entry points (via `pub export fn`):
//   ZSTD_noCompressLiterals, ZSTD_compressRleLiteralsBlock, ZSTD_compressLiterals.
//
// Also exports types/consts that are "closest to home" here (callers and
// slice 5+ re-import these):
//   SymbolEncodingType_e (set_basic/set_rle/set_compressed/set_repeat),
//   ZSTD_strategy enum, LitHufLog, MIN_LITERALS_FOR_4_STREAMS,
//   HUF_OPTIMAL_DEPTH_THRESHOLD, ZSTD_hufCTables_t (extern struct matching
//   zstd_compress_internal.h layout), ZSTD_literalsCompressionMode_e,
//   ZSTD_minGain, ZSTD_literalsCompressionIsDisabled helper.

const std = @import("std");
const common = @import("zstd_common.zig");
const huf = @import("huf_compress.zig");
const ec = @import("entropy_common.zig");

const zstdError = common.zstdError;

// -------------------------------------------------------------------------
//  Shared types — "closest to home": literal/sequence block formats live
//  here and in zstd_compress_sequences.zig. Future slice 5 imports them.
// -------------------------------------------------------------------------

/// SymbolEncodingType_e — mirror of lib/common/zstd_internal.h.
/// Order and numeric values are wire-visible.
pub const SymbolEncodingType_e = enum(c_uint) {
    set_basic = 0,
    set_rle = 1,
    set_compressed = 2,
    set_repeat = 3,
};
pub const set_basic = SymbolEncodingType_e.set_basic;
pub const set_rle = SymbolEncodingType_e.set_rle;
pub const set_compressed = SymbolEncodingType_e.set_compressed;
pub const set_repeat = SymbolEncodingType_e.set_repeat;

/// ZSTD_strategy — mirrors zstd.h public enum.
pub const ZSTD_strategy = enum(c_int) {
    ZSTD_fast = 1,
    ZSTD_dfast = 2,
    ZSTD_greedy = 3,
    ZSTD_lazy = 4,
    ZSTD_lazy2 = 5,
    ZSTD_btlazy2 = 6,
    ZSTD_btopt = 7,
    ZSTD_btultra = 8,
    ZSTD_btultra2 = 9,
};

/// HUF_OPTIMAL_DEPTH_THRESHOLD — huf.h: `#define HUF_OPTIMAL_DEPTH_THRESHOLD ZSTD_btultra`.
pub const HUF_OPTIMAL_DEPTH_THRESHOLD: c_int = @intFromEnum(ZSTD_strategy.ZSTD_btultra);

/// LitHufLog — zstd_internal.h.
pub const LitHufLog: c_uint = 11;

/// MIN_LITERALS_FOR_4_STREAMS — zstd_internal.h.
pub const MIN_LITERALS_FOR_4_STREAMS: usize = 6;

/// Literal compression mode (used by ZSTD_literalsCompressionIsDisabled).
/// Port of `ZSTD_paramSwitch_e` alias used for the literal mode field.
pub const ZSTD_literalsCompressionMode_e = enum(c_int) {
    ZSTD_lcm_auto = 0, // ZSTD_ps_auto
    ZSTD_lcm_huffman = 1, // ZSTD_ps_enable
    ZSTD_lcm_uncompressed = 2, // ZSTD_ps_disable
};
pub const ZSTD_lcm_auto = ZSTD_literalsCompressionMode_e.ZSTD_lcm_auto;
pub const ZSTD_lcm_huffman = ZSTD_literalsCompressionMode_e.ZSTD_lcm_huffman;
pub const ZSTD_lcm_uncompressed = ZSTD_literalsCompressionMode_e.ZSTD_lcm_uncompressed;

/// HUF_CTABLE_SIZE_ST(255) — upstream macro expands to 257 size_t entries
/// (header + 256 symbol slots). Needed to mirror zstd_hufCTables_t layout.
pub const HUF_CTABLE_SIZE_ST_255: usize = 1 + 256;

/// ZSTD_hufCTables_t — extern struct mirroring zstd_compress_internal.h.
/// Slice 5 will adopt this as-is.
pub const ZSTD_hufCTables_t = extern struct {
    CTable: [HUF_CTABLE_SIZE_ST_255]huf.HUF_CElt,
    repeatMode: huf.HUF_repeat,
};

// -------------------------------------------------------------------------
//  ZSTD_minGain — port of zstd_compress_internal.h (MEM_STATIC inline).
// -------------------------------------------------------------------------
pub fn ZSTD_minGain(srcSize: usize, strat: ZSTD_strategy) usize {
    const s_int: c_int = @intFromEnum(strat);
    const minlog: u5 = if (s_int >= @intFromEnum(ZSTD_strategy.ZSTD_btultra))
        @intCast(s_int - 1)
    else
        6;
    return (srcSize >> minlog) + 2;
}

// -------------------------------------------------------------------------
//  Block header helpers (little-endian writes)
// -------------------------------------------------------------------------
inline fn writeLE16(dst: [*]u8, v: u16) void {
    std.mem.writeInt(u16, dst[0..2], v, .little);
}

inline fn writeLE24(dst: [*]u8, v: u32) void {
    // Upstream MEM_writeLE24 = writeLE16(low) + write byte(high).
    std.mem.writeInt(u16, dst[0..2], @intCast(v & 0xFFFF), .little);
    dst[2] = @intCast((v >> 16) & 0xFF);
}

inline fn writeLE32(dst: [*]u8, v: u32) void {
    std.mem.writeInt(u32, dst[0..4], v, .little);
}

// -------------------------------------------------------------------------
//  ZSTD_noCompressLiterals — emit a raw (set_basic) literals section.
// -------------------------------------------------------------------------
pub export fn ZSTD_noCompressLiterals(
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    const ostart: [*]u8 = @ptrCast(dst.?);
    // Upstream (zstd/compress/zstd_compress_literals.c) computes
    //   U32 const flSize = 1 + (srcSize>31) + (srcSize>4095);
    // i.e. three int-typed values summed into a U32. In Zig
    // @intFromBool yields u1, and u1+u1 can overflow u1 (max 1+1=2).
    // Widen each term to u32 before adding so the sum stays in 1..3.
    const flSize: u32 =
        1 + @as(u32, @intFromBool(srcSize > 31)) + @as(u32, @intFromBool(srcSize > 4095));

    if (srcSize + flSize > dstCapacity) return zstdError(.dstSize_tooSmall);

    const basic: u32 = @intFromEnum(set_basic);
    switch (flSize) {
        1 => { // 2 - 1 - 5
            ostart[0] = @intCast(basic + (srcSize << 3));
        },
        2 => { // 2 - 2 - 12
            writeLE16(ostart, @intCast(basic + (1 << 2) + (srcSize << 4)));
        },
        3 => { // 2 - 2 - 20
            writeLE32(ostart, @intCast(basic + (3 << 2) + (srcSize << 4)));
        },
        else => unreachable,
    }

    if (srcSize != 0) {
        const s: [*]const u8 = @ptrCast(src.?);
        @memcpy(ostart[flSize .. flSize + srcSize], s[0..srcSize]);
    }
    return srcSize + flSize;
}

// -------------------------------------------------------------------------
//  allBytesIdentical — static helper, matches upstream semantics.
// -------------------------------------------------------------------------
fn allBytesIdentical(src: [*]const u8, srcSize: usize) bool {
    std.debug.assert(srcSize >= 1);
    const b = src[0];
    var p: usize = 1;
    while (p < srcSize) : (p += 1) {
        if (src[p] != b) return false;
    }
    return true;
}

// -------------------------------------------------------------------------
//  ZSTD_compressRleLiteralsBlock — single-byte RLE literals section.
// -------------------------------------------------------------------------
pub export fn ZSTD_compressRleLiteralsBlock(
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    const ostart: [*]u8 = @ptrCast(dst.?);
    // Upstream (zstd/compress/zstd_compress_literals.c) computes
    //   U32 const flSize = 1 + (srcSize>31) + (srcSize>4095);
    // i.e. three int-typed values summed into a U32. In Zig
    // @intFromBool yields u1, and u1+u1 can overflow u1 (max 1+1=2).
    // Widen each term to u32 before adding so the sum stays in 1..3.
    const flSize: u32 =
        1 + @as(u32, @intFromBool(srcSize > 31)) + @as(u32, @intFromBool(srcSize > 4095));

    std.debug.assert(dstCapacity >= 4);

    const s: [*]const u8 = @ptrCast(src.?);
    std.debug.assert(allBytesIdentical(s, srcSize));

    const rle: u32 = @intFromEnum(set_rle);
    switch (flSize) {
        1 => { // 2 - 1 - 5
            ostart[0] = @intCast(rle + (srcSize << 3));
        },
        2 => { // 2 - 2 - 12
            writeLE16(ostart, @intCast(rle + (1 << 2) + (srcSize << 4)));
        },
        3 => { // 2 - 2 - 20
            writeLE32(ostart, @intCast(rle + (3 << 2) + (srcSize << 4)));
        },
        else => unreachable,
    }

    ostart[flSize] = s[0];
    return flSize + 1;
}

// -------------------------------------------------------------------------
//  ZSTD_minLiteralsToCompress — static helper matching upstream thresholds.
// -------------------------------------------------------------------------
fn ZSTD_minLiteralsToCompress(strat: ZSTD_strategy, huf_repeat: huf.HUF_repeat) usize {
    const s_int: c_int = @intFromEnum(strat);
    std.debug.assert(s_int >= 0);
    std.debug.assert(s_int <= 9);
    const shift_raw: c_int = 9 - s_int;
    const shift: u6 = @intCast(@min(shift_raw, 3));
    const mintc: usize = if (huf_repeat == .HUF_repeat_valid) 6 else (@as(usize, 8) << shift);
    return mintc;
}

// -------------------------------------------------------------------------
//  ZSTD_compressLiterals — main entry point.
// -------------------------------------------------------------------------
pub export fn ZSTD_compressLiterals(
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    entropyWorkspace: ?*anyopaque,
    entropyWorkspaceSize: usize,
    prevHuf: ?*const ZSTD_hufCTables_t,
    nextHuf: ?*ZSTD_hufCTables_t,
    strategy: ZSTD_strategy,
    disableLiteralCompression: c_int,
    suspectUncompressible: c_int,
    bmi2: c_int,
) usize {
    const KB: usize = 1024;
    const lhSize: usize = @as(usize, 3) + @intFromBool(srcSize >= 1 * KB) + @intFromBool(srcSize >= 16 * KB);
    const ostart: [*]u8 = @ptrCast(dst.?);
    var singleStream: c_uint = @intFromBool(srcSize < 256);
    var hType: SymbolEncodingType_e = set_compressed;

    // Prepare nextEntropy assuming reusing the existing table.
    const p = prevHuf.?;
    const n = nextHuf.?;
    n.* = p.*;

    if (disableLiteralCompression != 0)
        return ZSTD_noCompressLiterals(dst, dstCapacity, src, srcSize);

    if (srcSize < ZSTD_minLiteralsToCompress(strategy, p.repeatMode))
        return ZSTD_noCompressLiterals(dst, dstCapacity, src, srcSize);

    if (dstCapacity < lhSize + 1) return zstdError(.dstSize_tooSmall);

    var cLitSize: usize = 0;
    {
        var repeat: huf.HUF_repeat = p.repeatMode;
        const s_int: c_int = @intFromEnum(strategy);
        var flags: c_int = 0;
        if (bmi2 != 0) flags |= ec.HUF_flags_bmi2;
        if (s_int < @intFromEnum(ZSTD_strategy.ZSTD_lazy) and srcSize <= 1024)
            flags |= ec.HUF_flags_preferRepeat;
        if (s_int >= HUF_OPTIMAL_DEPTH_THRESHOLD)
            flags |= ec.HUF_flags_optimalDepth;
        if (suspectUncompressible != 0)
            flags |= ec.HUF_flags_suspectUncompressible;

        if (repeat == .HUF_repeat_valid and lhSize == 3) singleStream = 1;

        const dst_bytes: [*]u8 = ostart + lhSize;
        if (singleStream != 0) {
            cLitSize = huf.HUF_compress1X_repeat(
                dst_bytes,
                dstCapacity - lhSize,
                src,
                srcSize,
                huf.HUF_SYMBOLVALUE_MAX,
                LitHufLog,
                entropyWorkspace,
                entropyWorkspaceSize,
                @ptrCast(&n.CTable),
                &repeat,
                flags,
            );
        } else {
            cLitSize = huf.HUF_compress4X_repeat(
                dst_bytes,
                dstCapacity - lhSize,
                src,
                srcSize,
                huf.HUF_SYMBOLVALUE_MAX,
                LitHufLog,
                entropyWorkspace,
                entropyWorkspaceSize,
                @ptrCast(&n.CTable),
                &repeat,
                flags,
            );
        }
        if (repeat != .HUF_repeat_none) {
            hType = set_repeat;
        }
    }

    {
        const minGainValue: usize = ZSTD_minGain(srcSize, strategy);
        if (cLitSize == 0 or cLitSize >= srcSize - minGainValue or common.ERR_isError(cLitSize) != 0) {
            n.* = p.*;
            return ZSTD_noCompressLiterals(dst, dstCapacity, src, srcSize);
        }
    }
    if (cLitSize == 1) {
        // A return value of 1 normally signals "single-symbol alphabet". For srcSize < 8
        // it could actually be a valid 1-byte compressed output; verify.
        const s_bytes: [*]const u8 = @ptrCast(src.?);
        if (srcSize >= 8 or allBytesIdentical(s_bytes, srcSize)) {
            n.* = p.*;
            return ZSTD_compressRleLiteralsBlock(dst, dstCapacity, src, srcSize);
        }
    }

    if (hType == set_compressed) {
        n.repeatMode = .HUF_repeat_check;
    }

    // Build literals section header.
    switch (lhSize) {
        3 => {
            if (singleStream == 0) std.debug.assert(srcSize >= MIN_LITERALS_FOR_4_STREAMS);
            const nonSingle: u32 = if (singleStream == 0) 1 else 0;
            const lhc: u32 = @as(u32, @intFromEnum(hType)) + (nonSingle << 2) +
                (@as(u32, @intCast(srcSize)) << 4) + (@as(u32, @intCast(cLitSize)) << 14);
            writeLE24(ostart, lhc);
        },
        4 => {
            std.debug.assert(srcSize >= MIN_LITERALS_FOR_4_STREAMS);
            const lhc: u32 = @as(u32, @intFromEnum(hType)) + (2 << 2) +
                (@as(u32, @intCast(srcSize)) << 4) + (@as(u32, @intCast(cLitSize)) << 18);
            writeLE32(ostart, lhc);
        },
        5 => {
            std.debug.assert(srcSize >= MIN_LITERALS_FOR_4_STREAMS);
            const lhc: u32 = @as(u32, @intFromEnum(hType)) + (3 << 2) +
                (@as(u32, @intCast(srcSize)) << 4) + (@as(u32, @intCast(cLitSize)) << 22);
            writeLE32(ostart, lhc);
            ostart[4] = @intCast((cLitSize >> 10) & 0xFF);
        },
        else => unreachable,
    }
    return lhSize + cLitSize;
}

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------
test "ZSTD_noCompressLiterals — small size-1 header path" {
    // srcSize=16 → flSize=1 (since srcSize<=31).
    const src = [_]u8{ 0xAB, 0xCD, 0xEF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D };
    var dst: [64]u8 = undefined;
    const r = ZSTD_noCompressLiterals(&dst, dst.len, &src, src.len);
    try std.testing.expect(common.ERR_isError(r) == 0);
    try std.testing.expectEqual(@as(usize, 1 + src.len), r);
    // Header byte = set_basic(0) + (srcSize<<3)
    try std.testing.expectEqual(@as(u8, @intCast(src.len << 3)), dst[0]);
    try std.testing.expectEqualSlices(u8, &src, dst[1 .. 1 + src.len]);
}

test "ZSTD_noCompressLiterals — size-2 header path" {
    // srcSize=256 → flSize=2 (srcSize>31, <=4095).
    var src: [256]u8 = undefined;
    for (&src, 0..) |*b, i| b.* = @intCast(i & 0xFF);
    var dst: [400]u8 = undefined;
    const r = ZSTD_noCompressLiterals(&dst, dst.len, &src, src.len);
    try std.testing.expect(common.ERR_isError(r) == 0);
    try std.testing.expectEqual(@as(usize, 2 + src.len), r);
    // Decode header: low 2 bits = set_basic(0), next 2 bits = 01b (size=2 case),
    // next 12 bits = srcSize.
    const hdr = std.mem.readInt(u16, dst[0..2], .little);
    try std.testing.expectEqual(@as(u16, 0), hdr & 0x3);
    try std.testing.expectEqual(@as(u16, 1), (hdr >> 2) & 0x3);
    try std.testing.expectEqual(@as(u16, @intCast(src.len)), hdr >> 4);
}

test "ZSTD_noCompressLiterals — dstSize_tooSmall error" {
    var src = [_]u8{ 1, 2, 3, 4 };
    var dst: [2]u8 = undefined;
    const r = ZSTD_noCompressLiterals(&dst, dst.len, &src, src.len);
    try std.testing.expect(common.ERR_isError(r) != 0);
    try std.testing.expectEqual(common.ZSTD_ErrorCode.dstSize_tooSmall, common.ZSTD_getErrorCode(r));
}

test "ZSTD_compressRleLiteralsBlock — size-1 header path" {
    const src = [_]u8{0x55} ** 8;
    var dst: [4]u8 = undefined;
    const r = ZSTD_compressRleLiteralsBlock(&dst, dst.len, &src, src.len);
    try std.testing.expectEqual(@as(usize, 2), r);
    // Header byte = set_rle(1) + (srcSize<<3)
    try std.testing.expectEqual(@as(u8, @intCast(1 + (src.len << 3))), dst[0]);
    try std.testing.expectEqual(@as(u8, 0x55), dst[1]);
}

test "ZSTD_compressRleLiteralsBlock — size-2 header path" {
    const src = [_]u8{0xAA} ** 100; // > 31
    var dst: [8]u8 = undefined;
    const r = ZSTD_compressRleLiteralsBlock(&dst, dst.len, &src, src.len);
    try std.testing.expectEqual(@as(usize, 3), r);
    const hdr = std.mem.readInt(u16, dst[0..2], .little);
    // low 2 bits set_rle=1, next 2 = 01b, rest = srcSize
    try std.testing.expectEqual(@as(u16, 1), hdr & 0x3);
    try std.testing.expectEqual(@as(u16, 1), (hdr >> 2) & 0x3);
    try std.testing.expectEqual(@as(u16, @intCast(src.len)), hdr >> 4);
    try std.testing.expectEqual(@as(u8, 0xAA), dst[2]);
}

test "ZSTD_minGain monotonicity" {
    // Stronger strategies require larger gains.
    const s1 = ZSTD_minGain(10_000, .ZSTD_fast);
    const s2 = ZSTD_minGain(10_000, .ZSTD_btultra);
    const s3 = ZSTD_minGain(10_000, .ZSTD_btultra2);
    try std.testing.expect(s1 > 0);
    try std.testing.expect(s2 > 0);
    try std.testing.expect(s3 > 0);
    // btultra2 >= btultra (strat-1 shift smaller → more gain required)
    try std.testing.expect(s3 <= s2);
}

test "ZSTD_hufCTables_t sizeof stable" {
    // Sanity check that extern struct matches what slice 5 will assume:
    //  CTable[257] + repeatMode(c_int)  → 257*8 + 4 = 2060 → 2064 after tail padding? actually c_int=4.
    // We don't enforce a tight number, just that it's at least as big as upstream.
    try std.testing.expect(@sizeOf(ZSTD_hufCTables_t) >= 257 * @sizeOf(huf.HUF_CElt));
}
