// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7's compression-parameter derivation machinery.
// Source: /tmp/raw_zstd_compress.zig lines ~32327..32698 (dedicatedDictSearch,
// clampCParams, adjustCParams_internal, getCParams_internal,
// getParams_internal, overrideCParams), lines 31552..31574
// (getCParamsFromCCtxParams), lines 31381..31396 (reset_compressedBlockState),
// lines 31842..31850 (cycleLog), lines 32157..32231 (rowMatchFinderSupported /
// CDictIndicesAreTagged / friends), lines 32488..32515 (dictAndWindowLog),
// lines 38656..39493 (ZSTD_defaultCParameters — the 4×23 strategy table),
// lines 39494..39522 (getCParamRowSize), lines 24196..24219 + 24393..24405
// (public ZSTD_{getCParams,getParams,adjustCParams}).
//
// The 4×23 default-cparams table is preserved value-for-value from upstream;
// translate-c's anonymous `@as(c_uint, @bitCast(@as(c_int, N)))` noise is
// flattened to integer literals. Results are bit-identical.
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).

const std = @import("std");
const common = @import("zstd_common.zig");
const zstd_compress = @import("zstd_compress.zig");

// -------------------------------------------------------------------------
//  Imports from the rest of the module
// -------------------------------------------------------------------------

pub const ZSTD_compressionParameters = zstd_compress.ZSTD_compressionParameters;
pub const ZSTD_parameters = zstd_compress.ZSTD_parameters;
pub const ZSTD_frameParameters = zstd_compress.ZSTD_frameParameters;
pub const ZSTD_CCtx_params = zstd_compress.ZSTD_CCtx_params;
pub const ZSTD_strategy = zstd_compress.ZSTD_strategy;
pub const ZSTD_ParamSwitch_e = zstd_compress.ZSTD_ParamSwitch_e;
pub const ZSTD_bounds = zstd_compress.ZSTD_bounds;

const ZSTD_fast = zstd_compress.ZSTD_fast;
const ZSTD_dfast = zstd_compress.ZSTD_dfast;
const ZSTD_greedy = zstd_compress.ZSTD_greedy;
const ZSTD_lazy = zstd_compress.ZSTD_lazy;
const ZSTD_lazy2 = zstd_compress.ZSTD_lazy2;
const ZSTD_btlazy2 = zstd_compress.ZSTD_btlazy2;
const ZSTD_btopt = zstd_compress.ZSTD_btopt;
const ZSTD_btultra = zstd_compress.ZSTD_btultra;
const ZSTD_btultra2 = zstd_compress.ZSTD_btultra2;

const ZSTD_ps_auto = zstd_compress.ZSTD_ps_auto;
const ZSTD_ps_enable = zstd_compress.ZSTD_ps_enable;
const ZSTD_ps_disable = zstd_compress.ZSTD_ps_disable;

const ZSTD_c_windowLog = zstd_compress.ZSTD_c_windowLog;
const ZSTD_c_chainLog = zstd_compress.ZSTD_c_chainLog;
const ZSTD_c_hashLog = zstd_compress.ZSTD_c_hashLog;
const ZSTD_c_searchLog = zstd_compress.ZSTD_c_searchLog;
const ZSTD_c_minMatch = zstd_compress.ZSTD_c_minMatch;
const ZSTD_c_targetLength = zstd_compress.ZSTD_c_targetLength;
const ZSTD_c_strategy = zstd_compress.ZSTD_c_strategy;
const ZSTD_cParam_getBounds = zstd_compress.ZSTD_cParam_getBounds;
const ZSTD_minCLevel = zstd_compress.ZSTD_minCLevel;

// -------------------------------------------------------------------------
//  CParamMode + small numeric helpers
// -------------------------------------------------------------------------

pub const ZSTD_CParamMode_e = c_uint;
pub const ZSTD_cpm_noAttachDict: c_uint = 0;
pub const ZSTD_cpm_attachDict: c_uint = 1;
pub const ZSTD_cpm_createCDict: c_uint = 2;
pub const ZSTD_cpm_unknown: c_uint = 3;

pub const U32 = u32;
pub const U64 = u64;

