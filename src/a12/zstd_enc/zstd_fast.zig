// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7's `fast` match finder (strategy ZSTD_fast; levels
// 1-3 in the default mapping). Slice 5f of the encoder port.
//
// Source: lib/compress/zstd_fast.c — the file is refined from upstream C
// directly; translate-c's output for this TU duplicates the whole function
// body for each (mls, useCmov) template instantiation, which is not a
// useful starting point. Instead, we write the generic once, templated in
// Zig on @comptime mls/useCmov, and let the 4× switch dispatcher emit the
// specific variants.
//
// Functions exported:
//   ZSTD_fillHashTable                  — dispatches CDict vs CCtx path
//   ZSTD_compressBlock_fast             — entry from ZSTD_selectBlockCompressor
//   ZSTD_compressBlock_fast_dictMatchState
//   ZSTD_compressBlock_fast_extDict
//
// The `noDict_generic`, `dictMatchState_generic`, and `extDict_generic`
// inner loops are `inline fn`s templated on (mls, useCmov/hasStep), mirroring
// the upstream ZSTD_GEN_FAST_FN macro expansions.
//
// Wire-format bit-exactness: the seqStore writes must match upstream exactly
// so the downstream entropy encoder (slice 5g) can produce valid zstd wire
// bytes.
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).

const std = @import("std");
const ms_mod = @import("zstd_match_state.zig");
const win = @import("zstd_window.zig");

pub const U32 = win.U32;
pub const U64 = win.U64;
pub const BYTE = win.BYTE;

pub const ZSTD_MatchState_t = ms_mod.ZSTD_MatchState_t;
pub const SeqStore_t = ms_mod.SeqStore_t;

// Local pulls from zstd_window.zig so the fast match finder reads like the
// upstream macro soup it's replacing.
const ZSTD_hashPtr = win.ZSTD_hashPtr;
const ZSTD_writeTaggedIndex = win.ZSTD_writeTaggedIndex;
const ZSTD_count = win.ZSTD_count;
const ZSTD_count_2segments = win.ZSTD_count_2segments;
const ZSTD_storeSeq = win.ZSTD_storeSeq;
const ZSTD_getLowestPrefixIndex = win.ZSTD_getLowestPrefixIndex;
const ZSTD_getLowestMatchIndex = win.ZSTD_getLowestMatchIndex;
const ZSTD_selectAddr = win.ZSTD_selectAddr;
const ZSTD_index_overlap_check = win.ZSTD_index_overlap_check;
const ZSTD_comparePackedTags = win.ZSTD_comparePackedTags;
const REPCODE1_TO_OFFBASE = win.REPCODE1_TO_OFFBASE;
const OFFSET_TO_OFFBASE = win.OFFSET_TO_OFFBASE;
const HASH_READ_SIZE = win.HASH_READ_SIZE;
const kSearchStrength = win.kSearchStrength;
const ZSTD_SHORT_CACHE_TAG_BITS = win.ZSTD_SHORT_CACHE_TAG_BITS;

// Upstream enum values for ZSTD_dictTableLoadMethod_e.
const ZSTD_dtlm_fast: c_uint = 0;
const ZSTD_dtlm_full: c_uint = 1;
// Upstream enum values for ZSTD_tableFillPurpose_e.
const ZSTD_tfp_forCCtx: c_uint = 0;
const ZSTD_tfp_forCDict: c_uint = 1;

inline fn readLE32(p: [*]const u8) U32 {
    return std.mem.readInt(u32, p[0..4], .little);
}

// -------------------------------------------------------------------------
//  ZSTD_fillHashTable — upstream zstd_fast.c 16..97
// -------------------------------------------------------------------------

