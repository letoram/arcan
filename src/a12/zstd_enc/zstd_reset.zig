// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7's sizeof / estimate / reset-matchState helpers.
// Slice 5c of the zstd encoder port.
//
// Source line ranges from /tmp/raw_zstd_compress.zig:
//   23794..23962    ZSTD_estimateCCtxSize / CStream / CDict (public)
//   30696..30903    ZSTD_window_{clear,isEmpty,hasExtDict,init}
//   31381..31396    ZSTD_reset_compressedBlockState
//   32697..32786    ZSTD_sizeof_matchState,
//                   ZSTD_estimateCCtxSize_usingCCtxParams_internal,
//                   ZSTD_maxNbSeq
//   32787..32816    ZSTD_estimateCCtxSize_internal, CStreamSize_internal
//   32832..32864    ZSTD_invalidateMatchState, ZSTD_bitmix, advanceHashSalt
//   32866..32982    ZSTD_reset_matchState
//   32984..32992    ZSTD_indexTooCloseToMax / ZSTD_dictTooBig
//
// Everything else in the 32993..33386 range (ZSTD_resetCCtx_internal,
// ZSTD_resetCCtx_byAttachingCDict, ZSTD_resetCCtx_byCopyingCDict) is deferred
// to slice 5d — it depends on ldmState, extSeqBuf, seqStore reservation and
// the streaming buffer plumbing that slice 5c's CCtx layout can't express
// until slice 5d grows the struct_ZSTD_CCtx_s body to the upstream shape.
//
// Noise removed: translate-c's per-argument `var x = arg_x; _ = &x;` shells,
// `while (true) { if (!false) break; }` DEBUGLOG scaffolding, and the fat
// integer-ceremony `@as(usize, @bitCast(@as(c_uint, @truncate(...))))` casts
// around @sizeOf of structs (sizeof already returns usize in Zig).
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).

const std = @import("std");
const ms_mod = @import("zstd_match_state.zig");
const cwksp_mod = @import("zstd_cwksp.zig");
const cparams_mod = @import("zstd_cparams.zig");
const zstd_compress = @import("zstd_compress.zig");

// -------------------------------------------------------------------------
//  Type aliases
// -------------------------------------------------------------------------

pub const U32 = ms_mod.U32;
pub const U64 = ms_mod.U64;
pub const BYTE = ms_mod.BYTE;
pub const ZSTD_window_t = ms_mod.ZSTD_window_t;
pub const ZSTD_MatchState_t = ms_mod.ZSTD_MatchState_t;
pub const ZSTD_compressedBlockState_t = ms_mod.ZSTD_compressedBlockState_t;
pub const SeqDef = ms_mod.SeqDef;
pub const ZSTD_match_t = ms_mod.ZSTD_match_t;
pub const ZSTD_optimal_t = ms_mod.ZSTD_optimal_t;
pub const rawSeq = ms_mod.rawSeq;
pub const ZSTD_cwksp = cwksp_mod.ZSTD_cwksp;

pub const ZSTD_compressionParameters = zstd_compress.ZSTD_compressionParameters;
pub const ZSTD_CCtx_params = zstd_compress.ZSTD_CCtx_params;
pub const ldmParams_t = zstd_compress.ldmParams_t;
pub const ZSTD_ParamSwitch_e = zstd_compress.ZSTD_ParamSwitch_e;

pub const ZSTD_ps_auto = zstd_compress.ZSTD_ps_auto;
pub const ZSTD_ps_enable = zstd_compress.ZSTD_ps_enable;
pub const ZSTD_ps_disable = zstd_compress.ZSTD_ps_disable;
pub const ZSTD_bm_buffered = zstd_compress.ZSTD_bm_buffered;
pub const ZSTD_btopt = zstd_compress.ZSTD_btopt;
pub const ZSTD_btultra = zstd_compress.ZSTD_btultra;

const ZSTD_error_memory_allocation: c_int = 64;
const ZSTD_error_GENERIC: c_int = 1;

inline fn zerr(code: c_int) usize {
    return @bitCast(-@as(isize, code));
}

// -------------------------------------------------------------------------
//  Small bit helpers — port of lines 32850..32864
// -------------------------------------------------------------------------

pub inline fn ZSTD_rotateRight_U64(val: U64, count_in: U32) U64 {
    const cnt: u6 = @intCast(count_in & 63);
    return std.math.rotr(U64, val, cnt);
}

// Line 32850..32859.
pub fn ZSTD_bitmix(val_in: U64, len: U64) callconv(.c) U64 {
    var val = val_in;
    val ^= ZSTD_rotateRight_U64(val, 49) ^ ZSTD_rotateRight_U64(val, 24);
    val *%= 0x9FB21C651E98DF25; // 11507291218515648293
    val ^= (val >> 35) +% len;
    val *%= 0x9FB21C651E98DF25;
    return val ^ (val >> 28);
}

