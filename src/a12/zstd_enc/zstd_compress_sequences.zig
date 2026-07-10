// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/compress/zstd_compress_sequences.c (slice 4b).
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// Public C-ABI entry points (via `pub export fn`):
//   ZSTD_buildCTable, ZSTD_encodeSequences, ZSTD_fseBitCost,
//   ZSTD_crossEntropyCost, ZSTD_selectEncodingType.
//
// Also exports types/consts "closest to home" for sequence encoding:
//   SeqDef (extern struct mirroring zstd_compress_internal.h SeqDef),
//   ZSTD_DefaultPolicy_e,
//   MaxML/MaxLL/MaxOff/MaxSeq/MLFSELog/LLFSELog/OffFSELog/MaxFSELog,
//   LL_bits[], ML_bits[], MINMATCH, STREAM_ACCUMULATOR_MIN_32/64,
//   FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32 helper,
//   ZSTD_BuildCTableWksp (extern struct).
//
// SymbolEncodingType_e and ZSTD_strategy live in zstd_compress_literals.zig
// (set_basic/rle/compressed/repeat). We re-import them here.

const std = @import("std");
const common = @import("zstd_common.zig");
const fse = @import("fse_compress.zig");
const lits = @import("zstd_compress_literals.zig");

const zstdError = common.zstdError;

// -------------------------------------------------------------------------
//  Re-exports from literals module (shared enums)
// -------------------------------------------------------------------------
pub const SymbolEncodingType_e = lits.SymbolEncodingType_e;
pub const set_basic = lits.set_basic;
pub const set_rle = lits.set_rle;
pub const set_compressed = lits.set_compressed;
pub const set_repeat = lits.set_repeat;

pub const ZSTD_strategy = lits.ZSTD_strategy;

// -------------------------------------------------------------------------
//  Shared constants — zstd_internal.h. Kept here (central-feeling place).
// -------------------------------------------------------------------------
pub const MINMATCH: c_uint = 3;
pub const MaxLL: c_uint = 35;
pub const MaxML: c_uint = 52;
pub const MaxOff: c_uint = 31;
pub const MaxSeq: c_uint = MaxML; // MAX(MaxLL, MaxML); MaxML > MaxLL
pub const MLFSELog: c_uint = 9;
pub const LLFSELog: c_uint = 9;
pub const OffFSELog: c_uint = 8;
pub const MaxFSELog: c_uint = MLFSELog; // MAX(MLFSELog, LLFSELog, OffFSELog)

pub const STREAM_ACCUMULATOR_MIN_32: c_uint = 25;
pub const STREAM_ACCUMULATOR_MIN_64: c_uint = 57;
// 64-bit target assumption (this port targets 64-bit Zig only, matching the
// rest of the encoder's bit-stream assumptions in fse_compress.zig).
pub const STREAM_ACCUMULATOR_MIN: c_uint = STREAM_ACCUMULATOR_MIN_64;

// Upstream: static const U8 LL_bits[MaxLL+1].
pub const LL_bits = [_]u8{
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 3, 3,
    4, 6, 7, 8, 9, 10, 11, 12,
    13, 14, 15, 16,
};

// Upstream: static const U8 ML_bits[MaxML+1].
pub const ML_bits = [_]u8{
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 3, 3,
    4, 4, 5, 7, 8, 9, 10, 11,
    12, 13, 14, 15, 16,
};

// -------------------------------------------------------------------------
//  SeqDef — mirrors zstd_compress_internal.h.
// -------------------------------------------------------------------------
pub const SeqDef = extern struct {
    offBase: u32, // offBase == Offset + ZSTD_REP_NUM, or repcode 1,2,3
    litLength: u16,
    mlBase: u16, // mlBase == matchLength - MINMATCH
};

// -------------------------------------------------------------------------
//  ZSTD_DefaultPolicy_e — header enum.
// -------------------------------------------------------------------------
pub const ZSTD_DefaultPolicy_e = enum(c_int) {
    ZSTD_defaultDisallowed = 0,
    ZSTD_defaultAllowed = 1,
};
pub const ZSTD_defaultDisallowed = ZSTD_DefaultPolicy_e.ZSTD_defaultDisallowed;
pub const ZSTD_defaultAllowed = ZSTD_DefaultPolicy_e.ZSTD_defaultAllowed;

