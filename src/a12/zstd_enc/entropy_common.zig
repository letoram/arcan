// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/common/entropy_common.c — shared FSE/HUF helpers
// used by both encoder and decoder paths.
//
// Upstream:
//   Common functions of New Generation Entropy library
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// Public entry points kept on C-ABI linker names via `pub export fn`:
//   FSE_versionNumber, FSE_isError, FSE_getErrorName,
//   HUF_isError, HUF_getErrorName,
//   FSE_readNCount, FSE_readNCount_bmi2,
//   HUF_readStats, HUF_readStats_wksp.
//
// `HUF_readStats_body` calls FSE_decompress_wksp_bmi2; that function lives in
// fse_decompress.zig (same slice). All `MEM_readLE32` uses lower to
// `std.mem.readInt(u32, …, .little)`.

const std = @import("std");
const common = @import("zstd_common.zig");

const ZSTD_ErrorCode = common.ZSTD_ErrorCode;
const zstdError = common.zstdError;

// -------------------------------------------------------------------------
//  FSE/HUF constants mirrored from lib/common/fse.h and lib/common/huf.h
// -------------------------------------------------------------------------
pub const FSE_VERSION_MAJOR: c_uint = 0;
pub const FSE_VERSION_MINOR: c_uint = 9;
pub const FSE_VERSION_RELEASE: c_uint = 0;
pub const FSE_VERSION_NUMBER: c_uint =
    FSE_VERSION_MAJOR * 100 * 100 + FSE_VERSION_MINOR * 100 + FSE_VERSION_RELEASE;

pub const FSE_MAX_MEMORY_USAGE: c_uint = 14;
pub const FSE_DEFAULT_MEMORY_USAGE: c_uint = 13;
pub const FSE_MAX_SYMBOL_VALUE: c_uint = 255;
pub const FSE_MAX_TABLELOG: c_uint = FSE_MAX_MEMORY_USAGE - 2; // 12
pub const FSE_MAX_TABLESIZE: c_uint = @as(c_uint, 1) << @intCast(FSE_MAX_TABLELOG);
pub const FSE_DEFAULT_TABLELOG: c_uint = FSE_DEFAULT_MEMORY_USAGE - 2; // 11
pub const FSE_MIN_TABLELOG: c_uint = 5;
pub const FSE_TABLELOG_ABSOLUTE_MAX: c_uint = 15;

pub const FSE_NCOUNTBOUND: usize = 512;

pub const HUF_TABLELOG_MAX: c_uint = 12;
pub const HUF_TABLELOG_ABSOLUTEMAX: c_uint = 12;
pub const HUF_SYMBOLVALUE_MAX: c_uint = 255;

pub const HUF_flags_bmi2: c_int = 1 << 0;
pub const HUF_flags_optimalDepth: c_int = 1 << 1;
pub const HUF_flags_preferRepeat: c_int = 1 << 2;
pub const HUF_flags_suspectUncompressible: c_int = 1 << 3;
pub const HUF_flags_disableAsm: c_int = 1 << 4;
pub const HUF_flags_disableFast: c_int = 1 << 5;

// FSE_DECOMPRESS_WKSP_SIZE_U32(6, HUF_TABLELOG_MAX-1) with HUF_TABLELOG_MAX=12
//   = FSE_DTABLE_SIZE_U32(6) + 1 + FSE_BUILD_DTABLE_WKSP_SIZE_U32(6, 11) + (256)/2 + 1
//   = 65 + 1 + 43 + 128 + 1 = 238? Upstream defines: HUF_READ_STATS_WORKSPACE_SIZE_U32
// Compute at comptime so it matches upstream exactly.
pub const HUF_READ_STATS_WORKSPACE_SIZE_U32: usize = blk: {
    const dtable_size_u32: usize = 1 + (1 << 6); // FSE_DTABLE_SIZE_U32(6) = 65
    const build_dtable_wksp_size: usize = @sizeOf(i16) * (11 + 1) + (1 << 6) + 8; // 24+64+8 = 96
    const build_dtable_wksp_size_u32: usize = (build_dtable_wksp_size + @sizeOf(c_uint) - 1) / @sizeOf(c_uint);
    break :blk dtable_size_u32 + 1 + build_dtable_wksp_size_u32 + (FSE_MAX_SYMBOL_VALUE + 1) / 2 + 1;
};

// -------------------------------------------------------------------------
//  bits.h helpers used here — countTrailingZeros32 / highbit32
// -------------------------------------------------------------------------
pub inline fn ZSTD_highbit32(val: u32) u32 {
    std.debug.assert(val != 0);
    return 31 - @clz(val);
}

