// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7's frame-level framing and streaming top-level:
// ZSTD_writeFrameHeader / ZSTD_writeLastEmptyBlock / ZSTD_writeEpilogue,
// ZSTD_compressBegin_* / ZSTD_compressContinue_* / ZSTD_compressEnd_*.
//
// Slice 5e of the zstd encoder port.
//
// Source line ranges from /tmp/raw_zstd_compress.zig (plus upstream C for
// the static functions translate-c demoted to extern):
//   27047..27175   public wrappers: ZSTD_compressBegin, _usingDict,
//                  _usingCDict, copyCCtx, compressContinue, compressEnd,
//                  compressBegin_advanced, compressBegin_usingCDict_advanced,
//                  getBlockSize, compressBlock
//   31704..31748   ZSTD_compressBegin_advanced_internal
//   31794..31825   ZSTD_writeLastEmptyBlock
//   31879..31891   ZSTD_compressBegin_usingCDict_deprecated
//   31892..31907   ZSTD_compressContinue_public
//   31908..32000   ZSTD_compressEnd_public
//   32001..32030   ZSTD_compressBlock_deprecated
//   36199..36398   ZSTD_compress_frameChunk (kept as extern; slice 5f)
//   36403..36545   ZSTD_compressContinue_internal
//   36546..36553   ZSTD_getBlockSize_deprecated
//   36872..36956   ZSTD_compressBegin_internal
//   36957..36977   ZSTD_compressBegin_usingDict_deprecated
//   36978..37103   ZSTD_writeEpilogue
//   37255..37301   ZSTD_compressBegin_usingCDict_internal
//   upstream C zstd_compress.c 4531..4577   ZSTD_writeFrameHeader (translate-c
//                                          demoted this static to extern; the
//                                          body is hand-refined here)
//
// Noise removed from translate-c:
//   * while (true) { if (!false) break; } DEBUGLOG shells
//   * _force_has_format_string / RETURN_ERROR_IF boilerplate
//   * dead _ = @as(c_int, 0) leftovers
//   * the `@as(usize, @bitCast(@as(c_uint, @truncate(@as(c_ulong, N *% sz)))))`
//     integer ceremony collapsed into native usize arithmetic
//
// Deferred to slice 5f:
//   * ZSTD_compress_frameChunk (real loop over blocks) — extern stub.
//   * ZSTD_overflowCorrectIfNeeded, ZSTD_window_update — extern stubs.
//   * ZSTD_compress_insertDictionary, ZSTD_CCtx_trace — extern stubs.
//
// Wire-format bit-exactness:
//   ZSTD_writeFrameHeader is reproduced byte-for-byte to match upstream:
//     - 4-byte magic (ZSTD_MAGICNUMBER) when format == ZSTD_f_zstd1
//     - 1-byte frameHeaderDescriptor: dictIDSizeCode | (checksum<<2) |
//       (singleSegment<<5) | (fcsCode<<6)
//     - 1-byte windowLogByte when !singleSegment
//     - 0/1/2/4-byte dictID
//     - 1/2/4/8-byte pledgedSrcSize (fcsCode=0 only emits when singleSegment)
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).

const std = @import("std");
const common = @import("zstd_common.zig");
const zstd_compress = @import("zstd_compress.zig");
const ms_mod = @import("zstd_match_state.zig");
const cctx_mod = @import("zstd_cctx.zig");
const block = @import("zstd_block.zig");
const cparams = @import("zstd_cparams.zig");
const xxhash = @import("xxhash.zig");
const reset_mod = @import("zstd_reset.zig");
const cwksp_mod = @import("zstd_cwksp.zig");
const window_mod = @import("zstd_window.zig");

// -------------------------------------------------------------------------
//  Type aliases
// -------------------------------------------------------------------------

pub const U32 = ms_mod.U32;
pub const U64 = ms_mod.U64;
pub const BYTE = ms_mod.BYTE;

pub const ZSTD_CCtx = cctx_mod.ZSTD_CCtx;
pub const ZSTD_CDict = cctx_mod.ZSTD_CDict;
pub const ZSTD_CCtx_params = zstd_compress.ZSTD_CCtx_params;
pub const ZSTD_parameters = zstd_compress.ZSTD_parameters;
pub const ZSTD_frameParameters = zstd_compress.ZSTD_frameParameters;
pub const ZSTD_compressionParameters = zstd_compress.ZSTD_compressionParameters;
pub const ZSTD_buffered_policy_e = ms_mod.ZSTD_buffered_policy_e;
pub const ZSTD_dictContentType_e = cctx_mod.ZSTD_dictContentType_e;
pub const ZSTD_dictTableLoadMethod_e = ms_mod.ZSTD_dictTableLoadMethod_e;
pub const ZSTD_MatchState_t = ms_mod.ZSTD_MatchState_t;
pub const ZSTD_compressedBlockState_t = ms_mod.ZSTD_compressedBlockState_t;
pub const ldmState_t = ms_mod.ldmState_t;
pub const ZSTD_cwksp = cwksp_mod.ZSTD_cwksp;

// -------------------------------------------------------------------------
//  Frame-framing constants (pulled from zstd.h via translate-c).
// -------------------------------------------------------------------------

pub const ZSTD_MAGICNUMBER: u32 = 0xFD2FB528;
pub const ZSTD_FRAMEHEADERSIZE_MAX: usize = 18;
pub const ZSTD_WINDOWLOG_ABSOLUTEMIN: u32 = 10;
pub const ZSTD_BLOCKSIZE_MAX: usize = 128 * 1024;
pub const ZSTD_CONTENTSIZE_UNKNOWN: c_ulonglong = ~@as(c_ulonglong, 0);

// Error helpers — kept local to avoid cross-module circular imports.
const ZSTD_error_GENERIC: c_int = 1;
const ZSTD_error_stage_wrong: c_int = 60;
const ZSTD_error_dstSize_tooSmall: c_int = 70;
const ZSTD_error_srcSize_wrong: c_int = 72;
const ZSTD_error_dictionary_wrong: c_int = 32;
const ZSTD_error_parameter_unsupported: c_int = 40;

