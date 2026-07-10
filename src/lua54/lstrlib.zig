const std = @import("std");
const c_builtins = std.zig.c_builtins;

// Builtin functions used by translated Lua code
pub const __builtin_bswap16 = c_builtins.__builtin_bswap16;
pub const __builtin_bswap32 = c_builtins.__builtin_bswap32;
pub const __builtin_bswap64 = c_builtins.__builtin_bswap64;
pub const __builtin_signbit = c_builtins.__builtin_signbit;
pub const __builtin_popcount = c_builtins.__builtin_popcount;
pub const __builtin_clz = c_builtins.__builtin_clz;
pub const __builtin_expect = c_builtins.__builtin_expect;
pub const __builtin_nanf = c_builtins.__builtin_nanf;
pub const __builtin_inff = c_builtins.__builtin_inff;
pub const __builtin_isnan = c_builtins.__builtin_isnan;
pub const __builtin_isinf = c_builtins.__builtin_isinf;
pub const __builtin_isinf_sign = c_builtins.__builtin_isinf_sign;

// Type aliases (C standard types used by extern declarations)
pub const ptrdiff_t = c_long;
pub const sig_atomic_t = c_int;
pub const wchar_t = c_uint;
pub const char16_t = c_ushort;
pub const char32_t = c_uint;
pub const errno_t = c_int;
pub const wint_t = c_uint;
pub const bool32 = c_int;
pub const intmax_t = c_long;
pub const uintmax_t = c_ulong;
pub const max_align_t = c_longdouble;

