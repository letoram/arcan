// SPDX-License-Identifier: BSD-3-Clause OR GPL-2.0-only
//
// Zig port of zstd 1.5.7 lib/compress/zstd_cwksp.h — slice 5b.
//
// Source: refined from /tmp/raw_zstd_compress.zig lines 28926..29431
// (the translate-c output of zstd_compress.c, which includes cwksp.h inline).
// Noise removed: the `while (true) { if (!false) break; }` DEBUGLOG shells
// translate-c emits for upstream's assert-wrapped blocks, the
// `_ = @as(c_int, 0);` remnants of `(void)0` statements, and the
// `var x = arg_x; _ = &x;` binding boilerplate that has no Zig purpose.
// Behaviour is bit-identical to upstream apart from the dropped asserts.
//
// Upstream:
//   Copyright (c) Meta Platforms, Inc. and affiliates.
//   Dual-licensed under the BSD-style license (LICENSE) and GPLv2 (COPYING).

const std = @import("std");
const common = @import("zstd_common.zig");

pub const ZSTD_customMem = common.ZSTD_customMem;

// Error encoding mirrors the scheme in zstd_compress.zig: (size_t)-errno.
const ZSTD_error_memory_allocation: c_int = 64;
inline fn zerr(code: c_int) usize {
    return @bitCast(-@as(isize, code));
}

// -------------------------------------------------------------------------
//  Enums / struct
// -------------------------------------------------------------------------

pub const ZSTD_cwksp_alloc_phase_e = c_uint;
pub const ZSTD_cwksp_alloc_objects: c_uint = 0;
pub const ZSTD_cwksp_alloc_aligned_init_once: c_uint = 1;
pub const ZSTD_cwksp_alloc_aligned: c_uint = 2;
pub const ZSTD_cwksp_alloc_buffers: c_uint = 3;

pub const ZSTD_cwksp_static_alloc_e = c_uint;
pub const ZSTD_cwksp_dynamic_alloc: c_uint = 0;
pub const ZSTD_cwksp_static_alloc: c_uint = 1;

pub const ZSTD_CWKSP_ALIGNMENT_BYTES: usize = 64;

/// ZSTD_cwksp: a tight bump allocator for the compressor's working buffers.
///
/// The 8 pointer fields carve the workspace up into four regions that grow
/// towards each other:
///
///   [workspace .. objectEnd)       — objects (CCtx / CDict / blockState)
///   [objectEnd .. tableEnd)        — tables (chain / hash / hash3)
///   [tableEnd  .. allocStart)      — unused headroom
///   [allocStart .. workspaceEnd)   — buffers (seq store / huf table / ...)
///
/// `tableValidEnd` tracks the high-water mark of *initialized* table bytes so
/// clear_tables can zero only the dirty slice; `initOnceStart` is the analog
/// for `reserve_aligned_init_once` (table-row-hash tag tables, mostly).
pub const ZSTD_cwksp = extern struct {
    workspace: ?*anyopaque = null,
    workspaceEnd: ?*anyopaque = null,
    objectEnd: ?*anyopaque = null,
    tableEnd: ?*anyopaque = null,
    tableValidEnd: ?*anyopaque = null,
    allocStart: ?*anyopaque = null,
    initOnceStart: ?*anyopaque = null,
    allocFailed: u8 = 0,
    workspaceOversizedDuration: c_int = 0,
    phase: ZSTD_cwksp_alloc_phase_e = 0,
    isStatic: ZSTD_cwksp_static_alloc_e = 0,
};

// -------------------------------------------------------------------------
//  Size helpers
// -------------------------------------------------------------------------

pub fn ZSTD_cwksp_align(size: usize, alignment: usize) callconv(.c) usize {
    const mask: usize = alignment -% 1;
    return (size +% mask) & ~mask;
}

pub fn ZSTD_cwksp_alloc_size(size: usize) callconv(.c) usize {
    if (size == 0) return 0;
    return size;
}

pub fn ZSTD_cwksp_aligned_alloc_size(size: usize, alignment: usize) callconv(.c) usize {
    return ZSTD_cwksp_alloc_size(ZSTD_cwksp_align(size, alignment));
}

