// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/compress/huf_compress.c — Huffman table
// construction (slice 3a of 3). Slice 3b wires up the actual encoder loop
// (HUF_compress{1,4}X_usingCTable) + state plumbing; slice 3c adds the
// high-level HUF_compress_* entry points.
//
// Upstream:
//   Huffman encoder, part of New Generation Entropy library
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// Scope of this slice:
//   * Packed HUF_CElt accessors       (getNbBits / getValue / setNbBits / setValue)
//   * HUF_CTableHeader read/write
//   * Huffman table construction       (HUF_sort, HUF_buildTree, HUF_setMaxHeight,
//                                       HUF_buildCTableFromTree, HUF_buildCTable_wksp)
//   * Huffman table emission           (HUF_compressWeights, HUF_writeCTable_wksp,
//                                       HUF_writeCTable)
//   * Huffman table read-back          (HUF_readCTable, HUF_getNbBitsFromCTable)
//
// Public C-ABI entry points kept on `pub export fn`:
//   HUF_buildCTable_wksp, HUF_writeCTable_wksp, HUF_writeCTable,
//   HUF_readCTable, HUF_readCTableHeader, HUF_getNbBitsFromCTable,
//   HUF_estimateCompressedSize, HUF_validateCTable, HUF_compressBound.
//
// Layout reminder — a HUF_CElt[] holds:
//   CTable[0]     — HUF_CTableHeader (tableLog / maxSymbolValue)
//   CTable[1..]   — per-symbol packed (nbBits, value) pairs (see below)
// Packed CElt format (size_t on 64-bit targets):
//     bits [0,4)    = nbBits (0..12)
//     bits [4, 64-nbBits) = 0
//     bits [64-nbBits, 64) = value (big-endian at the top)

const std = @import("std");
const common = @import("zstd_common.zig");
const ec = @import("entropy_common.zig");
const fsec = @import("fse_compress.zig");
const hist = @import("hist.zig");

const zstdError = common.zstdError;

// -------------------------------------------------------------------------
//  Public constants mirrored from lib/common/huf.h
// -------------------------------------------------------------------------
pub const HUF_TABLELOG_MAX: c_uint = ec.HUF_TABLELOG_MAX; // 12
pub const HUF_TABLELOG_DEFAULT: c_uint = 11;
pub const HUF_TABLELOG_ABSOLUTEMAX: c_uint = ec.HUF_TABLELOG_ABSOLUTEMAX; // 12
pub const HUF_SYMBOLVALUE_MAX: c_uint = ec.HUF_SYMBOLVALUE_MAX; // 255

pub const HUF_BLOCKSIZE_MAX: usize = 128 * 1024;
pub const HUF_CTABLEBOUND: usize = 129;
pub inline fn HUF_BLOCKBOUND(size: usize) usize {
    return size + (size >> 8) + 8;
}
pub inline fn HUF_COMPRESSBOUND(size: usize) usize {
    return HUF_CTABLEBOUND + HUF_BLOCKBOUND(size);
}

// HUF_CTable workspace = huffNodeTable[2 * 256] (4096 B) + rankPosition[192] (768 B)
pub const HUF_CTABLE_WORKSPACE_SIZE_U32: usize = (4 * (HUF_SYMBOLVALUE_MAX + 1)) + 192;
pub const HUF_CTABLE_WORKSPACE_SIZE: usize = HUF_CTABLE_WORKSPACE_SIZE_U32 * @sizeOf(c_uint);

/// HUF_CElt is `typedef size_t HUF_CElt` upstream; we're 64-bit only in this
/// port (matching the BitContainerType assumption in fse_compress.zig).
pub const HUF_CElt = u64;

/// HUF_CTableHeader — stored at CTable[0]. Upstream:
///     BYTE tableLog;
///     BYTE maxSymbolValue;
///     BYTE unused[sizeof(size_t) - 2];
pub const HUF_CTableHeader = extern struct {
    tableLog: u8,
    maxSymbolValue: u8,
    unused: [@sizeOf(HUF_CElt) - 2]u8 = [_]u8{0} ** (@sizeOf(HUF_CElt) - 2),
};

comptime {
    std.debug.assert(@sizeOf(HUF_CTableHeader) == @sizeOf(HUF_CElt));
}

const HUF_BITS_IN_CONTAINER: u32 = @sizeOf(HUF_CElt) * 8; // 64

// -------------------------------------------------------------------------
//  Packed CElt accessors — port of static inline helpers at the top of
//  upstream huf_compress.c.
// -------------------------------------------------------------------------
pub inline fn HUF_getNbBits(elt: HUF_CElt) usize {
    return elt & 0xFF;
}

inline fn HUF_getNbBitsFast(elt: HUF_CElt) usize {
    return elt;
}

inline fn HUF_getValue(elt: HUF_CElt) HUF_CElt {
    return elt & ~@as(HUF_CElt, 0xFF);
}

inline fn HUF_getValueFast(elt: HUF_CElt) HUF_CElt {
    return elt;
}

inline fn HUF_setNbBits(elt: *HUF_CElt, nbBits: usize) void {
    std.debug.assert(nbBits <= HUF_TABLELOG_ABSOLUTEMAX);
    elt.* = @intCast(nbBits);
}

inline fn HUF_setValue(elt: *HUF_CElt, value: u64) void {
    const nbBits: u64 = HUF_getNbBits(elt.*);
    if (nbBits > 0) {
        std.debug.assert((value >> @intCast(nbBits)) == 0);
        elt.* |= value << @intCast(HUF_BITS_IN_CONTAINER - nbBits);
    }
}

// -------------------------------------------------------------------------
//  HUF_CTableHeader read / write
// -------------------------------------------------------------------------
pub export fn HUF_readCTableHeader(ctable: [*]const HUF_CElt) HUF_CTableHeader {
    var header: HUF_CTableHeader = undefined;
    const dst: [*]u8 = @ptrCast(&header);
    const src: [*]const u8 = @ptrCast(ctable);
    @memcpy(dst[0..@sizeOf(HUF_CTableHeader)], src[0..@sizeOf(HUF_CTableHeader)]);
    return header;
}

fn HUF_writeCTableHeader(ctable: [*]HUF_CElt, tableLog: u32, maxSymbolValue: u32) void {
    std.debug.assert(tableLog < 256);
    std.debug.assert(maxSymbolValue < 256);
    var header: HUF_CTableHeader = .{
        .tableLog = @intCast(tableLog),
        .maxSymbolValue = @intCast(maxSymbolValue),
    };
    const dst: [*]u8 = @ptrCast(ctable);
    const src: [*]const u8 = @ptrCast(&header);
    @memcpy(dst[0..@sizeOf(HUF_CTableHeader)], src[0..@sizeOf(HUF_CTableHeader)]);
}

// -------------------------------------------------------------------------
//  HUF_alignUpWorkspace — advance a workspace pointer to the next u32
//  alignment, shrinking remaining size. Returns null when not enough room.
// -------------------------------------------------------------------------
fn hufAlignUpWorkspace(workspace: ?*anyopaque, workspaceSizePtr: *usize, alignment: usize) ?[*]u8 {
    std.debug.assert((alignment & (alignment - 1)) == 0);
    std.debug.assert(alignment <= 8);
    const mask = alignment - 1;
    const addr: usize = @intFromPtr(workspace);
    const rem = addr & mask;
    const add: usize = (alignment - rem) & mask;
    if (workspaceSizePtr.* >= add) {
        workspaceSizePtr.* -= add;
        const aligned: [*]u8 = @ptrFromInt(addr + add);
        return aligned;
    } else {
        workspaceSizePtr.* = 0;
        return null;
    }
}

// -------------------------------------------------------------------------
//  HUF_compressWeights — FSE-compress the weight stream that precedes the
//  main Huffman bitstream. Uses a private FSE CTable parameterised for the
//  small alphabet (0..HUF_TABLELOG_MAX).
// -------------------------------------------------------------------------
const MAX_FSE_TABLELOG_FOR_HUFF_HEADER: u32 = 6;

const HUF_CompressWeightsWksp = extern struct {
    // FSE_CTABLE_SIZE_U32(6, 12) = 1 + (1<<5) + (12+1)*2 = 59
    CTable: [59]fsec.FSE_CTable align(@alignOf(u64)),
    // FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32(12, 6) = ((12+2) + (1<<6))/2 + 2 = 41
    scratchBuffer: [41]u32,
    count: [HUF_TABLELOG_MAX + 1]c_uint,
    norm: [HUF_TABLELOG_MAX + 1]i16,
};

fn HUF_compressWeights(
    dst: [*]u8,
    dstSize: usize,
    weightTable: [*]const u8,
    wtSize: usize,
    workspace: ?*anyopaque,
    workspaceSize_in: usize,
) usize {
    var workspaceSize = workspaceSize_in;
    const wkspBytes = hufAlignUpWorkspace(workspace, &workspaceSize, @alignOf(u32)) orelse
        return zstdError(.generic_err);
    if (workspaceSize < @sizeOf(HUF_CompressWeightsWksp)) return zstdError(.generic_err);
    const wksp: *HUF_CompressWeightsWksp = @ptrCast(@alignCast(wkspBytes));

    if (wtSize <= 1) return 0; // not compressible

    const ostart = dst;
    var op = dst;
    const oend = dst + dstSize;

    var maxSymbolValue: c_uint = HUF_TABLELOG_MAX;
    var tableLog: u32 = MAX_FSE_TABLELOG_FOR_HUFF_HEADER;

    {
        const maxCount = hist.HIST_count_simple(&wksp.count, &maxSymbolValue, weightTable, wtSize);
        if (maxCount == wtSize) return 1; // rle
        if (maxCount == 1) return 0; // not compressible
    }

    tableLog = fsec.FSE_optimalTableLog(tableLog, wtSize, maxSymbolValue);
    {
        const r = fsec.FSE_normalizeCount(&wksp.norm, tableLog, &wksp.count, wtSize, maxSymbolValue, 0);
        if (common.ERR_isError(r) != 0) return r;
    }

    // write table description header
    {
        const hSize = fsec.FSE_writeNCount(op, @intFromPtr(oend) - @intFromPtr(op), &wksp.norm, maxSymbolValue, tableLog);
        if (common.ERR_isError(hSize) != 0) return hSize;
        op += hSize;
    }

    // build CTable + compress
    {
        const r = fsec.FSE_buildCTable_wksp(
            &wksp.CTable,
            &wksp.norm,
            maxSymbolValue,
            tableLog,
            &wksp.scratchBuffer,
            @sizeOf(@TypeOf(wksp.scratchBuffer)),
        );
        if (common.ERR_isError(r) != 0) return r;
    }
    {
        const cSize = fsec.FSE_compress_usingCTable(op, @intFromPtr(oend) - @intFromPtr(op), weightTable, wtSize, &wksp.CTable);
        if (common.ERR_isError(cSize) != 0) return cSize;
        if (cSize == 0) return 0;
        op += cSize;
    }
    return @intFromPtr(op) - @intFromPtr(ostart);
}

// -------------------------------------------------------------------------
//  HUF_writeCTable_wksp / HUF_writeCTable
// -------------------------------------------------------------------------
const HUF_WriteCTableWksp = extern struct {
    wksp: HUF_CompressWeightsWksp,
    bitsToWeight: [HUF_TABLELOG_MAX + 1]u8,
    huffWeight: [HUF_SYMBOLVALUE_MAX]u8,
};