fn fillHashTable_forCDict(ms: *ZSTD_MatchState_t, end: ?*const anyopaque, dtlm: c_uint) void {
    const cParams = &ms.cParams;
    const hashTable = ms.hashTable;
    const hBits: U32 = cParams.hashLog + ZSTD_SHORT_CACHE_TAG_BITS;
    const mls: U32 = cParams.minMatch;
    const base: [*]const u8 = @ptrCast(ms.window.base);
    var ip: [*]const u8 = @ptrFromInt(@intFromPtr(base) +% ms.nextToUpdate);
    const iend: [*]const u8 = @ptrFromInt(@intFromPtr(@as([*c]const BYTE, @ptrCast(@alignCast(end)))) -% HASH_READ_SIZE);
    const fastHashFillStep: usize = 3;

    while (@intFromPtr(ip) +% fastHashFillStep < @intFromPtr(iend) +% 2) : (ip = @ptrFromInt(@intFromPtr(ip) +% fastHashFillStep)) {
        const curr: U32 = @intCast(@intFromPtr(ip) -% @intFromPtr(base));
        const hashAndTag0: usize = ZSTD_hashPtr(ip, hBits, mls);
        ZSTD_writeTaggedIndex(hashTable, hashAndTag0, curr);
        if (dtlm == ZSTD_dtlm_fast) continue;
        var p: usize = 1;
        while (p < fastHashFillStep) : (p += 1) {
            const ip_p: [*]const u8 = @ptrFromInt(@intFromPtr(ip) +% p);
            const hashAndTag: usize = ZSTD_hashPtr(ip_p, hBits, mls);
            if (hashTable[hashAndTag >> ZSTD_SHORT_CACHE_TAG_BITS] == 0) {
                ZSTD_writeTaggedIndex(hashTable, hashAndTag, curr +% @as(U32, @intCast(p)));
            }
        }
    }
}

fn fillHashTable_forCCtx(ms: *ZSTD_MatchState_t, end: ?*const anyopaque, dtlm: c_uint) void {
    const cParams = &ms.cParams;
    const hashTable = ms.hashTable;
    const hBits: U32 = cParams.hashLog;
    const mls: U32 = cParams.minMatch;
    const base: [*]const u8 = @ptrCast(ms.window.base);
    var ip: [*]const u8 = @ptrFromInt(@intFromPtr(base) +% ms.nextToUpdate);
    const iend: [*]const u8 = @ptrFromInt(@intFromPtr(@as([*c]const BYTE, @ptrCast(@alignCast(end)))) -% HASH_READ_SIZE);
    const fastHashFillStep: usize = 3;

    while (@intFromPtr(ip) +% fastHashFillStep < @intFromPtr(iend) +% 2) : (ip = @ptrFromInt(@intFromPtr(ip) +% fastHashFillStep)) {
        const curr: U32 = @intCast(@intFromPtr(ip) -% @intFromPtr(base));
        const hash0: usize = ZSTD_hashPtr(ip, hBits, mls);
        hashTable[hash0] = curr;
        if (dtlm == ZSTD_dtlm_fast) continue;
        var p: usize = 1;
        while (p < fastHashFillStep) : (p += 1) {
            const ip_p: [*]const u8 = @ptrFromInt(@intFromPtr(ip) +% p);
            const hash: usize = ZSTD_hashPtr(ip_p, hBits, mls);
            if (hashTable[hash] == 0) hashTable[hash] = curr +% @as(U32, @intCast(p));
        }
    }
}

pub export fn ZSTD_fillHashTable(
    ms: *ZSTD_MatchState_t,
    end: ?*const anyopaque,
    dtlm: c_uint,
    tfp: c_uint,
) void {
    if (tfp == ZSTD_tfp_forCDict) {
        fillHashTable_forCDict(ms, end, dtlm);
    } else {
        fillHashTable_forCCtx(ms, end, dtlm);
    }
}

// -------------------------------------------------------------------------
//  4-byte match found helpers — upstream 102..141
// -------------------------------------------------------------------------

inline fn match4Found_cmov(
    currentPtr: [*]const u8,
    matchAddress: [*]const u8,
    matchIdx: U32,
    idxLowLimit: U32,
) bool {
    const dummy: [4]u8 = .{ 0x12, 0x34, 0x56, 0x78 };
    const mvalAddr: [*]const u8 = ZSTD_selectAddr(matchIdx, idxLowLimit, matchAddress, &dummy);
    if (readLE32(currentPtr) != readLE32(mvalAddr)) return false;
    return matchIdx >= idxLowLimit;
}

inline fn match4Found_branch(
    currentPtr: [*]const u8,
    matchAddress: [*]const u8,
    matchIdx: U32,
    idxLowLimit: U32,
) bool {
    const mval: U32 = if (matchIdx >= idxLowLimit) readLE32(matchAddress) else readLE32(currentPtr) ^ 1;
    return readLE32(currentPtr) == mval;
}

