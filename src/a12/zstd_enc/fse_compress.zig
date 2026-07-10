// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/compress/fse_compress.c — core FSE encoder.
//
// Upstream:
//   FSE : Finite State Entropy encoder
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// Public entry points kept on C-ABI linker names via `pub export fn`:
//   FSE_NCountWriteBound, FSE_writeNCount,
//   FSE_buildCTable_rle, FSE_buildCTable_wksp,
//   FSE_normalizeCount, FSE_optimalTableLog_internal, FSE_optimalTableLog,
//   FSE_compressBound, FSE_compress_usingCTable.
//
// Upstream note: FSE_createCTable/FSE_freeCTable/FSE_buildCTable_raw do not
// exist in zstd 1.5.7 — they were removed from the internal FSE library; all
// callers use the _wksp variants. Similarly FSE_buildDTable_raw/_rle do not
// exist on the decoder side.

const std = @import("std");
const common = @import("zstd_common.zig");
const ec = @import("entropy_common.zig");

const zstdError = common.zstdError;

const FSE_MAX_SYMBOL_VALUE = ec.FSE_MAX_SYMBOL_VALUE; // 255
const FSE_MAX_TABLELOG = ec.FSE_MAX_TABLELOG; // 12
const FSE_MIN_TABLELOG = ec.FSE_MIN_TABLELOG; // 5
const FSE_DEFAULT_TABLELOG = ec.FSE_DEFAULT_TABLELOG; // 11

const FSE_NCOUNTBOUND = ec.FSE_NCOUNTBOUND; // 512

pub const FSE_CTable = u32;

/// FSE_repeat — table-reuse hint shared with downstream sequence encoder.
/// Mirrors `FSE_repeat` in lib/common/fse.h.
pub const FSE_repeat = enum(c_int) {
    FSE_repeat_none = 0,
    FSE_repeat_check = 1,
    FSE_repeat_valid = 2,
};

// FSE_BLOCKBOUND / FSE_COMPRESSBOUND
inline fn fseBlockBound(size: usize) usize {
    return size + (size >> 7) + 4 + @sizeOf(usize);
}

inline fn fseTableStep(tableSize: u32) u32 {
    return (tableSize >> 1) + (tableSize >> 3) + 3;
}

// FSE_symbolCompressionTransform: 8 bytes total
pub const FSE_symbolCompressionTransform = extern struct {
    deltaFindState: i32,
    deltaNbBits: u32,
};

inline fn highbit32(v: u32) u32 {
    std.debug.assert(v != 0);
    return 31 - @clz(v);
}

// -------------------------------------------------------------------------
//  Public: FSE_compressBound
// -------------------------------------------------------------------------
pub export fn FSE_compressBound(size: usize) usize {
    return FSE_NCOUNTBOUND + fseBlockBound(size);
}

// -------------------------------------------------------------------------
//  FSE_NCountWriteBound
// -------------------------------------------------------------------------
pub export fn FSE_NCountWriteBound(maxSymbolValue: c_uint, tableLog: c_uint) usize {
    const maxHeader: usize =
        (((maxSymbolValue + 1) * tableLog + 4 + 2) / 8) + 1 + 2;
    return if (maxSymbolValue != 0) maxHeader else FSE_NCOUNTBOUND;
}