inline fn ZSTD_highbit32(val: U32) c_uint {
    // Match upstream: for val != 0, returns 31 - clz32. val==0 is UB upstream.
    return 31 -% @as(c_uint, @clz(val));
}

pub fn ZSTD_cycleLog(hashLog: U32, strat: ZSTD_strategy) callconv(.c) U32 {
    const btScale: U32 = @intFromBool(strat >= @as(c_uint, @bitCast(ZSTD_btlazy2)));
    return hashLog -% btScale;
}

pub fn ZSTD_rowMatchFinderSupported(strategy: ZSTD_strategy) callconv(.c) c_int {
    // Upstream: greedy/lazy/lazy2 support row-based match finding.
    return @intFromBool(
        strategy == @as(c_uint, @bitCast(ZSTD_greedy)) or
            strategy == @as(c_uint, @bitCast(ZSTD_lazy)) or
            strategy == @as(c_uint, @bitCast(ZSTD_lazy2)),
    );
}

pub fn ZSTD_rowMatchFinderUsed(
    strategy: ZSTD_strategy,
    mode: ZSTD_ParamSwitch_e,
) callconv(.c) c_int {
    return @intFromBool(
        ZSTD_rowMatchFinderSupported(strategy) != 0 and
            mode == @as(c_uint, @bitCast(ZSTD_ps_enable)),
    );
}

pub fn ZSTD_CDictIndicesAreTagged(cParams: *const ZSTD_compressionParameters) callconv(.c) c_int {
    return @intFromBool(
        cParams.strategy == @as(c_uint, @bitCast(ZSTD_fast)) or
            cParams.strategy == @as(c_uint, @bitCast(ZSTD_dfast)),
    );
}

// Port of line 32670..32696.
pub fn ZSTD_overrideCParams(
    cParams: *ZSTD_compressionParameters,
    overrides: *const ZSTD_compressionParameters,
) callconv(.c) void {
    if (overrides.windowLog != 0) cParams.windowLog = overrides.windowLog;
    if (overrides.hashLog != 0) cParams.hashLog = overrides.hashLog;
    if (overrides.chainLog != 0) cParams.chainLog = overrides.chainLog;
    if (overrides.searchLog != 0) cParams.searchLog = overrides.searchLog;
    if (overrides.minMatch != 0) cParams.minMatch = overrides.minMatch;
    if (overrides.targetLength != 0) cParams.targetLength = overrides.targetLength;
    if (overrides.strategy != 0) cParams.strategy = overrides.strategy;
}

// -------------------------------------------------------------------------
//  The strategy-default cparam matrix (4 rows × 23 levels).
// -------------------------------------------------------------------------
//
// Preserved value-for-value from upstream (lines 38656..39492); translate-c's
// wrappers are flattened to plain integer literals. Row 0 targets >=256 KiB,
// row 1 targets 256 KiB, row 2 targets 128 KiB, row 3 targets <=16 KiB.

const P = ZSTD_compressionParameters;
fn cp(wl: u32, cl: u32, hl: u32, sl: u32, mm: u32, tl: u32, st: c_int) P {
    return .{
        .windowLog = wl,
        .chainLog = cl,
        .hashLog = hl,
        .searchLog = sl,
        .minMatch = mm,
        .targetLength = tl,
        .strategy = @bitCast(st),
    };
}

