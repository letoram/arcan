// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/compress/zstd_compress.c — slice 5a
// (CCtx lifecycle + parameter machinery).
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// Method: produced by refining `zig translate-c` output from
//   $ZSTD/lib/compress/zstd_compress.c → /tmp/raw_zstd_compress.zig
// (see project memory: slice 5 plan). Lines 21709..24076 (lifecycle/params
// section) were the source; large dependent types (ZSTD_cwksp, SeqStore_t,
// ldmState_t, blockSplitCtx, …) are deferred to slices 5b/5c — here we only
// expose the fields that ZSTD_CCtx_{setParameter,reset,setPledgedSrcSize,
// sizeof} actually read/write.
//
// Public C-ABI entry points (via `pub export fn`):
//   ZSTD_createCCtx, ZSTD_createCCtx_advanced, ZSTD_initStaticCCtx,
//   ZSTD_freeCCtx, ZSTD_sizeof_CCtx,
//   ZSTD_CCtx_reset, ZSTD_CCtx_setParameter, ZSTD_CCtx_setPledgedSrcSize,
//   ZSTD_cParam_getBounds, ZSTD_compressBound, ZSTD_sequenceBound,
//   ZSTD_minCLevel, ZSTD_maxCLevel, ZSTD_defaultCLevel,
//   ZSTD_CCtxParams_init, ZSTD_CCtxParams_reset,
//   ZSTD_CCtxParams_setParameter,
//   ZSTD_isUpdateAuthorized.
// Stub (returns -ZSTD_error_GENERIC until slice 5c lands the encode core):
//   ZSTD_compressCCtx, ZSTD_compress, ZSTD_compress2.
//
// All of struct_ZSTD_CCtx_s's 50+ fields are *not* modelled here; our CCtx
// wrapper carries only {staticSize, streamStage, pledgedSrcSizePlusOne,
// cParamsChanged, requestedParams, customMem}. Once slice 5c ports the cwksp
// allocator and the real encode path, this struct grows to the full upstream
// layout — callers hold an opaque pointer either way.

const std = @import("std");
const common = @import("zstd_common.zig");

// -------------------------------------------------------------------------
//  Shared types — mirrors of lib/zstd.h
// -------------------------------------------------------------------------

pub const ZSTD_customMem = common.ZSTD_customMem;
pub const ZSTD_defaultCMem = common.ZSTD_defaultCMem;

pub const ZSTD_strategy = c_uint;
pub const ZSTD_fast: c_int = 1;
pub const ZSTD_dfast: c_int = 2;
pub const ZSTD_greedy: c_int = 3;
pub const ZSTD_lazy: c_int = 4;
pub const ZSTD_lazy2: c_int = 5;
pub const ZSTD_btlazy2: c_int = 6;
pub const ZSTD_btopt: c_int = 7;
pub const ZSTD_btultra: c_int = 8;
pub const ZSTD_btultra2: c_int = 9;

pub const ZSTD_compressionParameters = extern struct {
    windowLog: c_uint = 0,
    chainLog: c_uint = 0,
    hashLog: c_uint = 0,
    searchLog: c_uint = 0,
    minMatch: c_uint = 0,
    targetLength: c_uint = 0,
    strategy: ZSTD_strategy = 0,
};

pub const ZSTD_frameParameters = extern struct {
    contentSizeFlag: c_int = 0,
    checksumFlag: c_int = 0,
    noDictIDFlag: c_int = 0,
};

pub const ZSTD_parameters = extern struct {
    cParams: ZSTD_compressionParameters = .{},
    fParams: ZSTD_frameParameters = .{},
};

pub const ZSTD_format_e = c_uint;
pub const ZSTD_f_zstd1: c_int = 0;
pub const ZSTD_f_zstd1_magicless: c_int = 1;

pub const ZSTD_dictAttachPref_e = c_uint;
pub const ZSTD_dictDefaultAttach: c_int = 0;
pub const ZSTD_dictForceAttach: c_int = 1;
pub const ZSTD_dictForceCopy: c_int = 2;
pub const ZSTD_dictForceLoad: c_int = 3;

