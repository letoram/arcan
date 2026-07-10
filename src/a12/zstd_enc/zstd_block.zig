// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7's block-framing primitives.
// Slice 5g of the zstd encoder port (extended from 5e).
//
// Source line ranges from /tmp/raw_zstd_compress.zig:
//   28586..28590   ZSTD_blockHeaderSize / bt_{raw,rle,compressed,reserved}
//   29516..29559   ZSTD_seqToCodes
//   29882..30101   ZSTD_LLcode / ZSTD_MLcode (big static tables)
//   30125..30165   ZSTD_noCompressBlock
//   30166..30205   ZSTD_rleCompressBlock
//   30206..30216   ZSTD_minGain
//   32817..32831   ZSTD_assertEqualCParams  (no-op in upstream debug path)
//   33702..33718   ZSTD_useTargetCBlockSize / ZSTD_blockSplitterEnabled
//   33727..33860   ZSTD_buildSequencesStatistics
//   33861..34073   ZSTD_entropyCompressSeqStore_internal
//   34074..34141   ZSTD_entropyCompressSeqStore_wExtLitBuffer
//   34142..34164   ZSTD_entropyCompressSeqStore
//   34165..34174   ZSTD_storeLastLiterals
//   34283..34290   ZSTD_validateSeqStore   (no-op)
//   34475..34477   ZSTDbss_{compress,noCompress}
//   34478..34705   ZSTD_buildSeqStore
//   34857..34879   ZSTD_blockState_confirmRepcodesAndEntropyTables,
//                  writeBlockHeader
//   upstream C zstd_compress.c 4382..4448  ZSTD_compressBlock_internal
//                  (translate-c demoted this to extern)
//   35985..36117   ZSTD_compressBlock_targetCBlockSize_body and
//                  ZSTD_compressBlock_targetCBlockSize
//   29577..29647   ZSTD_buildBlockEntropyStats (wrapper over
//                  _literals and _sequences)
//
// Noise removed from translate-c:
//   * while (true) { if (!false) break; } DEBUGLOG shells
//   * _force_has_format_string / RETURN_ERROR_IF boilerplate
//   * dead _ = @as(c_int, 0) leftovers
//   * verbose @bitCast/@truncate integer ceremony
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).

const std = @import("std");
const common = @import("zstd_common.zig");
const zstd_compress = @import("zstd_compress.zig");
const ms_mod = @import("zstd_match_state.zig");
const cctx_mod = @import("zstd_cctx.zig");
const lits = @import("zstd_compress_literals.zig");
const seqs = @import("zstd_compress_sequences.zig");
const hist_mod = @import("hist.zig");
const fse_mod = @import("fse_compress.zig");
const fast_mod = @import("zstd_fast.zig");

// -------------------------------------------------------------------------
//  Type aliases
// -------------------------------------------------------------------------

pub const U32 = ms_mod.U32;
pub const U64 = ms_mod.U64;
pub const BYTE = ms_mod.BYTE;

pub const ZSTD_CCtx = cctx_mod.ZSTD_CCtx;
pub const ZSTD_CCtx_params = zstd_compress.ZSTD_CCtx_params;
pub const ZSTD_blockState_t = ms_mod.ZSTD_blockState_t;
pub const ZSTD_compressedBlockState_t = ms_mod.ZSTD_compressedBlockState_t;
pub const SeqStore_t = ms_mod.SeqStore_t;
pub const SeqDef = ms_mod.SeqDef;
pub const ZSTD_entropyCTables_t = ms_mod.ZSTD_entropyCTables_t;
pub const ZSTD_hufCTables_t = ms_mod.ZSTD_hufCTables_t;
pub const ZSTD_fseCTables_t = ms_mod.ZSTD_fseCTables_t;
pub const ZSTD_hufCTablesMetadata_t = ms_mod.ZSTD_hufCTablesMetadata_t;
pub const ZSTD_fseCTablesMetadata_t = ms_mod.ZSTD_fseCTablesMetadata_t;
pub const ZSTD_entropyCTablesMetadata_t = ms_mod.ZSTD_entropyCTablesMetadata_t;
pub const ZSTD_strategy = zstd_compress.ZSTD_strategy;

// -------------------------------------------------------------------------
//  Block-header constants — translate-c lines 28586..28590, 34475..34477.
// -------------------------------------------------------------------------

pub const ZSTD_blockHeaderSize: usize = 3;

pub const bt_raw: c_int = 0;
pub const bt_rle: c_int = 1;
pub const bt_compressed: c_int = 2;
pub const bt_reserved: c_int = 3;
pub const ZSTD_blockType_e = c_uint;

pub const ZSTDbss_compress: c_int = 0;
pub const ZSTDbss_noCompress: c_int = 1;
pub const ZSTD_BuildSeqStore_e = c_uint;

// Error helpers (keep consistent with zstd_cctx.zig).
const ZSTD_error_dstSize_tooSmall: c_int = 70;
const ZSTD_error_parameter_combination_unsupported: c_int = 41;
const ZSTD_error_sequenceProducer_failed: c_int = 106;

// Runtime debug flag — flip to true while developing to trace seqStore output.
pub const zstd_debug_trace: bool = false;

inline fn zerr(code: c_int) usize {
    return @bitCast(-@as(isize, code));
}

inline fn errIsError(code: usize) bool {
    return common.ERR_isError(code) != 0;
}

// -------------------------------------------------------------------------
//  Little-endian writers — replacements for MEM_writeLE16/24/32/64.
//  Keep these in one place; block/frame/literals all need them.
// -------------------------------------------------------------------------

pub inline fn writeLE16(dst: [*]u8, v: u16) void {
    std.mem.writeInt(u16, dst[0..2], v, .little);
}

pub inline fn writeLE24(dst: [*]u8, v: u32) void {
    std.mem.writeInt(u16, dst[0..2], @intCast(v & 0xFFFF), .little);
    dst[2] = @intCast((v >> 16) & 0xFF);
}

pub inline fn writeLE32(dst: [*]u8, v: u32) void {
    std.mem.writeInt(u32, dst[0..4], v, .little);
}

pub inline fn writeLE64(dst: [*]u8, v: u64) void {
    std.mem.writeInt(u64, dst[0..8], v, .little);
}

// MEM_writeLE* convenience overloads that take ?*anyopaque so they can
// drop in where the C code used MEM_writeLE{16,24,32,64}(void*,...).
pub inline fn memWriteLE16(dst: ?*anyopaque, v: u16) void {
    writeLE16(@ptrCast(@alignCast(dst.?)), v);
}
pub inline fn memWriteLE24(dst: ?*anyopaque, v: u32) void {
    writeLE24(@ptrCast(@alignCast(dst.?)), v);
}
pub inline fn memWriteLE32(dst: ?*anyopaque, v: u32) void {
    writeLE32(@ptrCast(@alignCast(dst.?)), v);
}
pub inline fn memWriteLE64(dst: ?*anyopaque, v: u64) void {
    writeLE64(@ptrCast(@alignCast(dst.?)), v);
}

