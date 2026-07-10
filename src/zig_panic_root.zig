//! Root module installed for all binaries built via createExe in build.zig.
//! Override Zig's default panic handler with the `simple_panic` namespace —
//! it writes the panic message to stderr and traps, with no DWARF parsing.
//!
//! The default handler (`std.debug.defaultPanic`) tries to walk DWARF on
//! panic, and our binary's compressed `.zdebug_*` sections trip an internal
//! assert in `std.compress.flate.Decompress.tossBitsEnding`. Result: the
//! panic-handler crashes recursively before flushing the original message,
//! leaving us with a silent SIGABRT and no diagnostic. Switching to
//! simple_panic guarantees `panic: <message>\n` reaches stderr regardless
//! of debug-info shape. We use coredumps + offline addr2line for stacks
//! when we need them.

const std = @import("std");

pub const panic = std.debug.simple_panic;

// Default std.log filter is `.warn`, which drops `.info` and `.debug`. Bump to
// `.info` so vk_wsi's acquireDrmDisplay diagnostics (connector scan, per-fd
// vkGetDrmDisplayEXT VkResult, mode enumeration) actually reach stderr. `.err`
// and `.warn` calls already show; this only adds more detail.
pub const std_options: std.Options = .{ .log_level = .info };

// start.zig's comptime block requires `root.main` to exist when building an
// exe. Our real C-ABI `main` is provided by arcan_main.zig / frameserver.zig
// / tui_main.zig etc. via `export fn main` in their own object files. Give
// start.zig a non-exported stub with C calling convention: the comptime check
// `root.main` calling-convention == .c makes start.zig skip exporting its own
// wrapper, so libc's startup finds the real C `main` at link time.
pub fn main() callconv(.c) c_int {
    return 0;
}