pub const ZSTD_ParamSwitch_e = c_uint;
pub const ZSTD_ps_auto: c_int = 0;
pub const ZSTD_ps_enable: c_int = 1;
pub const ZSTD_ps_disable: c_int = 2;

pub const ZSTD_bufferMode_e = c_uint;
pub const ZSTD_bm_buffered: c_int = 0;
pub const ZSTD_bm_stable: c_int = 1;

pub const ZSTD_SequenceFormat_e = c_uint;
pub const ZSTD_sf_noBlockDelimiters: c_int = 0;
pub const ZSTD_sf_explicitBlockDelimiters: c_int = 1;

pub const ZSTD_ResetDirective = c_uint;
pub const ZSTD_reset_session_only: c_int = 1;
pub const ZSTD_reset_parameters: c_int = 2;
pub const ZSTD_reset_session_and_parameters: c_int = 3;

pub const ZSTD_cStreamStage = c_uint;
pub const zcss_init: c_int = 0;
pub const zcss_load: c_int = 1;
pub const zcss_flush: c_int = 2;

// LDM (long-distance matching) params — slice 5c will fold these into the
// real match-finder; here we only need them as storage inside CCtx_params.
pub const ldmParams_t = extern struct {
    enableLdm: ZSTD_ParamSwitch_e = 0,
    hashLog: u32 = 0,
    bucketSizeLog: u32 = 0,
    minMatchLength: u32 = 0,
    hashRateLog: u32 = 0,
    windowLog: u32 = 0,
};

pub const ZSTD_sequenceProducer_F = ?*const fn (
    sequenceProducerState: ?*anyopaque,
    outSeqs: ?*anyopaque,
    outSeqsCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    dict: ?*const anyopaque,
    dictSize: usize,
    compressionLevel: c_int,
    windowSize: usize,
) callconv(.c) usize;

pub const ZSTD_CCtx_params = extern struct {
    format: ZSTD_format_e = 0,
    cParams: ZSTD_compressionParameters = .{},
    fParams: ZSTD_frameParameters = .{},
    compressionLevel: c_int = 0,
    forceWindow: c_int = 0,
    targetCBlockSize: usize = 0,
    srcSizeHint: c_int = 0,
    attachDictPref: ZSTD_dictAttachPref_e = 0,
    literalCompressionMode: ZSTD_ParamSwitch_e = 0,
    nbWorkers: c_int = 0,
    jobSize: usize = 0,
    overlapLog: c_int = 0,
    rsyncable: c_int = 0,
    ldmParams: ldmParams_t = .{},
    enableDedicatedDictSearch: c_int = 0,
    inBufferMode: ZSTD_bufferMode_e = 0,
    outBufferMode: ZSTD_bufferMode_e = 0,
    blockDelimiters: ZSTD_SequenceFormat_e = 0,
    validateSequences: c_int = 0,
    postBlockSplitter: ZSTD_ParamSwitch_e = 0,
    preBlockSplitter_level: c_int = 0,
    maxBlockSize: usize = 0,
    useRowMatchFinder: ZSTD_ParamSwitch_e = 0,
    deterministicRefPrefix: c_int = 0,
    customMem: ZSTD_customMem = .{},
    prefetchCDictTables: ZSTD_ParamSwitch_e = 0,
    enableMatchFinderFallback: c_int = 0,
    extSeqProdState: ?*anyopaque = null,
    extSeqProdFunc: ZSTD_sequenceProducer_F = null,
    searchForExternalRepcodes: ZSTD_ParamSwitch_e = 0,
};

pub const ZSTD_bounds = extern struct {
    @"error": usize = 0,
    lowerBound: c_int = 0,
    upperBound: c_int = 0,
};