// -------------------------------------------------------------------------
//  ZSTD_minGain — translate-c 30206..30216.
//  Already present as a private helper in zstd_compress_literals.zig; re-use
//  the shared implementation so the tables stay in lock-step.
// -------------------------------------------------------------------------

pub fn ZSTD_minGain(srcSize: usize, strat: ZSTD_strategy) callconv(.c) usize {
    const strat_u: c_uint = @as(c_uint, @bitCast(strat));
    const btultra_u: c_uint = @as(c_uint, @bitCast(zstd_compress.ZSTD_btultra));
    const minlog: u32 = if (strat_u >= btultra_u) strat_u -% 1 else 6;
    return (srcSize >> @intCast(minlog)) +% 2;
}

// -------------------------------------------------------------------------
//  ZSTD_noCompressBlock — emit a raw (bt_raw) block with block header and
//  an unmodified copy of src. Translate-c lines 30125..30165.
// -------------------------------------------------------------------------

pub export fn ZSTD_noCompressBlock(
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    lastBlock: U32,
) usize {
    // cBlockHeader24 = lastBlock | (bt_raw << 1) | (srcSize << 3)
    const bt_raw_u: U32 = @as(U32, @bitCast(bt_raw));
    const cBlockHeader24: U32 = lastBlock +% (bt_raw_u << 1) +% @as(U32, @intCast(srcSize << 3));

    if (srcSize +% ZSTD_blockHeaderSize > dstCapacity) return zerr(ZSTD_error_dstSize_tooSmall);

    const op: [*]u8 = @ptrCast(@alignCast(dst.?));
    writeLE24(op, cBlockHeader24);
    if (srcSize != 0) {
        const sp: [*]const u8 = @ptrCast(@alignCast(src.?));
        @memcpy(op[ZSTD_blockHeaderSize .. ZSTD_blockHeaderSize + srcSize], sp[0..srcSize]);
    }
    return ZSTD_blockHeaderSize +% srcSize;
}

// -------------------------------------------------------------------------
//  ZSTD_rleCompressBlock — emit a 4-byte RLE block (header + repeated byte).
//  Translate-c lines 30166..30205.
// -------------------------------------------------------------------------

pub export fn ZSTD_rleCompressBlock(
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: BYTE,
    srcSize: usize,
    lastBlock: U32,
) usize {
    const bt_rle_u: U32 = @as(U32, @bitCast(bt_rle));
    const cBlockHeader: U32 = lastBlock +% (bt_rle_u << 1) +% @as(U32, @intCast(srcSize << 3));
    if (dstCapacity < 4) return zerr(ZSTD_error_dstSize_tooSmall);

    const op: [*]u8 = @ptrCast(@alignCast(dst.?));
    writeLE24(op, cBlockHeader);
    op[3] = src;
    return 4;
}

// -------------------------------------------------------------------------
//  writeBlockHeader — translate-c lines 34864..34879.
//  Used by the super-block emitter and the split-block path.
// -------------------------------------------------------------------------

pub fn writeBlockHeader(op: ?*anyopaque, cSize: usize, blockSize: usize, lastBlock: U32) callconv(.c) void {
    const bt: U32 = if (cSize == 1) @as(U32, @bitCast(bt_rle)) else @as(U32, @bitCast(bt_compressed));
    const size_bits: U32 = if (cSize == 1)
        @as(U32, @intCast(blockSize << 3))
    else
        @as(U32, @intCast(cSize << 3));
    const cBlockHeader: U32 = lastBlock +% (bt << 1) +% size_bits;
    memWriteLE24(op, cBlockHeader);
}

// -------------------------------------------------------------------------
//  ZSTD_blockState_confirmRepcodesAndEntropyTables — translate-c 34857..34862.
//  Swap prev/next compressed-block states after a successful block emit.
// -------------------------------------------------------------------------

pub fn ZSTD_blockState_confirmRepcodesAndEntropyTables(bs: [*c]ZSTD_blockState_t) callconv(.c) void {
    const tmp: [*c]ZSTD_compressedBlockState_t = bs.*.prevCBlock;
    bs.*.prevCBlock = bs.*.nextCBlock;
    bs.*.nextCBlock = tmp;
}

// -------------------------------------------------------------------------
//  ZSTD_useTargetCBlockSize / ZSTD_blockSplitterEnabled — translate-c
//  lines 33702..33718. Parameter-side guards consulted by the frame-chunk
//  emitter to pick a block-compression strategy.
// -------------------------------------------------------------------------

pub fn ZSTD_useTargetCBlockSize(cctxParams: [*c]const ZSTD_CCtx_params) callconv(.c) c_int {
    return @intFromBool(cctxParams.*.targetCBlockSize != 0);
}

pub fn ZSTD_blockSplitterEnabled(cctxParams: [*c]ZSTD_CCtx_params) callconv(.c) c_int {
    return @intFromBool(
        cctxParams.*.postBlockSplitter == @as(c_uint, @bitCast(zstd_compress.ZSTD_ps_enable)),
    );
}

// -------------------------------------------------------------------------
//  Real ports for the former-stubs. ZSTD_compressSuperBlock remains a stub
//  because the targetCBlockSize path is off for level 3 (see
//  ZSTD_useTargetCBlockSize → 0 when cctxParams.targetCBlockSize == 0).
// -------------------------------------------------------------------------

// ZSTD_compressSuperBlock: only entered from targetCBlockSize path, which
// requires cctxParams.targetCBlockSize != 0. Our default simple-API path
// leaves it at 0 → this never fires. Return dstSize_tooSmall so the caller
// falls back to noCompressBlock (upstream translate-c 36009).
pub fn ZSTD_compressSuperBlock(
    zc: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    lastBlock: U32,
) callconv(.c) usize {
    _ = zc;
    _ = dst;
    _ = dstCapacity;
    _ = src;
    _ = srcSize;
    _ = lastBlock;
    return zerr(ZSTD_error_dstSize_tooSmall);
}

// ZSTD_maybeRLE — upstream: heuristic "seqStore only has one repeating
// sequence-of-zero-offset". Conservative "no" is always legal (only skips
// a fast path).
pub fn ZSTD_maybeRLE(seqStore: [*c]const SeqStore_t) callconv(.c) c_int {
    _ = seqStore;
    return 0;
}

// ZSTD_isRLE — returns 1 iff all bytes in [src..src+length) are equal.
// Translate-c line ~29710.
pub fn ZSTD_isRLE(src: [*c]const BYTE, length: usize) callconv(.c) c_int {
    if (length <= 1) return 1;
    const b: BYTE = src[0];
    var i: usize = 1;
    while (i < length) : (i +%= 1) {
        if (src[i] != b) return 0;
    }
    return 1;
}

// -------------------------------------------------------------------------
//  ZSTD_assertEqualCParams — upstream debug-only no-op.
// -------------------------------------------------------------------------

pub fn ZSTD_assertEqualCParams(
    cParams1: zstd_compress.ZSTD_compressionParameters,
    cParams2: zstd_compress.ZSTD_compressionParameters,
) callconv(.c) void {
    _ = cParams1;
    _ = cParams2;
}

