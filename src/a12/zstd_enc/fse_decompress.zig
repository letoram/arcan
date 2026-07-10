// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/common/fse_decompress.c — FSE decoder.
//
// Upstream:
//   FSE : Finite State Entropy decoder
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// Purpose inside the zstd_enc tree: the encoder itself does not call the FSE
// *decoder* directly, but the shared `HUF_readStats_wksp` helper in
// entropy_common.zig invokes `FSE_decompress_wksp_bmi2` when a Huffman table
// arrives with its weights FSE-compressed. That path is exercised whenever
// the encoder parses a dictionary (ZSTD_loadCEntropy ultimately reads Huffman
// stats from the dictionary bytes), so a correct implementation is required
// here for dictionary support even though the encoder itself never decodes
// non-dictionary frames.
//
// DYNAMIC_BMI2 is folded away for our platform — `bmi2` argument is ignored.

const std = @import("std");
const common = @import("zstd_common.zig");
const ec = @import("entropy_common.zig");

const ZSTD_ErrorCode = common.ZSTD_ErrorCode;
const zstdError = common.zstdError;

const FSE_MAX_SYMBOL_VALUE = ec.FSE_MAX_SYMBOL_VALUE; // 255
const FSE_MAX_TABLELOG = ec.FSE_MAX_TABLELOG; // 12

// FSE_DTable is defined in fse.h as `unsigned`; an FSE_DTable[] pointer starts
// with a 1-word header then `1 << tableLog` entries of FSE_decode_t.
pub const FSE_DTable = u32;

const FSE_DTableHeader = extern struct {
    tableLog: u16,
    fastMode: u16,
};

const FSE_decode_t = extern struct {
    newState: u16,
    symbol: u8,
    nbBits: u8,
};

// FSE_BUILD_DTABLE_WKSP_SIZE(tableLog, maxSymbolValue)
inline fn fseBuildDTableWkspSize(tableLog: u32, maxSymbolValue: u32) usize {
    return @sizeOf(i16) * (maxSymbolValue + 1) + (@as(usize, 1) << @intCast(tableLog)) + 8;
}

// FSE_DTABLE_SIZE(tableLog) in bytes
inline fn fseDTableSize(tableLog: u32) usize {
    return (1 + (@as(usize, 1) << @intCast(tableLog))) * @sizeOf(FSE_DTable);
}

inline fn fseTableStep(tableSize: u32) u32 {
    return (tableSize >> 1) + (tableSize >> 3) + 3;
}

// -------------------------------------------------------------------------
//  BIT_* decoder primitives (inlined from bitstream.h).
//  64-bit container, little-endian — matches BIT_DStream_t layout exactly.
// -------------------------------------------------------------------------
const BIT_DStream_status = enum(c_uint) {
    unfinished = 0,
    endOfBuffer = 1,
    completed = 2,
    overflow = 3,
};

const BIT_DStream_t = struct {
    bitContainer: u64,
    bitsConsumed: u32,
    ptr: [*]const u8,
    start: [*]const u8,
    limitPtr: [*]const u8,
};

fn bitInitDStream(bitD: *BIT_DStream_t, src: [*]const u8, srcSize: usize) usize {
    if (srcSize < 1) {
        bitD.* = .{
            .bitContainer = 0,
            .bitsConsumed = 0,
            .ptr = src,
            .start = src,
            .limitPtr = src,
        };
        return zstdError(.srcSize_wrong);
    }
    bitD.start = src;
    bitD.limitPtr = src + @sizeOf(u64);
    if (srcSize >= @sizeOf(u64)) {
        bitD.ptr = src + srcSize - @sizeOf(u64);
        bitD.bitContainer = std.mem.readInt(u64, bitD.ptr[0..8], .little);
        const lastByte = src[srcSize - 1];
        if (lastByte == 0) return zstdError(.generic_err);
        bitD.bitsConsumed = 8 - highbit32(lastByte);
    } else {
        bitD.ptr = src;
        var bc: u64 = src[0];
        // fall-through switch from upstream
        if (srcSize >= 7) bc += @as(u64, src[6]) << (64 - 16);
        if (srcSize >= 6) bc += @as(u64, src[5]) << (64 - 24);
        if (srcSize >= 5) bc += @as(u64, src[4]) << (64 - 32);
        if (srcSize >= 4) bc += @as(u64, src[3]) << 24;
        if (srcSize >= 3) bc += @as(u64, src[2]) << 16;
        if (srcSize >= 2) bc += @as(u64, src[1]) << 8;
        bitD.bitContainer = bc;
        const lastByte = src[srcSize - 1];
        if (lastByte == 0) return zstdError(.corruption_detected);
        bitD.bitsConsumed = 8 - highbit32(lastByte);
        bitD.bitsConsumed += @intCast((@sizeOf(u64) - srcSize) * 8);
    }
    return srcSize;
}