pub export fn HUF_writeCTable_wksp(
    dst: ?*anyopaque,
    maxDstSize: usize,
    ctable_in: [*]const HUF_CElt,
    maxSymbolValue: c_uint,
    huffLog: c_uint,
    workspace: ?*anyopaque,
    workspaceSize_in: usize,
) usize {
    var workspaceSize = workspaceSize_in;
    const wkspBytes = hufAlignUpWorkspace(workspace, &workspaceSize, @alignOf(u32)) orelse
        return zstdError(.generic_err);
    if (workspaceSize < @sizeOf(HUF_WriteCTableWksp)) return zstdError(.generic_err);
    const wksp: *HUF_WriteCTableWksp = @ptrCast(@alignCast(wkspBytes));
    if (maxSymbolValue > HUF_SYMBOLVALUE_MAX) return zstdError(.maxSymbolValue_tooLarge);
    if (maxDstSize < 1) return zstdError(.dstSize_tooSmall);

    const hdr = HUF_readCTableHeader(ctable_in);
    std.debug.assert(hdr.maxSymbolValue == maxSymbolValue);
    std.debug.assert(hdr.tableLog == huffLog);

    const ct: [*]const HUF_CElt = ctable_in + 1;
    const op: [*]u8 = @ptrCast(dst.?);

    // convert to weight
    wksp.bitsToWeight[0] = 0;
    {
        var n: u32 = 1;
        while (n < huffLog + 1) : (n += 1) {
            wksp.bitsToWeight[n] = @intCast(huffLog + 1 - n);
        }
    }
    {
        var n: u32 = 0;
        while (n < maxSymbolValue) : (n += 1) {
            wksp.huffWeight[n] = wksp.bitsToWeight[HUF_getNbBits(ct[n])];
        }
    }

    // attempt FSE compression of weights
    {
        const hSize = HUF_compressWeights(op + 1, maxDstSize - 1, &wksp.huffWeight, maxSymbolValue, &wksp.wksp, @sizeOf(@TypeOf(wksp.wksp)));
        if (common.ERR_isError(hSize) != 0) return hSize;
        if ((hSize > 1) and (hSize < maxSymbolValue / 2)) {
            op[0] = @intCast(hSize);
            return hSize + 1;
        }
    }

    // raw 4-bits-per-weight fallback
    if (maxSymbolValue > (256 - 128)) return zstdError(.generic_err);
    if (((maxSymbolValue + 1) / 2) + 1 > maxDstSize) return zstdError(.dstSize_tooSmall);
    op[0] = @intCast(128 + (maxSymbolValue - 1));
    wksp.huffWeight[maxSymbolValue] = 0; // msan guard
    {
        var n: u32 = 0;
        while (n < maxSymbolValue) : (n += 2) {
            op[(n / 2) + 1] = (wksp.huffWeight[n] << 4) + wksp.huffWeight[n + 1];
        }
    }
    return ((maxSymbolValue + 1) / 2) + 1;
}

pub export fn HUF_writeCTable(
    dst: ?*anyopaque,
    maxDstSize: usize,
    ctable_in: [*]const HUF_CElt,
    maxSymbolValue: c_uint,
    huffLog: c_uint,
) usize {
    var wksp: HUF_WriteCTableWksp = undefined;
    return HUF_writeCTable_wksp(dst, maxDstSize, ctable_in, maxSymbolValue, huffLog, &wksp, @sizeOf(@TypeOf(wksp)));
}

// -------------------------------------------------------------------------
//  HUF_readCTable — decode a serialized Huffman table back into a CTable.
// -------------------------------------------------------------------------
pub export fn HUF_readCTable(
    ctable_out: [*]HUF_CElt,
    maxSymbolValuePtr: *c_uint,
    src: ?*const anyopaque,
    srcSize: usize,
    hasZeroWeights: *c_uint,
) usize {
    var huffWeight: [HUF_SYMBOLVALUE_MAX + 1]u8 = undefined;
    var rankVal: [HUF_TABLELOG_ABSOLUTEMAX + 1]u32 = [_]u32{0} ** (HUF_TABLELOG_ABSOLUTEMAX + 1);
    var tableLog: u32 = 0;
    var nbSymbols: u32 = 0;
    const ct: [*]HUF_CElt = ctable_out + 1;

    const readSize = ec.HUF_readStats(&huffWeight, huffWeight.len, &rankVal, &nbSymbols, &tableLog, src, srcSize);
    if (common.ERR_isError(readSize) != 0) return readSize;
    hasZeroWeights.* = @intFromBool(rankVal[0] > 0);
    if (tableLog > HUF_TABLELOG_MAX) return zstdError(.tableLog_tooLarge);
    if (nbSymbols > maxSymbolValuePtr.* + 1) return zstdError(.maxSymbolValue_tooSmall);

    maxSymbolValuePtr.* = nbSymbols - 1;
    HUF_writeCTableHeader(ctable_out, tableLog, maxSymbolValuePtr.*);

    // base value per rank
    {
        var nextRankStart: u32 = 0;
        var n: u32 = 1;
        while (n <= tableLog) : (n += 1) {
            const curr = nextRankStart;
            nextRankStart += rankVal[n] << @intCast(n - 1);
            rankVal[n] = curr;
        }
    }

    // fill nbBits
    {
        var n: u32 = 0;
        while (n < nbSymbols) : (n += 1) {
            const w: u32 = huffWeight[n];
            // (tableLog + 1 - w) & -(w != 0) — zero weights keep nbBits=0
            const bits: u32 = if (w != 0) (tableLog + 1 - w) else 0;
            HUF_setNbBits(&ct[n], bits);
        }
    }

    // fill val
    {
        var nbPerRank: [HUF_TABLELOG_MAX + 2]u16 = [_]u16{0} ** (HUF_TABLELOG_MAX + 2);
        var valPerRank: [HUF_TABLELOG_MAX + 2]u16 = [_]u16{0} ** (HUF_TABLELOG_MAX + 2);
        {
            var n: u32 = 0;
            while (n < nbSymbols) : (n += 1) {
                const nb = HUF_getNbBits(ct[n]);
                nbPerRank[nb] += 1;
            }
        }
        // determine starting value per rank
        valPerRank[tableLog + 1] = 0;
        {
            var min: u16 = 0;
            var n: u32 = tableLog;
            while (n > 0) : (n -= 1) {
                valPerRank[n] = min;
                min += nbPerRank[n];
                min >>= 1;
            }
        }
        // assign value within rank, symbol order
        {
            var n: u32 = 0;
            while (n < nbSymbols) : (n += 1) {
                const nb = HUF_getNbBits(ct[n]);
                HUF_setValue(&ct[n], valPerRank[nb]);
                valPerRank[nb] += 1;
            }
        }
    }
    return readSize;
}

pub export fn HUF_getNbBitsFromCTable(ctable_in: [*]const HUF_CElt, symbolValue: u32) u32 {
    const ct: [*]const HUF_CElt = ctable_in + 1;
    std.debug.assert(symbolValue <= HUF_SYMBOLVALUE_MAX);
    const hdr = HUF_readCTableHeader(ctable_in);
    if (symbolValue > hdr.maxSymbolValue) return 0;
    return @intCast(HUF_getNbBits(ct[symbolValue]));
}

// -------------------------------------------------------------------------
//  nodeElt + HUF_sort — bucket sort symbols by descending count.
// -------------------------------------------------------------------------
const nodeElt = extern struct {
    count: u32,
    parent: u16,
    byte: u8,
    nbBits: u8,
};

const rankPos = extern struct {
    base: u16,
    curr: u16,
};

const HUF_SYMBOLVALUE_MAX_P1: usize = HUF_SYMBOLVALUE_MAX + 1;
const huffNodeTable = [2 * HUF_SYMBOLVALUE_MAX_P1]nodeElt;

const RANK_POSITION_TABLE_SIZE: usize = 192;
const RANK_POSITION_MAX_COUNT_LOG: usize = 32;
const RANK_POSITION_LOG_BUCKETS_BEGIN: usize = (RANK_POSITION_TABLE_SIZE - 1) - RANK_POSITION_MAX_COUNT_LOG - 1;
const RANK_POSITION_DISTINCT_COUNT_CUTOFF: usize = RANK_POSITION_LOG_BUCKETS_BEGIN + highbit32u(@intCast(RANK_POSITION_LOG_BUCKETS_BEGIN));

inline fn highbit32u(v: u32) u32 {
    std.debug.assert(v != 0);
    return 31 - @clz(v);
}

fn hufGetIndex(count: u32) u32 {
    if (count < RANK_POSITION_DISTINCT_COUNT_CUTOFF) return count;
    return highbit32u(count) + @as(u32, @intCast(RANK_POSITION_LOG_BUCKETS_BEGIN));
}

fn hufSwapNodes(a: *nodeElt, b: *nodeElt) void {
    const tmp = a.*;
    a.* = b.*;
    b.* = tmp;
}

fn hufInsertionSort(arr_in: [*]nodeElt, low: i32, high: i32) void {
    const size: i32 = high - low + 1;
    const arr = arr_in + @as(usize, @intCast(low));
    var i: i32 = 1;
    while (i < size) : (i += 1) {
        const key = arr[@intCast(i)];
        var j: i32 = i - 1;
        while (j >= 0 and arr[@intCast(j)].count < key.count) : (j -= 1) {
            arr[@intCast(j + 1)] = arr[@intCast(j)];
        }
        arr[@intCast(j + 1)] = key;
    }
}

fn hufQuickSortPartition(arr: [*]nodeElt, low: i32, high: i32) i32 {
    const pivot = arr[@intCast(high)].count;
    var i: i32 = low - 1;
    var j: i32 = low;
    while (j < high) : (j += 1) {
        if (arr[@intCast(j)].count > pivot) {
            i += 1;
            hufSwapNodes(&arr[@intCast(i)], &arr[@intCast(j)]);
        }
    }
    hufSwapNodes(&arr[@intCast(i + 1)], &arr[@intCast(high)]);
    return i + 1;
}

fn hufSimpleQuickSort(arr: [*]nodeElt, low_in: i32, high_in: i32) void {
    const kInsertionSortThreshold: i32 = 8;
    var low = low_in;
    var high = high_in;
    if (high - low < kInsertionSortThreshold) {
        hufInsertionSort(arr, low, high);
        return;
    }
    while (low < high) {
        const idx = hufQuickSortPartition(arr, low, high);
        if (idx - low < high - idx) {
            hufSimpleQuickSort(arr, low, idx - 1);
            low = idx + 1;
        } else {
            hufSimpleQuickSort(arr, idx + 1, high);
            high = idx - 1;
        }
    }
}