pub fn ZSTD_advanceHashSalt(ms: *ZSTD_MatchState_t) callconv(.c) void {
    ms.hashSalt = ZSTD_bitmix(ms.hashSalt, 8) ^ ZSTD_bitmix(@as(U64, ms.hashSaltEntropy), 4);
}

// -------------------------------------------------------------------------
//  Window helpers — lines 30696..30712, 30892..30902
// -------------------------------------------------------------------------

pub fn ZSTD_window_clear(window: *ZSTD_window_t) callconv(.c) void {
    const endT: usize = @intFromPtr(window.nextSrc) -% @intFromPtr(window.base);
    const end: U32 = @truncate(endT);
    window.lowLimit = end;
    window.dictLimit = end;
}

pub fn ZSTD_window_isEmpty(window: ZSTD_window_t) callconv(.c) U32 {
    const distance: usize = @intFromPtr(window.nextSrc) -% @intFromPtr(window.base);
    return @intFromBool(window.dictLimit == 2 and window.lowLimit == 2 and distance == 2);
}

pub fn ZSTD_window_hasExtDict(window: ZSTD_window_t) callconv(.c) U32 {
    return @intFromBool(window.lowLimit < window.dictLimit);
}

// Upstream: zeros the window, then seeds base/dictBase to a static 1-byte
// string so that the distance-from-base pointer arithmetic yields 2 (two
// past a synthetic origin, so that zero-value indices encode "none"). The
// magic " " string is read-only + byte-addressable — we use a module-local
// sentinel to match.
const kWindowSentinel: [1]BYTE = .{' '};

pub fn ZSTD_window_init(window: *ZSTD_window_t) callconv(.c) void {
    window.* = .{};
    window.base = &kWindowSentinel[0];
    window.dictBase = &kWindowSentinel[0];
    window.dictLimit = 2;
    window.lowLimit = 2;
    window.nextSrc = window.base + 2;
    window.nbOverflowCorrections = 0;
}

// -------------------------------------------------------------------------
//  Reset per-block entropy + repcodes — line 31381..31396
// -------------------------------------------------------------------------

pub const repStartValue: [3]U32 = .{ 1, 4, 8 };

pub export fn ZSTD_reset_compressedBlockState(bs: *ZSTD_compressedBlockState_t) void {
    var i: usize = 0;
    while (i < 3) : (i += 1) bs.rep[i] = repStartValue[i];
    bs.entropy.huf.repeatMode = .HUF_repeat_none;
    bs.entropy.fse.offcode_repeatMode = .FSE_repeat_none;
    bs.entropy.fse.matchlength_repeatMode = .FSE_repeat_none;
    bs.entropy.fse.litlength_repeatMode = .FSE_repeat_none;
}

// -------------------------------------------------------------------------
//  Resolve* helpers used by the estimators — lines 32157..32212
// -------------------------------------------------------------------------

pub fn ZSTD_rowMatchFinderSupported(strategy: c_uint) callconv(.c) c_int {
    return @intFromBool(
        strategy >= @as(c_uint, @bitCast(zstd_compress.ZSTD_greedy)) and
            strategy <= @as(c_uint, @bitCast(zstd_compress.ZSTD_lazy2)),
    );
}

pub fn ZSTD_rowMatchFinderUsed(strategy: c_uint, mode: ZSTD_ParamSwitch_e) callconv(.c) c_int {
    return @intFromBool(
        ZSTD_rowMatchFinderSupported(strategy) != 0 and
            mode == @as(c_uint, @bitCast(ZSTD_ps_enable)),
    );
}

// Port of line 32186..32192.
pub fn ZSTD_allocateChainTable(
    strategy: c_uint,
    useRowMatchFinder: ZSTD_ParamSwitch_e,
    forDDSDict: U32,
) callconv(.c) c_int {
    return @intFromBool(
        forDDSDict != 0 or
            (strategy != @as(c_uint, @bitCast(zstd_compress.ZSTD_fast)) and
                ZSTD_rowMatchFinderUsed(strategy, useRowMatchFinder) == 0),
    );
}

pub fn ZSTD_resolveMaxBlockSize(maxBlockSize: usize) callconv(.c) usize {
    if (maxBlockSize == 0) return 1 << 17;
    return maxBlockSize;
}

