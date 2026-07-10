// Zig port of platform/stub/mem.c
// Public domain, no copyright claimed.
//
// Memory allocation helpers.  In the Zig port these are thin wrappers around
// the standard allocator passed in by the caller.  The arcan_strarr type and
// the grow/free helpers are ported to idiomatic Zig (ArrayList of owned strings).

const std = @import("std");
const builtin = @import("builtin");

// ---------------------------------------------------------------------------
// arcan_strarr — a growable null-terminated array of owned C strings
// This replaces the C struct { char** data; size_t limit; size_t count; }.
// ---------------------------------------------------------------------------

pub const StringArr = struct {
    /// Owned slices (each allocated with the same allocator).
    items: std.ArrayListUnmanaged([]u8) = .{},

    /// Append a copy of `str` to the array.
    pub fn append(self: *StringArr, allocator: std.mem.Allocator, str: []const u8) !void {
        const owned = try allocator.dupe(u8, str);
        errdefer allocator.free(owned);
        try self.items.append(allocator, owned);
    }

    /// Free all entries and reset to empty.
    pub fn deinit(self: *StringArr, allocator: std.mem.Allocator) void {
        for (self.items.items) |s| allocator.free(s);
        self.items.deinit(allocator);
        self.* = .{};
    }
};

// ---------------------------------------------------------------------------
// Allocation helpers — direct allocator wrappers
// ---------------------------------------------------------------------------

/// Allocate `nb` bytes.  Returns null on OOM when `nonfatal` is true;
/// otherwise triggers a panic (matches C ARCAN_MEM_NONFATAL semantics).
pub fn arcan_alloc_mem(
    allocator: std.mem.Allocator,
    nb: usize,
    zeroed: bool,
    nonfatal: bool,
) ?[]u8 {
    const buf = if (zeroed)
        allocator.alloc(u8, nb) catch null
    else
        allocator.alloc(u8, nb) catch null;

    if (buf == null) {
        if (!nonfatal) {
            @panic("arcan_alloc_mem: out of memory");
        }
        return null;
    }

    const slice = buf.?;
    if (zeroed) @memset(slice, 0);
    return slice;
}

/// Allocate a copy of `data`.
pub fn arcan_alloc_fillmem(
    allocator: std.mem.Allocator,
    data: []const u8,
    zeroed: bool,
    nonfatal: bool,
) ?[]u8 {
    const buf = arcan_alloc_mem(allocator, data.len, zeroed, nonfatal) orelse return null;
    @memcpy(buf, data);
    return buf;
}

/// Free a slice previously returned by arcan_alloc_mem / arcan_alloc_fillmem.
pub fn arcan_mem_free(allocator: std.mem.Allocator, ptr: []u8) void {
    allocator.free(ptr);
}

/// Periodic tick — no-op in this implementation (kept for API parity).
pub fn arcan_mem_tick() void {}