fn hufSort(huffNode: [*]nodeElt, count: [*]const c_uint, maxSymbolValue: u32, rankPosition: [*]rankPos) void {
    const maxSymbolValue1: u32 = maxSymbolValue + 1;
    @memset(rankPosition[0..RANK_POSITION_TABLE_SIZE], .{ .base = 0, .curr = 0 });

    {
        var n: u32 = 0;
        while (n < maxSymbolValue1) : (n += 1) {
            const lowerRank = hufGetIndex(count[n]);
            std.debug.assert(lowerRank < RANK_POSITION_TABLE_SIZE - 1);
            rankPosition[lowerRank].base += 1;
        }
    }
    // rankPosition[N-1].base == 0 (initialised by memset)
    {
        var n: usize = RANK_POSITION_TABLE_SIZE - 1;
        while (n > 0) : (n -= 1) {
            rankPosition[n - 1].base += rankPosition[n].base;
            rankPosition[n - 1].curr = rankPosition[n - 1].base;
        }
    }
    // insert each symbol into the bucket
    {
        var n: u32 = 0;
        while (n < maxSymbolValue1) : (n += 1) {
            const c = count[n];
            const r = hufGetIndex(c) + 1;
            const pos = rankPosition[r].curr;
            rankPosition[r].curr = pos + 1;
            std.debug.assert(pos < maxSymbolValue1);
            huffNode[pos].count = c;
            huffNode[pos].byte = @intCast(n);
        }
    }
    // sort each "log" bucket; distinct-count buckets are already trivially sorted
    {
        var n: usize = RANK_POSITION_DISTINCT_COUNT_CUTOFF;
        while (n < RANK_POSITION_TABLE_SIZE - 1) : (n += 1) {
            const bucketSize: i32 = @as(i32, rankPosition[n].curr) - @as(i32, rankPosition[n].base);
            const bucketStartIdx = rankPosition[n].base;
            if (bucketSize > 1) {
                hufSimpleQuickSort(huffNode + bucketStartIdx, 0, bucketSize - 1);
            }
        }
    }
}

// -------------------------------------------------------------------------
//  HUF_buildTree — raw (unlimited-depth) Huffman tree from sorted counts.
// -------------------------------------------------------------------------
const STARTNODE: i32 = @intCast(HUF_SYMBOLVALUE_MAX + 1);

fn hufBuildTree(huffNode: [*]nodeElt, maxSymbolValue: u32) i32 {
    // huffNode is huffNode0 + 1 — huffNode0 is the sentinel at [-1].
    const huffNode0 = huffNode - 1;

    // init leaves' counts were filled by HUF_sort.
    var nonNullRank: i32 = @intCast(maxSymbolValue);
    while (huffNode[@intCast(nonNullRank)].count == 0) nonNullRank -= 1;

    var lowS: i32 = nonNullRank;
    const nodeRoot: i32 = STARTNODE + lowS - 1;
    var lowN: i32 = STARTNODE;
    var nodeNb: i32 = STARTNODE;

    huffNode[@intCast(nodeNb)].count =
        huffNode[@intCast(lowS)].count + huffNode[@intCast(lowS - 1)].count;
    huffNode[@intCast(lowS)].parent = @intCast(nodeNb);
    huffNode[@intCast(lowS - 1)].parent = @intCast(nodeNb);
    nodeNb += 1;
    lowS -= 2;

    {
        var n: i32 = nodeNb;
        while (n <= nodeRoot) : (n += 1) huffNode[@intCast(n)].count = @as(u32, 1) << 30;
    }
    // strong barrier at sentinel
    huffNode0[0].count = @as(u32, 1) << 31;

    // create parents.
    //
    // Upstream HUF_buildTree (zstd/huf_compress.c:700) relies on `lowS`
    // walking past 0 into the sentinel at `huffNode[-1]` (== huffNode0[0])
    // when symbols run out: the sentinel's count of 1<<31 is bigger than
    // any real count, so the lowS branch stops being taken and lowN takes
    // over for the rest of the tree. Expressed in Zig, indexing via
    // `huffNode[@intCast(lowS)]` panics the moment lowS becomes -1 (it's
    // a runtime-checked unsigned cast). Read via huffNode0[lowS + 1]
    // instead — that way lowS=-1 is the sentinel slot by construction,
    // no cast is needed, and the semantics stay identical to upstream.
    //
    // This path is hit when the symbol distribution is sparse enough that
    // the tree can't be balanced without the sentinel — e.g. TPACK
    // frames from afsrv_terminal, which previously crashed the ZC/ZZ
    // matrix cells.
    while (nodeNb <= nodeRoot) {
        const lowS_count = huffNode0[@intCast(lowS + 1)].count;
        const lowN_count = huffNode[@intCast(lowN)].count;
        const n1: i32 = if (lowS_count < lowN_count) blk: {
            const r = lowS;
            lowS -= 1;
            break :blk r;
        } else blk: {
            const r = lowN;
            lowN += 1;
            break :blk r;
        };
        const lowS_count2 = huffNode0[@intCast(lowS + 1)].count;
        const lowN_count2 = huffNode[@intCast(lowN)].count;
        const n2: i32 = if (lowS_count2 < lowN_count2) blk: {
            const r = lowS;
            lowS -= 1;
            break :blk r;
        } else blk: {
            const r = lowN;
            lowN += 1;
            break :blk r;
        };
        // n1 / n2 reference real tree nodes (not the sentinel) because
        // lowN starts at STARTNODE (>=0) and each iteration allocates a
        // parent at nodeNb (also >=0). Use huffNode0 here too so
        // n1 == -1 → huffNode0[0] works transparently in the rare case
        // where the tree degenerates into a single lowS-exhausted path.
        huffNode[@intCast(nodeNb)].count =
            huffNode0[@intCast(n1 + 1)].count + huffNode0[@intCast(n2 + 1)].count;
        huffNode0[@intCast(n1 + 1)].parent = @intCast(nodeNb);
        huffNode0[@intCast(n2 + 1)].parent = @intCast(nodeNb);
        nodeNb += 1;
    }

    // distribute weights
    huffNode[@intCast(nodeRoot)].nbBits = 0;
    {
        var n: i32 = nodeRoot - 1;
        while (n >= STARTNODE) : (n -= 1) {
            const p = huffNode[@intCast(n)].parent;
            huffNode[@intCast(n)].nbBits = huffNode[p].nbBits + 1;
        }
    }
    {
        var n: i32 = 0;
        while (n <= nonNullRank) : (n += 1) {
            const p = huffNode[@intCast(n)].parent;
            huffNode[@intCast(n)].nbBits = huffNode[p].nbBits + 1;
        }
    }
    return nonNullRank;
}

// -------------------------------------------------------------------------
//  HUF_setMaxHeight — clip the Huffman tree to targetNbBits, re-balancing.
// -------------------------------------------------------------------------
const NO_SYMBOL: u32 = 0xF0F0F0F0;

fn hufSetMaxHeight(huffNode: [*]nodeElt, lastNonNull: u32, targetNbBits_in: u32) u32 {
    const largestBits: u32 = huffNode[lastNonNull].nbBits;
    if (largestBits <= targetNbBits_in) return largestBits;
    const targetNbBits = targetNbBits_in;

    var totalCost: i32 = 0;
    const baseCost: u32 = @as(u32, 1) << @intCast(largestBits - targetNbBits);
    var n: i32 = @intCast(lastNonNull);

    while (huffNode[@intCast(n)].nbBits > targetNbBits) {
        totalCost += @intCast(baseCost - (@as(u32, 1) << @intCast(largestBits - huffNode[@intCast(n)].nbBits)));
        huffNode[@intCast(n)].nbBits = @intCast(targetNbBits);
        n -= 1;
    }
    std.debug.assert(huffNode[@intCast(n)].nbBits <= targetNbBits);
    while (huffNode[@intCast(n)].nbBits == targetNbBits) n -= 1;

    std.debug.assert((@as(u32, @intCast(totalCost)) & (baseCost - 1)) == 0);
    totalCost >>= @intCast(largestBits - targetNbBits);
    std.debug.assert(totalCost > 0);

    var rankLast: [HUF_TABLELOG_MAX + 2]u32 = [_]u32{NO_SYMBOL} ** (HUF_TABLELOG_MAX + 2);

    {
        var currentNbBits: u32 = targetNbBits;
        var pos: i32 = n;
        while (pos >= 0) : (pos -= 1) {
            if (huffNode[@intCast(pos)].nbBits >= currentNbBits) continue;
            currentNbBits = huffNode[@intCast(pos)].nbBits;
            rankLast[targetNbBits - currentNbBits] = @intCast(pos);
        }
    }

    while (totalCost > 0) {
        var nBitsToDecrease: u32 = highbit32u(@intCast(totalCost)) + 1;
        while (nBitsToDecrease > 1) : (nBitsToDecrease -= 1) {
            const highPos = rankLast[nBitsToDecrease];
            const lowPos = rankLast[nBitsToDecrease - 1];
            if (highPos == NO_SYMBOL) continue;
            if (lowPos == NO_SYMBOL) break;
            const highTotal = huffNode[highPos].count;
            const lowTotal: u32 = 2 * huffNode[lowPos].count;
            if (highTotal <= lowTotal) break;
        }
        std.debug.assert(rankLast[nBitsToDecrease] != NO_SYMBOL or nBitsToDecrease == 1);
        while ((nBitsToDecrease <= HUF_TABLELOG_MAX) and (rankLast[nBitsToDecrease] == NO_SYMBOL))
            nBitsToDecrease += 1;
        std.debug.assert(rankLast[nBitsToDecrease] != NO_SYMBOL);

        totalCost -= @as(i32, 1) << @intCast(nBitsToDecrease - 1);
        huffNode[rankLast[nBitsToDecrease]].nbBits += 1;

        if (rankLast[nBitsToDecrease - 1] == NO_SYMBOL)
            rankLast[nBitsToDecrease - 1] = rankLast[nBitsToDecrease];
        if (rankLast[nBitsToDecrease] == 0) {
            rankLast[nBitsToDecrease] = NO_SYMBOL;
        } else {
            rankLast[nBitsToDecrease] -= 1;
            if (huffNode[rankLast[nBitsToDecrease]].nbBits != targetNbBits - nBitsToDecrease)
                rankLast[nBitsToDecrease] = NO_SYMBOL;
        }
    }

    while (totalCost < 0) {
        if (rankLast[1] == NO_SYMBOL) {
            while (huffNode[@intCast(n)].nbBits == targetNbBits) n -= 1;
            huffNode[@intCast(n + 1)].nbBits -= 1;
            std.debug.assert(n >= 0);
            rankLast[1] = @intCast(n + 1);
            totalCost += 1;
            continue;
        }
        huffNode[rankLast[1] + 1].nbBits -= 1;
        rankLast[1] += 1;
        totalCost += 1;
    }
    return targetNbBits;
}