pub fn ZSTD_resolveRowMatchFinderMode(
    mode_in: ZSTD_ParamSwitch_e,
    cParams: *const ZSTD_compressionParameters,
) callconv(.c) ZSTD_ParamSwitch_e {
    if (mode_in != @as(c_uint, @bitCast(ZSTD_ps_auto))) return mode_in;
    if (ZSTD_rowMatchFinderSupported(cParams.strategy) == 0) {
        return @as(c_uint, @bitCast(ZSTD_ps_disable));
    }
    if (cParams.windowLog > 14) return @as(c_uint, @bitCast(ZSTD_ps_enable));
    return @as(c_uint, @bitCast(ZSTD_ps_disable));
}

// Line 31874..31878.
pub fn ZSTD_hasExtSeqProd(params: *const ZSTD_CCtx_params) callconv(.c) c_int {
    return @intFromBool(params.extSeqProdFunc != null);
}

// -------------------------------------------------------------------------
//  ZSTD_sizeof_matchState — line 32697..32726
// -------------------------------------------------------------------------

// Magic constants from upstream zstd_compress_internal.h:
const MaxLL: c_int = 35;
const MaxML: c_int = 52;
const MaxOff: c_int = 31;
const MaxLit: c_int = 1 << 8; // 256
const ZSTD_OPT_SIZE: c_int = (1 << 12) + 3;

pub fn ZSTD_sizeof_matchState(
    cParams: *const ZSTD_compressionParameters,
    useRowMatchFinder: ZSTD_ParamSwitch_e,
    enableDedicatedDictSearch: c_int,
    forCCtx: U32,
) callconv(.c) usize {
    const dds: U32 = @intFromBool(enableDedicatedDictSearch != 0 and forCCtx == 0);
    const chainSize: usize = if (ZSTD_allocateChainTable(cParams.strategy, useRowMatchFinder, dds) != 0)
        @as(usize, 1) << @intCast(cParams.chainLog)
    else
        0;
    const hSize: usize = @as(usize, 1) << @intCast(cParams.hashLog);
    const hashLog3: U32 = if (forCCtx != 0 and cParams.minMatch == 3)
        (if (cParams.windowLog > 17) 17 else cParams.windowLog)
    else
        0;
    const h3Size: usize = if (hashLog3 != 0) (@as(usize, 1) << @intCast(hashLog3)) else 0;
    const tableSpace: usize = (chainSize *% @sizeOf(U32)) +%
        (hSize *% @sizeOf(U32)) +%
        (h3Size *% @sizeOf(U32));

    const aa64 = cwksp_mod.ZSTD_cwksp_aligned64_alloc_size;
    const optPotentialSpace: usize =
        aa64(@as(usize, @intCast(MaxML + 1)) * @sizeOf(c_uint)) +%
        aa64(@as(usize, @intCast(MaxLL + 1)) * @sizeOf(c_uint)) +%
        aa64(@as(usize, @intCast(MaxOff + 1)) * @sizeOf(c_uint)) +%
        aa64(@as(usize, @intCast(MaxLit)) * @sizeOf(c_uint)) +%
        aa64(@as(usize, @intCast(ZSTD_OPT_SIZE)) * @sizeOf(ZSTD_match_t)) +%
        aa64(@as(usize, @intCast(ZSTD_OPT_SIZE)) * @sizeOf(ZSTD_optimal_t));

    const lazyAdditionalSpace: usize = if (ZSTD_rowMatchFinderUsed(cParams.strategy, useRowMatchFinder) != 0)
        aa64(hSize)
    else
        0;
    const optSpace: usize = if (forCCtx != 0 and cParams.strategy >= @as(c_uint, @bitCast(ZSTD_btopt)))
        optPotentialSpace
    else
        0;
    const slackSpace: usize = cwksp_mod.ZSTD_cwksp_slack_space_required();

    return tableSpace +% optSpace +% slackSpace +% lazyAdditionalSpace;
}

// -------------------------------------------------------------------------
//  ZSTD_maxNbSeq + LDM stubs — lines 32727..32736
// -------------------------------------------------------------------------

pub fn ZSTD_maxNbSeq(blockSize: usize, minMatch: c_uint, useSequenceProducer: c_int) callconv(.c) usize {
    const divider: U32 = if (minMatch == 3 or useSequenceProducer != 0) 3 else 4;
    return blockSize / divider;
}

// LDM getters are defined in lib/compress/zstd_ldm.c, not yet ported. They
// return the byte footprint of the LDM hash table / max LDM sequences.
// Upstream formulas (from zstd_ldm.c, lines 62 + 70 in 1.5.7):
//   getTableSize(p)         = (1u << p.hashLog) * sizeof(ldmEntry_t)
//                           + (1u << (p.hashLog - p.bucketSizeLog)) bytes
//   getMaxNbSeq(p, maxSize) = maxSize / p.minMatchLength
pub fn ZSTD_ldm_getTableSize(params: ldmParams_t) callconv(.c) usize {
    const ldmEntry_sz: usize = @sizeOf(ms_mod.ldmEntry_t);
    const numEntries: usize = @as(usize, 1) << @intCast(params.hashLog);
    const bucketOffsets: usize = @as(usize, 1) << @intCast(params.hashLog -% params.bucketSizeLog);
    return numEntries * ldmEntry_sz + bucketOffsets;
}