pub fn ZSTD_cwksp_aligned64_alloc_size(size: usize) callconv(.c) usize {
    return ZSTD_cwksp_aligned_alloc_size(size, ZSTD_CWKSP_ALIGNMENT_BYTES);
}

pub fn ZSTD_cwksp_slack_space_required() callconv(.c) usize {
    // Upstream: 64*2 bytes of slack for two alignments.
    return ZSTD_CWKSP_ALIGNMENT_BYTES * 2;
}

inline fn bytePtr(p: ?*anyopaque) [*]u8 {
    return @ptrCast(@alignCast(p));
}

inline fn constBytePtr(p: ?*const anyopaque) [*]const u8 {
    return @ptrCast(@alignCast(p));
}

inline fn offsetBy(p: ?*anyopaque, n: usize) ?*anyopaque {
    return @ptrCast(bytePtr(p) + n);
}

inline fn offsetBack(p: ?*anyopaque, n: usize) ?*anyopaque {
    return @ptrCast(bytePtr(p) - n);
}

inline fn byteDiff(hi: ?*const anyopaque, lo: ?*const anyopaque) usize {
    const a = @intFromPtr(hi);
    const b = @intFromPtr(lo);
    // Upstream asserts hi >= lo; mirror the unchecked subtraction.
    return a -% b;
}

pub fn ZSTD_cwksp_bytes_to_align_ptr(ptr: ?*anyopaque, alignBytes: usize) callconv(.c) usize {
    const mask: usize = alignBytes -% 1;
    return (alignBytes -% (@intFromPtr(ptr) & mask)) & mask;
}

// -------------------------------------------------------------------------
//  Core layout helpers
// -------------------------------------------------------------------------

pub fn ZSTD_cwksp_available_space(ws: *ZSTD_cwksp) callconv(.c) usize {
    return byteDiff(ws.allocStart, ws.tableEnd);
}

pub fn ZSTD_cwksp_initialAllocStart(ws: *ZSTD_cwksp) callconv(.c) ?*anyopaque {
    const end = @intFromPtr(ws.workspaceEnd);
    const aligned = end - (end % ZSTD_CWKSP_ALIGNMENT_BYTES);
    return @ptrFromInt(aligned);
}

pub fn ZSTD_cwksp_sizeof(ws: *const ZSTD_cwksp) callconv(.c) usize {
    return byteDiff(ws.workspaceEnd, ws.workspace);
}

pub fn ZSTD_cwksp_used(ws: *const ZSTD_cwksp) callconv(.c) usize {
    return byteDiff(ws.tableEnd, ws.workspace) +%
        byteDiff(ws.workspaceEnd, ws.allocStart);
}

pub fn ZSTD_cwksp_owns_buffer(ws: *const ZSTD_cwksp, ptr: ?*const anyopaque) callconv(.c) c_int {
    if (ptr == null) return 0;
    const p = @intFromPtr(ptr);
    const lo = @intFromPtr(ws.workspace);
    const hi = @intFromPtr(ws.workspaceEnd);
    return @intFromBool((lo <= p) and (p < hi));
}

// -------------------------------------------------------------------------
//  Phase management
// -------------------------------------------------------------------------

fn ZSTD_cwksp_internal_advance_phase(
    ws: *ZSTD_cwksp,
    phase: ZSTD_cwksp_alloc_phase_e,
) callconv(.c) usize {
    if (phase > ws.phase) {
        // Transitioning into a phase that uses aligned allocations? Then we
        // must first round the table/object boundary up to CWKSP_ALIGNMENT.
        if (ws.phase < ZSTD_cwksp_alloc_aligned_init_once and
            phase >= ZSTD_cwksp_alloc_aligned_init_once)
        {
            ws.tableValidEnd = ws.objectEnd;
            ws.initOnceStart = ZSTD_cwksp_initialAllocStart(ws);

            const alloc = ws.objectEnd;
            const bytesToAlign = ZSTD_cwksp_bytes_to_align_ptr(
                alloc,
                ZSTD_CWKSP_ALIGNMENT_BYTES,
            );
            const objectEnd = offsetBy(alloc, bytesToAlign);
            if (@intFromPtr(objectEnd) > @intFromPtr(ws.workspaceEnd)) {
                return zerr(ZSTD_error_memory_allocation);
            }
            ws.objectEnd = objectEnd;
            ws.tableEnd = objectEnd;
            if (@intFromPtr(ws.tableValidEnd) < @intFromPtr(ws.tableEnd)) {
                ws.tableValidEnd = ws.tableEnd;
            }
        }
        ws.phase = phase;
    }
    return 0;
}