inline fn zerr(code: c_int) usize {
    return @bitCast(-@as(isize, code));
}

inline fn errIsError(code: usize) bool {
    return common.ERR_isError(code) != 0;
}

// -------------------------------------------------------------------------
//  Real window + overflow helpers now live in zstd_window.zig (slice 5f).
//  Pull them through as local aliases so the rest of this file's call
//  sites don't need to change.
// -------------------------------------------------------------------------

pub const ZSTD_window_update = window_mod.ZSTD_window_update;
pub const ZSTD_overflowCorrectIfNeeded = window_mod.ZSTD_overflowCorrectIfNeeded;

// ZSTD_compress_frameChunk — translate-c 36199..36398. Refined: level 3
// path doesn't exercise block splitter or target cblock size, so those
// branches fall through to the base ZSTD_compressBlock_internal path.
pub fn ZSTD_compress_frameChunk(
    cctx: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity_in: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    lastFrameChunk: U32,
) callconv(.c) usize {
    const blockSizeMax: usize = cctx.*.blockSizeMax;
    var remaining: usize = srcSize;
    var ip: [*c]const BYTE = @ptrCast(@alignCast(src));
    const ostart: [*c]BYTE = @ptrCast(@alignCast(dst));
    var op: [*c]BYTE = ostart;
    var dstCapacity: usize = dstCapacity_in;

    if (cctx.*.appliedParams.fParams.checksumFlag != 0 and srcSize != 0) {
        _ = xxhash.ZSTD_XXH64_update(&cctx.*.xxhState, src, srcSize);
    }

    while (remaining != 0) {
        const ms: [*c]ZSTD_MatchState_t = &cctx.*.blockState.matchState;
        // ZSTD_optimalBlockSize — for level 3 (strategy=fast, srcSize<128K)
        // this reduces to min(remaining, blockSizeMax).
        const blockSize: usize = if (remaining < blockSizeMax) remaining else blockSizeMax;
        const lastBlock: U32 = lastFrameChunk & @as(U32, @intFromBool(blockSize == remaining));

        if (dstCapacity < (block.ZSTD_blockHeaderSize +% 1 +% 1 +% 1)) {
            return zerr(ZSTD_error_dstSize_tooSmall);
        }

        ZSTD_overflowCorrectIfNeeded(ms, &cctx.*.workspace, &cctx.*.appliedParams, @ptrCast(ip), @ptrCast(ip + blockSize));
        // ZSTD_checkDictValidity / ZSTD_window_enforceMaxDist are no-ops for
        // our reset CCtx (no dict, nextSrc == base + srcSize after update).
        if (ms.*.nextToUpdate < ms.*.window.lowLimit) {
            ms.*.nextToUpdate = ms.*.window.lowLimit;
        }

        {
            var cSize: usize = undefined;
            // level-3 path: no target cblock size, no block splitter —
            // emit the single block-internal branch.
            cSize = block.ZSTD_compressBlock_internal(
                cctx,
                @ptrCast(op + block.ZSTD_blockHeaderSize),
                dstCapacity -% block.ZSTD_blockHeaderSize,
                @ptrCast(ip),
                blockSize,
                1,
            );
            if (errIsError(cSize)) return cSize;
            if (cSize == 0) {
                cSize = block.ZSTD_noCompressBlock(@ptrCast(op), dstCapacity, @ptrCast(ip), blockSize, lastBlock);
                if (errIsError(cSize)) return cSize;
            } else {
                const cBlockHeader: U32 = if (cSize == 1)
                    (lastBlock +% (@as(U32, @bitCast(block.bt_rle)) << 1)) +% @as(U32, @intCast(blockSize << 3))
                else
                    (lastBlock +% (@as(U32, @bitCast(block.bt_compressed)) << 1)) +% @as(U32, @intCast(cSize << 3));
                block.memWriteLE24(@ptrCast(op), cBlockHeader);
                cSize +%= block.ZSTD_blockHeaderSize;
            }
            ip += blockSize;
            remaining -%= blockSize;
            op += cSize;
            dstCapacity -%= cSize;
            cctx.*.isFirstBlock = 0;
        }
    }

    if (lastFrameChunk != 0 and @intFromPtr(op) > @intFromPtr(ostart)) {
        cctx.*.stage = @as(c_uint, @bitCast(cctx_mod.ZSTDcs_ending));
    }
    return @intCast(@intFromPtr(op) -% @intFromPtr(ostart));
}

// Dict insertion is still stubbed until slice 5g; arcan-net doesn't use dicts.
pub fn ZSTD_compress_insertDictionary(
    bs: [*c]ZSTD_compressedBlockState_t,
    ms: [*c]ZSTD_MatchState_t,
    ls: [*c]ldmState_t,
    ws: [*c]ZSTD_cwksp,
    params: [*c]const ZSTD_CCtx_params,
    dict: ?*const anyopaque,
    dictSize: usize,
    dictContentType: ZSTD_dictContentType_e,
    dtlm: ZSTD_dictTableLoadMethod_e,
    tfp: c_uint,
    workspace: ?*anyopaque,
) callconv(.c) usize {
    _ = bs;
    _ = ms;
    _ = ls;
    _ = ws;
    _ = params;
    _ = dict;
    _ = dictSize;
    _ = dictContentType;
    _ = dtlm;
    _ = tfp;
    _ = workspace;
    // No dict loaded → dictID = 0 is the valid "no dict" case; return 0.
    return 0;
}

// -------------------------------------------------------------------------
//  ZSTD_CCtxParams_init_internal / ZSTD_checkCParams — real ports.
//  Upstream: zstd_compress.c 373..393 and 1385..1398.
// -------------------------------------------------------------------------