// -------------------------------------------------------------------------
//  HUF_buildCTableFromTree — emit (value, nbBits) pairs per symbol.
// -------------------------------------------------------------------------
fn hufBuildCTableFromTree(
    ctable: [*]HUF_CElt,
    huffNode: [*]const nodeElt,
    nonNullRank: i32,
    maxSymbolValue: u32,
    maxNbBits: u32,
) void {
    const ct: [*]HUF_CElt = ctable + 1;
    var nbPerRank: [HUF_TABLELOG_MAX + 1]u16 = [_]u16{0} ** (HUF_TABLELOG_MAX + 1);
    var valPerRank: [HUF_TABLELOG_MAX + 1]u16 = [_]u16{0} ** (HUF_TABLELOG_MAX + 1);
    const alphabetSize: u32 = maxSymbolValue + 1;

    {
        var i: i32 = 0;
        while (i <= nonNullRank) : (i += 1) nbPerRank[huffNode[@intCast(i)].nbBits] += 1;
    }
    // starting value per rank
    {
        var min: u16 = 0;
        var i: i32 = @intCast(maxNbBits);
        while (i > 0) : (i -= 1) {
            valPerRank[@intCast(i)] = min;
            min += nbPerRank[@intCast(i)];
            min >>= 1;
        }
    }
    // First zero all entries [0..alphabetSize) to ensure symbols that received
    // no count get a well-defined (nbBits=0, value=0) encoding.
    {
        var i: u32 = 0;
        while (i < alphabetSize) : (i += 1) ct[i] = 0;
    }
    // push nbBits per symbol (in symbol order, via huffNode[n].byte permutation)
    {
        var i: i32 = 0;
        while (i < @as(i32, @intCast(alphabetSize))) : (i += 1) {
            HUF_setNbBits(&ct[huffNode[@intCast(i)].byte], huffNode[@intCast(i)].nbBits);
        }
    }
    // assign value within rank, symbol order
    {
        var i: u32 = 0;
        while (i < alphabetSize) : (i += 1) {
            const nb = HUF_getNbBits(ct[i]);
            HUF_setValue(&ct[i], valPerRank[nb]);
            valPerRank[nb] += 1;
        }
    }
    HUF_writeCTableHeader(ctable, maxNbBits, maxSymbolValue);
}

// -------------------------------------------------------------------------
//  HUF_buildCTable_wksp — public entry point.
// -------------------------------------------------------------------------
const HUF_buildCTable_wksp_tables = extern struct {
    huffNodeTbl: [2 * HUF_SYMBOLVALUE_MAX_P1]nodeElt,
    rankPosition: [RANK_POSITION_TABLE_SIZE]rankPos,
};

comptime {
    // Upstream HUF_STATIC_ASSERT(HUF_CTABLE_WORKSPACE_SIZE == sizeof(HUF_buildCTable_wksp_tables)).
    std.debug.assert(HUF_CTABLE_WORKSPACE_SIZE == @sizeOf(HUF_buildCTable_wksp_tables));
}

pub export fn HUF_buildCTable_wksp(
    ctable: [*]HUF_CElt,
    count: [*]const c_uint,
    maxSymbolValue: u32,
    maxNbBits_in: u32,
    workspace: ?*anyopaque,
    wkspSize_in: usize,
) usize {
    var wkspSize = wkspSize_in;
    const wkspBytes = hufAlignUpWorkspace(workspace, &wkspSize, @alignOf(u32)) orelse
        return zstdError(.workSpace_tooSmall);
    if (wkspSize < @sizeOf(HUF_buildCTable_wksp_tables))
        return zstdError(.workSpace_tooSmall);

    const wksp_tables: *HUF_buildCTable_wksp_tables = @ptrCast(@alignCast(wkspBytes));
    const huffNode0: [*]nodeElt = &wksp_tables.huffNodeTbl;
    const huffNode: [*]nodeElt = huffNode0 + 1;

    var maxNbBits = maxNbBits_in;
    if (maxNbBits == 0) maxNbBits = HUF_TABLELOG_DEFAULT;
    if (maxSymbolValue > HUF_SYMBOLVALUE_MAX) return zstdError(.maxSymbolValue_tooLarge);

    @memset(wksp_tables.huffNodeTbl[0..], .{ .count = 0, .parent = 0, .byte = 0, .nbBits = 0 });

    // sort, decreasing order
    hufSort(huffNode, count, maxSymbolValue, &wksp_tables.rankPosition);

    // build tree
    const nonNullRank = hufBuildTree(huffNode, maxSymbolValue);

    // determine + enforce maxTableLog
    const finalNbBits = hufSetMaxHeight(huffNode, @intCast(nonNullRank), maxNbBits);
    if (finalNbBits > HUF_TABLELOG_MAX) return zstdError(.generic_err);

    hufBuildCTableFromTree(ctable, huffNode, nonNullRank, maxSymbolValue, finalNbBits);

    return finalNbBits;
}

// -------------------------------------------------------------------------
//  HUF_estimateCompressedSize / HUF_validateCTable / HUF_compressBound
// -------------------------------------------------------------------------
pub export fn HUF_estimateCompressedSize(
    ctable_in: [*]const HUF_CElt,
    count: [*]const c_uint,
    maxSymbolValue: c_uint,
) usize {
    const ct: [*]const HUF_CElt = ctable_in + 1;
    var nbBits: usize = 0;
    var s: u32 = 0;
    while (s <= maxSymbolValue) : (s += 1) {
        nbBits += HUF_getNbBits(ct[s]) * count[s];
    }
    return nbBits >> 3;
}

pub export fn HUF_validateCTable(
    ctable_in: [*]const HUF_CElt,
    count: [*]const c_uint,
    maxSymbolValue: c_uint,
) c_int {
    const hdr = HUF_readCTableHeader(ctable_in);
    const ct: [*]const HUF_CElt = ctable_in + 1;
    std.debug.assert(hdr.tableLog <= HUF_TABLELOG_ABSOLUTEMAX);
    if (hdr.maxSymbolValue < maxSymbolValue) return 0;
    var bad: c_uint = 0;
    var s: u32 = 0;
    while (s <= maxSymbolValue) : (s += 1) {
        bad |= @intFromBool((count[s] != 0) and (HUF_getNbBits(ct[s]) == 0));
    }
    return if (bad == 0) 1 else 0;
}

pub export fn HUF_compressBound(size: usize) usize {
    return HUF_COMPRESSBOUND(size);
}

// -------------------------------------------------------------------------
//  HUF_CStream_t — Huffman-specific bitstream state (slice 3b).
//
//  Format reminder (from upstream):
//    * Each container is filled from the TOP down — bits flow toward the LSB.
//    * addBits does:   container >>= nbBits;   container |= value
//      where `value` already lives in the top `nbBits` bits of the HUF_CElt.
//    * `bitPos[idx]`'s low 8 bits track the number of populated bits
//      (the upper bits accumulate harmless noise from the HUF_CElt add).
//    * bitContainer[1] is a secondary container that lets the unrolled loop
//      start filling the "next slot" without a data dependency on index 0;
//      HUF_mergeIndex1 folds it in, HUF_zeroIndex1 resets it.
// -------------------------------------------------------------------------
pub const HUF_CStream_t = extern struct {
    bitContainer: [2]u64,
    bitPos: [2]u64,
    startPtr: [*]u8,
    ptr: [*]u8,
    endPtr: [*]u8,
};

fn HUF_initCStream(bitC: *HUF_CStream_t, startPtr: [*]u8, dstCapacity: usize) usize {
    bitC.bitContainer = .{ 0, 0 };
    bitC.bitPos = .{ 0, 0 };
    bitC.startPtr = startPtr;
    bitC.ptr = startPtr;
    if (dstCapacity <= @sizeOf(u64)) return zstdError(.dstSize_tooSmall);
    bitC.endPtr = startPtr + dstCapacity - @sizeOf(u64);
    return 0;
}

/// HUF_addBits — add the symbol carried by HUF_CElt `elt` to bitstream slot `idx`.
/// `kFast`: caller guarantees ≥4 unused bits remain after insertion (enables
/// getValueFast / skipping low-bit mask). `idx` is 0 or 1.
inline fn HUF_addBits(bitC: *HUF_CStream_t, elt: HUF_CElt, comptime idx: u1, comptime kFast: bool) void {
    std.debug.assert(HUF_getNbBits(elt) <= HUF_TABLELOG_ABSOLUTEMAX);
    const nbBits = HUF_getNbBits(elt);
    // Right-shift the container by nbBits to make room at the TOP for the new value.
    // nbBits is in [0, HUF_TABLELOG_ABSOLUTEMAX=12] so always < 64.
    // Zig disallows >> 64 at runtime, but nbBits=0 is fine (shift by 0).
    bitC.bitContainer[idx] = bitC.bitContainer[idx] >> @intCast(nbBits);
    const add: u64 = if (kFast) HUF_getValueFast(elt) else HUF_getValue(elt);
    bitC.bitContainer[idx] |= add;
    // bitPos may have garbage in the high bits from HUF_getNbBitsFast's raw-elt return;
    // upstream only cares about the low 8 bits via `& 0xFF`. size_t wraps; use +%.
    bitC.bitPos[idx] +%= HUF_getNbBitsFast(elt);
    std.debug.assert((bitC.bitPos[idx] & 0xFF) <= HUF_BITS_IN_CONTAINER);
}

inline fn HUF_zeroIndex1(bitC: *HUF_CStream_t) void {
    bitC.bitContainer[1] = 0;
    bitC.bitPos[1] = 0;
}

/// Merge container[1] into container[0] and zero container[1].
inline fn HUF_mergeIndex1(bitC: *HUF_CStream_t) void {
    std.debug.assert((bitC.bitPos[1] & 0xFF) < HUF_BITS_IN_CONTAINER);
    const shift: u6 = @intCast(bitC.bitPos[1] & 0xFF);
    bitC.bitContainer[0] = bitC.bitContainer[0] >> shift;
    bitC.bitContainer[0] |= bitC.bitContainer[1];
    bitC.bitPos[0] +%= bitC.bitPos[1];
    std.debug.assert((bitC.bitPos[0] & 0xFF) <= HUF_BITS_IN_CONTAINER);
    bitC.bitContainer[1] = 0;
    bitC.bitPos[1] = 0;
}

/// Drain full bytes from container[0] to `ptr`. After flush, bitPos[0] ∈ [0,7].
inline fn HUF_flushBits(bitC: *HUF_CStream_t, comptime kFast: bool) void {
    const nbBits: u64 = bitC.bitPos[0] & 0xFF;
    const nbBytes: u64 = nbBits >> 3;
    std.debug.assert(nbBits > 0);
    std.debug.assert(nbBits <= HUF_BITS_IN_CONTAINER);
    std.debug.assert(@intFromPtr(bitC.ptr) <= @intFromPtr(bitC.endPtr));
    // Extract the top `nbBits` as a size_t and write little-endian.
    const bitContainer: u64 = if (nbBits == HUF_BITS_IN_CONTAINER)
        bitC.bitContainer[0]
    else
        bitC.bitContainer[0] >> @intCast(HUF_BITS_IN_CONTAINER - nbBits);
    bitC.bitPos[0] &= 7;
    const dst = bitC.ptr[0..8];
    std.mem.writeInt(u64, dst, bitContainer, .little);
    bitC.ptr += @intCast(nbBytes);
    if (!kFast and @intFromPtr(bitC.ptr) > @intFromPtr(bitC.endPtr)) bitC.ptr = bitC.endPtr;
    // Leftover bits remain at the top of bitContainer[0]; they'll be re-written
    // on the next flush. No need to clear them.
}

/// HUF_endMark — a 1-bit value = 1.
inline fn HUF_endMark() HUF_CElt {
    var em: HUF_CElt = 0;
    HUF_setNbBits(&em, 1);
    HUF_setValue(&em, 1);
    return em;
}

fn HUF_closeCStream(bitC: *HUF_CStream_t) usize {
    HUF_addBits(bitC, HUF_endMark(), 0, false);
    HUF_flushBits(bitC, false);
    const nbBits: u64 = bitC.bitPos[0] & 0xFF;
    if (@intFromPtr(bitC.ptr) >= @intFromPtr(bitC.endPtr)) return 0;
    const size = @intFromPtr(bitC.ptr) - @intFromPtr(bitC.startPtr);
    return size + @intFromBool(nbBits > 0);
}