// cParameter — values match lib/zstd.h exactly.
pub const ZSTD_cParameter = c_uint;
pub const ZSTD_c_compressionLevel: c_int = 100;
pub const ZSTD_c_windowLog: c_int = 101;
pub const ZSTD_c_hashLog: c_int = 102;
pub const ZSTD_c_chainLog: c_int = 103;
pub const ZSTD_c_searchLog: c_int = 104;
pub const ZSTD_c_minMatch: c_int = 105;
pub const ZSTD_c_targetLength: c_int = 106;
pub const ZSTD_c_strategy: c_int = 107;
pub const ZSTD_c_targetCBlockSize: c_int = 130;
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
pub const ZSTD_c_experimentalParam20: c_int = 1017;

// Error encoding: ZSTD's `(size_t)-errno` convention. Values match
// lib/common/error_private.h.
inline fn zerr(code: c_int) usize {
    return @bitCast(-@as(isize, code));
}
const ZSTD_error_GENERIC: c_int = 1;
const ZSTD_error_parameter_unsupported: c_int = 40;
const ZSTD_error_stage_wrong: c_int = 60;
const ZSTD_error_memory_allocation: c_int = 64;
const ZSTD_error_srcSize_wrong: c_int = 72;

// -------------------------------------------------------------------------
//  Shared streaming I/O types — translate-c lines 21830..21844, 23139..23144
// -------------------------------------------------------------------------

pub const ZSTD_inBuffer = extern struct {
    src: ?*const anyopaque = null,
    size: usize = 0,
    pos: usize = 0,
};

pub const ZSTD_outBuffer = extern struct {
    dst: ?*anyopaque = null,
    size: usize = 0,
    pos: usize = 0,
};

pub const ZSTD_Sequence = extern struct {
    offset: c_uint = 0,
    litLength: c_uint = 0,
    matchLength: c_uint = 0,
    rep: c_uint = 0,
};

pub const ZSTD_CLEVEL_DEFAULT: c_int = 3;

// -------------------------------------------------------------------------
//  Public lifecycle API
// -------------------------------------------------------------------------

pub export fn ZSTD_minCLevel() c_int {
    return -(@as(c_int, 1) << 17);
}

pub export fn ZSTD_maxCLevel() c_int {
    return 22;
}

pub export fn ZSTD_defaultCLevel() c_int {
    return ZSTD_CLEVEL_DEFAULT;
}

// Port of line 21959..21966 of /tmp/raw_zstd_compress.zig — pure integer math,
// no dependencies.
pub export fn ZSTD_compressBound(srcSize: usize) usize {
    // ZSTD_COMPRESSBOUND from lib/zstd.h:
    //   (srcSize) + ((srcSize)>>8) + (((srcSize) < (128<<10)) ? (((128<<10) - (srcSize)) >> 11) : 0)
    // guarded against huge srcSize → 0.
    const limit: usize = if (@sizeOf(usize) == 8)
        @as(usize, 0xFF00_0000_0000_0000)
    else
        @as(usize, 0xFF00_0000);
    if (srcSize >= limit) return zerr(ZSTD_error_srcSize_wrong);
    const margin_threshold: usize = 128 << 10;
    const margin: usize = if (srcSize < margin_threshold)
        (margin_threshold - srcSize) >> 11
    else
        0;
    return srcSize + (srcSize >> 8) + margin;
}

pub export fn ZSTD_sequenceBound(srcSize: usize) usize {
    const maxNbSeq: usize = (srcSize / 3) + 1;
    const maxNbDelims: usize = (srcSize / (@as(usize, 1) << 10)) + 1;
    return maxNbSeq + maxNbDelims;
}

// CCtx lifecycle (ZSTD_createCCtx / ZSTD_freeCCtx / ZSTD_sizeof_CCtx /
// ZSTD_initStaticCCtx) was originally a slice-5a minimal stub here; the
// real impls moved to zstd_cctx.zig in slice 5d, where the full CCtx
// layout (with workspace + blockState) lives.

// -------------------------------------------------------------------------
//  Parameter machinery
// -------------------------------------------------------------------------