// -------------------------------------------------------------------------
//  FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32 — from fse.h
// -------------------------------------------------------------------------
pub fn FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32(maxSymbolValue: usize, tableLog: usize) usize {
    return ((maxSymbolValue + 2) + (@as(usize, 1) << @intCast(tableLog))) / 2 + @sizeOf(u64) / @sizeOf(u32);
}

// -------------------------------------------------------------------------
//  ZSTD_BuildCTableWksp — sized for max (MaxSeq, MaxFSELog).
// -------------------------------------------------------------------------
pub const ZSTD_BuildCTableWksp_norm_len: usize = MaxSeq + 1;
pub const ZSTD_BuildCTableWksp_wksp_len: usize =
    FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32(MaxSeq, MaxFSELog);

pub const ZSTD_BuildCTableWksp = extern struct {
    norm: [ZSTD_BuildCTableWksp_norm_len]i16,
    wksp: [ZSTD_BuildCTableWksp_wksp_len]u32,
};

// -------------------------------------------------------------------------
//  FSE_NCOUNTBOUND — fse.h
// -------------------------------------------------------------------------
pub const FSE_NCOUNTBOUND: usize = 512;

// -------------------------------------------------------------------------
//  kInverseProbabilityLog256 — static table.
// -------------------------------------------------------------------------
const kInverseProbabilityLog256 = [256]c_uint{
    0,    2048, 1792, 1642, 1536, 1453, 1386, 1329, 1280, 1236, 1197, 1162,
    1130, 1100, 1073, 1047, 1024, 1001, 980,  960,  941,  923,  906,  889,
    874,  859,  844,  830,  817,  804,  791,  779,  768,  756,  745,  734,
    724,  714,  704,  694,  685,  676,  667,  658,  650,  642,  633,  626,
    618,  610,  603,  595,  588,  581,  574,  567,  561,  554,  548,  542,
    535,  529,  523,  517,  512,  506,  500,  495,  489,  484,  478,  473,
    468,  463,  458,  453,  448,  443,  438,  434,  429,  424,  420,  415,
    411,  407,  402,  398,  394,  390,  386,  382,  377,  373,  370,  366,
    362,  358,  354,  350,  347,  343,  339,  336,  332,  329,  325,  322,
    318,  315,  311,  308,  305,  302,  298,  295,  292,  289,  286,  282,
    279,  276,  273,  270,  267,  264,  261,  258,  256,  253,  250,  247,
    244,  241,  239,  236,  233,  230,  228,  225,  222,  220,  217,  215,
    212,  209,  207,  204,  202,  199,  197,  194,  192,  190,  187,  185,
    182,  180,  178,  175,  173,  171,  168,  166,  164,  162,  159,  157,
    155,  153,  151,  149,  146,  144,  142,  140,  138,  136,  134,  132,
    130,  128,  126,  123,  121,  119,  117,  115,  114,  112,  110,  108,
    106,  104,  102,  100,  98,   96,   94,   93,   91,   89,   87,   85,
    83,   82,   80,   78,   76,   74,   73,   71,   69,   67,   66,   64,
    62,   61,   59,   57,   55,   54,   52,   50,   49,   47,   46,   44,
    42,   41,   39,   37,   36,   34,   33,   31,   30,   28,   26,   25,
    23,   22,   20,   19,   17,   16,   14,   13,   11,   10,   8,    7,
    5,    4,    2,    1,
};

// -------------------------------------------------------------------------
//  ZSTD_getFSEMaxSymbolValue — read the second u16 of the CTable header.
// -------------------------------------------------------------------------
fn ZSTD_getFSEMaxSymbolValue(ctable: [*]const fse.FSE_CTable) c_uint {
    const bytes: [*]const u8 = @ptrCast(ctable);
    const hdr: *const u16 = @ptrCast(@alignCast(bytes + @sizeOf(u16)));
    return hdr.*;
}

// -------------------------------------------------------------------------
//  ZSTD_useLowProbCount — heuristic mirroring upstream.
// -------------------------------------------------------------------------
fn ZSTD_useLowProbCount(nbSeq: usize) c_uint {
    return @intFromBool(nbSeq >= 2048);
}