pub fn ZSTD_ldm_getMaxNbSeq(params: ldmParams_t, maxChunkSize: usize) callconv(.c) usize {
    if (params.minMatchLength == 0) return 0;
    return maxChunkSize / params.minMatchLength;
}

// -------------------------------------------------------------------------
//  ZSTD_estimateCCtxSize_usingCCtxParams_internal — line 32738..32786
// -------------------------------------------------------------------------

// tmpWorkspaceSize: upstream computes
//   MAX(HUF_WORKSPACE_SIZE,
//       ZSTD_MAX_HUF_HEADER_SIZE + (MAX(MaxLL, MaxML)+2)*sizeof(unsigned))
// where HUF_WORKSPACE_SIZE = 8208. In practice
//   8*1024 + 512 + sizeof(unsigned) * 54 = 8920 > 8208, so the MAX evaluates
// to the second branch.
inline fn tmpWorkspaceBytes() usize {
    const hufHeader: usize = (8 << 10) + 512;
    const mv: c_int = if (MaxLL > MaxML) MaxLL else MaxML;
    const candidate: usize = hufHeader + @sizeOf(c_uint) * @as(usize, @intCast(mv + 2));
    return if (candidate > 8208) candidate else 8208;
}

pub fn ZSTD_estimateCCtxSize_usingCCtxParams_internal(
    cParams: *const ZSTD_compressionParameters,
    ldmParams: *const ldmParams_t,
    isStatic: c_int,
    useRowMatchFinder: ZSTD_ParamSwitch_e,
    buffInSize: usize,
    buffOutSize: usize,
    pledgedSrcSize: U64,
    useSequenceProducer: c_int,
    maxBlockSize: usize,
) callconv(.c) usize {
    const oneShl: U64 = @as(U64, 1) << @intCast(cParams.windowLog);
    const effective: U64 = if (oneShl < pledgedSrcSize) oneShl else pledgedSrcSize;
    const windowSize: usize = @truncate(if (effective < 1) 1 else effective);

    const resolved = ZSTD_resolveMaxBlockSize(maxBlockSize);
    const blockSize: usize = if (resolved < windowSize) resolved else windowSize;
    const maxNbSeq: usize = ZSTD_maxNbSeq(blockSize, cParams.minMatch, useSequenceProducer);

    const a = cwksp_mod.ZSTD_cwksp_alloc_size;
    const aa64 = cwksp_mod.ZSTD_cwksp_aligned64_alloc_size;

    const tokenSpace: usize = a(32 +% blockSize) +%
        aa64(maxNbSeq *% @sizeOf(SeqDef)) +%
        (3 *% a(maxNbSeq *% @sizeOf(BYTE)));

    const tmpWorkSpace: usize = a(tmpWorkspaceBytes());
    const blockStateSpace: usize = 2 *% a(@sizeOf(ZSTD_compressedBlockState_t));
    const matchStateSize: usize = ZSTD_sizeof_matchState(cParams, useRowMatchFinder, 0, 1);
    const ldmSpace: usize = ZSTD_ldm_getTableSize(ldmParams.*);
    const maxNbLdmSeq: usize = ZSTD_ldm_getMaxNbSeq(ldmParams.*, blockSize);
    const ldmSeqSpace: usize = if (ldmParams.enableLdm == @as(c_uint, @bitCast(ZSTD_ps_enable)))
        aa64(maxNbLdmSeq *% @sizeOf(rawSeq))
    else
        0;
    const bufferSpace: usize = a(buffInSize) +% a(buffOutSize);
    const cctxSpace: usize = if (isStatic != 0) a(@sizeOf(@import("zstd_cctx.zig").ZSTD_CCtx)) else 0;

    const maxNbExternalSeq: usize = zstd_compress.ZSTD_sequenceBound(blockSize);
    // ZSTD_Sequence is 4 × c_uint = 16 bytes per upstream layout.
    const zstdSeq_sz: usize = 4 * @sizeOf(c_uint);
    const externalSeqSpace: usize = if (useSequenceProducer != 0)
        aa64(maxNbExternalSeq *% zstdSeq_sz)
    else
        0;

    return cctxSpace +% tmpWorkSpace +% blockStateSpace +% ldmSpace +%
        ldmSeqSpace +% matchStateSize +% tokenSpace +% bufferSpace +%
        externalSeqSpace;
}

