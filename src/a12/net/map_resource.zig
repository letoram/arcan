// Zig port of platform/posix/map_resource.c
// Copyright, Björn Ståhl — 3-Clause BSD
//
// Maps a DataSource into a readable memory region, using mmap for aligned
// regular files and a read-into-heap fallback for pipes, sockets, or
// unaligned offsets.

const std = @import("std");
const posix = std.posix;
const resource_io = @import("resource_io.zig");
const DataSource = resource_io.DataSource;

/// Maximum byte count we are willing to mmap in one call.
/// Resources larger than this must be handled by other means.
pub const MAX_RESMAP_SIZE: usize = 1024 * 1024 * 40; // 40 MiB

/// A mapped region returned by arcan_map_resource.
pub const MapRegion = struct {
    /// Pointer to the data, or null on failure.
    ptr: ?[]u8 = null,
    /// True when ptr was produced by mmap and must be unmapped rather than freed.
    is_mmap: bool = false,
};

/// Map `source` into memory.
///
/// `allocator` is used only for the heap-read fallback path; it is not used
/// when mmap succeeds.
///
/// `allow_write` forces the heap-read path (produces a mutable copy).
///
/// Returns a MapRegion; on failure MapRegion.ptr is null.
pub fn arcan_map_resource(
    allocator: std.mem.Allocator,
    source: *DataSource,
    allow_write: bool,
) MapRegion {
    var rv = MapRegion{};

    // Resolve file size if not yet known.
    if (source.len == 0) {
        const stat = posix.fstat(source.fd) catch return rv;
        source.len = stat.size;
        source.start = 0;

        // Pipes and sockets: cap to MAX_RESMAP_SIZE and force read path.
        const mode = stat.mode & posix.S.IFMT;
        if (mode == posix.S.IFIFO or mode == posix.S.IFSOCK) {
            source.len = @intCast(MAX_RESMAP_SIZE);
            return readIntoHeap(allocator, source, true);
        }
    }

    if (source.len == 0) return rv;

    const page_size: usize = std.mem.page_size;
    const offset: usize = @intCast(source.start);
    const length: usize = @intCast(source.len);

    // Use mmap for aligned, read-only, reasonably sized resources.
    if (!allow_write and
        (offset % page_size == 0) and
        length > 0 and
        length <= MAX_RESMAP_SIZE)
    {
        const prot = posix.PROT.READ;
        const flags = posix.MAP{ .TYPE = .PRIVATE };
        const ptr = posix.mmap(
            null,
            length,
            prot,
            flags,
            source.fd,
            @intCast(offset),
        ) catch |err| {
            std.log.warn("arcan_map_resource: mmap failed: {}", .{err});
            return rv;
        };
        rv.ptr = ptr;
        rv.is_mmap = true;
        return rv;
    }

    // Fallback: read the bytes into a heap buffer.
    return readIntoHeap(allocator, source, false);
}

/// Release a MapRegion obtained from arcan_map_resource.
/// Pass the same allocator that was used to create it.
pub fn arcan_release_map(allocator: std.mem.Allocator, region: MapRegion) void {
    const data = region.ptr orelse return;
    if (region.is_mmap) {
        posix.munmap(@alignCast(data));
    } else {
        allocator.free(data);
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn readIntoHeap(
    allocator: std.mem.Allocator,
    source: *DataSource,
    allow_trunc: bool,
) MapRegion {
    var rv = MapRegion{};
    const req_len: usize = @intCast(source.len);

    // Skip bytes before source.start when lseek fails (e.g. pipes).
    if (source.start > 0) {
        const seek_ok = posix.lseek_SET(source.fd, @intCast(source.start)) catch blk: {
            // Can't seek — drain the bytes manually.
            skipBytes(source.fd, @intCast(source.start)) catch break :blk error.Unexpected;
            break :blk {};
        };
        _ = seek_ok;
    }

    const buf = allocator.alloc(u8, req_len) catch return rv;
    errdefer allocator.free(buf);

    var total: usize = 0;
    while (total < req_len) {
        const n = posix.read(source.fd, buf[total..]) catch |err| switch (err) {
            error.WouldBlock, error.Interrupted => continue,
            else => break,
        };
        if (n == 0) break;
        total += n;
    }

    if (total == req_len) {
        source.len = @intCast(total);
        rv.ptr = buf;
        return rv;
    }

    // Short read: acceptable for pipes/sockets when allow_trunc is set.
    if (allow_trunc and total > 0) {
        const shrunk = allocator.realloc(buf, total) catch buf[0..total];
        source.len = @intCast(total);
        rv.ptr = shrunk;
        return rv;
    }

    allocator.free(buf);
    return rv;
}

/// Drain `n` bytes from `fd` by reading into a small stack buffer (for
/// un-seekable fds where we need to skip an initial offset).
fn skipBytes(fd: posix.fd_t, n: usize) !void {
    var remaining = n;
    var scratch: [8192]u8 = undefined;
    while (remaining > 0) {
        const want = @min(remaining, scratch.len);
        const got = try posix.read(fd, scratch[0..want]);
        if (got == 0) return error.UnexpectedEof;
        remaining -= got;
    }
}