pub inline fn ZSTD_countTrailingZeros32(val: u32) u32 {
    std.debug.assert(val != 0);
    return @ctz(val);
}

// -------------------------------------------------------------------------
//  Version / Error plumbing
// -------------------------------------------------------------------------
pub export fn FSE_versionNumber() c_uint {
    return FSE_VERSION_NUMBER;
}

pub export fn FSE_isError(code: usize) c_uint {
    return common.ERR_isError(code);
}

pub export fn FSE_getErrorName(code: usize) [*:0]const u8 {
    return common.ERR_getErrorName(code);
}

pub export fn HUF_isError(code: usize) c_uint {
    return common.ERR_isError(code);
}

pub export fn HUF_getErrorName(code: usize) [*:0]const u8 {
    return common.ERR_getErrorName(code);
}

// -------------------------------------------------------------------------
//  FSE_readNCount — decode a compactly-saved normalized distribution.
//
//  Port of FSE_readNCount_body. DYNAMIC_BMI2 path is folded away (the
//  compile-time target on our platform never enables it); the public
//  FSE_readNCount_bmi2 accepts the flag and always dispatches to the scalar
//  body, matching the `(void)bmi2` upstream branch.
// -------------------------------------------------------------------------
fn readNCountBody(
    normalizedCounter: [*]i16,
    maxSVPtr: *c_uint,
    tableLogPtr: *c_uint,
    headerBuffer: [*]const u8,
    hbSize: usize,
) usize {
    if (hbSize < 8) {
        // Pad short inputs into a scratch buffer and recurse.
        var buffer: [8]u8 = [_]u8{0} ** 8;
        @memcpy(buffer[0..hbSize], headerBuffer[0..hbSize]);
        const countSize = FSE_readNCount(normalizedCounter, maxSVPtr, tableLogPtr, &buffer, buffer.len);
        if (FSE_isError(countSize) != 0) return countSize;
        if (countSize > hbSize) return zstdError(.corruption_detected);
        return countSize;
    }
    std.debug.assert(hbSize >= 8);

    const istart = headerBuffer;
    const iend = headerBuffer + hbSize;
    var ip = headerBuffer;

    const maxSV1 = maxSVPtr.* + 1;
    var previous0: bool = false;
    var charnum: c_uint = 0;

    // all symbols not present in NCount have a frequency of 0
    @memset(normalizedCounter[0..maxSV1], 0);

    var bitStream: u32 = std.mem.readInt(u32, ip[0..4], .little);
    var nbBits: i32 = @intCast((bitStream & 0xF) + FSE_MIN_TABLELOG);
    if (nbBits > FSE_TABLELOG_ABSOLUTE_MAX) return zstdError(.tableLog_tooLarge);
    bitStream >>= 4;
    var bitCount: i32 = 4;
    tableLogPtr.* = @intCast(nbBits);
    var remaining: i32 = (@as(i32, 1) << @intCast(nbBits)) + 1;
    var threshold: i32 = @as(i32, 1) << @intCast(nbBits);
    nbBits += 1;

    outer: while (true) {
        if (previous0) {
            // Count 2-bit repeats (0b11 = another repeat).
            var repeats: u32 = ZSTD_countTrailingZeros32(~bitStream | 0x80000000) >> 1;
            while (repeats >= 12) {
                charnum += 3 * 12;
                if (@intFromPtr(ip) <= @intFromPtr(iend) - 7) {
                    ip += 3;
                } else {
                    // bitCount -= 8 * (iend - 7 - ip)
                    const delta: isize = @as(isize, @intCast(@intFromPtr(iend) - 7 - @intFromPtr(ip)));
                    bitCount -= @intCast(8 * delta);
                    bitCount &= 31;
                    ip = iend - 4;
                }
                bitStream = std.mem.readInt(u32, ip[0..4], .little) >> @intCast(bitCount);
                repeats = ZSTD_countTrailingZeros32(~bitStream | 0x80000000) >> 1;
            }
            charnum += 3 * repeats;
            bitStream >>= @intCast(2 * repeats);
            bitCount += @intCast(2 * repeats);

            // final (non-0b11) repeat
            std.debug.assert((bitStream & 3) < 3);
            charnum += bitStream & 3;
            bitCount += 2;

            if (charnum >= maxSV1) break :outer;

            if (@intFromPtr(ip) <= @intFromPtr(iend) - 7 or
                @intFromPtr(ip) + @as(usize, @intCast(bitCount >> 3)) <= @intFromPtr(iend) - 4)
            {
                std.debug.assert((bitCount >> 3) <= 3);
                ip += @intCast(bitCount >> 3);
                bitCount &= 7;
            } else {
                const delta: isize = @as(isize, @intCast(@intFromPtr(iend) - 4 - @intFromPtr(ip)));
                bitCount -= @intCast(8 * delta);
                bitCount &= 31;
                ip = iend - 4;
            }
            bitStream = std.mem.readInt(u32, ip[0..4], .little) >> @intCast(bitCount);
        }
        {
            const max: i32 = (2 * threshold - 1) - remaining;
            var count: i32 = undefined;
            if (@as(i32, @intCast(bitStream & @as(u32, @intCast(threshold - 1)))) < max) {
                count = @intCast(bitStream & @as(u32, @intCast(threshold - 1)));
                bitCount += nbBits - 1;
            } else {
                count = @intCast(bitStream & @as(u32, @intCast(2 * threshold - 1)));
                if (count >= threshold) count -= max;
                bitCount += nbBits;
            }

            count -= 1; // extra accuracy
            if (count >= 0) {
                remaining -= count;
            } else {
                std.debug.assert(count == -1);
                remaining += count;
            }
            normalizedCounter[charnum] = @intCast(count);
            charnum += 1;
            previous0 = (count == 0);

            std.debug.assert(threshold > 1);
            if (remaining < threshold) {
                if (remaining <= 1) break :outer;
                nbBits = @intCast(ZSTD_highbit32(@intCast(remaining)) + 1);
                threshold = @as(i32, 1) << @intCast(nbBits - 1);
            }
            if (charnum >= maxSV1) break :outer;

            if (@intFromPtr(ip) <= @intFromPtr(iend) - 7 or
                @intFromPtr(ip) + @as(usize, @intCast(bitCount >> 3)) <= @intFromPtr(iend) - 4)
            {
                ip += @intCast(bitCount >> 3);
                bitCount &= 7;
            } else {
                const delta: isize = @as(isize, @intCast(@intFromPtr(iend) - 4 - @intFromPtr(ip)));
                bitCount -= @intCast(8 * delta);
                bitCount &= 31;
                ip = iend - 4;
            }
            bitStream = std.mem.readInt(u32, ip[0..4], .little) >> @intCast(bitCount);
        }
    }
    if (remaining != 1) return zstdError(.corruption_detected);
    if (charnum > maxSV1) return zstdError(.maxSymbolValue_tooSmall);
    if (bitCount > 32) return zstdError(.corruption_detected);
    maxSVPtr.* = charnum - 1;

    ip += @intCast((bitCount + 7) >> 3);
    return @intFromPtr(ip) - @intFromPtr(istart);
}

