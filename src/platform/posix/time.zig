// Zig port of posix/time.c
// Monotonic clock queries (ms/us), platform timing config, and EINTR-safe nanosleep.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const platform_timing = extern struct {
    tickless: bool,
    cost_us: c_uint,
};

export fn arcan_timemillis() c_longlong {
    if (is_freestanding) return 0;
    return arcan_timemillis_posix();
}

export fn arcan_timemicros() c_longlong {
    if (is_freestanding) return 0;
    return arcan_timemicros_posix();
}

export fn platform_hardware_clockcfg() platform_timing {
    return .{
        .cost_us = 0,
        .tickless = true,
    };
}

export fn arcan_timesleep(val: c_ulong) void {
    if (is_freestanding) return;
    arcan_timesleep_posix(val);
}

// --- POSIX implementations (only compiled on non-freestanding) ---

fn arcan_timemillis_posix() c_longlong {
    var tp: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &tp);
    return @as(c_longlong, tp.sec) * 1000 + @divTrunc(tp.nsec, 1_000_000);
}

fn arcan_timemicros_posix() c_longlong {
    var tp: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &tp);
    return @as(c_longlong, tp.sec) * 1_000_000 + @divTrunc(tp.nsec, 1000);
}

fn arcan_timesleep_posix(val: c_ulong) void {
    var ms = val;
    const secs: isize = @intCast(ms / 1000);
    ms -= @as(c_ulong, @intCast(secs)) * 1000;
    var req: std.c.timespec = .{
        .sec = secs,
        .nsec = @intCast(ms * 1_000_000),
    };

    var rem: std.c.timespec = .{ .sec = 0, .nsec = 0 };

    while (std.c.nanosleep(&req, &rem) == -1) {
        const e = std.c._errno().*;
        std.debug.assert(e != @intFromEnum(std.os.linux.E.INVAL));
        if (e == @intFromEnum(std.os.linux.E.FAULT))
            break;

        // Sweeping EINTR introduces an error rate that can grow large;
        // check if the remaining time is less than a threshold (4 ms).
        if (e == @intFromEnum(std.os.linux.E.INTR)) {
            req = rem;
            const rem_ms = rem.sec * 1000 + @divTrunc(1 + req.nsec, 1_000_000);
            if (rem_ms < 4)
                break;
        }
    }
}
