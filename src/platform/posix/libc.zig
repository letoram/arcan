//! Shared libc shim for tools that need stdio + signal + mmap + a handful
//! of related POSIX entry points. Zig's `std.c` doesn't expose stdio
//! streams (stderr/stdout/stdin) on all targets and the printf-family
//! varargs are inconvenient through the std interface. Tools used to
//! redeclare these per-file; collect them here.
//!
//! Only add things that show up in 2+ tools. Tool-specific extern decls
//! stay in the tool's own .zig.

const std = @import("std");
const builtin = @import("builtin");
const is_darwin = builtin.os.tag.isDarwin();

// stdio FILE + streams + printf-family

pub const FILE = std.c.FILE;
pub extern "c" var stdin: *FILE;
pub extern "c" var stdout: *FILE;
pub extern "c" var stderr: *FILE;

pub extern "c" fn printf(fmt: [*:0]const u8, ...) c_int;
pub extern "c" fn fprintf(stream: ?*FILE, fmt: [*:0]const u8, ...) c_int;
pub extern "c" fn fflush(stream: ?*FILE) c_int;
pub extern "c" fn feof(stream: *FILE) c_int;
pub extern "c" fn ferror(stream: *FILE) c_int;
pub extern "c" fn putchar(ch: c_int) c_int;
pub extern "c" fn fileno(stream: ?*FILE) c_int;
pub extern "c" fn popen(cmd: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
pub extern "c" fn pclose(stream: *FILE) c_int;
pub extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
pub extern "c" fn fclose(stream: ?*FILE) c_int;
pub extern "c" fn fdopen(fd: c_int, mode: [*:0]const u8) ?*FILE;
pub extern "c" fn fread(ptr: ?*anyopaque, size: usize, nmemb: usize, stream: ?*FILE) usize;
pub extern fn fwrite(ptr: ?*const anyopaque, size: usize, nmemb: usize, stream: ?*FILE) usize;
pub extern "c" fn fseek(stream: *FILE, offset: c_long, whence: c_int) c_int;
pub extern "c" fn ftell(stream: *FILE) c_long;
pub const SEEK_END: c_int = 2;
pub const SEEK_CUR: c_int = 1;
pub extern "c" fn strtoul(nptr: [*:0]const u8, endptr: ?*[*c]u8, base: c_int) c_ulong;
pub extern "c" fn strtol(nptr: [*:0]const u8, endptr: ?*[*c]u8, base: c_int) c_long;

// memory + mmap

pub extern "c" fn malloc(sz: usize) ?*anyopaque;
pub extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
pub extern "c" fn free(ptr: ?*anyopaque) void;
pub extern fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
pub extern "c" fn memset(dst: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;
pub extern "c" fn memcmp(a: ?*const anyopaque, b: ?*const anyopaque, n: usize) c_int;
// sprintf — variadic. Callers pass a mutable buffer. Unsafe vs snprintf but a12.zig
// preserves the legacy signature for a small number of fixed-size formats.
pub extern "c" fn sprintf(buf: [*c]u8, fmt: [*:0]const u8, ...) c_int;
// __assert_fail — glibc assertion stub referenced when <assert.h> translates an
// active assert() call. We forward-declare it so dispatch consumers can alias it.
pub extern "c" fn __assert_fail(assertion: [*c]const u8, file: [*c]const u8, line: c_uint, function: [*c]const u8) noreturn;

// struct iovec — sys/uio.h
pub const struct_iovec = extern struct {
    iov_base: ?*anyopaque = null,
    iov_len: usize = 0,
};
pub const iovec = struct_iovec;

pub extern "c" fn mmap(
    addr: ?*anyopaque,
    length: usize,
    prot: c_int,
    flags: c_int,
    fd: c_int,
    offset: i64,
) ?*anyopaque;
pub extern "c" fn munmap(addr: ?*anyopaque, length: usize) c_int;
pub extern "c" fn mprotect(addr: ?*anyopaque, length: usize, prot: c_int) c_int;

pub const PROT_NONE: c_int = 0;
pub const PROT_READ: c_int = 1;
pub const PROT_WRITE: c_int = 2;
pub const PROT_EXEC: c_int = 4;

pub const MAP_SHARED: c_int = 0x01;
pub const MAP_PRIVATE: c_int = 0x02;
pub const MAP_ANONYMOUS: c_int = if (is_darwin) 0x1000 else 0x20;
pub const MAP_ANON: c_int = MAP_ANONYMOUS;
pub const MAP_FIXED: c_int = 0x10;
pub const MAP_FAILED: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));

// files