fn ZSTD_cwksp_reserve_internal_buffer_space(ws: *ZSTD_cwksp, bytes: usize) callconv(.c) ?*anyopaque {
    const alloc = offsetBack(ws.allocStart, bytes);
    const bottom = ws.tableEnd;
    if (@intFromPtr(alloc) < @intFromPtr(bottom)) {
        ws.allocFailed = 1;
        return null;
    }
    if (@intFromPtr(alloc) < @intFromPtr(ws.tableValidEnd)) {
        ws.tableValidEnd = alloc;
    }
    ws.allocStart = alloc;
    return alloc;
}

fn ZSTD_cwksp_reserve_internal(
    ws: *ZSTD_cwksp,
    bytes: usize,
    phase: ZSTD_cwksp_alloc_phase_e,
) callconv(.c) ?*anyopaque {
    const err = ZSTD_cwksp_internal_advance_phase(ws, phase);
    if (common.ERR_isError(err) != 0 or bytes == 0) return null;
    return ZSTD_cwksp_reserve_internal_buffer_space(ws, bytes);
}

// -------------------------------------------------------------------------
//  Public reservations
// -------------------------------------------------------------------------

pub fn ZSTD_cwksp_reserve_buffer(ws: *ZSTD_cwksp, bytes: usize) callconv(.c) ?*anyopaque {
    return ZSTD_cwksp_reserve_internal(ws, bytes, ZSTD_cwksp_alloc_buffers);
}

pub fn ZSTD_cwksp_reserve_aligned_init_once(
    ws: *ZSTD_cwksp,
    bytes: usize,
) callconv(.c) ?*anyopaque {
    const alignedBytes = ZSTD_cwksp_align(bytes, ZSTD_CWKSP_ALIGNMENT_BYTES);
    const ptr = ZSTD_cwksp_reserve_internal(ws, alignedBytes, ZSTD_cwksp_alloc_aligned_init_once);
    if (ptr != null and @intFromPtr(ptr) < @intFromPtr(ws.initOnceStart)) {
        // Only the *new* slice below initOnceStart needs zeroing — the rest
        // was initialised on a previous call and can stay hot.
        const span_to_zero = byteDiff(ws.initOnceStart, ptr);
        const n = if (span_to_zero < alignedBytes) span_to_zero else alignedBytes;
        @memset(bytePtr(ptr)[0..n], 0);
        ws.initOnceStart = ptr;
    }
    return ptr;
}

pub fn ZSTD_cwksp_reserve_aligned64(ws: *ZSTD_cwksp, bytes: usize) callconv(.c) ?*anyopaque {
    return ZSTD_cwksp_reserve_internal(
        ws,
        ZSTD_cwksp_align(bytes, ZSTD_CWKSP_ALIGNMENT_BYTES),
        ZSTD_cwksp_alloc_aligned,
    );
}

pub fn ZSTD_cwksp_reserve_table(ws: *ZSTD_cwksp, bytes: usize) callconv(.c) ?*anyopaque {
    const phase: ZSTD_cwksp_alloc_phase_e = ZSTD_cwksp_alloc_aligned_init_once;
    if (ws.phase < phase) {
        if (common.ERR_isError(ZSTD_cwksp_internal_advance_phase(ws, phase)) != 0) {
            return null;
        }
    }
    const alloc = ws.tableEnd;
    const end = offsetBy(alloc, bytes);
    const top = ws.allocStart;
    if (@intFromPtr(end) > @intFromPtr(top)) {
        ws.allocFailed = 1;
        return null;
    }
    ws.tableEnd = end;
    return alloc;
}

pub fn ZSTD_cwksp_reserve_object(ws: *ZSTD_cwksp, bytes: usize) callconv(.c) ?*anyopaque {
    const roundedBytes = ZSTD_cwksp_align(bytes, @sizeOf(*anyopaque));
    const alloc = ws.objectEnd;
    const end = offsetBy(alloc, roundedBytes);
    if (ws.phase != ZSTD_cwksp_alloc_objects or
        @intFromPtr(end) > @intFromPtr(ws.workspaceEnd))
    {
        ws.allocFailed = 1;
        return null;
    }
    ws.objectEnd = end;
    ws.tableEnd = end;
    ws.tableValidEnd = end;
    return alloc;
}