pub extern fn isatty(c_int) bool32;
pub extern fn getcwd([*c]u8, usize) [*c]u8;
pub extern fn realpath([*c]const u8, [*c]u8) [*c]u8;
pub extern fn ttyname(c_int) [*c]u8;
pub extern fn access([*c]const u8, c_int) c_int;
pub extern fn chdir([*c]const u8) c_int;
pub extern fn chmod([*c]const u8, c_uint) c_int;
pub extern fn chown([*c]const u8, c_uint, c_uint) c_int;
pub extern fn chroot([*c]const u8) c_int;
pub extern fn close(c_int) c_int;
pub extern fn creat([*c]const u8, c_uint) c_int;
pub extern fn dup(c_int) c_int;
pub extern fn dup2(c_int, c_int) c_int;
pub extern fn dup3(c_int, c_int, c_int) c_int;
pub extern fn execl([*c]const u8, [*c]const u8, ...) c_int;
pub extern fn execle([*c]const u8, [*c]const u8, ...) c_int;
pub extern fn execlp([*c]const u8, [*c]const u8, ...) c_int;
pub extern fn execv([*c]const u8, [*c]const [*c]u8) c_int;
pub extern fn execve([*c]const u8, [*c]const [*c]u8, [*c]const [*c]u8) c_int;
pub extern fn execvp([*c]const u8, [*c]const [*c]u8) c_int;
pub extern fn faccessat(c_int, [*c]const u8, c_int, c_int) c_int;
pub extern fn fchdir(c_int) c_int;
pub extern fn fchmod(c_int, c_uint) c_int;
pub extern fn fchmodat(c_int, [*c]const u8, c_uint, c_int) c_int;
pub extern fn fchown(c_int, c_uint, c_uint) c_int;
pub extern fn fchownat(c_int, [*c]const u8, c_uint, c_uint, c_int) c_int;
pub extern fn fdatasync(c_int) c_int;
pub extern fn fexecve(c_int, [*c]const [*c]u8, [*c]const [*c]u8) c_int;
pub extern fn flock(c_int, c_int) c_int;
pub extern fn fork() c_int;
pub extern fn fsync(c_int) c_int;
pub extern fn ftruncate(c_int, i64) c_int;
pub extern fn getdomainname([*c]u8, usize) c_int;
pub extern fn getgroups(c_int, [*c]c_uint) c_int;
pub extern fn gethostname([*c]u8, usize) c_int;
pub extern fn getloadavg([*c]f64, c_int) c_int;
pub extern fn getpgid(c_int) c_int;
pub extern fn getpgrp() c_int;
pub extern fn getpid() c_int;
pub extern fn getppid() c_int;
pub extern fn getpriority(c_int, c_uint) c_int;
pub extern fn getsid(c_int) c_int;
pub extern fn ioctl(c_int, c_ulong, ...) c_int;
pub extern fn issetugid() c_int;
pub extern fn kill(c_int, c_int) c_int;
pub extern fn killpg(c_int, c_int) c_int;
pub extern fn lchmod([*c]const u8, c_uint) c_int;
pub extern fn lchown([*c]const u8, c_uint, c_uint) c_int;
pub extern fn link([*c]const u8, [*c]const u8) c_int;
pub extern fn linkat(c_int, [*c]const u8, c_int, [*c]const u8, c_int) c_int;
pub extern fn mincore(?*anyopaque, usize, [*c]u8) c_int;
pub extern fn mkdir([*c]const u8, c_uint) c_int;
pub extern fn mkdirat(c_int, [*c]const u8, c_uint) c_int;
pub extern fn mknod([*c]const u8, c_uint, u64) c_int;
pub extern fn nice(c_int) c_int;
pub extern fn open([*c]const u8, c_int, ...) c_int;
pub extern fn openat(c_int, [*c]const u8, c_int, ...) c_int;
pub extern fn pause() c_int;
pub extern fn pipe([*c]c_int) c_int;
pub extern fn pipe2([*c]c_int, c_int) c_int;
pub extern fn posix_fadvise(c_int, i64, i64, c_int) c_int;
pub extern fn posix_madvise(?*anyopaque, u64, c_int) c_int;
pub extern fn raise(c_int) c_int;
pub extern fn reboot(c_int) c_int;
pub extern fn remove([*c]const u8) c_int;
pub extern fn rename([*c]const u8, [*c]const u8) c_int;
pub extern fn renameat(c_int, [*c]const u8, c_int, [*c]const u8) c_int;
pub extern fn rmdir([*c]const u8) c_int;
pub extern fn sched_yield() c_int;
pub extern fn setegid(c_uint) c_int;
pub extern fn seteuid(c_uint) c_int;
pub extern fn setfsgid(c_uint) c_int;
pub extern fn setfsuid(c_uint) c_int;
pub extern fn setgid(c_uint) c_int;
pub extern fn setgroups(usize, [*c]const c_uint) c_int;
pub extern fn setpgid(c_int, c_int) c_int;
pub extern fn setpgrp() c_int;
pub extern fn setpriority(c_int, c_uint, c_int) c_int;
pub extern fn setregid(c_uint, c_uint) c_int;
pub extern fn setreuid(c_uint, c_uint) c_int;
pub extern fn setsid() c_int;
pub extern fn setuid(c_uint) c_int;
pub extern fn shm_open([*c]const u8, c_int, c_uint) c_int;
pub extern fn shm_unlink([*c]const u8) c_int;
pub extern fn sigignore(c_int) c_int;
pub extern fn siginterrupt(c_int, c_int) c_int;
pub extern fn symlink([*c]const u8, [*c]const u8) c_int;
pub extern fn symlinkat([*c]const u8, c_int, [*c]const u8) c_int;
pub extern fn tcgetpgrp(c_int) c_int;
pub extern fn tcsetpgrp(c_int, c_int) c_int;
pub extern fn truncate([*c]const u8, i64) c_int;
pub extern fn ttyname_r(c_int, [*c]u8, usize) c_int;
pub extern fn unlink([*c]const u8) c_int;
pub extern fn unlinkat(c_int, [*c]const u8, c_int) c_int;
pub extern fn usleep(u64) c_int;
pub extern fn vfork() c_int;
pub extern fn wait([*c]c_int) c_int;
pub extern fn waitpid(c_int, [*c]c_int, c_int) c_int;
pub extern fn clock() i64;
pub extern fn time([*c]i64) i64;
pub extern fn copy_file_range(c_int, [*c]c_long, c_int, [*c]c_long, usize, c_uint) isize;
pub extern fn lseek(c_int, i64, c_int) isize;
pub extern fn pread(c_int, ?*anyopaque, usize, i64) isize;
pub extern fn pwrite(c_int, ?*const anyopaque, usize, i64) isize;
pub extern fn read(c_int, ?*anyopaque, usize) isize;
pub extern fn readlink([*c]const u8, [*c]u8, usize) isize;
pub extern fn readlinkat(c_int, [*c]const u8, [*c]u8, usize) isize;
pub extern fn write(c_int, ?*const anyopaque, usize) isize;
pub extern fn alarm(c_uint) c_uint;
pub extern fn getegid() c_uint;
pub extern fn geteuid() c_uint;
pub extern fn getgid() c_uint;
pub extern fn getuid() c_uint;
pub extern fn sleep(c_uint) c_uint;
pub extern fn ualarm(c_uint, c_uint) c_uint;
pub extern fn umask(c_uint) c_uint;
pub extern fn sync() void;
pub extern fn system([*c]const u8) c_int;
pub const struct_termios = extern struct {
    c_iflag: u32 = std.mem.zeroes(u32),
    c_oflag: u32 = std.mem.zeroes(u32),
    c_cflag: u32 = std.mem.zeroes(u32),
    c_lflag: u32 = std.mem.zeroes(u32),
    c_cc: [20]u8 = std.mem.zeroes([20]u8),
    _c_ispeed: u32 = std.mem.zeroes(u32),
    _c_ospeed: u32 = std.mem.zeroes(u32),
};
pub const struct_winsize = extern struct {
    ws_row: u16 = std.mem.zeroes(u16),
    ws_col: u16 = std.mem.zeroes(u16),
    ws_xpixel: u16 = std.mem.zeroes(u16),
    ws_ypixel: u16 = std.mem.zeroes(u16),
};
pub extern fn tcgetattr(c_int, [*c]struct_termios) c_int;
pub extern fn tcsetattr(c_int, c_int, [*c]const struct_termios) c_int;
pub extern fn openpty([*c]c_int, [*c]c_int, [*c]u8, [*c]const struct_termios, [*c]const struct_winsize) c_int;
pub extern fn forkpty([*c]c_int, [*c]u8, [*c]const struct_termios, [*c]const struct_winsize) c_int;
pub extern fn ptsname(c_int) [*c]u8;
pub extern fn ptsname_r(c_int, [*c]u8, usize) errno_t;
pub extern fn grantpt(c_int) c_int;
pub extern fn unlockpt(c_int) c_int;
pub extern fn posix_openpt(c_int) c_int;
pub extern fn tcdrain(c_int) c_int;
pub extern fn tcgetsid(c_int) c_int;
pub extern fn tcflow(c_int, c_int) c_int;
pub extern fn tcflush(c_int, c_int) c_int;
pub extern fn tcsetsid(c_int, c_int) c_int;
pub extern fn tcsendbreak(c_int, c_int) c_int;
pub extern fn cfmakeraw([*c]struct_termios) void;
pub extern fn cfsetspeed([*c]struct_termios, u32) c_int;
pub extern fn cfsetospeed([*c]struct_termios, u32) c_int;
pub extern fn cfsetispeed([*c]struct_termios, u32) c_int;
pub extern fn cfgetospeed([*c]const struct_termios) u32;
pub extern fn cfgetispeed([*c]const struct_termios) u32;
pub extern fn tcsetwinsize(c_int, [*c]const struct_winsize) c_int;
pub extern fn tcgetwinsize(c_int, [*c]struct_winsize) c_int;
pub extern fn abs(c_int) c_int;
pub extern fn labs(c_long) c_long;
pub extern fn llabs(c_longlong) c_longlong;
pub extern fn imaxabs(intmax_t) intmax_t;
pub extern fn atoi([*c]const u8) c_int;
pub extern fn atol([*c]const u8) c_long;
pub extern fn atoll([*c]const u8) c_longlong;
pub extern fn strtoul([*c]const u8, [*c][*c]u8, c_int) c_ulong;
pub extern fn strtoll([*c]const u8, [*c][*c]u8, c_int) c_longlong;
pub extern fn strtoull([*c]const u8, [*c][*c]u8, c_int) c_ulonglong;
pub extern fn strtoimax([*c]const u8, [*c][*c]u8, c_int) intmax_t;
pub extern fn strtoumax([*c]const u8, [*c][*c]u8, c_int) uintmax_t;
pub extern fn wcstoimax([*c]const wchar_t, [*c][*c]wchar_t, c_int) intmax_t;
pub extern fn wcstoumax([*c]const wchar_t, [*c][*c]wchar_t, c_int) uintmax_t;
pub extern fn wcstol([*c]const wchar_t, [*c][*c]wchar_t, c_int) c_long;
pub extern fn wcstoul([*c]const wchar_t, [*c][*c]wchar_t, c_int) c_ulong;
pub extern fn strtol([*c]const u8, [*c][*c]u8, c_int) c_long;
pub extern fn sizetol([*c]const u8, c_long) c_long;
pub extern fn sizefmt([*c]u8, u64, u64) [*c]u8;
pub extern fn wcstoll([*c]const wchar_t, [*c][*c]wchar_t, c_int) c_longlong;
pub extern fn wcstoull([*c]const wchar_t, [*c][*c]wchar_t, c_int) c_ulonglong;
pub extern fn wcscoll([*c]const wchar_t, [*c]const wchar_t) c_int;
pub extern fn wcsxfrm([*c]wchar_t, [*c]const wchar_t, usize) usize;
pub extern fn atof([*c]const u8) f64;
pub extern fn strtof([*c]const u8, [*c][*c]u8) f32;
pub extern fn strtod([*c]const u8, [*c][*c]u8) f64;
pub extern fn strtold([*c]const u8, [*c][*c]u8) c_longdouble;
pub extern fn wcstof([*c]const wchar_t, [*c][*c]wchar_t) f32;
pub extern fn wcstod([*c]const wchar_t, [*c][*c]wchar_t) f64;
pub extern fn wcstold([*c]const wchar_t, [*c][*c]wchar_t) c_longdouble;
pub const div_t = extern struct {
    quot: c_int = std.mem.zeroes(c_int),
    rem: c_int = std.mem.zeroes(c_int),
};
pub const ldiv_t = extern struct {
    quot: c_long = std.mem.zeroes(c_long),
    rem: c_long = std.mem.zeroes(c_long),
};
pub const lldiv_t = extern struct {
    quot: c_longlong = std.mem.zeroes(c_longlong),
    rem: c_longlong = std.mem.zeroes(c_longlong),
};
pub const imaxdiv_t = extern struct {
    quot: intmax_t = std.mem.zeroes(intmax_t),
    rem: intmax_t = std.mem.zeroes(intmax_t),
};
pub extern fn div(c_int, c_int) div_t;
pub extern fn ldiv(c_long, c_long) ldiv_t;
pub extern fn lldiv(c_longlong, c_longlong) lldiv_t;
pub extern fn imaxdiv(intmax_t, intmax_t) imaxdiv_t;
pub extern fn bsearch(?*const anyopaque, ?*const anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int) ?*anyopaque;
pub extern fn qsort(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int) void;
pub extern fn qsort_r(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, ?*anyopaque) void;
pub extern fn smoothsort(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int) void;
pub extern fn smoothsort_r(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, ?*anyopaque) void;
pub extern fn heapsort(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int) c_int;
pub extern fn heapsort_r(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, ?*anyopaque) c_int;
pub extern fn mergesort(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int) c_int;
pub extern fn mergesort_r(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, ?*anyopaque) c_int;
pub extern fn free(?*anyopaque) void;
pub extern fn malloc(c_ulong) ?*anyopaque;
pub extern fn calloc(c_ulong, c_ulong) ?*anyopaque;
pub extern fn memalign(c_ulong, c_ulong) ?*anyopaque;
pub extern fn realloc(?*anyopaque, c_ulong) ?*anyopaque;
pub extern fn realloc_in_place(?*anyopaque, usize) ?*anyopaque;
pub extern fn reallocarray(?*anyopaque, usize, usize) ?*anyopaque;
pub extern fn valloc(usize) ?*anyopaque;
pub extern fn pvalloc(usize) ?*anyopaque;
pub extern fn strdup([*c]const u8) [*c]u8;
pub extern fn strndup([*c]const u8, c_ulong) [*c]u8;
pub extern fn aligned_alloc(c_ulong, c_ulong) ?*anyopaque;
pub extern fn posix_memalign([*c]?*anyopaque, usize, usize) c_int;
pub extern fn mallopt(c_int, c_int) c_int;
pub extern fn malloc_trim(usize) c_int;
pub extern fn malloc_usable_size(?*anyopaque) usize;
pub extern fn wcsdup([*c]const wchar_t) [*c]wchar_t;
pub const struct_mallinfo = extern struct {
    arena: usize = std.mem.zeroes(usize),
    ordblks: usize = std.mem.zeroes(usize),
    smblks: usize = std.mem.zeroes(usize),
    hblks: usize = std.mem.zeroes(usize),
    hblkhd: usize = std.mem.zeroes(usize),
    usmblks: usize = std.mem.zeroes(usize),
    fsmblks: usize = std.mem.zeroes(usize),
    uordblks: usize = std.mem.zeroes(usize),
    fordblks: usize = std.mem.zeroes(usize),
    keepcost: usize = std.mem.zeroes(usize),
};
pub extern fn mallinfo() struct_mallinfo;
pub const jmp_buf = [22]c_long;
pub const sigjmp_buf = [25]c_long;
pub extern fn mcount() void;
pub extern fn daemon(c_int, c_int) c_int;
pub extern fn getauxval(c_ulong) c_ulong;
pub extern fn setjmp([*c]c_long) c_int;
pub extern fn longjmp([*c]c_long, c_int) noreturn;
pub extern fn _setjmp([*c]c_long) c_int;
pub extern fn sigsetjmp([*c]c_long, c_int) c_int;
pub extern fn siglongjmp([*c]c_long, c_int) noreturn;
pub extern fn _longjmp([*c]c_long, c_int) noreturn;
pub extern fn exit(c_int) noreturn;
pub extern fn _exit(c_int) noreturn;
pub extern fn _Exit(c_int) noreturn;
pub extern fn quick_exit(c_int) noreturn;
pub extern fn abort() noreturn;
pub extern fn atexit(?*const fn () callconv(.c) void) c_int;
pub extern fn getenv([*c]const u8) [*c]u8;
pub extern fn putenv([*c]u8) c_int;
pub extern fn setenv([*c]const u8, [*c]const u8, c_int) c_int;
pub extern fn unsetenv([*c]const u8) c_int;
pub extern fn clearenv() c_int;
pub extern fn fpreset() void;
pub extern fn mmap(?*anyopaque, u64, i32, i32, i32, i64) ?*anyopaque;
pub extern fn cosmo_mremap(?*anyopaque, usize, usize, c_int, ...) ?*anyopaque;
pub extern fn munmap(?*anyopaque, u64) c_int;
pub extern fn mprotect(?*anyopaque, u64, c_int) c_int;
pub extern fn msync(?*anyopaque, usize, c_int) c_int;
pub extern fn mlock(?*const anyopaque, usize) c_int;
pub extern fn munlock(?*const anyopaque, usize) c_int;
pub extern fn getlogin() [*c]u8;
pub extern fn getlogin_r([*c]u8, usize) c_int;
pub extern fn login_tty(c_int) c_int;
pub extern fn getpagesize() c_int;
pub extern fn getgransize() c_int;
pub extern fn syncfs(c_int) c_int;
pub extern fn vhangup() c_int;
pub extern fn getdtablesize() c_int;
pub extern fn sethostname([*c]const u8, usize) c_int;
pub extern fn acct([*c]const u8) c_int;
pub extern fn dprintf(c_int, [*c]const u8, ...) c_int;
pub const struct___va_list_1 = extern struct {
    __stack: ?*anyopaque = std.mem.zeroes(?*anyopaque),
    __gr_top: ?*anyopaque = std.mem.zeroes(?*anyopaque),
    __vr_top: ?*anyopaque = std.mem.zeroes(?*anyopaque),
    __gr_offs: c_int = std.mem.zeroes(c_int),
    __vr_offs: c_int = std.mem.zeroes(c_int),
};
pub const __builtin_va_list = struct___va_list_1;
pub extern fn vdprintf(c_int, [*c]const u8, __builtin_va_list) c_int;
pub extern fn rand() c_int;
pub extern fn srand(c_uint) void;
pub extern fn strfry([*c]u8) [*c]u8;
pub extern fn getentropy(?*anyopaque, usize) c_int;
pub extern fn getrandom(?*anyopaque, usize, c_uint) isize;
pub extern fn initstate(c_uint, [*c]u8, usize) [*c]u8;
pub extern fn setstate([*c]u8) [*c]u8;
pub extern fn random() c_long;
pub extern fn srandom(c_uint) void;
pub extern fn rand_r([*c]c_uint) c_int;
pub extern fn fcvt(f64, c_int, [*c]c_int, [*c]c_int) [*c]u8;
pub extern fn ecvt(f64, c_int, [*c]c_int, [*c]c_int) [*c]u8;
pub extern fn gcvt(f64, c_int, [*c]u8) [*c]u8;
pub extern fn at_quick_exit(?*const fn () callconv(.c) void) c_int;
pub extern fn memset(?*anyopaque, c_int, c_ulong) ?*anyopaque;
pub extern fn memmove(?*anyopaque, ?*const anyopaque, c_ulong) ?*anyopaque;
pub extern fn memcpy(?*anyopaque, ?*const anyopaque, c_ulong) ?*anyopaque;
pub extern fn hexpcpy([*c]u8, ?*const anyopaque, usize) [*c]u8;
pub extern fn memcmp(?*const anyopaque, ?*const anyopaque, c_ulong) c_int;
pub extern fn timingsafe_bcmp(?*const anyopaque, ?*const anyopaque, usize) c_int;
pub extern fn timingsafe_memcmp(?*const anyopaque, ?*const anyopaque, usize) c_int;
pub extern fn strlen([*c]const u8) c_ulong;
pub extern fn strnlen([*c]const u8, usize) usize;
pub extern fn strnlen_s([*c]const u8, usize) usize;
pub extern fn strchr([*c]const u8, c_int) [*c]u8;
pub extern fn memchr(?*const anyopaque, c_int, c_ulong) ?*anyopaque;
pub extern fn rawmemchr(?*const anyopaque, c_int) ?*anyopaque;
pub extern fn wcslen([*c]const c_uint) c_ulong;
pub extern fn wcsnlen([*c]const wchar_t, usize) usize;
pub extern fn wcsnlen_s([*c]const wchar_t, usize) usize;
pub extern fn wcschr([*c]const c_uint, c_uint) [*c]c_uint;
pub extern fn wmemchr([*c]const c_uint, c_uint, c_ulong) [*c]c_uint;
pub extern fn wcschrnul([*c]const wchar_t, wchar_t) [*c]wchar_t;
pub extern fn strstr([*c]const u8, [*c]const u8) [*c]u8;
pub extern fn wcsstr([*c]const wchar_t, [*c]const wchar_t) [*c]wchar_t;
pub extern fn strcmp([*c]const u8, [*c]const u8) c_int;
pub extern fn strncmp([*c]const u8, [*c]const u8, c_ulong) c_int;
pub extern fn wcscmp([*c]const c_uint, [*c]const c_uint) c_int;
pub extern fn wcsncmp([*c]const c_uint, [*c]const c_uint, c_ulong) c_int;
pub extern fn wmemcmp([*c]const c_uint, [*c]const c_uint, c_ulong) c_int;
pub extern fn strcasecmp([*c]const u8, [*c]const u8) c_int;
pub extern fn wcscasecmp([*c]const wchar_t, [*c]const wchar_t) c_int;
pub extern fn strncasecmp([*c]const u8, [*c]const u8, c_ulong) c_int;
pub extern fn wcsncasecmp([*c]const wchar_t, [*c]const wchar_t, usize) c_int;
pub extern fn strrchr([*c]const u8, c_int) [*c]u8;
pub extern fn wcsrchr([*c]const wchar_t, wchar_t) [*c]wchar_t;
pub extern fn strpbrk([*c]const u8, [*c]const u8) [*c]u8;
pub extern fn wcspbrk([*c]const wchar_t, [*c]const wchar_t) [*c]wchar_t;
pub extern fn strspn([*c]const u8, [*c]const u8) c_ulong;
pub extern fn wcsspn([*c]const wchar_t, [*c]const wchar_t) usize;
pub extern fn strcspn([*c]const u8, [*c]const u8) c_ulong;
pub extern fn wcscspn([*c]const wchar_t, [*c]const wchar_t) usize;
pub extern fn memfrob(?*anyopaque, usize) ?*anyopaque;
pub extern fn strcoll([*c]const u8, [*c]const u8) c_int;
pub extern fn stpcpy([*c]u8, [*c]const u8) [*c]u8;
pub extern fn stpncpy([*c]u8, [*c]const u8, c_ulong) [*c]u8;
pub extern fn strcat([*c]u8, [*c]const u8) [*c]u8;
pub extern fn wcscat([*c]wchar_t, [*c]const wchar_t) [*c]wchar_t;
pub extern fn strxfrm([*c]u8, [*c]const u8, c_ulong) c_ulong;
pub extern fn strcpy([*c]u8, [*c]const u8) [*c]u8;
pub extern fn wcscpy([*c]wchar_t, [*c]const wchar_t) [*c]wchar_t;
pub extern fn strncat([*c]u8, [*c]const u8, c_ulong) [*c]u8;
pub extern fn wcsncat([*c]wchar_t, [*c]const wchar_t, usize) [*c]wchar_t;
pub extern fn strncpy([*c]u8, [*c]const u8, c_ulong) [*c]u8;
pub extern fn strtok([*c]u8, [*c]const u8) [*c]u8;
pub extern fn strtok_r([*c]u8, [*c]const u8, [*c][*c]u8) [*c]u8;
pub extern fn wcstok([*c]wchar_t, [*c]const wchar_t, [*c][*c]wchar_t) [*c]wchar_t;
pub extern fn wmemset([*c]wchar_t, wchar_t, usize) [*c]wchar_t;
pub extern fn wmemcpy([*c]c_uint, [*c]const c_uint, c_ulong) [*c]c_uint;
pub extern fn wmemmove([*c]c_uint, [*c]const c_uint, c_ulong) [*c]c_uint;
pub extern fn strfmon([*c]u8, usize, [*c]const u8, ...) isize;
pub extern fn a64l([*c]const u8) c_long;
pub extern fn l64a(c_long) [*c]u8;
pub const mbstate_t = c_uint;
pub extern fn wcsncpy([*c]wchar_t, [*c]const wchar_t, usize) [*c]wchar_t;
pub extern fn mbtowc([*c]wchar_t, [*c]const u8, usize) c_int;
pub extern fn mbrtowc([*c]wchar_t, [*c]const u8, usize, [*c]mbstate_t) usize;
pub extern fn mbsrtowcs([*c]wchar_t, [*c][*c]const u8, usize, [*c]mbstate_t) usize;
pub extern fn mbstowcs([*c]wchar_t, [*c]const u8, usize) usize;
pub extern fn wcrtomb([*c]u8, wchar_t, [*c]mbstate_t) usize;
pub extern fn c32rtomb([*c]u8, char32_t, [*c]mbstate_t) usize;
pub extern fn mbrtoc32([*c]char32_t, [*c]const u8, usize, [*c]mbstate_t) usize;
pub extern fn c16rtomb([*c]u8, char16_t, [*c]mbstate_t) usize;
pub extern fn mbrtoc16([*c]char16_t, [*c]const u8, usize, [*c]mbstate_t) usize;
pub extern fn mbrlen([*c]const u8, usize, [*c]mbstate_t) usize;
pub extern fn mbsnrtowcs([*c]wchar_t, [*c][*c]const u8, usize, usize, [*c]mbstate_t) usize;
pub extern fn wcsnrtombs([*c]u8, [*c][*c]const wchar_t, usize, usize, [*c]mbstate_t) usize;
pub extern fn wcsrtombs([*c]u8, [*c][*c]const wchar_t, usize, [*c]mbstate_t) usize;
pub extern fn wcstombs([*c]u8, [*c]const wchar_t, usize) usize;
pub extern fn mbsinit([*c]const mbstate_t) c_int;
pub extern fn mblen([*c]const u8, usize) c_int;
pub extern fn wctomb([*c]u8, wchar_t) c_int;
pub extern fn wctob(wint_t) c_int;
pub extern fn btowc(c_int) wint_t;
pub extern fn getsubopt([*c][*c]u8, [*c]const [*c]u8, [*c][*c]u8) c_int;
pub extern fn strsignal(c_int) [*c]u8;
pub extern fn strerror(c_int) [*c]u8;
pub extern fn strerror_r(c_int, [*c]u8, usize) errno_t;
pub extern fn __xpg_strerror_r(c_int, [*c]u8, usize) [*c]u8;
pub extern fn bcmp(?*const anyopaque, ?*const anyopaque, c_ulong) c_int;
pub extern fn bcopy(?*const anyopaque, ?*anyopaque, c_ulong) void;
pub extern fn bzero(?*anyopaque, c_ulong) void;
pub extern fn index([*c]const u8, c_int) [*c]u8;
pub extern fn rindex([*c]const u8, c_int) [*c]u8;
pub extern fn mktemp([*c]u8) [*c]u8;
pub extern fn mkdtemp([*c]u8) [*c]u8;
pub extern fn mkstemp([*c]u8) c_int;
pub extern fn mkstemps([*c]u8, c_int) c_int;
pub extern fn drand48() f64;
pub extern fn erand48([*c]c_ushort) f64;
pub extern fn lrand48() c_long;
pub extern fn nrand48([*c]c_ushort) c_long;
pub extern fn mrand48() c_long;
pub extern fn jrand48([*c]c_ushort) c_long;
pub extern fn srand48(c_long) void;
pub extern fn seed48([*c]c_ushort) [*c]c_ushort;
pub extern fn lcong48([*c]c_ushort) void;
pub extern fn __assert_fail([*c]const u8, [*c]const u8, c_int) void;
pub extern fn unassert([*c]const u8, [*c]const u8, c_int) void;
pub const float_t = f32;
pub const double_t = f64;
pub extern var signgam: c_int;
pub extern fn acos(f64) f64;
pub extern fn acosh(f64) f64;
pub extern fn asin(f64) f64;
pub extern fn asinh(f64) f64;
pub extern fn atan(f64) f64;
pub extern fn atan2(f64, f64) f64;
pub extern fn atanh(f64) f64;
pub extern fn cbrt(f64) f64;
pub extern fn ceil(f64) f64;
pub extern fn copysign(f64, f64) f64;
pub extern fn cos(f64) f64;
pub extern fn cosh(f64) f64;
pub extern fn drem(f64, f64) f64;
pub extern fn erf(f64) f64;
pub extern fn erfc(f64) f64;
pub extern fn exp(f64) f64;
pub extern fn exp10(f64) f64;
pub extern fn exp2(f64) f64;
pub extern fn expm1(f64) f64;
pub extern fn fabs(f64) f64;
pub extern fn fdim(f64, f64) f64;
pub extern fn floor(f64) f64;
pub extern fn fma(f64, f64, f64) f64;
pub extern fn fmax(f64, f64) f64;
pub extern fn fmin(f64, f64) f64;
pub extern fn fmod(f64, f64) f64;
pub extern fn hypot(f64, f64) f64;
pub extern fn ldexp(f64, c_int) f64;
pub extern fn log(f64) f64;
pub extern fn log10(f64) f64;
pub extern fn log1p(f64) f64;
pub extern fn log2(f64) f64;
pub extern fn logb(f64) f64;
pub extern fn nearbyint(f64) f64;
pub extern fn nextafter(f64, f64) f64;
pub extern fn nexttoward(f64, c_longdouble) f64;
pub extern fn pow(f64, f64) f64;
pub extern fn pow10(f64) f64;
pub extern fn powi(f64, c_int) f64;
pub extern fn remainder(f64, f64) f64;
pub extern fn rint(f64) f64;
pub extern fn round(f64) f64;
pub extern fn scalb(f64, f64) f64;
pub extern fn scalbln(f64, c_long) f64;
pub extern fn scalbn(f64, c_int) f64;
pub extern fn significand(f64) f64;
pub extern fn sin(f64) f64;
pub extern fn sinh(f64) f64;
pub extern fn sqrt(f64) f64;
pub extern fn tan(f64) f64;
pub extern fn tanh(f64) f64;
pub extern fn trunc(f64) f64;
pub extern fn tgamma(f64) f64;
pub extern fn lgamma(f64) f64;
pub extern fn lgamma_r(f64, [*c]c_int) f64;
pub extern fn finite(f64) c_int;
pub extern fn acosf(f32) f32;
pub extern fn acoshf(f32) f32;
pub extern fn asinf(f32) f32;
pub extern fn asinhf(f32) f32;
pub extern fn atan2f(f32, f32) f32;
pub extern fn atanf(f32) f32;
pub extern fn atanhf(f32) f32;
pub extern fn cbrtf(f32) f32;
pub extern fn ceilf(f32) f32;
pub extern fn copysignf(f32, f32) f32;
pub extern fn cosf(f32) f32;
pub extern fn coshf(f32) f32;
pub extern fn dremf(f32, f32) f32;
pub extern fn erfcf(f32) f32;
pub extern fn erff(f32) f32;
pub extern fn exp10f(f32) f32;
pub extern fn exp2f(f32) f32;
pub extern fn expf(f32) f32;
pub extern fn expm1f(f32) f32;
pub extern fn fabsf(f32) f32;
pub extern fn fdimf(f32, f32) f32;
pub extern fn floorf(f32) f32;
pub extern fn fmaf(f32, f32, f32) f32;
pub extern fn fmaxf(f32, f32) f32;
pub extern fn fminf(f32, f32) f32;
pub extern fn fmodf(f32, f32) f32;
pub extern fn hypotf(f32, f32) f32;
pub extern fn ldexpf(f32, c_int) f32;
pub extern fn lgammaf(f32) f32;
pub extern fn lgammaf_r(f32, [*c]c_int) f32;
pub extern fn log10f(f32) f32;
pub extern fn log1pf(f32) f32;
pub extern fn log2f(f32) f32;
pub extern fn logbf(f32) f32;
pub extern fn logf(f32) f32;
pub extern fn nearbyintf(f32) f32;
pub extern fn nextafterf(f32, f32) f32;
pub extern fn nexttowardf(f32, c_longdouble) f32;
pub extern fn pow10f(f32) f32;
pub extern fn powf(f32, f32) f32;
pub extern fn powif(f32, c_int) f32;
pub extern fn remainderf(f32, f32) f32;
pub extern fn rintf(f32) f32;
pub extern fn roundf(f32) f32;
pub extern fn scalbf(f32, f32) f32;
pub extern fn scalblnf(f32, c_long) f32;
pub extern fn scalbnf(f32, c_int) f32;
pub extern fn significandf(f32) f32;
pub extern fn sinf(f32) f32;
pub extern fn sinhf(f32) f32;
pub extern fn sqrtf(f32) f32;
pub extern fn tanf(f32) f32;
pub extern fn tanhf(f32) f32;
pub extern fn tgammaf(f32) f32;
pub extern fn truncf(f32) f32;
pub extern fn finitef(f32) c_int;
pub extern fn finitel(c_longdouble) c_int;
pub extern fn acoshl(c_longdouble) c_longdouble;
pub extern fn acosl(c_longdouble) c_longdouble;
pub extern fn asinhl(c_longdouble) c_longdouble;
pub extern fn asinl(c_longdouble) c_longdouble;
pub extern fn atan2l(c_longdouble, c_longdouble) c_longdouble;
pub extern fn atanhl(c_longdouble) c_longdouble;
pub extern fn atanl(c_longdouble) c_longdouble;
pub extern fn cbrtl(c_longdouble) c_longdouble;
pub extern fn ceill(c_longdouble) c_longdouble;
pub extern fn copysignl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn coshl(c_longdouble) c_longdouble;
pub extern fn cosl(c_longdouble) c_longdouble;
pub extern fn dreml(c_longdouble, c_longdouble) c_longdouble;
pub extern fn erfcl(c_longdouble) c_longdouble;
pub extern fn erfl(c_longdouble) c_longdouble;
pub extern fn exp10l(c_longdouble) c_longdouble;
pub extern fn exp2l(c_longdouble) c_longdouble;
pub extern fn expl(c_longdouble) c_longdouble;
pub extern fn expm1l(c_longdouble) c_longdouble;
pub extern fn fabsl(c_longdouble) c_longdouble;
pub extern fn fdiml(c_longdouble, c_longdouble) c_longdouble;
pub extern fn floorl(c_longdouble) c_longdouble;
pub extern fn fmal(c_longdouble, c_longdouble, c_longdouble) c_longdouble;
pub extern fn fmaxl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn fminl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn fmodl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn hypotl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn ldexpl(c_longdouble, c_int) c_longdouble;
pub extern fn lgammal(c_longdouble) c_longdouble;
pub extern fn lgammal_r(c_longdouble, [*c]c_int) c_longdouble;
pub extern fn log10l(c_longdouble) c_longdouble;
pub extern fn log1pl(c_longdouble) c_longdouble;
pub extern fn log2l(c_longdouble) c_longdouble;
pub extern fn logbl(c_longdouble) c_longdouble;
pub extern fn logl(c_longdouble) c_longdouble;
pub extern fn nearbyintl(c_longdouble) c_longdouble;
pub extern fn nextafterl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn nexttowardl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn pow10l(c_longdouble) c_longdouble;
pub extern fn powl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn remainderl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn rintl(c_longdouble) c_longdouble;
pub extern fn roundl(c_longdouble) c_longdouble;
pub extern fn scalbl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn scalblnl(c_longdouble, c_long) c_longdouble;
pub extern fn scalbnl(c_longdouble, c_int) c_longdouble;
pub extern fn significandl(c_longdouble) c_longdouble;
pub extern fn sinhl(c_longdouble) c_longdouble;
pub extern fn sinl(c_longdouble) c_longdouble;
pub extern fn sqrtl(c_longdouble) c_longdouble;
pub extern fn tanhl(c_longdouble) c_longdouble;
pub extern fn tanl(c_longdouble) c_longdouble;
pub extern fn tgammal(c_longdouble) c_longdouble;
pub extern fn truncl(c_longdouble) c_longdouble;
pub extern fn lrint(f64) c_long;
pub extern fn lrintf(f32) c_long;
pub extern fn lrintl(c_longdouble) c_long;
pub extern fn lround(f64) c_long;
pub extern fn lroundf(f32) c_long;
pub extern fn lroundl(c_longdouble) c_long;
pub extern fn ilogbf(f32) c_int;
pub extern fn ilogb(f64) c_int;
pub extern fn ilogbl(c_longdouble) c_int;
pub extern fn llrint(f64) c_longlong;
pub extern fn llrintf(f32) c_longlong;
pub extern fn llrintl(c_longdouble) c_longlong;
pub extern fn llround(f64) c_longlong;
pub extern fn llroundf(f32) c_longlong;
pub extern fn llroundl(c_longdouble) c_longlong;
pub extern fn frexp(f64, [*c]c_int) f64;
pub extern fn modf(f64, [*c]f64) f64;
pub extern fn nan([*c]const u8) f64;
pub extern fn remquo(f64, f64, [*c]c_int) f64;
pub extern fn frexpf(f32, [*c]c_int) f32;
pub extern fn modff(f32, [*c]f32) f32;
pub extern fn nanf([*c]const u8) f32;
pub extern fn remquof(f32, f32, [*c]c_int) f32;
pub extern fn frexpl(c_longdouble, [*c]c_int) c_longdouble;
pub extern fn modfl(c_longdouble, [*c]c_longdouble) c_longdouble;
pub extern fn nanl([*c]const u8) c_longdouble;
pub extern fn remquol(c_longdouble, c_longdouble, [*c]c_int) c_longdouble;
pub extern fn sincos(f64, [*c]f64, [*c]f64) void;
pub extern fn sincosf(f32, [*c]f32, [*c]f32) void;
pub extern fn sincosl(c_longdouble, [*c]c_longdouble, [*c]c_longdouble) void;
pub extern fn fsumf([*c]const f32, usize) f64;
pub extern fn fsum([*c]const f64, usize) f64;
pub extern fn j0(f64) f64;
pub extern fn j1(f64) f64;
pub extern fn jn(c_int, f64) f64;
pub extern fn j0f(f32) f32;
pub extern fn j1f(f32) f32;
pub extern fn jnf(c_int, f32) f32;
pub extern fn y0(f64) f64;
pub extern fn y1(f64) f64;
pub extern fn yn(c_int, f64) f64;
pub extern fn y0f(f32) f32;
pub extern fn y1f(f32) f32;
pub extern fn ynf(c_int, f32) f32;
pub const struct_tm = extern struct {
    tm_sec: i32 = std.mem.zeroes(i32),
    tm_min: i32 = std.mem.zeroes(i32),
    tm_hour: i32 = std.mem.zeroes(i32),
    tm_mday: i32 = std.mem.zeroes(i32),
    tm_mon: i32 = std.mem.zeroes(i32),
    tm_year: i32 = std.mem.zeroes(i32),
    tm_wday: i32 = std.mem.zeroes(i32),
    tm_yday: i32 = std.mem.zeroes(i32),
    tm_isdst: i32 = std.mem.zeroes(i32),
    tm_gmtoff: i64 = std.mem.zeroes(i64),
    tm_zone: [*c]const u8 = std.mem.zeroes([*c]const u8),
};
pub const struct_timezone = extern struct {
    tz_minuteswest: i32 = std.mem.zeroes(i32),
    tz_dsttime: i32 = std.mem.zeroes(i32),
};
pub extern var tzname: [2][*c]u8;
pub extern var timezone: c_long;
pub extern var daylight: c_int;
pub extern fn tzset() void;
pub extern fn asctime([*c]const struct_tm) [*c]u8;
pub extern fn asctime_r([*c]const struct_tm, [*c]u8) [*c]u8;
pub extern fn strptime([*c]const u8, [*c]const u8, [*c]struct_tm) [*c]u8;
pub extern fn mktime([*c]struct_tm) i64;
pub extern fn timegm([*c]struct_tm) i64;
pub extern fn timelocal([*c]struct_tm) i64;
pub extern fn timeoff([*c]struct_tm, c_long) i64;
pub extern fn strftime([*c]u8, usize, [*c]const u8, [*c]const struct_tm) usize;
pub extern fn wcsftime([*c]wchar_t, usize, [*c]const wchar_t, [*c]const struct_tm) usize;
pub extern fn gmtime([*c]const i64) [*c]struct_tm;
pub extern fn gmtime_r([*c]const i64, [*c]struct_tm) [*c]struct_tm;
pub extern fn localtime([*c]const i64) [*c]struct_tm;
pub extern fn localtime_r([*c]const i64, [*c]struct_tm) [*c]struct_tm;
pub extern fn ctime([*c]const i64) [*c]u8;
pub extern fn ctime_r([*c]const i64, [*c]u8) [*c]u8;
pub extern fn difftime(i64, i64) f64;
pub extern fn stime([*c]const i64) c_int;
pub const struct_HttpSlice = extern struct {
    a: c_short = std.mem.zeroes(c_short),
    b: c_short = std.mem.zeroes(c_short),
};
pub const struct_HttpHeader = extern struct {
    k: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    v: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
};
pub const struct_HttpHeaders = extern struct {
    n: c_uint = std.mem.zeroes(c_uint),
    c: c_uint = std.mem.zeroes(c_uint),
    p: [*c]struct_HttpHeader = std.mem.zeroes([*c]struct_HttpHeader),
};
pub const struct_HttpMessage = extern struct {
    i: c_int = std.mem.zeroes(c_int),
    a: c_int = std.mem.zeroes(c_int),
    status: c_int = std.mem.zeroes(c_int),
    t: u8 = std.mem.zeroes(u8),
    type: u8 = std.mem.zeroes(u8),
    version: u8 = std.mem.zeroes(u8),
    method: u64 = std.mem.zeroes(u64),
    k: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    uri: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    scratch: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    message: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    headers: [93]struct_HttpSlice = std.mem.zeroes([93]struct_HttpSlice),
    xheaders: struct_HttpHeaders = std.mem.zeroes(struct_HttpHeaders),
};
pub const struct_HttpUnchunker = extern struct {
    t: c_int = std.mem.zeroes(c_int),
    i: usize = std.mem.zeroes(usize),
    j: usize = std.mem.zeroes(usize),
    m: isize = std.mem.zeroes(isize),
};
pub extern const kHttpToken: [256]u8;
pub extern const kHttpRepeatable: [93]u8;
pub extern fn GetHttpReason(c_int) [*c]const u8;
pub extern fn GetHttpHeaderName(c_int) [*c]const u8;
pub extern fn GetHttpHeader([*c]const u8, usize) c_int;
pub extern fn InitHttpMessage([*c]struct_HttpMessage, c_int) void;
pub extern fn DestroyHttpMessage([*c]struct_HttpMessage) void;
pub extern fn ResetHttpMessage([*c]struct_HttpMessage, c_int) void;
pub extern fn ParseHttpMessage([*c]struct_HttpMessage, [*c]const u8, usize, usize) c_int;
pub extern fn HeaderHas([*c]struct_HttpMessage, [*c]const u8, c_int, [*c]const u8, usize) bool32;
pub extern fn ParseContentLength([*c]const u8, usize) i64;
pub extern fn FormatHttpDateTime([*c]u8, [*c]struct_tm) [*c]u8;
pub extern fn ParseHttpRange([*c]const u8, usize, c_long, [*c]c_long, [*c]c_long) bool32;
pub extern fn ParseHttpDateTime([*c]const u8, usize) i64;
pub extern fn ParseHttpMethod([*c]const u8, usize) u64;
pub extern fn IsValidHttpToken([*c]const u8, usize) bool32;
pub extern fn IsValidCookieValue([*c]const u8, usize) bool32;
pub extern fn IsAcceptablePath([*c]const u8, usize) bool32;
pub extern fn IsAcceptableHost([*c]const u8, usize) bool32;
pub extern fn IsAcceptablePort([*c]const u8, usize) bool32;
pub extern fn IsReasonablePath([*c]const u8, usize) bool32;
pub extern fn ParseForwarded([*c]const u8, usize, [*c]u32, [*c]u16) c_int;
pub extern fn IsMimeType([*c]const u8, usize, [*c]const u8) bool32;
pub extern fn Unchunk([*c]struct_HttpUnchunker, [*c]u8, usize, [*c]usize) isize;
pub extern fn FindContentType([*c]const u8, usize) [*c]const u8;
pub extern fn IsNoCompressExt([*c]const u8, usize) bool32;
pub extern fn FoldHeader([*c]struct_HttpMessage, [*c]const u8, c_int, [*c]usize) [*c]u8;
pub const struct_UrlView = extern struct {
    n: usize = std.mem.zeroes(usize),
    p: [*c]u8 = std.mem.zeroes([*c]u8),
};
pub const struct_UrlParam_2 = extern struct {
    key: struct_UrlView = std.mem.zeroes(struct_UrlView),
    val: struct_UrlView = std.mem.zeroes(struct_UrlView),
};
pub const struct_UrlParams = extern struct {
    n: usize = std.mem.zeroes(usize),
    p: [*c]struct_UrlParam_2 = std.mem.zeroes([*c]struct_UrlParam_2),
};
pub const struct_Url = extern struct {
    scheme: struct_UrlView = std.mem.zeroes(struct_UrlView),
    user: struct_UrlView = std.mem.zeroes(struct_UrlView),
    pass: struct_UrlView = std.mem.zeroes(struct_UrlView),
    host: struct_UrlView = std.mem.zeroes(struct_UrlView),
    port: struct_UrlView = std.mem.zeroes(struct_UrlView),
    path: struct_UrlView = std.mem.zeroes(struct_UrlView),
    params: struct_UrlParams = std.mem.zeroes(struct_UrlParams),
    fragment: struct_UrlView = std.mem.zeroes(struct_UrlView),
};
pub extern fn EncodeUrl([*c]struct_Url, [*c]usize) [*c]u8;
pub extern fn ParseUrl([*c]const u8, usize, [*c]struct_Url, c_int) [*c]u8;
pub extern fn ParseParams([*c]const u8, usize, [*c]struct_UrlParams) [*c]u8;
pub extern fn ParseHost([*c]const u8, usize, [*c]struct_Url) [*c]u8;
pub extern fn EscapeUrlView([*c]u8, [*c]struct_UrlView, [*c]const u8) [*c]u8;
pub const struct_FILE = opaque {};
pub const FILE = struct_FILE;
pub extern var stdin: ?*FILE;
pub extern var stdout: ?*FILE;
pub extern var stderr: ?*FILE;
pub extern fn ferror(?*FILE) errno_t;
pub extern fn clearerr(?*FILE) void;
pub extern fn feof(?*FILE) c_int;
pub extern fn getc(?*FILE) c_int;
pub extern fn putc(c_int, ?*FILE) c_int;
pub extern fn fflush(?*FILE) c_int;
pub extern fn fpurge(?*FILE) c_int;
pub extern fn fgetc(?*FILE) c_int;
pub extern fn fgetln(?*FILE, [*c]usize) [*c]u8;
pub extern fn ungetc(c_int, ?*FILE) c_int;
pub extern fn fileno(?*FILE) c_int;
pub extern fn fputc(c_int, ?*FILE) c_int;
pub extern fn fputs([*c]const u8, ?*FILE) c_int;
pub extern fn fputws([*c]const wchar_t, ?*FILE) c_int;
pub extern fn flockfile(?*FILE) void;
pub extern fn funlockfile(?*FILE) void;
pub extern fn ftrylockfile(?*FILE) c_int;
pub extern fn fgets([*c]u8, c_int, ?*FILE) [*c]u8;
pub extern fn fgetws([*c]wchar_t, c_int, ?*FILE) [*c]wchar_t;
pub extern fn putwc(wchar_t, ?*FILE) wint_t;
pub extern fn fputwc(wchar_t, ?*FILE) wint_t;
pub extern fn putwchar(wchar_t) wint_t;
pub extern fn getwchar() wint_t;
pub extern fn getwc(?*FILE) wint_t;
pub extern fn fgetwc(?*FILE) wint_t;
pub extern fn ungetwc(wint_t, ?*FILE) wint_t;
pub extern fn getchar() c_int;
pub extern fn putchar(c_int) c_int;
pub extern fn puts([*c]const u8) c_int;
pub extern fn getline([*c][*c]u8, [*c]usize, ?*FILE) isize;
pub extern fn getdelim([*c][*c]u8, [*c]usize, c_int, ?*FILE) isize;
pub extern fn fopen([*c]const u8, [*c]const u8) ?*FILE;
pub extern fn fdopen(c_int, [*c]const u8) ?*FILE;
pub extern fn fmemopen(?*anyopaque, usize, [*c]const u8) ?*FILE;
pub extern fn freopen([*c]const u8, [*c]const u8, ?*FILE) ?*FILE;
pub extern fn fread(?*anyopaque, c_ulong, c_ulong, ?*FILE) c_ulong;
pub extern fn fwrite(?*const anyopaque, c_ulong, c_ulong, ?*FILE) c_ulong;
pub extern fn fclose(?*FILE) c_int;
pub extern fn fseek(?*FILE, c_long, c_int) c_int;
pub extern fn ftell(?*FILE) c_long;
pub extern fn fseeko(?*FILE, i64, c_int) c_int;
pub extern fn ftello(?*FILE) i64;
pub extern fn rewind(?*FILE) void;
pub extern fn fopenflags([*c]const u8) c_int;
pub extern fn setlinebuf(?*FILE) void;
pub extern fn setbuf(?*FILE, [*c]u8) void;
pub extern fn setbuffer(?*FILE, [*c]u8, usize) void;
pub extern fn setvbuf(?*FILE, [*c]u8, c_int, usize) c_int;
pub extern fn pclose(?*FILE) c_int;
pub extern fn ctermid([*c]u8) [*c]u8;
pub extern fn perror([*c]const u8) void;
pub extern fn open_memstream([*c][*c]u8, [*c]usize) ?*FILE;
pub const fpos_t = u64;
pub extern fn gets([*c]u8) [*c]u8;
pub extern fn fgetpos(?*FILE, [*c]fpos_t) c_int;
pub extern fn fsetpos(?*FILE, [*c]const fpos_t) c_int;
pub extern fn tmpfile() ?*FILE;
pub extern fn tmpnam([*c]u8) [*c]u8;
pub extern fn tmpnam_r([*c]u8) [*c]u8;
pub extern fn popen([*c]const u8, [*c]const u8) ?*FILE;
pub extern fn printf([*c]const u8, ...) c_int;
pub extern fn vprintf(noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn fprintf(noalias ?*FILE, noalias [*c]const u8, ...) c_int;
pub extern fn vfprintf(noalias ?*FILE, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn scanf(noalias [*c]const u8, ...) c_int;
pub extern fn vscanf(noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn fscanf(noalias ?*FILE, noalias [*c]const u8, ...) c_int;
pub extern fn vfscanf(noalias ?*FILE, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn snprintf(noalias [*c]u8, c_ulong, noalias [*c]const u8, ...) c_int;
pub extern fn vsnprintf(noalias [*c]u8, c_ulong, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn sprintf(noalias [*c]u8, noalias [*c]const u8, ...) c_int;
pub extern fn vsprintf(noalias [*c]u8, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn fwprintf(?*FILE, [*c]const wchar_t, ...) c_int;
pub extern fn fwscanf(?*FILE, [*c]const wchar_t, ...) c_int;
pub extern fn swprintf([*c]wchar_t, usize, [*c]const wchar_t, ...) c_int;
pub extern fn swscanf([*c]const wchar_t, [*c]const wchar_t, ...) c_int;
pub extern fn vfwprintf(?*FILE, [*c]const wchar_t, __builtin_va_list) c_int;
pub extern fn vfwscanf(?*FILE, [*c]const wchar_t, __builtin_va_list) c_int;
pub extern fn vswprintf([*c]wchar_t, usize, [*c]const wchar_t, __builtin_va_list) c_int;
pub extern fn vswscanf([*c]const wchar_t, [*c]const wchar_t, __builtin_va_list) c_int;
pub extern fn vwprintf([*c]const wchar_t, __builtin_va_list) c_int;
pub extern fn vwscanf([*c]const wchar_t, __builtin_va_list) c_int;
pub extern fn wprintf([*c]const wchar_t, ...) c_int;
pub extern fn wscanf([*c]const wchar_t, ...) c_int;
pub extern fn fwide(?*FILE, c_int) c_int;
pub extern fn sscanf(noalias [*c]const u8, noalias [*c]const u8, ...) c_int;
pub extern fn vsscanf(noalias [*c]const u8, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn asprintf([*c][*c]u8, [*c]const u8, ...) c_int;
pub extern fn vasprintf([*c][*c]u8, [*c]const u8, __builtin_va_list) c_int;
pub extern fn getc_unlocked(?*FILE) c_int;
pub extern fn puts_unlocked([*c]const u8) c_int;
pub extern fn getchar_unlocked() c_int;
pub extern fn putc_unlocked(c_int, ?*FILE) c_int;
pub extern fn putchar_unlocked(c_int) c_int;
pub extern fn clearerr_unlocked(?*FILE) void;
pub extern fn feof_unlocked(?*FILE) c_int;
pub extern fn ferror_unlocked(?*FILE) c_int;
pub extern fn fileno_unlocked(?*FILE) c_int;
pub extern fn fflush_unlocked(?*FILE) c_int;
pub extern fn fgetc_unlocked(?*FILE) c_int;
pub extern fn fputc_unlocked(c_int, ?*FILE) c_int;
pub extern fn fread_unlocked(?*anyopaque, usize, usize, ?*FILE) usize;
pub extern fn fwrite_unlocked(?*const anyopaque, usize, usize, ?*FILE) usize;
pub extern fn fgets_unlocked([*c]u8, c_int, ?*FILE) [*c]u8;
pub extern fn fputs_unlocked([*c]const u8, ?*FILE) c_int;
pub extern fn getwc_unlocked(?*FILE) wint_t;
pub extern fn getwchar_unlocked() wint_t;
pub extern fn fgetwc_unlocked(?*FILE) wint_t;
pub extern fn fputwc_unlocked(wchar_t, ?*FILE) wint_t;
pub extern fn putwc_unlocked(wchar_t, ?*FILE) wint_t;
pub extern fn putwchar_unlocked(wchar_t) wint_t;
pub extern fn fgetws_unlocked([*c]wchar_t, c_int, ?*FILE) [*c]wchar_t;
pub extern fn fputws_unlocked([*c]const wchar_t, ?*FILE) c_int;
pub extern fn ungetwc_unlocked(wint_t, ?*FILE) wint_t;
pub extern fn ungetc_unlocked(c_int, ?*FILE) c_int;
pub extern fn fseek_unlocked(?*FILE, i64, c_int) c_int;
pub extern fn getdelim_unlocked([*c][*c]u8, [*c]usize, c_int, ?*FILE) isize;
pub extern fn fprintf_unlocked(?*FILE, [*c]const u8, ...) c_int;
pub extern fn vfprintf_unlocked(?*FILE, [*c]const u8, __builtin_va_list) c_int;
pub const struct_lconv = extern struct {
    decimal_point: [*c]u8 = std.mem.zeroes([*c]u8),
    thousands_sep: [*c]u8 = std.mem.zeroes([*c]u8),
    grouping: [*c]u8 = std.mem.zeroes([*c]u8),
    int_curr_symbol: [*c]u8 = std.mem.zeroes([*c]u8),
    currency_symbol: [*c]u8 = std.mem.zeroes([*c]u8),
    mon_decimal_point: [*c]u8 = std.mem.zeroes([*c]u8),
    mon_thousands_sep: [*c]u8 = std.mem.zeroes([*c]u8),
    mon_grouping: [*c]u8 = std.mem.zeroes([*c]u8),
    positive_sign: [*c]u8 = std.mem.zeroes([*c]u8),
    negative_sign: [*c]u8 = std.mem.zeroes([*c]u8),
    int_frac_digits: u8 = std.mem.zeroes(u8),
    frac_digits: u8 = std.mem.zeroes(u8),
    p_cs_precedes: u8 = std.mem.zeroes(u8),
    p_sep_by_space: u8 = std.mem.zeroes(u8),
    n_cs_precedes: u8 = std.mem.zeroes(u8),
    n_sep_by_space: u8 = std.mem.zeroes(u8),
    p_sign_posn: u8 = std.mem.zeroes(u8),
    n_sign_posn: u8 = std.mem.zeroes(u8),
    int_p_cs_precedes: u8 = std.mem.zeroes(u8),
    int_n_cs_precedes: u8 = std.mem.zeroes(u8),
    int_p_sep_by_space: u8 = std.mem.zeroes(u8),
    int_n_sep_by_space: u8 = std.mem.zeroes(u8),
    int_p_sign_posn: u8 = std.mem.zeroes(u8),
    int_n_sign_posn: u8 = std.mem.zeroes(u8),
};
pub extern fn wcwidth(wchar_t) c_int;
pub extern fn wcswidth([*c]const wchar_t, usize) c_int;
pub extern fn localeconv() [*c]struct_lconv;
pub const struct_lua_State = opaque {};
pub const lua_State = struct_lua_State;
pub const lua_Number = f64;
pub const lua_Integer = c_longlong;
pub const lua_Unsigned = c_ulonglong;
pub const lua_KContext = isize;
pub const lua_CFunction = ?*const fn (?*lua_State) callconv(.c) c_int;
pub const lua_KFunction = ?*const fn (?*lua_State, c_int, lua_KContext) callconv(.c) c_int;
pub const lua_Reader = ?*const fn (?*lua_State, ?*anyopaque, [*c]usize) callconv(.c) [*c]const u8;
pub const lua_Writer = ?*const fn (?*lua_State, ?*const anyopaque, usize, ?*anyopaque) callconv(.c) c_int;
pub const lua_Alloc = ?*const fn (?*anyopaque, ?*anyopaque, usize, usize) callconv(.c) ?*anyopaque;
pub const lua_WarnFunction = ?*const fn (?*anyopaque, [*c]const u8, c_int) callconv(.c) void;
pub const struct_CallInfo_3 = opaque {};
pub const struct_lua_Debug = extern struct {
    event: c_int = std.mem.zeroes(c_int),
    name: [*c]const u8 = std.mem.zeroes([*c]const u8),
    namewhat: [*c]const u8 = std.mem.zeroes([*c]const u8),
    what: [*c]const u8 = std.mem.zeroes([*c]const u8),
    source: [*c]const u8 = std.mem.zeroes([*c]const u8),
    srclen: usize = std.mem.zeroes(usize),
    currentline: c_int = std.mem.zeroes(c_int),
    linedefined: c_int = std.mem.zeroes(c_int),
    lastlinedefined: c_int = std.mem.zeroes(c_int),
    nups: u8 = std.mem.zeroes(u8),
    nparams: u8 = std.mem.zeroes(u8),
    isvararg: u8 = std.mem.zeroes(u8),
    istailcall: u8 = std.mem.zeroes(u8),
    ftransfer: c_ushort = std.mem.zeroes(c_ushort),
    ntransfer: c_ushort = std.mem.zeroes(c_ushort),
    short_src: [60]u8 = std.mem.zeroes([60]u8),
    i_ci: ?*struct_CallInfo_3 = std.mem.zeroes(?*struct_CallInfo_3),
};
pub const lua_Debug = struct_lua_Debug;
pub const lua_Hook = ?*const fn (?*lua_State, [*c]lua_Debug) callconv(.c) void;
pub const lua_ident: [*c]const u8 = @extern([*c]const u8, .{
    .name = "lua_ident",
});
pub extern fn lua_newstate(f: lua_Alloc, ud: ?*anyopaque) ?*lua_State;
pub extern fn lua_close(L: ?*lua_State) void;
pub extern fn lua_newthread(L: ?*lua_State) ?*lua_State;
pub extern fn lua_closethread(L: ?*lua_State, from: ?*lua_State) c_int;
pub extern fn lua_resetthread(L: ?*lua_State) c_int;
pub extern fn lua_atpanic(L: ?*lua_State, panicf: lua_CFunction) lua_CFunction;
pub extern fn lua_version(L: ?*lua_State) lua_Number;
pub extern fn lua_absindex(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_gettop(L: ?*lua_State) c_int;
pub extern fn lua_settop(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_pushvalue(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_rotate(L: ?*lua_State, idx: c_int, n: c_int) void;
pub extern fn lua_copy(L: ?*lua_State, fromidx: c_int, toidx: c_int) void;
pub extern fn lua_checkstack(L: ?*lua_State, n: c_int) c_int;
pub extern fn lua_xmove(from: ?*lua_State, to: ?*lua_State, n: c_int) void;
pub extern fn lua_isnumber(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_isstring(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_iscfunction(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_isinteger(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_isuserdata(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_type(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_typename(L: ?*lua_State, tp: c_int) [*c]const u8;
pub extern fn lua_tonumberx(L: ?*lua_State, idx: c_int, isnum: [*c]c_int) lua_Number;
pub extern fn lua_tointegerx(L: ?*lua_State, idx: c_int, isnum: [*c]c_int) lua_Integer;
pub extern fn lua_toboolean(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_tolstring(L: ?*lua_State, idx: c_int, len: [*c]usize) [*c]const u8;
pub extern fn lua_rawlen(L: ?*lua_State, idx: c_int) lua_Unsigned;
pub extern fn lua_tocfunction(L: ?*lua_State, idx: c_int) lua_CFunction;
pub extern fn lua_touserdata(L: ?*lua_State, idx: c_int) ?*anyopaque;
pub extern fn lua_tothread(L: ?*lua_State, idx: c_int) ?*lua_State;
pub extern fn lua_topointer(L: ?*lua_State, idx: c_int) ?*const anyopaque;
pub extern fn lua_arith(L: ?*lua_State, op: c_int) void;
pub extern fn lua_rawequal(L: ?*lua_State, idx1: c_int, idx2: c_int) c_int;
pub extern fn lua_compare(L: ?*lua_State, idx1: c_int, idx2: c_int, op: c_int) c_int;
pub extern fn lua_pushnil(L: ?*lua_State) void;
pub extern fn lua_pushnumber(L: ?*lua_State, n: lua_Number) void;
pub extern fn lua_pushinteger(L: ?*lua_State, n: lua_Integer) void;
pub extern fn lua_pushlstring(L: ?*lua_State, s: [*c]const u8, len: usize) [*c]const u8;
pub extern fn lua_pushstring(L: ?*lua_State, s: [*c]const u8) [*c]const u8;
pub extern fn lua_pushvfstring(L: ?*lua_State, fmt: [*c]const u8, argp: __builtin_va_list) [*c]const u8;
pub extern fn lua_pushfstring(L: ?*lua_State, fmt: [*c]const u8, ...) [*c]const u8;
pub extern fn lua_pushcclosure(L: ?*lua_State, @"fn": lua_CFunction, n: c_int) void;
pub extern fn lua_pushboolean(L: ?*lua_State, b: c_int) void;
pub extern fn lua_pushlightuserdata(L: ?*lua_State, p: ?*anyopaque) void;
pub extern fn lua_pushthread(L: ?*lua_State) c_int;
pub extern fn lua_getglobal(L: ?*lua_State, name: [*c]const u8) c_int;
pub extern fn lua_gettable(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_getfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) c_int;
pub extern fn lua_geti(L: ?*lua_State, idx: c_int, n: lua_Integer) c_int;
pub extern fn lua_rawget(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_rawgeti(L: ?*lua_State, idx: c_int, n: lua_Integer) c_int;
pub extern fn lua_rawgetp(L: ?*lua_State, idx: c_int, p: ?*const anyopaque) c_int;
pub extern fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
pub extern fn lua_newuserdatauv(L: ?*lua_State, sz: usize, nuvalue: c_int) ?*anyopaque;
pub extern fn lua_getmetatable(L: ?*lua_State, objindex: c_int) c_int;
pub extern fn lua_getiuservalue(L: ?*lua_State, idx: c_int, n: c_int) c_int;
pub extern fn lua_setglobal(L: ?*lua_State, name: [*c]const u8) void;
pub extern fn lua_settable(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) void;
pub extern fn lua_seti(L: ?*lua_State, idx: c_int, n: lua_Integer) void;
pub extern fn lua_rawset(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_rawseti(L: ?*lua_State, idx: c_int, n: lua_Integer) void;
pub extern fn lua_rawsetp(L: ?*lua_State, idx: c_int, p: ?*const anyopaque) void;
pub extern fn lua_setmetatable(L: ?*lua_State, objindex: c_int) c_int;
pub extern fn lua_setiuservalue(L: ?*lua_State, idx: c_int, n: c_int) c_int;
pub extern fn lua_callk(L: ?*lua_State, nargs: c_int, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) void;
pub extern fn lua_pcallk(L: ?*lua_State, nargs: c_int, nresults: c_int, errfunc: c_int, ctx: lua_KContext, k: lua_KFunction) c_int;
pub extern fn lua_load(L: ?*lua_State, reader: lua_Reader, dt: ?*anyopaque, chunkname: [*c]const u8, mode: [*c]const u8) c_int;
pub extern fn lua_dump(L: ?*lua_State, writer: lua_Writer, data: ?*anyopaque, strip: c_int) c_int;
pub extern fn lua_yieldk(L: ?*lua_State, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) c_int;
pub extern fn lua_resume(L: ?*lua_State, from: ?*lua_State, narg: c_int, nres: [*c]c_int) c_int;
pub extern fn lua_status(L: ?*lua_State) c_int;
pub extern fn lua_isyieldable(L: ?*lua_State) c_int;
pub extern fn lua_setwarnf(L: ?*lua_State, f: lua_WarnFunction, ud: ?*anyopaque) void;
pub extern fn lua_warning(L: ?*lua_State, msg: [*c]const u8, tocont: c_int) void;
pub extern fn lua_gc(L: ?*lua_State, what: c_int, ...) c_int;
pub extern fn lua_error(L: ?*lua_State) c_int;
pub extern fn lua_next(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_concat(L: ?*lua_State, n: c_int) void;
pub extern fn lua_len(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_stringtonumber(L: ?*lua_State, s: [*c]const u8) usize;
pub extern fn lua_getallocf(L: ?*lua_State, ud: [*c]?*anyopaque) lua_Alloc;
pub extern fn lua_setallocf(L: ?*lua_State, f: lua_Alloc, ud: ?*anyopaque) void;
pub extern fn lua_toclose(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_closeslot(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_getstack(L: ?*lua_State, level: c_int, ar: [*c]lua_Debug) c_int;
pub extern fn lua_getinfo(L: ?*lua_State, what: [*c]const u8, ar: [*c]lua_Debug) c_int;
pub extern fn lua_getlocal(L: ?*lua_State, ar: [*c]const lua_Debug, n: c_int) [*c]const u8;
pub extern fn lua_setlocal(L: ?*lua_State, ar: [*c]const lua_Debug, n: c_int) [*c]const u8;
pub extern fn lua_getupvalue(L: ?*lua_State, funcindex: c_int, n: c_int) [*c]const u8;
pub extern fn lua_setupvalue(L: ?*lua_State, funcindex: c_int, n: c_int) [*c]const u8;
pub extern fn lua_upvalueid(L: ?*lua_State, fidx: c_int, n: c_int) ?*anyopaque;
pub extern fn lua_upvaluejoin(L: ?*lua_State, fidx1: c_int, n1: c_int, fidx2: c_int, n2: c_int) void;
pub extern fn lua_sethook(L: ?*lua_State, func: lua_Hook, mask: c_int, count: c_int) void;
pub extern fn lua_gethook(L: ?*lua_State) lua_Hook;
pub extern fn lua_gethookmask(L: ?*lua_State) c_int;
pub extern fn lua_gethookcount(L: ?*lua_State) c_int;
pub extern fn lua_setcstacklimit(L: ?*lua_State, limit: c_uint) c_int;
pub extern var g_lua_path_default: [*c]const u8;
const union_unnamed_4 = extern union {
    n: lua_Number,
    u: f64,
    s: ?*anyopaque,
    i: lua_Integer,
    l: c_long,
    b: [1024]u8,
};
pub const struct_luaL_Buffer = extern struct {
    b: [*c]u8 = std.mem.zeroes([*c]u8),
    size: usize = std.mem.zeroes(usize),
    n: usize = std.mem.zeroes(usize),
    L: ?*lua_State = std.mem.zeroes(?*lua_State),
    init: union_unnamed_4 = std.mem.zeroes(union_unnamed_4),
};
pub const luaL_Buffer = struct_luaL_Buffer;
pub const struct_luaL_Reg = extern struct {
    name: [*c]const u8 = std.mem.zeroes([*c]const u8),
    func: lua_CFunction = std.mem.zeroes(lua_CFunction),
};
pub const luaL_Reg = struct_luaL_Reg;
pub extern fn luaL_checkversion_(L: ?*lua_State, ver: lua_Number, sz: usize) void;
pub extern fn luaL_getmetafield(L: ?*lua_State, obj: c_int, e: [*c]const u8) c_int;
pub extern fn luaL_callmeta(L: ?*lua_State, obj: c_int, e: [*c]const u8) c_int;
pub extern fn luaL_tolstring(L: ?*lua_State, idx: c_int, len: [*c]usize) [*c]const u8;
pub extern fn luaL_argerror(L: ?*lua_State, arg: c_int, extramsg: [*c]const u8) c_int;
pub extern fn luaL_typeerror(L: ?*lua_State, arg: c_int, tname: [*c]const u8) c_int;
pub extern fn luaL_checklstring(L: ?*lua_State, arg: c_int, l: [*c]usize) [*c]const u8;
pub extern fn luaL_optlstring(L: ?*lua_State, arg: c_int, def: [*c]const u8, l: [*c]usize) [*c]const u8;
pub extern fn luaL_checknumber(L: ?*lua_State, arg: c_int) lua_Number;
pub extern fn luaL_optnumber(L: ?*lua_State, arg: c_int, def: lua_Number) lua_Number;
pub extern fn luaL_checkinteger(L: ?*lua_State, arg: c_int) lua_Integer;
pub extern fn luaL_optinteger(L: ?*lua_State, arg: c_int, def: lua_Integer) lua_Integer;
pub extern fn luaL_checkstack(L: ?*lua_State, sz: c_int, msg: [*c]const u8) void;
pub extern fn luaL_checktype(L: ?*lua_State, arg: c_int, t: c_int) void;
pub extern fn luaL_checkany(L: ?*lua_State, arg: c_int) void;
pub extern fn luaL_newmetatable(L: ?*lua_State, tname: [*c]const u8) c_int;
pub extern fn luaL_setmetatable(L: ?*lua_State, tname: [*c]const u8) void;
pub extern fn luaL_testudata(L: ?*lua_State, ud: c_int, tname: [*c]const u8) ?*anyopaque;
pub extern fn luaL_checkudata(L: ?*lua_State, ud: c_int, tname: [*c]const u8) ?*anyopaque;
pub extern fn luaL_where(L: ?*lua_State, lvl: c_int) void;
pub extern fn luaL_error(L: ?*lua_State, fmt: [*c]const u8, ...) c_int;
pub extern fn luaL_checkoption(L: ?*lua_State, arg: c_int, def: [*c]const u8, lst: [*c]const [*c]const u8) c_int;
pub extern fn luaL_fileresult(L: ?*lua_State, stat: c_int, fname: [*c]const u8) c_int;
pub extern fn luaL_execresult(L: ?*lua_State, stat: c_int) c_int;
pub extern fn luaL_ref(L: ?*lua_State, t: c_int) c_int;
pub extern fn luaL_unref(L: ?*lua_State, t: c_int, ref: c_int) void;
pub extern fn luaL_loadfilex(L: ?*lua_State, filename: [*c]const u8, mode: [*c]const u8) c_int;
pub extern fn luaL_loadbufferx(L: ?*lua_State, buff: [*c]const u8, sz: usize, name: [*c]const u8, mode: [*c]const u8) c_int;
pub extern fn luaL_loadstring(L: ?*lua_State, s: [*c]const u8) c_int;
pub extern fn luaL_newstate() ?*lua_State;
pub extern fn luaL_len(L: ?*lua_State, idx: c_int) lua_Integer;
pub extern fn luaL_addgsub(b: [*c]luaL_Buffer, s: [*c]const u8, p: [*c]const u8, r: [*c]const u8) void;
pub extern fn luaL_gsub(L: ?*lua_State, s: [*c]const u8, p: [*c]const u8, r: [*c]const u8) [*c]const u8;
pub extern fn luaL_setfuncs(L: ?*lua_State, l: [*c]const luaL_Reg, nup: c_int) void;
pub extern fn luaL_getsubtable(L: ?*lua_State, idx: c_int, fname: [*c]const u8) c_int;
pub extern fn luaL_traceback(L: ?*lua_State, L1: ?*lua_State, msg: [*c]const u8, level: c_int) void;
pub extern fn luaL_traceback2(L: ?*lua_State, L1: ?*lua_State, msg: [*c]const u8, level: c_int) void;
pub extern fn luaL_requiref(L: ?*lua_State, modname: [*c]const u8, openf: lua_CFunction, glb: c_int) void;
pub extern fn luaL_buffinit(L: ?*lua_State, B: [*c]luaL_Buffer) void;
pub extern fn luaL_prepbuffsize(B: [*c]luaL_Buffer, sz: usize) [*c]u8;
pub extern fn luaL_addlstring(B: [*c]luaL_Buffer, s: [*c]const u8, l: usize) void;
pub extern fn luaL_addstring(B: [*c]luaL_Buffer, s: [*c]const u8) void;
pub extern fn luaL_addvalue(B: [*c]luaL_Buffer) void;
pub extern fn luaL_pushresult(B: [*c]luaL_Buffer) void;
pub extern fn luaL_pushresultsize(B: [*c]luaL_Buffer, sz: usize) void;
pub extern fn luaL_buffinitsize(L: ?*lua_State, B: [*c]luaL_Buffer, sz: usize) [*c]u8;
pub const struct_luaL_Stream = extern struct {
    f: ?*FILE = std.mem.zeroes(?*FILE),
    closef: lua_CFunction = std.mem.zeroes(lua_CFunction),
};
pub const luaL_Stream = struct_luaL_Stream;
pub const struct_LuaVisited = extern struct {
    i: c_int = std.mem.zeroes(c_int),
    n: c_int = std.mem.zeroes(c_int),
    p: [*c]?*const anyopaque = std.mem.zeroes([*c]?*const anyopaque),
};
pub extern fn LuaPushVisit([*c]struct_LuaVisited, ?*const anyopaque) c_int;
pub extern fn LuaPopVisit([*c]struct_LuaVisited) void;
pub const struct_EncoderConfig = extern struct {
    maxdepth: c_short = std.mem.zeroes(c_short),
    sorted: bool = std.mem.zeroes(bool),
    pretty: bool = std.mem.zeroes(bool),
    indent: [*c]const u8 = std.mem.zeroes([*c]const u8),
};
pub const struct_Serializer = extern struct {
    visited: struct_LuaVisited = std.mem.zeroes(struct_LuaVisited),
    conf: struct_EncoderConfig = std.mem.zeroes(struct_EncoderConfig),
    reason: [*c]const u8 = std.mem.zeroes([*c]const u8),
    strbuf: [*c]u8 = std.mem.zeroes([*c]u8),
    strbuflen: usize = std.mem.zeroes(usize),
    bsp: usize = std.mem.zeroes(usize),
};
pub extern fn LuaHasMultipleItems(?*lua_State) bool;
pub extern fn LuaFormatStack(?*lua_State) [*c]u8;
pub extern fn LuaCallWithTrace(?*lua_State, c_int, c_int, ?*lua_State) c_int;
pub extern fn LuaEncodeJsonData(?*lua_State, [*c][*c]u8, c_int, struct_EncoderConfig) c_int;
pub extern fn LuaEncodeLuaData(?*lua_State, [*c][*c]u8, c_int, struct_EncoderConfig) c_int;
pub extern fn LuaEncodeUrl(?*lua_State) c_int;
pub extern fn LuaParseUrl(?*lua_State) c_int;
pub extern fn LuaPushHeader(?*lua_State, [*c]struct_HttpMessage, [*c]const u8, c_int) c_int;
pub extern fn LuaPushHeaders(?*lua_State, [*c]struct_HttpMessage, [*c]const u8) c_int;
pub extern fn LuaPrintStack(?*lua_State) void;
pub extern fn LuaPushLatin1(?*lua_State, [*c]const u8, usize) void;
pub extern fn LuaPushUrlParams(?*lua_State, [*c]struct_UrlParams) void;
pub extern fn SerializeObjectStart([*c][*c]u8, [*c]struct_Serializer, c_int, bool) c_int;
pub extern fn SerializeObjectEnd([*c][*c]u8, [*c]struct_Serializer, c_int, bool) c_int;
pub extern fn SerializeObjectIndent([*c][*c]u8, [*c]struct_Serializer, c_int) c_int;
pub extern fn isascii(c_int) c_int;
pub extern fn isspace(c_int) c_int;
pub extern fn isalpha(c_int) c_int;
pub extern fn isdigit(c_int) c_int;
pub extern fn isalnum(c_int) c_int;
pub extern fn isxdigit(c_int) c_int;
pub extern fn isprint(c_int) c_int;
pub extern fn islower(c_int) c_int;
pub extern fn isupper(c_int) c_int;
pub extern fn isblank(c_int) c_int;
pub extern fn iscntrl(c_int) c_int;
pub extern fn isgraph(c_int) c_int;
pub extern fn tolower(c_int) c_int;
pub extern fn ispunct(c_int) c_int;
pub extern fn toupper(c_int) c_int;
pub extern fn toascii(c_int) c_int;
pub extern fn luaopen_base(L: ?*lua_State) c_int;
pub extern fn luaopen_coroutine(L: ?*lua_State) c_int;
pub extern fn luaopen_table(L: ?*lua_State) c_int;
pub extern fn luaopen_io(L: ?*lua_State) c_int;
pub extern fn luaopen_os(L: ?*lua_State) c_int;
pub export fn luaopen_string(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    _ = blk: {
        _ = blk_1: {
            luaL_checkversion_(L, @as(lua_Number, @floatFromInt(@as(c_int, 504))), (@sizeOf(lua_Integer) *% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 16))))) +% @sizeOf(lua_Number));
            break :blk_1 lua_createtable(L, @as(c_int, 0), @as(c_int, @bitCast(@as(c_uint, @truncate((@sizeOf([18]luaL_Reg) / @sizeOf(luaL_Reg)) -% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))))))));
        };
        break :blk luaL_setfuncs(L, @as([*c]const luaL_Reg, @ptrCast(@alignCast(&strlib[@as(usize, @intCast(0))]))), @as(c_int, 0));
    };
    createmetatable(L);
    return 1;
}
pub extern fn luaopen_utf8(L: ?*lua_State) c_int;
pub extern fn luaopen_math(L: ?*lua_State) c_int;
pub extern fn luaopen_debug(L: ?*lua_State) c_int;
pub extern fn luaopen_package(L: ?*lua_State) c_int;
pub extern fn luaL_openlibs(L: ?*lua_State) void;
comptime {
    // asm (".section .yoink\n\tb\t\"lua_notice\"\n\t.previous");
}
// str_format — ported from lstrlib.c (translate-c failed on goto intcase)
pub fn str_format(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    const top: c_int = lua_gettop(L);
    var arg: c_int = 1;
    var sfl: usize = undefined;
    var strfrmt: [*c]const u8 = luaL_checklstring(L, arg, &sfl);
    const strfrmt_end: [*c]const u8 = strfrmt + sfl;
    var b: luaL_Buffer = undefined;
    luaL_buffinit(L, &b);
    while (@intFromPtr(strfrmt) < @intFromPtr(strfrmt_end)) {
        if (strfrmt.* != L_ESC) {
            // luaL_addchar inlined: ensure space, then store byte
            if (b.n >= b.size) _ = luaL_prepbuffsize(&b, 1);
            b.b[b.n] = strfrmt.*;
            b.n += 1;
            strfrmt += 1;
        } else if ((strfrmt + 1).* == L_ESC) {
            strfrmt += 1; // skip first %
            if (b.n >= b.size) _ = luaL_prepbuffsize(&b, 1);
            b.b[b.n] = strfrmt.*;
            b.n += 1;
            strfrmt += 1;
        } else {
            // format item
            var form: [MAX_FORMAT]u8 = undefined;
            var maxitem: c_int = MAX_ITEM;
            var buff: [*c]u8 = luaL_prepbuffsize(&b, @intCast(maxitem));
            var nb: c_int = 0;
            arg += 1;
            if (arg > top)
                return luaL_argerror(L, arg, "no value");
            strfrmt = getformat(L, strfrmt + 1, &form);
            const fmt_ch = strfrmt.*;
            strfrmt += 1;
            switch (fmt_ch) {
                'c' => {
                    checkformat(L, &form, L_FMTFLAGSC, 0);
                    const ch: u8 = @intCast(@as(u64, @bitCast(luaL_checkinteger(L, arg))) & 0xFF);
                    buff[0] = ch;
                    nb = 1;
                },
                'd', 'i' => {
                    const n: lua_Integer = luaL_checkinteger(L, arg);
                    checkformat(L, &form, L_FMTFLAGSI, 1);
                    nb = zigFmtInt(buff, @intCast(maxitem), n);
                },
                'u' => {
                    const n: lua_Integer = luaL_checkinteger(L, arg);
                    checkformat(L, &form, L_FMTFLAGSU, 1);
                    nb = zigFmtInt(buff, @intCast(maxitem), n);
                },
                'o', 'x', 'X' => {
                    const n: lua_Integer = luaL_checkinteger(L, arg);
                    checkformat(L, &form, L_FMTFLAGSX, 1);
                    nb = zigFmtHex(buff, @intCast(maxitem), @bitCast(n), fmt_ch == 'o');
                },
                'a', 'A', 'f', 'e', 'E', 'g', 'G' => {
                    if (fmt_ch == 'f') { maxitem = 512; buff = luaL_prepbuffsize(&b, @intCast(maxitem)); }
                    const n_f: lua_Number = luaL_checknumber(L, arg);
                    _ = n_f;
                    // Float formatting: write placeholder (proper impl needs float→string)
                    const ph = "<float>";
                    for (ph, 0..) |ch, idx| { buff[idx] = ch; }
                    nb = @intCast(ph.len);
                },
                'p' => {
                    const p_ptr: ?*const anyopaque = lua_topointer(L, arg);
                    checkformat(L, &form, L_FMTFLAGSC, 0);
                    if (p_ptr == null) {
                        const ph = "(null)";
                        for (ph, 0..) |ch, idx| { buff[idx] = ch; }
                        nb = @intCast(ph.len);
                    } else {
                        nb = zigFmtHex(buff, @intCast(maxitem), @intFromPtr(p_ptr), false);
                    }
                },
                'q' => {
                    if (form[2] != 0)
                        return luaL_error(L, "specifier '%%q' cannot have modifiers");
                    addliteral(L, &b, arg);
                    nb = 0; // addliteral handles the buffer
                },
                's' => {
                    var l: usize = 0;
                    const s_str = luaL_checklstring(L, arg, &l);
                    if (l > 0 and s_str != null) {
                        const dst = luaL_prepbuffsize(&b, l);
                        const src: [*]const u8 = @ptrCast(s_str);
                        for (0..l) |j| { dst[j] = src[j]; }
                        b.n += @intCast(l);
                    }
                    nb = 0;
                },
                else => {
                    return luaL_error(L, "invalid conversion '%s' to 'format'", &form);
                },
            }
            // luaL_addsize inlined
            if (nb > 0) {
                b.n += @intCast(nb);
            }
        }
    }
    luaL_pushresult(&b);
    return 1;
}
pub fn str_len(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var l: usize = undefined;
    _ = &l;
    _ = luaL_checklstring(L, @as(c_int, 1), &l);
    lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_ulonglong, l))));
    return 1;
}
pub fn posrelatI(arg_pos: lua_Integer, arg_len: usize) callconv(.c) usize {
    var pos = arg_pos;
    _ = &pos;
    var len = arg_len;
    _ = &len;
    if (pos > @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 0))))) return @as(usize, @bitCast(@as(c_long, @truncate(pos)))) else if (pos == @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 0))))) return 1 else if (pos < -@as(lua_Integer, @bitCast(@as(c_ulonglong, len)))) return 1 else return (len +% @as(usize, @bitCast(@as(c_long, @truncate(pos))))) +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))));
    return std.mem.zeroes(usize);
}
pub fn getendpos(arg_L: ?*lua_State, arg_arg: c_int, arg_def: lua_Integer, arg_len: usize) callconv(.c) usize {
    var L = arg_L;
    _ = &L;
    var arg = arg_arg;
    _ = &arg;
    var def = arg_def;
    _ = &def;
    var len = arg_len;
    _ = &len;
    var pos: lua_Integer = luaL_optinteger(L, arg, def);
    _ = &pos;
    if (pos > @as(lua_Integer, @bitCast(@as(c_ulonglong, len)))) return len else if (pos >= @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 0))))) return @as(usize, @bitCast(@as(c_long, @truncate(pos)))) else if (pos < -@as(lua_Integer, @bitCast(@as(c_ulonglong, len)))) return 0 else return (len +% @as(usize, @bitCast(@as(c_long, @truncate(pos))))) +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))));
    return std.mem.zeroes(usize);
}
pub fn str_sub(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var l: usize = undefined;
    _ = &l;
    var s: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &l);
    _ = &s;
    var start: usize = posrelatI(luaL_checkinteger(L, @as(c_int, 2)), l);
    _ = &start;
    var end: usize = getendpos(L, @as(c_int, 3), @as(lua_Integer, @bitCast(@as(c_longlong, -@as(c_int, 1)))), l);
    _ = &end;
    if (start <= end) {
        _ = lua_pushlstring(L, (s + start) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))), (end -% start) +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1)))));
    } else {
        _ = lua_pushstring(L, "");
    }
    return 1;
}
pub fn str_reverse(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var l: usize = undefined;
    _ = &l;
    var i: usize = undefined;
    _ = &i;
    var b: luaL_Buffer = undefined;
    _ = &b;
    var s: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &l);
    _ = &s;
    var p: [*c]u8 = luaL_buffinitsize(L, &b, l);
    _ = &p;
    {
        i = 0;
        while (i < l) : (i +%= 1) {
            p[i] = s[(l -% i) -% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))];
        }
    }
    luaL_pushresultsize(&b, l);
    return 1;
}
pub fn str_lower(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var l: usize = undefined;
    _ = &l;
    var i: usize = undefined;
    _ = &i;
    var b: luaL_Buffer = undefined;
    _ = &b;
    var s: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &l);
    _ = &s;
    var p: [*c]u8 = luaL_buffinitsize(L, &b, l);
    _ = &p;
    {
        i = 0;
        while (i < l) : (i +%= 1) {
            p[i] = @as(u8, @bitCast(@as(i8, @truncate(tolower(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(s[i]))))))))));
        }
    }
    luaL_pushresultsize(&b, l);
    return 1;
}
pub fn str_upper(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var l: usize = undefined;
    _ = &l;
    var i: usize = undefined;
    _ = &i;
    var b: luaL_Buffer = undefined;
    _ = &b;
    var s: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &l);
    _ = &s;
    var p: [*c]u8 = luaL_buffinitsize(L, &b, l);
    _ = &p;
    {
        i = 0;
        while (i < l) : (i +%= 1) {
            p[i] = @as(u8, @bitCast(@as(i8, @truncate(toupper(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(s[i]))))))))));
        }
    }
    luaL_pushresultsize(&b, l);
    return 1;
}
pub fn str_rep(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var l: usize = undefined;
    _ = &l;
    var lsep: usize = undefined;
    _ = &lsep;
    var s: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &l);
    _ = &s;
    var n: lua_Integer = luaL_checkinteger(L, @as(c_int, 2));
    _ = &n;
    var sep: [*c]const u8 = luaL_optlstring(L, @as(c_int, 3), "", &lsep);
    _ = &sep;
    if (n <= @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 0))))) {
        _ = lua_pushstring(L, "");
    } else if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(((l +% lsep) < l) or (@as(c_ulonglong, @bitCast(@as(c_ulonglong, l +% lsep))) > (@as(c_ulonglong, @bitCast(@as(c_ulonglong, if (@sizeOf(usize) < @sizeOf(c_int)) ~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) else @as(usize, @bitCast(@as(c_long, @as(c_int, 2147483647))))))) / @as(c_ulonglong, @bitCast(n))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) return luaL_error(L, "resulting string too large") else {
        var totallen: usize = (@as(usize, @bitCast(@as(c_long, @truncate(n)))) *% l) +% (@as(usize, @bitCast(@as(c_long, @truncate(n - @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 1)))))))) *% lsep);
        _ = &totallen;
        var b: luaL_Buffer = undefined;
        _ = &b;
        var p: [*c]u8 = luaL_buffinitsize(L, &b, totallen);
        _ = &p;
        while ((blk: {
            const ref = &n;
            const tmp = ref.*;
            ref.* -= 1;
            break :blk tmp;
        }) > @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 1))))) {
            _ = memcpy(@as(?*anyopaque, @ptrCast(p)), @as(?*const anyopaque, @ptrCast(s)), l *% @sizeOf(u8));
            p += l;
            if (lsep > @as(usize, @bitCast(@as(c_long, @as(c_int, 0))))) {
                _ = memcpy(@as(?*anyopaque, @ptrCast(p)), @as(?*const anyopaque, @ptrCast(sep)), lsep *% @sizeOf(u8));
                p += lsep;
            }
        }
        _ = memcpy(@as(?*anyopaque, @ptrCast(p)), @as(?*const anyopaque, @ptrCast(s)), l *% @sizeOf(u8));
        luaL_pushresultsize(&b, totallen);
    }
    return 1;
}
pub fn str_byte(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var l: usize = undefined;
    _ = &l;
    var s: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &l);
    _ = &s;
    var pi: lua_Integer = luaL_optinteger(L, @as(c_int, 2), @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 1)))));
    _ = &pi;
    var posi: usize = posrelatI(pi, l);
    _ = &posi;
    var pose: usize = getendpos(L, @as(c_int, 3), pi, l);
    _ = &pose;
    var n: c_int = undefined;
    _ = &n;
    var i: c_int = undefined;
    _ = &i;
    if (posi > pose) return 0;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((pose -% posi) >= @as(usize, @bitCast(@as(c_long, @as(c_int, 2147483647))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) return luaL_error(L, "string slice too long");
    n = @as(c_int, @bitCast(@as(c_uint, @truncate(pose -% posi)))) + @as(c_int, 1);
    luaL_checkstack(L, n, "string slice too long");
    {
        i = 0;
        while (i < n) : (i += 1) {
            lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_ulonglong, @as(u8, @bitCast(s[(posi +% @as(usize, @bitCast(@as(c_long, i)))) -% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))]))))));
        }
    }
    return n;
}
pub fn str_char(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var n: c_int = lua_gettop(L);
    _ = &n;
    var i: c_int = undefined;
    _ = &i;
    var b: luaL_Buffer = undefined;
    _ = &b;
    var p: [*c]u8 = luaL_buffinitsize(L, &b, @as(usize, @bitCast(@as(c_long, n))));
    _ = &p;
    {
        i = 1;
        while (i <= n) : (i += 1) {
            var c: lua_Unsigned = @as(lua_Unsigned, @bitCast(luaL_checkinteger(L, i)));
            _ = &c;
            _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(c <= @as(lua_Unsigned, @bitCast(@as(c_longlong, @as(c_int, 255))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, i, "value out of range") != 0);
            (blk: {
                const tmp = i - @as(c_int, 1);
                if (tmp >= 0) break :blk p + @as(usize, @intCast(tmp)) else break :blk p - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(u8, @bitCast(@as(u8, @bitCast(@as(u8, @truncate(c))))));
        }
    }
    luaL_pushresultsize(&b, @as(usize, @bitCast(@as(c_long, n))));
    return 1;
}
pub const struct_str_Writer = extern struct {
    init: c_int = std.mem.zeroes(c_int),
    B: luaL_Buffer = std.mem.zeroes(luaL_Buffer),
};
pub fn writer(arg_L: ?*lua_State, arg_b: ?*const anyopaque, arg_size: usize, arg_ud: ?*anyopaque) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var b = arg_b;
    _ = &b;
    var size = arg_size;
    _ = &size;
    var ud = arg_ud;
    _ = &ud;
    var state: [*c]struct_str_Writer = @as([*c]struct_str_Writer, @ptrCast(@alignCast(ud)));
    _ = &state;
    if (!(state.*.init != 0)) {
        state.*.init = 1;
        luaL_buffinit(L, &state.*.B);
    }
    luaL_addlstring(&state.*.B, @as([*c]const u8, @ptrCast(@alignCast(b))), size);
    return 0;
}
pub fn str_dump(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var state: struct_str_Writer = undefined;
    _ = &state;
    var strip: c_int = lua_toboolean(L, @as(c_int, 2));
    _ = &strip;
    luaL_checktype(L, @as(c_int, 1), @as(c_int, 6));
    lua_settop(L, @as(c_int, 1));
    state.init = 0;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(lua_dump(L, &writer, @as(?*anyopaque, @ptrCast(&state)), strip) != @as(c_int, 0)) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) return luaL_error(L, "unable to dump given function");
    luaL_pushresult(&state.B);
    return 1;
}
pub fn tonum(arg_L: ?*lua_State, arg_arg: c_int) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var arg = arg_arg;
    _ = &arg;
    if (lua_type(L, arg) == @as(c_int, 3)) {
        lua_pushvalue(L, arg);
        return 1;
    } else {
        var len: usize = undefined;
        _ = &len;
        var s: [*c]const u8 = lua_tolstring(L, arg, &len);
        _ = &s;
        return @intFromBool((s != @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) and (lua_stringtonumber(L, s) == (len +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1)))))));
    }
    return 0;
}
pub fn trymt(arg_L: ?*lua_State, arg_mtname: [*c]const u8) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var mtname = arg_mtname;
    _ = &mtname;
    lua_settop(L, @as(c_int, 2));
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((lua_type(L, @as(c_int, 2)) == @as(c_int, 4)) or !(luaL_getmetafield(L, @as(c_int, 2), mtname) != 0)) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
        _ = luaL_error(L, "attempt to %s a '%s' with a '%s'", mtname + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))), lua_typename(L, lua_type(L, -@as(c_int, 2))), lua_typename(L, lua_type(L, -@as(c_int, 1))));
    }
    lua_rotate(L, -@as(c_int, 3), @as(c_int, 1));
    lua_callk(L, @as(c_int, 2), @as(c_int, 1), @as(lua_KContext, @bitCast(@as(c_long, @as(c_int, 0)))), null);
}
pub fn arith(arg_L: ?*lua_State, arg_op: c_int, arg_mtname: [*c]const u8) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var op = arg_op;
    _ = &op;
    var mtname = arg_mtname;
    _ = &mtname;
    if ((tonum(L, @as(c_int, 1)) != 0) and (tonum(L, @as(c_int, 2)) != 0)) {
        lua_arith(L, op);
    } else {
        trymt(L, mtname);
    }
    return 1;
}
pub fn arith_add(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    return arith(L, @as(c_int, 0), "__add");
}
pub fn arith_sub(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    return arith(L, @as(c_int, 1), "__sub");
}
pub fn arith_mul(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    if (lua_isinteger(L, @as(c_int, 2)) != 0) {
        lua_pushcclosure(L, &str_rep, @as(c_int, 0));
        lua_pushvalue(L, @as(c_int, 1));
        lua_pushvalue(L, @as(c_int, 2));
        lua_callk(L, @as(c_int, 2), @as(c_int, 1), @as(lua_KContext, @bitCast(@as(c_long, @as(c_int, 0)))), null);
        return 1;
    } else {
        return arith(L, @as(c_int, 2), "__mul");
    }
    return 0;
}
pub fn arith_mod(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var i: c_int = undefined;
    _ = &i;
    var n: c_int = undefined;
    _ = &n;
    if (lua_type(L, @as(c_int, 2)) == @as(c_int, 5)) {
        lua_len(L, @as(c_int, 2));
        n = @as(c_int, @bitCast(@as(c_int, @truncate(lua_tointegerx(L, -@as(c_int, 1), null)))));
        lua_settop(L, -@as(c_int, 1) - @as(c_int, 1));
        lua_pushcclosure(L, &str_format, @as(c_int, 0));
        lua_pushvalue(L, @as(c_int, 1));
        {
            i = 1;
            while (i <= n) : (i += 1) {
                _ = lua_geti(L, @as(c_int, 2), @as(lua_Integer, @bitCast(@as(c_longlong, i))));
            }
        }
        lua_callk(L, @as(c_int, 1) + n, @as(c_int, 1), @as(lua_KContext, @bitCast(@as(c_long, @as(c_int, 0)))), null);
        return 1;
    } else {
        return arith(L, @as(c_int, 3), "__mod");
    }
    return 0;
}
pub fn arith_pow(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    return arith(L, @as(c_int, 4), "__pow");
}
pub fn arith_div(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    return arith(L, @as(c_int, 5), "__div");
}
pub fn arith_idiv(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    return arith(L, @as(c_int, 6), "__idiv");
}
pub fn arith_unm(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    return arith(L, @as(c_int, 12), "__unm");
}
pub const stringmetamethods: [10]luaL_Reg = [10]luaL_Reg{
    luaL_Reg{
        .name = "__add",
        .func = &arith_add,
    },
    luaL_Reg{
        .name = "__sub",
        .func = &arith_sub,
    },
    luaL_Reg{
        .name = "__mul",
        .func = &arith_mul,
    },
    luaL_Reg{
        .name = "__mod",
        .func = &arith_mod,
    },
    luaL_Reg{
        .name = "__pow",
        .func = &arith_pow,
    },
    luaL_Reg{
        .name = "__div",
        .func = &arith_div,
    },
    luaL_Reg{
        .name = "__idiv",
        .func = &arith_idiv,
    },
    luaL_Reg{
        .name = "__unm",
        .func = &arith_unm,
    },
    luaL_Reg{
        .name = "__index",
        .func = null,
    },
    luaL_Reg{
        .name = null,
        .func = null,
    },
};
const struct_unnamed_5 = extern struct {
    init: [*c]const u8 = std.mem.zeroes([*c]const u8),
    len: ptrdiff_t = std.mem.zeroes(ptrdiff_t),
};
pub const struct_MatchState = extern struct {
    src_init: [*c]const u8 = std.mem.zeroes([*c]const u8),
    src_end: [*c]const u8 = std.mem.zeroes([*c]const u8),
    p_end: [*c]const u8 = std.mem.zeroes([*c]const u8),
    L: ?*lua_State = std.mem.zeroes(?*lua_State),
    matchdepth: c_int = std.mem.zeroes(c_int),
    level: u8 = std.mem.zeroes(u8),
    capture: [32]struct_unnamed_5 = std.mem.zeroes([32]struct_unnamed_5),
};
pub const MatchState = struct_MatchState;
// match — ported from lstrlib.c (translate-c failed on goto init)
pub fn match(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_p: [*c]const u8) callconv(.c) [*c]const u8 {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    var p = arg_p;
    if (__builtin_expect(@as(c_long, @intFromBool((blk: {
        const ref = &ms.*.matchdepth;
        const tmp = ref.*;
        ref.* -= 1;
        break :blk tmp;
    }) == @as(c_int, 0))), @as(c_long, 0)) != 0) {
        _ = luaL_error(ms.*.L, "pattern too complex");
    }
    // init: label — using while(true) + continue for tail recursion
    while (true) {
        if (p != ms.*.p_end) {
            switch (@as(c_int, @bitCast(@as(c_uint, p.*)))) {
                '(' => {
                    // start capture
                    if ((p + 1).* == @as(u8, ')')) {
                        s = start_capture(ms, s, p + 2, CAP_POSITION);
                    } else {
                        s = start_capture(ms, s, p + 1, CAP_UNFINISHED);
                    }
                    break; // exit switch, fall to end
                },
                ')' => {
                    // end capture
                    s = end_capture(ms, s, p + 1);
                    break;
                },
                '$' => {
                    if ((p + 1) != ms.*.p_end) {
                        // not the last char — go to default
                        const ep = classend(ms, p);
                        if (singlematch(ms, s, p, ep) == 0) {
                            if (ep.* == '*' or ep.* == '?' or ep.* == '-') {
                                p = ep + 1;
                                continue; // goto init
                            } else {
                                s = null;
                            }
                        } else {
                            switch (@as(c_int, @bitCast(@as(c_uint, ep.*)))) {
                                '?' => {
                                    const res = match(ms, s + 1, ep + 1);
                                    if (res != null) {
                                        s = res;
                                    } else {
                                        p = ep + 1;
                                        continue; // goto init
                                    }
                                },
                                '+' => {
                                    s += 1; // 1 match already done
                                    s = max_expand(ms, s, p, ep);
                                },
                                '*' => {
                                    s = max_expand(ms, s, p, ep);
                                },
                                '-' => {
                                    s = min_expand(ms, s, p, ep);
                                },
                                else => {
                                    s += 1;
                                    p = ep;
                                    continue; // goto init
                                },
                            }
                        }
                        break;
                    }
                    // '$' is the last char in pattern — check end of string
                    s = if (s == ms.*.src_end) s else null;
                    break;
                },
                L_ESC => {
                    // escaped sequences
                    switch (@as(c_int, @bitCast(@as(c_uint, (p + 1).*)))) {
                        'b' => {
                            // balanced string
                            s = matchbalance(ms, s, p + 2);
                            if (s != null) {
                                p += 4;
                                continue; // goto init
                            }
                            break;
                        },
                        'f' => {
                            // frontier
                            p += 2;
                            if (__builtin_expect(@as(c_long, @intFromBool(p.* != @as(u8, '['))), @as(c_long, 0)) != 0) {
                                _ = luaL_error(ms.*.L, "missing '[' after '%%f' in pattern");
                            }
                            const ep = classend(ms, p);
                            const previous: u8 = if (s == ms.*.src_init) 0 else (s - 1).*;
                            if (matchbracketclass(@as(c_int, previous), p, ep - 1) == 0 and
                                matchbracketclass(@as(c_int, @bitCast(@as(c_uint, s.*))), p, ep - 1) != 0)
                            {
                                p = ep;
                                continue; // goto init
                            }
                            s = null;
                            break;
                        },
                        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                            // capture results
                            s = match_capture(ms, s, uchar((p + 1).*));
                            if (s != null) {
                                p += 2;
                                continue; // goto init
                            }
                            break;
                        },
                        else => {
                            // default for L_ESC: pattern class plus optional suffix
                            const ep = classend(ms, p);
                            if (singlematch(ms, s, p, ep) == 0) {
                                if (ep.* == '*' or ep.* == '?' or ep.* == '-') {
                                    p = ep + 1;
                                    continue; // goto init
                                } else {
                                    s = null;
                                }
                            } else {
                                switch (@as(c_int, @bitCast(@as(c_uint, ep.*)))) {
                                    '?' => {
                                        const res = match(ms, s + 1, ep + 1);
                                        if (res != null) {
                                            s = res;
                                        } else {
                                            p = ep + 1;
                                            continue; // goto init
                                        }
                                    },
                                    '+' => {
                                        s += 1;
                                        s = max_expand(ms, s, p, ep);
                                    },
                                    '*' => {
                                        s = max_expand(ms, s, p, ep);
                                    },
                                    '-' => {
                                        s = min_expand(ms, s, p, ep);
                                    },
                                    else => {
                                        s += 1;
                                        p = ep;
                                        continue; // goto init
                                    },
                                }
                            }
                            break;
                        },
                    }
                },
                else => {
                    // dflt: pattern class plus optional suffix
                    const ep = classend(ms, p);
                    if (singlematch(ms, s, p, ep) == 0) {
                        if (ep.* == '*' or ep.* == '?' or ep.* == '-') {
                            p = ep + 1;
                            continue; // goto init
                        } else {
                            s = null;
                        }
                    } else {
                        switch (@as(c_int, @bitCast(@as(c_uint, ep.*)))) {
                            '?' => {
                                const res = match(ms, s + 1, ep + 1);
                                if (res != null) {
                                    s = res;
                                } else {
                                    p = ep + 1;
                                    continue; // goto init
                                }
                            },
                            '+' => {
                                s += 1;
                                s = max_expand(ms, s, p, ep);
                            },
                            '*' => {
                                s = max_expand(ms, s, p, ep);
                            },
                            '-' => {
                                s = min_expand(ms, s, p, ep);
                            },
                            else => {
                                s += 1;
                                p = ep;
                                continue; // goto init
                            },
                        }
                    }
                    break;
                },
            }
        }
        break; // end of pattern or after switch
    }
    ms.*.matchdepth += 1;
    return s;
}
pub fn check_capture(arg_ms: [*c]MatchState, arg_l: c_int) callconv(.c) c_int {
    var ms = arg_ms;
    _ = &ms;
    var l = arg_l;
    _ = &l;
    l -= @as(c_int, '1');
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(((l < @as(c_int, 0)) or (l >= @as(c_int, @bitCast(@as(c_uint, ms.*.level))))) or (ms.*.capture[@as(c_uint, @intCast(l))].len == @as(ptrdiff_t, @bitCast(@as(c_long, -@as(c_int, 1)))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) return luaL_error(ms.*.L, "invalid capture index %%%d", l + @as(c_int, 1));
    return l;
}
pub fn capture_to_close(arg_ms: [*c]MatchState) callconv(.c) c_int {
    var ms = arg_ms;
    _ = &ms;
    var level: c_int = @as(c_int, @bitCast(@as(c_uint, ms.*.level)));
    _ = &level;
    {
        level -= 1;
        while (level >= @as(c_int, 0)) : (level -= 1) if (ms.*.capture[@as(c_uint, @intCast(level))].len == @as(ptrdiff_t, @bitCast(@as(c_long, -@as(c_int, 1))))) return level;
    }
    return luaL_error(ms.*.L, "invalid pattern capture");
}
pub fn classend(arg_ms: [*c]MatchState, arg_p: [*c]const u8) callconv(.c) [*c]const u8 {
    var ms = arg_ms;
    _ = &ms;
    var p = arg_p;
    _ = &p;
    while (true) {
        switch (@as(c_int, @bitCast(@as(c_uint, (blk: {
            const ref = &p;
            const tmp = ref.*;
            ref.* += 1;
            break :blk tmp;
        }).*)))) {
            @as(c_int, 37) => {
                {
                    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(p == ms.*.p_end) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
                        _ = luaL_error(ms.*.L, "malformed pattern (ends with '%%')");
                    }
                    return p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                }
            },
            @as(c_int, 91) => {
                {
                    if (@as(c_int, @bitCast(@as(c_uint, p.*))) == @as(c_int, '^')) {
                        p += 1;
                    }
                    while (true) {
                        if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(p == ms.*.p_end) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
                            _ = luaL_error(ms.*.L, "malformed pattern (missing ']')");
                        }
                        if ((@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const ref = &p;
                            const tmp = ref.*;
                            ref.* += 1;
                            break :blk tmp;
                        }).*))) == @as(c_int, '%')) and (p < ms.*.p_end)) {
                            p += 1;
                        }
                        if (!(@as(c_int, @bitCast(@as(c_uint, p.*))) != @as(c_int, ']'))) break;
                    }
                    return p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                }
            },
            else => {
                {
                    return p;
                }
            },
        }
        break;
    }
    return null;
}
pub fn match_class(arg_c: c_int, arg_cl: c_int) callconv(.c) c_int {
    var c = arg_c;
    _ = &c;
    var cl = arg_cl;
    _ = &cl;
    var res: c_int = undefined;
    _ = &res;
    while (true) {
        switch (tolower(cl)) {
            @as(c_int, 97) => {
                res = isalpha(c);
                break;
            },
            @as(c_int, 99) => {
                res = iscntrl(c);
                break;
            },
            @as(c_int, 100) => {
                res = isdigit(c);
                break;
            },
            @as(c_int, 103) => {
                res = isgraph(c);
                break;
            },
            @as(c_int, 108) => {
                res = islower(c);
                break;
            },
            @as(c_int, 112) => {
                res = ispunct(c);
                break;
            },
            @as(c_int, 115) => {
                res = isspace(c);
                break;
            },
            @as(c_int, 117) => {
                res = isupper(c);
                break;
            },
            @as(c_int, 119) => {
                res = isalnum(c);
                break;
            },
            @as(c_int, 120) => {
                res = isxdigit(c);
                break;
            },
            @as(c_int, 122) => {
                res = @intFromBool(c == @as(c_int, 0));
                break;
            },
            else => return @intFromBool(cl == c),
        }
        break;
    }
    return if (islower(cl) != 0) res else @intFromBool(!(res != 0));
}
pub fn matchbracketclass(arg_c: c_int, arg_p: [*c]const u8, arg_ec: [*c]const u8) callconv(.c) c_int {
    var c = arg_c;
    _ = &c;
    var p = arg_p;
    _ = &p;
    var ec = arg_ec;
    _ = &ec;
    var sig: c_int = 1;
    _ = &sig;
    if (@as(c_int, @bitCast(@as(c_uint, (p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).*))) == @as(c_int, '^')) {
        sig = 0;
        p += 1;
    }
    while ((blk: {
        const ref = &p;
        ref.* += 1;
        break :blk ref.*;
    }) < ec) {
        if (@as(c_int, @bitCast(@as(c_uint, p.*))) == @as(c_int, '%')) {
            p += 1;
            if (match_class(c, @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(p.*)))))) != 0) return sig;
        } else if ((@as(c_int, @bitCast(@as(c_uint, (p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).*))) == @as(c_int, '-')) and ((p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))))) < ec)) {
            p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
            if ((@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((p - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))))).*))))) <= c) and (c <= @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(p.*))))))) return sig;
        } else if (@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(p.*))))) == c) return sig;
    }
    return @intFromBool(!(sig != 0));
}
pub fn singlematch(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_p: [*c]const u8, arg_ep: [*c]const u8) callconv(.c) c_int {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    _ = &s;
    var p = arg_p;
    _ = &p;
    var ep = arg_ep;
    _ = &ep;
    if (s >= ms.*.src_end) return 0 else {
        var c: c_int = @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(s.*)))));
        _ = &c;
        while (true) {
            switch (@as(c_int, @bitCast(@as(c_uint, p.*)))) {
                @as(c_int, 46) => return 1,
                @as(c_int, 37) => return match_class(c, @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).*)))))),
                @as(c_int, 91) => return matchbracketclass(c, p, ep - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))),
                else => return @intFromBool(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(p.*))))) == c),
            }
            break;
        }
    }
    return 0;
}
pub fn matchbalance(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_p: [*c]const u8) callconv(.c) [*c]const u8 {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    _ = &s;
    var p = arg_p;
    _ = &p;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(p >= (ms.*.p_end - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
        _ = luaL_error(ms.*.L, "malformed pattern (missing arguments to '%%b')");
    }
    if (@as(c_int, @bitCast(@as(c_uint, s.*))) != @as(c_int, @bitCast(@as(c_uint, p.*)))) return null else {
        var b: c_int = @as(c_int, @bitCast(@as(c_uint, p.*)));
        _ = &b;
        var e: c_int = @as(c_int, @bitCast(@as(c_uint, (p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).*)));
        _ = &e;
        var cont: c_int = 1;
        _ = &cont;
        while ((blk: {
            const ref = &s;
            ref.* += 1;
            break :blk ref.*;
        }) < ms.*.src_end) {
            if (@as(c_int, @bitCast(@as(c_uint, s.*))) == e) {
                if ((blk: {
                    const ref = &cont;
                    ref.* -= 1;
                    break :blk ref.*;
                }) == @as(c_int, 0)) return s + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
            } else if (@as(c_int, @bitCast(@as(c_uint, s.*))) == b) {
                cont += 1;
            }
        }
    }
    return null;
}
pub fn max_expand(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_p: [*c]const u8, arg_ep: [*c]const u8) callconv(.c) [*c]const u8 {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    _ = &s;
    var p = arg_p;
    _ = &p;
    var ep = arg_ep;
    _ = &ep;
    var i: ptrdiff_t = 0;
    _ = &i;
    while (singlematch(ms, s + @as(usize, @bitCast(@as(isize, @intCast(i)))), p, ep) != 0) {
        i += 1;
    }
    while (i >= @as(ptrdiff_t, @bitCast(@as(c_long, @as(c_int, 0))))) {
        var res: [*c]const u8 = match(ms, s + @as(usize, @bitCast(@as(isize, @intCast(i)))), ep + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))));
        _ = &res;
        if (res != null) return res;
        i -= 1;
    }
    return null;
}
pub fn min_expand(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_p: [*c]const u8, arg_ep: [*c]const u8) callconv(.c) [*c]const u8 {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    _ = &s;
    var p = arg_p;
    _ = &p;
    var ep = arg_ep;
    _ = &ep;
    while (true) {
        var res: [*c]const u8 = match(ms, s, ep + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))));
        _ = &res;
        if (res != @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return res else if (singlematch(ms, s, p, ep) != 0) {
            s += 1;
        } else return null;
    }
    return null;
}
pub fn start_capture(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_p: [*c]const u8, arg_what: c_int) callconv(.c) [*c]const u8 {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    _ = &s;
    var p = arg_p;
    _ = &p;
    var what = arg_what;
    _ = &what;
    var res: [*c]const u8 = undefined;
    _ = &res;
    var level: c_int = @as(c_int, @bitCast(@as(c_uint, ms.*.level)));
    _ = &level;
    if (level >= @as(c_int, 32)) {
        _ = luaL_error(ms.*.L, "too many captures");
    }
    ms.*.capture[@as(c_uint, @intCast(level))].init = s;
    ms.*.capture[@as(c_uint, @intCast(level))].len = @as(ptrdiff_t, @bitCast(@as(c_long, what)));
    ms.*.level = @as(u8, @bitCast(@as(i8, @truncate(level + @as(c_int, 1)))));
    if ((blk: {
        const tmp = match(ms, s, p);
        res = tmp;
        break :blk tmp;
    }) == @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        ms.*.level -%= 1;
    }
    return res;
}
pub fn end_capture(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_p: [*c]const u8) callconv(.c) [*c]const u8 {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    _ = &s;
    var p = arg_p;
    _ = &p;
    var l: c_int = capture_to_close(ms);
    _ = &l;
    var res: [*c]const u8 = undefined;
    _ = &res;
    ms.*.capture[@as(c_uint, @intCast(l))].len = @divExact(@as(c_long, @bitCast(@intFromPtr(s) -% @intFromPtr(ms.*.capture[@as(c_uint, @intCast(l))].init))), @sizeOf(u8));
    if ((blk: {
        const tmp = match(ms, s, p);
        res = tmp;
        break :blk tmp;
    }) == @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        ms.*.capture[@as(c_uint, @intCast(l))].len = @as(ptrdiff_t, @bitCast(@as(c_long, -@as(c_int, 1))));
    }
    return res;
}
pub fn match_capture(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_l: c_int) callconv(.c) [*c]const u8 {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    _ = &s;
    var l = arg_l;
    _ = &l;
    var len: usize = undefined;
    _ = &len;
    l = check_capture(ms, l);
    len = @as(usize, @bitCast(ms.*.capture[@as(c_uint, @intCast(l))].len));
    if ((@as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(ms.*.src_end) -% @intFromPtr(s))), @sizeOf(u8)))) >= len) and (memcmp(@as(?*const anyopaque, @ptrCast(ms.*.capture[@as(c_uint, @intCast(l))].init)), @as(?*const anyopaque, @ptrCast(s)), len) == @as(c_int, 0))) return s + len else return null;
    return null;
}
pub fn lmemfind(arg_s1: [*c]const u8, arg_l1: usize, arg_s2: [*c]const u8, arg_l2: usize) callconv(.c) [*c]const u8 {
    var s1 = arg_s1;
    _ = &s1;
    var l1 = arg_l1;
    _ = &l1;
    var s2 = arg_s2;
    _ = &s2;
    var l2 = arg_l2;
    _ = &l2;
    if (l2 == @as(usize, @bitCast(@as(c_long, @as(c_int, 0))))) return s1 else if (l2 > l1) return null else {
        var init: [*c]const u8 = undefined;
        _ = &init;
        l2 -%= 1;
        l1 = l1 -% l2;
        while ((l1 > @as(usize, @bitCast(@as(c_long, @as(c_int, 0))))) and ((blk: {
            const tmp = @as([*c]const u8, @ptrCast(@alignCast(memchr(@as(?*const anyopaque, @ptrCast(s1)), @as(c_int, @bitCast(@as(c_uint, s2.*))), l1))));
            init = tmp;
            break :blk tmp;
        }) != @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))) {
            init += 1;
            if (memcmp(@as(?*const anyopaque, @ptrCast(init)), @as(?*const anyopaque, @ptrCast(s2 + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))))), l2) == @as(c_int, 0)) return init - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))) else {
                l1 -%= @as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(init) -% @intFromPtr(s1))), @sizeOf(u8))));
                s1 = init;
            }
        }
        return null;
    }
    return null;
}
pub fn get_onecapture(arg_ms: [*c]MatchState, arg_i: c_int, arg_s: [*c]const u8, arg_e: [*c]const u8, arg_cap: [*c][*c]const u8) callconv(.c) usize {
    var ms = arg_ms;
    _ = &ms;
    var i = arg_i;
    _ = &i;
    var s = arg_s;
    _ = &s;
    var e = arg_e;
    _ = &e;
    var cap = arg_cap;
    _ = &cap;
    if (i >= @as(c_int, @bitCast(@as(c_uint, ms.*.level)))) {
        if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(i != @as(c_int, 0)) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
            _ = luaL_error(ms.*.L, "invalid capture index %%%d", i + @as(c_int, 1));
        }
        cap.* = s;
        return @as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(e) -% @intFromPtr(s))), @sizeOf(u8))));
    } else {
        var capl: ptrdiff_t = ms.*.capture[@as(c_uint, @intCast(i))].len;
        _ = &capl;
        cap.* = ms.*.capture[@as(c_uint, @intCast(i))].init;
        if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(capl == @as(ptrdiff_t, @bitCast(@as(c_long, -@as(c_int, 1))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
            _ = luaL_error(ms.*.L, "unfinished capture");
        } else if (capl == @as(ptrdiff_t, @bitCast(@as(c_long, -@as(c_int, 2))))) {
            lua_pushinteger(ms.*.L, @as(lua_Integer, @bitCast(@as(c_longlong, @divExact(@as(c_long, @bitCast(@intFromPtr(ms.*.capture[@as(c_uint, @intCast(i))].init) -% @intFromPtr(ms.*.src_init))), @sizeOf(u8)) + @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))))));
        }
        return @as(usize, @bitCast(capl));
    }
    return std.mem.zeroes(usize);
}
pub fn push_onecapture(arg_ms: [*c]MatchState, arg_i: c_int, arg_s: [*c]const u8, arg_e: [*c]const u8) callconv(.c) void {
    var ms = arg_ms;
    _ = &ms;
    var i = arg_i;
    _ = &i;
    var s = arg_s;
    _ = &s;
    var e = arg_e;
    _ = &e;
    var cap: [*c]const u8 = undefined;
    _ = &cap;
    var l: ptrdiff_t = @as(ptrdiff_t, @bitCast(get_onecapture(ms, i, s, e, &cap)));
    _ = &l;
    if (l != @as(ptrdiff_t, @bitCast(@as(c_long, -@as(c_int, 2))))) {
        _ = lua_pushlstring(ms.*.L, cap, @as(usize, @bitCast(l)));
    }
}
pub fn push_captures(arg_ms: [*c]MatchState, arg_s: [*c]const u8, arg_e: [*c]const u8) callconv(.c) c_int {
    var ms = arg_ms;
    _ = &ms;
    var s = arg_s;
    _ = &s;
    var e = arg_e;
    _ = &e;
    var i: c_int = undefined;
    _ = &i;
    var nlevels: c_int = if ((@as(c_int, @bitCast(@as(c_uint, ms.*.level))) == @as(c_int, 0)) and (s != null)) @as(c_int, 1) else @as(c_int, @bitCast(@as(c_uint, ms.*.level)));
    _ = &nlevels;
    luaL_checkstack(ms.*.L, nlevels, "too many captures");
    {
        i = 0;
        while (i < nlevels) : (i += 1) {
            push_onecapture(ms, i, s, e);
        }
    }
    return nlevels;
}
pub fn nospecials(arg_p: [*c]const u8, arg_l: usize) callconv(.c) c_int {
    var p = arg_p;
    _ = &p;
    var l = arg_l;
    _ = &l;
    var upto: usize = 0;
    _ = &upto;
    while (true) {
        if (strpbrk(p + upto, "^$*+?.([%-") != null) return 0;
        upto +%= @as(usize, @bitCast(strlen(p + upto) +% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1))))));
        if (!(upto <= l)) break;
    }
    return 1;
}
pub fn prepstate(arg_ms: [*c]MatchState, arg_L: ?*lua_State, arg_s: [*c]const u8, arg_ls: usize, arg_p: [*c]const u8, arg_lp: usize) callconv(.c) void {
    var ms = arg_ms;
    _ = &ms;
    var L = arg_L;
    _ = &L;
    var s = arg_s;
    _ = &s;
    var ls = arg_ls;
    _ = &ls;
    var p = arg_p;
    _ = &p;
    var lp = arg_lp;
    _ = &lp;
    ms.*.L = L;
    ms.*.matchdepth = 200;
    ms.*.src_init = s;
    ms.*.src_end = s + ls;
    ms.*.p_end = p + lp;
}
pub fn reprepstate(arg_ms: [*c]MatchState) callconv(.c) void {
    var ms = arg_ms;
    _ = &ms;
    ms.*.level = 0;
    _ = @as(c_int, 0);
}
pub fn str_find_aux(arg_L: ?*lua_State, arg_find: c_int) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var find = arg_find;
    _ = &find;
    var ls: usize = undefined;
    _ = &ls;
    var lp: usize = undefined;
    _ = &lp;
    var s: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &ls);
    _ = &s;
    var p: [*c]const u8 = luaL_checklstring(L, @as(c_int, 2), &lp);
    _ = &p;
    var init: usize = posrelatI(luaL_optinteger(L, @as(c_int, 3), @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 1))))), ls) -% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))));
    _ = &init;
    if (init > ls) {
        lua_pushnil(L);
        return 1;
    }
    if ((find != 0) and ((lua_toboolean(L, @as(c_int, 4)) != 0) or (nospecials(p, lp) != 0))) {
        var s2: [*c]const u8 = lmemfind(s + init, ls -% init, p, lp);
        _ = &s2;
        if (s2 != null) {
            lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_longlong, @divExact(@as(c_long, @bitCast(@intFromPtr(s2) -% @intFromPtr(s))), @sizeOf(u8)) + @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))))));
            lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_ulonglong, @as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(s2) -% @intFromPtr(s))), @sizeOf(u8)))) +% lp))));
            return 2;
        }
    } else {
        var ms: MatchState = undefined;
        _ = &ms;
        var s1: [*c]const u8 = s + init;
        _ = &s1;
        var anchor: c_int = @intFromBool(@as(c_int, @bitCast(@as(c_uint, p.*))) == @as(c_int, '^'));
        _ = &anchor;
        if (anchor != 0) {
            p += 1;
            lp -%= 1;
        }
        prepstate(&ms, L, s, ls, p, lp);
        while (true) {
            var res: [*c]const u8 = undefined;
            _ = &res;
            reprepstate(&ms);
            if ((blk: {
                const tmp = match(&ms, s1, p);
                res = tmp;
                break :blk tmp;
            }) != @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
                if (find != 0) {
                    lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_longlong, @divExact(@as(c_long, @bitCast(@intFromPtr(s1) -% @intFromPtr(s))), @sizeOf(u8)) + @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))))));
                    lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_longlong, @divExact(@as(c_long, @bitCast(@intFromPtr(res) -% @intFromPtr(s))), @sizeOf(u8))))));
                    return push_captures(&ms, null, null) + @as(c_int, 2);
                } else return push_captures(&ms, s1, res);
            }
            if (!(((blk: {
                const ref = &s1;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }) < ms.src_end) and !(anchor != 0))) break;
        }
    }
    lua_pushnil(L);
    return 1;
}
pub fn str_find(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    return str_find_aux(L, @as(c_int, 1));
}
pub fn str_match(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    return str_find_aux(L, @as(c_int, 0));
}
pub const struct_GMatchState = extern struct {
    src: [*c]const u8 = std.mem.zeroes([*c]const u8),
    p: [*c]const u8 = std.mem.zeroes([*c]const u8),
    lastmatch: [*c]const u8 = std.mem.zeroes([*c]const u8),
    ms: MatchState = std.mem.zeroes(MatchState),
};
pub const GMatchState = struct_GMatchState;
pub fn gmatch_aux(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var gm: [*c]GMatchState = @as([*c]GMatchState, @ptrCast(@alignCast(lua_touserdata(L, (-@as(c_int, 1000000) - @as(c_int, 1000)) - @as(c_int, 3)))));
    _ = &gm;
    var src: [*c]const u8 = undefined;
    _ = &src;
    gm.*.ms.L = L;
    {
        src = gm.*.src;
        while (src <= gm.*.ms.src_end) : (src += 1) {
            var e: [*c]const u8 = undefined;
            _ = &e;
            reprepstate(&gm.*.ms);
            if (((blk: {
                const tmp = match(&gm.*.ms, src, gm.*.p);
                e = tmp;
                break :blk tmp;
            }) != @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) and (e != gm.*.lastmatch)) {
                gm.*.src = blk: {
                    const tmp = e;
                    gm.*.lastmatch = tmp;
                    break :blk tmp;
                };
                return push_captures(&gm.*.ms, src, e);
            }
        }
    }
    return 0;
}
pub fn gmatch(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var ls: usize = undefined;
    _ = &ls;
    var lp: usize = undefined;
    _ = &lp;
    var s: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &ls);
    _ = &s;
    var p: [*c]const u8 = luaL_checklstring(L, @as(c_int, 2), &lp);
    _ = &p;
    var init: usize = posrelatI(luaL_optinteger(L, @as(c_int, 3), @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 1))))), ls) -% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))));
    _ = &init;
    var gm: [*c]GMatchState = undefined;
    _ = &gm;
    lua_settop(L, @as(c_int, 2));
    gm = @as([*c]GMatchState, @ptrCast(@alignCast(lua_newuserdatauv(L, @sizeOf(GMatchState), @as(c_int, 0)))));
    if (init > ls) {
        init = ls +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))));
    }
    prepstate(&gm.*.ms, L, s, ls, p, lp);
    gm.*.src = s + init;
    gm.*.p = p;
    gm.*.lastmatch = null;
    lua_pushcclosure(L, &gmatch_aux, @as(c_int, 3));
    return 1;
}
pub fn add_s(arg_ms: [*c]MatchState, arg_b: [*c]luaL_Buffer, arg_s: [*c]const u8, arg_e: [*c]const u8) callconv(.c) void {
    var ms = arg_ms;
    _ = &ms;
    var b = arg_b;
    _ = &b;
    var s = arg_s;
    _ = &s;
    var e = arg_e;
    _ = &e;
    var l: usize = undefined;
    _ = &l;
    var L: ?*lua_State = ms.*.L;
    _ = &L;
    var news: [*c]const u8 = lua_tolstring(L, @as(c_int, 3), &l);
    _ = &news;
    var p: [*c]const u8 = undefined;
    _ = &p;
    while ((blk: {
        const tmp = @as([*c]u8, @ptrCast(@alignCast(memchr(@as(?*const anyopaque, @ptrCast(news)), @as(c_int, '%'), l))));
        p = tmp;
        break :blk tmp;
    }) != @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        luaL_addlstring(b, news, @as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(p) -% @intFromPtr(news))), @sizeOf(u8)))));
        p += 1;
        if (@as(c_int, @bitCast(@as(c_uint, p.*))) == @as(c_int, '%')) {
            _ = blk: {
                _ = (b.*.n < b.*.size) or (luaL_prepbuffsize(b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                break :blk blk_1: {
                    const tmp = p.*;
                    b.*.b[blk_2: {
                        const ref = &b.*.n;
                        const tmp_3 = ref.*;
                        ref.* +%= 1;
                        break :blk_2 tmp_3;
                    }] = tmp;
                    break :blk_1 tmp;
                };
            };
        } else if (@as(c_int, @bitCast(@as(c_uint, p.*))) == @as(c_int, '0')) {
            luaL_addlstring(b, s, @as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(e) -% @intFromPtr(s))), @sizeOf(u8)))));
        } else if (isdigit(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(p.*)))))) != 0) {
            var cap: [*c]const u8 = undefined;
            _ = &cap;
            var resl: ptrdiff_t = @as(ptrdiff_t, @bitCast(get_onecapture(ms, @as(c_int, @bitCast(@as(c_uint, p.*))) - @as(c_int, '1'), s, e, &cap)));
            _ = &resl;
            if (resl == @as(ptrdiff_t, @bitCast(@as(c_long, -@as(c_int, 2))))) {
                luaL_addvalue(b);
            } else {
                luaL_addlstring(b, cap, @as(usize, @bitCast(resl)));
            }
        } else {
            _ = luaL_error(L, "invalid use of '%c' in replacement string", @as(c_int, '%'));
        }
        l -%= @as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))) -% @intFromPtr(news))), @sizeOf(u8))));
        news = p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
    }
    luaL_addlstring(b, news, l);
}
pub fn add_value(arg_ms: [*c]MatchState, arg_b: [*c]luaL_Buffer, arg_s: [*c]const u8, arg_e: [*c]const u8, arg_tr: c_int) callconv(.c) c_int {
    var ms = arg_ms;
    _ = &ms;
    var b = arg_b;
    _ = &b;
    var s = arg_s;
    _ = &s;
    var e = arg_e;
    _ = &e;
    var tr = arg_tr;
    _ = &tr;
    var L: ?*lua_State = ms.*.L;
    _ = &L;
    while (true) {
        switch (tr) {
            @as(c_int, 6) => {
                {
                    var n: c_int = undefined;
                    _ = &n;
                    lua_pushvalue(L, @as(c_int, 3));
                    n = push_captures(ms, s, e);
                    lua_callk(L, n, @as(c_int, 1), @as(lua_KContext, @bitCast(@as(c_long, @as(c_int, 0)))), null);
                    break;
                }
            },
            @as(c_int, 5) => {
                {
                    push_onecapture(ms, @as(c_int, 0), s, e);
                    _ = lua_gettable(L, @as(c_int, 3));
                    break;
                }
            },
            else => {
                {
                    add_s(ms, b, s, e);
                    return 1;
                }
            },
        }
        break;
    }
    if (!(lua_toboolean(L, -@as(c_int, 1)) != 0)) {
        lua_settop(L, -@as(c_int, 1) - @as(c_int, 1));
        luaL_addlstring(b, s, @as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(e) -% @intFromPtr(s))), @sizeOf(u8)))));
        return 0;
    } else if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(!(lua_isstring(L, -@as(c_int, 1)) != 0)) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) return luaL_error(L, "invalid replacement value (a %s)", lua_typename(L, lua_type(L, -@as(c_int, 1)))) else {
        luaL_addvalue(b);
        return 1;
    }
    return 0;
}
pub fn str_gsub(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var srcl: usize = undefined;
    _ = &srcl;
    var lp: usize = undefined;
    _ = &lp;
    var src: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), &srcl);
    _ = &src;
    var p: [*c]const u8 = luaL_checklstring(L, @as(c_int, 2), &lp);
    _ = &p;
    var lastmatch: [*c]const u8 = null;
    _ = &lastmatch;
    var tr: c_int = lua_type(L, @as(c_int, 3));
    _ = &tr;
    var max_s: lua_Integer = luaL_optinteger(L, @as(c_int, 4), @as(lua_Integer, @bitCast(@as(c_ulonglong, srcl +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))))));
    _ = &max_s;
    var anchor: c_int = @intFromBool(@as(c_int, @bitCast(@as(c_uint, p.*))) == @as(c_int, '^'));
    _ = &anchor;
    var n: lua_Integer = 0;
    _ = &n;
    var changed: c_int = 0;
    _ = &changed;
    var ms: MatchState = undefined;
    _ = &ms;
    var b: luaL_Buffer = undefined;
    _ = &b;
    _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((((tr == @as(c_int, 3)) or (tr == @as(c_int, 4))) or (tr == @as(c_int, 6))) or (tr == @as(c_int, 5))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_typeerror(L, @as(c_int, 3), "string/function/table") != 0);
    luaL_buffinit(L, &b);
    if (anchor != 0) {
        p += 1;
        lp -%= 1;
    }
    prepstate(&ms, L, src, srcl, p, lp);
    while (n < max_s) {
        var e: [*c]const u8 = undefined;
        _ = &e;
        reprepstate(&ms);
        if (((blk: {
            const tmp = match(&ms, src, p);
            e = tmp;
            break :blk tmp;
        }) != @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) and (e != lastmatch)) {
            n += 1;
            changed = add_value(&ms, &b, src, e, tr) | changed;
            src = blk: {
                const tmp = e;
                lastmatch = tmp;
                break :blk tmp;
            };
        } else if (src < ms.src_end) {
            _ = blk: {
                _ = ((&b).*.n < (&b).*.size) or (luaL_prepbuffsize(&b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                break :blk blk_1: {
                    const tmp = (blk_2: {
                        const ref = &src;
                        const tmp_3 = ref.*;
                        ref.* += 1;
                        break :blk_2 tmp_3;
                    }).*;
                    (&b).*.b[blk_2: {
                        const ref = &(&b).*.n;
                        const tmp_3 = ref.*;
                        ref.* +%= 1;
                        break :blk_2 tmp_3;
                    }] = tmp;
                    break :blk_1 tmp;
                };
            };
        } else break;
        if (anchor != 0) break;
    }
    if (!(changed != 0)) {
        lua_pushvalue(L, @as(c_int, 1));
    } else {
        luaL_addlstring(&b, src, @as(usize, @bitCast(@divExact(@as(c_long, @bitCast(@intFromPtr(ms.src_end) -% @intFromPtr(src))), @sizeOf(u8)))));
        luaL_pushresult(&b);
    }
    lua_pushinteger(L, n);
    return 2;
}
pub fn addquoted(arg_b: [*c]luaL_Buffer, arg_s: [*c]const u8, arg_len: usize) callconv(.c) void {
    var b = arg_b;
    _ = &b;
    var s = arg_s;
    _ = &s;
    var len = arg_len;
    _ = &len;
    _ = blk: {
        _ = (b.*.n < b.*.size) or (luaL_prepbuffsize(b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
        break :blk blk_1: {
            const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, '"')))));
            b.*.b[blk_2: {
                const ref = &b.*.n;
                const tmp_3 = ref.*;
                ref.* +%= 1;
                break :blk_2 tmp_3;
            }] = tmp;
            break :blk_1 tmp;
        };
    };
    while ((blk: {
        const ref = &len;
        const tmp = ref.*;
        ref.* -%= 1;
        break :blk tmp;
    }) != 0) {
        if (((@as(c_int, @bitCast(@as(c_uint, s.*))) == @as(c_int, '"')) or (@as(c_int, @bitCast(@as(c_uint, s.*))) == @as(c_int, '\\'))) or (@as(c_int, @bitCast(@as(c_uint, s.*))) == @as(c_int, '\n'))) {
            _ = blk: {
                _ = (b.*.n < b.*.size) or (luaL_prepbuffsize(b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                break :blk blk_1: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, '\\')))));
                    b.*.b[blk_2: {
                        const ref = &b.*.n;
                        const tmp_3 = ref.*;
                        ref.* +%= 1;
                        break :blk_2 tmp_3;
                    }] = tmp;
                    break :blk_1 tmp;
                };
            };
            _ = blk: {
                _ = (b.*.n < b.*.size) or (luaL_prepbuffsize(b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                break :blk blk_1: {
                    const tmp = s.*;
                    b.*.b[blk_2: {
                        const ref = &b.*.n;
                        const tmp_3 = ref.*;
                        ref.* +%= 1;
                        break :blk_2 tmp_3;
                    }] = tmp;
                    break :blk_1 tmp;
                };
            };
        } else if (iscntrl(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(s.*)))))) != 0) {
            var buff: [10]u8 = undefined;
            _ = &buff;
            if (!(isdigit(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((s + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).*)))))) != 0)) {
                _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&buff[@as(usize, @intCast(0))]))), @sizeOf([10]u8), "\\%d", @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(s.*))))));
            } else {
                _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&buff[@as(usize, @intCast(0))]))), @sizeOf([10]u8), "\\%03d", @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(s.*))))));
            }
            luaL_addstring(b, @as([*c]u8, @ptrCast(@alignCast(&buff[@as(usize, @intCast(0))]))));
        } else {
            _ = blk: {
                _ = (b.*.n < b.*.size) or (luaL_prepbuffsize(b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                break :blk blk_1: {
                    const tmp = s.*;
                    b.*.b[blk_2: {
                        const ref = &b.*.n;
                        const tmp_3 = ref.*;
                        ref.* +%= 1;
                        break :blk_2 tmp_3;
                    }] = tmp;
                    break :blk_1 tmp;
                };
            };
        }
        s += 1;
    }
    _ = blk: {
        _ = (b.*.n < b.*.size) or (luaL_prepbuffsize(b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
        break :blk blk_1: {
            const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, '"')))));
            b.*.b[blk_2: {
                const ref = &b.*.n;
                const tmp_3 = ref.*;
                ref.* +%= 1;
                break :blk_2 tmp_3;
            }] = tmp;
            break :blk_1 tmp;
        };
    };
}
// /src/cosmopolitan/libc/math.h:136:19: warning: TODO implement function '__builtin_inf' in std.zig.c_builtins