// -------------------------------------------------------------------------
//  FSE_writeNCount_generic — compactly encode a normalized distribution
// -------------------------------------------------------------------------
fn writeNCountGeneric(
    header: [*]u8,
    headerBufferSize: usize,
    normalizedCounter: [*]const i16,
    maxSymbolValue: u32,
    tableLog: u32,
    writeIsSafe: bool,
) usize {
    const ostart = header;
    var out = header;
    const oend = header + headerBufferSize;
    const tableSize: i32 = @as(i32, 1) << @intCast(tableLog);
    var remaining: i32 = tableSize + 1;
    var threshold: i32 = tableSize;
    var nbBits: i32 = @as(i32, @intCast(tableLog)) + 1;
    var bitStream: u32 = 0;
    var bitCount: u32 = 0;
    var symbol: u32 = 0;
    const alphabetSize: u32 = maxSymbolValue + 1;
    var previousIs0 = false;

    // Table Size header
    bitStream += (tableLog - FSE_MIN_TABLELOG) << @intCast(bitCount);
    bitCount += 4;

    while (symbol < alphabetSize and remaining > 1) {
        if (previousIs0) {
            var start: u32 = symbol;
            while (symbol < alphabetSize and normalizedCounter[symbol] == 0) symbol += 1;
            if (symbol == alphabetSize) break;
            while (symbol >= start + 24) {
                start += 24;
                bitStream += @as(u32, 0xFFFF) << @intCast(bitCount);
                if (!writeIsSafe and @intFromPtr(out) > @intFromPtr(oend) - 2)
                    return zstdError(.dstSize_tooSmall);
                out[0] = @truncate(bitStream);
                out[1] = @truncate(bitStream >> 8);
                out += 2;
                bitStream >>= 16;
            }
            while (symbol >= start + 3) {
                start += 3;
                bitStream += @as(u32, 3) << @intCast(bitCount);
                bitCount += 2;
            }
            bitStream += (symbol - start) << @intCast(bitCount);
            bitCount += 2;
            if (bitCount > 16) {
                if (!writeIsSafe and @intFromPtr(out) > @intFromPtr(oend) - 2)
                    return zstdError(.dstSize_tooSmall);
                out[0] = @truncate(bitStream);
                out[1] = @truncate(bitStream >> 8);
                out += 2;
                bitStream >>= 16;
                bitCount -= 16;
            }
        }
        {
            var count: i32 = normalizedCounter[symbol];
            symbol += 1;
            const max: i32 = (2 * threshold - 1) - remaining;
            remaining -= if (count < 0) -count else count;
            count += 1; // +1 for extra accuracy
            if (count >= threshold) count += max;
            bitStream += @as(u32, @intCast(count)) << @intCast(bitCount);
            bitCount += @intCast(nbBits);
            bitCount -= @intFromBool(count < max);
            previousIs0 = (count == 1);
            if (remaining < 1) return zstdError(.generic_err);
            while (remaining < threshold) {
                nbBits -= 1;
                threshold >>= 1;
            }
        }
        if (bitCount > 16) {
            if (!writeIsSafe and @intFromPtr(out) > @intFromPtr(oend) - 2)
                return zstdError(.dstSize_tooSmall);
            out[0] = @truncate(bitStream);
            out[1] = @truncate(bitStream >> 8);
            out += 2;
            bitStream >>= 16;
            bitCount -= 16;
        }
    }

    if (remaining != 1) return zstdError(.generic_err);
    std.debug.assert(symbol <= alphabetSize);

    if (!writeIsSafe and @intFromPtr(out) > @intFromPtr(oend) - 2)
        return zstdError(.dstSize_tooSmall);
    out[0] = @truncate(bitStream);
    out[1] = @truncate(bitStream >> 8);
    out += (bitCount + 7) / 8;

    return @intFromPtr(out) - @intFromPtr(ostart);
}

pub export fn FSE_writeNCount(
    buffer: ?*anyopaque,
    bufferSize: usize,
    normalizedCounter: [*]const i16,
    maxSymbolValue: c_uint,
    tableLog: c_uint,
) usize {
    if (tableLog > FSE_MAX_TABLELOG) return zstdError(.tableLog_tooLarge);
    if (tableLog < FSE_MIN_TABLELOG) return zstdError(.generic_err);
    const buf: [*]u8 = @ptrCast(buffer.?);
    const isSafe = bufferSize >= FSE_NCountWriteBound(maxSymbolValue, tableLog);
    return writeNCountGeneric(buf, bufferSize, normalizedCounter, maxSymbolValue, tableLog, isSafe);
}