pub extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
pub extern "c" fn close(fd: c_int) c_int;

// signals + jmp

// `*align(1)` so that SIG_IGN/SIG_DFL/SIG_ERR sentinels (1, 0, max-int)
// can fit in this type without requiring address alignment.
pub const SigHandler = *align(1) const fn (c_int) callconv(.c) void;
pub extern "c" fn signal(sig: c_int, handler: ?SigHandler) ?SigHandler;
pub extern "c" fn sigsetjmp(env: *anyopaque, savemask: c_int) c_int;
pub extern "c" fn siglongjmp(env: *anyopaque, val: c_int) noreturn;

// jmp_buf: aarch64-linux-musl is 312 bytes, glibc 512. Use glibc-sized
// opaque buffer — larger is fine (unused bytes just waste stack).
pub const jmp_buf = extern struct {
    _opaque: [512]u8 align(8),
};
pub extern "c" fn setjmp(env: *jmp_buf) c_int;
pub extern "c" fn _setjmp(env: *jmp_buf) c_int;
pub extern "c" fn longjmp(env: *jmp_buf, val: c_int) noreturn;

// process / env

pub extern "c" fn fork() c_int;
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
pub extern "c" fn unsetenv(name: [*:0]const u8) c_int;
pub extern "c" fn abort() noreturn;
pub extern "c" fn exit(status: c_int) noreturn;

// fcntl / unistd / errno

pub const off_t = c_long;
pub const mode_t = c_uint;

pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_RDWR: c_int = 2;
pub const O_CREAT: c_int = if (is_darwin) 0x200 else 0o100;
pub const O_EXCL: c_int = if (is_darwin) 0x800 else 0o200;
pub const O_TRUNC: c_int = if (is_darwin) 0x400 else 0o1000;
pub const O_APPEND: c_int = if (is_darwin) 0x8 else 0o2000;
pub const O_NONBLOCK: c_int = if (is_darwin) 0x4 else 0o4000;
pub const O_DIRECTORY: c_int = if (is_darwin) 0x100000 else switch (builtin.target.cpu.arch) {
    .aarch64, .aarch64_be, .arm, .armeb => 0o40000,
    else => 0o200000,
};
pub const O_CLOEXEC: c_int = if (is_darwin) 0x1000000 else 0o2000000;
pub const FD_CLOEXEC: c_int = 1;
pub const F_GETFD: c_int = 1;
pub const F_SETFD: c_int = 2;
pub const F_GETFL: c_int = 3;
pub const F_SETFL: c_int = 4;
pub const SEEK_SET: c_int = 0;
pub const EAGAIN: c_int = if (is_darwin) 35 else 11;
pub const EINTR: c_int = 4;
pub const ENOMEM: c_int = 12;
pub const ESPIPE: c_int = 29;
pub const EOVERFLOW: c_int = if (is_darwin) 84 else 75;
pub const EINVAL: c_int = 22;
pub const EPIPE: c_int = 32;
pub const ECHILD: c_int = 10;
pub const ENODEV: c_int = 19;

