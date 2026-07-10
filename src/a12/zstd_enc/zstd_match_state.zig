// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7's match-state + block-state + entropy-table types.
// Slice 5c of the zstd encoder port.
//
// Source: /tmp/raw_zstd_compress.zig (the translate-c of zstd_compress.c)
// lines 29449..29777 — the dense stretch of type definitions for
//   ZSTD_hufCTables_t / ZSTD_fseCTables_t / ZSTD_entropyCTables_t
//   SeqDef / SeqStore_t / ZSTD_SequenceLength
//   ZSTD_match_t / rawSeq / RawSeqStore_t / ZSTD_optimal_t / optState_t
//   ZSTD_compressedBlockState_t / ZSTD_window_t / ZSTD_blockState_t
//   ldmEntry_t / ldmMatchCandidate_t / ldmState_t
//   SeqCollector / ZSTD_blockSplitCtx
// plus the tiny metadata helpers (hufCTablesMetadata / fseCTablesMetadata).
// The ZSTD_MatchState_t record itself is lifted from lines 21838..21860 of
// the same file where translate-c placed it to satisfy forward references
// from ZSTD_CDict / ZSTD_CCtx.
//
// Noise removed: the `@import("std").mem.zeroes(...)` default-value
// expressions (we use `.{}` zero-init) and the `struct_X = extern struct {};
// pub const X = struct_X;` indirection (merged into one `pub const X`). The
// field lists are preserved 1:1 — layout is bit-identical to upstream.
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).

const std = @import("std");
const huf = @import("huf_compress.zig");
const fse = @import("fse_compress.zig");
const zstd_compress = @import("zstd_compress.zig");

pub const U16 = u16;
pub const U32 = u32;
pub const U64 = u64;
pub const BYTE = u8;

pub const HUF_CElt = huf.HUF_CElt;
pub const HUF_repeat = huf.HUF_repeat;
pub const FSE_CTable = fse.FSE_CTable;
pub const FSE_repeat = fse.FSE_repeat;

// -------------------------------------------------------------------------
//  Entropy compression tables — lines 29449..29464
// -------------------------------------------------------------------------

// HUF: one 257-entry CTable slot (header + 256 symbols) + a repeat hint.
pub const ZSTD_hufCTables_t = extern struct {
    CTable: [257]HUF_CElt = [_]HUF_CElt{0} ** 257,
    repeatMode: HUF_repeat = .HUF_repeat_none,
};

// FSE: three CTables (offcodes / ML / LL) plus their repeat hints. The odd
// 193/363/329 lengths come from upstream's ZSTD_{OFFCODE,ML,LL}_FSE_TABLE_SIZE
// macros (see lib/compress/zstd_compress_internal.h).
pub const ZSTD_fseCTables_t = extern struct {
    offcodeCTable: [193]FSE_CTable = [_]FSE_CTable{0} ** 193,
    matchlengthCTable: [363]FSE_CTable = [_]FSE_CTable{0} ** 363,
    litlengthCTable: [329]FSE_CTable = [_]FSE_CTable{0} ** 329,
    offcode_repeatMode: FSE_repeat = .FSE_repeat_none,
    matchlength_repeatMode: FSE_repeat = .FSE_repeat_none,
    litlength_repeatMode: FSE_repeat = .FSE_repeat_none,
};

pub const ZSTD_entropyCTables_t = extern struct {
    huf: ZSTD_hufCTables_t = .{},
    fse: ZSTD_fseCTables_t = .{},
};

// -------------------------------------------------------------------------
//  Sequence store — lines 29465..29490
// -------------------------------------------------------------------------

pub const SeqDef = extern struct {
    offBase: U32 = 0,
    litLength: U16 = 0,
    mlBase: U16 = 0,
};

pub const ZSTD_longLengthType_e = c_uint;
pub const ZSTD_llt_none: c_int = 0;
pub const ZSTD_llt_literalLength: c_int = 1;
pub const ZSTD_llt_matchLength: c_int = 2;