// -------------------------------------------------------------------------
//  ZSTD_NCountCost — cost in bytes of encoding the normalized count header.
// -------------------------------------------------------------------------
fn ZSTD_NCountCost(
    count: [*]const c_uint,
    max: c_uint,
    nbSeq: usize,
    FSELog: c_uint,
) usize {
    var wksp: [FSE_NCOUNTBOUND]u8 = undefined;
    var norm: [MaxSeq + 1]i16 = undefined;
    const tableLog: c_uint = fse.FSE_optimalTableLog(FSELog, nbSeq, max);
    const nerr = fse.FSE_normalizeCount(&norm, tableLog, count, nbSeq, max, ZSTD_useLowProbCount(nbSeq));
    if (common.ERR_isError(nerr) != 0) return nerr;
    return fse.FSE_writeNCount(&wksp, wksp.len, &norm, max, tableLog);
}

// -------------------------------------------------------------------------
//  ZSTD_entropyCost — cost in bits of encoding count using entropy bound.
//  Public C-ABI (upstream is `static`, but slice 5 will call it across files;
//  we expose it the same way other compute helpers are exposed.)
// -------------------------------------------------------------------------
pub export fn ZSTD_entropyCost(
    count: [*]const c_uint,
    max: c_uint,
    total: usize,
) usize {
    var cost: c_uint = 0;
    std.debug.assert(total > 0);
    var s: c_uint = 0;
    while (s <= max) : (s += 1) {
        var norm: c_uint = @intCast((256 * @as(usize, count[s])) / total);
        if (count[s] != 0 and norm == 0) norm = 1;
        std.debug.assert(count[s] < total);
        cost += count[s] * kInverseProbabilityLog256[norm];
    }
    return cost >> 8;
}

// -------------------------------------------------------------------------
//  ZSTD_fseBitCost — cost in bits of encoding `count` via `ctable`.
// -------------------------------------------------------------------------
pub export fn ZSTD_fseBitCost(
    ctable: [*]const fse.FSE_CTable,
    count: [*]const c_uint,
    max: c_uint,
) usize {
    const kAccuracyLog: u32 = 8;
    var cost: usize = 0;
    var cstate: fse.FSE_CState_t = undefined;
    fse.fseInitCState(&cstate, ctable);
    if (ZSTD_getFSEMaxSymbolValue(ctable) < max) {
        return zstdError(.generic_err);
    }
    var s: c_uint = 0;
    while (s <= max) : (s += 1) {
        const tableLog: u32 = cstate.stateLog;
        const badCost: u32 = (tableLog + 1) << @intCast(kAccuracyLog);
        const bitCost: u32 = fse.FSE_bitCost(cstate.symbolTT, tableLog, s, kAccuracyLog);
        if (count[s] == 0) continue;
        if (bitCost >= badCost) return zstdError(.generic_err);
        cost += @as(usize, count[s]) * @as(usize, bitCost);
    }
    return cost >> @intCast(kAccuracyLog);
}

// -------------------------------------------------------------------------
//  ZSTD_crossEntropyCost — bits for encoding `count` given tabled `norm`.
// -------------------------------------------------------------------------
pub export fn ZSTD_crossEntropyCost(
    norm: [*]const i16,
    accuracyLog: c_uint,
    count: [*]const c_uint,
    max: c_uint,
) usize {
    const shift: u5 = @intCast(8 - accuracyLog);
    var cost: usize = 0;
    std.debug.assert(accuracyLog <= 8);
    var s: c_uint = 0;
    while (s <= max) : (s += 1) {
        const normAcc: c_uint = if (norm[s] != -1) @intCast(norm[s]) else 1;
        const norm256: c_uint = normAcc << shift;
        std.debug.assert(norm256 > 0);
        std.debug.assert(norm256 < 256);
        cost += @as(usize, count[s]) * @as(usize, kInverseProbabilityLog256[norm256]);
    }
    return cost >> 8;
}