pub const ZSTD_defaultCParameters: [4][23]ZSTD_compressionParameters = .{
    // Row 0 — window 19..27 (>256 KiB)
    .{
        cp(19, 12, 13, 1, 6, 1, ZSTD_fast), //  level 0 (unused; filled as -1 synonym)
        cp(19, 13, 14, 1, 7, 0, ZSTD_fast),
        cp(20, 15, 16, 1, 6, 0, ZSTD_fast),
        cp(21, 16, 17, 1, 5, 0, ZSTD_dfast),
        cp(21, 18, 18, 1, 5, 0, ZSTD_dfast),
        cp(21, 18, 19, 3, 5, 2, ZSTD_greedy),
        cp(21, 18, 19, 3, 5, 4, ZSTD_lazy),
        cp(21, 19, 20, 4, 5, 8, ZSTD_lazy),
        cp(21, 19, 20, 4, 5, 16, ZSTD_lazy2),
        cp(22, 20, 21, 4, 5, 16, ZSTD_lazy2),
        cp(22, 21, 22, 5, 5, 16, ZSTD_lazy2),
        cp(22, 21, 22, 6, 5, 16, ZSTD_lazy2),
        cp(22, 22, 23, 6, 5, 32, ZSTD_lazy2),
        cp(22, 22, 22, 4, 5, 32, ZSTD_btlazy2),
        cp(22, 22, 23, 5, 5, 32, ZSTD_btlazy2),
        cp(22, 23, 23, 6, 5, 32, ZSTD_btlazy2),
        cp(22, 22, 22, 5, 5, 48, ZSTD_btopt),
        cp(23, 23, 22, 5, 4, 64, ZSTD_btopt),
        cp(23, 23, 22, 6, 3, 64, ZSTD_btultra),
        cp(23, 24, 22, 7, 3, 256, ZSTD_btultra2),
        cp(25, 25, 23, 7, 3, 256, ZSTD_btultra2),
        cp(26, 26, 24, 7, 3, 512, ZSTD_btultra2),
        cp(27, 27, 25, 9, 3, 999, ZSTD_btultra2),
    },
    // Row 1 — window 18 (256 KiB)
    .{
        cp(18, 12, 13, 1, 5, 1, ZSTD_fast),
        cp(18, 13, 14, 1, 6, 0, ZSTD_fast),
        cp(18, 14, 14, 1, 5, 0, ZSTD_dfast),
        cp(18, 16, 16, 1, 4, 0, ZSTD_dfast),
        cp(18, 16, 17, 3, 5, 2, ZSTD_greedy),
        cp(18, 17, 18, 5, 5, 2, ZSTD_greedy),
        cp(18, 18, 19, 3, 5, 4, ZSTD_lazy),
        cp(18, 18, 19, 4, 4, 4, ZSTD_lazy),
        cp(18, 18, 19, 4, 4, 8, ZSTD_lazy2),
        cp(18, 18, 19, 5, 4, 8, ZSTD_lazy2),
        cp(18, 18, 19, 6, 4, 8, ZSTD_lazy2),
        cp(18, 18, 19, 5, 4, 12, ZSTD_btlazy2),
        cp(18, 19, 19, 7, 4, 12, ZSTD_btlazy2),
        cp(18, 18, 19, 4, 4, 16, ZSTD_btopt),
        cp(18, 18, 19, 4, 3, 32, ZSTD_btopt),
        cp(18, 18, 19, 6, 3, 128, ZSTD_btopt),
        cp(18, 19, 19, 6, 3, 128, ZSTD_btultra),
        cp(18, 19, 19, 8, 3, 256, ZSTD_btultra),
        cp(18, 19, 19, 6, 3, 128, ZSTD_btultra2),
        cp(18, 19, 19, 8, 3, 256, ZSTD_btultra2),
        cp(18, 19, 19, 10, 3, 512, ZSTD_btultra2),
        cp(18, 19, 19, 12, 3, 512, ZSTD_btultra2),
        cp(18, 19, 19, 13, 3, 999, ZSTD_btultra2),
    },
    // Row 2 — window 17 (128 KiB)
    .{
        cp(17, 12, 12, 1, 5, 1, ZSTD_fast),
        cp(17, 12, 13, 1, 6, 0, ZSTD_fast),
        cp(17, 13, 15, 1, 5, 0, ZSTD_fast),
        cp(17, 15, 16, 2, 5, 0, ZSTD_dfast),
        cp(17, 17, 17, 2, 4, 0, ZSTD_dfast),
        cp(17, 16, 17, 3, 4, 2, ZSTD_greedy),
        cp(17, 16, 17, 3, 4, 4, ZSTD_lazy),
        cp(17, 16, 17, 3, 4, 8, ZSTD_lazy2),
        cp(17, 16, 17, 4, 4, 8, ZSTD_lazy2),
        cp(17, 16, 17, 5, 4, 8, ZSTD_lazy2),
        cp(17, 16, 17, 6, 4, 8, ZSTD_lazy2),
        cp(17, 17, 17, 5, 4, 8, ZSTD_btlazy2),
        cp(17, 18, 17, 7, 4, 12, ZSTD_btlazy2),
        cp(17, 18, 17, 3, 4, 12, ZSTD_btopt),
        cp(17, 18, 17, 4, 3, 32, ZSTD_btopt),
        cp(17, 18, 17, 6, 3, 256, ZSTD_btopt),
        cp(17, 18, 17, 6, 3, 128, ZSTD_btultra),
        cp(17, 18, 17, 8, 3, 256, ZSTD_btultra),
        cp(17, 18, 17, 10, 3, 512, ZSTD_btultra),
        cp(17, 18, 17, 5, 3, 256, ZSTD_btultra2),
        cp(17, 18, 17, 7, 3, 512, ZSTD_btultra2),
        cp(17, 18, 17, 9, 3, 512, ZSTD_btultra2),
        cp(17, 18, 17, 11, 3, 999, ZSTD_btultra2),
    },
    // Row 3 — window 14 (<=16 KiB)
    .{
        cp(14, 12, 13, 1, 5, 1, ZSTD_fast),
        cp(14, 14, 15, 1, 5, 0, ZSTD_fast),
        cp(14, 14, 15, 1, 4, 0, ZSTD_fast),
        cp(14, 14, 15, 2, 4, 0, ZSTD_dfast),
        cp(14, 14, 14, 4, 4, 2, ZSTD_greedy),
        cp(14, 14, 14, 3, 4, 4, ZSTD_lazy),
        cp(14, 14, 14, 4, 4, 8, ZSTD_lazy2),
        cp(14, 14, 14, 6, 4, 8, ZSTD_lazy2),
        cp(14, 14, 14, 8, 4, 8, ZSTD_lazy2),
        cp(14, 15, 14, 5, 4, 8, ZSTD_btlazy2),
        cp(14, 15, 14, 9, 4, 8, ZSTD_btlazy2),
        cp(14, 15, 14, 3, 4, 12, ZSTD_btopt),
        cp(14, 15, 14, 4, 3, 24, ZSTD_btopt),
        cp(14, 15, 14, 5, 3, 32, ZSTD_btultra),
        cp(14, 15, 15, 6, 3, 64, ZSTD_btultra),
        cp(14, 15, 15, 7, 3, 256, ZSTD_btultra),
        cp(14, 15, 15, 5, 3, 48, ZSTD_btultra2),
        cp(14, 15, 15, 6, 3, 128, ZSTD_btultra2),
        cp(14, 15, 15, 7, 3, 256, ZSTD_btultra2),
        cp(14, 15, 15, 8, 3, 256, ZSTD_btultra2),
        cp(14, 15, 15, 8, 3, 512, ZSTD_btultra2),
        cp(14, 15, 15, 9, 3, 512, ZSTD_btultra2),
        cp(14, 15, 15, 10, 3, 999, ZSTD_btultra2),
    },
};

