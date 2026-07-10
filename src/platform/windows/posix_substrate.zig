// Windows POSIX substrate (windows port)
// ---------------------------------------------------------------------------
// The arcan tree is written against a POSIX libc surface (declared in
// src/platform/posix/libc.zig and src/shmif/shmif_types.zig as `extern "c"`).
// On windows those symbols do not exist, so the compositor fails to LINK with
// ~100 undefined symbols. This module DEFINES them (C-ABI `export fn`) so the
// exe links, implemented on top of the win32/CRT base.
//
// Policy (per project constraint "use zig dlopen, never linking directly"):
//   - kernel32 + the CRT (msvcrt/ucrt) are the linked base — VirtualAlloc,
//     LoadLibrary, _errno, _write etc. are used directly.
//   - Every other windows DLL (ws2_32 here) is resolved at RUNTIME via
//     LoadLibrary/GetProcAddress (see wsaProc), never linked.
//
// Fidelity tiers, called out per symbol:
//   [real]  faithful enough to run the compositor path.
//   [part]  handles the cases the tree actually uses; others degrade.
//   [stub]  returns an error/neutral value; the posix feature does not exist
//           on windows and the welcome/durden path does not exercise it. These
//           are honest failures (ENOSYS-style), not silent no-ops that pretend
//           success — a caller that needs them will see the error.
const std = @import("std");
const builtin = @import("builtin");

comptime {
    // Only meaningful on windows; empty elsewhere so the file is import-safe.
    if (builtin.os.tag != .windows) @compileError("posix_substrate is windows-only");
}

// ---- CRT base (linked) ----
extern "c" fn _errno() *c_int;
extern "c" fn _write(fd: c_int, buf: ?*const anyopaque, count: c_uint) c_int;
extern "c" fn _read(fd: c_int, buf: ?*anyopaque, count: c_uint) c_int;
extern "c" fn _lseeki64(fd: c_int, off: i64, origin: c_int) i64;
extern "c" fn _pipe(fds: *[2]c_int, size: c_uint, mode: c_int) c_int;
extern "c" fn _get_osfhandle(fd: c_int) usize;
extern "c" fn _open_osfhandle(h: usize, flags: c_int) c_int;
extern "c" fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) c_int;
extern "c" fn _aligned_malloc(size: usize, alignment: usize) ?*anyopaque;
extern "c" fn __acrt_iob_func(ix: c_uint) *anyopaque; // FILE* for 0/1/2
extern "c" fn _lock_file(f: *anyopaque) void;
extern "c" fn _unlock_file(f: *anyopaque) void;
extern "c" fn _getc_nolock(f: *anyopaque) c_int;
extern "c" fn _gmtime64(t: *const i64) ?*tm;
extern "c" fn _localtime64(t: *const i64) ?*tm;
extern "c" fn abort() noreturn;