inline fn highbit32(val: u32) u32 {
    std.debug.assert(val != 0);
    return 31 - @clz(val);
}

inline fn bitLookBits(bitD: *const BIT_DStream_t, nbBits: u32) u64 {
    const start: u6 = @intCast(64 - bitD.bitsConsumed - nbBits);
    if (nbBits == 0) return 0;
    const mask: u64 = (@as(u64, 1) << @intCast(nbBits)) - 1;
    return (bitD.bitContainer >> start) & mask;
}

inline fn bitLookBitsFast(bitD: *const BIT_DStream_t, nbBits: u32) u64 {
    std.debug.assert(nbBits >= 1);
    const regMask: u32 = 63;
    const l: u6 = @intCast(bitD.bitsConsumed & regMask);
    const r: u6 = @intCast((regMask + 1 - nbBits) & regMask);
    return (bitD.bitContainer << l) >> r;
}

inline fn bitSkipBits(bitD: *BIT_DStream_t, nbBits: u32) void {
    bitD.bitsConsumed += nbBits;
}

inline fn bitReadBits(bitD: *BIT_DStream_t, nbBits: u32) u64 {
    const v = bitLookBits(bitD, nbBits);
    bitSkipBits(bitD, nbBits);
    return v;
}

inline fn bitReadBitsFast(bitD: *BIT_DStream_t, nbBits: u32) u64 {
    const v = bitLookBitsFast(bitD, nbBits);
    bitSkipBits(bitD, nbBits);
    return v;
}

fn bitReloadDStream(bitD: *BIT_DStream_t) BIT_DStream_status {
    if (bitD.bitsConsumed > 64) {
        // overflow — rebind ptr to a zero word so further reads are harmless
        const zeroBytes = struct {
            const v: [8]u8 = [_]u8{0} ** 8;
        };
        bitD.ptr = &zeroBytes.v;
        return .overflow;
    }
    std.debug.assert(@intFromPtr(bitD.ptr) >= @intFromPtr(bitD.start));
    if (@intFromPtr(bitD.ptr) >= @intFromPtr(bitD.limitPtr)) {
        bitD.ptr -= bitD.bitsConsumed >> 3;
        bitD.bitsConsumed &= 7;
        bitD.bitContainer = std.mem.readInt(u64, bitD.ptr[0..8], .little);
        return .unfinished;
    }
    if (bitD.ptr == bitD.start) {
        if (bitD.bitsConsumed < 64) return .endOfBuffer;
        return .completed;
    }
    var nbBytes: u32 = bitD.bitsConsumed >> 3;
    var result: BIT_DStream_status = .unfinished;
    const delta: usize = @intFromPtr(bitD.ptr) - @intFromPtr(bitD.start);
    if (nbBytes > delta) {
        nbBytes = @intCast(delta);
        result = .endOfBuffer;
    }
    bitD.ptr -= nbBytes;
    bitD.bitsConsumed -= nbBytes * 8;
    bitD.bitContainer = std.mem.readInt(u64, bitD.ptr[0..8], .little);
    return result;
}

// -------------------------------------------------------------------------
//  FSE_DState / decoding helpers
// -------------------------------------------------------------------------
const FSE_DState_t = struct {
    state: u64,
    table: [*]const FSE_decode_t,
};

fn fseInitDState(s: *FSE_DState_t, bitD: *BIT_DStream_t, dt: [*]const FSE_DTable) void {
    const hdr: *const FSE_DTableHeader = @ptrCast(@alignCast(dt));
    s.state = bitReadBits(bitD, hdr.tableLog);
    _ = bitReloadDStream(bitD);
    s.table = @ptrCast(@alignCast(dt + 1));
}