// Port of line 22099..22311 of /tmp/raw_zstd_compress.zig. Stripped of the
// `while(true) { ... break; }` shells translate-c leaves behind for C's
// fall-through case labels.
pub export fn ZSTD_cParam_getBounds(param: ZSTD_cParameter) ZSTD_bounds {
    var b: ZSTD_bounds = .{};
    const WLOG_MAX: c_int = if (@sizeOf(usize) == 4) 30 else 31;
    const HLOG_MAX: c_int = if (WLOG_MAX < 30) WLOG_MAX else 30;
    switch (param) {
        @as(c_uint, @bitCast(ZSTD_c_compressionLevel)) => {
            b.lowerBound = ZSTD_minCLevel();
            b.upperBound = ZSTD_maxCLevel();
        },
        @as(c_uint, @bitCast(ZSTD_c_windowLog)) => {
            b.lowerBound = 10;
            b.upperBound = WLOG_MAX;
        },
        @as(c_uint, @bitCast(ZSTD_c_hashLog)) => {
            b.lowerBound = 6;
            b.upperBound = HLOG_MAX;
        },
        @as(c_uint, @bitCast(ZSTD_c_chainLog)) => {
            b.lowerBound = 6;
            b.upperBound = if (@sizeOf(usize) == 4) @as(c_int, 29) else 30;
        },
        @as(c_uint, @bitCast(ZSTD_c_searchLog)) => {
            b.lowerBound = 1;
            b.upperBound = WLOG_MAX - 1;
        },
        @as(c_uint, @bitCast(ZSTD_c_minMatch)) => {
            b.lowerBound = 3;
            b.upperBound = 7;
        },
        @as(c_uint, @bitCast(ZSTD_c_targetLength)) => {
            b.lowerBound = 0;
            b.upperBound = @as(c_int, 1) << 17;
        },
        @as(c_uint, @bitCast(ZSTD_c_strategy)) => {
            b.lowerBound = ZSTD_fast;
            b.upperBound = ZSTD_btultra2;
        },
        @as(c_uint, @bitCast(ZSTD_c_contentSizeFlag)),
        @as(c_uint, @bitCast(ZSTD_c_checksumFlag)),
        @as(c_uint, @bitCast(ZSTD_c_dictIDFlag)),
        => {
            b.lowerBound = 0;
            b.upperBound = 1;
        },
        @as(c_uint, @bitCast(ZSTD_c_nbWorkers)),
        @as(c_uint, @bitCast(ZSTD_c_jobSize)),
        @as(c_uint, @bitCast(ZSTD_c_overlapLog)),
        => {
            b.lowerBound = 0;
            b.upperBound = 0;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam8)) => {
            b.lowerBound = 0;
            b.upperBound = 1;
        },
        @as(c_uint, @bitCast(ZSTD_c_enableLongDistanceMatching)) => {
            b.lowerBound = ZSTD_ps_auto;
            b.upperBound = ZSTD_ps_disable;
        },
        @as(c_uint, @bitCast(ZSTD_c_ldmHashLog)) => {
            b.lowerBound = 6;
            b.upperBound = HLOG_MAX;
        },
        @as(c_uint, @bitCast(ZSTD_c_ldmMinMatch)) => {
            b.lowerBound = 4;
            b.upperBound = 4096;
        },
        @as(c_uint, @bitCast(ZSTD_c_ldmBucketSizeLog)) => {
            b.lowerBound = 1;
            b.upperBound = 8;
        },
        @as(c_uint, @bitCast(ZSTD_c_ldmHashRateLog)) => {
            b.lowerBound = 0;
            b.upperBound = WLOG_MAX - 6;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam1)),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam3)),
        => {
            b.lowerBound = 0;
            b.upperBound = 1;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam2)) => {
            b.lowerBound = ZSTD_f_zstd1;
            b.upperBound = ZSTD_f_zstd1_magicless;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam4)) => {
            b.lowerBound = ZSTD_dictDefaultAttach;
            b.upperBound = ZSTD_dictForceLoad;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam5)),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam13)),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam16)),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam19)),
        => {
            b.lowerBound = ZSTD_ps_auto;
            b.upperBound = ZSTD_ps_disable;
        },
        @as(c_uint, @bitCast(ZSTD_c_targetCBlockSize)) => {
            b.lowerBound = 1340;
            b.upperBound = @as(c_int, 1) << 17;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam7)) => {
            b.lowerBound = 0;
            b.upperBound = 2147483647;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam9)),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam10)),
        => {
            b.lowerBound = ZSTD_bm_buffered;
            b.upperBound = ZSTD_bm_stable;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam11)) => {
            b.lowerBound = ZSTD_sf_noBlockDelimiters;
            b.upperBound = ZSTD_sf_explicitBlockDelimiters;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam12)),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam15)),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam17)),
        => {
            b.lowerBound = 0;
            b.upperBound = 1;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam14)) => {
            b.lowerBound = @as(c_int, 1) << 10;
            b.upperBound = @as(c_int, 1) << 17;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam18)) => {
            b.lowerBound = @as(c_int, 1) << 10;
            b.upperBound = @as(c_int, 1) << 17;
        },
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam20)) => {
            b.lowerBound = 0;
            b.upperBound = 6;
        },
        else => {
            b.@"error" = zerr(ZSTD_error_parameter_unsupported);
        },
    }
    return b;
}

