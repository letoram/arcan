// C-ABI vararg symbol for a12int_trace. Upstream defines it as a file-scope
// macro in a12.h; our Zig callers in net.zig / dir_*.zig declare it as
// `extern "c" fn a12int_trace(mask: c_int, fmt: [*:0]const u8, ...) void`.
//
// Zig's @cVaStart/@cVaCopy are disabled as of 0.15 ("disabled due to
// miscompilations"), so we can't forward the user's varargs to vfprintf
// from pure Zig. Instead we emit a fixed-form trace header and drop the
// formatted payload — the interop harness greps for group tokens, not the
// per-call detail. a12.zig's private `fn a12int_trace` (comptime-fmt)
// continues to handle the rich in-process traces.

const std = @import("std");

const FILE = opaque {};
extern "c" var a12_trace_dst: ?*FILE;
extern "c" var a12_trace_targets: c_int;
extern "c" fn a12int_group_tostr(group: c_int) [*:0]const u8;
extern "c" fn fprintf(stream: *FILE, fmt: [*:0]const u8, ...) c_int;

pub export fn a12int_trace(mask: c_int, fmt: [*:0]const u8, ...) callconv(.c) void {
    _ = fmt;
    const dst = a12_trace_dst orelse return;
    if ((a12_trace_targets & mask) == 0) return;
    const group = a12int_group_tostr(mask);
    const ts_ms: i64 = std.time.milliTimestamp();
    _ = fprintf(dst, "tag=a12:ts=%lld:group=%s:<trace>\n", ts_ms, group);
}