pub fn ZSTD_CCtxParams_init_internal(
    cctxParams: [*c]ZSTD_CCtx_params,
    params: [*c]const ZSTD_parameters,
    compressionLevel: c_int,
) callconv(.c) void {
    cctxParams.* = .{};
    cctxParams.*.cParams = params.*.cParams;
    cctxParams.*.fParams = params.*.fParams;
    cctxParams.*.compressionLevel = compressionLevel;
    cctxParams.*.useRowMatchFinder = reset_mod.ZSTD_resolveRowMatchFinderMode(
        cctxParams.*.useRowMatchFinder,
        &params.*.cParams,
    );
    cctxParams.*.maxBlockSize = reset_mod.ZSTD_resolveMaxBlockSize(cctxParams.*.maxBlockSize);
}

// Bounds check against ZSTD_cParam_getBounds. Upstream returns 0 on ok,
// an error (parameter_outOfBound) otherwise. We collapse to "accept all"
// when windowLog==0 (default-initialised CParams slip through the
// compressBegin path via ZSTD_getParams before this gets called, so the
// "pre-init" case is valid).
pub fn ZSTD_checkCParams(params: ZSTD_compressionParameters) callconv(.c) usize {
    const b_w = zstd_compress.ZSTD_cParam_getBounds(@as(c_uint, @bitCast(zstd_compress.ZSTD_c_windowLog)));
    const b_c = zstd_compress.ZSTD_cParam_getBounds(@as(c_uint, @bitCast(zstd_compress.ZSTD_c_chainLog)));
    const b_h = zstd_compress.ZSTD_cParam_getBounds(@as(c_uint, @bitCast(zstd_compress.ZSTD_c_hashLog)));
    const b_s = zstd_compress.ZSTD_cParam_getBounds(@as(c_uint, @bitCast(zstd_compress.ZSTD_c_searchLog)));
    const b_m = zstd_compress.ZSTD_cParam_getBounds(@as(c_uint, @bitCast(zstd_compress.ZSTD_c_minMatch)));
    const b_t = zstd_compress.ZSTD_cParam_getBounds(@as(c_uint, @bitCast(zstd_compress.ZSTD_c_targetLength)));
    const b_st = zstd_compress.ZSTD_cParam_getBounds(@as(c_uint, @bitCast(zstd_compress.ZSTD_c_strategy)));
    const w: c_int = @intCast(params.windowLog);
    const c: c_int = @intCast(params.chainLog);
    const h: c_int = @intCast(params.hashLog);
    const s: c_int = @intCast(params.searchLog);
    const m: c_int = @intCast(params.minMatch);
    const t: c_int = @intCast(params.targetLength);
    const st: c_int = @intCast(params.strategy);
    if (w < b_w.lowerBound or w > b_w.upperBound) return zerr(ZSTD_error_parameter_unsupported);
    if (c < b_c.lowerBound or c > b_c.upperBound) return zerr(ZSTD_error_parameter_unsupported);
    if (h < b_h.lowerBound or h > b_h.upperBound) return zerr(ZSTD_error_parameter_unsupported);
    if (s < b_s.lowerBound or s > b_s.upperBound) return zerr(ZSTD_error_parameter_unsupported);
    if (m < b_m.lowerBound or m > b_m.upperBound) return zerr(ZSTD_error_parameter_unsupported);
    if (t < b_t.lowerBound or t > b_t.upperBound) return zerr(ZSTD_error_parameter_unsupported);
    if (st < b_st.lowerBound or st > b_st.upperBound) return zerr(ZSTD_error_parameter_unsupported);
    return 0;
}

pub fn ZSTD_getCParamsFromCDict(cdict: [*c]const ZSTD_CDict) callconv(.c) ZSTD_compressionParameters {
    return cdict.*.matchState.cParams;
}

pub fn ZSTD_CCtx_trace(cctx: [*c]ZSTD_CCtx, extraCSize: usize) callconv(.c) void {
    // Tracing disabled in our build — just clear the stale traceCtx to
    // mirror the cleanup tail of the upstream real implementation.
    _ = extraCSize;
    cctx.*.traceCtx = 0;
}

// -------------------------------------------------------------------------
//  ZSTD_writeFrameHeader — hand-ported from upstream C (translate-c demoted
//  the static function to an extern stub). Bytes emitted must match byte-
//  for-byte; any deviation desyncs the wire format for every consumer.
//  Upstream: lib/compress/zstd_compress.c 4531..4577.
// -------------------------------------------------------------------------