// -------------------------------------------------------------------------
//  FSE_buildCTable_wksp — build encoding table from normalized distribution.
// -------------------------------------------------------------------------
pub export fn FSE_buildCTable_wksp(
    ct: [*]FSE_CTable,
    normalizedCounter: [*]const i16,
    maxSymbolValue: c_uint,
    tableLog: c_uint,
    workSpace: ?*anyopaque,
    wkspSize: usize,
) usize {
    const tableSize: u32 = @as(u32, 1) << @intCast(tableLog);
    const tableMask: u32 = tableSize - 1;
    // Layout of ct: [u16 tableLog, u16 maxSymbolValue, stateTable(tableSize u16s), FSE_symbolCompressionTransform[maxSV+1]]
    const ctBytes: [*]u8 = @ptrCast(ct);
    const tableU16: [*]u16 = @ptrCast(@alignCast(ctBytes + 2 * @sizeOf(u16)));
    const stateOffset: usize = if (tableLog != 0) (@as(usize, tableSize) >> 1) else 1;
    const fsct: [*]FSE_symbolCompressionTransform = @ptrCast(@alignCast(ctBytes + @sizeOf(u32) * (1 + stateOffset)));
    const symbolTT = fsct;
    const step: u32 = fseTableStep(tableSize);
    const maxSV1: u32 = maxSymbolValue + 1;

    const wsBytes: [*]u8 = @ptrCast(workSpace.?);
    // workspace: cumul[maxSV1+1] (u16), tableSymbol[tableSize+8] (u8)
    const cumul: [*]u16 = @ptrCast(@alignCast(wsBytes));
    const tableSymbol: [*]u8 = @ptrCast(wsBytes + (maxSV1 + 1) * @sizeOf(u16));

    var highThreshold: u32 = tableSize - 1;

    // Wksp size check — FSE_BUILD_CTABLE_WORKSPACE_SIZE bytes.
    const wkspBytesNeeded: usize =
        @sizeOf(u32) * (((@as(usize, maxSymbolValue) + 2) + tableSize) / 2 + @sizeOf(u64) / @sizeOf(u32));
    if (wkspBytesNeeded > wkspSize) return zstdError(.tableLog_tooLarge);

    // CTable header: tableU16[-2], tableU16[-1]
    const hdr: [*]u16 = @ptrCast(@alignCast(ctBytes));
    hdr[0] = @intCast(tableLog);
    hdr[1] = @intCast(maxSymbolValue);
    std.debug.assert(tableLog < 16);

    // Symbol cumulative start positions
    {
        cumul[0] = 0;
        var u: u32 = 1;
        while (u <= maxSV1) : (u += 1) {
            if (normalizedCounter[u - 1] == -1) {
                cumul[u] = cumul[u - 1] + 1;
                tableSymbol[highThreshold] = @intCast(u - 1);
                highThreshold -%= 1;
            } else {
                std.debug.assert(normalizedCounter[u - 1] >= 0);
                cumul[u] = cumul[u - 1] + @as(u16, @intCast(normalizedCounter[u - 1]));
                std.debug.assert(cumul[u] >= cumul[u - 1]);
            }
        }
        cumul[maxSV1] = @intCast(tableSize + 1);
    }

    // Spread symbols
    if (highThreshold == tableSize - 1) {
        // fast path — no low-prob symbols.
        // tableSymbol array is followed by +8 guard bytes (for u64 writes).
        {
            var pos: usize = 0;
            var s: u32 = 0;
            while (s < maxSV1) : (s += 1) {
                const n: i32 = normalizedCounter[s];
                if (n > 0) {
                    @memset(tableSymbol[pos .. pos + @as(usize, @intCast(n))], @intCast(s));
                    pos += @intCast(n);
                }
            }
        }
        {
            var position: usize = 0;
            const unroll: usize = 2;
            std.debug.assert(tableSize % unroll == 0);
            const spreadBuf = tableSymbol; // upstream re-aliases `spread = tableSymbol + tableSize`
            _ = spreadBuf;
            // Upstream first lays out to `spread` then scatters into tableSymbol.
            // We wrote into tableSymbol directly above, so we need to read back
            // from a copy: allocate a temp spread on the stack is unsafe for
            // tableSize up to 4096; instead recompute via cumul.
            //
            // Simplest equivalent: copy tableSymbol->spread then scatter.
            var spread_buf: [1 << 12]u8 = undefined;
            @memcpy(spread_buf[0..tableSize], tableSymbol[0..tableSize]);
            var s: usize = 0;
            while (s < tableSize) : (s += unroll) {
                var u: usize = 0;
                while (u < unroll) : (u += 1) {
                    const uPosition = (position + (u * step)) & tableMask;
                    tableSymbol[uPosition] = spread_buf[s + u];
                }
                position = (position + (unroll * step)) & tableMask;
            }
            std.debug.assert(position == 0);
        }
    } else {
        var position: u32 = 0;
        var symbol: u32 = 0;
        while (symbol < maxSV1) : (symbol += 1) {
            const freq: i32 = normalizedCounter[symbol];
            var occ: i32 = 0;
            while (occ < freq) : (occ += 1) {
                tableSymbol[position] = @intCast(symbol);
                position = (position + step) & tableMask;
                while (position > highThreshold) position = (position + step) & tableMask;
            }
        }
        std.debug.assert(position == 0);
    }

    // Build next-state table
    {
        var u: u32 = 0;
        while (u < tableSize) : (u += 1) {
            const s: u32 = tableSymbol[u];
            tableU16[cumul[s]] = @intCast(tableSize + u);
            cumul[s] += 1;
        }
    }

    // Build Symbol Transformation Table
    {
        var total: u32 = 0;
        var s: u32 = 0;
        while (s <= maxSymbolValue) : (s += 1) {
            const nc: i32 = normalizedCounter[s];
            if (nc == 0) {
                symbolTT[s].deltaNbBits = ((tableLog + 1) << 16) - (@as(u32, 1) << @intCast(tableLog));
            } else if (nc == -1 or nc == 1) {
                symbolTT[s].deltaNbBits = (tableLog << 16) - (@as(u32, 1) << @intCast(tableLog));
                symbolTT[s].deltaFindState = @intCast(@as(i64, total) - 1);
                total += 1;
            } else {
                std.debug.assert(nc > 1);
                const ncU: u32 = @intCast(nc);
                const maxBitsOut: u32 = tableLog - highbit32(ncU - 1);
                const minStatePlus: u32 = ncU << @intCast(maxBitsOut);
                symbolTT[s].deltaNbBits = (maxBitsOut << 16) -% minStatePlus;
                symbolTT[s].deltaFindState = @intCast(@as(i64, total) - @as(i64, ncU));
                total += ncU;
            }
        }
    }
    return 0;
}

