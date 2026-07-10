// Darwin libc bridges — linked into every macOS arcan executable.
//
// The Zig ports across the tree reference a handful of glibc-private symbol
// names; Darwin libc spells them differently. Rather than link any Apple
// framework (the Vulkan ICD — MoltenVK / KosmicKrisp — and the ObjC runtime
// used by cocoa_window.zig are reached through libSystem / the dlopen'd
// loader), we only provide these thin C-ABI shims here. One object per exe,
// so no cross-object symbol collisions.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (!builtin.os.tag.isDarwin())
        @compileError("libc_darwin.zig is Darwin-only — exclude it elsewhere");
}

// glibc __errno_location ↔ Darwin __error (same contract: *errno)
extern "c" fn __error() *c_int;
export fn __errno_location() callconv(.c) *c_int {
    return __error();
}

// glibc __sigsetjmp(env, savemask) ↔ Darwin sigsetjmp (fsrv_guard.zig calls
// the glibc-internal name directly). Naked tail branch — a wrapper frame
// would break the setjmp contract (longjmp would return into a dead frame).
// Args stay in x0/x1. This object is compiled with the LLVM backend, which
// can assemble the branch (the self-hosted backend cannot yet).
export fn __sigsetjmp() callconv(.naked) noreturn {
    asm volatile ("b _sigsetjmp");
}

// glibc __assert_fail ↔ Darwin __assert_rtn (arg order differs).
extern "c" fn __assert_rtn(func: [*c]const u8, file: [*c]const u8, line: c_int, expr: [*c]const u8) noreturn;
export fn __assert_fail(assertion: [*c]const u8, file: [*c]const u8, line: c_uint, function: [*c]const u8) callconv(.c) noreturn {
    __assert_rtn(function, file, @intCast(line), assertion);
}

// glibc exposes stdin/stdout/stderr as those exact symbol names; Darwin libc
// spells the globals __stdinp/__stdoutp/__stderrp. Provide the glibc-named
// symbols (the tree's `extern "c" var stderr` etc. resolve here) and fill
// them from the Darwin globals via a __mod_init_func constructor that runs
// before main.
extern "c" var __stdinp: *anyopaque;
extern "c" var __stdoutp: *anyopaque;
extern "c" var __stderrp: *anyopaque;
export var stdin: ?*anyopaque = null;
export var stdout: ?*anyopaque = null;
export var stderr: ?*anyopaque = null;

fn initStdio() callconv(.c) void {
    stdin = __stdinp;
    stdout = __stdoutp;
    stderr = __stderrp;
}
const stdio_ctor: *const fn () callconv(.c) void = &initStdio;
comptime {
    @export(&stdio_ctor, .{ .name = "arcan_darwin_stdio_ctor", .section = "__DATA,__mod_init_func" });
}

// Linux-only privilege-separation syscalls referenced by psep_open — the
// psep paths never run on macOS (no /dev/dri, no setuid chain); succeed.
export fn setfsuid(uid: c_int) callconv(.c) c_int {
    return uid;
}
export fn setfsgid(gid: c_int) callconv(.c) c_int {
    return gid;
}

// mremap has no Darwin equivalent. The only caller (posix shm resize) treats
// MAP_FAILED as a resize failure and errors out — segment resizes are
// deferred on macOS until a shm_open+remap path is written.
export fn mremap(old: ?*anyopaque, old_size: usize, new_size: usize, flags: c_int) callconv(.c) ?*anyopaque {
    _ = old;
    _ = old_size;
    _ = new_size;
    _ = flags;
    return @ptrFromInt(std.math.maxInt(usize)); // MAP_FAILED
}

// glibc __ctype_b_loc — returns **table where table is indexed [-128,255]
// with per-character classification bitmasks (translated isalnum/isspace
// call sites in a12.zig / nbio.zig use it). Darwin has _DefaultRuneLocale
// instead; provide a C-locale table with glibc's _ISbit() encoding.
const ISbit = struct {
    // #define _ISbit(bit) ((bit) < 8 ? ((1 << (bit)) << 8) : ((1 << (bit)) >> 8))
    fn bit(comptime b: u4) u16 {
        return if (b < 8) @as(u16, 1) << (8 + @as(u4, b)) else @as(u16, 1) << (@as(u4, b) - 8);
    }
    const upper = bit(0);
    const lower = bit(1);
    const alpha = bit(2);
    const digit = bit(3);
    const xdigit = bit(4);
    const space = bit(5);
    const print = bit(6);
    const graph = bit(7);
    const cntrl = bit(8);
    const punct = bit(9);
    const alnum = bit(10);
    const blank = bit(11);
};