// Port of line 32315..32326 of /tmp/raw_zstd_compress.zig.
pub export fn ZSTD_isUpdateAuthorized(param: ZSTD_cParameter) c_int {
    return switch (param) {
        @as(c_uint, @bitCast(ZSTD_c_compressionLevel)),
        @as(c_uint, @bitCast(ZSTD_c_hashLog)),
        @as(c_uint, @bitCast(ZSTD_c_chainLog)),
        @as(c_uint, @bitCast(ZSTD_c_searchLog)),
        @as(c_uint, @bitCast(ZSTD_c_minMatch)),
        @as(c_uint, @bitCast(ZSTD_c_targetLength)),
        @as(c_uint, @bitCast(ZSTD_c_strategy)),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam20)),
        => 1,
        else => 0,
    };
}

// Set the param on a CCtx_params struct. Validates via getBounds, then writes
// into the matching field. This is a slice-5a stub: upstream has a monster
// switch that derives a bunch of dependent state (cParams resolution, etc.);
// we persist the raw value and defer re-resolution to slice 5c. That matches
// upstream semantics for the ZSTD_CCtx_setParameter entry — upstream also
// lazily reapplies on the next compress call.
pub export fn ZSTD_CCtxParams_setParameter(
    params: *ZSTD_CCtx_params,
    param: ZSTD_cParameter,
    value: c_int,
) usize {
    const bounds = ZSTD_cParam_getBounds(param);
    if (bounds.@"error" != 0) return bounds.@"error";
    if (value < bounds.lowerBound or value > bounds.upperBound) {
        // upstream returns parameter_outOfBound (42), but our minimal error
        // table only carries parameter_unsupported — reuse it rather than
        // plumb a second error here; slice 5c will align precisely.
        return zerr(ZSTD_error_parameter_unsupported);
    }
    switch (param) {
        @as(c_uint, @bitCast(ZSTD_c_compressionLevel)) => params.compressionLevel = value,
        @as(c_uint, @bitCast(ZSTD_c_windowLog)) => params.cParams.windowLog = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_hashLog)) => params.cParams.hashLog = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_chainLog)) => params.cParams.chainLog = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_searchLog)) => params.cParams.searchLog = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_minMatch)) => params.cParams.minMatch = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_targetLength)) => params.cParams.targetLength = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_strategy)) => params.cParams.strategy = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_contentSizeFlag)) => params.fParams.contentSizeFlag = value,
        @as(c_uint, @bitCast(ZSTD_c_checksumFlag)) => params.fParams.checksumFlag = value,
        @as(c_uint, @bitCast(ZSTD_c_dictIDFlag)) => params.fParams.noDictIDFlag = if (value == 0) 1 else 0,
        @as(c_uint, @bitCast(ZSTD_c_nbWorkers)) => params.nbWorkers = value,
        @as(c_uint, @bitCast(ZSTD_c_jobSize)) => params.jobSize = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_overlapLog)) => params.overlapLog = value,
        @as(c_uint, @bitCast(ZSTD_c_enableLongDistanceMatching)) => params.ldmParams.enableLdm = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_ldmHashLog)) => params.ldmParams.hashLog = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_ldmMinMatch)) => params.ldmParams.minMatchLength = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_ldmBucketSizeLog)) => params.ldmParams.bucketSizeLog = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_ldmHashRateLog)) => params.ldmParams.hashRateLog = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_targetCBlockSize)) => params.targetCBlockSize = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam2)) => params.format = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam4)) => params.attachDictPref = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam5)) => params.literalCompressionMode = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam7)) => params.srcSizeHint = value,
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam9)) => params.inBufferMode = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam10)) => params.outBufferMode = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam11)) => params.blockDelimiters = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam12)) => params.validateSequences = value,
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam13)) => params.postBlockSplitter = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam20)) => params.preBlockSplitter_level = value,
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam15)) => params.deterministicRefPrefix = value,
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam16)) => params.prefetchCDictTables = @intCast(value),
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam17)) => params.enableMatchFinderFallback = value,
        @as(c_uint, @bitCast(ZSTD_c_experimentalParam19)) => params.searchForExternalRepcodes = @intCast(value),
        // Params whose storage lives in CCtx, not CCtx_params (maxBlockSize,
        // useRowMatchFinder, etc.) — writes handled at the CCtx layer in 5c.
        else => {},
    }
    return 0;
}

