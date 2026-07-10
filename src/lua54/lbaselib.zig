pub const __builtin_bswap16 = @import("std").zig.c_builtins.__builtin_bswap16;
pub const __builtin_bswap32 = @import("std").zig.c_builtins.__builtin_bswap32;
pub const __builtin_bswap64 = @import("std").zig.c_builtins.__builtin_bswap64;
pub const __builtin_signbit = @import("std").zig.c_builtins.__builtin_signbit;
pub const __builtin_signbitf = @import("std").zig.c_builtins.__builtin_signbitf;
pub const __builtin_popcount = @import("std").zig.c_builtins.__builtin_popcount;
pub const __builtin_ctz = @import("std").zig.c_builtins.__builtin_ctz;
pub const __builtin_clz = @import("std").zig.c_builtins.__builtin_clz;
pub const __builtin_sqrt = @import("std").zig.c_builtins.__builtin_sqrt;
pub const __builtin_sqrtf = @import("std").zig.c_builtins.__builtin_sqrtf;
pub const __builtin_sin = @import("std").zig.c_builtins.__builtin_sin;
pub const __builtin_sinf = @import("std").zig.c_builtins.__builtin_sinf;
pub const __builtin_cos = @import("std").zig.c_builtins.__builtin_cos;
pub const __builtin_cosf = @import("std").zig.c_builtins.__builtin_cosf;
pub const __builtin_exp = @import("std").zig.c_builtins.__builtin_exp;
pub const __builtin_expf = @import("std").zig.c_builtins.__builtin_expf;
pub const __builtin_exp2 = @import("std").zig.c_builtins.__builtin_exp2;
pub const __builtin_exp2f = @import("std").zig.c_builtins.__builtin_exp2f;
pub const __builtin_log = @import("std").zig.c_builtins.__builtin_log;
pub const __builtin_logf = @import("std").zig.c_builtins.__builtin_logf;
pub const __builtin_log2 = @import("std").zig.c_builtins.__builtin_log2;
pub const __builtin_log2f = @import("std").zig.c_builtins.__builtin_log2f;
pub const __builtin_log10 = @import("std").zig.c_builtins.__builtin_log10;
pub const __builtin_log10f = @import("std").zig.c_builtins.__builtin_log10f;
pub const __builtin_abs = @import("std").zig.c_builtins.__builtin_abs;
pub const __builtin_labs = @import("std").zig.c_builtins.__builtin_labs;
pub const __builtin_llabs = @import("std").zig.c_builtins.__builtin_llabs;
pub const __builtin_fabs = @import("std").zig.c_builtins.__builtin_fabs;
pub const __builtin_fabsf = @import("std").zig.c_builtins.__builtin_fabsf;
pub const __builtin_floor = @import("std").zig.c_builtins.__builtin_floor;
pub const __builtin_floorf = @import("std").zig.c_builtins.__builtin_floorf;
pub const __builtin_ceil = @import("std").zig.c_builtins.__builtin_ceil;
pub const __builtin_ceilf = @import("std").zig.c_builtins.__builtin_ceilf;
pub const __builtin_trunc = @import("std").zig.c_builtins.__builtin_trunc;
pub const __builtin_truncf = @import("std").zig.c_builtins.__builtin_truncf;
pub const __builtin_round = @import("std").zig.c_builtins.__builtin_round;
pub const __builtin_roundf = @import("std").zig.c_builtins.__builtin_roundf;
pub const __builtin_strlen = @import("std").zig.c_builtins.__builtin_strlen;
pub const __builtin_strcmp = @import("std").zig.c_builtins.__builtin_strcmp;
pub const __builtin_object_size = @import("std").zig.c_builtins.__builtin_object_size;
pub const __builtin___memset_chk = @import("std").zig.c_builtins.__builtin___memset_chk;
pub const __builtin_memset = @import("std").zig.c_builtins.__builtin_memset;
pub const __builtin___memcpy_chk = @import("std").zig.c_builtins.__builtin___memcpy_chk;
pub const __builtin_memcpy = @import("std").zig.c_builtins.__builtin_memcpy;
pub const __builtin_expect = @import("std").zig.c_builtins.__builtin_expect;
pub const __builtin_nanf = @import("std").zig.c_builtins.__builtin_nanf;
pub const __builtin_huge_valf = @import("std").zig.c_builtins.__builtin_huge_valf;
pub const __builtin_inff = @import("std").zig.c_builtins.__builtin_inff;
pub const __builtin_isnan = @import("std").zig.c_builtins.__builtin_isnan;
pub const __builtin_isinf = @import("std").zig.c_builtins.__builtin_isinf;
pub const __builtin_isinf_sign = @import("std").zig.c_builtins.__builtin_isinf_sign;
pub const __has_builtin = @import("std").zig.c_builtins.__has_builtin;
pub const __builtin_assume = @import("std").zig.c_builtins.__builtin_assume;
pub const __builtin_unreachable = @import("std").zig.c_builtins.__builtin_unreachable;
pub const __builtin_constant_p = @import("std").zig.c_builtins.__builtin_constant_p;
pub const __builtin_mul_overflow = @import("std").zig.c_builtins.__builtin_mul_overflow;
pub const wchar_t = c_uint;
pub const char16_t = c_ushort;
pub const char32_t = c_uint;
pub const errno_t = c_int;
pub const ptrdiff_t = isize;
pub const wint_t = c_uint;
pub const bool32 = c_int;
pub const intmax_t = c_long;
pub const uintmax_t = c_ulong;
pub const max_align_t = c_longdouble;
pub const axdx_t = extern struct {
    ax: isize = @import("std").mem.zeroes(isize),
    dx: isize = @import("std").mem.zeroes(isize),
};
pub const sig_atomic_t = c_int;
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
    c_iflag: u32 = @import("std").mem.zeroes(u32),
    c_oflag: u32 = @import("std").mem.zeroes(u32),
    c_cflag: u32 = @import("std").mem.zeroes(u32),
    c_lflag: u32 = @import("std").mem.zeroes(u32),
    c_cc: [20]u8 = @import("std").mem.zeroes([20]u8),
    _c_ispeed: u32 = @import("std").mem.zeroes(u32),
    _c_ospeed: u32 = @import("std").mem.zeroes(u32),
};
pub const struct_winsize = extern struct {
    ws_row: u16 = @import("std").mem.zeroes(u16),
    ws_col: u16 = @import("std").mem.zeroes(u16),
    ws_xpixel: u16 = @import("std").mem.zeroes(u16),
    ws_ypixel: u16 = @import("std").mem.zeroes(u16),
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
    quot: c_int = @import("std").mem.zeroes(c_int),
    rem: c_int = @import("std").mem.zeroes(c_int),
};
pub const ldiv_t = extern struct {
    quot: c_long = @import("std").mem.zeroes(c_long),
    rem: c_long = @import("std").mem.zeroes(c_long),
};
pub const lldiv_t = extern struct {
    quot: c_longlong = @import("std").mem.zeroes(c_longlong),
    rem: c_longlong = @import("std").mem.zeroes(c_longlong),
};
pub const imaxdiv_t = extern struct {
    quot: intmax_t = @import("std").mem.zeroes(intmax_t),
    rem: intmax_t = @import("std").mem.zeroes(intmax_t),
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
pub extern fn malloc(usize) ?*anyopaque;
pub extern fn calloc(usize, usize) ?*anyopaque;
pub extern fn memalign(usize, usize) ?*anyopaque;
pub extern fn realloc(?*anyopaque, usize) ?*anyopaque;
pub extern fn realloc_in_place(?*anyopaque, usize) ?*anyopaque;
pub extern fn reallocarray(?*anyopaque, usize, usize) ?*anyopaque;
pub extern fn valloc(usize) ?*anyopaque;
pub extern fn pvalloc(usize) ?*anyopaque;
pub extern fn strdup([*c]const u8) [*c]u8;
pub extern fn strndup([*c]const u8, usize) [*c]u8;
pub extern fn aligned_alloc(usize, usize) ?*anyopaque;
pub extern fn posix_memalign([*c]?*anyopaque, usize, usize) c_int;
pub extern fn mallopt(c_int, c_int) c_int;
pub extern fn malloc_trim(usize) c_int;
pub extern fn malloc_usable_size(?*anyopaque) usize;
pub extern fn wcsdup([*c]const wchar_t) [*c]wchar_t;
pub const struct_mallinfo = extern struct {
    arena: usize = @import("std").mem.zeroes(usize),
    ordblks: usize = @import("std").mem.zeroes(usize),
    smblks: usize = @import("std").mem.zeroes(usize),
    hblks: usize = @import("std").mem.zeroes(usize),
    hblkhd: usize = @import("std").mem.zeroes(usize),
    usmblks: usize = @import("std").mem.zeroes(usize),
    fsmblks: usize = @import("std").mem.zeroes(usize),
    uordblks: usize = @import("std").mem.zeroes(usize),
    fordblks: usize = @import("std").mem.zeroes(usize),
    keepcost: usize = @import("std").mem.zeroes(usize),
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
    __stack: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __gr_top: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __vr_top: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __gr_offs: c_int = @import("std").mem.zeroes(c_int),
    __vr_offs: c_int = @import("std").mem.zeroes(c_int),
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
pub extern fn memset(?*anyopaque, c_int, usize) ?*anyopaque;
pub extern fn memmove(?*anyopaque, ?*const anyopaque, usize) ?*anyopaque;
pub extern fn memcpy(?*anyopaque, ?*const anyopaque, usize) ?*anyopaque;
pub extern fn hexpcpy([*c]u8, ?*const anyopaque, usize) [*c]u8;
pub extern fn memcmp(?*const anyopaque, ?*const anyopaque, usize) c_int;
pub extern fn timingsafe_bcmp(?*const anyopaque, ?*const anyopaque, usize) c_int;
pub extern fn timingsafe_memcmp(?*const anyopaque, ?*const anyopaque, usize) c_int;
pub extern fn strlen([*c]const u8) c_ulong;
pub extern fn strnlen([*c]const u8, usize) usize;
pub extern fn strnlen_s([*c]const u8, usize) usize;
pub extern fn strchr([*c]const u8, c_int) [*c]u8;
pub extern fn memchr(?*const anyopaque, c_int, usize) ?*anyopaque;
pub extern fn rawmemchr(?*const anyopaque, c_int) ?*anyopaque;
pub extern fn wcslen([*c]const c_uint) c_ulong;
pub extern fn wcsnlen([*c]const wchar_t, usize) usize;
pub extern fn wcsnlen_s([*c]const wchar_t, usize) usize;
pub extern fn wcschr([*c]const c_uint, c_uint) [*c]c_uint;
pub extern fn wmemchr([*c]const c_uint, c_uint, usize) [*c]c_uint;
pub extern fn wcschrnul([*c]const wchar_t, wchar_t) [*c]wchar_t;
pub extern fn strstr([*c]const u8, [*c]const u8) [*c]u8;
pub extern fn wcsstr([*c]const wchar_t, [*c]const wchar_t) [*c]wchar_t;
pub extern fn strcmp([*c]const u8, [*c]const u8) c_int;
pub extern fn strncmp([*c]const u8, [*c]const u8, usize) c_int;
pub extern fn wcscmp([*c]const c_uint, [*c]const c_uint) c_int;
pub extern fn wcsncmp([*c]const c_uint, [*c]const c_uint, usize) c_int;
pub extern fn wmemcmp([*c]const c_uint, [*c]const c_uint, usize) c_int;
pub extern fn strcasecmp([*c]const u8, [*c]const u8) c_int;
pub extern fn wcscasecmp([*c]const wchar_t, [*c]const wchar_t) c_int;
pub extern fn strncasecmp([*c]const u8, [*c]const u8, usize) c_int;
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
pub extern fn stpncpy([*c]u8, [*c]const u8, usize) [*c]u8;
pub extern fn strcat([*c]u8, [*c]const u8) [*c]u8;
pub extern fn wcscat([*c]wchar_t, [*c]const wchar_t) [*c]wchar_t;
pub extern fn strxfrm([*c]u8, [*c]const u8, usize) usize;
pub extern fn strcpy([*c]u8, [*c]const u8) [*c]u8;
pub extern fn wcscpy([*c]wchar_t, [*c]const wchar_t) [*c]wchar_t;
pub extern fn strncat([*c]u8, [*c]const u8, usize) [*c]u8;
pub extern fn wcsncat([*c]wchar_t, [*c]const wchar_t, usize) [*c]wchar_t;
pub extern fn strncpy([*c]u8, [*c]const u8, usize) [*c]u8;
pub extern fn strtok([*c]u8, [*c]const u8) [*c]u8;
pub extern fn strtok_r([*c]u8, [*c]const u8, [*c][*c]u8) [*c]u8;
pub extern fn wcstok([*c]wchar_t, [*c]const wchar_t, [*c][*c]wchar_t) [*c]wchar_t;
pub extern fn wmemset([*c]wchar_t, wchar_t, usize) [*c]wchar_t;
pub extern fn wmemcpy([*c]c_uint, [*c]const c_uint, usize) [*c]c_uint;
pub extern fn wmemmove([*c]c_uint, [*c]const c_uint, usize) [*c]c_uint;
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
pub extern fn bcmp(?*const anyopaque, ?*const anyopaque, usize) c_int;
pub extern fn bcopy(?*const anyopaque, ?*anyopaque, usize) void;
pub extern fn bzero(?*anyopaque, usize) void;
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
pub extern fn fread(?*anyopaque, usize, usize, ?*FILE) usize;
pub extern fn fwrite(?*const anyopaque, usize, usize, ?*FILE) usize;
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
pub extern fn snprintf(noalias [*c]u8, usize, noalias [*c]const u8, ...) c_int;
pub extern fn vsnprintf(noalias [*c]u8, usize, noalias [*c]const u8, __builtin_va_list) c_int;
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
    decimal_point: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    thousands_sep: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    grouping: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    int_curr_symbol: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    currency_symbol: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    mon_decimal_point: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    mon_thousands_sep: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    mon_grouping: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    positive_sign: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    negative_sign: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    int_frac_digits: u8 = @import("std").mem.zeroes(u8),
    frac_digits: u8 = @import("std").mem.zeroes(u8),
    p_cs_precedes: u8 = @import("std").mem.zeroes(u8),
    p_sep_by_space: u8 = @import("std").mem.zeroes(u8),
    n_cs_precedes: u8 = @import("std").mem.zeroes(u8),
    n_sep_by_space: u8 = @import("std").mem.zeroes(u8),
    p_sign_posn: u8 = @import("std").mem.zeroes(u8),
    n_sign_posn: u8 = @import("std").mem.zeroes(u8),
    int_p_cs_precedes: u8 = @import("std").mem.zeroes(u8),
    int_n_cs_precedes: u8 = @import("std").mem.zeroes(u8),
    int_p_sep_by_space: u8 = @import("std").mem.zeroes(u8),
    int_n_sep_by_space: u8 = @import("std").mem.zeroes(u8),
    int_p_sign_posn: u8 = @import("std").mem.zeroes(u8),
    int_n_sign_posn: u8 = @import("std").mem.zeroes(u8),
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
pub const struct_CallInfo_2 = opaque {};
pub const struct_lua_Debug = extern struct {
    event: c_int = @import("std").mem.zeroes(c_int),
    name: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    namewhat: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    what: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    source: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    srclen: usize = @import("std").mem.zeroes(usize),
    currentline: c_int = @import("std").mem.zeroes(c_int),
    linedefined: c_int = @import("std").mem.zeroes(c_int),
    lastlinedefined: c_int = @import("std").mem.zeroes(c_int),
    nups: u8 = @import("std").mem.zeroes(u8),
    nparams: u8 = @import("std").mem.zeroes(u8),
    isvararg: u8 = @import("std").mem.zeroes(u8),
    istailcall: u8 = @import("std").mem.zeroes(u8),
    ftransfer: c_ushort = @import("std").mem.zeroes(c_ushort),
    ntransfer: c_ushort = @import("std").mem.zeroes(c_ushort),
    short_src: [60]u8 = @import("std").mem.zeroes([60]u8),
    i_ci: ?*struct_CallInfo_2 = @import("std").mem.zeroes(?*struct_CallInfo_2),
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
const union_unnamed_3 = extern union {
    n: lua_Number,
    u: f64,
    s: ?*anyopaque,
    i: lua_Integer,
    l: c_long,
    b: [1024]u8,
};
pub const struct_luaL_Buffer = extern struct {
    b: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    size: usize = @import("std").mem.zeroes(usize),
    n: usize = @import("std").mem.zeroes(usize),
    L: ?*lua_State = @import("std").mem.zeroes(?*lua_State),
    init: union_unnamed_3 = @import("std").mem.zeroes(union_unnamed_3),
};
pub const luaL_Buffer = struct_luaL_Buffer;
pub const struct_luaL_Reg = extern struct {
    name: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    func: lua_CFunction = @import("std").mem.zeroes(lua_CFunction),
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
    f: ?*FILE = @import("std").mem.zeroes(?*FILE),
    closef: lua_CFunction = @import("std").mem.zeroes(lua_CFunction),
};
pub const luaL_Stream = struct_luaL_Stream;
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

const LUA_REGISTRYINDEX = -1001000;
pub export fn luaopen_base(L: ?*lua_State) callconv(.c) c_int {
    _ = lua_rawgeti(L, LUA_REGISTRYINDEX, @as(lua_Integer, 2));
    luaL_setfuncs(L, @as([*c]const luaL_Reg, @ptrCast(@alignCast(&base_funcs[0]))), 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "_G");
    _ = lua_pushstring(L, "Lua 5.4");
    lua_setfield(L, -2, "_VERSION");
    return 1;
}
pub extern fn luaopen_coroutine(L: ?*lua_State) c_int;
pub extern fn luaopen_table(L: ?*lua_State) c_int;
pub extern fn luaopen_io(L: ?*lua_State) c_int;
pub extern fn luaopen_os(L: ?*lua_State) c_int;
pub extern fn luaopen_string(L: ?*lua_State) c_int;
pub extern fn luaopen_utf8(L: ?*lua_State) c_int;
pub extern fn luaopen_math(L: ?*lua_State) c_int;
pub extern fn luaopen_debug(L: ?*lua_State) c_int;
pub extern fn luaopen_package(L: ?*lua_State) c_int;
pub extern fn luaL_openlibs(L: ?*lua_State) void;
comptime {
    // asm (".section .yoink\n\tb\t\"lua_notice\"\n\t.previous");
}
pub fn luaB_print(L: ?*lua_State) callconv(.c) c_int {
    const n: c_int = lua_gettop(L);
    var i: c_int = 1;
    while (i <= n) : (i += 1) {
        var l: usize = 0;
        const s: [*c]const u8 = luaL_tolstring(L, i, &l);
        if (i > 1) earlyPutc('\t');
        if (s != null) {
            var j: usize = 0;
            while (j < l) : (j += 1) earlyPutc(s[j]);
        }
        lua_settop(L, -1 - 1);
    }
    earlyPutc('\r');
    earlyPutc('\n');
    return 0;
}

/// Write a byte to the Lua console output.
/// Resolves to boot.zig's luaPutc which routes to ACM1 (USB VUART).
extern fn luaPutc(c: u8) void;

fn earlyPutc(c: u8) void {
    luaPutc(c);
}
pub fn luaB_warn(L: ?*lua_State) callconv(.c) c_int {
    const n: c_int = lua_gettop(L);
    var i: c_int = undefined;
    _ = luaL_checklstring(L, 1, null);
    {
        i = 2;
        while (i <= n) : (i += 1) {
            _ = luaL_checklstring(L, i, null);
        }
    }
    {
        i = 1;
        while (i < n) : (i += 1) {
            lua_warning(L, lua_tolstring(L, i, null), 1);
        }
    }
    lua_warning(L, lua_tolstring(L, n, null), 0);
    return 0;
}
pub fn b_str2int(arg_s: [*c]const u8, base: c_int, pn: [*c]lua_Integer) callconv(.c) [*c]const u8 {
    var s = arg_s;
    var n: lua_Unsigned = 0;
    var neg: c_int = 0;
    s += strspn(s, " \x0c\n\r\t\x0b");
    if (@as(c_int, @intCast(s.*)) == @as(c_int, '-')) {
        s += 1;
        neg = 1;
    } else if (@as(c_int, @intCast(s.*)) == @as(c_int, '+')) {
        s += 1;
    }
    if (!(isalnum(@as(c_int, @intCast(@as(u8, @bitCast(s.*))))) != 0)) return null;
    while (true) {
        const digit: c_int = if (isdigit(@as(c_int, @intCast(@as(u8, @bitCast(s.*))))) != 0) @as(c_int, @intCast(s.*)) - @as(c_int, '0') else (toupper(@as(c_int, @intCast(@as(u8, @bitCast(s.*))))) - @as(c_int, 'A')) + 10;
        if (digit >= base) return null;
        n = (n *% @as(lua_Unsigned, @bitCast(@as(c_longlong, base)))) +% @as(lua_Unsigned, @bitCast(@as(c_longlong, digit)));
        s += 1;
        if (!(isalnum(@as(c_int, @intCast(@as(u8, @bitCast(s.*))))) != 0)) break;
    }
    s += strspn(s, " \x0c\n\r\t\x0b");
    pn.* = @as(lua_Integer, @bitCast(if (neg != 0) 0 -% n else n));
    return s;
}
pub fn luaB_tonumber(L: ?*lua_State) callconv(.c) c_int {
    if (lua_type(L, 2) <= 0) {
        if (lua_type(L, 1) == 3) {
            lua_settop(L, 1);
            return 1;
        } else {
            var l: usize = undefined;
            const s: [*c]const u8 = lua_tolstring(L, 1, &l);
            if ((s != null) and (lua_stringtonumber(L, s) == (l +% @as(usize, 1)))) return 1;
            luaL_checkany(L, 1);
        }
    } else {
        var l: usize = undefined;
        var s: [*c]const u8 = undefined;
        var n: lua_Integer = 0;
        const base: lua_Integer = luaL_checkinteger(L, 2);
        luaL_checktype(L, 1, 4);
        s = lua_tolstring(L, 1, &l);
        _ = (((@as(lua_Integer, 2) <= base) and (base <= @as(lua_Integer, 36)))) or (luaL_argerror(L, 2, "base out of range") != 0);
        if (b_str2int(s, @as(c_int, @truncate(base)), &n) == (s + l)) {
            lua_pushinteger(L, n);
            return 1;
        }
    }
    lua_pushnil(L);
    return 1;
}
pub fn luaB_error(L: ?*lua_State) callconv(.c) c_int {
    const level: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(luaL_optinteger(L, 2, @as(lua_Integer, 1))))));
    lua_settop(L, 1);
    if ((lua_type(L, 1) == 4) and (level > 0)) {
        luaL_where(L, level);
        lua_pushvalue(L, 1);
        lua_concat(L, 2);
    }
    return lua_error(L);
}
pub fn luaB_getmetatable(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkany(L, 1);
    if (lua_getmetatable(L, 1) == 0) {
        lua_pushnil(L);
        return 1;
    }
    _ = luaL_getmetafield(L, 1, "__metatable");
    return 1;
}
pub fn luaB_setmetatable(L: ?*lua_State) callconv(.c) c_int {
    const t: c_int = lua_type(L, 2);
    luaL_checktype(L, 1, 5);
    _ = (((t == 0) or (t == 5))) or (luaL_typeerror(L, 2, "nil or table") != 0);
    if ((luaL_getmetafield(L, 1, "__metatable") != 0)) return luaL_error(L, "cannot change a protected metatable");
    lua_settop(L, 2);
    _ = lua_setmetatable(L, 1);
    return 1;
}
pub fn luaB_rawequal(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkany(L, 1);
    luaL_checkany(L, 2);
    lua_pushboolean(L, lua_rawequal(L, 1, 2));
    return 1;
}
pub fn luaB_rawlen(L: ?*lua_State) callconv(.c) c_int {
    const t: c_int = lua_type(L, 1);
    _ = (((t == 5) or (t == 4))) or (luaL_typeerror(L, 1, "table or string") != 0);
    lua_pushinteger(L, @as(lua_Integer, @bitCast(lua_rawlen(L, 1))));
    return 1;
}
pub fn luaB_rawget(L: ?*lua_State) callconv(.c) c_int {
    luaL_checktype(L, 1, 5);
    luaL_checkany(L, 2);
    lua_settop(L, 2);
    _ = lua_rawget(L, 1);
    return 1;
}
pub fn luaB_rawset(L: ?*lua_State) callconv(.c) c_int {
    luaL_checktype(L, 1, 5);
    luaL_checkany(L, 2);
    luaL_checkany(L, 3);
    lua_settop(L, 3);
    lua_rawset(L, 1);
    return 1;
}
pub fn pushmode(L: ?*lua_State, oldmode: c_int) callconv(.c) c_int {
    if (oldmode == -1) {
        lua_pushnil(L);
    } else {
        _ = lua_pushstring(L, if (oldmode == 11) "incremental" else "generational");
    }
    return 1;
}
pub fn luaB_collectgarbage(L: ?*lua_State) callconv(.c) c_int {
    const opts = struct {
        const static: [11][*c]const u8 = [11][*c]const u8{
            "stop",
            "restart",
            "collect",
            "count",
            "step",
            "setpause",
            "setstepmul",
            "isrunning",
            "generational",
            "incremental",
            null,
        };
    };
    const optsnum = struct {
        const static: [10]c_int = [10]c_int{
            0,
            1,
            2,
            3,
            5,
            6,
            7,
            9,
            10,
            11,
        };
    };
    const o: c_int = optsnum.static[@as(c_uint, @intCast(luaL_checkoption(L, 1, "collect", @as([*c]const [*c]const u8, @ptrCast(@alignCast(&opts.static[0]))))))];
    while (true) {
        switch (o) {
            3 => {
                {
                    const k: c_int = lua_gc(L, o);
                    const b: c_int = lua_gc(L, 4);
                    {
                        if (k == -1) break;
                    }
                    lua_pushnumber(L, @as(lua_Number, @floatFromInt(k)) + (@as(lua_Number, @floatFromInt(b)) / @as(lua_Number, 1024)));
                    return 1;
                }
            },
            5 => {
                {
                    const step: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(luaL_optinteger(L, 2, @as(lua_Integer, 0))))));
                    const res: c_int = lua_gc(L, o, step);
                    {
                        if (res == -1) break;
                    }
                    lua_pushboolean(L, res);
                    return 1;
                }
            },
            6, 7 => {
                {
                    const p: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(luaL_optinteger(L, 2, @as(lua_Integer, 0))))));
                    const previous: c_int = lua_gc(L, o, p);
                    {
                        if (previous == -1) break;
                    }
                    lua_pushinteger(L, @as(lua_Integer, @intCast(previous)));
                    return 1;
                }
            },
            9 => {
                {
                    const res: c_int = lua_gc(L, o);
                    {
                        if (res == -1) break;
                    }
                    lua_pushboolean(L, res);
                    return 1;
                }
            },
            10 => {
                {
                    const minormul: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(luaL_optinteger(L, 2, @as(lua_Integer, 0))))));
                    const majormul: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(luaL_optinteger(L, 3, @as(lua_Integer, 0))))));
                    return pushmode(L, lua_gc(L, o, minormul, majormul));
                }
            },
            11 => {
                {
                    const pause_1: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(luaL_optinteger(L, 2, @as(lua_Integer, 0))))));
                    const stepmul: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(luaL_optinteger(L, 3, @as(lua_Integer, 0))))));
                    const stepsize: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(luaL_optinteger(L, 4, @as(lua_Integer, 0))))));
                    return pushmode(L, lua_gc(L, o, pause_1, stepmul, stepsize));
                }
            },
            else => {
                {
                    const res: c_int = lua_gc(L, o);
                    {
                        if (res == -1) break;
                    }
                    lua_pushinteger(L, @as(lua_Integer, @intCast(res)));
                    return 1;
                }
            },
        }
        break;
    }
    lua_pushnil(L);
    return 1;
}
pub fn luaB_type(L: ?*lua_State) callconv(.c) c_int {
    const t: c_int = lua_type(L, 1);
    _ = (t != -1) or (luaL_argerror(L, 1, "value expected") != 0);
    _ = lua_pushstring(L, lua_typename(L, t));
    return 1;
}
pub fn luaB_next(L: ?*lua_State) callconv(.c) c_int {
    luaL_checktype(L, 1, 5);
    lua_settop(L, 2);
    if (lua_next(L, 1) != 0) return 2 else {
        lua_pushnil(L);
        return 1;
    }
    return 0;
}
pub fn pairscont(_: ?*lua_State, _: c_int, _: lua_KContext) callconv(.c) c_int {
    return 3;
}
pub fn luaB_pairs(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkany(L, 1);
    if (luaL_getmetafield(L, 1, "__pairs") == 0) {
        lua_pushcclosure(L, &luaB_next, 0);
        lua_pushvalue(L, 1);
        lua_pushnil(L);
    } else {
        lua_pushvalue(L, 1);
        lua_callk(L, 1, 3, 0, &pairscont);
    }
    return 3;
}
pub fn ipairsaux(L: ?*lua_State) callconv(.c) c_int {
    var i: lua_Integer = luaL_checkinteger(L, 2);
    i = @as(lua_Integer, @bitCast(@as(lua_Unsigned, @bitCast(i)) +% @as(lua_Unsigned, 1)));
    lua_pushinteger(L, i);
    return if (lua_geti(L, 1, i) == 0) 1 else 2;
}
pub fn luaB_ipairs(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkany(L, 1);
    lua_pushcclosure(L, &ipairsaux, 0);
    lua_pushvalue(L, 1);
    lua_pushinteger(L, @as(lua_Integer, 0));
    return 3;
}
pub fn load_aux(L: ?*lua_State, status: c_int, envidx: c_int) callconv(.c) c_int {
    if (status == 0) {
        if (envidx != 0) {
            lua_pushvalue(L, envidx);
            if (!(lua_setupvalue(L, -2, 1) != null)) {
                lua_settop(L, -1 - 1);
            }
        }
        return 1;
    } else {
        lua_pushnil(L);
        lua_rotate(L, -2, 1);
        return 2;
    }
    return 0;
}
pub fn luaB_loadfile(L: ?*lua_State) callconv(.c) c_int {
    const fname: [*c]const u8 = luaL_optlstring(L, 1, null, null);
    const mode: [*c]const u8 = luaL_optlstring(L, 2, null, null);
    const env: c_int = if (!(lua_type(L, 3) == -1)) 3 else 0;
    const status: c_int = luaL_loadfilex(L, fname, mode);
    return load_aux(L, status, env);
}
pub fn generic_reader(L: ?*lua_State, _: ?*anyopaque, size: [*c]usize) callconv(.c) [*c]const u8 {
    luaL_checkstack(L, 2, "too many nested functions");
    lua_pushvalue(L, 1);
    lua_callk(L, 0, 1, 0, null);
    if (lua_type(L, -1) == 0) {
        lua_settop(L, -1 - 1);
        size.* = 0;
        return null;
    } else if ((lua_isstring(L, -1) == 0)) {
        _ = luaL_error(L, "reader function must return a string");
    }
    _ = blk: {
        lua_copy(L, -1, 5);
        break :blk lua_settop(L, -1 - 1);
    };
    return lua_tolstring(L, 5, size);
}
pub fn luaB_load(L: ?*lua_State) callconv(.c) c_int {
    var status: c_int = undefined;
    var l: usize = undefined;
    const s: [*c]const u8 = lua_tolstring(L, 1, &l);
    const mode: [*c]const u8 = luaL_optlstring(L, 3, "bt", null);
    const env: c_int = if (!(lua_type(L, 4) == -1)) 4 else 0;
    if (s != null) {
        const chunkname: [*c]const u8 = luaL_optlstring(L, 2, s, null);
        status = luaL_loadbufferx(L, s, l, chunkname, mode);
    } else {
        const chunkname: [*c]const u8 = luaL_optlstring(L, 2, "=(load)", null);
        luaL_checktype(L, 1, 6);
        lua_settop(L, 5);
        status = lua_load(L, &generic_reader, null, chunkname, mode);
    }
    return load_aux(L, status, env);
}
pub fn dofilecont(L: ?*lua_State, _: c_int, _: lua_KContext) callconv(.c) c_int {
    return lua_gettop(L) - 1;
}
pub fn luaB_dofile(L: ?*lua_State) callconv(.c) c_int {
    const fname: [*c]const u8 = luaL_optlstring(L, 1, null, null);
    lua_settop(L, 1);
    if ((luaL_loadfilex(L, fname, null) != 0)) return lua_error(L);
    lua_callk(L, 0, -1, 0, &dofilecont);
    return dofilecont(L, 0, 0);
}
pub fn luaB_assert(L: ?*lua_State) callconv(.c) c_int {
    if ((lua_toboolean(L, 1) != 0)) return lua_gettop(L) else {
        luaL_checkany(L, 1);
        _ = blk: {
            lua_rotate(L, 1, -1);
            break :blk lua_settop(L, -1 - 1);
        };
        _ = lua_pushstring(L, "assertion failed!");
        lua_settop(L, 1);
        return luaB_error(L);
    }
    return 0;
}
pub fn luaB_select(L: ?*lua_State) callconv(.c) c_int {
    const n: c_int = lua_gettop(L);
    if ((lua_type(L, 1) == 4) and (@as(c_int, @bitCast(@as(c_uint, lua_tolstring(L, 1, null).*))) == @as(c_int, '#'))) {
        lua_pushinteger(L, @as(lua_Integer, @bitCast(@as(c_longlong, n - 1))));
        return 1;
    } else {
        var i: lua_Integer = luaL_checkinteger(L, 1);
        if (i < @as(lua_Integer, 0)) {
            i = @as(lua_Integer, @intCast(n)) + i;
        } else if (i > @as(lua_Integer, @intCast(n))) {
            i = @as(lua_Integer, @intCast(n));
        }
        _ = ((@as(lua_Integer, 1) <= i)) or (luaL_argerror(L, 1, "index out of range") != 0);
        return n - @as(c_int, @truncate(i));
    }
    return 0;
}
pub fn finishpcall(L: ?*lua_State, status: c_int, extra: lua_KContext) callconv(.c) c_int {
    if (((status != 0) and (status != 1))) {
        lua_pushboolean(L, 0);
        lua_pushvalue(L, -2);
        return 2;
    } else return lua_gettop(L) - @as(c_int, @truncate(extra));
    return 0;
}
pub fn luaB_pcall(L: ?*lua_State) callconv(.c) c_int {
    var status: c_int = undefined;
    luaL_checkany(L, 1);
    lua_pushboolean(L, 1);
    lua_rotate(L, 1, 1);
    status = lua_pcallk(L, lua_gettop(L) - 2, -1, 0, 0, &finishpcall);
    return finishpcall(L, status, 0);
}
pub fn luaB_xpcall(L: ?*lua_State) callconv(.c) c_int {
    var status: c_int = undefined;
    const n: c_int = lua_gettop(L);
    luaL_checktype(L, 2, 6);
    lua_pushboolean(L, 1);
    lua_pushvalue(L, 1);
    lua_rotate(L, 3, 2);
    status = lua_pcallk(L, n - 2, -1, 2, 2, &finishpcall);
    return finishpcall(L, status, 2);
}
pub fn luaB_tostring(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkany(L, 1);
    _ = luaL_tolstring(L, 1, null);
    return 1;
}
pub const base_funcs: [26]luaL_Reg = [26]luaL_Reg{
    luaL_Reg{
        .name = "assert",
        .func = &luaB_assert,
    },
    luaL_Reg{
        .name = "collectgarbage",
        .func = &luaB_collectgarbage,
    },
    luaL_Reg{
        .name = "dofile",
        .func = &luaB_dofile,
    },
    luaL_Reg{
        .name = "error",
        .func = &luaB_error,
    },
    luaL_Reg{
        .name = "getmetatable",
        .func = &luaB_getmetatable,
    },
    luaL_Reg{
        .name = "ipairs",
        .func = &luaB_ipairs,
    },
    luaL_Reg{
        .name = "loadfile",
        .func = &luaB_loadfile,
    },
    luaL_Reg{
        .name = "load",
        .func = &luaB_load,
    },
    luaL_Reg{
        .name = "next",
        .func = &luaB_next,
    },
    luaL_Reg{
        .name = "pairs",
        .func = &luaB_pairs,
    },
    luaL_Reg{
        .name = "pcall",
        .func = &luaB_pcall,
    },
    luaL_Reg{
        .name = "print",
        .func = &luaB_print,
    },
    luaL_Reg{
        .name = "warn",
        .func = &luaB_warn,
    },
    luaL_Reg{
        .name = "rawequal",
        .func = &luaB_rawequal,
    },
    luaL_Reg{
        .name = "rawlen",
        .func = &luaB_rawlen,
    },
    luaL_Reg{
        .name = "rawget",
        .func = &luaB_rawget,
    },
    luaL_Reg{
        .name = "rawset",
        .func = &luaB_rawset,
    },
    luaL_Reg{
        .name = "select",
        .func = &luaB_select,
    },
    luaL_Reg{
        .name = "setmetatable",
        .func = &luaB_setmetatable,
    },
    luaL_Reg{
        .name = "tonumber",
        .func = &luaB_tonumber,
    },
    luaL_Reg{
        .name = "tostring",
        .func = &luaB_tostring,
    },
    luaL_Reg{
        .name = "type",
        .func = &luaB_type,
    },
    luaL_Reg{
        .name = "xpcall",
        .func = &luaB_xpcall,
    },
    luaL_Reg{
        .name = "_G",
        .func = null,
    },
    luaL_Reg{
        .name = "_VERSION",
        .func = null,
    },
    luaL_Reg{
        .name = null,
        .func = null,
    },
};