// -------------------------------------------------------------------------
//  Row-size bucketing + getCParams_internal
// -------------------------------------------------------------------------

pub fn ZSTD_getCParamRowSize(
    srcSizeHint: U64,
    dictSizeIn: usize,
    mode: ZSTD_CParamMode_e,
) callconv(.c) U64 {
    var dictSize = dictSizeIn;
    // For attachDict mode upstream zeroes dictSize so it's not counted toward
    // the row-picker; createCDict/noAttachDict/unknown include it.
    if (mode == ZSTD_cpm_attachDict) dictSize = 0;

    const unknown: bool = srcSizeHint == std.math.maxInt(c_ulonglong);
    if (unknown and dictSize == 0) return std.math.maxInt(U64);
    const addedSize: usize = if (unknown and dictSize > 0) 500 else 0;
    return srcSizeHint +% @as(U64, dictSize) +% @as(U64, addedSize);
}

// Port of line 32488..32515.
pub fn ZSTD_dictAndWindowLog(
    windowLog: U32,
    srcSize: U64,
    dictSize: U64,
) callconv(.c) U32 {
    const maxWindowSize: U64 = @as(U64, 1) << (if (@sizeOf(usize) == 4) 30 else 31);
    if (dictSize == 0) return windowLog;
    const windowSize: U64 = @as(U64, 1) << @intCast(windowLog);
    const dictAndWindowSize: U64 = dictSize +% windowSize;
    if (windowSize >= dictSize +% srcSize) return windowLog;
    if (dictAndWindowSize >= maxWindowSize)
        return if (@sizeOf(usize) == 4) 30 else 31;
    return ZSTD_highbit32(@truncate(dictAndWindowSize -% 1)) +% 1;
}