pub fn ZSTD_validateSeqStore(
    seqStore: [*c]const SeqStore_t,
    cParams: [*c]const zstd_compress.ZSTD_compressionParameters,
) callconv(.c) void {
    _ = seqStore;
    _ = cParams;
}

// -------------------------------------------------------------------------
//  ZSTD_LLcode / ZSTD_MLcode — translate-c 29882..30101.
// -------------------------------------------------------------------------

const LL_Code_static: [64]BYTE = .{
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    16, 16, 17, 17, 18, 18, 19, 19, 20, 20, 20, 20, 21, 21, 21, 21,
    22, 22, 22, 22, 22, 22, 22, 22, 23, 23, 23, 23, 23, 23, 23, 23,
    24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
};
const LL_deltaCode: U32 = 19;

const ML_Code_static: [128]BYTE = .{
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    32, 32, 33, 33, 34, 34, 35, 35, 36, 36, 36, 36, 37, 37, 37, 37,
    38, 38, 38, 38, 38, 38, 38, 38, 39, 39, 39, 39, 39, 39, 39, 39,
    40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40,
    41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41,
    42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42,
    42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42,
};
const ML_deltaCode: U32 = 36;

inline fn highbit32(v: U32) U32 {
    // Upstream ZSTD_highbit32 uses __builtin_clz; equivalent under @clz.
    return 31 -% @as(U32, @intCast(@clz(v)));
}

pub fn ZSTD_LLcode(litLength: U32) callconv(.c) U32 {
    if (litLength > 63) return highbit32(litLength) +% LL_deltaCode;
    return @as(U32, LL_Code_static[litLength]);
}

pub fn ZSTD_MLcode(mlBase: U32) callconv(.c) U32 {
    if (mlBase > 127) return highbit32(mlBase) +% ML_deltaCode;
    return @as(U32, ML_Code_static[mlBase]);
}

// -------------------------------------------------------------------------
//  ZSTD_seqToCodes — translate-c 29516..29559.
// -------------------------------------------------------------------------

pub fn ZSTD_seqToCodes(seqStorePtr: [*c]const SeqStore_t) callconv(.c) c_int {
    const sequences = seqStorePtr.*.sequencesStart;
    const llCodeTable = seqStorePtr.*.llCode;
    const ofCodeTable = seqStorePtr.*.ofCode;
    const mlCodeTable = seqStorePtr.*.mlCode;
    const nbSeq: U32 = @intCast(
        @divExact(@intFromPtr(seqStorePtr.*.sequences) -% @intFromPtr(seqStorePtr.*.sequencesStart), @sizeOf(SeqDef)),
    );
    const longOffsets: c_int = 0;
    var u: U32 = 0;
    // 64-bit target: ofCode must exceed 57 to toggle longOffsets; the check
    // is only active on 32-bit builds (MEM_32bits()). We target 64-bit only.
    while (u < nbSeq) : (u +%= 1) {
        const llv: U32 = sequences[u].litLength;
        const ofCode: U32 = highbit32(sequences[u].offBase);
        const mlv: U32 = sequences[u].mlBase;
        llCodeTable[u] = @truncate(ZSTD_LLcode(llv));
        ofCodeTable[u] = @truncate(ofCode);
        mlCodeTable[u] = @truncate(ZSTD_MLcode(mlv));
    }
    if (seqStorePtr.*.longLengthType == @as(c_uint, @bitCast(ms_mod.ZSTD_llt_literalLength))) {
        llCodeTable[seqStorePtr.*.longLengthPos] = 35;
    }
    if (seqStorePtr.*.longLengthType == @as(c_uint, @bitCast(ms_mod.ZSTD_llt_matchLength))) {
        mlCodeTable[seqStorePtr.*.longLengthPos] = 52;
    }
    return longOffsets;
}

// -------------------------------------------------------------------------
//  ZSTD_storeLastLiterals — translate-c 34165..34174.
// -------------------------------------------------------------------------

pub fn ZSTD_storeLastLiterals(
    seqStorePtr: [*c]SeqStore_t,
    anchor: [*c]const BYTE,
    lastLLSize: usize,
) callconv(.c) void {
    if (lastLLSize != 0) {
        const dst: [*]u8 = @ptrCast(seqStorePtr.*.lit);
        const src_ptr: [*]const u8 = @ptrCast(anchor);
        std.mem.copyForwards(u8, dst[0..lastLLSize], src_ptr[0..lastLLSize]);
    }
    seqStorePtr.*.lit += lastLLSize;
}

// -------------------------------------------------------------------------
//  ZSTD_matchState_dictMode — translate-c (zstd_compress_internal.h inline).
//  For our level-3 path (no dict, no ext-dict) this always resolves to
//  ZSTD_noDict. Branch on ms fields just in case.
// -------------------------------------------------------------------------

pub fn ZSTD_matchState_dictMode(ms: [*c]const ms_mod.ZSTD_MatchState_t) callconv(.c) ms_mod.ZSTD_dictMode_e {
    if (ms.*.dedicatedDictSearch != 0) return @as(c_uint, @bitCast(ms_mod.ZSTD_dedicatedDictSearch));
    if (ms.*.dictMatchState != null) return @as(c_uint, @bitCast(ms_mod.ZSTD_dictMatchState));
    // ext-dict check: window.dictBase differs from window.base and
    // dictLimit > lowLimit. We approximate: if dictLimit > window start we
    // might be in ext-dict. For our fresh-reset path this is false.
    const win = &ms.*.window;
    if (win.dictLimit > @import("zstd_window.zig").ZSTD_WINDOW_START_INDEX and
        @intFromPtr(win.dictBase) != @intFromPtr(win.base))
    {
        return @as(c_uint, @bitCast(ms_mod.ZSTD_extDict));
    }
    return @as(c_uint, @bitCast(ms_mod.ZSTD_noDict));
}

// -------------------------------------------------------------------------
//  ZSTD_buildSeqStore — translate-c 34478..34705. Simplified for level 3:
//  no external sequence producer, no LDM, no external-seqStore — those all
//  require match-state branches we haven't ported. Falls through to the
//  block compressor selected via ZSTD_selectBlockCompressor.
// -------------------------------------------------------------------------

