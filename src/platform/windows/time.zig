// Win32 monotonic clock shims — QueryPerformanceCounter based.
// Same C-ABI export surface as platform/{posix,darwin}/time.zig.

const std = @import("std");

const BOOL = c_int;
extern "kernel32" fn QueryPerformanceCounter(count: *i64) callconv(.winapi) BOOL;
extern "kernel32" fn QueryPerformanceFrequency(freq: *i64) callconv(.winapi) BOOL;
extern "kernel32" fn Sleep(ms: u32) callconv(.winapi) void;

const platform_timing = extern struct {
    tickless: bool,
    cost_us: c_uint,
};

var qpc_freq: i64 = 0;

fn freq() i64 {
    if (qpc_freq == 0) {
        var f: i64 = 0;
        _ = QueryPerformanceFrequency(&f);
        qpc_freq = if (f != 0) f else 1;
    }
    return qpc_freq;
}

fn nowNs() u64 {
    var ctr: i64 = 0;
    _ = QueryPerformanceCounter(&ctr);
    // ns = ctr * 1e9 / freq, done in 128-bit to avoid overflow
    const wide: u128 = @as(u128, @intCast(ctr)) * 1_000_000_000;
    return @intCast(wide / @as(u128, @intCast(freq())));
}

export fn arcan_timemillis() c_ulonglong {
    return @intCast(nowNs() / 1_000_000);
}

export fn arcan_timemicros() c_ulonglong {
    return @intCast(nowNs() / 1000);
}

export fn platform_monotonic_ns() u64 {
    return nowNs();
}

export fn arcan_timesleep(val: c_ulong) void {
    // millisecond granularity (Sleep). Sub-ms callers just yield.
    Sleep(@intCast(val));
}

export fn platform_hardware_clockcfg() platform_timing {
    return .{ .cost_us = 0, .tickless = true };
}
