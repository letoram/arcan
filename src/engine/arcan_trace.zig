// Pure Zig port of engine/arcan_trace.c — zero C helpers.
// Trace buffer: binary-packed trace marks with timestamps for profiling.

const std = @import("std");

// Engine time function (defined in platform/posix/time.c)
extern fn arcan_timemicros() callconv(.c) c_ulonglong;

// Module-level state (replaces C static vars)
var buffer: ?[*]u8 = null;
var buffer_sz: usize = 0;
var buffer_pos: usize = 0;
var buffer_flag: ?*bool = null;

export var arcan_trace_enabled: bool = false;

export fn arcan_trace_setbuffer(buf: ?[*]u8, buf_sz: usize, finish_flag: ?*bool) void {
    if (buffer != null) {
        buffer_flag.?.* = true;
        buffer = null;
        buffer_flag = null;
        buffer_pos = 0;
    }

    if (buf == null or buf_sz == 0) return;

    buffer = buf;
    buffer_flag = finish_flag;
    buffer_sz = buf_sz;
    arcan_trace_enabled = true;
}

export fn arcan_trace_threadname(_: ?[*:0]const u8) void {}

export fn arcan_trace_log(message: ?[*]const u8, len: usize) void {
    if (!arcan_trace_enabled) return;
    const msg = message orelse return;
    const buf = buffer orelse return;

    for (0..len) |i| {
        if (buffer_pos + i >= buffer_sz) return;
        buf[buffer_pos + i] = msg[i];
    }
}

export fn arcan_trace_init(_: ?*anyopaque) void {}

export fn arcan_trace_mark(
    sys: [*:0]const u8,
    subsys: [*:0]const u8,
    trigger: u8,
    tracelevel: u8,
    ident: u64,
    quant: u32,
    message: ?[*:0]const u8,
    _: ?[*:0]const u8, // file_name (unused)
    _: ?[*:0]const u8, // func_name (unused)
    _: u32, // line (unused)
) void {
    if (!arcan_trace_enabled) return;
    const buf = buffer orelse return;

    const start_ofs = buffer_pos;

    const sys_len = std.mem.len(sys) + 1;
    const subsys_len = std.mem.len(subsys) + 1;
    const msg_len: usize = if (message) |m| std.mem.len(m) + 1 else 1;
    const tot: usize = 1 + // ok marker
        8 + // timestamp
        1 + // trigger
        1 + // trace level
        8 + // identifier
        4 + // quantifier
        sys_len + subsys_len + msg_len;

    // tight packing format: valid-mark (0xff) then arguments in order,
    // when buffer is full, write eos mark (0xaa), set finish_flag and stop
    if (buffer_sz - buffer_pos < tot) {
        // fail_short
        buffer_flag.?.* = true;
        buf[start_ofs] = 0xaa;
        return;
    }

    // ok marker (placeholder, written as 0xff at end on success)
    buffer_pos += 1;

    // timestamp
    const ts: u64 = @intCast(arcan_timemicros());
    const ts_bytes = std.mem.asBytes(&ts);
    @memcpy(buf[buffer_pos .. buffer_pos + 8], ts_bytes);
    buffer_pos += 8;

    // sys / subsys (including null terminator)
    @memcpy(buf[buffer_pos .. buffer_pos + sys_len], sys[0..sys_len]);
    buffer_pos += sys_len;
    @memcpy(buf[buffer_pos .. buffer_pos + subsys_len], subsys[0..subsys_len]);
    buffer_pos += subsys_len;

    // trigger
    buf[buffer_pos] = trigger;
    buffer_pos += 1;

    // tracelevel
    buf[buffer_pos] = tracelevel;
    buffer_pos += 1;

    // identifier
    const ident_bytes = std.mem.asBytes(&ident);
    @memcpy(buf[buffer_pos .. buffer_pos + 8], ident_bytes);
    buffer_pos += 8;

    // quantifier
    const quant_bytes = std.mem.asBytes(&quant);
    @memcpy(buf[buffer_pos .. buffer_pos + 4], quant_bytes);
    buffer_pos += 4;

    // message
    if (message) |msg| {
        @memcpy(buf[buffer_pos .. buffer_pos + msg_len], msg[0..msg_len]);
        buffer_pos += msg_len;
    } else {
        buf[buffer_pos] = 0;
        buffer_pos += 1;
    }

    // mark sample as completed
    buf[start_ofs] = 0xff;
}

export fn arcan_trace_close() void {
    if (!arcan_trace_enabled) return;
    // Releases trace buffer if it exists
    arcan_trace_setbuffer(buffer, 0, null);
}
