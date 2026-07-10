const std = @import("std");
const c_builtins = std.zig.c_builtins;

pub const __builtin_bswap16 = c_builtins.__builtin_bswap16;
pub const __builtin_bswap32 = c_builtins.__builtin_bswap32;
pub const __builtin_bswap64 = c_builtins.__builtin_bswap64;
pub const __builtin_signbit = c_builtins.__builtin_signbit;
pub const __builtin_signbitf = c_builtins.__builtin_signbitf;
pub const __builtin_popcount = c_builtins.__builtin_popcount;
pub const __builtin_ctz = c_builtins.__builtin_ctz;
pub const __builtin_clz = c_builtins.__builtin_clz;
pub const __builtin_sqrt = c_builtins.__builtin_sqrt;
pub const __builtin_sqrtf = c_builtins.__builtin_sqrtf;
pub const __builtin_sin = c_builtins.__builtin_sin;
pub const __builtin_sinf = c_builtins.__builtin_sinf;
pub const __builtin_cos = c_builtins.__builtin_cos;
pub const __builtin_cosf = c_builtins.__builtin_cosf;
pub const __builtin_exp = c_builtins.__builtin_exp;
pub const __builtin_expf = c_builtins.__builtin_expf;
pub const __builtin_exp2 = c_builtins.__builtin_exp2;
pub const __builtin_exp2f = c_builtins.__builtin_exp2f;
pub const __builtin_log = c_builtins.__builtin_log;
pub const __builtin_logf = c_builtins.__builtin_logf;
pub const __builtin_log2 = c_builtins.__builtin_log2;
pub const __builtin_log2f = c_builtins.__builtin_log2f;
pub const __builtin_log10 = c_builtins.__builtin_log10;
pub const __builtin_log10f = c_builtins.__builtin_log10f;
pub const __builtin_abs = c_builtins.__builtin_abs;
pub const __builtin_labs = c_builtins.__builtin_labs;
pub const __builtin_llabs = c_builtins.__builtin_llabs;
pub const __builtin_fabs = c_builtins.__builtin_fabs;
pub const __builtin_fabsf = c_builtins.__builtin_fabsf;
pub const __builtin_floor = c_builtins.__builtin_floor;
pub const __builtin_floorf = c_builtins.__builtin_floorf;
pub const __builtin_ceil = c_builtins.__builtin_ceil;
pub const __builtin_ceilf = c_builtins.__builtin_ceilf;
pub const __builtin_trunc = c_builtins.__builtin_trunc;
pub const __builtin_truncf = c_builtins.__builtin_truncf;
pub const __builtin_round = c_builtins.__builtin_round;
pub const __builtin_roundf = c_builtins.__builtin_roundf;
pub const __builtin_strlen = c_builtins.__builtin_strlen;
pub const __builtin_strcmp = c_builtins.__builtin_strcmp;
pub const __builtin_object_size = c_builtins.__builtin_object_size;
pub const __builtin___memset_chk = c_builtins.__builtin___memset_chk;
pub const __builtin_memset = c_builtins.__builtin_memset;
pub const __builtin___memcpy_chk = c_builtins.__builtin___memcpy_chk;
pub const __builtin_memcpy = c_builtins.__builtin_memcpy;
pub const __builtin_expect = c_builtins.__builtin_expect;
pub const __builtin_nanf = c_builtins.__builtin_nanf;
pub const __builtin_huge_valf = c_builtins.__builtin_huge_valf;
pub const __builtin_inff = c_builtins.__builtin_inff;
pub const __builtin_isnan = c_builtins.__builtin_isnan;
pub const __builtin_isinf = c_builtins.__builtin_isinf;
pub const __builtin_isinf_sign = c_builtins.__builtin_isinf_sign;
pub const __has_builtin = c_builtins.__has_builtin;
pub const __builtin_assume = c_builtins.__builtin_assume;
pub const __builtin_unreachable = c_builtins.__builtin_unreachable;
pub const __builtin_constant_p = c_builtins.__builtin_constant_p;
pub const __builtin_mul_overflow = c_builtins.__builtin_mul_overflow;
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
    ax: isize = std.mem.zeroes(isize),
    dx: isize = std.mem.zeroes(isize),
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
pub export fn LuaHasMultipleItems(L: ?*lua_State) bool {
    lua_pushnil(L);
    var i: c_int = 0;
    while (lua_next(L, -2) != 0) : (i += 1) {
        if (i > 0) {
            lua_settop(L, -3);
            return true;
        }
        lua_settop(L, -2);
    }
    return false;
}
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
pub extern fn SerializeObjectStart(buf: [*c][*c]u8, z: [*c]struct_Serializer, depth: c_int, multi: bool) c_int;
pub extern fn SerializeObjectEnd(buf: [*c][*c]u8, z: [*c]struct_Serializer, depth: c_int, multi: bool) c_int;
pub extern fn SerializeObjectIndent(buf: [*c][*c]u8, z: [*c]struct_Serializer, depth: c_int) c_int;
// Dead compiler/system macro constants removed (translate-c artifacts from cosmopolitan libc).
// Original block: __llvm__, __clang_*, __GNUC_*, __ATOMIC_*, __SIZEOF_*, __FLT_*, __DBL_*,
// __LDBL_*, __INT*_*, __UINT*_*, POSIX constants, cosmopolitan internal macros, etc.
// (dead compiler/system macro constants block removed - ~1100 lines of translate-c artifacts)
// Removed: __ATOMIC_*, __MEMORY_SCOPE_*, __OPENCL_*, __FPCLASS_*, __PRAGMA_*, __VERSION__,
// __ORDER_*, __CHAR_BIT__, __SIZEOF_*, __FLT_*, __DBL_*, __LDBL_*, __INT*_*, __UINT*_*,
// _POSIX_*, SEEK_*, NSIG, CLOCKS_PER_SEC, cosmopolitan internal macros, etc.
// These are compiler intrinsics/system constants that should use @import("std") equivalents.
// (dead block continues - see comment above)
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
pub inline fn appendd(b: anytype, s: anytype, n: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &b;
    _ = &s;
    _ = &n;
    return @as(c_int, 0);
}
pub inline fn appends(b: anytype, s: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &b;
    _ = &s;
    return @as(c_int, 0);
}
pub inline fn FormatInt64(b: anytype, v: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &b;
    _ = &v;
    return @as(c_int, 0);
}
pub inline fn ShowCrashReports() anyopaque {
    return std.zig.c_translation.cast(anyopaque, @as(c_int, 0));
}
pub inline fn makedirs(p: anytype, m: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &p;
    _ = &m;
    return @as(c_int, 0);
}
pub inline fn memccpy(d: anytype, s: anytype, c: anytype, n: anytype) @TypeOf(memcpy(d, s, n)) {
    _ = &d;
    _ = &s;
    _ = &c;
    _ = &n;
    return memcpy(d, s, n);
}
pub const COSMOPOLITAN_LIBC_LOG_ROP_H_ = "";
pub const COSMOPOLITAN_LIBC_BITS_LIKELY_H_ = "";
pub inline fn LIKELY(x: anytype) @TypeOf(__builtin_expect(!!(x != 0), @as(c_int, 1))) {
    _ = &x;
    return __builtin_expect(!!(x != 0), @as(c_int, 1));
}
pub inline fn UNLIKELY(x: anytype) @TypeOf(__builtin_expect(!!(x != 0), @as(c_int, 0))) {
    _ = &x;
    return __builtin_expect(!!(x != 0), @as(c_int, 0));
}
pub inline fn VERY_LIKELY(x: anytype) @TypeOf(LIKELY(x)) {
    _ = &x;
    return LIKELY(x);
}
pub inline fn VERY_UNLIKELY(x: anytype) @TypeOf(UNLIKELY(x)) {
    _ = &x;
    return UNLIKELY(x);
}
pub const RETURN_ON_ERROR = @compileError("unable to translate macro: undefined identifier `OnError`");
// /src/cosmopolitan/libc/log/rop.internal.h:5:9
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
pub const l_floor = @compileError("unable to translate macro: undefined identifier `floor`");
// /src/cosmopolitan/third_party/lua/luaconf.h:348:9
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
pub inline fn luai_likely(x: anytype) @TypeOf(__builtin_expect(x != @as(c_int, 0), @as(c_int, 1))) {
    _ = &x;
    return __builtin_expect(x != @as(c_int, 0), @as(c_int, 1));
}
pub inline fn luai_unlikely(x: anytype) @TypeOf(__builtin_expect(x != @as(c_int, 0), @as(c_int, 0))) {
    _ = &x;
    return __builtin_expect(x != @as(c_int, 0), @as(c_int, 0));
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
pub inline fn luaL_argcheck(L: anytype, cond: anytype, arg: anytype, extramsg: anytype) anyopaque {
    _ = &L;
    _ = &cond;
    _ = &arg;
    _ = &extramsg;
    return std.zig.c_translation.cast(anyopaque, (luai_likely(cond) != 0) or (luaL_argerror(L, arg, extramsg) != 0));
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
