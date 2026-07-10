// Pure Zig port of posix/fsrv_guard.c — SIGBUS guard for frameserver shmpage access.
// Provides platform_fsrv_enter / platform_fsrv_leave / platform_fsrv_clock.
//
// When accessing shared memory owned by a frameserver client, SIGBUS can occur
// if the client truncates the backing fd. This module installs a SIGBUS handler
// that longjmps back to the caller's recovery point set via platform_fsrv_enter.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

// libc externs

// signal(2) — install a signal handler, returns previous handler or SIG_ERR
extern "c" fn signal(
    sig: c_int,
    handler: ?*const fn (c_int) callconv(.c) void,
) ?*const fn (c_int) callconv(.c) void;

// abort(3)
extern "c" fn abort() noreturn;

// __sigsetjmp is the actual glibc symbol that sigsetjmp(env, savemask) maps to.
// Returns 0 on direct call, nonzero on siglongjmp return.
extern "c" fn __sigsetjmp(env: *anyopaque, savemask: c_int) c_int;

// siglongjmp(3) — restore environment saved by sigsetjmp, does not return
extern "c" fn siglongjmp(env: *anyopaque, val: c_int) noreturn;

// longjmp(3) — restore environment saved by setjmp, does not return
extern "c" fn longjmp(env: *anyopaque, val: c_int) noreturn;

// engine externs

extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn platform_fsrv_dropshared(ctx: *anyopaque) void;

// constants

const SIGBUS: c_int = 7; // aarch64-linux

// SIG_ERR is ((void(*)(int))-1) on glibc — the maximum pointer value
// Use @ptrFromInt with comptime-known value to avoid alignment check
const SIG_ERR_RAW: usize = std.math.maxInt(usize);
fn isSigErr(h: ?*const fn (c_int) callconv(.c) void) bool {
    return @intFromPtr(h) == SIG_ERR_RAW;
}

// jmp_buf sizing
// On aarch64 glibc: struct __jmp_buf_tag { __jmp_buf[22] (176 bytes), int (4), pad (4),
// __sigset_t (128 bytes) } = 312 bytes. jmp_buf and sigjmp_buf are both this type.
const JMPBUF_SIZE: usize = 312;

// module state

var tag: ?*anyopaque = null;
var recover: [JMPBUF_SIZE]u8 align(16) = undefined;
var counter: usize = 0;

// SIGBUS handler

fn bus_handler(_: c_int) callconv(.c) void {
    if (is_freestanding) return;
    if (tag == null) {
        abort();
    }

    siglongjmp(&recover, 1);
}

// exported API

export fn platform_fsrv_enter(m: *anyopaque, out: *anyopaque) void {
    if (is_freestanding) return;

    const S = struct {
        var initialized: bool = false;
    };

    counter += 1;

    if (!S.initialized) {
        S.initialized = true;
        if (isSigErr(signal(SIGBUS, &bus_handler))) {
            arcan_warning("(posix/fsrv_guard) can't install sigbus handler.\n");
        }
    }

    if (__sigsetjmp(&recover, 0) != 0) {
        arcan_warning("(posix/fsrv_guard) DoS attempt from client.\n");
        platform_fsrv_dropshared(tag.?);
        tag = null;
        longjmp(out, -1);
    }

    tag = m;
}

export fn platform_fsrv_clock() usize {
    return counter;
}

export fn platform_fsrv_leave() void {
    tag = null;
}