inline fn HUF_encodeSymbol(
    bitC: *HUF_CStream_t,
    symbol: u32,
    ct: [*]const HUF_CElt,
    comptime idx: u1,
    comptime fast: bool,
) void {
    HUF_addBits(bitC, ct[symbol], idx, fast);
}

// -------------------------------------------------------------------------
//  Body loop — template over unroll factor and fast flags. Iterates input
//  RIGHT-TO-LEFT (matches bitstream reversal required by the decoder).
// -------------------------------------------------------------------------
fn HUF_compress1X_usingCTable_internal_body_loop(
    bitC: *HUF_CStream_t,
    ip: [*]const u8,
    srcSize: usize,
    ct: [*]const HUF_CElt,
    comptime kUnroll: u32,
    comptime kFastFlush: bool,
    comptime kLastFast: bool,
) void {
    var n: i64 = @intCast(srcSize);

    // Join to kUnroll
    var rem: i64 = @mod(n, kUnroll);
    if (rem > 0) {
        while (rem > 0) : (rem -= 1) {
            n -= 1;
            HUF_encodeSymbol(bitC, ip[@intCast(n)], ct, 0, false);
        }
        HUF_flushBits(bitC, kFastFlush);
    }
    std.debug.assert(@mod(n, kUnroll) == 0);

    // Join to 2 * kUnroll
    if (@mod(n, 2 * kUnroll) != 0) {
        comptime var u: u32 = 1;
        inline while (u < kUnroll) : (u += 1) {
            HUF_encodeSymbol(bitC, ip[@intCast(n - u)], ct, 0, true);
        }
        HUF_encodeSymbol(bitC, ip[@intCast(n - kUnroll)], ct, 0, kLastFast);
        HUF_flushBits(bitC, kFastFlush);
        n -= kUnroll;
    }
    std.debug.assert(@mod(n, 2 * kUnroll) == 0);

    while (n > 0) : (n -= 2 * kUnroll) {
        // kUnroll symbols into slot 0
        comptime var u: u32 = 1;
        inline while (u < kUnroll) : (u += 1) {
            HUF_encodeSymbol(bitC, ip[@intCast(n - u)], ct, 0, true);
        }
        HUF_encodeSymbol(bitC, ip[@intCast(n - kUnroll)], ct, 0, kLastFast);
        HUF_flushBits(bitC, kFastFlush);
        // kUnroll symbols into slot 1
        HUF_zeroIndex1(bitC);
        comptime var v: u32 = 1;
        inline while (v < kUnroll) : (v += 1) {
            HUF_encodeSymbol(bitC, ip[@intCast(n - kUnroll - v)], ct, 1, true);
        }
        HUF_encodeSymbol(bitC, ip[@intCast(n - kUnroll - kUnroll)], ct, 1, kLastFast);
        // merge + flush
        HUF_mergeIndex1(bitC);
        HUF_flushBits(bitC, kFastFlush);
    }
    std.debug.assert(n == 0);
}

pub fn HUF_tightCompressBound(srcSize: usize, tableLog: usize) usize {
    return ((srcSize * tableLog) >> 3) + 8;
}

// Body wrapping init + table-log-specialised unroll choice + close.
fn HUF_compress1X_usingCTable_internal_body(
    dst: [*]u8,
    dstSize: usize,
    src: [*]const u8,
    srcSize: usize,
    ctable: [*]const HUF_CElt,
) usize {
    const tableLog: u32 = HUF_readCTableHeader(ctable).tableLog;
    const ct: [*]const HUF_CElt = ctable + 1;
    const ostart = dst;
    const oend = ostart + dstSize;
    _ = oend;
    var bitC: HUF_CStream_t = undefined;

    if (dstSize < 8) return 0; // not enough space to compress
    {
        const initErr = HUF_initCStream(&bitC, ostart, dstSize);
        if (common.ERR_isError(initErr) != 0) return 0;
    }

    // We're 64-bit only: kUnroll choice follows upstream's !MEM_32bits() branch.
    const tight = HUF_tightCompressBound(srcSize, tableLog);
    if (dstSize < tight or tableLog > 11) {
        HUF_compress1X_usingCTable_internal_body_loop(&bitC, src, srcSize, ct, 4, false, false);
    } else {
        switch (tableLog) {
            11 => HUF_compress1X_usingCTable_internal_body_loop(&bitC, src, srcSize, ct, 5, true, false),
            10 => HUF_compress1X_usingCTable_internal_body_loop(&bitC, src, srcSize, ct, 5, true, true),
            9 => HUF_compress1X_usingCTable_internal_body_loop(&bitC, src, srcSize, ct, 6, true, false),
            8 => HUF_compress1X_usingCTable_internal_body_loop(&bitC, src, srcSize, ct, 7, true, false),
            7 => HUF_compress1X_usingCTable_internal_body_loop(&bitC, src, srcSize, ct, 8, true, false),
            // 6 + default
            else => HUF_compress1X_usingCTable_internal_body_loop(&bitC, src, srcSize, ct, 9, true, true),
        }
    }
    std.debug.assert(@intFromPtr(bitC.ptr) <= @intFromPtr(bitC.endPtr));

    return HUF_closeCStream(&bitC);
}

// bmi2 / default variants — we do not have runtime dispatch here, both call
// the same body. The `flags` / `bmi2` path exists upstream purely so the
// compiler can target-attribute the body; Zig handles that via the build.
// Promoted to `pub` for slice 3c so the high-level wrappers can dispatch on
// HUF_nbStreams_e without crossing the C-ABI boundary.
pub fn HUF_compress1X_usingCTable_internal(
    dst: [*]u8,
    dstSize: usize,
    src: [*]const u8,
    srcSize: usize,
    ctable: [*]const HUF_CElt,
    flags: c_int,
) usize {
    _ = flags;
    return HUF_compress1X_usingCTable_internal_body(dst, dstSize, src, srcSize, ctable);
}

pub export fn HUF_compress1X_usingCTable(
    dst: ?*anyopaque,
    dstSize: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    ctable: [*]const HUF_CElt,
    flags: c_int,
) usize {
    const dstP: [*]u8 = @ptrCast(dst.?);
    const srcP: [*]const u8 = @ptrCast(src.?);
    return HUF_compress1X_usingCTable_internal(dstP, dstSize, srcP, srcSize, ctable, flags);
}

// -------------------------------------------------------------------------
//  4X variant — split src into 4 segments, write a 6-byte jump table, then
//  emit four back-to-back 1X streams.
// -------------------------------------------------------------------------
// Promoted to `pub` for slice 3c (see comment on the 1X variant above).
pub fn HUF_compress4X_usingCTable_internal(
    dst: [*]u8,
    dstSize: usize,
    src: [*]const u8,
    srcSize: usize,
    ctable: [*]const HUF_CElt,
    flags: c_int,
) usize {
    const segmentSize: usize = (srcSize + 3) / 4;
    var ip = src;
    const iend = src + srcSize;
    const ostart = dst;
    const oend = ostart + dstSize;
    var op = ostart;

    if (dstSize < 6 + 1 + 1 + 1 + 8) return 0;
    if (srcSize < 12) return 0;
    op += 6; // jump table
    std.debug.assert(@intFromPtr(op) <= @intFromPtr(oend));

    // segment 0
    {
        const cSize = HUF_compress1X_usingCTable_internal(op, @intFromPtr(oend) - @intFromPtr(op), ip, segmentSize, ctable, flags);
        if (common.ERR_isError(cSize) != 0) return cSize;
        if (cSize == 0 or cSize > 65535) return 0;
        std.mem.writeInt(u16, ostart[0..2], @intCast(cSize), .little);
        op += cSize;
    }
    ip += segmentSize;
    std.debug.assert(@intFromPtr(op) <= @intFromPtr(oend));

    // segment 1
    {
        const cSize = HUF_compress1X_usingCTable_internal(op, @intFromPtr(oend) - @intFromPtr(op), ip, segmentSize, ctable, flags);
        if (common.ERR_isError(cSize) != 0) return cSize;
        if (cSize == 0 or cSize > 65535) return 0;
        std.mem.writeInt(u16, (ostart + 2)[0..2], @intCast(cSize), .little);
        op += cSize;
    }
    ip += segmentSize;
    std.debug.assert(@intFromPtr(op) <= @intFromPtr(oend));

    // segment 2
    {
        const cSize = HUF_compress1X_usingCTable_internal(op, @intFromPtr(oend) - @intFromPtr(op), ip, segmentSize, ctable, flags);
        if (common.ERR_isError(cSize) != 0) return cSize;
        if (cSize == 0 or cSize > 65535) return 0;
        std.mem.writeInt(u16, (ostart + 4)[0..2], @intCast(cSize), .little);
        op += cSize;
    }
    ip += segmentSize;
    std.debug.assert(@intFromPtr(op) <= @intFromPtr(oend));
    std.debug.assert(@intFromPtr(ip) <= @intFromPtr(iend));

    // segment 3 (remainder)
    {
        const tail = @intFromPtr(iend) - @intFromPtr(ip);
        const cSize = HUF_compress1X_usingCTable_internal(op, @intFromPtr(oend) - @intFromPtr(op), ip, tail, ctable, flags);
        if (common.ERR_isError(cSize) != 0) return cSize;
        if (cSize == 0 or cSize > 65535) return 0;
        op += cSize;
    }

    return @intFromPtr(op) - @intFromPtr(ostart);
}

pub export fn HUF_compress4X_usingCTable(
    dst: ?*anyopaque,
    dstSize: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    ctable: [*]const HUF_CElt,
    flags: c_int,
) usize {
    const dstP: [*]u8 = @ptrCast(dst.?);
    const srcP: [*]const u8 = @ptrCast(src.?);
    return HUF_compress4X_usingCTable_internal(dstP, dstSize, srcP, srcSize, ctable, flags);
}

// -------------------------------------------------------------------------
//  HUF_cardinality / HUF_minTableLog / HUF_optimalTableLog
//  Public version (not the FSE internal one); consulted by slice 3c.
// -------------------------------------------------------------------------
pub export fn HUF_cardinality(count: [*]const c_uint, maxSymbolValue: c_uint) c_uint {
    var card: c_uint = 0;
    var i: c_uint = 0;
    while (i < maxSymbolValue + 1) : (i += 1) {
        if (count[i] != 0) card += 1;
    }
    return card;
}

pub export fn HUF_minTableLog(symbolCardinality: c_uint) c_uint {
    // ZSTD_highbit32(card) + 1 — undefined for 0, but upstream never calls with 0.
    std.debug.assert(symbolCardinality != 0);
    return highbit32u(symbolCardinality) + 1;
}