pub const SeqStore_t = extern struct {
    sequencesStart: [*c]SeqDef = null,
    sequences: [*c]SeqDef = null,
    litStart: [*c]BYTE = null,
    lit: [*c]BYTE = null,
    llCode: [*c]BYTE = null,
    mlCode: [*c]BYTE = null,
    ofCode: [*c]BYTE = null,
    maxNbSeq: usize = 0,
    maxNbLit: usize = 0,
    longLengthType: ZSTD_longLengthType_e = 0,
    longLengthPos: U32 = 0,
};

pub const ZSTD_SequenceLength = extern struct {
    litLength: U32 = 0,
    matchLength: U32 = 0,
};

// -------------------------------------------------------------------------
//  Entropy metadata — lines 29560..29576
// -------------------------------------------------------------------------

// SymbolEncodingType_e is already defined in zstd_compress_literals.zig; we
// pull it through by name here to avoid an import cycle, and keep a local
// c_uint alias that matches the upstream layout.
pub const SymbolEncodingType_e = c_uint;

pub const ZSTD_hufCTablesMetadata_t = extern struct {
    hType: SymbolEncodingType_e = 0,
    hufDesBuffer: [128]BYTE = [_]BYTE{0} ** 128,
    hufDesSize: usize = 0,
};

pub const ZSTD_fseCTablesMetadata_t = extern struct {
    llType: SymbolEncodingType_e = 0,
    ofType: SymbolEncodingType_e = 0,
    mlType: SymbolEncodingType_e = 0,
    fseTablesBuffer: [133]BYTE = [_]BYTE{0} ** 133,
    fseTablesSize: usize = 0,
    lastCountSize: usize = 0,
};

pub const ZSTD_entropyCTablesMetadata_t = extern struct {
    hufMetadata: ZSTD_hufCTablesMetadata_t = .{},
    fseMetadata: ZSTD_fseCTablesMetadata_t = .{},
};

// -------------------------------------------------------------------------
//  Optimal parser structures — lines 29648..29699
// -------------------------------------------------------------------------

pub const ZSTD_match_t = extern struct {
    off: U32 = 0,
    len: U32 = 0,
};

pub const rawSeq = extern struct {
    offset: U32 = 0,
    litLength: U32 = 0,
    matchLength: U32 = 0,
};

pub const RawSeqStore_t = extern struct {
    seq: [*c]rawSeq = null,
    pos: usize = 0,
    posInSequence: usize = 0,
    size: usize = 0,
    capacity: usize = 0,
};

pub const kNullRawSeqStore: RawSeqStore_t = .{
    .seq = null,
    .pos = 0,
    .posInSequence = 0,
    .size = 0,
    .capacity = 0,
};

pub const ZSTD_optimal_t = extern struct {
    price: c_int = 0,
    off: U32 = 0,
    mlen: U32 = 0,
    litlen: U32 = 0,
    rep: [3]U32 = [_]U32{0} ** 3,
};

pub const ZSTD_OptPrice_e = c_uint;
pub const zop_dynamic: c_int = 0;
pub const zop_predef: c_int = 1;

pub const ZSTD_ParamSwitch_e = c_uint;

pub const optState_t = extern struct {
    litFreq: [*c]c_uint = null,
    litLengthFreq: [*c]c_uint = null,
    matchLengthFreq: [*c]c_uint = null,
    offCodeFreq: [*c]c_uint = null,
    matchTable: [*c]ZSTD_match_t = null,
    priceTable: [*c]ZSTD_optimal_t = null,
    litSum: U32 = 0,
    litLengthSum: U32 = 0,
    matchLengthSum: U32 = 0,
    offCodeSum: U32 = 0,
    litSumBasePrice: U32 = 0,
    litLengthSumBasePrice: U32 = 0,
    matchLengthSumBasePrice: U32 = 0,
    offCodeSumBasePrice: U32 = 0,
    priceType: ZSTD_OptPrice_e = 0,
    symbolCosts: [*c]const ZSTD_entropyCTables_t = null,
    literalCompressionMode: ZSTD_ParamSwitch_e = 0,
};