// -------------------------------------------------------------------------
//  FSE_buildCTable_rle — single-symbol CTable
// -------------------------------------------------------------------------
pub export fn FSE_buildCTable_rle(ct: [*]FSE_CTable, symbolValue: u8) usize {
    const ctBytes: [*]u8 = @ptrCast(ct);
    const hdr: [*]u16 = @ptrCast(@alignCast(ctBytes));
    hdr[0] = 0;
    hdr[1] = symbolValue;
    // tableU16[0] = 0; tableU16[1] = 0 (skip the two header words)
    const tableU16: [*]u16 = @ptrCast(@alignCast(ctBytes + 2 * @sizeOf(u16)));
    tableU16[0] = 0;
    tableU16[1] = 0;
    // symbolTT starts after one u32 header word — upstream: `(U32*)ptr + 2`.
    const fsct: [*]FSE_symbolCompressionTransform = @ptrCast(@alignCast(ctBytes + 2 * @sizeOf(u32)));
    fsct[symbolValue].deltaNbBits = 0;
    fsct[symbolValue].deltaFindState = 0;
    return 0;
}

// -------------------------------------------------------------------------
//  FSE_normalizeCount / helpers
// -------------------------------------------------------------------------
fn fseMinTableLog(srcSize: usize, maxSymbolValue: u32) u32 {
    const minBitsSrc = highbit32(@intCast(srcSize)) + 1;
    const minBitsSymbols = highbit32(maxSymbolValue) + 2;
    return if (minBitsSrc < minBitsSymbols) minBitsSrc else minBitsSymbols;
}

pub export fn FSE_optimalTableLog_internal(
    maxTableLog: c_uint,
    srcSize: usize,
    maxSymbolValue: c_uint,
    minus: c_uint,
) c_uint {
    const maxBitsSrc: u32 = highbit32(@intCast(srcSize - 1)) - minus;
    var tableLog: u32 = maxTableLog;
    const minBits: u32 = fseMinTableLog(srcSize, maxSymbolValue);
    std.debug.assert(srcSize > 1);
    if (tableLog == 0) tableLog = FSE_DEFAULT_TABLELOG;
    if (maxBitsSrc < tableLog) tableLog = maxBitsSrc;
    if (minBits > tableLog) tableLog = minBits;
    if (tableLog < FSE_MIN_TABLELOG) tableLog = FSE_MIN_TABLELOG;
    if (tableLog > FSE_MAX_TABLELOG) tableLog = FSE_MAX_TABLELOG;
    return tableLog;
}

pub export fn FSE_optimalTableLog(
    maxTableLog: c_uint,
    srcSize: usize,
    maxSymbolValue: c_uint,
) c_uint {
    return FSE_optimalTableLog_internal(maxTableLog, srcSize, maxSymbolValue, 2);
}