// -------------------------------------------------------------------------
//  ZSTD_selectEncodingType — pick table encoding for one of LL/ML/OF streams.
// -------------------------------------------------------------------------
pub export fn ZSTD_selectEncodingType(
    repeatMode: *fse.FSE_repeat,
    count: [*]const c_uint,
    max: c_uint,
    mostFrequent: usize,
    nbSeq: usize,
    FSELog: c_uint,
    prevCTable: [*]const fse.FSE_CTable,
    defaultNorm: [*]const i16,
    defaultNormLog: u32,
    isDefaultAllowed: ZSTD_DefaultPolicy_e,
    strategy: ZSTD_strategy,
) SymbolEncodingType_e {
    const allow_default: bool = (@intFromEnum(isDefaultAllowed) != 0);
    if (mostFrequent == nbSeq) {
        repeatMode.* = .FSE_repeat_none;
        if (allow_default and nbSeq <= 2) {
            // Prefer set_basic over set_rle when ≤2 symbols.
            return set_basic;
        }
        return set_rle;
    }
    const s_int: c_int = @intFromEnum(strategy);
    if (s_int < @intFromEnum(ZSTD_strategy.ZSTD_lazy)) {
        if (allow_default) {
            const staticFse_nbSeq_max: usize = 1000;
            const mult: usize = @intCast(10 - s_int);
            const baseLog: u6 = 3;
            const dynamicFse_nbSeq_min: usize =
                ((@as(usize, 1) << @intCast(defaultNormLog)) * mult) >> baseLog;
            std.debug.assert(defaultNormLog >= 5 and defaultNormLog <= 6);
            std.debug.assert(mult <= 9 and mult >= 7);
            if (repeatMode.* == .FSE_repeat_valid and nbSeq < staticFse_nbSeq_max) {
                return set_repeat;
            }
            if (nbSeq < dynamicFse_nbSeq_min or
                mostFrequent < (nbSeq >> @intCast(defaultNormLog - 1)))
            {
                // The format allows default tables to be repeated, but it isn't useful.
                repeatMode.* = .FSE_repeat_none;
                return set_basic;
            }
        }
    } else {
        const basicCost: usize = if (allow_default)
            ZSTD_crossEntropyCost(defaultNorm, defaultNormLog, count, max)
        else
            zstdError(.generic_err);
        const repeatCost: usize = if (repeatMode.* != .FSE_repeat_none)
            ZSTD_fseBitCost(prevCTable, count, max)
        else
            zstdError(.generic_err);
        const NCountCost: usize = ZSTD_NCountCost(count, max, nbSeq, FSELog);
        const compressedCost: usize = (NCountCost << 3) + ZSTD_entropyCost(count, max, nbSeq);

        if (allow_default) {
            std.debug.assert(common.ERR_isError(basicCost) == 0);
            std.debug.assert(!(repeatMode.* == .FSE_repeat_valid and common.ERR_isError(repeatCost) != 0));
        }
        std.debug.assert(common.ERR_isError(NCountCost) == 0);
        if (basicCost <= repeatCost and basicCost <= compressedCost) {
            std.debug.assert(allow_default);
            repeatMode.* = .FSE_repeat_none;
            return set_basic;
        }
        if (repeatCost <= compressedCost) {
            std.debug.assert(common.ERR_isError(repeatCost) == 0);
            return set_repeat;
        }
        std.debug.assert(compressedCost < basicCost and compressedCost < repeatCost);
    }
    repeatMode.* = .FSE_repeat_check;
    return set_compressed;
}