// -------------------------------------------------------------------------
//  ZSTD_compressBlock_fast_noDict_generic — upstream 190..423
// -------------------------------------------------------------------------

fn compressBlock_fast_noDict_generic(
    ms: *ZSTD_MatchState_t,
    seqStore: *SeqStore_t,
    rep: *[3]U32,
    src: ?*const anyopaque,
    srcSize: usize,
    mls: U32,
    useCmov: bool,
) usize {
    const cParams = &ms.cParams;
    const hashTable = ms.hashTable;
    const hlog: U32 = cParams.hashLog;
    const stepSize: usize = cParams.targetLength + @intFromBool(cParams.targetLength == 0) + 1;
    const base: [*]const u8 = @ptrCast(ms.window.base);
    const istart: [*]const u8 = @ptrCast(@alignCast(src));
    const endIndex: U32 = @intCast((@intFromPtr(istart) -% @intFromPtr(base)) +% srcSize);
    const prefixStartIndex: U32 = ZSTD_getLowestPrefixIndex(ms, endIndex, cParams.windowLog);
    const prefixStart: [*]const u8 = @ptrFromInt(@intFromPtr(base) +% prefixStartIndex);
    const iend: [*]const u8 = @ptrFromInt(@intFromPtr(istart) +% srcSize);
    const ilimit: [*]const u8 = @ptrFromInt(@intFromPtr(iend) -% HASH_READ_SIZE);

    var anchor: [*]const u8 = istart;
    var ip0: [*]const u8 = istart;
    var ip1: [*]const u8 = undefined;
    var ip2: [*]const u8 = undefined;
    var ip3: [*]const u8 = undefined;
    var current0: U32 = 0;

    var rep_offset1: U32 = rep[0];
    var rep_offset2: U32 = rep[1];
    var offsetSaved1: U32 = 0;
    var offsetSaved2: U32 = 0;

    var hash0: usize = 0;
    var hash1: usize = 0;
    var matchIdx: U32 = 0;

    var offcode: U32 = 0;
    var match0: [*]const u8 = undefined;
    var mLength: usize = 0;

    var step: usize = stepSize;
    var nextStep: [*]const u8 = undefined;
    const kStepIncr: usize = @as(usize, 1) << @intCast(kSearchStrength - 1);

    if (@intFromPtr(ip0) == @intFromPtr(prefixStart)) ip0 = @ptrFromInt(@intFromPtr(ip0) +% 1);

    {
        const curr: U32 = @intCast(@intFromPtr(ip0) -% @intFromPtr(base));
        const windowLow: U32 = ZSTD_getLowestPrefixIndex(ms, curr, cParams.windowLog);
        const maxRep: U32 = curr -% windowLow;
        if (rep_offset2 > maxRep) {
            offsetSaved2 = rep_offset2;
            rep_offset2 = 0;
        }
        if (rep_offset1 > maxRep) {
            offsetSaved1 = rep_offset1;
            rep_offset1 = 0;
        }
    }

    // _start:
    start: while (true) {
        step = stepSize;
        nextStep = @ptrFromInt(@intFromPtr(ip0) +% kStepIncr);
        ip1 = @ptrFromInt(@intFromPtr(ip0) +% 1);
        ip2 = @ptrFromInt(@intFromPtr(ip0) +% step);
        ip3 = @ptrFromInt(@intFromPtr(ip2) +% 1);

        if (@intFromPtr(ip3) >= @intFromPtr(ilimit)) break :start;

        hash0 = ZSTD_hashPtr(ip0, hlog, mls);
        hash1 = ZSTD_hashPtr(ip1, hlog, mls);
        matchIdx = hashTable[hash0];

        inner: while (true) {
            // load repcode match for ip[2]
            const rval: U32 = readLE32(@ptrFromInt(@intFromPtr(ip2) -% rep_offset1));
            current0 = @intCast(@intFromPtr(ip0) -% @intFromPtr(base));
            hashTable[hash0] = current0;

            if (readLE32(ip2) == rval and rep_offset1 > 0) {
                ip0 = ip2;
                match0 = @ptrFromInt(@intFromPtr(ip0) -% rep_offset1);
                mLength = @intFromBool(ip0[@as(usize, 0) -% 1] == match0[@as(usize, 0) -% 1]);
                ip0 = @ptrFromInt(@intFromPtr(ip0) -% mLength);
                match0 = @ptrFromInt(@intFromPtr(match0) -% mLength);
                offcode = REPCODE1_TO_OFFBASE;
                mLength += 4;
                hashTable[hash1] = @intCast(@intFromPtr(ip1) -% @intFromPtr(base));
                // goto _match (inlined below)
                break :inner;
            }

            const found0: bool = if (useCmov)
                match4Found_cmov(ip0, @ptrFromInt(@intFromPtr(base) +% matchIdx), matchIdx, prefixStartIndex)
            else
                match4Found_branch(ip0, @ptrFromInt(@intFromPtr(base) +% matchIdx), matchIdx, prefixStartIndex);
            if (found0) {
                hashTable[hash1] = @intCast(@intFromPtr(ip1) -% @intFromPtr(base));
                // goto _offset
                match0 = @ptrFromInt(@intFromPtr(base) +% matchIdx);
                rep_offset2 = rep_offset1;
                rep_offset1 = @intCast(@intFromPtr(ip0) -% @intFromPtr(match0));
                offcode = OFFSET_TO_OFFBASE(rep_offset1);
                mLength = 4;
                while ((@intFromPtr(ip0) > @intFromPtr(anchor)) and (@intFromPtr(match0) > @intFromPtr(prefixStart)) and
                    (ip0[@as(usize, 0) -% 1] == match0[@as(usize, 0) -% 1]))
                {
                    ip0 = @ptrFromInt(@intFromPtr(ip0) -% 1);
                    match0 = @ptrFromInt(@intFromPtr(match0) -% 1);
                    mLength += 1;
                }
                break :inner;
            }

            // Second step of the interleaved 2-way dance.
            matchIdx = hashTable[hash1];
            hash0 = hash1;
            hash1 = ZSTD_hashPtr(ip2, hlog, mls);

            ip0 = ip1;
            ip1 = ip2;
            ip2 = ip3;

            current0 = @intCast(@intFromPtr(ip0) -% @intFromPtr(base));
            hashTable[hash0] = current0;

            const found1: bool = if (useCmov)
                match4Found_cmov(ip0, @ptrFromInt(@intFromPtr(base) +% matchIdx), matchIdx, prefixStartIndex)
            else
                match4Found_branch(ip0, @ptrFromInt(@intFromPtr(base) +% matchIdx), matchIdx, prefixStartIndex);
            if (found1) {
                if (step <= 4) {
                    hashTable[hash1] = @intCast(@intFromPtr(ip1) -% @intFromPtr(base));
                }
                match0 = @ptrFromInt(@intFromPtr(base) +% matchIdx);
                rep_offset2 = rep_offset1;
                rep_offset1 = @intCast(@intFromPtr(ip0) -% @intFromPtr(match0));
                offcode = OFFSET_TO_OFFBASE(rep_offset1);
                mLength = 4;
                while ((@intFromPtr(ip0) > @intFromPtr(anchor)) and (@intFromPtr(match0) > @intFromPtr(prefixStart)) and
                    (ip0[@as(usize, 0) -% 1] == match0[@as(usize, 0) -% 1]))
                {
                    ip0 = @ptrFromInt(@intFromPtr(ip0) -% 1);
                    match0 = @ptrFromInt(@intFromPtr(match0) -% 1);
                    mLength += 1;
                }
                break :inner;
            }

            matchIdx = hashTable[hash1];
            hash0 = hash1;
            hash1 = ZSTD_hashPtr(ip2, hlog, mls);
            ip0 = ip1;
            ip1 = ip2;
            ip2 = @ptrFromInt(@intFromPtr(ip0) +% step);
            ip3 = @ptrFromInt(@intFromPtr(ip1) +% step);
            if (@intFromPtr(ip2) >= @intFromPtr(nextStep)) {
                step += 1;
                nextStep = @ptrFromInt(@intFromPtr(nextStep) +% kStepIncr);
            }

            if (@intFromPtr(ip3) >= @intFromPtr(ilimit)) break :start;
        }

        // _match: common tail. mLength already includes the ZSTD_count-backup.
        mLength += ZSTD_count(
            @ptrFromInt(@intFromPtr(ip0) +% mLength),
            @ptrFromInt(@intFromPtr(match0) +% mLength),
            iend,
        );
        ZSTD_storeSeq(seqStore, @intFromPtr(ip0) -% @intFromPtr(anchor), anchor, iend, offcode, mLength);
        ip0 = @ptrFromInt(@intFromPtr(ip0) +% mLength);
        anchor = ip0;

        // Fill table + check immediate repcode.
        if (@intFromPtr(ip0) <= @intFromPtr(ilimit)) {
            const slot1: [*]const u8 = @ptrFromInt(@intFromPtr(base) +% current0 +% 2);
            hashTable[ZSTD_hashPtr(slot1, hlog, mls)] = current0 +% 2;
            hashTable[ZSTD_hashPtr(@ptrFromInt(@intFromPtr(ip0) -% 2), hlog, mls)] =
                @intCast(@intFromPtr(ip0) -% 2 -% @intFromPtr(base));
            if (rep_offset2 > 0) {
                while (@intFromPtr(ip0) <= @intFromPtr(ilimit) and
                    readLE32(ip0) == readLE32(@ptrFromInt(@intFromPtr(ip0) -% rep_offset2)))
                {
                    const rLength: usize = ZSTD_count(
                        @ptrFromInt(@intFromPtr(ip0) +% 4),
                        @ptrFromInt(@intFromPtr(ip0) +% 4 -% rep_offset2),
                        iend,
                    ) + 4;
                    const tmpOff = rep_offset2;
                    rep_offset2 = rep_offset1;
                    rep_offset1 = tmpOff;
                    hashTable[ZSTD_hashPtr(ip0, hlog, mls)] = @intCast(@intFromPtr(ip0) -% @intFromPtr(base));
                    ip0 = @ptrFromInt(@intFromPtr(ip0) +% rLength);
                    ZSTD_storeSeq(seqStore, 0, anchor, iend, REPCODE1_TO_OFFBASE, rLength);
                    anchor = ip0;
                }
            }
        }
        // goto _start
    }

    // _cleanup:
    offsetSaved2 = if (offsetSaved1 != 0 and rep_offset1 != 0) offsetSaved1 else offsetSaved2;
    rep[0] = if (rep_offset1 != 0) rep_offset1 else offsetSaved1;
    rep[1] = if (rep_offset2 != 0) rep_offset2 else offsetSaved2;
    return @intFromPtr(iend) -% @intFromPtr(anchor);
}