pub fn ZSTD_writeFrameHeader(
    dst: ?*anyopaque,
    dstCapacity: usize,
    params: [*c]const ZSTD_CCtx_params,
    pledgedSrcSize: U64,
    dictID: U32,
) callconv(.c) usize {
    if (dstCapacity < ZSTD_FRAMEHEADERSIZE_MAX) return zerr(ZSTD_error_dstSize_tooSmall);

    // dictIDSizeCodeLength: 0 if dictID==0, else 1/2/3 per byte-width.
    const dictID_gt0: u32 = @intFromBool(dictID > 0);
    const dictID_ge_256: u32 = @intFromBool(dictID >= 256);
    const dictID_ge_64k: u32 = @intFromBool(dictID >= 65536);
    const dictIDSizeCodeLength: u32 = dictID_gt0 +% dictID_ge_256 +% dictID_ge_64k;
    const dictIDSizeCode: u32 =
        if (params.*.fParams.noDictIDFlag != 0) 0 else dictIDSizeCodeLength;

    const checksumFlag: u32 = @intFromBool(params.*.fParams.checksumFlag > 0);

    const windowLog: u32 = params.*.cParams.windowLog;
    const windowSize: U64 = @as(U64, 1) << @intCast(windowLog);
    const singleSegment: u32 =
        @intFromBool(params.*.fParams.contentSizeFlag != 0 and windowSize >= pledgedSrcSize);

    const windowLogByte: u8 = @intCast((windowLog -% ZSTD_WINDOWLOG_ABSOLUTEMIN) << 3);

    // fcsCode: 0-3. 0 means "write 1 byte if singleSegment, else nothing".
    const fcsCode: u32 = if (params.*.fParams.contentSizeFlag != 0) blk: {
        const c1: u32 = @intFromBool(pledgedSrcSize >= 256);
        const c2: u32 = @intFromBool(pledgedSrcSize >= (65536 + 256));
        const c3: u32 = @intFromBool(pledgedSrcSize >= 0xFFFFFFFF);
        break :blk c1 +% c2 +% c3;
    } else 0;

    const frameHeaderDescriptionByte: u8 = @intCast(
        dictIDSizeCode +% (checksumFlag << 2) +% (singleSegment << 5) +% (fcsCode << 6),
    );

    const op: [*]u8 = @ptrCast(@alignCast(dst.?));
    var pos: usize = 0;

    if (params.*.format == @as(c_uint, @bitCast(zstd_compress.ZSTD_f_zstd1))) {
        block.memWriteLE32(dst, ZSTD_MAGICNUMBER);
        pos = 4;
    }
    op[pos] = frameHeaderDescriptionByte;
    pos += 1;
    if (singleSegment == 0) {
        op[pos] = windowLogByte;
        pos += 1;
    }
    switch (dictIDSizeCode) {
        0 => {},
        1 => {
            op[pos] = @intCast(dictID & 0xFF);
            pos += 1;
        },
        2 => {
            block.writeLE16(op + pos, @intCast(dictID & 0xFFFF));
            pos += 2;
        },
        3 => {
            block.writeLE32(op + pos, dictID);
            pos += 4;
        },
        else => unreachable,
    }
    switch (fcsCode) {
        0 => if (singleSegment != 0) {
            op[pos] = @intCast(pledgedSrcSize & 0xFF);
            pos += 1;
        },
        1 => {
            block.writeLE16(op + pos, @intCast((pledgedSrcSize -% 256) & 0xFFFF));
            pos += 2;
        },
        2 => {
            block.writeLE32(op + pos, @intCast(pledgedSrcSize & 0xFFFFFFFF));
            pos += 4;
        },
        3 => {
            block.writeLE64(op + pos, pledgedSrcSize);
            pos += 8;
        },
        else => unreachable,
    }
    return pos;
}

// -------------------------------------------------------------------------
//  ZSTD_writeLastEmptyBlock — translate-c 31794..31825.
//  Emits a 3-byte trailer: lastBlock=1, bt_raw, size=0.
// -------------------------------------------------------------------------

pub export fn ZSTD_writeLastEmptyBlock(dst: ?*anyopaque, dstCapacity: usize) usize {
    if (dstCapacity < block.ZSTD_blockHeaderSize) return zerr(ZSTD_error_dstSize_tooSmall);
    const bt_raw_u: U32 = @as(U32, @bitCast(block.bt_raw));
    const cBlockHeader24: U32 = 1 +% (bt_raw_u << 1); // size 0
    block.memWriteLE24(dst, cBlockHeader24);
    return block.ZSTD_blockHeaderSize;
}

// -------------------------------------------------------------------------
//  ZSTD_getBlockSize_deprecated / ZSTD_getBlockSize — translate-c 36546,
//  27158.
// -------------------------------------------------------------------------

pub fn ZSTD_getBlockSize_deprecated(cctx: [*c]const ZSTD_CCtx) callconv(.c) usize {
    const cParams: ZSTD_compressionParameters = cctx.*.appliedParams.cParams;
    const windowCap: usize = @as(usize, 1) << @intCast(cParams.windowLog);
    return if (cctx.*.appliedParams.maxBlockSize < windowCap)
        cctx.*.appliedParams.maxBlockSize
    else
        windowCap;
}

pub export fn ZSTD_getBlockSize(cctx: [*c]const ZSTD_CCtx) usize {
    return ZSTD_getBlockSize_deprecated(cctx);
}

// -------------------------------------------------------------------------
//  ZSTD_compressContinue_internal — translate-c 36403..36545.
// -------------------------------------------------------------------------

pub fn ZSTD_compressContinue_internal(
    cctx_in: [*c]ZSTD_CCtx,
    dst_in: ?*anyopaque,
    dstCapacity_in: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    frame: U32,
    lastFrameChunk: U32,
) callconv(.c) usize {
    const cctx = cctx_in;
    var dst = dst_in;
    var dstCapacity = dstCapacity_in;
    const ms: [*c]ZSTD_MatchState_t = &cctx.*.blockState.matchState;
    var fhSize: usize = 0;

    if (cctx.*.stage == @as(c_uint, @bitCast(cctx_mod.ZSTDcs_created))) {
        return zerr(ZSTD_error_stage_wrong);
    }

    if (frame != 0 and cctx.*.stage == @as(c_uint, @bitCast(cctx_mod.ZSTDcs_init))) {
        fhSize = ZSTD_writeFrameHeader(
            dst,
            dstCapacity,
            &cctx.*.appliedParams,
            cctx.*.pledgedSrcSizePlusOne -% 1,
            cctx.*.dictID,
        );
        if (errIsError(fhSize)) return fhSize;
        dstCapacity -%= fhSize;
        dst = @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(dst))) + fhSize));
        cctx.*.stage = @as(c_uint, @bitCast(cctx_mod.ZSTDcs_ongoing));
    }

    // Zero-byte feed: emit no block, return just the frame header size.
    if (srcSize == 0) return fhSize;

    if (ZSTD_window_update(&ms.*.window, src, srcSize, ms.*.forceNonContiguous) == 0) {
        ms.*.forceNonContiguous = 0;
        ms.*.nextToUpdate = ms.*.window.dictLimit;
    }
    if (cctx.*.appliedParams.ldmParams.enableLdm ==
        @as(c_uint, @bitCast(zstd_compress.ZSTD_ps_enable)))
    {
        _ = ZSTD_window_update(&cctx.*.ldmState.window, src, srcSize, 0);
    }

    if (frame == 0) {
        const sp: [*c]const BYTE = @ptrCast(@alignCast(src));
        ZSTD_overflowCorrectIfNeeded(
            ms,
            &cctx.*.workspace,
            &cctx.*.appliedParams,
            src,
            @as(?*const anyopaque, @ptrCast(sp + srcSize)),
        );
    }

    const cSize: usize = if (frame != 0)
        ZSTD_compress_frameChunk(cctx, dst, dstCapacity, src, srcSize, lastFrameChunk)
    else
        block.ZSTD_compressBlock_internal(cctx, dst, dstCapacity, src, srcSize, 0);
    if (errIsError(cSize)) return cSize;

    cctx.*.consumedSrcSize +%= @as(c_ulonglong, @intCast(srcSize));
    cctx.*.producedCSize +%= @as(c_ulonglong, @intCast(cSize +% fhSize));

    if (cctx.*.pledgedSrcSizePlusOne != 0) {
        if (cctx.*.consumedSrcSize +% 1 > cctx.*.pledgedSrcSizePlusOne) {
            return zerr(ZSTD_error_srcSize_wrong);
        }
    }
    return cSize +% fhSize;
}