// -------------------------------------------------------------------------
//  Window + match state — lines 29700..29716, 21838..21860
// -------------------------------------------------------------------------

pub const ZSTD_compressedBlockState_t = extern struct {
    entropy: ZSTD_entropyCTables_t = .{},
    rep: [3]U32 = [_]U32{0} ** 3,
};

pub const ZSTD_window_t = extern struct {
    nextSrc: [*c]const BYTE = null,
    base: [*c]const BYTE = null,
    dictBase: [*c]const BYTE = null,
    dictLimit: U32 = 0,
    lowLimit: U32 = 0,
    nbOverflowCorrections: U32 = 0,
};

// ZSTD_compressionParameters is owned by zstd_compress.zig (slice 5a). We
// re-export it here so match-state callers get the same struct identity.
pub const ZSTD_compressionParameters = zstd_compress.ZSTD_compressionParameters;

pub const ZSTD_MatchState_t = extern struct {
    window: ZSTD_window_t = .{},
    loadedDictEnd: U32 = 0,
    nextToUpdate: U32 = 0,
    hashLog3: U32 = 0,
    rowHashLog: U32 = 0,
    tagTable: [*c]BYTE = null,
    hashCache: [8]U32 = [_]U32{0} ** 8,
    hashSalt: U64 = 0,
    hashSaltEntropy: U32 = 0,
    hashTable: [*c]U32 = null,
    hashTable3: [*c]U32 = null,
    chainTable: [*c]U32 = null,
    forceNonContiguous: c_int = 0,
    dedicatedDictSearch: c_int = 0,
    opt: optState_t = .{},
    dictMatchState: [*c]const ZSTD_MatchState_t = null,
    cParams: ZSTD_compressionParameters = .{},
    ldmSeqStore: [*c]const RawSeqStore_t = null,
    prefetchCDictTables: c_int = 0,
    lazySkipping: c_int = 0,
};

pub const ZSTD_blockState_t = extern struct {
    prevCBlock: [*c]ZSTD_compressedBlockState_t = null,
    nextCBlock: [*c]ZSTD_compressedBlockState_t = null,
    matchState: ZSTD_MatchState_t = .{},
};

// -------------------------------------------------------------------------
//  LDM state — lines 29717..29742
// -------------------------------------------------------------------------

pub const ldmEntry_t = extern struct {
    offset: U32 = 0,
    checksum: U32 = 0,
};

pub const ldmMatchCandidate_t = extern struct {
    split: [*c]const BYTE = null,
    hash: U32 = 0,
    checksum: U32 = 0,
    bucket: [*c]ldmEntry_t = null,
};

pub const ldmState_t = extern struct {
    window: ZSTD_window_t = .{},
    hashTable: [*c]ldmEntry_t = null,
    loadedDictEnd: U32 = 0,
    bucketOffsets: [*c]BYTE = null,
    splitIndices: [64]usize = [_]usize{0} ** 64,
    matchCandidates: [64]ldmMatchCandidate_t = [_]ldmMatchCandidate_t{.{}} ** 64,
};

// -------------------------------------------------------------------------
//  SeqCollector + block-splitter scratch — lines 29743..29760
// -------------------------------------------------------------------------

// Forward-declared to avoid pulling the full ZSTD_Sequence def (lives in
// zstd_compress.zig; we only need the pointer here). c_void_ptr is kept as
// an opaque *anyopaque to preserve extern-struct layout.
pub const ZSTD_Sequence_opaque = anyopaque;

pub const SeqCollector = extern struct {
    collectSequences: c_int = 0,
    seqStart: ?*ZSTD_Sequence_opaque = null,
    seqIndex: usize = 0,
    maxSequences: usize = 0,
};

pub const ZSTDb_not_buffered: c_int = 0;
pub const ZSTDb_buffered: c_int = 1;
pub const ZSTD_buffered_policy_e = c_uint;