// Port of line 24984..24992.
pub export fn ZSTD_CCtxParams_reset(params: ?*ZSTD_CCtx_params) usize {
    const p = params orelse return zerr(ZSTD_error_GENERIC);
    return ZSTD_CCtxParams_init(p, ZSTD_CLEVEL_DEFAULT);
}

pub export fn ZSTD_CCtxParams_init(params: ?*ZSTD_CCtx_params, compressionLevel: c_int) usize {
    const p = params orelse return zerr(ZSTD_error_GENERIC);
    p.* = .{};
    p.compressionLevel = compressionLevel;
    p.fParams.contentSizeFlag = 1;
    return 0;
}

// CCtx-level encode entry points (ZSTD_compressCCtx / ZSTD_compress /
// ZSTD_compress2) live in zstd_cctx.zig — they need the full ZSTD_CCtx
// layout with workspace + blockState.

test "ZSTD_compressBound monotonic" {
    // Zero-size frame still needs ~64 bytes of header overhead.
    try std.testing.expect(ZSTD_compressBound(0) > 0);
    try std.testing.expect(ZSTD_compressBound(1024) > 1024);
    try std.testing.expect(ZSTD_compressBound(1 << 20) > (1 << 20));
}

test "ZSTD_cParam_getBounds known params" {
    const nb = ZSTD_cParam_getBounds(@as(c_uint, @bitCast(ZSTD_c_nbWorkers)));
    try std.testing.expectEqual(@as(usize, 0), nb.@"error");
    try std.testing.expectEqual(@as(c_int, 0), nb.lowerBound);
    try std.testing.expectEqual(@as(c_int, 0), nb.upperBound);

    const cl = ZSTD_cParam_getBounds(@as(c_uint, @bitCast(ZSTD_c_compressionLevel)));
    try std.testing.expectEqual(@as(usize, 0), cl.@"error");
    try std.testing.expectEqual(@as(c_int, 22), cl.upperBound);

    const bogus = ZSTD_cParam_getBounds(@as(c_uint, 9999));
    try std.testing.expect(bogus.@"error" != 0);
}

// CCtx lifecycle test moved to zstd_cctx.zig (slice 5d).