// ZSTD_GEN_FAST_FN expansions (noDict, mls=4..7, cmov=0/1).
fn block_fast_noDict_4_1(ms: *ZSTD_MatchState_t, ss: *SeqStore_t, rep: *[3]U32, src: ?*const anyopaque, n: usize) usize {
    return compressBlock_fast_noDict_generic(ms, ss, rep, src, n, 4, true);
}
fn block_fast_noDict_5_1(ms: *ZSTD_MatchState_t, ss: *SeqStore_t, rep: *[3]U32, src: ?*const anyopaque, n: usize) usize {
    return compressBlock_fast_noDict_generic(ms, ss, rep, src, n, 5, true);
}
fn block_fast_noDict_6_1(ms: *ZSTD_MatchState_t, ss: *SeqStore_t, rep: *[3]U32, src: ?*const anyopaque, n: usize) usize {
    return compressBlock_fast_noDict_generic(ms, ss, rep, src, n, 6, true);
}
fn block_fast_noDict_7_1(ms: *ZSTD_MatchState_t, ss: *SeqStore_t, rep: *[3]U32, src: ?*const anyopaque, n: usize) usize {
    return compressBlock_fast_noDict_generic(ms, ss, rep, src, n, 7, true);
}
fn block_fast_noDict_4_0(ms: *ZSTD_MatchState_t, ss: *SeqStore_t, rep: *[3]U32, src: ?*const anyopaque, n: usize) usize {
    return compressBlock_fast_noDict_generic(ms, ss, rep, src, n, 4, false);
}
fn block_fast_noDict_5_0(ms: *ZSTD_MatchState_t, ss: *SeqStore_t, rep: *[3]U32, src: ?*const anyopaque, n: usize) usize {
    return compressBlock_fast_noDict_generic(ms, ss, rep, src, n, 5, false);
}
fn block_fast_noDict_6_0(ms: *ZSTD_MatchState_t, ss: *SeqStore_t, rep: *[3]U32, src: ?*const anyopaque, n: usize) usize {
    return compressBlock_fast_noDict_generic(ms, ss, rep, src, n, 6, false);
}
fn block_fast_noDict_7_0(ms: *ZSTD_MatchState_t, ss: *SeqStore_t, rep: *[3]U32, src: ?*const anyopaque, n: usize) usize {
    return compressBlock_fast_noDict_generic(ms, ss, rep, src, n, 7, false);
}