// Secondary normalization method (upstream FSE_normalizeM2).
fn fseNormalizeM2(
    norm: [*]i16,
    tableLog: u32,
    count: [*]const u32,
    total_in: usize,
    maxSymbolValue: u32,
    lowProbCount: i16,
) usize {
    const NOT_YET_ASSIGNED: i16 = -2;
    var total = total_in;
    var distributed: u32 = 0;
    var toDistribute: u32 = 0;

    const lowThreshold: u32 = @intCast(total >> @intCast(tableLog));
    var lowOne: u32 = @intCast((total * 3) >> @intCast(tableLog + 1));

    {
        var s: u32 = 0;
        while (s <= maxSymbolValue) : (s += 1) {
            if (count[s] == 0) {
                norm[s] = 0;
                continue;
            }
            if (count[s] <= lowThreshold) {
                norm[s] = lowProbCount;
                distributed += 1;
                total -= count[s];
                continue;
            }
            if (count[s] <= lowOne) {
                norm[s] = 1;
                distributed += 1;
                total -= count[s];
                continue;
            }
            norm[s] = NOT_YET_ASSIGNED;
        }
    }
    toDistribute = (@as(u32, 1) << @intCast(tableLog)) - distributed;
    if (toDistribute == 0) return 0;

    if (total / toDistribute > lowOne) {
        lowOne = @intCast((total * 3) / (@as(usize, toDistribute) * 2));
        var s: u32 = 0;
        while (s <= maxSymbolValue) : (s += 1) {
            if (norm[s] == NOT_YET_ASSIGNED and count[s] <= lowOne) {
                norm[s] = 1;
                distributed += 1;
                total -= count[s];
            }
        }
        toDistribute = (@as(u32, 1) << @intCast(tableLog)) - distributed;
    }

    if (distributed == maxSymbolValue + 1) {
        var maxV: u32 = 0;
        var maxC: u32 = 0;
        var s: u32 = 0;
        while (s <= maxSymbolValue) : (s += 1) {
            if (count[s] > maxC) {
                maxV = s;
                maxC = count[s];
            }
        }
        norm[maxV] += @intCast(toDistribute);
        return 0;
    }

    if (total == 0) {
        var s: u32 = 0;
        while (toDistribute > 0) {
            if (norm[s] > 0) {
                toDistribute -= 1;
                norm[s] += 1;
            }
            s = (s + 1) % (maxSymbolValue + 1);
        }
        return 0;
    }

    {
        const vStepLog: u6 = @intCast(62 - tableLog);
        const mid: u64 = (@as(u64, 1) << (vStepLog - 1)) - 1;
        const rStep: u64 = ((@as(u64, 1) << vStepLog) * toDistribute + mid) / @as(u64, @intCast(total));
        var tmpTotal: u64 = mid;
        var s: u32 = 0;
        while (s <= maxSymbolValue) : (s += 1) {
            if (norm[s] == NOT_YET_ASSIGNED) {
                const end: u64 = tmpTotal + @as(u64, count[s]) * rStep;
                const sStart: u32 = @intCast(tmpTotal >> vStepLog);
                const sEnd: u32 = @intCast(end >> vStepLog);
                const weight: u32 = sEnd - sStart;
                if (weight < 1) return zstdError(.generic_err);
                norm[s] = @intCast(weight);
                tmpTotal = end;
            }
        }
    }
    return 0;
}

pub export fn FSE_normalizeCount(
    normalizedCounter: [*]i16,
    tableLog_in: c_uint,
    count: [*]const c_uint,
    total: usize,
    maxSymbolValue: c_uint,
    useLowProbCount: c_uint,
) usize {
    var tableLog = tableLog_in;
    if (tableLog == 0) tableLog = FSE_DEFAULT_TABLELOG;
    if (tableLog < FSE_MIN_TABLELOG) return zstdError(.generic_err);
    if (tableLog > FSE_MAX_TABLELOG) return zstdError(.tableLog_tooLarge);
    if (tableLog < fseMinTableLog(total, maxSymbolValue)) return zstdError(.generic_err);

    const rtbTable: [8]u32 = .{ 0, 473195, 504333, 520860, 550000, 700000, 750000, 830000 };
    const lowProbCount: i16 = if (useLowProbCount != 0) -1 else 1;
    const scale: u6 = @intCast(62 - tableLog);
    const step: u64 = (@as(u64, 1) << 62) / @as(u64, @intCast(total));
    const vStep: u64 = @as(u64, 1) << @intCast(scale - 20);
    var stillToDistribute: i32 = @as(i32, 1) << @intCast(tableLog);
    var largest: u32 = 0;
    var largestP: i16 = 0;
    const lowThreshold: u32 = @intCast(total >> @intCast(tableLog));

    var s: u32 = 0;
    while (s <= maxSymbolValue) : (s += 1) {
        if (count[s] == total) return 0; // rle special case
        if (count[s] == 0) {
            normalizedCounter[s] = 0;
            continue;
        }
        if (count[s] <= lowThreshold) {
            normalizedCounter[s] = lowProbCount;
            stillToDistribute -= 1;
        } else {
            var proba: i16 = @intCast((@as(u64, count[s]) * step) >> scale);
            if (proba < 8) {
                const restToBeat: u64 = vStep * rtbTable[@intCast(proba)];
                const lhs: u64 = @as(u64, count[s]) * step - (@as(u64, @intCast(proba)) << scale);
                if (lhs > restToBeat) proba += 1;
            }
            if (proba > largestP) {
                largestP = proba;
                largest = s;
            }
            normalizedCounter[s] = proba;
            stillToDistribute -= proba;
        }
    }

    if (-stillToDistribute >= @as(i32, normalizedCounter[largest] >> 1)) {
        const err = fseNormalizeM2(normalizedCounter, tableLog, count, total, maxSymbolValue, lowProbCount);
        if (common.ERR_isError(err) != 0) return err;
    } else {
        normalizedCounter[largest] += @intCast(stillToDistribute);
    }
    return tableLog;
}