// -------------------------------------------------------------------------
//  ZSTD_buildCTable — build next encoding table from chosen type.
// -------------------------------------------------------------------------
pub export fn ZSTD_buildCTable(
    dst: ?*anyopaque,
    dstCapacity: usize,
    nextCTable: [*]fse.FSE_CTable,
    FSELog: u32,
    kind: SymbolEncodingType_e,
    count: [*]c_uint,
    max: u32,
    codeTable: [*]const u8,
    nbSeq: usize,
    defaultNorm: [*]const i16,
    defaultNormLog: u32,
    defaultMax: u32,
    prevCTable: [*]const fse.FSE_CTable,
    prevCTableSize: usize,
    entropyWorkspace: ?*anyopaque,
    entropyWorkspaceSize: usize,
) usize {
    switch (kind) {
        .set_rle => {
            const err = fse.FSE_buildCTable_rle(nextCTable, @intCast(max));
            if (common.ERR_isError(err) != 0) return err;
            if (dstCapacity == 0) return zstdError(.dstSize_tooSmall);
            const op: [*]u8 = @ptrCast(dst.?);
            op[0] = codeTable[nbSeq - 1];
            return 1;
        },
        .set_repeat => {
            const dst_bytes: [*]u8 = @ptrCast(nextCTable);
            const src_bytes: [*]const u8 = @ptrCast(prevCTable);
            @memcpy(dst_bytes[0..prevCTableSize], src_bytes[0..prevCTableSize]);
            return 0;
        },
        .set_basic => {
            const err = fse.FSE_buildCTable_wksp(
                nextCTable,
                defaultNorm,
                defaultMax,
                defaultNormLog,
                entropyWorkspace,
                entropyWorkspaceSize,
            );
            if (common.ERR_isError(err) != 0) return err;
            return 0;
        },
        .set_compressed => {
            std.debug.assert(entropyWorkspaceSize >= @sizeOf(ZSTD_BuildCTableWksp));
            const wksp: *ZSTD_BuildCTableWksp = @ptrCast(@alignCast(entropyWorkspace.?));
            var nbSeq_1: usize = nbSeq;
            const tableLog: u32 = fse.FSE_optimalTableLog(FSELog, nbSeq, max);
            if (count[codeTable[nbSeq - 1]] > 1) {
                count[codeTable[nbSeq - 1]] -= 1;
                nbSeq_1 -= 1;
            }
            std.debug.assert(nbSeq_1 > 1);
            const norm_err = fse.FSE_normalizeCount(
                &wksp.norm,
                tableLog,
                count,
                nbSeq_1,
                max,
                ZSTD_useLowProbCount(nbSeq_1),
            );
            if (common.ERR_isError(norm_err) != 0) return norm_err;
            const op: [*]u8 = @ptrCast(dst.?);
            const NCountSize = fse.FSE_writeNCount(op, dstCapacity, &wksp.norm, max, tableLog);
            if (common.ERR_isError(NCountSize) != 0) return NCountSize;
            const build_err = fse.FSE_buildCTable_wksp(
                nextCTable,
                &wksp.norm,
                max,
                tableLog,
                &wksp.wksp,
                @sizeOf(@TypeOf(wksp.wksp)),
            );
            if (common.ERR_isError(build_err) != 0) return build_err;
            return NCountSize;
        },
    }
}