// Port of line 32413..32486 — saturate each cParams field against its bounds.
pub fn ZSTD_clampCParams(arg_cParams: ZSTD_compressionParameters) callconv(.c) ZSTD_compressionParameters {
    var cParams = arg_cParams;
    const clampField = struct {
        fn run(val: *c_uint, param: c_int) void {
            const b = ZSTD_cParam_getBounds(@bitCast(param));
            const v: c_int = @bitCast(val.*);
            if (v < b.lowerBound) val.* = @bitCast(b.lowerBound);
            if (v > b.upperBound) val.* = @bitCast(b.upperBound);
        }
    };
    clampField.run(&cParams.windowLog, ZSTD_c_windowLog);
    clampField.run(&cParams.chainLog, ZSTD_c_chainLog);
    clampField.run(&cParams.hashLog, ZSTD_c_hashLog);
    clampField.run(&cParams.searchLog, ZSTD_c_searchLog);
    clampField.run(&cParams.minMatch, ZSTD_c_minMatch);
    clampField.run(&cParams.targetLength, ZSTD_c_targetLength);
    clampField.run(&cParams.strategy, ZSTD_c_strategy);
    return cParams;
}

// Port of line 32517..32607 — resolve cparams for a final (srcSize, dictSize).
pub fn ZSTD_adjustCParams_internal(
    arg_cPar: ZSTD_compressionParameters,
    arg_srcSize: c_ulonglong,
    arg_dictSize: usize,
    mode: ZSTD_CParamMode_e,
    useRowMatchFinderIn: ZSTD_ParamSwitch_e,
) callconv(.c) ZSTD_compressionParameters {
    var cPar = arg_cPar;
    var srcSize = arg_srcSize;
    var dictSize = arg_dictSize;
    var useRowMatchFinder = useRowMatchFinderIn;

    const minSrcSize: U64 = 513;
    const maxWindowResizeLog: u6 = if (@sizeOf(usize) == 4) 29 else 30;
    const maxWindowResize: U64 = @as(U64, 1) << maxWindowResizeLog;

    // Mode-specific srcSize/dictSize adjustments.
    switch (mode) {
        ZSTD_cpm_noAttachDict, ZSTD_cpm_unknown => {},
        ZSTD_cpm_createCDict => {
            if (dictSize != 0 and srcSize == std.math.maxInt(c_ulonglong)) {
                srcSize = minSrcSize;
            }
        },
        ZSTD_cpm_attachDict => {
            dictSize = 0;
        },
        else => {},
    }

    // Shrink windowLog to fit src+dict if both are small.
    if (srcSize <= maxWindowResize and @as(U64, dictSize) <= maxWindowResize) {
        const tSize: U32 = @truncate(srcSize +% @as(U64, dictSize));
        const hashSizeMin: U32 = 1 << 6;
        const srcLog: U32 = if (tSize < hashSizeMin)
            6
        else
            ZSTD_highbit32(tSize -% 1) +% 1;
        if (cPar.windowLog > srcLog) cPar.windowLog = srcLog;
    }

    // Cap hashLog/chainLog by dict+window span.
    if (srcSize != std.math.maxInt(c_ulonglong)) {
        const dictAndWindowLog = ZSTD_dictAndWindowLog(
            cPar.windowLog,
            srcSize,
            @as(U64, dictSize),
        );
        const cycleLog = ZSTD_cycleLog(cPar.chainLog, cPar.strategy);
        if (cPar.hashLog > dictAndWindowLog +% 1) cPar.hashLog = dictAndWindowLog +% 1;
        if (cycleLog > dictAndWindowLog) cPar.chainLog -%= cycleLog -% dictAndWindowLog;
    }

    if (cPar.windowLog < 10) cPar.windowLog = 10;

    // CDict-tagged-index mode: short-cache hashLog/chainLog limit.
    if (mode == ZSTD_cpm_createCDict and ZSTD_CDictIndicesAreTagged(&cPar) != 0) {
        const maxShortCacheHashLog: U32 = 32 - 8;
        if (cPar.hashLog > maxShortCacheHashLog) cPar.hashLog = maxShortCacheHashLog;
        if (cPar.chainLog > maxShortCacheHashLog) cPar.chainLog = maxShortCacheHashLog;
    }

    if (useRowMatchFinder == ZSTD_ps_auto) useRowMatchFinder = ZSTD_ps_enable;
    if (ZSTD_rowMatchFinderUsed(cPar.strategy, useRowMatchFinder) != 0) {
        const rowLog: U32 = @min(@max(@as(U32, 4), cPar.searchLog), 6);
        const maxRowHashLog: U32 = 32 - 8;
        const maxHashLog: U32 = maxRowHashLog +% rowLog;
        if (cPar.hashLog > maxHashLog) cPar.hashLog = maxHashLog;
    }

    return cPar;
}

