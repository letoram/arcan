// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/compress/hist.c — symbol histogram helpers used
// by the FSE / Huffman encoders.
//
// Upstream:
//   hist : Histogram functions, part of Finite State Entropy project
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// All six public entry points (HIST_isError, HIST_count_simple,
// HIST_count_wksp, HIST_countFast_wksp, HIST_count, HIST_countFast) are
// exposed with the original C-ABI linker names via `pub export fn`.
//
// Notes:
//   - translate-c demoted HIST_count_parallel_wksp to extern because it hit
//     ZSTD_memmove -> __builtin_memmove (unimplemented in std.zig.c_builtins
//     today). That function is hand-ported below.
//   - The original `{U32 cached = MEM_read32(ip); ip += 4; ...}` hot loop is
//     preserved bit-for-bit, using std.mem.readInt for the unaligned 32-bit
//     reads (MEM_read32 semantics).

const std = @import("std");
const common = @import("zstd_common.zig");

const ZSTD_ErrorCode = common.ZSTD_ErrorCode;
const zstdError = common.zstdError;

// HIST_WKSP_SIZE_U32 from compress/hist.h
pub const HIST_WKSP_SIZE_U32: usize = 1024;
pub const HIST_WKSP_SIZE: usize = HIST_WKSP_SIZE_U32 * @sizeOf(c_uint);

// -------------------------------------------------------------------------
//  Error plumbing
// -------------------------------------------------------------------------
pub export fn HIST_isError(code: usize) c_uint {
    return common.ERR_isError(code);
}

// -------------------------------------------------------------------------
//  HIST_add — unused by the modern encoder but kept for completeness.
// -------------------------------------------------------------------------
pub export fn HIST_add(count: [*]c_uint, src: ?*const anyopaque, srcSize: usize) void {
    if (srcSize == 0) return;
    const ip: [*]const u8 = @ptrCast(src.?);
    var i: usize = 0;
    while (i < srcSize) : (i += 1) {
        count[ip[i]] +%= 1;
    }
}

// -------------------------------------------------------------------------
//  HIST_count_simple — scalar, used for small inputs.
//  Returns the largest single-symbol count or 0 when srcSize == 0.
// -------------------------------------------------------------------------
pub export fn HIST_count_simple(
    count: [*]c_uint,
    maxSymbolValuePtr: *c_uint,
    src: ?*const anyopaque,
    srcSize: usize,
) c_uint {
    var maxSymbolValue = maxSymbolValuePtr.*;

    // count[0..=maxSymbolValue] = 0
    @memset(count[0 .. maxSymbolValue + 1], 0);
    if (srcSize == 0) {
        maxSymbolValuePtr.* = 0;
        return 0;
    }

    const ip: [*]const u8 = @ptrCast(src.?);
    var i: usize = 0;
    while (i < srcSize) : (i += 1) {
        std.debug.assert(ip[i] <= maxSymbolValue);
        count[ip[i]] +%= 1;
    }

    while (count[maxSymbolValue] == 0) : (maxSymbolValue -%= 1) {}
    maxSymbolValuePtr.* = maxSymbolValue;

    var largestCount: c_uint = 0;
    var s: c_uint = 0;
    while (s <= maxSymbolValue) : (s +%= 1) {
        if (count[s] > largestCount) largestCount = count[s];
    }
    return largestCount;
}

// HIST_checkInput_e — HIST_count_parallel_wksp's "should I validate alphabet
// bounds?" toggle.
const HIST_checkInput_e = enum(c_uint) {
    trustInput = 0,
    checkMaxSymbolValue = 1,
};