inline fn fseDecodeSymbol(s: *FSE_DState_t, bitD: *BIT_DStream_t) u8 {
    const info = s.table[s.state];
    const lowBits = bitReadBits(bitD, info.nbBits);
    s.state = @as(u64, info.newState) + lowBits;
    return info.symbol;
}

inline fn fseDecodeSymbolFast(s: *FSE_DState_t, bitD: *BIT_DStream_t) u8 {
    const info = s.table[s.state];
    const lowBits = bitReadBitsFast(bitD, info.nbBits);
    s.state = @as(u64, info.newState) + lowBits;
    return info.symbol;
}

// -------------------------------------------------------------------------
//  FSE_buildDTable_internal — builds a decoding table from a normalized
//  distribution. Zig port of the upstream template-instantiated body.
// -------------------------------------------------------------------------
fn fseBuildDTableInternal(
    dt: [*]FSE_DTable,
    normalizedCounter: [*]const i16,
    maxSymbolValue: u32,
    tableLog: u32,
    workSpace: [*]u8,
    wkspSize: usize,
) usize {
    // Layout of dt: [header(1 u32)] [table entries...]
    const tdPtr: [*]FSE_decode_t = @ptrCast(@alignCast(dt + 1));
    const tableDecode = tdPtr;

    const maxSV1: u32 = maxSymbolValue + 1;
    const tableSize: u32 = @as(u32, 1) << @intCast(tableLog);
    var highThreshold: u32 = tableSize - 1;

    if (fseBuildDTableWkspSize(tableLog, maxSymbolValue) > wkspSize)
        return zstdError(.maxSymbolValue_tooLarge);
    if (maxSymbolValue > FSE_MAX_SYMBOL_VALUE) return zstdError(.maxSymbolValue_tooLarge);
    if (tableLog > FSE_MAX_TABLELOG) return zstdError(.tableLog_tooLarge);

    // symbolNext occupies (maxSV1+1)*2 bytes at workspace start; spread[] follows.
    const symbolNext: [*]u16 = @ptrCast(@alignCast(workSpace));
    const spread: [*]u8 = workSpace + (maxSymbolValue + 1) * @sizeOf(u16);

    // Header + lay down lowprob symbols
    var hdr: FSE_DTableHeader = .{ .tableLog = @intCast(tableLog), .fastMode = 1 };
    {
        const largeLimit: i16 = @intCast(@as(u32, 1) << @intCast(tableLog - 1));
        var s: u32 = 0;
        while (s < maxSV1) : (s += 1) {
            if (normalizedCounter[s] == -1) {
                tableDecode[highThreshold].symbol = @intCast(s);
                highThreshold -%= 1;
                symbolNext[s] = 1;
            } else {
                if (normalizedCounter[s] >= largeLimit) hdr.fastMode = 0;
                symbolNext[s] = @bitCast(normalizedCounter[s]);
            }
        }
    }
    @memcpy(@as([*]u8, @ptrCast(dt))[0..@sizeOf(FSE_DTableHeader)], std.mem.asBytes(&hdr));

    // Spread symbols
    if (highThreshold == tableSize - 1) {
        const tableMask: usize = tableSize - 1;
        const step: usize = fseTableStep(tableSize);
        // lay down symbol positions byte-by-byte (upstream writes u64 chunks;
        // we rely on @memset which is equally fast and simpler).
        {
            var pos: usize = 0;
            var s: u32 = 0;
            while (s < maxSV1) : (s += 1) {
                const n: i32 = normalizedCounter[s];
                if (n > 0) {
                    @memset(spread[pos .. pos + @as(usize, @intCast(n))], @intCast(s));
                    pos += @intCast(n);
                }
            }
        }
        // scatter positions across the table (unroll=2 as upstream)
        {
            var position: usize = 0;
            const unroll: usize = 2;
            std.debug.assert(tableSize % unroll == 0);
            var s: usize = 0;
            while (s < tableSize) : (s += unroll) {
                var u: usize = 0;
                while (u < unroll) : (u += 1) {
                    const uPosition = (position + (u * step)) & tableMask;
                    tableDecode[uPosition].symbol = spread[s + u];
                }
                position = (position + (unroll * step)) & tableMask;
            }
            std.debug.assert(position == 0);
        }
    } else {
        const tableMask: u32 = tableSize - 1;
        const step: u32 = fseTableStep(tableSize);
        var position: u32 = 0;
        var s: u32 = 0;
        while (s < maxSV1) : (s += 1) {
            var i: i32 = 0;
            while (i < normalizedCounter[s]) : (i += 1) {
                tableDecode[position].symbol = @intCast(s);
                position = (position + step) & tableMask;
                while (position > highThreshold) position = (position + step) & tableMask;
            }
        }
        if (position != 0) return zstdError(.generic_err);
    }

    // Build decoding transitions
    {
        var u: u32 = 0;
        while (u < tableSize) : (u += 1) {
            const symbol = tableDecode[u].symbol;
            const nextState: u32 = symbolNext[symbol];
            symbolNext[symbol] += 1;
            tableDecode[u].nbBits = @intCast(tableLog - highbit32(nextState));
            tableDecode[u].newState = @intCast((nextState << @intCast(tableDecode[u].nbBits)) - tableSize);
        }
    }
    return 0;
}