// -------------------------------------------------------------------------
//  Public ZSTD_estimate* wrappers — lines 23794..23940, 32787..32816
// -------------------------------------------------------------------------

// Rebuild the loop from line 23794: sweep from min(level, 1) to level,
// take max.
fn estimateUsingCCtxParams(params: *const ZSTD_CCtx_params) usize {
    if (params.nbWorkers > 0) return zerr(ZSTD_error_GENERIC);

    const cParams = cparams_mod.ZSTD_getCParamsFromCCtxParams(
        params,
        std.math.maxInt(U64),
        0,
        @as(c_uint, @bitCast(cparams_mod.ZSTD_cpm_noAttachDict)),
    );
    const useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(params.useRowMatchFinder, &cParams);
    return ZSTD_estimateCCtxSize_usingCCtxParams_internal(
        &cParams,
        &params.ldmParams,
        1,
        useRowMatchFinder,
        0,
        0,
        std.math.maxInt(U64),
        ZSTD_hasExtSeqProd(params),
        params.maxBlockSize,
    );
}

pub export fn ZSTD_estimateCCtxSize_usingCCtxParams(params: *const ZSTD_CCtx_params) usize {
    return estimateUsingCCtxParams(params);
}

pub fn ZSTD_makeCCtxParamsFromCParams(cParams: ZSTD_compressionParameters) callconv(.c) ZSTD_CCtx_params {
    var cctxParams: ZSTD_CCtx_params = .{};
    _ = zstd_compress.ZSTD_CCtxParams_init(&cctxParams, 3);
    cctxParams.cParams = cParams;
    cctxParams.useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(cctxParams.useRowMatchFinder, &cParams);
    cctxParams.maxBlockSize = ZSTD_resolveMaxBlockSize(cctxParams.maxBlockSize);
    return cctxParams;
}

pub export fn ZSTD_estimateCCtxSize_usingCParams(cParams: ZSTD_compressionParameters) usize {
    var initialParams = ZSTD_makeCCtxParamsFromCParams(cParams);
    if (ZSTD_rowMatchFinderSupported(cParams.strategy) != 0) {
        initialParams.useRowMatchFinder = @as(c_uint, @bitCast(ZSTD_ps_disable));
        const noRow = ZSTD_estimateCCtxSize_usingCCtxParams(&initialParams);
        initialParams.useRowMatchFinder = @as(c_uint, @bitCast(ZSTD_ps_enable));
        const withRow = ZSTD_estimateCCtxSize_usingCCtxParams(&initialParams);
        return if (noRow > withRow) noRow else withRow;
    }
    return ZSTD_estimateCCtxSize_usingCCtxParams(&initialParams);
}

pub fn ZSTD_estimateCCtxSize_internal(compressionLevel: c_int) callconv(.c) usize {
    const srcSizeTiers: [4]U64 = .{
        16 * (1 << 10),
        128 * (1 << 10),
        256 * (1 << 10),
        std.math.maxInt(U64),
    };
    var largestSize: usize = 0;
    var tier: usize = 0;
    while (tier < 4) : (tier += 1) {
        const cParams = cparams_mod.ZSTD_getCParams_internal(
            compressionLevel,
            srcSizeTiers[tier],
            0,
            @as(c_uint, @bitCast(cparams_mod.ZSTD_cpm_noAttachDict)),
        );
        const s = ZSTD_estimateCCtxSize_usingCParams(cParams);
        if (s > largestSize) largestSize = s;
    }
    return largestSize;
}

pub export fn ZSTD_estimateCCtxSize(compressionLevel: c_int) usize {
    var memBudget: usize = 0;
    var level: c_int = if (compressionLevel < 1) compressionLevel else 1;
    while (level <= compressionLevel) : (level += 1) {
        const newMB = ZSTD_estimateCCtxSize_internal(level);
        if (newMB > memBudget) memBudget = newMB;
    }
    return memBudget;
}

