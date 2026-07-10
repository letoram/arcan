// Zig port of platform/posix/dbpath.c
// Copyright 2014-2016, Björn Ståhl — 3-Clause BSD
//
// Returns the path to the arcan SQLite database, creating ~/.arcan/ if needed.

const std = @import("std");

/// Return an allocated slice containing the path to the arcan SQLite database.
/// The caller owns the returned slice and must free it with `allocator.free()`.
///
/// Returns null when the HOME environment variable is unset or empty.
/// Errors from directory creation are ignored (mkdir EEXIST is expected).
pub fn platform_dbstore_path(allocator: std.mem.Allocator) error{OutOfMemory}!?[]u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    if (home.len == 0) return null;

    // Build ~/.arcan and create it (ignore errors — EEXIST is fine).
    const dir_path = try std.fmt.allocPrint(allocator, "{s}/.arcan", .{home});
    defer allocator.free(dir_path);

    std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {}, // best-effort; proceed even if mkdir fails
    };

    // Build ~/.arcan/arcan.sqlite
    return std.fmt.allocPrint(allocator, "{s}/.arcan/arcan.sqlite", .{home});
}