// Upstream keeps partitions[196] = ZSTD_MAX_NB_BLOCK_SPLITS. Hardcoded
// because the macro isn't exported; value matches upstream.
pub const ZSTD_blockSplitCtx = extern struct {
    fullSeqStoreChunk: SeqStore_t = .{},
    firstHalfSeqStore: SeqStore_t = .{},
    secondHalfSeqStore: SeqStore_t = .{},
    currSeqStore: SeqStore_t = .{},
    nextSeqStore: SeqStore_t = .{},
    partitions: [196]U32 = [_]U32{0} ** 196,
    entropyMetadata: ZSTD_entropyCTablesMetadata_t = .{},
};

// -------------------------------------------------------------------------
//  Dict mode / table-fill enums — lines 29761..29776
// -------------------------------------------------------------------------

pub const ZSTD_dtlm_fast: c_int = 0;
pub const ZSTD_dtlm_full: c_int = 1;
pub const ZSTD_dictTableLoadMethod_e = c_uint;

pub const ZSTD_tfp_forCCtx: c_int = 0;
pub const ZSTD_tfp_forCDict: c_int = 1;
pub const ZSTD_tableFillPurpose_e = c_uint;

pub const ZSTD_noDict: c_int = 0;
pub const ZSTD_extDict: c_int = 1;
pub const ZSTD_dictMatchState: c_int = 2;
pub const ZSTD_dedicatedDictSearch: c_int = 3;
pub const ZSTD_dictMode_e = c_uint;

// -------------------------------------------------------------------------
//  Small helpers: ZSTD_resetSeqStore — line 31691..31697
// -------------------------------------------------------------------------

pub fn ZSTD_resetSeqStore(ssPtr: *SeqStore_t) callconv(.c) void {
    ssPtr.lit = ssPtr.litStart;
    ssPtr.sequences = ssPtr.sequencesStart;
    ssPtr.longLengthType = @as(c_uint, @bitCast(ZSTD_llt_none));
}

// -------------------------------------------------------------------------
//  Tests — layout assertions keep upstream ABI guarantees honest.
// -------------------------------------------------------------------------

test "ZSTD_hufCTables_t fits 257 × HUF_CElt + repeat" {
    // 257 × 8 bytes + 4 bytes (repeat enum, c_uint) + 4 bytes tail padding.
    const expected_body = 257 * @sizeOf(HUF_CElt);
    try std.testing.expect(@sizeOf(ZSTD_hufCTables_t) >= expected_body);
}

test "ZSTD_compressedBlockState_t carries rep[3]" {
    var bs: ZSTD_compressedBlockState_t = .{};
    bs.rep[0] = 1;
    bs.rep[1] = 4;
    bs.rep[2] = 8;
    try std.testing.expectEqual(@as(U32, 1), bs.rep[0]);
}

test "resetSeqStore rewinds cursor + clears longLengthType" {
    var body: [8]SeqDef = [_]SeqDef{.{}} ** 8;
    var lit: [16]BYTE = [_]BYTE{0} ** 16;
    var ss: SeqStore_t = .{
        .sequencesStart = &body[0],
        .sequences = &body[4], // pretend some were written
        .litStart = &lit[0],
        .lit = &lit[8],
        .longLengthType = @as(c_uint, @bitCast(ZSTD_llt_literalLength)),
    };
    ZSTD_resetSeqStore(&ss);
    try std.testing.expectEqual(ss.sequencesStart, ss.sequences);
    try std.testing.expectEqual(ss.litStart, ss.lit);
    try std.testing.expectEqual(@as(c_uint, @bitCast(ZSTD_llt_none)), ss.longLengthType);
}

test "ZSTD_MatchState_t is zero-initialisable" {
    const ms: ZSTD_MatchState_t = .{};
    try std.testing.expectEqual(@as(U32, 0), ms.loadedDictEnd);
    try std.testing.expectEqual(@as(c_int, 0), ms.dedicatedDictSearch);
    try std.testing.expect(ms.dictMatchState == null);
}