pub export fn FSE_readNCount_bmi2(
    normalizedCounter: [*]i16,
    maxSVPtr: *c_uint,
    tableLogPtr: *c_uint,
    headerBuffer: ?*const anyopaque,
    hbSize: usize,
    bmi2: c_int,
) usize {
    _ = bmi2; // DYNAMIC_BMI2 disabled on this platform
    const hb: [*]const u8 = @ptrCast(headerBuffer.?);
    return readNCountBody(normalizedCounter, maxSVPtr, tableLogPtr, hb, hbSize);
}

pub export fn FSE_readNCount(
    normalizedCounter: [*]i16,
    maxSVPtr: *c_uint,
    tableLogPtr: *c_uint,
    headerBuffer: ?*const anyopaque,
    hbSize: usize,
) usize {
    return FSE_readNCount_bmi2(normalizedCounter, maxSVPtr, tableLogPtr, headerBuffer, hbSize, 0);
}

// -------------------------------------------------------------------------
//  HUF_readStats — parses a Huffman header into per-symbol weights + counts.
//
//  Cross-file dependency: the FSE-compressed header path calls
//  FSE_decompress_wksp_bmi2 (defined in fse_decompress.zig). We declare it
//  extern so link-time resolution finds the Zig-side definition.
// -------------------------------------------------------------------------
extern fn FSE_decompress_wksp_bmi2(
    dst: ?*anyopaque,
    dstCapacity: usize,
    cSrc: ?*const anyopaque,
    cSrcSize: usize,
    maxLog: c_uint,
    workSpace: ?*anyopaque,
    wkspSize: usize,
    bmi2: c_int,
) usize;