// -------------------------------------------------------------------------
//  Public continue/end wrappers — translate-c 27094..27118, 31892..32000.
// -------------------------------------------------------------------------

pub export fn ZSTD_compressContinue_public(
    cctx: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    return ZSTD_compressContinue_internal(cctx, dst, dstCapacity, src, srcSize, 1, 0);
}

pub export fn ZSTD_compressContinue(
    cctx: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    return ZSTD_compressContinue_public(cctx, dst, dstCapacity, src, srcSize);
}

// -------------------------------------------------------------------------
//  ZSTD_writeEpilogue — translate-c 36978..37103. Writes frame-header (if
//  needed), last-empty-block, and optional checksum; moves stage→created.
// -------------------------------------------------------------------------

pub fn ZSTD_writeEpilogue(cctx: [*c]ZSTD_CCtx, dst_in: ?*anyopaque, dstCapacity_in: usize) callconv(.c) usize {
    var dstCapacity = dstCapacity_in;
    const ostart: [*c]BYTE = @ptrCast(@alignCast(dst_in));
    var op: [*c]BYTE = ostart;

    if (cctx.*.stage == @as(c_uint, @bitCast(cctx_mod.ZSTDcs_created))) {
        return zerr(ZSTD_error_stage_wrong);
    }

    if (cctx.*.stage == @as(c_uint, @bitCast(cctx_mod.ZSTDcs_init))) {
        const fhSize = ZSTD_writeFrameHeader(
            @as(?*anyopaque, @ptrCast(op)),
            dstCapacity,
            &cctx.*.appliedParams,
            0,
            0,
        );
        if (errIsError(fhSize)) return fhSize;
        dstCapacity -%= fhSize;
        op += fhSize;
        cctx.*.stage = @as(c_uint, @bitCast(cctx_mod.ZSTDcs_ongoing));
    }

    if (cctx.*.stage != @as(c_uint, @bitCast(cctx_mod.ZSTDcs_ending))) {
        const bt_raw_u: U32 = @as(U32, @bitCast(block.bt_raw));
        const cBlockHeader24: U32 = 1 +% (bt_raw_u << 1) +% 0;
        if (dstCapacity < block.ZSTD_blockHeaderSize) return zerr(ZSTD_error_dstSize_tooSmall);
        block.memWriteLE24(@as(?*anyopaque, @ptrCast(op)), cBlockHeader24);
        op += block.ZSTD_blockHeaderSize;
        dstCapacity -%= block.ZSTD_blockHeaderSize;
    }

    if (cctx.*.appliedParams.fParams.checksumFlag != 0) {
        const checksum: U32 = @truncate(xxhash.ZSTD_XXH64_digest(&cctx.*.xxhState));
        if (dstCapacity < 4) return zerr(ZSTD_error_dstSize_tooSmall);
        block.memWriteLE32(@as(?*anyopaque, @ptrCast(op)), checksum);
        op += 4;
    }

    cctx.*.stage = @as(c_uint, @bitCast(cctx_mod.ZSTDcs_created));
    return @intCast(@intFromPtr(op) -% @intFromPtr(ostart));
}

pub export fn ZSTD_compressEnd_public(
    cctx: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    const cSize: usize = ZSTD_compressContinue_internal(cctx, dst, dstCapacity, src, srcSize, 1, 1);
    if (errIsError(cSize)) return cSize;

    const endResult: usize = ZSTD_writeEpilogue(
        cctx,
        @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(dst))) + cSize)),
        dstCapacity -% cSize,
    );
    if (errIsError(endResult)) return endResult;

    if (cctx.*.pledgedSrcSizePlusOne != 0) {
        if (cctx.*.pledgedSrcSizePlusOne != cctx.*.consumedSrcSize +% 1) {
            return zerr(ZSTD_error_srcSize_wrong);
        }
    }
    ZSTD_CCtx_trace(cctx, endResult);
    return cSize +% endResult;
}

pub export fn ZSTD_compressEnd(
    cctx: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    return ZSTD_compressEnd_public(cctx, dst, dstCapacity, src, srcSize);
}

// -------------------------------------------------------------------------
//  ZSTD_compressBlock_deprecated / ZSTD_compressBlock — translate-c
//  32001..32030, 27163..27175. Non-framed block emit (one-shot).
// -------------------------------------------------------------------------

pub export fn ZSTD_compressBlock_deprecated(
    cctx: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    const blockSizeMax: usize = ZSTD_getBlockSize_deprecated(cctx);
    if (srcSize > blockSizeMax) return zerr(ZSTD_error_srcSize_wrong);
    return ZSTD_compressContinue_internal(cctx, dst, dstCapacity, src, srcSize, 0, 0);
}

pub export fn ZSTD_compressBlock(
    cctx: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    return ZSTD_compressBlock_deprecated(cctx, dst, dstCapacity, src, srcSize);
}