// -------------------------------------------------------------------------
//  Table-management helpers
// -------------------------------------------------------------------------

pub fn ZSTD_cwksp_mark_tables_dirty(ws: *ZSTD_cwksp) callconv(.c) void {
    ws.tableValidEnd = ws.objectEnd;
}

pub fn ZSTD_cwksp_mark_tables_clean(ws: *ZSTD_cwksp) callconv(.c) void {
    if (@intFromPtr(ws.tableValidEnd) < @intFromPtr(ws.tableEnd)) {
        ws.tableValidEnd = ws.tableEnd;
    }
}

pub fn ZSTD_cwksp_clean_tables(ws: *ZSTD_cwksp) callconv(.c) void {
    if (@intFromPtr(ws.tableValidEnd) < @intFromPtr(ws.tableEnd)) {
        const len = byteDiff(ws.tableEnd, ws.tableValidEnd);
        @memset(bytePtr(ws.tableValidEnd)[0..len], 0);
    }
    ZSTD_cwksp_mark_tables_clean(ws);
}

pub fn ZSTD_cwksp_clear_tables(ws: *ZSTD_cwksp) callconv(.c) void {
    ws.tableEnd = ws.objectEnd;
}

pub fn ZSTD_cwksp_clear(ws: *ZSTD_cwksp) callconv(.c) void {
    ws.tableEnd = ws.objectEnd;
    ws.allocStart = ZSTD_cwksp_initialAllocStart(ws);
    ws.allocFailed = 0;
    // Roll the phase back to aligned_init_once — any buffer-phase state is
    // gone, and init_once callers must re-zero below initOnceStart, which
    // `reserve_aligned_init_once` handles on each call anyway. Keeping the
    // phase at aligned_init_once preserves the init_once fast-path.
    if (ws.phase > ZSTD_cwksp_alloc_aligned_init_once) {
        ws.phase = ZSTD_cwksp_alloc_aligned_init_once;
    }
}

// -------------------------------------------------------------------------
//  Lifecycle
// -------------------------------------------------------------------------

pub fn ZSTD_cwksp_init(
    ws: *ZSTD_cwksp,
    start: ?*anyopaque,
    size: usize,
    isStatic: ZSTD_cwksp_static_alloc_e,
) callconv(.c) void {
    ws.workspace = start;
    ws.workspaceEnd = offsetBy(start, size);
    ws.objectEnd = ws.workspace;
    ws.tableValidEnd = ws.objectEnd;
    ws.initOnceStart = ZSTD_cwksp_initialAllocStart(ws);
    ws.phase = ZSTD_cwksp_alloc_objects;
    ws.isStatic = isStatic;
    ZSTD_cwksp_clear(ws);
    ws.workspaceOversizedDuration = 0;
}

pub fn ZSTD_cwksp_create(
    ws: *ZSTD_cwksp,
    size: usize,
    customMem: ZSTD_customMem,
) callconv(.c) usize {
    const workspace = common.ZSTD_customMalloc(size, customMem);
    if (workspace == null) return zerr(ZSTD_error_memory_allocation);
    ZSTD_cwksp_init(ws, workspace, size, ZSTD_cwksp_dynamic_alloc);
    return 0;
}

pub fn ZSTD_cwksp_free(ws: *ZSTD_cwksp, customMem: ZSTD_customMem) callconv(.c) void {
    const ptr = ws.workspace;
    @memset(std.mem.asBytes(ws), 0);
    common.ZSTD_customFree(ptr, customMem);
}

pub fn ZSTD_cwksp_move(dst: *ZSTD_cwksp, src: *ZSTD_cwksp) callconv(.c) void {
    dst.* = src.*;
    @memset(std.mem.asBytes(src), 0);
}

// -------------------------------------------------------------------------
//  Diagnostics / budgeting
// -------------------------------------------------------------------------

pub fn ZSTD_cwksp_reserve_failed(ws: *const ZSTD_cwksp) callconv(.c) c_int {
    return @intCast(ws.allocFailed);
}