fn readStatsBody(
    huffWeight: [*]u8,
    hwSize: usize,
    rankStats: [*]u32,
    nbSymbolsPtr: *u32,
    tableLogPtr: *u32,
    src: [*]const u8,
    srcSize: usize,
    workSpace: ?*anyopaque,
    wkspSize: usize,
    bmi2: c_int,
) usize {
    if (srcSize == 0) return zstdError(.srcSize_wrong);
    var ip = src;
    var iSize: usize = ip[0];
    var oSize: usize = 0;

    if (iSize >= 128) {
        // special header: weights packed 2 per byte
        oSize = iSize - 127;
        iSize = (oSize + 1) / 2;
        if (iSize + 1 > srcSize) return zstdError(.srcSize_wrong);
        if (oSize >= hwSize) return zstdError(.corruption_detected);
        ip += 1;
        var n: usize = 0;
        while (n < oSize) : (n += 2) {
            huffWeight[n] = ip[n / 2] >> 4;
            huffWeight[n + 1] = ip[n / 2] & 15;
        }
    } else {
        // FSE-compressed weights table
        if (iSize + 1 > srcSize) return zstdError(.srcSize_wrong);
        oSize = FSE_decompress_wksp_bmi2(
            huffWeight,
            hwSize - 1,
            ip + 1,
            iSize,
            6,
            workSpace,
            wkspSize,
            bmi2,
        );
        if (FSE_isError(oSize) != 0) return oSize;
    }

    // collect weight stats
    @memset(rankStats[0 .. HUF_TABLELOG_MAX + 1], 0);
    var weightTotal: u32 = 0;
    {
        var n: usize = 0;
        while (n < oSize) : (n += 1) {
            if (huffWeight[n] > HUF_TABLELOG_MAX) return zstdError(.corruption_detected);
            rankStats[huffWeight[n]] += 1;
            weightTotal += (@as(u32, 1) << @intCast(huffWeight[n])) >> 1;
        }
    }
    if (weightTotal == 0) return zstdError(.corruption_detected);

    // last non-null symbol weight is implied — total must be 2^n
    const tableLog: u32 = ZSTD_highbit32(weightTotal) + 1;
    if (tableLog > HUF_TABLELOG_MAX) return zstdError(.corruption_detected);
    tableLogPtr.* = tableLog;
    {
        const total: u32 = @as(u32, 1) << @intCast(tableLog);
        const rest: u32 = total - weightTotal;
        const verif: u32 = @as(u32, 1) << @intCast(ZSTD_highbit32(rest));
        const lastWeight: u32 = ZSTD_highbit32(rest) + 1;
        if (verif != rest) return zstdError(.corruption_detected); // must be clean pow2
        huffWeight[oSize] = @intCast(lastWeight);
        rankStats[lastWeight] += 1;
    }

    // tree validity: at least 2 rank-1 symbols, even count
    if (rankStats[1] < 2 or (rankStats[1] & 1) != 0) return zstdError(.corruption_detected);

    nbSymbolsPtr.* = @intCast(oSize + 1);
    return iSize + 1;
}

pub export fn HUF_readStats_wksp(
    huffWeight: [*]u8,
    hwSize: usize,
    rankStats: [*]u32,
    nbSymbolsPtr: *u32,
    tableLogPtr: *u32,
    src: ?*const anyopaque,
    srcSize: usize,
    workSpace: ?*anyopaque,
    wkspSize: usize,
    flags: c_int,
) usize {
    const s: [*]const u8 = @ptrCast(src.?);
    const bmi2: c_int = if ((flags & HUF_flags_bmi2) != 0) 1 else 0;
    return readStatsBody(huffWeight, hwSize, rankStats, nbSymbolsPtr, tableLogPtr, s, srcSize, workSpace, wkspSize, bmi2);
}

pub export fn HUF_readStats(
    huffWeight: [*]u8,
    hwSize: usize,
    rankStats: [*]u32,
    nbSymbolsPtr: *u32,
    tableLogPtr: *u32,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    var wksp: [HUF_READ_STATS_WORKSPACE_SIZE_U32]u32 = undefined;
    return HUF_readStats_wksp(
        huffWeight,
        hwSize,
        rankStats,
        nbSymbolsPtr,
        tableLogPtr,
        src,
        srcSize,
        &wksp,
        @sizeOf(@TypeOf(wksp)),
        0,
    );
}

// -------------------------------------------------------------------------
//  Sanity checks
// -------------------------------------------------------------------------
test "FSE version matches upstream" {
    try std.testing.expectEqual(@as(c_uint, 900), FSE_versionNumber());
}

test "FSE_isError round-trip" {
    const e = zstdError(.tableLog_tooLarge);
    try std.testing.expect(FSE_isError(e) == 1);
    try std.testing.expect(FSE_isError(0) == 0);
    try std.testing.expect(HUF_isError(e) == 1);
}

test "HUF_READ_STATS workspace size sanity" {
    // Must be at least large enough for the FSE decompress workspace.
    try std.testing.expect(HUF_READ_STATS_WORKSPACE_SIZE_U32 > 64);
}