// -------------------------------------------------------------------------
//  ZSTD_compressBegin_internal — translate-c 36872..36956.
//  Resets the CCtx (using the CDict attach/copy fast-path if applicable),
//  then loads any dict content into the block state.
// -------------------------------------------------------------------------

// ZSTD_tfp_forCCtx = 0, ZSTD_tfp_forCDict = 1 — see zstd_compress_internal.h.
const ZSTD_tfp_forCCtx: c_uint = 0;

pub fn ZSTD_compressBegin_internal(
    cctx: [*c]ZSTD_CCtx,
    dict: ?*const anyopaque,
    dictSize: usize,
    dictContentType: ZSTD_dictContentType_e,
    dtlm: ZSTD_dictTableLoadMethod_e,
    cdict: [*c]const ZSTD_CDict,
    params: [*c]const ZSTD_CCtx_params,
    pledgedSrcSize: U64,
    zbuff: ZSTD_buffered_policy_e,
) callconv(.c) usize {
    const dictContentSize: usize =
        if (cdict != null) cdict.*.dictContentSize else dictSize;

    // Tracing off by default — mirror upstream by zeroing traceCtx.
    cctx.*.traceCtx = 0;

    // CDict attach/copy fast-path: when we have a cdict and the workload
    // crosses the "small enough to attach" thresholds, hop into the
    // CDict-reset path and skip the generic reset + dict-insert sequence.
    const ZSTD_dictForceLoad: c_uint = 3;
    if (cdict != null and cdict.*.dictContentSize > 0 and
        (pledgedSrcSize < 128 * 1024 or
            pledgedSrcSize < (@as(U64, @intCast(cdict.*.dictContentSize)) *% 6) or
            pledgedSrcSize == ZSTD_CONTENTSIZE_UNKNOWN or
            cdict.*.compressionLevel == 0) and
        params.*.attachDictPref != ZSTD_dictForceLoad)
    {
        return cctx_mod.ZSTD_resetCCtx_usingCDict(cctx, cdict, params, pledgedSrcSize, zbuff);
    }

    const reset_err = cctx_mod.ZSTD_resetCCtx_internal(
        cctx,
        params,
        pledgedSrcSize,
        dictContentSize,
        @as(c_uint, @bitCast(reset_mod.ZSTDcrp_makeClean)),
        zbuff,
    );
    if (errIsError(reset_err)) return reset_err;

    // Insert dictionary: from cdict content if provided, otherwise from the
    // caller's dict pointer.
    const dict_ptr: ?*const anyopaque = if (cdict != null) cdict.*.dictContent else dict;
    const dict_size: usize = if (cdict != null) cdict.*.dictContentSize else dictSize;
    const dict_type: ZSTD_dictContentType_e = if (cdict != null) cdict.*.dictContentType else dictContentType;

    const dictID: usize = ZSTD_compress_insertDictionary(
        cctx.*.blockState.prevCBlock,
        &cctx.*.blockState.matchState,
        &cctx.*.ldmState,
        &cctx.*.workspace,
        &cctx.*.appliedParams,
        dict_ptr,
        dict_size,
        dict_type,
        dtlm,
        ZSTD_tfp_forCCtx,
        cctx.*.tmpWorkspace,
    );
    if (errIsError(dictID)) return dictID;
    cctx.*.dictID = @truncate(dictID);
    cctx.*.dictContentSize = dictContentSize;
    return 0;
}

// -------------------------------------------------------------------------
//  ZSTD_compressBegin_advanced_internal — translate-c 31704..31748.
// -------------------------------------------------------------------------

pub export fn ZSTD_compressBegin_advanced_internal(
    cctx: [*c]ZSTD_CCtx,
    dict: ?*const anyopaque,
    dictSize: usize,
    dictContentType: ZSTD_dictContentType_e,
    dtlm: ZSTD_dictTableLoadMethod_e,
    cdict: [*c]const ZSTD_CDict,
    params: [*c]const ZSTD_CCtx_params,
    pledgedSrcSize: c_ulonglong,
) usize {
    const chk = ZSTD_checkCParams(params.*.cParams);
    if (errIsError(chk)) return chk;
    return ZSTD_compressBegin_internal(
        cctx,
        dict,
        dictSize,
        dictContentType,
        dtlm,
        cdict,
        params,
        pledgedSrcSize,
        @as(c_uint, @bitCast(ms_mod.ZSTDb_not_buffered)),
    );
}

// -------------------------------------------------------------------------
//  ZSTD_compressBegin_usingDict_deprecated — translate-c 36957..36977.
//  Builds a throw-away ZSTD_CCtx_params from a compression level + dict
//  size hint, then defers to the internal begin.
// -------------------------------------------------------------------------

pub fn ZSTD_compressBegin_usingDict_deprecated(
    cctx: [*c]ZSTD_CCtx,
    dict: ?*const anyopaque,
    dictSize: usize,
    compressionLevel: c_int,
) callconv(.c) usize {
    var cctxParams: ZSTD_CCtx_params = .{};
    const p: ZSTD_parameters = cparams.ZSTD_getParams_internal(
        compressionLevel,
        ZSTD_CONTENTSIZE_UNKNOWN,
        dictSize,
        @as(c_uint, @bitCast(cparams.ZSTD_cpm_noAttachDict)),
    );
    ZSTD_CCtxParams_init_internal(
        &cctxParams,
        &p,
        if (compressionLevel == 0) @as(c_int, 3) else compressionLevel,
    );
    return ZSTD_compressBegin_internal(
        cctx,
        dict,
        dictSize,
        @as(c_uint, @bitCast(cctx_mod.ZSTD_dct_auto)),
        @as(c_uint, @bitCast(ms_mod.ZSTD_dtlm_fast)),
        null,
        &cctxParams,
        ZSTD_CONTENTSIZE_UNKNOWN,
        @as(c_uint, @bitCast(ms_mod.ZSTDb_not_buffered)),
    );
}

