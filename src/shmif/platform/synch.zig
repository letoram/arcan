// Zig reimplementation of platform/synch.c
// Drop-in C-ABI-compatible replacement for synchronization primitives.
//
// Exports: shmif_platform_sync_mark, shmif_platform_sync_wait,
//          shmif_platform_sync_post, shmif_platform_sync_trywait
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

extern fn arcan_timesleep(ms: c_ulong) void;

const SYNC_EVENT = c.SYNC_EVENT;
const SYNC_VIDEO = c.SYNC_VIDEO;
const SYNC_AUDIO = c.SYNC_AUDIO;

// Linux futex operation constants (matching kernel ABI)
const FUTEX_WAIT: usize = 0;
const FUTEX_WAKE: usize = 1;

// shmif_platform_sync_mark

export fn shmif_platform_sync_mark(P: *anyopaque, slot: c_int) void {
    if (is_freestanding) return;
    if ((slot & SYNC_EVENT) != 0) {
        off.Page.setEsync(P, 1);
    }

    if ((slot & SYNC_VIDEO) != 0) {
        off.Page.setVsync(P, 1);
    }

    if ((slot & SYNC_AUDIO) != 0) {
        off.Page.setAsync(P, 1);
    }
}

// Platform-specific sync implementations

// Linux uses futex syscalls
fn linux_sync_wait(P: *anyopaque, slot: c_int) c_int {
    const linux = std.os.linux;

    if (((slot & SYNC_EVENT) != 0) and (off.Page.getEsync(P) != 0)) {
        while (true) {
            const rc = linux.syscall6(
                linux.SYS.futex,
                @intFromPtr(off.Page.getEsyncPtr(P)),
                FUTEX_WAIT,
                1,
                0,
                0,
                0,
            );
            const e = linux.E.init(rc);
            if (e != .INTR) break;
        }
    }

    if ((slot & SYNC_VIDEO) != 0) {
        while (off.Page.getVsync(P) == 1) {
            const rc = linux.syscall6(
                linux.SYS.futex,
                @intFromPtr(off.Page.getVsyncPtr(P)),
                FUTEX_WAIT,
                1,
                0,
                0,
                0,
            );
            const e = linux.E.init(rc);
            if (e != .INTR) break;
        }
    }

    if ((slot & SYNC_AUDIO) != 0) {
        while (off.Page.getAsync(P) == 1) {
            const rc = linux.syscall6(
                linux.SYS.futex,
                @intFromPtr(off.Page.getAsyncPtr(P)),
                FUTEX_WAIT,
                1,
                0,
                0,
                0,
            );
            const e = linux.E.init(rc);
            if (e != .INTR) break;
        }
    }

    return 1;
}

fn linux_sync_post(P: *anyopaque, slot: c_int) c_int {
    const linux = std.os.linux;

    if ((slot & SYNC_EVENT) != 0) {
        _ = linux.syscall6(
            linux.SYS.futex,
            @intFromPtr(off.Page.getEsyncPtr(P)),
            FUTEX_WAKE,
            1,
            0,
            0,
            0,
        );
    }

    if ((slot & SYNC_VIDEO) != 0) {
        off.Page.setVsync(P, 0);
        _ = linux.syscall6(
            linux.SYS.futex,
            @intFromPtr(off.Page.getVsyncPtr(P)),
            FUTEX_WAKE,
            1,
            0,
            0,
            0,
        );
    }

    if ((slot & SYNC_AUDIO) != 0) {
        off.Page.setAsync(P, 0);
        _ = linux.syscall6(
            linux.SYS.futex,
            @intFromPtr(off.Page.getAsyncPtr(P)),
            FUTEX_WAKE,
            1,
            0,
            0,
            0,
        );
    }

    return 1;
}

