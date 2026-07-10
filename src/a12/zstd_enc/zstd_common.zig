// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/common/zstd_common.c (and the companion bits
// from error_private.c / allocations.h required for linkage).
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license found in LICENSE and the
//   GPLv2 found in COPYING in the root of the zstd source tree.
//
// Scope: this slice provides pure-Zig replacements for the custom allocation
// primitives (ZSTD_customMalloc/Calloc/Free), the version query helpers, and
// the external error-code plumbing (ZSTD_isError/getErrorCode/getErrorName/
// getErrorString, backed by ERR_* internals). All entry points keep the
// C-ABI linker names via `pub export fn` so other C code still compiling
// against libzstd can transparently link against this file.

const std = @import("std");

// -------------------------------------------------------------------------
//  libc glue (same ABI the upstream ZSTD_DEPS_NEED_MALLOC path uses)
// -------------------------------------------------------------------------
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memset(s: ?*anyopaque, c: c_int, n: usize) ?*anyopaque;

// -------------------------------------------------------------------------
//  Public typedefs (mirrors lib/zstd.h)
// -------------------------------------------------------------------------
pub const ZSTD_allocFunction = ?*const fn (opaque_ctx: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque;
pub const ZSTD_freeFunction = ?*const fn (opaque_ctx: ?*anyopaque, address: ?*anyopaque) callconv(.c) void;

pub const ZSTD_customMem = extern struct {
    customAlloc: ZSTD_allocFunction = null,
    customFree: ZSTD_freeFunction = null,
    opaque_ctx: ?*anyopaque = null,
};

pub const ZSTD_defaultCMem: ZSTD_customMem = .{};

// ZSTD_ErrorCode — keep numeric values identical to lib/zstd_errors.h so the
// shared size_t-encoded error protocol round-trips.
pub const ZSTD_ErrorCode = enum(c_int) {
    no_error = 0,
    generic_err = 1,
    prefix_unknown = 10,
    version_unsupported = 12,
    frameParameter_unsupported = 14,
    frameParameter_windowTooLarge = 16,
    corruption_detected = 20,
    checksum_wrong = 22,
    literals_headerWrong = 24,
    dictionary_corrupted = 30,
    dictionary_wrong = 32,
    dictionaryCreation_failed = 34,
    parameter_unsupported = 40,
    parameter_combination_unsupported = 41,
    parameter_outOfBound = 42,
    tableLog_tooLarge = 44,
    maxSymbolValue_tooLarge = 46,
    maxSymbolValue_tooSmall = 48,
    cannotProduce_uncompressedBlock = 49,
    stabilityCondition_notRespected = 50,
    stage_wrong = 60,
    init_missing = 62,
    memory_allocation = 64,
    workSpace_tooSmall = 66,
    dstSize_tooSmall = 70,
    srcSize_wrong = 72,
    dstBuffer_null = 74,
    noForwardProgress_destFull = 80,
    noForwardProgress_inputEmpty = 82,
    frameIndex_tooLarge = 100,
    seekableIO = 102,
    dstBuffer_wrong = 104,
    srcBuffer_wrong = 105,
    sequenceProducer_failed = 106,
    externalSequences_invalid = 107,
    maxCode = 120,
    _,
};

// ERROR(name) in zstd internals is ((size_t)-PREFIX(name)). Keep this helper
// available for other slices to share.
pub inline fn zstdError(code: ZSTD_ErrorCode) usize {
    return @bitCast(-@as(isize, @intCast(@intFromEnum(code))));
}

// -------------------------------------------------------------------------
//  Custom allocator primitives (port of lib/common/allocations.h)
// -------------------------------------------------------------------------
pub export fn ZSTD_customMalloc(size: usize, customMem: ZSTD_customMem) ?*anyopaque {
    if (customMem.customAlloc) |alloc_fn| {
        return alloc_fn(customMem.opaque_ctx, size);
    }
    return malloc(size);
}

pub export fn ZSTD_customCalloc(size: usize, customMem: ZSTD_customMem) ?*anyopaque {
    if (customMem.customAlloc) |alloc_fn| {
        // Upstream documents: calloc is implemented as malloc+memset when a
        // custom allocator is supplied, since we have no callback for calloc.
        const ptr = alloc_fn(customMem.opaque_ctx, size);
        if (ptr) |p| _ = memset(p, 0, size);
        return ptr;
    }
    return calloc(1, size);
}

pub export fn ZSTD_customFree(ptr: ?*anyopaque, customMem: ZSTD_customMem) void {
    if (ptr) |p| {
        if (customMem.customFree) |free_fn| {
            free_fn(customMem.opaque_ctx, p);
        } else {
            free(p);
        }
    }
}

// -------------------------------------------------------------------------
//  Version
// -------------------------------------------------------------------------
pub const ZSTD_VERSION_MAJOR: c_uint = 1;
pub const ZSTD_VERSION_MINOR: c_uint = 5;
pub const ZSTD_VERSION_RELEASE: c_uint = 7;
pub const ZSTD_VERSION_NUMBER: c_uint =
    ZSTD_VERSION_MAJOR * 100 * 100 + ZSTD_VERSION_MINOR * 100 + ZSTD_VERSION_RELEASE;
pub const ZSTD_VERSION_STRING: [:0]const u8 = "1.5.7";

pub export fn ZSTD_versionNumber() c_uint {
    return ZSTD_VERSION_NUMBER;
}

pub export fn ZSTD_versionString() [*:0]const u8 {
    return ZSTD_VERSION_STRING.ptr;
}

// -------------------------------------------------------------------------
//  Error Management (port of error_private.c + zstd_common.c error stubs)
// -------------------------------------------------------------------------

/// Tell if a size_t return value is a zstd error code.
pub export fn ERR_isError(code: usize) c_uint {
    // ERROR(maxCode) == (size_t)-120.
    // A value is an error if code > (size_t)-maxCode (underflow interval).
    return @intFromBool(code > zstdError(.maxCode));
}

pub export fn ERR_getErrorCode(code: usize) ZSTD_ErrorCode {
    if (ERR_isError(code) == 0) return .no_error;
    // Recover the enum from the negated size_t encoding.
    const neg: isize = @bitCast(code);
    return @enumFromInt(@as(c_int, @intCast(-neg)));
}

pub export fn ERR_getErrorString(code: ZSTD_ErrorCode) [*:0]const u8 {
    const msg: [:0]const u8 = switch (code) {
        .no_error => "No error detected",
        .generic_err => "Error (generic)",
        .prefix_unknown => "Unknown frame descriptor",
        .version_unsupported => "Version not supported",
        .frameParameter_unsupported => "Unsupported frame parameter",
        .frameParameter_windowTooLarge => "Frame requires too much memory for decoding",
        .corruption_detected => "Data corruption detected",
        .checksum_wrong => "Restored data doesn't match checksum",
        .literals_headerWrong => "Header of Literals' block doesn't respect format specification",
        .parameter_unsupported => "Unsupported parameter",
        .parameter_combination_unsupported => "Unsupported combination of parameters",
        .parameter_outOfBound => "Parameter is out of bound",
        .init_missing => "Context should be init first",
        .memory_allocation => "Allocation error : not enough memory",
        .workSpace_tooSmall => "workSpace buffer is not large enough",
        .stage_wrong => "Operation not authorized at current processing stage",
        .tableLog_tooLarge => "tableLog requires too much memory : unsupported",
        .maxSymbolValue_tooLarge => "Unsupported max Symbol Value : too large",
        .maxSymbolValue_tooSmall => "Specified maxSymbolValue is too small",
        .cannotProduce_uncompressedBlock => "This mode cannot generate an uncompressed block",
        .stabilityCondition_notRespected => "pledged buffer stability condition is not respected",
        .dictionary_corrupted => "Dictionary is corrupted",
        .dictionary_wrong => "Dictionary mismatch",
        .dictionaryCreation_failed => "Cannot create Dictionary from provided samples",
        .dstSize_tooSmall => "Destination buffer is too small",
        .srcSize_wrong => "Src size is incorrect",
        .dstBuffer_null => "Operation on NULL destination buffer",
        .noForwardProgress_destFull => "Operation made no progress over multiple calls, due to output buffer being full",
        .noForwardProgress_inputEmpty => "Operation made no progress over multiple calls, due to input being empty",
        .frameIndex_tooLarge => "Frame index is too large",
        .seekableIO => "An I/O error occurred when reading/seeking",
        .dstBuffer_wrong => "Destination buffer is wrong",
        .srcBuffer_wrong => "Source buffer is wrong",
        .sequenceProducer_failed => "Block-level external sequence producer returned an error code",
        .externalSequences_invalid => "External sequences are not valid",
        .maxCode, _ => "Unspecified error code",
    };
    return msg.ptr;
}

pub export fn ERR_getErrorName(code: usize) [*:0]const u8 {
    return ERR_getErrorString(ERR_getErrorCode(code));
}

// Public ZSTD_* facade (identical to zstd_common.c).
pub export fn ZSTD_isError(code: usize) c_uint {
    return ERR_isError(code);
}

pub export fn ZSTD_getErrorCode(code: usize) ZSTD_ErrorCode {
    return ERR_getErrorCode(code);
}

pub export fn ZSTD_getErrorName(code: usize) [*:0]const u8 {
    return ERR_getErrorName(code);
}

pub export fn ZSTD_getErrorString(code: ZSTD_ErrorCode) [*:0]const u8 {
    return ERR_getErrorString(code);
}

// -------------------------------------------------------------------------
//  Sanity checks
// -------------------------------------------------------------------------
test "ZSTD_isError round-trip" {
    const e = zstdError(.memory_allocation);
    try std.testing.expect(ZSTD_isError(e) == 1);
    try std.testing.expect(ZSTD_isError(0) == 0);
    try std.testing.expect(ZSTD_getErrorCode(e) == .memory_allocation);
}

test "version constants" {
    try std.testing.expectEqual(@as(c_uint, 10507), ZSTD_versionNumber());
    const vs = ZSTD_versionString();
    try std.testing.expectEqualStrings("1.5.7", std.mem.span(vs));
}

test "customMalloc falls back to libc when no callback" {
    const cm = ZSTD_defaultCMem;
    const p = ZSTD_customMalloc(64, cm) orelse return error.AllocFailed;
    ZSTD_customFree(p, cm);
}