/// Public HUF_optimalTableLog — trial-builds tables at several depths if
/// `HUF_flags_optimalDepth` is set, otherwise falls back to the cheap FSE
/// heuristic. Needs a workspace ≥ `HUF_buildCTable_wksp_tables` big.
pub export fn HUF_optimalTableLog(
    maxTableLog: c_uint,
    srcSize: usize,
    maxSymbolValue: c_uint,
    workSpace: ?*anyopaque,
    wkspSize: usize,
    table: [*]HUF_CElt,
    count: [*]const c_uint,
    flags: c_int,
) c_uint {
    std.debug.assert(srcSize > 1);
    std.debug.assert(wkspSize >= @sizeOf(HUF_buildCTable_wksp_tables));

    if ((flags & ec.HUF_flags_optimalDepth) == 0) {
        return fsec.FSE_optimalTableLog_internal(maxTableLog, srcSize, maxSymbolValue, 1);
    }

    // Probe Huffman depths, pick the one that yields the smallest table+data.
    const wsBytes: [*]u8 = @ptrCast(workSpace.?);
    const dstBuf: [*]u8 = wsBytes + @sizeOf(HUF_WriteCTableWksp);
    const dstSize: usize = if (wkspSize >= @sizeOf(HUF_WriteCTableWksp))
        wkspSize - @sizeOf(HUF_WriteCTableWksp)
    else
        0;
    const symbolCardinality: c_uint = HUF_cardinality(count, maxSymbolValue);
    const minLog: c_uint = HUF_minTableLog(symbolCardinality);
    var optSize: usize = @as(usize, ~@as(usize, 0)) - 1;
    var optLog: c_uint = maxTableLog;

    var guess: c_uint = minLog;
    while (guess <= maxTableLog) : (guess += 1) {
        const maxBits = HUF_buildCTable_wksp(table, count, maxSymbolValue, guess, workSpace, wkspSize);
        if (common.ERR_isError(maxBits) != 0) continue;
        if (maxBits < guess and guess > minLog) break;

        const hSize = HUF_writeCTable_wksp(dstBuf, dstSize, table, maxSymbolValue, @intCast(maxBits), workSpace, wkspSize);
        if (common.ERR_isError(hSize) != 0) continue;

        const newSize = HUF_estimateCompressedSize(table, count, maxSymbolValue) + hSize;
        if (newSize > optSize + 1) break;
        if (newSize < optSize) {
            optSize = newSize;
            optLog = guess;
        }
    }
    std.debug.assert(optLog <= HUF_TABLELOG_MAX);
    return optLog;
}

// =========================================================================
//  Slice 3c — high-level HUF_compress_* wrappers (final huf_compress.c piece)
// =========================================================================
//
//  Public surface:
//      HUF_WORKSPACE_SIZE / HUF_WORKSPACE_SIZE_U64 constants
//      HUF_nbStreams_e   (extern enum: singleStream / fourStreams)
//      HUF_repeat        (extern enum: none / check / valid)
//      HUF_compress1X_repeat, HUF_compress4X_repeat
//  Internal helpers:
//      HUF_compressCTable_internal, HUF_compress_internal,
//      HUF_compress_tables_t (extern union overlaying buildCTable /
//      writeCTable / hist workspaces plus a scratch CTable).

/// HUF_WORKSPACE_SIZE / _U64 — mirror of the definition in huf.h.
pub const HUF_WORKSPACE_SIZE: usize = (8 << 10) + 512;
pub const HUF_WORKSPACE_SIZE_U64: usize = HUF_WORKSPACE_SIZE / @sizeOf(u64);
pub const HUF_WORKSPACE_MAX_ALIGNMENT: usize = 8;

/// HUF_nbStreams_e — dispatch selector for 1-stream vs 4-stream layout.
pub const HUF_nbStreams_e = enum(c_int) {
    HUF_singleStream = 0,
    HUF_fourStreams = 1,
};
pub const HUF_singleStream = HUF_nbStreams_e.HUF_singleStream;
pub const HUF_fourStreams = HUF_nbStreams_e.HUF_fourStreams;

/// HUF_repeat — CTable reuse hint passed through HUF_compress{1,4}X_repeat.
pub const HUF_repeat = enum(c_int) {
    HUF_repeat_none = 0,
    HUF_repeat_check = 1,
    HUF_repeat_valid = 2,
};
pub const HUF_repeat_none = HUF_repeat.HUF_repeat_none;
pub const HUF_repeat_check = HUF_repeat.HUF_repeat_check;
pub const HUF_repeat_valid = HUF_repeat.HUF_repeat_valid;

/// HUF_compress_tables_t — workspace union. Upstream overlays a histogram
/// scratchbuf, a buildCTable_wksp, and a writeCTable_wksp on top of one
/// another. We model it as an extern union; the CTable scratch and the
/// histogram `count` live outside the union (they need to survive across
/// all three phases).
const HUF_wksps_union = extern union {
    buildCTable_wksp: HUF_buildCTable_wksp_tables,
    writeCTable_wksp: HUF_WriteCTableWksp,
    hist_wksp: [hist.HIST_WKSP_SIZE_U32]u32,
};

pub const HUF_compress_tables_t = extern struct {
    count: [HUF_SYMBOLVALUE_MAX + 1]c_uint,
    CTable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt, // HUF_CTABLE_SIZE_ST(HUF_SYMBOLVALUE_MAX)
    wksps: HUF_wksps_union,
};

comptime {
    // Matches the upstream HUF_STATIC_ASSERT in HUF_compress_internal.
    std.debug.assert(@sizeOf(HUF_compress_tables_t) + HUF_WORKSPACE_MAX_ALIGNMENT <= HUF_WORKSPACE_SIZE);
}

// -------------------------------------------------------------------------
//  HUF_compressCTable_internal — dispatch into 1X or 4X, check compressibility.
// -------------------------------------------------------------------------
fn HUF_compressCTable_internal(
    ostart: [*]u8,
    op_in: [*]u8,
    oend: [*]u8,
    src: [*]const u8,
    srcSize: usize,
    nbStreams: HUF_nbStreams_e,
    ctable: [*]const HUF_CElt,
    flags: c_int,
) usize {
    var op = op_in;
    const avail: usize = @intFromPtr(oend) - @intFromPtr(op);
    const cSize: usize = switch (nbStreams) {
        .HUF_singleStream => HUF_compress1X_usingCTable_internal(op, avail, src, srcSize, ctable, flags),
        .HUF_fourStreams => HUF_compress4X_usingCTable_internal(op, avail, src, srcSize, ctable, flags),
    };
    if (common.ERR_isError(cSize) != 0) return cSize;
    if (cSize == 0) return 0;
    op += cSize;
    std.debug.assert(@intFromPtr(op) >= @intFromPtr(ostart));
    const produced: usize = @intFromPtr(op) - @intFromPtr(ostart);
    if (produced >= srcSize - 1) return 0;
    return produced;
}

// -------------------------------------------------------------------------
//  HUF_compress_internal — workhorse. Mirrors lines 1329-1434 of upstream.
// -------------------------------------------------------------------------
const SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE: usize = 4096;
const SUSPECT_INCOMPRESSIBLE_SAMPLE_RATIO: usize = 10; // must be >= 2

fn HUF_compress_internal(
    dst: ?*anyopaque,
    dstSize: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    maxSymbolValue_in: c_uint,
    huffLog_in: c_uint,
    nbStreams: HUF_nbStreams_e,
    workSpace: ?*anyopaque,
    wkspSize_in: usize,
    oldHufTable: ?[*]HUF_CElt,
    repeat: ?*HUF_repeat,
    flags: c_int,
) usize {
    var wkspSize = wkspSize_in;
    const wkspBytes = hufAlignUpWorkspace(workSpace, &wkspSize, @alignOf(u64)) orelse
        return zstdError(.workSpace_tooSmall);
    if (wkspSize < @sizeOf(HUF_compress_tables_t)) return zstdError(.workSpace_tooSmall);
    const table: *HUF_compress_tables_t = @ptrCast(@alignCast(wkspBytes));

    const ostart: [*]u8 = @ptrCast(dst.?);
    const oend: [*]u8 = ostart + dstSize;
    var op: [*]u8 = ostart;

    // checks & inits
    if (srcSize == 0) return 0;
    if (dstSize == 0) return 0;
    if (srcSize > HUF_BLOCKSIZE_MAX) return zstdError(.srcSize_wrong);
    if (huffLog_in > HUF_TABLELOG_MAX) return zstdError(.tableLog_tooLarge);
    if (maxSymbolValue_in > HUF_SYMBOLVALUE_MAX) return zstdError(.maxSymbolValue_tooLarge);

    var maxSymbolValue: c_uint = if (maxSymbolValue_in == 0) HUF_SYMBOLVALUE_MAX else maxSymbolValue_in;
    var huffLog: c_uint = if (huffLog_in == 0) HUF_TABLELOG_DEFAULT else huffLog_in;

    const srcBytes: [*]const u8 = @ptrCast(src.?);

    // Heuristic: if old table is valid and the caller prefers repeat, use it.
    if ((flags & ec.HUF_flags_preferRepeat) != 0 and repeat != null and repeat.?.* == .HUF_repeat_valid) {
        return HUF_compressCTable_internal(ostart, op, oend, srcBytes, srcSize, nbStreams, oldHufTable.?, flags);
    }

    // If uncompressible data is suspected, sample before committing.
    if ((flags & ec.HUF_flags_suspectUncompressible) != 0 and
        srcSize >= (SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE * SUSPECT_INCOMPRESSIBLE_SAMPLE_RATIO))
    {
        var largestTotal: usize = 0;
        {
            var maxSymbolValueBegin: c_uint = maxSymbolValue;
            const largestBegin = hist.HIST_count_simple(&table.count, &maxSymbolValueBegin, srcBytes, SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE);
            if (common.ERR_isError(largestBegin) != 0) return largestBegin;
            largestTotal += largestBegin;
        }
        {
            var maxSymbolValueEnd: c_uint = maxSymbolValue;
            const tail = srcBytes + srcSize - SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE;
            const largestEnd = hist.HIST_count_simple(&table.count, &maxSymbolValueEnd, tail, SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE);
            if (common.ERR_isError(largestEnd) != 0) return largestEnd;
            largestTotal += largestEnd;
        }
        if (largestTotal <= ((2 * SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE) >> 7) + 4) return 0;
    }

    // Scan input and build symbol stats.
    {
        const largest = hist.HIST_count_wksp(
            &table.count,
            &maxSymbolValue,
            srcBytes,
            srcSize,
            @ptrCast(&table.wksps.hist_wksp),
            @sizeOf(@TypeOf(table.wksps.hist_wksp)),
        );
        if (common.ERR_isError(largest) != 0) return largest;
        if (largest == srcSize) {
            ostart[0] = srcBytes[0];
            return 1; // rle: single-symbol block
        }
        if (largest <= (srcSize >> 7) + 4) return 0; // heuristic: not compressible
    }

    // Check validity of previous table.
    if (repeat) |rp| {
        if (rp.* == .HUF_repeat_check and HUF_validateCTable(oldHufTable.?, &table.count, maxSymbolValue) == 0) {
            rp.* = .HUF_repeat_none;
        }
    }
    // Heuristic: use existing table for small inputs.
    if ((flags & ec.HUF_flags_preferRepeat) != 0 and repeat != null and repeat.?.* != .HUF_repeat_none) {
        return HUF_compressCTable_internal(ostart, op, oend, srcBytes, srcSize, nbStreams, oldHufTable.?, flags);
    }

    // Build Huffman tree.
    huffLog = HUF_optimalTableLog(
        huffLog,
        srcSize,
        maxSymbolValue,
        @ptrCast(&table.wksps),
        @sizeOf(@TypeOf(table.wksps)),
        &table.CTable,
        &table.count,
        flags,
    );
    {
        const maxBits = HUF_buildCTable_wksp(
            &table.CTable,
            &table.count,
            maxSymbolValue,
            huffLog,
            @ptrCast(&table.wksps.buildCTable_wksp),
            @sizeOf(@TypeOf(table.wksps.buildCTable_wksp)),
        );
        if (common.ERR_isError(maxBits) != 0) return maxBits;
        huffLog = @intCast(maxBits);
    }

    // Write table description header, and decide whether reusing the old
    // table would be cheaper than emitting a new one.
    {
        const hSize = HUF_writeCTable_wksp(
            op,
            dstSize,
            &table.CTable,
            maxSymbolValue,
            huffLog,
            @ptrCast(&table.wksps.writeCTable_wksp),
            @sizeOf(@TypeOf(table.wksps.writeCTable_wksp)),
        );
        if (common.ERR_isError(hSize) != 0) return hSize;

        if (repeat) |rp| {
            if (rp.* != .HUF_repeat_none) {
                const oldSize = HUF_estimateCompressedSize(oldHufTable.?, &table.count, maxSymbolValue);
                const newSize = HUF_estimateCompressedSize(&table.CTable, &table.count, maxSymbolValue);
                if (oldSize <= hSize + newSize or hSize + 12 >= srcSize) {
                    return HUF_compressCTable_internal(ostart, op, oend, srcBytes, srcSize, nbStreams, oldHufTable.?, flags);
                }
            }
        }

        if (hSize + 12 >= srcSize) return 0;
        op += hSize;
        if (repeat) |rp| rp.* = .HUF_repeat_none;
        if (oldHufTable) |oht| {
            const dstPtr: [*]u8 = @ptrCast(oht);
            const srcPtr: [*]const u8 = @ptrCast(&table.CTable);
            @memcpy(dstPtr[0..@sizeOf(@TypeOf(table.CTable))], srcPtr[0..@sizeOf(@TypeOf(table.CTable))]);
        }
    }
    return HUF_compressCTable_internal(ostart, op, oend, srcBytes, srcSize, nbStreams, &table.CTable, flags);
}

