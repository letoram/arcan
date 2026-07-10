// Zig port of posix/dbpath.c
// Returns the default path to arcan's sqlite database (~/.arcan/arcan.sqlite).

const std = @import("std");
const c = @import("posix");

export fn platform_dbstore_path() [*c]u8 {
    const homedir: [*c]const u8 = c.getenv("HOME") orelse return null;
    const len = c.strlen(homedir);
    if (len == 0) return null;
    const home = homedir[0..len];

    // Build ~/.arcan directory path and ensure it exists
    var dirbuf: [4096]u8 = undefined;
    const dir = std.fmt.bufPrintZ(&dirbuf, "{s}/.arcan", .{home}) catch return null;
    _ = c.mkdir(dir.ptr, 0o700);

    // Build full database path
    var fbuf: [4096]u8 = undefined;
    const path = std.fmt.bufPrintZ(&fbuf, "{s}/.arcan/arcan.sqlite", .{home}) catch return null;

    return c.strdup(path.ptr);
}