pub fn ZSTD_buildSeqStore(zc: [*c]ZSTD_CCtx, src: ?*const anyopaque, srcSize: usize) callconv(.c) usize {
    const ms: [*c]ms_mod.ZSTD_MatchState_t = &zc.*.blockState.matchState;
    ZSTD_assertEqualCParams(zc.*.appliedParams.cParams, ms.*.cParams);

    // Size gate — if we can't fit a minimum block, skip compression.
    // Upstream: srcSize < MIN_CBLOCK_SIZE = 1 + 1 + ZSTD_blockHeaderSize + 1 + 1 = 6? Actually: 2 + 3 + 1 + 1 = 7? Upstream expands:
    //   if (srcSize < 1+1 + blockHeaderSize(3) + 1 + 1) = srcSize < 7.
    const minBlockSize: usize = 1 +% 1 +% ZSTD_blockHeaderSize +% 1 +% 1;
    if (srcSize < minBlockSize) {
        // Our build has no LDM and no externSeqStore — just return noCompress.
        return @as(usize, @bitCast(@as(isize, ZSTDbss_noCompress)));
    }

    ms_mod.ZSTD_resetSeqStore(&zc.*.seqStore);
    ms.*.opt.symbolCosts = &zc.*.blockState.prevCBlock.*.entropy;
    ms.*.opt.literalCompressionMode = zc.*.appliedParams.literalCompressionMode;

    // nextToUpdate clamp — upstream: if curr > nextToUpdate + 384, bump
    // nextToUpdate to curr - min(192, curr - nextToUpdate - 384).
    {
        const base: [*c]const BYTE = ms.*.window.base;
        const istart: [*c]const BYTE = @ptrCast(@alignCast(src));
        const curr: U32 = @intCast(@intFromPtr(istart) -% @intFromPtr(base));
        if (curr > ms.*.nextToUpdate +% 384) {
            const delta: U32 = (curr -% ms.*.nextToUpdate) -% 384;
            const step: U32 = if (192 < delta) 192 else delta;
            ms.*.nextToUpdate = curr -% step;
        }
    }

    // Bail out of LDM / ext-producer paths; those require code we don't
    // have. Strategy must be ZSTD_fast or ZSTD_dfast (levels 1-3). We don't
    // have a real doubleFast port — treat dfast as fast; valid but slightly
    // less compressed.
    const strat = zc.*.appliedParams.cParams.strategy;
    const fast_u: c_uint = @intCast(@intFromEnum(lits.ZSTD_strategy.ZSTD_fast));
    const dfast_u: c_uint = @intCast(@intFromEnum(lits.ZSTD_strategy.ZSTD_dfast));
    if (strat != fast_u and strat != dfast_u) {
        return zerr(ZSTD_error_parameter_combination_unsupported);
    }

    // Copy repcodes from prev → next.
    {
        var i: usize = 0;
        while (i < 3) : (i +%= 1) {
            zc.*.blockState.nextCBlock.*.rep[i] = zc.*.blockState.prevCBlock.*.rep[i];
        }
    }

    ms.*.ldmSeqStore = null;
    const lastLLSize: usize = fast_mod.ZSTD_compressBlock_fast(
        @ptrCast(ms),
        @ptrCast(&zc.*.seqStore),
        @ptrCast(@alignCast(&zc.*.blockState.nextCBlock.*.rep[0])),
        src,
        srcSize,
    );

    // Store last literals (the tail not covered by any sequence).
    const srcBytes: [*c]const BYTE = @ptrCast(@alignCast(src));
    const lastLiterals: [*c]const BYTE = srcBytes + srcSize - lastLLSize;
    ZSTD_storeLastLiterals(&zc.*.seqStore, lastLiterals, lastLLSize);

    ZSTD_validateSeqStore(&zc.*.seqStore, &zc.*.appliedParams.cParams);
    return @as(usize, @bitCast(@as(isize, ZSTDbss_compress)));
}

// -------------------------------------------------------------------------
//  ZSTD_buildSequencesStatistics — translate-c 33727..33859.
// -------------------------------------------------------------------------

pub const ZSTD_symbolEncodingTypeStats_t = extern struct {
    LLtype: U32 = 0,
    Offtype: U32 = 0,
    MLtype: U32 = 0,
    size: usize = 0,
    lastCountSize: usize = 0,
    longOffsets: c_int = 0,
};

// LL/ML/OF default norms — translate-c 28635..28816. Wire-visible bit-exact.
const LL_defaultNorm: [36]i16 = .{
    4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
};
const LL_defaultNormLog: u32 = 6;

const ML_defaultNorm: [53]i16 = .{
    1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1,
    -1, -1, -1, -1, -1,
};
const ML_defaultNormLog: u32 = 6;

const OF_defaultNorm: [29]i16 = .{
    1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    -1, -1, -1, -1, -1,
};
const OF_defaultNormLog: u32 = 5;

// set_compressed value for bitcast from SymbolEncodingType_e.
const set_compressed_u: U32 = @intFromEnum(lits.SymbolEncodingType_e.set_compressed);