// -------------------------------------------------------------------------
//  Public wrappers: HUF_compress1X_repeat / HUF_compress4X_repeat
// -------------------------------------------------------------------------
pub export fn HUF_compress1X_repeat(
    dst: ?*anyopaque,
    dstSize: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    maxSymbolValue: c_uint,
    huffLog: c_uint,
    workSpace: ?*anyopaque,
    wkspSize: usize,
    hufTable: ?[*]HUF_CElt,
    repeat: ?*HUF_repeat,
    flags: c_int,
) usize {
    return HUF_compress_internal(
        dst,
        dstSize,
        src,
        srcSize,
        maxSymbolValue,
        huffLog,
        .HUF_singleStream,
        workSpace,
        wkspSize,
        hufTable,
        repeat,
        flags,
    );
}

pub export fn HUF_compress4X_repeat(
    dst: ?*anyopaque,
    dstSize: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    maxSymbolValue: c_uint,
    huffLog: c_uint,
    workSpace: ?*anyopaque,
    wkspSize: usize,
    hufTable: ?[*]HUF_CElt,
    repeat: ?*HUF_repeat,
    flags: c_int,
) usize {
    return HUF_compress_internal(
        dst,
        dstSize,
        src,
        srcSize,
        maxSymbolValue,
        huffLog,
        .HUF_fourStreams,
        workSpace,
        wkspSize,
        hufTable,
        repeat,
        flags,
    );
}
// -------------------------------------------------------------------------

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------
test "HUF_CElt pack/unpack round-trip" {
    var elt: HUF_CElt = 0;
    HUF_setNbBits(&elt, 5);
    HUF_setValue(&elt, 0b10110);
    try std.testing.expectEqual(@as(usize, 5), HUF_getNbBits(elt));
    // value occupies top 5 bits of a u64
    try std.testing.expectEqual(@as(HUF_CElt, 0b10110 << 59 | 5), elt);
}

test "HUF_writeCTableHeader round-trip" {
    var table: [2]HUF_CElt = [_]HUF_CElt{0} ** 2;
    HUF_writeCTableHeader(&table, 11, 200);
    const hdr = HUF_readCTableHeader(&table);
    try std.testing.expectEqual(@as(u8, 11), hdr.tableLog);
    try std.testing.expectEqual(@as(u8, 200), hdr.maxSymbolValue);
}

test "HUF_buildCTable_wksp trivial 2-symbol distribution" {
    // Two equally-likely symbols → both get 1 bit.
    var ctable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    count[0] = 50;
    count[1] = 50;
    var wksp: HUF_buildCTable_wksp_tables = undefined;
    const maxBits = HUF_buildCTable_wksp(&ctable, &count, 1, 0, &wksp, @sizeOf(@TypeOf(wksp)));
    try std.testing.expect(common.ERR_isError(maxBits) == 0);
    try std.testing.expectEqual(@as(usize, 1), maxBits);
    try std.testing.expectEqual(@as(u32, 1), HUF_getNbBitsFromCTable(&ctable, 0));
    try std.testing.expectEqual(@as(u32, 1), HUF_getNbBitsFromCTable(&ctable, 1));
    try std.testing.expectEqual(@as(u32, 0), HUF_getNbBitsFromCTable(&ctable, 2)); // beyond max
}

test "HUF_buildCTable skewed distribution — depth-limited" {
    // 4 symbols, power-of-2 frequencies → simple canonical tree.
    var ctable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    count[0] = 8;
    count[1] = 4;
    count[2] = 2;
    count[3] = 2;
    var wksp: HUF_buildCTable_wksp_tables = undefined;
    const maxBits = HUF_buildCTable_wksp(&ctable, &count, 3, 0, &wksp, @sizeOf(@TypeOf(wksp)));
    try std.testing.expect(common.ERR_isError(maxBits) == 0);
    // Expected: sym0 = 1 bit, sym1 = 2 bits, sym2/3 = 3 bits.
    try std.testing.expectEqual(@as(u32, 1), HUF_getNbBitsFromCTable(&ctable, 0));
    try std.testing.expectEqual(@as(u32, 2), HUF_getNbBitsFromCTable(&ctable, 1));
    try std.testing.expectEqual(@as(u32, 3), HUF_getNbBitsFromCTable(&ctable, 2));
    try std.testing.expectEqual(@as(u32, 3), HUF_getNbBitsFromCTable(&ctable, 3));
    // validateCTable on the same counts must accept it.
    try std.testing.expectEqual(@as(c_int, 1), HUF_validateCTable(&ctable, &count, 3));
}

test "HUF_writeCTable / HUF_readCTable round-trip" {
    var ctable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    count[0] = 8;
    count[1] = 4;
    count[2] = 2;
    count[3] = 2;
    var wksp: HUF_buildCTable_wksp_tables = undefined;
    const maxBits = HUF_buildCTable_wksp(&ctable, &count, 3, 0, &wksp, @sizeOf(@TypeOf(wksp)));
    try std.testing.expect(common.ERR_isError(maxBits) == 0);

    var buf: [128]u8 = undefined;
    const written = HUF_writeCTable(&buf, buf.len, &ctable, 3, @intCast(maxBits));
    try std.testing.expect(common.ERR_isError(written) == 0);
    try std.testing.expect(written > 0);

    var ctable2: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var maxSV: c_uint = HUF_SYMBOLVALUE_MAX;
    var hasZero: c_uint = 0;
    const read = HUF_readCTable(&ctable2, &maxSV, &buf, written, &hasZero);
    try std.testing.expect(common.ERR_isError(read) == 0);
    try std.testing.expectEqual(@as(c_uint, 3), maxSV);

    // Bit-lengths must match; value assignments must match.
    var s: u32 = 0;
    while (s <= 3) : (s += 1) {
        try std.testing.expectEqual(HUF_getNbBitsFromCTable(&ctable, s), HUF_getNbBitsFromCTable(&ctable2, s));
    }
}

// ---- Slice 3b encoder tests ------------------------------------------------

test "HUF_tightCompressBound bounds" {
    // srcSize * tableLog / 8 + 8
    try std.testing.expectEqual(@as(usize, ((1000 * 11) >> 3) + 8), HUF_tightCompressBound(1000, 11));
    try std.testing.expectEqual(@as(usize, 8), HUF_tightCompressBound(0, 11));
}

test "HUF_cardinality counts non-zero entries" {
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    count[0] = 10;
    count[1] = 0;
    count[2] = 7;
    count[3] = 3;
    try std.testing.expectEqual(@as(c_uint, 3), HUF_cardinality(&count, 3));
    try std.testing.expectEqual(@as(c_uint, 3), HUF_cardinality(&count, HUF_SYMBOLVALUE_MAX));
}

test "HUF_minTableLog matches highbit+1" {
    try std.testing.expectEqual(@as(c_uint, 1), HUF_minTableLog(1));
    try std.testing.expectEqual(@as(c_uint, 2), HUF_minTableLog(2));
    try std.testing.expectEqual(@as(c_uint, 2), HUF_minTableLog(3));
    try std.testing.expectEqual(@as(c_uint, 8), HUF_minTableLog(255));
}

test "HUF_compress1X_usingCTable compresses and shrinks" {
    // Build a CTable from a highly-biased count so Huffman wins.
    var ctable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    // 'a'=180, 'b'=40, 'c'=20, 'd'=10  (total 250)
    count['a'] = 180;
    count['b'] = 40;
    count['c'] = 20;
    count['d'] = 10;
    var wksp: HUF_buildCTable_wksp_tables = undefined;
    const maxBits = HUF_buildCTable_wksp(&ctable, &count, 'd', 0, &wksp, @sizeOf(@TypeOf(wksp)));
    try std.testing.expect(common.ERR_isError(maxBits) == 0);

    var src: [250]u8 = undefined;
    var idx: usize = 0;
    inline for (.{ .{ 'a', 180 }, .{ 'b', 40 }, .{ 'c', 20 }, .{ 'd', 10 } }) |pair| {
        var k: usize = 0;
        while (k < pair[1]) : (k += 1) {
            src[idx] = pair[0];
            idx += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 250), idx);

    var out: [HUF_COMPRESSBOUND(250)]u8 = undefined;
    const cSize = HUF_compress1X_usingCTable(&out, out.len, &src, src.len, &ctable, 0);
    try std.testing.expect(common.ERR_isError(cSize) == 0);
    try std.testing.expect(cSize > 0);
    try std.testing.expect(cSize < src.len); // Huffman should shrink this
}

test "HUF_compress1X_usingCTable rejects tiny dst" {
    // dstSize < 8 ⇒ returns 0 (cannot compress).
    var ctable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    count[0] = 50;
    count[1] = 50;
    var wksp: HUF_buildCTable_wksp_tables = undefined;
    _ = HUF_buildCTable_wksp(&ctable, &count, 1, 0, &wksp, @sizeOf(@TypeOf(wksp)));

    const src = [_]u8{ 0, 1, 0, 1, 0, 1, 0, 1 };
    var tiny: [4]u8 = undefined;
    const r = HUF_compress1X_usingCTable(&tiny, tiny.len, &src, src.len, &ctable, 0);
    try std.testing.expectEqual(@as(usize, 0), r);
}