pub export fn ZSTD_estimateCStreamSize_usingCCtxParams(params: *const ZSTD_CCtx_params) usize {
    if (params.nbWorkers > 0) return zerr(ZSTD_error_GENERIC);
    const cParams = cparams_mod.ZSTD_getCParamsFromCCtxParams(
        params,
        std.math.maxInt(U64),
        0,
        @as(c_uint, @bitCast(cparams_mod.ZSTD_cpm_noAttachDict)),
    );
    const resolvedMax = ZSTD_resolveMaxBlockSize(params.maxBlockSize);
    const windowLog_usize: usize = @as(usize, 1) << @intCast(cParams.windowLog);
    const blockSize: usize = if (resolvedMax < windowLog_usize) resolvedMax else windowLog_usize;
    const inBuffSize: usize = if (params.inBufferMode == @as(c_uint, @bitCast(ZSTD_bm_buffered)))
        windowLog_usize +% blockSize
    else
        0;
    const outBuffSize: usize = if (params.outBufferMode == @as(c_uint, @bitCast(ZSTD_bm_buffered)))
        zstd_compress.ZSTD_compressBound(blockSize) +% 1
    else
        0;
    const useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(params.useRowMatchFinder, &params.cParams);
    return ZSTD_estimateCCtxSize_usingCCtxParams_internal(
        &cParams,
        &params.ldmParams,
        1,
        useRowMatchFinder,
        inBuffSize,
        outBuffSize,
        std.math.maxInt(U64),
        ZSTD_hasExtSeqProd(params),
        params.maxBlockSize,
    );
}

pub export fn ZSTD_estimateCStreamSize_usingCParams(cParams: ZSTD_compressionParameters) usize {
    var initialParams = ZSTD_makeCCtxParamsFromCParams(cParams);
    if (ZSTD_rowMatchFinderSupported(cParams.strategy) != 0) {
        initialParams.useRowMatchFinder = @as(c_uint, @bitCast(ZSTD_ps_disable));
        const noRow = ZSTD_estimateCStreamSize_usingCCtxParams(&initialParams);
        initialParams.useRowMatchFinder = @as(c_uint, @bitCast(ZSTD_ps_enable));
        const withRow = ZSTD_estimateCStreamSize_usingCCtxParams(&initialParams);
        return if (noRow > withRow) noRow else withRow;
    }
    return ZSTD_estimateCStreamSize_usingCCtxParams(&initialParams);
}

pub fn ZSTD_estimateCStreamSize_internal(compressionLevel: c_int) callconv(.c) usize {
    const cParams = cparams_mod.ZSTD_getCParams_internal(
        compressionLevel,
        std.math.maxInt(U64),
        0,
        @as(c_uint, @bitCast(cparams_mod.ZSTD_cpm_noAttachDict)),
    );
    return ZSTD_estimateCStreamSize_usingCParams(cParams);
}

pub export fn ZSTD_estimateCStreamSize(compressionLevel: c_int) usize {
    var memBudget: usize = 0;
    var level: c_int = if (compressionLevel < 1) compressionLevel else 1;
    while (level <= compressionLevel) : (level += 1) {
        const newMB = ZSTD_estimateCStreamSize_internal(level);
        if (newMB > memBudget) memBudget = newMB;
    }
    return memBudget;
}

// -------------------------------------------------------------------------
//  ZSTD_invalidateMatchState + reset — lines 32832..32982
// -------------------------------------------------------------------------

pub fn ZSTD_invalidateMatchState(ms: *ZSTD_MatchState_t) callconv(.c) void {
    ZSTD_window_clear(&ms.window);
    ms.nextToUpdate = ms.window.dictLimit;
    ms.loadedDictEnd = 0;
    ms.opt.litLengthSum = 0;
    ms.dictMatchState = null;
}

pub const ZSTDcrp_makeClean: c_int = 0;
pub const ZSTDcrp_leaveDirty: c_int = 1;
pub const ZSTD_compResetPolicy_e = c_uint;

pub const ZSTDirp_continue: c_int = 0;
pub const ZSTDirp_reset: c_int = 1;
pub const ZSTD_indexResetPolicy_e = c_uint;

pub const ZSTD_resetTarget_CDict: c_int = 0;
pub const ZSTD_resetTarget_CCtx: c_int = 1;
pub const ZSTD_resetTarget_e = c_uint;