pub fn ZSTD_buildSequencesStatistics(
    seqStorePtr: [*c]const SeqStore_t,
    nbSeq: usize,
    prevEntropy: [*c]const ZSTD_fseCTables_t,
    nextEntropy: [*c]ZSTD_fseCTables_t,
    dst_in: [*c]BYTE,
    dstEnd: [*c]const BYTE,
    strategy: zstd_compress.ZSTD_strategy,
    countWorkspace: [*c]c_uint,
    entropyWorkspace: ?*anyopaque,
    entropyWkspSize: usize,
) callconv(.c) ZSTD_symbolEncodingTypeStats_t {
    const ostart: [*c]BYTE = dst_in;
    const oend: [*c]const BYTE = dstEnd;
    var op: [*c]BYTE = ostart;
    const CTable_LitLength: [*]fse_mod.FSE_CTable = @ptrCast(@alignCast(&nextEntropy.*.litlengthCTable[0]));
    const CTable_OffsetBits: [*]fse_mod.FSE_CTable = @ptrCast(@alignCast(&nextEntropy.*.offcodeCTable[0]));
    const CTable_MatchLength: [*]fse_mod.FSE_CTable = @ptrCast(@alignCast(&nextEntropy.*.matchlengthCTable[0]));
    const ofCodeTable = seqStorePtr.*.ofCode;
    const llCodeTable = seqStorePtr.*.llCode;
    const mlCodeTable = seqStorePtr.*.mlCode;

    var stats: ZSTD_symbolEncodingTypeStats_t = .{};
    stats.lastCountSize = 0;
    stats.longOffsets = ZSTD_seqToCodes(seqStorePtr);

    // Strategy as a fse-compress enum view.
    const strategy_lits: lits.ZSTD_strategy = @enumFromInt(@as(c_int, @bitCast(strategy)));

    // ----- Literal Lengths ------
    {
        var max: c_uint = 35;
        const mostFrequent: usize = hist_mod.HIST_countFast_wksp(
            countWorkspace,
            &max,
            @ptrCast(llCodeTable),
            nbSeq,
            entropyWorkspace,
            entropyWkspSize,
        );
        nextEntropy.*.litlength_repeatMode = prevEntropy.*.litlength_repeatMode;
        const enc_type = seqs.ZSTD_selectEncodingType(
            &nextEntropy.*.litlength_repeatMode,
            countWorkspace,
            max,
            mostFrequent,
            nbSeq,
            9,
            @as([*]const fse_mod.FSE_CTable, @ptrCast(@alignCast(&prevEntropy.*.litlengthCTable[0]))),
            &LL_defaultNorm,
            LL_defaultNormLog,
            seqs.ZSTD_defaultAllowed,
            strategy_lits,
        );
        stats.LLtype = @intFromEnum(enc_type);
        const countSize: usize = seqs.ZSTD_buildCTable(
            @ptrCast(op),
            @intCast(@intFromPtr(oend) -% @intFromPtr(op)),
            CTable_LitLength,
            9,
            enc_type,
            countWorkspace,
            // BUG fix: pass DYNAMIC max from histogram, not the static
            // cap.  When set_rle is chosen, FSE_buildCTable_rle zeros
            // symbolTT[max] only — passing 35 here means symbolTT[0..34]
            // stay uninitialized, and the encoder reads garbage when the
            // actual RLE symbol was, say, 0 or 1.  Upstream
            // zstd_compress.c:2785 passes the histogram max here.
            // (fossil 7c2828e9bd / bug 133 follow-up — diagnostic at
            // /tmp/arcan_fse_oob.log captured deltaNbBits=0x2a0033 etc.
            // before clamp engaged.)
            max,
            @ptrCast(llCodeTable),
            nbSeq,
            &LL_defaultNorm,
            LL_defaultNormLog,
            35,
            @as([*]const fse_mod.FSE_CTable, @ptrCast(@alignCast(&prevEntropy.*.litlengthCTable[0]))),
            @sizeOf([329]fse_mod.FSE_CTable),
            entropyWorkspace,
            entropyWkspSize,
        );
        if (errIsError(countSize)) {
            stats.size = countSize;
            return stats;
        }
        if (stats.LLtype == set_compressed_u) stats.lastCountSize = countSize;
        op += countSize;
    }

    // ----- Offset Codes ------
    {
        var max: c_uint = 31;
        const mostFrequent: usize = hist_mod.HIST_countFast_wksp(
            countWorkspace,
            &max,
            @ptrCast(ofCodeTable),
            nbSeq,
            entropyWorkspace,
            entropyWkspSize,
        );
        const defaultPolicy: seqs.ZSTD_DefaultPolicy_e = if (max <= 28)
            seqs.ZSTD_defaultAllowed
        else
            seqs.ZSTD_defaultDisallowed;
        nextEntropy.*.offcode_repeatMode = prevEntropy.*.offcode_repeatMode;
        const enc_type = seqs.ZSTD_selectEncodingType(
            &nextEntropy.*.offcode_repeatMode,
            countWorkspace,
            max,
            mostFrequent,
            nbSeq,
            8,
            @as([*]const fse_mod.FSE_CTable, @ptrCast(@alignCast(&prevEntropy.*.offcodeCTable[0]))),
            &OF_defaultNorm,
            OF_defaultNormLog,
            defaultPolicy,
            strategy_lits,
        );
        stats.Offtype = @intFromEnum(enc_type);
        const countSize: usize = seqs.ZSTD_buildCTable(
            @ptrCast(op),
            @intCast(@intFromPtr(oend) -% @intFromPtr(op)),
            CTable_OffsetBits,
            8,
            enc_type,
            countWorkspace,
            // BUG fix: pass DYNAMIC max from histogram, not the static
            // cap (28).  Same issue as the Literal Lengths block above —
            // upstream zstd_compress.c:2817 passes histogram max.
            max,
            @ptrCast(ofCodeTable),
            nbSeq,
            &OF_defaultNorm,
            OF_defaultNormLog,
            28,
            @as([*]const fse_mod.FSE_CTable, @ptrCast(@alignCast(&prevEntropy.*.offcodeCTable[0]))),
            @sizeOf([193]fse_mod.FSE_CTable),
            entropyWorkspace,
            entropyWkspSize,
        );
        if (errIsError(countSize)) {
            stats.size = countSize;
            return stats;
        }
        if (stats.Offtype == set_compressed_u) stats.lastCountSize = countSize;
        op += countSize;
    }

    // ----- Match Lengths ------
    {
        var max: c_uint = 52;
        const mostFrequent: usize = hist_mod.HIST_countFast_wksp(
            countWorkspace,
            &max,
            @ptrCast(mlCodeTable),
            nbSeq,
            entropyWorkspace,
            entropyWkspSize,
        );
        nextEntropy.*.matchlength_repeatMode = prevEntropy.*.matchlength_repeatMode;
        const enc_type = seqs.ZSTD_selectEncodingType(
            &nextEntropy.*.matchlength_repeatMode,
            countWorkspace,
            max,
            mostFrequent,
            nbSeq,
            9,
            @as([*]const fse_mod.FSE_CTable, @ptrCast(@alignCast(&prevEntropy.*.matchlengthCTable[0]))),
            &ML_defaultNorm,
            ML_defaultNormLog,
            seqs.ZSTD_defaultAllowed,
            strategy_lits,
        );
        stats.MLtype = @intFromEnum(enc_type);
        const countSize: usize = seqs.ZSTD_buildCTable(
            @ptrCast(op),
            @intCast(@intFromPtr(oend) -% @intFromPtr(op)),
            CTable_MatchLength,
            9,
            enc_type,
            countWorkspace,
            // BUG fix: pass DYNAMIC max from histogram, not the static
            // cap (52).  Same issue as the Literal Lengths and Offset
            // Codes blocks above — upstream zstd_compress.c:2847 passes
            // histogram max.
            max,
            @ptrCast(mlCodeTable),
            nbSeq,
            &ML_defaultNorm,
            ML_defaultNormLog,
            52,
            @as([*]const fse_mod.FSE_CTable, @ptrCast(@alignCast(&prevEntropy.*.matchlengthCTable[0]))),
            @sizeOf([363]fse_mod.FSE_CTable),
            entropyWorkspace,
            entropyWkspSize,
        );
        if (errIsError(countSize)) {
            stats.size = countSize;
            return stats;
        }
        if (stats.MLtype == set_compressed_u) stats.lastCountSize = countSize;
        op += countSize;
    }

    stats.size = @intCast(@intFromPtr(op) -% @intFromPtr(ostart));
    return stats;
}

// -------------------------------------------------------------------------
//  ZSTD_entropyCompressSeqStore_internal — translate-c 33861..34073.
// -------------------------------------------------------------------------