// -------------------------------------------------------------------------
//  ZSTD_compressBegin_usingCDict_internal — translate-c 37255..37301.
//  Derives cParams from the cdict (either by direct copy or by deriving
//  from the cdict.compressionLevel when the workload is large enough).
// -------------------------------------------------------------------------

pub fn ZSTD_compressBegin_usingCDict_internal(
    cctx: [*c]ZSTD_CCtx,
    cdict: [*c]const ZSTD_CDict,
    fParams: ZSTD_frameParameters,
    pledgedSrcSize: c_ulonglong,
) callconv(.c) usize {
    if (cdict == null) return zerr(ZSTD_error_dictionary_wrong);

    var cctxParams: ZSTD_CCtx_params = .{};
    var p: ZSTD_parameters = .{};
    p.fParams = fParams;
    // Small workload or a "level 0" cdict: attach (use cdict's cParams).
    // Large workload: rederive from cdict.compressionLevel.
    const small_workload: bool =
        pledgedSrcSize < 128 * 1024 or
        pledgedSrcSize < (@as(c_ulonglong, @intCast(cdict.*.dictContentSize)) *% 6) or
        pledgedSrcSize == ZSTD_CONTENTSIZE_UNKNOWN or
        cdict.*.compressionLevel == 0;
    p.cParams = if (small_workload)
        ZSTD_getCParamsFromCDict(cdict)
    else
        cparams.ZSTD_getCParams(cdict.*.compressionLevel, pledgedSrcSize, cdict.*.dictContentSize);
    ZSTD_CCtxParams_init_internal(&cctxParams, &p, cdict.*.compressionLevel);

    // Upper-bound the cParams.windowLog by a derived "limited" log for
    // smaller source sizes — copy of upstream translate-c 37293..37299.
    if (pledgedSrcSize != ZSTD_CONTENTSIZE_UNKNOWN) {
        const cap: c_ulonglong = @as(c_ulonglong, 1) << 19;
        const limitedSrcSize: U32 = @truncate(if (pledgedSrcSize < cap) pledgedSrcSize else cap);
        const limitedSrcLog: U32 = if (limitedSrcSize > 1)
            cparams_highbit32(limitedSrcSize -% 1) +% 1
        else
            1;
        if (cctxParams.cParams.windowLog < limitedSrcLog) {
            cctxParams.cParams.windowLog = limitedSrcLog;
        }
    }

    return ZSTD_compressBegin_internal(
        cctx,
        null,
        0,
        @as(c_uint, @bitCast(cctx_mod.ZSTD_dct_auto)),
        @as(c_uint, @bitCast(ms_mod.ZSTD_dtlm_fast)),
        cdict,
        &cctxParams,
        pledgedSrcSize,
        @as(c_uint, @bitCast(ms_mod.ZSTDb_not_buffered)),
    );
}

// cparams_highbit32: cparams_mod.zig exposes ZSTD_highbit32 at file scope
// as `inline fn`; it's not `pub`, so we re-declare a one-liner helper.
inline fn cparams_highbit32(val: U32) u32 {
    return 31 -% @as(u32, @intCast(@clz(val)));
}

pub fn ZSTD_compressBegin_usingCDict_deprecated(
    cctx: [*c]ZSTD_CCtx,
    cdict: [*c]const ZSTD_CDict,
) callconv(.c) usize {
    const fParams: ZSTD_frameParameters = .{};
    return ZSTD_compressBegin_usingCDict_internal(cctx, cdict, fParams, ZSTD_CONTENTSIZE_UNKNOWN);
}

// -------------------------------------------------------------------------
//  Public compressBegin wrappers — translate-c 27047..27141.
// -------------------------------------------------------------------------

pub export fn ZSTD_compressBegin(cctx: [*c]ZSTD_CCtx, compressionLevel: c_int) usize {
    return ZSTD_compressBegin_usingDict_deprecated(cctx, null, 0, compressionLevel);
}

pub export fn ZSTD_compressBegin_usingDict(
    cctx: [*c]ZSTD_CCtx,
    dict: ?*const anyopaque,
    dictSize: usize,
    compressionLevel: c_int,
) usize {
    return ZSTD_compressBegin_usingDict_deprecated(cctx, dict, dictSize, compressionLevel);
}

pub export fn ZSTD_compressBegin_usingCDict(
    cctx: [*c]ZSTD_CCtx,
    cdict: [*c]const ZSTD_CDict,
) usize {
    return ZSTD_compressBegin_usingCDict_deprecated(cctx, cdict);
}

pub export fn ZSTD_compressBegin_advanced(
    cctx: [*c]ZSTD_CCtx,
    dict: ?*const anyopaque,
    dictSize: usize,
    params: ZSTD_parameters,
    pledgedSrcSize: c_ulonglong,
) usize {
    var cctxParams: ZSTD_CCtx_params = .{};
    ZSTD_CCtxParams_init_internal(&cctxParams, &params, 0);
    return ZSTD_compressBegin_advanced_internal(
        cctx,
        dict,
        dictSize,
        @as(c_uint, @bitCast(cctx_mod.ZSTD_dct_auto)),
        @as(c_uint, @bitCast(ms_mod.ZSTD_dtlm_fast)),
        null,
        &cctxParams,
        pledgedSrcSize,
    );
}

pub export fn ZSTD_compressBegin_usingCDict_advanced(
    cctx: [*c]ZSTD_CCtx,
    cdict: [*c]const ZSTD_CDict,
    fParams: ZSTD_frameParameters,
    pledgedSrcSize: c_ulonglong,
) usize {
    return ZSTD_compressBegin_usingCDict_internal(cctx, cdict, fParams, pledgedSrcSize);
}

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------