// -------------------------------------------------------------------------
//  BIT_* encoder (inlined subset of bitstream.h needed by encode loop)
// -------------------------------------------------------------------------
pub const BIT_CStream_t = struct {
    bitContainer: u64,
    bitPos: u32,
    startPtr: [*]u8,
    ptr: [*]u8,
    endPtr: [*]u8,
};

pub fn bitInitCStream(bitC: *BIT_CStream_t, startPtr: [*]u8, dstCapacity: usize) usize {
    bitC.bitContainer = 0;
    bitC.bitPos = 0;
    bitC.startPtr = startPtr;
    bitC.ptr = startPtr;
    if (dstCapacity <= @sizeOf(u64)) return zstdError(.dstSize_tooSmall);
    bitC.endPtr = startPtr + dstCapacity - @sizeOf(u64);
    return 0;
}

pub inline fn bitAddBits(bitC: *BIT_CStream_t, value: u64, nbBits: u32) void {
    const mask: u64 = if (nbBits == 0) 0 else (@as(u64, 1) << @intCast(nbBits)) - 1;
    bitC.bitContainer |= (value & mask) << @intCast(bitC.bitPos);
    bitC.bitPos += nbBits;
}

pub inline fn bitAddBitsFast(bitC: *BIT_CStream_t, value: u64, nbBits: u32) void {
    bitC.bitContainer |= value << @intCast(bitC.bitPos);
    bitC.bitPos += nbBits;
}

pub inline fn bitFlushBitsFast(bitC: *BIT_CStream_t) void {
    const nbBytes = bitC.bitPos >> 3;
    std.mem.writeInt(u64, bitC.ptr[0..8], bitC.bitContainer, .little);
    bitC.ptr += nbBytes;
    bitC.bitPos &= 7;
    bitC.bitContainer >>= @intCast(nbBytes * 8);
}

pub inline fn bitFlushBits(bitC: *BIT_CStream_t) void {
    const nbBytes = bitC.bitPos >> 3;
    std.mem.writeInt(u64, bitC.ptr[0..8], bitC.bitContainer, .little);
    bitC.ptr += nbBytes;
    if (@intFromPtr(bitC.ptr) > @intFromPtr(bitC.endPtr)) bitC.ptr = bitC.endPtr;
    bitC.bitPos &= 7;
    bitC.bitContainer >>= @intCast(nbBytes * 8);
}

pub fn bitCloseCStream(bitC: *BIT_CStream_t) usize {
    bitAddBitsFast(bitC, 1, 1);
    bitFlushBits(bitC);
    if (@intFromPtr(bitC.ptr) >= @intFromPtr(bitC.endPtr)) return 0;
    const size = @intFromPtr(bitC.ptr) - @intFromPtr(bitC.startPtr);
    return size + @intFromBool(bitC.bitPos > 0);
}

// FSE encoder state
pub const FSE_CState_t = struct {
    value: i64,
    stateTable: [*]const u16,
    symbolTT: [*]const FSE_symbolCompressionTransform,
    stateLog: u32,
};

pub fn fseInitCState(s: *FSE_CState_t, ct: [*]const FSE_CTable) void {
    const ctBytes: [*]const u8 = @ptrCast(ct);
    const hdr: *const u16 = @ptrCast(@alignCast(ctBytes));
    const tl: u32 = hdr.*;
    s.value = @as(i64, 1) << @intCast(tl);
    s.stateTable = @ptrCast(@alignCast(ctBytes + 2 * @sizeOf(u16)));
    const stateOffset: usize = if (tl != 0) (@as(usize, 1) << @intCast(tl - 1)) else 1;
    s.symbolTT = @ptrCast(@alignCast(ctBytes + @sizeOf(u32) * (1 + stateOffset)));
    s.stateLog = tl;
}