pub fn ZSTD_entropyCompressSeqStore_internal(
    dst: ?*anyopaque,
    dstCapacity: usize,
    literals: ?*const anyopaque,
    litSize: usize,
    seqStorePtr: [*c]const SeqStore_t,
    prevEntropy: [*c]const ZSTD_entropyCTables_t,
    nextEntropy: [*c]ZSTD_entropyCTables_t,
    cctxParams: [*c]const ZSTD_CCtx_params,
    entropyWorkspace_in: ?*anyopaque,
    entropyWkspSize_in: usize,
    bmi2: c_int,
) callconv(.c) usize {
    const strategy = cctxParams.*.cParams.strategy;
    const count: [*c]c_uint = @ptrCast(@alignCast(entropyWorkspace_in));
    const CTable_LitLength: [*]fse_mod.FSE_CTable = @ptrCast(@alignCast(&nextEntropy.*.fse.litlengthCTable[0]));
    const CTable_OffsetBits: [*]fse_mod.FSE_CTable = @ptrCast(@alignCast(&nextEntropy.*.fse.offcodeCTable[0]));
    const CTable_MatchLength: [*]fse_mod.FSE_CTable = @ptrCast(@alignCast(&nextEntropy.*.fse.matchlengthCTable[0]));
    const sequences = seqStorePtr.*.sequencesStart;
    const nbSeq: usize = @divExact(
        @intFromPtr(seqStorePtr.*.sequences) -% @intFromPtr(seqStorePtr.*.sequencesStart),
        @sizeOf(SeqDef),
    );
    const ofCodeTable = seqStorePtr.*.ofCode;
    const llCodeTable = seqStorePtr.*.llCode;
    const mlCodeTable = seqStorePtr.*.mlCode;
    const ostart: [*c]BYTE = @ptrCast(@alignCast(dst));
    const oend: [*c]BYTE = ostart + dstCapacity;
    var op: [*c]BYTE = ostart;
    var lastCountSize: usize = 0;
    var longOffsets: c_int = 0;

    // Advance the workspace cursor past the count[] array (max(MaxLL, MaxML)+1 u32s).
    const countArrayLen: usize = @max(35, 52) +% 1; // 53
    const entropyWorkspace: ?*anyopaque = @ptrCast(count + countArrayLen);
    const entropyWkspSize: usize = entropyWkspSize_in -% (countArrayLen *% @sizeOf(c_uint));

    // --- Literals ---
    {
        const suspectUncompressible: c_int = @intFromBool(nbSeq == 0 or (litSize / nbSeq) >= 20);
        const prevHuf_lits: *const lits.ZSTD_hufCTables_t = @ptrCast(@alignCast(&prevEntropy.*.huf));
        const nextHuf_lits: *lits.ZSTD_hufCTables_t = @ptrCast(@alignCast(&nextEntropy.*.huf));
        const cSize: usize = lits.ZSTD_compressLiterals(
            @ptrCast(op),
            dstCapacity,
            literals,
            litSize,
            entropyWorkspace,
            entropyWkspSize,
            prevHuf_lits,
            nextHuf_lits,
            @enumFromInt(@as(c_int, @bitCast(cctxParams.*.cParams.strategy))),
            ZSTD_literalsCompressionIsDisabled(cctxParams),
            suspectUncompressible,
            bmi2,
        );
        if (errIsError(cSize)) return cSize;
        op += cSize;
    }

    // --- Seq count header (3 extra bytes: 1 header + block-header slack) ---
    if (@intFromPtr(oend) -% @intFromPtr(op) < 4) return zerr(ZSTD_error_dstSize_tooSmall);

    if (nbSeq < 128) {
        op[0] = @truncate(nbSeq);
        op += 1;
    } else if (nbSeq < 32512) { // 0x7F00
        op[0] = @truncate((nbSeq >> 8) +% 128);
        op[1] = @truncate(nbSeq);
        op += 2;
    } else {
        op[0] = 255;
        writeLE16(@ptrCast(op + 1), @truncate(nbSeq -% 32512));
        op += 3;
    }

    if (nbSeq == 0) {
        @memcpy(
            @as([*]u8, @ptrCast(&nextEntropy.*.fse))[0..@sizeOf(ZSTD_fseCTables_t)],
            @as([*]const u8, @ptrCast(&prevEntropy.*.fse))[0..@sizeOf(ZSTD_fseCTables_t)],
        );
        return @intCast(@intFromPtr(op) -% @intFromPtr(ostart));
    }

    // --- Sequence stats: LL/OF/ML encoding types + CTables ---
    {
        const seqHead: [*c]BYTE = op;
        op += 1;
        const stats = ZSTD_buildSequencesStatistics(
            seqStorePtr,
            nbSeq,
            &prevEntropy.*.fse,
            &nextEntropy.*.fse,
            op,
            oend,
            strategy,
            count,
            entropyWorkspace,
            entropyWkspSize,
        );
        if (errIsError(stats.size)) return stats.size;
        seqHead[0] = @truncate(((stats.LLtype << 6) +% (stats.Offtype << 4)) +% (stats.MLtype << 2));
        lastCountSize = stats.lastCountSize;
        op += stats.size;
        longOffsets = stats.longOffsets;
    }

    // --- Bitstream ---
    {
        const remaining_bytes: usize = @intCast(@intFromPtr(oend) -% @intFromPtr(op));
        const bitstreamSize: usize = seqs.ZSTD_encodeSequences(
            @ptrCast(op),
            remaining_bytes,
            CTable_MatchLength,
            mlCodeTable,
            CTable_OffsetBits,
            ofCodeTable,
            CTable_LitLength,
            llCodeTable,
            @ptrCast(sequences),
            nbSeq,
            longOffsets,
            bmi2,
        );
        if (errIsError(bitstreamSize)) return bitstreamSize;
        op += bitstreamSize;
        // zstd < 1.3.4 had a bug where the sum could overflow into the block
        // tail; upstream still guards so every zstd decoder accepts it.
        if (lastCountSize != 0 and (lastCountSize +% bitstreamSize) < 4) {
            return 0;
        }
    }
    return @intCast(@intFromPtr(op) -% @intFromPtr(ostart));
}

pub fn ZSTD_entropyCompressSeqStore_wExtLitBuffer(
    dst: ?*anyopaque,
    dstCapacity: usize,
    literals: ?*const anyopaque,
    litSize: usize,
    blockSize: usize,
    seqStorePtr: [*c]const SeqStore_t,
    prevEntropy: [*c]const ZSTD_entropyCTables_t,
    nextEntropy: [*c]ZSTD_entropyCTables_t,
    cctxParams: [*c]const ZSTD_CCtx_params,
    entropyWorkspace: ?*anyopaque,
    entropyWkspSize: usize,
    bmi2: c_int,
) callconv(.c) usize {
    const cSize: usize = ZSTD_entropyCompressSeqStore_internal(
        dst,
        dstCapacity,
        literals,
        litSize,
        seqStorePtr,
        prevEntropy,
        nextEntropy,
        cctxParams,
        entropyWorkspace,
        entropyWkspSize,
        bmi2,
    );
    if (cSize == 0) return 0;
    if (cSize == zerr(ZSTD_error_dstSize_tooSmall) and blockSize <= dstCapacity) {
        return 0;
    }
    if (errIsError(cSize)) return cSize;
    {
        const maxCSize: usize = blockSize -% ZSTD_minGain(blockSize, cctxParams.*.cParams.strategy);
        if (cSize >= maxCSize) return 0;
    }
    return cSize;
}

pub fn ZSTD_entropyCompressSeqStore(
    seqStorePtr: [*c]const SeqStore_t,
    prevEntropy: [*c]const ZSTD_entropyCTables_t,
    nextEntropy: [*c]ZSTD_entropyCTables_t,
    cctxParams: [*c]const ZSTD_CCtx_params,
    dst: ?*anyopaque,
    dstCapacity: usize,
    srcSize: usize,
    entropyWorkspace: ?*anyopaque,
    entropyWkspSize: usize,
    bmi2: c_int,
) callconv(.c) usize {
    const litPtr: ?*const anyopaque = @ptrCast(seqStorePtr.*.litStart);
    const litSize: usize = @intCast(@intFromPtr(seqStorePtr.*.lit) -% @intFromPtr(seqStorePtr.*.litStart));
    return ZSTD_entropyCompressSeqStore_wExtLitBuffer(
        dst,
        dstCapacity,
        litPtr,
        litSize,
        srcSize,
        seqStorePtr,
        prevEntropy,
        nextEntropy,
        cctxParams,
        entropyWorkspace,
        entropyWkspSize,
        bmi2,
    );
}