test "HUF_compress4X_usingCTable writes jump table + 4 streams" {
    var ctable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    // Build a biased alphabet across 6 symbols; 256-byte src.
    count['a'] = 128;
    count['b'] = 64;
    count['c'] = 32;
    count['d'] = 16;
    count['e'] = 8;
    count['f'] = 8;
    var wksp: HUF_buildCTable_wksp_tables = undefined;
    const maxBits = HUF_buildCTable_wksp(&ctable, &count, 'f', 0, &wksp, @sizeOf(@TypeOf(wksp)));
    try std.testing.expect(common.ERR_isError(maxBits) == 0);

    var src: [256]u8 = undefined;
    {
        var idx: usize = 0;
        inline for (.{
            .{ 'a', 128 }, .{ 'b', 64 }, .{ 'c', 32 },
            .{ 'd', 16 },  .{ 'e', 8 },  .{ 'f', 8 },
        }) |pair| {
            var k: usize = 0;
            while (k < pair[1]) : (k += 1) {
                src[idx] = pair[0];
                idx += 1;
            }
        }
    }

    var out: [HUF_COMPRESSBOUND(256)]u8 = undefined;
    const cSize = HUF_compress4X_usingCTable(&out, out.len, &src, src.len, &ctable, 0);
    try std.testing.expect(common.ERR_isError(cSize) == 0);
    try std.testing.expect(cSize > 6); // must include jump table
    try std.testing.expect(cSize < src.len);

    // Jump table: three u16 LE giving segment 0/1/2 sizes; segment 3 implicit.
    const s0: u16 = std.mem.readInt(u16, out[0..2], .little);
    const s1: u16 = std.mem.readInt(u16, out[2..4], .little);
    const s2: u16 = std.mem.readInt(u16, out[4..6], .little);
    try std.testing.expect(s0 > 0);
    try std.testing.expect(s1 > 0);
    try std.testing.expect(s2 > 0);
    try std.testing.expect(@as(usize, 6) + s0 + s1 + s2 < cSize);
}

test "HUF_compress4X_usingCTable short input — not compressible" {
    var ctable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    count[0] = 5;
    count[1] = 5;
    var wksp: HUF_buildCTable_wksp_tables = undefined;
    _ = HUF_buildCTable_wksp(&ctable, &count, 1, 0, &wksp, @sizeOf(@TypeOf(wksp)));

    const src = [_]u8{ 0, 1, 0, 1, 0, 1, 0, 1 }; // 8 bytes < 12
    var out: [HUF_COMPRESSBOUND(8)]u8 = undefined;
    const cSize = HUF_compress4X_usingCTable(&out, out.len, &src, src.len, &ctable, 0);
    try std.testing.expectEqual(@as(usize, 0), cSize);
}

test "HUF_optimalTableLog cheap path returns FSE answer" {
    // With HUF_flags_optimalDepth unset, we must match FSE_optimalTableLog_internal(... , 1).
    var ctable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var count: [HUF_SYMBOLVALUE_MAX + 1]c_uint = [_]c_uint{0} ** (HUF_SYMBOLVALUE_MAX + 1);
    count[0] = 256;
    count[1] = 256;
    var wksp: HUF_buildCTable_wksp_tables = undefined;
    const got = HUF_optimalTableLog(11, 1024, 1, &wksp, @sizeOf(@TypeOf(wksp)), &ctable, &count, 0);
    const want = fsec.FSE_optimalTableLog_internal(11, 1024, 1, 1);
    try std.testing.expectEqual(want, got);
}

// ---- Slice 3c entry-point tests --------------------------------------------

test "HUF_WORKSPACE_SIZE covers HUF_compress_tables_t + alignment" {
    try std.testing.expect(@sizeOf(HUF_compress_tables_t) + HUF_WORKSPACE_MAX_ALIGNMENT <= HUF_WORKSPACE_SIZE);
    try std.testing.expectEqual(@as(usize, (8 << 10) + 512), HUF_WORKSPACE_SIZE);
    try std.testing.expectEqual(HUF_WORKSPACE_SIZE / 8, HUF_WORKSPACE_SIZE_U64);
}

// Helper for 3c tests: build a 4 KiB biased buffer (repeat-safe).
fn make3cSample(buf: []u8) void {
    // 4-symbol geometric distribution: 60% / 25% / 10% / 5%.
    // Produces well-compressible input whose Huffman code occupies 1-3 bits/symbol.
    var prng = std.Random.DefaultPrng.init(0xABCD_1234_DEADBEEF);
    const rng = prng.random();
    for (buf) |*b| {
        const r = rng.int(u32) % 100;
        b.* = if (r < 60) @as(u8, 'a') else if (r < 85) @as(u8, 'b') else if (r < 95) @as(u8, 'c') else @as(u8, 'd');
    }
}

test "HUF_compress1X_repeat round-trip — output < input" {
    var src: [4096]u8 = undefined;
    make3cSample(&src);

    var out: [HUF_COMPRESSBOUND(src.len)]u8 = undefined;
    var wksp: [HUF_WORKSPACE_SIZE_U64]u64 align(8) = undefined;
    const cSize = HUF_compress1X_repeat(
        &out,
        out.len,
        &src,
        src.len,
        0,
        0,
        @ptrCast(&wksp),
        @sizeOf(@TypeOf(wksp)),
        null,
        null,
        0,
    );
    try std.testing.expect(common.ERR_isError(cSize) == 0);
    try std.testing.expect(cSize > 0);
    try std.testing.expect(cSize < src.len); // Huffman must shrink biased input
}

test "HUF_compress4X_repeat round-trip — output < input" {
    var src: [4096]u8 = undefined;
    make3cSample(&src);

    var out: [HUF_COMPRESSBOUND(src.len)]u8 = undefined;
    var wksp: [HUF_WORKSPACE_SIZE_U64]u64 align(8) = undefined;
    const cSize = HUF_compress4X_repeat(
        &out,
        out.len,
        &src,
        src.len,
        255,
        HUF_TABLELOG_DEFAULT,
        @ptrCast(&wksp),
        @sizeOf(@TypeOf(wksp)),
        null,
        null,
        0,
    );
    try std.testing.expect(common.ERR_isError(cSize) == 0);
    try std.testing.expect(cSize > 0);
    try std.testing.expect(cSize < src.len);
    // Output must include the jump table (6 bytes) + table header (>=1 byte) + ≥4 stream bytes.
    try std.testing.expect(cSize > 6);
}

test "HUF_compress1X_repeat output is deterministic (xxh64)" {
    // Bit-exactness sanity: feeding the same input must yield the same bytes.
    // If the implementation is deterministic, two runs produce identical output
    // and identical xxhash. We check both the raw bytes and the hash.
    const xxhash = @import("xxhash.zig");

    var src: [2048]u8 = undefined;
    make3cSample(&src);

    var out_a: [HUF_COMPRESSBOUND(src.len)]u8 = undefined;
    var out_b: [HUF_COMPRESSBOUND(src.len)]u8 = undefined;
    var wksp_a: [HUF_WORKSPACE_SIZE_U64]u64 align(8) = undefined;
    var wksp_b: [HUF_WORKSPACE_SIZE_U64]u64 align(8) = undefined;

    const a = HUF_compress1X_repeat(&out_a, out_a.len, &src, src.len, 0, 0, @ptrCast(&wksp_a), @sizeOf(@TypeOf(wksp_a)), null, null, 0);
    const b = HUF_compress1X_repeat(&out_b, out_b.len, &src, src.len, 0, 0, @ptrCast(&wksp_b), @sizeOf(@TypeOf(wksp_b)), null, null, 0);
    try std.testing.expectEqual(a, b);
    try std.testing.expect(a > 0);
    try std.testing.expectEqualSlices(u8, out_a[0..a], out_b[0..b]);

    const ha = xxhash.ZSTD_XXH64(&out_a, a, 0);
    const hb = xxhash.ZSTD_XXH64(&out_b, b, 0);
    try std.testing.expectEqual(ha, hb);
}

test "HUF_compress1X_repeat — rle path for single-symbol input" {
    var src: [4096]u8 = @splat(@as(u8, 'Z'));
    var out: [HUF_COMPRESSBOUND(src.len)]u8 = undefined;
    var wksp: [HUF_WORKSPACE_SIZE_U64]u64 align(8) = undefined;
    const r = HUF_compress1X_repeat(&out, out.len, &src, src.len, 0, 0, @ptrCast(&wksp), @sizeOf(@TypeOf(wksp)), null, null, 0);
    try std.testing.expectEqual(@as(usize, 1), r);
    try std.testing.expectEqual(@as(u8, 'Z'), out[0]);
}

test "HUF_compress1X_repeat — empty / dstSize 0 — zero" {
    var wksp: [HUF_WORKSPACE_SIZE_U64]u64 align(8) = undefined;
    var out: [32]u8 = undefined;
    const src = [_]u8{ 1, 2, 3 };
    // srcSize == 0 → 0
    try std.testing.expectEqual(
        @as(usize, 0),
        HUF_compress1X_repeat(&out, out.len, &src, 0, 0, 0, @ptrCast(&wksp), @sizeOf(@TypeOf(wksp)), null, null, 0),
    );
    // dstSize == 0 → 0
    try std.testing.expectEqual(
        @as(usize, 0),
        HUF_compress1X_repeat(&out, 0, &src, src.len, 0, 0, @ptrCast(&wksp), @sizeOf(@TypeOf(wksp)), null, null, 0),
    );
}

test "HUF_compress1X_repeat — repeat state transitions none→none on first call" {
    var src: [4096]u8 = undefined;
    make3cSample(&src);

    var out: [HUF_COMPRESSBOUND(src.len)]u8 = undefined;
    var wksp: [HUF_WORKSPACE_SIZE_U64]u64 align(8) = undefined;
    var savedTable: [HUF_SYMBOLVALUE_MAX + 2]HUF_CElt = [_]HUF_CElt{0} ** (HUF_SYMBOLVALUE_MAX + 2);
    var rep: HUF_repeat = .HUF_repeat_none;

    const cSize = HUF_compress1X_repeat(
        &out,
        out.len,
        &src,
        src.len,
        0,
        0,
        @ptrCast(&wksp),
        @sizeOf(@TypeOf(wksp)),
        &savedTable,
        &rep,
        0,
    );
    try std.testing.expect(common.ERR_isError(cSize) == 0);
    try std.testing.expect(cSize > 0);
    try std.testing.expect(cSize < src.len);
    // After a fresh build, upstream always sets repeat = HUF_repeat_none.
    try std.testing.expectEqual(HUF_repeat.HUF_repeat_none, rep);

    // savedTable must now hold a valid CTable (header has tableLog ≤ MAX).
    const hdr = HUF_readCTableHeader(&savedTable);
    try std.testing.expect(hdr.tableLog >= 1);
    try std.testing.expect(hdr.tableLog <= HUF_TABLELOG_MAX);
}

test "HUF_compress4X_repeat — uncompressible when below 12 bytes" {
    var wksp: [HUF_WORKSPACE_SIZE_U64]u64 align(8) = undefined;
    var out: [128]u8 = undefined;
    const src = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 }; // 8 bytes
    const r = HUF_compress4X_repeat(&out, out.len, &src, src.len, 0, 0, @ptrCast(&wksp), @sizeOf(@TypeOf(wksp)), null, null, 0);
    // HUF_compress4X_usingCTable_internal bails when srcSize < 12; that trips
    // the cSize==0 branch in HUF_compressCTable_internal — net output = 0.
    try std.testing.expectEqual(@as(usize, 0), r);
}
