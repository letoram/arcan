// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/common/xxhash.c (which is just a thin shim
// instantiating the header-only xxhash.h implementation).
//
// Upstream:
//   xxHash - Extremely Fast Hash algorithm
//   Copyright (c) Yann Collet - Meta Platforms, Inc
//   Dual-licensed under BSD-style license (LICENSE) and GPLv2 (COPYING).
//
// Strategy: zstd compiles xxhash with -DXXH_NAMESPACE=ZSTD_, which renames
// every public symbol to `ZSTD_XXH*`. We delegate to `std.hash.XxHash64`
// rather than porting the ~3000-LOC header verbatim — the algorithm is
// specified bit-exact and std.hash.XxHash64 has been exercised against the
// reference test vectors for years. See `test "xxhash one-shot matches
// reference vector"` at the bottom for a sanity check.
//
// This slice only wires the subset the encoder actually touches:
//   - ZSTD_XXH_versionNumber (info)
//   - ZSTD_XXH64 (one-shot digest)
//   - ZSTD_XXH64_createState / freeState / reset / update / digest / copyState
//
// XXH32 and XXH3 variants can be added in a later slice if needed; they are
// not exercised by the single-threaded encoder at level 2–3.

const std = @import("std");

extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;

// -------------------------------------------------------------------------
//  Public types — layout must match xxhash.h so C callers can embed states.
// -------------------------------------------------------------------------
pub const XXH64_hash_t = u64;

pub const XXH_errorcode = enum(c_int) {
    OK = 0,
    ERROR = 1,
};

// xxhash.h declares XXH64_state_s as a C struct. Our implementation keeps a
// `std.hash.XxHash64` plus a trailing byte budget to preserve the public
// sizeof — C callers using static storage (stack XXH64_state_t) must get a
// struct at least as large as the upstream. We generously reserve 88 bytes
// to match upstream sizeof(XXH64_state_s) = 88 on 64-bit.
pub const XXH64_state_t = extern struct {
    // Inline accumulator. The first field of std.hash.XxHash64 is used for
    // the running state; we store the zig struct as raw bytes so the extern
    // struct remains C-ABI-safe and layout-stable.
    raw: [@sizeOf(std.hash.XxHash64) + 8]u8 align(8) = @splat(0),
    seed: u64 = 0,
    initialized: u8 = 0,
    _pad: [7]u8 = @splat(0),

    inline fn engine(self: *XXH64_state_t) *std.hash.XxHash64 {
        return @ptrCast(@alignCast(&self.raw[0]));
    }
};

// -------------------------------------------------------------------------
//  Version
// -------------------------------------------------------------------------
pub const XXH_VERSION_NUMBER: c_uint = 0 * 100 * 100 + 8 * 100 + 3; // 0.8.3

pub export fn ZSTD_XXH_versionNumber() c_uint {
    return XXH_VERSION_NUMBER;
}

// -------------------------------------------------------------------------
//  XXH64 — one-shot
// -------------------------------------------------------------------------
pub export fn ZSTD_XXH64(input: ?*const anyopaque, len: usize, seed: XXH64_hash_t) XXH64_hash_t {
    if (len == 0) return std.hash.XxHash64.hash(seed, &[_]u8{});
    const p: [*]const u8 = @ptrCast(input.?);
    return std.hash.XxHash64.hash(seed, p[0..len]);
}

// -------------------------------------------------------------------------
//  XXH64 — streaming
// -------------------------------------------------------------------------
pub export fn ZSTD_XXH64_createState() ?*XXH64_state_t {
    const p = malloc(@sizeOf(XXH64_state_t)) orelse return null;
    const st: *XXH64_state_t = @ptrCast(@alignCast(p));
    st.* = .{};
    return st;
}

pub export fn ZSTD_XXH64_freeState(statePtr: ?*XXH64_state_t) XXH_errorcode {
    if (statePtr) |s| free(@ptrCast(s));
    return .OK;
}

pub export fn ZSTD_XXH64_copyState(dst: ?*XXH64_state_t, src: ?*const XXH64_state_t) void {
    if (dst == null or src == null) return;
    dst.?.* = src.?.*;
}

pub export fn ZSTD_XXH64_reset(statePtr: ?*XXH64_state_t, seed: XXH64_hash_t) XXH_errorcode {
    const s = statePtr orelse return .ERROR;
    s.* = .{};
    s.seed = seed;
    s.engine().* = std.hash.XxHash64.init(seed);
    s.initialized = 1;
    return .OK;
}

pub export fn ZSTD_XXH64_update(statePtr: ?*XXH64_state_t, input: ?*const anyopaque, length: usize) XXH_errorcode {
    const s = statePtr orelse return .ERROR;
    if (s.initialized == 0) {
        s.engine().* = std.hash.XxHash64.init(s.seed);
        s.initialized = 1;
    }
    if (length == 0) return .OK;
    const p: [*]const u8 = @ptrCast(input.?);
    s.engine().update(p[0..length]);
    return .OK;
}

pub export fn ZSTD_XXH64_digest(statePtr: ?*const XXH64_state_t) XXH64_hash_t {
    // The upstream contract allows digest() without mutating visible state.
    // std.hash.XxHash64.final() mutates; clone first.
    const s = statePtr orelse return 0;
    var tmp: std.hash.XxHash64 = undefined;
    // Hoist through a mutable alias — const-cast is the idiom here because
    // digest() is semantically read-only but our engine() helper is *mut.
    const mut: *XXH64_state_t = @constCast(s);
    if (mut.initialized == 0) {
        tmp = std.hash.XxHash64.init(mut.seed);
    } else {
        tmp = mut.engine().*;
    }
    return tmp.final();
}

// -------------------------------------------------------------------------
//  Tests
// -------------------------------------------------------------------------
test "xxhash one-shot matches reference vector" {
    // Reference: XXH64("hello", seed=0) == 0x26C7827D889F6DA3
    const msg = "hello";
    const h = ZSTD_XXH64(msg.ptr, msg.len, 0);
    try std.testing.expectEqual(@as(u64, 0x26C7827D889F6DA3), h);
}

test "xxhash streaming equals one-shot" {
    const msg = "the quick brown fox jumps over the lazy dog";
    const one_shot = ZSTD_XXH64(msg.ptr, msg.len, 0);
    const s = ZSTD_XXH64_createState() orelse return error.AllocFailed;
    defer _ = ZSTD_XXH64_freeState(s);
    try std.testing.expect(ZSTD_XXH64_reset(s, 0) == .OK);
    try std.testing.expect(ZSTD_XXH64_update(s, msg.ptr, 10) == .OK);
    try std.testing.expect(ZSTD_XXH64_update(s, msg.ptr + 10, msg.len - 10) == .OK);
    try std.testing.expectEqual(one_shot, ZSTD_XXH64_digest(s));
}