// -------------------------------------------------------------------------
//  ZSTD_compressBlock_internal — upstream C zstd_compress.c 4382..4448.
//  Translate-c demoted the static; hand-refined here.
// -------------------------------------------------------------------------

const rleMaxLength: U32 = 25;

pub fn ZSTD_compressBlock_internal(
    zc: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    frame: U32,
) callconv(.c) usize {
    const ip: [*c]const BYTE = @ptrCast(@alignCast(src));
    const op: [*c]BYTE = @ptrCast(@alignCast(dst));

    var cSize: usize = 0;
    const bss: usize = ZSTD_buildSeqStore(zc, src, srcSize);
    if (errIsError(bss)) return bss;
    if (bss == @as(usize, @bitCast(@as(isize, ZSTDbss_noCompress)))) {
        if (zc.*.seqCollector.collectSequences != 0) {
            return zerr(ZSTD_error_sequenceProducer_failed);
        }
        cSize = 0;
    } else {
        if (zc.*.seqCollector.collectSequences != 0) {
            // Upstream branches to ZSTD_copyBlockSequences + confirm and return 0.
            // Our arcan-net callers never enable seqCollector; fall through.
            return 0;
        }

        // encode sequences and literals
        cSize = ZSTD_entropyCompressSeqStore(
            &zc.*.seqStore,
            &zc.*.blockState.prevCBlock.*.entropy,
            &zc.*.blockState.nextCBlock.*.entropy,
            &zc.*.appliedParams,
            dst,
            dstCapacity,
            srcSize,
            zc.*.tmpWorkspace,
            zc.*.tmpWkspSize,
            zc.*.bmi2,
        );

        // RLE fast-path at tail (upstream 4423..4434).
        if (frame != 0 and zc.*.isFirstBlock == 0 and cSize < rleMaxLength and
            ZSTD_isRLE(ip, srcSize) != 0)
        {
            cSize = 1;
            op[0] = ip[0];
        }
    }

    if (!errIsError(cSize) and cSize > 1) {
        ZSTD_blockState_confirmRepcodesAndEntropyTables(&zc.*.blockState);
    }
    if (zc.*.blockState.prevCBlock.*.entropy.fse.offcode_repeatMode == .FSE_repeat_valid) {
        zc.*.blockState.prevCBlock.*.entropy.fse.offcode_repeatMode = .FSE_repeat_check;
    }
    return cSize;
}

// Entropy-stats wrappers (the old stubs are superseded by the real impl
// above — this slice's targetCBlockSize path is not exercised at level 3, so
// these two wrappers can stay as stubs). Keep them so ZSTD_buildBlockEntropyStats
// (used only by the super-block path) still links.
pub fn ZSTD_buildBlockEntropyStats_literals(
    src: ?*anyopaque,
    srcSize: usize,
    prevHuf: [*c]const ZSTD_hufCTables_t,
    nextHuf: [*c]ZSTD_hufCTables_t,
    hufMetadata: [*c]ZSTD_hufCTablesMetadata_t,
    literalsCompressionIsDisabled: c_int,
    workspace: ?*anyopaque,
    wkspSize: usize,
    hufFlags: c_int,
) callconv(.c) usize {
    _ = src;
    _ = srcSize;
    _ = prevHuf;
    _ = nextHuf;
    _ = hufMetadata;
    _ = literalsCompressionIsDisabled;
    _ = workspace;
    _ = wkspSize;
    _ = hufFlags;
    // Super-block path unused at level 3; error fast if the caller reaches here.
    return zerr(ZSTD_error_parameter_combination_unsupported);
}

pub fn ZSTD_buildBlockEntropyStats_sequences(
    seqStorePtr: [*c]const SeqStore_t,
    prevEntropy: [*c]const ZSTD_fseCTables_t,
    nextEntropy: [*c]ZSTD_fseCTables_t,
    cctxParams: [*c]const ZSTD_CCtx_params,
    fseMetadata: [*c]ZSTD_fseCTablesMetadata_t,
    workspace: ?*anyopaque,
    wkspSize: usize,
) callconv(.c) usize {
    _ = seqStorePtr;
    _ = prevEntropy;
    _ = nextEntropy;
    _ = cctxParams;
    _ = fseMetadata;
    _ = workspace;
    _ = wkspSize;
    return zerr(ZSTD_error_parameter_combination_unsupported);
}

pub fn ZSTD_literalsCompressionIsDisabled(cctxParams: [*c]const ZSTD_CCtx_params) callconv(.c) c_int {
    // Upstream consults cctxParams.literalCompressionMode (ZSTD_lcm_uncompressed
    // → disabled). We don't model that field yet; default to "enabled" so the
    // stats builder tries to compress.
    _ = cctxParams;
    return 0;
}

// HUF flag constant used by ZSTD_buildBlockEntropyStats.
pub const HUF_flags_optimalDepth: c_int = 1;

// -------------------------------------------------------------------------
//  ZSTD_buildBlockEntropyStats — translate-c 29577..29647.
//  Pure wrapper that sequences the literals + sequences stats builders.
// -------------------------------------------------------------------------

pub export fn ZSTD_buildBlockEntropyStats(
    seqStorePtr: [*c]const SeqStore_t,
    prevEntropy: [*c]const ZSTD_entropyCTables_t,
    nextEntropy: [*c]ZSTD_entropyCTables_t,
    cctxParams: [*c]const ZSTD_CCtx_params,
    entropyMetadata: [*c]ZSTD_entropyCTablesMetadata_t,
    workspace: ?*anyopaque,
    wkspSize: usize,
) usize {
    const litStart = seqStorePtr.*.litStart;
    const litPtr = seqStorePtr.*.lit;
    const litSize: usize = @intFromPtr(litPtr) -% @intFromPtr(litStart);

    const huf_useOptDepth: c_int = @intFromBool(
        cctxParams.*.cParams.strategy >= @as(c_uint, @bitCast(zstd_compress.ZSTD_btultra)),
    );
    const hufFlags: c_int = if (huf_useOptDepth != 0) HUF_flags_optimalDepth else 0;

    entropyMetadata.*.hufMetadata.hufDesSize = ZSTD_buildBlockEntropyStats_literals(
        @as(?*anyopaque, @ptrCast(litStart)),
        litSize,
        &prevEntropy.*.huf,
        &nextEntropy.*.huf,
        &entropyMetadata.*.hufMetadata,
        ZSTD_literalsCompressionIsDisabled(cctxParams),
        workspace,
        wkspSize,
        hufFlags,
    );
    if (errIsError(entropyMetadata.*.hufMetadata.hufDesSize)) {
        return entropyMetadata.*.hufMetadata.hufDesSize;
    }

    entropyMetadata.*.fseMetadata.fseTablesSize = ZSTD_buildBlockEntropyStats_sequences(
        seqStorePtr,
        &prevEntropy.*.fse,
        &nextEntropy.*.fse,
        cctxParams,
        &entropyMetadata.*.fseMetadata,
        workspace,
        wkspSize,
    );
    if (errIsError(entropyMetadata.*.fseMetadata.fseTablesSize)) {
        return entropyMetadata.*.fseMetadata.fseTablesSize;
    }
    return 0;
}

