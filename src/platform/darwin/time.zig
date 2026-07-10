// Zig port of platform/darwin/time.c — mach-based monotonic clock.
// macOS's CLOCK_MONOTONIC is available, but the reference implementation
// uses mach_absolute_time + mach_timebase_info; keep that so behaviour
// matches the historical C shim exactly.
// Copyright: Björn Ståhl (original C), 3-Clause BSD (see COPYING).

const std = @import("std");

extern "c" fn mach_absolute_time() u64;
const mach_timebase_info_data_t = extern struct { numer: u32, denom: u32 };
extern "c" fn mach_timebase_info(info: *mach_timebase_info_data_t) c_int;

const platform_timing = extern struct {
    tickless: bool,
    cost_us: c_uint,
};

var scale: f64 = 0;

fn timebaseScale() f64 {
    if (scale == 0) {
        var info: mach_timebase_info_data_t = .{ .numer = 0, .denom = 0 };
        if (mach_timebase_info(&info) == 0 and info.denom != 0) {
            scale = @as(f64, @floatFromInt(info.numer)) / @as(f64, @floatFromInt(info.denom));
        } else {
            scale = 1.0;
        }
    }
    return scale;
}

export fn arcan_timemillis() c_ulonglong {
    const t: f64 = @floatFromInt(mach_absolute_time());
    return @intFromFloat(t * timebaseScale() / 1_000_000.0);
}

export fn arcan_timemicros() c_ulonglong {
    const t: f64 = @floatFromInt(mach_absolute_time());
    return @intFromFloat(t * timebaseScale() / 1000.0);
}

export fn platform_monotonic_ns() u64 {
    const t: f64 = @floatFromInt(mach_absolute_time());
    // mach_absolute_time is already in nanoseconds after scaling
    return @intFromFloat(t * timebaseScale());
}

export fn arcan_timesleep(val_in: c_ulong) void {
    var val = val_in;
    var req: std.c.timespec = .{
        .sec = @intCast(val / 1000),
        .nsec = 0,
    };
    val -= @as(c_ulong, @intCast(req.sec)) * 1000;
    req.nsec = @intCast(val * 1_000_000);

    var rem: std.c.timespec = .{ .sec = 0, .nsec = 0 };
    while (std.c.nanosleep(&req, &rem) == -1) {
        const e = std.c._errno().*;
        std.debug.assert(e != @intFromEnum(std.c.E.INVAL));
        if (e == @intFromEnum(std.c.E.FAULT))
            break;
        // EINTR: resume for the remainder unless it's below a 4ms threshold.
        if (e == @intFromEnum(std.c.E.INTR)) {
            req = rem;
            const rem_ms = rem.sec * 1000 + @divTrunc(1 + req.nsec, 1_000_000);
            if (rem_ms < 4)
                break;
        }
    }
}

export fn platform_hardware_clockcfg() platform_timing {
    return .{ .cost_us = 0, .tickless = true };
}