fn linux_sync_trywait(P: *anyopaque, slot: c_int) c_int {
    const linux = std.os.linux;
    var rv: c_int = 1;

    // 1ms timeout for futex
    const req = linux.timespec{ .sec = 0, .nsec = 1000000 };

    if (((slot & SYNC_EVENT) != 0) and (off.Page.getEsync(P) != 0)) {
        _ = linux.syscall6(
            linux.SYS.futex,
            @intFromPtr(off.Page.getEsyncPtr(P)),
            FUTEX_WAIT,
            0xffffffff,
            @intFromPtr(&req),
            0,
            0,
        );
        if (off.Page.getEsync(P) != 0)
            rv = 0;
    }

    if (((slot & SYNC_VIDEO) != 0) and (off.Page.getVsync(P) != 0)) {
        _ = linux.syscall6(
            linux.SYS.futex,
            @intFromPtr(off.Page.getVsyncPtr(P)),
            FUTEX_WAIT,
            0xffffffff,
            @intFromPtr(&req),
            0,
            0,
        );
        if (off.Page.getVsync(P) != 0)
            rv = 0;
    }

    if (((slot & SYNC_AUDIO) != 0) and (off.Page.getAsync(P) != 0)) {
        _ = linux.syscall6(
            linux.SYS.futex,
            @intFromPtr(off.Page.getAsyncPtr(P)),
            FUTEX_WAIT,
            0xffffffff,
            @intFromPtr(&req),
            0,
            0,
        );
        if (off.Page.getAsync(P) != 0)
            rv = 0;
    }

    return rv;
}

// Fallback: poll with timesleep
fn fallback_sync_wait(P: *anyopaque, slot: c_int) c_int {
    if ((slot & SYNC_EVENT) != 0) {
        while (off.Page.getEsync(P) != 0)
            arcan_timesleep(1);
    }
    if ((slot & SYNC_VIDEO) != 0) {
        while (off.Page.getVsync(P) != 0)
            arcan_timesleep(1);
    }
    if ((slot & SYNC_AUDIO) != 0) {
        while (off.Page.getAsync(P) != 0)
            arcan_timesleep(1);
    }
    return 1;
}

fn fallback_sync_trywait(P: *anyopaque, slot: c_int) c_int {
    var rv: c_int = 1;
    if ((slot & SYNC_EVENT) != 0)
        rv = if (off.Page.getEsync(P) == 0) @as(c_int, 1) else @as(c_int, 0);
    if ((slot & SYNC_VIDEO) != 0)
        rv = if (off.Page.getVsync(P) == 0) @as(c_int, 1) else @as(c_int, 0);
    if ((slot & SYNC_AUDIO) != 0)
        rv = if (off.Page.getAsync(P) == 0) @as(c_int, 1) else @as(c_int, 0);
    return rv;
}

fn fallback_sync_post(P: *anyopaque, slot: c_int) c_int {
    if ((slot & SYNC_EVENT) != 0) {
        // no-op for fallback event sync
    }
    if ((slot & SYNC_VIDEO) != 0) {
        off.Page.setVsync(P, 0);
    }
    if ((slot & SYNC_AUDIO) != 0) {
        off.Page.setAsync(P, 0);
    }
    return 1;
}

// Exported functions

export fn shmif_platform_sync_wait(P: *anyopaque, slot: c_int) c_int {
    if (is_freestanding) return 0;
    if (comptime builtin.os.tag == .linux) {
        return linux_sync_wait(P, slot);
    } else {
        return fallback_sync_wait(P, slot);
    }
}

export fn shmif_platform_sync_post(P: *anyopaque, slot: c_int) c_int {
    if (is_freestanding) return 0;
    if (comptime builtin.os.tag == .linux) {
        return linux_sync_post(P, slot);
    } else {
        return fallback_sync_post(P, slot);
    }
}

export fn shmif_platform_sync_trywait(P: *anyopaque, slot: c_int) c_int {
    if (is_freestanding) return 0;
    if (comptime builtin.os.tag == .linux) {
        return linux_sync_trywait(P, slot);
    } else {
        return fallback_sync_trywait(P, slot);
    }
}
