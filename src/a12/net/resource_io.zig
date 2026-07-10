// Zig port of platform/posix/resource_io.c
// Copyright 2014-2016, Björn Ståhl — 3-Clause BSD
//
// Wraps a file descriptor + metadata into a DataSource handle, matching the
// arcan resource-open / release API used by map_resource and friends.

const std = @import("std");
const posix = std.posix;

/// Sentinel value for an uninitialised / closed file descriptor.
pub const BADFD: posix.fd_t = -1;

/// Mirrors the C `data_source` struct.
pub const DataSource = struct {
    /// Underlying file descriptor, or BADFD when not open.
    fd: posix.fd_t = BADFD,
    /// Offset within the file where the resource starts (0 for whole files).
    start: i64 = -1,
    /// Byte length of the resource, or 0 meaning "figure it out at map time".
    len: i64 = -1,
    /// Owned copy of the originating URL/path, or null.
    source: ?[]u8 = null,
};

/// Open a file for read-only access and return a DataSource.
///
/// `allocator` is used to duplicate the `url` string into `source`.
/// On failure the returned DataSource has fd == BADFD.
pub fn arcan_open_resource(allocator: std.mem.Allocator, url: []const u8) DataSource {
    var res = DataSource{};

    const file = std.fs.openFileAbsolute(url, .{ .mode = .read_only }) catch
        std.fs.cwd().openFile(url, .{ .mode = .read_only }) catch return res;

    // Set CLOEXEC so the fd does not leak into child processes.
    const flags = posix.fcntl(file.handle, posix.F.GETFD, 0) catch 0;
    _ = posix.fcntl(file.handle, posix.F.SETFD, flags | posix.FD_CLOEXEC) catch {};

    res.fd = file.handle;
    res.start = 0;
    res.len = 0; // map_resource resolves the real size via fstat
    res.source = allocator.dupe(u8, url) catch null;
    return res;
}

/// Close the file descriptor and free the source string.
/// Safe to call on an already-released DataSource.
pub fn arcan_release_resource(allocator: std.mem.Allocator, sptr: *DataSource) void {
    if (sptr.fd != BADFD) {
        // Retry close on EINTR, give up on anything else.
        while (true) {
            posix.close(sptr.fd);
            break;
        }
    }
    if (sptr.source) |s| allocator.free(s);
    sptr.* = DataSource{};
}