// -------------------------------------------------------------------------
//  ZSTD_encodeSequences_body — 64-bit only (we don't target 32-bit).
// -------------------------------------------------------------------------
fn encodeSequencesBody(
    dst: ?*anyopaque,
    dstCapacity: usize,
    CTable_MatchLength: [*]const fse.FSE_CTable,
    mlCodeTable: [*]const u8,
    CTable_OffsetBits: [*]const fse.FSE_CTable,
    ofCodeTable: [*]const u8,
    CTable_LitLength: [*]const fse.FSE_CTable,
    llCodeTable: [*]const u8,
    sequences: [*]const SeqDef,
    nbSeq: usize,
    longOffsets: c_int,
) usize {
    var blockStream: fse.BIT_CStream_t = undefined;
    var stateMatchLength: fse.FSE_CState_t = undefined;
    var stateOffsetBits: fse.FSE_CState_t = undefined;
    var stateLitLength: fse.FSE_CState_t = undefined;

    const d: [*]u8 = @ptrCast(dst.?);
    const init_err = fse.bitInitCStream(&blockStream, d, dstCapacity);
    if (common.ERR_isError(init_err) != 0) return zstdError(.dstSize_tooSmall);

    // First (tail) symbols.
    fse.fseInitCState2(&stateMatchLength, CTable_MatchLength, mlCodeTable[nbSeq - 1]);
    fse.fseInitCState2(&stateOffsetBits, CTable_OffsetBits, ofCodeTable[nbSeq - 1]);
    fse.fseInitCState2(&stateLitLength, CTable_LitLength, llCodeTable[nbSeq - 1]);

    fse.bitAddBits(&blockStream, sequences[nbSeq - 1].litLength, LL_bits[llCodeTable[nbSeq - 1]]);
    fse.bitAddBits(&blockStream, sequences[nbSeq - 1].mlBase, ML_bits[mlCodeTable[nbSeq - 1]]);
    if (longOffsets != 0) {
        const ofBits: u32 = ofCodeTable[nbSeq - 1];
        const clampMin: u32 = STREAM_ACCUMULATOR_MIN - 1;
        const clamped: u32 = if (ofBits < clampMin) ofBits else clampMin;
        const extraBits: u32 = ofBits - clamped;
        if (extraBits != 0) {
            fse.bitAddBits(&blockStream, sequences[nbSeq - 1].offBase, extraBits);
            fse.bitFlushBits(&blockStream);
        }
        fse.bitAddBits(
            &blockStream,
            @as(u64, sequences[nbSeq - 1].offBase) >> @intCast(extraBits),
            ofBits - extraBits,
        );
    } else {
        fse.bitAddBits(&blockStream, sequences[nbSeq - 1].offBase, ofCodeTable[nbSeq - 1]);
    }
    fse.bitFlushBits(&blockStream);

    // Remaining sequences, encoded in reverse. Upstream uses `for (n=nbSeq-2; n<nbSeq; n--)`
    // which relies on size_t wrap; we do the explicit reverse-range version.
    if (nbSeq >= 2) {
        var n: usize = nbSeq - 2;
        while (true) {
            const llCode: u8 = llCodeTable[n];
            const ofCode: u8 = ofCodeTable[n];
            const mlCode: u8 = mlCodeTable[n];
            const llBits: u32 = LL_bits[llCode];
            const ofBits: u32 = ofCode;
            const mlBits: u32 = ML_bits[mlCode];

            fse.fseEncodeSymbol(&blockStream, &stateOffsetBits, ofCode);
            fse.fseEncodeSymbol(&blockStream, &stateMatchLength, mlCode);
            fse.fseEncodeSymbol(&blockStream, &stateLitLength, llCode);
            if (ofBits + mlBits + llBits >= 64 - 7 - (LLFSELog + MLFSELog + OffFSELog))
                fse.bitFlushBits(&blockStream);
            fse.bitAddBits(&blockStream, sequences[n].litLength, llBits);
            fse.bitAddBits(&blockStream, sequences[n].mlBase, mlBits);
            if (ofBits + mlBits + llBits > 56) fse.bitFlushBits(&blockStream);
            if (longOffsets != 0) {
                const clampMin: u32 = STREAM_ACCUMULATOR_MIN - 1;
                const clamped: u32 = if (ofBits < clampMin) ofBits else clampMin;
                const extraBits: u32 = ofBits - clamped;
                if (extraBits != 0) {
                    fse.bitAddBits(&blockStream, sequences[n].offBase, extraBits);
                    fse.bitFlushBits(&blockStream);
                }
                fse.bitAddBits(
                    &blockStream,
                    @as(u64, sequences[n].offBase) >> @intCast(extraBits),
                    ofBits - extraBits,
                );
            } else {
                fse.bitAddBits(&blockStream, sequences[n].offBase, ofBits);
            }
            fse.bitFlushBits(&blockStream);
            if (n == 0) break;
            n -= 1;
        }
    }

    fse.fseFlushCState(&blockStream, &stateMatchLength);
    fse.fseFlushCState(&blockStream, &stateOffsetBits);
    fse.fseFlushCState(&blockStream, &stateLitLength);

    const streamSize = fse.bitCloseCStream(&blockStream);
    if (streamSize == 0) return zstdError(.dstSize_tooSmall);
    return streamSize;
}

// -------------------------------------------------------------------------
//  ZSTD_encodeSequences — public entry point.
// -------------------------------------------------------------------------
pub export fn ZSTD_encodeSequences(
    dst: ?*anyopaque,
    dstCapacity: usize,
    CTable_MatchLength: [*]const fse.FSE_CTable,
    mlCodeTable: [*]const u8,
    CTable_OffsetBits: [*]const fse.FSE_CTable,
    ofCodeTable: [*]const u8,
    CTable_LitLength: [*]const fse.FSE_CTable,
    llCodeTable: [*]const u8,
    sequences: [*]const SeqDef,
    nbSeq: usize,
    longOffsets: c_int,
    bmi2: c_int,
) usize {
    _ = bmi2; // pure-Zig build does not carve a BMI2-specialised variant
    return encodeSequencesBody(
        dst,
        dstCapacity,
        CTable_MatchLength,
        mlCodeTable,
        CTable_OffsetBits,
        ofCodeTable,
        CTable_LitLength,
        llCodeTable,
        sequences,
        nbSeq,
        longOffsets,
    );
}

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------
test "ZSTD_selectEncodingType — set_rle for single-symbol histogram" {
    // Single symbol dominates: mostFrequent == nbSeq, allow_default=1, nbSeq > 2.
    var counts = [_]c_uint{0} ** (MaxSeq + 1);
    counts[5] = 50; // all 50 sequences map to symbol 5
    var rep: fse.FSE_repeat = .FSE_repeat_valid; // will be forced to none
    const defaultNorm: [MaxSeq + 1]i16 = .{0} ** (MaxSeq + 1);
    var dummyPrev: [1024]fse.FSE_CTable = undefined;
    const kind = ZSTD_selectEncodingType(
        &rep,
        &counts,
        5,
        50, // mostFrequent == nbSeq
        50,
        LLFSELog,
        &dummyPrev,
        &defaultNorm,
        6,
        ZSTD_defaultAllowed,
        .ZSTD_fast,
    );
    try std.testing.expectEqual(SymbolEncodingType_e.set_rle, kind);
    try std.testing.expectEqual(fse.FSE_repeat.FSE_repeat_none, rep);
}