// Port of line 32608..32647.
pub fn ZSTD_getCParams_internal(
    compressionLevel: c_int,
    srcSizeHint: c_ulonglong,
    dictSize: usize,
    mode: ZSTD_CParamMode_e,
) callconv(.c) ZSTD_compressionParameters {
    const rSize: U64 = ZSTD_getCParamRowSize(srcSizeHint, dictSize, mode);
    const tableID: U32 = @as(U32, @intFromBool(rSize <= 256 * (1 << 10))) +%
        @as(U32, @intFromBool(rSize <= 128 * (1 << 10))) +%
        @as(U32, @intFromBool(rSize <= 16 * (1 << 10)));

    var row: c_int = undefined;
    if (compressionLevel == 0) {
        row = 3;
    } else if (compressionLevel < 0) {
        row = 0;
    } else if (compressionLevel > 22) {
        row = 22;
    } else {
        row = compressionLevel;
    }

    var cparams = ZSTD_defaultCParameters[@intCast(tableID)][@intCast(row)];
    if (compressionLevel < 0) {
        const clamped: c_int = @max(ZSTD_minCLevel(), compressionLevel);
        cparams.targetLength = @bitCast(-clamped);
    }
    return ZSTD_adjustCParams_internal(cparams, srcSizeHint, dictSize, mode, ZSTD_ps_auto);
}

// Port of line 32649..32669.
pub fn ZSTD_getParams_internal(
    compressionLevel: c_int,
    srcSizeHint: c_ulonglong,
    dictSize: usize,
    mode: ZSTD_CParamMode_e,
) callconv(.c) ZSTD_parameters {
    const cParams = ZSTD_getCParams_internal(compressionLevel, srcSizeHint, dictSize, mode);
    var params: ZSTD_parameters = .{};
    params.cParams = cParams;
    params.fParams.contentSizeFlag = 1;
    return params;
}

// -------------------------------------------------------------------------
//  dedicatedDictSearch hash-rewire
// -------------------------------------------------------------------------

// Port of line 32327..32344.
pub fn ZSTD_dedicatedDictSearch_getCParams(
    compressionLevel: c_int,
    dictSize: usize,
) callconv(.c) ZSTD_compressionParameters {
    var cParams = ZSTD_getCParams_internal(compressionLevel, 0, dictSize, ZSTD_cpm_createCDict);
    switch (cParams.strategy) {
        @as(c_uint, @bitCast(ZSTD_fast)), @as(c_uint, @bitCast(ZSTD_dfast)) => {},
        @as(c_uint, @bitCast(ZSTD_greedy)),
        @as(c_uint, @bitCast(ZSTD_lazy)),
        @as(c_uint, @bitCast(ZSTD_lazy2)),
        => {
            cParams.hashLog +%= 2;
        },
        @as(c_uint, @bitCast(ZSTD_btlazy2)),
        @as(c_uint, @bitCast(ZSTD_btopt)),
        @as(c_uint, @bitCast(ZSTD_btultra)),
        @as(c_uint, @bitCast(ZSTD_btultra2)),
        => {},
        else => {},
    }
    return cParams;
}

pub fn ZSTD_dedicatedDictSearch_isSupported(
    cParams: *const ZSTD_compressionParameters,
) callconv(.c) c_int {
    return @intFromBool(
        cParams.strategy >= @as(c_uint, @bitCast(ZSTD_greedy)) and
            cParams.strategy <= @as(c_uint, @bitCast(ZSTD_lazy2)) and
            cParams.hashLog > cParams.chainLog and
            cParams.chainLog <= 24,
    );
}