pub fn ZSTD_reset_matchState(
    ms: *ZSTD_MatchState_t,
    ws: *ZSTD_cwksp,
    cParams: *const ZSTD_compressionParameters,
    useRowMatchFinder: ZSTD_ParamSwitch_e,
    crp: ZSTD_compResetPolicy_e,
    forceResetIndex: ZSTD_indexResetPolicy_e,
    forWho: ZSTD_resetTarget_e,
) callconv(.c) usize {
    const forDDSDict: U32 = @intFromBool(
        ms.dedicatedDictSearch != 0 and
            forWho == @as(c_uint, @bitCast(ZSTD_resetTarget_CDict)),
    );
    const chainSize: usize = if (ZSTD_allocateChainTable(cParams.strategy, useRowMatchFinder, forDDSDict) != 0)
        @as(usize, 1) << @intCast(cParams.chainLog)
    else
        0;
    const hSize: usize = @as(usize, 1) << @intCast(cParams.hashLog);
    const hashLog3: U32 = if (forWho == @as(c_uint, @bitCast(ZSTD_resetTarget_CCtx)) and cParams.minMatch == 3)
        (if (cParams.windowLog > 17) 17 else cParams.windowLog)
    else
        0;
    const h3Size: usize = if (hashLog3 != 0) (@as(usize, 1) << @intCast(hashLog3)) else 0;

    if (forceResetIndex == @as(c_uint, @bitCast(ZSTDirp_reset))) {
        ZSTD_window_init(&ms.window);
        cwksp_mod.ZSTD_cwksp_mark_tables_dirty(ws);
    }
    ms.hashLog3 = hashLog3;
    ms.lazySkipping = 0;
    ZSTD_invalidateMatchState(ms);

    cwksp_mod.ZSTD_cwksp_clear_tables(ws);

    ms.hashTable = @ptrCast(@alignCast(
        cwksp_mod.ZSTD_cwksp_reserve_table(ws, hSize *% @sizeOf(U32)),
    ));
    ms.chainTable = @ptrCast(@alignCast(
        cwksp_mod.ZSTD_cwksp_reserve_table(ws, chainSize *% @sizeOf(U32)),
    ));
    ms.hashTable3 = @ptrCast(@alignCast(
        cwksp_mod.ZSTD_cwksp_reserve_table(ws, h3Size *% @sizeOf(U32)),
    ));
    if (cwksp_mod.ZSTD_cwksp_reserve_failed(ws) != 0) {
        return zerr(ZSTD_error_memory_allocation);
    }

    if (crp != @as(c_uint, @bitCast(ZSTDcrp_leaveDirty))) {
        cwksp_mod.ZSTD_cwksp_clean_tables(ws);
    }

    if (ZSTD_rowMatchFinderUsed(cParams.strategy, useRowMatchFinder) != 0) {
        const tagTableSize: usize = hSize;
        if (forWho == @as(c_uint, @bitCast(ZSTD_resetTarget_CCtx))) {
            ms.tagTable = @ptrCast(@alignCast(
                cwksp_mod.ZSTD_cwksp_reserve_aligned_init_once(ws, tagTableSize),
            ));
            ZSTD_advanceHashSalt(ms);
        } else {
            ms.tagTable = @ptrCast(@alignCast(
                cwksp_mod.ZSTD_cwksp_reserve_aligned64(ws, tagTableSize),
            ));
            if (ms.tagTable != null) {
                @memset(@as([*]u8, @ptrCast(ms.tagTable))[0..tagTableSize], 0);
            }
            ms.hashSalt = 0;
        }
        {
            const rowLog_lo: c_uint = if (cParams.searchLog < 6) cParams.searchLog else 6;
            const rowLog: U32 = if (4 > rowLog_lo) 4 else rowLog_lo;
            ms.rowHashLog = cParams.hashLog -% rowLog;
        }
    }
    if (forWho == @as(c_uint, @bitCast(ZSTD_resetTarget_CCtx)) and
        cParams.strategy >= @as(c_uint, @bitCast(ZSTD_btopt)))
    {
        const aa64 = cwksp_mod.ZSTD_cwksp_reserve_aligned64;
        ms.opt.litFreq = @ptrCast(@alignCast(aa64(ws, @as(usize, @intCast(MaxLit)) * @sizeOf(c_uint))));
        ms.opt.litLengthFreq = @ptrCast(@alignCast(aa64(ws, @as(usize, @intCast(MaxLL + 1)) * @sizeOf(c_uint))));
        ms.opt.matchLengthFreq = @ptrCast(@alignCast(aa64(ws, @as(usize, @intCast(MaxML + 1)) * @sizeOf(c_uint))));
        ms.opt.offCodeFreq = @ptrCast(@alignCast(aa64(ws, @as(usize, @intCast(MaxOff + 1)) * @sizeOf(c_uint))));
        ms.opt.matchTable = @ptrCast(@alignCast(aa64(ws, @as(usize, @intCast(ZSTD_OPT_SIZE)) * @sizeOf(ZSTD_match_t))));
        ms.opt.priceTable = @ptrCast(@alignCast(aa64(ws, @as(usize, @intCast(ZSTD_OPT_SIZE)) * @sizeOf(ZSTD_optimal_t))));
    }
    ms.cParams = cParams.*;
    if (cwksp_mod.ZSTD_cwksp_reserve_failed(ws) != 0) {
        return zerr(ZSTD_error_memory_allocation);
    }
    return 0;
}

// -------------------------------------------------------------------------
//  Window-threshold helpers — lines 32984..32992
// -------------------------------------------------------------------------

