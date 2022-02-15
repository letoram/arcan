pub const wchar_t = c_int;
pub const _Float32 = f32;
pub const _Float64 = f64;
pub const _Float32x = f64;
pub const _Float64x = c_longdouble;
const struct_unnamed_1 = extern struct {
    quot: c_int,
    rem: c_int,
};
pub const div_t = struct_unnamed_1;
const struct_unnamed_2 = extern struct {
    quot: c_long,
    rem: c_long,
};
pub const ldiv_t = struct_unnamed_2;
const struct_unnamed_3 = extern struct {
    quot: c_longlong,
    rem: c_longlong,
};
pub const lldiv_t = struct_unnamed_3;
pub extern fn __ctype_get_mb_cur_max() usize;
pub fn atof(arg___nptr: [*c]const u8) callconv(.C) f64 {
    var __nptr = arg___nptr;
    return strtod(__nptr, @ptrCast([*c][*c]u8, @alignCast(@alignOf([*c]u8), (@intToPtr(?*c_void, @as(c_int, 0))))));
}
pub fn atoi(arg___nptr: [*c]const u8) callconv(.C) c_int {
    var __nptr = arg___nptr;
    return @bitCast(c_int, @truncate(c_int, strtol(__nptr, @ptrCast([*c][*c]u8, @alignCast(@alignOf([*c]u8), (@intToPtr(?*c_void, @as(c_int, 0))))), @as(c_int, 10))));
}
pub fn atol(arg___nptr: [*c]const u8) callconv(.C) c_long {
    var __nptr = arg___nptr;
    return strtol(__nptr, @ptrCast([*c][*c]u8, @alignCast(@alignOf([*c]u8), (@intToPtr(?*c_void, @as(c_int, 0))))), @as(c_int, 10));
}
pub fn atoll(arg___nptr: [*c]const u8) callconv(.C) c_longlong {
    var __nptr = arg___nptr;
    return strtoll(__nptr, @ptrCast([*c][*c]u8, @alignCast(@alignOf([*c]u8), (@intToPtr(?*c_void, @as(c_int, 0))))), @as(c_int, 10));
}
pub extern fn strtod(__nptr: [*c]const u8, __endptr: [*c][*c]u8) f64;
pub extern fn strtof(__nptr: [*c]const u8, __endptr: [*c][*c]u8) f32;
pub extern fn strtold(__nptr: [*c]const u8, __endptr: [*c][*c]u8) c_longdouble;
pub extern fn strtol(__nptr: [*c]const u8, __endptr: [*c][*c]u8, __base: c_int) c_long;
pub extern fn strtoul(__nptr: [*c]const u8, __endptr: [*c][*c]u8, __base: c_int) c_ulong;
pub extern fn strtoq(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_longlong;
pub extern fn strtouq(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulonglong;
pub extern fn strtoll(__nptr: [*c]const u8, __endptr: [*c][*c]u8, __base: c_int) c_longlong;
pub extern fn strtoull(__nptr: [*c]const u8, __endptr: [*c][*c]u8, __base: c_int) c_ulonglong;
pub extern fn l64a(__n: c_long) [*c]u8;
pub extern fn a64l(__s: [*c]const u8) c_long;
pub const __u_char = u8;
pub const __u_short = c_ushort;
pub const __u_int = c_uint;
pub const __u_long = c_ulong;
pub const __int8_t = i8;
pub const __uint8_t = u8;
pub const __int16_t = c_short;
pub const __uint16_t = c_ushort;
pub const __int32_t = c_int;
pub const __uint32_t = c_uint;
pub const __int64_t = c_long;
pub const __uint64_t = c_ulong;
pub const __int_least8_t = __int8_t;
pub const __uint_least8_t = __uint8_t;
pub const __int_least16_t = __int16_t;
pub const __uint_least16_t = __uint16_t;
pub const __int_least32_t = __int32_t;
pub const __uint_least32_t = __uint32_t;
pub const __int_least64_t = __int64_t;
pub const __uint_least64_t = __uint64_t;
pub const __quad_t = c_long;
pub const __u_quad_t = c_ulong;
pub const __intmax_t = c_long;
pub const __uintmax_t = c_ulong;
pub const __dev_t = c_ulong;
pub const __uid_t = c_uint;
pub const __gid_t = c_uint;
pub const __ino_t = c_ulong;
pub const __ino64_t = c_ulong;
pub const __mode_t = c_uint;
pub const __nlink_t = c_ulong;
pub const __off_t = c_long;
pub const __off64_t = c_long;
pub const __pid_t = c_int;
const struct_unnamed_4 = extern struct {
    __val: [2]c_int,
};
pub const __fsid_t = struct_unnamed_4;
pub const __clock_t = c_long;
pub const __rlim_t = c_ulong;
pub const __rlim64_t = c_ulong;
pub const __id_t = c_uint;
pub const __time_t = c_long;
pub const __useconds_t = c_uint;
pub const __suseconds_t = c_long;
pub const __suseconds64_t = c_long;
pub const __daddr_t = c_int;
pub const __key_t = c_int;
pub const __clockid_t = c_int;
pub const __timer_t = ?*c_void;
pub const __blksize_t = c_long;
pub const __blkcnt_t = c_long;
pub const __blkcnt64_t = c_long;
pub const __fsblkcnt_t = c_ulong;
pub const __fsblkcnt64_t = c_ulong;
pub const __fsfilcnt_t = c_ulong;
pub const __fsfilcnt64_t = c_ulong;
pub const __fsword_t = c_long;
pub const __ssize_t = c_long;
pub const __syscall_slong_t = c_long;
pub const __syscall_ulong_t = c_ulong;
pub const __loff_t = __off64_t;
pub const __caddr_t = [*c]u8;
pub const __intptr_t = c_long;
pub const __socklen_t = c_uint;
pub const __sig_atomic_t = c_int;
pub const u_char = __u_char;
pub const u_short = __u_short;
pub const u_int = __u_int;
pub const u_long = __u_long;
pub const quad_t = __quad_t;
pub const u_quad_t = __u_quad_t;
pub const fsid_t = __fsid_t;
pub const loff_t = __loff_t;
pub const ino_t = __ino_t;
pub const dev_t = __dev_t;
pub const gid_t = __gid_t;
pub const mode_t = __mode_t;
pub const nlink_t = __nlink_t;
pub const uid_t = __uid_t;
pub const off_t = __off_t;
pub const pid_t = __pid_t;
pub const id_t = __id_t;
pub const daddr_t = __daddr_t;
pub const caddr_t = __caddr_t;
pub const key_t = __key_t;
pub const clock_t = __clock_t;
pub const clockid_t = __clockid_t;
pub const time_t = __time_t;
pub const timer_t = __timer_t;
pub const ulong = c_ulong;
pub const ushort = c_ushort;
pub const uint = c_uint;
pub const u_int8_t = __uint8_t;
pub const u_int16_t = __uint16_t;
pub const u_int32_t = __uint32_t;
pub const u_int64_t = __uint64_t;
pub const register_t = c_long;
pub fn __bswap_16(arg___bsx: __uint16_t) callconv(.C) __uint16_t {
    var __bsx = arg___bsx;
    return (@bitCast(__uint16_t, @truncate(c_short, (((@bitCast(c_int, @as(c_uint, (__bsx))) >> @intCast(@import("std").math.Log2Int(c_int), 8)) & @as(c_int, 255)) | ((@bitCast(c_int, @as(c_uint, (__bsx))) & @as(c_int, 255)) << @intCast(@import("std").math.Log2Int(c_int), 8))))));
}
pub fn __bswap_32(arg___bsx: __uint32_t) callconv(.C) __uint32_t {
    var __bsx = arg___bsx;
    return ((((((__bsx) & @as(c_uint, 4278190080)) >> @intCast(@import("std").math.Log2Int(c_uint), 24)) | (((__bsx) & @as(c_uint, 16711680)) >> @intCast(@import("std").math.Log2Int(c_uint), 8))) | (((__bsx) & @as(c_uint, 65280)) << @intCast(@import("std").math.Log2Int(c_uint), 8))) | (((__bsx) & @as(c_uint, 255)) << @intCast(@import("std").math.Log2Int(c_uint), 24)));
}
pub fn __bswap_64(arg___bsx: __uint64_t) callconv(.C) __uint64_t {
    var __bsx = arg___bsx;
    return @bitCast(__uint64_t, @truncate(c_ulong, (((((((((@bitCast(c_ulonglong, @as(c_ulonglong, (__bsx))) & @as(c_ulonglong, 18374686479671623680)) >> @intCast(@import("std").math.Log2Int(c_ulonglong), 56)) | ((@bitCast(c_ulonglong, @as(c_ulonglong, (__bsx))) & @as(c_ulonglong, 71776119061217280)) >> @intCast(@import("std").math.Log2Int(c_ulonglong), 40))) | ((@bitCast(c_ulonglong, @as(c_ulonglong, (__bsx))) & @as(c_ulonglong, 280375465082880)) >> @intCast(@import("std").math.Log2Int(c_ulonglong), 24))) | ((@bitCast(c_ulonglong, @as(c_ulonglong, (__bsx))) & @as(c_ulonglong, 1095216660480)) >> @intCast(@import("std").math.Log2Int(c_ulonglong), 8))) | ((@bitCast(c_ulonglong, @as(c_ulonglong, (__bsx))) & @as(c_ulonglong, 4278190080)) << @intCast(@import("std").math.Log2Int(c_ulonglong), 8))) | ((@bitCast(c_ulonglong, @as(c_ulonglong, (__bsx))) & @as(c_ulonglong, 16711680)) << @intCast(@import("std").math.Log2Int(c_ulonglong), 24))) | ((@bitCast(c_ulonglong, @as(c_ulonglong, (__bsx))) & @as(c_ulonglong, 65280)) << @intCast(@import("std").math.Log2Int(c_ulonglong), 40))) | ((@bitCast(c_ulonglong, @as(c_ulonglong, (__bsx))) & @as(c_ulonglong, 255)) << @intCast(@import("std").math.Log2Int(c_ulonglong), 56)))));
}
pub fn __uint16_identity(arg___x: __uint16_t) callconv(.C) __uint16_t {
    var __x = arg___x;
    return __x;
}
pub fn __uint32_identity(arg___x: __uint32_t) callconv(.C) __uint32_t {
    var __x = arg___x;
    return __x;
}
pub fn __uint64_identity(arg___x: __uint64_t) callconv(.C) __uint64_t {
    var __x = arg___x;
    return __x;
}
const struct_unnamed_5 = extern struct {
    __val: [16]c_ulong,
};
pub const __sigset_t = struct_unnamed_5;
pub const sigset_t = __sigset_t;
pub const struct_timeval = extern struct {
    tv_sec: __time_t,
    tv_usec: __suseconds_t,
};
pub const struct_timespec = extern struct {
    tv_sec: __time_t,
    tv_nsec: __syscall_slong_t,
};
pub const suseconds_t = __suseconds_t;
pub const __fd_mask = c_long;
const struct_unnamed_6 = extern struct {
    __fds_bits: [16]__fd_mask,
};
pub const fd_set = struct_unnamed_6;
pub const fd_mask = __fd_mask;
pub extern fn select(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]struct_timeval) c_int;
pub extern fn pselect(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]const struct_timespec, noalias __sigmask: [*c]const __sigset_t) c_int;
pub const blksize_t = __blksize_t;
pub const blkcnt_t = __blkcnt_t;
pub const fsblkcnt_t = __fsblkcnt_t;
pub const fsfilcnt_t = __fsfilcnt_t;
pub const struct___pthread_internal_list = extern struct {
    __prev: [*c]struct___pthread_internal_list,
    __next: [*c]struct___pthread_internal_list,
};
pub const __pthread_list_t = struct___pthread_internal_list;
pub const struct___pthread_internal_slist = extern struct {
    __next: [*c]struct___pthread_internal_slist,
};
pub const __pthread_slist_t = struct___pthread_internal_slist;
pub const struct___pthread_mutex_s = extern struct {
    __lock: c_int,
    __count: c_uint,
    __owner: c_int,
    __nusers: c_uint,
    __kind: c_int,
    __spins: c_short,
    __elision: c_short,
    __list: __pthread_list_t,
};
pub const struct___pthread_rwlock_arch_t = extern struct {
    __readers: c_uint,
    __writers: c_uint,
    __wrphase_futex: c_uint,
    __writers_futex: c_uint,
    __pad3: c_uint,
    __pad4: c_uint,
    __cur_writer: c_int,
    __shared: c_int,
    __rwelision: i8,
    __pad1: [7]u8,
    __pad2: c_ulong,
    __flags: c_uint,
};
const struct_unnamed_8 = extern struct {
    __low: c_uint,
    __high: c_uint,
};
const union_unnamed_7 = extern union {
    __wseq: c_ulonglong,
    __wseq32: struct_unnamed_8,
};
const struct_unnamed_10 = extern struct {
    __low: c_uint,
    __high: c_uint,
};
const union_unnamed_9 = extern union {
    __g1_start: c_ulonglong,
    __g1_start32: struct_unnamed_10,
};
pub const struct___pthread_cond_s = extern struct {
    unnamed_0: union_unnamed_7,
    unnamed_1: union_unnamed_9,
    __g_refs: [2]c_uint,
    __g_size: [2]c_uint,
    __g1_orig_size: c_uint,
    __wrefs: c_uint,
    __g_signals: [2]c_uint,
};
pub const __tss_t = c_uint;
pub const __thrd_t = c_ulong;
const struct_unnamed_11 = extern struct {
    __data: c_int,
};
pub const __once_flag = struct_unnamed_11;
pub const pthread_t = c_ulong;
const union_unnamed_12 = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_mutexattr_t = union_unnamed_12;
const union_unnamed_13 = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_condattr_t = union_unnamed_13;
pub const pthread_key_t = c_uint;
pub const pthread_once_t = c_int;
pub const union_pthread_attr_t = extern union {
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_attr_t = union_pthread_attr_t;
const union_unnamed_14 = extern union {
    __data: struct___pthread_mutex_s,
    __size: [40]u8,
    __align: c_long,
};
pub const pthread_mutex_t = union_unnamed_14;
const union_unnamed_15 = extern union {
    __data: struct___pthread_cond_s,
    __size: [48]u8,
    __align: c_longlong,
};
pub const pthread_cond_t = union_unnamed_15;
const union_unnamed_16 = extern union {
    __data: struct___pthread_rwlock_arch_t,
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_rwlock_t = union_unnamed_16;
const union_unnamed_17 = extern union {
    __size: [8]u8,
    __align: c_long,
};
pub const pthread_rwlockattr_t = union_unnamed_17;
pub const pthread_spinlock_t = c_int;
const union_unnamed_18 = extern union {
    __size: [32]u8,
    __align: c_long,
};
pub const pthread_barrier_t = union_unnamed_18;
const union_unnamed_19 = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_barrierattr_t = union_unnamed_19;
pub extern fn random() c_long;
pub extern fn srandom(__seed: c_uint) void;
pub extern fn initstate(__seed: c_uint, __statebuf: [*c]u8, __statelen: usize) [*c]u8;
pub extern fn setstate(__statebuf: [*c]u8) [*c]u8;
pub const struct_random_data = extern struct {
    fptr: [*c]i32,
    rptr: [*c]i32,
    state: [*c]i32,
    rand_type: c_int,
    rand_deg: c_int,
    rand_sep: c_int,
    end_ptr: [*c]i32,
};
pub extern fn random_r(noalias __buf: [*c]struct_random_data, noalias __result: [*c]i32) c_int;
pub extern fn srandom_r(__seed: c_uint, __buf: [*c]struct_random_data) c_int;
pub extern fn initstate_r(__seed: c_uint, noalias __statebuf: [*c]u8, __statelen: usize, noalias __buf: [*c]struct_random_data) c_int;
pub extern fn setstate_r(noalias __statebuf: [*c]u8, noalias __buf: [*c]struct_random_data) c_int;
pub extern fn rand() c_int;
pub extern fn srand(__seed: c_uint) void;
pub extern fn rand_r(__seed: [*c]c_uint) c_int;
pub extern fn drand48() f64;
pub extern fn erand48(__xsubi: [*c]c_ushort) f64;
pub extern fn lrand48() c_long;
pub extern fn nrand48(__xsubi: [*c]c_ushort) c_long;
pub extern fn mrand48() c_long;
pub extern fn jrand48(__xsubi: [*c]c_ushort) c_long;
pub extern fn srand48(__seedval: c_long) void;
pub extern fn seed48(__seed16v: [*c]c_ushort) [*c]c_ushort;
pub extern fn lcong48(__param: [*c]c_ushort) void;
pub const struct_drand48_data = extern struct {
    __x: [3]c_ushort,
    __old_x: [3]c_ushort,
    __c: c_ushort,
    __init: c_ushort,
    __a: c_ulonglong,
};
pub extern fn drand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]f64) c_int;
pub extern fn erand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]f64) c_int;
pub extern fn lrand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn nrand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn mrand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn jrand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn srand48_r(__seedval: c_long, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn seed48_r(__seed16v: [*c]c_ushort, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn lcong48_r(__param: [*c]c_ushort, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn malloc(__size: c_ulong) ?*c_void;
pub extern fn calloc(__nmemb: c_ulong, __size: c_ulong) ?*c_void;
pub extern fn realloc(__ptr: ?*c_void, __size: c_ulong) ?*c_void;
pub extern fn reallocarray(__ptr: ?*c_void, __nmemb: usize, __size: usize) ?*c_void;
pub extern fn free(__ptr: ?*c_void) void;
pub extern fn alloca(__size: c_ulong) ?*c_void;
pub extern fn valloc(__size: usize) ?*c_void;
pub extern fn posix_memalign(__memptr: [*c]?*c_void, __alignment: usize, __size: usize) c_int;
pub extern fn aligned_alloc(__alignment: usize, __size: usize) ?*c_void;
pub extern fn abort() noreturn;
pub extern fn atexit(__func: ?fn () callconv(.C) void) c_int;
pub extern fn at_quick_exit(__func: ?fn () callconv(.C) void) c_int;
pub extern fn on_exit(__func: ?fn (c_int, ?*c_void) callconv(.C) void, __arg: ?*c_void) c_int;
pub extern fn exit(__status: c_int) noreturn;
pub extern fn quick_exit(__status: c_int) noreturn;
pub extern fn _Exit(__status: c_int) noreturn;
pub extern fn getenv(__name: [*c]const u8) [*c]u8;
pub extern fn putenv(__string: [*c]u8) c_int;
pub extern fn setenv(__name: [*c]const u8, __value: [*c]const u8, __replace: c_int) c_int;
pub extern fn unsetenv(__name: [*c]const u8) c_int;
pub extern fn clearenv() c_int;
pub extern fn mktemp(__template: [*c]u8) [*c]u8;
pub extern fn mkstemp(__template: [*c]u8) c_int;
pub extern fn mkstemps(__template: [*c]u8, __suffixlen: c_int) c_int;
pub extern fn mkdtemp(__template: [*c]u8) [*c]u8;
pub extern fn system(__command: [*c]const u8) c_int;
pub extern fn realpath(noalias __name: [*c]const u8, noalias __resolved: [*c]u8) [*c]u8;
pub const __compar_fn_t = ?fn (?*const c_void, ?*const c_void) callconv(.C) c_int;
pub fn bsearch(arg___key: ?*const c_void, arg___base: ?*const c_void, arg___nmemb: usize, arg___size: usize, arg___compar: __compar_fn_t) callconv(.C) ?*c_void {
    var __key = arg___key;
    var __base = arg___base;
    var __nmemb = arg___nmemb;
    var __size = arg___size;
    var __compar = arg___compar;
    var __l: usize = undefined;
    var __u: usize = undefined;
    var __idx: usize = undefined;
    var __p: ?*const c_void = undefined;
    var __comparison: c_int = undefined;
    __l = @bitCast(usize, @as(c_long, @as(c_int, 0)));
    __u = __nmemb;
    while (__l < __u) {
        __idx = ((__l +% __u) / @bitCast(c_ulong, @as(c_long, @as(c_int, 2))));
        __p = @intToPtr(?*c_void, @ptrToInt(((@ptrCast([*c]const u8, @alignCast(@alignOf(u8), __base))) + (__idx *% __size))));
        __comparison = (__compar).?(__key, __p);
        if (__comparison < @as(c_int, 0)) __u = __idx else if (__comparison > @as(c_int, 0)) __l = (__idx +% @bitCast(c_ulong, @as(c_long, @as(c_int, 1)))) else return @intToPtr(?*c_void, @ptrToInt(__p));
    }
    return (@intToPtr(?*c_void, @as(c_int, 0)));
}
pub extern fn qsort(__base: ?*c_void, __nmemb: usize, __size: usize, __compar: __compar_fn_t) void;
pub extern fn abs(__x: c_int) c_int;
pub extern fn labs(__x: c_long) c_long;
pub extern fn llabs(__x: c_longlong) c_longlong;
pub extern fn div(__numer: c_int, __denom: c_int) div_t;
pub extern fn ldiv(__numer: c_long, __denom: c_long) ldiv_t;
pub extern fn lldiv(__numer: c_longlong, __denom: c_longlong) lldiv_t;
pub extern fn ecvt(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn fcvt(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn gcvt(__value: f64, __ndigit: c_int, __buf: [*c]u8) [*c]u8;
pub extern fn qecvt(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn qfcvt(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn qgcvt(__value: c_longdouble, __ndigit: c_int, __buf: [*c]u8) [*c]u8;
pub extern fn ecvt_r(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn fcvt_r(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn qecvt_r(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn qfcvt_r(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn mblen(__s: [*c]const u8, __n: usize) c_int;
pub extern fn mbtowc(noalias __pwc: [*c]wchar_t, noalias __s: [*c]const u8, __n: usize) c_int;
pub extern fn wctomb(__s: [*c]u8, __wchar: wchar_t) c_int;
pub extern fn mbstowcs(noalias __pwcs: [*c]wchar_t, noalias __s: [*c]const u8, __n: usize) usize;
pub extern fn wcstombs(noalias __s: [*c]u8, noalias __pwcs: [*c]const wchar_t, __n: usize) usize;
pub extern fn rpmatch(__response: [*c]const u8) c_int;
pub extern fn getsubopt(noalias __optionp: [*c][*c]u8, noalias __tokens: [*c]const [*c]u8, noalias __valuep: [*c][*c]u8) c_int;
pub extern fn getloadavg(__loadavg: [*c]f64, __nelem: c_int) c_int;
pub const int_least8_t = __int_least8_t;
pub const int_least16_t = __int_least16_t;
pub const int_least32_t = __int_least32_t;
pub const int_least64_t = __int_least64_t;
pub const uint_least8_t = __uint_least8_t;
pub const uint_least16_t = __uint_least16_t;
pub const uint_least32_t = __uint_least32_t;
pub const uint_least64_t = __uint_least64_t;
pub const int_fast8_t = i8;
pub const int_fast16_t = c_long;
pub const int_fast32_t = c_long;
pub const int_fast64_t = c_long;
pub const uint_fast8_t = u8;
pub const uint_fast16_t = c_ulong;
pub const uint_fast32_t = c_ulong;
pub const uint_fast64_t = c_ulong;
pub const intmax_t = __intmax_t;
pub const uintmax_t = __uintmax_t;
pub const va_list = __builtin_va_list;
pub const __gnuc_va_list = __builtin_va_list;
const union_unnamed_21 = extern union {
    __wch: c_uint,
    __wchb: [4]u8,
};
const struct_unnamed_20 = extern struct {
    __count: c_int,
    __value: union_unnamed_21,
};
pub const __mbstate_t = struct_unnamed_20;
pub const struct__G_fpos_t = extern struct {
    __pos: __off_t,
    __state: __mbstate_t,
};
pub const __fpos_t = struct__G_fpos_t;
pub const struct__G_fpos64_t = extern struct {
    __pos: __off64_t,
    __state: __mbstate_t,
};
pub const __fpos64_t = struct__G_fpos64_t;
pub const struct__IO_marker = opaque {};
pub const struct__IO_codecvt = opaque {};
pub const struct__IO_wide_data = opaque {};
pub const struct__IO_FILE = extern struct {
    _flags: c_int,
    _IO_read_ptr: [*c]u8,
    _IO_read_end: [*c]u8,
    _IO_read_base: [*c]u8,
    _IO_write_base: [*c]u8,
    _IO_write_ptr: [*c]u8,
    _IO_write_end: [*c]u8,
    _IO_buf_base: [*c]u8,
    _IO_buf_end: [*c]u8,
    _IO_save_base: [*c]u8,
    _IO_backup_base: [*c]u8,
    _IO_save_end: [*c]u8,
    _markers: ?*struct__IO_marker,
    _chain: [*c]struct__IO_FILE,
    _fileno: c_int,
    _flags2: c_int,
    _old_offset: __off_t,
    _cur_column: c_ushort,
    _vtable_offset: i8,
    _shortbuf: [1]u8,
    _lock: ?*_IO_lock_t,
    _offset: __off64_t,
    _codecvt: ?*struct__IO_codecvt,
    _wide_data: ?*struct__IO_wide_data,
    _freeres_list: [*c]struct__IO_FILE,
    _freeres_buf: ?*c_void,
    __pad5: usize,
    _mode: c_int,
    _unused2: [20]u8,
};
pub const __FILE = struct__IO_FILE;
pub const FILE = struct__IO_FILE;
pub const _IO_lock_t = c_void;
pub const fpos_t = __fpos_t;
pub extern var stdin: [*c]FILE;
pub extern var stdout: [*c]FILE;
pub extern var stderr: [*c]FILE;
pub extern fn remove(__filename: [*c]const u8) c_int;
pub extern fn rename(__old: [*c]const u8, __new: [*c]const u8) c_int;
pub extern fn renameat(__oldfd: c_int, __old: [*c]const u8, __newfd: c_int, __new: [*c]const u8) c_int;
pub extern fn tmpfile() [*c]FILE;
pub extern fn tmpnam(__s: [*c]u8) [*c]u8;
pub extern fn tmpnam_r(__s: [*c]u8) [*c]u8;
pub extern fn tempnam(__dir: [*c]const u8, __pfx: [*c]const u8) [*c]u8;
pub extern fn fclose(__stream: [*c]FILE) c_int;
pub extern fn fflush(__stream: [*c]FILE) c_int;
pub extern fn fflush_unlocked(__stream: [*c]FILE) c_int;
pub extern fn fopen(__filename: [*c]const u8, __modes: [*c]const u8) [*c]FILE;
pub extern fn freopen(noalias __filename: [*c]const u8, noalias __modes: [*c]const u8, noalias __stream: [*c]FILE) [*c]FILE;
pub extern fn fdopen(__fd: c_int, __modes: [*c]const u8) [*c]FILE;
pub extern fn fmemopen(__s: ?*c_void, __len: usize, __modes: [*c]const u8) [*c]FILE;
pub extern fn open_memstream(__bufloc: [*c][*c]u8, __sizeloc: [*c]usize) [*c]FILE;
pub extern fn setbuf(noalias __stream: [*c]FILE, noalias __buf: [*c]u8) void;
pub extern fn setvbuf(noalias __stream: [*c]FILE, noalias __buf: [*c]u8, __modes: c_int, __n: usize) c_int;
pub extern fn setbuffer(noalias __stream: [*c]FILE, noalias __buf: [*c]u8, __size: usize) void;
pub extern fn setlinebuf(__stream: [*c]FILE) void;
pub extern fn fprintf(__stream: [*c]FILE, __format: [*c]const u8, ...) c_int;
pub extern fn printf(__format: [*c]const u8, ...) c_int;
pub extern fn sprintf(__s: [*c]u8, __format: [*c]const u8, ...) c_int;
pub const struct___va_list_tag = extern struct {
    gp_offset: c_uint,
    fp_offset: c_uint,
    overflow_arg_area: ?*c_void,
    reg_save_area: ?*c_void,
};
pub extern fn vfprintf(__s: [*c]FILE, __format: [*c]const u8, __arg: [*c]struct___va_list_tag) c_int;
pub fn vprintf(arg___fmt: [*c]const u8, arg___arg: [*c]struct___va_list_tag) callconv(.C) c_int {
    var __fmt = arg___fmt;
    var __arg = arg___arg;
    return vfprintf(stdout, __fmt, __arg);
}
pub extern fn vsprintf(__s: [*c]u8, __format: [*c]const u8, __arg: [*c]struct___va_list_tag) c_int;
pub extern fn snprintf(__s: [*c]u8, __maxlen: c_ulong, __format: [*c]const u8, ...) c_int;
pub extern fn vsnprintf(__s: [*c]u8, __maxlen: c_ulong, __format: [*c]const u8, __arg: [*c]struct___va_list_tag) c_int;
pub extern fn vdprintf(__fd: c_int, noalias __fmt: [*c]const u8, __arg: [*c]struct___va_list_tag) c_int;
pub extern fn dprintf(__fd: c_int, noalias __fmt: [*c]const u8, ...) c_int;
pub extern fn fscanf(noalias __stream: [*c]FILE, noalias __format: [*c]const u8, ...) c_int;
pub extern fn scanf(noalias __format: [*c]const u8, ...) c_int;
pub extern fn sscanf(noalias __s: [*c]const u8, noalias __format: [*c]const u8, ...) c_int;
pub extern fn vfscanf(noalias __s: [*c]FILE, noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag) c_int;
pub extern fn vscanf(noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag) c_int;
pub extern fn vsscanf(noalias __s: [*c]const u8, noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag) c_int;
pub extern fn fgetc(__stream: [*c]FILE) c_int;
pub extern fn getc(__stream: [*c]FILE) c_int;
pub fn getchar() callconv(.C) c_int {
    return getc(stdin);
} // /usr/include/sys/cdefs.h:402:33: warning: TODO implement translation of CastKind BuiltinFnToFnPtr
pub const getc_unlocked = @compileError("unable to translate function"); // /usr/include/bits/stdio.h:66:1
// /usr/include/sys/cdefs.h:402:33: warning: TODO implement translation of CastKind BuiltinFnToFnPtr
pub const getchar_unlocked = @compileError("unable to translate function"); // /usr/include/bits/stdio.h:73:1
// /usr/include/sys/cdefs.h:402:33: warning: TODO implement translation of CastKind BuiltinFnToFnPtr
pub const fgetc_unlocked = @compileError("unable to translate function"); // /usr/include/bits/stdio.h:56:1
pub extern fn fputc(__c: c_int, __stream: [*c]FILE) c_int;
pub extern fn putc(__c: c_int, __stream: [*c]FILE) c_int;
pub fn putchar(arg___c: c_int) callconv(.C) c_int {
    var __c = arg___c;
    return putc(__c, stdout);
} // /usr/include/sys/cdefs.h:402:33: warning: TODO implement translation of CastKind BuiltinFnToFnPtr
pub const fputc_unlocked = @compileError("unable to translate function"); // /usr/include/bits/stdio.h:91:1
// /usr/include/sys/cdefs.h:402:33: warning: TODO implement translation of CastKind BuiltinFnToFnPtr
pub const putc_unlocked = @compileError("unable to translate function"); // /usr/include/bits/stdio.h:101:1
// /usr/include/sys/cdefs.h:402:33: warning: TODO implement translation of CastKind BuiltinFnToFnPtr
pub const putchar_unlocked = @compileError("unable to translate function"); // /usr/include/bits/stdio.h:108:1
pub extern fn getw(__stream: [*c]FILE) c_int;
pub extern fn putw(__w: c_int, __stream: [*c]FILE) c_int;
pub extern fn fgets(noalias __s: [*c]u8, __n: c_int, noalias __stream: [*c]FILE) [*c]u8;
pub extern fn __getdelim(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, __delimiter: c_int, noalias __stream: [*c]FILE) __ssize_t;
pub extern fn getdelim(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, __delimiter: c_int, noalias __stream: [*c]FILE) __ssize_t;
pub extern fn getline(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, noalias __stream: [*c]FILE) __ssize_t;
pub extern fn fputs(noalias __s: [*c]const u8, noalias __stream: [*c]FILE) c_int;
pub extern fn puts(__s: [*c]const u8) c_int;
pub extern fn ungetc(__c: c_int, __stream: [*c]FILE) c_int;
pub extern fn fread(__ptr: ?*c_void, __size: c_ulong, __n: c_ulong, __stream: [*c]FILE) c_ulong;
pub extern fn fwrite(__ptr: ?*const c_void, __size: c_ulong, __n: c_ulong, __s: [*c]FILE) c_ulong;
pub extern fn fread_unlocked(noalias __ptr: ?*c_void, __size: usize, __n: usize, noalias __stream: [*c]FILE) usize;
pub extern fn fwrite_unlocked(noalias __ptr: ?*const c_void, __size: usize, __n: usize, noalias __stream: [*c]FILE) usize;
pub extern fn fseek(__stream: [*c]FILE, __off: c_long, __whence: c_int) c_int;
pub extern fn ftell(__stream: [*c]FILE) c_long;
pub extern fn rewind(__stream: [*c]FILE) void;
pub extern fn fseeko(__stream: [*c]FILE, __off: __off_t, __whence: c_int) c_int;
pub extern fn ftello(__stream: [*c]FILE) __off_t;
pub extern fn fgetpos(noalias __stream: [*c]FILE, noalias __pos: [*c]fpos_t) c_int;
pub extern fn fsetpos(__stream: [*c]FILE, __pos: [*c]const fpos_t) c_int;
pub extern fn clearerr(__stream: [*c]FILE) void;
pub extern fn feof(__stream: [*c]FILE) c_int;
pub extern fn ferror(__stream: [*c]FILE) c_int;
pub extern fn clearerr_unlocked(__stream: [*c]FILE) void;
pub fn feof_unlocked(arg___stream: [*c]FILE) callconv(.C) c_int {
    var __stream = arg___stream;
    return (((__stream).*._flags & @as(c_int, 16)) != @as(c_int, 0));
}
pub fn ferror_unlocked(arg___stream: [*c]FILE) callconv(.C) c_int {
    var __stream = arg___stream;
    return (((__stream).*._flags & @as(c_int, 32)) != @as(c_int, 0));
}
pub extern fn perror(__s: [*c]const u8) void;
pub extern fn fileno(__stream: [*c]FILE) c_int;
pub extern fn fileno_unlocked(__stream: [*c]FILE) c_int;
pub extern fn popen(__command: [*c]const u8, __modes: [*c]const u8) [*c]FILE;
pub extern fn pclose(__stream: [*c]FILE) c_int;
pub extern fn ctermid(__s: [*c]u8) [*c]u8;
pub extern fn flockfile(__stream: [*c]FILE) void;
pub extern fn ftrylockfile(__stream: [*c]FILE) c_int;
pub extern fn funlockfile(__stream: [*c]FILE) void;
pub extern fn __uflow([*c]FILE) c_int;
pub extern fn __overflow([*c]FILE, c_int) c_int;
pub const ptrdiff_t = c_long;
const struct_unnamed_22 = extern struct {
    __clang_max_align_nonce1: c_longlong align(8),
    __clang_max_align_nonce2: c_longdouble align(16),
};
pub const max_align_t = struct_unnamed_22;
pub const memory_order_relaxed = @enumToInt(enum_memory_order._relaxed);
pub const memory_order_consume = @enumToInt(enum_memory_order._consume);
pub const memory_order_acquire = @enumToInt(enum_memory_order._acquire);
pub const memory_order_release = @enumToInt(enum_memory_order._release);
pub const memory_order_acq_rel = @enumToInt(enum_memory_order._acq_rel);
pub const memory_order_seq_cst = @enumToInt(enum_memory_order._seq_cst);
pub const enum_memory_order = extern enum(c_int) {
    _relaxed = 0,
    _consume = 1,
    _acquire = 2,
    _release = 3,
    _acq_rel = 4,
    _seq_cst = 5,
    _,
};
pub const memory_order = enum_memory_order;
pub extern fn atomic_thread_fence(memory_order) void;
pub extern fn atomic_signal_fence(memory_order) void; // /usr/lib/zig/include/stdatomic.h:76:37: warning: unsupported type: 'Atomic'
pub const atomic_bool = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:76:37
// /usr/lib/zig/include/stdatomic.h:78:37: warning: unsupported type: 'Atomic'
pub const atomic_char = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:78:37
// /usr/lib/zig/include/stdatomic.h:79:37: warning: unsupported type: 'Atomic'
pub const atomic_schar = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:79:37
// /usr/lib/zig/include/stdatomic.h:80:37: warning: unsupported type: 'Atomic'
pub const atomic_uchar = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:80:37
// /usr/lib/zig/include/stdatomic.h:81:37: warning: unsupported type: 'Atomic'
pub const atomic_short = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:81:37
// /usr/lib/zig/include/stdatomic.h:82:37: warning: unsupported type: 'Atomic'
pub const atomic_ushort = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:82:37
// /usr/lib/zig/include/stdatomic.h:83:37: warning: unsupported type: 'Atomic'
pub const atomic_int = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:83:37
// /usr/lib/zig/include/stdatomic.h:84:37: warning: unsupported type: 'Atomic'
pub const atomic_uint = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:84:37
// /usr/lib/zig/include/stdatomic.h:85:37: warning: unsupported type: 'Atomic'
pub const atomic_long = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:85:37
// /usr/lib/zig/include/stdatomic.h:86:37: warning: unsupported type: 'Atomic'
pub const atomic_ulong = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:86:37
// /usr/lib/zig/include/stdatomic.h:87:37: warning: unsupported type: 'Atomic'
pub const atomic_llong = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:87:37
// /usr/lib/zig/include/stdatomic.h:88:37: warning: unsupported type: 'Atomic'
pub const atomic_ullong = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:88:37
// /usr/lib/zig/include/stdatomic.h:89:37: warning: unsupported type: 'Atomic'
pub const atomic_char16_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:89:37
// /usr/lib/zig/include/stdatomic.h:90:37: warning: unsupported type: 'Atomic'
pub const atomic_char32_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:90:37
// /usr/lib/zig/include/stdatomic.h:91:37: warning: unsupported type: 'Atomic'
pub const atomic_wchar_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:91:37
// /usr/lib/zig/include/stdatomic.h:92:37: warning: unsupported type: 'Atomic'
pub const atomic_int_least8_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:92:37
// /usr/lib/zig/include/stdatomic.h:93:37: warning: unsupported type: 'Atomic'
pub const atomic_uint_least8_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:93:37
// /usr/lib/zig/include/stdatomic.h:94:37: warning: unsupported type: 'Atomic'
pub const atomic_int_least16_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:94:37
// /usr/lib/zig/include/stdatomic.h:95:37: warning: unsupported type: 'Atomic'
pub const atomic_uint_least16_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:95:37
// /usr/lib/zig/include/stdatomic.h:96:37: warning: unsupported type: 'Atomic'
pub const atomic_int_least32_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:96:37
// /usr/lib/zig/include/stdatomic.h:97:37: warning: unsupported type: 'Atomic'
pub const atomic_uint_least32_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:97:37
// /usr/lib/zig/include/stdatomic.h:98:37: warning: unsupported type: 'Atomic'
pub const atomic_int_least64_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:98:37
// /usr/lib/zig/include/stdatomic.h:99:37: warning: unsupported type: 'Atomic'
pub const atomic_uint_least64_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:99:37
// /usr/lib/zig/include/stdatomic.h:100:37: warning: unsupported type: 'Atomic'
pub const atomic_int_fast8_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:100:37
// /usr/lib/zig/include/stdatomic.h:101:37: warning: unsupported type: 'Atomic'
pub const atomic_uint_fast8_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:101:37
// /usr/lib/zig/include/stdatomic.h:102:37: warning: unsupported type: 'Atomic'
pub const atomic_int_fast16_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:102:37
// /usr/lib/zig/include/stdatomic.h:103:37: warning: unsupported type: 'Atomic'
pub const atomic_uint_fast16_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:103:37
// /usr/lib/zig/include/stdatomic.h:104:37: warning: unsupported type: 'Atomic'
pub const atomic_int_fast32_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:104:37
// /usr/lib/zig/include/stdatomic.h:105:37: warning: unsupported type: 'Atomic'
pub const atomic_uint_fast32_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:105:37
// /usr/lib/zig/include/stdatomic.h:106:37: warning: unsupported type: 'Atomic'
pub const atomic_int_fast64_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:106:37
// /usr/lib/zig/include/stdatomic.h:107:37: warning: unsupported type: 'Atomic'
pub const atomic_uint_fast64_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:107:37
// /usr/lib/zig/include/stdatomic.h:108:37: warning: unsupported type: 'Atomic'
pub const atomic_intptr_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:108:37
// /usr/lib/zig/include/stdatomic.h:109:37: warning: unsupported type: 'Atomic'
pub const atomic_uintptr_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:109:37
// /usr/lib/zig/include/stdatomic.h:110:37: warning: unsupported type: 'Atomic'
pub const atomic_size_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:110:37
// /usr/lib/zig/include/stdatomic.h:111:37: warning: unsupported type: 'Atomic'
pub const atomic_ptrdiff_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:111:37
// /usr/lib/zig/include/stdatomic.h:112:37: warning: unsupported type: 'Atomic'
pub const atomic_intmax_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:112:37
// /usr/lib/zig/include/stdatomic.h:113:37: warning: unsupported type: 'Atomic'
pub const atomic_uintmax_t = @compileError("unable to resolve typedef child type"); // /usr/lib/zig/include/stdatomic.h:113:37
pub const struct_atomic_flag = extern struct {
    _Value: atomic_bool,
};
pub const atomic_flag = struct_atomic_flag;
pub extern fn atomic_flag_test_and_set([*c]volatile atomic_flag) bool;
pub extern fn atomic_flag_test_and_set_explicit([*c]volatile atomic_flag, memory_order) bool;
pub extern fn atomic_flag_clear([*c]volatile atomic_flag) void;
pub extern fn atomic_flag_clear_explicit([*c]volatile atomic_flag, memory_order) void;
pub const useconds_t = __useconds_t;
pub const socklen_t = __socklen_t;
pub extern fn access(__name: [*c]const u8, __type: c_int) c_int;
pub extern fn faccessat(__fd: c_int, __file: [*c]const u8, __type: c_int, __flag: c_int) c_int;
pub extern fn lseek(__fd: c_int, __offset: __off_t, __whence: c_int) __off_t;
pub extern fn close(__fd: c_int) c_int;
pub extern fn read(__fd: c_int, __buf: ?*c_void, __nbytes: usize) isize;
pub extern fn write(__fd: c_int, __buf: ?*const c_void, __n: usize) isize;
pub extern fn pread(__fd: c_int, __buf: ?*c_void, __nbytes: usize, __offset: __off_t) isize;
pub extern fn pwrite(__fd: c_int, __buf: ?*const c_void, __n: usize, __offset: __off_t) isize;
pub extern fn pipe(__pipedes: [*c]c_int) c_int;
pub extern fn alarm(__seconds: c_uint) c_uint;
pub extern fn sleep(__seconds: c_uint) c_uint;
pub extern fn ualarm(__value: __useconds_t, __interval: __useconds_t) __useconds_t;
pub extern fn usleep(__useconds: __useconds_t) c_int;
pub extern fn pause() c_int;
pub extern fn chown(__file: [*c]const u8, __owner: __uid_t, __group: __gid_t) c_int;
pub extern fn fchown(__fd: c_int, __owner: __uid_t, __group: __gid_t) c_int;
pub extern fn lchown(__file: [*c]const u8, __owner: __uid_t, __group: __gid_t) c_int;
pub extern fn fchownat(__fd: c_int, __file: [*c]const u8, __owner: __uid_t, __group: __gid_t, __flag: c_int) c_int;
pub extern fn chdir(__path: [*c]const u8) c_int;
pub extern fn fchdir(__fd: c_int) c_int;
pub extern fn getcwd(__buf: [*c]u8, __size: usize) [*c]u8;
pub extern fn getwd(__buf: [*c]u8) [*c]u8;
pub extern fn dup(__fd: c_int) c_int;
pub extern fn dup2(__fd: c_int, __fd2: c_int) c_int;
pub extern var __environ: [*c][*c]u8;
pub extern fn execve(__path: [*c]const u8, __argv: [*c]const [*c]u8, __envp: [*c]const [*c]u8) c_int;
pub extern fn fexecve(__fd: c_int, __argv: [*c]const [*c]u8, __envp: [*c]const [*c]u8) c_int;
pub extern fn execv(__path: [*c]const u8, __argv: [*c]const [*c]u8) c_int;
pub extern fn execle(__path: [*c]const u8, __arg: [*c]const u8, ...) c_int;
pub extern fn execl(__path: [*c]const u8, __arg: [*c]const u8, ...) c_int;
pub extern fn execvp(__file: [*c]const u8, __argv: [*c]const [*c]u8) c_int;
pub extern fn execlp(__file: [*c]const u8, __arg: [*c]const u8, ...) c_int;
pub extern fn nice(__inc: c_int) c_int;
pub extern fn _exit(__status: c_int) noreturn;
pub const _PC_LINK_MAX = @enumToInt(enum_unnamed_23._PC_LINK_MAX);
pub const _PC_MAX_CANON = @enumToInt(enum_unnamed_23._PC_MAX_CANON);
pub const _PC_MAX_INPUT = @enumToInt(enum_unnamed_23._PC_MAX_INPUT);
pub const _PC_NAME_MAX = @enumToInt(enum_unnamed_23._PC_NAME_MAX);
pub const _PC_PATH_MAX = @enumToInt(enum_unnamed_23._PC_PATH_MAX);
pub const _PC_PIPE_BUF = @enumToInt(enum_unnamed_23._PC_PIPE_BUF);
pub const _PC_CHOWN_RESTRICTED = @enumToInt(enum_unnamed_23._PC_CHOWN_RESTRICTED);
pub const _PC_NO_TRUNC = @enumToInt(enum_unnamed_23._PC_NO_TRUNC);
pub const _PC_VDISABLE = @enumToInt(enum_unnamed_23._PC_VDISABLE);
pub const _PC_SYNC_IO = @enumToInt(enum_unnamed_23._PC_SYNC_IO);
pub const _PC_ASYNC_IO = @enumToInt(enum_unnamed_23._PC_ASYNC_IO);
pub const _PC_PRIO_IO = @enumToInt(enum_unnamed_23._PC_PRIO_IO);
pub const _PC_SOCK_MAXBUF = @enumToInt(enum_unnamed_23._PC_SOCK_MAXBUF);
pub const _PC_FILESIZEBITS = @enumToInt(enum_unnamed_23._PC_FILESIZEBITS);
pub const _PC_REC_INCR_XFER_SIZE = @enumToInt(enum_unnamed_23._PC_REC_INCR_XFER_SIZE);
pub const _PC_REC_MAX_XFER_SIZE = @enumToInt(enum_unnamed_23._PC_REC_MAX_XFER_SIZE);
pub const _PC_REC_MIN_XFER_SIZE = @enumToInt(enum_unnamed_23._PC_REC_MIN_XFER_SIZE);
pub const _PC_REC_XFER_ALIGN = @enumToInt(enum_unnamed_23._PC_REC_XFER_ALIGN);
pub const _PC_ALLOC_SIZE_MIN = @enumToInt(enum_unnamed_23._PC_ALLOC_SIZE_MIN);
pub const _PC_SYMLINK_MAX = @enumToInt(enum_unnamed_23._PC_SYMLINK_MAX);
pub const _PC_2_SYMLINKS = @enumToInt(enum_unnamed_23._PC_2_SYMLINKS);
const enum_unnamed_23 = extern enum(c_int) {
    _PC_LINK_MAX,
    _PC_MAX_CANON,
    _PC_MAX_INPUT,
    _PC_NAME_MAX,
    _PC_PATH_MAX,
    _PC_PIPE_BUF,
    _PC_CHOWN_RESTRICTED,
    _PC_NO_TRUNC,
    _PC_VDISABLE,
    _PC_SYNC_IO,
    _PC_ASYNC_IO,
    _PC_PRIO_IO,
    _PC_SOCK_MAXBUF,
    _PC_FILESIZEBITS,
    _PC_REC_INCR_XFER_SIZE,
    _PC_REC_MAX_XFER_SIZE,
    _PC_REC_MIN_XFER_SIZE,
    _PC_REC_XFER_ALIGN,
    _PC_ALLOC_SIZE_MIN,
    _PC_SYMLINK_MAX,
    _PC_2_SYMLINKS,
    _,
};
pub const _SC_ARG_MAX = @enumToInt(enum_unnamed_24._SC_ARG_MAX);
pub const _SC_CHILD_MAX = @enumToInt(enum_unnamed_24._SC_CHILD_MAX);
pub const _SC_CLK_TCK = @enumToInt(enum_unnamed_24._SC_CLK_TCK);
pub const _SC_NGROUPS_MAX = @enumToInt(enum_unnamed_24._SC_NGROUPS_MAX);
pub const _SC_OPEN_MAX = @enumToInt(enum_unnamed_24._SC_OPEN_MAX);
pub const _SC_STREAM_MAX = @enumToInt(enum_unnamed_24._SC_STREAM_MAX);
pub const _SC_TZNAME_MAX = @enumToInt(enum_unnamed_24._SC_TZNAME_MAX);
pub const _SC_JOB_CONTROL = @enumToInt(enum_unnamed_24._SC_JOB_CONTROL);
pub const _SC_SAVED_IDS = @enumToInt(enum_unnamed_24._SC_SAVED_IDS);
pub const _SC_REALTIME_SIGNALS = @enumToInt(enum_unnamed_24._SC_REALTIME_SIGNALS);
pub const _SC_PRIORITY_SCHEDULING = @enumToInt(enum_unnamed_24._SC_PRIORITY_SCHEDULING);
pub const _SC_TIMERS = @enumToInt(enum_unnamed_24._SC_TIMERS);
pub const _SC_ASYNCHRONOUS_IO = @enumToInt(enum_unnamed_24._SC_ASYNCHRONOUS_IO);
pub const _SC_PRIORITIZED_IO = @enumToInt(enum_unnamed_24._SC_PRIORITIZED_IO);
pub const _SC_SYNCHRONIZED_IO = @enumToInt(enum_unnamed_24._SC_SYNCHRONIZED_IO);
pub const _SC_FSYNC = @enumToInt(enum_unnamed_24._SC_FSYNC);
pub const _SC_MAPPED_FILES = @enumToInt(enum_unnamed_24._SC_MAPPED_FILES);
pub const _SC_MEMLOCK = @enumToInt(enum_unnamed_24._SC_MEMLOCK);
pub const _SC_MEMLOCK_RANGE = @enumToInt(enum_unnamed_24._SC_MEMLOCK_RANGE);
pub const _SC_MEMORY_PROTECTION = @enumToInt(enum_unnamed_24._SC_MEMORY_PROTECTION);
pub const _SC_MESSAGE_PASSING = @enumToInt(enum_unnamed_24._SC_MESSAGE_PASSING);
pub const _SC_SEMAPHORES = @enumToInt(enum_unnamed_24._SC_SEMAPHORES);
pub const _SC_SHARED_MEMORY_OBJECTS = @enumToInt(enum_unnamed_24._SC_SHARED_MEMORY_OBJECTS);
pub const _SC_AIO_LISTIO_MAX = @enumToInt(enum_unnamed_24._SC_AIO_LISTIO_MAX);
pub const _SC_AIO_MAX = @enumToInt(enum_unnamed_24._SC_AIO_MAX);
pub const _SC_AIO_PRIO_DELTA_MAX = @enumToInt(enum_unnamed_24._SC_AIO_PRIO_DELTA_MAX);
pub const _SC_DELAYTIMER_MAX = @enumToInt(enum_unnamed_24._SC_DELAYTIMER_MAX);
pub const _SC_MQ_OPEN_MAX = @enumToInt(enum_unnamed_24._SC_MQ_OPEN_MAX);
pub const _SC_MQ_PRIO_MAX = @enumToInt(enum_unnamed_24._SC_MQ_PRIO_MAX);
pub const _SC_VERSION = @enumToInt(enum_unnamed_24._SC_VERSION);
pub const _SC_PAGESIZE = @enumToInt(enum_unnamed_24._SC_PAGESIZE);
pub const _SC_RTSIG_MAX = @enumToInt(enum_unnamed_24._SC_RTSIG_MAX);
pub const _SC_SEM_NSEMS_MAX = @enumToInt(enum_unnamed_24._SC_SEM_NSEMS_MAX);
pub const _SC_SEM_VALUE_MAX = @enumToInt(enum_unnamed_24._SC_SEM_VALUE_MAX);
pub const _SC_SIGQUEUE_MAX = @enumToInt(enum_unnamed_24._SC_SIGQUEUE_MAX);
pub const _SC_TIMER_MAX = @enumToInt(enum_unnamed_24._SC_TIMER_MAX);
pub const _SC_BC_BASE_MAX = @enumToInt(enum_unnamed_24._SC_BC_BASE_MAX);
pub const _SC_BC_DIM_MAX = @enumToInt(enum_unnamed_24._SC_BC_DIM_MAX);
pub const _SC_BC_SCALE_MAX = @enumToInt(enum_unnamed_24._SC_BC_SCALE_MAX);
pub const _SC_BC_STRING_MAX = @enumToInt(enum_unnamed_24._SC_BC_STRING_MAX);
pub const _SC_COLL_WEIGHTS_MAX = @enumToInt(enum_unnamed_24._SC_COLL_WEIGHTS_MAX);
pub const _SC_EQUIV_CLASS_MAX = @enumToInt(enum_unnamed_24._SC_EQUIV_CLASS_MAX);
pub const _SC_EXPR_NEST_MAX = @enumToInt(enum_unnamed_24._SC_EXPR_NEST_MAX);
pub const _SC_LINE_MAX = @enumToInt(enum_unnamed_24._SC_LINE_MAX);
pub const _SC_RE_DUP_MAX = @enumToInt(enum_unnamed_24._SC_RE_DUP_MAX);
pub const _SC_CHARCLASS_NAME_MAX = @enumToInt(enum_unnamed_24._SC_CHARCLASS_NAME_MAX);
pub const _SC_2_VERSION = @enumToInt(enum_unnamed_24._SC_2_VERSION);
pub const _SC_2_C_BIND = @enumToInt(enum_unnamed_24._SC_2_C_BIND);
pub const _SC_2_C_DEV = @enumToInt(enum_unnamed_24._SC_2_C_DEV);
pub const _SC_2_FORT_DEV = @enumToInt(enum_unnamed_24._SC_2_FORT_DEV);
pub const _SC_2_FORT_RUN = @enumToInt(enum_unnamed_24._SC_2_FORT_RUN);
pub const _SC_2_SW_DEV = @enumToInt(enum_unnamed_24._SC_2_SW_DEV);
pub const _SC_2_LOCALEDEF = @enumToInt(enum_unnamed_24._SC_2_LOCALEDEF);
pub const _SC_PII = @enumToInt(enum_unnamed_24._SC_PII);
pub const _SC_PII_XTI = @enumToInt(enum_unnamed_24._SC_PII_XTI);
pub const _SC_PII_SOCKET = @enumToInt(enum_unnamed_24._SC_PII_SOCKET);
pub const _SC_PII_INTERNET = @enumToInt(enum_unnamed_24._SC_PII_INTERNET);
pub const _SC_PII_OSI = @enumToInt(enum_unnamed_24._SC_PII_OSI);
pub const _SC_POLL = @enumToInt(enum_unnamed_24._SC_POLL);
pub const _SC_SELECT = @enumToInt(enum_unnamed_24._SC_SELECT);
pub const _SC_UIO_MAXIOV = @enumToInt(enum_unnamed_24._SC_UIO_MAXIOV);
pub const _SC_IOV_MAX = @enumToInt(enum_unnamed_24._SC_IOV_MAX);
pub const _SC_PII_INTERNET_STREAM = @enumToInt(enum_unnamed_24._SC_PII_INTERNET_STREAM);
pub const _SC_PII_INTERNET_DGRAM = @enumToInt(enum_unnamed_24._SC_PII_INTERNET_DGRAM);
pub const _SC_PII_OSI_COTS = @enumToInt(enum_unnamed_24._SC_PII_OSI_COTS);
pub const _SC_PII_OSI_CLTS = @enumToInt(enum_unnamed_24._SC_PII_OSI_CLTS);
pub const _SC_PII_OSI_M = @enumToInt(enum_unnamed_24._SC_PII_OSI_M);
pub const _SC_T_IOV_MAX = @enumToInt(enum_unnamed_24._SC_T_IOV_MAX);
pub const _SC_THREADS = @enumToInt(enum_unnamed_24._SC_THREADS);
pub const _SC_THREAD_SAFE_FUNCTIONS = @enumToInt(enum_unnamed_24._SC_THREAD_SAFE_FUNCTIONS);
pub const _SC_GETGR_R_SIZE_MAX = @enumToInt(enum_unnamed_24._SC_GETGR_R_SIZE_MAX);
pub const _SC_GETPW_R_SIZE_MAX = @enumToInt(enum_unnamed_24._SC_GETPW_R_SIZE_MAX);
pub const _SC_LOGIN_NAME_MAX = @enumToInt(enum_unnamed_24._SC_LOGIN_NAME_MAX);
pub const _SC_TTY_NAME_MAX = @enumToInt(enum_unnamed_24._SC_TTY_NAME_MAX);
pub const _SC_THREAD_DESTRUCTOR_ITERATIONS = @enumToInt(enum_unnamed_24._SC_THREAD_DESTRUCTOR_ITERATIONS);
pub const _SC_THREAD_KEYS_MAX = @enumToInt(enum_unnamed_24._SC_THREAD_KEYS_MAX);
pub const _SC_THREAD_STACK_MIN = @enumToInt(enum_unnamed_24._SC_THREAD_STACK_MIN);
pub const _SC_THREAD_THREADS_MAX = @enumToInt(enum_unnamed_24._SC_THREAD_THREADS_MAX);
pub const _SC_THREAD_ATTR_STACKADDR = @enumToInt(enum_unnamed_24._SC_THREAD_ATTR_STACKADDR);
pub const _SC_THREAD_ATTR_STACKSIZE = @enumToInt(enum_unnamed_24._SC_THREAD_ATTR_STACKSIZE);
pub const _SC_THREAD_PRIORITY_SCHEDULING = @enumToInt(enum_unnamed_24._SC_THREAD_PRIORITY_SCHEDULING);
pub const _SC_THREAD_PRIO_INHERIT = @enumToInt(enum_unnamed_24._SC_THREAD_PRIO_INHERIT);
pub const _SC_THREAD_PRIO_PROTECT = @enumToInt(enum_unnamed_24._SC_THREAD_PRIO_PROTECT);
pub const _SC_THREAD_PROCESS_SHARED = @enumToInt(enum_unnamed_24._SC_THREAD_PROCESS_SHARED);
pub const _SC_NPROCESSORS_CONF = @enumToInt(enum_unnamed_24._SC_NPROCESSORS_CONF);
pub const _SC_NPROCESSORS_ONLN = @enumToInt(enum_unnamed_24._SC_NPROCESSORS_ONLN);
pub const _SC_PHYS_PAGES = @enumToInt(enum_unnamed_24._SC_PHYS_PAGES);
pub const _SC_AVPHYS_PAGES = @enumToInt(enum_unnamed_24._SC_AVPHYS_PAGES);
pub const _SC_ATEXIT_MAX = @enumToInt(enum_unnamed_24._SC_ATEXIT_MAX);
pub const _SC_PASS_MAX = @enumToInt(enum_unnamed_24._SC_PASS_MAX);
pub const _SC_XOPEN_VERSION = @enumToInt(enum_unnamed_24._SC_XOPEN_VERSION);
pub const _SC_XOPEN_XCU_VERSION = @enumToInt(enum_unnamed_24._SC_XOPEN_XCU_VERSION);
pub const _SC_XOPEN_UNIX = @enumToInt(enum_unnamed_24._SC_XOPEN_UNIX);
pub const _SC_XOPEN_CRYPT = @enumToInt(enum_unnamed_24._SC_XOPEN_CRYPT);
pub const _SC_XOPEN_ENH_I18N = @enumToInt(enum_unnamed_24._SC_XOPEN_ENH_I18N);
pub const _SC_XOPEN_SHM = @enumToInt(enum_unnamed_24._SC_XOPEN_SHM);
pub const _SC_2_CHAR_TERM = @enumToInt(enum_unnamed_24._SC_2_CHAR_TERM);
pub const _SC_2_C_VERSION = @enumToInt(enum_unnamed_24._SC_2_C_VERSION);
pub const _SC_2_UPE = @enumToInt(enum_unnamed_24._SC_2_UPE);
pub const _SC_XOPEN_XPG2 = @enumToInt(enum_unnamed_24._SC_XOPEN_XPG2);
pub const _SC_XOPEN_XPG3 = @enumToInt(enum_unnamed_24._SC_XOPEN_XPG3);
pub const _SC_XOPEN_XPG4 = @enumToInt(enum_unnamed_24._SC_XOPEN_XPG4);
pub const _SC_CHAR_BIT = @enumToInt(enum_unnamed_24._SC_CHAR_BIT);
pub const _SC_CHAR_MAX = @enumToInt(enum_unnamed_24._SC_CHAR_MAX);
pub const _SC_CHAR_MIN = @enumToInt(enum_unnamed_24._SC_CHAR_MIN);
pub const _SC_INT_MAX = @enumToInt(enum_unnamed_24._SC_INT_MAX);
pub const _SC_INT_MIN = @enumToInt(enum_unnamed_24._SC_INT_MIN);
pub const _SC_LONG_BIT = @enumToInt(enum_unnamed_24._SC_LONG_BIT);
pub const _SC_WORD_BIT = @enumToInt(enum_unnamed_24._SC_WORD_BIT);
pub const _SC_MB_LEN_MAX = @enumToInt(enum_unnamed_24._SC_MB_LEN_MAX);
pub const _SC_NZERO = @enumToInt(enum_unnamed_24._SC_NZERO);
pub const _SC_SSIZE_MAX = @enumToInt(enum_unnamed_24._SC_SSIZE_MAX);
pub const _SC_SCHAR_MAX = @enumToInt(enum_unnamed_24._SC_SCHAR_MAX);
pub const _SC_SCHAR_MIN = @enumToInt(enum_unnamed_24._SC_SCHAR_MIN);
pub const _SC_SHRT_MAX = @enumToInt(enum_unnamed_24._SC_SHRT_MAX);
pub const _SC_SHRT_MIN = @enumToInt(enum_unnamed_24._SC_SHRT_MIN);
pub const _SC_UCHAR_MAX = @enumToInt(enum_unnamed_24._SC_UCHAR_MAX);
pub const _SC_UINT_MAX = @enumToInt(enum_unnamed_24._SC_UINT_MAX);
pub const _SC_ULONG_MAX = @enumToInt(enum_unnamed_24._SC_ULONG_MAX);
pub const _SC_USHRT_MAX = @enumToInt(enum_unnamed_24._SC_USHRT_MAX);
pub const _SC_NL_ARGMAX = @enumToInt(enum_unnamed_24._SC_NL_ARGMAX);
pub const _SC_NL_LANGMAX = @enumToInt(enum_unnamed_24._SC_NL_LANGMAX);
pub const _SC_NL_MSGMAX = @enumToInt(enum_unnamed_24._SC_NL_MSGMAX);
pub const _SC_NL_NMAX = @enumToInt(enum_unnamed_24._SC_NL_NMAX);
pub const _SC_NL_SETMAX = @enumToInt(enum_unnamed_24._SC_NL_SETMAX);
pub const _SC_NL_TEXTMAX = @enumToInt(enum_unnamed_24._SC_NL_TEXTMAX);
pub const _SC_XBS5_ILP32_OFF32 = @enumToInt(enum_unnamed_24._SC_XBS5_ILP32_OFF32);
pub const _SC_XBS5_ILP32_OFFBIG = @enumToInt(enum_unnamed_24._SC_XBS5_ILP32_OFFBIG);
pub const _SC_XBS5_LP64_OFF64 = @enumToInt(enum_unnamed_24._SC_XBS5_LP64_OFF64);
pub const _SC_XBS5_LPBIG_OFFBIG = @enumToInt(enum_unnamed_24._SC_XBS5_LPBIG_OFFBIG);
pub const _SC_XOPEN_LEGACY = @enumToInt(enum_unnamed_24._SC_XOPEN_LEGACY);
pub const _SC_XOPEN_REALTIME = @enumToInt(enum_unnamed_24._SC_XOPEN_REALTIME);
pub const _SC_XOPEN_REALTIME_THREADS = @enumToInt(enum_unnamed_24._SC_XOPEN_REALTIME_THREADS);
pub const _SC_ADVISORY_INFO = @enumToInt(enum_unnamed_24._SC_ADVISORY_INFO);
pub const _SC_BARRIERS = @enumToInt(enum_unnamed_24._SC_BARRIERS);
pub const _SC_BASE = @enumToInt(enum_unnamed_24._SC_BASE);
pub const _SC_C_LANG_SUPPORT = @enumToInt(enum_unnamed_24._SC_C_LANG_SUPPORT);
pub const _SC_C_LANG_SUPPORT_R = @enumToInt(enum_unnamed_24._SC_C_LANG_SUPPORT_R);
pub const _SC_CLOCK_SELECTION = @enumToInt(enum_unnamed_24._SC_CLOCK_SELECTION);
pub const _SC_CPUTIME = @enumToInt(enum_unnamed_24._SC_CPUTIME);
pub const _SC_THREAD_CPUTIME = @enumToInt(enum_unnamed_24._SC_THREAD_CPUTIME);
pub const _SC_DEVICE_IO = @enumToInt(enum_unnamed_24._SC_DEVICE_IO);
pub const _SC_DEVICE_SPECIFIC = @enumToInt(enum_unnamed_24._SC_DEVICE_SPECIFIC);
pub const _SC_DEVICE_SPECIFIC_R = @enumToInt(enum_unnamed_24._SC_DEVICE_SPECIFIC_R);
pub const _SC_FD_MGMT = @enumToInt(enum_unnamed_24._SC_FD_MGMT);
pub const _SC_FIFO = @enumToInt(enum_unnamed_24._SC_FIFO);
pub const _SC_PIPE = @enumToInt(enum_unnamed_24._SC_PIPE);
pub const _SC_FILE_ATTRIBUTES = @enumToInt(enum_unnamed_24._SC_FILE_ATTRIBUTES);
pub const _SC_FILE_LOCKING = @enumToInt(enum_unnamed_24._SC_FILE_LOCKING);
pub const _SC_FILE_SYSTEM = @enumToInt(enum_unnamed_24._SC_FILE_SYSTEM);
pub const _SC_MONOTONIC_CLOCK = @enumToInt(enum_unnamed_24._SC_MONOTONIC_CLOCK);
pub const _SC_MULTI_PROCESS = @enumToInt(enum_unnamed_24._SC_MULTI_PROCESS);
pub const _SC_SINGLE_PROCESS = @enumToInt(enum_unnamed_24._SC_SINGLE_PROCESS);
pub const _SC_NETWORKING = @enumToInt(enum_unnamed_24._SC_NETWORKING);
pub const _SC_READER_WRITER_LOCKS = @enumToInt(enum_unnamed_24._SC_READER_WRITER_LOCKS);
pub const _SC_SPIN_LOCKS = @enumToInt(enum_unnamed_24._SC_SPIN_LOCKS);
pub const _SC_REGEXP = @enumToInt(enum_unnamed_24._SC_REGEXP);
pub const _SC_REGEX_VERSION = @enumToInt(enum_unnamed_24._SC_REGEX_VERSION);
pub const _SC_SHELL = @enumToInt(enum_unnamed_24._SC_SHELL);
pub const _SC_SIGNALS = @enumToInt(enum_unnamed_24._SC_SIGNALS);
pub const _SC_SPAWN = @enumToInt(enum_unnamed_24._SC_SPAWN);
pub const _SC_SPORADIC_SERVER = @enumToInt(enum_unnamed_24._SC_SPORADIC_SERVER);
pub const _SC_THREAD_SPORADIC_SERVER = @enumToInt(enum_unnamed_24._SC_THREAD_SPORADIC_SERVER);
pub const _SC_SYSTEM_DATABASE = @enumToInt(enum_unnamed_24._SC_SYSTEM_DATABASE);
pub const _SC_SYSTEM_DATABASE_R = @enumToInt(enum_unnamed_24._SC_SYSTEM_DATABASE_R);
pub const _SC_TIMEOUTS = @enumToInt(enum_unnamed_24._SC_TIMEOUTS);
pub const _SC_TYPED_MEMORY_OBJECTS = @enumToInt(enum_unnamed_24._SC_TYPED_MEMORY_OBJECTS);
pub const _SC_USER_GROUPS = @enumToInt(enum_unnamed_24._SC_USER_GROUPS);
pub const _SC_USER_GROUPS_R = @enumToInt(enum_unnamed_24._SC_USER_GROUPS_R);
pub const _SC_2_PBS = @enumToInt(enum_unnamed_24._SC_2_PBS);
pub const _SC_2_PBS_ACCOUNTING = @enumToInt(enum_unnamed_24._SC_2_PBS_ACCOUNTING);
pub const _SC_2_PBS_LOCATE = @enumToInt(enum_unnamed_24._SC_2_PBS_LOCATE);
pub const _SC_2_PBS_MESSAGE = @enumToInt(enum_unnamed_24._SC_2_PBS_MESSAGE);
pub const _SC_2_PBS_TRACK = @enumToInt(enum_unnamed_24._SC_2_PBS_TRACK);
pub const _SC_SYMLOOP_MAX = @enumToInt(enum_unnamed_24._SC_SYMLOOP_MAX);
pub const _SC_STREAMS = @enumToInt(enum_unnamed_24._SC_STREAMS);
pub const _SC_2_PBS_CHECKPOINT = @enumToInt(enum_unnamed_24._SC_2_PBS_CHECKPOINT);
pub const _SC_V6_ILP32_OFF32 = @enumToInt(enum_unnamed_24._SC_V6_ILP32_OFF32);
pub const _SC_V6_ILP32_OFFBIG = @enumToInt(enum_unnamed_24._SC_V6_ILP32_OFFBIG);
pub const _SC_V6_LP64_OFF64 = @enumToInt(enum_unnamed_24._SC_V6_LP64_OFF64);
pub const _SC_V6_LPBIG_OFFBIG = @enumToInt(enum_unnamed_24._SC_V6_LPBIG_OFFBIG);
pub const _SC_HOST_NAME_MAX = @enumToInt(enum_unnamed_24._SC_HOST_NAME_MAX);
pub const _SC_TRACE = @enumToInt(enum_unnamed_24._SC_TRACE);
pub const _SC_TRACE_EVENT_FILTER = @enumToInt(enum_unnamed_24._SC_TRACE_EVENT_FILTER);
pub const _SC_TRACE_INHERIT = @enumToInt(enum_unnamed_24._SC_TRACE_INHERIT);
pub const _SC_TRACE_LOG = @enumToInt(enum_unnamed_24._SC_TRACE_LOG);
pub const _SC_LEVEL1_ICACHE_SIZE = @enumToInt(enum_unnamed_24._SC_LEVEL1_ICACHE_SIZE);
pub const _SC_LEVEL1_ICACHE_ASSOC = @enumToInt(enum_unnamed_24._SC_LEVEL1_ICACHE_ASSOC);
pub const _SC_LEVEL1_ICACHE_LINESIZE = @enumToInt(enum_unnamed_24._SC_LEVEL1_ICACHE_LINESIZE);
pub const _SC_LEVEL1_DCACHE_SIZE = @enumToInt(enum_unnamed_24._SC_LEVEL1_DCACHE_SIZE);
pub const _SC_LEVEL1_DCACHE_ASSOC = @enumToInt(enum_unnamed_24._SC_LEVEL1_DCACHE_ASSOC);
pub const _SC_LEVEL1_DCACHE_LINESIZE = @enumToInt(enum_unnamed_24._SC_LEVEL1_DCACHE_LINESIZE);
pub const _SC_LEVEL2_CACHE_SIZE = @enumToInt(enum_unnamed_24._SC_LEVEL2_CACHE_SIZE);
pub const _SC_LEVEL2_CACHE_ASSOC = @enumToInt(enum_unnamed_24._SC_LEVEL2_CACHE_ASSOC);
pub const _SC_LEVEL2_CACHE_LINESIZE = @enumToInt(enum_unnamed_24._SC_LEVEL2_CACHE_LINESIZE);
pub const _SC_LEVEL3_CACHE_SIZE = @enumToInt(enum_unnamed_24._SC_LEVEL3_CACHE_SIZE);
pub const _SC_LEVEL3_CACHE_ASSOC = @enumToInt(enum_unnamed_24._SC_LEVEL3_CACHE_ASSOC);
pub const _SC_LEVEL3_CACHE_LINESIZE = @enumToInt(enum_unnamed_24._SC_LEVEL3_CACHE_LINESIZE);
pub const _SC_LEVEL4_CACHE_SIZE = @enumToInt(enum_unnamed_24._SC_LEVEL4_CACHE_SIZE);
pub const _SC_LEVEL4_CACHE_ASSOC = @enumToInt(enum_unnamed_24._SC_LEVEL4_CACHE_ASSOC);
pub const _SC_LEVEL4_CACHE_LINESIZE = @enumToInt(enum_unnamed_24._SC_LEVEL4_CACHE_LINESIZE);
pub const _SC_IPV6 = @enumToInt(enum_unnamed_24._SC_IPV6);
pub const _SC_RAW_SOCKETS = @enumToInt(enum_unnamed_24._SC_RAW_SOCKETS);
pub const _SC_V7_ILP32_OFF32 = @enumToInt(enum_unnamed_24._SC_V7_ILP32_OFF32);
pub const _SC_V7_ILP32_OFFBIG = @enumToInt(enum_unnamed_24._SC_V7_ILP32_OFFBIG);
pub const _SC_V7_LP64_OFF64 = @enumToInt(enum_unnamed_24._SC_V7_LP64_OFF64);
pub const _SC_V7_LPBIG_OFFBIG = @enumToInt(enum_unnamed_24._SC_V7_LPBIG_OFFBIG);
pub const _SC_SS_REPL_MAX = @enumToInt(enum_unnamed_24._SC_SS_REPL_MAX);
pub const _SC_TRACE_EVENT_NAME_MAX = @enumToInt(enum_unnamed_24._SC_TRACE_EVENT_NAME_MAX);
pub const _SC_TRACE_NAME_MAX = @enumToInt(enum_unnamed_24._SC_TRACE_NAME_MAX);
pub const _SC_TRACE_SYS_MAX = @enumToInt(enum_unnamed_24._SC_TRACE_SYS_MAX);
pub const _SC_TRACE_USER_EVENT_MAX = @enumToInt(enum_unnamed_24._SC_TRACE_USER_EVENT_MAX);
pub const _SC_XOPEN_STREAMS = @enumToInt(enum_unnamed_24._SC_XOPEN_STREAMS);
pub const _SC_THREAD_ROBUST_PRIO_INHERIT = @enumToInt(enum_unnamed_24._SC_THREAD_ROBUST_PRIO_INHERIT);
pub const _SC_THREAD_ROBUST_PRIO_PROTECT = @enumToInt(enum_unnamed_24._SC_THREAD_ROBUST_PRIO_PROTECT);
const enum_unnamed_24 = extern enum(c_int) {
    _SC_ARG_MAX = 0,
    _SC_CHILD_MAX = 1,
    _SC_CLK_TCK = 2,
    _SC_NGROUPS_MAX = 3,
    _SC_OPEN_MAX = 4,
    _SC_STREAM_MAX = 5,
    _SC_TZNAME_MAX = 6,
    _SC_JOB_CONTROL = 7,
    _SC_SAVED_IDS = 8,
    _SC_REALTIME_SIGNALS = 9,
    _SC_PRIORITY_SCHEDULING = 10,
    _SC_TIMERS = 11,
    _SC_ASYNCHRONOUS_IO = 12,
    _SC_PRIORITIZED_IO = 13,
    _SC_SYNCHRONIZED_IO = 14,
    _SC_FSYNC = 15,
    _SC_MAPPED_FILES = 16,
    _SC_MEMLOCK = 17,
    _SC_MEMLOCK_RANGE = 18,
    _SC_MEMORY_PROTECTION = 19,
    _SC_MESSAGE_PASSING = 20,
    _SC_SEMAPHORES = 21,
    _SC_SHARED_MEMORY_OBJECTS = 22,
    _SC_AIO_LISTIO_MAX = 23,
    _SC_AIO_MAX = 24,
    _SC_AIO_PRIO_DELTA_MAX = 25,
    _SC_DELAYTIMER_MAX = 26,
    _SC_MQ_OPEN_MAX = 27,
    _SC_MQ_PRIO_MAX = 28,
    _SC_VERSION = 29,
    _SC_PAGESIZE = 30,
    _SC_RTSIG_MAX = 31,
    _SC_SEM_NSEMS_MAX = 32,
    _SC_SEM_VALUE_MAX = 33,
    _SC_SIGQUEUE_MAX = 34,
    _SC_TIMER_MAX = 35,
    _SC_BC_BASE_MAX = 36,
    _SC_BC_DIM_MAX = 37,
    _SC_BC_SCALE_MAX = 38,
    _SC_BC_STRING_MAX = 39,
    _SC_COLL_WEIGHTS_MAX = 40,
    _SC_EQUIV_CLASS_MAX = 41,
    _SC_EXPR_NEST_MAX = 42,
    _SC_LINE_MAX = 43,
    _SC_RE_DUP_MAX = 44,
    _SC_CHARCLASS_NAME_MAX = 45,
    _SC_2_VERSION = 46,
    _SC_2_C_BIND = 47,
    _SC_2_C_DEV = 48,
    _SC_2_FORT_DEV = 49,
    _SC_2_FORT_RUN = 50,
    _SC_2_SW_DEV = 51,
    _SC_2_LOCALEDEF = 52,
    _SC_PII = 53,
    _SC_PII_XTI = 54,
    _SC_PII_SOCKET = 55,
    _SC_PII_INTERNET = 56,
    _SC_PII_OSI = 57,
    _SC_POLL = 58,
    _SC_SELECT = 59,
    _SC_UIO_MAXIOV = 60,
    _SC_IOV_MAX = 60,
    _SC_PII_INTERNET_STREAM = 61,
    _SC_PII_INTERNET_DGRAM = 62,
    _SC_PII_OSI_COTS = 63,
    _SC_PII_OSI_CLTS = 64,
    _SC_PII_OSI_M = 65,
    _SC_T_IOV_MAX = 66,
    _SC_THREADS = 67,
    _SC_THREAD_SAFE_FUNCTIONS = 68,
    _SC_GETGR_R_SIZE_MAX = 69,
    _SC_GETPW_R_SIZE_MAX = 70,
    _SC_LOGIN_NAME_MAX = 71,
    _SC_TTY_NAME_MAX = 72,
    _SC_THREAD_DESTRUCTOR_ITERATIONS = 73,
    _SC_THREAD_KEYS_MAX = 74,
    _SC_THREAD_STACK_MIN = 75,
    _SC_THREAD_THREADS_MAX = 76,
    _SC_THREAD_ATTR_STACKADDR = 77,
    _SC_THREAD_ATTR_STACKSIZE = 78,
    _SC_THREAD_PRIORITY_SCHEDULING = 79,
    _SC_THREAD_PRIO_INHERIT = 80,
    _SC_THREAD_PRIO_PROTECT = 81,
    _SC_THREAD_PROCESS_SHARED = 82,
    _SC_NPROCESSORS_CONF = 83,
    _SC_NPROCESSORS_ONLN = 84,
    _SC_PHYS_PAGES = 85,
    _SC_AVPHYS_PAGES = 86,
    _SC_ATEXIT_MAX = 87,
    _SC_PASS_MAX = 88,
    _SC_XOPEN_VERSION = 89,
    _SC_XOPEN_XCU_VERSION = 90,
    _SC_XOPEN_UNIX = 91,
    _SC_XOPEN_CRYPT = 92,
    _SC_XOPEN_ENH_I18N = 93,
    _SC_XOPEN_SHM = 94,
    _SC_2_CHAR_TERM = 95,
    _SC_2_C_VERSION = 96,
    _SC_2_UPE = 97,
    _SC_XOPEN_XPG2 = 98,
    _SC_XOPEN_XPG3 = 99,
    _SC_XOPEN_XPG4 = 100,
    _SC_CHAR_BIT = 101,
    _SC_CHAR_MAX = 102,
    _SC_CHAR_MIN = 103,
    _SC_INT_MAX = 104,
    _SC_INT_MIN = 105,
    _SC_LONG_BIT = 106,
    _SC_WORD_BIT = 107,
    _SC_MB_LEN_MAX = 108,
    _SC_NZERO = 109,
    _SC_SSIZE_MAX = 110,
    _SC_SCHAR_MAX = 111,
    _SC_SCHAR_MIN = 112,
    _SC_SHRT_MAX = 113,
    _SC_SHRT_MIN = 114,
    _SC_UCHAR_MAX = 115,
    _SC_UINT_MAX = 116,
    _SC_ULONG_MAX = 117,
    _SC_USHRT_MAX = 118,
    _SC_NL_ARGMAX = 119,
    _SC_NL_LANGMAX = 120,
    _SC_NL_MSGMAX = 121,
    _SC_NL_NMAX = 122,
    _SC_NL_SETMAX = 123,
    _SC_NL_TEXTMAX = 124,
    _SC_XBS5_ILP32_OFF32 = 125,
    _SC_XBS5_ILP32_OFFBIG = 126,
    _SC_XBS5_LP64_OFF64 = 127,
    _SC_XBS5_LPBIG_OFFBIG = 128,
    _SC_XOPEN_LEGACY = 129,
    _SC_XOPEN_REALTIME = 130,
    _SC_XOPEN_REALTIME_THREADS = 131,
    _SC_ADVISORY_INFO = 132,
    _SC_BARRIERS = 133,
    _SC_BASE = 134,
    _SC_C_LANG_SUPPORT = 135,
    _SC_C_LANG_SUPPORT_R = 136,
    _SC_CLOCK_SELECTION = 137,
    _SC_CPUTIME = 138,
    _SC_THREAD_CPUTIME = 139,
    _SC_DEVICE_IO = 140,
    _SC_DEVICE_SPECIFIC = 141,
    _SC_DEVICE_SPECIFIC_R = 142,
    _SC_FD_MGMT = 143,
    _SC_FIFO = 144,
    _SC_PIPE = 145,
    _SC_FILE_ATTRIBUTES = 146,
    _SC_FILE_LOCKING = 147,
    _SC_FILE_SYSTEM = 148,
    _SC_MONOTONIC_CLOCK = 149,
    _SC_MULTI_PROCESS = 150,
    _SC_SINGLE_PROCESS = 151,
    _SC_NETWORKING = 152,
    _SC_READER_WRITER_LOCKS = 153,
    _SC_SPIN_LOCKS = 154,
    _SC_REGEXP = 155,
    _SC_REGEX_VERSION = 156,
    _SC_SHELL = 157,
    _SC_SIGNALS = 158,
    _SC_SPAWN = 159,
    _SC_SPORADIC_SERVER = 160,
    _SC_THREAD_SPORADIC_SERVER = 161,
    _SC_SYSTEM_DATABASE = 162,
    _SC_SYSTEM_DATABASE_R = 163,
    _SC_TIMEOUTS = 164,
    _SC_TYPED_MEMORY_OBJECTS = 165,
    _SC_USER_GROUPS = 166,
    _SC_USER_GROUPS_R = 167,
    _SC_2_PBS = 168,
    _SC_2_PBS_ACCOUNTING = 169,
    _SC_2_PBS_LOCATE = 170,
    _SC_2_PBS_MESSAGE = 171,
    _SC_2_PBS_TRACK = 172,
    _SC_SYMLOOP_MAX = 173,
    _SC_STREAMS = 174,
    _SC_2_PBS_CHECKPOINT = 175,
    _SC_V6_ILP32_OFF32 = 176,
    _SC_V6_ILP32_OFFBIG = 177,
    _SC_V6_LP64_OFF64 = 178,
    _SC_V6_LPBIG_OFFBIG = 179,
    _SC_HOST_NAME_MAX = 180,
    _SC_TRACE = 181,
    _SC_TRACE_EVENT_FILTER = 182,
    _SC_TRACE_INHERIT = 183,
    _SC_TRACE_LOG = 184,
    _SC_LEVEL1_ICACHE_SIZE = 185,
    _SC_LEVEL1_ICACHE_ASSOC = 186,
    _SC_LEVEL1_ICACHE_LINESIZE = 187,
    _SC_LEVEL1_DCACHE_SIZE = 188,
    _SC_LEVEL1_DCACHE_ASSOC = 189,
    _SC_LEVEL1_DCACHE_LINESIZE = 190,
    _SC_LEVEL2_CACHE_SIZE = 191,
    _SC_LEVEL2_CACHE_ASSOC = 192,
    _SC_LEVEL2_CACHE_LINESIZE = 193,
    _SC_LEVEL3_CACHE_SIZE = 194,
    _SC_LEVEL3_CACHE_ASSOC = 195,
    _SC_LEVEL3_CACHE_LINESIZE = 196,
    _SC_LEVEL4_CACHE_SIZE = 197,
    _SC_LEVEL4_CACHE_ASSOC = 198,
    _SC_LEVEL4_CACHE_LINESIZE = 199,
    _SC_IPV6 = 235,
    _SC_RAW_SOCKETS = 236,
    _SC_V7_ILP32_OFF32 = 237,
    _SC_V7_ILP32_OFFBIG = 238,
    _SC_V7_LP64_OFF64 = 239,
    _SC_V7_LPBIG_OFFBIG = 240,
    _SC_SS_REPL_MAX = 241,
    _SC_TRACE_EVENT_NAME_MAX = 242,
    _SC_TRACE_NAME_MAX = 243,
    _SC_TRACE_SYS_MAX = 244,
    _SC_TRACE_USER_EVENT_MAX = 245,
    _SC_XOPEN_STREAMS = 246,
    _SC_THREAD_ROBUST_PRIO_INHERIT = 247,
    _SC_THREAD_ROBUST_PRIO_PROTECT = 248,
    _,
};
pub const _CS_PATH = @enumToInt(enum_unnamed_25._CS_PATH);
pub const _CS_V6_WIDTH_RESTRICTED_ENVS = @enumToInt(enum_unnamed_25._CS_V6_WIDTH_RESTRICTED_ENVS);
pub const _CS_GNU_LIBC_VERSION = @enumToInt(enum_unnamed_25._CS_GNU_LIBC_VERSION);
pub const _CS_GNU_LIBPTHREAD_VERSION = @enumToInt(enum_unnamed_25._CS_GNU_LIBPTHREAD_VERSION);
pub const _CS_V5_WIDTH_RESTRICTED_ENVS = @enumToInt(enum_unnamed_25._CS_V5_WIDTH_RESTRICTED_ENVS);
pub const _CS_V7_WIDTH_RESTRICTED_ENVS = @enumToInt(enum_unnamed_25._CS_V7_WIDTH_RESTRICTED_ENVS);
pub const _CS_LFS_CFLAGS = @enumToInt(enum_unnamed_25._CS_LFS_CFLAGS);
pub const _CS_LFS_LDFLAGS = @enumToInt(enum_unnamed_25._CS_LFS_LDFLAGS);
pub const _CS_LFS_LIBS = @enumToInt(enum_unnamed_25._CS_LFS_LIBS);
pub const _CS_LFS_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_LFS_LINTFLAGS);
pub const _CS_LFS64_CFLAGS = @enumToInt(enum_unnamed_25._CS_LFS64_CFLAGS);
pub const _CS_LFS64_LDFLAGS = @enumToInt(enum_unnamed_25._CS_LFS64_LDFLAGS);
pub const _CS_LFS64_LIBS = @enumToInt(enum_unnamed_25._CS_LFS64_LIBS);
pub const _CS_LFS64_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_LFS64_LINTFLAGS);
pub const _CS_XBS5_ILP32_OFF32_CFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_ILP32_OFF32_CFLAGS);
pub const _CS_XBS5_ILP32_OFF32_LDFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_ILP32_OFF32_LDFLAGS);
pub const _CS_XBS5_ILP32_OFF32_LIBS = @enumToInt(enum_unnamed_25._CS_XBS5_ILP32_OFF32_LIBS);
pub const _CS_XBS5_ILP32_OFF32_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_ILP32_OFF32_LINTFLAGS);
pub const _CS_XBS5_ILP32_OFFBIG_CFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_ILP32_OFFBIG_CFLAGS);
pub const _CS_XBS5_ILP32_OFFBIG_LDFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_ILP32_OFFBIG_LDFLAGS);
pub const _CS_XBS5_ILP32_OFFBIG_LIBS = @enumToInt(enum_unnamed_25._CS_XBS5_ILP32_OFFBIG_LIBS);
pub const _CS_XBS5_ILP32_OFFBIG_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_ILP32_OFFBIG_LINTFLAGS);
pub const _CS_XBS5_LP64_OFF64_CFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_LP64_OFF64_CFLAGS);
pub const _CS_XBS5_LP64_OFF64_LDFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_LP64_OFF64_LDFLAGS);
pub const _CS_XBS5_LP64_OFF64_LIBS = @enumToInt(enum_unnamed_25._CS_XBS5_LP64_OFF64_LIBS);
pub const _CS_XBS5_LP64_OFF64_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_LP64_OFF64_LINTFLAGS);
pub const _CS_XBS5_LPBIG_OFFBIG_CFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_LPBIG_OFFBIG_CFLAGS);
pub const _CS_XBS5_LPBIG_OFFBIG_LDFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_LPBIG_OFFBIG_LDFLAGS);
pub const _CS_XBS5_LPBIG_OFFBIG_LIBS = @enumToInt(enum_unnamed_25._CS_XBS5_LPBIG_OFFBIG_LIBS);
pub const _CS_XBS5_LPBIG_OFFBIG_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_XBS5_LPBIG_OFFBIG_LINTFLAGS);
pub const _CS_POSIX_V6_ILP32_OFF32_CFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_ILP32_OFF32_CFLAGS);
pub const _CS_POSIX_V6_ILP32_OFF32_LDFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_ILP32_OFF32_LDFLAGS);
pub const _CS_POSIX_V6_ILP32_OFF32_LIBS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_ILP32_OFF32_LIBS);
pub const _CS_POSIX_V6_ILP32_OFF32_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_ILP32_OFF32_LINTFLAGS);
pub const _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_ILP32_OFFBIG_CFLAGS);
pub const _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS);
pub const _CS_POSIX_V6_ILP32_OFFBIG_LIBS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_ILP32_OFFBIG_LIBS);
pub const _CS_POSIX_V6_ILP32_OFFBIG_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_ILP32_OFFBIG_LINTFLAGS);
pub const _CS_POSIX_V6_LP64_OFF64_CFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_LP64_OFF64_CFLAGS);
pub const _CS_POSIX_V6_LP64_OFF64_LDFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_LP64_OFF64_LDFLAGS);
pub const _CS_POSIX_V6_LP64_OFF64_LIBS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_LP64_OFF64_LIBS);
pub const _CS_POSIX_V6_LP64_OFF64_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_LP64_OFF64_LINTFLAGS);
pub const _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS);
pub const _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS);
pub const _CS_POSIX_V6_LPBIG_OFFBIG_LIBS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_LPBIG_OFFBIG_LIBS);
pub const _CS_POSIX_V6_LPBIG_OFFBIG_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V6_LPBIG_OFFBIG_LINTFLAGS);
pub const _CS_POSIX_V7_ILP32_OFF32_CFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_ILP32_OFF32_CFLAGS);
pub const _CS_POSIX_V7_ILP32_OFF32_LDFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_ILP32_OFF32_LDFLAGS);
pub const _CS_POSIX_V7_ILP32_OFF32_LIBS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_ILP32_OFF32_LIBS);
pub const _CS_POSIX_V7_ILP32_OFF32_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_ILP32_OFF32_LINTFLAGS);
pub const _CS_POSIX_V7_ILP32_OFFBIG_CFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_ILP32_OFFBIG_CFLAGS);
pub const _CS_POSIX_V7_ILP32_OFFBIG_LDFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_ILP32_OFFBIG_LDFLAGS);
pub const _CS_POSIX_V7_ILP32_OFFBIG_LIBS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_ILP32_OFFBIG_LIBS);
pub const _CS_POSIX_V7_ILP32_OFFBIG_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_ILP32_OFFBIG_LINTFLAGS);
pub const _CS_POSIX_V7_LP64_OFF64_CFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_LP64_OFF64_CFLAGS);
pub const _CS_POSIX_V7_LP64_OFF64_LDFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_LP64_OFF64_LDFLAGS);
pub const _CS_POSIX_V7_LP64_OFF64_LIBS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_LP64_OFF64_LIBS);
pub const _CS_POSIX_V7_LP64_OFF64_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_LP64_OFF64_LINTFLAGS);
pub const _CS_POSIX_V7_LPBIG_OFFBIG_CFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_LPBIG_OFFBIG_CFLAGS);
pub const _CS_POSIX_V7_LPBIG_OFFBIG_LDFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_LPBIG_OFFBIG_LDFLAGS);
pub const _CS_POSIX_V7_LPBIG_OFFBIG_LIBS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_LPBIG_OFFBIG_LIBS);
pub const _CS_POSIX_V7_LPBIG_OFFBIG_LINTFLAGS = @enumToInt(enum_unnamed_25._CS_POSIX_V7_LPBIG_OFFBIG_LINTFLAGS);
pub const _CS_V6_ENV = @enumToInt(enum_unnamed_25._CS_V6_ENV);
pub const _CS_V7_ENV = @enumToInt(enum_unnamed_25._CS_V7_ENV);
const enum_unnamed_25 = extern enum(c_int) {
    _CS_PATH = 0,
    _CS_V6_WIDTH_RESTRICTED_ENVS = 1,
    _CS_GNU_LIBC_VERSION = 2,
    _CS_GNU_LIBPTHREAD_VERSION = 3,
    _CS_V5_WIDTH_RESTRICTED_ENVS = 4,
    _CS_V7_WIDTH_RESTRICTED_ENVS = 5,
    _CS_LFS_CFLAGS = 1000,
    _CS_LFS_LDFLAGS = 1001,
    _CS_LFS_LIBS = 1002,
    _CS_LFS_LINTFLAGS = 1003,
    _CS_LFS64_CFLAGS = 1004,
    _CS_LFS64_LDFLAGS = 1005,
    _CS_LFS64_LIBS = 1006,
    _CS_LFS64_LINTFLAGS = 1007,
    _CS_XBS5_ILP32_OFF32_CFLAGS = 1100,
    _CS_XBS5_ILP32_OFF32_LDFLAGS = 1101,
    _CS_XBS5_ILP32_OFF32_LIBS = 1102,
    _CS_XBS5_ILP32_OFF32_LINTFLAGS = 1103,
    _CS_XBS5_ILP32_OFFBIG_CFLAGS = 1104,
    _CS_XBS5_ILP32_OFFBIG_LDFLAGS = 1105,
    _CS_XBS5_ILP32_OFFBIG_LIBS = 1106,
    _CS_XBS5_ILP32_OFFBIG_LINTFLAGS = 1107,
    _CS_XBS5_LP64_OFF64_CFLAGS = 1108,
    _CS_XBS5_LP64_OFF64_LDFLAGS = 1109,
    _CS_XBS5_LP64_OFF64_LIBS = 1110,
    _CS_XBS5_LP64_OFF64_LINTFLAGS = 1111,
    _CS_XBS5_LPBIG_OFFBIG_CFLAGS = 1112,
    _CS_XBS5_LPBIG_OFFBIG_LDFLAGS = 1113,
    _CS_XBS5_LPBIG_OFFBIG_LIBS = 1114,
    _CS_XBS5_LPBIG_OFFBIG_LINTFLAGS = 1115,
    _CS_POSIX_V6_ILP32_OFF32_CFLAGS = 1116,
    _CS_POSIX_V6_ILP32_OFF32_LDFLAGS = 1117,
    _CS_POSIX_V6_ILP32_OFF32_LIBS = 1118,
    _CS_POSIX_V6_ILP32_OFF32_LINTFLAGS = 1119,
    _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS = 1120,
    _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS = 1121,
    _CS_POSIX_V6_ILP32_OFFBIG_LIBS = 1122,
    _CS_POSIX_V6_ILP32_OFFBIG_LINTFLAGS = 1123,
    _CS_POSIX_V6_LP64_OFF64_CFLAGS = 1124,
    _CS_POSIX_V6_LP64_OFF64_LDFLAGS = 1125,
    _CS_POSIX_V6_LP64_OFF64_LIBS = 1126,
    _CS_POSIX_V6_LP64_OFF64_LINTFLAGS = 1127,
    _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS = 1128,
    _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS = 1129,
    _CS_POSIX_V6_LPBIG_OFFBIG_LIBS = 1130,
    _CS_POSIX_V6_LPBIG_OFFBIG_LINTFLAGS = 1131,
    _CS_POSIX_V7_ILP32_OFF32_CFLAGS = 1132,
    _CS_POSIX_V7_ILP32_OFF32_LDFLAGS = 1133,
    _CS_POSIX_V7_ILP32_OFF32_LIBS = 1134,
    _CS_POSIX_V7_ILP32_OFF32_LINTFLAGS = 1135,
    _CS_POSIX_V7_ILP32_OFFBIG_CFLAGS = 1136,
    _CS_POSIX_V7_ILP32_OFFBIG_LDFLAGS = 1137,
    _CS_POSIX_V7_ILP32_OFFBIG_LIBS = 1138,
    _CS_POSIX_V7_ILP32_OFFBIG_LINTFLAGS = 1139,
    _CS_POSIX_V7_LP64_OFF64_CFLAGS = 1140,
    _CS_POSIX_V7_LP64_OFF64_LDFLAGS = 1141,
    _CS_POSIX_V7_LP64_OFF64_LIBS = 1142,
    _CS_POSIX_V7_LP64_OFF64_LINTFLAGS = 1143,
    _CS_POSIX_V7_LPBIG_OFFBIG_CFLAGS = 1144,
    _CS_POSIX_V7_LPBIG_OFFBIG_LDFLAGS = 1145,
    _CS_POSIX_V7_LPBIG_OFFBIG_LIBS = 1146,
    _CS_POSIX_V7_LPBIG_OFFBIG_LINTFLAGS = 1147,
    _CS_V6_ENV = 1148,
    _CS_V7_ENV = 1149,
    _,
};
pub extern fn pathconf(__path: [*c]const u8, __name: c_int) c_long;
pub extern fn fpathconf(__fd: c_int, __name: c_int) c_long;
pub extern fn sysconf(__name: c_int) c_long;
pub extern fn confstr(__name: c_int, __buf: [*c]u8, __len: usize) usize;
pub extern fn getpid() __pid_t;
pub extern fn getppid() __pid_t;
pub extern fn getpgrp() __pid_t;
pub extern fn __getpgid(__pid: __pid_t) __pid_t;
pub extern fn getpgid(__pid: __pid_t) __pid_t;
pub extern fn setpgid(__pid: __pid_t, __pgid: __pid_t) c_int;
pub extern fn setpgrp() c_int;
pub extern fn setsid() __pid_t;
pub extern fn getsid(__pid: __pid_t) __pid_t;
pub extern fn getuid() __uid_t;
pub extern fn geteuid() __uid_t;
pub extern fn getgid() __gid_t;
pub extern fn getegid() __gid_t;
pub extern fn getgroups(__size: c_int, __list: [*c]__gid_t) c_int;
pub extern fn setuid(__uid: __uid_t) c_int;
pub extern fn setreuid(__ruid: __uid_t, __euid: __uid_t) c_int;
pub extern fn seteuid(__uid: __uid_t) c_int;
pub extern fn setgid(__gid: __gid_t) c_int;
pub extern fn setregid(__rgid: __gid_t, __egid: __gid_t) c_int;
pub extern fn setegid(__gid: __gid_t) c_int;
pub extern fn fork() __pid_t;
pub extern fn vfork() c_int;
pub extern fn ttyname(__fd: c_int) [*c]u8;
pub extern fn ttyname_r(__fd: c_int, __buf: [*c]u8, __buflen: usize) c_int;
pub extern fn isatty(__fd: c_int) c_int;
pub extern fn ttyslot() c_int;
pub extern fn link(__from: [*c]const u8, __to: [*c]const u8) c_int;
pub extern fn linkat(__fromfd: c_int, __from: [*c]const u8, __tofd: c_int, __to: [*c]const u8, __flags: c_int) c_int;
pub extern fn symlink(__from: [*c]const u8, __to: [*c]const u8) c_int;
pub extern fn readlink(noalias __path: [*c]const u8, noalias __buf: [*c]u8, __len: usize) isize;
pub extern fn symlinkat(__from: [*c]const u8, __tofd: c_int, __to: [*c]const u8) c_int;
pub extern fn readlinkat(__fd: c_int, noalias __path: [*c]const u8, noalias __buf: [*c]u8, __len: usize) isize;
pub extern fn unlink(__name: [*c]const u8) c_int;
pub extern fn unlinkat(__fd: c_int, __name: [*c]const u8, __flag: c_int) c_int;
pub extern fn rmdir(__path: [*c]const u8) c_int;
pub extern fn tcgetpgrp(__fd: c_int) __pid_t;
pub extern fn tcsetpgrp(__fd: c_int, __pgrp_id: __pid_t) c_int;
pub extern fn getlogin() [*c]u8;
pub extern fn getlogin_r(__name: [*c]u8, __name_len: usize) c_int;
pub extern fn setlogin(__name: [*c]const u8) c_int;
pub extern var optarg: [*c]u8;
pub extern var optind: c_int;
pub extern var opterr: c_int;
pub extern var optopt: c_int;
pub extern fn getopt(___argc: c_int, ___argv: [*c]const [*c]u8, __shortopts: [*c]const u8) c_int;
pub extern fn gethostname(__name: [*c]u8, __len: usize) c_int;
pub extern fn sethostname(__name: [*c]const u8, __len: usize) c_int;
pub extern fn sethostid(__id: c_long) c_int;
pub extern fn getdomainname(__name: [*c]u8, __len: usize) c_int;
pub extern fn setdomainname(__name: [*c]const u8, __len: usize) c_int;
pub extern fn vhangup() c_int;
pub extern fn revoke(__file: [*c]const u8) c_int;
pub extern fn profil(__sample_buffer: [*c]c_ushort, __size: usize, __offset: usize, __scale: c_uint) c_int;
pub extern fn acct(__name: [*c]const u8) c_int;
pub extern fn getusershell() [*c]u8;
pub extern fn endusershell() void;
pub extern fn setusershell() void;
pub extern fn daemon(__nochdir: c_int, __noclose: c_int) c_int;
pub extern fn chroot(__path: [*c]const u8) c_int;
pub extern fn getpass(__prompt: [*c]const u8) [*c]u8;
pub extern fn fsync(__fd: c_int) c_int;
pub extern fn gethostid() c_long;
pub extern fn sync() void;
pub extern fn getpagesize() c_int;
pub extern fn getdtablesize() c_int;
pub extern fn truncate(__file: [*c]const u8, __length: __off_t) c_int;
pub extern fn ftruncate(__fd: c_int, __length: __off_t) c_int;
pub extern fn brk(__addr: ?*c_void) c_int;
pub extern fn sbrk(__delta: isize) ?*c_void;
pub extern fn syscall(__sysno: c_long, ...) c_long;
pub extern fn lockf(__fd: c_int, __cmd: c_int, __len: __off_t) c_int;
pub extern fn fdatasync(__fildes: c_int) c_int;
pub extern fn crypt(__key: [*c]const u8, __salt: [*c]const u8) [*c]u8;
pub extern fn getentropy(__buffer: ?*c_void, __length: usize) c_int;
pub extern fn memcpy(__dest: ?*c_void, __src: ?*const c_void, __n: c_ulong) ?*c_void;
pub extern fn memmove(__dest: ?*c_void, __src: ?*const c_void, __n: c_ulong) ?*c_void;
pub extern fn memccpy(__dest: ?*c_void, __src: ?*const c_void, __c: c_int, __n: c_ulong) ?*c_void;
pub extern fn memset(__s: ?*c_void, __c: c_int, __n: c_ulong) ?*c_void;
pub extern fn memcmp(__s1: ?*const c_void, __s2: ?*const c_void, __n: c_ulong) c_int;
pub extern fn memchr(__s: ?*const c_void, __c: c_int, __n: c_ulong) ?*c_void;
pub extern fn strcpy(__dest: [*c]u8, __src: [*c]const u8) [*c]u8;
pub extern fn strncpy(__dest: [*c]u8, __src: [*c]const u8, __n: c_ulong) [*c]u8;
pub extern fn strcat(__dest: [*c]u8, __src: [*c]const u8) [*c]u8;
pub extern fn strncat(__dest: [*c]u8, __src: [*c]const u8, __n: c_ulong) [*c]u8;
pub extern fn strcmp(__s1: [*c]const u8, __s2: [*c]const u8) c_int;
pub extern fn strncmp(__s1: [*c]const u8, __s2: [*c]const u8, __n: c_ulong) c_int;
pub extern fn strcoll(__s1: [*c]const u8, __s2: [*c]const u8) c_int;
pub extern fn strxfrm(__dest: [*c]u8, __src: [*c]const u8, __n: c_ulong) c_ulong;
pub const struct___locale_data = opaque {};
pub const struct___locale_struct = extern struct {
    __locales: [13]?*struct___locale_data,
    __ctype_b: [*c]const c_ushort,
    __ctype_tolower: [*c]const c_int,
    __ctype_toupper: [*c]const c_int,
    __names: [13][*c]const u8,
};
pub const __locale_t = [*c]struct___locale_struct;
pub const locale_t = __locale_t;
pub extern fn strcoll_l(__s1: [*c]const u8, __s2: [*c]const u8, __l: locale_t) c_int;
pub extern fn strxfrm_l(__dest: [*c]u8, __src: [*c]const u8, __n: usize, __l: locale_t) usize;
pub extern fn strdup(__s: [*c]const u8) [*c]u8;
pub extern fn strndup(__string: [*c]const u8, __n: c_ulong) [*c]u8;
pub extern fn strchr(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn strrchr(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn strcspn(__s: [*c]const u8, __reject: [*c]const u8) c_ulong;
pub extern fn strspn(__s: [*c]const u8, __accept: [*c]const u8) c_ulong;
pub extern fn strpbrk(__s: [*c]const u8, __accept: [*c]const u8) [*c]u8;
pub extern fn strstr(__haystack: [*c]const u8, __needle: [*c]const u8) [*c]u8;
pub extern fn strtok(__s: [*c]u8, __delim: [*c]const u8) [*c]u8;
pub extern fn __strtok_r(noalias __s: [*c]u8, noalias __delim: [*c]const u8, noalias __save_ptr: [*c][*c]u8) [*c]u8;
pub extern fn strtok_r(noalias __s: [*c]u8, noalias __delim: [*c]const u8, noalias __save_ptr: [*c][*c]u8) [*c]u8;
pub extern fn strlen(__s: [*c]const u8) c_ulong;
pub extern fn strnlen(__string: [*c]const u8, __maxlen: usize) usize;
pub extern fn strerror(__errnum: c_int) [*c]u8;
pub extern fn strerror_r(__errnum: c_int, __buf: [*c]u8, __buflen: usize) c_int;
pub extern fn strerror_l(__errnum: c_int, __l: locale_t) [*c]u8;
pub extern fn bcmp(__s1: ?*const c_void, __s2: ?*const c_void, __n: c_ulong) c_int;
pub extern fn bcopy(__src: ?*const c_void, __dest: ?*c_void, __n: usize) void;
pub extern fn bzero(__s: ?*c_void, __n: c_ulong) void;
pub extern fn index(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn rindex(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn ffs(__i: c_int) c_int;
pub extern fn ffsl(__l: c_long) c_int;
pub extern fn ffsll(__ll: c_longlong) c_int;
pub extern fn strcasecmp(__s1: [*c]const u8, __s2: [*c]const u8) c_int;
pub extern fn strncasecmp(__s1: [*c]const u8, __s2: [*c]const u8, __n: c_ulong) c_int;
pub extern fn strcasecmp_l(__s1: [*c]const u8, __s2: [*c]const u8, __loc: locale_t) c_int;
pub extern fn strncasecmp_l(__s1: [*c]const u8, __s2: [*c]const u8, __n: usize, __loc: locale_t) c_int;
pub extern fn explicit_bzero(__s: ?*c_void, __n: usize) void;
pub extern fn strsep(noalias __stringp: [*c][*c]u8, noalias __delim: [*c]const u8) [*c]u8;
pub extern fn strsignal(__sig: c_int) [*c]u8;
pub extern fn __stpcpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8) [*c]u8;
pub extern fn stpcpy(__dest: [*c]u8, __src: [*c]const u8) [*c]u8;
pub extern fn __stpncpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8, __n: usize) [*c]u8;
pub extern fn stpncpy(__dest: [*c]u8, __src: [*c]const u8, __n: c_ulong) [*c]u8;
pub const struct_stat = extern struct {
    st_dev: __dev_t,
    st_ino: __ino_t,
    st_nlink: __nlink_t,
    st_mode: __mode_t,
    st_uid: __uid_t,
    st_gid: __gid_t,
    __pad0: c_int,
    st_rdev: __dev_t,
    st_size: __off_t,
    st_blksize: __blksize_t,
    st_blocks: __blkcnt_t,
    st_atim: struct_timespec,
    st_mtim: struct_timespec,
    st_ctim: struct_timespec,
    __glibc_reserved: [3]__syscall_slong_t,
};
pub fn stat(noalias arg___path: [*c]const u8, noalias arg___statbuf: [*c]struct_stat) callconv(.C) c_int {
    var __path = arg___path;
    var __statbuf = arg___statbuf;
    return __xstat(@as(c_int, 1), __path, __statbuf);
}
pub fn fstat(arg___fd: c_int, arg___statbuf: [*c]struct_stat) callconv(.C) c_int {
    var __fd = arg___fd;
    var __statbuf = arg___statbuf;
    return __fxstat(@as(c_int, 1), __fd, __statbuf);
}
pub fn fstatat(arg___fd: c_int, noalias arg___filename: [*c]const u8, noalias arg___statbuf: [*c]struct_stat, arg___flag: c_int) callconv(.C) c_int {
    var __fd = arg___fd;
    var __filename = arg___filename;
    var __statbuf = arg___statbuf;
    var __flag = arg___flag;
    return __fxstatat(@as(c_int, 1), __fd, __filename, __statbuf, __flag);
}
pub fn lstat(noalias arg___path: [*c]const u8, noalias arg___statbuf: [*c]struct_stat) callconv(.C) c_int {
    var __path = arg___path;
    var __statbuf = arg___statbuf;
    return __lxstat(@as(c_int, 1), __path, __statbuf);
}
pub extern fn chmod(__file: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn lchmod(__file: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn fchmod(__fd: c_int, __mode: __mode_t) c_int;
pub extern fn fchmodat(__fd: c_int, __file: [*c]const u8, __mode: __mode_t, __flag: c_int) c_int;
pub extern fn umask(__mask: __mode_t) __mode_t;
pub extern fn mkdir(__path: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn mkdirat(__fd: c_int, __path: [*c]const u8, __mode: __mode_t) c_int;
pub fn mknod(arg___path: [*c]const u8, arg___mode: __mode_t, arg___dev: __dev_t) callconv(.C) c_int {
    var __path = arg___path;
    var __mode = arg___mode;
    var __dev = arg___dev;
    return __xmknod(@as(c_int, 0), __path, __mode, &__dev);
}
pub fn mknodat(arg___fd: c_int, arg___path: [*c]const u8, arg___mode: __mode_t, arg___dev: __dev_t) callconv(.C) c_int {
    var __fd = arg___fd;
    var __path = arg___path;
    var __mode = arg___mode;
    var __dev = arg___dev;
    return __xmknodat(@as(c_int, 0), __fd, __path, __mode, &__dev);
}
pub extern fn mkfifo(__path: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn mkfifoat(__fd: c_int, __path: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn utimensat(__fd: c_int, __path: [*c]const u8, __times: [*c]const struct_timespec, __flags: c_int) c_int;
pub extern fn futimens(__fd: c_int, __times: [*c]const struct_timespec) c_int;
pub extern fn __fxstat(__ver: c_int, __fildes: c_int, __stat_buf: [*c]struct_stat) c_int;
pub extern fn __xstat(__ver: c_int, __filename: [*c]const u8, __stat_buf: [*c]struct_stat) c_int;
pub extern fn __lxstat(__ver: c_int, __filename: [*c]const u8, __stat_buf: [*c]struct_stat) c_int;
pub extern fn __fxstatat(__ver: c_int, __fildes: c_int, __filename: [*c]const u8, __stat_buf: [*c]struct_stat, __flag: c_int) c_int;
pub extern fn __xmknod(__ver: c_int, __path: [*c]const u8, __mode: __mode_t, __dev: [*c]__dev_t) c_int;
pub extern fn __xmknodat(__ver: c_int, __fd: c_int, __path: [*c]const u8, __mode: __mode_t, __dev: [*c]__dev_t) c_int;
const union_unnamed_26 = extern union {
    __size: [32]u8,
    __align: c_long,
};
pub const sem_t = union_unnamed_26;
pub extern fn sem_init(__sem: [*c]sem_t, __pshared: c_int, __value: c_uint) c_int;
pub extern fn sem_destroy(__sem: [*c]sem_t) c_int;
pub extern fn sem_open(__name: [*c]const u8, __oflag: c_int, ...) [*c]sem_t;
pub extern fn sem_close(__sem: [*c]sem_t) c_int;
pub extern fn sem_unlink(__name: [*c]const u8) c_int;
pub extern fn sem_wait(__sem: [*c]sem_t) c_int;
pub extern fn sem_timedwait(noalias __sem: [*c]sem_t, noalias __abstime: [*c]const struct_timespec) c_int;
pub extern fn sem_trywait(__sem: [*c]sem_t) c_int;
pub extern fn sem_post(__sem: [*c]sem_t) c_int;
pub extern fn sem_getvalue(noalias __sem: [*c]sem_t, noalias __sval: [*c]c_int) c_int;
pub const file_handle = c_int;
pub const process_handle = pid_t;
pub const sem_handle = [*c]sem_t;
pub extern fn arcan_timemillis() c_longlong;
pub extern fn arcan_sem_post(sem: sem_handle) c_int;
pub extern fn arcan_fetchhandle(insock: c_int, block: bool) file_handle;
pub extern fn arcan_pushhandle(fd: c_int, channel: c_int) bool;
pub extern fn arcan_sem_wait(sem: sem_handle) c_int;
pub extern fn arcan_sem_trywait(sem: sem_handle) c_int;
pub extern fn arcan_fdscan(listout: [*c][*c]c_int) c_int;
pub const struct_arcan_shmif_page = // /usr/include/arcan/shmif/arcan_shmif_control.h:1007:34: warning: unsupported type: 'Atomic'
    opaque {}; // /usr/include/arcan/shmif/arcan_shmif_control.h:969:8: warning: struct demoted to opaque type - unable to translate type of field abufused
const union_unnamed_27 = extern union {
    vidp: [*c]shmif_pixel,
    floatp: [*c]f32,
    vidb: [*c]u8,
};
const union_unnamed_28 = extern union {
    audp: [*c]shmif_asample,
    audb: [*c]u8,
};
pub const struct_arcan_shmif_region = extern struct {
    x1: u16,
    x2: u16,
    y1: u16,
    y2: u16,
};
pub const struct_shmif_hidden = opaque {};
pub const struct_shmif_ext_hidden = opaque {};
pub const struct_arcan_shmif_cont = extern struct {
    addr: [*c]struct_arcan_shmif_page,
    unnamed_0: union_unnamed_27,
    unnamed_1: union_unnamed_28,
    oflow_cookie: i16,
    abufused: u16,
    abufpos: u16,
    abufsize: u16,
    abufcount: u16,
    abuf_cnt: u8,
    epipe: file_handle,
    shmh: file_handle,
    shmsize: usize,
    vsem: sem_handle,
    asem: sem_handle,
    esem: sem_handle,
    w: usize,
    h: usize,
    stride: usize,
    pitch: usize,
    adata: u32,
    samplerate: usize,
    hints: u8,
    dirty: struct_arcan_shmif_region,
    cookie: u64,
    user: ?*c_void,
    priv: ?*struct_shmif_hidden,
    privext: ?*struct_shmif_ext_hidden,
    segment_token: u32,
    vbufsize: usize,
};
const union_unnamed_31 = extern union {
    io: arcan_ioevent,
    vid: arcan_vevent,
    aud: arcan_aevent,
    sys: arcan_sevent,
    tgt: arcan_tgtevent,
    fsrv: arcan_fsrvevent,
    ext: arcan_extevent,
};
const struct_unnamed_30 = extern struct {
    unnamed_0: union_unnamed_31,
    category: u8,
};
const union_unnamed_29 = extern union {
    unnamed_0: struct_unnamed_30,
    pad: [128]u8,
};
pub const struct_arcan_event = extern struct {
    unnamed_0: union_unnamed_29,
};
pub extern fn arcan_shmif_poll([*c]struct_arcan_shmif_cont, dst: [*c]struct_arcan_event) c_int;
pub extern fn arcan_shmif_wait([*c]struct_arcan_shmif_cont, dst: [*c]struct_arcan_event) c_int;
pub extern fn arcan_shmif_wait_timed([*c]struct_arcan_shmif_cont, time_us: [*c]c_uint, dst: [*c]struct_arcan_event) c_int;
pub extern fn arcan_shmif_acquireloop([*c]struct_arcan_shmif_cont, [*c]struct_arcan_event, [*c][*c]struct_arcan_event, [*c]isize) bool;
pub extern fn arcan_shmif_descrevent([*c]struct_arcan_event) bool;
pub extern fn arcan_shmif_guid([*c]struct_arcan_shmif_cont, [*c]u64) void;
pub extern fn arcan_shmif_defimpl(newchild: [*c]struct_arcan_shmif_cont, type: c_int, pref: ?*c_void) void;
pub extern fn arcan_shmif_enqueue([*c]struct_arcan_shmif_cont, [*c]const struct_arcan_event) c_int;
pub extern fn arcan_shmif_tryenqueue([*c]struct_arcan_shmif_cont, [*c]const struct_arcan_event) c_int;
pub extern fn arcan_shmif_eventstr(aev: [*c]struct_arcan_event, dbuf: [*c]u8, dsz: usize) [*c]const u8;
pub extern fn arcan_shmif_eventpack(aev: [*c]const struct_arcan_event, dbuf: [*c]u8, dbuf_sz: usize) isize;
pub extern fn arcan_shmif_eventunpack(buf: [*c]const u8, buf_sz: usize, out: [*c]struct_arcan_event) isize;
pub extern fn arcan_shmif_resolve_connpath(key: [*c]const u8, dst: [*c]u8, dsz: usize) c_int;
pub extern fn arcan_shmif_segkind(con: [*c]struct_arcan_shmif_cont) c_int;
pub extern fn arcan_shmif_cookie() u64;
pub const struct_arg_arr = extern struct {
    key: [*c]u8,
    value: [*c]u8,
};
pub extern fn arg_unpack([*c]const u8) [*c]struct_arg_arr;
pub extern fn arg_lookup(arr: [*c]struct_arg_arr, key: [*c]const u8, ind: c_ushort, found: [*c][*c]const u8) bool;
pub extern fn arg_cleanup([*c]struct_arg_arr) void;
pub const struct_shmif_privsep_node = extern struct {
    path: [*c]const u8,
    perm: [*c]const u8,
};
pub extern fn arcan_shmif_privsep(C: [*c]struct_arcan_shmif_cont, pledge: [*c]const u8, [*c][*c]struct_shmif_privsep_node, opts: c_int) void;
pub extern fn arcan_shmif_dupfd(fd: c_int, dstnum: c_int, blocking: bool) c_int;
pub extern fn arcan_shmif_last_words(cont: [*c]struct_arcan_shmif_cont, msg: [*c]const u8) void;
pub extern fn arcan_shmif_handover_exec(cont: [*c]struct_arcan_shmif_cont, ev: struct_arcan_event, path: [*c]const u8, argv: [*c]const [*c]u8, env: [*c]const [*c]u8, detach: c_int) pid_t;
pub extern fn arcan_shmif_dirty([*c]struct_arcan_shmif_cont, x1: usize, y1: usize, x2: usize, y2: usize, fl: c_int) c_int;
pub extern fn arcan_shmif_deadline([*c]struct_arcan_shmif_cont, last_cost: c_uint, jitter: [*c]c_int, errc: [*c]c_int) c_int;
pub extern fn arcan_shmif_bgcopy([*c]struct_arcan_shmif_cont, fdin: c_int, fdout: c_int, sigfd: c_int, flags: c_int) void;
pub extern fn arcan_shmif_mousestate_setup(con: [*c]struct_arcan_shmif_cont, relative: bool, state: [*c]u8) void;
pub extern fn arcan_shmif_mousestate([*c]struct_arcan_shmif_cont, state: [*c]u8, inev: [*c]struct_arcan_event, out_x: [*c]c_int, out_y: [*c]c_int) bool;
pub const EVENT_SYSTEM = @enumToInt(enum_ARCAN_EVENT_CATEGORY.EVENT_SYSTEM);
pub const EVENT_IO = @enumToInt(enum_ARCAN_EVENT_CATEGORY.EVENT_IO);
pub const EVENT_VIDEO = @enumToInt(enum_ARCAN_EVENT_CATEGORY.EVENT_VIDEO);
pub const EVENT_AUDIO = @enumToInt(enum_ARCAN_EVENT_CATEGORY.EVENT_AUDIO);
pub const EVENT_TARGET = @enumToInt(enum_ARCAN_EVENT_CATEGORY.EVENT_TARGET);
pub const EVENT_FSRV = @enumToInt(enum_ARCAN_EVENT_CATEGORY.EVENT_FSRV);
pub const EVENT_EXTERNAL = @enumToInt(enum_ARCAN_EVENT_CATEGORY.EVENT_EXTERNAL);
pub const EVENT_LIM = @enumToInt(enum_ARCAN_EVENT_CATEGORY.EVENT_LIM);
pub const enum_ARCAN_EVENT_CATEGORY = extern enum(c_int) {
    EVENT_SYSTEM = 1,
    EVENT_IO = 2,
    EVENT_VIDEO = 4,
    EVENT_AUDIO = 8,
    EVENT_TARGET = 16,
    EVENT_FSRV = 32,
    EVENT_EXTERNAL = 64,
    EVENT_LIM = 2147483647,
    _,
};
pub const SEGID_UNKNOWN = @enumToInt(enum_ARCAN_SEGID.SEGID_UNKNOWN);
pub const SEGID_LWA = @enumToInt(enum_ARCAN_SEGID.SEGID_LWA);
pub const SEGID_NETWORK_SERVER = @enumToInt(enum_ARCAN_SEGID.SEGID_NETWORK_SERVER);
pub const SEGID_NETWORK_CLIENT = @enumToInt(enum_ARCAN_SEGID.SEGID_NETWORK_CLIENT);
pub const SEGID_MEDIA = @enumToInt(enum_ARCAN_SEGID.SEGID_MEDIA);
pub const SEGID_TERMINAL = @enumToInt(enum_ARCAN_SEGID.SEGID_TERMINAL);
pub const SEGID_REMOTING = @enumToInt(enum_ARCAN_SEGID.SEGID_REMOTING);
pub const SEGID_ENCODER = @enumToInt(enum_ARCAN_SEGID.SEGID_ENCODER);
pub const SEGID_SENSOR = @enumToInt(enum_ARCAN_SEGID.SEGID_SENSOR);
pub const SEGID_GAME = @enumToInt(enum_ARCAN_SEGID.SEGID_GAME);
pub const SEGID_APPLICATION = @enumToInt(enum_ARCAN_SEGID.SEGID_APPLICATION);
pub const SEGID_BROWSER = @enumToInt(enum_ARCAN_SEGID.SEGID_BROWSER);
pub const SEGID_VM = @enumToInt(enum_ARCAN_SEGID.SEGID_VM);
pub const SEGID_HMD_SBS = @enumToInt(enum_ARCAN_SEGID.SEGID_HMD_SBS);
pub const SEGID_HMD_L = @enumToInt(enum_ARCAN_SEGID.SEGID_HMD_L);
pub const SEGID_HMD_R = @enumToInt(enum_ARCAN_SEGID.SEGID_HMD_R);
pub const SEGID_POPUP = @enumToInt(enum_ARCAN_SEGID.SEGID_POPUP);
pub const SEGID_ICON = @enumToInt(enum_ARCAN_SEGID.SEGID_ICON);
pub const SEGID_TITLEBAR = @enumToInt(enum_ARCAN_SEGID.SEGID_TITLEBAR);
pub const SEGID_CURSOR = @enumToInt(enum_ARCAN_SEGID.SEGID_CURSOR);
pub const SEGID_ACCESSIBILITY = @enumToInt(enum_ARCAN_SEGID.SEGID_ACCESSIBILITY);
pub const SEGID_CLIPBOARD = @enumToInt(enum_ARCAN_SEGID.SEGID_CLIPBOARD);
pub const SEGID_CLIPBOARD_PASTE = @enumToInt(enum_ARCAN_SEGID.SEGID_CLIPBOARD_PASTE);
pub const SEGID_WIDGET = @enumToInt(enum_ARCAN_SEGID.SEGID_WIDGET);
pub const SEGID_TUI = @enumToInt(enum_ARCAN_SEGID.SEGID_TUI);
pub const SEGID_SERVICE = @enumToInt(enum_ARCAN_SEGID.SEGID_SERVICE);
pub const SEGID_BRIDGE_X11 = @enumToInt(enum_ARCAN_SEGID.SEGID_BRIDGE_X11);
pub const SEGID_BRIDGE_WAYLAND = @enumToInt(enum_ARCAN_SEGID.SEGID_BRIDGE_WAYLAND);
pub const SEGID_HANDOVER = @enumToInt(enum_ARCAN_SEGID.SEGID_HANDOVER);
pub const SEGID_DEBUG = @enumToInt(enum_ARCAN_SEGID.SEGID_DEBUG);
pub const SEGID_LIM = @enumToInt(enum_ARCAN_SEGID.SEGID_LIM);
pub const enum_ARCAN_SEGID = extern enum(c_int) {
    SEGID_UNKNOWN = 0,
    SEGID_LWA = 1,
    SEGID_NETWORK_SERVER = 2,
    SEGID_NETWORK_CLIENT = 3,
    SEGID_MEDIA = 4,
    SEGID_TERMINAL = 5,
    SEGID_REMOTING = 6,
    SEGID_ENCODER = 7,
    SEGID_SENSOR = 8,
    SEGID_GAME = 9,
    SEGID_APPLICATION = 10,
    SEGID_BROWSER = 11,
    SEGID_VM = 12,
    SEGID_HMD_SBS = 13,
    SEGID_HMD_L = 14,
    SEGID_HMD_R = 15,
    SEGID_POPUP = 16,
    SEGID_ICON = 17,
    SEGID_TITLEBAR = 18,
    SEGID_CURSOR = 19,
    SEGID_ACCESSIBILITY = 20,
    SEGID_CLIPBOARD = 21,
    SEGID_CLIPBOARD_PASTE = 22,
    SEGID_WIDGET = 23,
    SEGID_TUI = 24,
    SEGID_SERVICE = 25,
    SEGID_BRIDGE_X11 = 26,
    SEGID_BRIDGE_WAYLAND = 27,
    SEGID_HANDOVER = 28,
    SEGID_DEBUG = 255,
    SEGID_LIM = 2147483647,
    _,
};
pub const TARGET_COMMAND_EXIT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_EXIT);
pub const TARGET_COMMAND_FRAMESKIP = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_FRAMESKIP);
pub const TARGET_COMMAND_STEPFRAME = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_STEPFRAME);
pub const TARGET_COMMAND_COREOPT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_COREOPT);
pub const TARGET_COMMAND_STORE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_STORE);
pub const TARGET_COMMAND_RESTORE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_RESTORE);
pub const TARGET_COMMAND_BCHUNK_IN = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_BCHUNK_IN);
pub const TARGET_COMMAND_BCHUNK_OUT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_BCHUNK_OUT);
pub const TARGET_COMMAND_RESET = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_RESET);
pub const TARGET_COMMAND_PAUSE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_PAUSE);
pub const TARGET_COMMAND_UNPAUSE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_UNPAUSE);
pub const TARGET_COMMAND_SEEKTIME = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_SEEKTIME);
pub const TARGET_COMMAND_SEEKCONTENT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_SEEKCONTENT);
pub const TARGET_COMMAND_DISPLAYHINT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_DISPLAYHINT);
pub const TARGET_COMMAND_SETIODEV = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_SETIODEV);
pub const TARGET_COMMAND_STREAMSET = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_STREAMSET);
pub const TARGET_COMMAND_ATTENUATE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_ATTENUATE);
pub const TARGET_COMMAND_AUDDELAY = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_AUDDELAY);
pub const TARGET_COMMAND_NEWSEGMENT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_NEWSEGMENT);
pub const TARGET_COMMAND_REQFAIL = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_REQFAIL);
pub const TARGET_COMMAND_BUFFER_FAIL = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_BUFFER_FAIL);
pub const TARGET_COMMAND_DEVICE_NODE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_DEVICE_NODE);
pub const TARGET_COMMAND_GRAPHMODE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_GRAPHMODE);
pub const TARGET_COMMAND_MESSAGE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_MESSAGE);
pub const TARGET_COMMAND_FONTHINT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_FONTHINT);
pub const TARGET_COMMAND_GEOHINT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_GEOHINT);
pub const TARGET_COMMAND_OUTPUTHINT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_OUTPUTHINT);
pub const TARGET_COMMAND_ACTIVATE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_ACTIVATE);
pub const TARGET_COMMAND_DEVICESTATE = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_DEVICESTATE);
pub const TARGET_COMMAND_LIMIT = @enumToInt(enum_ARCAN_TARGET_COMMAND.TARGET_COMMAND_LIMIT);
pub const enum_ARCAN_TARGET_COMMAND = extern enum(c_int) {
    TARGET_COMMAND_EXIT = 1,
    TARGET_COMMAND_FRAMESKIP = 2,
    TARGET_COMMAND_STEPFRAME = 3,
    TARGET_COMMAND_COREOPT = 4,
    TARGET_COMMAND_STORE = 5,
    TARGET_COMMAND_RESTORE = 6,
    TARGET_COMMAND_BCHUNK_IN = 7,
    TARGET_COMMAND_BCHUNK_OUT = 8,
    TARGET_COMMAND_RESET = 9,
    TARGET_COMMAND_PAUSE = 10,
    TARGET_COMMAND_UNPAUSE = 11,
    TARGET_COMMAND_SEEKTIME = 12,
    TARGET_COMMAND_SEEKCONTENT = 13,
    TARGET_COMMAND_DISPLAYHINT = 14,
    TARGET_COMMAND_SETIODEV = 15,
    TARGET_COMMAND_STREAMSET = 16,
    TARGET_COMMAND_ATTENUATE = 17,
    TARGET_COMMAND_AUDDELAY = 18,
    TARGET_COMMAND_NEWSEGMENT = 19,
    TARGET_COMMAND_REQFAIL = 20,
    TARGET_COMMAND_BUFFER_FAIL = 21,
    TARGET_COMMAND_DEVICE_NODE = 22,
    TARGET_COMMAND_GRAPHMODE = 23,
    TARGET_COMMAND_MESSAGE = 24,
    TARGET_COMMAND_FONTHINT = 25,
    TARGET_COMMAND_GEOHINT = 26,
    TARGET_COMMAND_OUTPUTHINT = 27,
    TARGET_COMMAND_ACTIVATE = 28,
    TARGET_COMMAND_DEVICESTATE = 29,
    TARGET_COMMAND_LIMIT = 2147483647,
    _,
};
pub const EVENT_EXTERNAL_MESSAGE = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_MESSAGE);
pub const EVENT_EXTERNAL_COREOPT = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_COREOPT);
pub const EVENT_EXTERNAL_IDENT = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_IDENT);
pub const EVENT_EXTERNAL_FAILURE = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_FAILURE);
pub const EVENT_EXTERNAL_BUFFERSTREAM = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_BUFFERSTREAM);
pub const EVENT_EXTERNAL_FRAMESTATUS = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_FRAMESTATUS);
pub const EVENT_EXTERNAL_STREAMINFO = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_STREAMINFO);
pub const EVENT_EXTERNAL_STREAMSTATUS = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_STREAMSTATUS);
pub const EVENT_EXTERNAL_STATESIZE = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_STATESIZE);
pub const EVENT_EXTERNAL_FLUSHAUD = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_FLUSHAUD);
pub const EVENT_EXTERNAL_SEGREQ = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_SEGREQ);
pub const EVENT_EXTERNAL_CURSORHINT = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_CURSORHINT);
pub const EVENT_EXTERNAL_VIEWPORT = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_VIEWPORT);
pub const EVENT_EXTERNAL_CONTENT = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_CONTENT);
pub const EVENT_EXTERNAL_LABELHINT = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_LABELHINT);
pub const EVENT_EXTERNAL_REGISTER = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_REGISTER);
pub const EVENT_EXTERNAL_ALERT = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_ALERT);
pub const EVENT_EXTERNAL_CLOCKREQ = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_CLOCKREQ);
pub const EVENT_EXTERNAL_BCHUNKSTATE = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_BCHUNKSTATE);
pub const EVENT_EXTERNAL_PRIVDROP = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_PRIVDROP);
pub const EVENT_EXTERNAL_INPUTMASK = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_INPUTMASK);
pub const EVENT_EXTERNAL_ULIM = @enumToInt(enum_ARCAN_EVENT_EXTERNAL.EVENT_EXTERNAL_ULIM);
pub const enum_ARCAN_EVENT_EXTERNAL = extern enum(c_int) {
    EVENT_EXTERNAL_MESSAGE = 0,
    EVENT_EXTERNAL_COREOPT = 1,
    EVENT_EXTERNAL_IDENT = 2,
    EVENT_EXTERNAL_FAILURE = 3,
    EVENT_EXTERNAL_BUFFERSTREAM = 4,
    EVENT_EXTERNAL_FRAMESTATUS = 5,
    EVENT_EXTERNAL_STREAMINFO = 6,
    EVENT_EXTERNAL_STREAMSTATUS = 7,
    EVENT_EXTERNAL_STATESIZE = 8,
    EVENT_EXTERNAL_FLUSHAUD = 9,
    EVENT_EXTERNAL_SEGREQ = 10,
    EVENT_EXTERNAL_CURSORHINT = 12,
    EVENT_EXTERNAL_VIEWPORT = 13,
    EVENT_EXTERNAL_CONTENT = 14,
    EVENT_EXTERNAL_LABELHINT = 15,
    EVENT_EXTERNAL_REGISTER = 16,
    EVENT_EXTERNAL_ALERT = 17,
    EVENT_EXTERNAL_CLOCKREQ = 18,
    EVENT_EXTERNAL_BCHUNKSTATE = 19,
    EVENT_EXTERNAL_PRIVDROP = 20,
    EVENT_EXTERNAL_INPUTMASK = 21,
    EVENT_EXTERNAL_ULIM = 2147483647,
    _,
};
pub const TARGET_SKIP_AUTO = @enumToInt(enum_ARCAN_TARGET_SKIPMODE.TARGET_SKIP_AUTO);
pub const TARGET_SKIP_NONE = @enumToInt(enum_ARCAN_TARGET_SKIPMODE.TARGET_SKIP_NONE);
pub const TARGET_SKIP_REVERSE = @enumToInt(enum_ARCAN_TARGET_SKIPMODE.TARGET_SKIP_REVERSE);
pub const TARGET_SKIP_ROLLBACK = @enumToInt(enum_ARCAN_TARGET_SKIPMODE.TARGET_SKIP_ROLLBACK);
pub const TARGET_SKIP_STEP = @enumToInt(enum_ARCAN_TARGET_SKIPMODE.TARGET_SKIP_STEP);
pub const TARGET_SKIP_FASTFWD = @enumToInt(enum_ARCAN_TARGET_SKIPMODE.TARGET_SKIP_FASTFWD);
pub const TARGET_SKIP_ULIM = @enumToInt(enum_ARCAN_TARGET_SKIPMODE.TARGET_SKIP_ULIM);
pub const enum_ARCAN_TARGET_SKIPMODE = extern enum(c_int) {
    TARGET_SKIP_AUTO = 0,
    TARGET_SKIP_NONE = -1,
    TARGET_SKIP_REVERSE = -2,
    TARGET_SKIP_ROLLBACK = -3,
    TARGET_SKIP_STEP = 1,
    TARGET_SKIP_FASTFWD = 10,
    TARGET_SKIP_ULIM = 2147483647,
    _,
};
pub const EVENT_IO_BUTTON = @enumToInt(enum_ARCAN_EVENT_IO.EVENT_IO_BUTTON);
pub const EVENT_IO_AXIS_MOVE = @enumToInt(enum_ARCAN_EVENT_IO.EVENT_IO_AXIS_MOVE);
pub const EVENT_IO_TOUCH = @enumToInt(enum_ARCAN_EVENT_IO.EVENT_IO_TOUCH);
pub const EVENT_IO_STATUS = @enumToInt(enum_ARCAN_EVENT_IO.EVENT_IO_STATUS);
pub const EVENT_IO_EYES = @enumToInt(enum_ARCAN_EVENT_IO.EVENT_IO_EYES);
pub const EVENT_IO_ULIM = @enumToInt(enum_ARCAN_EVENT_IO.EVENT_IO_ULIM);
pub const enum_ARCAN_EVENT_IO = extern enum(c_int) {
    EVENT_IO_BUTTON = 0,
    EVENT_IO_AXIS_MOVE = 1,
    EVENT_IO_TOUCH = 2,
    EVENT_IO_STATUS = 3,
    EVENT_IO_EYES = 4,
    EVENT_IO_ULIM = 2147483647,
    _,
};
pub const MBTN_LEFT_IND = @enumToInt(enum_ARCAN_MBTN_IMAP.MBTN_LEFT_IND);
pub const MBTN_RIGHT_IND = @enumToInt(enum_ARCAN_MBTN_IMAP.MBTN_RIGHT_IND);
pub const MBTN_MIDDLE_IND = @enumToInt(enum_ARCAN_MBTN_IMAP.MBTN_MIDDLE_IND);
pub const MBTN_WHEEL_UP_IND = @enumToInt(enum_ARCAN_MBTN_IMAP.MBTN_WHEEL_UP_IND);
pub const MBTN_WHEEL_DOWN_IND = @enumToInt(enum_ARCAN_MBTN_IMAP.MBTN_WHEEL_DOWN_IND);
pub const enum_ARCAN_MBTN_IMAP = extern enum(c_int) {
    MBTN_LEFT_IND = 1,
    MBTN_RIGHT_IND = 2,
    MBTN_MIDDLE_IND = 3,
    MBTN_WHEEL_UP_IND = 4,
    MBTN_WHEEL_DOWN_IND = 5,
    _,
};
pub const EVENT_IDEVKIND_KEYBOARD = @enumToInt(enum_ARCAN_EVENT_IDEVKIND.EVENT_IDEVKIND_KEYBOARD);
pub const EVENT_IDEVKIND_MOUSE = @enumToInt(enum_ARCAN_EVENT_IDEVKIND.EVENT_IDEVKIND_MOUSE);
pub const EVENT_IDEVKIND_GAMEDEV = @enumToInt(enum_ARCAN_EVENT_IDEVKIND.EVENT_IDEVKIND_GAMEDEV);
pub const EVENT_IDEVKIND_TOUCHDISP = @enumToInt(enum_ARCAN_EVENT_IDEVKIND.EVENT_IDEVKIND_TOUCHDISP);
pub const EVENT_IDEVKIND_LEDCTRL = @enumToInt(enum_ARCAN_EVENT_IDEVKIND.EVENT_IDEVKIND_LEDCTRL);
pub const EVENT_IDEVKIND_EYETRACKER = @enumToInt(enum_ARCAN_EVENT_IDEVKIND.EVENT_IDEVKIND_EYETRACKER);
pub const EVENT_IDEVKIND_STATUS = @enumToInt(enum_ARCAN_EVENT_IDEVKIND.EVENT_IDEVKIND_STATUS);
pub const EVENT_IDEVKIND_ULIM = @enumToInt(enum_ARCAN_EVENT_IDEVKIND.EVENT_IDEVKIND_ULIM);
pub const enum_ARCAN_EVENT_IDEVKIND = extern enum(c_int) {
    EVENT_IDEVKIND_KEYBOARD = 1,
    EVENT_IDEVKIND_MOUSE = 2,
    EVENT_IDEVKIND_GAMEDEV = 4,
    EVENT_IDEVKIND_TOUCHDISP = 8,
    EVENT_IDEVKIND_LEDCTRL = 16,
    EVENT_IDEVKIND_EYETRACKER = 32,
    EVENT_IDEVKIND_STATUS = 64,
    EVENT_IDEVKIND_ULIM = 2147483647,
    _,
};
pub const EVENT_IDEV_ADDED = @enumToInt(enum_ARCAN_IDEV_STATUS.EVENT_IDEV_ADDED);
pub const EVENT_IDEV_REMOVED = @enumToInt(enum_ARCAN_IDEV_STATUS.EVENT_IDEV_REMOVED);
pub const EVENT_IDEV_BLOCKED = @enumToInt(enum_ARCAN_IDEV_STATUS.EVENT_IDEV_BLOCKED);
pub const enum_ARCAN_IDEV_STATUS = extern enum(c_int) {
    EVENT_IDEV_ADDED = 0,
    EVENT_IDEV_REMOVED = 1,
    EVENT_IDEV_BLOCKED = 2,
    _,
};
pub const EVENT_IDATATYPE_ANALOG = @enumToInt(enum_ARCAN_EVENT_IDATATYPE.EVENT_IDATATYPE_ANALOG);
pub const EVENT_IDATATYPE_DIGITAL = @enumToInt(enum_ARCAN_EVENT_IDATATYPE.EVENT_IDATATYPE_DIGITAL);
pub const EVENT_IDATATYPE_TRANSLATED = @enumToInt(enum_ARCAN_EVENT_IDATATYPE.EVENT_IDATATYPE_TRANSLATED);
pub const EVENT_IDATATYPE_TOUCH = @enumToInt(enum_ARCAN_EVENT_IDATATYPE.EVENT_IDATATYPE_TOUCH);
pub const EVENT_IDATATYPE_EYES = @enumToInt(enum_ARCAN_EVENT_IDATATYPE.EVENT_IDATATYPE_EYES);
pub const EVENT_IDATATYPE_ULIM = @enumToInt(enum_ARCAN_EVENT_IDATATYPE.EVENT_IDATATYPE_ULIM);
pub const enum_ARCAN_EVENT_IDATATYPE = extern enum(c_int) {
    EVENT_IDATATYPE_ANALOG = 1,
    EVENT_IDATATYPE_DIGITAL = 2,
    EVENT_IDATATYPE_TRANSLATED = 4,
    EVENT_IDATATYPE_TOUCH = 8,
    EVENT_IDATATYPE_EYES = 16,
    EVENT_IDATATYPE_ULIM = 2147483647,
    _,
};
pub const EVENT_VIDEO_EXPIRE = @enumToInt(enum_ARCAN_EVENT_VIDEO.EVENT_VIDEO_EXPIRE);
pub const EVENT_VIDEO_CHAIN_OVER = @enumToInt(enum_ARCAN_EVENT_VIDEO.EVENT_VIDEO_CHAIN_OVER);
pub const EVENT_VIDEO_DISPLAY_RESET = @enumToInt(enum_ARCAN_EVENT_VIDEO.EVENT_VIDEO_DISPLAY_RESET);
pub const EVENT_VIDEO_DISPLAY_ADDED = @enumToInt(enum_ARCAN_EVENT_VIDEO.EVENT_VIDEO_DISPLAY_ADDED);
pub const EVENT_VIDEO_DISPLAY_REMOVED = @enumToInt(enum_ARCAN_EVENT_VIDEO.EVENT_VIDEO_DISPLAY_REMOVED);
pub const EVENT_VIDEO_DISPLAY_CHANGED = @enumToInt(enum_ARCAN_EVENT_VIDEO.EVENT_VIDEO_DISPLAY_CHANGED);
pub const EVENT_VIDEO_ASYNCHIMAGE_LOADED = @enumToInt(enum_ARCAN_EVENT_VIDEO.EVENT_VIDEO_ASYNCHIMAGE_LOADED);
pub const EVENT_VIDEO_ASYNCHIMAGE_FAILED = @enumToInt(enum_ARCAN_EVENT_VIDEO.EVENT_VIDEO_ASYNCHIMAGE_FAILED);
pub const enum_ARCAN_EVENT_VIDEO = extern enum(c_int) {
    EVENT_VIDEO_EXPIRE,
    EVENT_VIDEO_CHAIN_OVER,
    EVENT_VIDEO_DISPLAY_RESET,
    EVENT_VIDEO_DISPLAY_ADDED,
    EVENT_VIDEO_DISPLAY_REMOVED,
    EVENT_VIDEO_DISPLAY_CHANGED,
    EVENT_VIDEO_ASYNCHIMAGE_LOADED,
    EVENT_VIDEO_ASYNCHIMAGE_FAILED,
    _,
};
pub const EVENT_SYSTEM_EXIT = @enumToInt(enum_ARCAN_EVENT_SYSTEM.EVENT_SYSTEM_EXIT);
pub const enum_ARCAN_EVENT_SYSTEM = extern enum(c_int) {
    EVENT_SYSTEM_EXIT = 0,
    _,
};
pub const EVENT_AUDIO_PLAYBACK_FINISHED = @enumToInt(enum_ARCAN_EVENT_AUDIO.EVENT_AUDIO_PLAYBACK_FINISHED);
pub const EVENT_AUDIO_PLAYBACK_ABORTED = @enumToInt(enum_ARCAN_EVENT_AUDIO.EVENT_AUDIO_PLAYBACK_ABORTED);
pub const EVENT_AUDIO_BUFFER_UNDERRUN = @enumToInt(enum_ARCAN_EVENT_AUDIO.EVENT_AUDIO_BUFFER_UNDERRUN);
pub const EVENT_AUDIO_PITCH_TRANSFORMATION_FINISHED = @enumToInt(enum_ARCAN_EVENT_AUDIO.EVENT_AUDIO_PITCH_TRANSFORMATION_FINISHED);
pub const EVENT_AUDIO_GAIN_TRANSFORMATION_FINISHED = @enumToInt(enum_ARCAN_EVENT_AUDIO.EVENT_AUDIO_GAIN_TRANSFORMATION_FINISHED);
pub const EVENT_AUDIO_OBJECT_GONE = @enumToInt(enum_ARCAN_EVENT_AUDIO.EVENT_AUDIO_OBJECT_GONE);
pub const EVENT_AUDIO_INVALID_OBJECT_REFERENCED = @enumToInt(enum_ARCAN_EVENT_AUDIO.EVENT_AUDIO_INVALID_OBJECT_REFERENCED);
pub const enum_ARCAN_EVENT_AUDIO = extern enum(c_int) {
    EVENT_AUDIO_PLAYBACK_FINISHED = 0,
    EVENT_AUDIO_PLAYBACK_ABORTED = 1,
    EVENT_AUDIO_BUFFER_UNDERRUN = 2,
    EVENT_AUDIO_PITCH_TRANSFORMATION_FINISHED = 3,
    EVENT_AUDIO_GAIN_TRANSFORMATION_FINISHED = 4,
    EVENT_AUDIO_OBJECT_GONE = 5,
    EVENT_AUDIO_INVALID_OBJECT_REFERENCED = 6,
    _,
};
pub const EVENT_FSRV_EXTCONN = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_EXTCONN);
pub const EVENT_FSRV_RESIZED = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_RESIZED);
pub const EVENT_FSRV_TERMINATED = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_TERMINATED);
pub const EVENT_FSRV_DROPPEDFRAME = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_DROPPEDFRAME);
pub const EVENT_FSRV_DELIVEREDFRAME = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_DELIVEREDFRAME);
pub const EVENT_FSRV_PREROLL = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_PREROLL);
pub const EVENT_FSRV_APROTO = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_APROTO);
pub const EVENT_FSRV_GAMMARAMP = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_GAMMARAMP);
pub const EVENT_FSRV_ADDVRLIMB = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_ADDVRLIMB);
pub const EVENT_FSRV_LOSTVRLIMB = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_LOSTVRLIMB);
pub const EVENT_FSRV_IONESTED = @enumToInt(enum_ARCAN_EVENT_FSRV.EVENT_FSRV_IONESTED);
pub const enum_ARCAN_EVENT_FSRV = extern enum(c_int) {
    EVENT_FSRV_EXTCONN,
    EVENT_FSRV_RESIZED,
    EVENT_FSRV_TERMINATED,
    EVENT_FSRV_DROPPEDFRAME,
    EVENT_FSRV_DELIVEREDFRAME,
    EVENT_FSRV_PREROLL,
    EVENT_FSRV_APROTO,
    EVENT_FSRV_GAMMARAMP,
    EVENT_FSRV_ADDVRLIMB,
    EVENT_FSRV_LOSTVRLIMB,
    EVENT_FSRV_IONESTED,
    _,
};
const struct_unnamed_32 = extern struct {
    active: u8,
};
const struct_unnamed_33 = extern struct {
    gotrel: i8,
    nvalues: u8,
    axisval: [4]i16,
};
const struct_unnamed_34 = extern struct {
    active: u8,
    x: i16,
    y: i16,
    pressure: f32,
    size: f32,
    tilt_x: u16,
    tilt_y: u16,
    tool: u8,
};
const struct_unnamed_35 = extern struct {
    head_pos: [3]f32,
    head_ang: [3]f32,
    gaze_x1: f32,
    gaze_y1: f32,
    gaze_x2: f32,
    gaze_y2: f32,
    blink_left: u8,
    blink_right: u8,
    present: u8,
};
const struct_unnamed_36 = extern struct {
    action: u8,
    devkind: u8,
    devref: u16,
    domain: u8,
};
const struct_unnamed_37 = extern struct {
    utf8: [5]u8,
    active: u8,
    scancode: u8,
    keysym: u32,
    modifiers: u16,
};
pub const union_arcan_ioevent_data = extern union {
    digital: struct_unnamed_32,
    analog: struct_unnamed_33,
    touch: struct_unnamed_34,
    eyes: struct_unnamed_35,
    status: struct_unnamed_36,
    translated: struct_unnamed_37,
};
pub const arcan_ioevent_data = union_arcan_ioevent_data;
pub const ARCAN_IOFL_GESTURE = @enumToInt(enum_ARCAN_EVENT_IOFLAG.ARCAN_IOFL_GESTURE);
pub const ARCAN_IOFL_ENTER = @enumToInt(enum_ARCAN_EVENT_IOFLAG.ARCAN_IOFL_ENTER);
pub const ARCAN_IOFL_LEAVE = @enumToInt(enum_ARCAN_EVENT_IOFLAG.ARCAN_IOFL_LEAVE);
pub const enum_ARCAN_EVENT_IOFLAG = extern enum(c_int) {
    ARCAN_IOFL_GESTURE = 1,
    ARCAN_IOFL_ENTER = 2,
    ARCAN_IOFL_LEAVE = 4,
    _,
};
const struct_unnamed_40 = extern struct {
    devid: u16,
    subid: u16,
};
const union_unnamed_39 = extern union {
    unnamed_0: struct_unnamed_40,
    id: [2]u16,
    iid: u32,
};
const struct_unnamed_38 = extern struct {
    kind: enum_ARCAN_EVENT_IO,
    devkind: enum_ARCAN_EVENT_IDEVKIND,
    datatype: enum_ARCAN_EVENT_IDATATYPE,
    label: [16]u8,
    flags: u8,
    unnamed_0: union_unnamed_39,
    pts: u64,
    input: arcan_ioevent_data,
};
pub const arcan_ioevent = struct_unnamed_38;
const struct_unnamed_43 = extern struct {
    width: i16,
    height: i16,
    flags: c_int,
    vppcm: f32,
    displayid: c_int,
    ledctrl: c_int,
    ledid: c_int,
    cardid: c_int,
};
const union_unnamed_42 = extern union {
    unnamed_0: struct_unnamed_43,
    slot: c_int,
};
const struct_unnamed_41 = extern struct {
    kind: enum_ARCAN_EVENT_VIDEO,
    source: i64,
    unnamed_0: union_unnamed_42,
    data: isize,
};
pub const arcan_vevent = struct_unnamed_41;
const struct_unnamed_46 = extern struct {
    audio: i32,
    width: usize,
    height: usize,
    xofs: usize,
    yofs: usize,
    glsource: i8,
    pts: u64,
    counter: u64,
    message: [32]u8,
};
const struct_unnamed_47 = extern struct {
    ident: [32]u8,
    descriptor: i64,
};
const struct_unnamed_48 = extern struct {
    aproto: c_int,
};
const struct_unnamed_49 = extern struct {
    limb: c_uint,
};
const union_unnamed_45 = extern union {
    unnamed_0: struct_unnamed_46,
    unnamed_1: struct_unnamed_47,
    unnamed_2: struct_unnamed_48,
    unnamed_3: struct_unnamed_49,
    input: arcan_ioevent,
};
const struct_unnamed_44 = extern struct {
    kind: enum_ARCAN_EVENT_FSRV,
    unnamed_0: union_unnamed_45,
    video: i64,
    otag: isize,
};
pub const arcan_fsrvevent = struct_unnamed_44;
const union_unnamed_51 = extern union {
    otag: isize,
    data: [*c]usize,
};
const struct_unnamed_50 = extern struct {
    kind: enum_ARCAN_EVENT_AUDIO,
    source: i32,
    unnamed_0: union_unnamed_51,
};
pub const arcan_aevent = struct_unnamed_50;
const struct_unnamed_53 = extern struct {
    hitag: u32,
    lotag: u32,
};
const struct_unnamed_54 = extern struct {
    dyneval_msg: [*c]u8,
};
const union_unnamed_52 = extern union {
    tagv: struct_unnamed_53,
    mesg: struct_unnamed_54,
    message: [64]u8,
};
pub const struct_arcan_sevent = extern struct {
    kind: enum_ARCAN_EVENT_SYSTEM,
    errcode: c_int,
    unnamed_0: union_unnamed_52,
};
pub const arcan_sevent = struct_arcan_sevent;
const union_unnamed_55 = extern union {
    uiv: u32,
    iv: i32,
    fv: f32,
    cv: [4]u8,
};
const union_unnamed_56 = extern union {
    message: [78]u8,
    bmessage: [78]u8,
    timestamp: u64,
};
pub const struct_arcan_tgtevent = extern struct {
    kind: enum_ARCAN_TARGET_COMMAND,
    ioevs: [8]union_unnamed_55,
    code: c_int,
    unnamed_0: union_unnamed_56,
};
pub const arcan_tgtevent = struct_arcan_tgtevent;
const struct_unnamed_58 = extern struct {
    data: [78]u8,
    multipart: u8,
};
const struct_unnamed_59 = extern struct {
    index: u8,
    type: u8,
    data: [77]u8,
};
const struct_unnamed_60 = extern struct {
    size: u32,
    type: u32,
};
const struct_unnamed_61 = extern struct {
    id: u8,
    keysym: u32,
    active: u8,
};
const struct_unnamed_62 = extern struct {
    rate: u32,
    dynamic: u8,
    once: u8,
    id: u32,
};
const struct_unnamed_63 = extern struct {
    size: u64,
    input: u8,
    hint: u8,
    stream: u8,
    extensions: [68]u8,
};
const struct_unnamed_64 = extern struct {
    external: u8,
    sandboxed: u8,
    networked: u8,
};
const struct_unnamed_65 = extern struct {
    device: u32,
    types: u32,
};
const struct_unnamed_66 = extern struct {
    label: [16]u8,
    initial: u16,
    descr: [53]u8,
    vsym: [5]u8,
    subv: u16,
    idatatype: u8,
    modifiers: u16,
};
const struct_unnamed_67 = extern struct {
    stride: u32,
    format: u32,
    offset: u32,
    mod_hi: u32,
    mod_lo: u32,
    gpuid: u32,
    width: u32,
    height: u32,
    left: u8,
};
const struct_unnamed_68 = extern struct {
    streamid: u8,
    datakind: u8,
    langid: [4]u8,
};
const struct_unnamed_69 = extern struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    parent: u32,
    border: [4]u8,
    edge: u8,
    order: i8,
    embedded: u8,
    invisible: u8,
    focus: u8,
    anchor_edge: u8,
    anchor_pos: u8,
};
const struct_unnamed_70 = extern struct {
    x_pos: f32,
    x_sz: f32,
    y_pos: f32,
    y_sz: f32,
    width: f32,
    height: f32,
    cell_w: u8,
    cell_h: u8,
    min_w: u32,
    min_h: u32,
    max_w: u32,
    max_h: u32,
};
const struct_unnamed_71 = extern struct {
    id: u32,
    width: u16,
    height: u16,
    xofs: i16,
    yofs: i16,
    dir: u8,
    hints: u8,
    kind: enum_ARCAN_SEGID,
};
const struct_unnamed_72 = extern struct {
    title: [64]u8,
    kind: enum_ARCAN_SEGID,
    guid: [2]u64,
};
const struct_unnamed_73 = extern struct {
    timestr: [9]u8,
    timelim: [9]u8,
    completion: f32,
    streaming: u8,
    frameno: u32,
};
const struct_unnamed_74 = extern struct {
    framenumber: u32,
    pts: u64,
    acquired: u64,
    fhint: f32,
};
const union_unnamed_57 = extern union {
    message: struct_unnamed_58,
    coreopt: struct_unnamed_59,
    stateinf: struct_unnamed_60,
    key: struct_unnamed_61,
    clock: struct_unnamed_62,
    bchunk: struct_unnamed_63,
    privdrop: struct_unnamed_64,
    inputmask: struct_unnamed_65,
    labelhint: struct_unnamed_66,
    bstream: struct_unnamed_67,
    streaminf: struct_unnamed_68,
    viewport: struct_unnamed_69,
    content: struct_unnamed_70,
    segreq: struct_unnamed_71,
    registr: struct_unnamed_72,
    streamstat: struct_unnamed_73,
    framestatus: struct_unnamed_74,
};
pub const struct_arcan_extevent = extern struct {
    kind: enum_ARCAN_EVENT_EXTERNAL,
    source: i64,
    unnamed_0: union_unnamed_57,
};
pub const arcan_extevent = struct_arcan_extevent;
pub const arcan_event = struct_arcan_event;
pub const ARKMOD_NONE = @enumToInt(enum_unnamed_75.ARKMOD_NONE);
pub const ARKMOD_LSHIFT = @enumToInt(enum_unnamed_75.ARKMOD_LSHIFT);
pub const ARKMOD_RSHIFT = @enumToInt(enum_unnamed_75.ARKMOD_RSHIFT);
pub const ARKMOD_LCTRL = @enumToInt(enum_unnamed_75.ARKMOD_LCTRL);
pub const ARKMOD_RCTRL = @enumToInt(enum_unnamed_75.ARKMOD_RCTRL);
pub const ARKMOD_LALT = @enumToInt(enum_unnamed_75.ARKMOD_LALT);
pub const ARKMOD_RALT = @enumToInt(enum_unnamed_75.ARKMOD_RALT);
pub const ARKMOD_LMETA = @enumToInt(enum_unnamed_75.ARKMOD_LMETA);
pub const ARKMOD_RMETA = @enumToInt(enum_unnamed_75.ARKMOD_RMETA);
pub const ARKMOD_NUM = @enumToInt(enum_unnamed_75.ARKMOD_NUM);
pub const ARKMOD_CAPS = @enumToInt(enum_unnamed_75.ARKMOD_CAPS);
pub const ARKMOD_MODE = @enumToInt(enum_unnamed_75.ARKMOD_MODE);
pub const ARKMOD_REPEAT = @enumToInt(enum_unnamed_75.ARKMOD_REPEAT);
pub const ARKMOD_LIMIT = @enumToInt(enum_unnamed_75.ARKMOD_LIMIT);
const enum_unnamed_75 = extern enum(c_int) {
    ARKMOD_NONE = 0,
    ARKMOD_LSHIFT = 1,
    ARKMOD_RSHIFT = 2,
    ARKMOD_LCTRL = 64,
    ARKMOD_RCTRL = 128,
    ARKMOD_LALT = 256,
    ARKMOD_RALT = 512,
    ARKMOD_LMETA = 1024,
    ARKMOD_RMETA = 2048,
    ARKMOD_NUM = 4096,
    ARKMOD_CAPS = 8192,
    ARKMOD_MODE = 16384,
    ARKMOD_REPEAT = 32768,
    ARKMOD_LIMIT = 2147483647,
    _,
};
pub const key_modifiers = enum_unnamed_75;
const struct_unnamed_76 = extern struct {
    killswitch: [*c]volatile u8,
    handle: sem_handle,
};
pub const struct_arcan_evctx = extern struct {
    c_ticks: i32,
    mask_cat_inp: u32,
    state_fl: u32,
    exit_code: c_int,
    drain: ?fn ([*c]arcan_event, c_int) callconv(.C) void,
    eventbuf_sz: u8,
    eventbuf: [*c]arcan_event,
    front: [*c]volatile u8,
    back: [*c]volatile u8,
    local: i8,
    synch: struct_unnamed_76,
};
pub const arcan_evctx = struct_arcan_evctx;
pub const ARCAN_SHMIF_QUEUE_SZ: c_int = 127;
pub const shmif_asample = i16;
pub const ARCAN_SHMIF_SAMPLERATE: c_int = 48000;
pub const ARCAN_SHMIF_ACHANNELS: c_int = 2;
pub const ARCAN_SHMPAGE_MAXW: c_int = 8192;
pub const ARCAN_SHMPAGE_MAXH: c_int = 8192;
pub const shmif_ppcm_default: f32 = @floatCast(f32, 37.795276);
pub const shmif_pixel = u32;
pub const ARCAN_SHMPAGE_MAX_SZ: c_int = 104857600;
pub const ARCAN_SHMPAGE_START_SZ: c_int = 2014088;
pub const ARCAN_SHMPAGE_ALIGN: c_int = 64;
pub const SHMIF_INPUT = @enumToInt(enum_arcan_shmif_type.SHMIF_INPUT);
pub const SHMIF_OUTPUT = @enumToInt(enum_arcan_shmif_type.SHMIF_OUTPUT);
pub const enum_arcan_shmif_type = extern enum(c_int) {
    SHMIF_INPUT = 1,
    SHMIF_OUTPUT = 2,
    _,
};
pub const SHMIF_SIGVID = @enumToInt(enum_arcan_shmif_sigmask.SHMIF_SIGVID);
pub const SHMIF_SIGAUD = @enumToInt(enum_arcan_shmif_sigmask.SHMIF_SIGAUD);
pub const SHMIF_SIGBLK_FORCE = @enumToInt(enum_arcan_shmif_sigmask.SHMIF_SIGBLK_FORCE);
pub const SHMIF_SIGBLK_NONE = @enumToInt(enum_arcan_shmif_sigmask.SHMIF_SIGBLK_NONE);
pub const enum_arcan_shmif_sigmask = extern enum(c_int) {
    SHMIF_SIGVID = 1,
    SHMIF_SIGAUD = 2,
    SHMIF_SIGBLK_FORCE = 0,
    SHMIF_SIGBLK_NONE = 4,
    _,
};
const struct_unnamed_77 = extern struct {
    fd: c_int,
    type: c_int,
    hinting: c_int,
    size_mm: f32,
};
const struct_unnamed_78 = extern struct {
    fg: [3]u8,
    bg: [3]u8,
    fg_set: bool,
    bg_set: bool,
};
pub const struct_arcan_shmif_initial = extern struct {
    fonts: [4]struct_unnamed_77,
    density: f32,
    rgb_layout: c_int,
    display_width_px: usize,
    display_height_px: usize,
    rate: u16,
    lang: [4]u8,
    country: [4]u8,
    text_lang: [4]u8,
    latitude: f32,
    longitude: f32,
    elevation: f32,
    render_node: c_int,
    timezone: c_int,
    colors: [36]struct_unnamed_78,
};
pub const shmif_trigger_hook = ?fn ([*c]struct_arcan_shmif_cont) callconv(.C) enum_arcan_shmif_sigmask;
pub const shmif_reset_hook = ?fn (c_int, ?*c_void) callconv(.C) void;
pub const SHMIF_NOFLAGS = @enumToInt(enum_ARCAN_FLAGS.SHMIF_NOFLAGS);
pub const SHMIF_DONT_UNLINK = @enumToInt(enum_ARCAN_FLAGS.SHMIF_DONT_UNLINK);
pub const SHMIF_DISABLE_GUARD = @enumToInt(enum_ARCAN_FLAGS.SHMIF_DISABLE_GUARD);
pub const SHMIF_ACQUIRE_FATALFAIL = @enumToInt(enum_ARCAN_FLAGS.SHMIF_ACQUIRE_FATALFAIL);
pub const SHMIF_FATALFAIL_FUNC = @enumToInt(enum_ARCAN_FLAGS.SHMIF_FATALFAIL_FUNC);
pub const SHMIF_CONNECT_LOOP = @enumToInt(enum_ARCAN_FLAGS.SHMIF_CONNECT_LOOP);
pub const SHMIF_MANUAL_PAUSE = @enumToInt(enum_ARCAN_FLAGS.SHMIF_MANUAL_PAUSE);
pub const SHMIF_NOAUTO_RECONNECT = @enumToInt(enum_ARCAN_FLAGS.SHMIF_NOAUTO_RECONNECT);
pub const SHMIF_MIGRATE_SUBSEGMENTS = @enumToInt(enum_ARCAN_FLAGS.SHMIF_MIGRATE_SUBSEGMENTS);
pub const SHMIF_NOACTIVATE_RESIZE = @enumToInt(enum_ARCAN_FLAGS.SHMIF_NOACTIVATE_RESIZE);
pub const SHMIF_NOACTIVATE = @enumToInt(enum_ARCAN_FLAGS.SHMIF_NOACTIVATE);
pub const SHMIF_NOREGISTER = @enumToInt(enum_ARCAN_FLAGS.SHMIF_NOREGISTER);
pub const enum_ARCAN_FLAGS = extern enum(c_int) {
    SHMIF_NOFLAGS = 0,
    SHMIF_DONT_UNLINK = 1,
    SHMIF_DISABLE_GUARD = 2,
    SHMIF_ACQUIRE_FATALFAIL = 4,
    SHMIF_FATALFAIL_FUNC = 8,
    SHMIF_CONNECT_LOOP = 16,
    SHMIF_MANUAL_PAUSE = 32,
    SHMIF_NOAUTO_RECONNECT = 64,
    SHMIF_MIGRATE_SUBSEGMENTS = 128,
    SHMIF_NOACTIVATE_RESIZE = 256,
    SHMIF_NOACTIVATE = 512,
    SHMIF_NOREGISTER = 1024,
    _,
};
pub extern fn arcan_shmif_open(type: enum_ARCAN_SEGID, flags: enum_ARCAN_FLAGS, [*c][*c]struct_arg_arr) struct_arcan_shmif_cont;
pub extern fn arcan_shmif_args([*c]struct_arcan_shmif_cont) [*c]struct_arg_arr;
pub const struct_shmif_open_ext = extern struct {
    type: enum_ARCAN_SEGID,
    title: [*c]const u8,
    ident: [*c]const u8,
    guid: [2]u64,
};
pub extern fn arcan_shmif_open_ext(flags: enum_ARCAN_FLAGS, [*c][*c]struct_arg_arr, struct_shmif_open_ext, ext_sz: usize) struct_arcan_shmif_cont;
pub extern fn arcan_shmif_unlink(c: [*c]struct_arcan_shmif_cont) void;
pub extern fn arcan_shmif_segment_key(c: [*c]struct_arcan_shmif_cont) [*c]const u8;
pub extern fn arcan_shmif_initial([*c]struct_arcan_shmif_cont, [*c][*c]struct_arcan_shmif_initial) usize;
pub extern fn arcan_shmif_connect(connpath: [*c]const u8, connkey: [*c]const u8, conn_ch: [*c]file_handle) [*c]u8;
pub const SHMIF_MIGRATE_OK = @enumToInt(enum_shmif_migrate_status.SHMIF_MIGRATE_OK);
pub const SHMIF_MIGRATE_BADARG = @enumToInt(enum_shmif_migrate_status.SHMIF_MIGRATE_BADARG);
pub const SHMIF_MIGRATE_NOCON = @enumToInt(enum_shmif_migrate_status.SHMIF_MIGRATE_NOCON);
pub const SHMIF_MIGRATE_TRANSFER_FAIL = @enumToInt(enum_shmif_migrate_status.SHMIF_MIGRATE_TRANSFER_FAIL);
pub const SHMIF_MIGRATE_BAD_SOURCE = @enumToInt(enum_shmif_migrate_status.SHMIF_MIGRATE_BAD_SOURCE);
pub const enum_shmif_migrate_status = extern enum(c_int) {
    SHMIF_MIGRATE_OK = 0,
    SHMIF_MIGRATE_BADARG = -1,
    SHMIF_MIGRATE_NOCON = -2,
    SHMIF_MIGRATE_TRANSFER_FAIL = -4,
    SHMIF_MIGRATE_BAD_SOURCE = -8,
    _,
};
pub extern fn arcan_shmif_migrate(cont: [*c]struct_arcan_shmif_cont, newpath: [*c]const u8, key: [*c]const u8) enum_shmif_migrate_status;
pub extern fn arcan_shmif_acquire(parent: [*c]struct_arcan_shmif_cont, shmkey: [*c]const u8, type: c_int, flags: c_int, ...) struct_arcan_shmif_cont;
pub extern fn arcan_shmif_mapav(addr: ?*struct_arcan_shmif_page, vbuf: [*c][*c]shmif_pixel, vbufc: usize, vbuf_sz: usize, abuf: [*c][*c]shmif_asample, abufc: usize, abuf_sz: usize) usize;
pub extern fn arcan_shmif_vbufsz(meta: c_int, hints: u8, w: usize, h: usize, rows: usize, cols: usize) usize;
pub extern fn arcan_shmif_signalhook([*c]struct_arcan_shmif_cont, mask: enum_arcan_shmif_sigmask, shmif_trigger_hook, data: ?*c_void) shmif_trigger_hook;
pub extern fn arcan_shmif_setevqs(?*struct_arcan_shmif_page, sem_handle, inevq: [*c]arcan_evctx, outevq: [*c]arcan_evctx, parent: bool) void;
pub extern fn arcan_shmif_resize([*c]struct_arcan_shmif_cont, width: c_uint, height: c_uint) bool;
pub const SHMIF_META_NONE = @enumToInt(enum_shmif_ext_meta.SHMIF_META_NONE);
pub const SHMIF_META_CM = @enumToInt(enum_shmif_ext_meta.SHMIF_META_CM);
pub const SHMIF_META_HDRF16 = @enumToInt(enum_shmif_ext_meta.SHMIF_META_HDRF16);
pub const SHMIF_META_VOBJ = @enumToInt(enum_shmif_ext_meta.SHMIF_META_VOBJ);
pub const SHMIF_META_VR = @enumToInt(enum_shmif_ext_meta.SHMIF_META_VR);
pub const SHMIF_META_LDEF = @enumToInt(enum_shmif_ext_meta.SHMIF_META_LDEF);
pub const SHMIF_META_VENC = @enumToInt(enum_shmif_ext_meta.SHMIF_META_VENC);
pub const enum_shmif_ext_meta = extern enum(c_int) {
    SHMIF_META_NONE = 0,
    SHMIF_META_CM = 2,
    SHMIF_META_HDRF16 = 4,
    SHMIF_META_VOBJ = 8,
    SHMIF_META_VR = 16,
    SHMIF_META_LDEF = 32,
    SHMIF_META_VENC = 64,
    _,
};
pub const struct_shmif_resize_ext = extern struct {
    meta: u32,
    abuf_sz: usize,
    abuf_cnt: isize,
    samplerate: isize,
    vbuf_cnt: isize,
    rows: usize,
    cols: usize,
    nops: usize,
    op_fm: usize,
};
pub extern fn arcan_shmif_resize_ext([*c]struct_arcan_shmif_cont, width: c_uint, height: c_uint, struct_shmif_resize_ext) bool;
pub extern fn arcan_shmif_drop([*c]struct_arcan_shmif_cont) void;
pub extern fn arcan_shmif_signal([*c]struct_arcan_shmif_cont, enum_arcan_shmif_sigmask) c_uint;
pub extern fn arcan_shmif_signalhandle(ctx: [*c]struct_arcan_shmif_cont, mask: c_int, handle: c_int, stride: usize, format: c_int, ...) c_uint;
pub extern fn arcan_shmif_handle_permitted(ctx: [*c]struct_arcan_shmif_cont) bool;
pub extern fn arcan_shmif_primary(enum_arcan_shmif_type) [*c]struct_arcan_shmif_cont;
pub extern fn arcan_shmif_setprimary(enum_arcan_shmif_type, [*c]struct_arcan_shmif_cont) void;
pub extern fn arcan_shmif_lock([*c]struct_arcan_shmif_cont) bool;
pub extern fn arcan_shmif_unlock([*c]struct_arcan_shmif_cont) bool;
pub const SHMIF_RESET_RESIZE = @enumToInt(enum_shmif_reset_hook.SHMIF_RESET_RESIZE);
pub const SHMIF_RESET_LOST = @enumToInt(enum_shmif_reset_hook.SHMIF_RESET_LOST);
pub const SHMIF_RESET_REMAP = @enumToInt(enum_shmif_reset_hook.SHMIF_RESET_REMAP);
pub const SHMIF_RESET_NOCHG = @enumToInt(enum_shmif_reset_hook.SHMIF_RESET_NOCHG);
pub const SHMIF_RESET_FAIL = @enumToInt(enum_shmif_reset_hook.SHMIF_RESET_FAIL);
pub const enum_shmif_reset_hook = extern enum(c_int) {
    SHMIF_RESET_RESIZE = 0,
    SHMIF_RESET_LOST = 1,
    SHMIF_RESET_REMAP = 2,
    SHMIF_RESET_NOCHG = 3,
    SHMIF_RESET_FAIL = 4,
    _,
};
pub extern fn arcan_shmif_resetfunc([*c]struct_arcan_shmif_cont, shmif_reset_hook, tag: ?*c_void) shmif_reset_hook;
pub extern fn arcan_shmif_integrity_check([*c]struct_arcan_shmif_cont) bool;
pub extern fn arcan_shmif_signalstatus([*c]struct_arcan_shmif_cont) c_int;
pub const SHMIF_RHINT_ORIGO_UL = @enumToInt(enum_rhint_mask.SHMIF_RHINT_ORIGO_UL);
pub const SHMIF_RHINT_ORIGO_LL = @enumToInt(enum_rhint_mask.SHMIF_RHINT_ORIGO_LL);
pub const SHMIF_RHINT_SUBREGION = @enumToInt(enum_rhint_mask.SHMIF_RHINT_SUBREGION);
pub const SHMIF_RHINT_IGNORE_ALPHA = @enumToInt(enum_rhint_mask.SHMIF_RHINT_IGNORE_ALPHA);
pub const SHMIF_RHINT_CSPACE_SRGB = @enumToInt(enum_rhint_mask.SHMIF_RHINT_CSPACE_SRGB);
pub const SHMIF_RHINT_AUTH_TOK = @enumToInt(enum_rhint_mask.SHMIF_RHINT_AUTH_TOK);
pub const SHMIF_RHINT_VSIGNAL_EV = @enumToInt(enum_rhint_mask.SHMIF_RHINT_VSIGNAL_EV);
pub const SHMIF_RHINT_SUBREGION_CHAIN = @enumToInt(enum_rhint_mask.SHMIF_RHINT_SUBREGION_CHAIN);
pub const SHMIF_RHINT_TPACK = @enumToInt(enum_rhint_mask.SHMIF_RHINT_TPACK);
pub const enum_rhint_mask = extern enum(c_int) {
    SHMIF_RHINT_ORIGO_UL = 0,
    SHMIF_RHINT_ORIGO_LL = 1,
    SHMIF_RHINT_SUBREGION = 2,
    SHMIF_RHINT_IGNORE_ALPHA = 4,
    SHMIF_RHINT_CSPACE_SRGB = 8,
    SHMIF_RHINT_AUTH_TOK = 16,
    SHMIF_RHINT_VSIGNAL_EV = 32,
    SHMIF_RHINT_SUBREGION_CHAIN = 64,
    SHMIF_RHINT_TPACK = 128,
    _,
};
pub fn SHMIF_RGBA_DECOMP(arg_val: shmif_pixel, arg_r: [*c]u8, arg_g: [*c]u8, arg_b: [*c]u8, arg_a: [*c]u8) callconv(.C) void {
    var val = arg_val;
    var r = arg_r;
    var g = arg_g;
    var b = arg_b;
    var a = arg_a;
    b.?.* = @bitCast(u8, @truncate(u8, (val & @bitCast(c_uint, @as(c_int, 255)))));
    g.?.* = @bitCast(u8, @truncate(u8, (val & @bitCast(c_uint, @as(c_int, 65280))) >> @intCast(@import("std").math.Log2Int(c_uint), 8)));
    r.?.* = @bitCast(u8, @truncate(u8, (val & @bitCast(c_uint, @as(c_int, 16711680))) >> @intCast(@import("std").math.Log2Int(c_uint), 16)));
    a.?.* = @bitCast(u8, @truncate(u8, (val & @as(c_uint, 4278190080)) >> @intCast(@import("std").math.Log2Int(c_uint), 24)));
}
pub fn subp_checksum(buf: [*c]const u8, arg_len: usize) callconv(.C) u16 {
    var len = arg_len;
    var res: u16 = @bitCast(u16, @truncate(c_short, @as(c_int, 0)));
    {
        var i: usize = @bitCast(usize, @as(c_long, @as(c_int, 0)));
        while (i < len) : (i +%= 1) {
            if ((@bitCast(c_int, @as(c_uint, res)) & @as(c_int, 1)) != 0) res |= @intCast(u16, 65536);
            res = @bitCast(u16, @truncate(c_short, (((@bitCast(c_int, @as(c_uint, res)) >> @intCast(@import("std").math.Log2Int(c_int), 1)) + @bitCast(c_int, @as(c_uint, buf[i]))) & @as(c_int, 65535))));
        }
    }
    return res;
}
pub const struct_arcan_shmif_vr = opaque {};
pub const struct_arcan_shmif_ramp = // /usr/include/arcan/shmif/arcan_shmif_sub.h:189:24: warning: unsupported type: 'Atomic'
    opaque {}; // /usr/include/arcan/shmif/arcan_shmif_sub.h:69:8: warning: struct demoted to opaque type - unable to translate type of field dirty_in
pub const struct_arcan_shmif_hdr16f = extern struct {
    unused: c_int,
};
pub const struct_arcan_shmif_vector = opaque {}; // /usr/include/arcan/shmif/arcan_shmif_sub.h:149:27: warning: struct demoted to opaque type - has variable length array
pub const struct_arcan_shmif_venc = extern struct {
    fourcc: [4]u8,
    framesize: usize,
};
pub const union_shmif_ext_substruct = extern union {
    vr: ?*struct_arcan_shmif_vr,
    cramp: ?*struct_arcan_shmif_ramp,
    hdr: [*c]struct_arcan_shmif_hdr16f,
    vector: ?*struct_arcan_shmif_vector,
    venc: [*c]struct_arcan_shmif_venc,
};
pub extern fn arcan_shmif_substruct(ctx: [*c]struct_arcan_shmif_cont, meta: enum_shmif_ext_meta) union_shmif_ext_substruct;
const struct_unnamed_80 = extern struct {
    ofs_ramp: u32,
    sz_ramp: u32,
    ofs_vr: u32,
    sz_vr: u32,
    ofs_hdr: u32,
    sz_hdr: u32,
    ofs_vector: u32,
    sz_vector: u32,
};
const union_unnamed_79 = extern union {
    unnamed_0: struct_unnamed_80,
    offsets: [32]u32,
};
pub const struct_arcan_shmif_ofstbl = extern struct {
    unnamed_0: union_unnamed_79,
};
pub const struct_shmif_vector_mesh = extern struct {
    ofs_verts: i32,
    ofs_txcos: i32,
    ofs_txcos2: i32,
    ofs_normals: i32,
    ofs_colors: i32,
    ofs_tangents: i32,
    ofs_bitangents: i32,
    ofs_weights: i32,
    ofs_joints: i32,
    ofs_indices: i32,
    vertex_size: usize,
    n_vertices: usize,
    n_indices: usize,
    primitive: c_int,
    buffer_sz: usize,
    buffer: [*c]u8,
};
pub const struct_ramp_block = extern struct {
    format: u8,
    checksum: u16,
    plane_sizes: [4]usize,
    edid: [128]u8,
    width: usize,
    height: usize,
    vrate_int: u8,
    vrate_fract: u8,
    planes: [4095]f32,
};
pub extern fn arcan_shmifsub_getramp(cont: [*c]struct_arcan_shmif_cont, ind: usize, out: [*c]struct_ramp_block) bool;
pub extern fn arcan_shmifsub_setramp(cont: [*c]struct_arcan_shmif_cont, ind: usize, in: [*c]struct_ramp_block) bool;
pub const arcan_tui_conn = struct_arcan_shmif_cont;
pub const tui_pixel = shmif_pixel;
pub const TUI_INSERT_MODE = @enumToInt(enum_tui_context_flags.TUI_INSERT_MODE);
pub const TUI_AUTO_WRAP = @enumToInt(enum_tui_context_flags.TUI_AUTO_WRAP);
pub const TUI_REL_ORIGIN = @enumToInt(enum_tui_context_flags.TUI_REL_ORIGIN);
pub const TUI_INVERSE = @enumToInt(enum_tui_context_flags.TUI_INVERSE);
pub const TUI_HIDE_CURSOR = @enumToInt(enum_tui_context_flags.TUI_HIDE_CURSOR);
pub const TUI_FIXED_POS = @enumToInt(enum_tui_context_flags.TUI_FIXED_POS);
pub const TUI_ALTERNATE = @enumToInt(enum_tui_context_flags.TUI_ALTERNATE);
pub const TUI_MOUSE = @enumToInt(enum_tui_context_flags.TUI_MOUSE);
pub const TUI_MOUSE_FULL = @enumToInt(enum_tui_context_flags.TUI_MOUSE_FULL);
pub const enum_tui_context_flags = extern enum(c_int) {
    TUI_INSERT_MODE = 1,
    TUI_AUTO_WRAP = 2,
    TUI_REL_ORIGIN = 4,
    TUI_INVERSE = 8,
    TUI_HIDE_CURSOR = 16,
    TUI_FIXED_POS = 32,
    TUI_ALTERNATE = 64,
    TUI_MOUSE = 128,
    TUI_MOUSE_FULL = 256,
    _,
};
pub const TUI_ATTR_BOLD = @enumToInt(enum_tui_attr_flags.TUI_ATTR_BOLD);
pub const TUI_ATTR_UNDERLINE = @enumToInt(enum_tui_attr_flags.TUI_ATTR_UNDERLINE);
pub const TUI_ATTR_UNDERLINE_ALT = @enumToInt(enum_tui_attr_flags.TUI_ATTR_UNDERLINE_ALT);
pub const TUI_ATTR_ITALIC = @enumToInt(enum_tui_attr_flags.TUI_ATTR_ITALIC);
pub const TUI_ATTR_INVERSE = @enumToInt(enum_tui_attr_flags.TUI_ATTR_INVERSE);
pub const TUI_ATTR_PROTECT = @enumToInt(enum_tui_attr_flags.TUI_ATTR_PROTECT);
pub const TUI_ATTR_BLINK = @enumToInt(enum_tui_attr_flags.TUI_ATTR_BLINK);
pub const TUI_ATTR_STRIKETHROUGH = @enumToInt(enum_tui_attr_flags.TUI_ATTR_STRIKETHROUGH);
pub const TUI_ATTR_SHAPE_BREAK = @enumToInt(enum_tui_attr_flags.TUI_ATTR_SHAPE_BREAK);
pub const TUI_ATTR_COLOR_INDEXED = @enumToInt(enum_tui_attr_flags.TUI_ATTR_COLOR_INDEXED);
pub const TUI_ATTR_BORDER_RIGHT = @enumToInt(enum_tui_attr_flags.TUI_ATTR_BORDER_RIGHT);
pub const TUI_ATTR_BORDER_DOWN = @enumToInt(enum_tui_attr_flags.TUI_ATTR_BORDER_DOWN);
pub const TUI_ATTR_GLYPH_INDEXED = @enumToInt(enum_tui_attr_flags.TUI_ATTR_GLYPH_INDEXED);
pub const enum_tui_attr_flags = extern enum(c_int) {
    TUI_ATTR_BOLD = 1,
    TUI_ATTR_UNDERLINE = 2,
    TUI_ATTR_UNDERLINE_ALT = 4,
    TUI_ATTR_ITALIC = 8,
    TUI_ATTR_INVERSE = 16,
    TUI_ATTR_PROTECT = 32,
    TUI_ATTR_BLINK = 64,
    TUI_ATTR_STRIKETHROUGH = 128,
    TUI_ATTR_SHAPE_BREAK = 256,
    TUI_ATTR_COLOR_INDEXED = 512,
    TUI_ATTR_BORDER_RIGHT = 1024,
    TUI_ATTR_BORDER_DOWN = 2048,
    TUI_ATTR_GLYPH_INDEXED = 4096,
    _,
};
pub const TUI_WND_NORMAL = @enumToInt(enum_tui_wndhint_flags.TUI_WND_NORMAL);
pub const TUI_WND_FOCUS = @enumToInt(enum_tui_wndhint_flags.TUI_WND_FOCUS);
pub const TUI_WND_HIDDEN = @enumToInt(enum_tui_wndhint_flags.TUI_WND_HIDDEN);
pub const enum_tui_wndhint_flags = extern enum(c_int) {
    TUI_WND_NORMAL = 0,
    TUI_WND_FOCUS = 1,
    TUI_WND_HIDDEN = 2,
    _,
};
pub const TUI_MESSAGE_PROMPT = @enumToInt(enum_tui_message_slots.TUI_MESSAGE_PROMPT);
pub const TUI_MESSAGE_ALERT = @enumToInt(enum_tui_message_slots.TUI_MESSAGE_ALERT);
pub const TUI_MESSAGE_NOTIFICATION = @enumToInt(enum_tui_message_slots.TUI_MESSAGE_NOTIFICATION);
pub const TUI_MESSAGE_FAILURE = @enumToInt(enum_tui_message_slots.TUI_MESSAGE_FAILURE);
pub const enum_tui_message_slots = extern enum(c_int) {
    TUI_MESSAGE_PROMPT = 0,
    TUI_MESSAGE_ALERT = 1,
    TUI_MESSAGE_NOTIFICATION = 2,
    TUI_MESSAGE_FAILURE = 3,
    _,
};
pub const TUI_PROGRESS_INTERNAL = @enumToInt(enum_tui_progress_type.TUI_PROGRESS_INTERNAL);
pub const TUI_PROGRESS_BCHUNK_IN = @enumToInt(enum_tui_progress_type.TUI_PROGRESS_BCHUNK_IN);
pub const TUI_PROGRESS_BCHUNK_OUT = @enumToInt(enum_tui_progress_type.TUI_PROGRESS_BCHUNK_OUT);
pub const TUI_PROGRESS_STATE_IN = @enumToInt(enum_tui_progress_type.TUI_PROGRESS_STATE_IN);
pub const TUI_PROGRESS_STATE_OUT = @enumToInt(enum_tui_progress_type.TUI_PROGRESS_STATE_OUT);
pub const enum_tui_progress_type = extern enum(c_int) {
    TUI_PROGRESS_INTERNAL = 0,
    TUI_PROGRESS_BCHUNK_IN = 1,
    TUI_PROGRESS_BCHUNK_OUT = 2,
    TUI_PROGRESS_STATE_IN = 3,
    TUI_PROGRESS_STATE_OUT = 4,
    _,
};
pub const TUI_CLI_BEGIN = @enumToInt(enum_tui_cli.TUI_CLI_BEGIN);
pub const TUI_CLI_EVAL = @enumToInt(enum_tui_cli.TUI_CLI_EVAL);
pub const TUI_CLI_COMMIT = @enumToInt(enum_tui_cli.TUI_CLI_COMMIT);
pub const TUI_CLI_CANCEL = @enumToInt(enum_tui_cli.TUI_CLI_CANCEL);
pub const TUI_CLI_SUGGEST = @enumToInt(enum_tui_cli.TUI_CLI_SUGGEST);
pub const TUI_CLI_ACCEPT = @enumToInt(enum_tui_cli.TUI_CLI_ACCEPT);
pub const TUI_CLI_INVALID = @enumToInt(enum_tui_cli.TUI_CLI_INVALID);
pub const TUI_CLI_REPLACE = @enumToInt(enum_tui_cli.TUI_CLI_REPLACE);
pub const enum_tui_cli = extern enum(c_int) {
    TUI_CLI_BEGIN = 0,
    TUI_CLI_EVAL = 1,
    TUI_CLI_COMMIT = 2,
    TUI_CLI_CANCEL = 3,
    TUI_CLI_SUGGEST = 4,
    TUI_CLI_ACCEPT = 5,
    TUI_CLI_INVALID = 6,
    TUI_CLI_REPLACE = 7,
    _,
};
pub const TUI_DETACH_PROCESS = @enumToInt(enum_tui_handover_flags.TUI_DETACH_PROCESS);
pub const TUI_DETACH_STDIN = @enumToInt(enum_tui_handover_flags.TUI_DETACH_STDIN);
pub const TUI_DETACH_STDOUT = @enumToInt(enum_tui_handover_flags.TUI_DETACH_STDOUT);
pub const TUI_DETACH_STDERR = @enumToInt(enum_tui_handover_flags.TUI_DETACH_STDERR);
pub const enum_tui_handover_flags = extern enum(c_int) {
    TUI_DETACH_PROCESS = 1,
    TUI_DETACH_STDIN = 2,
    TUI_DETACH_STDOUT = 4,
    TUI_DETACH_STDERR = 8,
    _,
};
pub const TUI_WND_TUI = @enumToInt(enum_tui_subwnd_type.TUI_WND_TUI);
pub const TUI_WND_POPUP = @enumToInt(enum_tui_subwnd_type.TUI_WND_POPUP);
pub const TUI_WND_ACCESSIBILITY = @enumToInt(enum_tui_subwnd_type.TUI_WND_ACCESSIBILITY);
pub const TUI_WND_DEBUG = @enumToInt(enum_tui_subwnd_type.TUI_WND_DEBUG);
pub const TUI_WND_HANDOVER = @enumToInt(enum_tui_subwnd_type.TUI_WND_HANDOVER);
pub const enum_tui_subwnd_type = extern enum(c_int) {
    TUI_WND_TUI = 23,
    TUI_WND_POPUP = 16,
    TUI_WND_ACCESSIBILITY = 19,
    TUI_WND_DEBUG = 255,
    TUI_WND_HANDOVER = 26,
    _,
};
pub const TUI_COL_PRIMARY = @enumToInt(enum_tui_color_group.TUI_COL_PRIMARY);
pub const TUI_COL_SECONDARY = @enumToInt(enum_tui_color_group.TUI_COL_SECONDARY);
pub const TUI_COL_BG = @enumToInt(enum_tui_color_group.TUI_COL_BG);
pub const TUI_COL_TEXT = @enumToInt(enum_tui_color_group.TUI_COL_TEXT);
pub const TUI_COL_CURSOR = @enumToInt(enum_tui_color_group.TUI_COL_CURSOR);
pub const TUI_COL_ALTCURSOR = @enumToInt(enum_tui_color_group.TUI_COL_ALTCURSOR);
pub const TUI_COL_HIGHLIGHT = @enumToInt(enum_tui_color_group.TUI_COL_HIGHLIGHT);
pub const TUI_COL_LABEL = @enumToInt(enum_tui_color_group.TUI_COL_LABEL);
pub const TUI_COL_WARNING = @enumToInt(enum_tui_color_group.TUI_COL_WARNING);
pub const TUI_COL_ERROR = @enumToInt(enum_tui_color_group.TUI_COL_ERROR);
pub const TUI_COL_ALERT = @enumToInt(enum_tui_color_group.TUI_COL_ALERT);
pub const TUI_COL_REFERENCE = @enumToInt(enum_tui_color_group.TUI_COL_REFERENCE);
pub const TUI_COL_INACTIVE = @enumToInt(enum_tui_color_group.TUI_COL_INACTIVE);
pub const TUI_COL_UI = @enumToInt(enum_tui_color_group.TUI_COL_UI);
pub const TUI_COL_TBASE = @enumToInt(enum_tui_color_group.TUI_COL_TBASE);
pub const TUI_COL_LIMIT = @enumToInt(enum_tui_color_group.TUI_COL_LIMIT);
pub const enum_tui_color_group = extern enum(c_int) {
    TUI_COL_PRIMARY = 2,
    TUI_COL_SECONDARY = 3,
    TUI_COL_BG = 4,
    TUI_COL_TEXT = 5,
    TUI_COL_CURSOR = 6,
    TUI_COL_ALTCURSOR = 7,
    TUI_COL_HIGHLIGHT = 8,
    TUI_COL_LABEL = 9,
    TUI_COL_WARNING = 10,
    TUI_COL_ERROR = 11,
    TUI_COL_ALERT = 12,
    TUI_COL_REFERENCE = 13,
    TUI_COL_INACTIVE = 14,
    TUI_COL_UI = 15,
    TUI_COL_TBASE = 16,
    TUI_COL_LIMIT = 36,
    _,
};
pub const CURSOR_BLOCK = @enumToInt(enum_tui_cursors.CURSOR_BLOCK);
pub const CURSOR_HALFBLOCK = @enumToInt(enum_tui_cursors.CURSOR_HALFBLOCK);
pub const CURSOR_FRAME = @enumToInt(enum_tui_cursors.CURSOR_FRAME);
pub const CURSOR_VLINE = @enumToInt(enum_tui_cursors.CURSOR_VLINE);
pub const CURSOR_ULINE = @enumToInt(enum_tui_cursors.CURSOR_ULINE);
pub const CURSOR_END = @enumToInt(enum_tui_cursors.CURSOR_END);
pub const enum_tui_cursors = extern enum(c_int) {
    CURSOR_BLOCK = 0,
    CURSOR_HALFBLOCK = 1,
    CURSOR_FRAME = 2,
    CURSOR_VLINE = 3,
    CURSOR_ULINE = 4,
    CURSOR_END = 5,
    _,
};
pub const TUIM_NONE = @enumToInt(enum_tuim_syms.TUIM_NONE);
pub const TUIM_LSHIFT = @enumToInt(enum_tuim_syms.TUIM_LSHIFT);
pub const TUIM_RSHIFT = @enumToInt(enum_tuim_syms.TUIM_RSHIFT);
pub const TUIM_LCTRL = @enumToInt(enum_tuim_syms.TUIM_LCTRL);
pub const TUIM_RCTRL = @enumToInt(enum_tuim_syms.TUIM_RCTRL);
pub const TUIM_LALT = @enumToInt(enum_tuim_syms.TUIM_LALT);
pub const TUIM_RALT = @enumToInt(enum_tuim_syms.TUIM_RALT);
pub const TUIM_ALT = @enumToInt(enum_tuim_syms.TUIM_ALT);
pub const TUIM_LMETA = @enumToInt(enum_tuim_syms.TUIM_LMETA);
pub const TUIM_RMETA = @enumToInt(enum_tuim_syms.TUIM_RMETA);
pub const TUIM_META = @enumToInt(enum_tuim_syms.TUIM_META);
pub const TUIM_REPEAT = @enumToInt(enum_tuim_syms.TUIM_REPEAT);
pub const enum_tuim_syms = extern enum(c_int) {
    TUIM_NONE = 0,
    TUIM_LSHIFT = 1,
    TUIM_RSHIFT = 2,
    TUIM_LCTRL = 64,
    TUIM_RCTRL = 128,
    TUIM_LALT = 256,
    TUIM_RALT = 512,
    TUIM_ALT = 768,
    TUIM_LMETA = 1024,
    TUIM_RMETA = 2048,
    TUIM_META = 3072,
    TUIM_REPEAT = 32768,
    _,
};
pub const TUIBTN_LEFT = @enumToInt(enum_tuibtn_syms.TUIBTN_LEFT);
pub const TUIBTN_RIGHT = @enumToInt(enum_tuibtn_syms.TUIBTN_RIGHT);
pub const TUIBTN_MIDDLE = @enumToInt(enum_tuibtn_syms.TUIBTN_MIDDLE);
pub const TUIBTN_WHEEL_UP = @enumToInt(enum_tuibtn_syms.TUIBTN_WHEEL_UP);
pub const TUIBTN_WHEEL_DOWN = @enumToInt(enum_tuibtn_syms.TUIBTN_WHEEL_DOWN);
pub const enum_tuibtn_syms = extern enum(c_int) {
    TUIBTN_LEFT = 1,
    TUIBTN_RIGHT = 2,
    TUIBTN_MIDDLE = 3,
    TUIBTN_WHEEL_UP = 4,
    TUIBTN_WHEEL_DOWN = 5,
    _,
};
pub const TUIK_UNKNOWN = @enumToInt(enum_tuik_syms.TUIK_UNKNOWN);
pub const TUIK_FIRST = @enumToInt(enum_tuik_syms.TUIK_FIRST);
pub const TUIK_BACKSPACE = @enumToInt(enum_tuik_syms.TUIK_BACKSPACE);
pub const TUIK_TAB = @enumToInt(enum_tuik_syms.TUIK_TAB);
pub const TUIK_CLEAR = @enumToInt(enum_tuik_syms.TUIK_CLEAR);
pub const TUIK_RETURN = @enumToInt(enum_tuik_syms.TUIK_RETURN);
pub const TUIK_PAUSE = @enumToInt(enum_tuik_syms.TUIK_PAUSE);
pub const TUIK_ESCAPE = @enumToInt(enum_tuik_syms.TUIK_ESCAPE);
pub const TUIK_SPACE = @enumToInt(enum_tuik_syms.TUIK_SPACE);
pub const TUIK_EXCLAIM = @enumToInt(enum_tuik_syms.TUIK_EXCLAIM);
pub const TUIK_QUOTEDBL = @enumToInt(enum_tuik_syms.TUIK_QUOTEDBL);
pub const TUIK_HASH = @enumToInt(enum_tuik_syms.TUIK_HASH);
pub const TUIK_DOLLAR = @enumToInt(enum_tuik_syms.TUIK_DOLLAR);
pub const TUIK_0 = @enumToInt(enum_tuik_syms.TUIK_0);
pub const TUIK_1 = @enumToInt(enum_tuik_syms.TUIK_1);
pub const TUIK_2 = @enumToInt(enum_tuik_syms.TUIK_2);
pub const TUIK_3 = @enumToInt(enum_tuik_syms.TUIK_3);
pub const TUIK_4 = @enumToInt(enum_tuik_syms.TUIK_4);
pub const TUIK_5 = @enumToInt(enum_tuik_syms.TUIK_5);
pub const TUIK_6 = @enumToInt(enum_tuik_syms.TUIK_6);
pub const TUIK_7 = @enumToInt(enum_tuik_syms.TUIK_7);
pub const TUIK_8 = @enumToInt(enum_tuik_syms.TUIK_8);
pub const TUIK_9 = @enumToInt(enum_tuik_syms.TUIK_9);
pub const TUIK_MINUS = @enumToInt(enum_tuik_syms.TUIK_MINUS);
pub const TUIK_EQUALS = @enumToInt(enum_tuik_syms.TUIK_EQUALS);
pub const TUIK_A = @enumToInt(enum_tuik_syms.TUIK_A);
pub const TUIK_B = @enumToInt(enum_tuik_syms.TUIK_B);
pub const TUIK_C = @enumToInt(enum_tuik_syms.TUIK_C);
pub const TUIK_D = @enumToInt(enum_tuik_syms.TUIK_D);
pub const TUIK_E = @enumToInt(enum_tuik_syms.TUIK_E);
pub const TUIK_F = @enumToInt(enum_tuik_syms.TUIK_F);
pub const TUIK_G = @enumToInt(enum_tuik_syms.TUIK_G);
pub const TUIK_H = @enumToInt(enum_tuik_syms.TUIK_H);
pub const TUIK_I = @enumToInt(enum_tuik_syms.TUIK_I);
pub const TUIK_J = @enumToInt(enum_tuik_syms.TUIK_J);
pub const TUIK_K = @enumToInt(enum_tuik_syms.TUIK_K);
pub const TUIK_L = @enumToInt(enum_tuik_syms.TUIK_L);
pub const TUIK_M = @enumToInt(enum_tuik_syms.TUIK_M);
pub const TUIK_N = @enumToInt(enum_tuik_syms.TUIK_N);
pub const TUIK_O = @enumToInt(enum_tuik_syms.TUIK_O);
pub const TUIK_P = @enumToInt(enum_tuik_syms.TUIK_P);
pub const TUIK_Q = @enumToInt(enum_tuik_syms.TUIK_Q);
pub const TUIK_R = @enumToInt(enum_tuik_syms.TUIK_R);
pub const TUIK_S = @enumToInt(enum_tuik_syms.TUIK_S);
pub const TUIK_T = @enumToInt(enum_tuik_syms.TUIK_T);
pub const TUIK_U = @enumToInt(enum_tuik_syms.TUIK_U);
pub const TUIK_V = @enumToInt(enum_tuik_syms.TUIK_V);
pub const TUIK_W = @enumToInt(enum_tuik_syms.TUIK_W);
pub const TUIK_X = @enumToInt(enum_tuik_syms.TUIK_X);
pub const TUIK_Y = @enumToInt(enum_tuik_syms.TUIK_Y);
pub const TUIK_Z = @enumToInt(enum_tuik_syms.TUIK_Z);
pub const TUIK_LESS = @enumToInt(enum_tuik_syms.TUIK_LESS);
pub const TUIK_KP_LEFTBRACE = @enumToInt(enum_tuik_syms.TUIK_KP_LEFTBRACE);
pub const TUIK_KP_RIGHTBRACE = @enumToInt(enum_tuik_syms.TUIK_KP_RIGHTBRACE);
pub const TUIK_KP_ENTER = @enumToInt(enum_tuik_syms.TUIK_KP_ENTER);
pub const TUIK_LCTRL = @enumToInt(enum_tuik_syms.TUIK_LCTRL);
pub const TUIK_SEMICOLON = @enumToInt(enum_tuik_syms.TUIK_SEMICOLON);
pub const TUIK_APOSTROPHE = @enumToInt(enum_tuik_syms.TUIK_APOSTROPHE);
pub const TUIK_GRAVE = @enumToInt(enum_tuik_syms.TUIK_GRAVE);
pub const TUIK_LSHIFT = @enumToInt(enum_tuik_syms.TUIK_LSHIFT);
pub const TUIK_BACKSLASH = @enumToInt(enum_tuik_syms.TUIK_BACKSLASH);
pub const TUIK_COMMA = @enumToInt(enum_tuik_syms.TUIK_COMMA);
pub const TUIK_PERIOD = @enumToInt(enum_tuik_syms.TUIK_PERIOD);
pub const TUIK_SLASH = @enumToInt(enum_tuik_syms.TUIK_SLASH);
pub const TUIK_RSHIFT = @enumToInt(enum_tuik_syms.TUIK_RSHIFT);
pub const TUIK_KP_MULTIPLY = @enumToInt(enum_tuik_syms.TUIK_KP_MULTIPLY);
pub const TUIK_LALT = @enumToInt(enum_tuik_syms.TUIK_LALT);
pub const TUIK_CAPSLOCK = @enumToInt(enum_tuik_syms.TUIK_CAPSLOCK);
pub const TUIK_F1 = @enumToInt(enum_tuik_syms.TUIK_F1);
pub const TUIK_F2 = @enumToInt(enum_tuik_syms.TUIK_F2);
pub const TUIK_F3 = @enumToInt(enum_tuik_syms.TUIK_F3);
pub const TUIK_F4 = @enumToInt(enum_tuik_syms.TUIK_F4);
pub const TUIK_F5 = @enumToInt(enum_tuik_syms.TUIK_F5);
pub const TUIK_F6 = @enumToInt(enum_tuik_syms.TUIK_F6);
pub const TUIK_F7 = @enumToInt(enum_tuik_syms.TUIK_F7);
pub const TUIK_F8 = @enumToInt(enum_tuik_syms.TUIK_F8);
pub const TUIK_F9 = @enumToInt(enum_tuik_syms.TUIK_F9);
pub const TUIK_F10 = @enumToInt(enum_tuik_syms.TUIK_F10);
pub const TUIK_NUMLOCKCLEAR = @enumToInt(enum_tuik_syms.TUIK_NUMLOCKCLEAR);
pub const TUIK_SCROLLLOCK = @enumToInt(enum_tuik_syms.TUIK_SCROLLLOCK);
pub const TUIK_KP_0 = @enumToInt(enum_tuik_syms.TUIK_KP_0);
pub const TUIK_KP_1 = @enumToInt(enum_tuik_syms.TUIK_KP_1);
pub const TUIK_KP_2 = @enumToInt(enum_tuik_syms.TUIK_KP_2);
pub const TUIK_KP_3 = @enumToInt(enum_tuik_syms.TUIK_KP_3);
pub const TUIK_KP_4 = @enumToInt(enum_tuik_syms.TUIK_KP_4);
pub const TUIK_KP_5 = @enumToInt(enum_tuik_syms.TUIK_KP_5);
pub const TUIK_KP_6 = @enumToInt(enum_tuik_syms.TUIK_KP_6);
pub const TUIK_KP_7 = @enumToInt(enum_tuik_syms.TUIK_KP_7);
pub const TUIK_KP_8 = @enumToInt(enum_tuik_syms.TUIK_KP_8);
pub const TUIK_KP_9 = @enumToInt(enum_tuik_syms.TUIK_KP_9);
pub const TUIK_KP_MINUS = @enumToInt(enum_tuik_syms.TUIK_KP_MINUS);
pub const TUIK_KP_PLUS = @enumToInt(enum_tuik_syms.TUIK_KP_PLUS);
pub const TUIK_KP_PERIOD = @enumToInt(enum_tuik_syms.TUIK_KP_PERIOD);
pub const TUIK_INTERNATIONAL1 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL1);
pub const TUIK_INTERNATIONAL2 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL2);
pub const TUIK_F11 = @enumToInt(enum_tuik_syms.TUIK_F11);
pub const TUIK_F12 = @enumToInt(enum_tuik_syms.TUIK_F12);
pub const TUIK_INTERNATIONAL3 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL3);
pub const TUIK_INTERNATIONAL4 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL4);
pub const TUIK_INTERNATIONAL5 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL5);
pub const TUIK_INTERNATIONAL6 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL6);
pub const TUIK_INTERNATIONAL7 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL7);
pub const TUIK_INTERNATIONAL8 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL8);
pub const TUIK_INTERNATIONAL9 = @enumToInt(enum_tuik_syms.TUIK_INTERNATIONAL9);
pub const TUIK_RCTRL = @enumToInt(enum_tuik_syms.TUIK_RCTRL);
pub const TUIK_KP_DIVIDE = @enumToInt(enum_tuik_syms.TUIK_KP_DIVIDE);
pub const TUIK_SYSREQ = @enumToInt(enum_tuik_syms.TUIK_SYSREQ);
pub const TUIK_RALT = @enumToInt(enum_tuik_syms.TUIK_RALT);
pub const TUIK_HOME = @enumToInt(enum_tuik_syms.TUIK_HOME);
pub const TUIK_UP = @enumToInt(enum_tuik_syms.TUIK_UP);
pub const TUIK_PAGEUP = @enumToInt(enum_tuik_syms.TUIK_PAGEUP);
pub const TUIK_LEFT = @enumToInt(enum_tuik_syms.TUIK_LEFT);
pub const TUIK_RIGHT = @enumToInt(enum_tuik_syms.TUIK_RIGHT);
pub const TUIK_END = @enumToInt(enum_tuik_syms.TUIK_END);
pub const TUIK_DOWN = @enumToInt(enum_tuik_syms.TUIK_DOWN);
pub const TUIK_PAGEDOWN = @enumToInt(enum_tuik_syms.TUIK_PAGEDOWN);
pub const TUIK_INSERT = @enumToInt(enum_tuik_syms.TUIK_INSERT);
pub const TUIK_DELETE = @enumToInt(enum_tuik_syms.TUIK_DELETE);
pub const TUIK_LMETA = @enumToInt(enum_tuik_syms.TUIK_LMETA);
pub const TUIK_RMETA = @enumToInt(enum_tuik_syms.TUIK_RMETA);
pub const TUIK_COMPOSE = @enumToInt(enum_tuik_syms.TUIK_COMPOSE);
pub const TUIK_MUTE = @enumToInt(enum_tuik_syms.TUIK_MUTE);
pub const TUIK_VOLUMEDOWN = @enumToInt(enum_tuik_syms.TUIK_VOLUMEDOWN);
pub const TUIK_VOLUMEUP = @enumToInt(enum_tuik_syms.TUIK_VOLUMEUP);
pub const TUIK_POWER = @enumToInt(enum_tuik_syms.TUIK_POWER);
pub const TUIK_KP_EQUALS = @enumToInt(enum_tuik_syms.TUIK_KP_EQUALS);
pub const TUIK_KP_PLUSMINUS = @enumToInt(enum_tuik_syms.TUIK_KP_PLUSMINUS);
pub const TUIK_LANG1 = @enumToInt(enum_tuik_syms.TUIK_LANG1);
pub const TUIK_LANG2 = @enumToInt(enum_tuik_syms.TUIK_LANG2);
pub const TUIK_LANG3 = @enumToInt(enum_tuik_syms.TUIK_LANG3);
pub const TUIK_LGUI = @enumToInt(enum_tuik_syms.TUIK_LGUI);
pub const TUIK_RGUI = @enumToInt(enum_tuik_syms.TUIK_RGUI);
pub const TUIK_STOP = @enumToInt(enum_tuik_syms.TUIK_STOP);
pub const TUIK_AGAIN = @enumToInt(enum_tuik_syms.TUIK_AGAIN);
pub const enum_tuik_syms = extern enum(c_int) {
    TUIK_UNKNOWN = 0,
    TUIK_FIRST = 0,
    TUIK_BACKSPACE = 8,
    TUIK_TAB = 9,
    TUIK_CLEAR = 12,
    TUIK_RETURN = 13,
    TUIK_PAUSE = 19,
    TUIK_ESCAPE = 27,
    TUIK_SPACE = 32,
    TUIK_EXCLAIM = 33,
    TUIK_QUOTEDBL = 34,
    TUIK_HASH = 35,
    TUIK_DOLLAR = 36,
    TUIK_0 = 48,
    TUIK_1 = 49,
    TUIK_2 = 50,
    TUIK_3 = 51,
    TUIK_4 = 52,
    TUIK_5 = 53,
    TUIK_6 = 54,
    TUIK_7 = 55,
    TUIK_8 = 56,
    TUIK_9 = 57,
    TUIK_MINUS = 20,
    TUIK_EQUALS = 21,
    TUIK_A = 97,
    TUIK_B = 98,
    TUIK_C = 99,
    TUIK_D = 100,
    TUIK_E = 101,
    TUIK_F = 102,
    TUIK_G = 103,
    TUIK_H = 104,
    TUIK_I = 105,
    TUIK_J = 106,
    TUIK_K = 107,
    TUIK_L = 108,
    TUIK_M = 109,
    TUIK_N = 110,
    TUIK_O = 111,
    TUIK_P = 112,
    TUIK_Q = 113,
    TUIK_R = 114,
    TUIK_S = 115,
    TUIK_T = 116,
    TUIK_U = 117,
    TUIK_V = 118,
    TUIK_W = 119,
    TUIK_X = 120,
    TUIK_Y = 121,
    TUIK_Z = 122,
    TUIK_LESS = 60,
    TUIK_KP_LEFTBRACE = 91,
    TUIK_KP_RIGHTBRACE = 93,
    TUIK_KP_ENTER = 271,
    TUIK_LCTRL = 306,
    TUIK_SEMICOLON = 59,
    TUIK_APOSTROPHE = 48,
    TUIK_GRAVE = 49,
    TUIK_LSHIFT = 304,
    TUIK_BACKSLASH = 92,
    TUIK_COMMA = 44,
    TUIK_PERIOD = 46,
    TUIK_SLASH = 61,
    TUIK_RSHIFT = 303,
    TUIK_KP_MULTIPLY = 268,
    TUIK_LALT = 308,
    TUIK_CAPSLOCK = 301,
    TUIK_F1 = 282,
    TUIK_F2 = 283,
    TUIK_F3 = 284,
    TUIK_F4 = 285,
    TUIK_F5 = 286,
    TUIK_F6 = 287,
    TUIK_F7 = 288,
    TUIK_F8 = 289,
    TUIK_F9 = 290,
    TUIK_F10 = 291,
    TUIK_NUMLOCKCLEAR = 300,
    TUIK_SCROLLLOCK = 302,
    TUIK_KP_0 = 256,
    TUIK_KP_1 = 257,
    TUIK_KP_2 = 258,
    TUIK_KP_3 = 259,
    TUIK_KP_4 = 260,
    TUIK_KP_5 = 261,
    TUIK_KP_6 = 262,
    TUIK_KP_7 = 263,
    TUIK_KP_8 = 264,
    TUIK_KP_9 = 265,
    TUIK_KP_MINUS = 269,
    TUIK_KP_PLUS = 270,
    TUIK_KP_PERIOD = 266,
    TUIK_INTERNATIONAL1 = 267,
    TUIK_INTERNATIONAL2 = 268,
    TUIK_F11 = 292,
    TUIK_F12 = 293,
    TUIK_INTERNATIONAL3 = 294,
    TUIK_INTERNATIONAL4 = 295,
    TUIK_INTERNATIONAL5 = 296,
    TUIK_INTERNATIONAL6 = 297,
    TUIK_INTERNATIONAL7 = 298,
    TUIK_INTERNATIONAL8 = 299,
    TUIK_INTERNATIONAL9 = 300,
    TUIK_RCTRL = 305,
    TUIK_KP_DIVIDE = 267,
    TUIK_SYSREQ = 317,
    TUIK_RALT = 307,
    TUIK_HOME = 278,
    TUIK_UP = 273,
    TUIK_PAGEUP = 280,
    TUIK_LEFT = 276,
    TUIK_RIGHT = 275,
    TUIK_END = 279,
    TUIK_DOWN = 274,
    TUIK_PAGEDOWN = 281,
    TUIK_INSERT = 277,
    TUIK_DELETE = 127,
    TUIK_LMETA = 310,
    TUIK_RMETA = 309,
    TUIK_COMPOSE = 314,
    TUIK_MUTE = 315,
    TUIK_VOLUMEDOWN = 316,
    TUIK_VOLUMEUP = 317,
    TUIK_POWER = 318,
    TUIK_KP_EQUALS = 319,
    TUIK_KP_PLUSMINUS = 320,
    TUIK_LANG1 = 321,
    TUIK_LANG2 = 322,
    TUIK_LANG3 = 323,
    TUIK_LGUI = 324,
    TUIK_RGUI = 325,
    TUIK_STOP = 326,
    TUIK_AGAIN = 327,
    _,
};
pub const struct_tui_context = opaque {};
pub const struct_tui_constraints = extern struct {
    anch_row: c_int,
    anch_col: c_int,
    max_rows: c_int,
    max_cols: c_int,
    min_rows: c_int,
    min_cols: c_int,
};
const struct_unnamed_82 = extern struct {
    fr: u8,
    fg: u8,
    fb: u8,
};
const union_unnamed_81 = extern union {
    fc: [3]u8,
    unnamed_0: struct_unnamed_82,
};
const struct_unnamed_84 = extern struct {
    br: u8,
    bg: u8,
    bb: u8,
};
const union_unnamed_83 = extern union {
    bc: [3]u8,
    unnamed_0: struct_unnamed_84,
};
pub const struct_tui_screen_attr = extern struct {
    unnamed_0: union_unnamed_81,
    unnamed_1: union_unnamed_83,
    aflags: u16,
    custom_id: u8,
};
pub fn tui_attr_equal(arg_a: struct_tui_screen_attr, arg_b: struct_tui_screen_attr) callconv(.C) bool {
    var a = arg_a;
    var b = arg_b;
    return ((((((((@bitCast(c_int, @as(c_uint, a.unnamed_0.unnamed_0.fr)) == @bitCast(c_int, @as(c_uint, b.unnamed_0.unnamed_0.fr))) and (@bitCast(c_int, @as(c_uint, a.unnamed_0.unnamed_0.fg)) == @bitCast(c_int, @as(c_uint, b.unnamed_0.unnamed_0.fg)))) and (@bitCast(c_int, @as(c_uint, a.unnamed_0.unnamed_0.fb)) == @bitCast(c_int, @as(c_uint, b.unnamed_0.unnamed_0.fb)))) and (@bitCast(c_int, @as(c_uint, a.unnamed_1.unnamed_0.br)) == @bitCast(c_int, @as(c_uint, b.unnamed_1.unnamed_0.br)))) and (@bitCast(c_int, @as(c_uint, a.unnamed_1.unnamed_0.bg)) == @bitCast(c_int, @as(c_uint, b.unnamed_1.unnamed_0.bg)))) and (@bitCast(c_int, @as(c_uint, a.unnamed_1.unnamed_0.bb)) == @bitCast(c_int, @as(c_uint, b.unnamed_1.unnamed_0.bb)))) and (@bitCast(c_int, @as(c_uint, a.aflags)) == @bitCast(c_int, @as(c_uint, b.aflags)))) and (@bitCast(c_int, @as(c_uint, a.custom_id)) == @bitCast(c_int, @as(c_uint, b.custom_id))));
}
pub const struct_tui_cell = extern struct {
    attr: struct_tui_screen_attr,
    ch: u32,
    draw_ch: u32,
    real_x: u32,
    cell_w: u8,
    fstamp: u8,
};
pub const struct_tui_labelent = extern struct {
    label: [16]u8,
    descr: [58]u8,
    vsym: [5]u8,
    idatatype: u8,
    initial: u16,
    subv: u16,
    modifiers: u16,
};
pub const struct_tui_cbcfg = extern struct {
    tag: ?*c_void,
    query_label: ?fn (?*struct_tui_context, usize, [*c]const u8, [*c]const u8, [*c]struct_tui_labelent, ?*c_void) callconv(.C) bool,
    input_label: ?fn (?*struct_tui_context, [*c]const u8, bool, ?*c_void) callconv(.C) bool,
    input_alabel: ?fn (?*struct_tui_context, [*c]const u8, [*c]const i16, usize, bool, u8, ?*c_void) callconv(.C) bool,
    input_mouse_motion: ?fn (?*struct_tui_context, bool, c_int, c_int, c_int, ?*c_void) callconv(.C) void,
    input_mouse_button: ?fn (?*struct_tui_context, c_int, c_int, c_int, bool, c_int, ?*c_void) callconv(.C) void,
    input_utf8: ?fn (?*struct_tui_context, [*c]const u8, usize, ?*c_void) callconv(.C) bool,
    input_key: ?fn (?*struct_tui_context, u32, u8, u8, u16, ?*c_void) callconv(.C) void,
    input_misc: ?fn (?*struct_tui_context, [*c]const arcan_ioevent, ?*c_void) callconv(.C) void,
    state: ?fn (?*struct_tui_context, bool, c_int, ?*c_void) callconv(.C) void,
    bchunk: ?fn (?*struct_tui_context, bool, u64, c_int, [*c]const u8, ?*c_void) callconv(.C) void,
    vpaste: ?fn (?*struct_tui_context, [*c]shmif_pixel, usize, usize, usize, ?*c_void) callconv(.C) void,
    apaste: ?fn (?*struct_tui_context, [*c]shmif_asample, usize, usize, usize, ?*c_void) callconv(.C) void,
    tick: ?fn (?*struct_tui_context, ?*c_void) callconv(.C) void,
    utf8: ?fn (?*struct_tui_context, [*c]const u8, usize, bool, ?*c_void) callconv(.C) void,
    resized: ?fn (?*struct_tui_context, usize, usize, usize, usize, ?*c_void) callconv(.C) void,
    reset: ?fn (?*struct_tui_context, c_int, ?*c_void) callconv(.C) void,
    geohint: ?fn (?*struct_tui_context, f32, f32, f32, [*c]const u8, [*c]const u8, ?*c_void) callconv(.C) void,
    recolor: ?fn (?*struct_tui_context, ?*c_void) callconv(.C) void,
    subwindow: ?fn (?*struct_tui_context, [*c]arcan_tui_conn, u32, u8, ?*c_void) callconv(.C) bool,
    substitute: ?fn (?*struct_tui_context, [*c]struct_tui_cell, usize, usize, ?*c_void) callconv(.C) bool,
    resize: ?fn (?*struct_tui_context, usize, usize, usize, usize, ?*c_void) callconv(.C) void,
    visibility: ?fn (?*struct_tui_context, bool, bool, ?*c_void) callconv(.C) void,
    exec_state: ?fn (?*struct_tui_context, c_int, ?*c_void) callconv(.C) void,
    cli_command: ?fn (?*struct_tui_context, [*c][*c]const u8, usize, c_int, [*c][*c]const u8, [*c]usize) callconv(.C) c_int,
};
pub const TUI_ERRC_OK = @enumToInt(enum_tui_process_errc.TUI_ERRC_OK);
pub const TUI_ERRC_BAD_ARG = @enumToInt(enum_tui_process_errc.TUI_ERRC_BAD_ARG);
pub const TUI_ERRC_BAD_FD = @enumToInt(enum_tui_process_errc.TUI_ERRC_BAD_FD);
pub const TUI_ERRC_BAD_CTX = @enumToInt(enum_tui_process_errc.TUI_ERRC_BAD_CTX);
pub const enum_tui_process_errc = extern enum(c_int) {
    TUI_ERRC_OK = 0,
    TUI_ERRC_BAD_ARG = -1,
    TUI_ERRC_BAD_FD = -2,
    TUI_ERRC_BAD_CTX = -3,
    _,
};
pub const struct_tui_region = extern struct {
    dx: c_int,
    dy: c_int,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
};
pub const struct_tui_process_res = extern struct {
    ok: u32,
    bad: u32,
    errc: c_int,
};
pub const TUIWND_SPLIT_NONE = @enumToInt(enum_tui_subwnd_hint.TUIWND_SPLIT_NONE);
pub const TUIWND_SPLIT_LEFT = @enumToInt(enum_tui_subwnd_hint.TUIWND_SPLIT_LEFT);
pub const TUIWND_SPLIT_RIGHT = @enumToInt(enum_tui_subwnd_hint.TUIWND_SPLIT_RIGHT);
pub const TUIWND_SPLIT_TOP = @enumToInt(enum_tui_subwnd_hint.TUIWND_SPLIT_TOP);
pub const TUIWND_SPLIT_BOTTOM = @enumToInt(enum_tui_subwnd_hint.TUIWND_SPLIT_BOTTOM);
pub const TUIWND_JOIN_LEFT = @enumToInt(enum_tui_subwnd_hint.TUIWND_JOIN_LEFT);
pub const TUIWND_JOIN_RIGHT = @enumToInt(enum_tui_subwnd_hint.TUIWND_JOIN_RIGHT);
pub const TUIWND_JOIN_TOP = @enumToInt(enum_tui_subwnd_hint.TUIWND_JOIN_TOP);
pub const TUIWND_JOIN_DOWN = @enumToInt(enum_tui_subwnd_hint.TUIWND_JOIN_DOWN);
pub const TUIWND_TAB = @enumToInt(enum_tui_subwnd_hint.TUIWND_TAB);
pub const enum_tui_subwnd_hint = extern enum(c_int) {
    TUIWND_SPLIT_NONE = 0,
    TUIWND_SPLIT_LEFT = 1,
    TUIWND_SPLIT_RIGHT = 2,
    TUIWND_SPLIT_TOP = 3,
    TUIWND_SPLIT_BOTTOM = 4,
    TUIWND_JOIN_LEFT = 5,
    TUIWND_JOIN_RIGHT = 6,
    TUIWND_JOIN_TOP = 7,
    TUIWND_JOIN_DOWN = 8,
    TUIWND_TAB = 9,
    _,
};
pub const struct_tui_subwnd_req = extern struct {
    dir: c_int,
    rows: usize,
    columns: usize,
    hint: enum_tui_subwnd_hint,
};
pub extern fn arcan_tui_setup(con: [*c]arcan_tui_conn, parent: ?*struct_tui_context, cfg: [*c]const struct_tui_cbcfg, cfg_sz: usize, ...) ?*struct_tui_context;
pub extern fn arcan_tui_bind(con: [*c]arcan_tui_conn, orphan: ?*struct_tui_context) bool;
pub extern fn arcan_tui_destroy(?*struct_tui_context, message: [*c]const u8) void;
pub extern fn arcan_tui_process(contexts: [*c]?*struct_tui_context, n_contexts: usize, fdset: [*c]c_int, fdset_sz: usize, timeout: c_int) struct_tui_process_res;
pub extern fn arcan_tui_get_handles(contexts: [*c]?*struct_tui_context, n_contexts: usize, fddst: [*c]c_int, fddst_lim: usize) usize;
pub extern fn arcan_tui_refresh(?*struct_tui_context) c_int;
pub extern fn arcan_tui_invalidate(?*struct_tui_context) void;
pub extern fn arcan_tui_acon(?*struct_tui_context) [*c]arcan_tui_conn;
pub extern fn arcan_tui_open_display(title: [*c]const u8, ident: [*c]const u8) [*c]arcan_tui_conn;
pub extern fn arcan_tui_copy(?*struct_tui_context, utf8_msg: [*c]const u8) bool;
pub extern fn arcan_tui_ident(?*struct_tui_context, ident: [*c]const u8) void;
pub extern fn arcan_tui_getxy(?*struct_tui_context, x: usize, y: usize, f: bool) struct_tui_cell;
pub extern fn arcan_tui_request_subwnd(?*struct_tui_context, type: c_uint, id: u16) void;
pub extern fn arcan_tui_request_subwnd_ext(?*struct_tui_context, type: c_uint, id: u16, req: struct_tui_subwnd_req, req_sz: usize) void;
pub extern fn arcan_tui_update_handlers(?*struct_tui_context, new_handlers: [*c]const struct_tui_cbcfg, old: [*c]struct_tui_cbcfg, cb_sz: usize) bool;
pub extern fn arcan_tui_wndhint(wnd: ?*struct_tui_context, par: ?*struct_tui_context, cons: struct_tui_constraints) void;
pub extern fn arcan_tui_announce_io(c: ?*struct_tui_context, immediately: bool, input_descr: [*c]const u8, output_descr: [*c]const u8) void;
pub extern fn arcan_tui_bgcopy(?*struct_tui_context, fdin: c_int, fdout: c_int, sigfd: c_int, flags: c_int) void;
pub extern fn arcan_tui_statesize(c: ?*struct_tui_context, sz: usize) void;
pub extern fn arcan_tui_erase_screen(?*struct_tui_context, protect: bool) void;
pub extern fn arcan_tui_eraseattr_screen(?*struct_tui_context, protect: bool, struct_tui_screen_attr) void;
pub extern fn arcan_tui_erase_region(?*struct_tui_context, x1: usize, y1: usize, x2: usize, y2: usize, protect: bool) void;
pub extern fn arcan_tui_erase_sb(?*struct_tui_context) void;
pub extern fn arcan_tui_eraseattr_region(?*struct_tui_context, x1: usize, y1: usize, x2: usize, y2: usize, protect: bool, struct_tui_screen_attr) void;
pub extern fn arcan_tui_erase_cursor_to_screen(?*struct_tui_context, protect: bool) void;
pub extern fn arcan_tui_erase_screen_to_cursor(?*struct_tui_context, protect: bool) void;
pub extern fn arcan_tui_erase_cursor_to_end(?*struct_tui_context, protect: bool) void;
pub extern fn arcan_tui_erase_home_to_cursor(?*struct_tui_context, protect: bool) void;
pub extern fn arcan_tui_erase_current_line(?*struct_tui_context, protect: bool) void;
pub extern fn arcan_tui_erase_chars(?*struct_tui_context, n: usize) void;
pub extern fn arcan_tui_write(?*struct_tui_context, ucode: u32, [*c]const struct_tui_screen_attr) void;
pub extern fn arcan_tui_writeu8(?*struct_tui_context, u8: [*c]const u8, n: usize, [*c]struct_tui_screen_attr) bool;
pub extern fn arcan_tui_writestr(?*struct_tui_context, str: [*c]const u8, [*c]struct_tui_screen_attr) bool;
pub extern fn arcan_tui_printf(ctx: ?*struct_tui_context, attr: [*c]struct_tui_screen_attr, msg: [*c]const u8, ...) usize;
pub extern fn arcan_tui_cursorpos(?*struct_tui_context, x: [*c]usize, y: [*c]usize) void;
pub extern fn arcan_tui_defcattr(tui: ?*struct_tui_context, group: c_int) struct_tui_screen_attr;
pub extern fn arcan_tui_get_color(tui: ?*struct_tui_context, group: c_int, rgb: [*c]u8) void;
pub extern fn arcan_tui_get_bgcolor(tui: ?*struct_tui_context, group: c_int, rgb: [*c]u8) void;
pub extern fn arcan_tui_set_color(tui: ?*struct_tui_context, group: c_int, rgb: [*c]u8) void;
pub extern fn arcan_tui_set_bgcolor(tui: ?*struct_tui_context, group: c_int, rgb: [*c]u8) void;
pub extern fn arcan_tui_reset(?*struct_tui_context) void;
pub extern fn arcan_tui_reset_labels(?*struct_tui_context) void;
pub extern fn arcan_tui_set_flags(?*struct_tui_context, tui_flags: c_int) c_int;
pub extern fn arcan_tui_reset_flags(?*struct_tui_context, tui_flags: c_int) void;
pub extern fn arcan_tui_handover(?*struct_tui_context, [*c]arcan_tui_conn, constraints: [*c]struct_tui_constraints, path: [*c]const u8, argv: [*c]const [*c]u8, env: [*c]const [*c]u8, flags: c_int) pid_t;
pub extern fn arcan_tui_scrollhint(?*struct_tui_context, n_regions: usize, [*c]struct_tui_region) void;
pub extern fn arcan_tui_statedescr(?*struct_tui_context) [*c]u8;
pub extern fn arcan_tui_dimensions(?*struct_tui_context, rows: [*c]usize, cols: [*c]usize) void;
pub extern fn arcan_tui_ucs4utf8(u32, dst: [*c]u8) usize;
pub extern fn arcan_tui_ucs4utf8_s(u32, dst: [*c]u8) usize;
pub extern fn arcan_tui_utf8ucs4(src: [*c]const u8, dst: [*c]u32) isize;
pub extern fn arcan_tui_defattr(?*struct_tui_context, attr: [*c]struct_tui_screen_attr) struct_tui_screen_attr;
pub extern fn arcan_tui_refinc(?*struct_tui_context) void;
pub extern fn arcan_tui_refdec(?*struct_tui_context) void;
pub extern fn arcan_tui_move_to(?*struct_tui_context, x: usize, y: usize) void;
pub extern fn arcan_tui_hasglyph(?*struct_tui_context, u32) bool;
pub extern fn arcan_tui_message(?*struct_tui_context, target: c_int, msg: [*c]const u8) void;
pub extern fn arcan_tui_progress(?*struct_tui_context, type: c_int, status: f32) void;
pub extern fn arcan_tui_set_tabstop(?*struct_tui_context) void;
pub extern fn arcan_tui_insert_lines(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_newline(?*struct_tui_context) void;
pub extern fn arcan_tui_delete_lines(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_insert_chars(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_delete_chars(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_tab_right(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_tab_left(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_scroll_up(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_scroll_down(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_reset_tabstop(?*struct_tui_context) void;
pub extern fn arcan_tui_reset_all_tabstops(?*struct_tui_context) void;
pub extern fn arcan_tui_move_up(?*struct_tui_context, num: usize, scroll: bool) void;
pub extern fn arcan_tui_move_down(?*struct_tui_context, num: usize, scroll: bool) void;
pub extern fn arcan_tui_move_left(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_move_right(?*struct_tui_context, usize) void;
pub extern fn arcan_tui_move_line_end(?*struct_tui_context) void;
pub extern fn arcan_tui_move_line_home(?*struct_tui_context) void;
pub extern fn arcan_tui_set_margins(?*struct_tui_context, top: usize, bottom: usize) c_int;
pub const __gwchar_t = c_int;
const struct_unnamed_85 = extern struct {
    quot: c_long,
    rem: c_long,
};
pub const imaxdiv_t = struct_unnamed_85;
pub extern fn imaxabs(__n: intmax_t) intmax_t;
pub extern fn imaxdiv(__numer: intmax_t, __denom: intmax_t) imaxdiv_t;
pub fn strtoimax(noalias arg___nptr: [*c]const u8, noalias arg___endptr: [*c][*c]u8, arg___base: c_int) callconv(.C) intmax_t {
    var __nptr = arg___nptr;
    var __endptr = arg___endptr;
    var __base = arg___base;
    return __strtol_internal(__nptr, __endptr, __base, @as(c_int, 0));
}
pub fn strtoumax(noalias arg___nptr: [*c]const u8, noalias arg___endptr: [*c][*c]u8, arg___base: c_int) callconv(.C) uintmax_t {
    var __nptr = arg___nptr;
    var __endptr = arg___endptr;
    var __base = arg___base;
    return __strtoul_internal(__nptr, __endptr, __base, @as(c_int, 0));
}
pub fn wcstoimax(noalias arg___nptr: [*c]const __gwchar_t, noalias arg___endptr: [*c][*c]__gwchar_t, arg___base: c_int) callconv(.C) intmax_t {
    var __nptr = arg___nptr;
    var __endptr = arg___endptr;
    var __base = arg___base;
    return __wcstol_internal(__nptr, __endptr, __base, @as(c_int, 0));
}
pub fn wcstoumax(noalias arg___nptr: [*c]const __gwchar_t, noalias arg___endptr: [*c][*c]__gwchar_t, arg___base: c_int) callconv(.C) uintmax_t {
    var __nptr = arg___nptr;
    var __endptr = arg___endptr;
    var __base = arg___base;
    return __wcstoul_internal(__nptr, __endptr, __base, @as(c_int, 0));
}
pub extern fn __strtol_internal(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int, __group: c_int) c_long;
pub extern fn __strtoul_internal(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int, __group: c_int) c_ulong;
pub extern fn __wcstol_internal(noalias __nptr: [*c]const __gwchar_t, noalias __endptr: [*c][*c]__gwchar_t, __base: c_int, __group: c_int) c_long;
pub extern fn __wcstoul_internal(noalias __nptr: [*c]const __gwchar_t, noalias __endptr: [*c][*c]__gwchar_t, __base: c_int, __group: c_int) c_ulong;
pub extern fn __errno_location() [*c]c_int; // /usr/lib/zig/include/stdarg.h:17:29: warning: TODO implement translation of CastKind BuiltinFnToFnPtr
pub const trace = @compileError("unable to translate function"); // tui_test.c:12:20
// tui_test.c:28:2: warning: TODO implement translation of DeclStmt kind Record
pub const redraw = @compileError("unable to translate function"); // tui_test.c:23:13
pub fn query_label(arg_ctx: ?*struct_tui_context, arg_ind: usize, arg_country: [*c]const u8, arg_lang: [*c]const u8, arg_dstlbl: [*c]struct_tui_labelent, arg_t: ?*c_void) callconv(.C) bool {
    var ctx = arg_ctx;
    var ind = arg_ind;
    var country = arg_country;
    var lang = arg_lang;
    var dstlbl = arg_dstlbl;
    var t = arg_t;
    trace("query_label(%zu for %s:%s)\n", ind, if (country != null) country else "unknown(country)", if (lang != null) lang else "unknown(language)");
    return @as(c_int, 0) != 0;
}
pub fn on_label(arg_c: ?*struct_tui_context, arg_label: [*c]const u8, arg_act: bool, arg_t: ?*c_void) callconv(.C) bool {
    var c = arg_c;
    var label = arg_label;
    var act = arg_act;
    var t = arg_t;
    trace("label(%s)", label);
    return @as(c_int, 1) != 0;
}
pub fn on_alabel(arg_c: ?*struct_tui_context, arg_label: [*c]const u8, arg_smpls: [*c]const i16, arg_n: usize, arg_rel: bool, arg_datatype: u8, arg_t: ?*c_void) callconv(.C) bool {
    var c = arg_c;
    var label = arg_label;
    var smpls = arg_smpls;
    var n = arg_n;
    var rel = arg_rel;
    var datatype = arg_datatype;
    var t = arg_t;
    trace("a-label(%s)", label);
    return @as(c_int, 0) != 0;
}
pub fn on_mouse(arg_c: ?*struct_tui_context, arg_relative: bool, arg_x: c_int, arg_y: c_int, arg_modifiers: c_int, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var relative = arg_relative;
    var x = arg_x;
    var y = arg_y;
    var modifiers = arg_modifiers;
    var t = arg_t;
    trace("mouse(%d:%d, mods:%d, rel: %d", x, y, modifiers, @intCast(c_int, @bitCast(i1, @intCast(u1, @boolToInt(relative)))));
}
pub fn on_key(arg_c: ?*struct_tui_context, arg_xkeysym: u32, arg_scancode: u8, arg_mods: u8, arg_subid: u16, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var xkeysym = arg_xkeysym;
    var scancode = arg_scancode;
    var mods = arg_mods;
    var subid = arg_subid;
    var t = arg_t;
    trace("unknown_key(%u,%u,%u)", xkeysym, @bitCast(c_int, @as(c_uint, scancode)), @bitCast(c_int, @as(c_uint, subid)));
}
pub fn on_u8(arg_c: ?*struct_tui_context, arg_u8_1: [*c]const u8, arg_len: usize, arg_t: ?*c_void) callconv(.C) bool {
    var c = arg_c;
    var u8_1 = arg_u8_1;
    var len = arg_len;
    var t = arg_t;
    var buf: [5]u8 = [1]u8{
        @bitCast(u8, @truncate(i8, @as(c_int, 0))),
    } ++ [1]u8{0} ** 4;
    _ = memcpy(@ptrCast(?*c_void, &buf), @ptrCast(?*const c_void, u8_1), if (len >= @bitCast(c_ulong, @as(c_long, @as(c_int, 5)))) @bitCast(c_ulong, @as(c_long, @as(c_int, 4))) else len);
    trace("utf8-input: %s", &buf);
    _ = arcan_tui_writeu8(c, &buf, len, null);
    return @as(c_int, 1) != 0;
}
pub fn on_misc(arg_c: ?*struct_tui_context, arg_ev: [*c]const arcan_ioevent, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var ev = arg_ev;
    var t = arg_t;
    trace("on_ioevent()");
}
pub fn on_state(arg_c: ?*struct_tui_context, arg_input: bool, arg_fd: c_int, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var input = arg_input;
    var fd = arg_fd;
    var t = arg_t;
    trace("on-state(in:%d)", @intCast(c_int, @bitCast(i1, @intCast(u1, @boolToInt(input)))));
}
pub fn on_bchunk(arg_c: ?*struct_tui_context, arg_input: bool, arg_size: u64, arg_fd: c_int, arg_tag: [*c]const u8, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var input = arg_input;
    var size = arg_size;
    var fd = arg_fd;
    var tag = arg_tag;
    var t = arg_t;
    trace("on_bchunk(%lu, in:%d)", size, @intCast(c_int, @bitCast(i1, @intCast(u1, @boolToInt(input)))));
}
pub fn on_vpaste(arg_c: ?*struct_tui_context, arg_vidp: [*c]shmif_pixel, arg_w: usize, arg_h: usize, arg_stride: usize, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var vidp = arg_vidp;
    var w = arg_w;
    var h = arg_h;
    var stride = arg_stride;
    var t = arg_t;
    trace("on_vpaste(%zu, %zu str %zu)", w, h, stride);
}
pub fn on_apaste(arg_c: ?*struct_tui_context, arg_audp: [*c]shmif_asample, arg_n_samples: usize, arg_frequency: usize, arg_nch: usize, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var audp = arg_audp;
    var n_samples = arg_n_samples;
    var frequency = arg_frequency;
    var nch = arg_nch;
    var t = arg_t;
    trace("on_apaste(%zu @ %zu:%zu)", n_samples, frequency, nch);
}
pub fn on_tick(arg_c: ?*struct_tui_context, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var t = arg_t;
}
pub fn on_utf8_paste(arg_c: ?*struct_tui_context, arg_str: [*c]const u8, arg_len: usize, arg_cont: bool, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var str = arg_str;
    var len = arg_len;
    var cont = arg_cont;
    var t = arg_t;
    trace("utf8-paste(%s):%d", str, @intCast(c_int, @bitCast(i1, @intCast(u1, @boolToInt(cont)))));
}
pub fn on_resize(arg_c: ?*struct_tui_context, arg_neww: usize, arg_newh: usize, arg_col: usize, arg_row: usize, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var neww = arg_neww;
    var newh = arg_newh;
    var col = arg_col;
    var row = arg_row;
    var t = arg_t;
    trace("resize(%zu(%zu),%zu(%zu))", neww, col, newh, row);
    redraw(c);
}
pub fn on_recolor(arg_c: ?*struct_tui_context, arg_t: ?*c_void) callconv(.C) void {
    var c = arg_c;
    var t = arg_t;
    redraw(c);
} // (no file):0:0: warning: type does not have an implicit init value
pub const main = @compileError("unable to translate function"); // tui_test.c:280:5
pub const __INTMAX_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // (no file):62:9
pub const __UINTMAX_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_unsigned"); // (no file):66:9
pub const __PTRDIFF_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // (no file):73:9
pub const __INTPTR_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // (no file):77:9
pub const __SIZE_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_unsigned"); // (no file):81:9
pub const __UINTPTR_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_unsigned"); // (no file):96:9
pub const __INT64_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // (no file):159:9
pub const __UINT64_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_unsigned"); // (no file):187:9
pub const __INT_LEAST64_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // (no file):225:9
pub const __UINT_LEAST64_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_unsigned"); // (no file):229:9
pub const __INT_FAST64_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // (no file):265:9
pub const __UINT_FAST64_TYPE__ = @compileError("unable to translate C expr: unexpected token .Keyword_unsigned"); // (no file):269:9
pub const __GLIBC_USE = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/features.h:179:9
pub const __NTH = @compileError("unable to translate C expr: unexpected token .Identifier"); // /usr/include/sys/cdefs.h:57:11
pub const __NTHNL = @compileError("unable to translate C expr: unexpected token .Identifier"); // /usr/include/sys/cdefs.h:58:11
pub const __CONCAT = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/sys/cdefs.h:105:9
pub const __STRING = @compileError("unable to translate C expr: unexpected token .Hash"); // /usr/include/sys/cdefs.h:106:9
pub const __ptr_t = @compileError("unable to translate C expr: unexpected token .Nl"); // /usr/include/sys/cdefs.h:109:9
pub const __warndecl = @compileError("unable to translate C expr: unexpected token .Keyword_extern"); // /usr/include/sys/cdefs.h:133:10
pub const __warnattr = @compileError("unable to translate C expr: unexpected token .Nl"); // /usr/include/sys/cdefs.h:134:10
pub const __errordecl = @compileError("unable to translate C expr: unexpected token .Keyword_extern"); // /usr/include/sys/cdefs.h:135:10
pub const __flexarr = @compileError("unable to translate C expr: unexpected token .LBracket"); // /usr/include/sys/cdefs.h:143:10
pub const __REDIRECT = @compileError("unable to translate C expr: unexpected token .Hash"); // /usr/include/sys/cdefs.h:174:10
pub const __REDIRECT_NTH = @compileError("unable to translate C expr: unexpected token .Hash"); // /usr/include/sys/cdefs.h:181:11
pub const __REDIRECT_NTHNL = @compileError("unable to translate C expr: unexpected token .Hash"); // /usr/include/sys/cdefs.h:183:11
pub const __ASMNAME2 = @compileError("unable to translate C expr: unexpected token .Identifier"); // /usr/include/sys/cdefs.h:187:10
pub const __attribute_alloc_size__ = @compileError("unable to translate C expr: unexpected token .Nl"); // /usr/include/sys/cdefs.h:219:10
pub const __extern_inline = @compileError("unable to translate C expr: unexpected token .Keyword_extern"); // /usr/include/sys/cdefs.h:346:11
pub const __extern_always_inline = @compileError("unable to translate C expr: unexpected token .Keyword_extern"); // /usr/include/sys/cdefs.h:347:11
pub const __attribute_copy__ = @compileError("unable to translate C expr: unexpected token .Nl"); // /usr/include/sys/cdefs.h:441:10
pub const __LDBL_REDIR2_DECL = @compileError("unable to translate C expr: unexpected token .Nl"); // /usr/include/sys/cdefs.h:512:10
pub const __LDBL_REDIR_DECL = @compileError("unable to translate C expr: unexpected token .Nl"); // /usr/include/sys/cdefs.h:513:10
pub const __glibc_macro_warning1 = @compileError("unable to translate C expr: unexpected token .Hash"); // /usr/include/sys/cdefs.h:527:10
pub const __attr_access = @compileError("unable to translate C expr: unexpected token .Nl"); // /usr/include/sys/cdefs.h:559:11
pub const __f32 = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/bits/floatn-common.h:91:12
pub const __f64x = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/bits/floatn-common.h:120:13
pub const __CFLOAT32 = @compileError("unable to translate C expr: unexpected token .Keyword_complex"); // /usr/include/bits/floatn-common.h:149:12
pub const __CFLOAT64 = @compileError("unable to translate C expr: unexpected token .Keyword_complex"); // /usr/include/bits/floatn-common.h:160:13
pub const __CFLOAT32X = @compileError("unable to translate C expr: unexpected token .Keyword_complex"); // /usr/include/bits/floatn-common.h:169:12
pub const __CFLOAT64X = @compileError("unable to translate C expr: unexpected token .Keyword_complex"); // /usr/include/bits/floatn-common.h:178:13
pub const __builtin_huge_valf32 = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/bits/floatn-common.h:218:12
pub const __builtin_inff32 = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/bits/floatn-common.h:219:12
pub const __builtin_huge_valf64 = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/bits/floatn-common.h:255:13
pub const __builtin_inff64 = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/bits/floatn-common.h:256:13
pub const __builtin_huge_valf32x = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/bits/floatn-common.h:272:12
pub const __builtin_inff32x = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/bits/floatn-common.h:273:12
pub const __builtin_huge_valf64x = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/bits/floatn-common.h:289:13
pub const __builtin_inff64x = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/bits/floatn-common.h:290:13
pub const MB_CUR_MAX = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/stdlib.h:96:9
pub const __S16_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:109:9
pub const __U16_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:110:9
pub const __SLONGWORD_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:113:9
pub const __ULONGWORD_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:114:9
pub const __SQUAD_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:128:10
pub const __UQUAD_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:129:10
pub const __SWORD_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:130:10
pub const __UWORD_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:131:10
pub const __S64_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:134:10
pub const __U64_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_int"); // /usr/include/bits/types.h:135:10
pub const __STD_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_typedef"); // /usr/include/bits/types.h:137:10
pub const __TIMER_T_TYPE = @compileError("unable to translate C expr: unexpected token .Nl"); // /usr/include/bits/typesizes.h:71:9
pub const __FSID_T_TYPE = @compileError("unable to translate C expr: unexpected token .Keyword_struct"); // /usr/include/bits/typesizes.h:73:9
pub const __FD_ZERO = @compileError("unable to translate C expr: unexpected token .Keyword_do"); // /usr/include/bits/select.h:25:9
pub const __FD_SET = @compileError("unable to translate C expr: expected ')''"); // /usr/include/bits/select.h:32:9
pub const __FD_CLR = @compileError("unable to translate C expr: expected ')''"); // /usr/include/bits/select.h:34:9
pub const _SIGSET_NWORDS = @compileError("unable to translate C expr: expected ')'"); // /usr/include/bits/types/__sigset_t.h:4:9
pub const __PTHREAD_MUTEX_INITIALIZER = @compileError("unable to translate C expr: unexpected token .LBrace"); // /usr/include/bits/struct_mutex.h:56:10
pub const __PTHREAD_RWLOCK_ELISION_EXTRA = @compileError("unable to translate C expr: unexpected token .LBrace"); // /usr/include/bits/struct_rwlock.h:40:11
pub const __ONCE_FLAG_INIT = @compileError("unable to translate C expr: unexpected token .LBrace"); // /usr/include/bits/thread-shared-types.h:127:9
pub const __INT64_C = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/stdint.h:106:11
pub const __UINT64_C = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/stdint.h:107:11
pub const INT64_C = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/stdint.h:252:11
pub const UINT32_C = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/stdint.h:260:10
pub const UINT64_C = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/stdint.h:262:11
pub const INTMAX_C = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/stdint.h:269:11
pub const UINTMAX_C = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/stdint.h:270:11
pub const __getc_unlocked_body = @compileError("TODO postfix inc/dec expr"); // /usr/include/bits/types/struct_FILE.h:102:9
pub const __putc_unlocked_body = @compileError("TODO postfix inc/dec expr"); // /usr/include/bits/types/struct_FILE.h:106:9
pub const ATOMIC_FLAG_INIT = @compileError("unable to translate C expr: unexpected token .LBrace"); // /usr/lib/zig/include/stdatomic.h:151:9
pub const LOG = @compileError("unable to translate C expr: expected ')'"); // /usr/include/arcan/shmif/arcan_shmif_interop.h:47:9
pub const _INT_SHMIF_TMERGE = @compileError("unable to translate C expr: unexpected token .HashHash"); // /usr/include/arcan/shmif/arcan_shmif_event.h:644:9
pub const SHMIF_CMRAMP_RVA = @compileError("unable to translate C expr: unexpected token .Keyword_struct"); // /usr/include/arcan/shmif/arcan_shmif_sub.h:201:9
pub const errno = @compileError("unable to translate C expr: unexpected token .RParen"); // /usr/include/errno.h:38:10
pub const __llvm__ = 1;
pub const __clang__ = 1;
pub const __clang_major__ = 11;
pub const __clang_minor__ = 0;
pub const __clang_patchlevel__ = 0;
pub const __clang_version__ = "11.0.0 ";
pub const __GNUC__ = 4;
pub const __GNUC_MINOR__ = 2;
pub const __GNUC_PATCHLEVEL__ = 1;
pub const __GXX_ABI_VERSION = 1002;
pub const __ATOMIC_RELAXED = 0;
pub const __ATOMIC_CONSUME = 1;
pub const __ATOMIC_ACQUIRE = 2;
pub const __ATOMIC_RELEASE = 3;
pub const __ATOMIC_ACQ_REL = 4;
pub const __ATOMIC_SEQ_CST = 5;
pub const __OPENCL_MEMORY_SCOPE_WORK_ITEM = 0;
pub const __OPENCL_MEMORY_SCOPE_WORK_GROUP = 1;
pub const __OPENCL_MEMORY_SCOPE_DEVICE = 2;
pub const __OPENCL_MEMORY_SCOPE_ALL_SVM_DEVICES = 3;
pub const __OPENCL_MEMORY_SCOPE_SUB_GROUP = 4;
pub const __PRAGMA_REDEFINE_EXTNAME = 1;
pub const __VERSION__ = "Clang 11.0.0";
pub const __OBJC_BOOL_IS_BOOL = 0;
pub const __CONSTANT_CFSTRINGS__ = 1;
pub const __OPTIMIZE__ = 1;
pub const __ORDER_LITTLE_ENDIAN__ = 1234;
pub const __ORDER_BIG_ENDIAN__ = 4321;
pub const __ORDER_PDP_ENDIAN__ = 3412;
pub const __BYTE_ORDER__ = __ORDER_LITTLE_ENDIAN__;
pub const __LITTLE_ENDIAN__ = 1;
pub const _LP64 = 1;
pub const __LP64__ = 1;
pub const __CHAR_BIT__ = 8;
pub const __SCHAR_MAX__ = 127;
pub const __SHRT_MAX__ = 32767;
pub const __INT_MAX__ = 2147483647;
pub const __LONG_MAX__ = @as(c_long, 9223372036854775807);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __WCHAR_MAX__ = 2147483647;
pub const __WINT_MAX__ = @as(c_uint, 4294967295);
pub const __INTMAX_MAX__ = @as(c_long, 9223372036854775807);
pub const __SIZE_MAX__ = @as(c_ulong, 18446744073709551615);
pub const __UINTMAX_MAX__ = @as(c_ulong, 18446744073709551615);
pub const __PTRDIFF_MAX__ = @as(c_long, 9223372036854775807);
pub const __INTPTR_MAX__ = @as(c_long, 9223372036854775807);
pub const __UINTPTR_MAX__ = @as(c_ulong, 18446744073709551615);
pub const __SIZEOF_DOUBLE__ = 8;
pub const __SIZEOF_FLOAT__ = 4;
pub const __SIZEOF_INT__ = 4;
pub const __SIZEOF_LONG__ = 8;
pub const __SIZEOF_LONG_DOUBLE__ = 16;
pub const __SIZEOF_LONG_LONG__ = 8;
pub const __SIZEOF_POINTER__ = 8;
pub const __SIZEOF_SHORT__ = 2;
pub const __SIZEOF_PTRDIFF_T__ = 8;
pub const __SIZEOF_SIZE_T__ = 8;
pub const __SIZEOF_WCHAR_T__ = 4;
pub const __SIZEOF_WINT_T__ = 4;
pub const __SIZEOF_INT128__ = 16;
pub const __INTMAX_FMTd__ = "ld";
pub const __INTMAX_FMTi__ = "li";
pub const __INTMAX_C_SUFFIX__ = L;
pub const __UINTMAX_FMTo__ = "lo";
pub const __UINTMAX_FMTu__ = "lu";
pub const __UINTMAX_FMTx__ = "lx";
pub const __UINTMAX_FMTX__ = "lX";
pub const __UINTMAX_C_SUFFIX__ = UL;
pub const __INTMAX_WIDTH__ = 64;
pub const __PTRDIFF_FMTd__ = "ld";
pub const __PTRDIFF_FMTi__ = "li";
pub const __PTRDIFF_WIDTH__ = 64;
pub const __INTPTR_FMTd__ = "ld";
pub const __INTPTR_FMTi__ = "li";
pub const __INTPTR_WIDTH__ = 64;
pub const __SIZE_FMTo__ = "lo";
pub const __SIZE_FMTu__ = "lu";
pub const __SIZE_FMTx__ = "lx";
pub const __SIZE_FMTX__ = "lX";
pub const __SIZE_WIDTH__ = 64;
pub const __WCHAR_TYPE__ = c_int;
pub const __WCHAR_WIDTH__ = 32;
pub const __WINT_TYPE__ = c_uint;
pub const __WINT_WIDTH__ = 32;
pub const __SIG_ATOMIC_WIDTH__ = 32;
pub const __SIG_ATOMIC_MAX__ = 2147483647;
pub const __CHAR16_TYPE__ = c_ushort;
pub const __CHAR32_TYPE__ = c_uint;
pub const __UINTMAX_WIDTH__ = 64;
pub const __UINTPTR_FMTo__ = "lo";
pub const __UINTPTR_FMTu__ = "lu";
pub const __UINTPTR_FMTx__ = "lx";
pub const __UINTPTR_FMTX__ = "lX";
pub const __UINTPTR_WIDTH__ = 64;
pub const __FLT_DENORM_MIN__ = @as(f32, 1.40129846e-45);
pub const __FLT_HAS_DENORM__ = 1;
pub const __FLT_DIG__ = 6;
pub const __FLT_DECIMAL_DIG__ = 9;
pub const __FLT_EPSILON__ = @as(f32, 1.19209290e-7);
pub const __FLT_HAS_INFINITY__ = 1;
pub const __FLT_HAS_QUIET_NAN__ = 1;
pub const __FLT_MANT_DIG__ = 24;
pub const __FLT_MAX_10_EXP__ = 38;
pub const __FLT_MAX_EXP__ = 128;
pub const __FLT_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_MIN_10_EXP__ = -37;
pub const __FLT_MIN_EXP__ = -125;
pub const __FLT_MIN__ = @as(f32, 1.17549435e-38);
pub const __DBL_DENORM_MIN__ = 4.9406564584124654e-324;
pub const __DBL_HAS_DENORM__ = 1;
pub const __DBL_DIG__ = 15;
pub const __DBL_DECIMAL_DIG__ = 17;
pub const __DBL_EPSILON__ = 2.2204460492503131e-16;
pub const __DBL_HAS_INFINITY__ = 1;
pub const __DBL_HAS_QUIET_NAN__ = 1;
pub const __DBL_MANT_DIG__ = 53;
pub const __DBL_MAX_10_EXP__ = 308;
pub const __DBL_MAX_EXP__ = 1024;
pub const __DBL_MAX__ = 1.7976931348623157e+308;
pub const __DBL_MIN_10_EXP__ = -307;
pub const __DBL_MIN_EXP__ = -1021;
pub const __DBL_MIN__ = 2.2250738585072014e-308;
pub const __LDBL_DENORM_MIN__ = @as(c_longdouble, 3.64519953188247460253e-4951);
pub const __LDBL_HAS_DENORM__ = 1;
pub const __LDBL_DIG__ = 18;
pub const __LDBL_DECIMAL_DIG__ = 21;
pub const __LDBL_EPSILON__ = @as(c_longdouble, 1.08420217248550443401e-19);
pub const __LDBL_HAS_INFINITY__ = 1;
pub const __LDBL_HAS_QUIET_NAN__ = 1;
pub const __LDBL_MANT_DIG__ = 64;
pub const __LDBL_MAX_10_EXP__ = 4932;
pub const __LDBL_MAX_EXP__ = 16384;
pub const __LDBL_MAX__ = @as(c_longdouble, 1.18973149535723176502e+4932);
pub const __LDBL_MIN_10_EXP__ = -4931;
pub const __LDBL_MIN_EXP__ = -16381;
pub const __LDBL_MIN__ = @as(c_longdouble, 3.36210314311209350626e-4932);
pub const __POINTER_WIDTH__ = 64;
pub const __BIGGEST_ALIGNMENT__ = 16;
pub const __WINT_UNSIGNED__ = 1;
pub const __INT8_TYPE__ = i8;
pub const __INT8_FMTd__ = "hhd";
pub const __INT8_FMTi__ = "hhi";
pub const __INT16_TYPE__ = c_short;
pub const __INT16_FMTd__ = "hd";
pub const __INT16_FMTi__ = "hi";
pub const __INT32_TYPE__ = c_int;
pub const __INT32_FMTd__ = "d";
pub const __INT32_FMTi__ = "i";
pub const __INT64_FMTd__ = "ld";
pub const __INT64_FMTi__ = "li";
pub const __INT64_C_SUFFIX__ = L;
pub const __UINT8_TYPE__ = u8;
pub const __UINT8_FMTo__ = "hho";
pub const __UINT8_FMTu__ = "hhu";
pub const __UINT8_FMTx__ = "hhx";
pub const __UINT8_FMTX__ = "hhX";
pub const __UINT8_MAX__ = 255;
pub const __INT8_MAX__ = 127;
pub const __UINT16_TYPE__ = c_ushort;
pub const __UINT16_FMTo__ = "ho";
pub const __UINT16_FMTu__ = "hu";
pub const __UINT16_FMTx__ = "hx";
pub const __UINT16_FMTX__ = "hX";
pub const __UINT16_MAX__ = 65535;
pub const __INT16_MAX__ = 32767;
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_C_SUFFIX__ = U;
pub const __UINT32_MAX__ = @as(c_uint, 4294967295);
pub const __INT32_MAX__ = 2147483647;
pub const __UINT64_FMTo__ = "lo";
pub const __UINT64_FMTu__ = "lu";
pub const __UINT64_FMTx__ = "lx";
pub const __UINT64_FMTX__ = "lX";
pub const __UINT64_C_SUFFIX__ = UL;
pub const __UINT64_MAX__ = @as(c_ulong, 18446744073709551615);
pub const __INT64_MAX__ = @as(c_long, 9223372036854775807);
pub const __INT_LEAST8_TYPE__ = i8;
pub const __INT_LEAST8_MAX__ = 127;
pub const __INT_LEAST8_FMTd__ = "hhd";
pub const __INT_LEAST8_FMTi__ = "hhi";
pub const __UINT_LEAST8_TYPE__ = u8;
pub const __UINT_LEAST8_MAX__ = 255;
pub const __UINT_LEAST8_FMTo__ = "hho";
pub const __UINT_LEAST8_FMTu__ = "hhu";
pub const __UINT_LEAST8_FMTx__ = "hhx";
pub const __UINT_LEAST8_FMTX__ = "hhX";
pub const __INT_LEAST16_TYPE__ = c_short;
pub const __INT_LEAST16_MAX__ = 32767;
pub const __INT_LEAST16_FMTd__ = "hd";
pub const __INT_LEAST16_FMTi__ = "hi";
pub const __UINT_LEAST16_TYPE__ = c_ushort;
pub const __UINT_LEAST16_MAX__ = 65535;
pub const __UINT_LEAST16_FMTo__ = "ho";
pub const __UINT_LEAST16_FMTu__ = "hu";
pub const __UINT_LEAST16_FMTx__ = "hx";
pub const __UINT_LEAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = 2147483647;
pub const __INT_LEAST32_FMTd__ = "d";
pub const __INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = @as(c_uint, 4294967295);
pub const __UINT_LEAST32_FMTo__ = "o";
pub const __UINT_LEAST32_FMTu__ = "u";
pub const __UINT_LEAST32_FMTx__ = "x";
pub const __UINT_LEAST32_FMTX__ = "X";
pub const __INT_LEAST64_MAX__ = @as(c_long, 9223372036854775807);
pub const __INT_LEAST64_FMTd__ = "ld";
pub const __INT_LEAST64_FMTi__ = "li";
pub const __UINT_LEAST64_MAX__ = @as(c_ulong, 18446744073709551615);
pub const __UINT_LEAST64_FMTo__ = "lo";
pub const __UINT_LEAST64_FMTu__ = "lu";
pub const __UINT_LEAST64_FMTx__ = "lx";
pub const __UINT_LEAST64_FMTX__ = "lX";
pub const __INT_FAST8_TYPE__ = i8;
pub const __INT_FAST8_MAX__ = 127;
pub const __INT_FAST8_FMTd__ = "hhd";
pub const __INT_FAST8_FMTi__ = "hhi";
pub const __UINT_FAST8_TYPE__ = u8;
pub const __UINT_FAST8_MAX__ = 255;
pub const __UINT_FAST8_FMTo__ = "hho";
pub const __UINT_FAST8_FMTu__ = "hhu";
pub const __UINT_FAST8_FMTx__ = "hhx";
pub const __UINT_FAST8_FMTX__ = "hhX";
pub const __INT_FAST16_TYPE__ = c_short;
pub const __INT_FAST16_MAX__ = 32767;
pub const __INT_FAST16_FMTd__ = "hd";
pub const __INT_FAST16_FMTi__ = "hi";
pub const __UINT_FAST16_TYPE__ = c_ushort;
pub const __UINT_FAST16_MAX__ = 65535;
pub const __UINT_FAST16_FMTo__ = "ho";
pub const __UINT_FAST16_FMTu__ = "hu";
pub const __UINT_FAST16_FMTx__ = "hx";
pub const __UINT_FAST16_FMTX__ = "hX";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = 2147483647;
pub const __INT_FAST32_FMTd__ = "d";
pub const __INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = @as(c_uint, 4294967295);
pub const __UINT_FAST32_FMTo__ = "o";
pub const __UINT_FAST32_FMTu__ = "u";
pub const __UINT_FAST32_FMTx__ = "x";
pub const __UINT_FAST32_FMTX__ = "X";
pub const __INT_FAST64_MAX__ = @as(c_long, 9223372036854775807);
pub const __INT_FAST64_FMTd__ = "ld";
pub const __INT_FAST64_FMTi__ = "li";
pub const __UINT_FAST64_MAX__ = @as(c_ulong, 18446744073709551615);
pub const __UINT_FAST64_FMTo__ = "lo";
pub const __UINT_FAST64_FMTu__ = "lu";
pub const __UINT_FAST64_FMTx__ = "lx";
pub const __UINT_FAST64_FMTX__ = "lX";
pub const __FINITE_MATH_ONLY__ = 0;
pub const __GNUC_STDC_INLINE__ = 1;
pub const __GCC_ATOMIC_TEST_AND_SET_TRUEVAL = 1;
pub const __CLANG_ATOMIC_BOOL_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_CHAR_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_CHAR16_T_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_CHAR32_T_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_WCHAR_T_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_SHORT_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_INT_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_LONG_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_LLONG_LOCK_FREE = 2;
pub const __CLANG_ATOMIC_POINTER_LOCK_FREE = 2;
pub const __GCC_ATOMIC_BOOL_LOCK_FREE = 2;
pub const __GCC_ATOMIC_CHAR_LOCK_FREE = 2;
pub const __GCC_ATOMIC_CHAR16_T_LOCK_FREE = 2;
pub const __GCC_ATOMIC_CHAR32_T_LOCK_FREE = 2;
pub const __GCC_ATOMIC_WCHAR_T_LOCK_FREE = 2;
pub const __GCC_ATOMIC_SHORT_LOCK_FREE = 2;
pub const __GCC_ATOMIC_INT_LOCK_FREE = 2;
pub const __GCC_ATOMIC_LONG_LOCK_FREE = 2;
pub const __GCC_ATOMIC_LLONG_LOCK_FREE = 2;
pub const __GCC_ATOMIC_POINTER_LOCK_FREE = 2;
pub const __FLT_EVAL_METHOD__ = 0;
pub const __FLT_RADIX__ = 2;
pub const __DECIMAL_DIG__ = __LDBL_DECIMAL_DIG__;
pub const __GCC_ASM_FLAG_OUTPUTS__ = 1;
pub const __code_model_small__ = 1;
pub const __amd64__ = 1;
pub const __amd64 = 1;
pub const __x86_64 = 1;
pub const __x86_64__ = 1;
pub const __SEG_GS = 1;
pub const __SEG_FS = 1;
pub const __seg_gs = __attribute__(address_space(256));
pub const __seg_fs = __attribute__(address_space(257));
pub const __k8 = 1;
pub const __k8__ = 1;
pub const __tune_k8__ = 1;
pub const __NO_MATH_INLINES = 1;
pub const __AES__ = 1;
pub const __VAES__ = 1;
pub const __PCLMUL__ = 1;
pub const __VPCLMULQDQ__ = 1;
pub const __LZCNT__ = 1;
pub const __RDRND__ = 1;
pub const __FSGSBASE__ = 1;
pub const __BMI__ = 1;
pub const __BMI2__ = 1;
pub const __POPCNT__ = 1;
pub const __PRFCHW__ = 1;
pub const __RDSEED__ = 1;
pub const __ADX__ = 1;
pub const __MWAITX__ = 1;
pub const __MOVBE__ = 1;
pub const __SSE4A__ = 1;
pub const __FMA__ = 1;
pub const __F16C__ = 1;
pub const __SHA__ = 1;
pub const __FXSR__ = 1;
pub const __XSAVE__ = 1;
pub const __XSAVEOPT__ = 1;
pub const __XSAVEC__ = 1;
pub const __XSAVES__ = 1;
pub const __PKU__ = 1;
pub const __CLFLUSHOPT__ = 1;
pub const __CLWB__ = 1;
pub const __WBNOINVD__ = 1;
pub const __SHSTK__ = 1;
pub const __CLZERO__ = 1;
pub const __RDPID__ = 1;
pub const __INVPCID__ = 1;
pub const __AVX2__ = 1;
pub const __AVX__ = 1;
pub const __SSE4_2__ = 1;
pub const __SSE4_1__ = 1;
pub const __SSSE3__ = 1;
pub const __SSE3__ = 1;
pub const __SSE2__ = 1;
pub const __SSE2_MATH__ = 1;
pub const __SSE__ = 1;
pub const __SSE_MATH__ = 1;
pub const __MMX__ = 1;
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_1 = 1;
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_2 = 1;
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_4 = 1;
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 = 1;
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_16 = 1;
pub const __SIZEOF_FLOAT128__ = 16;
pub const unix = 1;
pub const __unix = 1;
pub const __unix__ = 1;
pub const linux = 1;
pub const __linux = 1;
pub const __linux__ = 1;
pub const __ELF__ = 1;
pub const __gnu_linux__ = 1;
pub const __FLOAT128__ = 1;
pub const __STDC__ = 1;
pub const __STDC_HOSTED__ = 1;
pub const __STDC_VERSION__ = @as(c_long, 201710);
pub const __STDC_UTF_16__ = 1;
pub const __STDC_UTF_32__ = 1;
pub const _DEBUG = 1;
pub const _LIBC_LIMITS_H_ = 1;
pub const _FEATURES_H = 1;
pub inline fn __GNUC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GNUC__ << 16) + __GNUC_MINOR__) >= ((maj << 16) + min)) {
    return ((__GNUC__ << 16) + __GNUC_MINOR__) >= ((maj << 16) + min);
}
pub inline fn __glibc_clang_prereq(maj: anytype, min: anytype) @TypeOf(((__clang_major__ << 16) + __clang_minor__) >= ((maj << 16) + min)) {
    return ((__clang_major__ << 16) + __clang_minor__) >= ((maj << 16) + min);
}
pub const _DEFAULT_SOURCE = 1;
pub const __GLIBC_USE_ISOC2X = 0;
pub const __USE_ISOC11 = 1;
pub const __USE_ISOC99 = 1;
pub const __USE_ISOC95 = 1;
pub const __USE_POSIX_IMPLICITLY = 1;
pub const _POSIX_SOURCE = 1;
pub const _POSIX_C_SOURCE = @as(c_long, 200809);
pub const __USE_POSIX = 1;
pub const __USE_POSIX2 = 1;
pub const __USE_POSIX199309 = 1;
pub const __USE_POSIX199506 = 1;
pub const __USE_XOPEN2K = 1;
pub const __USE_XOPEN2K8 = 1;
pub const _ATFILE_SOURCE = 1;
pub const __USE_MISC = 1;
pub const __USE_ATFILE = 1;
pub const __USE_FORTIFY_LEVEL = 0;
pub const __GLIBC_USE_DEPRECATED_GETS = 0;
pub const __GLIBC_USE_DEPRECATED_SCANF = 0;
pub const _STDC_PREDEF_H = 1;
pub const __STDC_IEC_559__ = 1;
pub const __STDC_IEC_559_COMPLEX__ = 1;
pub const __STDC_ISO_10646__ = @as(c_long, 201706);
pub const __GNU_LIBRARY__ = 6;
pub const __GLIBC__ = 2;
pub const __GLIBC_MINOR__ = 32;
pub inline fn __GLIBC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GLIBC__ << 16) + __GLIBC_MINOR__) >= ((maj << 16) + min)) {
    return ((__GLIBC__ << 16) + __GLIBC_MINOR__) >= ((maj << 16) + min);
}
pub const _SYS_CDEFS_H = 1;
pub const __THROW = __attribute__(__nothrow__ ++ __LEAF);
pub const __THROWNL = __attribute__(__nothrow__);
pub inline fn __glibc_clang_has_extension(ext: anytype) @TypeOf(__has_extension(ext)) {
    return __has_extension(ext);
}
pub inline fn __P(args: anytype) @TypeOf(args) {
    return args;
}
pub inline fn __PMT(args: anytype) @TypeOf(args) {
    return args;
}
pub inline fn __bos(ptr: anytype) @TypeOf(__builtin_object_size(ptr, __USE_FORTIFY_LEVEL > 1)) {
    return __builtin_object_size(ptr, __USE_FORTIFY_LEVEL > 1);
}
pub inline fn __bos0(ptr: anytype) @TypeOf(__builtin_object_size(ptr, 0)) {
    return __builtin_object_size(ptr, 0);
}
pub const __glibc_c99_flexarr_available = 1;
pub inline fn __ASMNAME(cname: anytype) @TypeOf(__ASMNAME2(__USER_LABEL_PREFIX__, cname)) {
    return __ASMNAME2(__USER_LABEL_PREFIX__, cname);
}
pub const __attribute_malloc__ = __attribute__(__malloc__);
pub const __attribute_pure__ = __attribute__(__pure__);
pub const __attribute_const__ = __attribute__(__const__);
pub const __attribute_used__ = __attribute__(__used__);
pub const __attribute_noinline__ = __attribute__(__noinline__);
pub const __attribute_deprecated__ = __attribute__(__deprecated__);
pub inline fn __attribute_deprecated_msg__(msg: anytype) @TypeOf(__attribute__(__deprecated__(msg))) {
    return __attribute__(__deprecated__(msg));
}
pub inline fn __attribute_format_arg__(x: anytype) @TypeOf(__attribute__(__format_arg__(x))) {
    return __attribute__(__format_arg__(x));
}
pub inline fn __attribute_format_strfmon__(a: anytype, b: anytype) @TypeOf(__attribute__(__format__(__strfmon__, a, b))) {
    return __attribute__(__format__(__strfmon__, a, b));
}
pub inline fn __nonnull(params: anytype) @TypeOf(__attribute__(__nonnull__ ++ params)) {
    return __attribute__(__nonnull__ ++ params);
}
pub const __attribute_warn_unused_result__ = __attribute__(__warn_unused_result__);
pub const __always_inline = __inline ++ __attribute__(__always_inline__);
pub const __fortify_function = __extern_always_inline ++ __attribute_artificial__;
pub const __restrict_arr = __restrict;
pub inline fn __glibc_unlikely(cond: anytype) @TypeOf(__builtin_expect(cond, 0)) {
    return __builtin_expect(cond, 0);
}
pub inline fn __glibc_likely(cond: anytype) @TypeOf(__builtin_expect(cond, 1)) {
    return __builtin_expect(cond, 1);
}
pub inline fn __glibc_has_attribute(attr: anytype) @TypeOf(__has_attribute(attr)) {
    return __has_attribute(attr);
}
pub const __WORDSIZE = 64;
pub const __WORDSIZE_TIME64_COMPAT32 = 1;
pub const __SYSCALL_WORDSIZE = 64;
pub const __LDOUBLE_REDIRECTS_TO_FLOAT128_ABI = 0;
pub inline fn __LDBL_REDIR1(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto) {
    return name ++ proto;
}
pub inline fn __LDBL_REDIR(name: anytype, proto: anytype) @TypeOf(name ++ proto) {
    return name ++ proto;
}
pub inline fn __LDBL_REDIR1_NTH(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto ++ __THROW) {
    return name ++ proto ++ __THROW;
}
pub inline fn __LDBL_REDIR_NTH(name: anytype, proto: anytype) @TypeOf(name ++ proto ++ __THROW) {
    return name ++ proto ++ __THROW;
}
pub inline fn __REDIRECT_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT(name, proto, alias)) {
    return __REDIRECT(name, proto, alias);
}
pub inline fn __REDIRECT_NTH_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT_NTH(name, proto, alias)) {
    return __REDIRECT_NTH(name, proto, alias);
}
pub inline fn __glibc_macro_warning(message: anytype) @TypeOf(__glibc_macro_warning1(GCC ++ warning ++ message)) {
    return __glibc_macro_warning1(GCC ++ warning ++ message);
}
pub const __HAVE_GENERIC_SELECTION = 1;
pub const __USE_EXTERN_INLINES = 1;
pub const __GLIBC_USE_LIB_EXT2 = 0;
pub const __GLIBC_USE_IEC_60559_BFP_EXT = 0;
pub const __GLIBC_USE_IEC_60559_BFP_EXT_C2X = 0;
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT = 0;
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT_C2X = 0;
pub const __GLIBC_USE_IEC_60559_TYPES_EXT = 0;
pub const MB_LEN_MAX = 16;
pub const SCHAR_MAX = __SCHAR_MAX__;
pub const SHRT_MAX = __SHRT_MAX__;
pub const INT_MAX = __INT_MAX__;
pub const LONG_MAX = __LONG_MAX__;
pub const SCHAR_MIN = -__SCHAR_MAX__ - 1;
pub const SHRT_MIN = -__SHRT_MAX__ - 1;
pub const INT_MIN = -__INT_MAX__ - 1;
pub const LONG_MIN = -__LONG_MAX__ - @as(c_long, 1);
pub const UCHAR_MAX = (__SCHAR_MAX__ * 2) + 1;
pub const USHRT_MAX = (__SHRT_MAX__ * 2) + 1;
pub const UINT_MAX = (__INT_MAX__ * @as(c_uint, 2)) + @as(c_uint, 1);
pub const ULONG_MAX = (__LONG_MAX__ * @as(c_ulong, 2)) + @as(c_ulong, 1);
pub const CHAR_BIT = __CHAR_BIT__;
pub const CHAR_MIN = SCHAR_MIN;
pub const CHAR_MAX = __SCHAR_MAX__;
pub const LLONG_MAX = __LONG_LONG_MAX__;
pub const LLONG_MIN = -__LONG_LONG_MAX__ - @as(c_longlong, 1);
pub const ULLONG_MAX = (__LONG_LONG_MAX__ * @as(c_ulonglong, 2)) + @as(c_ulonglong, 1);
pub const _BITS_POSIX1_LIM_H = 1;
pub const _POSIX_AIO_LISTIO_MAX = 2;
pub const _POSIX_AIO_MAX = 1;
pub const _POSIX_ARG_MAX = 4096;
pub const _POSIX_CHILD_MAX = 25;
pub const _POSIX_DELAYTIMER_MAX = 32;
pub const _POSIX_HOST_NAME_MAX = 255;
pub const _POSIX_LINK_MAX = 8;
pub const _POSIX_LOGIN_NAME_MAX = 9;
pub const _POSIX_MAX_CANON = 255;
pub const _POSIX_MAX_INPUT = 255;
pub const _POSIX_MQ_OPEN_MAX = 8;
pub const _POSIX_MQ_PRIO_MAX = 32;
pub const _POSIX_NAME_MAX = 14;
pub const _POSIX_NGROUPS_MAX = 8;
pub const _POSIX_OPEN_MAX = 20;
pub const _POSIX_PATH_MAX = 256;
pub const _POSIX_PIPE_BUF = 512;
pub const _POSIX_RE_DUP_MAX = 255;
pub const _POSIX_RTSIG_MAX = 8;
pub const _POSIX_SEM_NSEMS_MAX = 256;
pub const _POSIX_SEM_VALUE_MAX = 32767;
pub const _POSIX_SIGQUEUE_MAX = 32;
pub const _POSIX_SSIZE_MAX = 32767;
pub const _POSIX_STREAM_MAX = 8;
pub const _POSIX_SYMLINK_MAX = 255;
pub const _POSIX_SYMLOOP_MAX = 8;
pub const _POSIX_TIMER_MAX = 32;
pub const _POSIX_TTY_NAME_MAX = 9;
pub const _POSIX_TZNAME_MAX = 6;
pub const _POSIX_CLOCKRES_MIN = 20000000;
pub const NR_OPEN = 1024;
pub const NGROUPS_MAX = 65536;
pub const ARG_MAX = 131072;
pub const LINK_MAX = 127;
pub const MAX_CANON = 255;
pub const MAX_INPUT = 255;
pub const NAME_MAX = 255;
pub const PATH_MAX = 4096;
pub const PIPE_BUF = 4096;
pub const XATTR_NAME_MAX = 255;
pub const XATTR_SIZE_MAX = 65536;
pub const XATTR_LIST_MAX = 65536;
pub const RTSIG_MAX = 32;
pub const _POSIX_THREAD_KEYS_MAX = 128;
pub const PTHREAD_KEYS_MAX = 1024;
pub const _POSIX_THREAD_DESTRUCTOR_ITERATIONS = 4;
pub const PTHREAD_DESTRUCTOR_ITERATIONS = _POSIX_THREAD_DESTRUCTOR_ITERATIONS;
pub const _POSIX_THREAD_THREADS_MAX = 64;
pub const AIO_PRIO_DELTA_MAX = 20;
pub const PTHREAD_STACK_MIN = 16384;
pub const DELAYTIMER_MAX = 2147483647;
pub const TTY_NAME_MAX = 32;
pub const LOGIN_NAME_MAX = 256;
pub const HOST_NAME_MAX = 64;
pub const MQ_PRIO_MAX = 32768;
pub const SEM_VALUE_MAX = 2147483647;
pub const SSIZE_MAX = LONG_MAX;
pub const _BITS_POSIX2_LIM_H = 1;
pub const _POSIX2_BC_BASE_MAX = 99;
pub const _POSIX2_BC_DIM_MAX = 2048;
pub const _POSIX2_BC_SCALE_MAX = 99;
pub const _POSIX2_BC_STRING_MAX = 1000;
pub const _POSIX2_COLL_WEIGHTS_MAX = 2;
pub const _POSIX2_EXPR_NEST_MAX = 32;
pub const _POSIX2_LINE_MAX = 2048;
pub const _POSIX2_RE_DUP_MAX = 255;
pub const _POSIX2_CHARCLASS_NAME_MAX = 14;
pub const BC_BASE_MAX = _POSIX2_BC_BASE_MAX;
pub const BC_DIM_MAX = _POSIX2_BC_DIM_MAX;
pub const BC_SCALE_MAX = _POSIX2_BC_SCALE_MAX;
pub const BC_STRING_MAX = _POSIX2_BC_STRING_MAX;
pub const COLL_WEIGHTS_MAX = 255;
pub const EXPR_NEST_MAX = _POSIX2_EXPR_NEST_MAX;
pub const LINE_MAX = _POSIX2_LINE_MAX;
pub const CHARCLASS_NAME_MAX = 2048;
pub const RE_DUP_MAX = 0x7fff;
pub const NULL = (@import("std").meta.cast(?*c_void, 0));
pub const _STDLIB_H = 1;
pub const WNOHANG = 1;
pub const WUNTRACED = 2;
pub const WSTOPPED = 2;
pub const WEXITED = 4;
pub const WCONTINUED = 8;
pub const WNOWAIT = 0x01000000;
pub const __WNOTHREAD = 0x20000000;
pub const __WALL = 0x40000000;
pub const __WCLONE = 0x80000000;
pub inline fn __WEXITSTATUS(status: anytype) @TypeOf((status & 0xff00) >> 8) {
    return (status & 0xff00) >> 8;
}
pub inline fn __WTERMSIG(status: anytype) @TypeOf(status & 0x7f) {
    return status & 0x7f;
}
pub inline fn __WSTOPSIG(status: anytype) @TypeOf(__WEXITSTATUS(status)) {
    return __WEXITSTATUS(status);
}
pub inline fn __WIFEXITED(status: anytype) @TypeOf(__WTERMSIG(status) == 0) {
    return __WTERMSIG(status) == 0;
}
pub inline fn __WIFSIGNALED(status: anytype) @TypeOf(((@import("std").meta.cast(i8, (status & 0x7f) + 1)) >> 1) > 0) {
    return ((@import("std").meta.cast(i8, (status & 0x7f) + 1)) >> 1) > 0;
}
pub inline fn __WIFSTOPPED(status: anytype) @TypeOf((status & 0xff) == 0x7f) {
    return (status & 0xff) == 0x7f;
}
pub inline fn __WIFCONTINUED(status: anytype) @TypeOf(status == __W_CONTINUED) {
    return status == __W_CONTINUED;
}
pub inline fn __WCOREDUMP(status: anytype) @TypeOf(status & __WCOREFLAG) {
    return status & __WCOREFLAG;
}
pub inline fn __W_EXITCODE(ret: anytype, sig: anytype) @TypeOf((ret << 8) | sig) {
    return (ret << 8) | sig;
}
pub inline fn __W_STOPCODE(sig: anytype) @TypeOf((sig << 8) | 0x7f) {
    return (sig << 8) | 0x7f;
}
pub const __W_CONTINUED = 0xffff;
pub const __WCOREFLAG = 0x80;
pub inline fn WEXITSTATUS(status: anytype) @TypeOf(__WEXITSTATUS(status)) {
    return __WEXITSTATUS(status);
}
pub inline fn WTERMSIG(status: anytype) @TypeOf(__WTERMSIG(status)) {
    return __WTERMSIG(status);
}
pub inline fn WSTOPSIG(status: anytype) @TypeOf(__WSTOPSIG(status)) {
    return __WSTOPSIG(status);
}
pub inline fn WIFEXITED(status: anytype) @TypeOf(__WIFEXITED(status)) {
    return __WIFEXITED(status);
}
pub inline fn WIFSIGNALED(status: anytype) @TypeOf(__WIFSIGNALED(status)) {
    return __WIFSIGNALED(status);
}
pub inline fn WIFSTOPPED(status: anytype) @TypeOf(__WIFSTOPPED(status)) {
    return __WIFSTOPPED(status);
}
pub inline fn WIFCONTINUED(status: anytype) @TypeOf(__WIFCONTINUED(status)) {
    return __WIFCONTINUED(status);
}
pub const __HAVE_FLOAT128 = 0;
pub const __HAVE_DISTINCT_FLOAT128 = 0;
pub const __HAVE_FLOAT64X = 1;
pub const __HAVE_FLOAT64X_LONG_DOUBLE = 1;
pub const __HAVE_FLOAT16 = 0;
pub const __HAVE_FLOAT32 = 1;
pub const __HAVE_FLOAT64 = 1;
pub const __HAVE_FLOAT32X = 1;
pub const __HAVE_FLOAT128X = 0;
pub const __HAVE_DISTINCT_FLOAT16 = __HAVE_FLOAT16;
pub const __HAVE_DISTINCT_FLOAT32 = 0;
pub const __HAVE_DISTINCT_FLOAT64 = 0;
pub const __HAVE_DISTINCT_FLOAT32X = 0;
pub const __HAVE_DISTINCT_FLOAT64X = 0;
pub const __HAVE_DISTINCT_FLOAT128X = __HAVE_FLOAT128X;
pub const __HAVE_FLOAT128_UNLIKE_LDBL = (__HAVE_DISTINCT_FLOAT128 != 0) and (__LDBL_MANT_DIG__ != 113);
pub const __HAVE_FLOATN_NOT_TYPEDEF = 0;
pub inline fn __f64(x: anytype) @TypeOf(x) {
    return x;
}
pub inline fn __f32x(x: anytype) @TypeOf(x) {
    return x;
}
pub inline fn __builtin_nanf32(x: anytype) @TypeOf(__builtin_nanf(x)) {
    return __builtin_nanf(x);
}
pub inline fn __builtin_nansf32(x: anytype) @TypeOf(__builtin_nansf(x)) {
    return __builtin_nansf(x);
}
pub inline fn __builtin_nanf64(x: anytype) @TypeOf(__builtin_nan(x)) {
    return __builtin_nan(x);
}
pub inline fn __builtin_nansf64(x: anytype) @TypeOf(__builtin_nans(x)) {
    return __builtin_nans(x);
}
pub inline fn __builtin_nanf32x(x: anytype) @TypeOf(__builtin_nan(x)) {
    return __builtin_nan(x);
}
pub inline fn __builtin_nansf32x(x: anytype) @TypeOf(__builtin_nans(x)) {
    return __builtin_nans(x);
}
pub inline fn __builtin_nanf64x(x: anytype) @TypeOf(__builtin_nanl(x)) {
    return __builtin_nanl(x);
}
pub inline fn __builtin_nansf64x(x: anytype) @TypeOf(__builtin_nansl(x)) {
    return __builtin_nansl(x);
}
pub const __ldiv_t_defined = 1;
pub const __lldiv_t_defined = 1;
pub const RAND_MAX = 2147483647;
pub const EXIT_FAILURE = 1;
pub const EXIT_SUCCESS = 0;
pub const _SYS_TYPES_H = 1;
pub const _BITS_TYPES_H = 1;
pub const __TIMESIZE = __WORDSIZE;
pub const __S32_TYPE = c_int;
pub const __U32_TYPE = c_uint;
pub const __SLONG32_TYPE = c_int;
pub const __ULONG32_TYPE = c_uint;
pub const _BITS_TYPESIZES_H = 1;
pub const __SYSCALL_SLONG_TYPE = __SLONGWORD_TYPE;
pub const __SYSCALL_ULONG_TYPE = __ULONGWORD_TYPE;
pub const __DEV_T_TYPE = __UQUAD_TYPE;
pub const __UID_T_TYPE = __U32_TYPE;
pub const __GID_T_TYPE = __U32_TYPE;
pub const __INO_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __INO64_T_TYPE = __UQUAD_TYPE;
pub const __MODE_T_TYPE = __U32_TYPE;
pub const __NLINK_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSWORD_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __OFF_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __OFF64_T_TYPE = __SQUAD_TYPE;
pub const __PID_T_TYPE = __S32_TYPE;
pub const __RLIM_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __RLIM64_T_TYPE = __UQUAD_TYPE;
pub const __BLKCNT_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __BLKCNT64_T_TYPE = __SQUAD_TYPE;
pub const __FSBLKCNT_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSBLKCNT64_T_TYPE = __UQUAD_TYPE;
pub const __FSFILCNT_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSFILCNT64_T_TYPE = __UQUAD_TYPE;
pub const __ID_T_TYPE = __U32_TYPE;
pub const __CLOCK_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __TIME_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __USECONDS_T_TYPE = __U32_TYPE;
pub const __SUSECONDS_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __SUSECONDS64_T_TYPE = __SQUAD_TYPE;
pub const __DADDR_T_TYPE = __S32_TYPE;
pub const __KEY_T_TYPE = __S32_TYPE;
pub const __CLOCKID_T_TYPE = __S32_TYPE;
pub const __BLKSIZE_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __SSIZE_T_TYPE = __SWORD_TYPE;
pub const __CPU_MASK_TYPE = __SYSCALL_ULONG_TYPE;
pub const __OFF_T_MATCHES_OFF64_T = 1;
pub const __INO_T_MATCHES_INO64_T = 1;
pub const __RLIM_T_MATCHES_RLIM64_T = 1;
pub const __STATFS_MATCHES_STATFS64 = 1;
pub const __KERNEL_OLD_TIMEVAL_MATCHES_TIMEVAL64 = 1;
pub const __FD_SETSIZE = 1024;
pub const _BITS_TIME64_H = 1;
pub const __TIME64_T_TYPE = __TIME_T_TYPE;
pub const __clock_t_defined = 1;
pub const __clockid_t_defined = 1;
pub const __time_t_defined = 1;
pub const __timer_t_defined = 1;
pub const _BITS_STDINT_INTN_H = 1;
pub const __BIT_TYPES_DEFINED__ = 1;
pub const _ENDIAN_H = 1;
pub const _BITS_ENDIAN_H = 1;
pub const __LITTLE_ENDIAN = 1234;
pub const __BIG_ENDIAN = 4321;
pub const __PDP_ENDIAN = 3412;
pub const _BITS_ENDIANNESS_H = 1;
pub const __BYTE_ORDER = __LITTLE_ENDIAN;
pub const __FLOAT_WORD_ORDER = __BYTE_ORDER;
pub inline fn __LONG_LONG_PAIR(HI: anytype, LO: anytype) @TypeOf(HI) {
    return blk: {
        _ = LO;
        break :blk HI;
    };
}
pub const LITTLE_ENDIAN = __LITTLE_ENDIAN;
pub const BIG_ENDIAN = __BIG_ENDIAN;
pub const PDP_ENDIAN = __PDP_ENDIAN;
pub const BYTE_ORDER = __BYTE_ORDER;
pub const _BITS_BYTESWAP_H = 1;
pub inline fn __bswap_constant_16(x: anytype) @TypeOf((@import("std").meta.cast(__uint16_t, ((x >> 8) & 0xff) | ((x & 0xff) << 8)))) {
    return (@import("std").meta.cast(__uint16_t, ((x >> 8) & 0xff) | ((x & 0xff) << 8)));
}
pub inline fn __bswap_constant_32(x: anytype) @TypeOf(((((x & @as(c_uint, 0xff000000)) >> 24) | ((x & @as(c_uint, 0x00ff0000)) >> 8)) | ((x & @as(c_uint, 0x0000ff00)) << 8)) | ((x & @as(c_uint, 0x000000ff)) << 24)) {
    return ((((x & @as(c_uint, 0xff000000)) >> 24) | ((x & @as(c_uint, 0x00ff0000)) >> 8)) | ((x & @as(c_uint, 0x0000ff00)) << 8)) | ((x & @as(c_uint, 0x000000ff)) << 24);
}
pub inline fn __bswap_constant_64(x: anytype) @TypeOf(((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> 56) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> 40)) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> 24)) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> 8)) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << 8)) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << 24)) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << 40)) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << 56)) {
    return ((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> 56) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> 40)) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> 24)) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> 8)) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << 8)) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << 24)) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << 40)) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << 56);
}
pub const _BITS_UINTN_IDENTITY_H = 1;
pub inline fn htobe16(x: anytype) @TypeOf(__bswap_16(x)) {
    return __bswap_16(x);
}
pub inline fn htole16(x: anytype) @TypeOf(__uint16_identity(x)) {
    return __uint16_identity(x);
}
pub inline fn be16toh(x: anytype) @TypeOf(__bswap_16(x)) {
    return __bswap_16(x);
}
pub inline fn le16toh(x: anytype) @TypeOf(__uint16_identity(x)) {
    return __uint16_identity(x);
}
pub inline fn htobe32(x: anytype) @TypeOf(__bswap_32(x)) {
    return __bswap_32(x);
}
pub inline fn htole32(x: anytype) @TypeOf(__uint32_identity(x)) {
    return __uint32_identity(x);
}
pub inline fn be32toh(x: anytype) @TypeOf(__bswap_32(x)) {
    return __bswap_32(x);
}
pub inline fn le32toh(x: anytype) @TypeOf(__uint32_identity(x)) {
    return __uint32_identity(x);
}
pub inline fn htobe64(x: anytype) @TypeOf(__bswap_64(x)) {
    return __bswap_64(x);
}
pub inline fn htole64(x: anytype) @TypeOf(__uint64_identity(x)) {
    return __uint64_identity(x);
}
pub inline fn be64toh(x: anytype) @TypeOf(__bswap_64(x)) {
    return __bswap_64(x);
}
pub inline fn le64toh(x: anytype) @TypeOf(__uint64_identity(x)) {
    return __uint64_identity(x);
}
pub const _SYS_SELECT_H = 1;
pub inline fn __FD_ISSET(d: anytype, s: anytype) @TypeOf((__FDS_BITS(s)[__FD_ELT(d)] & __FD_MASK(d)) != 0) {
    return (__FDS_BITS(s)[__FD_ELT(d)] & __FD_MASK(d)) != 0;
}
pub const __sigset_t_defined = 1;
pub const __timeval_defined = 1;
pub const _STRUCT_TIMESPEC = 1;
pub const __NFDBITS = 8 * (@import("std").meta.cast(c_int, @import("std").meta.sizeof(__fd_mask)));
pub inline fn __FD_ELT(d: anytype) @TypeOf(d / __NFDBITS) {
    return d / __NFDBITS;
}
pub inline fn __FD_MASK(d: anytype) @TypeOf((@import("std").meta.cast(__fd_mask, @as(c_ulong, 1) << (d % __NFDBITS)))) {
    return (@import("std").meta.cast(__fd_mask, @as(c_ulong, 1) << (d % __NFDBITS)));
}
pub inline fn __FDS_BITS(set: anytype) @TypeOf(set.*.__fds_bits) {
    return set.*.__fds_bits;
}
pub const FD_SETSIZE = __FD_SETSIZE;
pub const NFDBITS = __NFDBITS;
pub inline fn FD_SET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_SET(fd, fdsetp)) {
    return __FD_SET(fd, fdsetp);
}
pub inline fn FD_CLR(fd: anytype, fdsetp: anytype) @TypeOf(__FD_CLR(fd, fdsetp)) {
    return __FD_CLR(fd, fdsetp);
}
pub inline fn FD_ISSET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_ISSET(fd, fdsetp)) {
    return __FD_ISSET(fd, fdsetp);
}
pub inline fn FD_ZERO(fdsetp: anytype) @TypeOf(__FD_ZERO(fdsetp)) {
    return __FD_ZERO(fdsetp);
}
pub const _BITS_PTHREADTYPES_COMMON_H = 1;
pub const _THREAD_SHARED_TYPES_H = 1;
pub const _BITS_PTHREADTYPES_ARCH_H = 1;
pub const __SIZEOF_PTHREAD_MUTEX_T = 40;
pub const __SIZEOF_PTHREAD_ATTR_T = 56;
pub const __SIZEOF_PTHREAD_RWLOCK_T = 56;
pub const __SIZEOF_PTHREAD_BARRIER_T = 32;
pub const __SIZEOF_PTHREAD_MUTEXATTR_T = 4;
pub const __SIZEOF_PTHREAD_COND_T = 48;
pub const __SIZEOF_PTHREAD_CONDATTR_T = 4;
pub const __SIZEOF_PTHREAD_RWLOCKATTR_T = 8;
pub const __SIZEOF_PTHREAD_BARRIERATTR_T = 4;
pub const _THREAD_MUTEX_INTERNAL_H = 1;
pub const __PTHREAD_MUTEX_HAVE_PREV = 1;
pub inline fn __PTHREAD_RWLOCK_INITIALIZER(__flags: anytype) @TypeOf(__flags) {
    return blk: {
        _ = 0;
        _ = 0;
        _ = 0;
        _ = 0;
        _ = 0;
        _ = 0;
        _ = 0;
        _ = 0;
        _ = __PTHREAD_RWLOCK_ELISION_EXTRA;
        _ = 0;
        break :blk __flags;
    };
}
pub const __have_pthread_attr_t = 1;
pub const _ALLOCA_H = 1;
pub const _STDINT_H = 1;
pub const _BITS_WCHAR_H = 1;
pub const __WCHAR_MAX = __WCHAR_MAX__;
pub const __WCHAR_MIN = -__WCHAR_MAX - 1;
pub const _BITS_STDINT_UINTN_H = 1;
pub const INT8_MIN = -128;
pub const INT16_MIN = -32767 - 1;
pub const INT32_MIN = -2147483647 - 1;
pub const INT64_MIN = -__INT64_C(9223372036854775807) - 1;
pub const INT8_MAX = 127;
pub const INT16_MAX = 32767;
pub const INT32_MAX = 2147483647;
pub const INT64_MAX = __INT64_C(9223372036854775807);
pub const UINT8_MAX = 255;
pub const UINT16_MAX = 65535;
pub const UINT32_MAX = @as(c_uint, 4294967295);
pub const UINT64_MAX = __UINT64_C(18446744073709551615);
pub const INT_LEAST8_MIN = -128;
pub const INT_LEAST16_MIN = -32767 - 1;
pub const INT_LEAST32_MIN = -2147483647 - 1;
pub const INT_LEAST64_MIN = -__INT64_C(9223372036854775807) - 1;
pub const INT_LEAST8_MAX = 127;
pub const INT_LEAST16_MAX = 32767;
pub const INT_LEAST32_MAX = 2147483647;
pub const INT_LEAST64_MAX = __INT64_C(9223372036854775807);
pub const UINT_LEAST8_MAX = 255;
pub const UINT_LEAST16_MAX = 65535;
pub const UINT_LEAST32_MAX = @as(c_uint, 4294967295);
pub const UINT_LEAST64_MAX = __UINT64_C(18446744073709551615);
pub const INT_FAST8_MIN = -128;
pub const INT_FAST16_MIN = -@as(c_long, 9223372036854775807) - 1;
pub const INT_FAST32_MIN = -@as(c_long, 9223372036854775807) - 1;
pub const INT_FAST64_MIN = -__INT64_C(9223372036854775807) - 1;
pub const INT_FAST8_MAX = 127;
pub const INT_FAST16_MAX = @as(c_long, 9223372036854775807);
pub const INT_FAST32_MAX = @as(c_long, 9223372036854775807);
pub const INT_FAST64_MAX = __INT64_C(9223372036854775807);
pub const UINT_FAST8_MAX = 255;
pub const UINT_FAST16_MAX = @as(c_ulong, 18446744073709551615);
pub const UINT_FAST32_MAX = @as(c_ulong, 18446744073709551615);
pub const UINT_FAST64_MAX = __UINT64_C(18446744073709551615);
pub const INTPTR_MIN = -@as(c_long, 9223372036854775807) - 1;
pub const INTPTR_MAX = @as(c_long, 9223372036854775807);
pub const UINTPTR_MAX = @as(c_ulong, 18446744073709551615);
pub const INTMAX_MIN = -__INT64_C(9223372036854775807) - 1;
pub const INTMAX_MAX = __INT64_C(9223372036854775807);
pub const UINTMAX_MAX = __UINT64_C(18446744073709551615);
pub const PTRDIFF_MIN = -@as(c_long, 9223372036854775807) - 1;
pub const PTRDIFF_MAX = @as(c_long, 9223372036854775807);
pub const SIG_ATOMIC_MIN = -2147483647 - 1;
pub const SIG_ATOMIC_MAX = 2147483647;
pub const SIZE_MAX = @as(c_ulong, 18446744073709551615);
pub const WCHAR_MIN = __WCHAR_MIN;
pub const WCHAR_MAX = __WCHAR_MAX;
pub const WINT_MIN = @as(c_uint, 0);
pub const WINT_MAX = @as(c_uint, 4294967295);
pub inline fn INT8_C(c: anytype) @TypeOf(c) {
    return c;
}
pub inline fn INT16_C(c: anytype) @TypeOf(c) {
    return c;
}
pub inline fn INT32_C(c: anytype) @TypeOf(c) {
    return c;
}
pub inline fn UINT8_C(c: anytype) @TypeOf(c) {
    return c;
}
pub inline fn UINT16_C(c: anytype) @TypeOf(c) {
    return c;
}
pub const _STDIO_H = 1;
pub inline fn va_start(ap: anytype, param: anytype) @TypeOf(__builtin_va_start(ap, param)) {
    return __builtin_va_start(ap, param);
}
pub inline fn va_end(ap: anytype) @TypeOf(__builtin_va_end(ap)) {
    return __builtin_va_end(ap);
}
pub inline fn va_arg(ap: anytype, type_1: anytype) @TypeOf(__builtin_va_arg(ap, type_1)) {
    return __builtin_va_arg(ap, type_1);
}
pub inline fn __va_copy(d: anytype, s: anytype) @TypeOf(__builtin_va_copy(d, s)) {
    return __builtin_va_copy(d, s);
}
pub inline fn va_copy(dest: anytype, src: anytype) @TypeOf(__builtin_va_copy(dest, src)) {
    return __builtin_va_copy(dest, src);
}
pub const __GNUC_VA_LIST = 1;
pub const _____fpos_t_defined = 1;
pub const ____mbstate_t_defined = 1;
pub const _____fpos64_t_defined = 1;
pub const ____FILE_defined = 1;
pub const __FILE_defined = 1;
pub const __struct_FILE_defined = 1;
pub const _IO_EOF_SEEN = 0x0010;
pub inline fn __feof_unlocked_body(_fp: anytype) @TypeOf(((_fp.*._flags) & _IO_EOF_SEEN) != 0) {
    return ((_fp.*._flags) & _IO_EOF_SEEN) != 0;
}
pub const _IO_ERR_SEEN = 0x0020;
pub inline fn __ferror_unlocked_body(_fp: anytype) @TypeOf(((_fp.*._flags) & _IO_ERR_SEEN) != 0) {
    return ((_fp.*._flags) & _IO_ERR_SEEN) != 0;
}
pub const _IO_USER_LOCK = 0x8000;
pub const _IOFBF = 0;
pub const _IOLBF = 1;
pub const _IONBF = 2;
pub const BUFSIZ = 8192;
pub const EOF = -1;
pub const SEEK_SET = 0;
pub const SEEK_CUR = 1;
pub const SEEK_END = 2;
pub const P_tmpdir = "/tmp";
pub const _BITS_STDIO_LIM_H = 1;
pub const L_tmpnam = 20;
pub const TMP_MAX = 238328;
pub const FILENAME_MAX = 4096;
pub const L_ctermid = 9;
pub const FOPEN_MAX = 16;
pub const _BITS_STDIO_H = 1;
pub const __STDIO_INLINE = __extern_inline;
pub inline fn offsetof(t: anytype, d: anytype) @TypeOf(__builtin_offsetof(t, d)) {
    return __builtin_offsetof(t, d);
}
pub const ATOMIC_BOOL_LOCK_FREE = __CLANG_ATOMIC_BOOL_LOCK_FREE;
pub const ATOMIC_CHAR_LOCK_FREE = __CLANG_ATOMIC_CHAR_LOCK_FREE;
pub const ATOMIC_CHAR16_T_LOCK_FREE = __CLANG_ATOMIC_CHAR16_T_LOCK_FREE;
pub const ATOMIC_CHAR32_T_LOCK_FREE = __CLANG_ATOMIC_CHAR32_T_LOCK_FREE;
pub const ATOMIC_WCHAR_T_LOCK_FREE = __CLANG_ATOMIC_WCHAR_T_LOCK_FREE;
pub const ATOMIC_SHORT_LOCK_FREE = __CLANG_ATOMIC_SHORT_LOCK_FREE;
pub const ATOMIC_INT_LOCK_FREE = __CLANG_ATOMIC_INT_LOCK_FREE;
pub const ATOMIC_LONG_LOCK_FREE = __CLANG_ATOMIC_LONG_LOCK_FREE;
pub const ATOMIC_LLONG_LOCK_FREE = __CLANG_ATOMIC_LLONG_LOCK_FREE;
pub const ATOMIC_POINTER_LOCK_FREE = __CLANG_ATOMIC_POINTER_LOCK_FREE;
pub inline fn ATOMIC_VAR_INIT(value: anytype) @TypeOf(value) {
    return value;
}
pub const atomic_init = __c11_atomic_init;
pub inline fn kill_dependency(y: anytype) @TypeOf(y) {
    return y;
}
pub inline fn atomic_is_lock_free(obj: anytype) @TypeOf(__c11_atomic_is_lock_free(@import("std").meta.sizeof(obj.*))) {
    return __c11_atomic_is_lock_free(@import("std").meta.sizeof(obj.*));
}
pub inline fn atomic_store(object: anytype, desired: anytype) @TypeOf(__c11_atomic_store(object, desired, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_store(object, desired, __ATOMIC_SEQ_CST);
}
pub const atomic_store_explicit = __c11_atomic_store;
pub inline fn atomic_load(object: anytype) @TypeOf(__c11_atomic_load(object, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_load(object, __ATOMIC_SEQ_CST);
}
pub const atomic_load_explicit = __c11_atomic_load;
pub inline fn atomic_exchange(object: anytype, desired: anytype) @TypeOf(__c11_atomic_exchange(object, desired, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_exchange(object, desired, __ATOMIC_SEQ_CST);
}
pub const atomic_exchange_explicit = __c11_atomic_exchange;
pub inline fn atomic_compare_exchange_strong(object: anytype, expected: anytype, desired: anytype) @TypeOf(__c11_atomic_compare_exchange_strong(object, expected, desired, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_compare_exchange_strong(object, expected, desired, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}
pub const atomic_compare_exchange_strong_explicit = __c11_atomic_compare_exchange_strong;
pub inline fn atomic_compare_exchange_weak(object: anytype, expected: anytype, desired: anytype) @TypeOf(__c11_atomic_compare_exchange_weak(object, expected, desired, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_compare_exchange_weak(object, expected, desired, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}
pub const atomic_compare_exchange_weak_explicit = __c11_atomic_compare_exchange_weak;
pub inline fn atomic_fetch_add(object: anytype, operand: anytype) @TypeOf(__c11_atomic_fetch_add(object, operand, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_fetch_add(object, operand, __ATOMIC_SEQ_CST);
}
pub const atomic_fetch_add_explicit = __c11_atomic_fetch_add;
pub inline fn atomic_fetch_sub(object: anytype, operand: anytype) @TypeOf(__c11_atomic_fetch_sub(object, operand, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_fetch_sub(object, operand, __ATOMIC_SEQ_CST);
}
pub const atomic_fetch_sub_explicit = __c11_atomic_fetch_sub;
pub inline fn atomic_fetch_or(object: anytype, operand: anytype) @TypeOf(__c11_atomic_fetch_or(object, operand, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_fetch_or(object, operand, __ATOMIC_SEQ_CST);
}
pub const atomic_fetch_or_explicit = __c11_atomic_fetch_or;
pub inline fn atomic_fetch_xor(object: anytype, operand: anytype) @TypeOf(__c11_atomic_fetch_xor(object, operand, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_fetch_xor(object, operand, __ATOMIC_SEQ_CST);
}
pub const atomic_fetch_xor_explicit = __c11_atomic_fetch_xor;
pub inline fn atomic_fetch_and(object: anytype, operand: anytype) @TypeOf(__c11_atomic_fetch_and(object, operand, __ATOMIC_SEQ_CST)) {
    return __c11_atomic_fetch_and(object, operand, __ATOMIC_SEQ_CST);
}
pub const atomic_fetch_and_explicit = __c11_atomic_fetch_and;
pub const bool_86 = bool;
pub const @"true" = 1;
pub const @"false" = 0;
pub const __bool_true_false_are_defined = 1;
pub const _UNISTD_H = 1;
pub const _POSIX_VERSION = @as(c_long, 200809);
pub const __POSIX2_THIS_VERSION = @as(c_long, 200809);
pub const _POSIX2_VERSION = __POSIX2_THIS_VERSION;
pub const _POSIX2_C_VERSION = __POSIX2_THIS_VERSION;
pub const _POSIX2_C_BIND = __POSIX2_THIS_VERSION;
pub const _POSIX2_C_DEV = __POSIX2_THIS_VERSION;
pub const _POSIX2_SW_DEV = __POSIX2_THIS_VERSION;
pub const _POSIX2_LOCALEDEF = __POSIX2_THIS_VERSION;
pub const _XOPEN_VERSION = 700;
pub const _XOPEN_XCU_VERSION = 4;
pub const _XOPEN_XPG2 = 1;
pub const _XOPEN_XPG3 = 1;
pub const _XOPEN_XPG4 = 1;
pub const _XOPEN_UNIX = 1;
pub const _XOPEN_ENH_I18N = 1;
pub const _XOPEN_LEGACY = 1;
pub const _BITS_POSIX_OPT_H = 1;
pub const _POSIX_JOB_CONTROL = 1;
pub const _POSIX_SAVED_IDS = 1;
pub const _POSIX_PRIORITY_SCHEDULING = @as(c_long, 200809);
pub const _POSIX_SYNCHRONIZED_IO = @as(c_long, 200809);
pub const _POSIX_FSYNC = @as(c_long, 200809);
pub const _POSIX_MAPPED_FILES = @as(c_long, 200809);
pub const _POSIX_MEMLOCK = @as(c_long, 200809);
pub const _POSIX_MEMLOCK_RANGE = @as(c_long, 200809);
pub const _POSIX_MEMORY_PROTECTION = @as(c_long, 200809);
pub const _POSIX_CHOWN_RESTRICTED = 0;
pub const _POSIX_VDISABLE = '\x00';
pub const _POSIX_NO_TRUNC = 1;
pub const _XOPEN_REALTIME = 1;
pub const _XOPEN_REALTIME_THREADS = 1;
pub const _XOPEN_SHM = 1;
pub const _POSIX_THREADS = @as(c_long, 200809);
pub const _POSIX_REENTRANT_FUNCTIONS = 1;
pub const _POSIX_THREAD_SAFE_FUNCTIONS = @as(c_long, 200809);
pub const _POSIX_THREAD_PRIORITY_SCHEDULING = @as(c_long, 200809);
pub const _POSIX_THREAD_ATTR_STACKSIZE = @as(c_long, 200809);
pub const _POSIX_THREAD_ATTR_STACKADDR = @as(c_long, 200809);
pub const _POSIX_THREAD_PRIO_INHERIT = @as(c_long, 200809);
pub const _POSIX_THREAD_PRIO_PROTECT = @as(c_long, 200809);
pub const _POSIX_THREAD_ROBUST_PRIO_INHERIT = @as(c_long, 200809);
pub const _POSIX_THREAD_ROBUST_PRIO_PROTECT = -1;
pub const _POSIX_SEMAPHORES = @as(c_long, 200809);
pub const _POSIX_REALTIME_SIGNALS = @as(c_long, 200809);
pub const _POSIX_ASYNCHRONOUS_IO = @as(c_long, 200809);
pub const _POSIX_ASYNC_IO = 1;
pub const _LFS_ASYNCHRONOUS_IO = 1;
pub const _POSIX_PRIORITIZED_IO = @as(c_long, 200809);
pub const _LFS64_ASYNCHRONOUS_IO = 1;
pub const _LFS_LARGEFILE = 1;
pub const _LFS64_LARGEFILE = 1;
pub const _LFS64_STDIO = 1;
pub const _POSIX_SHARED_MEMORY_OBJECTS = @as(c_long, 200809);
pub const _POSIX_CPUTIME = 0;
pub const _POSIX_THREAD_CPUTIME = 0;
pub const _POSIX_REGEXP = 1;
pub const _POSIX_READER_WRITER_LOCKS = @as(c_long, 200809);
pub const _POSIX_SHELL = 1;
pub const _POSIX_TIMEOUTS = @as(c_long, 200809);
pub const _POSIX_SPIN_LOCKS = @as(c_long, 200809);
pub const _POSIX_SPAWN = @as(c_long, 200809);
pub const _POSIX_TIMERS = @as(c_long, 200809);
pub const _POSIX_BARRIERS = @as(c_long, 200809);
pub const _POSIX_MESSAGE_PASSING = @as(c_long, 200809);
pub const _POSIX_THREAD_PROCESS_SHARED = @as(c_long, 200809);
pub const _POSIX_MONOTONIC_CLOCK = 0;
pub const _POSIX_CLOCK_SELECTION = @as(c_long, 200809);
pub const _POSIX_ADVISORY_INFO = @as(c_long, 200809);
pub const _POSIX_IPV6 = @as(c_long, 200809);
pub const _POSIX_RAW_SOCKETS = @as(c_long, 200809);
pub const _POSIX2_CHAR_TERM = @as(c_long, 200809);
pub const _POSIX_SPORADIC_SERVER = -1;
pub const _POSIX_THREAD_SPORADIC_SERVER = -1;
pub const _POSIX_TRACE = -1;
pub const _POSIX_TRACE_EVENT_FILTER = -1;
pub const _POSIX_TRACE_INHERIT = -1;
pub const _POSIX_TRACE_LOG = -1;
pub const _POSIX_TYPED_MEMORY_OBJECTS = -1;
pub const _POSIX_V7_LPBIG_OFFBIG = -1;
pub const _POSIX_V6_LPBIG_OFFBIG = -1;
pub const _XBS5_LPBIG_OFFBIG = -1;
pub const _POSIX_V7_LP64_OFF64 = 1;
pub const _POSIX_V6_LP64_OFF64 = 1;
pub const _XBS5_LP64_OFF64 = 1;
pub const __ILP32_OFF32_CFLAGS = "-m32";
pub const __ILP32_OFF32_LDFLAGS = "-m32";
pub const __ILP32_OFFBIG_CFLAGS = "-m32 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64";
pub const __ILP32_OFFBIG_LDFLAGS = "-m32";
pub const __LP64_OFF64_CFLAGS = "-m64";
pub const __LP64_OFF64_LDFLAGS = "-m64";
pub const STDIN_FILENO = 0;
pub const STDOUT_FILENO = 1;
pub const STDERR_FILENO = 2;
pub const R_OK = 4;
pub const W_OK = 2;
pub const X_OK = 1;
pub const F_OK = 0;
pub const L_SET = SEEK_SET;
pub const L_INCR = SEEK_CUR;
pub const L_XTND = SEEK_END;
pub const _SC_PAGE_SIZE = _SC_PAGESIZE;
pub const _CS_POSIX_V6_WIDTH_RESTRICTED_ENVS = _CS_V6_WIDTH_RESTRICTED_ENVS;
pub const _CS_POSIX_V5_WIDTH_RESTRICTED_ENVS = _CS_V5_WIDTH_RESTRICTED_ENVS;
pub const _CS_POSIX_V7_WIDTH_RESTRICTED_ENVS = _CS_V7_WIDTH_RESTRICTED_ENVS;
pub const _GETOPT_POSIX_H = 1;
pub const _GETOPT_CORE_H = 1;
pub const F_ULOCK = 0;
pub const F_LOCK = 1;
pub const F_TLOCK = 2;
pub const F_TEST = 3;
pub const _STRING_H = 1;
pub const _BITS_TYPES_LOCALE_T_H = 1;
pub const _BITS_TYPES___LOCALE_T_H = 1;
pub const _STRINGS_H = 1;
pub const ASHMIF_VERSION_MAJOR = 0;
pub const ASHMIF_VERSION_MINOR = 13;
pub const BADFD = -1;
pub const _SYS_STAT_H = 1;
pub const _BITS_STAT_H = 1;
pub const _STAT_VER_KERNEL = 0;
pub const _STAT_VER_LINUX = 1;
pub const _MKNOD_VER_LINUX = 0;
pub const _STAT_VER = _STAT_VER_LINUX;
pub const st_atime = st_atim.tv_sec;
pub const st_mtime = st_mtim.tv_sec;
pub const st_ctime = st_ctim.tv_sec;
pub const __S_IFMT = 0o0170000;
pub const __S_IFDIR = 0o0040000;
pub const __S_IFCHR = 0o0020000;
pub const __S_IFBLK = 0o0060000;
pub const __S_IFREG = 0o0100000;
pub const __S_IFIFO = 0o0010000;
pub const __S_IFLNK = 0o0120000;
pub const __S_IFSOCK = 0o0140000;
pub inline fn __S_TYPEISMQ(buf: anytype) @TypeOf((buf.*.st_mode) - (buf.*.st_mode)) {
    return (buf.*.st_mode) - (buf.*.st_mode);
}
pub inline fn __S_TYPEISSEM(buf: anytype) @TypeOf((buf.*.st_mode) - (buf.*.st_mode)) {
    return (buf.*.st_mode) - (buf.*.st_mode);
}
pub inline fn __S_TYPEISSHM(buf: anytype) @TypeOf((buf.*.st_mode) - (buf.*.st_mode)) {
    return (buf.*.st_mode) - (buf.*.st_mode);
}
pub const __S_ISUID = 0o04000;
pub const __S_ISGID = 0o02000;
pub const __S_ISVTX = 0o01000;
pub const __S_IREAD = 0o0400;
pub const __S_IWRITE = 0o0200;
pub const __S_IEXEC = 0o0100;
pub const UTIME_NOW = (@as(c_long, 1) << 30) - @as(c_long, 1);
pub const UTIME_OMIT = (@as(c_long, 1) << 30) - @as(c_long, 2);
pub const S_IFMT = __S_IFMT;
pub const S_IFDIR = __S_IFDIR;
pub const S_IFCHR = __S_IFCHR;
pub const S_IFBLK = __S_IFBLK;
pub const S_IFREG = __S_IFREG;
pub const S_IFIFO = __S_IFIFO;
pub const S_IFLNK = __S_IFLNK;
pub const S_IFSOCK = __S_IFSOCK;
pub inline fn __S_ISTYPE(mode: anytype, mask: anytype) @TypeOf((mode & __S_IFMT) == mask) {
    return (mode & __S_IFMT) == mask;
}
pub inline fn S_ISDIR(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFDIR)) {
    return __S_ISTYPE(mode, __S_IFDIR);
}
pub inline fn S_ISCHR(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFCHR)) {
    return __S_ISTYPE(mode, __S_IFCHR);
}
pub inline fn S_ISBLK(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFBLK)) {
    return __S_ISTYPE(mode, __S_IFBLK);
}
pub inline fn S_ISREG(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFREG)) {
    return __S_ISTYPE(mode, __S_IFREG);
}
pub inline fn S_ISFIFO(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFIFO)) {
    return __S_ISTYPE(mode, __S_IFIFO);
}
pub inline fn S_ISLNK(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFLNK)) {
    return __S_ISTYPE(mode, __S_IFLNK);
}
pub inline fn S_ISSOCK(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFSOCK)) {
    return __S_ISTYPE(mode, __S_IFSOCK);
}
pub inline fn S_TYPEISMQ(buf: anytype) @TypeOf(__S_TYPEISMQ(buf)) {
    return __S_TYPEISMQ(buf);
}
pub inline fn S_TYPEISSEM(buf: anytype) @TypeOf(__S_TYPEISSEM(buf)) {
    return __S_TYPEISSEM(buf);
}
pub inline fn S_TYPEISSHM(buf: anytype) @TypeOf(__S_TYPEISSHM(buf)) {
    return __S_TYPEISSHM(buf);
}
pub const S_ISUID = __S_ISUID;
pub const S_ISGID = __S_ISGID;
pub const S_ISVTX = __S_ISVTX;
pub const S_IRUSR = __S_IREAD;
pub const S_IWUSR = __S_IWRITE;
pub const S_IXUSR = __S_IEXEC;
pub const S_IRWXU = (__S_IREAD | __S_IWRITE) | __S_IEXEC;
pub const S_IREAD = S_IRUSR;
pub const S_IWRITE = S_IWUSR;
pub const S_IEXEC = S_IXUSR;
pub const S_IRGRP = S_IRUSR >> 3;
pub const S_IWGRP = S_IWUSR >> 3;
pub const S_IXGRP = S_IXUSR >> 3;
pub const S_IRWXG = S_IRWXU >> 3;
pub const S_IROTH = S_IRGRP >> 3;
pub const S_IWOTH = S_IWGRP >> 3;
pub const S_IXOTH = S_IXGRP >> 3;
pub const S_IRWXO = S_IRWXG >> 3;
pub const ACCESSPERMS = (S_IRWXU | S_IRWXG) | S_IRWXO;
pub const ALLPERMS = ((((S_ISUID | S_ISGID) | S_ISVTX) | S_IRWXU) | S_IRWXG) | S_IRWXO;
pub const DEFFILEMODE = ((((S_IRUSR | S_IWUSR) | S_IRGRP) | S_IWGRP) | S_IROTH) | S_IWOTH;
pub const S_BLKSIZE = 512;
pub const _MKNOD_VER = 0;
pub const _SEMAPHORE_H = 1;
pub const __SIZEOF_SEM_T = 32;
pub const SEM_FAILED = (@import("std").meta.cast([*c]sem_t, 0));
pub const SHMIF_PLEDGE_PREFIX = "stdio unix sendfd recvfd proc ps rpath wpath cpath tmppath unveil video";
pub const ASHMIF_MSTATE_SZ = 32;
pub inline fn _INT_SHMIF_TEVAL(X: anytype, Y: anytype) @TypeOf(_INT_SHMIF_TMERGE(X, Y)) {
    return _INT_SHMIF_TMERGE(X, Y);
}
pub inline fn ARCAN_EVENT(X: anytype) @TypeOf(_INT_SHMIF_TEVAL(EVENT_EXTERNAL_, X)) {
    return _INT_SHMIF_TEVAL(EVENT_EXTERNAL_, X);
}
pub const ARCAN_SHMIF_PREFIX = ".arcan/.";
pub const ARCAN_SHM_UMASK = S_IRWXU | S_IRWXG;
pub const PP_QUEUE_SZ = 127;
pub const AUDIO_SAMPLE_TYPE = i16;
pub inline fn SHMIF_AFLOAT(X: anytype) @TypeOf((@import("std").meta.cast(i16, X * 32767.0))) {
    return (@import("std").meta.cast(i16, X * 32767.0));
}
pub inline fn SHMIF_AINT16(X: anytype) @TypeOf((@import("std").meta.cast(i16, X))) {
    return (@import("std").meta.cast(i16, X));
}
pub const ARCAN_SHMIF_ABUFC_LIM = 12;
pub const ARCAN_SHMIF_VBUFC_LIM = 3;
pub const PP_SHMPAGE_MAXW = 8192;
pub const PP_SHMPAGE_MAXH = 8192;
pub const PP_SHMPAGE_SHMKEYLIM = 32;
pub const VIDEO_PIXEL_TYPE = u32;
pub const ARCAN_SHMPAGE_VCHANNELS = 4;
pub const ARCAN_SHMPAGE_DEFAULT_PPCM = 37.795276;
pub const PP_SHMPAGE_STARTSZ = 2014088;
pub const PP_SHMPAGE_MAXSZ = 104857600;
pub const PP_SHMPAGE_ALIGN = 64;
pub inline fn SHMIF_RGBA(r: anytype, g: anytype, b: anytype, a: anytype) @TypeOf(((((@import("std").meta.cast(u32, a)) << 24) | ((@import("std").meta.cast(u32, r)) << 16)) | ((@import("std").meta.cast(u32, g)) << 8)) | (@import("std").meta.cast(u32, b))) {
    return ((((@import("std").meta.cast(u32, a)) << 24) | ((@import("std").meta.cast(u32, r)) << 16)) | ((@import("std").meta.cast(u32, g)) << 8)) | (@import("std").meta.cast(u32, b));
}
pub const SHMIF_RGBA_RSHIFT = 16;
pub const SHMIF_RGBA_GSHIFT = 8;
pub const SHMIF_RGBA_BSHIFT = 0;
pub const SHMIF_RGBA_ASHIFT = 24;
pub const SHMIF_CMRAMP_PLIM = 4;
pub const SHMIF_CMRAMP_UPLIM = 4095;
pub const ARCAN_SHMIF_RAMPMAGIC = 0xfafafa10;
pub inline fn TUI_HAS_ATTR(X: anytype, Y: anytype) @TypeOf(!!((X.aflags) & Y != 0)) {
    return !!((X.aflags) & Y != 0);
}
pub const _INTTYPES_H = 1;
pub const ____gwchar_t_defined = 1;
pub const __PRI64_PREFIX = "l";
pub const __PRIPTR_PREFIX = "l";
pub const PRId8 = "d";
pub const PRId16 = "d";
pub const PRId32 = "d";
pub const PRId64 = __PRI64_PREFIX ++ "d";
pub const PRIdLEAST8 = "d";
pub const PRIdLEAST16 = "d";
pub const PRIdLEAST32 = "d";
pub const PRIdLEAST64 = __PRI64_PREFIX ++ "d";
pub const PRIdFAST8 = "d";
pub const PRIdFAST16 = __PRIPTR_PREFIX ++ "d";
pub const PRIdFAST32 = __PRIPTR_PREFIX ++ "d";
pub const PRIdFAST64 = __PRI64_PREFIX ++ "d";
pub const PRIi8 = "i";
pub const PRIi16 = "i";
pub const PRIi32 = "i";
pub const PRIi64 = __PRI64_PREFIX ++ "i";
pub const PRIiLEAST8 = "i";
pub const PRIiLEAST16 = "i";
pub const PRIiLEAST32 = "i";
pub const PRIiLEAST64 = __PRI64_PREFIX ++ "i";
pub const PRIiFAST8 = "i";
pub const PRIiFAST16 = __PRIPTR_PREFIX ++ "i";
pub const PRIiFAST32 = __PRIPTR_PREFIX ++ "i";
pub const PRIiFAST64 = __PRI64_PREFIX ++ "i";
pub const PRIo8 = "o";
pub const PRIo16 = "o";
pub const PRIo32 = "o";
pub const PRIo64 = __PRI64_PREFIX ++ "o";
pub const PRIoLEAST8 = "o";
pub const PRIoLEAST16 = "o";
pub const PRIoLEAST32 = "o";
pub const PRIoLEAST64 = __PRI64_PREFIX ++ "o";
pub const PRIoFAST8 = "o";
pub const PRIoFAST16 = __PRIPTR_PREFIX ++ "o";
pub const PRIoFAST32 = __PRIPTR_PREFIX ++ "o";
pub const PRIoFAST64 = __PRI64_PREFIX ++ "o";
pub const PRIu8 = "u";
pub const PRIu16 = "u";
pub const PRIu32 = "u";
pub const PRIu64 = __PRI64_PREFIX ++ "u";
pub const PRIuLEAST8 = "u";
pub const PRIuLEAST16 = "u";
pub const PRIuLEAST32 = "u";
pub const PRIuLEAST64 = __PRI64_PREFIX ++ "u";
pub const PRIuFAST8 = "u";
pub const PRIuFAST16 = __PRIPTR_PREFIX ++ "u";
pub const PRIuFAST32 = __PRIPTR_PREFIX ++ "u";
pub const PRIuFAST64 = __PRI64_PREFIX ++ "u";
pub const PRIx8 = "x";
pub const PRIx16 = "x";
pub const PRIx32 = "x";
pub const PRIx64 = __PRI64_PREFIX ++ "x";
pub const PRIxLEAST8 = "x";
pub const PRIxLEAST16 = "x";
pub const PRIxLEAST32 = "x";
pub const PRIxLEAST64 = __PRI64_PREFIX ++ "x";
pub const PRIxFAST8 = "x";
pub const PRIxFAST16 = __PRIPTR_PREFIX ++ "x";
pub const PRIxFAST32 = __PRIPTR_PREFIX ++ "x";
pub const PRIxFAST64 = __PRI64_PREFIX ++ "x";
pub const PRIX8 = "X";
pub const PRIX16 = "X";
pub const PRIX32 = "X";
pub const PRIX64 = __PRI64_PREFIX ++ "X";
pub const PRIXLEAST8 = "X";
pub const PRIXLEAST16 = "X";
pub const PRIXLEAST32 = "X";
pub const PRIXLEAST64 = __PRI64_PREFIX ++ "X";
pub const PRIXFAST8 = "X";
pub const PRIXFAST16 = __PRIPTR_PREFIX ++ "X";
pub const PRIXFAST32 = __PRIPTR_PREFIX ++ "X";
pub const PRIXFAST64 = __PRI64_PREFIX ++ "X";
pub const PRIdMAX = __PRI64_PREFIX ++ "d";
pub const PRIiMAX = __PRI64_PREFIX ++ "i";
pub const PRIoMAX = __PRI64_PREFIX ++ "o";
pub const PRIuMAX = __PRI64_PREFIX ++ "u";
pub const PRIxMAX = __PRI64_PREFIX ++ "x";
pub const PRIXMAX = __PRI64_PREFIX ++ "X";
pub const PRIdPTR = __PRIPTR_PREFIX ++ "d";
pub const PRIiPTR = __PRIPTR_PREFIX ++ "i";
pub const PRIoPTR = __PRIPTR_PREFIX ++ "o";
pub const PRIuPTR = __PRIPTR_PREFIX ++ "u";
pub const PRIxPTR = __PRIPTR_PREFIX ++ "x";
pub const PRIXPTR = __PRIPTR_PREFIX ++ "X";
pub const SCNd8 = "hhd";
pub const SCNd16 = "hd";
pub const SCNd32 = "d";
pub const SCNd64 = __PRI64_PREFIX ++ "d";
pub const SCNdLEAST8 = "hhd";
pub const SCNdLEAST16 = "hd";
pub const SCNdLEAST32 = "d";
pub const SCNdLEAST64 = __PRI64_PREFIX ++ "d";
pub const SCNdFAST8 = "hhd";
pub const SCNdFAST16 = __PRIPTR_PREFIX ++ "d";
pub const SCNdFAST32 = __PRIPTR_PREFIX ++ "d";
pub const SCNdFAST64 = __PRI64_PREFIX ++ "d";
pub const SCNi8 = "hhi";
pub const SCNi16 = "hi";
pub const SCNi32 = "i";
pub const SCNi64 = __PRI64_PREFIX ++ "i";
pub const SCNiLEAST8 = "hhi";
pub const SCNiLEAST16 = "hi";
pub const SCNiLEAST32 = "i";
pub const SCNiLEAST64 = __PRI64_PREFIX ++ "i";
pub const SCNiFAST8 = "hhi";
pub const SCNiFAST16 = __PRIPTR_PREFIX ++ "i";
pub const SCNiFAST32 = __PRIPTR_PREFIX ++ "i";
pub const SCNiFAST64 = __PRI64_PREFIX ++ "i";
pub const SCNu8 = "hhu";
pub const SCNu16 = "hu";
pub const SCNu32 = "u";
pub const SCNu64 = __PRI64_PREFIX ++ "u";
pub const SCNuLEAST8 = "hhu";
pub const SCNuLEAST16 = "hu";
pub const SCNuLEAST32 = "u";
pub const SCNuLEAST64 = __PRI64_PREFIX ++ "u";
pub const SCNuFAST8 = "hhu";
pub const SCNuFAST16 = __PRIPTR_PREFIX ++ "u";
pub const SCNuFAST32 = __PRIPTR_PREFIX ++ "u";
pub const SCNuFAST64 = __PRI64_PREFIX ++ "u";
pub const SCNo8 = "hho";
pub const SCNo16 = "ho";
pub const SCNo32 = "o";
pub const SCNo64 = __PRI64_PREFIX ++ "o";
pub const SCNoLEAST8 = "hho";
pub const SCNoLEAST16 = "ho";
pub const SCNoLEAST32 = "o";
pub const SCNoLEAST64 = __PRI64_PREFIX ++ "o";
pub const SCNoFAST8 = "hho";
pub const SCNoFAST16 = __PRIPTR_PREFIX ++ "o";
pub const SCNoFAST32 = __PRIPTR_PREFIX ++ "o";
pub const SCNoFAST64 = __PRI64_PREFIX ++ "o";
pub const SCNx8 = "hhx";
pub const SCNx16 = "hx";
pub const SCNx32 = "x";
pub const SCNx64 = __PRI64_PREFIX ++ "x";
pub const SCNxLEAST8 = "hhx";
pub const SCNxLEAST16 = "hx";
pub const SCNxLEAST32 = "x";
pub const SCNxLEAST64 = __PRI64_PREFIX ++ "x";
pub const SCNxFAST8 = "hhx";
pub const SCNxFAST16 = __PRIPTR_PREFIX ++ "x";
pub const SCNxFAST32 = __PRIPTR_PREFIX ++ "x";
pub const SCNxFAST64 = __PRI64_PREFIX ++ "x";
pub const SCNdMAX = __PRI64_PREFIX ++ "d";
pub const SCNiMAX = __PRI64_PREFIX ++ "i";
pub const SCNoMAX = __PRI64_PREFIX ++ "o";
pub const SCNuMAX = __PRI64_PREFIX ++ "u";
pub const SCNxMAX = __PRI64_PREFIX ++ "x";
pub const SCNdPTR = __PRIPTR_PREFIX ++ "d";
pub const SCNiPTR = __PRIPTR_PREFIX ++ "i";
pub const SCNoPTR = __PRIPTR_PREFIX ++ "o";
pub const SCNuPTR = __PRIPTR_PREFIX ++ "u";
pub const SCNxPTR = __PRIPTR_PREFIX ++ "x";
pub const _ERRNO_H = 1;
pub const _BITS_ERRNO_H = 1;
pub const EPERM = 1;
pub const ENOENT = 2;
pub const ESRCH = 3;
pub const EINTR = 4;
pub const EIO = 5;
pub const ENXIO = 6;
pub const E2BIG = 7;
pub const ENOEXEC = 8;
pub const EBADF = 9;
pub const ECHILD = 10;
pub const EAGAIN = 11;
pub const ENOMEM = 12;
pub const EACCES = 13;
pub const EFAULT = 14;
pub const ENOTBLK = 15;
pub const EBUSY = 16;
pub const EEXIST = 17;
pub const EXDEV = 18;
pub const ENODEV = 19;
pub const ENOTDIR = 20;
pub const EISDIR = 21;
pub const EINVAL = 22;
pub const ENFILE = 23;
pub const EMFILE = 24;
pub const ENOTTY = 25;
pub const ETXTBSY = 26;
pub const EFBIG = 27;
pub const ENOSPC = 28;
pub const ESPIPE = 29;
pub const EROFS = 30;
pub const EMLINK = 31;
pub const EPIPE = 32;
pub const EDOM = 33;
pub const ERANGE = 34;
pub const EDEADLK = 35;
pub const ENAMETOOLONG = 36;
pub const ENOLCK = 37;
pub const ENOSYS = 38;
pub const ENOTEMPTY = 39;
pub const ELOOP = 40;
pub const EWOULDBLOCK = EAGAIN;
pub const ENOMSG = 42;
pub const EIDRM = 43;
pub const ECHRNG = 44;
pub const EL2NSYNC = 45;
pub const EL3HLT = 46;
pub const EL3RST = 47;
pub const ELNRNG = 48;
pub const EUNATCH = 49;
pub const ENOCSI = 50;
pub const EL2HLT = 51;
pub const EBADE = 52;
pub const EBADR = 53;
pub const EXFULL = 54;
pub const ENOANO = 55;
pub const EBADRQC = 56;
pub const EBADSLT = 57;
pub const EDEADLOCK = EDEADLK;
pub const EBFONT = 59;
pub const ENOSTR = 60;
pub const ENODATA = 61;
pub const ETIME = 62;
pub const ENOSR = 63;
pub const ENONET = 64;
pub const ENOPKG = 65;
pub const EREMOTE = 66;
pub const ENOLINK = 67;
pub const EADV = 68;
pub const ESRMNT = 69;
pub const ECOMM = 70;
pub const EPROTO = 71;
pub const EMULTIHOP = 72;
pub const EDOTDOT = 73;
pub const EBADMSG = 74;
pub const EOVERFLOW = 75;
pub const ENOTUNIQ = 76;
pub const EBADFD = 77;
pub const EREMCHG = 78;
pub const ELIBACC = 79;
pub const ELIBBAD = 80;
pub const ELIBSCN = 81;
pub const ELIBMAX = 82;
pub const ELIBEXEC = 83;
pub const EILSEQ = 84;
pub const ERESTART = 85;
pub const ESTRPIPE = 86;
pub const EUSERS = 87;
pub const ENOTSOCK = 88;
pub const EDESTADDRREQ = 89;
pub const EMSGSIZE = 90;
pub const EPROTOTYPE = 91;
pub const ENOPROTOOPT = 92;
pub const EPROTONOSUPPORT = 93;
pub const ESOCKTNOSUPPORT = 94;
pub const EOPNOTSUPP = 95;
pub const EPFNOSUPPORT = 96;
pub const EAFNOSUPPORT = 97;
pub const EADDRINUSE = 98;
pub const EADDRNOTAVAIL = 99;
pub const ENETDOWN = 100;
pub const ENETUNREACH = 101;
pub const ENETRESET = 102;
pub const ECONNABORTED = 103;
pub const ECONNRESET = 104;
pub const ENOBUFS = 105;
pub const EISCONN = 106;
pub const ENOTCONN = 107;
pub const ESHUTDOWN = 108;
pub const ETOOMANYREFS = 109;
pub const ETIMEDOUT = 110;
pub const ECONNREFUSED = 111;
pub const EHOSTDOWN = 112;
pub const EHOSTUNREACH = 113;
pub const EALREADY = 114;
pub const EINPROGRESS = 115;
pub const ESTALE = 116;
pub const EUCLEAN = 117;
pub const ENOTNAM = 118;
pub const ENAVAIL = 119;
pub const EISNAM = 120;
pub const EREMOTEIO = 121;
pub const EDQUOT = 122;
pub const ENOMEDIUM = 123;
pub const EMEDIUMTYPE = 124;
pub const ECANCELED = 125;
pub const ENOKEY = 126;
pub const EKEYEXPIRED = 127;
pub const EKEYREVOKED = 128;
pub const EKEYREJECTED = 129;
pub const EOWNERDEAD = 130;
pub const ENOTRECOVERABLE = 131;
pub const ERFKILL = 132;
pub const EHWPOISON = 133;
pub const ENOTSUP = EOPNOTSUPP;
pub const timeval = struct_timeval;
pub const timespec = struct_timespec;
pub const __pthread_internal_list = struct___pthread_internal_list;
pub const __pthread_internal_slist = struct___pthread_internal_slist;
pub const __pthread_mutex_s = struct___pthread_mutex_s;
pub const __pthread_rwlock_arch_t = struct___pthread_rwlock_arch_t;
pub const __pthread_cond_s = struct___pthread_cond_s;
pub const random_data = struct_random_data;
pub const drand48_data = struct_drand48_data;
pub const _G_fpos_t = struct__G_fpos_t;
pub const _G_fpos64_t = struct__G_fpos64_t;
pub const _IO_marker = struct__IO_marker;
pub const _IO_codecvt = struct__IO_codecvt;
pub const _IO_wide_data = struct__IO_wide_data;
pub const _IO_FILE = struct__IO_FILE;
pub const __va_list_tag = struct___va_list_tag;
pub const __locale_data = struct___locale_data;
pub const __locale_struct = struct___locale_struct;
pub const arcan_shmif_page = struct_arcan_shmif_page;
pub const arcan_shmif_region = struct_arcan_shmif_region;
pub const shmif_hidden = struct_shmif_hidden;
pub const shmif_ext_hidden = struct_shmif_ext_hidden;
pub const arcan_shmif_cont = struct_arcan_shmif_cont;
pub const arg_arr = struct_arg_arr;
pub const shmif_privsep_node = struct_shmif_privsep_node;
pub const ARCAN_EVENT_CATEGORY = enum_ARCAN_EVENT_CATEGORY;
pub const ARCAN_SEGID = enum_ARCAN_SEGID;
pub const ARCAN_TARGET_COMMAND = enum_ARCAN_TARGET_COMMAND;
pub const ARCAN_EVENT_EXTERNAL = enum_ARCAN_EVENT_EXTERNAL;
pub const ARCAN_TARGET_SKIPMODE = enum_ARCAN_TARGET_SKIPMODE;
pub const ARCAN_EVENT_IO = enum_ARCAN_EVENT_IO;
pub const ARCAN_MBTN_IMAP = enum_ARCAN_MBTN_IMAP;
pub const ARCAN_EVENT_IDEVKIND = enum_ARCAN_EVENT_IDEVKIND;
pub const ARCAN_IDEV_STATUS = enum_ARCAN_IDEV_STATUS;
pub const ARCAN_EVENT_IDATATYPE = enum_ARCAN_EVENT_IDATATYPE;
pub const ARCAN_EVENT_VIDEO = enum_ARCAN_EVENT_VIDEO;
pub const ARCAN_EVENT_SYSTEM = enum_ARCAN_EVENT_SYSTEM;
pub const ARCAN_EVENT_AUDIO = enum_ARCAN_EVENT_AUDIO;
pub const ARCAN_EVENT_FSRV = enum_ARCAN_EVENT_FSRV;
pub const ARCAN_EVENT_IOFLAG = enum_ARCAN_EVENT_IOFLAG;
pub const arcan_shmif_type = enum_arcan_shmif_type;
pub const arcan_shmif_sigmask = enum_arcan_shmif_sigmask;
pub const ARCAN_FLAGS = enum_ARCAN_FLAGS;
pub const shmif_open_ext = struct_shmif_open_ext;
pub const shmif_migrate_status = enum_shmif_migrate_status;
pub const shmif_ext_meta = enum_shmif_ext_meta;
pub const shmif_resize_ext = struct_shmif_resize_ext;
pub const rhint_mask = enum_rhint_mask;
pub const arcan_shmif_vr = struct_arcan_shmif_vr;
pub const arcan_shmif_ramp = struct_arcan_shmif_ramp;
pub const arcan_shmif_hdr16f = struct_arcan_shmif_hdr16f;
pub const arcan_shmif_vector = struct_arcan_shmif_vector;
pub const arcan_shmif_venc = struct_arcan_shmif_venc;
pub const shmif_ext_substruct = union_shmif_ext_substruct;
pub const arcan_shmif_ofstbl = struct_arcan_shmif_ofstbl;
pub const shmif_vector_mesh = struct_shmif_vector_mesh;
pub const ramp_block = struct_ramp_block;
pub const tui_context_flags = enum_tui_context_flags;
pub const tui_attr_flags = enum_tui_attr_flags;
pub const tui_wndhint_flags = enum_tui_wndhint_flags;
pub const tui_message_slots = enum_tui_message_slots;
pub const tui_progress_type = enum_tui_progress_type;
pub const tui_cli = enum_tui_cli;
pub const tui_handover_flags = enum_tui_handover_flags;
pub const tui_subwnd_type = enum_tui_subwnd_type;
pub const tui_color_group = enum_tui_color_group;
pub const tui_cursors = enum_tui_cursors;
pub const tuim_syms = enum_tuim_syms;
pub const tuibtn_syms = enum_tuibtn_syms;
pub const tuik_syms = enum_tuik_syms;
pub const tui_context = struct_tui_context;
pub const tui_constraints = struct_tui_constraints;
pub const tui_screen_attr = struct_tui_screen_attr;
pub const tui_cell = struct_tui_cell;
pub const tui_labelent = struct_tui_labelent;
pub const tui_cbcfg = struct_tui_cbcfg;
pub const tui_process_errc = enum_tui_process_errc;
pub const tui_region = struct_tui_region;
pub const tui_process_res = struct_tui_process_res;
pub const tui_subwnd_hint = enum_tui_subwnd_hint;
pub const tui_subwnd_req = struct_tui_subwnd_req;