// -------------------------------------------------------------------------
//  HIST_count_parallel_wksp — 4-way striped histogram to feed OoO cores.
//
//  This is the function translate-c demoted; port is faithful to the C
//  source, including the "ip-=4; finish last symbols" fix-up dance.
//
//  `workSpace` must be 4-byte-aligned and hold at least HIST_WKSP_SIZE_U32
//  u32 slots (that invariant is enforced by the callers below).
// -------------------------------------------------------------------------
fn HIST_count_parallel_wksp(
    count: [*]c_uint,
    maxSymbolValuePtr: *c_uint,
    source: ?*const anyopaque,
    sourceSize: usize,
    check: HIST_checkInput_e,
    workSpace: [*]u32,
) usize {
    const countSize = (maxSymbolValuePtr.* + 1) * @sizeOf(c_uint);
    var max: c_uint = 0;

    const counting1: [*]u32 = workSpace;
    const counting2: [*]u32 = workSpace + 256;
    const counting3: [*]u32 = workSpace + 512;
    const counting4: [*]u32 = workSpace + 768;

    std.debug.assert(maxSymbolValuePtr.* <= 255);
    if (sourceSize == 0) {
        // ZSTD_memset(count, 0, countSize) — use byte-wide memset to match.
        const cbytes: [*]u8 = @ptrCast(count);
        @memset(cbytes[0..countSize], 0);
        maxSymbolValuePtr.* = 0;
        return 0;
    }

    // Zero the full 4*256*u32 scratch.
    @memset(workSpace[0 .. 4 * 256], 0);

    // Stripes of 16 bytes (four u32 loads per iteration).
    const ip_base: [*]const u8 = @ptrCast(source.?);
    var ip: usize = 0;
    const iend: usize = sourceSize;
    if (iend >= 4) {
        var cached: u32 = std.mem.readInt(u32, ip_base[ip..][0..4], .little);
        ip += 4;
        // Stop while at least 16 bytes remain past ip.
        while (ip + 15 < iend) {
            var c: u32 = cached;
            cached = std.mem.readInt(u32, ip_base[ip..][0..4], .little);
            ip += 4;
            counting1[@as(u8, @truncate(c))] +%= 1;
            counting2[@as(u8, @truncate(c >> 8))] +%= 1;
            counting3[@as(u8, @truncate(c >> 16))] +%= 1;
            counting4[@as(u8, @truncate(c >> 24))] +%= 1;

            c = cached;
            cached = std.mem.readInt(u32, ip_base[ip..][0..4], .little);
            ip += 4;
            counting1[@as(u8, @truncate(c))] +%= 1;
            counting2[@as(u8, @truncate(c >> 8))] +%= 1;
            counting3[@as(u8, @truncate(c >> 16))] +%= 1;
            counting4[@as(u8, @truncate(c >> 24))] +%= 1;

            c = cached;
            cached = std.mem.readInt(u32, ip_base[ip..][0..4], .little);
            ip += 4;
            counting1[@as(u8, @truncate(c))] +%= 1;
            counting2[@as(u8, @truncate(c >> 8))] +%= 1;
            counting3[@as(u8, @truncate(c >> 16))] +%= 1;
            counting4[@as(u8, @truncate(c >> 24))] +%= 1;

            c = cached;
            cached = std.mem.readInt(u32, ip_base[ip..][0..4], .little);
            ip += 4;
            counting1[@as(u8, @truncate(c))] +%= 1;
            counting2[@as(u8, @truncate(c >> 8))] +%= 1;
            counting3[@as(u8, @truncate(c >> 16))] +%= 1;
            counting4[@as(u8, @truncate(c >> 24))] +%= 1;
        }
        // Upstream rewinds ip by 4 because the last `cached` was speculatively
        // loaded but not counted.
        ip -= 4;
    }

    // Finish trailing symbols scalar.
    while (ip < iend) : (ip += 1) {
        counting1[ip_base[ip]] +%= 1;
    }

    // Merge four streams; track running max.
    var s: usize = 0;
    while (s < 256) : (s += 1) {
        counting1[s] += counting2[s] + counting3[s] + counting4[s];
        if (counting1[s] > max) max = counting1[s];
    }

    var maxSymbolValue: c_uint = 255;
    while (counting1[maxSymbolValue] == 0) : (maxSymbolValue -%= 1) {}
    if (check == .checkMaxSymbolValue and maxSymbolValue > maxSymbolValuePtr.*) {
        return zstdError(.maxSymbolValue_tooLarge);
    }
    maxSymbolValuePtr.* = maxSymbolValue;

    // ZSTD_memmove(count, counting1, countSize) — count and counting1 may
    // overlap when the caller reuses workspace. Use std.mem.copyForwards /
    // copyBackwards depending on direction.
    const dst_bytes: [*]u8 = @ptrCast(count);
    const src_bytes: [*]const u8 = @ptrCast(counting1);
    memmoveBytes(dst_bytes, src_bytes, countSize);

    return @as(usize, max);
}

// memmove semantics for byte buffers. Translate-c avoided this because
// std.zig.c_builtins doesn't expose __builtin_memmove today.
inline fn memmoveBytes(dst: [*]u8, src: [*]const u8, len: usize) void {
    if (len == 0) return;
    const dst_addr = @intFromPtr(dst);
    const src_addr = @intFromPtr(src);
    if (dst_addr == src_addr) return;
    if (dst_addr < src_addr or dst_addr >= src_addr + len) {
        std.mem.copyForwards(u8, dst[0..len], src[0..len]);
    } else {
        std.mem.copyBackwards(u8, dst[0..len], src[0..len]);
    }
}