test "ZSTD_selectEncodingType — set_basic for ≤2 seq when default allowed" {
    var counts = [_]c_uint{0} ** (MaxSeq + 1);
    counts[3] = 2;
    var rep: fse.FSE_repeat = .FSE_repeat_none;
    const defaultNorm: [MaxSeq + 1]i16 = .{0} ** (MaxSeq + 1);
    var dummyPrev: [1024]fse.FSE_CTable = undefined;
    const kind = ZSTD_selectEncodingType(
        &rep,
        &counts,
        3,
        2, // mostFrequent == nbSeq == 2
        2,
        LLFSELog,
        &dummyPrev,
        &defaultNorm,
        6,
        ZSTD_defaultAllowed,
        .ZSTD_fast,
    );
    try std.testing.expectEqual(SymbolEncodingType_e.set_basic, kind);
    try std.testing.expectEqual(fse.FSE_repeat.FSE_repeat_none, rep);
}

test "SeqDef layout — 8 bytes, matches upstream" {
    // offBase u32 + litLength u16 + mlBase u16 = 8 bytes.
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(SeqDef));
}

test "LL_bits/ML_bits length sanity" {
    try std.testing.expectEqual(MaxLL + 1, LL_bits.len);
    try std.testing.expectEqual(MaxML + 1, ML_bits.len);
    // Spot-check a few upstream values (from zstd_internal.h):
    try std.testing.expectEqual(@as(u8, 16), LL_bits[35]); // last
    try std.testing.expectEqual(@as(u8, 16), ML_bits[52]); // last
    try std.testing.expectEqual(@as(u8, 0), LL_bits[0]);
    try std.testing.expectEqual(@as(u8, 0), ML_bits[31]);
}

test "ZSTD_entropyCost — uniform distribution has non-zero cost" {
    // Uniform 4-symbol distribution of 64 total: each count=16.
    // norm = 256*16/64 = 64 (nonzero), kInverseProbabilityLog256[64]=512.
    // cost per symbol = 16 * 512 = 8192; total = 4 * 8192 = 32768; >>8 = 128.
    var counts = [_]c_uint{ 16, 16, 16, 16 };
    const cost = ZSTD_entropyCost(&counts, 3, 64);
    try std.testing.expectEqual(@as(usize, 128), cost);
}

test "ZSTD_crossEntropyCost — matches entropy for matched norm" {
    // norm256 = normAcc << (8 - accuracyLog). With accuracyLog=8, shift=0, so
    // normAcc is directly the 256-scaled probability. Use uniform norm=64 for
    // 4 symbols and count={16,16,16,16}; expected = 16*512*4 >> 8 = 128 (matches
    // entropyCost above).
    var norm = [_]i16{ 64, 64, 64, 64 };
    var counts = [_]c_uint{ 16, 16, 16, 16 };
    const cost = ZSTD_crossEntropyCost(&norm, 8, &counts, 3);
    try std.testing.expectEqual(@as(usize, 128), cost);
}

test "FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32 basic" {
    // Upstream macro: ((maxSV + 2) + (1<<tableLog)) / 2 + 2 (for the U64 tail).
    const v = FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32(52, 9);
    // (54 + 512) / 2 + 2 = 283 + 2 = 285
    try std.testing.expectEqual(@as(usize, 285), v);
}