pub fn ZSTD_dedicatedDictSearch_revertCParams(
    cParams: *ZSTD_compressionParameters,
) callconv(.c) void {
    switch (cParams.strategy) {
        @as(c_uint, @bitCast(ZSTD_fast)), @as(c_uint, @bitCast(ZSTD_dfast)) => {},
        @as(c_uint, @bitCast(ZSTD_greedy)),
        @as(c_uint, @bitCast(ZSTD_lazy)),
        @as(c_uint, @bitCast(ZSTD_lazy2)),
        => {
            cParams.hashLog -%= 2;
            if (cParams.hashLog < 6) cParams.hashLog = 6;
        },
        @as(c_uint, @bitCast(ZSTD_btlazy2)),
        @as(c_uint, @bitCast(ZSTD_btopt)),
        @as(c_uint, @bitCast(ZSTD_btultra)),
        @as(c_uint, @bitCast(ZSTD_btultra2)),
        => {},
        else => {},
    }
}

// -------------------------------------------------------------------------
//  Public entry points (C-ABI exports)
// -------------------------------------------------------------------------

pub export fn ZSTD_getCParams(
    compressionLevel: c_int,
    srcSizeHintIn: c_ulonglong,
    dictSize: usize,
) ZSTD_compressionParameters {
    // srcSizeHint == 0 → "unknown" upstream.
    const srcSizeHint: c_ulonglong = if (srcSizeHintIn == 0)
        std.math.maxInt(c_ulonglong)
    else
        srcSizeHintIn;
    return ZSTD_getCParams_internal(compressionLevel, srcSizeHint, dictSize, ZSTD_cpm_unknown);
}

pub export fn ZSTD_getParams(
    compressionLevel: c_int,
    srcSizeHintIn: c_ulonglong,
    dictSize: usize,
) ZSTD_parameters {
    const srcSizeHint: c_ulonglong = if (srcSizeHintIn == 0)
        std.math.maxInt(c_ulonglong)
    else
        srcSizeHintIn;
    return ZSTD_getParams_internal(compressionLevel, srcSizeHint, dictSize, ZSTD_cpm_unknown);
}

pub export fn ZSTD_adjustCParams(
    cParIn: ZSTD_compressionParameters,
    srcSizeIn: c_ulonglong,
    dictSize: usize,
) ZSTD_compressionParameters {
    const cPar = ZSTD_clampCParams(cParIn);
    const srcSize: c_ulonglong = if (srcSizeIn == 0)
        std.math.maxInt(c_ulonglong)
    else
        srcSizeIn;
    return ZSTD_adjustCParams_internal(cPar, srcSize, dictSize, ZSTD_cpm_unknown, ZSTD_ps_auto);
}

// Port of line 31552..31574.
pub export fn ZSTD_getCParamsFromCCtxParams(
    CCtxParams: *const ZSTD_CCtx_params,
    srcSizeHintIn: U64,
    dictSize: usize,
    mode: ZSTD_CParamMode_e,
) ZSTD_compressionParameters {
    var srcSizeHint = srcSizeHintIn;
    if (srcSizeHint == std.math.maxInt(U64) and CCtxParams.srcSizeHint > 0) {
        srcSizeHint = @intCast(CCtxParams.srcSizeHint);
    }
    var cParams = ZSTD_getCParams_internal(
        CCtxParams.compressionLevel,
        srcSizeHint,
        dictSize,
        mode,
    );
    if (CCtxParams.ldmParams.enableLdm == @as(c_uint, @bitCast(ZSTD_ps_enable))) {
        cParams.windowLog = 27;
    }
    ZSTD_overrideCParams(&cParams, &CCtxParams.cParams);
    return ZSTD_adjustCParams_internal(
        cParams,
        srcSizeHint,
        dictSize,
        mode,
        CCtxParams.useRowMatchFinder,
    );
}

// -------------------------------------------------------------------------
//  reset_compressedBlockState — used by CCtx/CDict reset paths.
//  Slice 5b implements a minimal version: zstd_compress.zig doesn't yet carry
//  the `blockState` field on its CCtx (that arrives in slice 5c), so we keep
//  the function operating on a local struct hint. Callers inside 5c will feed
//  us a real pointer.
// -------------------------------------------------------------------------