// /src/cosmopolitan/third_party/lua/lstrlib.c:1190:12: warning: unable to translate function, demoted to extern
pub extern fn quotefloat(arg_L: ?*lua_State, arg_buff: [*c]u8, arg_n: lua_Number) callconv(.c) c_int;
pub fn addliteral(arg_L: ?*lua_State, arg_b: [*c]luaL_Buffer, arg_arg: c_int) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var b = arg_b;
    _ = &b;
    var arg = arg_arg;
    _ = &arg;
    while (true) {
        switch (lua_type(L, arg)) {
            @as(c_int, 4) => {
                {
                    var len: usize = undefined;
                    _ = &len;
                    var s: [*c]const u8 = lua_tolstring(L, arg, &len);
                    _ = &s;
                    addquoted(b, s, len);
                    break;
                }
            },
            @as(c_int, 3) => {
                {
                    var buff: [*c]u8 = luaL_prepbuffsize(b, @as(usize, @bitCast(@as(c_long, @as(c_int, 120)))));
                    _ = &buff;
                    var nb: c_int = undefined;
                    _ = &nb;
                    if (!(lua_isinteger(L, arg) != 0)) {
                        nb = quotefloat(L, buff, lua_tonumberx(L, arg, null));
                    } else {
                        var n: lua_Integer = lua_tointegerx(L, arg, null);
                        _ = &n;
                        var format: [*c]const u8 = if (n == (-@as(c_longlong, 9223372036854775807) - @as(c_longlong, @bitCast(@as(c_longlong, @as(c_int, 1)))))) "0x%llx" else "%lld";
                        _ = &format;
                        nb = snprintf(buff, @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 120)))), format, @as(c_longlong, @bitCast(n)));
                    }
                    _ = blk: {
                        const ref = &b.*.n;
                        ref.* +%= @as(usize, @bitCast(@as(c_long, nb)));
                        break :blk ref.*;
                    };
                    break;
                }
            },
            @as(c_int, 0), @as(c_int, 1) => {
                {
                    _ = luaL_tolstring(L, arg, null);
                    luaL_addvalue(b);
                    break;
                }
            },
            else => {
                {
                    _ = luaL_argerror(L, arg, "value has no literal form");
                }
            },
        }
        break;
    }
}
pub fn get2digits(arg_s: [*c]const u8) callconv(.c) [*c]const u8 {
    var s = arg_s;
    _ = &s;
    if (isdigit(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(s.*)))))) != 0) {
        s += 1;
        if (isdigit(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(s.*)))))) != 0) {
            s += 1;
        }
    }
    return s;
}
pub fn checkformat(arg_L: ?*lua_State, arg_form: [*c]const u8, arg_flags: [*c]const u8, arg_precision: c_int) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var form = arg_form;
    _ = &form;
    var flags = arg_flags;
    _ = &flags;
    var precision = arg_precision;
    _ = &precision;
    var spec: [*c]const u8 = form + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
    _ = &spec;
    spec += strspn(spec, flags);
    if (@as(c_int, @bitCast(@as(c_uint, spec.*))) != @as(c_int, '0')) {
        spec = get2digits(spec);
        if ((@as(c_int, @bitCast(@as(c_uint, spec.*))) == @as(c_int, '.')) and (precision != 0)) {
            spec += 1;
            spec = get2digits(spec);
        }
    }
    if (!(isalpha(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(spec.*)))))) != 0)) {
        _ = luaL_error(L, "invalid conversion specification: '%s'", form);
    }
}
pub fn getformat(arg_L: ?*lua_State, arg_strfrmt: [*c]const u8, arg_form: [*c]u8) callconv(.c) [*c]const u8 {
    var L = arg_L;
    _ = &L;
    var strfrmt = arg_strfrmt;
    _ = &strfrmt;
    var form = arg_form;
    _ = &form;
    var len: usize = strspn(strfrmt, "-+#0 123456789.");
    _ = &len;
    len +%= 1;
    if (len >= @as(usize, @bitCast(@as(c_long, @as(c_int, 32) - @as(c_int, 10))))) {
        _ = luaL_error(L, "invalid format (too long)");
    }
    (blk: {
        const ref = &form;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).* = '%';
    _ = memcpy(@as(?*anyopaque, @ptrCast(form)), @as(?*const anyopaque, @ptrCast(strfrmt)), len *% @sizeOf(u8));
    (form + len).* = '\x00';
    return (strfrmt + len) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
}
pub fn addlenmod(arg_form: [*c]u8, arg_lenmod: [*c]const u8) callconv(.c) void {
    var form = arg_form;
    _ = &form;
    var lenmod = arg_lenmod;
    _ = &lenmod;
    var l: usize = strlen(form);
    _ = &l;
    var lm: usize = strlen(lenmod);
    _ = &lm;
    var spec: u8 = form[l -% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))];
    _ = &spec;
    _ = strcpy((form + l) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))), lenmod);
    form[(l +% lm) -% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))] = spec;
    form[l +% lm] = '\x00';
}
const union_unnamed_6 = extern union {
    dummy: c_int,
    little: u8,
};
pub const nativeendian: union_unnamed_6 = union_unnamed_6{
    .dummy = @as(c_int, 1),
};
pub const struct_Header = extern struct {
    L: ?*lua_State = std.mem.zeroes(?*lua_State),
    islittle: c_int = std.mem.zeroes(c_int),
    maxalign: c_int = std.mem.zeroes(c_int),
};
pub const Header = struct_Header;
pub const Kint: c_int = 0;
pub const Kuint: c_int = 1;
pub const Kfloat: c_int = 2;
pub const Knumber: c_int = 3;
pub const Kdouble: c_int = 4;
pub const Kchar: c_int = 5;
pub const Kstring: c_int = 6;
pub const Kzstr: c_int = 7;
pub const Kpadding: c_int = 8;
pub const Kpaddalign: c_int = 9;
pub const Knop: c_int = 10;
pub const enum_KOption = c_uint;
pub const KOption = enum_KOption;
pub fn digit(arg_c: c_int) callconv(.c) c_int {
    var c = arg_c;
    _ = &c;
    return @intFromBool((@as(c_int, '0') <= c) and (c <= @as(c_int, '9')));
}
pub fn getnum(arg_fmt: [*c][*c]const u8, arg_df: c_int) callconv(.c) c_int {
    var fmt = arg_fmt;
    _ = &fmt;
    var df = arg_df;
    _ = &df;
    if (!(digit(@as(c_int, @bitCast(@as(c_uint, fmt.*.*)))) != 0)) return df else {
        var a: c_int = 0;
        _ = &a;
        while (true) {
            a = (a * @as(c_int, 10)) + (@as(c_int, @bitCast(@as(c_uint, (blk: {
                const ref = &fmt.*;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }).*))) - @as(c_int, '0'));
            if (!((digit(@as(c_int, @bitCast(@as(c_uint, fmt.*.*)))) != 0) and (a <= @divTrunc(@as(c_int, @bitCast(@as(c_uint, @truncate(if (@sizeOf(usize) < @sizeOf(c_int)) ~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) else @as(usize, @bitCast(@as(c_long, @as(c_int, 2147483647)))))))) - @as(c_int, 9), @as(c_int, 10))))) break;
        }
        return a;
    }
    return 0;
}
pub fn getnumlimit(arg_h: [*c]Header, arg_fmt: [*c][*c]const u8, arg_df: c_int) callconv(.c) c_int {
    var h = arg_h;
    _ = &h;
    var fmt = arg_fmt;
    _ = &fmt;
    var df = arg_df;
    _ = &df;
    var sz: c_int = getnum(fmt, df);
    _ = &sz;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((sz > @as(c_int, 16)) or (sz <= @as(c_int, 0))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) return luaL_error(h.*.L, "integral size (%d) out of limits [1,%d]", sz, @as(c_int, 16));
    return sz;
}
pub fn initheader(arg_L: ?*lua_State, arg_h: [*c]Header) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var h = arg_h;
    _ = &h;
    h.*.L = L;
    h.*.islittle = @as(c_int, @bitCast(@as(c_uint, nativeendian.little)));
    h.*.maxalign = 1;
}
const union_unnamed_7 = extern union {
    n: lua_Number,
    u: f64,
    s: ?*anyopaque,
    i: lua_Integer,
    l: c_long,
};
pub fn getoption(arg_h: [*c]Header, arg_fmt: [*c][*c]const u8, arg_size: [*c]c_int) callconv(.c) KOption {
    var h = arg_h;
    _ = &h;
    var fmt = arg_fmt;
    _ = &fmt;
    var size = arg_size;
    _ = &size;
    const struct_cD = extern struct {
        c: u8 = std.mem.zeroes(u8),
        u: union_unnamed_7 = std.mem.zeroes(union_unnamed_7),
    };
    _ = &struct_cD;
    var opt: c_int = @as(c_int, @bitCast(@as(c_uint, (blk: {
        const ref = &fmt.*;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).*)));
    _ = &opt;
    size.* = 0;
    while (true) {
        switch (opt) {
            @as(c_int, 98) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))));
                return @as(c_uint, @bitCast(Kint));
            },
            @as(c_int, 66) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))));
                return @as(c_uint, @bitCast(Kuint));
            },
            @as(c_int, 104) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(c_short)))));
                return @as(c_uint, @bitCast(Kint));
            },
            @as(c_int, 72) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(c_short)))));
                return @as(c_uint, @bitCast(Kuint));
            },
            @as(c_int, 108) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(c_long)))));
                return @as(c_uint, @bitCast(Kint));
            },
            @as(c_int, 76) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(c_long)))));
                return @as(c_uint, @bitCast(Kuint));
            },
            @as(c_int, 106) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))));
                return @as(c_uint, @bitCast(Kint));
            },
            @as(c_int, 74) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))));
                return @as(c_uint, @bitCast(Kuint));
            },
            @as(c_int, 84) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(usize)))));
                return @as(c_uint, @bitCast(Kuint));
            },
            @as(c_int, 102) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(f32)))));
                return @as(c_uint, @bitCast(Kfloat));
            },
            @as(c_int, 110) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Number)))));
                return @as(c_uint, @bitCast(Knumber));
            },
            @as(c_int, 100) => {
                size.* = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(f64)))));
                return @as(c_uint, @bitCast(Kdouble));
            },
            @as(c_int, 105) => {
                size.* = getnumlimit(h, fmt, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(c_int))))));
                return @as(c_uint, @bitCast(Kint));
            },
            @as(c_int, 73) => {
                size.* = getnumlimit(h, fmt, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(c_int))))));
                return @as(c_uint, @bitCast(Kuint));
            },
            @as(c_int, 115) => {
                size.* = getnumlimit(h, fmt, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(usize))))));
                return @as(c_uint, @bitCast(Kstring));
            },
            @as(c_int, 99) => {
                size.* = getnum(fmt, -@as(c_int, 1));
                if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(size.* == -@as(c_int, 1)) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
                    _ = luaL_error(h.*.L, "missing size for format option 'c'");
                }
                return @as(c_uint, @bitCast(Kchar));
            },
            @as(c_int, 122) => return @as(c_uint, @bitCast(Kzstr)),
            @as(c_int, 120) => {
                size.* = 1;
                return @as(c_uint, @bitCast(Kpadding));
            },
            @as(c_int, 88) => return @as(c_uint, @bitCast(Kpaddalign)),
            @as(c_int, 32) => break,
            @as(c_int, 60) => {
                h.*.islittle = 1;
                break;
            },
            @as(c_int, 62) => {
                h.*.islittle = 0;
                break;
            },
            @as(c_int, 61) => {
                h.*.islittle = @as(c_int, @bitCast(@as(c_uint, nativeendian.little)));
                break;
            },
            @as(c_int, 33) => {
                {
                    const maxalign: c_int = @as(c_int, @bitCast(@as(c_uint, @truncate(@offsetOf(struct_cD, "u")))));
                    _ = &maxalign;
                    h.*.maxalign = getnumlimit(h, fmt, maxalign);
                    break;
                }
            },
            else => {
                _ = luaL_error(h.*.L, "invalid format option '%c'", opt);
            },
        }
        break;
    }
    return @as(c_uint, @bitCast(Knop));
}
pub fn getdetails(arg_h: [*c]Header, arg_totalsize: usize, arg_fmt: [*c][*c]const u8, arg_psize: [*c]c_int, arg_ntoalign: [*c]c_int) callconv(.c) KOption {
    var h = arg_h;
    _ = &h;
    var totalsize = arg_totalsize;
    _ = &totalsize;
    var fmt = arg_fmt;
    _ = &fmt;
    var psize = arg_psize;
    _ = &psize;
    var ntoalign = arg_ntoalign;
    _ = &ntoalign;
    var opt: KOption = getoption(h, fmt, psize);
    _ = &opt;
    var @"align": c_int = psize.*;
    _ = &@"align";
    if (opt == @as(c_uint, @bitCast(Kpaddalign))) {
        if (((@as(c_int, @bitCast(@as(c_uint, fmt.*.*))) == @as(c_int, '\x00')) or (getoption(h, fmt, &@"align") == @as(c_uint, @bitCast(Kchar)))) or (@"align" == @as(c_int, 0))) {
            _ = luaL_argerror(h.*.L, @as(c_int, 1), "invalid next option for option 'X'");
        }
    }
    if ((@"align" <= @as(c_int, 1)) or (opt == @as(c_uint, @bitCast(Kchar)))) {
        ntoalign.* = 0;
    } else {
        if (@"align" > h.*.maxalign) {
            @"align" = h.*.maxalign;
        }
        if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((@"align" & (@"align" - @as(c_int, 1))) != @as(c_int, 0)) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
            _ = luaL_argerror(h.*.L, @as(c_int, 1), "format asks for alignment not power of 2");
        }
        ntoalign.* = (@"align" - @as(c_int, @bitCast(@as(c_uint, @truncate(totalsize & @as(usize, @bitCast(@as(c_long, @"align" - @as(c_int, 1))))))))) & (@"align" - @as(c_int, 1));
    }
    return opt;
}
pub fn packint(arg_b: [*c]luaL_Buffer, arg_n: lua_Unsigned, arg_islittle: c_int, arg_size: c_int, arg_neg: c_int) callconv(.c) void {
    var b = arg_b;
    _ = &b;
    var n = arg_n;
    _ = &n;
    var islittle = arg_islittle;
    _ = &islittle;
    var size = arg_size;
    _ = &size;
    var neg = arg_neg;
    _ = &neg;
    var buff: [*c]u8 = luaL_prepbuffsize(b, @as(usize, @bitCast(@as(c_long, size))));
    _ = &buff;
    var i: c_int = undefined;
    _ = &i;
    (blk: {
        const tmp = if (islittle != 0) @as(c_int, 0) else size - @as(c_int, 1);
        if (tmp >= 0) break :blk buff + @as(usize, @intCast(tmp)) else break :blk buff - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).* = @as(u8, @bitCast(@as(u8, @truncate(n & @as(lua_Unsigned, @bitCast(@as(c_longlong, (@as(c_int, 1) << @intCast(8)) - @as(c_int, 1))))))));
    {
        i = 1;
        while (i < size) : (i += 1) {
            n >>= @intCast(@as(c_int, 8));
            (blk: {
                const tmp = if (islittle != 0) i else (size - @as(c_int, 1)) - i;
                if (tmp >= 0) break :blk buff + @as(usize, @intCast(tmp)) else break :blk buff - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(u8, @bitCast(@as(u8, @truncate(n & @as(lua_Unsigned, @bitCast(@as(c_longlong, (@as(c_int, 1) << @intCast(8)) - @as(c_int, 1))))))));
        }
    }
    if ((neg != 0) and (size > @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer))))))) {
        {
            i = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))));
            while (i < size) : (i += 1) {
                (blk: {
                    const tmp = if (islittle != 0) i else (size - @as(c_int, 1)) - i;
                    if (tmp >= 0) break :blk buff + @as(usize, @intCast(tmp)) else break :blk buff - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = @as(u8, @bitCast(@as(i8, @truncate((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)))));
            }
        }
    }
    _ = blk: {
        const ref = &b.*.n;
        ref.* +%= @as(usize, @bitCast(@as(c_long, size)));
        break :blk ref.*;
    };
}
pub fn copywithendian(arg_dest: [*c]u8, arg_src: [*c]const u8, arg_size: c_int, arg_islittle: c_int) callconv(.c) void {
    var dest = arg_dest;
    _ = &dest;
    var src = arg_src;
    _ = &src;
    var size = arg_size;
    _ = &size;
    var islittle = arg_islittle;
    _ = &islittle;
    if (islittle == @as(c_int, @bitCast(@as(c_uint, nativeendian.little)))) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(dest)), @as(?*const anyopaque, @ptrCast(src)), @as(c_ulong, @bitCast(@as(c_long, size))));
    } else {
        dest += @as(usize, @bitCast(@as(isize, @intCast(size - @as(c_int, 1)))));
        while ((blk: {
            const ref = &size;
            const tmp = ref.*;
            ref.* -= 1;
            break :blk tmp;
        }) != @as(c_int, 0)) {
            (blk: {
                const ref = &dest;
                const tmp = ref.*;
                ref.* -= 1;
                break :blk tmp;
            }).* = (blk: {
                const ref = &src;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }).*;
        }
    }
}
pub fn str_pack(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var b: luaL_Buffer = undefined;
    _ = &b;
    var h: Header = undefined;
    _ = &h;
    var fmt: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), null);
    _ = &fmt;
    var arg: c_int = 1;
    _ = &arg;
    var totalsize: usize = 0;
    _ = &totalsize;
    initheader(L, &h);
    lua_pushnil(L);
    luaL_buffinit(L, &b);
    while (@as(c_int, @bitCast(@as(c_uint, fmt.*))) != @as(c_int, '\x00')) {
        var size: c_int = undefined;
        _ = &size;
        var ntoalign: c_int = undefined;
        _ = &ntoalign;
        var opt: KOption = getdetails(&h, totalsize, &fmt, &size, &ntoalign);
        _ = &opt;
        totalsize +%= @as(usize, @bitCast(@as(c_long, ntoalign + size)));
        while ((blk: {
            const ref = &ntoalign;
            const tmp = ref.*;
            ref.* -= 1;
            break :blk tmp;
        }) > @as(c_int, 0)) {
            _ = blk: {
                _ = ((&b).*.n < (&b).*.size) or (luaL_prepbuffsize(&b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                break :blk blk_1: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 0)))));
                    (&b).*.b[blk_2: {
                        const ref = &(&b).*.n;
                        const tmp_3 = ref.*;
                        ref.* +%= 1;
                        break :blk_2 tmp_3;
                    }] = tmp;
                    break :blk_1 tmp;
                };
            };
        }
        arg += 1;
        while (true) {
            switch (opt) {
                @as(c_uint, @bitCast(@as(c_int, 0))) => {
                    {
                        var n: lua_Integer = luaL_checkinteger(L, arg);
                        _ = &n;
                        if (size < @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))))) {
                            var lim: lua_Integer = @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 1)))) << @intCast((size * @as(c_int, 8)) - @as(c_int, 1));
                            _ = &lim;
                            _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((-lim <= n) and (n < lim)) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, arg, "integer overflow") != 0);
                        }
                        packint(&b, @as(lua_Unsigned, @bitCast(n)), h.islittle, size, @intFromBool(n < @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 0))))));
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 1))) => {
                    {
                        var n: lua_Integer = luaL_checkinteger(L, arg);
                        _ = &n;
                        if (size < @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))))) {
                            _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@as(lua_Unsigned, @bitCast(n)) < (@as(lua_Unsigned, @bitCast(@as(c_longlong, @as(c_int, 1)))) << @intCast(size * @as(c_int, 8)))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, arg, "unsigned overflow") != 0);
                        }
                        packint(&b, @as(lua_Unsigned, @bitCast(n)), h.islittle, size, @as(c_int, 0));
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 2))) => {
                    {
                        var f: f32 = @as(f32, @floatCast(luaL_checknumber(L, arg)));
                        _ = &f;
                        var buff: [*c]u8 = luaL_prepbuffsize(&b, @sizeOf(f32));
                        _ = &buff;
                        copywithendian(buff, @as([*c]u8, @ptrCast(@alignCast(&f))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(f32))))), h.islittle);
                        _ = blk: {
                            const ref = &(&b).*.n;
                            ref.* +%= @as(usize, @bitCast(@as(c_long, size)));
                            break :blk ref.*;
                        };
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 3))) => {
                    {
                        var f: lua_Number = luaL_checknumber(L, arg);
                        _ = &f;
                        var buff: [*c]u8 = luaL_prepbuffsize(&b, @sizeOf(lua_Number));
                        _ = &buff;
                        copywithendian(buff, @as([*c]u8, @ptrCast(@alignCast(&f))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Number))))), h.islittle);
                        _ = blk: {
                            const ref = &(&b).*.n;
                            ref.* +%= @as(usize, @bitCast(@as(c_long, size)));
                            break :blk ref.*;
                        };
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 4))) => {
                    {
                        var f: f64 = @as(f64, @floatCast(luaL_checknumber(L, arg)));
                        _ = &f;
                        var buff: [*c]u8 = luaL_prepbuffsize(&b, @sizeOf(f64));
                        _ = &buff;
                        copywithendian(buff, @as([*c]u8, @ptrCast(@alignCast(&f))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(f64))))), h.islittle);
                        _ = blk: {
                            const ref = &(&b).*.n;
                            ref.* +%= @as(usize, @bitCast(@as(c_long, size)));
                            break :blk ref.*;
                        };
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 5))) => {
                    {
                        var len: usize = undefined;
                        _ = &len;
                        var s: [*c]const u8 = luaL_checklstring(L, arg, &len);
                        _ = &s;
                        _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(len <= @as(usize, @bitCast(@as(c_long, size)))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, arg, "string longer than given size") != 0);
                        luaL_addlstring(&b, s, len);
                        while ((blk: {
                            const ref = &len;
                            const tmp = ref.*;
                            ref.* +%= 1;
                            break :blk tmp;
                        }) < @as(usize, @bitCast(@as(c_long, size)))) {
                            _ = blk: {
                                _ = ((&b).*.n < (&b).*.size) or (luaL_prepbuffsize(&b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                                break :blk blk_1: {
                                    const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 0)))));
                                    (&b).*.b[blk_2: {
                                        const ref = &(&b).*.n;
                                        const tmp_3 = ref.*;
                                        ref.* +%= 1;
                                        break :blk_2 tmp_3;
                                    }] = tmp;
                                    break :blk_1 tmp;
                                };
                            };
                        }
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 6))) => {
                    {
                        var len: usize = undefined;
                        _ = &len;
                        var s: [*c]const u8 = luaL_checklstring(L, arg, &len);
                        _ = &s;
                        _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((size >= @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(usize)))))) or (len < (@as(usize, @bitCast(@as(c_long, @as(c_int, 1)))) << @intCast(size * @as(c_int, 8))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, arg, "string length does not fit in given size") != 0);
                        packint(&b, @as(lua_Unsigned, @bitCast(@as(c_ulonglong, len))), h.islittle, size, @as(c_int, 0));
                        luaL_addlstring(&b, s, len);
                        totalsize +%= len;
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 7))) => {
                    {
                        var len: usize = undefined;
                        _ = &len;
                        var s: [*c]const u8 = luaL_checklstring(L, arg, &len);
                        _ = &s;
                        _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(strlen(s) == len) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, arg, "string contains zeros") != 0);
                        luaL_addlstring(&b, s, len);
                        _ = blk: {
                            _ = ((&b).*.n < (&b).*.size) or (luaL_prepbuffsize(&b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                            break :blk blk_1: {
                                const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, '\x00')))));
                                (&b).*.b[blk_2: {
                                    const ref = &(&b).*.n;
                                    const tmp_3 = ref.*;
                                    ref.* +%= 1;
                                    break :blk_2 tmp_3;
                                }] = tmp;
                                break :blk_1 tmp;
                            };
                        };
                        totalsize +%= len +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))));
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 8))) => {
                    _ = blk: {
                        _ = ((&b).*.n < (&b).*.size) or (luaL_prepbuffsize(&b, @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) != null);
                        break :blk blk_1: {
                            const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 0)))));
                            (&b).*.b[blk_2: {
                                const ref = &(&b).*.n;
                                const tmp_3 = ref.*;
                                ref.* +%= 1;
                                break :blk_2 tmp_3;
                            }] = tmp;
                            break :blk_1 tmp;
                        };
                    };
                    arg -= 1;
                    break;
                },
                @as(c_uint, @bitCast(@as(c_int, 9))), @as(c_uint, @bitCast(@as(c_int, 10))) => {
                    arg -= 1;
                    break;
                },
                else => {},
            }
            break;
        }
    }
    luaL_pushresult(&b);
    return 1;
}
pub fn str_packsize(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var h: Header = undefined;
    _ = &h;
    var fmt: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), null);
    _ = &fmt;
    var totalsize: usize = 0;
    _ = &totalsize;
    initheader(L, &h);
    while (@as(c_int, @bitCast(@as(c_uint, fmt.*))) != @as(c_int, '\x00')) {
        var size: c_int = undefined;
        _ = &size;
        var ntoalign: c_int = undefined;
        _ = &ntoalign;
        var opt: KOption = getdetails(&h, totalsize, &fmt, &size, &ntoalign);
        _ = &opt;
        _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((opt != @as(c_uint, @bitCast(Kstring))) and (opt != @as(c_uint, @bitCast(Kzstr)))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, @as(c_int, 1), "variable-length format") != 0);
        size += ntoalign;
        _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(totalsize <= ((if (@sizeOf(usize) < @sizeOf(c_int)) ~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) else @as(usize, @bitCast(@as(c_long, @as(c_int, 2147483647))))) -% @as(usize, @bitCast(@as(c_long, size))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, @as(c_int, 1), "format result too large") != 0);
        totalsize +%= @as(usize, @bitCast(@as(c_long, size)));
    }
    lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_ulonglong, totalsize))));
    return 1;
}
pub fn unpackint(arg_L: ?*lua_State, arg_str: [*c]const u8, arg_islittle: c_int, arg_size: c_int, arg_issigned: c_int) callconv(.c) lua_Integer {
    var L = arg_L;
    _ = &L;
    var str = arg_str;
    _ = &str;
    var islittle = arg_islittle;
    _ = &islittle;
    var size = arg_size;
    _ = &size;
    var issigned = arg_issigned;
    _ = &issigned;
    var res: lua_Unsigned = 0;
    _ = &res;
    var i: c_int = undefined;
    _ = &i;
    var limit: c_int = if (size <= @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))))) size else @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))));
    _ = &limit;
    {
        i = limit - @as(c_int, 1);
        while (i >= @as(c_int, 0)) : (i -= 1) {
            res <<= @intCast(@as(c_int, 8));
            res |= @as(lua_Unsigned, @bitCast(@as(c_ulonglong, @as(u8, @bitCast((blk: {
                const tmp = if (islittle != 0) i else (size - @as(c_int, 1)) - i;
                if (tmp >= 0) break :blk str + @as(usize, @intCast(tmp)) else break :blk str - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))));
        }
    }
    if (size < @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))))) {
        if (issigned != 0) {
            var mask: lua_Unsigned = @as(lua_Unsigned, @bitCast(@as(c_longlong, @as(c_int, 1)))) << @intCast((size * @as(c_int, 8)) - @as(c_int, 1));
            _ = &mask;
            res = (res ^ mask) -% mask;
        }
    } else if (size > @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Integer)))))) {
        var mask: c_int = if (!(issigned != 0) or (@as(lua_Integer, @bitCast(res)) >= @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 0)))))) @as(c_int, 0) else (@as(c_int, 1) << @intCast(8)) - @as(c_int, 1);
        _ = &mask;
        {
            i = limit;
            while (i < size) : (i += 1) {
                if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk: {
                    const tmp = if (islittle != 0) i else (size - @as(c_int, 1)) - i;
                    if (tmp >= 0) break :blk str + @as(usize, @intCast(tmp)) else break :blk str - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*))))) != mask) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 0))))) != 0) {
                    _ = luaL_error(L, "%d-byte integer does not fit into Lua Integer", size);
                }
            }
        }
    }
    return @as(lua_Integer, @bitCast(res));
}
pub fn str_unpack(arg_L: ?*lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var h: Header = undefined;
    _ = &h;
    var fmt: [*c]const u8 = luaL_checklstring(L, @as(c_int, 1), null);
    _ = &fmt;
    var ld: usize = undefined;
    _ = &ld;
    var data: [*c]const u8 = luaL_checklstring(L, @as(c_int, 2), &ld);
    _ = &data;
    var pos: usize = posrelatI(luaL_optinteger(L, @as(c_int, 3), @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 1))))), ld) -% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))));
    _ = &pos;
    var n: c_int = 0;
    _ = &n;
    _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(pos <= ld) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, @as(c_int, 3), "initial position out of string") != 0);
    initheader(L, &h);
    while (@as(c_int, @bitCast(@as(c_uint, fmt.*))) != @as(c_int, '\x00')) {
        var size: c_int = undefined;
        _ = &size;
        var ntoalign: c_int = undefined;
        _ = &ntoalign;
        var opt: KOption = getdetails(&h, pos, &fmt, &size, &ntoalign);
        _ = &opt;
        _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((@as(usize, @bitCast(@as(c_long, ntoalign))) +% @as(usize, @bitCast(@as(c_long, size)))) <= (ld -% pos)) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, @as(c_int, 2), "data string too short") != 0);
        pos +%= @as(usize, @bitCast(@as(c_long, ntoalign)));
        luaL_checkstack(L, @as(c_int, 2), "too many results");
        n += 1;
        while (true) {
            switch (opt) {
                @as(c_uint, @bitCast(@as(c_int, 0))), @as(c_uint, @bitCast(@as(c_int, 1))) => {
                    {
                        var res: lua_Integer = unpackint(L, data + pos, h.islittle, size, @intFromBool(opt == @as(c_uint, @bitCast(Kint))));
                        _ = &res;
                        lua_pushinteger(L, res);
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 2))) => {
                    {
                        var f: f32 = undefined;
                        _ = &f;
                        copywithendian(@as([*c]u8, @ptrCast(@alignCast(&f))), data + pos, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(f32))))), h.islittle);
                        lua_pushnumber(L, @as(lua_Number, @floatCast(f)));
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 3))) => {
                    {
                        var f: lua_Number = undefined;
                        _ = &f;
                        copywithendian(@as([*c]u8, @ptrCast(@alignCast(&f))), data + pos, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(lua_Number))))), h.islittle);
                        lua_pushnumber(L, f);
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 4))) => {
                    {
                        var f: f64 = undefined;
                        _ = &f;
                        copywithendian(@as([*c]u8, @ptrCast(@alignCast(&f))), data + pos, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(f64))))), h.islittle);
                        lua_pushnumber(L, @as(lua_Number, @floatCast(f)));
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 5))) => {
                    {
                        _ = lua_pushlstring(L, data + pos, @as(usize, @bitCast(@as(c_long, size))));
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 6))) => {
                    {
                        var len: usize = @as(usize, @bitCast(@as(c_long, @truncate(unpackint(L, data + pos, h.islittle, size, @as(c_int, 0))))));
                        _ = &len;
                        _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(len <= ((ld -% pos) -% @as(usize, @bitCast(@as(c_long, size))))) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, @as(c_int, 2), "data string too short") != 0);
                        _ = lua_pushlstring(L, (data + pos) + @as(usize, @bitCast(@as(isize, @intCast(size)))), len);
                        pos +%= len;
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 7))) => {
                    {
                        var len: usize = strlen(data + pos);
                        _ = &len;
                        _ = (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((pos +% len) < ld) != @as(c_int, 0))), @as(c_long, @bitCast(@as(c_long, @as(c_int, 1))))) != 0) or (luaL_argerror(L, @as(c_int, 2), "unfinished string for format 'z'") != 0);
                        _ = lua_pushlstring(L, data + pos, len);
                        pos +%= len +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))));
                        break;
                    }
                },
                @as(c_uint, @bitCast(@as(c_int, 9))), @as(c_uint, @bitCast(@as(c_int, 8))), @as(c_uint, @bitCast(@as(c_int, 10))) => {
                    n -= 1;
                    break;
                },
                else => {},
            }
            break;
        }
        pos +%= @as(usize, @bitCast(@as(c_long, size)));
    }
    lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_ulonglong, pos +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))))));
    return n + @as(c_int, 1);
}
pub const strlib: [18]luaL_Reg = [18]luaL_Reg{
    luaL_Reg{
        .name = "byte",
        .func = &str_byte,
    },
    luaL_Reg{
        .name = "char",
        .func = &str_char,
    },
    luaL_Reg{
        .name = "dump",
        .func = &str_dump,
    },
    luaL_Reg{
        .name = "find",
        .func = &str_find,
    },
    luaL_Reg{
        .name = "format",
        .func = &str_format,
    },
    luaL_Reg{
        .name = "gmatch",
        .func = &gmatch,
    },
    luaL_Reg{
        .name = "gsub",
        .func = &str_gsub,
    },
    luaL_Reg{
        .name = "len",
        .func = &str_len,
    },
    luaL_Reg{
        .name = "lower",
        .func = &str_lower,
    },
    luaL_Reg{
        .name = "match",
        .func = &str_match,
    },
    luaL_Reg{
        .name = "rep",
        .func = &str_rep,
    },
    luaL_Reg{
        .name = "reverse",
        .func = &str_reverse,
    },
    luaL_Reg{
        .name = "sub",
        .func = &str_sub,
    },
    luaL_Reg{
        .name = "upper",
        .func = &str_upper,
    },
    luaL_Reg{
        .name = "pack",
        .func = &str_pack,
    },
    luaL_Reg{
        .name = "packsize",
        .func = &str_packsize,
    },
    luaL_Reg{
        .name = "unpack",
        .func = &str_unpack,
    },
    luaL_Reg{
        .name = null,
        .func = null,
    },
};
pub fn createmetatable(arg_L: ?*lua_State) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    lua_createtable(L, @as(c_int, 0), @as(c_int, @bitCast(@as(c_uint, @truncate((@sizeOf([10]luaL_Reg) / @sizeOf(luaL_Reg)) -% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))))))));
    luaL_setfuncs(L, @as([*c]const luaL_Reg, @ptrCast(@alignCast(&stringmetamethods[@as(usize, @intCast(0))]))), @as(c_int, 0));
    _ = lua_pushstring(L, "");
    lua_pushvalue(L, -@as(c_int, 2));
    _ = lua_setmetatable(L, -@as(c_int, 2));
    lua_settop(L, -@as(c_int, 1) - @as(c_int, 1));
    lua_pushvalue(L, -@as(c_int, 2));
    lua_setfield(L, -@as(c_int, 2), "__index");
    lua_settop(L, -@as(c_int, 1) - @as(c_int, 1));
}
pub const __llvm__ = @as(c_int, 1);
pub const __clang__ = @as(c_int, 1);
pub const __clang_major__ = @as(c_int, 20);
pub const __clang_minor__ = @as(c_int, 1);
pub const __clang_patchlevel__ = @as(c_int, 2);
pub const __clang_version__ = "20.1.2 (https://github.com/ziglang/zig-bootstrap 7ef74e656cf8ddbd6bf891a8475892aa1afa6891)";
pub const __GNUC__ = @as(c_int, 4);
pub const __GNUC_MINOR__ = @as(c_int, 2);
pub const __GNUC_PATCHLEVEL__ = @as(c_int, 1);
pub const __GXX_ABI_VERSION = @as(c_int, 1002);
pub const __ATOMIC_RELAXED = @as(c_int, 0);
pub const __ATOMIC_CONSUME = @as(c_int, 1);
pub const __ATOMIC_ACQUIRE = @as(c_int, 2);
pub const __ATOMIC_RELEASE = @as(c_int, 3);
pub const __ATOMIC_ACQ_REL = @as(c_int, 4);
pub const __ATOMIC_SEQ_CST = @as(c_int, 5);
pub const __MEMORY_SCOPE_SYSTEM = @as(c_int, 0);
pub const __MEMORY_SCOPE_DEVICE = @as(c_int, 1);
pub const __MEMORY_SCOPE_WRKGRP = @as(c_int, 2);
pub const __MEMORY_SCOPE_WVFRNT = @as(c_int, 3);
pub const __MEMORY_SCOPE_SINGLE = @as(c_int, 4);
pub const __OPENCL_MEMORY_SCOPE_WORK_ITEM = @as(c_int, 0);
pub const __OPENCL_MEMORY_SCOPE_WORK_GROUP = @as(c_int, 1);
pub const __OPENCL_MEMORY_SCOPE_DEVICE = @as(c_int, 2);
pub const __OPENCL_MEMORY_SCOPE_ALL_SVM_DEVICES = @as(c_int, 3);
pub const __OPENCL_MEMORY_SCOPE_SUB_GROUP = @as(c_int, 4);
pub const __FPCLASS_SNAN = @as(c_int, 0x0001);
pub const __FPCLASS_QNAN = @as(c_int, 0x0002);
pub const __FPCLASS_NEGINF = @as(c_int, 0x0004);
pub const __FPCLASS_NEGNORMAL = @as(c_int, 0x0008);
pub const __FPCLASS_NEGSUBNORMAL = @as(c_int, 0x0010);
pub const __FPCLASS_NEGZERO = @as(c_int, 0x0020);
pub const __FPCLASS_POSZERO = @as(c_int, 0x0040);
pub const __FPCLASS_POSSUBNORMAL = @as(c_int, 0x0080);
pub const __FPCLASS_POSNORMAL = @as(c_int, 0x0100);
pub const __FPCLASS_POSINF = @as(c_int, 0x0200);
pub const __PRAGMA_REDEFINE_EXTNAME = @as(c_int, 1);
pub const __VERSION__ = "Clang 20.1.2 (https://github.com/ziglang/zig-bootstrap 7ef74e656cf8ddbd6bf891a8475892aa1afa6891)";
pub const __OBJC_BOOL_IS_BOOL = @as(c_int, 0);
pub const __CONSTANT_CFSTRINGS__ = @as(c_int, 1);
pub const __clang_literal_encoding__ = "UTF-8";
pub const __clang_wide_literal_encoding__ = "UTF-32";
pub const __ORDER_LITTLE_ENDIAN__ = @as(c_int, 1234);
pub const __ORDER_BIG_ENDIAN__ = @as(c_int, 4321);
pub const __ORDER_PDP_ENDIAN__ = @as(c_int, 3412);
pub const __BYTE_ORDER__ = __ORDER_LITTLE_ENDIAN__;
pub const __LITTLE_ENDIAN__ = @as(c_int, 1);
pub const _LP64 = @as(c_int, 1);
pub const __LP64__ = @as(c_int, 1);
pub const __CHAR_BIT__ = @as(c_int, 8);
pub const __BOOL_WIDTH__ = @as(c_int, 1);
pub const __SHRT_WIDTH__ = @as(c_int, 16);
pub const __INT_WIDTH__ = @as(c_int, 32);
pub const __LONG_WIDTH__ = @as(c_int, 64);
pub const __LLONG_WIDTH__ = @as(c_int, 64);
pub const __BITINT_MAXWIDTH__ = @as(c_int, 128);
pub const __SCHAR_MAX__ = @as(c_int, 127);
pub const __SHRT_MAX__ = @as(c_int, 32767);
pub const __INT_MAX__ = std.zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __LONG_MAX__ = std.zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __WCHAR_MAX__ = std.zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __WCHAR_WIDTH__ = @as(c_int, 32);
pub const __WINT_MAX__ = std.zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __WINT_WIDTH__ = @as(c_int, 32);
pub const __INTMAX_MAX__ = std.zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTMAX_WIDTH__ = @as(c_int, 64);
pub const __SIZE_MAX__ = std.zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __SIZE_WIDTH__ = @as(c_int, 64);
pub const __UINTMAX_MAX__ = std.zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTMAX_WIDTH__ = @as(c_int, 64);
pub const __PTRDIFF_MAX__ = std.zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __PTRDIFF_WIDTH__ = @as(c_int, 64);
pub const __INTPTR_MAX__ = std.zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTPTR_WIDTH__ = @as(c_int, 64);
pub const __UINTPTR_MAX__ = std.zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTPTR_WIDTH__ = @as(c_int, 64);
pub const __SIZEOF_DOUBLE__ = @as(c_int, 8);
pub const __SIZEOF_FLOAT__ = @as(c_int, 4);
pub const __SIZEOF_INT__ = @as(c_int, 4);
pub const __SIZEOF_LONG__ = @as(c_int, 8);
pub const __SIZEOF_LONG_DOUBLE__ = @as(c_int, 16);
pub const __SIZEOF_LONG_LONG__ = @as(c_int, 8);
pub const __SIZEOF_POINTER__ = @as(c_int, 8);
pub const __SIZEOF_SHORT__ = @as(c_int, 2);
pub const __SIZEOF_PTRDIFF_T__ = @as(c_int, 8);
pub const __SIZEOF_SIZE_T__ = @as(c_int, 8);
pub const __SIZEOF_WCHAR_T__ = @as(c_int, 4);
pub const __SIZEOF_WINT_T__ = @as(c_int, 4);
pub const __SIZEOF_INT128__ = @as(c_int, 16);
pub const __INTMAX_TYPE__ = c_long;
pub const __INTMAX_FMTd__ = "ld";
pub const __INTMAX_FMTi__ = "li";
pub const __INTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`");
// (no file):95:9
pub const __INTMAX_C = std.zig.c_translation.Macros.L_SUFFIX;
pub const __UINTMAX_TYPE__ = c_ulong;
pub const __UINTMAX_FMTo__ = "lo";
pub const __UINTMAX_FMTu__ = "lu";
pub const __UINTMAX_FMTx__ = "lx";
pub const __UINTMAX_FMTX__ = "lX";
pub const __UINTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`");
// (no file):102:9
pub const __UINTMAX_C = std.zig.c_translation.Macros.UL_SUFFIX;
pub const __PTRDIFF_TYPE__ = c_long;
pub const __PTRDIFF_FMTd__ = "ld";
pub const __PTRDIFF_FMTi__ = "li";
pub const __INTPTR_TYPE__ = c_long;
pub const __INTPTR_FMTd__ = "ld";
pub const __INTPTR_FMTi__ = "li";
pub const __SIZE_TYPE__ = c_ulong;
pub const __SIZE_FMTo__ = "lo";
pub const __SIZE_FMTu__ = "lu";
pub const __SIZE_FMTx__ = "lx";
pub const __SIZE_FMTX__ = "lX";
pub const __WCHAR_TYPE__ = c_uint;
pub const __WINT_TYPE__ = c_uint;
pub const __SIG_ATOMIC_MAX__ = std.zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __SIG_ATOMIC_WIDTH__ = @as(c_int, 32);
pub const __CHAR16_TYPE__ = c_ushort;
pub const __CHAR32_TYPE__ = c_uint;
pub const __UINTPTR_TYPE__ = c_ulong;
pub const __UINTPTR_FMTo__ = "lo";
pub const __UINTPTR_FMTu__ = "lu";
pub const __UINTPTR_FMTx__ = "lx";
pub const __UINTPTR_FMTX__ = "lX";
pub const __FLT16_DENORM_MIN__ = @as(f16, 5.9604644775390625e-8);
pub const __FLT16_NORM_MAX__ = @as(f16, 6.5504e+4);
pub const __FLT16_HAS_DENORM__ = @as(c_int, 1);
pub const __FLT16_DIG__ = @as(c_int, 3);
pub const __FLT16_DECIMAL_DIG__ = @as(c_int, 5);
pub const __FLT16_EPSILON__ = @as(f16, 9.765625e-4);
pub const __FLT16_HAS_INFINITY__ = @as(c_int, 1);
pub const __FLT16_HAS_QUIET_NAN__ = @as(c_int, 1);
pub const __FLT16_MANT_DIG__ = @as(c_int, 11);
pub const __FLT16_MAX_10_EXP__ = @as(c_int, 4);
pub const __FLT16_MAX_EXP__ = @as(c_int, 16);
pub const __FLT16_MAX__ = @as(f16, 6.5504e+4);
pub const __FLT16_MIN_10_EXP__ = -@as(c_int, 4);
pub const __FLT16_MIN_EXP__ = -@as(c_int, 13);
pub const __FLT16_MIN__ = @as(f16, 6.103515625e-5);
pub const __FLT_DENORM_MIN__ = @as(f32, 1.40129846e-45);
pub const __FLT_NORM_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_HAS_DENORM__ = @as(c_int, 1);
pub const __FLT_DIG__ = @as(c_int, 6);
pub const __FLT_DECIMAL_DIG__ = @as(c_int, 9);
pub const __FLT_EPSILON__ = @as(f32, 1.19209290e-7);
pub const __FLT_HAS_INFINITY__ = @as(c_int, 1);
pub const __FLT_HAS_QUIET_NAN__ = @as(c_int, 1);
pub const __FLT_MANT_DIG__ = @as(c_int, 24);
pub const __FLT_MAX_10_EXP__ = @as(c_int, 38);
pub const __FLT_MAX_EXP__ = @as(c_int, 128);
pub const __FLT_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_MIN_10_EXP__ = -@as(c_int, 37);
pub const __FLT_MIN_EXP__ = -@as(c_int, 125);
pub const __FLT_MIN__ = @as(f32, 1.17549435e-38);
pub const __DBL_DENORM_MIN__ = @as(f64, 4.9406564584124654e-324);
pub const __DBL_NORM_MAX__ = @as(f64, 1.7976931348623157e+308);
pub const __DBL_HAS_DENORM__ = @as(c_int, 1);
pub const __DBL_DIG__ = @as(c_int, 15);
pub const __DBL_DECIMAL_DIG__ = @as(c_int, 17);
pub const __DBL_EPSILON__ = @as(f64, 2.2204460492503131e-16);
pub const __DBL_HAS_INFINITY__ = @as(c_int, 1);
pub const __DBL_HAS_QUIET_NAN__ = @as(c_int, 1);
pub const __DBL_MANT_DIG__ = @as(c_int, 53);
pub const __DBL_MAX_10_EXP__ = @as(c_int, 308);
pub const __DBL_MAX_EXP__ = @as(c_int, 1024);
pub const __DBL_MAX__ = @as(f64, 1.7976931348623157e+308);
pub const __DBL_MIN_10_EXP__ = -@as(c_int, 307);
pub const __DBL_MIN_EXP__ = -@as(c_int, 1021);
pub const __DBL_MIN__ = @as(f64, 2.2250738585072014e-308);
pub const __LDBL_DENORM_MIN__ = @as(c_longdouble, 6.47517511943802511092443895822764655e-4966);
pub const __LDBL_NORM_MAX__ = @as(c_longdouble, 1.18973149535723176508575932662800702e+4932);
pub const __LDBL_HAS_DENORM__ = @as(c_int, 1);
pub const __LDBL_DIG__ = @as(c_int, 33);
pub const __LDBL_DECIMAL_DIG__ = @as(c_int, 36);
pub const __LDBL_EPSILON__ = @as(c_longdouble, 1.92592994438723585305597794258492732e-34);
pub const __LDBL_HAS_INFINITY__ = @as(c_int, 1);
pub const __LDBL_HAS_QUIET_NAN__ = @as(c_int, 1);
pub const __LDBL_MANT_DIG__ = @as(c_int, 113);
pub const __LDBL_MAX_10_EXP__ = @as(c_int, 4932);
pub const __LDBL_MAX_EXP__ = @as(c_int, 16384);
pub const __LDBL_MAX__ = @as(c_longdouble, 1.18973149535723176508575932662800702e+4932);
pub const __LDBL_MIN_10_EXP__ = -@as(c_int, 4931);
pub const __LDBL_MIN_EXP__ = -@as(c_int, 16381);
pub const __LDBL_MIN__ = @as(c_longdouble, 3.36210314311209350626267781732175260e-4932);
pub const __POINTER_WIDTH__ = @as(c_int, 64);
pub const __BIGGEST_ALIGNMENT__ = @as(c_int, 16);
pub const __CHAR_UNSIGNED__ = @as(c_int, 1);
pub const __WCHAR_UNSIGNED__ = @as(c_int, 1);
pub const __WINT_UNSIGNED__ = @as(c_int, 1);
pub const __INT8_TYPE__ = i8;
pub const __INT8_FMTd__ = "hhd";
pub const __INT8_FMTi__ = "hhi";
pub const __INT8_C_SUFFIX__ = "";
pub inline fn __INT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT16_TYPE__ = c_short;
pub const __INT16_FMTd__ = "hd";
pub const __INT16_FMTi__ = "hi";
pub const __INT16_C_SUFFIX__ = "";
pub inline fn __INT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT32_TYPE__ = c_int;
pub const __INT32_FMTd__ = "d";
pub const __INT32_FMTi__ = "i";
pub const __INT32_C_SUFFIX__ = "";
pub inline fn __INT32_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT64_TYPE__ = c_long;
pub const __INT64_FMTd__ = "ld";
pub const __INT64_FMTi__ = "li";
pub const __INT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`");
// (no file):209:9
pub const __INT64_C = std.zig.c_translation.Macros.L_SUFFIX;
pub const __UINT8_TYPE__ = u8;
pub const __UINT8_FMTo__ = "hho";
pub const __UINT8_FMTu__ = "hhu";
pub const __UINT8_FMTx__ = "hhx";
pub const __UINT8_FMTX__ = "hhX";
pub const __UINT8_C_SUFFIX__ = "";
pub inline fn __UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT8_MAX__ = @as(c_int, 255);
pub const __INT8_MAX__ = @as(c_int, 127);
pub const __UINT16_TYPE__ = c_ushort;
pub const __UINT16_FMTo__ = "ho";
pub const __UINT16_FMTu__ = "hu";
pub const __UINT16_FMTx__ = "hx";
pub const __UINT16_FMTX__ = "hX";
pub const __UINT16_C_SUFFIX__ = "";
pub inline fn __UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT16_MAX__ = std.zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __INT16_MAX__ = @as(c_int, 32767);
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `U`");
// (no file):234:9
pub const __UINT32_C = std.zig.c_translation.Macros.U_SUFFIX;
pub const __UINT32_MAX__ = std.zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __INT32_MAX__ = std.zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __UINT64_TYPE__ = c_ulong;
pub const __UINT64_FMTo__ = "lo";
pub const __UINT64_FMTu__ = "lu";
pub const __UINT64_FMTx__ = "lx";
pub const __UINT64_FMTX__ = "lX";
pub const __UINT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`");
// (no file):243:9
pub const __UINT64_C = std.zig.c_translation.Macros.UL_SUFFIX;
pub const __UINT64_MAX__ = std.zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __INT64_MAX__ = std.zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST8_TYPE__ = i8;
pub const __INT_LEAST8_MAX__ = @as(c_int, 127);
pub const __INT_LEAST8_WIDTH__ = @as(c_int, 8);
pub const __INT_LEAST8_FMTd__ = "hhd";
pub const __INT_LEAST8_FMTi__ = "hhi";
pub const __UINT_LEAST8_TYPE__ = u8;
pub const __UINT_LEAST8_MAX__ = @as(c_int, 255);
pub const __UINT_LEAST8_FMTo__ = "hho";
pub const __UINT_LEAST8_FMTu__ = "hhu";
pub const __UINT_LEAST8_FMTx__ = "hhx";
pub const __UINT_LEAST8_FMTX__ = "hhX";
pub const __INT_LEAST16_TYPE__ = c_short;
pub const __INT_LEAST16_MAX__ = @as(c_int, 32767);
pub const __INT_LEAST16_WIDTH__ = @as(c_int, 16);
pub const __INT_LEAST16_FMTd__ = "hd";
pub const __INT_LEAST16_FMTi__ = "hi";
pub const __UINT_LEAST16_TYPE__ = c_ushort;
pub const __UINT_LEAST16_MAX__ = std.zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __UINT_LEAST16_FMTo__ = "ho";
pub const __UINT_LEAST16_FMTu__ = "hu";
pub const __UINT_LEAST16_FMTx__ = "hx";
pub const __UINT_LEAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = std.zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_LEAST32_WIDTH__ = @as(c_int, 32);
pub const __INT_LEAST32_FMTd__ = "d";
pub const __INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = std.zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __UINT_LEAST32_FMTo__ = "o";
pub const __UINT_LEAST32_FMTu__ = "u";
pub const __UINT_LEAST32_FMTx__ = "x";
pub const __UINT_LEAST32_FMTX__ = "X";
pub const __INT_LEAST64_TYPE__ = c_long;
pub const __INT_LEAST64_MAX__ = std.zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST64_WIDTH__ = @as(c_int, 64);
pub const __INT_LEAST64_FMTd__ = "ld";
pub const __INT_LEAST64_FMTi__ = "li";
pub const __UINT_LEAST64_TYPE__ = c_ulong;
pub const __UINT_LEAST64_MAX__ = std.zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINT_LEAST64_FMTo__ = "lo";
pub const __UINT_LEAST64_FMTu__ = "lu";
pub const __UINT_LEAST64_FMTx__ = "lx";
pub const __UINT_LEAST64_FMTX__ = "lX";
pub const __INT_FAST8_TYPE__ = i8;
pub const __INT_FAST8_MAX__ = @as(c_int, 127);
pub const __INT_FAST8_WIDTH__ = @as(c_int, 8);
pub const __INT_FAST8_FMTd__ = "hhd";
pub const __INT_FAST8_FMTi__ = "hhi";
pub const __UINT_FAST8_TYPE__ = u8;
pub const __UINT_FAST8_MAX__ = @as(c_int, 255);
pub const __UINT_FAST8_FMTo__ = "hho";
pub const __UINT_FAST8_FMTu__ = "hhu";
pub const __UINT_FAST8_FMTx__ = "hhx";
pub const __UINT_FAST8_FMTX__ = "hhX";
pub const __INT_FAST16_TYPE__ = c_short;
pub const __INT_FAST16_MAX__ = @as(c_int, 32767);
pub const __INT_FAST16_WIDTH__ = @as(c_int, 16);
pub const __INT_FAST16_FMTd__ = "hd";
pub const __INT_FAST16_FMTi__ = "hi";
pub const __UINT_FAST16_TYPE__ = c_ushort;
pub const __UINT_FAST16_MAX__ = std.zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __UINT_FAST16_FMTo__ = "ho";
pub const __UINT_FAST16_FMTu__ = "hu";
pub const __UINT_FAST16_FMTx__ = "hx";
pub const __UINT_FAST16_FMTX__ = "hX";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = std.zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_FAST32_WIDTH__ = @as(c_int, 32);
pub const __INT_FAST32_FMTd__ = "d";
pub const __INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = std.zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __UINT_FAST32_FMTo__ = "o";
pub const __UINT_FAST32_FMTu__ = "u";
pub const __UINT_FAST32_FMTx__ = "x";
pub const __UINT_FAST32_FMTX__ = "X";
pub const __INT_FAST64_TYPE__ = c_long;
pub const __INT_FAST64_MAX__ = std.zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_FAST64_WIDTH__ = @as(c_int, 64);
pub const __INT_FAST64_FMTd__ = "ld";
pub const __INT_FAST64_FMTi__ = "li";
pub const __UINT_FAST64_TYPE__ = c_ulong;
pub const __UINT_FAST64_MAX__ = std.zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINT_FAST64_FMTo__ = "lo";
pub const __UINT_FAST64_FMTu__ = "lu";
pub const __UINT_FAST64_FMTx__ = "lx";
pub const __UINT_FAST64_FMTX__ = "lX";
pub const __USER_LABEL_PREFIX__ = "";
pub const __FINITE_MATH_ONLY__ = @as(c_int, 0);
pub const __GNUC_STDC_INLINE__ = @as(c_int, 1);
pub const __GCC_ATOMIC_TEST_AND_SET_TRUEVAL = @as(c_int, 1);
pub const __GCC_DESTRUCTIVE_SIZE = @as(c_int, 64);
pub const __GCC_CONSTRUCTIVE_SIZE = @as(c_int, 64);
pub const __CLANG_ATOMIC_BOOL_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_CHAR_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_SHORT_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_INT_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_LONG_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_LLONG_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_POINTER_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_BOOL_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_CHAR_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_SHORT_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_INT_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_LONG_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_LLONG_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_POINTER_LOCK_FREE = @as(c_int, 2);
pub const __NO_INLINE__ = @as(c_int, 1);
pub const __FLT_RADIX__ = @as(c_int, 2);
pub const __DECIMAL_DIG__ = __LDBL_DECIMAL_DIG__;
pub const __ELF__ = @as(c_int, 1);
pub const __AARCH64EL__ = @as(c_int, 1);
pub const __aarch64__ = @as(c_int, 1);
pub const __GCC_ASM_FLAG_OUTPUTS__ = @as(c_int, 1);
pub const __AARCH64_CMODEL_SMALL__ = @as(c_int, 1);
pub inline fn __ARM_ACLE_VERSION(year: anytype, quarter: anytype, patch: anytype) @TypeOf(((@as(c_int, 100) * year) + (@as(c_int, 10) * quarter)) + patch) {
    _ = &year;
    _ = &quarter;
    _ = &patch;
    return ((@as(c_int, 100) * year) + (@as(c_int, 10) * quarter)) + patch;
}
pub const __ARM_ACLE = std.zig.c_translation.promoteIntLiteral(c_int, 202420, .decimal);
pub const __FUNCTION_MULTI_VERSIONING_SUPPORT_LEVEL = std.zig.c_translation.promoteIntLiteral(c_int, 202430, .decimal);
pub const __ARM_ARCH = @as(c_int, 8);
pub const __ARM_ARCH_PROFILE = 'A';
pub const __ARM_64BIT_STATE = @as(c_int, 1);
pub const __ARM_PCS_AAPCS64 = @as(c_int, 1);
pub const __ARM_ARCH_ISA_A64 = @as(c_int, 1);
pub const __ARM_FEATURE_CLZ = @as(c_int, 1);
pub const __ARM_FEATURE_FMA = @as(c_int, 1);
pub const __ARM_FEATURE_LDREX = @as(c_int, 0xF);
pub const __ARM_FEATURE_IDIV = @as(c_int, 1);
pub const __ARM_FEATURE_DIV = @as(c_int, 1);
pub const __ARM_FEATURE_NUMERIC_MAXMIN = @as(c_int, 1);
pub const __ARM_FEATURE_DIRECTED_ROUNDING = @as(c_int, 1);
pub const __ARM_ALIGN_MAX_STACK_PWR = @as(c_int, 4);
pub const __ARM_STATE_ZA = @as(c_int, 1);
pub const __ARM_STATE_ZT0 = @as(c_int, 1);
pub const __ARM_FP = @as(c_int, 0xE);
pub const __ARM_FP16_FORMAT_IEEE = @as(c_int, 1);
pub const __ARM_FP16_ARGS = @as(c_int, 1);
pub const __ARM_NEON_SVE_BRIDGE = @as(c_int, 1);
pub const __ARM_SIZEOF_WCHAR_T = @as(c_int, 4);
pub const __ARM_SIZEOF_MINIMAL_ENUM = @as(c_int, 4);
pub const __ARM_NEON = @as(c_int, 1);
pub const __ARM_NEON_FP = @as(c_int, 0xE);
pub const __ARM_FEATURE_UNALIGNED = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_1 = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_2 = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_4 = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_16 = @as(c_int, 1);
pub const __FP_FAST_FMA = @as(c_int, 1);
pub const __FP_FAST_FMAF = @as(c_int, 1);
pub const unix = @as(c_int, 1);
pub const __unix = @as(c_int, 1);
pub const __unix__ = @as(c_int, 1);
pub const linux = @as(c_int, 1);
pub const __linux = @as(c_int, 1);
pub const __linux__ = @as(c_int, 1);
pub const __gnu_linux__ = @as(c_int, 1);
pub const __STDC__ = @as(c_int, 1);
pub const __STDC_HOSTED__ = @as(c_int, 1);
pub const __STDC_VERSION__ = @as(c_long, 201710);
pub const __STDC_UTF_16__ = @as(c_int, 1);
pub const __STDC_UTF_32__ = @as(c_int, 1);
pub const __STDC_EMBED_NOT_FOUND__ = @as(c_int, 0);
pub const __STDC_EMBED_FOUND__ = @as(c_int, 1);
pub const __STDC_EMBED_EMPTY__ = @as(c_int, 2);
pub const __GCC_HAVE_DWARF2_CFI_ASM = @as(c_int, 1);
pub const __COSMOPOLITAN_MAJOR__ = @as(c_int, 4);
pub const __COSMOPOLITAN_MINOR__ = @as(c_int, 0);
pub const __COSMOPOLITAN_PATCH__ = @as(c_int, 2);
pub const __COSMOPOLITAN__ = ((std.zig.c_translation.promoteIntLiteral(c_int, 100000000, .decimal) * __COSMOPOLITAN_MAJOR__) + (std.zig.c_translation.promoteIntLiteral(c_int, 1000000, .decimal) * __COSMOPOLITAN_MINOR__)) + __COSMOPOLITAN_PATCH__;
pub inline fn __has_cpp_attribute(x: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &x;
    return @as(c_int, 0);
}
pub const COSMOPOLITAN_C_START_ = "";
pub const COSMOPOLITAN_C_END_ = "";
pub const COSMOPOLITAN_CXX_START_ = "";
pub const COSMOPOLITAN_CXX_END_ = "";
pub const COSMOPOLITAN_CXX_USING_ = "";
pub const __gnu_printf__ = @compileError("unable to translate macro: undefined identifier `__printf__`");
// /src/cosmopolitan/libc/integral/c.inc:20:9
pub const __gnu_scanf__ = @compileError("unable to translate macro: undefined identifier `__scanf__`");
// /src/cosmopolitan/libc/integral/c.inc:21:9
pub const NULL = std.zig.c_translation.cast(?*anyopaque, @as(c_int, 0));
pub const __DEFINED_max_align_t = "";
pub const __AXDX_T = "";
pub const va_list = __builtin_va_list;
pub const va_arg = @compileError("unable to translate C expr: unexpected token 'an identifier'");
// /src/cosmopolitan/libc/integral/c.inc:103:9
pub const va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`");
// /src/cosmopolitan/libc/integral/c.inc:104:9
pub const va_end = @compileError("unable to translate macro: undefined identifier `__builtin_va_end`");
// /src/cosmopolitan/libc/integral/c.inc:105:9
pub const va_start = @compileError("unable to translate macro: undefined identifier `__builtin_va_start`");
// /src/cosmopolitan/libc/integral/c.inc:106:9
pub const libcesque = dontthrow ++ dontcallback;
pub const memcpyesque = libcesque;
pub const strlenesque = libcesque ++ nosideeffect ++ paramsnonnull();
pub const vallocesque = libcesque ++ __wur ++ returnsaligned(std.zig.c_translation.promoteIntLiteral(c_int, 65536, .decimal)) ++ returnspointerwithnoaliases;
pub const reallocesque = libcesque ++ returnsaligned(@as(c_int, 16));
pub const mallocesque = reallocesque ++ returnspointerwithnoaliases;
pub const pureconst = @compileError("unable to translate C expr: unexpected token '__attribute__'");
// /src/cosmopolitan/libc/integral/c.inc:120:9
pub const forcealign = @compileError("unable to translate macro: undefined identifier `__aligned__`");
// /src/cosmopolitan/libc/integral/c.inc:124:9
pub const thatispacked = @compileError("unable to translate macro: undefined identifier `__packed__`");
// /src/cosmopolitan/libc/integral/c.inc:126:9
pub const printfesque = @compileError("unable to translate macro: undefined identifier `__format__`");
// /src/cosmopolitan/libc/integral/c.inc:128:9
pub const scanfesque = @compileError("unable to translate macro: undefined identifier `__format__`");
// /src/cosmopolitan/libc/integral/c.inc:129:9
pub const strftimeesque = @compileError("unable to translate macro: undefined identifier `__format__`");
// /src/cosmopolitan/libc/integral/c.inc:130:9
pub const __privileged = @compileError("unable to translate macro: undefined identifier `_Section`");
// /src/cosmopolitan/libc/integral/c.inc:133:9
pub const wontreturn = @compileError("unable to translate macro: undefined identifier `__noreturn__`");
// /src/cosmopolitan/libc/integral/c.inc:139:9
pub const nosideeffect = @compileError("unable to translate macro: undefined identifier `__pure__`");
// /src/cosmopolitan/libc/integral/c.inc:148:9
pub const dontinline = @compileError("unable to translate macro: undefined identifier `__noinline__`");
// /src/cosmopolitan/libc/integral/c.inc:159:9
pub const dontclone = "";
pub const forceinline = @compileError("unable to translate macro: undefined identifier `__always_inline__`");
// /src/cosmopolitan/libc/integral/c.inc:184:9
pub const __wur = @compileError("unable to translate macro: undefined identifier `__warn_unused_result__`");
// /src/cosmopolitan/libc/integral/c.inc:204:9
pub const nullterminated = @compileError("unable to translate macro: undefined identifier `__sentinel__`");
// /src/cosmopolitan/libc/integral/c.inc:212:9
pub const flattenout = @compileError("unable to translate macro: undefined identifier `__flatten__`");
// /src/cosmopolitan/libc/integral/c.inc:221:9
pub const externinline = @compileError("unable to translate macro: undefined identifier `__gnu_inline__`");
// /src/cosmopolitan/libc/integral/c.inc:233:9
pub const relegated = @compileError("unable to translate macro: undefined identifier `__cold__`");
// /src/cosmopolitan/libc/integral/c.inc:245:9
pub const warnifused = @compileError("unable to translate macro: undefined identifier `__warning__`");
// /src/cosmopolitan/libc/integral/c.inc:253:9
pub const firstclass = @compileError("unable to translate macro: undefined identifier `__hot__`");
// /src/cosmopolitan/libc/integral/c.inc:261:9
pub const paramsnonnull = @compileError("unable to translate macro: undefined identifier `__nonnull__`");
// /src/cosmopolitan/libc/integral/c.inc:270:9
pub const hasatleast = @compileError("unable to translate C expr: unexpected token 'static'");
// /src/cosmopolitan/libc/integral/c.inc:277:9
pub const dontcallback = @compileError("unable to translate macro: undefined identifier `__leaf__`");
// /src/cosmopolitan/libc/integral/c.inc:286:9
pub const dontthrow = "";
pub const returnstwice = @compileError("unable to translate macro: undefined identifier `__returns_twice__`");
// /src/cosmopolitan/libc/integral/c.inc:307:9
pub const nodebuginfo = @compileError("unable to translate macro: undefined identifier `__nodebug__`");
// /src/cosmopolitan/libc/integral/c.inc:315:9
pub const forcealignargpointer = "need modern compiler";
pub const returnsnonnull = @compileError("unable to translate macro: undefined identifier `__returns_nonnull__`");
// /src/cosmopolitan/libc/integral/c.inc:331:9
pub const returnsaligned = @compileError("unable to translate macro: undefined identifier `__assume_aligned__`");
// /src/cosmopolitan/libc/integral/c.inc:339:9
pub const returnspointerwithnoaliases = @compileError("unable to translate macro: undefined identifier `__malloc__`");
// /src/cosmopolitan/libc/integral/c.inc:347:9
pub const attributeallocsize = @compileError("unable to translate macro: undefined identifier `__alloc_size__`");
// /src/cosmopolitan/libc/integral/c.inc:358:9
pub const attributeallocalign = @compileError("unable to translate macro: undefined identifier `__alloc_align__`");
// /src/cosmopolitan/libc/integral/c.inc:367:9
pub const autotype = @compileError("unable to translate C expr: unexpected token '__auto_type'");
// /src/cosmopolitan/libc/integral/c.inc:378:9
pub const offsetof = @compileError("unable to translate C expr: unexpected token 'an identifier'");
// /src/cosmopolitan/libc/integral/c.inc:383:9
pub const __read_only = @compileError("unable to translate C expr: expected ')' instead got '...'");
// /src/cosmopolitan/libc/integral/c.inc:392:9
pub const __write_only = @compileError("unable to translate C expr: expected ')' instead got '...'");
// /src/cosmopolitan/libc/integral/c.inc:393:9
pub const __read_write = @compileError("unable to translate C expr: expected ')' instead got '...'");
// /src/cosmopolitan/libc/integral/c.inc:394:9
pub const __fd_arg = @compileError("unable to translate C expr: unexpected token ''");
// /src/cosmopolitan/libc/integral/c.inc:400:9
pub const __veil = @compileError("unable to translate macro: undefined identifier `VeiledValue`");
// /src/cosmopolitan/libc/integral/c.inc:565:9
pub const __conceal = @compileError("unable to translate macro: undefined identifier `VeiledValue`");
// /src/cosmopolitan/libc/integral/c.inc:572:9
pub const __expropriate = @compileError("unable to translate C expr: unexpected token '__extension__'");
// /src/cosmopolitan/libc/integral/c.inc:579:9
pub const __yoink = @compileError("unable to translate C expr: unexpected token '__asm__'");
// /src/cosmopolitan/libc/integral/c.inc:589:9
pub const __static_yoink = @compileError("unable to translate C expr: unexpected token '__asm__'");
// /src/cosmopolitan/libc/integral/c.inc:599:9
pub inline fn __static_yoink_source(PATH: anytype) @TypeOf(__static_yoink(PATH)) {
    _ = &PATH;
    return __static_yoink(PATH);
}
pub inline fn __weak_reference(sym: anytype, alias: anytype) @TypeOf(__weak_reference_impl(sym, alias)) {
    _ = &sym;
    _ = &alias;
    return __weak_reference_impl(sym, alias);
}
pub const __weak_reference_impl = @compileError("unable to translate C expr: unexpected token '__asm__'");
// /src/cosmopolitan/libc/integral/c.inc:612:9
pub const __strong_reference = @compileError("unable to translate macro: undefined identifier `__alias__`");
// /src/cosmopolitan/libc/integral/c.inc:618:9
pub const __funline = @compileError("unable to translate macro: undefined identifier `__gnu_inline__`");
// /src/cosmopolitan/libc/integral/c.inc:625:9
pub const __target_clones = @compileError("unable to translate C expr: unexpected token ''");
// /src/cosmopolitan/libc/integral/c.inc:636:9
pub const __vex = __target_clones("avx");
pub const __notice = @compileError("unable to translate macro: undefined identifier `__section__`");
// /src/cosmopolitan/libc/integral/c.inc:645:9
pub const MACHINE_CODE_ANALYSIS_BEGIN_ = "";
pub const MACHINE_CODE_ANALYSIS_END_ = "";
pub const __STDBOOL_H = "";
pub const __bool_true_false_are_defined = @as(c_int, 1);
pub const @"bool" = bool;
pub const @"true" = @as(c_int, 1);
pub const @"false" = @as(c_int, 0);
pub const _STDLIB_H = "";
pub const COSMOPOLITAN_LIBC_CALLS_SYSCALLS_H_ = "";
pub const _POSIX_VERSION = @as(c_long, 200809);
pub const _POSIX2_VERSION = _POSIX_VERSION;
pub const _XOPEN_VERSION = @as(c_int, 700);
pub const _POSIX_MAPPED_FILES = _POSIX_VERSION;
pub const _POSIX_FSYNC = _POSIX_VERSION;
pub const _POSIX_IPV6 = _POSIX_VERSION;
pub const _POSIX_THREADS = _POSIX_VERSION;
pub const _POSIX_THREAD_PROCESS_SHARED = _POSIX_VERSION;
pub const _POSIX_THREAD_SAFE_FUNCTIONS = _POSIX_VERSION;
pub const _POSIX_THREAD_ATTR_STACKADDR = _POSIX_VERSION;
pub const _POSIX_THREAD_ATTR_STACKSIZE = _POSIX_VERSION;
pub const _POSIX_THREAD_PRIORITY_SCHEDULING = _POSIX_VERSION;
pub const _POSIX_THREAD_CPUTIME = _POSIX_VERSION;
pub const _POSIX_TIMEOUTS = _POSIX_VERSION;
pub const _POSIX_MONOTONIC_CLOCK = _POSIX_VERSION;
pub const _POSIX_CPUTIME = _POSIX_VERSION;
pub const _POSIX_BARRIERS = _POSIX_VERSION;
pub const _POSIX_SPIN_LOCKS = _POSIX_VERSION;
pub const _POSIX_READER_WRITER_LOCKS = _POSIX_VERSION;
pub const _POSIX_SEMAPHORES = _POSIX_VERSION;
pub const _POSIX_SHARED_MEMORY_OBJECTS = _POSIX_VERSION;
pub const _POSIX_MEMLOCK_RANGE = _POSIX_VERSION;
pub const _POSIX_SPAWN = _POSIX_VERSION;
pub const NSIG = @as(c_int, 64);
pub const SEEK_SET = @as(c_int, 0);
pub const SEEK_CUR = @as(c_int, 1);
pub const SEEK_END = @as(c_int, 2);
pub const __WALL = std.zig.c_translation.promoteIntLiteral(c_int, 0x40000000, .hex);
pub const __WCLONE = std.zig.c_translation.promoteIntLiteral(c_int, 0x80000000, .hex);
pub const SIG_ERR = @compileError("unable to translate C expr: expected ')' instead got '('");
// /src/cosmopolitan/libc/calls/calls.h:37:9
pub const SIG_DFL = @compileError("unable to translate C expr: expected ')' instead got '('");
// /src/cosmopolitan/libc/calls/calls.h:38:9
pub const SIG_IGN = @compileError("unable to translate C expr: expected ')' instead got '('");
// /src/cosmopolitan/libc/calls/calls.h:39:9
pub const CLOCKS_PER_SEC = @as(c_long, 1000000);
pub const MAP_FAILED = std.zig.c_translation.cast(?*anyopaque, -@as(c_int, 1));
pub inline fn WEXITSTATUS(s: anytype) @TypeOf(s >> @as(c_int, 8)) {
    _ = &s;
    return s >> @as(c_int, 8);
}
pub inline fn WTERMSIG(s: anytype) @TypeOf(s & @as(c_int, 0x7f)) {
    _ = &s;
    return s & @as(c_int, 0x7f);
}
pub inline fn WSTOPSIG(s: anytype) @TypeOf((s & std.zig.c_translation.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8)) {
    _ = &s;
    return (s & std.zig.c_translation.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8);
}
pub inline fn WIFEXITED(s: anytype) @TypeOf(!(WTERMSIG(s) != 0)) {
    _ = &s;
    return !(WTERMSIG(s) != 0);
}
pub inline fn WIFSTOPPED(s: anytype) @TypeOf((s & @as(c_int, 0xff)) == @as(c_int, 0x7f)) {
    _ = &s;
    return (s & @as(c_int, 0xff)) == @as(c_int, 0x7f);
}
pub inline fn WIFSIGNALED(s: anytype) @TypeOf((std.zig.c_translation.cast(i8, (s & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0)) {
    _ = &s;
    return (std.zig.c_translation.cast(i8, (s & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0);
}
pub inline fn WCOREDUMP(s: anytype) @TypeOf(s & @as(c_int, 0x80)) {
    _ = &s;
    return s & @as(c_int, 0x80);
}
pub inline fn WIFCONTINUED(s: anytype) @TypeOf((s & std.zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) == std.zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) {
    _ = &s;
    return (s & std.zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) == std.zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex);
}
pub inline fn W_STOPCODE(s: anytype) @TypeOf((s << @as(c_int, 8)) | @as(c_int, 0x7f)) {
    _ = &s;
    return (s << @as(c_int, 8)) | @as(c_int, 0x7f);
}
pub const COSMOPOLITAN_LIBC_CALLS_TERMIOS_H_ = "";
pub const COSMOPOLITAN_LIBC_CALLS_STRUCT_TERMIOS_H_ = "";
pub const NCCS = @as(c_int, 20);
pub const COSMOPOLITAN_LIBC_CALLS_STRUCT_WINSIZE_H_ = "";
pub const COSMOPOLITAN_LIBC_FMT_CONV_H_ = "";
pub const COSMOPOLITAN_LIBC_LIMITS_H_ = "";
pub const __STDC_LIMIT_MACROS = "";
pub const CHAR_BIT = @as(c_int, 8);
pub const PATH_MAX = @as(c_int, 1024);
pub const NAME_MAX = @as(c_int, 255);
pub const ARG_MAX = std.zig.c_translation.promoteIntLiteral(c_int, 131074, .decimal);
pub const UCHAR_MIN = @as(c_int, 0);
pub const UCHAR_MAX = @as(c_int, 255);
pub const CHAR_MIN = '\x00';
pub const CHAR_MAX = '\xff';
pub const SCHAR_MAX = __SCHAR_MAX__;
pub const SHRT_MAX = __SHRT_MAX__;
pub const INT_MAX = __INT_MAX__;
pub const LONG_MAX = __LONG_MAX__;
pub const LLONG_MAX = LONG_LONG_MAX;
pub const LONG_LONG_MAX = __LONG_LONG_MAX__;
pub const SIZE_MAX = __SIZE_MAX__;
pub const INT8_MAX = __INT8_MAX__;
pub const INT16_MAX = __INT16_MAX__;
pub const INT32_MAX = __INT32_MAX__;
pub const INT64_MAX = __INT64_MAX__;
pub const WINT_MAX = __WINT_MAX__;
pub const WCHAR_MAX = __WCHAR_MAX__;
pub const INTPTR_MAX = __INTPTR_MAX__;
pub const PTRDIFF_MAX = __PTRDIFF_MAX__;
pub const UINTPTR_MAX = __UINTPTR_MAX__;
pub const UINT8_MAX = __UINT8_MAX__;
pub const UINT16_MAX = __UINT16_MAX__;
pub const UINT32_MAX = __UINT32_MAX__;
pub const UINT64_MAX = __UINT64_MAX__;
pub const INTMAX_MAX = __INTMAX_MAX__;
pub const UINTMAX_MAX = __UINTMAX_MAX__;
pub const SSIZE_MAX = __INT64_MAX__;
pub const SCHAR_MIN = -SCHAR_MAX - @as(c_int, 1);
pub const SHRT_MIN = -SHRT_MAX - @as(c_int, 1);
pub const INT_MIN = -INT_MAX - @as(c_int, 1);
pub const LONG_MIN = -LONG_MAX - @as(c_int, 1);
pub const LLONG_MIN = -LLONG_MAX - @as(c_int, 1);
pub const LONG_LONG_MIN = -LONG_LONG_MAX - @as(c_int, 1);
pub const SIZE_MIN = -SIZE_MAX - @as(c_int, 1);
pub const INT8_MIN = -INT8_MAX - @as(c_int, 1);
pub const INT16_MIN = -INT16_MAX - @as(c_int, 1);
pub const INT32_MIN = -INT32_MAX - @as(c_int, 1);
pub const INT64_MIN = -INT64_MAX - @as(c_int, 1);
pub const INTMAX_MIN = -INTMAX_MAX - @as(c_int, 1);
pub const INTPTR_MIN = -INTPTR_MAX - @as(c_int, 1);
pub const WINT_MIN = @compileError("unable to translate macro: undefined identifier `__WINT_MIN__`");
// /src/cosmopolitan/libc/limits.h:58:9
pub const WCHAR_MIN = @compileError("unable to translate macro: undefined identifier `__WCHAR_MIN__`");
// /src/cosmopolitan/libc/limits.h:59:9
pub const PTRDIFF_MIN = -PTRDIFF_MAX - @as(c_int, 1);
pub const USHRT_MAX = std.zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_MAX = std.zig.c_translation.promoteIntLiteral(c_uint, 0xffffffff, .hex);
pub const ULONG_MAX = std.zig.c_translation.promoteIntLiteral(c_ulong, 0xffffffffffffffff, .hex);
pub const ULLONG_MAX = @as(c_ulonglong, 0xffffffffffffffff);
pub const ULONG_LONG_MAX = @as(c_ulonglong, 0xffffffffffffffff);
pub const USHRT_MIN = @as(c_int, 0);
pub const UINT_MIN = @as(c_uint, 0);
pub const ULONG_MIN = @as(c_ulong, 0);
pub const ULLONG_MIN = @as(c_ulonglong, 0);
pub const ULONG_LONG_MIN = @as(c_ulonglong, 0);
pub const UINT8_MIN = @as(c_int, 0);
pub const UINT16_MIN = @as(c_int, 0);
pub const UINT32_MIN = @as(c_uint, 0);
pub const UINT64_MIN = @as(c_ulonglong, 0);
pub const UINTPTR_MIN = @as(c_ulonglong, 0);
pub const UINTMAX_MIN = std.zig.c_translation.cast(uintmax_t, @as(c_int, 0));
pub const MB_CUR_MAX = @as(c_int, 4);
pub const MB_LEN_MAX = @as(c_int, 4);
pub const SIG_ATOMIC_MIN = INT32_MIN;
pub const SIG_ATOMIC_MAX = INT32_MAX;
pub const FILESIZEBITS = @as(c_int, 64);
pub const SYMLOOP_MAX = @as(c_int, 40);
pub const TTY_NAME_MAX = @as(c_int, 32);
pub const HOST_NAME_MAX = @as(c_int, 255);
pub const TZNAME_MAX = @as(c_int, 6);
pub const WORD_BIT = @as(c_int, 32);
pub const SEM_VALUE_MAX = std.zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const SEM_NSEMS_MAX = @as(c_int, 256);
pub const DELAYTIMER_MAX = std.zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const MQ_PRIO_MAX = std.zig.c_translation.promoteIntLiteral(c_int, 32768, .decimal);
pub const LOGIN_NAME_MAX = @as(c_int, 256);
pub const NL_ARGMAX = @as(c_int, 9);
pub const NL_MSGMAX = @as(c_int, 32767);
pub const NL_SETMAX = @as(c_int, 255);
pub const NL_TEXTMAX = @as(c_int, 2048);
pub const INT_FAST8_MIN = -__INT_FAST8_MAX__ - @as(c_int, 1);
pub const INT_FAST16_MIN = -__INT_FAST16_MAX__ - @as(c_int, 1);
pub const INT_FAST32_MIN = -__INT_FAST32_MAX__ - @as(c_int, 1);
pub const INT_FAST64_MIN = -__INT_FAST64_MAX__ - @as(c_int, 1);
pub const INT_LEAST8_MIN = -__INT_LEAST8_MAX__ - @as(c_int, 1);
pub const INT_LEAST16_MIN = -__INT_LEAST16_MAX__ - @as(c_int, 1);
pub const INT_LEAST32_MIN = -__INT_LEAST32_MAX__ - @as(c_int, 1);
pub const INT_LEAST64_MIN = -__INT_LEAST64_MAX__ - @as(c_int, 1);
pub const INT_FAST8_MAX = __INT_FAST8_MAX__;
pub const INT_FAST16_MAX = __INT_FAST16_MAX__;
pub const INT_FAST32_MAX = __INT_FAST32_MAX__;
pub const INT_FAST64_MAX = __INT_FAST64_MAX__;
pub const INT_LEAST8_MAX = __INT_LEAST8_MAX__;
pub const INT_LEAST16_MAX = __INT_LEAST16_MAX__;
pub const INT_LEAST32_MAX = __INT_LEAST32_MAX__;
pub const INT_LEAST64_MAX = __INT_LEAST64_MAX__;
pub const UINT_FAST8_MAX = __UINT_FAST8_MAX__;
pub const UINT_FAST16_MAX = __UINT_FAST16_MAX__;
pub const UINT_FAST32_MAX = __UINT_FAST32_MAX__;
pub const UINT_FAST64_MAX = __UINT_FAST64_MAX__;
pub const UINT_LEAST8_MAX = __UINT_LEAST8_MAX__;
pub const UINT_LEAST16_MAX = __UINT_LEAST16_MAX__;
pub const UINT_LEAST32_MAX = __UINT_LEAST32_MAX__;
pub const UINT_LEAST64_MAX = __UINT_LEAST64_MAX__;
pub const BC_BASE_MAX = @as(c_int, 99);
pub const BC_DIM_MAX = @as(c_int, 2048);
pub const BC_SCALE_MAX = @as(c_int, 99);
pub const BC_STRING_MAX = @as(c_int, 1000);
pub const CHARCLASS_NAME_MAX = @as(c_int, 14);
pub const COLL_WEIGHTS_MAX = @as(c_int, 2);
pub const EXPR_NEST_MAX = @as(c_int, 32);
pub const LINE_MAX = @as(c_int, 4096);
pub const RE_DUP_MAX = @as(c_int, 255);
pub const LONG_BIT = @as(c_int, 64);
pub const NZERO = @as(c_int, 20);
pub const NL_LANGMAX = @as(c_int, 32);
pub const COSMOPOLITAN_LIBC_ALG_ALG_H_ = "";
pub const COSMOPOLITAN_LIBC_MEM_ALLOCA_H_ = "";
pub const alloca = @compileError("unable to translate macro: undefined identifier `__builtin_alloca`");
// /src/cosmopolitan/libc/mem/alloca.h:4:9
pub const COSMOPOLITAN_LIBC_MEM_MEM_H_ = "";
pub const M_TRIM_THRESHOLD = -@as(c_int, 1);
pub const M_GRANULARITY = -@as(c_int, 2);
pub const M_MMAP_THRESHOLD = -@as(c_int, 3);
pub const M_RSEQ_MAX = -@as(c_int, 4);
pub const COSMOPOLITAN_LIBC_RUNTIME_RUNTIME_H_ = "";
pub const COSMOPOLITAN_LIBC_CALLS_DPRINTF_H_ = "";
pub const COSMOPOLITAN_LIBC_RAND_RAND_H_ = "";
pub const RAND_MAX = __INT_MAX__;
pub const COSMOPOLITAN_LIBC_STDLIB_H_ = "";
pub const COSMOPOLITAN_LIBC_STR_STR_H_ = "";
pub const INVALID_CODEPOINT = std.zig.c_translation.promoteIntLiteral(c_int, 0xfffd, .hex);
pub const WEOF = -@as(c_uint, 1);
pub const COSMOPOLITAN_LIBC_SYSV_CONSTS_EXIT_H_ = "";
pub const EXIT_FAILURE = @as(c_int, 1);
pub const EXIT_SUCCESS = @as(c_int, 0);
pub const COSMOPOLITAN_LIBC_TEMP_H_ = "";
pub const COSMOPOLITAN_THIRD_PARTY_MUSL_RAND48_H_ = "";
pub const _STRING_H = "";
pub const _ASSERT_H = "";
pub const assert = @compileError("unable to translate macro: undefined identifier `__FILE__`");
// /src/cosmopolitan/libc/assert.h:23:9
pub const static_assert = @compileError("unable to translate C expr: unexpected token '_Static_assert'");
// /src/cosmopolitan/libc/assert.h:29:9
pub inline fn lua_assert(c: anytype) anyopaque {
    _ = &c;
    return std.zig.c_translation.cast(anyopaque, @as(c_int, 0));
}
pub inline fn IsModeDbg() @TypeOf(@as(c_int, 0)) {
    return @as(c_int, 0);
}
pub const NDEBUG = @as(c_int, 1);
pub inline fn _bsr(x: anytype) @TypeOf(__builtin_clz(x)) {
    _ = &x;
    return __builtin_clz(x);
}
pub const WARNF = @compileError("unable to translate C expr: expected ')' instead got '...'");
// /tmp/lua_tc_defs.h:23:9
pub inline fn __die() @TypeOf(abort()) {
    return abort();
}
pub inline fn __get_tmpdir() @TypeOf("/tmp") {
    return "/tmp";
}
pub inline fn strlcpy(d: anytype, s: anytype, n: anytype) @TypeOf(strncpy(d, s, n)) {
    _ = &d;
    _ = &s;
    _ = &n;
    return strncpy(d, s, n);
}
pub inline fn strlcat(d: anytype, s: anytype, n: anytype) @TypeOf(strncat(d, s, (n - strlen(d)) - @as(c_int, 1))) {
    _ = &d;
    _ = &s;
    _ = &n;
    return strncat(d, s, (n - strlen(d)) - @as(c_int, 1));
}
pub inline fn appendw(b: anytype, w: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &b;
    _ = &w;
    return @as(c_int, 0);
}
pub const appendf = @compileError("unable to translate C expr: expected ')' instead got '...'");
// /tmp/lua_tc_defs.h:29:9
pub inline fn xrealloc(p: anytype, n: anytype) @TypeOf(realloc(p, n)) {
    _ = &p;
    _ = &n;
    return realloc(p, n);
}
pub inline fn IsWindows() @TypeOf(@as(c_int, 0)) {
    return @as(c_int, 0);
}
pub inline fn IsXnu() @TypeOf(@as(c_int, 0)) {
    return @as(c_int, 0);
}
pub inline fn IsOpenbsd() @TypeOf(@as(c_int, 0)) {
    return @as(c_int, 0);
}
pub inline fn IsNetbsd() @TypeOf(@as(c_int, 0)) {
    return @as(c_int, 0);
}
pub inline fn IsFreebsd() @TypeOf(@as(c_int, 0)) {
    return @as(c_int, 0);
}
pub inline fn IsTiny() @TypeOf(@as(c_int, 0)) {
    return @as(c_int, 0);
}
pub inline fn startswithi(s: anytype, p: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &s;
    _ = &p;
    return @as(c_int, 0);
}
pub const kCp437 = @compileError("unable to translate C expr: unexpected token 'const'");
// /tmp/lua_tc_defs.h:38:9
pub const lstrlib_c = "";
pub const LUA_LIB = "";
pub const COSMOPOLITAN_LIBC_MATH_H_ = "";
pub const M_E = @as(f64, 2.7182818284590452354);
pub const M_LOG2E = @as(f64, 1.4426950408889634074);
pub const M_LOG10E = @as(f64, 0.43429448190325182765);
pub const M_LN2 = @as(f64, 0.69314718055994530942);
pub const M_LN10 = @as(f64, 2.30258509299404568402);
pub const M_PI = @as(f64, 3.14159265358979323846);
pub const M_PI_2 = @as(f64, 1.57079632679489661923);
pub const M_PI_4 = @as(f64, 0.78539816339744830962);
pub const M_1_PI = @as(f64, 0.31830988618379067154);
pub const M_2_PI = @as(f64, 0.63661977236758134308);
pub const M_2_SQRTPI = @as(f64, 1.12837916709551257390);
pub const M_SQRT2 = @as(f64, 1.41421356237309504880);
pub const M_SQRT1_2 = @as(f64, 0.70710678118654752440);
pub const DBL_DECIMAL_DIG = __DBL_DECIMAL_DIG__;
pub const DBL_DIG = __DBL_DIG__;
pub const DBL_EPSILON = __DBL_EPSILON__;
pub const DBL_HAS_SUBNORM = __DBL_HAS_DENORM__;
pub const DBL_IS_IEC_60559 = @compileError("unable to translate macro: undefined identifier `__DBL_IS_IEC_60559__`");
// /src/cosmopolitan/libc/math.h:57:9
pub const DBL_MANT_DIG = __DBL_MANT_DIG__;
pub const DBL_MAX = __DBL_MAX__;
pub const DBL_MAX_10_EXP = __DBL_MAX_10_EXP__;
pub const DBL_MAX_EXP = __DBL_MAX_EXP__;
pub const DBL_MIN = __DBL_MIN__;
pub const DBL_MIN_10_EXP = __DBL_MIN_10_EXP__;
pub const DBL_MIN_EXP = __DBL_MIN_EXP__;
pub const DBL_NORM_MAX = __DBL_NORM_MAX__;
pub const DBL_TRUE_MIN = __DBL_DENORM_MIN__;
pub const DECIMAL_DIG = __LDBL_DECIMAL_DIG__;
pub const FLT_DECIMAL_DIG = __FLT_DECIMAL_DIG__;
pub const FLT_DIG = __FLT_DIG__;
pub const FLT_EPSILON = __FLT_EPSILON__;
pub const FLT_HAS_SUBNORM = __FLT_HAS_DENORM__;
pub const FLT_IS_IEC_60559 = @compileError("unable to translate macro: undefined identifier `__FLT_IS_IEC_60559__`");
// /src/cosmopolitan/libc/math.h:73:9
pub const FLT_MANT_DIG = __FLT_MANT_DIG__;
pub const FLT_MAX = __FLT_MAX__;
pub const FLT_MAX_10_EXP = __FLT_MAX_10_EXP__;
pub const FLT_MAX_EXP = __FLT_MAX_EXP__;
pub const FLT_MIN = __FLT_MIN__;
pub const FLT_MIN_10_EXP = __FLT_MIN_10_EXP__;
pub const FLT_MIN_EXP = __FLT_MIN_EXP__;
pub const FLT_NORM_MAX = __FLT_NORM_MAX__;
pub const FLT_RADIX = __FLT_RADIX__;
pub const FLT_TRUE_MIN = __FLT_DENORM_MIN__;
pub const HLF_MAX = @as(f32, 6.50e4);
pub const HLF_MIN = @as(f32, 3.10e-5);
pub const LDBL_DECIMAL_DIG = __LDBL_DECIMAL_DIG__;
pub const LDBL_DIG = __LDBL_DIG__;
pub const LDBL_EPSILON = __LDBL_EPSILON__;
pub const LDBL_HAS_SUBNORM = __LDBL_HAS_DENORM__;
pub const LDBL_IS_IEC_60559 = @compileError("unable to translate macro: undefined identifier `__LDBL_IS_IEC_60559__`");
// /src/cosmopolitan/libc/math.h:91:9
pub const LDBL_MANT_DIG = __LDBL_MANT_DIG__;
pub const LDBL_MAX = __LDBL_MAX__;
pub const LDBL_MAX_10_EXP = __LDBL_MAX_10_EXP__;
pub const LDBL_MAX_EXP = __LDBL_MAX_EXP__;
pub const LDBL_MIN = __LDBL_MIN__;
pub const LDBL_MIN_10_EXP = __LDBL_MIN_10_EXP__;
pub const LDBL_MIN_EXP = __LDBL_MIN_EXP__;
pub const LDBL_NORM_MAX = __LDBL_NORM_MAX__;
pub const LDBL_TRUE_MIN = __LDBL_DENORM_MIN__;
pub const FP_NAN = @as(c_int, 0);
pub const FP_INFINITE = @as(c_int, 1);
pub const FP_ZERO = @as(c_int, 2);
pub const FP_SUBNORMAL = @as(c_int, 3);
pub const FP_NORMAL = @as(c_int, 4);
pub const FP_ILOGB0 = -std.zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const FP_ILOGBNAN = -std.zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const MATH_ERRNO = @as(c_int, 1);
pub const MATH_ERREXCEPT = @as(c_int, 2);
pub const math_errhandling = MATH_ERRNO | MATH_ERREXCEPT;
pub const FP_FAST_FMA = @as(c_int, 1);
pub const FP_FAST_FMAF = @as(c_int, 1);
pub const NAN = __builtin_nanf("");
pub const INFINITY = __builtin_inff();
pub const HUGE_VAL = @compileError("unable to translate macro: undefined identifier `__builtin_inf`");
// /src/cosmopolitan/libc/math.h:136:9
pub const HUGE_VALF = __builtin_inff();
pub const HUGE_VALL = @compileError("unable to translate macro: undefined identifier `__builtin_infl`");
// /src/cosmopolitan/libc/math.h:138:9
pub inline fn isinf(x: anytype) @TypeOf(__builtin_isinf(x)) {
    _ = &x;
    return __builtin_isinf(x);
}
pub inline fn isnan(x: anytype) @TypeOf(__builtin_isnan(x)) {
    _ = &x;
    return __builtin_isnan(x);
}
pub const isfinite = @compileError("unable to translate macro: undefined identifier `__builtin_isfinite`");
// /src/cosmopolitan/libc/math.h:150:9
pub const isnormal = @compileError("unable to translate macro: undefined identifier `__builtin_isnormal`");
// /src/cosmopolitan/libc/math.h:151:9
pub const isgreater = @compileError("unable to translate macro: undefined identifier `__builtin_isgreater`");
// /src/cosmopolitan/libc/math.h:152:9
pub const isgreaterequal = @compileError("unable to translate macro: undefined identifier `__builtin_isgreaterequal`");
// /src/cosmopolitan/libc/math.h:153:9
pub const isless = @compileError("unable to translate macro: undefined identifier `__builtin_isless`");
// /src/cosmopolitan/libc/math.h:154:9
pub const islessequal = @compileError("unable to translate macro: undefined identifier `__builtin_islessequal`");
// /src/cosmopolitan/libc/math.h:155:9
pub const islessgreater = @compileError("unable to translate macro: undefined identifier `__builtin_islessgreater`");
// /src/cosmopolitan/libc/math.h:156:9
pub const isunordered = @compileError("unable to translate macro: undefined identifier `__builtin_isunordered`");
// /src/cosmopolitan/libc/math.h:157:9
pub const fpclassify = @compileError("unable to translate macro: undefined identifier `__builtin_fpclassify`");
// /src/cosmopolitan/libc/math.h:159:9
pub inline fn signbit(x: anytype) @TypeOf(__builtin_signbit(x)) {
    _ = &x;
    return __builtin_signbit(x);
}
pub const COSMOPOLITAN_THIRD_PARTY_LUA_COSMO_H_ = "";
pub const COSMOPOLITAN_LIBC_HTTP_HTTP_H_ = "";
pub const COSMOPOLITAN_SERIALIZE_H_ = "";
pub inline fn __SWAPBE16(x: anytype) @TypeOf(__builtin_bswap16(x)) {
    _ = &x;
    return __builtin_bswap16(x);
}
pub inline fn __SWAPBE32(x: anytype) @TypeOf(__builtin_bswap32(x)) {
    _ = &x;
    return __builtin_bswap32(x);
}
pub inline fn __SWAPBE64(x: anytype) @TypeOf(__builtin_bswap64(x)) {
    _ = &x;
    return __builtin_bswap64(x);
}
pub inline fn __SWAPLE16(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __SWAPLE32(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __SWAPLE64(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub const READ16LE = @compileError("unable to translate macro: undefined identifier `__x`");
// /src/cosmopolitan/libc/serialize.h:46:9
pub const READ16BE = @compileError("unable to translate macro: undefined identifier `__x`");
// /src/cosmopolitan/libc/serialize.h:53:9
pub const READ32LE = @compileError("unable to translate macro: undefined identifier `__x`");
// /src/cosmopolitan/libc/serialize.h:60:9
pub const READ32BE = @compileError("unable to translate macro: undefined identifier `__x`");
// /src/cosmopolitan/libc/serialize.h:67:9
pub const READ64LE = @compileError("unable to translate macro: undefined identifier `__x`");
// /src/cosmopolitan/libc/serialize.h:74:9
pub const READ64BE = @compileError("unable to translate macro: undefined identifier `__x`");
// /src/cosmopolitan/libc/serialize.h:81:9
pub const WRITE16LE = @compileError("unable to translate macro: undefined identifier `__p`");
// /src/cosmopolitan/libc/serialize.h:88:9
pub const WRITE16BE = @compileError("unable to translate macro: undefined identifier `__p`");
// /src/cosmopolitan/libc/serialize.h:96:9
pub const WRITE32LE = @compileError("unable to translate macro: undefined identifier `__p`");
// /src/cosmopolitan/libc/serialize.h:104:9
pub const WRITE32BE = @compileError("unable to translate macro: undefined identifier `__p`");
// /src/cosmopolitan/libc/serialize.h:112:9
pub const WRITE64LE = @compileError("unable to translate macro: undefined identifier `__p`");
// /src/cosmopolitan/libc/serialize.h:120:9
pub const WRITE64BE = @compileError("unable to translate macro: undefined identifier `__p`");
// /src/cosmopolitan/libc/serialize.h:128:9
pub const COSMOPOLITAN_LIBC_TIME_H_ = "";
pub const TIME_UTC = @as(c_int, 1);
pub const TIME_MONOTONIC = @as(c_int, 2);
pub const kHttpRequest = @as(c_int, 0);
pub const kHttpResponse = @as(c_int, 1);
pub const kHttpGet = READ32LE("GET");
pub const kHttpHead = READ32LE("HEAD");
pub const kHttpPost = READ32LE("POST");
pub const kHttpPut = READ32LE("PUT");
pub const kHttpDelete = READ64LE("DELETE\x00");
pub const kHttpOptions = READ64LE("OPTIONS");
pub const kHttpConnect = READ64LE("CONNECT");
pub const kHttpTrace = READ64LE("TRACE\x00\x00");
pub const kHttpStateStart = @as(c_int, 0);
pub const kHttpStateMethod = @as(c_int, 1);
pub const kHttpStateUri = @as(c_int, 2);
pub const kHttpStateVersion = @as(c_int, 3);
pub const kHttpStateStatus = @as(c_int, 4);
pub const kHttpStateMessage = @as(c_int, 5);
pub const kHttpStateName = @as(c_int, 6);
pub const kHttpStateColon = @as(c_int, 7);
pub const kHttpStateValue = @as(c_int, 8);
pub const kHttpStateCr = @as(c_int, 9);
pub const kHttpStateLf1 = @as(c_int, 10);
pub const kHttpStateLf2 = @as(c_int, 11);
pub const kHttpClientStateHeaders = @as(c_int, 0);
pub const kHttpClientStateBody = @as(c_int, 1);
pub const kHttpClientStateBodyChunked = @as(c_int, 2);
pub const kHttpClientStateBodyLengthed = @as(c_int, 3);
pub const kHttpStateChunkStart = @as(c_int, 0);
pub const kHttpStateChunkSize = @as(c_int, 1);
pub const kHttpStateChunkExt = @as(c_int, 2);
pub const kHttpStateChunkLf1 = @as(c_int, 3);
pub const kHttpStateChunk = @as(c_int, 4);
pub const kHttpStateChunkCr2 = @as(c_int, 5);
pub const kHttpStateChunkLf2 = @as(c_int, 6);
pub const kHttpStateTrailerStart = @as(c_int, 7);
pub const kHttpStateTrailer = @as(c_int, 8);
pub const kHttpStateTrailerLf1 = @as(c_int, 9);
pub const kHttpStateTrailerLf2 = @as(c_int, 10);
pub const kHttpHost = @as(c_int, 0);
pub const kHttpCacheControl = @as(c_int, 1);
pub const kHttpConnection = @as(c_int, 2);
pub const kHttpAccept = @as(c_int, 3);
pub const kHttpAcceptLanguage = @as(c_int, 4);
pub const kHttpAcceptEncoding = @as(c_int, 5);
pub const kHttpUserAgent = @as(c_int, 6);
pub const kHttpReferer = @as(c_int, 7);
pub const kHttpXForwardedFor = @as(c_int, 8);
pub const kHttpOrigin = @as(c_int, 9);
pub const kHttpUpgradeInsecureRequests = @as(c_int, 10);
pub const kHttpPragma = @as(c_int, 11);
pub const kHttpCookie = @as(c_int, 12);
pub const kHttpDnt = @as(c_int, 13);
pub const kHttpSecGpc = @as(c_int, 14);
pub const kHttpFrom = @as(c_int, 15);
pub const kHttpIfModifiedSince = @as(c_int, 16);
pub const kHttpXRequestedWith = @as(c_int, 17);
pub const kHttpXForwardedHost = @as(c_int, 18);
pub const kHttpXForwardedProto = @as(c_int, 19);
pub const kHttpXCsrfToken = @as(c_int, 20);
pub const kHttpSaveData = @as(c_int, 21);
pub const kHttpRange = @as(c_int, 22);
pub const kHttpContentLength = @as(c_int, 23);
pub const kHttpContentType = @as(c_int, 24);
pub const kHttpVary = @as(c_int, 25);
pub const kHttpDate = @as(c_int, 26);
pub const kHttpServer = @as(c_int, 27);
pub const kHttpExpires = @as(c_int, 28);
pub const kHttpContentEncoding = @as(c_int, 29);
pub const kHttpLastModified = @as(c_int, 30);
pub const kHttpEtag = @as(c_int, 31);
pub const kHttpAllow = @as(c_int, 32);
pub const kHttpContentRange = @as(c_int, 33);
pub const kHttpAcceptCharset = @as(c_int, 34);
pub const kHttpAccessControlAllowCredentials = @as(c_int, 35);
pub const kHttpAccessControlAllowHeaders = @as(c_int, 36);
pub const kHttpAccessControlAllowMethods = @as(c_int, 37);
pub const kHttpAccessControlAllowOrigin = @as(c_int, 38);
pub const kHttpAccessControlMaxAge = @as(c_int, 39);
pub const kHttpAccessControlMethod = @as(c_int, 40);
pub const kHttpAccessControlRequestHeaders = @as(c_int, 41);
pub const kHttpAccessControlRequestMethod = @as(c_int, 42);
pub const kHttpAccessControlRequestMethods = @as(c_int, 43);
pub const kHttpAge = @as(c_int, 44);
pub const kHttpAuthorization = @as(c_int, 45);
pub const kHttpContentBase = @as(c_int, 46);
pub const kHttpContentDescription = @as(c_int, 47);
pub const kHttpContentDisposition = @as(c_int, 48);
pub const kHttpContentLanguage = @as(c_int, 49);
pub const kHttpContentLocation = @as(c_int, 50);
pub const kHttpContentMd5 = @as(c_int, 51);
pub const kHttpExpect = @as(c_int, 52);
pub const kHttpIfMatch = @as(c_int, 53);
pub const kHttpIfNoneMatch = @as(c_int, 54);
pub const kHttpIfRange = @as(c_int, 55);
pub const kHttpIfUnmodifiedSince = @as(c_int, 56);
pub const kHttpKeepAlive = @as(c_int, 57);
pub const kHttpLink = @as(c_int, 58);
pub const kHttpLocation = @as(c_int, 59);
pub const kHttpMaxForwards = @as(c_int, 60);
pub const kHttpProxyAuthenticate = @as(c_int, 61);
pub const kHttpProxyAuthorization = @as(c_int, 62);
pub const kHttpProxyConnection = @as(c_int, 63);
pub const kHttpPublic = @as(c_int, 64);
pub const kHttpRetryAfter = @as(c_int, 65);
pub const kHttpTe = @as(c_int, 66);
pub const kHttpTrailer = @as(c_int, 67);
pub const kHttpTransferEncoding = @as(c_int, 68);
pub const kHttpUpgrade = @as(c_int, 69);
pub const kHttpWarning = @as(c_int, 70);
pub const kHttpWwwAuthenticate = @as(c_int, 71);
pub const kHttpVia = @as(c_int, 72);
pub const kHttpStrictTransportSecurity = @as(c_int, 73);
pub const kHttpXFrameOptions = @as(c_int, 74);
pub const kHttpXContentTypeOptions = @as(c_int, 75);
pub const kHttpAltSvc = @as(c_int, 76);
pub const kHttpReferrerPolicy = @as(c_int, 77);
pub const kHttpXXssProtection = @as(c_int, 78);
pub const kHttpAcceptRanges = @as(c_int, 79);
pub const kHttpSetCookie = @as(c_int, 80);
pub const kHttpSecChUa = @as(c_int, 81);
pub const kHttpSecChUaMobile = @as(c_int, 82);
pub const kHttpSecFetchSite = @as(c_int, 83);
pub const kHttpSecFetchMode = @as(c_int, 84);
pub const kHttpSecFetchUser = @as(c_int, 85);
pub const kHttpSecFetchDest = @as(c_int, 86);
pub const kHttpCfRay = @as(c_int, 87);
pub const kHttpCfVisitor = @as(c_int, 88);
pub const kHttpCfConnectingIp = @as(c_int, 89);
pub const kHttpCfIpcountry = @as(c_int, 90);
pub const kHttpSecChUaPlatform = @as(c_int, 91);
pub const kHttpCdnLoop = @as(c_int, 92);
pub const kHttpHeadersMax = @as(c_int, 93);
pub const COSMOPOLITAN_NET_HTTP_URL_H_ = "";
pub const kUrlPlus = @as(c_int, 1);
pub const kUrlLatin1 = @as(c_int, 2);
pub const kUrlOpaque = @as(c_int, 4);
pub const lauxlib_h = "";
pub const COSMOPOLITAN_LIBC_STDIO_H_ = "";
pub const EOF = -@as(c_int, 1);
pub const _IOFBF = @as(c_int, 0);
pub const _IOLBF = @as(c_int, 1);
pub const _IONBF = @as(c_int, 2);
pub const L_tmpnam = @as(c_int, 20);
pub const L_ctermid = @as(c_int, 20);
pub const P_tmpdir = "/tmp";
pub const FILENAME_MAX = @as(c_int, 1024);
pub const FOPEN_MAX = @as(c_int, 1000);
pub const TMP_MAX = @as(c_int, 10000);
pub const BUFSIZ = @as(c_int, 4096);
pub const COSMOPOLITAN_THIRD_PARTY_LUA_LUA_H_ = "";
pub const luaconf_h = "";
pub const COSMOPOLITAN_LIBC_STR_UNICODE_H_ = "";
pub const LUA_USE_LINENOISE = "";
pub const LUA_USE_POSIX = "";
pub const LUAI_IS32INT = (UINT_MAX >> @as(c_int, 30)) >= @as(c_int, 3);
pub const LUA_INT_INT = @as(c_int, 1);
pub const LUA_INT_LONG = @as(c_int, 2);
pub const LUA_INT_LONGLONG = @as(c_int, 3);
pub const LUA_FLOAT_FLOAT = @as(c_int, 1);
pub const LUA_FLOAT_DOUBLE = @as(c_int, 2);
pub const LUA_FLOAT_LONGDOUBLE = @as(c_int, 3);
pub const LUA_INT_DEFAULT = LUA_INT_LONGLONG;
pub const LUA_FLOAT_DEFAULT = LUA_FLOAT_DOUBLE;
pub const LUA_32BITS = @as(c_int, 0);
pub const LUA_C89_NUMBERS = @as(c_int, 0);
pub const LUA_INT_TYPE = LUA_INT_DEFAULT;
pub const LUA_FLOAT_TYPE = LUA_FLOAT_DEFAULT;
pub const LUA_PATH_SEP = ";";
pub const LUA_PATH_MARK = "?";
pub const LUA_EXEC_DIR = "!";
pub const LUA_VDIR = LUA_VERSION_MAJOR ++ "." ++ LUA_VERSION_MINOR;
pub const LUA_ROOT = "/zip/";
pub const LUA_LDIR = LUA_ROOT ++ ".lua/";
pub const LUA_CDIR = LUA_ROOT ++ ".lua/";
pub const LUA_PATH_DEFAULT = LUA_LDIR ++ "?.lua;" ++ LUA_LDIR ++ "?/init.lua;" ++ "./?.lua;" ++ "./?/init.lua";
pub const LUA_CPATH_DEFAULT = LUA_CDIR ++ "?.so;" ++ LUA_CDIR ++ "loadall.so;" ++ "./?.so";
pub const LUA_DIRSEP = "/";
pub const LUA_API = @compileError("unable to translate C expr: unexpected token 'extern'");
// /src/cosmopolitan/third_party/lua/luaconf.h:234:9
pub const LUALIB_API = LUA_API;
pub const LUAMOD_API = LUA_API;
pub const LUAI_FUNC = @compileError("unable to translate C expr: unexpected token 'extern'");
// /src/cosmopolitan/third_party/lua/luaconf.h:258:9
pub inline fn LUAI_DDEC(dec: anytype) @TypeOf(LUAI_FUNC ++ dec) {
    _ = &dec;
    return LUAI_FUNC ++ dec;
}
pub const LUAI_DDEF = "";
pub inline fn l_floor(x: anytype) @TypeOf(l_mathop(floor)(x)) {
    _ = &x;
    return l_mathop(floor)(x);
}
pub inline fn lua_number2str(s: anytype, sz: anytype, n: anytype) @TypeOf(l_sprintf(s, sz, LUA_NUMBER_FMT, LUAI_UACNUMBER(n))) {
    _ = &s;
    _ = &sz;
    _ = &n;
    return l_sprintf(s, sz, LUA_NUMBER_FMT, LUAI_UACNUMBER(n));
}
pub const lua_numbertointeger = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/luaconf.h:362:9
pub const LUA_NUMBER = f64;
pub const l_floatatt = @compileError("unable to translate macro: undefined identifier `DBL_`");
// /src/cosmopolitan/third_party/lua/luaconf.h:405:9
pub const LUAI_UACNUMBER = f64;
pub const LUA_NUMBER_FRMLEN = "";
pub const LUA_NUMBER_FMT = "%.14g";
pub inline fn l_mathop(op: anytype) @TypeOf(op) {
    _ = &op;
    return op;
}
pub inline fn lua_str2number(s: anytype, p: anytype) @TypeOf(strtod(s, p)) {
    _ = &s;
    _ = &p;
    return strtod(s, p);
}
pub const LUA_INTEGER_FMT = "%" ++ LUA_INTEGER_FRMLEN ++ "d";
pub const LUAI_UACINT = LUA_INTEGER;
pub inline fn lua_integer2str(s: anytype, sz: anytype, n: anytype) @TypeOf(l_sprintf(s, sz, LUA_INTEGER_FMT, LUAI_UACINT(n))) {
    _ = &s;
    _ = &sz;
    _ = &n;
    return l_sprintf(s, sz, LUA_INTEGER_FMT, LUAI_UACINT(n));
}
pub const LUA_UNSIGNED = c_uint ++ LUAI_UACINT;
pub const LUA_INTEGER = c_longlong;
pub const LUA_INTEGER_FRMLEN = "ll";
pub const LUA_MAXINTEGER = LLONG_MAX;
pub const LUA_MININTEGER = LLONG_MIN;
pub const LUA_MAXUNSIGNED = ULLONG_MAX;
pub inline fn l_sprintf(s: anytype, sz: anytype, f: anytype, i: anytype) @TypeOf(snprintf(s, sz, f, i)) {
    _ = &s;
    _ = &sz;
    _ = &f;
    _ = &i;
    return snprintf(s, sz, f, i);
}
pub inline fn lua_strx2number(s: anytype, p: anytype) @TypeOf(lua_str2number(s, p)) {
    _ = &s;
    _ = &p;
    return lua_str2number(s, p);
}
pub inline fn lua_pointer2str(buff: anytype, sz: anytype, p: anytype) @TypeOf(l_sprintf(buff, sz, "%p", p)) {
    _ = &buff;
    _ = &sz;
    _ = &p;
    return l_sprintf(buff, sz, "%p", p);
}
pub inline fn lua_number2strx(L: anytype, b: anytype, sz: anytype, f: anytype, n: anytype) @TypeOf(l_sprintf(b, sz, f, LUAI_UACNUMBER(n))) {
    _ = &L;
    _ = &b;
    _ = &sz;
    _ = &f;
    _ = &n;
    return blk_1: {
        _ = std.zig.c_translation.cast(anyopaque, L);
        break :blk_1 l_sprintf(b, sz, f, LUAI_UACNUMBER(n));
    };
}
pub const LUA_KCONTEXT = ptrdiff_t;
pub inline fn lua_getlocaledecpoint() @TypeOf(localeconv().*.decimal_point[@as(usize, @intCast(@as(c_int, 0)))]) {
    return localeconv().*.decimal_point[@as(usize, @intCast(@as(c_int, 0)))];
}
pub inline fn luai_likely(x: anytype) c_long {
    _ = &x;
    return __builtin_expect(@as(c_long, @intFromBool(x != @as(c_int, 0))), @as(c_long, 1));
}
pub inline fn luai_unlikely(x: anytype) @TypeOf(__builtin_expect(x != @as(c_int, 0), @as(c_int, 0))) {
    _ = &x;
    return __builtin_expect(x != @as(c_int, 0), @as(c_int, 0));
}
pub inline fn l_likely(x: anytype) @TypeOf(luai_likely(x)) {
    _ = &x;
    return luai_likely(x);
}
pub inline fn l_unlikely(x: anytype) @TypeOf(luai_unlikely(x)) {
    _ = &x;
    return luai_unlikely(x);
}
pub const LUAI_MAXSTACK = std.zig.c_translation.promoteIntLiteral(c_int, 1000000, .decimal);
pub const LUA_EXTRASPACE = std.zig.c_translation.sizeof(?*anyopaque);
pub const LUA_IDSIZE = @as(c_int, 60);
pub const LUAL_BUFFERSIZE = std.zig.c_translation.cast(c_int, (@as(c_int, 16) * std.zig.c_translation.sizeof(?*anyopaque)) * std.zig.c_translation.sizeof(lua_Number));
pub const LUAI_MAXALIGN = @compileError("unable to translate macro: undefined identifier `n`");
// /src/cosmopolitan/third_party/lua/luaconf.h:710:9
pub const LUA_VERSION_MAJOR = "5";
pub const LUA_VERSION_MINOR = "4";
pub const LUA_VERSION_RELEASE = "6";
pub const LUA_VERSION_NUM = @as(c_int, 504);
pub const LUA_VERSION_RELEASE_NUM = (LUA_VERSION_NUM * @as(c_int, 100)) + @as(c_int, 6);
pub const LUA_VERSION = "Lua " ++ LUA_VERSION_MAJOR ++ "." ++ LUA_VERSION_MINOR;
pub const LUA_RELEASE = LUA_VERSION ++ "." ++ LUA_VERSION_RELEASE;
pub const LUA_COPYRIGHT = LUA_RELEASE ++ "  Copyright (C) 1994-2023 Lua.org, PUC-Rio";
pub const LUA_AUTHORS = "R. Ierusalimschy, L. H. de Figueiredo, W. Celes";
pub const LUA_SIGNATURE = "\x1bLua";
pub const LUA_MULTRET = -@as(c_int, 1);
pub const LUA_REGISTRYINDEX = -LUAI_MAXSTACK - @as(c_int, 1000);
pub inline fn lua_upvalueindex(i: anytype) @TypeOf(LUA_REGISTRYINDEX - i) {
    _ = &i;
    return LUA_REGISTRYINDEX - i;
}
pub const LUA_OK = @as(c_int, 0);
pub const LUA_YIELD = @as(c_int, 1);
pub const LUA_ERRRUN = @as(c_int, 2);
pub const LUA_ERRSYNTAX = @as(c_int, 3);
pub const LUA_ERRMEM = @as(c_int, 4);
pub const LUA_ERRERR = @as(c_int, 5);
pub const LUA_TNONE = -@as(c_int, 1);
pub const LUA_TNIL = @as(c_int, 0);
pub const LUA_TBOOLEAN = @as(c_int, 1);
pub const LUA_TLIGHTUSERDATA = @as(c_int, 2);
pub const LUA_TNUMBER = @as(c_int, 3);
pub const LUA_TSTRING = @as(c_int, 4);
pub const LUA_TTABLE = @as(c_int, 5);
pub const LUA_TFUNCTION = @as(c_int, 6);
pub const LUA_TUSERDATA = @as(c_int, 7);
pub const LUA_TTHREAD = @as(c_int, 8);
pub const LUA_NUMTYPES = @as(c_int, 9);
pub const LUA_MINSTACK = @as(c_int, 20);
pub const LUA_RIDX_MAINTHREAD = @as(c_int, 1);
pub const LUA_RIDX_GLOBALS = @as(c_int, 2);
pub const LUA_RIDX_LAST = LUA_RIDX_GLOBALS;
pub const LUA_OPADD = @as(c_int, 0);
pub const LUA_OPSUB = @as(c_int, 1);
pub const LUA_OPMUL = @as(c_int, 2);
pub const LUA_OPMOD = @as(c_int, 3);
pub const LUA_OPPOW = @as(c_int, 4);
pub const LUA_OPDIV = @as(c_int, 5);
pub const LUA_OPIDIV = @as(c_int, 6);
pub const LUA_OPBAND = @as(c_int, 7);
pub const LUA_OPBOR = @as(c_int, 8);
pub const LUA_OPBXOR = @as(c_int, 9);
pub const LUA_OPSHL = @as(c_int, 10);
pub const LUA_OPSHR = @as(c_int, 11);
pub const LUA_OPUNM = @as(c_int, 12);
pub const LUA_OPBNOT = @as(c_int, 13);
pub const LUA_OPEQ = @as(c_int, 0);
pub const LUA_OPLT = @as(c_int, 1);
pub const LUA_OPLE = @as(c_int, 2);
pub inline fn lua_call(L: anytype, n: anytype, r: anytype) @TypeOf(lua_callk(L, n, r, @as(c_int, 0), NULL)) {
    _ = &L;
    _ = &n;
    _ = &r;
    return lua_callk(L, n, r, @as(c_int, 0), NULL);
}
pub inline fn lua_pcall(L: anytype, n: anytype, r: anytype, f: anytype) @TypeOf(lua_pcallk(L, n, r, f, @as(c_int, 0), NULL)) {
    _ = &L;
    _ = &n;
    _ = &r;
    _ = &f;
    return lua_pcallk(L, n, r, f, @as(c_int, 0), NULL);
}
pub inline fn lua_yield(L: anytype, n: anytype) @TypeOf(lua_yieldk(L, n, @as(c_int, 0), NULL)) {
    _ = &L;
    _ = &n;
    return lua_yieldk(L, n, @as(c_int, 0), NULL);
}
pub const LUA_GCSTOP = @as(c_int, 0);
pub const LUA_GCRESTART = @as(c_int, 1);
pub const LUA_GCCOLLECT = @as(c_int, 2);
pub const LUA_GCCOUNT = @as(c_int, 3);
pub const LUA_GCCOUNTB = @as(c_int, 4);
pub const LUA_GCSTEP = @as(c_int, 5);
pub const LUA_GCSETPAUSE = @as(c_int, 6);
pub const LUA_GCSETSTEPMUL = @as(c_int, 7);
pub const LUA_GCISRUNNING = @as(c_int, 9);
pub const LUA_GCGEN = @as(c_int, 10);
pub const LUA_GCINC = @as(c_int, 11);
pub inline fn lua_getextraspace(L: anytype) ?*anyopaque {
    _ = &L;
    return std.zig.c_translation.cast(?*anyopaque, std.zig.c_translation.cast([*c]u8, L) - LUA_EXTRASPACE);
}
pub inline fn lua_tonumber(L: anytype, i: anytype) @TypeOf(lua_tonumberx(L, i, NULL)) {
    _ = &L;
    _ = &i;
    return lua_tonumberx(L, i, NULL);
}
pub inline fn lua_tointeger(L: anytype, i: anytype) @TypeOf(lua_tointegerx(L, i, NULL)) {
    _ = &L;
    _ = &i;
    return lua_tointegerx(L, i, NULL);
}
pub inline fn lua_pop(L: anytype, n: anytype) @TypeOf(lua_settop(L, -n - @as(c_int, 1))) {
    _ = &L;
    _ = &n;
    return lua_settop(L, -n - @as(c_int, 1));
}
pub inline fn lua_newtable(L: anytype) @TypeOf(lua_createtable(L, @as(c_int, 0), @as(c_int, 0))) {
    _ = &L;
    return lua_createtable(L, @as(c_int, 0), @as(c_int, 0));
}
pub inline fn lua_register(L: anytype, n: anytype, f: anytype) @TypeOf(lua_setglobal(L, n)) {
    _ = &L;
    _ = &n;
    _ = &f;
    return blk_1: {
        _ = lua_pushcfunction(L, f);
        break :blk_1 lua_setglobal(L, n);
    };
}
pub inline fn lua_pushcfunction(L: anytype, f: anytype) @TypeOf(lua_pushcclosure(L, f, @as(c_int, 0))) {
    _ = &L;
    _ = &f;
    return lua_pushcclosure(L, f, @as(c_int, 0));
}
pub inline fn lua_isfunction(L: anytype, n: anytype) @TypeOf(lua_type(L, n) == LUA_TFUNCTION) {
    _ = &L;
    _ = &n;
    return lua_type(L, n) == LUA_TFUNCTION;
}
pub inline fn lua_istable(L: anytype, n: anytype) @TypeOf(lua_type(L, n) == LUA_TTABLE) {
    _ = &L;
    _ = &n;
    return lua_type(L, n) == LUA_TTABLE;
}
pub inline fn lua_islightuserdata(L: anytype, n: anytype) @TypeOf(lua_type(L, n) == LUA_TLIGHTUSERDATA) {
    _ = &L;
    _ = &n;
    return lua_type(L, n) == LUA_TLIGHTUSERDATA;
}
pub inline fn lua_isnil(L: anytype, n: anytype) @TypeOf(lua_type(L, n) == LUA_TNIL) {
    _ = &L;
    _ = &n;
    return lua_type(L, n) == LUA_TNIL;
}
pub inline fn lua_isboolean(L: anytype, n: anytype) @TypeOf(lua_type(L, n) == LUA_TBOOLEAN) {
    _ = &L;
    _ = &n;
    return lua_type(L, n) == LUA_TBOOLEAN;
}
pub inline fn lua_isthread(L: anytype, n: anytype) @TypeOf(lua_type(L, n) == LUA_TTHREAD) {
    _ = &L;
    _ = &n;
    return lua_type(L, n) == LUA_TTHREAD;
}
pub inline fn lua_isnone(L: anytype, n: anytype) @TypeOf(lua_type(L, n) == LUA_TNONE) {
    _ = &L;
    _ = &n;
    return lua_type(L, n) == LUA_TNONE;
}
pub inline fn lua_isnoneornil(L: anytype, n: anytype) @TypeOf(lua_type(L, n) <= @as(c_int, 0)) {
    _ = &L;
    _ = &n;
    return lua_type(L, n) <= @as(c_int, 0);
}
pub inline fn lua_pushliteral(L: anytype, s: anytype) @TypeOf(lua_pushstring(L, "" ++ s)) {
    _ = &L;
    _ = &s;
    return lua_pushstring(L, "" ++ s);
}
pub inline fn lua_pushglobaltable(L: anytype) anyopaque {
    _ = &L;
    return std.zig.c_translation.cast(anyopaque, lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS));
}
pub inline fn lua_tostring(L: anytype, i: anytype) @TypeOf(lua_tolstring(L, i, NULL)) {
    _ = &L;
    _ = &i;
    return lua_tolstring(L, i, NULL);
}
pub inline fn lua_insert(L: anytype, idx: anytype) @TypeOf(lua_rotate(L, idx, @as(c_int, 1))) {
    _ = &L;
    _ = &idx;
    return lua_rotate(L, idx, @as(c_int, 1));
}
pub inline fn lua_remove(L: anytype, idx: anytype) @TypeOf(lua_pop(L, @as(c_int, 1))) {
    _ = &L;
    _ = &idx;
    return blk_1: {
        _ = lua_rotate(L, idx, -@as(c_int, 1));
        break :blk_1 lua_pop(L, @as(c_int, 1));
    };
}
pub inline fn lua_replace(L: anytype, idx: anytype) @TypeOf(lua_pop(L, @as(c_int, 1))) {
    _ = &L;
    _ = &idx;
    return blk_1: {
        _ = lua_copy(L, -@as(c_int, 1), idx);
        break :blk_1 lua_pop(L, @as(c_int, 1));
    };
}
pub inline fn lua_newuserdata(L: anytype, s: anytype) @TypeOf(lua_newuserdatauv(L, s, @as(c_int, 1))) {
    _ = &L;
    _ = &s;
    return lua_newuserdatauv(L, s, @as(c_int, 1));
}
pub inline fn lua_getuservalue(L: anytype, idx: anytype) @TypeOf(lua_getiuservalue(L, idx, @as(c_int, 1))) {
    _ = &L;
    _ = &idx;
    return lua_getiuservalue(L, idx, @as(c_int, 1));
}
pub inline fn lua_setuservalue(L: anytype, idx: anytype) @TypeOf(lua_setiuservalue(L, idx, @as(c_int, 1))) {
    _ = &L;
    _ = &idx;
    return lua_setiuservalue(L, idx, @as(c_int, 1));
}
pub const LUA_NUMTAGS = LUA_NUMTYPES;
pub const LUA_HOOKCALL = @as(c_int, 0);
pub const LUA_HOOKRET = @as(c_int, 1);
pub const LUA_HOOKLINE = @as(c_int, 2);
pub const LUA_HOOKCOUNT = @as(c_int, 3);
pub const LUA_HOOKTAILCALL = @as(c_int, 4);
pub const LUA_MASKCALL = @as(c_int, 1) << LUA_HOOKCALL;
pub const LUA_MASKRET = @as(c_int, 1) << LUA_HOOKRET;
pub const LUA_MASKLINE = @as(c_int, 1) << LUA_HOOKLINE;
pub const LUA_MASKCOUNT = @as(c_int, 1) << LUA_HOOKCOUNT;
pub const LUA_GNAME = "_G";
pub const LUA_ERRFILE = LUA_ERRERR + @as(c_int, 1);
pub const LUA_LOADED_TABLE = "_LOADED";
pub const LUA_PRELOAD_TABLE = "_PRELOAD";
pub const LUAL_NUMSIZES = (std.zig.c_translation.sizeof(lua_Integer) * @as(c_int, 16)) + std.zig.c_translation.sizeof(lua_Number);
pub inline fn luaL_checkversion(L: anytype) @TypeOf(luaL_checkversion_(L, LUA_VERSION_NUM, LUAL_NUMSIZES)) {
    _ = &L;
    return luaL_checkversion_(L, LUA_VERSION_NUM, LUAL_NUMSIZES);
}
pub const LUA_NOREF = -@as(c_int, 2);
pub const LUA_REFNIL = -@as(c_int, 1);
pub inline fn luaL_loadfile(L: anytype, f: anytype) @TypeOf(luaL_loadfilex(L, f, NULL)) {
    _ = &L;
    _ = &f;
    return luaL_loadfilex(L, f, NULL);
}
pub const luaL_newlibtable = @compileError("unable to translate C expr: unexpected token '('");
// /src/cosmopolitan/third_party/lua/lauxlib.h:121:9
pub inline fn luaL_newlib(L: anytype, l: anytype) @TypeOf(luaL_setfuncs(L, l, @as(c_int, 0))) {
    _ = &L;
    _ = &l;
    return blk_1: {
        _ = luaL_checkversion(L);
        _ = luaL_newlibtable(L, l);
        break :blk_1 luaL_setfuncs(L, l, @as(c_int, 0));
    };
}
pub inline fn luaL_argcheck(L: anytype, cond: anytype, arg: anytype, extramsg: anytype) void {
    _ = &L;
    _ = &cond;
    _ = &arg;
    _ = &extramsg;
    if (luai_likely(cond) == 0) _ = luaL_argerror(L, arg, extramsg);
}
pub inline fn luaL_argexpected(L: anytype, cond: anytype, arg: anytype, tname: anytype) anyopaque {
    _ = &L;
    _ = &cond;
    _ = &arg;
    _ = &tname;
    return std.zig.c_translation.cast(anyopaque, (luai_likely(cond) != 0) or (luaL_typeerror(L, arg, tname) != 0));
}
pub inline fn luaL_checkstring(L: anytype, n: anytype) @TypeOf(luaL_checklstring(L, n, NULL)) {
    _ = &L;
    _ = &n;
    return luaL_checklstring(L, n, NULL);
}
pub inline fn luaL_optstring(L: anytype, n: anytype, d: anytype) @TypeOf(luaL_optlstring(L, n, d, NULL)) {
    _ = &L;
    _ = &n;
    _ = &d;
    return luaL_optlstring(L, n, d, NULL);
}
pub inline fn luaL_typename(L: anytype, i: anytype) @TypeOf(lua_typename(L, lua_type(L, i))) {
    _ = &L;
    _ = &i;
    return lua_typename(L, lua_type(L, i));
}
pub inline fn luaL_dofile(L: anytype, @"fn": anytype) @TypeOf((luaL_loadfile(L, @"fn") != 0) or (lua_pcall(L, @as(c_int, 0), LUA_MULTRET, @as(c_int, 0)) != 0)) {
    _ = &L;
    _ = &@"fn";
    return (luaL_loadfile(L, @"fn") != 0) or (lua_pcall(L, @as(c_int, 0), LUA_MULTRET, @as(c_int, 0)) != 0);
}
pub inline fn luaL_dostring(L: anytype, s: anytype) @TypeOf((luaL_loadstring(L, s) != 0) or (lua_pcall(L, @as(c_int, 0), LUA_MULTRET, @as(c_int, 0)) != 0)) {
    _ = &L;
    _ = &s;
    return (luaL_loadstring(L, s) != 0) or (lua_pcall(L, @as(c_int, 0), LUA_MULTRET, @as(c_int, 0)) != 0);
}
pub inline fn luaL_getmetatable(L: anytype, n: anytype) @TypeOf(lua_getfield(L, LUA_REGISTRYINDEX, n)) {
    _ = &L;
    _ = &n;
    return lua_getfield(L, LUA_REGISTRYINDEX, n);
}
pub inline fn luaL_opt(L: anytype, f: anytype, n: anytype, d: anytype) @TypeOf(if (lua_isnoneornil(L, n) != 0) d else f(L, n)) {
    _ = &L;
    _ = &f;
    _ = &n;
    _ = &d;
    return if (lua_isnoneornil(L, n) != 0) d else f(L, n);
}
pub inline fn luaL_loadbuffer(L: anytype, s: anytype, sz: anytype, n: anytype) @TypeOf(luaL_loadbufferx(L, s, sz, n, NULL)) {
    _ = &L;
    _ = &s;
    _ = &sz;
    _ = &n;
    return luaL_loadbufferx(L, s, sz, n, NULL);
}
pub inline fn luaL_intop(op: anytype, v1: anytype, v2: anytype) lua_Integer {
    _ = &op;
    _ = &v1;
    _ = &v2;
    return std.zig.c_translation.cast(lua_Integer, std.zig.c_translation.cast(lua_Unsigned, v1 ++ op(lua_Unsigned)(v2)));
}
pub inline fn luaL_pushfail(L: anytype) @TypeOf(lua_pushnil(L)) {
    _ = &L;
    return lua_pushnil(L);
}
pub inline fn luaL_bufflen(bf: anytype) @TypeOf(bf.*.n) {
    _ = &bf;
    return bf.*.n;
}
pub inline fn luaL_buffaddr(bf: anytype) @TypeOf(bf.*.b) {
    _ = &bf;
    return bf.*.b;
}
pub const luaL_addchar = @compileError("TODO postfix inc/dec expr");
// /src/cosmopolitan/third_party/lua/lauxlib.h:201:9
pub const luaL_addsize = @compileError("unable to translate C expr: expected ')' instead got '+='");
// /src/cosmopolitan/third_party/lua/lauxlib.h:205:9
pub const luaL_buffsub = @compileError("unable to translate C expr: expected ')' instead got '-='");
// /src/cosmopolitan/third_party/lua/lauxlib.h:207:9
pub inline fn luaL_prepbuffer(B: anytype) @TypeOf(luaL_prepbuffsize(B, LUAL_BUFFERSIZE)) {
    _ = &B;
    return luaL_prepbuffsize(B, LUAL_BUFFERSIZE);
}
pub const LUA_FILEHANDLE = "FILE*";
pub inline fn lua_writestring(s: anytype, l: anytype) @TypeOf(fwrite(s, std.zig.c_translation.sizeof(u8), l, stdout)) {
    _ = &s;
    _ = &l;
    return fwrite(s, std.zig.c_translation.sizeof(u8), l, stdout);
}
pub inline fn lua_writeline() @TypeOf(fflush(stdout)) {
    return blk_1: {
        _ = lua_writestring("\n", @as(c_int, 1));
        break :blk_1 fflush(stdout);
    };
}
pub inline fn lua_writestringerror(s: anytype, p: anytype) @TypeOf(fflush(stderr)) {
    _ = &s;
    _ = &p;
    return blk_1: {
        _ = fprintf(stderr, s, p);
        break :blk_1 fflush(stderr);
    };
}
pub const COSMOPOLITAN_THIRD_PARTY_LUA_VISITOR_H_ = "";
pub const lprefix_h = "";
pub const _XOPEN_SOURCE = @as(c_int, 600);
pub const COSMOPOLITAN_CTYPE_H_ = "";
pub inline fn _tolower(u: anytype) @TypeOf(@as(c_int, 0o040) | u) {
    _ = &u;
    return @as(c_int, 0o040) | u;
}
pub inline fn _toupper(u: anytype) @TypeOf(@as(c_int, 0o137) & u) {
    _ = &u;
    return @as(c_int, 0o137) & u;
}
pub const lualib_h = "";
pub const LUA_VERSUFFIX = "_" ++ LUA_VERSION_MAJOR ++ "_" ++ LUA_VERSION_MINOR;
pub const LUA_COLIBNAME = "coroutine";
pub const LUA_TABLIBNAME = "table";
pub const LUA_IOLIBNAME = "io";
pub const LUA_OSLIBNAME = "os";
pub const LUA_STRLIBNAME = "string";
pub const LUA_UTF8LIBNAME = "utf8";
pub const LUA_MATHLIBNAME = "math";
pub const LUA_DBLIBNAME = "debug";
pub const LUA_LOADLIBNAME = "package";
pub const LUA_MAXCAPTURES = @as(c_int, 32);
pub inline fn uchar(c: anytype) u8 {
    _ = &c;
    return std.zig.c_translation.cast(u8, c);
}
pub const MAX_SIZET = std.zig.c_translation.cast(usize, ~std.zig.c_translation.cast(usize, @as(c_int, 0)));
pub const MAXSIZE = if (std.zig.c_translation.sizeof(usize) < std.zig.c_translation.sizeof(c_int)) MAX_SIZET else std.zig.c_translation.cast(usize, INT_MAX);
pub const CAP_UNFINISHED = -@as(c_int, 1);
pub const CAP_POSITION = -@as(c_int, 2);
pub const MAXCCALLS = @as(c_int, 200);
extern fn earlyPutc(c: u8) void;
pub const L_ESC = '%';

// Zig-native formatters for str_format (replaces snprintf calls)
fn zigFmtInt(buf: [*c]u8, size: usize, val: c_longlong) c_int {
    var v: i64 = val;
    var pos: usize = 0;
    if (v < 0) { if (pos < size) { buf[pos] = '-'; pos += 1; } v = -v; }
    var digits: [20]u8 = undefined;
    var dlen: usize = 0;
    if (v == 0) { digits[0] = '0'; dlen = 1; } else {
        var u: u64 = @intCast(v);
        while (u > 0) : (dlen += 1) { digits[dlen] = @intCast(u % 10 + '0'); u /= 10; }
    }
    var d = dlen;
    while (d > 0 and pos < size) { d -= 1; buf[pos] = digits[d]; pos += 1; }
    return @intCast(pos);
}

fn zigFmtHex(buf: [*c]u8, size: usize, val: u64, is_octal: bool) c_int {
    _ = is_octal;
    const hex = "0123456789abcdef";
    var pos: usize = 0;
    if (pos + 2 < size) { buf[pos] = '0'; pos += 1; buf[pos] = 'x'; pos += 1; }
    var started = false;
    var i: u5 = 0;
    while (i < 16) : (i += 1) {
        const shift: u6 = @intCast((@as(u7, 15) - i) * 4);
        const nibble: u4 = @truncate(val >> shift);
        if (nibble != 0 or started or i == 15) {
            if (pos < size) { buf[pos] = hex[nibble]; pos += 1; }
            started = true;
        }
    }
    return @intCast(pos);
}
pub const SPECIALS = "^$*+?.([%-";
pub const MAX_ITEMF = @compileError("unable to translate macro: undefined identifier `MAX_10_EXP`");
// /src/cosmopolitan/third_party/lua/lstrlib.c:1117:9
pub const MAX_ITEM = @as(c_int, 120);
pub const L_FMTFLAGSF = "-+#0 ";
pub const L_FMTFLAGSX = "-#0";
pub const L_FMTFLAGSI = "-+0 ";
pub const L_FMTFLAGSU = "-0";
pub const L_FMTFLAGSC = "-";
pub const MAX_FORMAT = @as(c_int, 32);
pub const LUAL_PACKPADBYTE = @as(c_int, 0x00);
pub const MAXINTSIZE = @as(c_int, 16);
pub const NB = CHAR_BIT;
pub const MC = (@as(c_int, 1) << NB) - @as(c_int, 1);
pub const SZINT = std.zig.c_translation.cast(c_int, std.zig.c_translation.sizeof(lua_Integer));
pub const termios = struct_termios;
pub const winsize = struct_winsize;
pub const tm = struct_tm;
pub const HttpSlice = struct_HttpSlice;
pub const HttpHeader = struct_HttpHeader;
pub const HttpHeaders = struct_HttpHeaders;
pub const HttpMessage = struct_HttpMessage;
pub const HttpUnchunker = struct_HttpUnchunker;
pub const UrlView = struct_UrlView;
pub const UrlParams = struct_UrlParams;
pub const Url = struct_Url;
pub const lconv = struct_lconv;
pub const LuaVisited = struct_LuaVisited;
pub const EncoderConfig = struct_EncoderConfig;
pub const Serializer = struct_Serializer;
pub const str_Writer = struct_str_Writer;