pub extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
pub extern "c" fn lseek(fd: c_int, offset: off_t, whence: c_int) off_t;
pub extern "c" fn mkstemp(template: [*:0]u8) c_int;
pub extern "c" fn mkdtemp(template: [*:0]u8) ?[*:0]u8;
pub extern "c" fn unlink(path: [*:0]const u8) c_int;
pub extern "c" fn rmdir(path: [*:0]const u8) c_int;
pub extern "c" fn remove(path: [*:0]const u8) c_int;
pub extern "c" fn write(fd: c_int, buf: ?*const anyopaque, n: usize) isize;
pub extern "c" fn read(fd: c_int, buf: ?*anyopaque, n: usize) isize;
pub extern "c" fn pipe(fds: *[2]c_int) c_int;
pub extern "c" fn dup(fd: c_int) c_int;
pub extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
pub extern "c" fn ftruncate(fd: c_int, length: off_t) c_int;
pub extern "c" fn mkdir(path: [*:0]const u8, mode: mode_t) c_int;
// openat / renameat — pathname typed as [*c]const u8 to accept both
// sentinel-terminated strings and plain byte pointers (e.g. &fixed_buf).
// Callers are responsible for ensuring NUL-termination.
pub extern "c" fn openat(dirfd: c_int, pathname: [*c]const u8, flags: c_int, ...) c_int;
pub extern "c" fn renameat(olddirfd: c_int, oldpath: [*c]const u8, newdirfd: c_int, newpath: [*c]const u8) c_int;
// strdup / strlen — use [*c] so callers can pass either sentinel-terminated
// strings or arrays that happen to contain a NUL within bounds.
pub extern "c" fn strdup(s: [*c]const u8) [*c]u8;
pub extern fn strlen(s: [*c]const u8) usize;
// [*c] to accept both sentinel-terminated and non-sentinel byte buffers;
// callers must ensure NUL-termination within the buffer bounds.
pub extern "c" fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
pub extern "c" fn strncpy(dst: [*c]u8, src: [*c]const u8, n: usize) [*c]u8;
pub extern "c" fn strchr(s: [*c]const u8, ch: c_int) [*c]u8;
pub extern "c" fn strrchr(s: [*c]const u8, ch: c_int) [*c]u8;
pub extern "c" fn snprintf(buf: [*c]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
pub extern "c" fn __errno_location() *c_int;
pub extern "c" fn sysconf(name: c_int) c_long;
// realpath(3) — canonicalise path. If `resolved` is null, libc allocates
// (caller must free). Returns null + sets errno on failure.
pub extern "c" fn realpath(path: [*:0]const u8, resolved: [*c]u8) [*c]u8;

// access(2) / faccessat(2) — file existence + permission checks.
pub const F_OK: c_int = 0;
pub const X_OK: c_int = 1;
pub const W_OK: c_int = 2;
pub const R_OK: c_int = 4;
pub extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;
pub extern "c" fn faccessat(dirfd: c_int, pathname: [*c]const u8, mode: c_int, flags: c_int) c_int;

// exit status codes — stdlib.h
pub const EXIT_SUCCESS: c_int = 0;
pub const EXIT_FAILURE: c_int = 1;

// process
pub extern "c" fn execv(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
pub extern "c" fn execve(
    path: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) c_int;
pub extern "c" fn getpid() c_int;
pub extern "c" fn getppid() c_int;
pub extern "c" fn setsid() c_int;
pub extern "c" fn execvpe(
    file: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) c_int;
pub extern "c" fn sleep(seconds: c_uint) c_uint;
pub extern "c" fn _exit(status: c_int) noreturn;
pub extern "c" fn chdir(path: [*:0]const u8) c_int;
pub extern "c" fn fchdir(fd: c_int) c_int;
pub extern "c" fn readlinkat(dirfd: c_int, pathname: [*c]const u8, buf: [*]u8, bufsiz: usize) isize;
pub extern "c" fn readlink(path: [*c]const u8, buf: [*c]u8, bufsiz: usize) isize;

// additional stdio

pub extern "c" fn freopen(pathname: [*:0]const u8, mode: [*:0]const u8, stream: ?*FILE) ?*FILE;
pub extern "c" fn fgets(buf: [*]u8, size: c_int, stream: ?*FILE) ?[*]u8;
pub extern "c" fn fputs(s: [*:0]const u8, stream: ?*FILE) c_int;
pub extern "c" fn setlinebuf(stream: ?*FILE) void;
pub extern "c" fn fmemopen(buf: ?*anyopaque, size: usize, mode: [*:0]const u8) ?*FILE;
pub extern "c" fn strerror(errnum: c_int) [*c]const u8;
pub extern "c" fn strtoull(nptr: [*:0]const u8, endptr: ?*[*c]u8, base: c_int) c_ulonglong;
pub extern "c" fn open_memstream(ptr: *?[*]u8, sizeloc: *usize) ?*FILE;

// dirent.h — directory traversal

pub const struct_dirent = if (is_darwin) extern struct {
    d_ino: u64 = 0,
    d_seekoff: u64 = 0,
    d_reclen: c_ushort = 0,
    d_namlen: c_ushort = 0,
    d_type: u8 = 0,
    d_name: [1024]u8 = std.mem.zeroes([1024]u8),
} else extern struct {
    d_ino: c_ulong = 0,
    d_off: c_long = 0,
    d_reclen: c_ushort = 0,
    d_type: u8 = 0,
    d_name: [256]u8 = std.mem.zeroes([256]u8),
};
pub const DIR = opaque {};
pub extern "c" fn opendir(name: [*:0]const u8) ?*DIR;
pub extern "c" fn closedir(dirp: ?*DIR) c_int;
pub extern "c" fn readdir(dirp: ?*DIR) ?*struct_dirent;
pub extern "c" fn fdopendir(fd: c_int) ?*DIR;
pub extern "c" fn dirfd(dirp: ?*DIR) c_int;

pub const DT_UNKNOWN: u8 = 0;
pub const DT_FIFO: u8 = 1;
pub const DT_CHR: u8 = 2;
pub const DT_DIR: u8 = 4;
pub const DT_BLK: u8 = 6;
pub const DT_REG: u8 = 8;
pub const DT_LNK: u8 = 10;
pub const DT_SOCK: u8 = 12;

// time.h

pub const time_t = c_long;
pub const struct_tm = extern struct {
    tm_sec: c_int = 0,
    tm_min: c_int = 0,
    tm_hour: c_int = 0,
    tm_mday: c_int = 0,
    tm_mon: c_int = 0,
    tm_year: c_int = 0,
    tm_wday: c_int = 0,
    tm_yday: c_int = 0,
    tm_isdst: c_int = 0,
    tm_gmtoff: c_long = 0,
    tm_zone: ?[*:0]const u8 = null,
};
pub extern "c" fn time(tloc: ?*time_t) time_t;
pub extern "c" fn localtime(timer: *const time_t) ?*struct_tm;
pub extern "c" fn strftime(
    s: [*]u8,
    max: usize,
    format: [*:0]const u8,
    tm: *const struct_tm,
) usize;

// stdio descriptor numbers
pub const STDIN_FILENO: c_int = 0;
pub const STDOUT_FILENO: c_int = 1;
pub const STDERR_FILENO: c_int = 2;

// signal

pub const SIGINT: c_int = 2;
pub const SIGPIPE: c_int = 13;
pub const SIGCHLD: c_int = if (is_darwin) 20 else 17;

// minimal struct sigaction (glibc/aarch64 Linux): 152 bytes. Use an opaque
// blob of that size — callers just zero it and call sigaction().
pub const struct_sigaction = extern struct {
    _opaque: [152]u8 align(@alignOf(usize)) = std.mem.zeroes([152]u8),
};
pub extern "c" fn sigaction(
    signum: c_int,
    act: ?*const struct_sigaction,
    oldact: ?*struct_sigaction,
) c_int;

// sys/stat.h file type masks
pub const S_IFMT: c_uint = 0o170000;
pub const S_IFIFO: c_uint = 0o010000;
pub const S_IFCHR: c_uint = 0o020000;
pub const S_IFDIR: c_uint = 0o040000;
pub const S_IFBLK: c_uint = 0o060000;
pub const S_IFREG: c_uint = 0o100000;
pub const S_IFLNK: c_uint = 0o120000;
pub const S_IFSOCK: c_uint = 0o140000;

// sys/stat.h permission bits
pub const S_IRUSR: c_uint = 0o400;
pub const S_IWUSR: c_uint = 0o200;
pub const S_IXUSR: c_uint = 0o100;
pub const S_IRWXU: c_uint = 0o700;
pub const S_IRGRP: c_uint = 0o040;
pub const S_IWGRP: c_uint = 0o020;
pub const S_IRWXG: c_uint = 0o070;
pub const S_IROTH: c_uint = 0o004;
pub const S_IWOTH: c_uint = 0o002;
pub const S_IRWXO: c_uint = 0o007;

// sys/file.h — advisory locking
pub const LOCK_SH: c_int = 1;
pub const LOCK_EX: c_int = 2;
pub const LOCK_UN: c_int = 8;
pub const LOCK_NB: c_int = 4;
pub extern "c" fn flock(fd: c_int, operation: c_int) c_int;

// mkdirat / unlinkat — directory-fd-relative filesystem calls
pub extern "c" fn mkdirat(dirfd: c_int, pathname: [*c]const u8, mode: mode_t) c_int;
pub extern "c" fn unlinkat(dirfd: c_int, pathname: [*c]const u8, flags: c_int) c_int;
// unlinkat flag: remove an empty directory (like rmdir).
pub const AT_REMOVEDIR: c_int = if (is_darwin) 0x80 else 0x200;
pub extern "c" fn getline(
    lineptr: *?[*]u8,
    n: *usize,
    stream: ?*FILE,
) isize;

// sysconf names
pub const _SC_PAGE_SIZE: c_int = if (is_darwin) 29 else 30;
pub const _SC_PAGESIZE: c_int = _SC_PAGE_SIZE;

// rlimit (sys/resource.h) — Linux UAPI values
pub const RLIMIT_STACK: c_int = 3;
pub const RLIM_INFINITY: u64 = ~@as(u64, 0);
pub const struct_rlimit = extern struct {
    rlim_cur: u64,
    rlim_max: u64,
};
pub extern "c" fn setrlimit(resource: c_int, rlim: *const struct_rlimit) c_int;
pub extern "c" fn getrlimit(resource: c_int, rlim: *struct_rlimit) c_int;

// pthread

pub const PTHREAD_CREATE_DETACHED: c_int = if (is_darwin) 2 else 1;
pub const pthread_t = c_ulong;
pub const pthread_attr_t = extern struct {
    _opaque: [8]usize align(@alignOf(usize)),
};
comptime {
    std.debug.assert(@sizeOf(pthread_attr_t) == 64);
}

// pthread_mutex_t — 48 bytes on glibc/aarch64, 40 on musl. Use 48 so both
// fit; Linux runtime checks initialised fields, not trailing padding.
pub const pthread_mutex_t = if (is_darwin) extern struct {
    _data: [64]u8 align(@alignOf(usize)) = std.mem.zeroes([64]u8), // { long sig; char opaque[56] }
} else extern struct {
    _data: [48]u8 align(@alignOf(usize)) = std.mem.zeroes([48]u8),
};

pub extern "c" fn pthread_attr_init(attr: *pthread_attr_t) c_int;
pub extern "c" fn pthread_attr_destroy(attr: *pthread_attr_t) c_int;
pub extern "c" fn pthread_attr_setdetachstate(attr: *pthread_attr_t, state: c_int) c_int;
pub extern "c" fn pthread_attr_setstacksize(attr: *pthread_attr_t, stacksize: usize) c_int;
pub extern "c" fn pthread_create(
    thread: *pthread_t,
    attr: ?*const pthread_attr_t,
    start: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    arg: ?*anyopaque,
) c_int;
pub extern "c" fn pthread_detach(thread: pthread_t) c_int;
pub extern "c" fn pthread_mutex_init(mutex: *pthread_mutex_t, attr: ?*anyopaque) c_int;
pub extern "c" fn pthread_mutex_destroy(mutex: *pthread_mutex_t) c_int;
pub extern "c" fn pthread_mutex_lock(mutex: *pthread_mutex_t) c_int;
pub extern "c" fn pthread_mutex_unlock(mutex: *pthread_mutex_t) c_int;

// poll.h

pub const struct_pollfd = extern struct {
    fd: c_int = 0,
    events: c_short = 0,
    revents: c_short = 0,
};
pub const pollfd = struct_pollfd;

pub const POLLIN: c_short = 0x001;
pub const POLLPRI: c_short = 0x002;
pub const POLLOUT: c_short = 0x004;
pub const POLLERR: c_short = 0x008;
pub const POLLHUP: c_short = 0x010;
pub const POLLNVAL: c_short = 0x020;

pub extern "c" fn poll(fds: [*]struct_pollfd, nfds: c_ulong, timeout: c_int) c_int;

// sockets

pub extern "c" fn recv(sockfd: c_int, buf: ?*anyopaque, len: usize, flags: c_int) isize;
pub extern "c" fn send(sockfd: c_int, buf: ?*const anyopaque, len: usize, flags: c_int) isize;
pub extern "c" fn accept(sockfd: c_int, addr: ?*anyopaque, addrlen: ?*c_uint) c_int;
pub extern "c" fn bind(sockfd: c_int, addr: ?*const anyopaque, addrlen: c_uint) c_int;
pub extern "c" fn connect(sockfd: c_int, addr: ?*const anyopaque, addrlen: c_uint) c_int;
pub extern "c" fn listen(sockfd: c_int, backlog: c_int) c_int;
pub extern "c" fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
pub extern "c" fn socketpair(domain: c_int, sock_type: c_int, protocol: c_int, sv: *[2]c_int) c_int;
pub extern "c" fn shutdown(sockfd: c_int, how: c_int) c_int;
pub const SHUT_RD: c_int = 0;
pub const SHUT_WR: c_int = 1;
pub const SHUT_RDWR: c_int = 2;
pub extern "c" fn setsockopt(
    sockfd: c_int,
    level: c_int,
    optname: c_int,
    optval: ?*const anyopaque,
    optlen: c_uint,
) c_int;
pub extern "c" fn getsockopt(
    sockfd: c_int,
    level: c_int,
    optname: c_int,
    optval: ?*anyopaque,
    optlen: *c_uint,
) c_int;

pub const socklen_t = c_uint;

pub const AF_UNSPEC: c_int = 0;
pub const AF_UNIX: c_int = 1;
pub const AF_INET: c_int = 2;
pub const AF_INET6: c_int = if (is_darwin) 30 else 10;

pub const SOCK_STREAM: c_int = 1;
pub const SOCK_DGRAM: c_int = 2;

pub const IPPROTO_TCP: c_int = 6;
pub const IPPROTO_UDP: c_int = 17;

pub const SOL_SOCKET: c_int = if (is_darwin) 0xffff else 1;
pub const SO_REUSEADDR: c_int = if (is_darwin) 0x4 else 2;
pub const SO_REUSEPORT: c_int = if (is_darwin) 0x200 else 15;
pub const SO_SNDBUF: c_int = if (is_darwin) 0x1001 else 7;
pub const SO_RCVBUF: c_int = if (is_darwin) 0x1002 else 8;
pub const TCP_NODELAY: c_int = 1;

// struct sockaddr — opaque to callers; only used to take address of.
pub const struct_sockaddr = if (is_darwin) extern struct {
    sa_len: u8 = 0,
    sa_family: u8 = 0,
    sa_data: [14]u8 = std.mem.zeroes([14]u8),
} else extern struct {
    sa_family: c_ushort = 0,
    sa_data: [14]u8 = std.mem.zeroes([14]u8),
};

// isatty / asprintf / stdin
pub extern "c" fn isatty(fd: c_int) c_int;
pub extern "c" fn asprintf(strp: *?[*]u8, fmt: [*:0]const u8, ...) c_int;
// getpass — POSIX.1-2001 obsolescent but still present in glibc/musl.
// Returns a static buffer; no NUL sentinel guarantee in header, so use [*c].
pub extern "c" fn getpass(prompt: [*:0]const u8) [*c]u8;
// getcwd — POSIX working-directory query (used by terminal cli + builtins)
pub extern "c" fn getcwd(buf: [*c]u8, size: usize) [*c]u8;

// struct stat — POSIX stat(2) result. Aliased to std.c.Stat so the ABI
// matches the platform libc (size/layout differ between Linux and BSD).
// Used by consumers that want to call `stat` through the dispatch-struct
// pattern without re-deriving the layout.
pub const struct_stat = std.c.Stat;
pub extern "c" fn stat(path: [*c]const u8, buf: *struct_stat) c_int;
pub extern fn fstat(fd: c_int, buf: *struct_stat) c_int;

// ctype.h
pub extern "c" fn isalpha(c: c_int) c_int;
pub extern "c" fn isdigit(c: c_int) c_int;
pub extern "c" fn isalnum(c: c_int) c_int;
pub extern "c" fn tolower(c: c_int) c_int;
pub extern "c" fn isprint(c: c_int) c_int;

// additional string.h entry points
pub extern "c" fn strncmp(a: [*c]const u8, b: [*c]const u8, n: usize) c_int;
pub extern "c" fn strcasecmp(a: [*c]const u8, b: [*c]const u8) c_int;
pub extern "c" fn strncasecmp(a: [*c]const u8, b: [*c]const u8, n: usize) c_int;
pub extern "c" fn strtok_r(str: [*c]u8, delim: [*c]const u8, saveptr: *[*c]u8) [*c]u8;
pub extern "c" fn strtok(str: [*c]u8, delim: [*c]const u8) [*c]u8;

// additional stdio
pub extern "c" fn getc(stream: ?*FILE) c_int;
pub extern "c" fn ungetc(c: c_int, stream: ?*FILE) c_int;
pub extern "c" fn fputc(c: c_int, stream: ?*FILE) c_int;
pub const EOF: c_int = -1;

// additional socket-layer entry points
pub extern "c" fn sendto(
    sockfd: c_int,
    buf: ?*const anyopaque,
    len: usize,
    flags: c_int,
    dest_addr: ?*const anyopaque,
    addrlen: c_uint,
) isize;
pub extern "c" fn inet_pton(af: c_int, src: [*c]const u8, dst: ?*anyopaque) c_int;
pub extern "c" fn getnameinfo(
    sa: ?*const anyopaque,
    salen: c_uint,
    host: [*c]u8,
    hostlen: c_uint,
    serv: [*c]u8,
    servlen: c_uint,
    flags: c_int,
) c_int;

// htons/htonl — Linux/glibc headers inline these; declare as extern so the
// dispatch-struct alias resolves.
pub extern "c" fn htons(hostshort: u16) u16;
pub extern "c" fn htonl(hostlong: u32) u32;

// getnameinfo flags
pub const NI_NUMERICHOST: c_int = if (is_darwin) 2 else 1;
pub const NI_NUMERICSERV: c_int = if (is_darwin) 8 else 2;

// IPv4/IPv6 constants and addrinfo adjuncts used by beacon discovery.
pub const INET_ADDRSTRLEN: c_int = 16;
pub const INET6_ADDRSTRLEN: c_int = 46;
pub const INADDR_ANY: u32 = 0;
pub const INADDR_BROADCAST: u32 = 0xffffffff;
pub const SO_BROADCAST: c_int = if (is_darwin) 0x20 else 6;
pub const IPPROTO_IP: c_int = 0;
pub const IPPROTO_IPV6: c_int = 41;
pub const IP_PKTINFO: c_int = if (is_darwin) 26 else 8;
pub const IP_MULTICAST_LOOP: c_int = if (is_darwin) 11 else 34;
pub const IPV6_MULTICAST_HOPS: c_int = if (is_darwin) 10 else 18;
pub const IPV6_MULTICAST_LOOP: c_int = if (is_darwin) 11 else 19;
pub const IPV6_JOIN_GROUP: c_int = if (is_darwin) 12 else 20;

// struct in_addr — 32-bit IPv4 address in network byte order.
pub const struct_in_addr = extern struct {
    s_addr: u32 = 0,
};
pub const in_addr = struct_in_addr;

// struct in6_addr — 128-bit IPv6 address.
pub const struct_in6_addr = extern struct {
    s6_addr: [16]u8 = std.mem.zeroes([16]u8),
};
pub const in6_addr = struct_in6_addr;

// struct sockaddr_in — IPv4 socket address.
pub const struct_sockaddr_in = if (is_darwin) extern struct {
    sin_len: u8 = 0,
    sin_family: u8 = 0,
    sin_port: u16 = 0,
    sin_addr: struct_in_addr = .{},
    sin_zero: [8]u8 = std.mem.zeroes([8]u8),
} else extern struct {
    sin_family: c_ushort = 0,
    sin_port: u16 = 0,
    sin_addr: struct_in_addr = .{},
    sin_zero: [8]u8 = std.mem.zeroes([8]u8),
};
pub const sockaddr_in = struct_sockaddr_in;

// struct sockaddr_in6 — IPv6 socket address.
pub const struct_sockaddr_in6 = if (is_darwin) extern struct {
    sin6_len: u8 = 0,
    sin6_family: u8 = 0,
    sin6_port: u16 = 0,
    sin6_flowinfo: u32 = 0,
    sin6_addr: struct_in6_addr = .{},
    sin6_scope_id: u32 = 0,
} else extern struct {
    sin6_family: c_ushort = 0,
    sin6_port: u16 = 0,
    sin6_flowinfo: u32 = 0,
    sin6_addr: struct_in6_addr = .{},
    sin6_scope_id: u32 = 0,
};
pub const sockaddr_in6 = struct_sockaddr_in6;

// struct in_pktinfo — IP_PKTINFO ancillary data payload.
pub const struct_in_pktinfo = extern struct {
    ipi_ifindex: c_uint = 0,
    ipi_spec_dst: struct_in_addr = .{},
    ipi_addr: struct_in_addr = .{},
};
pub const in_pktinfo = struct_in_pktinfo;

// struct ipv6_mreq — IPV6_JOIN_GROUP payload.
pub const struct_ipv6_mreq = extern struct {
    ipv6mr_multiaddr: struct_in6_addr = .{},
    ipv6mr_interface: c_uint = 0,
};
pub const ipv6_mreq = struct_ipv6_mreq;

// struct iovec mirror (also in shmif_types; keep a local copy so libc
// consumers don't need to import shmif_types).
pub const struct_iovec_libc = struct_iovec;

// struct msghdr — recvmsg(2)/sendmsg(2) message header.
pub const struct_msghdr = if (is_darwin) extern struct {
    msg_name: ?*anyopaque = null,
    msg_namelen: c_uint = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    msg_iov: ?*struct_iovec = null,
    msg_iovlen: c_int = 0,
    _pad1: [4]u8 = .{ 0, 0, 0, 0 },
    msg_control: ?*anyopaque = null,
    msg_controllen: c_uint = 0,
    msg_flags: c_int = 0,
} else extern struct {
    msg_name: ?*anyopaque = null,
    msg_namelen: c_uint = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    msg_iov: ?*struct_iovec = null,
    msg_iovlen: usize = 0,
    msg_control: ?*anyopaque = null,
    msg_controllen: usize = 0,
    msg_flags: c_int = 0,
    _pad1: [4]u8 = .{ 0, 0, 0, 0 },
};
pub const msghdr = struct_msghdr;

// struct cmsghdr — ancillary control-message header.
pub const struct_cmsghdr = if (is_darwin) extern struct {
    cmsg_len: c_uint = 0,
    cmsg_level: c_int = 0,
    cmsg_type: c_int = 0,
} else extern struct {
    cmsg_len: usize = 0,
    cmsg_level: c_int = 0,
    cmsg_type: c_int = 0,
};
pub const cmsghdr = struct_cmsghdr;

pub extern "c" fn recvmsg(sockfd: c_int, msg: *struct_msghdr, flags: c_int) isize;
pub extern "c" fn sendmsg(sockfd: c_int, msg: *const struct_msghdr, flags: c_int) isize;
pub const MSG_DONTWAIT: c_int = if (is_darwin) 0x80 else 0x40;

// calloc / exit — additional stdlib entry points
pub extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;

// pid_t — process-id typedef, consolidated here so callers can route
// through the libc dispatch alias without double-importing shmif_types.
pub const pid_t = c_int;

// writev — vector I/O (sys/uio.h)
pub extern "c" fn writev(fd: c_int, iov: [*c]const struct_iovec, iovcnt: c_int) isize;
pub extern "c" fn readv(fd: c_int, iov: [*c]const struct_iovec, iovcnt: c_int) isize;

// termios.h — terminal settings
pub const struct_termios = if (is_darwin) extern struct {
    c_iflag: u64 = 0,
    c_oflag: u64 = 0,
    c_cflag: u64 = 0,
    c_lflag: u64 = 0,
    c_cc: [20]u8 = std.mem.zeroes([20]u8),
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    _c_ispeed: u64 = 0,
    _c_ospeed: u64 = 0,
} else extern struct {
    c_iflag: u32 = 0,
    c_oflag: u32 = 0,
    c_cflag: u32 = 0,
    c_lflag: u32 = 0,
    c_cc: [20]u8 = std.mem.zeroes([20]u8),
    _c_ispeed: u32 = 0,
    _c_ospeed: u32 = 0,
};
pub const termios = struct_termios;
pub const struct_winsize = extern struct {
    ws_row: c_ushort = 0,
    ws_col: c_ushort = 0,
    ws_xpixel: c_ushort = 0,
    ws_ypixel: c_ushort = 0,
};
pub const winsize = struct_winsize;

pub const TCSANOW: c_int = 0;
pub const VERASE: c_int = if (is_darwin) 3 else 2;
pub const IUTF8: c_uint = 0o040000;

pub extern "c" fn tcgetattr(fd: c_int, attr: *struct_termios) c_int;
pub extern "c" fn tcsetattr(fd: c_int, actions: c_int, attr: *const struct_termios) c_int;

// pty.h — pseudo-terminal helpers (glibc + musl via libutil)
pub extern "c" fn openpty(
    amaster: *c_int,
    aslave: *c_int,
    name: ?[*]u8,
    termp: ?*const struct_termios,
    winp: ?*const struct_winsize,
) c_int;
pub extern "c" fn forkpty(
    amaster: *c_int,
    name: ?[*]u8,
    termp: ?*const struct_termios,
    winp: ?*const struct_winsize,
) pid_t;

// stdlib.h pty management
pub extern "c" fn posix_openpt(flags: c_int) c_int;
pub extern "c" fn grantpt(fd: c_int) c_int;
pub extern "c" fn unlockpt(fd: c_int) c_int;
pub extern "c" fn ptsname(fd: c_int) [*c]u8;

// O_NOCTTY — fcntl flag for open/posix_openpt.
pub const O_NOCTTY: c_int = if (is_darwin) 0x20000 else 256;

// ioctl + tty control constants
pub extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
pub const TIOCSCTTY: c_ulong = if (is_darwin) 0x20007461 else 0x540E;
pub const TIOCSWINSZ: c_ulong = if (is_darwin) 0x80087467 else 0x5414;
pub const TIOCGWINSZ: c_ulong = if (is_darwin) 0x40087468 else 0x5413;
pub const TIOCSIG: c_ulong = 0x40045436;

// signal set + masking (signal.h)
pub const sigset_t = extern struct {
    _data: [16]c_ulong = std.mem.zeroes([16]c_ulong),
};
pub const SIG_BLOCK: c_int = 0;
pub const SIG_UNBLOCK: c_int = 1;
pub const SIG_SETMASK: c_int = 2;
pub const SIGUSR1: c_int = if (is_darwin) 30 else 10;
pub extern "c" fn sigemptyset(set: *sigset_t) c_int;
pub extern "c" fn sigfillset(set: *sigset_t) c_int;
pub extern "c" fn sigaddset(set: *sigset_t, signo: c_int) c_int;
pub extern "c" fn sigprocmask(how: c_int, set: ?*const sigset_t, oldset: ?*sigset_t) c_int;

// strsep — GNU string tokenizer used by resolve_path-style helpers.
pub extern "c" fn strsep(stringp: *[*c]u8, delim: [*c]const u8) [*c]u8;