pub const repStartValue: [3]U32 = .{ 1, 4, 8 };

// Opaque forward for the real state — 5c wires in the entropy tables.
pub const ZSTD_compressedBlockState_minimal = extern struct {
    rep: [3]U32 = .{ 0, 0, 0 },
    // Padding that `ZSTD_compressedBlockState_t` has (huf+fse tables); in
    // slice 5c this becomes the real ZSTD_entropyCTables_t.
    _entropy_pad: extern struct {
        huf_repeatMode: c_uint = 0,
        fse_offcode_repeatMode: c_uint = 0,
        fse_matchlength_repeatMode: c_uint = 0,
        fse_litlength_repeatMode: c_uint = 0,
    } = .{},
};

pub fn ZSTD_reset_compressedBlockState_minimal(
    bs: *ZSTD_compressedBlockState_minimal,
) callconv(.c) void {
    var i: usize = 0;
    while (i < 3) : (i += 1) bs.rep[i] = repStartValue[i];
    bs._entropy_pad.huf_repeatMode = 0; // HUF_repeat_none
    bs._entropy_pad.fse_offcode_repeatMode = 0; // FSE_repeat_none
    bs._entropy_pad.fse_matchlength_repeatMode = 0;
    bs._entropy_pad.fse_litlength_repeatMode = 0;
}

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------

test "getCParams returns windowLog >= 10" {
    const p = ZSTD_getCParams(3, 0, 0);
    try std.testing.expect(p.windowLog >= 10);
    try std.testing.expect(p.windowLog <= 31);
}

test "getCParams clamps level > 22 to row 22" {
    const a = ZSTD_getCParams(22, 0, 0);
    const b = ZSTD_getCParams(99, 0, 0);
    try std.testing.expectEqual(a.windowLog, b.windowLog);
    try std.testing.expectEqual(a.strategy, b.strategy);
}

test "getCParams level 0 == level 3" {
    const l0 = ZSTD_getCParams(0, 0, 0);
    const l3 = ZSTD_getCParams(3, 0, 0);
    try std.testing.expectEqual(l3.windowLog, l0.windowLog);
    try std.testing.expectEqual(l3.strategy, l0.strategy);
}

test "getCParamRowSize attachDict zeroes dictSize" {
    const a = ZSTD_getCParamRowSize(1024, 100000, ZSTD_cpm_attachDict);
    try std.testing.expectEqual(@as(U64, 1024), a);
    const b = ZSTD_getCParamRowSize(1024, 100000, ZSTD_cpm_noAttachDict);
    try std.testing.expectEqual(@as(U64, 101024), b);
}

test "defaultCParameters table shape" {
    try std.testing.expectEqual(@as(usize, 4), ZSTD_defaultCParameters.len);
    try std.testing.expectEqual(@as(usize, 23), ZSTD_defaultCParameters[0].len);
    // Row 0 level 3 should match upstream: wlog=21, chain=16, hash=17,
    // search=1, mm=5, tgt=0, strategy=dfast.
    const p = ZSTD_defaultCParameters[0][3];
    try std.testing.expectEqual(@as(u32, 21), p.windowLog);
    try std.testing.expectEqual(@as(u32, 16), p.chainLog);
    try std.testing.expectEqual(@as(u32, 17), p.hashLog);
    try std.testing.expectEqual(@as(c_uint, @bitCast(ZSTD_dfast)), p.strategy);
}

test "dedicatedDictSearch_getCParams boosts hashLog on lazy" {
    // Level 10 on a biggish dict lands in a lazy-family strategy.
    const before = ZSTD_getCParams_internal(10, 0, 1024 * 1024, ZSTD_cpm_createCDict);
    const after = ZSTD_dedicatedDictSearch_getCParams(10, 1024 * 1024);
    if (before.strategy >= @as(c_uint, @bitCast(ZSTD_greedy)) and
        before.strategy <= @as(c_uint, @bitCast(ZSTD_lazy2)))
    {
        try std.testing.expectEqual(before.hashLog + 2, after.hashLog);
    }
}