pub fn ZSTD_cwksp_estimated_space_within_bounds(
    ws: *const ZSTD_cwksp,
    estimatedSpace: usize,
) callconv(.c) c_int {
    const used = ZSTD_cwksp_used(ws);
    const slack = ZSTD_cwksp_slack_space_required();
    return @intFromBool((estimatedSpace -% slack) <= used and used <= estimatedSpace);
}

pub fn ZSTD_cwksp_check_available(
    ws: *ZSTD_cwksp,
    additionalNeededSpace: usize,
) callconv(.c) c_int {
    return @intFromBool(ZSTD_cwksp_available_space(ws) >= additionalNeededSpace);
}

pub fn ZSTD_cwksp_check_too_large(
    ws: *ZSTD_cwksp,
    additionalNeededSpace: usize,
) callconv(.c) c_int {
    return ZSTD_cwksp_check_available(ws, additionalNeededSpace *% 3);
}

pub fn ZSTD_cwksp_check_wasteful(
    ws: *ZSTD_cwksp,
    additionalNeededSpace: usize,
) callconv(.c) c_int {
    return @intFromBool(
        ZSTD_cwksp_check_too_large(ws, additionalNeededSpace) != 0 and
            ws.workspaceOversizedDuration > 128,
    );
}

pub fn ZSTD_cwksp_bump_oversized_duration(
    ws: *ZSTD_cwksp,
    additionalNeededSpace: usize,
) callconv(.c) void {
    if (ZSTD_cwksp_check_too_large(ws, additionalNeededSpace) != 0) {
        ws.workspaceOversizedDuration += 1;
    } else {
        ws.workspaceOversizedDuration = 0;
    }
}

// -------------------------------------------------------------------------
//  Tests (semantic smoke only — real callers come online in slice 5c)
// -------------------------------------------------------------------------

test "cwksp init + reserve + clear roundtrip" {
    var buf: [4096]u8 align(64) = undefined;
    var ws: ZSTD_cwksp = .{};
    ZSTD_cwksp_init(&ws, &buf, buf.len, ZSTD_cwksp_static_alloc);

    try std.testing.expectEqual(@as(usize, buf.len), ZSTD_cwksp_sizeof(&ws));
    // An object allocation carves from the low end.
    const obj = ZSTD_cwksp_reserve_object(&ws, 64) orelse return error.ReserveFailed;
    try std.testing.expect(ZSTD_cwksp_owns_buffer(&ws, obj) != 0);

    // A table allocation advances to aligned_init_once phase.
    const tbl = ZSTD_cwksp_reserve_table(&ws, 128) orelse return error.ReserveFailed;
    _ = tbl;
    try std.testing.expect(ws.phase >= ZSTD_cwksp_alloc_aligned_init_once);

    // A buffer allocation grows from the high end.
    const bufp = ZSTD_cwksp_reserve_buffer(&ws, 256) orelse return error.ReserveFailed;
    try std.testing.expect(ZSTD_cwksp_owns_buffer(&ws, bufp) != 0);

    // clear() rewinds the buffer/table regions, leaves objects pinned.
    ZSTD_cwksp_clear(&ws);
    try std.testing.expectEqual(@as(u8, 0), ws.allocFailed);
    try std.testing.expectEqual(ws.objectEnd, ws.tableEnd);
}

test "cwksp oversized duration accounting" {
    // check_too_large(ws, n) returns true when available >= n*3, i.e. the
    // workspace is ≥3× the requested allocation — a sign the buffer is
    // oversized for the actual need. `bump_oversized_duration` increments a
    // counter each time this holds; callers watch the counter to free.
    var buf: [1024]u8 align(64) = undefined;
    var ws: ZSTD_cwksp = .{};
    ZSTD_cwksp_init(&ws, &buf, buf.len, ZSTD_cwksp_static_alloc);
    // Need 64B — 1024 >= 64*3, so this trips the oversized check.
    ZSTD_cwksp_bump_oversized_duration(&ws, 64);
    try std.testing.expectEqual(@as(c_int, 1), ws.workspaceOversizedDuration);
    // Need 500B — 1024 < 500*3, not oversized, duration resets.
    ZSTD_cwksp_bump_oversized_duration(&ws, 500);
    try std.testing.expectEqual(@as(c_int, 0), ws.workspaceOversizedDuration);
}