const ctype_table: [384]c_ushort = blk: {
    @setEvalBranchQuota(8192);
    var t: [384]c_ushort = @splat(0);
    for (0..128) |i| {
        const ch: u8 = @intCast(i);
        var m: c_ushort = 0;
        if (std.ascii.isUpper(ch)) m |= ISbit.upper;
        if (std.ascii.isLower(ch)) m |= ISbit.lower;
        if (std.ascii.isAlphabetic(ch)) m |= ISbit.alpha;
        if (std.ascii.isDigit(ch)) m |= ISbit.digit;
        if (std.ascii.isHex(ch)) m |= ISbit.xdigit;
        if (std.ascii.isWhitespace(ch)) m |= ISbit.space;
        if (std.ascii.isPrint(ch)) m |= ISbit.print;
        if (std.ascii.isPrint(ch) and ch != ' ') m |= ISbit.graph;
        if (std.ascii.isControl(ch)) m |= ISbit.cntrl;
        if (std.ascii.isPrint(ch) and ch != ' ' and !std.ascii.isAlphanumeric(ch)) m |= ISbit.punct;
        if (std.ascii.isAlphanumeric(ch)) m |= ISbit.alnum;
        if (ch == ' ' or ch == '\t') m |= ISbit.blank;
        t[128 + i] = m;
    }
    break :blk t;
};
var ctype_ptr: [*c]const c_ushort = @ptrCast(&ctype_table[128]);
export fn __ctype_b_loc() callconv(.c) [*c][*c]const c_ushort {
    return @ptrCast(&ctype_ptr);
}

// glibc execvpe(file, argv, envp) — Darwin only has execvp/execve. Standard
// shim: install envp as the process environ, then PATH-search via execvp.
extern "c" fn _NSGetEnviron() *[*:null]const ?[*:0]const u8;
extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
export fn execvpe(
    file: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) c_int {
    _NSGetEnviron().* = envp;
    return execvp(file, argv);
}

// Linux-only syscalls referenced by subsystems that are runtime-dead on
// macOS. All callers degrade gracefully on -1:
//  * eventfd — ma_alsa poll wakeup (no ALSA on macOS; dlopen of libasound
//    fails first, audio runs null-backend)
//  * inotify — shmif migrate connpath watching (falls back to timed retry)
//    and evdev hotplug (evdev calls are comptime-dead in .metal mode)
export fn eventfd(initval: c_uint, flags: c_int) callconv(.c) c_int {
    _ = initval;
    _ = flags;
    return -1;
}
export fn inotify_init1(flags: c_int) callconv(.c) c_int {
    _ = flags;
    return -1;
}
export fn inotify_add_watch(fd: c_int, pathname: [*c]const u8, mask: u32) callconv(.c) c_int {
    _ = fd;
    _ = pathname;
    _ = mask;
    return -1;
}

// Weak stubs for the vk video platform's optional exports. posix/frameserver
// references them via weak @extern (present in the full arcan exe, absent in
// afsrv_* / net exes); the Mach-O link needs a definition either way. Weak
// linkage so the real (strong) definitions in video.zig / vk.zig win when
// both are present.
fn platform_video_auth_stub(cardn: c_int, token: c_uint) callconv(.c) bool {
    _ = cardn;
    _ = token;
    return false;
}
fn vk_gbm_free_stub(bo: ?*anyopaque, map_data: ?*anyopaque) callconv(.c) void {
    _ = bo;
    _ = map_data;
}
comptime {
    @export(&platform_video_auth_stub, .{ .name = "platform_video_auth", .linkage = .weak });
    @export(&vk_gbm_free_stub, .{ .name = "vk_gbm_free", .linkage = .weak });
}