test "ZSTD_writeLastEmptyBlock emits 3-byte trailer" {
    var dst: [8]u8 = .{0xAA} ** 8;
    const r = ZSTD_writeLastEmptyBlock(@ptrCast(&dst), dst.len);
    try std.testing.expectEqual(@as(usize, 3), r);
    // lastBlock=1 | (bt_raw=0 << 1) | (0 << 3) == 0x01
    try std.testing.expectEqual(@as(u8, 0x01), dst[0]);
    try std.testing.expectEqual(@as(u8, 0x00), dst[1]);
    try std.testing.expectEqual(@as(u8, 0x00), dst[2]);
}

test "ZSTD_writeLastEmptyBlock dstSize_tooSmall" {
    var dst: [2]u8 = .{0} ** 2;
    const r = ZSTD_writeLastEmptyBlock(@ptrCast(&dst), dst.len);
    try std.testing.expect(common.ERR_isError(r) != 0);
}

test "ZSTD_writeFrameHeader bit-exact: minimal frame (no dict, no checksum, unknown size)" {
    // Mirrors the upstream wire format:
    // Magic (4) + FHD (1) + WLB (1) + {nothing} = 6 bytes.
    var params: ZSTD_CCtx_params = .{};
    params.format = @as(c_uint, @bitCast(zstd_compress.ZSTD_f_zstd1));
    params.cParams.windowLog = 14; // WLB = (14 - 10) << 3 = 0x20
    params.fParams.contentSizeFlag = 0;
    params.fParams.checksumFlag = 0;
    params.fParams.noDictIDFlag = 0;

    var dst: [ZSTD_FRAMEHEADERSIZE_MAX]u8 = .{0xAA} ** ZSTD_FRAMEHEADERSIZE_MAX;
    const r = ZSTD_writeFrameHeader(@ptrCast(&dst), dst.len, &params, 0, 0);
    try std.testing.expectEqual(@as(usize, 6), r);
    // Magic: LE(0xFD2FB528) = 28 B5 2F FD
    try std.testing.expectEqual(@as(u8, 0x28), dst[0]);
    try std.testing.expectEqual(@as(u8, 0xB5), dst[1]);
    try std.testing.expectEqual(@as(u8, 0x2F), dst[2]);
    try std.testing.expectEqual(@as(u8, 0xFD), dst[3]);
    // FHD: dictIDSizeCode=0, checksum=0, singleSegment=0, fcsCode=0 → 0
    try std.testing.expectEqual(@as(u8, 0x00), dst[4]);
    // WLB: (14 - 10) << 3 = 0x20
    try std.testing.expectEqual(@as(u8, 0x20), dst[5]);
}

test "ZSTD_writeFrameHeader: contentSize 64K adds 2-byte FCS (fcsCode=1)" {
    var params: ZSTD_CCtx_params = .{};
    params.format = @as(c_uint, @bitCast(zstd_compress.ZSTD_f_zstd1));
    params.cParams.windowLog = 20; // WLB = 0x50
    params.fParams.contentSizeFlag = 1;

    var dst: [ZSTD_FRAMEHEADERSIZE_MAX]u8 = .{0} ** ZSTD_FRAMEHEADERSIZE_MAX;
    const r = ZSTD_writeFrameHeader(@ptrCast(&dst), dst.len, &params, 1024, 0);
    // Magic + FHD + WLB + 2-byte FCS (1024 - 256 = 768 = 0x0300) = 8 bytes.
    // singleSegment = 0 (windowSize (1 << 20 = 1M) >= 1024 is true → singleSegment = 1!)
    // Actually: (1 << 20 = 1048576) >= 1024 → singleSegment=1.
    // singleSegment=1 → no WLB, fcsCode=1 → 2 bytes pledged-256.
    try std.testing.expectEqual(@as(usize, 4 + 1 + 2), r);
    // FHD: fcsCode=1 << 6 = 0x40; singleSegment=1 << 5 = 0x20
    try std.testing.expectEqual(@as(u8, 0x40 | 0x20), dst[4]);
    // 1024 - 256 = 768 = 0x0300 little-endian: 00, 03
    try std.testing.expectEqual(@as(u8, 0x00), dst[5]);
    try std.testing.expectEqual(@as(u8, 0x03), dst[6]);
}

test "ZSTD_writeFrameHeader dstCapacity too small" {
    var params: ZSTD_CCtx_params = .{};
    params.format = @as(c_uint, @bitCast(zstd_compress.ZSTD_f_zstd1));
    params.cParams.windowLog = 14;

    var dst: [8]u8 = .{0} ** 8;
    const r = ZSTD_writeFrameHeader(@ptrCast(&dst), dst.len, &params, 0, 0);
    try std.testing.expect(common.ERR_isError(r) != 0);
}

test "compressBegin/compressContinue/compressEnd public wrappers link" {
    // Compile-only: proves each exported wrapper has a valid signature and
    // resolves its cross-module deps. Exec requires slice 5f (zstd_fast.c).
    const f1: ?*const fn ([*c]ZSTD_CCtx, c_int) callconv(.c) usize = &ZSTD_compressBegin;
    const f2: ?*const fn ([*c]ZSTD_CCtx, ?*anyopaque, usize, ?*const anyopaque, usize) callconv(.c) usize = &ZSTD_compressContinue;
    const f3: ?*const fn ([*c]ZSTD_CCtx, ?*anyopaque, usize, ?*const anyopaque, usize) callconv(.c) usize = &ZSTD_compressEnd;
    try std.testing.expect(f1 != null);
    try std.testing.expect(f2 != null);
    try std.testing.expect(f3 != null);
}

test "ZSTD_getBlockSize: min(maxBlockSize, 1 << windowLog)" {
    var c: ZSTD_CCtx = .{};
    c.appliedParams.cParams.windowLog = 17; // 128 KB
    c.appliedParams.maxBlockSize = 64 * 1024;
    try std.testing.expectEqual(@as(usize, 64 * 1024), ZSTD_getBlockSize(&c));
    c.appliedParams.maxBlockSize = 256 * 1024;
    try std.testing.expectEqual(@as(usize, 128 * 1024), ZSTD_getBlockSize(&c));
}