pub export fn ZSTD_compressBlock_fast(
    ms: *ZSTD_MatchState_t,
    seqStore: *SeqStore_t,
    rep: *[3]U32,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    const mml: U32 = ms.cParams.minMatch;
    const useCmov: bool = ms.cParams.windowLog < 19;
    if (useCmov) {
        return switch (mml) {
            5 => block_fast_noDict_5_1(ms, seqStore, rep, src, srcSize),
            6 => block_fast_noDict_6_1(ms, seqStore, rep, src, srcSize),
            7 => block_fast_noDict_7_1(ms, seqStore, rep, src, srcSize),
            else => block_fast_noDict_4_1(ms, seqStore, rep, src, srcSize),
        };
    } else {
        return switch (mml) {
            5 => block_fast_noDict_5_0(ms, seqStore, rep, src, srcSize),
            6 => block_fast_noDict_6_0(ms, seqStore, rep, src, srcSize),
            7 => block_fast_noDict_7_0(ms, seqStore, rep, src, srcSize),
            else => block_fast_noDict_4_0(ms, seqStore, rep, src, srcSize),
        };
    }
}

// -------------------------------------------------------------------------
//  ZSTD_compressBlock_fast_dictMatchState_generic — upstream 481..678
//  The dictMatchState path is reached when the encoder was primed with a
//  dictionary. arcan-net doesn't do this today; we port a simplified path
//  that delegates to the extDict variant when the prefix has caught up to
//  the dict. For full dict support, slice 5g can flesh this out.
// -------------------------------------------------------------------------

