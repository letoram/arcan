// shmif_monitor.zig — env-gated event observability for the fsrv bridge.
//
// When the env var ARCAN_SHMIF_MONITOR is set to a path, this module
// opens it for append and the emit() hot-path writes one line per
// event crossing arcan's fsrv queue in either direction:
//
//     t=<timestamp_ms> dir=<out|in> vid=<N> cat=<C> kind=<K>
//
// out  = arcan → shmif client (platform_fsrv_pushevent)
// in   = shmif client → arcan (arcan_event_queuetransfer ingress)
//
// When the env var is unset, every call is a single cached-pointer load
// + null check, so leaving the probes in place on a release build costs
// nothing.
//
// This is the letoram-style "watch what shmif is saying" debug idiom,
// preserved here as a drop-in module rather than scattered `warning()`
// calls across Lua or engine code.

const std = @import("std");
const builtin = @import("builtin");

extern fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fprintf(stream: ?*anyopaque, fmt: [*:0]const u8, ...) c_int;
extern fn fflush(stream: ?*anyopaque) c_int;
extern fn clock_gettime(clk_id: c_int, tp: *std.posix.timespec) c_int;

const CLOCK_MONOTONIC: c_int = if (builtin.os.tag.isDarwin()) 6 else 1;

var inited: bool = false;
var file: ?*anyopaque = null;

/// Lazy init on first emit. Idempotent and thread-unsafe on purpose —
/// the first call is expected to happen during single-threaded engine
/// startup.
fn ensure() void {
    if (inited) return;
    inited = true;
    if (builtin.os.tag == .freestanding) return;
    const p = getenv("ARCAN_SHMIF_MONITOR") orelse return;
    file = fopen(p, "a");
    if (file) |f| {
        _ = fprintf(f, "# arcan shmif monitor opened\n");
        _ = fflush(f);
    }
}

fn nowMs() i64 {
    if (builtin.os.tag == .freestanding) return 0;
    var ts: std.posix.timespec = undefined;
    _ = clock_gettime(CLOCK_MONOTONIC, &ts);
    return @as(i64, @intCast(ts.sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.nsec)), 1_000_000);
}

/// Record one event crossing the fsrv boundary.
///   dir: "out" for arcan→client, "in" for client→arcan
///   vid: fsrv vid (or -1 if unknown at this callsite)
///   cat: event category (EVENT_EXTERNAL, EVENT_TARGET, …)
///   kind: sub-kind within the category (tgt.kind or ext.kind)
pub fn emit(dir: [*:0]const u8, vid: i64, cat: c_int, kind: c_int) void {
    ensure();
    const f = file orelse return;
    _ = fprintf(f, "t=%lld dir=%s vid=%lld cat=%d kind=%d\n",
        nowMs(), dir, vid, cat, kind);
    _ = fflush(f);
}

/// Record a free-form string tag from the Lua side. Used by the
/// `shmifmon("tag")` Lua binding to correlate Lua-side handler fires
/// with engine-level event activity in the same log stream.
pub fn emitLuaTag(tag: [*:0]const u8) void {
    ensure();
    const f = file orelse return;
    _ = fprintf(f, "t=%lld dir=lua tag=%s\n", nowMs(), tag);
    _ = fflush(f);
}