pub export fn FSE_buildDTable_wksp(
    dt: [*]FSE_DTable,
    normalizedCounter: [*]const i16,
    maxSymbolValue: c_uint,
    tableLog: c_uint,
    workSpace: ?*anyopaque,
    wkspSize: usize,
) usize {
    const ws: [*]u8 = @ptrCast(workSpace.?);
    return fseBuildDTableInternal(dt, normalizedCounter, maxSymbolValue, tableLog, ws, wkspSize);
}

// -------------------------------------------------------------------------
//  FSE_decompress_usingDTable_generic — main decode loop, 2-state variant.
// -------------------------------------------------------------------------
fn fseDecompressUsingDTableGeneric(
    dst: [*]u8,
    maxDstSize: usize,
    cSrc: [*]const u8,
    cSrcSize: usize,
    dt: [*]const FSE_DTable,
    fast: bool,
) usize {
    const ostart = dst;
    var op = dst;
    const omax = dst + maxDstSize;
    const olimit = omax - 3;

    var bitD: BIT_DStream_t = undefined;
    {
        const r = bitInitDStream(&bitD, cSrc, cSrcSize);
        if (common.ERR_isError(r) != 0) return r;
    }

    var state1: FSE_DState_t = undefined;
    var state2: FSE_DState_t = undefined;
    fseInitDState(&state1, &bitD, dt);
    fseInitDState(&state2, &bitD, dt);

    if (bitReloadDStream(&bitD) == .overflow) return zstdError(.corruption_detected);

    // 4 symbols per loop. 64-bit container with FSE_MAX_TABLELOG=12 means
    // FSE_MAX_TABLELOG*4+7 = 55 < 64 — so the inner reload-after-2 branch is
    // static-false and dropped entirely.
    while (true) {
        const status = bitReloadDStream(&bitD);
        if (status != .unfinished) break;
        if (@intFromPtr(op) >= @intFromPtr(olimit)) break;
        if (fast) {
            op[0] = fseDecodeSymbolFast(&state1, &bitD);
            op[1] = fseDecodeSymbolFast(&state2, &bitD);
            op[2] = fseDecodeSymbolFast(&state1, &bitD);
            op[3] = fseDecodeSymbolFast(&state2, &bitD);
        } else {
            op[0] = fseDecodeSymbol(&state1, &bitD);
            op[1] = fseDecodeSymbol(&state2, &bitD);
            op[2] = fseDecodeSymbol(&state1, &bitD);
            op[3] = fseDecodeSymbol(&state2, &bitD);
        }
        op += 4;
    }

    // tail loop — exits on overflow
    while (true) {
        if (@intFromPtr(op) > @intFromPtr(omax) - 2) return zstdError(.dstSize_tooSmall);
        op[0] = if (fast) fseDecodeSymbolFast(&state1, &bitD) else fseDecodeSymbol(&state1, &bitD);
        op += 1;
        if (bitReloadDStream(&bitD) == .overflow) {
            op[0] = if (fast) fseDecodeSymbolFast(&state2, &bitD) else fseDecodeSymbol(&state2, &bitD);
            op += 1;
            break;
        }
        if (@intFromPtr(op) > @intFromPtr(omax) - 2) return zstdError(.dstSize_tooSmall);
        op[0] = if (fast) fseDecodeSymbolFast(&state2, &bitD) else fseDecodeSymbol(&state2, &bitD);
        op += 1;
        if (bitReloadDStream(&bitD) == .overflow) {
            op[0] = if (fast) fseDecodeSymbolFast(&state1, &bitD) else fseDecodeSymbol(&state1, &bitD);
            op += 1;
            break;
        }
    }

    return @intFromPtr(op) - @intFromPtr(ostart);
}