// -------------------------------------------------------------------------
//  ZSTD_compressBlock_targetCBlockSize_body — translate-c 35985..36046.
//  Tries the super-block compressor; falls back to raw (noCompress) on
//  dstSize_tooSmall or when savings are too small.
// -------------------------------------------------------------------------

pub fn ZSTD_compressBlock_targetCBlockSize_body(
    zc: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    bss: usize,
    lastBlock: U32,
) callconv(.c) usize {
    if (bss == @as(usize, @bitCast(@as(isize, ZSTDbss_compress)))) {
        // RLE fast-path: homogeneous block with a worthwhile seqStore.
        if (zc.*.isFirstBlock == 0 and
            ZSTD_maybeRLE(&zc.*.seqStore) != 0 and
            ZSTD_isRLE(@as([*c]const BYTE, @ptrCast(@alignCast(src))), srcSize) != 0)
        {
            const sp: [*c]const BYTE = @ptrCast(@alignCast(src));
            return ZSTD_rleCompressBlock(dst, dstCapacity, sp.*, srcSize, lastBlock);
        }
        const cSize: usize = ZSTD_compressSuperBlock(zc, dst, dstCapacity, src, srcSize, lastBlock);
        if (cSize != zerr(ZSTD_error_dstSize_tooSmall)) {
            const maxCSize: usize = srcSize -% ZSTD_minGain(srcSize, zc.*.appliedParams.cParams.strategy);
            if (errIsError(cSize)) return cSize;
            if (cSize != 0 and cSize < (maxCSize +% ZSTD_blockHeaderSize)) {
                ZSTD_blockState_confirmRepcodesAndEntropyTables(&zc.*.blockState);
                return cSize;
            }
        }
    }
    // Fallback: emit a raw block.
    return ZSTD_noCompressBlock(dst, dstCapacity, src, srcSize, lastBlock);
}

// -------------------------------------------------------------------------
//  ZSTD_compressBlock_targetCBlockSize — translate-c 36047..36118.
//  Builds the seq store, then delegates to _body; finally bumps the
//  offcode repeat-mode tracker on success.
// -------------------------------------------------------------------------

pub fn ZSTD_compressBlock_targetCBlockSize(
    zc: [*c]ZSTD_CCtx,
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    lastBlock: U32,
) callconv(.c) usize {
    const bss: usize = ZSTD_buildSeqStore(zc, src, srcSize);
    if (errIsError(bss)) return bss;
    const cSize: usize = ZSTD_compressBlock_targetCBlockSize_body(zc, dst, dstCapacity, src, srcSize, bss, lastBlock);
    if (errIsError(cSize)) return cSize;
    // Bump the prev-state offcode repeat tracker on successful emit —
    // translate-c 36114..36116. The fse module owns the FSE_repeat enum.
    const fse = @import("fse_compress.zig");
    if (zc.*.blockState.prevCBlock.*.entropy.fse.offcode_repeatMode == .FSE_repeat_valid) {
        zc.*.blockState.prevCBlock.*.entropy.fse.offcode_repeatMode = .FSE_repeat_check;
    }
    _ = fse;
    return cSize;
}

// -------------------------------------------------------------------------
//  Public wrappers — translate-c lines 27163..27175, 32001..32030.
//  ZSTD_compressBlock / _deprecated live in the frame module because they
//  call ZSTD_compressContinue_internal.
// -------------------------------------------------------------------------

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------

test "writeLE24 round-trips to 3 little-endian bytes" {
    var buf: [4]u8 = .{ 0xAA, 0xAA, 0xAA, 0xAA };
    writeLE24(&buf, 0x123456);
    try std.testing.expectEqual(@as(u8, 0x56), buf[0]);
    try std.testing.expectEqual(@as(u8, 0x34), buf[1]);
    try std.testing.expectEqual(@as(u8, 0x12), buf[2]);
    try std.testing.expectEqual(@as(u8, 0xAA), buf[3]);
}

test "ZSTD_noCompressBlock dstSize_tooSmall" {
    var dst: [2]u8 = .{ 0, 0 };
    const src: [4]u8 = .{ 1, 2, 3, 4 };
    const r = ZSTD_noCompressBlock(@ptrCast(&dst), dst.len, @ptrCast(&src), src.len, 0);
    try std.testing.expect(common.ERR_isError(r) != 0);
}

test "ZSTD_noCompressBlock emits header + payload" {
    var dst: [16]u8 = .{0} ** 16;
    const src: [4]u8 = .{ 0xAA, 0xBB, 0xCC, 0xDD };
    const r = ZSTD_noCompressBlock(@ptrCast(&dst), dst.len, @ptrCast(&src), src.len, 1);
    try std.testing.expectEqual(@as(usize, 3 + 4), r);
    // lastBlock=1 | (bt_raw=0 << 1) | (4 << 3) == 0x21
    try std.testing.expectEqual(@as(u8, 0x21), dst[0]);
    try std.testing.expectEqual(@as(u8, 0x00), dst[1]);
    try std.testing.expectEqual(@as(u8, 0x00), dst[2]);
    try std.testing.expectEqual(@as(u8, 0xAA), dst[3]);
    try std.testing.expectEqual(@as(u8, 0xDD), dst[6]);
}

test "ZSTD_rleCompressBlock emits header + byte" {
    var dst: [8]u8 = .{0} ** 8;
    const r = ZSTD_rleCompressBlock(@ptrCast(&dst), dst.len, 0x42, 1024, 0);
    try std.testing.expectEqual(@as(usize, 4), r);
    // lastBlock=0 | (bt_rle=1 << 1) | (1024 << 3) == 0x02 + 0x2000 = 0x2002
    try std.testing.expectEqual(@as(u8, 0x02), dst[0]);
    try std.testing.expectEqual(@as(u8, 0x20), dst[1]);
    try std.testing.expectEqual(@as(u8, 0x00), dst[2]);
    try std.testing.expectEqual(@as(u8, 0x42), dst[3]);
}

test "ZSTD_minGain parity with literals module" {
    // lits.ZSTD_minGain takes lits.ZSTD_strategy (enum); we take c_uint.
    // Both wrappers compute the same value for strat=ZSTD_fast.
    const strat_u: c_uint = @as(c_uint, @bitCast(zstd_compress.ZSTD_fast));
    const strat_e = lits.ZSTD_strategy.ZSTD_fast;
    try std.testing.expectEqual(lits.ZSTD_minGain(1024, strat_e), ZSTD_minGain(1024, strat_u));
}

test "block-type round-trip: bt_raw=0, bt_rle=1, bt_compressed=2" {
    try std.testing.expectEqual(@as(c_int, 0), bt_raw);
    try std.testing.expectEqual(@as(c_int, 1), bt_rle);
    try std.testing.expectEqual(@as(c_int, 2), bt_compressed);
    try std.testing.expectEqual(@as(usize, 3), ZSTD_blockHeaderSize);
}