const ZSTD_CURRENT_MAX_64: c_uint = 3500 * (1 << 20);
const ZSTD_CURRENT_MAX_32: c_uint = 2000 * (1 << 20);
const ZSTD_INDEXOVERFLOW_MARGIN: c_uint = 16 * (1 << 20);

pub fn ZSTD_indexTooCloseToMax(w: ZSTD_window_t) callconv(.c) c_int {
    const dist: usize = @intFromPtr(w.nextSrc) -% @intFromPtr(w.base);
    const curMax = if (@sizeOf(usize) == 8) ZSTD_CURRENT_MAX_64 else ZSTD_CURRENT_MAX_32;
    return @intFromBool(dist > (curMax -% ZSTD_INDEXOVERFLOW_MARGIN));
}

pub fn ZSTD_dictTooBig(loadedDictSize: usize) callconv(.c) c_int {
    const curMax = if (@sizeOf(usize) == 8) ZSTD_CURRENT_MAX_64 else ZSTD_CURRENT_MAX_32;
    const u32max: U32 = @bitCast(@as(i32, -1));
    return @intFromBool(loadedDictSize > (u32max -% curMax));
}

// ZSTD_resetCCtx_internal (translate-c lines 32993..33286) moved to
// zstd_cctx.zig in slice 5d — it needs the full ZSTD_CCtx layout that
// lives there.

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------

test "window_init yields dictLimit/lowLimit = 2 and nextSrc offset 2" {
    var w: ZSTD_window_t = .{};
    ZSTD_window_init(&w);
    try std.testing.expectEqual(@as(U32, 2), w.dictLimit);
    try std.testing.expectEqual(@as(U32, 2), w.lowLimit);
    const off: usize = @intFromPtr(w.nextSrc) - @intFromPtr(w.base);
    try std.testing.expectEqual(@as(usize, 2), off);
    try std.testing.expect(ZSTD_window_isEmpty(w) != 0);
    try std.testing.expectEqual(@as(U32, 0), ZSTD_window_hasExtDict(w));
}

test "window_clear collapses dictLimit/lowLimit to nextSrc offset" {
    var w: ZSTD_window_t = .{};
    ZSTD_window_init(&w);
    w.nextSrc = w.base + 42;
    ZSTD_window_clear(&w);
    try std.testing.expectEqual(@as(U32, 42), w.dictLimit);
    try std.testing.expectEqual(@as(U32, 42), w.lowLimit);
}

test "bitmix deterministic + nonzero" {
    const a = ZSTD_bitmix(0xDEAD_BEEF_CAFE_F00D, 8);
    const b = ZSTD_bitmix(0xDEAD_BEEF_CAFE_F00D, 8);
    try std.testing.expectEqual(a, b);
    const c = ZSTD_bitmix(0xDEAD_BEEF_CAFE_F00D, 16);
    try std.testing.expect(a != c);
}

test "reset_compressedBlockState installs repStartValues" {
    var bs: ZSTD_compressedBlockState_t = .{};
    bs.rep[0] = 999;
    bs.entropy.huf.repeatMode = .HUF_repeat_valid;
    ZSTD_reset_compressedBlockState(&bs);
    try std.testing.expectEqual(@as(U32, 1), bs.rep[0]);
    try std.testing.expectEqual(@as(U32, 4), bs.rep[1]);
    try std.testing.expectEqual(@as(U32, 8), bs.rep[2]);
    try std.testing.expectEqual(ms_mod.HUF_repeat.HUF_repeat_none, bs.entropy.huf.repeatMode);
}

test "sizeof_matchState nonzero for level-3 cparams" {
    const cp = cparams_mod.ZSTD_getCParams(3, 0, 0);
    const sz = ZSTD_sizeof_matchState(&cp, @as(c_uint, @bitCast(ZSTD_ps_auto)), 0, 1);
    try std.testing.expect(sz > 0);
}

test "estimateCCtxSize monotonic in level" {
    const s1 = ZSTD_estimateCCtxSize(1);
    const s19 = ZSTD_estimateCCtxSize(19);
    try std.testing.expect(s1 > 0);
    try std.testing.expect(s19 >= s1);
}

test "invalidateMatchState clears dictMatchState + loadedDictEnd" {
    var other: ZSTD_MatchState_t = .{};
    var ms: ZSTD_MatchState_t = .{};
    ZSTD_window_init(&ms.window);
    ms.dictMatchState = &other;
    ms.loadedDictEnd = 99;
    ms.opt.litLengthSum = 11;
    ZSTD_invalidateMatchState(&ms);
    try std.testing.expect(ms.dictMatchState == null);
    try std.testing.expectEqual(@as(U32, 0), ms.loadedDictEnd);
    try std.testing.expectEqual(@as(U32, 0), ms.opt.litLengthSum);
}