// -------------------------------------------------------------------------
//  HIST_countFast_wksp — fast variant (no alphabet check).
// -------------------------------------------------------------------------
pub export fn HIST_countFast_wksp(
    count: [*]c_uint,
    maxSymbolValuePtr: *c_uint,
    source: ?*const anyopaque,
    sourceSize: usize,
    workSpace: ?*anyopaque,
    workSpaceSize: usize,
) usize {
    if (sourceSize < 1500) {
        return @as(usize, HIST_count_simple(count, maxSymbolValuePtr, source, sourceSize));
    }
    if ((@intFromPtr(workSpace) & 3) != 0) return zstdError(.generic_err);
    if (workSpaceSize < HIST_WKSP_SIZE) return zstdError(.workSpace_tooSmall);
    const ws: [*]u32 = @ptrCast(@alignCast(workSpace.?));
    return HIST_count_parallel_wksp(count, maxSymbolValuePtr, source, sourceSize, .trustInput, ws);
}

// -------------------------------------------------------------------------
//  HIST_count_wksp — safe variant (validates alphabet).
// -------------------------------------------------------------------------
pub export fn HIST_count_wksp(
    count: [*]c_uint,
    maxSymbolValuePtr: *c_uint,
    source: ?*const anyopaque,
    sourceSize: usize,
    workSpace: ?*anyopaque,
    workSpaceSize: usize,
) usize {
    if ((@intFromPtr(workSpace) & 3) != 0) return zstdError(.generic_err);
    if (workSpaceSize < HIST_WKSP_SIZE) return zstdError(.workSpace_tooSmall);
    if (maxSymbolValuePtr.* < 255) {
        const ws: [*]u32 = @ptrCast(@alignCast(workSpace.?));
        return HIST_count_parallel_wksp(count, maxSymbolValuePtr, source, sourceSize, .checkMaxSymbolValue, ws);
    }
    maxSymbolValuePtr.* = 255;
    return HIST_countFast_wksp(count, maxSymbolValuePtr, source, sourceSize, workSpace, workSpaceSize);
}

// -------------------------------------------------------------------------
//  HIST_count / HIST_countFast — stack-workspace wrappers.
// -------------------------------------------------------------------------
pub export fn HIST_count(
    count: [*]c_uint,
    maxSymbolValuePtr: *c_uint,
    src: ?*const anyopaque,
    srcSize: usize,
) usize {
    var tmp: [HIST_WKSP_SIZE_U32]c_uint = undefined;
    return HIST_count_wksp(count, maxSymbolValuePtr, src, srcSize, @ptrCast(&tmp[0]), @sizeOf(@TypeOf(tmp)));
}

pub export fn HIST_countFast(
    count: [*]c_uint,
    maxSymbolValuePtr: *c_uint,
    source: ?*const anyopaque,
    sourceSize: usize,
) usize {
    var tmp: [HIST_WKSP_SIZE_U32]c_uint = undefined;
    return HIST_countFast_wksp(count, maxSymbolValuePtr, source, sourceSize, @ptrCast(&tmp[0]), @sizeOf(@TypeOf(tmp)));
}

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------
test "HIST_count_simple empty input" {
    var count: [256]c_uint = undefined;
    var msv: c_uint = 255;
    const largest = HIST_count_simple(&count, &msv, null, 0);
    try std.testing.expectEqual(@as(c_uint, 0), largest);
    try std.testing.expectEqual(@as(c_uint, 0), msv);
}

test "HIST_count on short buffer matches manual" {
    var buf: [32]u8 = undefined;
    for (&buf, 0..) |*b, i| b.* = @intCast(i % 8);
    var count: [256]c_uint = [_]c_uint{0} ** 256;
    var msv: c_uint = 255;
    const largest = HIST_count(&count, &msv, &buf[0], buf.len);
    try std.testing.expect(largest >= 1);
    try std.testing.expectEqual(@as(c_uint, 7), msv);
    var sum: c_uint = 0;
    for (0..8) |i| sum += count[i];
    try std.testing.expectEqual(@as(c_uint, 32), sum);
}

test "HIST_count on large buffer exercises parallel path" {
    // > 1500 bytes forces the parallel path.
    var buf: [4096]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const rand = prng.random();
    for (&buf) |*b| b.* = rand.int(u8);

    var count: [256]c_uint = [_]c_uint{0} ** 256;
    var msv: c_uint = 255;
    var ws: [HIST_WKSP_SIZE_U32]c_uint = undefined;
    const rc = HIST_count_wksp(&count, &msv, &buf[0], buf.len, @ptrCast(&ws[0]), @sizeOf(@TypeOf(ws)));
    try std.testing.expect(HIST_isError(rc) == 0);

    // Independent reference: plain scan.
    var ref: [256]c_uint = [_]c_uint{0} ** 256;
    for (buf) |b| ref[b] += 1;
    for (0..256) |i| try std.testing.expectEqual(ref[i], count[i]);
}