pub fn fseInitCState2(s: *FSE_CState_t, ct: [*]const FSE_CTable, symbol: u32) void {
    fseInitCState(s, ct);
    const symbolTT = s.symbolTT[symbol];
    // Direct port of lib/common/fse.h FSE_initCState2.  Upstream C uses U32
    // throughout and relies on natural u32 wrap-around; keep it in u32 land.
    // @truncate(u5) on the shift count mirrors aarch64's hardware mod-32
    // behaviour for the boundary case where nbBitsOut hits 32.
    const nbBitsOut: u32 = (symbolTT.deltaNbBits +% (1 << 15)) >> 16;
    const valU: u32 = (nbBitsOut << 16) -% symbolTT.deltaNbBits;
    const shifted: u32 = valU >> @as(u5, @truncate(nbBitsOut));
    const u_idx: u32 = shifted +% @as(u32, @bitCast(symbolTT.deltaFindState));
    s.value = @as(i64, s.stateTable[u_idx]);
}

pub inline fn fseEncodeSymbol(bitC: *BIT_CStream_t, s: *FSE_CState_t, symbol: u32) void {
    const symbolTT = s.symbolTT[symbol];
    const nbBitsOut: u32 = @intCast((s.value + @as(i64, symbolTT.deltaNbBits)) >> 16);
    bitAddBits(bitC, @as(u64, @intCast(s.value)), nbBitsOut);
    const shifted: u32 = @intCast(s.value >> @as(u6, @truncate(nbBitsOut)));
    const u_idx: u32 = shifted +% @as(u32, @bitCast(symbolTT.deltaFindState));
    s.value = @as(i64, s.stateTable[u_idx]);
}

pub inline fn fseFlushCState(bitC: *BIT_CStream_t, s: *const FSE_CState_t) void {
    bitAddBits(bitC, @as(u64, @intCast(s.value)), s.stateLog);
    bitFlushBits(bitC);
}

/// FSE_bitCost — fixed-point symbol cost estimation (accuracyLog fractional bits).
/// Port of MEM_STATIC FSE_bitCost in lib/common/fse.h.
pub fn FSE_bitCost(symbolTTPtr: [*]const FSE_symbolCompressionTransform, tableLog: u32, symbolValue: u32, accuracyLog: u32) u32 {
    const sTT = symbolTTPtr[symbolValue];
    const minNbBits: u32 = sTT.deltaNbBits >> 16;
    const threshold: u32 = (minNbBits + 1) << 16;
    std.debug.assert(tableLog < 16);
    std.debug.assert(accuracyLog < 31 - tableLog);
    const tableSize: u32 = @as(u32, 1) << @intCast(tableLog);
    const deltaFromThreshold: u32 = threshold -% (sTT.deltaNbBits +% tableSize);
    const normalizedDeltaFromThreshold: u32 = (deltaFromThreshold << @intCast(accuracyLog)) >> @intCast(tableLog);
    const bitMultiplier: u32 = @as(u32, 1) << @intCast(accuracyLog);
    std.debug.assert(sTT.deltaNbBits + tableSize <= threshold);
    std.debug.assert(normalizedDeltaFromThreshold <= bitMultiplier);
    return (minNbBits + 1) * bitMultiplier - normalizedDeltaFromThreshold;
}

// -------------------------------------------------------------------------
//  FSE_compress_usingCTable_generic — encoder main loop
// -------------------------------------------------------------------------
fn fseCompressUsingCTableGeneric(
    dst: [*]u8,
    dstSize: usize,
    src: [*]const u8,
    srcSize_in: usize,
    ct: [*]const FSE_CTable,
    fast: bool,
) usize {
    const istart = src;
    const iend = src + srcSize_in;
    var ip = iend;
    var srcSize = srcSize_in;

    var bitC: BIT_CStream_t = undefined;
    var cs1: FSE_CState_t = undefined;
    var cs2: FSE_CState_t = undefined;

    if (srcSize <= 2) return 0;
    {
        const r = bitInitCStream(&bitC, dst, dstSize);
        if (common.ERR_isError(r) != 0) return 0;
    }

    if ((srcSize & 1) != 0) {
        ip -= 1;
        fseInitCState2(&cs1, ct, ip[0]);
        ip -= 1;
        fseInitCState2(&cs2, ct, ip[0]);
        ip -= 1;
        fseEncodeSymbol(&bitC, &cs1, ip[0]);
        if (fast) bitFlushBitsFast(&bitC) else bitFlushBits(&bitC);
    } else {
        ip -= 1;
        fseInitCState2(&cs2, ct, ip[0]);
        ip -= 1;
        fseInitCState2(&cs1, ct, ip[0]);
    }

    srcSize -= 2;
    // sizeof(container)=8 bytes = 64 bits. FSE_MAX_TABLELOG=12 → 12*4+7=55 < 64,
    // so the "join to mod 4" branch is live when srcSize & 2 != 0.
    if ((srcSize & 2) != 0) {
        ip -= 1;
        fseEncodeSymbol(&bitC, &cs2, ip[0]);
        ip -= 1;
        fseEncodeSymbol(&bitC, &cs1, ip[0]);
        if (fast) bitFlushBitsFast(&bitC) else bitFlushBits(&bitC);
    }

    while (@intFromPtr(ip) > @intFromPtr(istart)) {
        ip -= 1;
        fseEncodeSymbol(&bitC, &cs2, ip[0]);
        // 64-bit container makes the MAX_TABLELOG*2+7 reload branch static-false.
        ip -= 1;
        fseEncodeSymbol(&bitC, &cs1, ip[0]);
        // MAX_TABLELOG*4+7 branch is live for 64-bit:
        ip -= 1;
        fseEncodeSymbol(&bitC, &cs2, ip[0]);
        ip -= 1;
        fseEncodeSymbol(&bitC, &cs1, ip[0]);
        if (fast) bitFlushBitsFast(&bitC) else bitFlushBits(&bitC);
    }

    fseFlushCState(&bitC, &cs2);
    fseFlushCState(&bitC, &cs1);
    return bitCloseCStream(&bitC);
}

