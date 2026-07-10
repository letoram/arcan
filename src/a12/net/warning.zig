// Zig port of platform/posix/warning.c
// Public domain, no copyright claimed.
//
// Provides arcan_warning / arcan_fatal equivalents.
// In this Zig port we use std.log and process.exit rather than raw stderr
// writes, which integrates cleanly with the rest of the Zig build.

const std = @import("std");

/// Optional hook called just before arcan_fatal terminates the process.
/// Set this before entering any hot path that needs cleanup on fatal error.
pub var fatal_hook: ?*const fn () void = null;

/// Log a non-fatal diagnostic message (maps to std.log.warn).
/// Accepts a comptime format string and runtime args, matching the C varargs API.
pub fn arcan_warning(comptime fmt: []const u8, args: anytype) void {
    std.log.warn(fmt, args);
}

/// Log a fatal error, call the optional fatal_hook, then terminate.
/// In debug builds this calls std.debug.panic (which prints a stack trace);
/// in release builds it calls std.process.exit(1).
pub fn arcan_fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);

    if (fatal_hook) |hook| hook();

    if (@import("builtin").mode == .Debug) {
        // Construct a message buffer on the stack for the panic string.
        var buf: [2048]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "arcan_fatal (message too long)";
        std.debug.panic("{s}", .{msg});
    } else {
        std.process.exit(1);
    }
}

/// Set / unset the log destination (no-op in the Zig port — std.log handles
/// routing — kept for API compatibility with C callers that call
/// arcan_log_destination()).
pub fn arcan_log_destination(level: c_int) void {
    _ = level;
}
