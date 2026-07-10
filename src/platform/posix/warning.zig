// Zig port of posix/warning.c
// Logging/fatal diagnostics: arcan_warning (conditional stderr), arcan_fatal (stderr + exit).
//
// arcan_warning / arcan_fatal do printf-style variadic format expansion by
// forwarding through musl's vfprintf (statically linked). This used to live
// in warning_va.c because zig 0.15.2's LLVM backend disables @cVaStart on
// aarch64-linux. The self-hosted (SH) aarch64 backend implements
// @cVaStart/@cVaArg (src/codegen/aarch64/Select.zig), so under -Duse-llvm=false
// the format substitution is done in pure Zig and warning_va.c is dropped.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

// The LLVM backend disables @cVaStart on aarch64 ("disabled due to
// miscompilations"); the self-hosted backend implements it. So under LLVM,
// arcan_warning / arcan_fatal come from warning_va.c (added by build.zig only
// for use_llvm builds); under the SH backend they are defined here in pure
// Zig and no C is compiled.
const va_in_zig = builtin.zig_backend != .stage2_llvm;

// shmif_log_stderr — write a raw message to stderr via write(2),
// bypassing stdio. On freestanding, platform_stubs.zig provides this;
// only export on hosted targets.
comptime {
    if (!is_freestanding) {
        @export(&shmif_log_stderr_impl, .{ .name = "shmif_log_stderr" });
        if (va_in_zig) {
            @export(&arcan_warning_impl, .{ .name = "arcan_warning" });
            @export(&arcan_fatal_impl, .{ .name = "arcan_fatal" });
        }
    }
}
fn shmif_log_stderr_impl(fmt: [*c]const u8, ...) callconv(.c) void {
    if (fmt == null) return;
    const slice = std.mem.span(@as([*:0]const u8, @ptrCast(fmt)));
    _ = std.posix.write(2, slice) catch {};
}

const c = if (is_freestanding) struct {
    // In freestanding builds the consumers below are behind `is_freestanding`
    // short-circuits, so `stderr` is never dereferenced. Keep the type
    // signature matching the hosted `posix_libc.stderr` (non-optional *FILE)
    // so the shared code compiles without wrapping the value in `if (c.stderr)`.
    pub var stderr: *FakeFile = @ptrFromInt(1);
    pub const FakeFile = opaque {};
    pub fn malloc(_: usize) ?*anyopaque { return null; }
    pub fn free(_: ?*anyopaque) void {}
    pub fn exit(_: c_int) noreturn { while (true) {} }
    pub fn abort() noreturn { while (true) {} }
} else @import("posix");

extern fn fputs(s: [*:0]const u8, stream: *anyopaque) c_int;
extern fn fflush(stream: ?*anyopaque) c_int;

// Variadic format expansion via musl's vfprintf. Works in pure Zig because
// the aarch64 SH backend implements @cVaStart/@cVaArg — see file header.
const VaList = std.builtin.VaList;
extern "c" fn vfprintf(stream: *anyopaque, fmt: [*:0]const u8, ap: VaList) c_int;
extern "c" fn abort() noreturn;

/// Global fatal-hook function pointer. Engine code sets this to a
/// shutdown handler; called just before exit/abort in arcan_fatal().
/// Read from warning_va.c via extern.
export var arcan_fatal_hook: ?*const fn () callconv(.c) void = null;

/// Global log destination (FILE*) and verbosity level.
/// Changed from threadlocal to global — threadlocal caused log_dst=null in
/// separately-compiled Zig objects (vk_shared.zig, arcan_lua.zig) even though
/// they run on the main thread. Arcan is single-threaded for Lua/AGP.
///
/// Exported as `arcan_warning_log_dst` so warning_va.c can read it. The
/// public C name is distinct from `log_dst` (the zig-internal symbol)
/// because the engine has plenty of other `log_dst` locals.
export var arcan_warning_log_dst: ?*anyopaque = null;
var log_level: c_int = 0;

export fn arcan_log_destination(outf: ?*anyopaque, level: c_int) void {
    arcan_warning_log_dst = outf;
    log_level = level;
}

// arcan_warning / arcan_fatal: variadic printf-style diagnostics, expanded via
// vfprintf. Pure Zig now that the SH backend supports @cVaStart on aarch64
// (these previously lived in warning_va.c under the LLVM backend). Exported
// only on hosted targets (see the comptime block above); on freestanding they
// are never referenced, so the libc externs below are never analyzed there.
fn arcan_warning_impl(msg: [*:0]const u8, ...) callconv(.c) void {
    const dst = arcan_warning_log_dst orelse return;
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    _ = vfprintf(dst, msg, ap);
}

fn arcan_fatal_impl(msg: [*:0]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    _ = vfprintf(c.stderr, msg, ap);
    _ = fflush(c.stderr);
    if (arcan_fatal_hook) |hook| hook();
    abort();
}

comptime {
    _ = fputs; // retained for future zig-only warnings
}