pub export fn FSE_compress_usingCTable(
    dst: ?*anyopaque,
    dstSize: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    ct: [*]const FSE_CTable,
) usize {
    const fast = dstSize >= fseBlockBound(srcSize);
    const d: [*]u8 = @ptrCast(dst.?);
    const s: [*]const u8 = @ptrCast(src.?);
    return fseCompressUsingCTableGeneric(d, dstSize, s, srcSize, ct, fast);
}

// -------------------------------------------------------------------------
//  Sanity / reference-vector tests
// -------------------------------------------------------------------------
test "optimalTableLog bounds" {
    const tl = FSE_optimalTableLog(0, 1024, 255);
    try std.testing.expect(tl >= FSE_MIN_TABLELOG);
    try std.testing.expect(tl <= FSE_MAX_TABLELOG);
}

test "compressBound vs NCountWriteBound" {
    try std.testing.expect(FSE_compressBound(100) > 100);
    try std.testing.expectEqual(@as(usize, FSE_NCOUNTBOUND), FSE_NCountWriteBound(0, 10));
}

test "normalizeCount rle shortcut returns 0" {
    var counts: [2]c_uint = .{ 100, 0 };
    var norm: [2]i16 = .{ 0, 0 };
    const r = FSE_normalizeCount(&norm, 0, &counts, 100, 1, 1);
    try std.testing.expectEqual(@as(usize, 0), r);
}

test "buildCTable_rle accepts single symbol" {
    var ct: [1 + 4 + 256 * 2]FSE_CTable = undefined; // oversized for safety
    const r = FSE_buildCTable_rle(&ct, 42);
    try std.testing.expectEqual(@as(usize, 0), r);
    const ctBytes: [*]const u8 = @ptrCast(&ct);
    const hdr: *const u16 = @ptrCast(@alignCast(ctBytes));
    try std.testing.expectEqual(@as(u16, 0), hdr.*);
    const hdr2: *const u16 = @ptrCast(@alignCast(ctBytes + 2));
    try std.testing.expectEqual(@as(u16, 42), hdr2.*);
}

test "writeNCount / readNCount round-trip" {
    // Build a small normalized distribution and verify it encodes, then
    // decodes back bit-exact via entropy_common.FSE_readNCount.
    var norm: [8]i16 = .{ 4, 4, 2, 2, 1, 1, 1, 1 }; // sum=16 = 2^4, tableLog=4 → must bump to FSE_MIN_TABLELOG=5
    // Re-normalize to tableLog=5 (sum=32) by doubling
    for (0..norm.len) |i| norm[i] *= 2;
    var buf: [64]u8 = undefined;
    const written = FSE_writeNCount(&buf, buf.len, &norm, 7, 5);
    try std.testing.expect(common.ERR_isError(written) == 0);
    try std.testing.expect(written > 0);

    var decoded: [8]i16 = [_]i16{0} ** 8;
    var maxSV: c_uint = 7;
    var tl: c_uint = 0;
    const read = ec.FSE_readNCount(&decoded, &maxSV, &tl, &buf, written);
    try std.testing.expect(common.ERR_isError(read) == 0);
    try std.testing.expectEqual(@as(c_uint, 5), tl);
    try std.testing.expectEqual(@as(c_uint, 7), maxSV);
    for (0..8) |i| try std.testing.expectEqual(norm[i], decoded[i]);
}
