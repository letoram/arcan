// Pure Zig port of posix/sync_helpers.c — zero C helpers.
// Futex-based wakeup signaling for frameserver sync fields (esync, vsync, async).
// Uses byte-offset accessors from shmif_offsets for opaque arcan_frameserver + arcan_shmif_page.

const std = @import("std");
const off = @import("shmif_offsets");

const builtin = @import("builtin");
const native_os = builtin.os.tag;

/// Issue a futex WAKE on the u32 at `ptr`, waking all waiters.
/// The futex is in shared memory (not process-private), so private = false.
fn futex_wake(ptr: *const anyopaque) void {
    if (native_os == .linux) {
        const linux = std.os.linux;
        _ = linux.futex_3arg(
            ptr,
            .{ .cmd = .WAKE, .private = false },
            std.math.maxInt(i32),
        );
    } else {
        // Fallback: just zero the value (no futex support on this platform).
        const p: *u32 = @constCast(@ptrCast(@alignCast(ptr)));
        p.* = 0;
    }
}

export fn platform_fsrv_signal_event(tgt: *anyopaque) callconv(.c) void {
    const page = off.Fsrv.getShmPtr(tgt) orelse return;
    futex_wake(off.Page.getEsyncPtr(page));
}

export fn platform_fsrv_signal_video(tgt: *anyopaque) callconv(.c) void {
    const page = off.Fsrv.getShmPtr(tgt) orelse return;
    futex_wake(@ptrCast(@volatileCast(off.Page.getVsyncPtr(page))));
}

export fn platform_fsrv_signal_audio(tgt: *anyopaque) callconv(.c) void {
    const page = off.Fsrv.getShmPtr(tgt) orelse return;
    futex_wake(@ptrCast(@volatileCast(off.Page.getAsyncPtr(page))));
}