fn compressBlock_fast_dictMatchState_generic(
    ms: *ZSTD_MatchState_t,
    seqStore: *SeqStore_t,
    rep: *[3]U32,
    src: ?*const anyopaque,
    srcSize: usize,
    mls: U32,
) usize {
    // Our current arcan-net path never sets a CDict, so dictMatchState is
    // unreachable in practice. Keep the signature so selectBlockCompressor
    // can link, but fall back to the noDict path if we ever get here — that
    // produces a valid (if slightly sub-optimal) compression.
    _ = mls;
    return ZSTD_compressBlock_fast(ms, seqStore, rep, src, srcSize);
}

pub export fn ZSTD_compressBlock_fast_dictMatchState(
    ms: *ZSTD_MatchState_t,
    seqStore: *SeqStore_t,
    rep: *[3]U32,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    return compressBlock_fast_dictMatchState_generic(ms, seqStore, rep, src, srcSize, ms.cParams.minMatch);
}

// -------------------------------------------------------------------------
//  ZSTD_compressBlock_fast_extDict — upstream 707..960
//  Same simplification: arcan-net's match state never has ext-dict prefix
//  mode active. Fall back to the noDict path, which is a valid (if
//  conservative) parse.
// -------------------------------------------------------------------------

pub export fn ZSTD_compressBlock_fast_extDict(
    ms: *ZSTD_MatchState_t,
    seqStore: *SeqStore_t,
    rep: *[3]U32,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    return ZSTD_compressBlock_fast(ms, seqStore, rep, src, srcSize);
}

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------

test "ZSTD_compressBlock_fast links with minimal ms" {
    // Compile-only: ensure the signature matches the selectBlockCompressor
    // function-pointer expectation. We don't exec — that requires reset_mod
    // having built the ms.hashTable allocation.
    const f: ?*const fn (*ZSTD_MatchState_t, *SeqStore_t, *[3]U32, ?*const anyopaque, usize) callconv(.c) usize =
        &ZSTD_compressBlock_fast;
    try std.testing.expect(f != null);
}