// -------------------------------------------------------------------------
//  FSE_decompress_wksp_bmi2 — public entry consumed by HUF_readStats_wksp.
// -------------------------------------------------------------------------
const FSE_DecompressWksp = extern struct {
    ncount: [FSE_MAX_SYMBOL_VALUE + 1]i16,
};

pub export fn FSE_decompress_wksp_bmi2(
    dst: ?*anyopaque,
    dstCapacity: usize,
    cSrc: ?*const anyopaque,
    cSrcSize_in: usize,
    maxLog: c_uint,
    workSpace: ?*anyopaque,
    wkspSize_in: usize,
    bmi2: c_int,
) usize {
    _ = bmi2; // DYNAMIC_BMI2 disabled
    const istart: [*]const u8 = @ptrCast(cSrc.?);
    var ip = istart;
    var cSrcSize = cSrcSize_in;
    var wkspSize = wkspSize_in;
    var tableLog: c_uint = 0;
    var maxSymbolValue: c_uint = FSE_MAX_SYMBOL_VALUE;

    const ws_u8: [*]u8 = @ptrCast(workSpace.?);
    if (wkspSize < @sizeOf(FSE_DecompressWksp)) return zstdError(.generic_err);
    const wksp: *FSE_DecompressWksp = @ptrCast(@alignCast(ws_u8));

    const dtable: [*]FSE_DTable = @ptrCast(@alignCast(ws_u8 + @sizeOf(FSE_DecompressWksp)));

    // Decode NCount header
    {
        const n = ec.FSE_readNCount_bmi2(
            @ptrCast(&wksp.ncount[0]),
            &maxSymbolValue,
            &tableLog,
            istart,
            cSrcSize,
            0,
        );
        if (common.ERR_isError(n) != 0) return n;
        if (tableLog > maxLog) return zstdError(.tableLog_tooLarge);
        std.debug.assert(n <= cSrcSize);
        ip += n;
        cSrcSize -= n;
    }

    const dtSize = fseDTableSize(tableLog);
    if (@sizeOf(FSE_DecompressWksp) + dtSize > wkspSize_in) return zstdError(.tableLog_tooLarge);
    const sub_ws: [*]u8 = ws_u8 + @sizeOf(FSE_DecompressWksp) + dtSize;
    wkspSize -= @sizeOf(FSE_DecompressWksp) + dtSize;

    {
        const r = fseBuildDTableInternal(dtable, @as([*]const i16, &wksp.ncount), maxSymbolValue, tableLog, sub_ws, wkspSize);
        if (common.ERR_isError(r) != 0) return r;
    }

    const hdr: *const FSE_DTableHeader = @ptrCast(@alignCast(dtable));
    const fastMode = hdr.fastMode != 0;
    const dstP: [*]u8 = @ptrCast(dst.?);
    return fseDecompressUsingDTableGeneric(dstP, dstCapacity, ip, cSrcSize, dtable, fastMode);
}

// -------------------------------------------------------------------------
//  Sanity checks
// -------------------------------------------------------------------------
test "FSE_DTableHeader layout" {
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(FSE_DTableHeader));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(FSE_decode_t));
}

test "buildDTable rejects bad params" {
    var dt: [1 + (1 << 12)]FSE_DTable = undefined;
    var ws: [8192]u8 = undefined;
    var nc: [256]i16 = [_]i16{0} ** 256;
    nc[0] = 1 << 11;
    // tableLog > FSE_MAX_TABLELOG must fail
    const r = FSE_buildDTable_wksp(&dt, &nc, 1, 13, &ws, ws.len);
    try std.testing.expect(common.ERR_isError(r) != 0);
}