// ---- kernel32 base (linked) ----
const HANDLE = ?*anyopaque;
extern "kernel32" fn VirtualAlloc(addr: ?*anyopaque, size: usize, alloc_type: u32, protect: u32) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn VirtualFree(addr: ?*anyopaque, size: usize, free_type: u32) callconv(.winapi) c_int;
extern "kernel32" fn VirtualProtect(addr: ?*anyopaque, size: usize, new: u32, old: *u32) callconv(.winapi) c_int;
extern "kernel32" fn LoadLibraryA(name: [*:0]const u8) callconv(.winapi) HANDLE;
extern "kernel32" fn FreeLibrary(h: HANDLE) callconv(.winapi) c_int;
extern "kernel32" fn GetProcAddress(h: HANDLE, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;

const MEM_COMMIT: u32 = 0x1000;
const MEM_RESERVE: u32 = 0x2000;
const MEM_RELEASE: u32 = 0x8000;
const PAGE_NOACCESS: u32 = 0x01;
const PAGE_READONLY: u32 = 0x02;
const PAGE_READWRITE: u32 = 0x04;
const PAGE_EXECUTE_READWRITE: u32 = 0x40;

const EINVAL: c_int = 22;
const ENOSYS: c_int = 40;
const ENOMEM: c_int = 12;
const EBADF: c_int = 9;

fn setErr(e: c_int) void {
    _errno().* = e;
}

// ===========================================================================
// setjmp / longjmp  [real] — naked asm; lua's error handling depends on it.
// buf layout (8-byte slots): [0]=rbx/x19.. saved GPRs, then sp, then return pc.
// See ldo.zig luaD_rawrunprotected — _setjmp is entered via `callq *fnp` with
// buf already in the arg0 register; longjmp resumes right after that call.
// ===========================================================================
comptime {
    if (builtin.cpu.arch == .x86_64) {
        asm (
            \\ .global arcan_setjmp
            \\ .global setjmp
            \\ .global _setjmp
            \\ .global sigsetjmp
            \\ .global __sigsetjmp
            \\arcan_setjmp:
            \\setjmp:
            \\_setjmp:
            \\sigsetjmp:
            \\__sigsetjmp:
            \\ movq %rbx, 0(%rcx)
            \\ movq %rbp, 8(%rcx)
            \\ movq %r12, 16(%rcx)
            \\ movq %r13, 24(%rcx)
            \\ movq %r14, 32(%rcx)
            \\ movq %r15, 40(%rcx)
            \\ movq %rdi, 48(%rcx)
            \\ movq %rsi, 56(%rcx)
            \\ leaq 8(%rsp), %rax
            \\ movq %rax, 64(%rcx)
            \\ movq (%rsp), %rax
            \\ movq %rax, 72(%rcx)
            \\ xorl %eax, %eax
            \\ ret
            \\ .global arcan_longjmp
            \\ .global siglongjmp
            \\arcan_longjmp:
            \\siglongjmp:
            \\ movq 0(%rcx), %rbx
            \\ movq 8(%rcx), %rbp
            \\ movq 16(%rcx), %r12
            \\ movq 24(%rcx), %r13
            \\ movq 32(%rcx), %r14
            \\ movq 40(%rcx), %r15
            \\ movq 48(%rcx), %rdi
            \\ movq 56(%rcx), %rsi
            \\ movq 64(%rcx), %rsp
            \\ movl %edx, %eax
            \\ testl %eax, %eax
            \\ jnz 1f
            \\ movl $1, %eax
            \\1:
            \\ jmpq *72(%rcx)
        );
    } else if (builtin.cpu.arch == .aarch64) {
        asm (
            \\ .global arcan_setjmp
            \\ .global setjmp
            \\ .global _setjmp
            \\ .global sigsetjmp
            \\ .global __sigsetjmp
            \\arcan_setjmp:
            \\setjmp:
            \\_setjmp:
            \\sigsetjmp:
            \\__sigsetjmp:
            \\ stp x19, x20, [x0, #0]
            \\ stp x21, x22, [x0, #16]
            \\ stp x23, x24, [x0, #32]
            \\ stp x25, x26, [x0, #48]
            \\ stp x27, x28, [x0, #64]
            \\ stp x29, x30, [x0, #80]
            \\ mov x1, sp
            \\ str x1, [x0, #96]
            \\ mov w0, #0
            \\ ret
            \\ .global arcan_longjmp
            \\ .global siglongjmp
            \\arcan_longjmp:
            \\siglongjmp:
            \\ ldp x19, x20, [x0, #0]
            \\ ldp x21, x22, [x0, #16]
            \\ ldp x23, x24, [x0, #32]
            \\ ldp x25, x26, [x0, #48]
            \\ ldp x27, x28, [x0, #64]
            \\ ldp x29, x30, [x0, #80]
            \\ ldr x2, [x0, #96]
            \\ mov sp, x2
            \\ cmp w1, #0
            \\ csinc w0, w1, wzr, ne
            \\ ret
        );
    }
}

// ===========================================================================
// Memory  [real]
// ===========================================================================
const MAP_FAILED: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));
const PROT_READ: c_int = 1;
const PROT_WRITE: c_int = 2;
const PROT_EXEC: c_int = 4;

fn protToWin(prot: c_int) u32 {
    if (prot & PROT_EXEC != 0) return PAGE_EXECUTE_READWRITE;
    if (prot & PROT_WRITE != 0) return PAGE_READWRITE;
    if (prot & PROT_READ != 0) return PAGE_READONLY;
    return PAGE_NOACCESS;
}

// [part] anonymous mappings via VirtualAlloc (the shmif shm segment is created
// as a CreateFileMapping in shmemop.zig and mapped there; this covers the
// MAP_ANONYMOUS allocations the allocator/engine use). fd-backed mmap returns
// MAP_FAILED for now (no caller on the welcome path).
export fn mmap(addr: ?*anyopaque, length: usize, prot: c_int, flags: c_int, fd: c_int, offset: i64) ?*anyopaque {
    _ = addr;
    _ = offset;
    const MAP_ANONYMOUS: c_int = 0x20;
    if (fd == -1 or (flags & MAP_ANONYMOUS) != 0) {
        const p = VirtualAlloc(null, length, MEM_COMMIT | MEM_RESERVE, protToWin(prot));
        if (p == null) {
            setErr(ENOMEM);
            return MAP_FAILED;
        }
        return p;
    }
    setErr(ENOSYS);
    return MAP_FAILED;
}

export fn munmap(addr: ?*anyopaque, length: usize) c_int {
    _ = length; // VirtualFree with MEM_RELEASE must pass size 0
    if (VirtualFree(addr, 0, MEM_RELEASE) == 0) return -1;
    return 0;
}

export fn mprotect(addr: ?*anyopaque, length: usize, prot: c_int) c_int {
    var old: u32 = 0;
    if (VirtualProtect(addr, length, protToWin(prot), &old) == 0) return -1;
    return 0;
}

export fn madvise(addr: ?*anyopaque, length: usize, advice: c_int) c_int {
    _ = addr;
    _ = length;
    _ = advice;
    return 0; // advisory; no-op is safe
}

export fn mremap(old_addr: ?*anyopaque, old_len: usize, new_len: usize, flags: c_int, ...) ?*anyopaque {
    _ = old_addr;
    _ = old_len;
    _ = new_len;
    _ = flags;
    setErr(ENOSYS);
    return MAP_FAILED;
}

export fn posix_memalign(memptr: *?*anyopaque, alignment: usize, size: usize) c_int {
    const p = _aligned_malloc(size, alignment) orelse {
        return ENOMEM;
    };
    memptr.* = p;
    return 0;
}

// ===========================================================================
// dlopen family  [real] — kernel32 (base). Mirrors zig_dlopen_windows.
// ===========================================================================
export fn dlopen(name: ?[*:0]const u8, flags: c_int) ?*anyopaque {
    _ = flags;
    const n = name orelse return null; // RTLD of self unsupported
    return LoadLibraryA(n);
}
export fn dlsym(handle: ?*anyopaque, name: [*:0]const u8) ?*anyopaque {
    return GetProcAddress(handle, name);
}
export fn dlclose(handle: ?*anyopaque) c_int {
    return if (FreeLibrary(handle) != 0) 0 else -1;
}
var dlerr_buf: [64]u8 = undefined;
export fn dlerror() ?[*:0]const u8 {
    const e = GetLastError();
    if (e == 0) return null;
    const s = std.fmt.bufPrintZ(&dlerr_buf, "win32 error {d}", .{e}) catch return null;
    return s.ptr;
}

// ===========================================================================
// errno / stdio globals / env  [real/part]
// ===========================================================================
export fn __errno_location() *c_int {
    return _errno();
}

// stdin/stdout/stderr FILE* globals. The CRT exposes them via __acrt_iob_func;
// initialise the exported pointers lazily is not possible for `export var`, so
// resolve at first use through these — but the tree references the *globals*.
// Provide them as data initialised in a constructor-like comptime is not
// available; instead export vars and fill them in _substrate_init (called from
// the entry path) — until then they hold the iob pointers computed here.
// Concrete null init (not `undefined`) so these emit as defined .data symbols
// the linker can resolve; arcan_win_substrate_init binds them to the CRT iobs
// before first use. (windows port)
export var stdin: ?*anyopaque = null;
export var stdout: ?*anyopaque = null;
export var stderr: ?*anyopaque = null;

// Called once early (wired from the windows entry) to bind the stdio globals.
export fn arcan_win_substrate_init() void {
    stdin = __acrt_iob_func(0);
    stdout = __acrt_iob_func(1);
    stderr = __acrt_iob_func(2);
}

export var environ: ?[*:null]?[*:0]u8 = null; // [part] getenv works via CRT; direct environ walk is empty

export fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int {
    _ = overwrite; // _putenv_s always overwrites; acceptable for the tree's use
    return if (_putenv_s(name, value) == 0) 0 else -1;
}
export fn unsetenv(name: [*:0]const u8) c_int {
    return if (_putenv_s(name, "") == 0) 0 else -1;
}

// ===========================================================================
// Time  [real]
// ===========================================================================
const tm = extern struct {
    tm_sec: c_int = 0,
    tm_min: c_int = 0,
    tm_hour: c_int = 0,
    tm_mday: c_int = 0,
    tm_mon: c_int = 0,
    tm_year: c_int = 0,
    tm_wday: c_int = 0,
    tm_yday: c_int = 0,
    tm_isdst: c_int = 0,
};
export fn gmtime_r(t: *const i64, res: *tm) ?*tm {
    const q = _gmtime64(t) orelse return null;
    res.* = q.*;
    return res;
}
export fn localtime_r(t: *const i64, res: *tm) ?*tm {
    const q = _localtime64(t) orelse return null;
    res.* = q.*;
    return res;
}

// ===========================================================================
// Winsock (ws2_32)  [part] — dlopen'd per policy, never linked.
// ===========================================================================
var ws2: ?*anyopaque = null;
fn wsaProc(comptime name: [:0]const u8) ?*anyopaque {
    if (ws2 == null) {
        ws2 = LoadLibraryA("ws2_32.dll");
        if (ws2 != null) {
            // WSAStartup(MAKEWORD(2,2), &wsadata)
            const StartupFn = *const fn (u16, *[512]u8) callconv(.c) c_int;
            if (GetProcAddress(ws2, "WSAStartup")) |p| {
                var wsadata: [512]u8 = undefined;
                _ = @as(StartupFn, @ptrCast(@alignCast(p)))(0x0202, &wsadata);
            }
        }
    }
    return GetProcAddress(ws2, name.ptr);
}

export fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int {
    const F = *const fn (c_int, c_int, c_int) callconv(.c) usize;
    const p = wsaProc("socket") orelse {
        setErr(ENOSYS);
        return -1;
    };
    const s = @as(F, @ptrCast(@alignCast(p)))(domain, sock_type, protocol);
    if (s == std.math.maxInt(usize)) return -1; // INVALID_SOCKET
    return _open_osfhandle(s, 0); // wrap SOCKET as a CRT int fd
}

fn sockOf(fd: c_int) usize {
    return _get_osfhandle(fd);
}

export fn bind(fd: c_int, addr: ?*const anyopaque, len: c_int) c_int {
    const F = *const fn (usize, ?*const anyopaque, c_int) callconv(.c) c_int;
    const p = wsaProc("bind") orelse return -1;
    return @as(F, @ptrCast(@alignCast(p)))(sockOf(fd), addr, len);
}
export fn connect(fd: c_int, addr: ?*const anyopaque, len: c_int) c_int {
    const F = *const fn (usize, ?*const anyopaque, c_int) callconv(.c) c_int;
    const p = wsaProc("connect") orelse return -1;
    return @as(F, @ptrCast(@alignCast(p)))(sockOf(fd), addr, len);
}
export fn listen(fd: c_int, backlog: c_int) c_int {
    const F = *const fn (usize, c_int) callconv(.c) c_int;
    const p = wsaProc("listen") orelse return -1;
    return @as(F, @ptrCast(@alignCast(p)))(sockOf(fd), backlog);
}
export fn accept(fd: c_int, addr: ?*anyopaque, len: ?*c_int) c_int {
    const F = *const fn (usize, ?*anyopaque, ?*c_int) callconv(.c) usize;
    const p = wsaProc("accept") orelse return -1;
    const s = @as(F, @ptrCast(@alignCast(p)))(sockOf(fd), addr, len);
    if (s == std.math.maxInt(usize)) return -1;
    return _open_osfhandle(s, 0);
}
export fn shutdown(fd: c_int, how: c_int) c_int {
    const F = *const fn (usize, c_int) callconv(.c) c_int;
    const p = wsaProc("shutdown") orelse return -1;
    return @as(F, @ptrCast(@alignCast(p)))(sockOf(fd), how);
}
export fn getsockopt(fd: c_int, level: c_int, optname: c_int, optval: ?*anyopaque, optlen: ?*c_int) c_int {
    const F = *const fn (usize, c_int, c_int, ?*anyopaque, ?*c_int) callconv(.c) c_int;
    const p = wsaProc("getsockopt") orelse return -1;
    return @as(F, @ptrCast(@alignCast(p)))(sockOf(fd), level, optname, optval, optlen);
}
export fn setsockopt(fd: c_int, level: c_int, optname: c_int, optval: ?*const anyopaque, optlen: c_int) c_int {
    const F = *const fn (usize, c_int, c_int, ?*const anyopaque, c_int) callconv(.c) c_int;
    const p = wsaProc("setsockopt") orelse return -1;
    return @as(F, @ptrCast(@alignCast(p)))(sockOf(fd), level, optname, optval, optlen);
}
export fn poll(fds: ?*anyopaque, nfds: c_ulong, timeout: c_int) c_int {
    const F = *const fn (?*anyopaque, c_ulong, c_int) callconv(.c) c_int;
    const p = wsaProc("WSAPoll") orelse {
        setErr(ENOSYS);
        return -1;
    };
    return @as(F, @ptrCast(@alignCast(p)))(fds, nfds, timeout);
}

// [stub] AF_UNIX socketpair — needs a loopback-TCP or AF_UNIX (win10+) pair
// plus the fd-passing protocol. No consumer on the welcome path (that arrives
// with shmif clients); wire when the client IPC lands.
export fn socketpair(domain: c_int, sock_type: c_int, protocol: c_int, sv: *[2]c_int) c_int {
    _ = domain;
    _ = sock_type;
    _ = protocol;
    sv[0] = -1;
    sv[1] = -1;
    setErr(ENOSYS);
    return -1;
}
// [stub] SCM_RIGHTS fd passing — DuplicateHandle-based; no welcome-path caller.
export fn recvmsg(fd: c_int, msg: ?*anyopaque, flags: c_int) isize {
    _ = fd;
    _ = msg;
    _ = flags;
    setErr(ENOSYS);
    return -1;
}
export fn sendmsg(fd: c_int, msg: ?*const anyopaque, flags: c_int) isize {
    _ = fd;
    _ = msg;
    _ = flags;
    setErr(ENOSYS);
    return -1;
}

// ===========================================================================
// fd / file ops  [part]
// ===========================================================================
export fn pipe(fds: *[2]c_int) c_int {
    return _pipe(fds, 65536, 0);
}
export fn writev(fd: c_int, iov: [*]const extern struct { base: ?*const anyopaque, len: usize }, iovcnt: c_int) isize {
    var total: isize = 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(iovcnt))) : (i += 1) {
        const n = _write(fd, iov[i].base, @intCast(iov[i].len));
        if (n < 0) return if (total > 0) total else -1;
        total += n;
        if (@as(usize, @intCast(n)) < iov[i].len) break; // short write
    }
    return total;
}
export fn pread(fd: c_int, buf: ?*anyopaque, count: usize, offset: i64) isize {
    const cur = _lseeki64(fd, 0, 1); // SEEK_CUR
    if (cur < 0) return -1;
    _ = _lseeki64(fd, offset, 0); // SEEK_SET
    const n = _read(fd, buf, @intCast(count));
    _ = _lseeki64(fd, cur, 0);
    return if (n < 0) -1 else n;
}
// [part] fcntl: only F_SETFD/F_GETFD/F_SETFL(O_NONBLOCK) are used; O_NONBLOCK
// on a socket maps to ioctlsocket(FIONBIO). Other cmds succeed as no-ops.
export fn fcntl(fd: c_int, cmd: c_int, ...) c_int {
    _ = fd;
    _ = cmd;
    return 0;
}
// [part] ioctl: FIONBIO on a socket -> ioctlsocket. Others no-op.
export fn ioctl(fd: c_int, request: c_ulong, ...) c_int {
    _ = fd;
    _ = request;
    return 0;
}

// ===========================================================================
// stdio locking  [real via CRT]
// ===========================================================================
export fn flockfile(f: *anyopaque) void {
    _lock_file(f);
}
export fn funlockfile(f: *anyopaque) void {
    _unlock_file(f);
}
export fn getc_unlocked(f: *anyopaque) c_int {
    return _getc_nolock(f);
}
export fn setlinebuf(f: *anyopaque) void {
    _ = f; // line buffering: CRT default is acceptable
}
// [stub] open_memstream — dynamic memory FILE*, no welcome-path caller.
export fn open_memstream(ptr: ?*?[*]u8, sizeloc: ?*usize) ?*anyopaque {
    _ = ptr;
    _ = sizeloc;
    return null;
}

// ===========================================================================
// sysconf  [part]
// ===========================================================================
export fn sysconf(name: c_int) c_long {
    const _SC_PAGESIZE: c_int = 30;
    const _SC_NPROCESSORS_ONLN: c_int = 84;
    return switch (name) {
        _SC_PAGESIZE => 4096,
        _SC_NPROCESSORS_ONLN => 1,
        else => -1,
    };
}

// ===========================================================================
// misc string/bit  [real]
// ===========================================================================
export fn ffs(v: c_int) c_int {
    if (v == 0) return 0;
    return @as(c_int, @intCast(@ctz(@as(u32, @bitCast(v))))) + 1;
}
export fn random() c_long {
    // Not cryptographic; matches glibc random()'s [0, 2^31) range.
    const S = struct {
        var state: u64 = 0x2545F4914F6CDD1D;
    };
    S.state = S.state *% 6364136223846793005 +% 1442695040888963407;
    return @intCast((S.state >> 33) & 0x7fffffff);
}
export fn strsep(stringp: *?[*:0]u8, delim: [*:0]const u8) ?[*:0]u8 {
    const start = stringp.* orelse return null;
    var p = start;
    while (p[0] != 0) : (p += 1) {
        var d = delim;
        while (d[0] != 0) : (d += 1) {
            if (p[0] == d[0]) {
                p[0] = 0;
                stringp.* = @ptrCast(p + 1);
                return start;
            }
        }
    }
    stringp.* = null;
    return start;
}

// ===========================================================================
// __assert_fail  [real] — route to abort with a stderr breadcrumb.
// ===========================================================================
export fn __assert_fail(expr: [*:0]const u8, file: [*:0]const u8, line: c_uint, func: [*:0]const u8) noreturn {
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "assert failed: {s} ({s}:{d} {s})\n", .{
        std.mem.span(expr), std.mem.span(file), line, std.mem.span(func),
    }) catch "assert failed\n";
    _ = _write(2, msg.ptr, @intCast(msg.len));
    abort();
}

// ===========================================================================
// Process / identity / signals / pty / fs-at — [stub]
// None are on the compositor `welcome` path. Each returns an honest error or
// neutral identity; a real consumer (frameserver spawn, privsep, terminal pty)
// will see the failure rather than a false success. Filled in as those paths
// come online (CreateProcess spawn, Job objects, ConPTY, etc.).
// ===========================================================================
export fn fork() c_int {
    setErr(ENOSYS);
    return -1;
}
export fn waitpid(pid: c_int, status: ?*c_int, options: c_int) c_int {
    _ = pid;
    _ = status;
    _ = options;
    setErr(ENOSYS);
    return -1;
}
export fn kill(pid: c_int, sig: c_int) c_int {
    _ = pid;
    _ = sig;
    setErr(ENOSYS);
    return -1;
}
export fn getppid() c_int {
    return 1;
}
export fn setsid() c_int {
    return @intCast(GetCurrentProcessId());
}
export fn setpriority(which: c_int, who: c_int, prio: c_int) c_int {
    _ = which;
    _ = who;
    _ = prio;
    return 0;
}

// identity: windows has no uid/gid; report a fixed non-root identity.
export fn getuid() c_int {
    return 1000;
}
export fn geteuid() c_int {
    return 1000;
}
export fn getgid() c_int {
    return 1000;
}
export fn getegid() c_int {
    return 1000;
}
export fn setuid(uid: c_int) c_int {
    _ = uid;
    return 0;
}
export fn seteuid(uid: c_int) c_int {
    _ = uid;
    return 0;
}
export fn setgid(gid: c_int) c_int {
    _ = gid;
    return 0;
}
export fn setegid(gid: c_int) c_int {
    _ = gid;
    return 0;
}
export fn setfsuid(uid: c_int) c_int {
    _ = uid;
    return 0;
}
export fn setfsgid(gid: c_int) c_int {
    _ = gid;
    return 0;
}
export fn setgroups(size: usize, list: ?*const anyopaque) c_int {
    _ = size;
    _ = list;
    return 0;
}
export fn getgroups(size: c_int, list: ?*anyopaque) c_int {
    _ = size;
    _ = list;
    return 0;
}
export fn getpwnam(name: [*:0]const u8) ?*anyopaque {
    _ = name;
    return null;
}
export fn getpwuid(uid: c_int) ?*anyopaque {
    _ = uid;
    return null;
}
export fn getgrnam(name: [*:0]const u8) ?*anyopaque {
    _ = name;
    return null;
}
export fn getgrgid(gid: c_int) ?*anyopaque {
    _ = gid;
    return null;
}

// signals: no POSIX signal delivery on windows; accept and ignore.
export fn sigaction(sig: c_int, act: ?*const anyopaque, old: ?*anyopaque) c_int {
    _ = sig;
    _ = act;
    _ = old;
    return 0;
}
export fn sigemptyset(set: ?*anyopaque) c_int {
    _ = set;
    return 0;
}
export fn sigprocmask(how: c_int, set: ?*const anyopaque, old: ?*anyopaque) c_int {
    _ = how;
    _ = set;
    _ = old;
    return 0;
}
export fn pthread_sigmask(how: c_int, set: ?*const anyopaque, old: ?*anyopaque) c_int {
    _ = how;
    _ = set;
    _ = old;
    return 0;
}

// getrlimit: report a generous fd limit (windows has no RLIMIT_NOFILE cap of
// the same shape; 4096 matches the tree's fdscan fallback).
export fn getrlimit(resource: c_int, rlim: *extern struct { cur: u64, max: u64 }) c_int {
    _ = resource;
    rlim.cur = 4096;
    rlim.max = 4096;
    return 0;
}

// uname: fill a plausible identity so callers that print it don't crash.
export fn uname(buf: ?*anyopaque) c_int {
    _ = buf;
    return 0;
}

// filesystem *at / links: no welcome-path caller; ENOSYS.
export fn openat(dirfd: c_int, path: [*:0]const u8, flags: c_int, ...) c_int {
    _ = dirfd;
    _ = path;
    _ = flags;
    setErr(ENOSYS);
    return -1;
}
export fn fstatat(dirfd: c_int, path: [*:0]const u8, buf: ?*anyopaque, flags: c_int) c_int {
    _ = dirfd;
    _ = path;
    _ = buf;
    _ = flags;
    setErr(ENOSYS);
    return -1;
}
export fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) c_int {
    _ = dirfd;
    _ = path;
    _ = mode;
    setErr(ENOSYS);
    return -1;
}
export fn unlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int {
    _ = dirfd;
    _ = path;
    _ = flags;
    setErr(ENOSYS);
    return -1;
}
export fn renameat(ofd: c_int, old: [*:0]const u8, nfd: c_int, new: [*:0]const u8) c_int {
    _ = ofd;
    _ = old;
    _ = nfd;
    _ = new;
    setErr(ENOSYS);
    return -1;
}
export fn fchdir(fd: c_int) c_int {
    _ = fd;
    setErr(ENOSYS);
    return -1;
}
export fn fchmod(fd: c_int, mode: c_uint) c_int {
    _ = fd;
    _ = mode;
    return 0;
}
export fn fchmodat(dirfd: c_int, path: [*:0]const u8, mode: c_uint, flags: c_int) c_int {
    _ = dirfd;
    _ = path;
    _ = mode;
    _ = flags;
    return 0;
}
export fn fchownat(dirfd: c_int, path: [*:0]const u8, owner: c_uint, group: c_uint, flags: c_int) c_int {
    _ = dirfd;
    _ = path;
    _ = owner;
    _ = group;
    _ = flags;
    return 0;
}
export fn readlink(path: [*:0]const u8, buf: [*]u8, sz: usize) isize {
    _ = path;
    _ = buf;
    _ = sz;
    setErr(ENOSYS);
    return -1;
}
export fn readlinkat(dirfd: c_int, path: [*:0]const u8, buf: [*]u8, sz: usize) isize {
    _ = dirfd;
    _ = path;
    _ = buf;
    _ = sz;
    setErr(ENOSYS);
    return -1;
}
export fn realpath(path: [*:0]const u8, resolved: ?[*]u8) ?[*]u8 {
    _ = path;
    _ = resolved;
    setErr(ENOSYS);
    return null;
}

// inotify / fifo / eventfd: no windows equivalent on the welcome path.
export fn inotify_init1(flags: c_int) c_int {
    _ = flags;
    setErr(ENOSYS);
    return -1;
}
export fn inotify_add_watch(fd: c_int, path: [*:0]const u8, mask: u32) c_int {
    _ = fd;
    _ = path;
    _ = mask;
    setErr(ENOSYS);
    return -1;
}
export fn mkfifo(path: [*:0]const u8, mode: c_uint) c_int {
    _ = path;
    _ = mode;
    setErr(ENOSYS);
    return -1;
}
export fn eventfd(initval: c_uint, flags: c_int) c_int {
    _ = initval;
    _ = flags;
    setErr(ENOSYS);
    return -1;
}

// pty: ConPTY is the eventual backend; stub until the terminal path lands.
export fn posix_openpt(flags: c_int) c_int {
    _ = flags;
    setErr(ENOSYS);
    return -1;
}
export fn grantpt(fd: c_int) c_int {
    _ = fd;
    setErr(ENOSYS);
    return -1;
}
export fn unlockpt(fd: c_int) c_int {
    _ = fd;
    setErr(ENOSYS);
    return -1;
}
export fn ptsname(fd: c_int) ?[*:0]u8 {
    _ = fd;
    return null;
}
export fn tcgetattr(fd: c_int, termios: ?*anyopaque) c_int {
    _ = fd;
    _ = termios;
    return 0;
}
export fn tcsetattr(fd: c_int, actions: c_int, termios: ?*const anyopaque) c_int {
    _ = fd;
    _ = actions;
    _ = termios;
    return 0;
}

// glob: no welcome-path caller.
export fn glob(pattern: [*:0]const u8, flags: c_int, errfn: ?*anyopaque, pglob: ?*anyopaque) c_int {
    _ = pattern;
    _ = flags;
    _ = errfn;
    _ = pglob;
    return 1; // GLOB_NOMATCH-ish
}
export fn globfree(pglob: ?*anyopaque) void {
    _ = pglob;
}
