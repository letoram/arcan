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
pub const off_t = c_long;
pub const struct__IO_FILE = opaque {};
pub const FILE = struct__IO_FILE;
pub const struct___va_list_1 = extern struct {
    __stack: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __gr_top: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __vr_top: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __gr_offs: c_int = @import("std").mem.zeroes(c_int),
    __vr_offs: c_int = @import("std").mem.zeroes(c_int),
};
pub const __builtin_va_list = struct___va_list_1;
pub const va_list = __builtin_va_list;
pub const __isoc_va_list = __builtin_va_list;
pub const union__G_fpos64_t = extern union {
    __opaque: [16]u8,
    __lldata: c_longlong,
    __align: f64,
};
pub const fpos_t = union__G_fpos64_t;
pub extern const stdin: ?*FILE;
pub extern const stdout: ?*FILE;
pub extern const stderr: ?*FILE;
pub extern fn fopen([*c]const u8, [*c]const u8) ?*FILE;
pub extern fn freopen(noalias [*c]const u8, noalias [*c]const u8, noalias ?*FILE) ?*FILE;
pub extern fn fclose(?*FILE) c_int;
pub extern fn remove([*c]const u8) c_int;
pub extern fn rename([*c]const u8, [*c]const u8) c_int;
pub extern fn feof(?*FILE) c_int;
pub extern fn ferror(?*FILE) c_int;
pub extern fn fflush(?*FILE) c_int;
pub extern fn clearerr(?*FILE) void;
pub extern fn fseek(?*FILE, c_long, c_int) c_int;
pub extern fn ftell(?*FILE) c_long;
pub extern fn rewind(?*FILE) void;
pub extern fn fgetpos(noalias ?*FILE, noalias [*c]fpos_t) c_int;
pub extern fn fsetpos(?*FILE, [*c]const fpos_t) c_int;
pub extern fn fread(?*anyopaque, c_ulong, c_ulong, ?*FILE) c_ulong;
pub extern fn fwrite(?*const anyopaque, c_ulong, c_ulong, ?*FILE) c_ulong;
pub extern fn fgetc(?*FILE) c_int;
pub extern fn getc(?*FILE) c_int;
pub extern fn getchar() c_int;
pub extern fn ungetc(c_int, ?*FILE) c_int;
pub extern fn fputc(c_int, ?*FILE) c_int;
pub extern fn putc(c_int, ?*FILE) c_int;
pub extern fn putchar(c_int) c_int;
pub extern fn fgets(noalias [*c]u8, c_int, noalias ?*FILE) [*c]u8;
pub extern fn fputs(noalias [*c]const u8, noalias ?*FILE) c_int;
pub extern fn puts([*c]const u8) c_int;
pub extern fn printf([*c]const u8, ...) c_int;
pub extern fn fprintf(noalias ?*FILE, noalias [*c]const u8, ...) c_int;
pub extern fn sprintf(noalias [*c]u8, noalias [*c]const u8, ...) c_int;
pub extern fn snprintf(noalias [*c]u8, c_ulong, noalias [*c]const u8, ...) c_int;
pub extern fn vprintf(noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn vfprintf(noalias ?*FILE, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn vsprintf(noalias [*c]u8, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn vsnprintf(noalias [*c]u8, c_ulong, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn scanf(noalias [*c]const u8, ...) c_int;
pub extern fn fscanf(noalias ?*FILE, noalias [*c]const u8, ...) c_int;
pub extern fn sscanf(noalias [*c]const u8, noalias [*c]const u8, ...) c_int;
pub extern fn vscanf(noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn vfscanf(noalias ?*FILE, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn vsscanf(noalias [*c]const u8, noalias [*c]const u8, __builtin_va_list) c_int;
pub extern fn perror([*c]const u8) void;
pub extern fn setvbuf(noalias ?*FILE, noalias [*c]u8, c_int, usize) c_int;
pub extern fn setbuf(noalias ?*FILE, noalias [*c]u8) void;
pub extern fn tmpnam([*c]u8) [*c]u8;
pub extern fn tmpfile() ?*FILE;
pub extern fn fmemopen(noalias ?*anyopaque, usize, noalias [*c]const u8) ?*FILE;
pub extern fn open_memstream([*c][*c]u8, [*c]usize) ?*FILE;
pub extern fn fdopen(c_int, [*c]const u8) ?*FILE;
pub extern fn popen([*c]const u8, [*c]const u8) ?*FILE;
pub extern fn pclose(?*FILE) c_int;
pub extern fn fileno(?*FILE) c_int;
pub extern fn fseeko(?*FILE, off_t, c_int) c_int;
pub extern fn ftello(?*FILE) off_t;
pub extern fn dprintf(c_int, noalias [*c]const u8, ...) c_int;
pub extern fn vdprintf(c_int, noalias [*c]const u8, __isoc_va_list) c_int;
pub extern fn flockfile(?*FILE) void;
pub extern fn ftrylockfile(?*FILE) c_int;
pub extern fn funlockfile(?*FILE) void;
pub extern fn getc_unlocked(?*FILE) c_int;
pub extern fn getchar_unlocked() c_int;
pub extern fn putc_unlocked(c_int, ?*FILE) c_int;
pub extern fn putchar_unlocked(c_int) c_int;
pub extern fn getdelim(noalias [*c][*c]u8, noalias [*c]usize, c_int, noalias ?*FILE) isize;
pub extern fn getline(noalias [*c][*c]u8, noalias [*c]usize, noalias ?*FILE) isize;
pub extern fn renameat(c_int, [*c]const u8, c_int, [*c]const u8) c_int;
pub extern fn ctermid([*c]u8) [*c]u8;
pub extern fn tempnam([*c]const u8, [*c]const u8) [*c]u8;
pub extern fn cuserid([*c]u8) [*c]u8;
pub extern fn setlinebuf(?*FILE) void;
pub extern fn setbuffer(?*FILE, [*c]u8, usize) void;
pub extern fn fgetc_unlocked(?*FILE) c_int;
pub extern fn fputc_unlocked(c_int, ?*FILE) c_int;
pub extern fn fflush_unlocked(?*FILE) c_int;
pub extern fn fread_unlocked(?*anyopaque, usize, usize, ?*FILE) usize;
pub extern fn fwrite_unlocked(?*const anyopaque, usize, usize, ?*FILE) usize;
pub extern fn clearerr_unlocked(?*FILE) void;
pub extern fn feof_unlocked(?*FILE) c_int;
pub extern fn ferror_unlocked(?*FILE) c_int;
pub extern fn fileno_unlocked(?*FILE) c_int;
pub extern fn getw(?*FILE) c_int;
pub extern fn putw(c_int, ?*FILE) c_int;
pub extern fn fgetln(?*FILE, [*c]usize) [*c]u8;
pub extern fn asprintf([*c][*c]u8, [*c]const u8, ...) c_int;
pub extern fn vasprintf([*c][*c]u8, [*c]const u8, __isoc_va_list) c_int;
pub const STBI_default: c_int = 0;
pub const STBI_grey: c_int = 1;
pub const STBI_grey_alpha: c_int = 2;
pub const STBI_rgb: c_int = 3;
pub const STBI_rgb_alpha: c_int = 4;
const enum_unnamed_2 = c_uint;
pub const wchar_t = c_uint;
pub extern fn atoi([*c]const u8) c_int;
pub extern fn atol([*c]const u8) c_long;
pub extern fn atoll([*c]const u8) c_longlong;
pub extern fn atof([*c]const u8) f64;
pub extern fn strtof([*c]const u8, [*c][*c]u8) f32;
pub extern fn strtod([*c]const u8, [*c][*c]u8) f64;
pub extern fn strtold([*c]const u8, [*c][*c]u8) c_longdouble;
pub extern fn strtol([*c]const u8, [*c][*c]u8, c_int) c_long;
pub extern fn strtoul([*c]const u8, [*c][*c]u8, c_int) c_ulong;
pub extern fn strtoll([*c]const u8, [*c][*c]u8, c_int) c_longlong;
pub extern fn strtoull([*c]const u8, [*c][*c]u8, c_int) c_ulonglong;
pub extern fn rand() c_int;
pub extern fn srand(c_uint) void;
pub extern fn malloc(c_ulong) ?*anyopaque;
pub extern fn calloc(c_ulong, c_ulong) ?*anyopaque;
pub extern fn realloc(?*anyopaque, c_ulong) ?*anyopaque;
pub extern fn free(?*anyopaque) void;
pub extern fn aligned_alloc(c_ulong, c_ulong) ?*anyopaque;
pub extern fn abort() noreturn;
pub extern fn atexit(?*const fn () callconv(.c) void) c_int;
pub extern fn exit(c_int) noreturn;
pub extern fn _Exit(c_int) noreturn;
pub extern fn at_quick_exit(?*const fn () callconv(.c) void) c_int;
pub extern fn quick_exit(c_int) void;
pub extern fn getenv([*c]const u8) [*c]u8;
pub extern fn system([*c]const u8) c_int;
pub extern fn bsearch(?*const anyopaque, ?*const anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int) ?*anyopaque;
pub extern fn qsort(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int) void;
pub extern fn abs(c_int) c_int;
pub extern fn labs(c_long) c_long;
pub extern fn llabs(c_longlong) c_longlong;
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
pub extern fn div(c_int, c_int) div_t;
pub extern fn ldiv(c_long, c_long) ldiv_t;
pub extern fn lldiv(c_longlong, c_longlong) lldiv_t;
pub extern fn mblen([*c]const u8, usize) c_int;
pub extern fn mbtowc(noalias [*c]wchar_t, noalias [*c]const u8, usize) c_int;
pub extern fn wctomb([*c]u8, wchar_t) c_int;
pub extern fn mbstowcs(noalias [*c]wchar_t, noalias [*c]const u8, usize) usize;
pub extern fn wcstombs(noalias [*c]u8, noalias [*c]const wchar_t, usize) usize;
pub extern fn __ctype_get_mb_cur_max() usize;
pub extern fn posix_memalign([*c]?*anyopaque, usize, usize) c_int;
pub extern fn setenv([*c]const u8, [*c]const u8, c_int) c_int;
pub extern fn unsetenv([*c]const u8) c_int;
pub extern fn mkstemp([*c]u8) c_int;
pub extern fn mkostemp([*c]u8, c_int) c_int;
pub extern fn mkdtemp([*c]u8) [*c]u8;
pub extern fn getsubopt([*c][*c]u8, [*c]const [*c]u8, [*c][*c]u8) c_int;
pub extern fn rand_r([*c]c_uint) c_int;
pub extern fn realpath(noalias [*c]const u8, noalias [*c]u8) [*c]u8;
pub extern fn random() c_long;
pub extern fn srandom(c_uint) void;
pub extern fn initstate(c_uint, [*c]u8, usize) [*c]u8;
pub extern fn setstate([*c]u8) [*c]u8;
pub extern fn putenv([*c]u8) c_int;
pub extern fn posix_openpt(c_int) c_int;
pub extern fn grantpt(c_int) c_int;
pub extern fn unlockpt(c_int) c_int;
pub extern fn ptsname(c_int) [*c]u8;
pub extern fn l64a(c_long) [*c]u8;
pub extern fn a64l([*c]const u8) c_long;
pub extern fn setkey([*c]const u8) void;
pub extern fn drand48() f64;
pub extern fn erand48([*c]c_ushort) f64;
pub extern fn lrand48() c_long;
pub extern fn nrand48([*c]c_ushort) c_long;
pub extern fn mrand48() c_long;
pub extern fn jrand48([*c]c_ushort) c_long;
pub extern fn srand48(c_long) void;
pub extern fn seed48([*c]c_ushort) [*c]c_ushort;
pub extern fn lcong48([*c]c_ushort) void;
pub extern fn alloca(c_ulong) ?*anyopaque;
pub extern fn mktemp([*c]u8) [*c]u8;
pub extern fn mkstemps([*c]u8, c_int) c_int;
pub extern fn mkostemps([*c]u8, c_int, c_int) c_int;
pub extern fn valloc(usize) ?*anyopaque;
pub extern fn memalign(c_ulong, c_ulong) ?*anyopaque;
pub extern fn getloadavg([*c]f64, c_int) c_int;
pub extern fn clearenv() c_int;
pub extern fn reallocarray(?*anyopaque, usize, usize) ?*anyopaque;
pub extern fn qsort_r(?*anyopaque, usize, usize, ?*const fn (?*const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, ?*anyopaque) void;
pub const stbi_uc = u8;
pub const stbi_us = c_ushort;
pub const stbi_io_callbacks = extern struct {
    read: ?*const fn (?*anyopaque, [*c]u8, c_int) callconv(.c) c_int = @import("std").mem.zeroes(?*const fn (?*anyopaque, [*c]u8, c_int) callconv(.c) c_int),
    skip: ?*const fn (?*anyopaque, c_int) callconv(.c) void = @import("std").mem.zeroes(?*const fn (?*anyopaque, c_int) callconv(.c) void),
    eof: ?*const fn (?*anyopaque) callconv(.c) c_int = @import("std").mem.zeroes(?*const fn (?*anyopaque) callconv(.c) c_int),
};
pub export fn stbi_load_from_memory(arg_buffer: [*c]const stbi_uc, arg_len: c_int, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]stbi_uc {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_mem(&s, buffer, len);
    return stbi__load_and_postprocess_8bit(&s, x, y, comp, req_comp);
}
pub fn stbi_load_from_callbacks(arg_clbk: [*c]const stbi_io_callbacks, arg_user: ?*anyopaque, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]stbi_uc {
    var clbk = arg_clbk;
    _ = &clbk;
    var user = arg_user;
    _ = &user;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_callbacks(&s, @as([*c]stbi_io_callbacks, @ptrCast(@constCast(@volatileCast(clbk)))), user);
    return stbi__load_and_postprocess_8bit(&s, x, y, comp, req_comp);
}
pub fn stbi_load(arg_filename: [*c]const u8, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]stbi_uc {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var f: ?*FILE = stbi__fopen(filename, "rb");
    _ = &f;
    var result: [*c]u8 = undefined;
    _ = &result;
    if (!(f != null)) return @as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
    result = stbi_load_from_file(f, x, y, comp, req_comp);
    _ = fclose(f);
    return result;
}
pub fn stbi_load_from_file(arg_f: ?*FILE, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]stbi_uc {
    var f = arg_f;
    _ = &f;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var result: [*c]u8 = undefined;
    _ = &result;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_file(&s, f);
    result = stbi__load_and_postprocess_8bit(&s, x, y, comp, req_comp);
    if (result != null) {
        _ = fseek(f, @as(c_long, @bitCast(@as(c_long, -@as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(s.img_buffer_end) -% @intFromPtr(s.img_buffer))), @sizeOf(stbi_uc))))))))), @as(c_int, 1));
    }
    return result;
}
pub extern fn stbi_load_gif_from_memory(buffer: [*c]const stbi_uc, len: c_int, delays: [*c][*c]c_int, x: [*c]c_int, y: [*c]c_int, z: [*c]c_int, comp: [*c]c_int, req_comp: c_int) [*c]stbi_uc;
pub fn stbi_load_16_from_memory(arg_buffer: [*c]const stbi_uc, arg_len: c_int, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_channels_in_file: [*c]c_int, arg_desired_channels: c_int) callconv(.c) [*c]stbi_us {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var channels_in_file = arg_channels_in_file;
    _ = &channels_in_file;
    var desired_channels = arg_desired_channels;
    _ = &desired_channels;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_mem(&s, buffer, len);
    return stbi__load_and_postprocess_16bit(&s, x, y, channels_in_file, desired_channels);
}
pub fn stbi_load_16_from_callbacks(arg_clbk: [*c]const stbi_io_callbacks, arg_user: ?*anyopaque, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_channels_in_file: [*c]c_int, arg_desired_channels: c_int) callconv(.c) [*c]stbi_us {
    var clbk = arg_clbk;
    _ = &clbk;
    var user = arg_user;
    _ = &user;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var channels_in_file = arg_channels_in_file;
    _ = &channels_in_file;
    var desired_channels = arg_desired_channels;
    _ = &desired_channels;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_callbacks(&s, @as([*c]stbi_io_callbacks, @ptrCast(@constCast(@volatileCast(clbk)))), user);
    return stbi__load_and_postprocess_16bit(&s, x, y, channels_in_file, desired_channels);
}
pub const stbi__uint16 = u16;
pub fn stbi_load_16(arg_filename: [*c]const u8, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]stbi_us {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var f: ?*FILE = stbi__fopen(filename, "rb");
    _ = &f;
    var result: [*c]stbi__uint16 = undefined;
    _ = &result;
    if (!(f != null)) return @as([*c]stbi_us, @ptrCast(@alignCast(@as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))))));
    result = stbi_load_from_file_16(f, x, y, comp, req_comp);
    _ = fclose(f);
    return result;
}
pub fn stbi_load_from_file_16(arg_f: ?*FILE, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]stbi_us {
    var f = arg_f;
    _ = &f;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var result: [*c]stbi__uint16 = undefined;
    _ = &result;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_file(&s, f);
    result = stbi__load_and_postprocess_16bit(&s, x, y, comp, req_comp);
    if (result != null) {
        _ = fseek(f, @as(c_long, @bitCast(@as(c_long, -@as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(s.img_buffer_end) -% @intFromPtr(s.img_buffer))), @sizeOf(stbi_uc))))))))), @as(c_int, 1));
    }
    return result;
}
pub fn stbi_loadf_from_memory(arg_buffer: [*c]const stbi_uc, arg_len: c_int, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]f32 {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_mem(&s, buffer, len);
    return stbi__loadf_main(&s, x, y, comp, req_comp);
}
pub fn stbi_loadf_from_callbacks(arg_clbk: [*c]const stbi_io_callbacks, arg_user: ?*anyopaque, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]f32 {
    var clbk = arg_clbk;
    _ = &clbk;
    var user = arg_user;
    _ = &user;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_callbacks(&s, @as([*c]stbi_io_callbacks, @ptrCast(@constCast(@volatileCast(clbk)))), user);
    return stbi__loadf_main(&s, x, y, comp, req_comp);
}
pub fn stbi_loadf(arg_filename: [*c]const u8, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]f32 {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var result: [*c]f32 = undefined;
    _ = &result;
    var f: ?*FILE = stbi__fopen(filename, "rb");
    _ = &f;
    if (!(f != null)) return @as([*c]f32, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
    result = stbi_loadf_from_file(f, x, y, comp, req_comp);
    _ = fclose(f);
    return result;
}
pub fn stbi_loadf_from_file(arg_f: ?*FILE, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]f32 {
    var f = arg_f;
    _ = &f;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_file(&s, f);
    return stbi__loadf_main(&s, x, y, comp, req_comp);
}
pub fn stbi_hdr_to_ldr_gamma(arg_gamma: f32) callconv(.c) void {
    var gamma = arg_gamma;
    _ = &gamma;
    stbi__h2l_gamma_i = @as(f32, @floatFromInt(@as(c_int, 1))) / gamma;
}
pub fn stbi_hdr_to_ldr_scale(arg_scale: f32) callconv(.c) void {
    var scale = arg_scale;
    _ = &scale;
    stbi__h2l_scale_i = @as(f32, @floatFromInt(@as(c_int, 1))) / scale;
}
pub fn stbi_ldr_to_hdr_gamma(arg_gamma: f32) callconv(.c) void {
    var gamma = arg_gamma;
    _ = &gamma;
    stbi__l2h_gamma = gamma;
}
pub fn stbi_ldr_to_hdr_scale(arg_scale: f32) callconv(.c) void {
    var scale = arg_scale;
    _ = &scale;
    stbi__l2h_scale = scale;
}
pub fn stbi_is_hdr_from_callbacks(arg_clbk: [*c]const stbi_io_callbacks, arg_user: ?*anyopaque) callconv(.c) c_int {
    var clbk = arg_clbk;
    _ = &clbk;
    var user = arg_user;
    _ = &user;
    _ = @sizeOf([*c]const stbi_io_callbacks);
    _ = @sizeOf(?*anyopaque);
    return 0;
}
pub fn stbi_is_hdr_from_memory(arg_buffer: [*c]const stbi_uc, arg_len: c_int) callconv(.c) c_int {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    _ = @sizeOf([*c]const stbi_uc);
    _ = @sizeOf(c_int);
    return 0;
}
pub fn stbi_is_hdr(arg_filename: [*c]const u8) callconv(.c) c_int {
    var filename = arg_filename;
    _ = &filename;
    var f: ?*FILE = stbi__fopen(filename, "rb");
    _ = &f;
    var result: c_int = 0;
    _ = &result;
    if (f != null) {
        result = stbi_is_hdr_from_file(f);
        _ = fclose(f);
    }
    return result;
}
pub fn stbi_is_hdr_from_file(arg_f: ?*FILE) callconv(.c) c_int {
    var f = arg_f;
    _ = &f;
    _ = @sizeOf(?*FILE);
    return 0;
}
pub fn stbi_failure_reason() callconv(.c) [*c]const u8 {
    return stbi__g_failure_reason;
}
pub fn stbi_image_free(arg_retval_from_stbi_load: ?*anyopaque) callconv(.c) void {
    var retval_from_stbi_load = arg_retval_from_stbi_load;
    _ = &retval_from_stbi_load;
    free(retval_from_stbi_load);
}
pub fn stbi_info_from_memory(arg_buffer: [*c]const stbi_uc, arg_len: c_int, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_mem(&s, buffer, len);
    return stbi__info_main(&s, x, y, comp);
}
pub fn stbi_info_from_callbacks(arg_c: [*c]const stbi_io_callbacks, arg_user: ?*anyopaque, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var c = arg_c;
    _ = &c;
    var user = arg_user;
    _ = &user;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_callbacks(&s, @as([*c]stbi_io_callbacks, @ptrCast(@constCast(@volatileCast(c)))), user);
    return stbi__info_main(&s, x, y, comp);
}
pub fn stbi_is_16_bit_from_memory(arg_buffer: [*c]const stbi_uc, arg_len: c_int) callconv(.c) c_int {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_mem(&s, buffer, len);
    return stbi__is_16_main(&s);
}
pub fn stbi_is_16_bit_from_callbacks(arg_c: [*c]const stbi_io_callbacks, arg_user: ?*anyopaque) callconv(.c) c_int {
    var c = arg_c;
    _ = &c;
    var user = arg_user;
    _ = &user;
    var s: stbi__context = undefined;
    _ = &s;
    stbi__start_callbacks(&s, @as([*c]stbi_io_callbacks, @ptrCast(@constCast(@volatileCast(c)))), user);
    return stbi__is_16_main(&s);
}
pub fn stbi_info(arg_filename: [*c]const u8, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var f: ?*FILE = stbi__fopen(filename, "rb");
    _ = &f;
    var result: c_int = undefined;
    _ = &result;
    if (!(f != null)) return 0;
    result = stbi_info_from_file(f, x, y, comp);
    _ = fclose(f);
    return result;
}
pub fn stbi_info_from_file(arg_f: ?*FILE, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var f = arg_f;
    _ = &f;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var r: c_int = undefined;
    _ = &r;
    var s: stbi__context = undefined;
    _ = &s;
    var pos: c_long = ftell(f);
    _ = &pos;
    stbi__start_file(&s, f);
    r = stbi__info_main(&s, x, y, comp);
    _ = fseek(f, pos, @as(c_int, 0));
    return r;
}
pub fn stbi_is_16_bit(arg_filename: [*c]const u8) callconv(.c) c_int {
    var filename = arg_filename;
    _ = &filename;
    var f: ?*FILE = stbi__fopen(filename, "rb");
    _ = &f;
    var result: c_int = undefined;
    _ = &result;
    if (!(f != null)) return 0;
    result = stbi_is_16_bit_from_file(f);
    _ = fclose(f);
    return result;
}
pub fn stbi_is_16_bit_from_file(arg_f: ?*FILE) callconv(.c) c_int {
    var f = arg_f;
    _ = &f;
    var r: c_int = undefined;
    _ = &r;
    var s: stbi__context = undefined;
    _ = &s;
    var pos: c_long = ftell(f);
    _ = &pos;
    stbi__start_file(&s, f);
    r = stbi__is_16_main(&s);
    _ = fseek(f, pos, @as(c_int, 0));
    return r;
}
pub fn stbi_set_unpremultiply_on_load(arg_flag_true_if_should_unpremultiply: c_int) callconv(.c) void {
    var flag_true_if_should_unpremultiply = arg_flag_true_if_should_unpremultiply;
    _ = &flag_true_if_should_unpremultiply;
    stbi__unpremultiply_on_load_global = flag_true_if_should_unpremultiply;
}
pub fn stbi_convert_iphone_png_to_rgb(arg_flag_true_if_should_convert: c_int) callconv(.c) void {
    var flag_true_if_should_convert = arg_flag_true_if_should_convert;
    _ = &flag_true_if_should_convert;
    stbi__de_iphone_flag_global = flag_true_if_should_convert;
}
pub export fn stbi_set_flip_vertically_on_load(arg_flag_true_if_should_flip: c_int) callconv(.c) void {
    var flag_true_if_should_flip = arg_flag_true_if_should_flip;
    _ = &flag_true_if_should_flip;
    stbi__vertically_flip_on_load_global = flag_true_if_should_flip;
}
pub fn stbi_set_unpremultiply_on_load_thread(arg_flag_true_if_should_unpremultiply: c_int) callconv(.c) void {
    var flag_true_if_should_unpremultiply = arg_flag_true_if_should_unpremultiply;
    _ = &flag_true_if_should_unpremultiply;
    stbi__unpremultiply_on_load_local = flag_true_if_should_unpremultiply;
    stbi__unpremultiply_on_load_set = 1;
}
pub fn stbi_convert_iphone_png_to_rgb_thread(arg_flag_true_if_should_convert: c_int) callconv(.c) void {
    var flag_true_if_should_convert = arg_flag_true_if_should_convert;
    _ = &flag_true_if_should_convert;
    stbi__de_iphone_flag_local = flag_true_if_should_convert;
    stbi__de_iphone_flag_set = 1;
}
pub fn stbi_set_flip_vertically_on_load_thread(arg_flag_true_if_should_flip: c_int) callconv(.c) void {
    var flag_true_if_should_flip = arg_flag_true_if_should_flip;
    _ = &flag_true_if_should_flip;
    stbi__vertically_flip_on_load_local = flag_true_if_should_flip;
    stbi__vertically_flip_on_load_set = 1;
}
pub fn stbi_zlib_decode_malloc_guesssize(arg_buffer: [*c]const u8, arg_len: c_int, arg_initial_size: c_int, arg_outlen: [*c]c_int) callconv(.c) [*c]u8 {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var initial_size = arg_initial_size;
    _ = &initial_size;
    var outlen = arg_outlen;
    _ = &outlen;
    var a: stbi__zbuf = undefined;
    _ = &a;
    var p: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(stbi__malloc(@as(usize, @bitCast(@as(c_long, initial_size)))))));
    _ = &p;
    if (p == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return null;
    a.zbuffer = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(buffer))));
    a.zbuffer_end = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(buffer)))) + @as(usize, @bitCast(@as(isize, @intCast(len))));
    if (stbi__do_zlib(&a, p, initial_size, @as(c_int, 1), @as(c_int, 1)) != 0) {
        if (outlen != null) {
            outlen.* = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(a.zout) -% @intFromPtr(a.zout_start))), @sizeOf(u8))))));
        }
        return a.zout_start;
    } else {
        free(@as(?*anyopaque, @ptrCast(a.zout_start)));
        return null;
    }
    return null;
}
pub fn stbi_zlib_decode_malloc_guesssize_headerflag(arg_buffer: [*c]const u8, arg_len: c_int, arg_initial_size: c_int, arg_outlen: [*c]c_int, arg_parse_header: c_int) callconv(.c) [*c]u8 {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var initial_size = arg_initial_size;
    _ = &initial_size;
    var outlen = arg_outlen;
    _ = &outlen;
    var parse_header = arg_parse_header;
    _ = &parse_header;
    var a: stbi__zbuf = undefined;
    _ = &a;
    var p: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(stbi__malloc(@as(usize, @bitCast(@as(c_long, initial_size)))))));
    _ = &p;
    if (p == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return null;
    a.zbuffer = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(buffer))));
    a.zbuffer_end = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(buffer)))) + @as(usize, @bitCast(@as(isize, @intCast(len))));
    if (stbi__do_zlib(&a, p, initial_size, @as(c_int, 1), parse_header) != 0) {
        if (outlen != null) {
            outlen.* = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(a.zout) -% @intFromPtr(a.zout_start))), @sizeOf(u8))))));
        }
        return a.zout_start;
    } else {
        free(@as(?*anyopaque, @ptrCast(a.zout_start)));
        return null;
    }
    return null;
}
pub fn stbi_zlib_decode_malloc(arg_buffer: [*c]const u8, arg_len: c_int, arg_outlen: [*c]c_int) callconv(.c) [*c]u8 {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var outlen = arg_outlen;
    _ = &outlen;
    return stbi_zlib_decode_malloc_guesssize(buffer, len, @as(c_int, 16384), outlen);
}
pub fn stbi_zlib_decode_buffer(arg_obuffer: [*c]u8, arg_olen: c_int, arg_ibuffer: [*c]const u8, arg_ilen: c_int) callconv(.c) c_int {
    var obuffer = arg_obuffer;
    _ = &obuffer;
    var olen = arg_olen;
    _ = &olen;
    var ibuffer = arg_ibuffer;
    _ = &ibuffer;
    var ilen = arg_ilen;
    _ = &ilen;
    var a: stbi__zbuf = undefined;
    _ = &a;
    a.zbuffer = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(ibuffer))));
    a.zbuffer_end = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(ibuffer)))) + @as(usize, @bitCast(@as(isize, @intCast(ilen))));
    if (stbi__do_zlib(&a, obuffer, olen, @as(c_int, 0), @as(c_int, 1)) != 0) return @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(a.zout) -% @intFromPtr(a.zout_start))), @sizeOf(u8)))))) else return -@as(c_int, 1);
    return 0;
}
pub fn stbi_zlib_decode_noheader_malloc(arg_buffer: [*c]const u8, arg_len: c_int, arg_outlen: [*c]c_int) callconv(.c) [*c]u8 {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    var outlen = arg_outlen;
    _ = &outlen;
    var a: stbi__zbuf = undefined;
    _ = &a;
    var p: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(stbi__malloc(@as(usize, @bitCast(@as(c_long, @as(c_int, 16384))))))));
    _ = &p;
    if (p == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return null;
    a.zbuffer = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(buffer))));
    a.zbuffer_end = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(buffer)))) + @as(usize, @bitCast(@as(isize, @intCast(len))));
    if (stbi__do_zlib(&a, p, @as(c_int, 16384), @as(c_int, 1), @as(c_int, 0)) != 0) {
        if (outlen != null) {
            outlen.* = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(a.zout) -% @intFromPtr(a.zout_start))), @sizeOf(u8))))));
        }
        return a.zout_start;
    } else {
        free(@as(?*anyopaque, @ptrCast(a.zout_start)));
        return null;
    }
    return null;
}
pub fn stbi_zlib_decode_noheader_buffer(arg_obuffer: [*c]u8, arg_olen: c_int, arg_ibuffer: [*c]const u8, arg_ilen: c_int) callconv(.c) c_int {
    var obuffer = arg_obuffer;
    _ = &obuffer;
    var olen = arg_olen;
    _ = &olen;
    var ibuffer = arg_ibuffer;
    _ = &ibuffer;
    var ilen = arg_ilen;
    _ = &ilen;
    var a: stbi__zbuf = undefined;
    _ = &a;
    a.zbuffer = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(ibuffer))));
    a.zbuffer_end = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(ibuffer)))) + @as(usize, @bitCast(@as(isize, @intCast(ilen))));
    if (stbi__do_zlib(&a, obuffer, olen, @as(c_int, 0), @as(c_int, 0)) != 0) return @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(a.zout) -% @intFromPtr(a.zout_start))), @sizeOf(u8)))))) else return -@as(c_int, 1);
    return 0;
}
pub const __gnuc_va_list = __builtin_va_list;
pub const ptrdiff_t = c_long;
pub const max_align_t = extern struct {
    __clang_max_align_nonce1: c_longlong align(8) = @import("std").mem.zeroes(c_longlong),
    __clang_max_align_nonce2: c_longdouble align(16) = @import("std").mem.zeroes(c_longdouble),
};
pub const struct___locale_struct = opaque {};
pub const locale_t = ?*struct___locale_struct;
pub extern fn memcpy(?*anyopaque, ?*const anyopaque, c_ulong) ?*anyopaque;
pub extern fn memmove(?*anyopaque, ?*const anyopaque, c_ulong) ?*anyopaque;
pub extern fn memset(?*anyopaque, c_int, c_ulong) ?*anyopaque;
pub extern fn memcmp(?*const anyopaque, ?*const anyopaque, c_ulong) c_int;
pub extern fn memchr(?*const anyopaque, c_int, c_ulong) ?*anyopaque;
pub extern fn strcpy([*c]u8, [*c]const u8) [*c]u8;
pub extern fn strncpy([*c]u8, [*c]const u8, c_ulong) [*c]u8;
pub extern fn strcat([*c]u8, [*c]const u8) [*c]u8;
pub extern fn strncat([*c]u8, [*c]const u8, c_ulong) [*c]u8;
pub extern fn strcmp([*c]const u8, [*c]const u8) c_int;
pub extern fn strncmp([*c]const u8, [*c]const u8, c_ulong) c_int;
pub extern fn strcoll([*c]const u8, [*c]const u8) c_int;
pub extern fn strxfrm([*c]u8, [*c]const u8, c_ulong) c_ulong;
pub extern fn strchr([*c]const u8, c_int) [*c]u8;
pub extern fn strrchr([*c]const u8, c_int) [*c]u8;
pub extern fn strcspn([*c]const u8, [*c]const u8) c_ulong;
pub extern fn strspn([*c]const u8, [*c]const u8) c_ulong;
pub extern fn strpbrk([*c]const u8, [*c]const u8) [*c]u8;
pub extern fn strstr([*c]const u8, [*c]const u8) [*c]u8;
pub extern fn strtok([*c]u8, [*c]const u8) [*c]u8;
pub extern fn strlen([*c]const u8) c_ulong;
pub extern fn strerror(c_int) [*c]u8;
pub extern fn bcmp(?*const anyopaque, ?*const anyopaque, c_ulong) c_int;
pub extern fn bcopy(?*const anyopaque, ?*anyopaque, c_ulong) void;
pub extern fn bzero(?*anyopaque, c_ulong) void;
pub extern fn index([*c]const u8, c_int) [*c]u8;
pub extern fn rindex([*c]const u8, c_int) [*c]u8;
pub extern fn ffs(c_int) c_int;
pub extern fn ffsl(c_long) c_int;
pub extern fn ffsll(c_longlong) c_int;
pub extern fn strcasecmp([*c]const u8, [*c]const u8) c_int;
pub extern fn strncasecmp([*c]const u8, [*c]const u8, c_ulong) c_int;
pub extern fn strcasecmp_l([*c]const u8, [*c]const u8, locale_t) c_int;
pub extern fn strncasecmp_l([*c]const u8, [*c]const u8, usize, locale_t) c_int;
pub extern fn strtok_r(noalias [*c]u8, noalias [*c]const u8, noalias [*c][*c]u8) [*c]u8;
pub extern fn strerror_r(c_int, [*c]u8, usize) c_int;
pub extern fn stpcpy([*c]u8, [*c]const u8) [*c]u8;
pub extern fn stpncpy([*c]u8, [*c]const u8, c_ulong) [*c]u8;
pub extern fn strnlen([*c]const u8, usize) usize;
pub extern fn strdup([*c]const u8) [*c]u8;
pub extern fn strndup([*c]const u8, c_ulong) [*c]u8;
pub extern fn strsignal(c_int) [*c]u8;
pub extern fn strerror_l(c_int, locale_t) [*c]u8;
pub extern fn strcoll_l([*c]const u8, [*c]const u8, locale_t) c_int;
pub extern fn strxfrm_l(noalias [*c]u8, noalias [*c]const u8, usize, locale_t) usize;
pub extern fn memmem(?*const anyopaque, usize, ?*const anyopaque, usize) ?*anyopaque;
pub extern fn memccpy(?*anyopaque, ?*const anyopaque, c_int, c_ulong) ?*anyopaque;
pub extern fn strsep([*c][*c]u8, [*c]const u8) [*c]u8;
pub extern fn strlcat([*c]u8, [*c]const u8, c_ulong) c_ulong;
pub extern fn strlcpy([*c]u8, [*c]const u8, c_ulong) c_ulong;
pub extern fn explicit_bzero(?*anyopaque, usize) void;
pub const float_t = f32;
pub const double_t = f64;
pub extern fn __fpclassify(f64) c_int;
pub extern fn __fpclassifyf(f32) c_int;
pub extern fn __fpclassifyl(c_longdouble) c_int;
pub fn __FLOAT_BITS(arg___f: f32) callconv(.c) c_uint {
    var __f = arg___f;
    _ = &__f;
    const union_unnamed_3 = extern union {
        __f: f32,
        __i: c_uint,
    };
    _ = &union_unnamed_3;
    var __u: union_unnamed_3 = undefined;
    _ = &__u;
    __u.__f = __f;
    return __u.__i;
}
pub fn __DOUBLE_BITS(arg___f: f64) callconv(.c) c_ulonglong {
    var __f = arg___f;
    _ = &__f;
    const union_unnamed_4 = extern union {
        __f: f64,
        __i: c_ulonglong,
    };
    _ = &union_unnamed_4;
    var __u: union_unnamed_4 = undefined;
    _ = &__u;
    __u.__f = __f;
    return __u.__i;
}
pub extern fn __signbit(f64) c_int;
pub extern fn __signbitf(f32) c_int;
pub extern fn __signbitl(c_longdouble) c_int;
pub fn __islessf(arg___x: float_t, arg___y: float_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x < __y));
}
pub fn __isless(arg___x: double_t, arg___y: double_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x < __y));
}
pub fn __islessl(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x < __y));
}
pub fn __islessequalf(arg___x: float_t, arg___y: float_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x <= __y));
}
pub fn __islessequal(arg___x: double_t, arg___y: double_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x <= __y));
}
pub fn __islessequall(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x <= __y));
}
pub fn __islessgreaterf(arg___x: float_t, arg___y: float_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x != __y));
}
pub fn __islessgreater(arg___x: double_t, arg___y: double_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x != __y));
}
pub fn __islessgreaterl(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x != __y));
}
pub fn __isgreaterf(arg___x: float_t, arg___y: float_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x > __y));
}
pub fn __isgreater(arg___x: double_t, arg___y: double_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x > __y));
}
pub fn __isgreaterl(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x > __y));
}
pub fn __isgreaterequalf(arg___x: float_t, arg___y: float_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x >= __y));
}
pub fn __isgreaterequal(arg___x: double_t, arg___y: double_t) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x >= __y));
}
pub fn __isgreaterequall(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.c) c_int {
    var __x = arg___x;
    _ = &__x;
    var __y = arg___y;
    _ = &__y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = &__y;
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x >= __y));
}
pub extern fn acos(f64) f64;
pub extern fn acosf(f32) f32;
pub extern fn acosl(c_longdouble) c_longdouble;
pub extern fn acosh(f64) f64;
pub extern fn acoshf(f32) f32;
pub extern fn acoshl(c_longdouble) c_longdouble;
pub extern fn asin(f64) f64;
pub extern fn asinf(f32) f32;
pub extern fn asinl(c_longdouble) c_longdouble;
pub extern fn asinh(f64) f64;
pub extern fn asinhf(f32) f32;
pub extern fn asinhl(c_longdouble) c_longdouble;
pub extern fn atan(f64) f64;
pub extern fn atanf(f32) f32;
pub extern fn atanl(c_longdouble) c_longdouble;
pub extern fn atan2(f64, f64) f64;
pub extern fn atan2f(f32, f32) f32;
pub extern fn atan2l(c_longdouble, c_longdouble) c_longdouble;
pub extern fn atanh(f64) f64;
pub extern fn atanhf(f32) f32;
pub extern fn atanhl(c_longdouble) c_longdouble;
pub extern fn cbrt(f64) f64;
pub extern fn cbrtf(f32) f32;
pub extern fn cbrtl(c_longdouble) c_longdouble;
pub extern fn ceil(f64) f64;
pub extern fn ceilf(f32) f32;
pub extern fn ceill(c_longdouble) c_longdouble;
pub extern fn copysign(f64, f64) f64;
pub extern fn copysignf(f32, f32) f32;
pub extern fn copysignl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn cos(f64) f64;
pub extern fn cosf(f32) f32;
pub extern fn cosl(c_longdouble) c_longdouble;
pub extern fn cosh(f64) f64;
pub extern fn coshf(f32) f32;
pub extern fn coshl(c_longdouble) c_longdouble;
pub extern fn erf(f64) f64;
pub extern fn erff(f32) f32;
pub extern fn erfl(c_longdouble) c_longdouble;
pub extern fn erfc(f64) f64;
pub extern fn erfcf(f32) f32;
pub extern fn erfcl(c_longdouble) c_longdouble;
pub extern fn exp(f64) f64;
pub extern fn expf(f32) f32;
pub extern fn expl(c_longdouble) c_longdouble;
pub extern fn exp2(f64) f64;
pub extern fn exp2f(f32) f32;
pub extern fn exp2l(c_longdouble) c_longdouble;
pub extern fn expm1(f64) f64;
pub extern fn expm1f(f32) f32;
pub extern fn expm1l(c_longdouble) c_longdouble;
pub extern fn fabs(f64) f64;
pub extern fn fabsf(f32) f32;
pub extern fn fabsl(c_longdouble) c_longdouble;
pub extern fn fdim(f64, f64) f64;
pub extern fn fdimf(f32, f32) f32;
pub extern fn fdiml(c_longdouble, c_longdouble) c_longdouble;
pub extern fn floor(f64) f64;
pub extern fn floorf(f32) f32;
pub extern fn floorl(c_longdouble) c_longdouble;
pub extern fn fma(f64, f64, f64) f64;
pub extern fn fmaf(f32, f32, f32) f32;
pub extern fn fmal(c_longdouble, c_longdouble, c_longdouble) c_longdouble;
pub extern fn fmax(f64, f64) f64;
pub extern fn fmaxf(f32, f32) f32;
pub extern fn fmaxl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn fmin(f64, f64) f64;
pub extern fn fminf(f32, f32) f32;
pub extern fn fminl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn fmod(f64, f64) f64;
pub extern fn fmodf(f32, f32) f32;
pub extern fn fmodl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn frexp(f64, [*c]c_int) f64;
pub extern fn frexpf(f32, [*c]c_int) f32;
pub extern fn frexpl(c_longdouble, [*c]c_int) c_longdouble;
pub extern fn hypot(f64, f64) f64;
pub extern fn hypotf(f32, f32) f32;
pub extern fn hypotl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn ilogb(f64) c_int;
pub extern fn ilogbf(f32) c_int;
pub extern fn ilogbl(c_longdouble) c_int;
pub extern fn ldexp(f64, c_int) f64;
pub extern fn ldexpf(f32, c_int) f32;
pub extern fn ldexpl(c_longdouble, c_int) c_longdouble;
pub extern fn lgamma(f64) f64;
pub extern fn lgammaf(f32) f32;
pub extern fn lgammal(c_longdouble) c_longdouble;
pub extern fn llrint(f64) c_longlong;
pub extern fn llrintf(f32) c_longlong;
pub extern fn llrintl(c_longdouble) c_longlong;
pub extern fn llround(f64) c_longlong;
pub extern fn llroundf(f32) c_longlong;
pub extern fn llroundl(c_longdouble) c_longlong;
pub extern fn log(f64) f64;
pub extern fn logf(f32) f32;
pub extern fn logl(c_longdouble) c_longdouble;
pub extern fn log10(f64) f64;
pub extern fn log10f(f32) f32;
pub extern fn log10l(c_longdouble) c_longdouble;
pub extern fn log1p(f64) f64;
pub extern fn log1pf(f32) f32;
pub extern fn log1pl(c_longdouble) c_longdouble;
pub extern fn log2(f64) f64;
pub extern fn log2f(f32) f32;
pub extern fn log2l(c_longdouble) c_longdouble;
pub extern fn logb(f64) f64;
pub extern fn logbf(f32) f32;
pub extern fn logbl(c_longdouble) c_longdouble;
pub extern fn lrint(f64) c_long;
pub extern fn lrintf(f32) c_long;
pub extern fn lrintl(c_longdouble) c_long;
pub extern fn lround(f64) c_long;
pub extern fn lroundf(f32) c_long;
pub extern fn lroundl(c_longdouble) c_long;
pub extern fn modf(f64, [*c]f64) f64;
pub extern fn modff(f32, [*c]f32) f32;
pub extern fn modfl(c_longdouble, [*c]c_longdouble) c_longdouble;
pub extern fn nan([*c]const u8) f64;
pub extern fn nanf([*c]const u8) f32;
pub extern fn nanl([*c]const u8) c_longdouble;
pub extern fn nearbyint(f64) f64;
pub extern fn nearbyintf(f32) f32;
pub extern fn nearbyintl(c_longdouble) c_longdouble;
pub extern fn nextafter(f64, f64) f64;
pub extern fn nextafterf(f32, f32) f32;
pub extern fn nextafterl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn nexttoward(f64, c_longdouble) f64;
pub extern fn nexttowardf(f32, c_longdouble) f32;
pub extern fn nexttowardl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn pow(f64, f64) f64;
pub extern fn powf(f32, f32) f32;
pub extern fn powl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn remainder(f64, f64) f64;
pub extern fn remainderf(f32, f32) f32;
pub extern fn remainderl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn remquo(f64, f64, [*c]c_int) f64;
pub extern fn remquof(f32, f32, [*c]c_int) f32;
pub extern fn remquol(c_longdouble, c_longdouble, [*c]c_int) c_longdouble;
pub extern fn rint(f64) f64;
pub extern fn rintf(f32) f32;
pub extern fn rintl(c_longdouble) c_longdouble;
pub extern fn round(f64) f64;
pub extern fn roundf(f32) f32;
pub extern fn roundl(c_longdouble) c_longdouble;
pub extern fn scalbln(f64, c_long) f64;
pub extern fn scalblnf(f32, c_long) f32;
pub extern fn scalblnl(c_longdouble, c_long) c_longdouble;
pub extern fn scalbn(f64, c_int) f64;
pub extern fn scalbnf(f32, c_int) f32;
pub extern fn scalbnl(c_longdouble, c_int) c_longdouble;
pub extern fn sin(f64) f64;
pub extern fn sinf(f32) f32;
pub extern fn sinl(c_longdouble) c_longdouble;
pub extern fn sinh(f64) f64;
pub extern fn sinhf(f32) f32;
pub extern fn sinhl(c_longdouble) c_longdouble;
pub extern fn sqrt(f64) f64;
pub extern fn sqrtf(f32) f32;
pub extern fn sqrtl(c_longdouble) c_longdouble;
pub extern fn tan(f64) f64;
pub extern fn tanf(f32) f32;
pub extern fn tanl(c_longdouble) c_longdouble;
pub extern fn tanh(f64) f64;
pub extern fn tanhf(f32) f32;
pub extern fn tanhl(c_longdouble) c_longdouble;
pub extern fn tgamma(f64) f64;
pub extern fn tgammaf(f32) f32;
pub extern fn tgammal(c_longdouble) c_longdouble;
pub extern fn trunc(f64) f64;
pub extern fn truncf(f32) f32;
pub extern fn truncl(c_longdouble) c_longdouble;
pub extern var signgam: c_int;
pub extern fn j0(f64) f64;
pub extern fn j1(f64) f64;
pub extern fn jn(c_int, f64) f64;
pub extern fn y0(f64) f64;
pub extern fn y1(f64) f64;
pub extern fn yn(c_int, f64) f64;
pub extern fn drem(f64, f64) f64;
pub extern fn dremf(f32, f32) f32;
pub extern fn finite(f64) c_int;
pub extern fn finitef(f32) c_int;
pub extern fn scalb(f64, f64) f64;
pub extern fn scalbf(f32, f32) f32;
pub extern fn significand(f64) f64;
pub extern fn significandf(f32) f32;
pub extern fn lgamma_r(f64, [*c]c_int) f64;
pub extern fn lgammaf_r(f32, [*c]c_int) f32;
pub extern fn j0f(f32) f32;
pub extern fn j1f(f32) f32;
pub extern fn jnf(c_int, f32) f32;
pub extern fn y0f(f32) f32;
pub extern fn y1f(f32) f32;
pub extern fn ynf(c_int, f32) f32;
pub extern fn __assert_fail([*c]const u8, [*c]const u8, c_int, [*c]const u8) void;
pub const intmax_t = c_long;
pub const uintmax_t = c_ulong;
pub const int_fast8_t = i8;
pub const int_fast64_t = i64;
pub const int_least8_t = i8;
pub const int_least16_t = i16;
pub const int_least32_t = i32;
pub const int_least64_t = i64;
pub const uint_fast8_t = u8;
pub const uint_fast64_t = u64;
pub const uint_least8_t = u8;
pub const uint_least16_t = u16;
pub const uint_least32_t = u32;
pub const uint_least64_t = u64;
pub const int_fast16_t = i32;
pub const int_fast32_t = i32;
pub const uint_fast16_t = u32;
pub const uint_fast32_t = u32;
pub const stbi__int16 = i16;
pub const stbi__uint32 = u32;
pub const stbi__int32 = i32;
pub const validate_uint32 = [1]u8;
pub const stbi__context = extern struct {
    img_x: stbi__uint32 = @import("std").mem.zeroes(stbi__uint32),
    img_y: stbi__uint32 = @import("std").mem.zeroes(stbi__uint32),
    img_n: c_int = @import("std").mem.zeroes(c_int),
    img_out_n: c_int = @import("std").mem.zeroes(c_int),
    io: stbi_io_callbacks = @import("std").mem.zeroes(stbi_io_callbacks),
    io_user_data: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    read_from_callbacks: c_int = @import("std").mem.zeroes(c_int),
    buflen: c_int = @import("std").mem.zeroes(c_int),
    buffer_start: [128]stbi_uc = @import("std").mem.zeroes([128]stbi_uc),
    callback_already_read: c_int = @import("std").mem.zeroes(c_int),
    img_buffer: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    img_buffer_end: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    img_buffer_original: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    img_buffer_original_end: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
};
pub fn stbi__refill_buffer(arg_s: [*c]stbi__context) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var n: c_int = s.*.io.read.?(s.*.io_user_data, @as([*c]u8, @ptrCast(@alignCast(@as([*c]stbi_uc, @ptrCast(@alignCast(&s.*.buffer_start[@as(usize, @intCast(0))])))))), s.*.buflen);
    _ = &n;
    s.*.callback_already_read += @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(s.*.img_buffer) -% @intFromPtr(s.*.img_buffer_original))), @sizeOf(stbi_uc))))));
    if (n == @as(c_int, 0)) {
        s.*.read_from_callbacks = 0;
        s.*.img_buffer = @as([*c]stbi_uc, @ptrCast(@alignCast(&s.*.buffer_start[@as(usize, @intCast(0))])));
        s.*.img_buffer_end = @as([*c]stbi_uc, @ptrCast(@alignCast(&s.*.buffer_start[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
        s.*.img_buffer.* = 0;
    } else {
        s.*.img_buffer = @as([*c]stbi_uc, @ptrCast(@alignCast(&s.*.buffer_start[@as(usize, @intCast(0))])));
        s.*.img_buffer_end = @as([*c]stbi_uc, @ptrCast(@alignCast(&s.*.buffer_start[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(n))));
    }
}
pub fn stbi__start_mem(arg_s: [*c]stbi__context, arg_buffer: [*c]const stbi_uc, arg_len: c_int) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    s.*.io.read = null;
    s.*.read_from_callbacks = 0;
    s.*.callback_already_read = 0;
    s.*.img_buffer = blk: {
        const tmp = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(buffer))));
        s.*.img_buffer_original = tmp;
        break :blk tmp;
    };
    s.*.img_buffer_end = blk: {
        const tmp = @as([*c]stbi_uc, @ptrCast(@constCast(@volatileCast(buffer)))) + @as(usize, @bitCast(@as(isize, @intCast(len))));
        s.*.img_buffer_original_end = tmp;
        break :blk tmp;
    };
}
pub fn stbi__start_callbacks(arg_s: [*c]stbi__context, arg_c: [*c]stbi_io_callbacks, arg_user: ?*anyopaque) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var c = arg_c;
    _ = &c;
    var user = arg_user;
    _ = &user;
    s.*.io = c.*;
    s.*.io_user_data = user;
    s.*.buflen = @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([128]stbi_uc)))));
    s.*.read_from_callbacks = 1;
    s.*.callback_already_read = 0;
    s.*.img_buffer = blk: {
        const tmp = @as([*c]stbi_uc, @ptrCast(@alignCast(&s.*.buffer_start[@as(usize, @intCast(0))])));
        s.*.img_buffer_original = tmp;
        break :blk tmp;
    };
    stbi__refill_buffer(s);
    s.*.img_buffer_original_end = s.*.img_buffer_end;
}
pub fn stbi__stdio_read(arg_user: ?*anyopaque, arg_data: [*c]u8, arg_size: c_int) callconv(.c) c_int {
    var user = arg_user;
    _ = &user;
    var data = arg_data;
    _ = &data;
    var size = arg_size;
    _ = &size;
    return @as(c_int, @bitCast(@as(c_uint, @truncate(fread(@as(?*anyopaque, @ptrCast(data)), @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))), @as(c_ulong, @bitCast(@as(c_long, size))), @as(?*FILE, @ptrCast(user)))))));
}
pub fn stbi__stdio_skip(arg_user: ?*anyopaque, arg_n: c_int) callconv(.c) void {
    var user = arg_user;
    _ = &user;
    var n = arg_n;
    _ = &n;
    var ch: c_int = undefined;
    _ = &ch;
    _ = fseek(@as(?*FILE, @ptrCast(user)), @as(c_long, @bitCast(@as(c_long, n))), @as(c_int, 1));
    ch = fgetc(@as(?*FILE, @ptrCast(user)));
    if (ch != -@as(c_int, 1)) {
        _ = ungetc(ch, @as(?*FILE, @ptrCast(user)));
    }
}
pub fn stbi__stdio_eof(arg_user: ?*anyopaque) callconv(.c) c_int {
    var user = arg_user;
    _ = &user;
    return @intFromBool((feof(@as(?*FILE, @ptrCast(user))) != 0) or (ferror(@as(?*FILE, @ptrCast(user))) != 0));
}
pub var stbi__stdio_callbacks: stbi_io_callbacks = stbi_io_callbacks{
    .read = &stbi__stdio_read,
    .skip = &stbi__stdio_skip,
    .eof = &stbi__stdio_eof,
};
pub fn stbi__start_file(arg_s: [*c]stbi__context, arg_f: ?*FILE) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var f = arg_f;
    _ = &f;
    stbi__start_callbacks(s, &stbi__stdio_callbacks, @as(?*anyopaque, @ptrCast(f)));
}
pub fn stbi__rewind(arg_s: [*c]stbi__context) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    s.*.img_buffer = s.*.img_buffer_original;
    s.*.img_buffer_end = s.*.img_buffer_original_end;
}
pub const STBI_ORDER_RGB: c_int = 0;
pub const STBI_ORDER_BGR: c_int = 1;
const enum_unnamed_5 = c_uint;
pub const stbi__result_info = extern struct {
    bits_per_channel: c_int = @import("std").mem.zeroes(c_int),
    num_channels: c_int = @import("std").mem.zeroes(c_int),
    channel_order: c_int = @import("std").mem.zeroes(c_int),
};
pub fn stbi__jpeg_test(arg_s: [*c]stbi__context) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var r: c_int = undefined;
    _ = &r;
    var j: [*c]stbi__jpeg = @as([*c]stbi__jpeg, @ptrCast(@alignCast(stbi__malloc(@sizeOf(stbi__jpeg)))));
    _ = &j;
    if (!(j != null)) return 0;
    _ = memset(@as(?*anyopaque, @ptrCast(j)), @as(c_int, 0), @sizeOf(stbi__jpeg));
    j.*.s = s;
    stbi__setup_jpeg(j);
    r = stbi__decode_jpeg_header(j, STBI__SCAN_type);
    stbi__rewind(s);
    free(@as(?*anyopaque, @ptrCast(j)));
    return r;
}
pub fn stbi__jpeg_load(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int, arg_ri: [*c]stbi__result_info) callconv(.c) ?*anyopaque {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var ri = arg_ri;
    _ = &ri;
    var result: [*c]u8 = undefined;
    _ = &result;
    var j: [*c]stbi__jpeg = @as([*c]stbi__jpeg, @ptrCast(@alignCast(stbi__malloc(@sizeOf(stbi__jpeg)))));
    _ = &j;
    if (!(j != null)) return @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))))));
    _ = memset(@as(?*anyopaque, @ptrCast(j)), @as(c_int, 0), @sizeOf(stbi__jpeg));
    _ = @sizeOf([*c]stbi__result_info);
    j.*.s = s;
    stbi__setup_jpeg(j);
    result = load_jpeg_image(j, x, y, comp, req_comp);
    free(@as(?*anyopaque, @ptrCast(j)));
    return @as(?*anyopaque, @ptrCast(result));
}
pub fn stbi__jpeg_info(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var result: c_int = undefined;
    _ = &result;
    var j: [*c]stbi__jpeg = @as([*c]stbi__jpeg, @ptrCast(@alignCast(stbi__malloc(@sizeOf(stbi__jpeg)))));
    _ = &j;
    if (!(j != null)) return 0;
    _ = memset(@as(?*anyopaque, @ptrCast(j)), @as(c_int, 0), @sizeOf(stbi__jpeg));
    j.*.s = s;
    result = stbi__jpeg_info_raw(j, x, y, comp);
    free(@as(?*anyopaque, @ptrCast(j)));
    return result;
}
pub fn stbi__png_test(arg_s: [*c]stbi__context) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var r: c_int = undefined;
    _ = &r;
    r = stbi__check_png_header(s);
    stbi__rewind(s);
    return r;
}
pub fn stbi__png_load(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int, arg_ri: [*c]stbi__result_info) callconv(.c) ?*anyopaque {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var ri = arg_ri;
    _ = &ri;
    var p: stbi__png = undefined;
    _ = &p;
    p.s = s;
    return stbi__do_png(&p, x, y, comp, req_comp, ri);
}
pub fn stbi__png_info(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var p: stbi__png = undefined;
    _ = &p;
    p.s = s;
    return stbi__png_info_raw(&p, x, y, comp);
}
pub fn stbi__png_is16(arg_s: [*c]stbi__context) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var p: stbi__png = undefined;
    _ = &p;
    p.s = s;
    if (!(stbi__png_info_raw(&p, null, null, null) != 0)) return 0;
    if (p.depth != @as(c_int, 16)) {
        stbi__rewind(p.s);
        return 0;
    }
    return 1;
}
pub threadlocal var stbi__g_failure_reason: [*c]const u8 = @import("std").mem.zeroes([*c]const u8);
pub fn stbi__malloc(arg_size: usize) callconv(.c) ?*anyopaque {
    var size = arg_size;
    _ = &size;
    return malloc(size);
}
pub fn stbi__addsizes_valid(arg_a: c_int, arg_b: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    if (b < @as(c_int, 0)) return 0;
    return @intFromBool(a <= (@as(c_int, 2147483647) - b));
}
pub fn stbi__mul2sizes_valid(arg_a: c_int, arg_b: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    if ((a < @as(c_int, 0)) or (b < @as(c_int, 0))) return 0;
    if (b == @as(c_int, 0)) return 1;
    return @intFromBool(a <= @divTrunc(@as(c_int, 2147483647), b));
}
pub fn stbi__mad2sizes_valid(arg_a: c_int, arg_b: c_int, arg_add: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var add = arg_add;
    _ = &add;
    return @intFromBool((stbi__mul2sizes_valid(a, b) != 0) and (stbi__addsizes_valid(a * b, add) != 0));
}
pub fn stbi__mad3sizes_valid(arg_a: c_int, arg_b: c_int, arg_c: c_int, arg_add: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var c = arg_c;
    _ = &c;
    var add = arg_add;
    _ = &add;
    return @intFromBool(((stbi__mul2sizes_valid(a, b) != 0) and (stbi__mul2sizes_valid(a * b, c) != 0)) and (stbi__addsizes_valid((a * b) * c, add) != 0));
}
pub fn stbi__mad4sizes_valid(arg_a: c_int, arg_b: c_int, arg_c: c_int, arg_d: c_int, arg_add: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var c = arg_c;
    _ = &c;
    var d = arg_d;
    _ = &d;
    var add = arg_add;
    _ = &add;
    return @intFromBool((((stbi__mul2sizes_valid(a, b) != 0) and (stbi__mul2sizes_valid(a * b, c) != 0)) and (stbi__mul2sizes_valid((a * b) * c, d) != 0)) and (stbi__addsizes_valid(((a * b) * c) * d, add) != 0));
}
pub fn stbi__malloc_mad2(arg_a: c_int, arg_b: c_int, arg_add: c_int) callconv(.c) ?*anyopaque {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var add = arg_add;
    _ = &add;
    if (!(stbi__mad2sizes_valid(a, b, add) != 0)) return @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));
    return stbi__malloc(@as(usize, @bitCast(@as(c_long, (a * b) + add))));
}
pub fn stbi__malloc_mad3(arg_a: c_int, arg_b: c_int, arg_c: c_int, arg_add: c_int) callconv(.c) ?*anyopaque {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var c = arg_c;
    _ = &c;
    var add = arg_add;
    _ = &add;
    if (!(stbi__mad3sizes_valid(a, b, c, add) != 0)) return @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));
    return stbi__malloc(@as(usize, @bitCast(@as(c_long, ((a * b) * c) + add))));
}
pub fn stbi__malloc_mad4(arg_a: c_int, arg_b: c_int, arg_c: c_int, arg_d: c_int, arg_add: c_int) callconv(.c) ?*anyopaque {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var c = arg_c;
    _ = &c;
    var d = arg_d;
    _ = &d;
    var add = arg_add;
    _ = &add;
    if (!(stbi__mad4sizes_valid(a, b, c, d, add) != 0)) return @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));
    return stbi__malloc(@as(usize, @bitCast(@as(c_long, (((a * b) * c) * d) + add))));
}
pub fn stbi__addints_valid(arg_a: c_int, arg_b: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    if (@intFromBool(a >= @as(c_int, 0)) != @intFromBool(b >= @as(c_int, 0))) return 1;
    if ((a < @as(c_int, 0)) and (b < @as(c_int, 0))) return @intFromBool(a >= ((-@as(c_int, 2147483647) - @as(c_int, 1)) - b));
    return @intFromBool(a <= (@as(c_int, 2147483647) - b));
}
pub fn stbi__mul2shorts_valid(arg_a: c_int, arg_b: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    if ((b == @as(c_int, 0)) or (b == -@as(c_int, 1))) return 1;
    if (@intFromBool(a >= @as(c_int, 0)) == @intFromBool(b >= @as(c_int, 0))) return @intFromBool(a <= @divTrunc(@as(c_int, 32767), b));
    if (b < @as(c_int, 0)) return @intFromBool(a <= @divTrunc(-@as(c_int, 32767) - @as(c_int, 1), b));
    return @intFromBool(a >= @divTrunc(-@as(c_int, 32767) - @as(c_int, 1), b));
}
pub fn stbi__ldr_to_hdr(arg_data: [*c]stbi_uc, arg_x: c_int, arg_y: c_int, arg_comp: c_int) callconv(.c) [*c]f32 {
    var data = arg_data;
    _ = &data;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var i: c_int = undefined;
    _ = &i;
    var k: c_int = undefined;
    _ = &k;
    var n: c_int = undefined;
    _ = &n;
    var output: [*c]f32 = undefined;
    _ = &output;
    if (!(data != null)) return null;
    output = @as([*c]f32, @ptrCast(@alignCast(stbi__malloc_mad4(x, y, comp, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(f32))))), @as(c_int, 0)))));
    if (output == @as([*c]f32, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        free(@as(?*anyopaque, @ptrCast(data)));
        return @as([*c]f32, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
    }
    if ((comp & @as(c_int, 1)) != 0) {
        n = comp;
    } else {
        n = comp - @as(c_int, 1);
    }
    {
        i = 0;
        while (i < (x * y)) : (i += 1) {
            {
                k = 0;
                while (k < n) : (k += 1) {
                    (blk: {
                        const tmp = (i * comp) + k;
                        if (tmp >= 0) break :blk output + @as(usize, @intCast(tmp)) else break :blk output - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).* = @as(f32, @floatCast(pow(@as(f64, @floatCast(@as(f32, @floatFromInt(@as(c_int, @bitCast(@as(c_uint, (blk: {
                        const tmp = (i * comp) + k;
                        if (tmp >= 0) break :blk data + @as(usize, @intCast(tmp)) else break :blk data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).*))))) / 255.0)), @as(f64, @floatCast(stbi__l2h_gamma))) * @as(f64, @floatCast(stbi__l2h_scale))));
                }
            }
        }
    }
    if (n < comp) {
        {
            i = 0;
            while (i < (x * y)) : (i += 1) {
                (blk: {
                    const tmp = (i * comp) + n;
                    if (tmp >= 0) break :blk output + @as(usize, @intCast(tmp)) else break :blk output - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = @as(f32, @floatFromInt(@as(c_int, @bitCast(@as(c_uint, (blk: {
                    const tmp = (i * comp) + n;
                    if (tmp >= 0) break :blk data + @as(usize, @intCast(tmp)) else break :blk data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*))))) / 255.0;
            }
        }
    }
    free(@as(?*anyopaque, @ptrCast(data)));
    return output;
}
pub var stbi__vertically_flip_on_load_global: c_int = 0;
pub threadlocal var stbi__vertically_flip_on_load_local: c_int = @import("std").mem.zeroes(c_int);
pub threadlocal var stbi__vertically_flip_on_load_set: c_int = @import("std").mem.zeroes(c_int);
pub fn stbi__load_main(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int, arg_ri: [*c]stbi__result_info, arg_bpc: c_int) callconv(.c) ?*anyopaque {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var ri = arg_ri;
    _ = &ri;
    var bpc = arg_bpc;
    _ = &bpc;
    _ = memset(@as(?*anyopaque, @ptrCast(ri)), @as(c_int, 0), @sizeOf(stbi__result_info));
    ri.*.bits_per_channel = 8;
    ri.*.channel_order = STBI_ORDER_RGB;
    ri.*.num_channels = 0;
    if (stbi__png_test(s) != 0) return stbi__png_load(s, x, y, comp, req_comp, ri);
    _ = @sizeOf(c_int);
    if (stbi__jpeg_test(s) != 0) return stbi__jpeg_load(s, x, y, comp, req_comp, ri);
    return @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))))));
}
pub fn stbi__convert_16_to_8(arg_orig: [*c]stbi__uint16, arg_w: c_int, arg_h: c_int, arg_channels: c_int) callconv(.c) [*c]stbi_uc {
    var orig = arg_orig;
    _ = &orig;
    var w = arg_w;
    _ = &w;
    var h = arg_h;
    _ = &h;
    var channels = arg_channels;
    _ = &channels;
    var i: c_int = undefined;
    _ = &i;
    var img_len: c_int = (w * h) * channels;
    _ = &img_len;
    var reduced: [*c]stbi_uc = undefined;
    _ = &reduced;
    reduced = @as([*c]stbi_uc, @ptrCast(@alignCast(stbi__malloc(@as(usize, @bitCast(@as(c_long, img_len)))))));
    if (reduced == @as([*c]stbi_uc, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return @as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
    {
        i = 0;
        while (i < img_len) : (i += 1) {
            (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk reduced + @as(usize, @intCast(tmp)) else break :blk reduced - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk orig + @as(usize, @intCast(tmp)) else break :blk orig - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))) >> @intCast(8)) & @as(c_int, 255)))));
        }
    }
    free(@as(?*anyopaque, @ptrCast(orig)));
    return reduced;
}
pub fn stbi__convert_8_to_16(arg_orig: [*c]stbi_uc, arg_w: c_int, arg_h: c_int, arg_channels: c_int) callconv(.c) [*c]stbi__uint16 {
    var orig = arg_orig;
    _ = &orig;
    var w = arg_w;
    _ = &w;
    var h = arg_h;
    _ = &h;
    var channels = arg_channels;
    _ = &channels;
    var i: c_int = undefined;
    _ = &i;
    var img_len: c_int = (w * h) * channels;
    _ = &img_len;
    var enlarged: [*c]stbi__uint16 = undefined;
    _ = &enlarged;
    enlarged = @as([*c]stbi__uint16, @ptrCast(@alignCast(stbi__malloc(@as(usize, @bitCast(@as(c_long, img_len * @as(c_int, 2))))))));
    if (enlarged == @as([*c]stbi__uint16, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return @as([*c]stbi__uint16, @ptrCast(@alignCast(@as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))))));
    {
        i = 0;
        while (i < img_len) : (i += 1) {
            (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk enlarged + @as(usize, @intCast(tmp)) else break :blk enlarged - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(stbi__uint16, @bitCast(@as(c_short, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk orig + @as(usize, @intCast(tmp)) else break :blk orig - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))) << @intCast(8)) + @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk orig + @as(usize, @intCast(tmp)) else break :blk orig - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))))));
        }
    }
    free(@as(?*anyopaque, @ptrCast(orig)));
    return enlarged;
}
pub fn stbi__vertical_flip(arg_image: ?*anyopaque, arg_w: c_int, arg_h: c_int, arg_bytes_per_pixel: c_int) callconv(.c) void {
    var image = arg_image;
    _ = &image;
    var w = arg_w;
    _ = &w;
    var h = arg_h;
    _ = &h;
    var bytes_per_pixel = arg_bytes_per_pixel;
    _ = &bytes_per_pixel;
    var row: c_int = undefined;
    _ = &row;
    var bytes_per_row: usize = @as(usize, @bitCast(@as(c_long, w))) *% @as(usize, @bitCast(@as(c_long, bytes_per_pixel)));
    _ = &bytes_per_row;
    var temp: [2048]stbi_uc = undefined;
    _ = &temp;
    var bytes: [*c]stbi_uc = @as([*c]stbi_uc, @ptrCast(@alignCast(image)));
    _ = &bytes;
    {
        row = 0;
        while (row < (h >> @intCast(1))) : (row += 1) {
            var row0: [*c]stbi_uc = bytes + (@as(usize, @bitCast(@as(c_long, row))) *% bytes_per_row);
            _ = &row0;
            var row1: [*c]stbi_uc = bytes + (@as(usize, @bitCast(@as(c_long, (h - row) - @as(c_int, 1)))) *% bytes_per_row);
            _ = &row1;
            var bytes_left: usize = bytes_per_row;
            _ = &bytes_left;
            while (bytes_left != 0) {
                var bytes_copy: usize = if (bytes_left < @sizeOf([2048]stbi_uc)) bytes_left else @sizeOf([2048]stbi_uc);
                _ = &bytes_copy;
                _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]stbi_uc, @ptrCast(@alignCast(&temp[@as(usize, @intCast(0))]))))), @as(?*const anyopaque, @ptrCast(row0)), bytes_copy);
                _ = memcpy(@as(?*anyopaque, @ptrCast(row0)), @as(?*const anyopaque, @ptrCast(row1)), bytes_copy);
                _ = memcpy(@as(?*anyopaque, @ptrCast(row1)), @as(?*const anyopaque, @ptrCast(@as([*c]stbi_uc, @ptrCast(@alignCast(&temp[@as(usize, @intCast(0))]))))), bytes_copy);
                row0 += bytes_copy;
                row1 += bytes_copy;
                bytes_left -%= bytes_copy;
            }
        }
    }
}
pub fn stbi__load_and_postprocess_8bit(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]u8 {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var ri: stbi__result_info = undefined;
    _ = &ri;
    var result: ?*anyopaque = stbi__load_main(s, x, y, comp, req_comp, &ri, @as(c_int, 8));
    _ = &result;
    if (result == @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))) return null;
    _ = ((ri.bits_per_channel == @as(c_int, 8)) or (ri.bits_per_channel == @as(c_int, 16))) or ((blk: {
        __assert_fail("ri.bits_per_channel == 8 || ri.bits_per_channel == 16", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 1269), "stbi__load_and_postprocess_8bit");
        break :blk @as(c_int, 0);
    }) != 0);
    if (ri.bits_per_channel != @as(c_int, 8)) {
        result = @as(?*anyopaque, @ptrCast(stbi__convert_16_to_8(@as([*c]stbi__uint16, @ptrCast(@alignCast(result))), x.*, y.*, if (req_comp == @as(c_int, 0)) comp.* else req_comp)));
        ri.bits_per_channel = 8;
    }
    if ((if (stbi__vertically_flip_on_load_set != 0) stbi__vertically_flip_on_load_local else stbi__vertically_flip_on_load_global) != 0) {
        var channels: c_int = if (req_comp != 0) req_comp else comp.*;
        _ = &channels;
        stbi__vertical_flip(result, x.*, y.*, @as(c_int, @bitCast(@as(c_uint, @truncate(@as(c_ulong, @bitCast(@as(c_long, channels))) *% @sizeOf(stbi_uc))))));
    }
    return @as([*c]u8, @ptrCast(@alignCast(result)));
}
pub fn stbi__load_and_postprocess_16bit(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]stbi__uint16 {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var ri: stbi__result_info = undefined;
    _ = &ri;
    var result: ?*anyopaque = stbi__load_main(s, x, y, comp, req_comp, &ri, @as(c_int, 16));
    _ = &result;
    if (result == @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))) return null;
    _ = ((ri.bits_per_channel == @as(c_int, 8)) or (ri.bits_per_channel == @as(c_int, 16))) or ((blk: {
        __assert_fail("ri.bits_per_channel == 8 || ri.bits_per_channel == 16", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 1295), "stbi__load_and_postprocess_16bit");
        break :blk @as(c_int, 0);
    }) != 0);
    if (ri.bits_per_channel != @as(c_int, 16)) {
        result = @as(?*anyopaque, @ptrCast(stbi__convert_8_to_16(@as([*c]stbi_uc, @ptrCast(@alignCast(result))), x.*, y.*, if (req_comp == @as(c_int, 0)) comp.* else req_comp)));
        ri.bits_per_channel = 16;
    }
    if ((if (stbi__vertically_flip_on_load_set != 0) stbi__vertically_flip_on_load_local else stbi__vertically_flip_on_load_global) != 0) {
        var channels: c_int = if (req_comp != 0) req_comp else comp.*;
        _ = &channels;
        stbi__vertical_flip(result, x.*, y.*, @as(c_int, @bitCast(@as(c_uint, @truncate(@as(c_ulong, @bitCast(@as(c_long, channels))) *% @sizeOf(stbi__uint16))))));
    }
    return @as([*c]stbi__uint16, @ptrCast(@alignCast(result)));
}
pub fn stbi__fopen(arg_filename: [*c]const u8, arg_mode: [*c]const u8) callconv(.c) ?*FILE {
    var filename = arg_filename;
    _ = &filename;
    var mode = arg_mode;
    _ = &mode;
    var f: ?*FILE = undefined;
    _ = &f;
    f = fopen(filename, mode);
    return f;
}
pub fn stbi__loadf_main(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]f32 {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var data: [*c]u8 = undefined;
    _ = &data;
    data = stbi__load_and_postprocess_8bit(s, x, y, comp, req_comp);
    if (data != null) return stbi__ldr_to_hdr(data, x.*, y.*, if (req_comp != 0) req_comp else comp.*);
    return @as([*c]f32, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
}
pub var stbi__l2h_gamma: f32 = 2.200000047683716;
pub var stbi__l2h_scale: f32 = 1.0;
pub var stbi__h2l_gamma_i: f32 = 1.0 / 2.200000047683716;
pub var stbi__h2l_scale_i: f32 = 1.0;
pub const STBI__SCAN_load: c_int = 0;
pub const STBI__SCAN_type: c_int = 1;
pub const STBI__SCAN_header: c_int = 2;
const enum_unnamed_6 = c_uint;
pub fn stbi__get8(arg_s: [*c]stbi__context) callconv(.c) stbi_uc {
    var s = arg_s;
    _ = &s;
    if (s.*.img_buffer < s.*.img_buffer_end) return (blk: {
        const ref = &s.*.img_buffer;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).*;
    if (s.*.read_from_callbacks != 0) {
        stbi__refill_buffer(s);
        return (blk: {
            const ref = &s.*.img_buffer;
            const tmp = ref.*;
            ref.* += 1;
            break :blk tmp;
        }).*;
    }
    return 0;
}
pub fn stbi__at_eof(arg_s: [*c]stbi__context) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    if (s.*.io.read != null) {
        if (!(s.*.io.eof.?(s.*.io_user_data) != 0)) return 0;
        if (s.*.read_from_callbacks == @as(c_int, 0)) return 1;
    }
    return @intFromBool(s.*.img_buffer >= s.*.img_buffer_end);
}
pub fn stbi__skip(arg_s: [*c]stbi__context, arg_n: c_int) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var n = arg_n;
    _ = &n;
    if (n == @as(c_int, 0)) return;
    if (n < @as(c_int, 0)) {
        s.*.img_buffer = s.*.img_buffer_end;
        return;
    }
    if (s.*.io.read != null) {
        var blen: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(s.*.img_buffer_end) -% @intFromPtr(s.*.img_buffer))), @sizeOf(stbi_uc))))));
        _ = &blen;
        if (blen < n) {
            s.*.img_buffer = s.*.img_buffer_end;
            s.*.io.skip.?(s.*.io_user_data, n - blen);
            return;
        }
    }
    s.*.img_buffer += @as(usize, @bitCast(@as(isize, @intCast(n))));
}
pub fn stbi__getn(arg_s: [*c]stbi__context, arg_buffer: [*c]stbi_uc, arg_n: c_int) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var buffer = arg_buffer;
    _ = &buffer;
    var n = arg_n;
    _ = &n;
    if (s.*.io.read != null) {
        var blen: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(s.*.img_buffer_end) -% @intFromPtr(s.*.img_buffer))), @sizeOf(stbi_uc))))));
        _ = &blen;
        if (blen < n) {
            var res: c_int = undefined;
            _ = &res;
            var count: c_int = undefined;
            _ = &count;
            _ = memcpy(@as(?*anyopaque, @ptrCast(buffer)), @as(?*const anyopaque, @ptrCast(s.*.img_buffer)), @as(c_ulong, @bitCast(@as(c_long, blen))));
            count = s.*.io.read.?(s.*.io_user_data, @as([*c]u8, @ptrCast(@alignCast(buffer))) + @as(usize, @bitCast(@as(isize, @intCast(blen)))), n - blen);
            res = @intFromBool(count == (n - blen));
            s.*.img_buffer = s.*.img_buffer_end;
            return res;
        }
    }
    if ((s.*.img_buffer + @as(usize, @bitCast(@as(isize, @intCast(n))))) <= s.*.img_buffer_end) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(buffer)), @as(?*const anyopaque, @ptrCast(s.*.img_buffer)), @as(c_ulong, @bitCast(@as(c_long, n))));
        s.*.img_buffer += @as(usize, @bitCast(@as(isize, @intCast(n))));
        return 1;
    } else return 0;
    return 0;
}
pub fn stbi__get16be(arg_s: [*c]stbi__context) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var z: c_int = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
    _ = &z;
    return (z << @intCast(8)) + @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
}
pub fn stbi__get32be(arg_s: [*c]stbi__context) callconv(.c) stbi__uint32 {
    var s = arg_s;
    _ = &s;
    var z: stbi__uint32 = @as(stbi__uint32, @bitCast(stbi__get16be(s)));
    _ = &z;
    return (z << @intCast(16)) +% @as(stbi__uint32, @bitCast(stbi__get16be(s)));
}
pub fn stbi__compute_y(arg_r: c_int, arg_g: c_int, arg_b: c_int) callconv(.c) stbi_uc {
    var r = arg_r;
    _ = &r;
    var g = arg_g;
    _ = &g;
    var b = arg_b;
    _ = &b;
    return @as(stbi_uc, @bitCast(@as(i8, @truncate((((r * @as(c_int, 77)) + (g * @as(c_int, 150))) + (@as(c_int, 29) * b)) >> @intCast(8)))));
}
pub fn stbi__convert_format(arg_data: [*c]u8, arg_img_n: c_int, arg_req_comp: c_int, arg_x: c_uint, arg_y: c_uint) callconv(.c) [*c]u8 {
    var data = arg_data;
    _ = &data;
    var img_n = arg_img_n;
    _ = &img_n;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var i: c_int = undefined;
    _ = &i;
    var j: c_int = undefined;
    _ = &j;
    var good: [*c]u8 = undefined;
    _ = &good;
    if (req_comp == img_n) return data;
    _ = ((req_comp >= @as(c_int, 1)) and (req_comp <= @as(c_int, 4))) or ((blk: {
        __assert_fail("req_comp >= 1 && req_comp <= 4", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 1761), "stbi__convert_format");
        break :blk @as(c_int, 0);
    }) != 0);
    good = @as([*c]u8, @ptrCast(@alignCast(stbi__malloc_mad3(req_comp, @as(c_int, @bitCast(x)), @as(c_int, @bitCast(y)), @as(c_int, 0)))));
    if (good == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        free(@as(?*anyopaque, @ptrCast(data)));
        return @as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
    }
    {
        j = 0;
        while (j < @as(c_int, @bitCast(y))) : (j += 1) {
            var src: [*c]u8 = data + ((@as(c_uint, @bitCast(j)) *% x) *% @as(c_uint, @bitCast(img_n)));
            _ = &src;
            var dest: [*c]u8 = good + ((@as(c_uint, @bitCast(j)) *% x) *% @as(c_uint, @bitCast(req_comp)));
            _ = &dest;
            while (true) {
                switch ((img_n * @as(c_int, 8)) + req_comp) {
                    @as(c_int, 10) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = 255;
                            }
                        }
                        break;
                    },
                    @as(c_int, 11) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                    const tmp = blk_1: {
                                        const tmp_2 = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                        dest[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                        break :blk_1 tmp_2;
                                    };
                                    dest[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                    break :blk tmp;
                                };
                            }
                        }
                        break;
                    },
                    @as(c_int, 12) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                    const tmp = blk_1: {
                                        const tmp_2 = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                        dest[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                        break :blk_1 tmp_2;
                                    };
                                    dest[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                    break :blk tmp;
                                };
                                dest[@as(c_uint, @intCast(@as(c_int, 3)))] = 255;
                            }
                        }
                        break;
                    },
                    @as(c_int, 17) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                            }
                        }
                        break;
                    },
                    @as(c_int, 19) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                    const tmp = blk_1: {
                                        const tmp_2 = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                        dest[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                        break :blk_1 tmp_2;
                                    };
                                    dest[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                    break :blk tmp;
                                };
                            }
                        }
                        break;
                    },
                    @as(c_int, 20) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                    const tmp = blk_1: {
                                        const tmp_2 = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                        dest[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                        break :blk_1 tmp_2;
                                    };
                                    dest[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                    break :blk tmp;
                                };
                                dest[@as(c_uint, @intCast(@as(c_int, 3)))] = src[@as(c_uint, @intCast(@as(c_int, 1)))];
                            }
                        }
                        break;
                    },
                    @as(c_int, 28) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = src[@as(c_uint, @intCast(@as(c_int, 1)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 2)))] = src[@as(c_uint, @intCast(@as(c_int, 2)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 3)))] = 255;
                            }
                        }
                        break;
                    },
                    @as(c_int, 25) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y(@as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 0)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 1)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 2)))]))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 26) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y(@as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 0)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 1)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 2)))]))));
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = 255;
                            }
                        }
                        break;
                    },
                    @as(c_int, 33) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y(@as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 0)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 1)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 2)))]))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 34) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y(@as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 0)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 1)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 2)))]))));
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = src[@as(c_uint, @intCast(@as(c_int, 3)))];
                            }
                        }
                        break;
                    },
                    @as(c_int, 35) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = src[@as(c_uint, @intCast(@as(c_int, 1)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 2)))] = src[@as(c_uint, @intCast(@as(c_int, 2)))];
                            }
                        }
                        break;
                    },
                    else => {
                        _ = (@as(c_int, 0) != 0) or ((blk: {
                            __assert_fail("0", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 1790), "stbi__convert_format");
                            break :blk @as(c_int, 0);
                        }) != 0);
                        free(@as(?*anyopaque, @ptrCast(data)));
                        free(@as(?*anyopaque, @ptrCast(good)));
                        return @as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
                    },
                }
                break;
            }
        }
    }
    free(@as(?*anyopaque, @ptrCast(data)));
    return good;
}
pub fn stbi__compute_y_16(arg_r: c_int, arg_g: c_int, arg_b: c_int) callconv(.c) stbi__uint16 {
    var r = arg_r;
    _ = &r;
    var g = arg_g;
    _ = &g;
    var b = arg_b;
    _ = &b;
    return @as(stbi__uint16, @bitCast(@as(c_short, @truncate((((r * @as(c_int, 77)) + (g * @as(c_int, 150))) + (@as(c_int, 29) * b)) >> @intCast(8)))));
}
pub fn stbi__convert_format16(arg_data: [*c]stbi__uint16, arg_img_n: c_int, arg_req_comp: c_int, arg_x: c_uint, arg_y: c_uint) callconv(.c) [*c]stbi__uint16 {
    var data = arg_data;
    _ = &data;
    var img_n = arg_img_n;
    _ = &img_n;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var i: c_int = undefined;
    _ = &i;
    var j: c_int = undefined;
    _ = &j;
    var good: [*c]stbi__uint16 = undefined;
    _ = &good;
    if (req_comp == img_n) return data;
    _ = ((req_comp >= @as(c_int, 1)) and (req_comp <= @as(c_int, 4))) or ((blk: {
        __assert_fail("req_comp >= 1 && req_comp <= 4", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 1818), "stbi__convert_format16");
        break :blk @as(c_int, 0);
    }) != 0);
    good = @as([*c]stbi__uint16, @ptrCast(@alignCast(stbi__malloc(@as(usize, @bitCast(@as(c_ulong, ((@as(c_uint, @bitCast(req_comp)) *% x) *% y) *% @as(c_uint, @bitCast(@as(c_int, 2))))))))));
    if (good == @as([*c]stbi__uint16, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        free(@as(?*anyopaque, @ptrCast(data)));
        return @as([*c]stbi__uint16, @ptrCast(@alignCast(@as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))))));
    }
    {
        j = 0;
        while (j < @as(c_int, @bitCast(y))) : (j += 1) {
            var src: [*c]stbi__uint16 = data + ((@as(c_uint, @bitCast(j)) *% x) *% @as(c_uint, @bitCast(img_n)));
            _ = &src;
            var dest: [*c]stbi__uint16 = good + ((@as(c_uint, @bitCast(j)) *% x) *% @as(c_uint, @bitCast(req_comp)));
            _ = &dest;
            while (true) {
                switch ((img_n * @as(c_int, 8)) + req_comp) {
                    @as(c_int, 10) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(@as(c_int, 65535)))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 11) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                    const tmp = blk_1: {
                                        const tmp_2 = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                        dest[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                        break :blk_1 tmp_2;
                                    };
                                    dest[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                    break :blk tmp;
                                };
                            }
                        }
                        break;
                    },
                    @as(c_int, 12) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                    const tmp = blk_1: {
                                        const tmp_2 = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                        dest[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                        break :blk_1 tmp_2;
                                    };
                                    dest[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                    break :blk tmp;
                                };
                                dest[@as(c_uint, @intCast(@as(c_int, 3)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(@as(c_int, 65535)))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 17) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                            }
                        }
                        break;
                    },
                    @as(c_int, 19) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                    const tmp = blk_1: {
                                        const tmp_2 = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                        dest[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                        break :blk_1 tmp_2;
                                    };
                                    dest[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                    break :blk tmp;
                                };
                            }
                        }
                        break;
                    },
                    @as(c_int, 20) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                    const tmp = blk_1: {
                                        const tmp_2 = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                        dest[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                        break :blk_1 tmp_2;
                                    };
                                    dest[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                    break :blk tmp;
                                };
                                dest[@as(c_uint, @intCast(@as(c_int, 3)))] = src[@as(c_uint, @intCast(@as(c_int, 1)))];
                            }
                        }
                        break;
                    },
                    @as(c_int, 28) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = src[@as(c_uint, @intCast(@as(c_int, 1)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 2)))] = src[@as(c_uint, @intCast(@as(c_int, 2)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 3)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(@as(c_int, 65535)))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 25) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y_16(@as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 0)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 1)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 2)))]))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 26) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y_16(@as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 0)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 1)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 2)))]))));
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(@as(c_int, 65535)))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 33) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y_16(@as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 0)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 1)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 2)))]))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 34) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y_16(@as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 0)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 1)))]))), @as(c_int, @bitCast(@as(c_uint, src[@as(c_uint, @intCast(@as(c_int, 2)))]))));
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = src[@as(c_uint, @intCast(@as(c_int, 3)))];
                            }
                        }
                        break;
                    },
                    @as(c_int, 35) => {
                        {
                            i = @as(c_int, @bitCast(x -% @as(c_uint, @bitCast(@as(c_int, 1)))));
                            while (i >= @as(c_int, 0)) : (_ = blk: {
                                _ = blk_1: {
                                    i -= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &src;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &dest;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest[@as(c_uint, @intCast(@as(c_int, 0)))] = src[@as(c_uint, @intCast(@as(c_int, 0)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 1)))] = src[@as(c_uint, @intCast(@as(c_int, 1)))];
                                dest[@as(c_uint, @intCast(@as(c_int, 2)))] = src[@as(c_uint, @intCast(@as(c_int, 2)))];
                            }
                        }
                        break;
                    },
                    else => {
                        _ = (@as(c_int, 0) != 0) or ((blk: {
                            __assert_fail("0", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 1847), "stbi__convert_format16");
                            break :blk @as(c_int, 0);
                        }) != 0);
                        free(@as(?*anyopaque, @ptrCast(data)));
                        free(@as(?*anyopaque, @ptrCast(good)));
                        return @as([*c]stbi__uint16, @ptrCast(@alignCast(@as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))))));
                    },
                }
                break;
            }
        }
    }
    free(@as(?*anyopaque, @ptrCast(data)));
    return good;
}
pub const stbi__huffman = extern struct {
    fast: [512]stbi_uc = @import("std").mem.zeroes([512]stbi_uc),
    code: [256]stbi__uint16 = @import("std").mem.zeroes([256]stbi__uint16),
    values: [256]stbi_uc = @import("std").mem.zeroes([256]stbi_uc),
    size: [257]stbi_uc = @import("std").mem.zeroes([257]stbi_uc),
    maxcode: [18]c_uint = @import("std").mem.zeroes([18]c_uint),
    delta: [17]c_int = @import("std").mem.zeroes([17]c_int),
};
const struct_unnamed_7 = extern struct {
    id: c_int = @import("std").mem.zeroes(c_int),
    h: c_int = @import("std").mem.zeroes(c_int),
    v: c_int = @import("std").mem.zeroes(c_int),
    tq: c_int = @import("std").mem.zeroes(c_int),
    hd: c_int = @import("std").mem.zeroes(c_int),
    ha: c_int = @import("std").mem.zeroes(c_int),
    dc_pred: c_int = @import("std").mem.zeroes(c_int),
    x: c_int = @import("std").mem.zeroes(c_int),
    y: c_int = @import("std").mem.zeroes(c_int),
    w2: c_int = @import("std").mem.zeroes(c_int),
    h2: c_int = @import("std").mem.zeroes(c_int),
    data: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    raw_data: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    raw_coeff: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    linebuf: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    coeff: [*c]c_short = @import("std").mem.zeroes([*c]c_short),
    coeff_w: c_int = @import("std").mem.zeroes(c_int),
    coeff_h: c_int = @import("std").mem.zeroes(c_int),
};
pub const stbi__jpeg = extern struct {
    s: [*c]stbi__context = @import("std").mem.zeroes([*c]stbi__context),
    huff_dc: [4]stbi__huffman = @import("std").mem.zeroes([4]stbi__huffman),
    huff_ac: [4]stbi__huffman = @import("std").mem.zeroes([4]stbi__huffman),
    dequant: [4][64]stbi__uint16 = @import("std").mem.zeroes([4][64]stbi__uint16),
    fast_ac: [4][512]stbi__int16 = @import("std").mem.zeroes([4][512]stbi__int16),
    img_h_max: c_int = @import("std").mem.zeroes(c_int),
    img_v_max: c_int = @import("std").mem.zeroes(c_int),
    img_mcu_x: c_int = @import("std").mem.zeroes(c_int),
    img_mcu_y: c_int = @import("std").mem.zeroes(c_int),
    img_mcu_w: c_int = @import("std").mem.zeroes(c_int),
    img_mcu_h: c_int = @import("std").mem.zeroes(c_int),
    img_comp: [4]struct_unnamed_7 = @import("std").mem.zeroes([4]struct_unnamed_7),
    code_buffer: stbi__uint32 = @import("std").mem.zeroes(stbi__uint32),
    code_bits: c_int = @import("std").mem.zeroes(c_int),
    marker: u8 = @import("std").mem.zeroes(u8),
    nomore: c_int = @import("std").mem.zeroes(c_int),
    progressive: c_int = @import("std").mem.zeroes(c_int),
    spec_start: c_int = @import("std").mem.zeroes(c_int),
    spec_end: c_int = @import("std").mem.zeroes(c_int),
    succ_high: c_int = @import("std").mem.zeroes(c_int),
    succ_low: c_int = @import("std").mem.zeroes(c_int),
    eob_run: c_int = @import("std").mem.zeroes(c_int),
    jfif: c_int = @import("std").mem.zeroes(c_int),
    app14_color_transform: c_int = @import("std").mem.zeroes(c_int),
    rgb: c_int = @import("std").mem.zeroes(c_int),
    scan_n: c_int = @import("std").mem.zeroes(c_int),
    order: [4]c_int = @import("std").mem.zeroes([4]c_int),
    restart_interval: c_int = @import("std").mem.zeroes(c_int),
    todo: c_int = @import("std").mem.zeroes(c_int),
    idct_block_kernel: ?*const fn ([*c]stbi_uc, c_int, [*c]c_short) callconv(.c) void = @import("std").mem.zeroes(?*const fn ([*c]stbi_uc, c_int, [*c]c_short) callconv(.c) void),
    YCbCr_to_RGB_kernel: ?*const fn ([*c]stbi_uc, [*c]const stbi_uc, [*c]const stbi_uc, [*c]const stbi_uc, c_int, c_int) callconv(.c) void = @import("std").mem.zeroes(?*const fn ([*c]stbi_uc, [*c]const stbi_uc, [*c]const stbi_uc, [*c]const stbi_uc, c_int, c_int) callconv(.c) void),
    resample_row_hv_2_kernel: ?*const fn ([*c]stbi_uc, [*c]stbi_uc, [*c]stbi_uc, c_int, c_int) callconv(.c) [*c]stbi_uc = @import("std").mem.zeroes(?*const fn ([*c]stbi_uc, [*c]stbi_uc, [*c]stbi_uc, c_int, c_int) callconv(.c) [*c]stbi_uc),
};
pub fn stbi__build_huffman(arg_h: [*c]stbi__huffman, arg_count: [*c]c_int) callconv(.c) c_int {
    var h = arg_h;
    _ = &h;
    var count = arg_count;
    _ = &count;
    var i: c_int = undefined;
    _ = &i;
    var j: c_int = undefined;
    _ = &j;
    var k: c_int = 0;
    _ = &k;
    var code: c_uint = undefined;
    _ = &code;
    {
        i = 0;
        while (i < @as(c_int, 16)) : (i += 1) {
            {
                j = 0;
                while (j < (blk: {
                    const tmp = i;
                    if (tmp >= 0) break :blk count + @as(usize, @intCast(tmp)) else break :blk count - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*) : (j += 1) {
                    h.*.size[@as(c_uint, @intCast(blk: {
                        const ref = &k;
                        const tmp = ref.*;
                        ref.* += 1;
                        break :blk tmp;
                    }))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(i + @as(c_int, 1)))));
                    if (k >= @as(c_int, 257)) return 0;
                }
            }
        }
    }
    h.*.size[@as(c_uint, @intCast(k))] = 0;
    code = 0;
    k = 0;
    {
        j = 1;
        while (j <= @as(c_int, 16)) : (j += 1) {
            h.*.delta[@as(c_uint, @intCast(j))] = @as(c_int, @bitCast(@as(c_uint, @bitCast(k)) -% code));
            if (@as(c_int, @bitCast(@as(c_uint, h.*.size[@as(c_uint, @intCast(k))]))) == j) {
                while (@as(c_int, @bitCast(@as(c_uint, h.*.size[@as(c_uint, @intCast(k))]))) == j) {
                    h.*.code[@as(c_uint, @intCast(blk: {
                        const ref = &k;
                        const tmp = ref.*;
                        ref.* += 1;
                        break :blk tmp;
                    }))] = @as(stbi__uint16, @bitCast(@as(c_ushort, @truncate(blk: {
                        const ref = &code;
                        const tmp = ref.*;
                        ref.* +%= 1;
                        break :blk tmp;
                    }))));
                }
                if ((code -% @as(c_uint, @bitCast(@as(c_int, 1)))) >= (@as(c_uint, 1) << @intCast(j))) return 0;
            }
            h.*.maxcode[@as(c_uint, @intCast(j))] = code << @intCast(@as(c_int, 16) - j);
            code <<= @intCast(@as(c_int, 1));
        }
    }
    h.*.maxcode[@as(c_uint, @intCast(j))] = 4294967295;
    _ = memset(@as(?*anyopaque, @ptrCast(@as([*c]stbi_uc, @ptrCast(@alignCast(&h.*.fast[@as(usize, @intCast(0))]))))), @as(c_int, 255), @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1) << @intCast(9)))));
    {
        i = 0;
        while (i < k) : (i += 1) {
            var s: c_int = @as(c_int, @bitCast(@as(c_uint, h.*.size[@as(c_uint, @intCast(i))])));
            _ = &s;
            if (s <= @as(c_int, 9)) {
                var c: c_int = @as(c_int, @bitCast(@as(c_uint, h.*.code[@as(c_uint, @intCast(i))]))) << @intCast(@as(c_int, 9) - s);
                _ = &c;
                var m: c_int = @as(c_int, 1) << @intCast(@as(c_int, 9) - s);
                _ = &m;
                {
                    j = 0;
                    while (j < m) : (j += 1) {
                        h.*.fast[@as(c_uint, @intCast(c + j))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(i))));
                    }
                }
            }
        }
    }
    return 1;
}
pub fn stbi__build_fast_ac(arg_fast_ac: [*c]stbi__int16, arg_h: [*c]stbi__huffman) callconv(.c) void {
    var fast_ac = arg_fast_ac;
    _ = &fast_ac;
    var h = arg_h;
    _ = &h;
    var i: c_int = undefined;
    _ = &i;
    {
        i = 0;
        while (i < (@as(c_int, 1) << @intCast(9))) : (i += 1) {
            var fast: stbi_uc = h.*.fast[@as(c_uint, @intCast(i))];
            _ = &fast;
            (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk fast_ac + @as(usize, @intCast(tmp)) else break :blk fast_ac - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = 0;
            if (@as(c_int, @bitCast(@as(c_uint, fast))) < @as(c_int, 255)) {
                var rs: c_int = @as(c_int, @bitCast(@as(c_uint, h.*.values[fast])));
                _ = &rs;
                var run: c_int = (rs >> @intCast(4)) & @as(c_int, 15);
                _ = &run;
                var magbits: c_int = rs & @as(c_int, 15);
                _ = &magbits;
                var len: c_int = @as(c_int, @bitCast(@as(c_uint, h.*.size[fast])));
                _ = &len;
                if ((magbits != 0) and ((len + magbits) <= @as(c_int, 9))) {
                    var k: c_int = ((i << @intCast(len)) & ((@as(c_int, 1) << @intCast(9)) - @as(c_int, 1))) >> @intCast(@as(c_int, 9) - magbits);
                    _ = &k;
                    var m: c_int = @as(c_int, 1) << @intCast(magbits - @as(c_int, 1));
                    _ = &m;
                    if (k < m) {
                        k += @as(c_int, @bitCast((~@as(c_uint, 0) << @intCast(magbits)) +% @as(c_uint, @bitCast(@as(c_int, 1)))));
                    }
                    if ((k >= -@as(c_int, 128)) and (k <= @as(c_int, 127))) {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk fast_ac + @as(usize, @intCast(tmp)) else break :blk fast_ac - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(stbi__int16, @bitCast(@as(c_short, @truncate(((k * @as(c_int, 256)) + (run * @as(c_int, 16))) + (len + magbits)))));
                    }
                }
            }
        }
    }
}
pub fn stbi__grow_buffer_unsafe(arg_j: [*c]stbi__jpeg) callconv(.c) void {
    var j = arg_j;
    _ = &j;
    while (true) {
        var b: c_uint = @as(c_uint, @bitCast(if (j.*.nomore != 0) @as(c_int, 0) else @as(c_int, @bitCast(@as(c_uint, stbi__get8(j.*.s))))));
        _ = &b;
        if (b == @as(c_uint, @bitCast(@as(c_int, 255)))) {
            var c: c_int = @as(c_int, @bitCast(@as(c_uint, stbi__get8(j.*.s))));
            _ = &c;
            while (c == @as(c_int, 255)) {
                c = @as(c_int, @bitCast(@as(c_uint, stbi__get8(j.*.s))));
            }
            if (c != @as(c_int, 0)) {
                j.*.marker = @as(u8, @bitCast(@as(i8, @truncate(c))));
                j.*.nomore = 1;
                return;
            }
        }
        j.*.code_buffer |= @as(stbi__uint32, @bitCast(b << @intCast(@as(c_int, 24) - j.*.code_bits)));
        j.*.code_bits += @as(c_int, 8);
        if (!(j.*.code_bits <= @as(c_int, 24))) break;
    }
}
pub const stbi__bmask: [17]stbi__uint32 = [17]stbi__uint32{
    0,
    1,
    3,
    7,
    15,
    31,
    63,
    127,
    255,
    @as(stbi__uint32, @bitCast(@as(c_int, 511))),
    @as(stbi__uint32, @bitCast(@as(c_int, 1023))),
    @as(stbi__uint32, @bitCast(@as(c_int, 2047))),
    @as(stbi__uint32, @bitCast(@as(c_int, 4095))),
    @as(stbi__uint32, @bitCast(@as(c_int, 8191))),
    @as(stbi__uint32, @bitCast(@as(c_int, 16383))),
    @as(stbi__uint32, @bitCast(@as(c_int, 32767))),
    @as(stbi__uint32, @bitCast(@as(c_int, 65535))),
};
pub fn stbi__jpeg_huff_decode(arg_j: [*c]stbi__jpeg, arg_h: [*c]stbi__huffman) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var h = arg_h;
    _ = &h;
    var temp: c_uint = undefined;
    _ = &temp;
    var c: c_int = undefined;
    _ = &c;
    var k: c_int = undefined;
    _ = &k;
    if (j.*.code_bits < @as(c_int, 16)) {
        stbi__grow_buffer_unsafe(j);
    }
    c = @as(c_int, @bitCast((j.*.code_buffer >> @intCast(@as(c_int, 32) - @as(c_int, 9))) & @as(stbi__uint32, @bitCast((@as(c_int, 1) << @intCast(9)) - @as(c_int, 1)))));
    k = @as(c_int, @bitCast(@as(c_uint, h.*.fast[@as(c_uint, @intCast(c))])));
    if (k < @as(c_int, 255)) {
        var s: c_int = @as(c_int, @bitCast(@as(c_uint, h.*.size[@as(c_uint, @intCast(k))])));
        _ = &s;
        if (s > j.*.code_bits) return -@as(c_int, 1);
        j.*.code_buffer <<= @intCast(s);
        j.*.code_bits -= s;
        return @as(c_int, @bitCast(@as(c_uint, h.*.values[@as(c_uint, @intCast(k))])));
    }
    temp = j.*.code_buffer >> @intCast(16);
    {
        k = @as(c_int, 9) + @as(c_int, 1);
        while (true) : (k += 1) if (temp < h.*.maxcode[@as(c_uint, @intCast(k))]) break;
    }
    if (k == @as(c_int, 17)) {
        j.*.code_bits -= @as(c_int, 16);
        return -@as(c_int, 1);
    }
    if (k > j.*.code_bits) return -@as(c_int, 1);
    c = @as(c_int, @bitCast(((j.*.code_buffer >> @intCast(@as(c_int, 32) - k)) & stbi__bmask[@as(c_uint, @intCast(k))]) +% @as(stbi__uint32, @bitCast(h.*.delta[@as(c_uint, @intCast(k))]))));
    if ((c < @as(c_int, 0)) or (c >= @as(c_int, 256))) return -@as(c_int, 1);
    _ = (((j.*.code_buffer >> @intCast(@as(c_int, 32) - @as(c_int, @bitCast(@as(c_uint, h.*.size[@as(c_uint, @intCast(c))]))))) & stbi__bmask[h.*.size[@as(c_uint, @intCast(c))]]) == @as(stbi__uint32, @bitCast(@as(c_uint, h.*.code[@as(c_uint, @intCast(c))])))) or ((blk: {
        __assert_fail("(((j->code_buffer) >> (32 - h->size[c])) & stbi__bmask[h->size[c]]) == h->code[c]", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 2140), "stbi__jpeg_huff_decode");
        break :blk @as(c_int, 0);
    }) != 0);
    j.*.code_bits -= k;
    j.*.code_buffer <<= @intCast(k);
    return @as(c_int, @bitCast(@as(c_uint, h.*.values[@as(c_uint, @intCast(c))])));
}
pub const stbi__jbias: [16]c_int = [16]c_int{
    0,
    -@as(c_int, 1),
    -@as(c_int, 3),
    -@as(c_int, 7),
    -@as(c_int, 15),
    -@as(c_int, 31),
    -@as(c_int, 63),
    -@as(c_int, 127),
    -@as(c_int, 255),
    -@as(c_int, 511),
    -@as(c_int, 1023),
    -@as(c_int, 2047),
    -@as(c_int, 4095),
    -@as(c_int, 8191),
    -@as(c_int, 16383),
    -@as(c_int, 32767),
};
pub fn stbi__extend_receive(arg_j: [*c]stbi__jpeg, arg_n: c_int) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var n = arg_n;
    _ = &n;
    var k: c_uint = undefined;
    _ = &k;
    var sgn: c_int = undefined;
    _ = &sgn;
    if (j.*.code_bits < n) {
        stbi__grow_buffer_unsafe(j);
    }
    if (j.*.code_bits < n) return 0;
    sgn = @as(c_int, @bitCast(j.*.code_buffer >> @intCast(31)));
    k = (j.*.code_buffer << @intCast(n)) | (j.*.code_buffer >> @intCast(-n & @as(c_int, 31)));
    j.*.code_buffer = k & ~stbi__bmask[@as(c_uint, @intCast(n))];
    k &= @as(c_uint, @bitCast(stbi__bmask[@as(c_uint, @intCast(n))]));
    j.*.code_bits -= n;
    return @as(c_int, @bitCast(k +% @as(c_uint, @bitCast(stbi__jbias[@as(c_uint, @intCast(n))] & (sgn - @as(c_int, 1))))));
}
pub fn stbi__jpeg_get_bits(arg_j: [*c]stbi__jpeg, arg_n: c_int) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var n = arg_n;
    _ = &n;
    var k: c_uint = undefined;
    _ = &k;
    if (j.*.code_bits < n) {
        stbi__grow_buffer_unsafe(j);
    }
    if (j.*.code_bits < n) return 0;
    k = (j.*.code_buffer << @intCast(n)) | (j.*.code_buffer >> @intCast(-n & @as(c_int, 31)));
    j.*.code_buffer = k & ~stbi__bmask[@as(c_uint, @intCast(n))];
    k &= @as(c_uint, @bitCast(stbi__bmask[@as(c_uint, @intCast(n))]));
    j.*.code_bits -= n;
    return @as(c_int, @bitCast(k));
}
pub fn stbi__jpeg_get_bit(arg_j: [*c]stbi__jpeg) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var k: c_uint = undefined;
    _ = &k;
    if (j.*.code_bits < @as(c_int, 1)) {
        stbi__grow_buffer_unsafe(j);
    }
    if (j.*.code_bits < @as(c_int, 1)) return 0;
    k = j.*.code_buffer;
    j.*.code_buffer <<= @intCast(@as(c_int, 1));
    j.*.code_bits -= 1;
    return @as(c_int, @bitCast(k & @as(c_uint, 2147483648)));
}
pub const stbi__jpeg_dezigzag: [79]stbi_uc = [79]stbi_uc{
    0,
    1,
    8,
    16,
    9,
    2,
    3,
    10,
    17,
    24,
    32,
    25,
    18,
    11,
    4,
    5,
    12,
    19,
    26,
    33,
    40,
    48,
    41,
    34,
    27,
    20,
    13,
    6,
    7,
    14,
    21,
    28,
    35,
    42,
    49,
    56,
    57,
    50,
    43,
    36,
    29,
    22,
    15,
    23,
    30,
    37,
    44,
    51,
    58,
    59,
    52,
    45,
    38,
    31,
    39,
    46,
    53,
    60,
    61,
    54,
    47,
    55,
    62,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
    63,
};
pub fn stbi__jpeg_decode_block(arg_j: [*c]stbi__jpeg, arg_data: [*c]c_short, arg_hdc: [*c]stbi__huffman, arg_hac: [*c]stbi__huffman, arg_fac: [*c]stbi__int16, arg_b: c_int, arg_dequant: [*c]stbi__uint16) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var data = arg_data;
    _ = &data;
    var hdc = arg_hdc;
    _ = &hdc;
    var hac = arg_hac;
    _ = &hac;
    var fac = arg_fac;
    _ = &fac;
    var b = arg_b;
    _ = &b;
    var dequant = arg_dequant;
    _ = &dequant;
    var diff: c_int = undefined;
    _ = &diff;
    var dc: c_int = undefined;
    _ = &dc;
    var k: c_int = undefined;
    _ = &k;
    var t: c_int = undefined;
    _ = &t;
    if (j.*.code_bits < @as(c_int, 16)) {
        stbi__grow_buffer_unsafe(j);
    }
    t = stbi__jpeg_huff_decode(j, hdc);
    if ((t < @as(c_int, 0)) or (t > @as(c_int, 15))) return 0;
    _ = memset(@as(?*anyopaque, @ptrCast(data)), @as(c_int, 0), @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 64)))) *% @sizeOf(c_short));
    diff = if (t != 0) stbi__extend_receive(j, t) else @as(c_int, 0);
    if (!(stbi__addints_valid(j.*.img_comp[@as(c_uint, @intCast(b))].dc_pred, diff) != 0)) return 0;
    dc = j.*.img_comp[@as(c_uint, @intCast(b))].dc_pred + diff;
    j.*.img_comp[@as(c_uint, @intCast(b))].dc_pred = dc;
    if (!(stbi__mul2shorts_valid(dc, @as(c_int, @bitCast(@as(c_uint, dequant[@as(c_uint, @intCast(@as(c_int, 0)))])))) != 0)) return 0;
    data[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(c_short, @bitCast(@as(c_short, @truncate(dc * @as(c_int, @bitCast(@as(c_uint, dequant[@as(c_uint, @intCast(@as(c_int, 0)))])))))));
    k = 1;
    while (true) {
        var zig: c_uint = undefined;
        _ = &zig;
        var c: c_int = undefined;
        _ = &c;
        var r: c_int = undefined;
        _ = &r;
        var s: c_int = undefined;
        _ = &s;
        if (j.*.code_bits < @as(c_int, 16)) {
            stbi__grow_buffer_unsafe(j);
        }
        c = @as(c_int, @bitCast((j.*.code_buffer >> @intCast(@as(c_int, 32) - @as(c_int, 9))) & @as(stbi__uint32, @bitCast((@as(c_int, 1) << @intCast(9)) - @as(c_int, 1)))));
        r = @as(c_int, @bitCast(@as(c_int, (blk: {
            const tmp = c;
            if (tmp >= 0) break :blk fac + @as(usize, @intCast(tmp)) else break :blk fac - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*)));
        if (r != 0) {
            k += (r >> @intCast(4)) & @as(c_int, 15);
            s = r & @as(c_int, 15);
            if (s > j.*.code_bits) return 0;
            j.*.code_buffer <<= @intCast(s);
            j.*.code_bits -= s;
            zig = @as(c_uint, @bitCast(@as(c_uint, stbi__jpeg_dezigzag[@as(c_uint, @intCast(blk: {
                const ref = &k;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }))])));
            data[zig] = @as(c_short, @bitCast(@as(c_short, @truncate((r >> @intCast(8)) * @as(c_int, @bitCast(@as(c_uint, dequant[zig])))))));
        } else {
            var rs: c_int = stbi__jpeg_huff_decode(j, hac);
            _ = &rs;
            if (rs < @as(c_int, 0)) return 0;
            s = rs & @as(c_int, 15);
            r = rs >> @intCast(4);
            if (s == @as(c_int, 0)) {
                if (rs != @as(c_int, 240)) break;
                k += @as(c_int, 16);
            } else {
                k += r;
                zig = @as(c_uint, @bitCast(@as(c_uint, stbi__jpeg_dezigzag[@as(c_uint, @intCast(blk: {
                    const ref = &k;
                    const tmp = ref.*;
                    ref.* += 1;
                    break :blk tmp;
                }))])));
                data[zig] = @as(c_short, @bitCast(@as(c_short, @truncate(stbi__extend_receive(j, s) * @as(c_int, @bitCast(@as(c_uint, dequant[zig])))))));
            }
        }
        if (!(k < @as(c_int, 64))) break;
    }
    return 1;
}
pub fn stbi__jpeg_decode_block_prog_dc(arg_j: [*c]stbi__jpeg, arg_data: [*c]c_short, arg_hdc: [*c]stbi__huffman, arg_b: c_int) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var data = arg_data;
    _ = &data;
    var hdc = arg_hdc;
    _ = &hdc;
    var b = arg_b;
    _ = &b;
    var diff: c_int = undefined;
    _ = &diff;
    var dc: c_int = undefined;
    _ = &dc;
    var t: c_int = undefined;
    _ = &t;
    if (j.*.spec_end != @as(c_int, 0)) return 0;
    if (j.*.code_bits < @as(c_int, 16)) {
        stbi__grow_buffer_unsafe(j);
    }
    if (j.*.succ_high == @as(c_int, 0)) {
        _ = memset(@as(?*anyopaque, @ptrCast(data)), @as(c_int, 0), @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 64)))) *% @sizeOf(c_short));
        t = stbi__jpeg_huff_decode(j, hdc);
        if ((t < @as(c_int, 0)) or (t > @as(c_int, 15))) return 0;
        diff = if (t != 0) stbi__extend_receive(j, t) else @as(c_int, 0);
        if (!(stbi__addints_valid(j.*.img_comp[@as(c_uint, @intCast(b))].dc_pred, diff) != 0)) return 0;
        dc = j.*.img_comp[@as(c_uint, @intCast(b))].dc_pred + diff;
        j.*.img_comp[@as(c_uint, @intCast(b))].dc_pred = dc;
        if (!(stbi__mul2shorts_valid(dc, @as(c_int, 1) << @intCast(j.*.succ_low)) != 0)) return 0;
        data[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(c_short, @bitCast(@as(c_short, @truncate(dc * (@as(c_int, 1) << @intCast(j.*.succ_low))))));
    } else {
        if (stbi__jpeg_get_bit(j) != 0) {
            data[@as(c_uint, @intCast(@as(c_int, 0)))] += @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_int, @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, 1) << @intCast(j.*.succ_low))))))))))));
        }
    }
    return 1;
}
pub fn stbi__jpeg_decode_block_prog_ac(arg_j: [*c]stbi__jpeg, arg_data: [*c]c_short, arg_hac: [*c]stbi__huffman, arg_fac: [*c]stbi__int16) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var data = arg_data;
    _ = &data;
    var hac = arg_hac;
    _ = &hac;
    var fac = arg_fac;
    _ = &fac;
    var k: c_int = undefined;
    _ = &k;
    if (j.*.spec_start == @as(c_int, 0)) return 0;
    if (j.*.succ_high == @as(c_int, 0)) {
        var shift: c_int = j.*.succ_low;
        _ = &shift;
        if (j.*.eob_run != 0) {
            j.*.eob_run -= 1;
            return 1;
        }
        k = j.*.spec_start;
        while (true) {
            var zig: c_uint = undefined;
            _ = &zig;
            var c: c_int = undefined;
            _ = &c;
            var r: c_int = undefined;
            _ = &r;
            var s: c_int = undefined;
            _ = &s;
            if (j.*.code_bits < @as(c_int, 16)) {
                stbi__grow_buffer_unsafe(j);
            }
            c = @as(c_int, @bitCast((j.*.code_buffer >> @intCast(@as(c_int, 32) - @as(c_int, 9))) & @as(stbi__uint32, @bitCast((@as(c_int, 1) << @intCast(9)) - @as(c_int, 1)))));
            r = @as(c_int, @bitCast(@as(c_int, (blk: {
                const tmp = c;
                if (tmp >= 0) break :blk fac + @as(usize, @intCast(tmp)) else break :blk fac - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)));
            if (r != 0) {
                k += (r >> @intCast(4)) & @as(c_int, 15);
                s = r & @as(c_int, 15);
                if (s > j.*.code_bits) return 0;
                j.*.code_buffer <<= @intCast(s);
                j.*.code_bits -= s;
                zig = @as(c_uint, @bitCast(@as(c_uint, stbi__jpeg_dezigzag[@as(c_uint, @intCast(blk: {
                    const ref = &k;
                    const tmp = ref.*;
                    ref.* += 1;
                    break :blk tmp;
                }))])));
                data[zig] = @as(c_short, @bitCast(@as(c_short, @truncate((r >> @intCast(8)) * (@as(c_int, 1) << @intCast(shift))))));
            } else {
                var rs: c_int = stbi__jpeg_huff_decode(j, hac);
                _ = &rs;
                if (rs < @as(c_int, 0)) return 0;
                s = rs & @as(c_int, 15);
                r = rs >> @intCast(4);
                if (s == @as(c_int, 0)) {
                    if (r < @as(c_int, 15)) {
                        j.*.eob_run = @as(c_int, 1) << @intCast(r);
                        if (r != 0) {
                            j.*.eob_run += stbi__jpeg_get_bits(j, r);
                        }
                        j.*.eob_run -= 1;
                        break;
                    }
                    k += @as(c_int, 16);
                } else {
                    k += r;
                    zig = @as(c_uint, @bitCast(@as(c_uint, stbi__jpeg_dezigzag[@as(c_uint, @intCast(blk: {
                        const ref = &k;
                        const tmp = ref.*;
                        ref.* += 1;
                        break :blk tmp;
                    }))])));
                    data[zig] = @as(c_short, @bitCast(@as(c_short, @truncate(stbi__extend_receive(j, s) * (@as(c_int, 1) << @intCast(shift))))));
                }
            }
            if (!(k <= j.*.spec_end)) break;
        }
    } else {
        var bit: c_short = @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, 1) << @intCast(j.*.succ_low)))));
        _ = &bit;
        if (j.*.eob_run != 0) {
            j.*.eob_run -= 1;
            {
                k = j.*.spec_start;
                while (k <= j.*.spec_end) : (k += 1) {
                    var p: [*c]c_short = &data[stbi__jpeg_dezigzag[@as(c_uint, @intCast(k))]];
                    _ = &p;
                    if (@as(c_int, @bitCast(@as(c_int, p.*))) != @as(c_int, 0)) if (stbi__jpeg_get_bit(j) != 0) if ((@as(c_int, @bitCast(@as(c_int, p.*))) & @as(c_int, @bitCast(@as(c_int, bit)))) == @as(c_int, 0)) {
                        if (@as(c_int, @bitCast(@as(c_int, p.*))) > @as(c_int, 0)) {
                            p.* += @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_int, bit)))))));
                        } else {
                            p.* -= @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_int, bit)))))));
                        }
                    };
                }
            }
        } else {
            k = j.*.spec_start;
            while (true) {
                var r: c_int = undefined;
                _ = &r;
                var s: c_int = undefined;
                _ = &s;
                var rs: c_int = stbi__jpeg_huff_decode(j, hac);
                _ = &rs;
                if (rs < @as(c_int, 0)) return 0;
                s = rs & @as(c_int, 15);
                r = rs >> @intCast(4);
                if (s == @as(c_int, 0)) {
                    if (r < @as(c_int, 15)) {
                        j.*.eob_run = (@as(c_int, 1) << @intCast(r)) - @as(c_int, 1);
                        if (r != 0) {
                            j.*.eob_run += stbi__jpeg_get_bits(j, r);
                        }
                        r = 64;
                    } else {}
                } else {
                    if (s != @as(c_int, 1)) return 0;
                    if (stbi__jpeg_get_bit(j) != 0) {
                        s = @as(c_int, @bitCast(@as(c_int, bit)));
                    } else {
                        s = -@as(c_int, @bitCast(@as(c_int, bit)));
                    }
                }
                while (k <= j.*.spec_end) {
                    var p: [*c]c_short = &data[stbi__jpeg_dezigzag[@as(c_uint, @intCast(blk: {
                        const ref = &k;
                        const tmp = ref.*;
                        ref.* += 1;
                        break :blk tmp;
                    }))]];
                    _ = &p;
                    if (@as(c_int, @bitCast(@as(c_int, p.*))) != @as(c_int, 0)) {
                        if (stbi__jpeg_get_bit(j) != 0) if ((@as(c_int, @bitCast(@as(c_int, p.*))) & @as(c_int, @bitCast(@as(c_int, bit)))) == @as(c_int, 0)) {
                            if (@as(c_int, @bitCast(@as(c_int, p.*))) > @as(c_int, 0)) {
                                p.* += @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_int, bit)))))));
                            } else {
                                p.* -= @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_int, bit)))))));
                            }
                        };
                    } else {
                        if (r == @as(c_int, 0)) {
                            p.* = @as(c_short, @bitCast(@as(c_short, @truncate(s))));
                            break;
                        }
                        r -= 1;
                    }
                }
                if (!(k <= j.*.spec_end)) break;
            }
        }
    }
    return 1;
}
pub fn stbi__clamp(arg_x: c_int) callconv(.c) stbi_uc {
    var x = arg_x;
    _ = &x;
    if (@as(c_uint, @bitCast(x)) > @as(c_uint, @bitCast(@as(c_int, 255)))) {
        if (x < @as(c_int, 0)) return 0;
        if (x > @as(c_int, 255)) return 255;
    }
    return @as(stbi_uc, @bitCast(@as(i8, @truncate(x))));
}
pub fn stbi__idct_block(arg_out: [*c]stbi_uc, arg_out_stride: c_int, arg_data: [*c]c_short) callconv(.c) void {
    var out = arg_out;
    _ = &out;
    var out_stride = arg_out_stride;
    _ = &out_stride;
    var data = arg_data;
    _ = &data;
    var i: c_int = undefined;
    _ = &i;
    var val: [64]c_int = undefined;
    _ = &val;
    var v: [*c]c_int = @as([*c]c_int, @ptrCast(@alignCast(&val[@as(usize, @intCast(0))])));
    _ = &v;
    var o: [*c]stbi_uc = undefined;
    _ = &o;
    var d: [*c]c_short = data;
    _ = &d;
    {
        i = 0;
        while (i < @as(c_int, 8)) : (_ = blk: {
            _ = blk_1: {
                i += 1;
                break :blk_1 blk_2: {
                    const ref = &d;
                    ref.* += 1;
                    break :blk_2 ref.*;
                };
            };
            break :blk blk_1: {
                const ref = &v;
                ref.* += 1;
                break :blk_1 ref.*;
            };
        }) {
            if (((((((@as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 8)))]))) == @as(c_int, 0)) and (@as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 16)))]))) == @as(c_int, 0))) and (@as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 24)))]))) == @as(c_int, 0))) and (@as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 32)))]))) == @as(c_int, 0))) and (@as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 40)))]))) == @as(c_int, 0))) and (@as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 48)))]))) == @as(c_int, 0))) and (@as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 56)))]))) == @as(c_int, 0))) {
                var dcterm: c_int = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 0)))]))) * @as(c_int, 4);
                _ = &dcterm;
                v[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                    const tmp = blk_1: {
                        const tmp_2 = blk_2: {
                            const tmp_3 = blk_3: {
                                const tmp_4 = blk_4: {
                                    const tmp_5 = blk_5: {
                                        const tmp_6 = blk_6: {
                                            const tmp_7 = dcterm;
                                            v[@as(c_uint, @intCast(@as(c_int, 56)))] = tmp_7;
                                            break :blk_6 tmp_7;
                                        };
                                        v[@as(c_uint, @intCast(@as(c_int, 48)))] = tmp_6;
                                        break :blk_5 tmp_6;
                                    };
                                    v[@as(c_uint, @intCast(@as(c_int, 40)))] = tmp_5;
                                    break :blk_4 tmp_5;
                                };
                                v[@as(c_uint, @intCast(@as(c_int, 32)))] = tmp_4;
                                break :blk_3 tmp_4;
                            };
                            v[@as(c_uint, @intCast(@as(c_int, 24)))] = tmp_3;
                            break :blk_2 tmp_3;
                        };
                        v[@as(c_uint, @intCast(@as(c_int, 16)))] = tmp_2;
                        break :blk_1 tmp_2;
                    };
                    v[@as(c_uint, @intCast(@as(c_int, 8)))] = tmp;
                    break :blk tmp;
                };
            } else {
                var t0: c_int = undefined;
                _ = &t0;
                var t1: c_int = undefined;
                _ = &t1;
                var t2: c_int = undefined;
                _ = &t2;
                var t3: c_int = undefined;
                _ = &t3;
                var p1: c_int = undefined;
                _ = &p1;
                var p2: c_int = undefined;
                _ = &p2;
                var p3: c_int = undefined;
                _ = &p3;
                var p4: c_int = undefined;
                _ = &p4;
                var p5: c_int = undefined;
                _ = &p5;
                var x0: c_int = undefined;
                _ = &x0;
                var x1: c_int = undefined;
                _ = &x1;
                var x2: c_int = undefined;
                _ = &x2;
                var x3: c_int = undefined;
                _ = &x3;
                p2 = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 16)))])));
                p3 = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 48)))])));
                p1 = (p2 + p3) * @as(c_int, @intFromFloat(@as(f64, @floatCast(0.5411961078643799 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
                t2 = p1 + (p3 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-1.8477590084075928 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5)));
                t3 = p1 + (p2 * @as(c_int, @intFromFloat(@as(f64, @floatCast(0.7653668522834778 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5)));
                p2 = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 0)))])));
                p3 = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 32)))])));
                t0 = (p2 + p3) * @as(c_int, 4096);
                t1 = (p2 - p3) * @as(c_int, 4096);
                x0 = t0 + t3;
                x3 = t0 - t3;
                x1 = t1 + t2;
                x2 = t1 - t2;
                t0 = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 56)))])));
                t1 = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 40)))])));
                t2 = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 24)))])));
                t3 = @as(c_int, @bitCast(@as(c_int, d[@as(c_uint, @intCast(@as(c_int, 8)))])));
                p3 = t0 + t2;
                p4 = t1 + t3;
                p1 = t0 + t3;
                p2 = t1 + t2;
                p5 = (p3 + p4) * @as(c_int, @intFromFloat(@as(f64, @floatCast(1.1758755445480347 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
                t0 = t0 * @as(c_int, @intFromFloat(@as(f64, @floatCast(0.29863134026527405 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
                t1 = t1 * @as(c_int, @intFromFloat(@as(f64, @floatCast(2.0531198978424072 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
                t2 = t2 * @as(c_int, @intFromFloat(@as(f64, @floatCast(3.0727109909057617 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
                t3 = t3 * @as(c_int, @intFromFloat(@as(f64, @floatCast(1.5013210773468018 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
                p1 = p5 + (p1 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-0.8999761939048767 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5)));
                p2 = p5 + (p2 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-2.562915563583374 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5)));
                p3 = p3 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-1.9615705013275146 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
                p4 = p4 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-0.39018064737319946 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
                t3 += p1 + p4;
                t2 += p2 + p3;
                t1 += p2 + p4;
                t0 += p1 + p3;
                x0 += @as(c_int, 512);
                x1 += @as(c_int, 512);
                x2 += @as(c_int, 512);
                x3 += @as(c_int, 512);
                v[@as(c_uint, @intCast(@as(c_int, 0)))] = (x0 + t3) >> @intCast(10);
                v[@as(c_uint, @intCast(@as(c_int, 56)))] = (x0 - t3) >> @intCast(10);
                v[@as(c_uint, @intCast(@as(c_int, 8)))] = (x1 + t2) >> @intCast(10);
                v[@as(c_uint, @intCast(@as(c_int, 48)))] = (x1 - t2) >> @intCast(10);
                v[@as(c_uint, @intCast(@as(c_int, 16)))] = (x2 + t1) >> @intCast(10);
                v[@as(c_uint, @intCast(@as(c_int, 40)))] = (x2 - t1) >> @intCast(10);
                v[@as(c_uint, @intCast(@as(c_int, 24)))] = (x3 + t0) >> @intCast(10);
                v[@as(c_uint, @intCast(@as(c_int, 32)))] = (x3 - t0) >> @intCast(10);
            }
        }
    }
    {
        _ = blk: {
            _ = blk_1: {
                i = 0;
                break :blk_1 blk_2: {
                    const tmp = @as([*c]c_int, @ptrCast(@alignCast(&val[@as(usize, @intCast(0))])));
                    v = tmp;
                    break :blk_2 tmp;
                };
            };
            break :blk blk_1: {
                const tmp = out;
                o = tmp;
                break :blk_1 tmp;
            };
        };
        while (i < @as(c_int, 8)) : (_ = blk: {
            _ = blk_1: {
                i += 1;
                break :blk_1 blk_2: {
                    const ref = &v;
                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 8)))));
                    break :blk_2 ref.*;
                };
            };
            break :blk blk_1: {
                const ref = &o;
                ref.* += @as(usize, @bitCast(@as(isize, @intCast(out_stride))));
                break :blk_1 ref.*;
            };
        }) {
            var t0: c_int = undefined;
            _ = &t0;
            var t1: c_int = undefined;
            _ = &t1;
            var t2: c_int = undefined;
            _ = &t2;
            var t3: c_int = undefined;
            _ = &t3;
            var p1: c_int = undefined;
            _ = &p1;
            var p2: c_int = undefined;
            _ = &p2;
            var p3: c_int = undefined;
            _ = &p3;
            var p4: c_int = undefined;
            _ = &p4;
            var p5: c_int = undefined;
            _ = &p5;
            var x0: c_int = undefined;
            _ = &x0;
            var x1: c_int = undefined;
            _ = &x1;
            var x2: c_int = undefined;
            _ = &x2;
            var x3: c_int = undefined;
            _ = &x3;
            p2 = v[@as(c_uint, @intCast(@as(c_int, 2)))];
            p3 = v[@as(c_uint, @intCast(@as(c_int, 6)))];
            p1 = (p2 + p3) * @as(c_int, @intFromFloat(@as(f64, @floatCast(0.5411961078643799 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
            t2 = p1 + (p3 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-1.8477590084075928 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5)));
            t3 = p1 + (p2 * @as(c_int, @intFromFloat(@as(f64, @floatCast(0.7653668522834778 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5)));
            p2 = v[@as(c_uint, @intCast(@as(c_int, 0)))];
            p3 = v[@as(c_uint, @intCast(@as(c_int, 4)))];
            t0 = (p2 + p3) * @as(c_int, 4096);
            t1 = (p2 - p3) * @as(c_int, 4096);
            x0 = t0 + t3;
            x3 = t0 - t3;
            x1 = t1 + t2;
            x2 = t1 - t2;
            t0 = v[@as(c_uint, @intCast(@as(c_int, 7)))];
            t1 = v[@as(c_uint, @intCast(@as(c_int, 5)))];
            t2 = v[@as(c_uint, @intCast(@as(c_int, 3)))];
            t3 = v[@as(c_uint, @intCast(@as(c_int, 1)))];
            p3 = t0 + t2;
            p4 = t1 + t3;
            p1 = t0 + t3;
            p2 = t1 + t2;
            p5 = (p3 + p4) * @as(c_int, @intFromFloat(@as(f64, @floatCast(1.1758755445480347 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
            t0 = t0 * @as(c_int, @intFromFloat(@as(f64, @floatCast(0.29863134026527405 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
            t1 = t1 * @as(c_int, @intFromFloat(@as(f64, @floatCast(2.0531198978424072 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
            t2 = t2 * @as(c_int, @intFromFloat(@as(f64, @floatCast(3.0727109909057617 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
            t3 = t3 * @as(c_int, @intFromFloat(@as(f64, @floatCast(1.5013210773468018 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
            p1 = p5 + (p1 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-0.8999761939048767 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5)));
            p2 = p5 + (p2 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-2.562915563583374 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5)));
            p3 = p3 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-1.9615705013275146 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
            p4 = p4 * @as(c_int, @intFromFloat(@as(f64, @floatCast(-0.39018064737319946 * @as(f32, @floatFromInt(@as(c_int, 4096))))) + 0.5));
            t3 += p1 + p4;
            t2 += p2 + p3;
            t1 += p2 + p4;
            t0 += p1 + p3;
            x0 += @as(c_int, 65536) + (@as(c_int, 128) << @intCast(17));
            x1 += @as(c_int, 65536) + (@as(c_int, 128) << @intCast(17));
            x2 += @as(c_int, 65536) + (@as(c_int, 128) << @intCast(17));
            x3 += @as(c_int, 65536) + (@as(c_int, 128) << @intCast(17));
            o[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__clamp((x0 + t3) >> @intCast(17));
            o[@as(c_uint, @intCast(@as(c_int, 7)))] = stbi__clamp((x0 - t3) >> @intCast(17));
            o[@as(c_uint, @intCast(@as(c_int, 1)))] = stbi__clamp((x1 + t2) >> @intCast(17));
            o[@as(c_uint, @intCast(@as(c_int, 6)))] = stbi__clamp((x1 - t2) >> @intCast(17));
            o[@as(c_uint, @intCast(@as(c_int, 2)))] = stbi__clamp((x2 + t1) >> @intCast(17));
            o[@as(c_uint, @intCast(@as(c_int, 5)))] = stbi__clamp((x2 - t1) >> @intCast(17));
            o[@as(c_uint, @intCast(@as(c_int, 3)))] = stbi__clamp((x3 + t0) >> @intCast(17));
            o[@as(c_uint, @intCast(@as(c_int, 4)))] = stbi__clamp((x3 - t0) >> @intCast(17));
        }
    }
}
pub fn stbi__get_marker(arg_j: [*c]stbi__jpeg) callconv(.c) stbi_uc {
    var j = arg_j;
    _ = &j;
    var x: stbi_uc = undefined;
    _ = &x;
    if (@as(c_int, @bitCast(@as(c_uint, j.*.marker))) != @as(c_int, 255)) {
        x = j.*.marker;
        j.*.marker = 255;
        return x;
    }
    x = stbi__get8(j.*.s);
    if (@as(c_int, @bitCast(@as(c_uint, x))) != @as(c_int, 255)) return 255;
    while (@as(c_int, @bitCast(@as(c_uint, x))) == @as(c_int, 255)) {
        x = stbi__get8(j.*.s);
    }
    return x;
}
pub fn stbi__jpeg_reset(arg_j: [*c]stbi__jpeg) callconv(.c) void {
    var j = arg_j;
    _ = &j;
    j.*.code_bits = 0;
    j.*.code_buffer = 0;
    j.*.nomore = 0;
    j.*.img_comp[@as(c_uint, @intCast(@as(c_int, 0)))].dc_pred = blk: {
        const tmp = blk_1: {
            const tmp_2 = blk_2: {
                const tmp_3 = @as(c_int, 0);
                j.*.img_comp[@as(c_uint, @intCast(@as(c_int, 3)))].dc_pred = tmp_3;
                break :blk_2 tmp_3;
            };
            j.*.img_comp[@as(c_uint, @intCast(@as(c_int, 2)))].dc_pred = tmp_2;
            break :blk_1 tmp_2;
        };
        j.*.img_comp[@as(c_uint, @intCast(@as(c_int, 1)))].dc_pred = tmp;
        break :blk tmp;
    };
    j.*.marker = 255;
    j.*.todo = if (j.*.restart_interval != 0) j.*.restart_interval else @as(c_int, 2147483647);
    j.*.eob_run = 0;
}
pub fn stbi__parse_entropy_coded_data(arg_z: [*c]stbi__jpeg) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    stbi__jpeg_reset(z);
    if (!(z.*.progressive != 0)) {
        if (z.*.scan_n == @as(c_int, 1)) {
            var i: c_int = undefined;
            _ = &i;
            var j: c_int = undefined;
            _ = &j;
            var data: [64]c_short = undefined;
            _ = &data;
            var n: c_int = z.*.order[@as(c_uint, @intCast(@as(c_int, 0)))];
            _ = &n;
            var w: c_int = (z.*.img_comp[@as(c_uint, @intCast(n))].x + @as(c_int, 7)) >> @intCast(3);
            _ = &w;
            var h: c_int = (z.*.img_comp[@as(c_uint, @intCast(n))].y + @as(c_int, 7)) >> @intCast(3);
            _ = &h;
            {
                j = 0;
                while (j < h) : (j += 1) {
                    {
                        i = 0;
                        while (i < w) : (i += 1) {
                            var ha: c_int = z.*.img_comp[@as(c_uint, @intCast(n))].ha;
                            _ = &ha;
                            if (!(stbi__jpeg_decode_block(z, @as([*c]c_short, @ptrCast(@alignCast(&data[@as(usize, @intCast(0))]))), @as([*c]stbi__huffman, @ptrCast(@alignCast(&z.*.huff_dc[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(z.*.img_comp[@as(c_uint, @intCast(n))].hd)))), @as([*c]stbi__huffman, @ptrCast(@alignCast(&z.*.huff_ac[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(ha)))), @as([*c]stbi__int16, @ptrCast(@alignCast(&z.*.fast_ac[@as(c_uint, @intCast(ha))][@as(usize, @intCast(0))]))), n, @as([*c]stbi__uint16, @ptrCast(@alignCast(&z.*.dequant[@as(c_uint, @intCast(z.*.img_comp[@as(c_uint, @intCast(n))].tq))][@as(usize, @intCast(0))])))) != 0)) return 0;
                            z.*.idct_block_kernel.?((z.*.img_comp[@as(c_uint, @intCast(n))].data + @as(usize, @bitCast(@as(isize, @intCast((z.*.img_comp[@as(c_uint, @intCast(n))].w2 * j) * @as(c_int, 8)))))) + @as(usize, @bitCast(@as(isize, @intCast(i * @as(c_int, 8))))), z.*.img_comp[@as(c_uint, @intCast(n))].w2, @as([*c]c_short, @ptrCast(@alignCast(&data[@as(usize, @intCast(0))]))));
                            if ((blk: {
                                const ref = &z.*.todo;
                                ref.* -= 1;
                                break :blk ref.*;
                            }) <= @as(c_int, 0)) {
                                if (z.*.code_bits < @as(c_int, 24)) {
                                    stbi__grow_buffer_unsafe(z);
                                }
                                if (!((@as(c_int, @bitCast(@as(c_uint, z.*.marker))) >= @as(c_int, 208)) and (@as(c_int, @bitCast(@as(c_uint, z.*.marker))) <= @as(c_int, 215)))) return 1;
                                stbi__jpeg_reset(z);
                            }
                        }
                    }
                }
            }
            return 1;
        } else {
            var i: c_int = undefined;
            _ = &i;
            var j: c_int = undefined;
            _ = &j;
            var k: c_int = undefined;
            _ = &k;
            var x: c_int = undefined;
            _ = &x;
            var y: c_int = undefined;
            _ = &y;
            var data: [64]c_short = undefined;
            _ = &data;
            {
                j = 0;
                while (j < z.*.img_mcu_y) : (j += 1) {
                    {
                        i = 0;
                        while (i < z.*.img_mcu_x) : (i += 1) {
                            {
                                k = 0;
                                while (k < z.*.scan_n) : (k += 1) {
                                    var n: c_int = z.*.order[@as(c_uint, @intCast(k))];
                                    _ = &n;
                                    {
                                        y = 0;
                                        while (y < z.*.img_comp[@as(c_uint, @intCast(n))].v) : (y += 1) {
                                            {
                                                x = 0;
                                                while (x < z.*.img_comp[@as(c_uint, @intCast(n))].h) : (x += 1) {
                                                    var x2: c_int = ((i * z.*.img_comp[@as(c_uint, @intCast(n))].h) + x) * @as(c_int, 8);
                                                    _ = &x2;
                                                    var y2: c_int = ((j * z.*.img_comp[@as(c_uint, @intCast(n))].v) + y) * @as(c_int, 8);
                                                    _ = &y2;
                                                    var ha: c_int = z.*.img_comp[@as(c_uint, @intCast(n))].ha;
                                                    _ = &ha;
                                                    if (!(stbi__jpeg_decode_block(z, @as([*c]c_short, @ptrCast(@alignCast(&data[@as(usize, @intCast(0))]))), @as([*c]stbi__huffman, @ptrCast(@alignCast(&z.*.huff_dc[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(z.*.img_comp[@as(c_uint, @intCast(n))].hd)))), @as([*c]stbi__huffman, @ptrCast(@alignCast(&z.*.huff_ac[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(ha)))), @as([*c]stbi__int16, @ptrCast(@alignCast(&z.*.fast_ac[@as(c_uint, @intCast(ha))][@as(usize, @intCast(0))]))), n, @as([*c]stbi__uint16, @ptrCast(@alignCast(&z.*.dequant[@as(c_uint, @intCast(z.*.img_comp[@as(c_uint, @intCast(n))].tq))][@as(usize, @intCast(0))])))) != 0)) return 0;
                                                    z.*.idct_block_kernel.?((z.*.img_comp[@as(c_uint, @intCast(n))].data + @as(usize, @bitCast(@as(isize, @intCast(z.*.img_comp[@as(c_uint, @intCast(n))].w2 * y2))))) + @as(usize, @bitCast(@as(isize, @intCast(x2)))), z.*.img_comp[@as(c_uint, @intCast(n))].w2, @as([*c]c_short, @ptrCast(@alignCast(&data[@as(usize, @intCast(0))]))));
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            if ((blk: {
                                const ref = &z.*.todo;
                                ref.* -= 1;
                                break :blk ref.*;
                            }) <= @as(c_int, 0)) {
                                if (z.*.code_bits < @as(c_int, 24)) {
                                    stbi__grow_buffer_unsafe(z);
                                }
                                if (!((@as(c_int, @bitCast(@as(c_uint, z.*.marker))) >= @as(c_int, 208)) and (@as(c_int, @bitCast(@as(c_uint, z.*.marker))) <= @as(c_int, 215)))) return 1;
                                stbi__jpeg_reset(z);
                            }
                        }
                    }
                }
            }
            return 1;
        }
    } else {
        if (z.*.scan_n == @as(c_int, 1)) {
            var i: c_int = undefined;
            _ = &i;
            var j: c_int = undefined;
            _ = &j;
            var n: c_int = z.*.order[@as(c_uint, @intCast(@as(c_int, 0)))];
            _ = &n;
            var w: c_int = (z.*.img_comp[@as(c_uint, @intCast(n))].x + @as(c_int, 7)) >> @intCast(3);
            _ = &w;
            var h: c_int = (z.*.img_comp[@as(c_uint, @intCast(n))].y + @as(c_int, 7)) >> @intCast(3);
            _ = &h;
            {
                j = 0;
                while (j < h) : (j += 1) {
                    {
                        i = 0;
                        while (i < w) : (i += 1) {
                            var data: [*c]c_short = z.*.img_comp[@as(c_uint, @intCast(n))].coeff + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 64) * (i + (j * z.*.img_comp[@as(c_uint, @intCast(n))].coeff_w))))));
                            _ = &data;
                            if (z.*.spec_start == @as(c_int, 0)) {
                                if (!(stbi__jpeg_decode_block_prog_dc(z, data, &z.*.huff_dc[@as(c_uint, @intCast(z.*.img_comp[@as(c_uint, @intCast(n))].hd))], n) != 0)) return 0;
                            } else {
                                var ha: c_int = z.*.img_comp[@as(c_uint, @intCast(n))].ha;
                                _ = &ha;
                                if (!(stbi__jpeg_decode_block_prog_ac(z, data, &z.*.huff_ac[@as(c_uint, @intCast(ha))], @as([*c]stbi__int16, @ptrCast(@alignCast(&z.*.fast_ac[@as(c_uint, @intCast(ha))][@as(usize, @intCast(0))])))) != 0)) return 0;
                            }
                            if ((blk: {
                                const ref = &z.*.todo;
                                ref.* -= 1;
                                break :blk ref.*;
                            }) <= @as(c_int, 0)) {
                                if (z.*.code_bits < @as(c_int, 24)) {
                                    stbi__grow_buffer_unsafe(z);
                                }
                                if (!((@as(c_int, @bitCast(@as(c_uint, z.*.marker))) >= @as(c_int, 208)) and (@as(c_int, @bitCast(@as(c_uint, z.*.marker))) <= @as(c_int, 215)))) return 1;
                                stbi__jpeg_reset(z);
                            }
                        }
                    }
                }
            }
            return 1;
        } else {
            var i: c_int = undefined;
            _ = &i;
            var j: c_int = undefined;
            _ = &j;
            var k: c_int = undefined;
            _ = &k;
            var x: c_int = undefined;
            _ = &x;
            var y: c_int = undefined;
            _ = &y;
            {
                j = 0;
                while (j < z.*.img_mcu_y) : (j += 1) {
                    {
                        i = 0;
                        while (i < z.*.img_mcu_x) : (i += 1) {
                            {
                                k = 0;
                                while (k < z.*.scan_n) : (k += 1) {
                                    var n: c_int = z.*.order[@as(c_uint, @intCast(k))];
                                    _ = &n;
                                    {
                                        y = 0;
                                        while (y < z.*.img_comp[@as(c_uint, @intCast(n))].v) : (y += 1) {
                                            {
                                                x = 0;
                                                while (x < z.*.img_comp[@as(c_uint, @intCast(n))].h) : (x += 1) {
                                                    var x2: c_int = (i * z.*.img_comp[@as(c_uint, @intCast(n))].h) + x;
                                                    _ = &x2;
                                                    var y2: c_int = (j * z.*.img_comp[@as(c_uint, @intCast(n))].v) + y;
                                                    _ = &y2;
                                                    var data: [*c]c_short = z.*.img_comp[@as(c_uint, @intCast(n))].coeff + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 64) * (x2 + (y2 * z.*.img_comp[@as(c_uint, @intCast(n))].coeff_w))))));
                                                    _ = &data;
                                                    if (!(stbi__jpeg_decode_block_prog_dc(z, data, &z.*.huff_dc[@as(c_uint, @intCast(z.*.img_comp[@as(c_uint, @intCast(n))].hd))], n) != 0)) return 0;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            if ((blk: {
                                const ref = &z.*.todo;
                                ref.* -= 1;
                                break :blk ref.*;
                            }) <= @as(c_int, 0)) {
                                if (z.*.code_bits < @as(c_int, 24)) {
                                    stbi__grow_buffer_unsafe(z);
                                }
                                if (!((@as(c_int, @bitCast(@as(c_uint, z.*.marker))) >= @as(c_int, 208)) and (@as(c_int, @bitCast(@as(c_uint, z.*.marker))) <= @as(c_int, 215)))) return 1;
                                stbi__jpeg_reset(z);
                            }
                        }
                    }
                }
            }
            return 1;
        }
    }
    return 0;
}
pub fn stbi__jpeg_dequantize(arg_data: [*c]c_short, arg_dequant: [*c]stbi__uint16) callconv(.c) void {
    var data = arg_data;
    _ = &data;
    var dequant = arg_dequant;
    _ = &dequant;
    var i: c_int = undefined;
    _ = &i;
    {
        i = 0;
        while (i < @as(c_int, 64)) : (i += 1) {
            (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk data + @as(usize, @intCast(tmp)) else break :blk data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* *= @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk dequant + @as(usize, @intCast(tmp)) else break :blk dequant - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))))));
        }
    }
}
pub fn stbi__jpeg_finish(arg_z: [*c]stbi__jpeg) callconv(.c) void {
    var z = arg_z;
    _ = &z;
    if (z.*.progressive != 0) {
        var i: c_int = undefined;
        _ = &i;
        var j: c_int = undefined;
        _ = &j;
        var n: c_int = undefined;
        _ = &n;
        {
            n = 0;
            while (n < z.*.s.*.img_n) : (n += 1) {
                var w: c_int = (z.*.img_comp[@as(c_uint, @intCast(n))].x + @as(c_int, 7)) >> @intCast(3);
                _ = &w;
                var h: c_int = (z.*.img_comp[@as(c_uint, @intCast(n))].y + @as(c_int, 7)) >> @intCast(3);
                _ = &h;
                {
                    j = 0;
                    while (j < h) : (j += 1) {
                        {
                            i = 0;
                            while (i < w) : (i += 1) {
                                var data: [*c]c_short = z.*.img_comp[@as(c_uint, @intCast(n))].coeff + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 64) * (i + (j * z.*.img_comp[@as(c_uint, @intCast(n))].coeff_w))))));
                                _ = &data;
                                stbi__jpeg_dequantize(data, @as([*c]stbi__uint16, @ptrCast(@alignCast(&z.*.dequant[@as(c_uint, @intCast(z.*.img_comp[@as(c_uint, @intCast(n))].tq))][@as(usize, @intCast(0))]))));
                                z.*.idct_block_kernel.?((z.*.img_comp[@as(c_uint, @intCast(n))].data + @as(usize, @bitCast(@as(isize, @intCast((z.*.img_comp[@as(c_uint, @intCast(n))].w2 * j) * @as(c_int, 8)))))) + @as(usize, @bitCast(@as(isize, @intCast(i * @as(c_int, 8))))), z.*.img_comp[@as(c_uint, @intCast(n))].w2, data);
                            }
                        }
                    }
                }
            }
        }
    }
}
pub fn stbi__process_marker(arg_z: [*c]stbi__jpeg, arg_m: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var m = arg_m;
    _ = &m;
    var L: c_int = undefined;
    _ = &L;
    while (true) {
        switch (m) {
            @as(c_int, 255) => return 0,
            @as(c_int, 221) => {
                if (stbi__get16be(z.*.s) != @as(c_int, 4)) return 0;
                z.*.restart_interval = stbi__get16be(z.*.s);
                return 1;
            },
            @as(c_int, 219) => {
                L = stbi__get16be(z.*.s) - @as(c_int, 2);
                while (L > @as(c_int, 0)) {
                    var q: c_int = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
                    _ = &q;
                    var p: c_int = q >> @intCast(4);
                    _ = &p;
                    var sixteen: c_int = @intFromBool(p != @as(c_int, 0));
                    _ = &sixteen;
                    var t: c_int = q & @as(c_int, 15);
                    _ = &t;
                    var i: c_int = undefined;
                    _ = &i;
                    if ((p != @as(c_int, 0)) and (p != @as(c_int, 1))) return 0;
                    if (t > @as(c_int, 3)) return 0;
                    {
                        i = 0;
                        while (i < @as(c_int, 64)) : (i += 1) {
                            z.*.dequant[@as(c_uint, @intCast(t))][stbi__jpeg_dezigzag[@as(c_uint, @intCast(i))]] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(if (sixteen != 0) stbi__get16be(z.*.s) else @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))))))));
                        }
                    }
                    L -= if (sixteen != 0) @as(c_int, 129) else @as(c_int, 65);
                }
                return @intFromBool(L == @as(c_int, 0));
            },
            @as(c_int, 196) => {
                L = stbi__get16be(z.*.s) - @as(c_int, 2);
                while (L > @as(c_int, 0)) {
                    var v: [*c]stbi_uc = undefined;
                    _ = &v;
                    var sizes: [16]c_int = undefined;
                    _ = &sizes;
                    var i: c_int = undefined;
                    _ = &i;
                    var n: c_int = 0;
                    _ = &n;
                    var q: c_int = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
                    _ = &q;
                    var tc: c_int = q >> @intCast(4);
                    _ = &tc;
                    var th: c_int = q & @as(c_int, 15);
                    _ = &th;
                    if ((tc > @as(c_int, 1)) or (th > @as(c_int, 3))) return 0;
                    {
                        i = 0;
                        while (i < @as(c_int, 16)) : (i += 1) {
                            sizes[@as(c_uint, @intCast(i))] = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
                            n += sizes[@as(c_uint, @intCast(i))];
                        }
                    }
                    if (n > @as(c_int, 256)) return 0;
                    L -= @as(c_int, 17);
                    if (tc == @as(c_int, 0)) {
                        if (!(stbi__build_huffman(@as([*c]stbi__huffman, @ptrCast(@alignCast(&z.*.huff_dc[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(th)))), @as([*c]c_int, @ptrCast(@alignCast(&sizes[@as(usize, @intCast(0))])))) != 0)) return 0;
                        v = @as([*c]stbi_uc, @ptrCast(@alignCast(&z.*.huff_dc[@as(c_uint, @intCast(th))].values[@as(usize, @intCast(0))])));
                    } else {
                        if (!(stbi__build_huffman(@as([*c]stbi__huffman, @ptrCast(@alignCast(&z.*.huff_ac[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(th)))), @as([*c]c_int, @ptrCast(@alignCast(&sizes[@as(usize, @intCast(0))])))) != 0)) return 0;
                        v = @as([*c]stbi_uc, @ptrCast(@alignCast(&z.*.huff_ac[@as(c_uint, @intCast(th))].values[@as(usize, @intCast(0))])));
                    }
                    {
                        i = 0;
                        while (i < n) : (i += 1) {
                            (blk: {
                                const tmp = i;
                                if (tmp >= 0) break :blk v + @as(usize, @intCast(tmp)) else break :blk v - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).* = stbi__get8(z.*.s);
                        }
                    }
                    if (tc != @as(c_int, 0)) {
                        stbi__build_fast_ac(@as([*c]stbi__int16, @ptrCast(@alignCast(&z.*.fast_ac[@as(c_uint, @intCast(th))][@as(usize, @intCast(0))]))), @as([*c]stbi__huffman, @ptrCast(@alignCast(&z.*.huff_ac[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(th)))));
                    }
                    L -= n;
                }
                return @intFromBool(L == @as(c_int, 0));
            },
            else => {},
        }
        break;
    }
    if (((m >= @as(c_int, 224)) and (m <= @as(c_int, 239))) or (m == @as(c_int, 254))) {
        L = stbi__get16be(z.*.s);
        if (L < @as(c_int, 2)) {
            if (m == @as(c_int, 254)) return 0 else return 0;
        }
        L -= @as(c_int, 2);
        if ((m == @as(c_int, 224)) and (L >= @as(c_int, 5))) {
            const tag = struct {
                const static: [5]u8 = [5]u8{
                    'J',
                    'F',
                    'I',
                    'F',
                    '\x00',
                };
            };
            _ = &tag;
            var ok: c_int = 1;
            _ = &ok;
            var i: c_int = undefined;
            _ = &i;
            {
                i = 0;
                while (i < @as(c_int, 5)) : (i += 1) if (@as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s)))) != @as(c_int, @bitCast(@as(c_uint, tag.static[@as(c_uint, @intCast(i))])))) {
                    ok = 0;
                };
            }
            L -= @as(c_int, 5);
            if (ok != 0) {
                z.*.jfif = 1;
            }
        } else if ((m == @as(c_int, 238)) and (L >= @as(c_int, 12))) {
            const tag = struct {
                const static: [6]u8 = [6]u8{
                    'A',
                    'd',
                    'o',
                    'b',
                    'e',
                    '\x00',
                };
            };
            _ = &tag;
            var ok: c_int = 1;
            _ = &ok;
            var i: c_int = undefined;
            _ = &i;
            {
                i = 0;
                while (i < @as(c_int, 6)) : (i += 1) if (@as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s)))) != @as(c_int, @bitCast(@as(c_uint, tag.static[@as(c_uint, @intCast(i))])))) {
                    ok = 0;
                };
            }
            L -= @as(c_int, 6);
            if (ok != 0) {
                _ = stbi__get8(z.*.s);
                _ = stbi__get16be(z.*.s);
                _ = stbi__get16be(z.*.s);
                z.*.app14_color_transform = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
                L -= @as(c_int, 6);
            }
        }
        stbi__skip(z.*.s, L);
        return 1;
    }
    return 0;
}
pub fn stbi__process_scan_header(arg_z: [*c]stbi__jpeg) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var i: c_int = undefined;
    _ = &i;
    var Ls: c_int = stbi__get16be(z.*.s);
    _ = &Ls;
    z.*.scan_n = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
    if (((z.*.scan_n < @as(c_int, 1)) or (z.*.scan_n > @as(c_int, 4))) or (z.*.scan_n > z.*.s.*.img_n)) return 0;
    if (Ls != (@as(c_int, 6) + (@as(c_int, 2) * z.*.scan_n))) return 0;
    {
        i = 0;
        while (i < z.*.scan_n) : (i += 1) {
            var id: c_int = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
            _ = &id;
            var which: c_int = undefined;
            _ = &which;
            var q: c_int = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
            _ = &q;
            {
                which = 0;
                while (which < z.*.s.*.img_n) : (which += 1) if (z.*.img_comp[@as(c_uint, @intCast(which))].id == id) break;
            }
            if (which == z.*.s.*.img_n) return 0;
            z.*.img_comp[@as(c_uint, @intCast(which))].hd = q >> @intCast(4);
            if (z.*.img_comp[@as(c_uint, @intCast(which))].hd > @as(c_int, 3)) return 0;
            z.*.img_comp[@as(c_uint, @intCast(which))].ha = q & @as(c_int, 15);
            if (z.*.img_comp[@as(c_uint, @intCast(which))].ha > @as(c_int, 3)) return 0;
            z.*.order[@as(c_uint, @intCast(i))] = which;
        }
    }
    {
        var aa: c_int = undefined;
        _ = &aa;
        z.*.spec_start = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
        z.*.spec_end = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
        aa = @as(c_int, @bitCast(@as(c_uint, stbi__get8(z.*.s))));
        z.*.succ_high = aa >> @intCast(4);
        z.*.succ_low = aa & @as(c_int, 15);
        if (z.*.progressive != 0) {
            if (((((z.*.spec_start > @as(c_int, 63)) or (z.*.spec_end > @as(c_int, 63))) or (z.*.spec_start > z.*.spec_end)) or (z.*.succ_high > @as(c_int, 13))) or (z.*.succ_low > @as(c_int, 13))) return 0;
        } else {
            if (z.*.spec_start != @as(c_int, 0)) return 0;
            if ((z.*.succ_high != @as(c_int, 0)) or (z.*.succ_low != @as(c_int, 0))) return 0;
            z.*.spec_end = 63;
        }
    }
    return 1;
}
pub fn stbi__free_jpeg_components(arg_z: [*c]stbi__jpeg, arg_ncomp: c_int, arg_why: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var ncomp = arg_ncomp;
    _ = &ncomp;
    var why = arg_why;
    _ = &why;
    var i: c_int = undefined;
    _ = &i;
    {
        i = 0;
        while (i < ncomp) : (i += 1) {
            if (z.*.img_comp[@as(c_uint, @intCast(i))].raw_data != null) {
                free(z.*.img_comp[@as(c_uint, @intCast(i))].raw_data);
                z.*.img_comp[@as(c_uint, @intCast(i))].raw_data = @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));
                z.*.img_comp[@as(c_uint, @intCast(i))].data = null;
            }
            if (z.*.img_comp[@as(c_uint, @intCast(i))].raw_coeff != null) {
                free(z.*.img_comp[@as(c_uint, @intCast(i))].raw_coeff);
                z.*.img_comp[@as(c_uint, @intCast(i))].raw_coeff = null;
                z.*.img_comp[@as(c_uint, @intCast(i))].coeff = null;
            }
            if (z.*.img_comp[@as(c_uint, @intCast(i))].linebuf != null) {
                free(@as(?*anyopaque, @ptrCast(z.*.img_comp[@as(c_uint, @intCast(i))].linebuf)));
                z.*.img_comp[@as(c_uint, @intCast(i))].linebuf = null;
            }
        }
    }
    return why;
}
pub fn stbi__process_frame_header(arg_z: [*c]stbi__jpeg, arg_scan: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var scan = arg_scan;
    _ = &scan;
    var s: [*c]stbi__context = z.*.s;
    _ = &s;
    var Lf: c_int = undefined;
    _ = &Lf;
    var p: c_int = undefined;
    _ = &p;
    var i: c_int = undefined;
    _ = &i;
    var q: c_int = undefined;
    _ = &q;
    var h_max: c_int = 1;
    _ = &h_max;
    var v_max: c_int = 1;
    _ = &v_max;
    var c: c_int = undefined;
    _ = &c;
    Lf = stbi__get16be(s);
    if (Lf < @as(c_int, 11)) return 0;
    p = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
    if (p != @as(c_int, 8)) return 0;
    s.*.img_y = @as(stbi__uint32, @bitCast(stbi__get16be(s)));
    if (s.*.img_y == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) return 0;
    s.*.img_x = @as(stbi__uint32, @bitCast(stbi__get16be(s)));
    if (s.*.img_x == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) return 0;
    if (s.*.img_y > @as(stbi__uint32, @bitCast(@as(c_int, 1) << @intCast(24)))) return 0;
    if (s.*.img_x > @as(stbi__uint32, @bitCast(@as(c_int, 1) << @intCast(24)))) return 0;
    c = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
    if (((c != @as(c_int, 3)) and (c != @as(c_int, 1))) and (c != @as(c_int, 4))) return 0;
    s.*.img_n = c;
    {
        i = 0;
        while (i < c) : (i += 1) {
            z.*.img_comp[@as(c_uint, @intCast(i))].data = null;
            z.*.img_comp[@as(c_uint, @intCast(i))].linebuf = null;
        }
    }
    if (Lf != (@as(c_int, 8) + (@as(c_int, 3) * s.*.img_n))) return 0;
    z.*.rgb = 0;
    {
        i = 0;
        while (i < s.*.img_n) : (i += 1) {
            const rgb = struct {
                const static: [3]u8 = [3]u8{
                    'R',
                    'G',
                    'B',
                };
            };
            _ = &rgb;
            z.*.img_comp[@as(c_uint, @intCast(i))].id = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
            if ((s.*.img_n == @as(c_int, 3)) and (z.*.img_comp[@as(c_uint, @intCast(i))].id == @as(c_int, @bitCast(@as(c_uint, rgb.static[@as(c_uint, @intCast(i))]))))) {
                z.*.rgb += 1;
            }
            q = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
            z.*.img_comp[@as(c_uint, @intCast(i))].h = q >> @intCast(4);
            if (!(z.*.img_comp[@as(c_uint, @intCast(i))].h != 0) or (z.*.img_comp[@as(c_uint, @intCast(i))].h > @as(c_int, 4))) return 0;
            z.*.img_comp[@as(c_uint, @intCast(i))].v = q & @as(c_int, 15);
            if (!(z.*.img_comp[@as(c_uint, @intCast(i))].v != 0) or (z.*.img_comp[@as(c_uint, @intCast(i))].v > @as(c_int, 4))) return 0;
            z.*.img_comp[@as(c_uint, @intCast(i))].tq = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
            if (z.*.img_comp[@as(c_uint, @intCast(i))].tq > @as(c_int, 3)) return 0;
        }
    }
    if (scan != STBI__SCAN_load) return 1;
    if (!(stbi__mad3sizes_valid(@as(c_int, @bitCast(s.*.img_x)), @as(c_int, @bitCast(s.*.img_y)), s.*.img_n, @as(c_int, 0)) != 0)) return 0;
    {
        i = 0;
        while (i < s.*.img_n) : (i += 1) {
            if (z.*.img_comp[@as(c_uint, @intCast(i))].h > h_max) {
                h_max = z.*.img_comp[@as(c_uint, @intCast(i))].h;
            }
            if (z.*.img_comp[@as(c_uint, @intCast(i))].v > v_max) {
                v_max = z.*.img_comp[@as(c_uint, @intCast(i))].v;
            }
        }
    }
    {
        i = 0;
        while (i < s.*.img_n) : (i += 1) {
            if (@import("std").zig.c_translation.signedRemainder(h_max, z.*.img_comp[@as(c_uint, @intCast(i))].h) != @as(c_int, 0)) return 0;
            if (@import("std").zig.c_translation.signedRemainder(v_max, z.*.img_comp[@as(c_uint, @intCast(i))].v) != @as(c_int, 0)) return 0;
        }
    }
    z.*.img_h_max = h_max;
    z.*.img_v_max = v_max;
    z.*.img_mcu_w = h_max * @as(c_int, 8);
    z.*.img_mcu_h = v_max * @as(c_int, 8);
    z.*.img_mcu_x = @as(c_int, @bitCast(((s.*.img_x +% @as(stbi__uint32, @bitCast(z.*.img_mcu_w))) -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))) / @as(stbi__uint32, @bitCast(z.*.img_mcu_w))));
    z.*.img_mcu_y = @as(c_int, @bitCast(((s.*.img_y +% @as(stbi__uint32, @bitCast(z.*.img_mcu_h))) -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))) / @as(stbi__uint32, @bitCast(z.*.img_mcu_h))));
    {
        i = 0;
        while (i < s.*.img_n) : (i += 1) {
            z.*.img_comp[@as(c_uint, @intCast(i))].x = @as(c_int, @bitCast((((s.*.img_x *% @as(stbi__uint32, @bitCast(z.*.img_comp[@as(c_uint, @intCast(i))].h))) +% @as(stbi__uint32, @bitCast(h_max))) -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))) / @as(stbi__uint32, @bitCast(h_max))));
            z.*.img_comp[@as(c_uint, @intCast(i))].y = @as(c_int, @bitCast((((s.*.img_y *% @as(stbi__uint32, @bitCast(z.*.img_comp[@as(c_uint, @intCast(i))].v))) +% @as(stbi__uint32, @bitCast(v_max))) -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))) / @as(stbi__uint32, @bitCast(v_max))));
            z.*.img_comp[@as(c_uint, @intCast(i))].w2 = (z.*.img_mcu_x * z.*.img_comp[@as(c_uint, @intCast(i))].h) * @as(c_int, 8);
            z.*.img_comp[@as(c_uint, @intCast(i))].h2 = (z.*.img_mcu_y * z.*.img_comp[@as(c_uint, @intCast(i))].v) * @as(c_int, 8);
            z.*.img_comp[@as(c_uint, @intCast(i))].coeff = null;
            z.*.img_comp[@as(c_uint, @intCast(i))].raw_coeff = null;
            z.*.img_comp[@as(c_uint, @intCast(i))].linebuf = null;
            z.*.img_comp[@as(c_uint, @intCast(i))].raw_data = stbi__malloc_mad2(z.*.img_comp[@as(c_uint, @intCast(i))].w2, z.*.img_comp[@as(c_uint, @intCast(i))].h2, @as(c_int, 15));
            if (z.*.img_comp[@as(c_uint, @intCast(i))].raw_data == @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))) return stbi__free_jpeg_components(z, i + @as(c_int, 1), @as(c_int, 0));
            z.*.img_comp[@as(c_uint, @intCast(i))].data = @as([*c]stbi_uc, @ptrFromInt((@as(usize, @intCast(@intFromPtr(z.*.img_comp[@as(c_uint, @intCast(i))].raw_data))) +% @as(usize, @bitCast(@as(c_long, @as(c_int, 15))))) & @as(usize, @bitCast(@as(c_long, ~@as(c_int, 15))))));
            if (z.*.progressive != 0) {
                z.*.img_comp[@as(c_uint, @intCast(i))].coeff_w = @divTrunc(z.*.img_comp[@as(c_uint, @intCast(i))].w2, @as(c_int, 8));
                z.*.img_comp[@as(c_uint, @intCast(i))].coeff_h = @divTrunc(z.*.img_comp[@as(c_uint, @intCast(i))].h2, @as(c_int, 8));
                z.*.img_comp[@as(c_uint, @intCast(i))].raw_coeff = stbi__malloc_mad3(z.*.img_comp[@as(c_uint, @intCast(i))].w2, z.*.img_comp[@as(c_uint, @intCast(i))].h2, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(c_short))))), @as(c_int, 15));
                if (z.*.img_comp[@as(c_uint, @intCast(i))].raw_coeff == @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))) return stbi__free_jpeg_components(z, i + @as(c_int, 1), @as(c_int, 0));
                z.*.img_comp[@as(c_uint, @intCast(i))].coeff = @as([*c]c_short, @ptrFromInt((@as(usize, @intCast(@intFromPtr(z.*.img_comp[@as(c_uint, @intCast(i))].raw_coeff))) +% @as(usize, @bitCast(@as(c_long, @as(c_int, 15))))) & @as(usize, @bitCast(@as(c_long, ~@as(c_int, 15))))));
            }
        }
    }
    return 1;
}
pub fn stbi__decode_jpeg_header(arg_z: [*c]stbi__jpeg, arg_scan: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var scan = arg_scan;
    _ = &scan;
    var m: c_int = undefined;
    _ = &m;
    z.*.jfif = 0;
    z.*.app14_color_transform = -@as(c_int, 1);
    z.*.marker = 255;
    m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(z))));
    if (!(m == @as(c_int, 216))) return 0;
    if (scan == STBI__SCAN_type) return 1;
    m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(z))));
    while (!(((m == @as(c_int, 192)) or (m == @as(c_int, 193))) or (m == @as(c_int, 194)))) {
        if (!(stbi__process_marker(z, m) != 0)) return 0;
        m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(z))));
        while (m == @as(c_int, 255)) {
            if (stbi__at_eof(z.*.s) != 0) return 0;
            m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(z))));
        }
    }
    z.*.progressive = @intFromBool(m == @as(c_int, 194));
    if (!(stbi__process_frame_header(z, scan) != 0)) return 0;
    return 1;
}
pub fn stbi__skip_jpeg_junk_at_end(arg_j: [*c]stbi__jpeg) callconv(.c) stbi_uc {
    var j = arg_j;
    _ = &j;
    while (!(stbi__at_eof(j.*.s) != 0)) {
        var x: stbi_uc = stbi__get8(j.*.s);
        _ = &x;
        while (@as(c_int, @bitCast(@as(c_uint, x))) == @as(c_int, 255)) {
            if (stbi__at_eof(j.*.s) != 0) return 255;
            x = stbi__get8(j.*.s);
            if ((@as(c_int, @bitCast(@as(c_uint, x))) != @as(c_int, 0)) and (@as(c_int, @bitCast(@as(c_uint, x))) != @as(c_int, 255))) {
                return x;
            }
        }
    }
    return 255;
}
pub fn stbi__decode_jpeg_image(arg_j: [*c]stbi__jpeg) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var m: c_int = undefined;
    _ = &m;
    {
        m = 0;
        while (m < @as(c_int, 4)) : (m += 1) {
            j.*.img_comp[@as(c_uint, @intCast(m))].raw_data = @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));
            j.*.img_comp[@as(c_uint, @intCast(m))].raw_coeff = @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));
        }
    }
    j.*.restart_interval = 0;
    if (!(stbi__decode_jpeg_header(j, STBI__SCAN_load) != 0)) return 0;
    m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(j))));
    while (!(m == @as(c_int, 217))) {
        if (m == @as(c_int, 218)) {
            if (!(stbi__process_scan_header(j) != 0)) return 0;
            if (!(stbi__parse_entropy_coded_data(j) != 0)) return 0;
            if (@as(c_int, @bitCast(@as(c_uint, j.*.marker))) == @as(c_int, 255)) {
                j.*.marker = stbi__skip_jpeg_junk_at_end(j);
            }
            m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(j))));
            if ((m >= @as(c_int, 208)) and (m <= @as(c_int, 215))) {
                m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(j))));
            }
        } else if (m == @as(c_int, 220)) {
            var Ld: c_int = stbi__get16be(j.*.s);
            _ = &Ld;
            var NL: stbi__uint32 = @as(stbi__uint32, @bitCast(stbi__get16be(j.*.s)));
            _ = &NL;
            if (Ld != @as(c_int, 4)) return 0;
            if (NL != j.*.s.*.img_y) return 0;
            m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(j))));
        } else {
            if (!(stbi__process_marker(j, m) != 0)) return 1;
            m = @as(c_int, @bitCast(@as(c_uint, stbi__get_marker(j))));
        }
    }
    if (j.*.progressive != 0) {
        stbi__jpeg_finish(j);
    }
    return 1;
}
pub const resample_row_func = ?*const fn ([*c]stbi_uc, [*c]stbi_uc, [*c]stbi_uc, c_int, c_int) callconv(.c) [*c]stbi_uc;
pub fn resample_row_1(arg_out: [*c]stbi_uc, arg_in_near: [*c]stbi_uc, arg_in_far: [*c]stbi_uc, arg_w: c_int, arg_hs: c_int) callconv(.c) [*c]stbi_uc {
    var out = arg_out;
    _ = &out;
    var in_near = arg_in_near;
    _ = &in_near;
    var in_far = arg_in_far;
    _ = &in_far;
    var w = arg_w;
    _ = &w;
    var hs = arg_hs;
    _ = &hs;
    _ = @sizeOf([*c]stbi_uc);
    _ = @sizeOf([*c]stbi_uc);
    _ = @sizeOf(c_int);
    _ = @sizeOf(c_int);
    return in_near;
}
pub fn stbi__resample_row_v_2(arg_out: [*c]stbi_uc, arg_in_near: [*c]stbi_uc, arg_in_far: [*c]stbi_uc, arg_w: c_int, arg_hs: c_int) callconv(.c) [*c]stbi_uc {
    var out = arg_out;
    _ = &out;
    var in_near = arg_in_near;
    _ = &in_near;
    var in_far = arg_in_far;
    _ = &in_far;
    var w = arg_w;
    _ = &w;
    var hs = arg_hs;
    _ = &hs;
    var i: c_int = undefined;
    _ = &i;
    _ = @sizeOf(c_int);
    {
        i = 0;
        while (i < w) : (i += 1) {
            (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((((@as(c_int, 3) * @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk in_near + @as(usize, @intCast(tmp)) else break :blk in_near - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))) + @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk in_far + @as(usize, @intCast(tmp)) else break :blk in_far - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))) + @as(c_int, 2)) >> @intCast(2)))));
        }
    }
    return out;
}
pub fn stbi__resample_row_h_2(arg_out: [*c]stbi_uc, arg_in_near: [*c]stbi_uc, arg_in_far: [*c]stbi_uc, arg_w: c_int, arg_hs: c_int) callconv(.c) [*c]stbi_uc {
    var out = arg_out;
    _ = &out;
    var in_near = arg_in_near;
    _ = &in_near;
    var in_far = arg_in_far;
    _ = &in_far;
    var w = arg_w;
    _ = &w;
    var hs = arg_hs;
    _ = &hs;
    var i: c_int = undefined;
    _ = &i;
    var input: [*c]stbi_uc = in_near;
    _ = &input;
    if (w == @as(c_int, 1)) {
        out[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
            const tmp = input[@as(c_uint, @intCast(@as(c_int, 0)))];
            out[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
            break :blk tmp;
        };
        return out;
    }
    out[@as(c_uint, @intCast(@as(c_int, 0)))] = input[@as(c_uint, @intCast(@as(c_int, 0)))];
    out[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate((((@as(c_int, @bitCast(@as(c_uint, input[@as(c_uint, @intCast(@as(c_int, 0)))]))) * @as(c_int, 3)) + @as(c_int, @bitCast(@as(c_uint, input[@as(c_uint, @intCast(@as(c_int, 1)))])))) + @as(c_int, 2)) >> @intCast(2)))));
    {
        i = 1;
        while (i < (w - @as(c_int, 1))) : (i += 1) {
            var n: c_int = (@as(c_int, 3) * @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk input + @as(usize, @intCast(tmp)) else break :blk input - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))) + @as(c_int, 2);
            _ = &n;
            (blk: {
                const tmp = (i * @as(c_int, 2)) + @as(c_int, 0);
                if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((n + @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i - @as(c_int, 1);
                if (tmp >= 0) break :blk input + @as(usize, @intCast(tmp)) else break :blk input - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))) >> @intCast(2)))));
            (blk: {
                const tmp = (i * @as(c_int, 2)) + @as(c_int, 1);
                if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((n + @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i + @as(c_int, 1);
                if (tmp >= 0) break :blk input + @as(usize, @intCast(tmp)) else break :blk input - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))) >> @intCast(2)))));
        }
    }
    (blk: {
        const tmp = (i * @as(c_int, 2)) + @as(c_int, 0);
        if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((((@as(c_int, @bitCast(@as(c_uint, (blk: {
        const tmp = w - @as(c_int, 2);
        if (tmp >= 0) break :blk input + @as(usize, @intCast(tmp)) else break :blk input - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*))) * @as(c_int, 3)) + @as(c_int, @bitCast(@as(c_uint, (blk: {
        const tmp = w - @as(c_int, 1);
        if (tmp >= 0) break :blk input + @as(usize, @intCast(tmp)) else break :blk input - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*)))) + @as(c_int, 2)) >> @intCast(2)))));
    (blk: {
        const tmp = (i * @as(c_int, 2)) + @as(c_int, 1);
        if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).* = (blk: {
        const tmp = w - @as(c_int, 1);
        if (tmp >= 0) break :blk input + @as(usize, @intCast(tmp)) else break :blk input - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*;
    _ = @sizeOf([*c]stbi_uc);
    _ = @sizeOf(c_int);
    return out;
}
pub fn stbi__resample_row_hv_2(arg_out: [*c]stbi_uc, arg_in_near: [*c]stbi_uc, arg_in_far: [*c]stbi_uc, arg_w: c_int, arg_hs: c_int) callconv(.c) [*c]stbi_uc {
    var out = arg_out;
    _ = &out;
    var in_near = arg_in_near;
    _ = &in_near;
    var in_far = arg_in_far;
    _ = &in_far;
    var w = arg_w;
    _ = &w;
    var hs = arg_hs;
    _ = &hs;
    var i: c_int = undefined;
    _ = &i;
    var t0: c_int = undefined;
    _ = &t0;
    var t1: c_int = undefined;
    _ = &t1;
    if (w == @as(c_int, 1)) {
        out[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
            const tmp = @as(stbi_uc, @bitCast(@as(i8, @truncate((((@as(c_int, 3) * @as(c_int, @bitCast(@as(c_uint, in_near[@as(c_uint, @intCast(@as(c_int, 0)))])))) + @as(c_int, @bitCast(@as(c_uint, in_far[@as(c_uint, @intCast(@as(c_int, 0)))])))) + @as(c_int, 2)) >> @intCast(2)))));
            out[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
            break :blk tmp;
        };
        return out;
    }
    t1 = (@as(c_int, 3) * @as(c_int, @bitCast(@as(c_uint, in_near[@as(c_uint, @intCast(@as(c_int, 0)))])))) + @as(c_int, @bitCast(@as(c_uint, in_far[@as(c_uint, @intCast(@as(c_int, 0)))])));
    out[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate((t1 + @as(c_int, 2)) >> @intCast(2)))));
    {
        i = 1;
        while (i < w) : (i += 1) {
            t0 = t1;
            t1 = (@as(c_int, 3) * @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk in_near + @as(usize, @intCast(tmp)) else break :blk in_near - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)))) + @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk in_far + @as(usize, @intCast(tmp)) else break :blk in_far - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)));
            (blk: {
                const tmp = (i * @as(c_int, 2)) - @as(c_int, 1);
                if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((((@as(c_int, 3) * t0) + t1) + @as(c_int, 8)) >> @intCast(4)))));
            (blk: {
                const tmp = i * @as(c_int, 2);
                if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((((@as(c_int, 3) * t1) + t0) + @as(c_int, 8)) >> @intCast(4)))));
        }
    }
    (blk: {
        const tmp = (w * @as(c_int, 2)) - @as(c_int, 1);
        if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((t1 + @as(c_int, 2)) >> @intCast(2)))));
    _ = @sizeOf(c_int);
    return out;
}
pub fn stbi__resample_row_generic(arg_out: [*c]stbi_uc, arg_in_near: [*c]stbi_uc, arg_in_far: [*c]stbi_uc, arg_w: c_int, arg_hs: c_int) callconv(.c) [*c]stbi_uc {
    var out = arg_out;
    _ = &out;
    var in_near = arg_in_near;
    _ = &in_near;
    var in_far = arg_in_far;
    _ = &in_far;
    var w = arg_w;
    _ = &w;
    var hs = arg_hs;
    _ = &hs;
    var i: c_int = undefined;
    _ = &i;
    var j: c_int = undefined;
    _ = &j;
    _ = @sizeOf([*c]stbi_uc);
    {
        i = 0;
        while (i < w) : (i += 1) {
            j = 0;
            while (j < hs) : (j += 1) {
                (blk: {
                    const tmp = (i * hs) + j;
                    if (tmp >= 0) break :blk out + @as(usize, @intCast(tmp)) else break :blk out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = (blk: {
                    const tmp = i;
                    if (tmp >= 0) break :blk in_near + @as(usize, @intCast(tmp)) else break :blk in_near - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
            }
        }
    }
    return out;
}
pub fn stbi__YCbCr_to_RGB_row(arg_out: [*c]stbi_uc, arg_y: [*c]const stbi_uc, arg_pcb: [*c]const stbi_uc, arg_pcr: [*c]const stbi_uc, arg_count: c_int, arg_step: c_int) callconv(.c) void {
    var out = arg_out;
    _ = &out;
    var y = arg_y;
    _ = &y;
    var pcb = arg_pcb;
    _ = &pcb;
    var pcr = arg_pcr;
    _ = &pcr;
    var count = arg_count;
    _ = &count;
    var step = arg_step;
    _ = &step;
    var i: c_int = undefined;
    _ = &i;
    {
        i = 0;
        while (i < count) : (i += 1) {
            var y_fixed: c_int = (@as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk y + @as(usize, @intCast(tmp)) else break :blk y - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))) << @intCast(20)) + (@as(c_int, 1) << @intCast(19));
            _ = &y_fixed;
            var r: c_int = undefined;
            _ = &r;
            var g: c_int = undefined;
            _ = &g;
            var b: c_int = undefined;
            _ = &b;
            var cr: c_int = @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk pcr + @as(usize, @intCast(tmp)) else break :blk pcr - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))) - @as(c_int, 128);
            _ = &cr;
            var cb: c_int = @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk pcb + @as(usize, @intCast(tmp)) else break :blk pcb - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))) - @as(c_int, 128);
            _ = &cb;
            r = y_fixed + (cr * (@as(c_int, @intFromFloat((1.4019999504089355 * 4096.0) + 0.5)) << @intCast(8)));
            g = @as(c_int, @bitCast(@as(c_uint, @bitCast(y_fixed + (cr * -(@as(c_int, @intFromFloat((0.714139997959137 * 4096.0) + 0.5)) << @intCast(8))))) +% (@as(c_uint, @bitCast(cb * -(@as(c_int, @intFromFloat((0.3441399931907654 * 4096.0) + 0.5)) << @intCast(8)))) & @as(c_uint, 4294901760))));
            b = y_fixed + (cb * (@as(c_int, @intFromFloat((1.7719999551773071 * 4096.0) + 0.5)) << @intCast(8)));
            r >>= @intCast(@as(c_int, 20));
            g >>= @intCast(@as(c_int, 20));
            b >>= @intCast(@as(c_int, 20));
            if (@as(c_uint, @bitCast(r)) > @as(c_uint, @bitCast(@as(c_int, 255)))) {
                if (r < @as(c_int, 0)) {
                    r = 0;
                } else {
                    r = 255;
                }
            }
            if (@as(c_uint, @bitCast(g)) > @as(c_uint, @bitCast(@as(c_int, 255)))) {
                if (g < @as(c_int, 0)) {
                    g = 0;
                } else {
                    g = 255;
                }
            }
            if (@as(c_uint, @bitCast(b)) > @as(c_uint, @bitCast(@as(c_int, 255)))) {
                if (b < @as(c_int, 0)) {
                    b = 0;
                } else {
                    b = 255;
                }
            }
            out[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(r))));
            out[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(g))));
            out[@as(c_uint, @intCast(@as(c_int, 2)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(b))));
            out[@as(c_uint, @intCast(@as(c_int, 3)))] = 255;
            out += @as(usize, @bitCast(@as(isize, @intCast(step))));
        }
    }
}
pub fn stbi__setup_jpeg(arg_j: [*c]stbi__jpeg) callconv(.c) void {
    var j = arg_j;
    _ = &j;
    j.*.idct_block_kernel = &stbi__idct_block;
    j.*.YCbCr_to_RGB_kernel = &stbi__YCbCr_to_RGB_row;
    j.*.resample_row_hv_2_kernel = &stbi__resample_row_hv_2;
}
pub fn stbi__cleanup_jpeg(arg_j: [*c]stbi__jpeg) callconv(.c) void {
    var j = arg_j;
    _ = &j;
    _ = stbi__free_jpeg_components(j, j.*.s.*.img_n, @as(c_int, 0));
}
pub const stbi__resample = extern struct {
    resample: resample_row_func = @import("std").mem.zeroes(resample_row_func),
    line0: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    line1: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    hs: c_int = @import("std").mem.zeroes(c_int),
    vs: c_int = @import("std").mem.zeroes(c_int),
    w_lores: c_int = @import("std").mem.zeroes(c_int),
    ystep: c_int = @import("std").mem.zeroes(c_int),
    ypos: c_int = @import("std").mem.zeroes(c_int),
};
pub fn stbi__blinn_8x8(arg_x: stbi_uc, arg_y: stbi_uc) callconv(.c) stbi_uc {
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var t: c_uint = @as(c_uint, @bitCast((@as(c_int, @bitCast(@as(c_uint, x))) * @as(c_int, @bitCast(@as(c_uint, y)))) + @as(c_int, 128)));
    _ = &t;
    return @as(stbi_uc, @bitCast(@as(u8, @truncate((t +% (t >> @intCast(8))) >> @intCast(8)))));
}
pub fn load_jpeg_image(arg_z: [*c]stbi__jpeg, arg_out_x: [*c]c_int, arg_out_y: [*c]c_int, arg_comp: [*c]c_int, arg_req_comp: c_int) callconv(.c) [*c]stbi_uc {
    var z = arg_z;
    _ = &z;
    var out_x = arg_out_x;
    _ = &out_x;
    var out_y = arg_out_y;
    _ = &out_y;
    var comp = arg_comp;
    _ = &comp;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var n: c_int = undefined;
    _ = &n;
    var decode_n: c_int = undefined;
    _ = &decode_n;
    var is_rgb: c_int = undefined;
    _ = &is_rgb;
    z.*.s.*.img_n = 0;
    if ((req_comp < @as(c_int, 0)) or (req_comp > @as(c_int, 4))) return @as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
    if (!(stbi__decode_jpeg_image(z) != 0)) {
        stbi__cleanup_jpeg(z);
        return null;
    }
    n = if (req_comp != 0) req_comp else if (z.*.s.*.img_n >= @as(c_int, 3)) @as(c_int, 3) else @as(c_int, 1);
    is_rgb = @intFromBool((z.*.s.*.img_n == @as(c_int, 3)) and ((z.*.rgb == @as(c_int, 3)) or ((z.*.app14_color_transform == @as(c_int, 0)) and !(z.*.jfif != 0))));
    if (((z.*.s.*.img_n == @as(c_int, 3)) and (n < @as(c_int, 3))) and !(is_rgb != 0)) {
        decode_n = 1;
    } else {
        decode_n = z.*.s.*.img_n;
    }
    if (decode_n <= @as(c_int, 0)) {
        stbi__cleanup_jpeg(z);
        return null;
    }
    {
        var k: c_int = undefined;
        _ = &k;
        var i: c_uint = undefined;
        _ = &i;
        var j: c_uint = undefined;
        _ = &j;
        var output: [*c]stbi_uc = undefined;
        _ = &output;
        var coutput: [4][*c]stbi_uc = [4][*c]stbi_uc{
            null,
            null,
            null,
            null,
        };
        _ = &coutput;
        var res_comp: [4]stbi__resample = undefined;
        _ = &res_comp;
        {
            k = 0;
            while (k < decode_n) : (k += 1) {
                var r: [*c]stbi__resample = &res_comp[@as(c_uint, @intCast(k))];
                _ = &r;
                z.*.img_comp[@as(c_uint, @intCast(k))].linebuf = @as([*c]stbi_uc, @ptrCast(@alignCast(stbi__malloc(@as(usize, @bitCast(@as(c_ulong, z.*.s.*.img_x +% @as(stbi__uint32, @bitCast(@as(c_int, 3))))))))));
                if (!(z.*.img_comp[@as(c_uint, @intCast(k))].linebuf != null)) {
                    stbi__cleanup_jpeg(z);
                    return @as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
                }
                r.*.hs = @divTrunc(z.*.img_h_max, z.*.img_comp[@as(c_uint, @intCast(k))].h);
                r.*.vs = @divTrunc(z.*.img_v_max, z.*.img_comp[@as(c_uint, @intCast(k))].v);
                r.*.ystep = r.*.vs >> @intCast(1);
                r.*.w_lores = @as(c_int, @bitCast(((z.*.s.*.img_x +% @as(stbi__uint32, @bitCast(r.*.hs))) -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))) / @as(stbi__uint32, @bitCast(r.*.hs))));
                r.*.ypos = 0;
                r.*.line0 = blk: {
                    const tmp = z.*.img_comp[@as(c_uint, @intCast(k))].data;
                    r.*.line1 = tmp;
                    break :blk tmp;
                };
                if ((r.*.hs == @as(c_int, 1)) and (r.*.vs == @as(c_int, 1))) {
                    r.*.resample = &resample_row_1;
                } else if ((r.*.hs == @as(c_int, 1)) and (r.*.vs == @as(c_int, 2))) {
                    r.*.resample = &stbi__resample_row_v_2;
                } else if ((r.*.hs == @as(c_int, 2)) and (r.*.vs == @as(c_int, 1))) {
                    r.*.resample = &stbi__resample_row_h_2;
                } else if ((r.*.hs == @as(c_int, 2)) and (r.*.vs == @as(c_int, 2))) {
                    r.*.resample = z.*.resample_row_hv_2_kernel;
                } else {
                    r.*.resample = &stbi__resample_row_generic;
                }
            }
        }
        output = @as([*c]stbi_uc, @ptrCast(@alignCast(stbi__malloc_mad3(n, @as(c_int, @bitCast(z.*.s.*.img_x)), @as(c_int, @bitCast(z.*.s.*.img_y)), @as(c_int, 1)))));
        if (!(output != null)) {
            stbi__cleanup_jpeg(z);
            return @as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))));
        }
        {
            j = 0;
            while (j < z.*.s.*.img_y) : (j +%= 1) {
                var out: [*c]stbi_uc = output + ((@as(stbi__uint32, @bitCast(n)) *% z.*.s.*.img_x) *% j);
                _ = &out;
                {
                    k = 0;
                    while (k < decode_n) : (k += 1) {
                        var r: [*c]stbi__resample = &res_comp[@as(c_uint, @intCast(k))];
                        _ = &r;
                        var y_bot: c_int = @intFromBool(r.*.ystep >= (r.*.vs >> @intCast(1)));
                        _ = &y_bot;
                        coutput[@as(c_uint, @intCast(k))] = r.*.resample.?(z.*.img_comp[@as(c_uint, @intCast(k))].linebuf, if (y_bot != 0) r.*.line1 else r.*.line0, if (y_bot != 0) r.*.line0 else r.*.line1, r.*.w_lores, r.*.hs);
                        if ((blk: {
                            const ref = &r.*.ystep;
                            ref.* += 1;
                            break :blk ref.*;
                        }) >= r.*.vs) {
                            r.*.ystep = 0;
                            r.*.line0 = r.*.line1;
                            if ((blk: {
                                const ref = &r.*.ypos;
                                ref.* += 1;
                                break :blk ref.*;
                            }) < z.*.img_comp[@as(c_uint, @intCast(k))].y) {
                                r.*.line1 += @as(usize, @bitCast(@as(isize, @intCast(z.*.img_comp[@as(c_uint, @intCast(k))].w2))));
                            }
                        }
                    }
                }
                if (n >= @as(c_int, 3)) {
                    var y: [*c]stbi_uc = coutput[@as(c_uint, @intCast(@as(c_int, 0)))];
                    _ = &y;
                    if (z.*.s.*.img_n == @as(c_int, 3)) {
                        if (is_rgb != 0) {
                            {
                                i = 0;
                                while (i < z.*.s.*.img_x) : (i +%= 1) {
                                    out[@as(c_uint, @intCast(@as(c_int, 0)))] = y[i];
                                    out[@as(c_uint, @intCast(@as(c_int, 1)))] = coutput[@as(c_uint, @intCast(@as(c_int, 1)))][i];
                                    out[@as(c_uint, @intCast(@as(c_int, 2)))] = coutput[@as(c_uint, @intCast(@as(c_int, 2)))][i];
                                    out[@as(c_uint, @intCast(@as(c_int, 3)))] = 255;
                                    out += @as(usize, @bitCast(@as(isize, @intCast(n))));
                                }
                            }
                        } else {
                            z.*.YCbCr_to_RGB_kernel.?(out, y, coutput[@as(c_uint, @intCast(@as(c_int, 1)))], coutput[@as(c_uint, @intCast(@as(c_int, 2)))], @as(c_int, @bitCast(z.*.s.*.img_x)), n);
                        }
                    } else if (z.*.s.*.img_n == @as(c_int, 4)) {
                        if (z.*.app14_color_transform == @as(c_int, 0)) {
                            {
                                i = 0;
                                while (i < z.*.s.*.img_x) : (i +%= 1) {
                                    var m: stbi_uc = coutput[@as(c_uint, @intCast(@as(c_int, 3)))][i];
                                    _ = &m;
                                    out[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__blinn_8x8(coutput[@as(c_uint, @intCast(@as(c_int, 0)))][i], m);
                                    out[@as(c_uint, @intCast(@as(c_int, 1)))] = stbi__blinn_8x8(coutput[@as(c_uint, @intCast(@as(c_int, 1)))][i], m);
                                    out[@as(c_uint, @intCast(@as(c_int, 2)))] = stbi__blinn_8x8(coutput[@as(c_uint, @intCast(@as(c_int, 2)))][i], m);
                                    out[@as(c_uint, @intCast(@as(c_int, 3)))] = 255;
                                    out += @as(usize, @bitCast(@as(isize, @intCast(n))));
                                }
                            }
                        } else if (z.*.app14_color_transform == @as(c_int, 2)) {
                            z.*.YCbCr_to_RGB_kernel.?(out, y, coutput[@as(c_uint, @intCast(@as(c_int, 1)))], coutput[@as(c_uint, @intCast(@as(c_int, 2)))], @as(c_int, @bitCast(z.*.s.*.img_x)), n);
                            {
                                i = 0;
                                while (i < z.*.s.*.img_x) : (i +%= 1) {
                                    var m: stbi_uc = coutput[@as(c_uint, @intCast(@as(c_int, 3)))][i];
                                    _ = &m;
                                    out[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__blinn_8x8(@as(stbi_uc, @bitCast(@as(i8, @truncate(@as(c_int, 255) - @as(c_int, @bitCast(@as(c_uint, out[@as(c_uint, @intCast(@as(c_int, 0)))]))))))), m);
                                    out[@as(c_uint, @intCast(@as(c_int, 1)))] = stbi__blinn_8x8(@as(stbi_uc, @bitCast(@as(i8, @truncate(@as(c_int, 255) - @as(c_int, @bitCast(@as(c_uint, out[@as(c_uint, @intCast(@as(c_int, 1)))]))))))), m);
                                    out[@as(c_uint, @intCast(@as(c_int, 2)))] = stbi__blinn_8x8(@as(stbi_uc, @bitCast(@as(i8, @truncate(@as(c_int, 255) - @as(c_int, @bitCast(@as(c_uint, out[@as(c_uint, @intCast(@as(c_int, 2)))]))))))), m);
                                    out += @as(usize, @bitCast(@as(isize, @intCast(n))));
                                }
                            }
                        } else {
                            z.*.YCbCr_to_RGB_kernel.?(out, y, coutput[@as(c_uint, @intCast(@as(c_int, 1)))], coutput[@as(c_uint, @intCast(@as(c_int, 2)))], @as(c_int, @bitCast(z.*.s.*.img_x)), n);
                        }
                    } else {
                        i = 0;
                        while (i < z.*.s.*.img_x) : (i +%= 1) {
                            out[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                const tmp = blk_1: {
                                    const tmp_2 = y[i];
                                    out[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                    break :blk_1 tmp_2;
                                };
                                out[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                break :blk tmp;
                            };
                            out[@as(c_uint, @intCast(@as(c_int, 3)))] = 255;
                            out += @as(usize, @bitCast(@as(isize, @intCast(n))));
                        }
                    }
                } else {
                    if (is_rgb != 0) {
                        if (n == @as(c_int, 1)) {
                            {
                                i = 0;
                                while (i < z.*.s.*.img_x) : (i +%= 1) {
                                    (blk: {
                                        const ref = &out;
                                        const tmp = ref.*;
                                        ref.* += 1;
                                        break :blk tmp;
                                    }).* = stbi__compute_y(@as(c_int, @bitCast(@as(c_uint, coutput[@as(c_uint, @intCast(@as(c_int, 0)))][i]))), @as(c_int, @bitCast(@as(c_uint, coutput[@as(c_uint, @intCast(@as(c_int, 1)))][i]))), @as(c_int, @bitCast(@as(c_uint, coutput[@as(c_uint, @intCast(@as(c_int, 2)))][i]))));
                                }
                            }
                        } else {
                            {
                                i = 0;
                                while (i < z.*.s.*.img_x) : (_ = blk: {
                                    i +%= 1;
                                    break :blk blk_1: {
                                        const ref = &out;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                        break :blk_1 ref.*;
                                    };
                                }) {
                                    out[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y(@as(c_int, @bitCast(@as(c_uint, coutput[@as(c_uint, @intCast(@as(c_int, 0)))][i]))), @as(c_int, @bitCast(@as(c_uint, coutput[@as(c_uint, @intCast(@as(c_int, 1)))][i]))), @as(c_int, @bitCast(@as(c_uint, coutput[@as(c_uint, @intCast(@as(c_int, 2)))][i]))));
                                    out[@as(c_uint, @intCast(@as(c_int, 1)))] = 255;
                                }
                            }
                        }
                    } else if ((z.*.s.*.img_n == @as(c_int, 4)) and (z.*.app14_color_transform == @as(c_int, 0))) {
                        {
                            i = 0;
                            while (i < z.*.s.*.img_x) : (i +%= 1) {
                                var m: stbi_uc = coutput[@as(c_uint, @intCast(@as(c_int, 3)))][i];
                                _ = &m;
                                var r: stbi_uc = stbi__blinn_8x8(coutput[@as(c_uint, @intCast(@as(c_int, 0)))][i], m);
                                _ = &r;
                                var g: stbi_uc = stbi__blinn_8x8(coutput[@as(c_uint, @intCast(@as(c_int, 1)))][i], m);
                                _ = &g;
                                var b: stbi_uc = stbi__blinn_8x8(coutput[@as(c_uint, @intCast(@as(c_int, 2)))][i], m);
                                _ = &b;
                                out[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__compute_y(@as(c_int, @bitCast(@as(c_uint, r))), @as(c_int, @bitCast(@as(c_uint, g))), @as(c_int, @bitCast(@as(c_uint, b))));
                                out[@as(c_uint, @intCast(@as(c_int, 1)))] = 255;
                                out += @as(usize, @bitCast(@as(isize, @intCast(n))));
                            }
                        }
                    } else if ((z.*.s.*.img_n == @as(c_int, 4)) and (z.*.app14_color_transform == @as(c_int, 2))) {
                        {
                            i = 0;
                            while (i < z.*.s.*.img_x) : (i +%= 1) {
                                out[@as(c_uint, @intCast(@as(c_int, 0)))] = stbi__blinn_8x8(@as(stbi_uc, @bitCast(@as(i8, @truncate(@as(c_int, 255) - @as(c_int, @bitCast(@as(c_uint, coutput[@as(c_uint, @intCast(@as(c_int, 0)))][i]))))))), coutput[@as(c_uint, @intCast(@as(c_int, 3)))][i]);
                                out[@as(c_uint, @intCast(@as(c_int, 1)))] = 255;
                                out += @as(usize, @bitCast(@as(isize, @intCast(n))));
                            }
                        }
                    } else {
                        var y: [*c]stbi_uc = coutput[@as(c_uint, @intCast(@as(c_int, 0)))];
                        _ = &y;
                        if (n == @as(c_int, 1)) {
                            {
                                i = 0;
                                while (i < z.*.s.*.img_x) : (i +%= 1) {
                                    out[i] = y[i];
                                }
                            }
                        } else {
                            i = 0;
                            while (i < z.*.s.*.img_x) : (i +%= 1) {
                                (blk: {
                                    const ref = &out;
                                    const tmp = ref.*;
                                    ref.* += 1;
                                    break :blk tmp;
                                }).* = y[i];
                                (blk: {
                                    const ref = &out;
                                    const tmp = ref.*;
                                    ref.* += 1;
                                    break :blk tmp;
                                }).* = 255;
                            }
                        }
                    }
                }
            }
        }
        stbi__cleanup_jpeg(z);
        out_x.* = @as(c_int, @bitCast(z.*.s.*.img_x));
        out_y.* = @as(c_int, @bitCast(z.*.s.*.img_y));
        if (comp != null) {
            comp.* = if (z.*.s.*.img_n >= @as(c_int, 3)) @as(c_int, 3) else @as(c_int, 1);
        }
        return output;
    }
}
pub fn stbi__jpeg_info_raw(arg_j: [*c]stbi__jpeg, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var j = arg_j;
    _ = &j;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    if (!(stbi__decode_jpeg_header(j, STBI__SCAN_header) != 0)) {
        stbi__rewind(j.*.s);
        return 0;
    }
    if (x != null) {
        x.* = @as(c_int, @bitCast(j.*.s.*.img_x));
    }
    if (y != null) {
        y.* = @as(c_int, @bitCast(j.*.s.*.img_y));
    }
    if (comp != null) {
        comp.* = if (j.*.s.*.img_n >= @as(c_int, 3)) @as(c_int, 3) else @as(c_int, 1);
    }
    return 1;
}
pub const stbi__zhuffman = extern struct {
    fast: [512]stbi__uint16 = @import("std").mem.zeroes([512]stbi__uint16),
    firstcode: [16]stbi__uint16 = @import("std").mem.zeroes([16]stbi__uint16),
    maxcode: [17]c_int = @import("std").mem.zeroes([17]c_int),
    firstsymbol: [16]stbi__uint16 = @import("std").mem.zeroes([16]stbi__uint16),
    size: [288]stbi_uc = @import("std").mem.zeroes([288]stbi_uc),
    value: [288]stbi__uint16 = @import("std").mem.zeroes([288]stbi__uint16),
};
pub fn stbi__bitreverse16(arg_n: c_int) callconv(.c) c_int {
    var n = arg_n;
    _ = &n;
    n = ((n & @as(c_int, 43690)) >> @intCast(1)) | ((n & @as(c_int, 21845)) << @intCast(1));
    n = ((n & @as(c_int, 52428)) >> @intCast(2)) | ((n & @as(c_int, 13107)) << @intCast(2));
    n = ((n & @as(c_int, 61680)) >> @intCast(4)) | ((n & @as(c_int, 3855)) << @intCast(4));
    n = ((n & @as(c_int, 65280)) >> @intCast(8)) | ((n & @as(c_int, 255)) << @intCast(8));
    return n;
}
pub fn stbi__bit_reverse(arg_v: c_int, arg_bits: c_int) callconv(.c) c_int {
    var v = arg_v;
    _ = &v;
    var bits = arg_bits;
    _ = &bits;
    _ = (bits <= @as(c_int, 16)) or ((blk: {
        __assert_fail("bits <= 16", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 4118), "stbi__bit_reverse");
        break :blk @as(c_int, 0);
    }) != 0);
    return stbi__bitreverse16(v) >> @intCast(@as(c_int, 16) - bits);
}
pub fn stbi__zbuild_huffman(arg_z: [*c]stbi__zhuffman, arg_sizelist: [*c]const stbi_uc, arg_num: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var sizelist = arg_sizelist;
    _ = &sizelist;
    var num = arg_num;
    _ = &num;
    var i: c_int = undefined;
    _ = &i;
    var k: c_int = 0;
    _ = &k;
    var code: c_int = undefined;
    _ = &code;
    var next_code: [16]c_int = undefined;
    _ = &next_code;
    var sizes: [17]c_int = undefined;
    _ = &sizes;
    _ = memset(@as(?*anyopaque, @ptrCast(@as([*c]c_int, @ptrCast(@alignCast(&sizes[@as(usize, @intCast(0))]))))), @as(c_int, 0), @sizeOf([17]c_int));
    _ = memset(@as(?*anyopaque, @ptrCast(@as([*c]stbi__uint16, @ptrCast(@alignCast(&z.*.fast[@as(usize, @intCast(0))]))))), @as(c_int, 0), @sizeOf([512]stbi__uint16));
    {
        i = 0;
        while (i < num) : (i += 1) {
            sizes[(blk: {
                const tmp = i;
                if (tmp >= 0) break :blk sizelist + @as(usize, @intCast(tmp)) else break :blk sizelist - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*] += 1;
        }
    }
    sizes[@as(c_uint, @intCast(@as(c_int, 0)))] = 0;
    {
        i = 1;
        while (i < @as(c_int, 16)) : (i += 1) if (sizes[@as(c_uint, @intCast(i))] > (@as(c_int, 1) << @intCast(i))) return 0;
    }
    code = 0;
    {
        i = 1;
        while (i < @as(c_int, 16)) : (i += 1) {
            next_code[@as(c_uint, @intCast(i))] = code;
            z.*.firstcode[@as(c_uint, @intCast(i))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(code))));
            z.*.firstsymbol[@as(c_uint, @intCast(i))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(k))));
            code = code + sizes[@as(c_uint, @intCast(i))];
            if (sizes[@as(c_uint, @intCast(i))] != 0) if ((code - @as(c_int, 1)) >= (@as(c_int, 1) << @intCast(i))) return 0;
            z.*.maxcode[@as(c_uint, @intCast(i))] = code << @intCast(@as(c_int, 16) - i);
            code <<= @intCast(@as(c_int, 1));
            k += sizes[@as(c_uint, @intCast(i))];
        }
    }
    z.*.maxcode[@as(c_uint, @intCast(@as(c_int, 16)))] = 65536;
    {
        i = 0;
        while (i < num) : (i += 1) {
            var s: c_int = @as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk sizelist + @as(usize, @intCast(tmp)) else break :blk sizelist - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)));
            _ = &s;
            if (s != 0) {
                var c: c_int = (next_code[@as(c_uint, @intCast(s))] - @as(c_int, @bitCast(@as(c_uint, z.*.firstcode[@as(c_uint, @intCast(s))])))) + @as(c_int, @bitCast(@as(c_uint, z.*.firstsymbol[@as(c_uint, @intCast(s))])));
                _ = &c;
                var fastv: stbi__uint16 = @as(stbi__uint16, @bitCast(@as(c_short, @truncate((s << @intCast(9)) | i))));
                _ = &fastv;
                z.*.size[@as(c_uint, @intCast(c))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(s))));
                z.*.value[@as(c_uint, @intCast(c))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(i))));
                if (s <= @as(c_int, 9)) {
                    var j: c_int = stbi__bit_reverse(next_code[@as(c_uint, @intCast(s))], s);
                    _ = &j;
                    while (j < (@as(c_int, 1) << @intCast(9))) {
                        z.*.fast[@as(c_uint, @intCast(j))] = fastv;
                        j += @as(c_int, 1) << @intCast(s);
                    }
                }
                next_code[@as(c_uint, @intCast(s))] += 1;
            }
        }
    }
    return 1;
}
pub const stbi__zbuf = extern struct {
    zbuffer: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    zbuffer_end: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    num_bits: c_int = @import("std").mem.zeroes(c_int),
    hit_zeof_once: c_int = @import("std").mem.zeroes(c_int),
    code_buffer: stbi__uint32 = @import("std").mem.zeroes(stbi__uint32),
    zout: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    zout_start: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    zout_end: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    z_expandable: c_int = @import("std").mem.zeroes(c_int),
    z_length: stbi__zhuffman = @import("std").mem.zeroes(stbi__zhuffman),
    z_distance: stbi__zhuffman = @import("std").mem.zeroes(stbi__zhuffman),
};
pub fn stbi__zeof(arg_z: [*c]stbi__zbuf) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    return @intFromBool(z.*.zbuffer >= z.*.zbuffer_end);
}
pub fn stbi__zget8(arg_z: [*c]stbi__zbuf) callconv(.c) stbi_uc {
    var z = arg_z;
    _ = &z;
    return @as(stbi_uc, @bitCast(@as(i8, @truncate(if (stbi__zeof(z) != 0) @as(c_int, 0) else @as(c_int, @bitCast(@as(c_uint, (blk: {
        const ref = &z.*.zbuffer;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).*)))))));
}
pub fn stbi__fill_bits(arg_z: [*c]stbi__zbuf) callconv(.c) void {
    var z = arg_z;
    _ = &z;
    while (true) {
        if (z.*.code_buffer >= (@as(c_uint, 1) << @intCast(z.*.num_bits))) {
            z.*.zbuffer = z.*.zbuffer_end;
            return;
        }
        z.*.code_buffer |= @as(stbi__uint32, @bitCast(@as(c_uint, @bitCast(@as(c_uint, stbi__zget8(z)))) << @intCast(z.*.num_bits)));
        z.*.num_bits += @as(c_int, 8);
        if (!(z.*.num_bits <= @as(c_int, 24))) break;
    }
}
pub fn stbi__zreceive(arg_z: [*c]stbi__zbuf, arg_n: c_int) callconv(.c) c_uint {
    var z = arg_z;
    _ = &z;
    var n = arg_n;
    _ = &n;
    var k: c_uint = undefined;
    _ = &k;
    if (z.*.num_bits < n) {
        stbi__fill_bits(z);
    }
    k = z.*.code_buffer & @as(stbi__uint32, @bitCast((@as(c_int, 1) << @intCast(n)) - @as(c_int, 1)));
    z.*.code_buffer >>= @intCast(n);
    z.*.num_bits -= n;
    return k;
}
pub fn stbi__zhuffman_decode_slowpath(arg_a: [*c]stbi__zbuf, arg_z: [*c]stbi__zhuffman) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var z = arg_z;
    _ = &z;
    var b: c_int = undefined;
    _ = &b;
    var s: c_int = undefined;
    _ = &s;
    var k: c_int = undefined;
    _ = &k;
    k = stbi__bit_reverse(@as(c_int, @bitCast(a.*.code_buffer)), @as(c_int, 16));
    {
        s = @as(c_int, 9) + @as(c_int, 1);
        while (true) : (s += 1) if (k < z.*.maxcode[@as(c_uint, @intCast(s))]) break;
    }
    if (s >= @as(c_int, 16)) return -@as(c_int, 1);
    b = ((k >> @intCast(@as(c_int, 16) - s)) - @as(c_int, @bitCast(@as(c_uint, z.*.firstcode[@as(c_uint, @intCast(s))])))) + @as(c_int, @bitCast(@as(c_uint, z.*.firstsymbol[@as(c_uint, @intCast(s))])));
    if (b >= @as(c_int, 288)) return -@as(c_int, 1);
    if (@as(c_int, @bitCast(@as(c_uint, z.*.size[@as(c_uint, @intCast(b))]))) != s) return -@as(c_int, 1);
    a.*.code_buffer >>= @intCast(s);
    a.*.num_bits -= s;
    return @as(c_int, @bitCast(@as(c_uint, z.*.value[@as(c_uint, @intCast(b))])));
}
pub fn stbi__zhuffman_decode(arg_a: [*c]stbi__zbuf, arg_z: [*c]stbi__zhuffman) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var z = arg_z;
    _ = &z;
    var b: c_int = undefined;
    _ = &b;
    var s: c_int = undefined;
    _ = &s;
    if (a.*.num_bits < @as(c_int, 16)) {
        if (stbi__zeof(a) != 0) {
            if (!(a.*.hit_zeof_once != 0)) {
                a.*.hit_zeof_once = 1;
                a.*.num_bits += @as(c_int, 16);
            } else {
                return -@as(c_int, 1);
            }
        } else {
            stbi__fill_bits(a);
        }
    }
    b = @as(c_int, @bitCast(@as(c_uint, z.*.fast[a.*.code_buffer & @as(stbi__uint32, @bitCast((@as(c_int, 1) << @intCast(9)) - @as(c_int, 1)))])));
    if (b != 0) {
        s = b >> @intCast(9);
        a.*.code_buffer >>= @intCast(s);
        a.*.num_bits -= s;
        return b & @as(c_int, 511);
    }
    return stbi__zhuffman_decode_slowpath(a, z);
}
pub fn stbi__zexpand(arg_z: [*c]stbi__zbuf, arg_zout: [*c]u8, arg_n: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var zout = arg_zout;
    _ = &zout;
    var n = arg_n;
    _ = &n;
    var q: [*c]u8 = undefined;
    _ = &q;
    var cur: c_uint = undefined;
    _ = &cur;
    var limit: c_uint = undefined;
    _ = &limit;
    var old_limit: c_uint = undefined;
    _ = &old_limit;
    z.*.zout = zout;
    if (!(z.*.z_expandable != 0)) return 0;
    cur = @as(c_uint, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(z.*.zout) -% @intFromPtr(z.*.zout_start))), @sizeOf(u8))))));
    limit = blk: {
        const tmp = @as(c_uint, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(z.*.zout_end) -% @intFromPtr(z.*.zout_start))), @sizeOf(u8))))));
        old_limit = tmp;
        break :blk tmp;
    };
    if ((((@as(c_uint, @bitCast(@as(c_int, 2147483647))) *% @as(c_uint, 2)) +% @as(c_uint, 1)) -% cur) < @as(c_uint, @bitCast(n))) return 0;
    while ((cur +% @as(c_uint, @bitCast(n))) > limit) {
        if (limit > (((@as(c_uint, @bitCast(@as(c_int, 2147483647))) *% @as(c_uint, 2)) +% @as(c_uint, 1)) / @as(c_uint, @bitCast(@as(c_int, 2))))) return 0;
        limit *%= @as(c_uint, @bitCast(@as(c_int, 2)));
    }
    q = @as([*c]u8, @ptrCast(@alignCast(realloc(@as(?*anyopaque, @ptrCast(z.*.zout_start)), @as(c_ulong, @bitCast(@as(c_ulong, limit)))))));
    _ = @sizeOf(c_uint);
    if (q == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return 0;
    z.*.zout_start = q;
    z.*.zout = q + cur;
    z.*.zout_end = q + limit;
    return 1;
}
pub const stbi__zlength_base: [31]c_int = [31]c_int{
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    13,
    15,
    17,
    19,
    23,
    27,
    31,
    35,
    43,
    51,
    59,
    67,
    83,
    99,
    115,
    131,
    163,
    195,
    227,
    258,
    0,
    0,
};
pub const stbi__zlength_extra: [31]c_int = [31]c_int{
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    5,
    5,
    5,
    5,
    0,
    0,
    0,
};
pub const stbi__zdist_base: [32]c_int = [32]c_int{
    1,
    2,
    3,
    4,
    5,
    7,
    9,
    13,
    17,
    25,
    33,
    49,
    65,
    97,
    129,
    193,
    257,
    385,
    513,
    769,
    1025,
    1537,
    2049,
    3073,
    4097,
    6145,
    8193,
    12289,
    16385,
    24577,
    0,
    0,
};
pub const stbi__zdist_extra: [32]c_int = [30]c_int{
    0,
    0,
    0,
    0,
    1,
    1,
    2,
    2,
    3,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    7,
    7,
    8,
    8,
    9,
    9,
    10,
    10,
    11,
    11,
    12,
    12,
    13,
    13,
} ++ [1]c_int{0} ** 2;
pub fn stbi__parse_huffman_block(arg_a: [*c]stbi__zbuf) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var zout: [*c]u8 = a.*.zout;
    _ = &zout;
    while (true) {
        var z: c_int = stbi__zhuffman_decode(a, &a.*.z_length);
        _ = &z;
        if (z < @as(c_int, 256)) {
            if (z < @as(c_int, 0)) return 0;
            if (zout >= a.*.zout_end) {
                if (!(stbi__zexpand(a, zout, @as(c_int, 1)) != 0)) return 0;
                zout = a.*.zout;
            }
            (blk: {
                const ref = &zout;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }).* = @as(u8, @bitCast(@as(i8, @truncate(z))));
        } else {
            var p: [*c]stbi_uc = undefined;
            _ = &p;
            var len: c_int = undefined;
            _ = &len;
            var dist: c_int = undefined;
            _ = &dist;
            if (z == @as(c_int, 256)) {
                a.*.zout = zout;
                if ((a.*.hit_zeof_once != 0) and (a.*.num_bits < @as(c_int, 16))) {
                    return 0;
                }
                return 1;
            }
            if (z >= @as(c_int, 286)) return 0;
            z -= @as(c_int, 257);
            len = stbi__zlength_base[@as(c_uint, @intCast(z))];
            if (stbi__zlength_extra[@as(c_uint, @intCast(z))] != 0) {
                len += @as(c_int, @bitCast(stbi__zreceive(a, stbi__zlength_extra[@as(c_uint, @intCast(z))])));
            }
            z = stbi__zhuffman_decode(a, &a.*.z_distance);
            if ((z < @as(c_int, 0)) or (z >= @as(c_int, 30))) return 0;
            dist = stbi__zdist_base[@as(c_uint, @intCast(z))];
            if (stbi__zdist_extra[@as(c_uint, @intCast(z))] != 0) {
                dist += @as(c_int, @bitCast(stbi__zreceive(a, stbi__zdist_extra[@as(c_uint, @intCast(z))])));
            }
            if (@divExact(@as(c_long, @bitCast(@intFromPtr(zout) -% @intFromPtr(a.*.zout_start))), @sizeOf(u8)) < @as(c_long, @bitCast(@as(c_long, dist)))) return 0;
            if (@as(c_long, @bitCast(@as(c_long, len))) > @divExact(@as(c_long, @bitCast(@intFromPtr(a.*.zout_end) -% @intFromPtr(zout))), @sizeOf(u8))) {
                if (!(stbi__zexpand(a, zout, len) != 0)) return 0;
                zout = a.*.zout;
            }
            p = @as([*c]stbi_uc, @ptrCast(@alignCast(zout - @as(usize, @bitCast(@as(isize, @intCast(dist)))))));
            if (dist == @as(c_int, 1)) {
                var v: stbi_uc = p.*;
                _ = &v;
                if (len != 0) {
                    while (true) {
                        (blk: {
                            const ref = &zout;
                            const tmp = ref.*;
                            ref.* += 1;
                            break :blk tmp;
                        }).* = @as(u8, @bitCast(v));
                        if (!((blk: {
                            const ref = &len;
                            ref.* -= 1;
                            break :blk ref.*;
                        }) != 0)) break;
                    }
                }
            } else {
                if (len != 0) {
                    while (true) {
                        (blk: {
                            const ref = &zout;
                            const tmp = ref.*;
                            ref.* += 1;
                            break :blk tmp;
                        }).* = @as(u8, @bitCast((blk: {
                            const ref = &p;
                            const tmp = ref.*;
                            ref.* += 1;
                            break :blk tmp;
                        }).*));
                        if (!((blk: {
                            const ref = &len;
                            ref.* -= 1;
                            break :blk ref.*;
                        }) != 0)) break;
                    }
                }
            }
        }
    }
    return 0;
}
pub fn stbi__compute_huffman_codes(arg_a: [*c]stbi__zbuf) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    const length_dezigzag = struct {
        const static: [19]stbi_uc = [19]stbi_uc{
            16,
            17,
            18,
            0,
            8,
            7,
            9,
            6,
            10,
            5,
            11,
            4,
            12,
            3,
            13,
            2,
            14,
            1,
            15,
        };
    };
    _ = &length_dezigzag;
    var z_codelength: stbi__zhuffman = undefined;
    _ = &z_codelength;
    var lencodes: [455]stbi_uc = undefined;
    _ = &lencodes;
    var codelength_sizes: [19]stbi_uc = undefined;
    _ = &codelength_sizes;
    var i: c_int = undefined;
    _ = &i;
    var n: c_int = undefined;
    _ = &n;
    var hlit: c_int = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 5)) +% @as(c_uint, @bitCast(@as(c_int, 257)))));
    _ = &hlit;
    var hdist: c_int = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 5)) +% @as(c_uint, @bitCast(@as(c_int, 1)))));
    _ = &hdist;
    var hclen: c_int = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 4)) +% @as(c_uint, @bitCast(@as(c_int, 4)))));
    _ = &hclen;
    var ntot: c_int = hlit + hdist;
    _ = &ntot;
    _ = memset(@as(?*anyopaque, @ptrCast(@as([*c]stbi_uc, @ptrCast(@alignCast(&codelength_sizes[@as(usize, @intCast(0))]))))), @as(c_int, 0), @sizeOf([19]stbi_uc));
    {
        i = 0;
        while (i < hclen) : (i += 1) {
            var s: c_int = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 3))));
            _ = &s;
            codelength_sizes[length_dezigzag.static[@as(c_uint, @intCast(i))]] = @as(stbi_uc, @bitCast(@as(i8, @truncate(s))));
        }
    }
    if (!(stbi__zbuild_huffman(&z_codelength, @as([*c]stbi_uc, @ptrCast(@alignCast(&codelength_sizes[@as(usize, @intCast(0))]))), @as(c_int, 19)) != 0)) return 0;
    n = 0;
    while (n < ntot) {
        var c: c_int = stbi__zhuffman_decode(a, &z_codelength);
        _ = &c;
        if ((c < @as(c_int, 0)) or (c >= @as(c_int, 19))) return 0;
        if (c < @as(c_int, 16)) {
            lencodes[@as(c_uint, @intCast(blk: {
                const ref = &n;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(c))));
        } else {
            var fill: stbi_uc = 0;
            _ = &fill;
            if (c == @as(c_int, 16)) {
                c = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 2)) +% @as(c_uint, @bitCast(@as(c_int, 3)))));
                if (n == @as(c_int, 0)) return 0;
                fill = lencodes[@as(c_uint, @intCast(n - @as(c_int, 1)))];
            } else if (c == @as(c_int, 17)) {
                c = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 3)) +% @as(c_uint, @bitCast(@as(c_int, 3)))));
            } else if (c == @as(c_int, 18)) {
                c = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 7)) +% @as(c_uint, @bitCast(@as(c_int, 11)))));
            } else {
                return 0;
            }
            if ((ntot - n) < c) return 0;
            _ = memset(@as(?*anyopaque, @ptrCast(@as([*c]stbi_uc, @ptrCast(@alignCast(&lencodes[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(n)))))), @as(c_int, @bitCast(@as(c_uint, fill))), @as(c_ulong, @bitCast(@as(c_long, c))));
            n += c;
        }
    }
    if (n != ntot) return 0;
    if (!(stbi__zbuild_huffman(&a.*.z_length, @as([*c]stbi_uc, @ptrCast(@alignCast(&lencodes[@as(usize, @intCast(0))]))), hlit) != 0)) return 0;
    if (!(stbi__zbuild_huffman(&a.*.z_distance, @as([*c]stbi_uc, @ptrCast(@alignCast(&lencodes[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(hlit)))), hdist) != 0)) return 0;
    return 1;
}
pub fn stbi__parse_uncompressed_block(arg_a: [*c]stbi__zbuf) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var header: [4]stbi_uc = undefined;
    _ = &header;
    var len: c_int = undefined;
    _ = &len;
    var nlen: c_int = undefined;
    _ = &nlen;
    var k: c_int = undefined;
    _ = &k;
    if ((a.*.num_bits & @as(c_int, 7)) != 0) {
        _ = stbi__zreceive(a, a.*.num_bits & @as(c_int, 7));
    }
    k = 0;
    while (a.*.num_bits > @as(c_int, 0)) {
        header[@as(c_uint, @intCast(blk: {
            const ref = &k;
            const tmp = ref.*;
            ref.* += 1;
            break :blk tmp;
        }))] = @as(stbi_uc, @bitCast(@as(u8, @truncate(a.*.code_buffer & @as(stbi__uint32, @bitCast(@as(c_int, 255)))))));
        a.*.code_buffer >>= @intCast(@as(c_int, 8));
        a.*.num_bits -= @as(c_int, 8);
    }
    if (a.*.num_bits < @as(c_int, 0)) return 0;
    while (k < @as(c_int, 4)) {
        header[@as(c_uint, @intCast(blk: {
            const ref = &k;
            const tmp = ref.*;
            ref.* += 1;
            break :blk tmp;
        }))] = stbi__zget8(a);
    }
    len = (@as(c_int, @bitCast(@as(c_uint, header[@as(c_uint, @intCast(@as(c_int, 1)))]))) * @as(c_int, 256)) + @as(c_int, @bitCast(@as(c_uint, header[@as(c_uint, @intCast(@as(c_int, 0)))])));
    nlen = (@as(c_int, @bitCast(@as(c_uint, header[@as(c_uint, @intCast(@as(c_int, 3)))]))) * @as(c_int, 256)) + @as(c_int, @bitCast(@as(c_uint, header[@as(c_uint, @intCast(@as(c_int, 2)))])));
    if (nlen != (len ^ @as(c_int, 65535))) return 0;
    if ((a.*.zbuffer + @as(usize, @bitCast(@as(isize, @intCast(len))))) > a.*.zbuffer_end) return 0;
    if ((a.*.zout + @as(usize, @bitCast(@as(isize, @intCast(len))))) > a.*.zout_end) if (!(stbi__zexpand(a, a.*.zout, len) != 0)) return 0;
    _ = memcpy(@as(?*anyopaque, @ptrCast(a.*.zout)), @as(?*const anyopaque, @ptrCast(a.*.zbuffer)), @as(c_ulong, @bitCast(@as(c_long, len))));
    a.*.zbuffer += @as(usize, @bitCast(@as(isize, @intCast(len))));
    a.*.zout += @as(usize, @bitCast(@as(isize, @intCast(len))));
    return 1;
}
pub fn stbi__parse_zlib_header(arg_a: [*c]stbi__zbuf) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var cmf: c_int = @as(c_int, @bitCast(@as(c_uint, stbi__zget8(a))));
    _ = &cmf;
    var cm: c_int = cmf & @as(c_int, 15);
    _ = &cm;
    var flg: c_int = @as(c_int, @bitCast(@as(c_uint, stbi__zget8(a))));
    _ = &flg;
    if (stbi__zeof(a) != 0) return 0;
    if (@import("std").zig.c_translation.signedRemainder((cmf * @as(c_int, 256)) + flg, @as(c_int, 31)) != @as(c_int, 0)) return 0;
    if ((flg & @as(c_int, 32)) != 0) return 0;
    if (cm != @as(c_int, 8)) return 0;
    return 1;
}
pub const stbi__zdefault_length: [288]stbi_uc = [288]stbi_uc{
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    9,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    7,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
    8,
};
pub const stbi__zdefault_distance: [32]stbi_uc = [32]stbi_uc{
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
};
pub fn stbi__parse_zlib(arg_a: [*c]stbi__zbuf, arg_parse_header: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var parse_header = arg_parse_header;
    _ = &parse_header;
    var final: c_int = undefined;
    _ = &final;
    var @"type": c_int = undefined;
    _ = &@"type";
    if (parse_header != 0) if (!(stbi__parse_zlib_header(a) != 0)) return 0;
    a.*.num_bits = 0;
    a.*.code_buffer = 0;
    a.*.hit_zeof_once = 0;
    while (true) {
        final = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 1))));
        @"type" = @as(c_int, @bitCast(stbi__zreceive(a, @as(c_int, 2))));
        if (@"type" == @as(c_int, 0)) {
            if (!(stbi__parse_uncompressed_block(a) != 0)) return 0;
        } else if (@"type" == @as(c_int, 3)) {
            return 0;
        } else {
            if (@"type" == @as(c_int, 1)) {
                if (!(stbi__zbuild_huffman(&a.*.z_length, @as([*c]const stbi_uc, @ptrCast(@alignCast(&stbi__zdefault_length[@as(usize, @intCast(0))]))), @as(c_int, 288)) != 0)) return 0;
                if (!(stbi__zbuild_huffman(&a.*.z_distance, @as([*c]const stbi_uc, @ptrCast(@alignCast(&stbi__zdefault_distance[@as(usize, @intCast(0))]))), @as(c_int, 32)) != 0)) return 0;
            } else {
                if (!(stbi__compute_huffman_codes(a) != 0)) return 0;
            }
            if (!(stbi__parse_huffman_block(a) != 0)) return 0;
        }
        if (!!(final != 0)) break;
    }
    return 1;
}
pub fn stbi__do_zlib(arg_a: [*c]stbi__zbuf, arg_obuf: [*c]u8, arg_olen: c_int, arg_exp_1: c_int, arg_parse_header: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var obuf = arg_obuf;
    _ = &obuf;
    var olen = arg_olen;
    _ = &olen;
    var exp_1 = arg_exp_1;
    _ = &exp_1;
    var parse_header = arg_parse_header;
    _ = &parse_header;
    a.*.zout_start = obuf;
    a.*.zout = obuf;
    a.*.zout_end = obuf + @as(usize, @bitCast(@as(isize, @intCast(olen))));
    a.*.z_expandable = exp_1;
    return stbi__parse_zlib(a, parse_header);
}
pub const stbi__pngchunk = extern struct {
    length: stbi__uint32 = @import("std").mem.zeroes(stbi__uint32),
    type: stbi__uint32 = @import("std").mem.zeroes(stbi__uint32),
};
pub fn stbi__get_chunk_header(arg_s: [*c]stbi__context) callconv(.c) stbi__pngchunk {
    var s = arg_s;
    _ = &s;
    var c: stbi__pngchunk = undefined;
    _ = &c;
    c.length = stbi__get32be(s);
    c.type = stbi__get32be(s);
    return c;
}
pub fn stbi__check_png_header(arg_s: [*c]stbi__context) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    const png_sig = struct {
        const static: [8]stbi_uc = [8]stbi_uc{
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
        };
    };
    _ = &png_sig;
    var i: c_int = undefined;
    _ = &i;
    {
        i = 0;
        while (i < @as(c_int, 8)) : (i += 1) if (@as(c_int, @bitCast(@as(c_uint, stbi__get8(s)))) != @as(c_int, @bitCast(@as(c_uint, png_sig.static[@as(c_uint, @intCast(i))])))) return 0;
    }
    return 1;
}
pub const stbi__png = extern struct {
    s: [*c]stbi__context = @import("std").mem.zeroes([*c]stbi__context),
    idata: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    expanded: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    out: [*c]stbi_uc = @import("std").mem.zeroes([*c]stbi_uc),
    depth: c_int = @import("std").mem.zeroes(c_int),
};
pub const STBI__F_none: c_int = 0;
pub const STBI__F_sub: c_int = 1;
pub const STBI__F_up: c_int = 2;
pub const STBI__F_avg: c_int = 3;
pub const STBI__F_paeth: c_int = 4;
pub const STBI__F_avg_first: c_int = 5;
const enum_unnamed_8 = c_uint;
pub var first_row_filter: [5]stbi_uc = [5]stbi_uc{
    @as(stbi_uc, @bitCast(@as(i8, @truncate(STBI__F_none)))),
    @as(stbi_uc, @bitCast(@as(i8, @truncate(STBI__F_sub)))),
    @as(stbi_uc, @bitCast(@as(i8, @truncate(STBI__F_none)))),
    @as(stbi_uc, @bitCast(@as(i8, @truncate(STBI__F_avg_first)))),
    @as(stbi_uc, @bitCast(@as(i8, @truncate(STBI__F_sub)))),
};
pub fn stbi__paeth(arg_a: c_int, arg_b: c_int, arg_c: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var c = arg_c;
    _ = &c;
    var thresh: c_int = (c * @as(c_int, 3)) - (a + b);
    _ = &thresh;
    var lo: c_int = if (a < b) a else b;
    _ = &lo;
    var hi: c_int = if (a < b) b else a;
    _ = &hi;
    var t0: c_int = if (hi <= thresh) lo else c;
    _ = &t0;
    var t1: c_int = if (thresh <= lo) hi else t0;
    _ = &t1;
    return t1;
}
pub const stbi__depth_scale_table: [9]stbi_uc = [9]stbi_uc{
    0,
    255,
    85,
    0,
    17,
    0,
    0,
    0,
    1,
};
pub fn stbi__create_png_alpha_expand8(arg_dest: [*c]stbi_uc, arg_src: [*c]stbi_uc, arg_x: stbi__uint32, arg_img_n: c_int) callconv(.c) void {
    var dest = arg_dest;
    _ = &dest;
    var src = arg_src;
    _ = &src;
    var x = arg_x;
    _ = &x;
    var img_n = arg_img_n;
    _ = &img_n;
    var i: c_int = undefined;
    _ = &i;
    if (img_n == @as(c_int, 1)) {
        {
            i = @as(c_int, @bitCast(x -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))));
            while (i >= @as(c_int, 0)) : (i -= 1) {
                (blk: {
                    const tmp = (i * @as(c_int, 2)) + @as(c_int, 1);
                    if (tmp >= 0) break :blk dest + @as(usize, @intCast(tmp)) else break :blk dest - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = 255;
                (blk: {
                    const tmp = (i * @as(c_int, 2)) + @as(c_int, 0);
                    if (tmp >= 0) break :blk dest + @as(usize, @intCast(tmp)) else break :blk dest - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = (blk: {
                    const tmp = i;
                    if (tmp >= 0) break :blk src + @as(usize, @intCast(tmp)) else break :blk src - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
            }
        }
    } else {
        _ = (img_n == @as(c_int, 3)) or ((blk: {
            __assert_fail("img_n == 3", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 4685), "stbi__create_png_alpha_expand8");
            break :blk @as(c_int, 0);
        }) != 0);
        {
            i = @as(c_int, @bitCast(x -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))));
            while (i >= @as(c_int, 0)) : (i -= 1) {
                (blk: {
                    const tmp = (i * @as(c_int, 4)) + @as(c_int, 3);
                    if (tmp >= 0) break :blk dest + @as(usize, @intCast(tmp)) else break :blk dest - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = 255;
                (blk: {
                    const tmp = (i * @as(c_int, 4)) + @as(c_int, 2);
                    if (tmp >= 0) break :blk dest + @as(usize, @intCast(tmp)) else break :blk dest - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = (blk: {
                    const tmp = (i * @as(c_int, 3)) + @as(c_int, 2);
                    if (tmp >= 0) break :blk src + @as(usize, @intCast(tmp)) else break :blk src - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                (blk: {
                    const tmp = (i * @as(c_int, 4)) + @as(c_int, 1);
                    if (tmp >= 0) break :blk dest + @as(usize, @intCast(tmp)) else break :blk dest - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = (blk: {
                    const tmp = (i * @as(c_int, 3)) + @as(c_int, 1);
                    if (tmp >= 0) break :blk src + @as(usize, @intCast(tmp)) else break :blk src - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                (blk: {
                    const tmp = (i * @as(c_int, 4)) + @as(c_int, 0);
                    if (tmp >= 0) break :blk dest + @as(usize, @intCast(tmp)) else break :blk dest - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = (blk: {
                    const tmp = (i * @as(c_int, 3)) + @as(c_int, 0);
                    if (tmp >= 0) break :blk src + @as(usize, @intCast(tmp)) else break :blk src - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
            }
        }
    }
}
pub fn stbi__create_png_image_raw(arg_a: [*c]stbi__png, arg_raw: [*c]stbi_uc, arg_raw_len: stbi__uint32, arg_out_n: c_int, arg_x: stbi__uint32, arg_y: stbi__uint32, arg_depth: c_int, arg_color: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var raw = arg_raw;
    _ = &raw;
    var raw_len = arg_raw_len;
    _ = &raw_len;
    var out_n = arg_out_n;
    _ = &out_n;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var depth = arg_depth;
    _ = &depth;
    var color = arg_color;
    _ = &color;
    var bytes: c_int = if (depth == @as(c_int, 16)) @as(c_int, 2) else @as(c_int, 1);
    _ = &bytes;
    var s: [*c]stbi__context = a.*.s;
    _ = &s;
    var i: stbi__uint32 = undefined;
    _ = &i;
    var j: stbi__uint32 = undefined;
    _ = &j;
    var stride: stbi__uint32 = (x *% @as(stbi__uint32, @bitCast(out_n))) *% @as(stbi__uint32, @bitCast(bytes));
    _ = &stride;
    var img_len: stbi__uint32 = undefined;
    _ = &img_len;
    var img_width_bytes: stbi__uint32 = undefined;
    _ = &img_width_bytes;
    var filter_buf: [*c]stbi_uc = undefined;
    _ = &filter_buf;
    var all_ok: c_int = 1;
    _ = &all_ok;
    var k: c_int = undefined;
    _ = &k;
    var img_n: c_int = s.*.img_n;
    _ = &img_n;
    var output_bytes: c_int = out_n * bytes;
    _ = &output_bytes;
    var filter_bytes: c_int = img_n * bytes;
    _ = &filter_bytes;
    var width: c_int = @as(c_int, @bitCast(x));
    _ = &width;
    _ = ((out_n == s.*.img_n) or (out_n == (s.*.img_n + @as(c_int, 1)))) or ((blk: {
        __assert_fail("out_n == s->img_n || out_n == s->img_n+1", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 4711), "stbi__create_png_image_raw");
        break :blk @as(c_int, 0);
    }) != 0);
    a.*.out = @as([*c]stbi_uc, @ptrCast(@alignCast(stbi__malloc_mad3(@as(c_int, @bitCast(x)), @as(c_int, @bitCast(y)), output_bytes, @as(c_int, 0)))));
    if (!(a.*.out != null)) return 0;
    if (!(stbi__mad3sizes_valid(img_n, @as(c_int, @bitCast(x)), depth, @as(c_int, 7)) != 0)) return 0;
    img_width_bytes = (((@as(stbi__uint32, @bitCast(img_n)) *% x) *% @as(stbi__uint32, @bitCast(depth))) +% @as(stbi__uint32, @bitCast(@as(c_int, 7)))) >> @intCast(3);
    if (!(stbi__mad2sizes_valid(@as(c_int, @bitCast(img_width_bytes)), @as(c_int, @bitCast(y)), @as(c_int, @bitCast(img_width_bytes))) != 0)) return 0;
    img_len = (img_width_bytes +% @as(stbi__uint32, @bitCast(@as(c_int, 1)))) *% y;
    if (raw_len < img_len) return 0;
    filter_buf = @as([*c]stbi_uc, @ptrCast(@alignCast(stbi__malloc_mad2(@as(c_int, @bitCast(img_width_bytes)), @as(c_int, 2), @as(c_int, 0)))));
    if (!(filter_buf != null)) return 0;
    if (depth < @as(c_int, 8)) {
        filter_bytes = 1;
        width = @as(c_int, @bitCast(img_width_bytes));
    }
    {
        j = 0;
        while (j < y) : (j +%= 1) {
            var cur: [*c]stbi_uc = filter_buf + ((j & @as(stbi__uint32, @bitCast(@as(c_int, 1)))) *% img_width_bytes);
            _ = &cur;
            var prior: [*c]stbi_uc = filter_buf + ((~j & @as(stbi__uint32, @bitCast(@as(c_int, 1)))) *% img_width_bytes);
            _ = &prior;
            var dest: [*c]stbi_uc = a.*.out + (stride *% j);
            _ = &dest;
            var nk: c_int = width * filter_bytes;
            _ = &nk;
            var filter: c_int = @as(c_int, @bitCast(@as(c_uint, (blk: {
                const ref = &raw;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }).*)));
            _ = &filter;
            if (filter > @as(c_int, 4)) {
                all_ok = 0;
                break;
            }
            if (j == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) {
                filter = @as(c_int, @bitCast(@as(c_uint, first_row_filter[@as(c_uint, @intCast(filter))])));
            }
            while (true) {
                switch (filter) {
                    @as(c_int, 0) => {
                        _ = memcpy(@as(?*anyopaque, @ptrCast(cur)), @as(?*const anyopaque, @ptrCast(raw)), @as(c_ulong, @bitCast(@as(c_long, nk))));
                        break;
                    },
                    @as(c_int, 1) => {
                        _ = memcpy(@as(?*anyopaque, @ptrCast(cur)), @as(?*const anyopaque, @ptrCast(raw)), @as(c_ulong, @bitCast(@as(c_long, filter_bytes))));
                        {
                            k = filter_bytes;
                            while (k < nk) : (k += 1) {
                                (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk raw + @as(usize, @intCast(tmp)) else break :blk raw - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) + @as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k - filter_bytes;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*)))) & @as(c_int, 255)))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 2) => {
                        {
                            k = 0;
                            while (k < nk) : (k += 1) {
                                (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk raw + @as(usize, @intCast(tmp)) else break :blk raw - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) + @as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk prior + @as(usize, @intCast(tmp)) else break :blk prior - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*)))) & @as(c_int, 255)))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 3) => {
                        {
                            k = 0;
                            while (k < filter_bytes) : (k += 1) {
                                (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk raw + @as(usize, @intCast(tmp)) else break :blk raw - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) + (@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk prior + @as(usize, @intCast(tmp)) else break :blk prior - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) >> @intCast(1))) & @as(c_int, 255)))));
                            }
                        }
                        {
                            k = filter_bytes;
                            while (k < nk) : (k += 1) {
                                (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk raw + @as(usize, @intCast(tmp)) else break :blk raw - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) + ((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk prior + @as(usize, @intCast(tmp)) else break :blk prior - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) + @as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k - filter_bytes;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*)))) >> @intCast(1))) & @as(c_int, 255)))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 4) => {
                        {
                            k = 0;
                            while (k < filter_bytes) : (k += 1) {
                                (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk raw + @as(usize, @intCast(tmp)) else break :blk raw - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) + @as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk prior + @as(usize, @intCast(tmp)) else break :blk prior - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*)))) & @as(c_int, 255)))));
                            }
                        }
                        {
                            k = filter_bytes;
                            while (k < nk) : (k += 1) {
                                (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk raw + @as(usize, @intCast(tmp)) else break :blk raw - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) + stbi__paeth(@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k - filter_bytes;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))), @as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk prior + @as(usize, @intCast(tmp)) else break :blk prior - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))), @as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k - filter_bytes;
                                    if (tmp >= 0) break :blk prior + @as(usize, @intCast(tmp)) else break :blk prior - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))))) & @as(c_int, 255)))));
                            }
                        }
                        break;
                    },
                    @as(c_int, 5) => {
                        _ = memcpy(@as(?*anyopaque, @ptrCast(cur)), @as(?*const anyopaque, @ptrCast(raw)), @as(c_ulong, @bitCast(@as(c_long, filter_bytes))));
                        {
                            k = filter_bytes;
                            while (k < nk) : (k += 1) {
                                (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k;
                                    if (tmp >= 0) break :blk raw + @as(usize, @intCast(tmp)) else break :blk raw - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) + (@as(c_int, @bitCast(@as(c_uint, (blk: {
                                    const tmp = k - filter_bytes;
                                    if (tmp >= 0) break :blk cur + @as(usize, @intCast(tmp)) else break :blk cur - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))) >> @intCast(1))) & @as(c_int, 255)))));
                            }
                        }
                        break;
                    },
                    else => {},
                }
                break;
            }
            raw += @as(usize, @bitCast(@as(isize, @intCast(nk))));
            if (depth < @as(c_int, 8)) {
                var scale: stbi_uc = @as(stbi_uc, @bitCast(@as(i8, @truncate(if (color == @as(c_int, 0)) @as(c_int, @bitCast(@as(c_uint, stbi__depth_scale_table[@as(c_uint, @intCast(depth))]))) else @as(c_int, 1)))));
                _ = &scale;
                var in: [*c]stbi_uc = cur;
                _ = &in;
                var out: [*c]stbi_uc = dest;
                _ = &out;
                var inb: stbi_uc = 0;
                _ = &inb;
                var nsmp: stbi__uint32 = x *% @as(stbi__uint32, @bitCast(img_n));
                _ = &nsmp;
                if (depth == @as(c_int, 4)) {
                    {
                        i = 0;
                        while (i < nsmp) : (i +%= 1) {
                            if ((i & @as(stbi__uint32, @bitCast(@as(c_int, 1)))) == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) {
                                inb = (blk: {
                                    const ref = &in;
                                    const tmp = ref.*;
                                    ref.* += 1;
                                    break :blk tmp;
                                }).*;
                            }
                            (blk: {
                                const ref = &out;
                                const tmp = ref.*;
                                ref.* += 1;
                                break :blk tmp;
                            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, scale))) * (@as(c_int, @bitCast(@as(c_uint, inb))) >> @intCast(4))))));
                            inb <<= @intCast(@as(c_int, 4));
                        }
                    }
                } else if (depth == @as(c_int, 2)) {
                    {
                        i = 0;
                        while (i < nsmp) : (i +%= 1) {
                            if ((i & @as(stbi__uint32, @bitCast(@as(c_int, 3)))) == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) {
                                inb = (blk: {
                                    const ref = &in;
                                    const tmp = ref.*;
                                    ref.* += 1;
                                    break :blk tmp;
                                }).*;
                            }
                            (blk: {
                                const ref = &out;
                                const tmp = ref.*;
                                ref.* += 1;
                                break :blk tmp;
                            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, scale))) * (@as(c_int, @bitCast(@as(c_uint, inb))) >> @intCast(6))))));
                            inb <<= @intCast(@as(c_int, 2));
                        }
                    }
                } else {
                    _ = (depth == @as(c_int, 1)) or ((blk: {
                        __assert_fail("depth == 1", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 4811), "stbi__create_png_image_raw");
                        break :blk @as(c_int, 0);
                    }) != 0);
                    {
                        i = 0;
                        while (i < nsmp) : (i +%= 1) {
                            if ((i & @as(stbi__uint32, @bitCast(@as(c_int, 7)))) == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) {
                                inb = (blk: {
                                    const ref = &in;
                                    const tmp = ref.*;
                                    ref.* += 1;
                                    break :blk tmp;
                                }).*;
                            }
                            (blk: {
                                const ref = &out;
                                const tmp = ref.*;
                                ref.* += 1;
                                break :blk tmp;
                            }).* = @as(stbi_uc, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, scale))) * (@as(c_int, @bitCast(@as(c_uint, inb))) >> @intCast(7))))));
                            inb <<= @intCast(@as(c_int, 1));
                        }
                    }
                }
                if (img_n != out_n) {
                    stbi__create_png_alpha_expand8(dest, dest, x, img_n);
                }
            } else if (depth == @as(c_int, 8)) {
                if (img_n == out_n) {
                    _ = memcpy(@as(?*anyopaque, @ptrCast(dest)), @as(?*const anyopaque, @ptrCast(cur)), @as(c_ulong, @bitCast(@as(c_ulong, x *% @as(stbi__uint32, @bitCast(img_n))))));
                } else {
                    stbi__create_png_alpha_expand8(dest, cur, x, img_n);
                }
            } else if (depth == @as(c_int, 16)) {
                var dest16: [*c]stbi__uint16 = @as([*c]stbi__uint16, @ptrCast(@alignCast(dest)));
                _ = &dest16;
                var nsmp: stbi__uint32 = x *% @as(stbi__uint32, @bitCast(img_n));
                _ = &nsmp;
                if (img_n == out_n) {
                    {
                        i = 0;
                        while (i < nsmp) : (_ = blk: {
                            _ = blk_1: {
                                i +%= 1;
                                break :blk_1 blk_2: {
                                    const ref = &dest16;
                                    ref.* += 1;
                                    break :blk_2 ref.*;
                                };
                            };
                            break :blk blk_1: {
                                const ref = &cur;
                                ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                break :blk_1 ref.*;
                            };
                        }) {
                            dest16.* = @as(stbi__uint16, @bitCast(@as(c_short, @truncate((@as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 0)))]))) << @intCast(8)) | @as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 1)))])))))));
                        }
                    }
                } else {
                    _ = ((img_n + @as(c_int, 1)) == out_n) or ((blk: {
                        __assert_fail("img_n+1 == out_n", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 4836), "stbi__create_png_image_raw");
                        break :blk @as(c_int, 0);
                    }) != 0);
                    if (img_n == @as(c_int, 1)) {
                        {
                            i = 0;
                            while (i < x) : (_ = blk: {
                                _ = blk_1: {
                                    i +%= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &dest16;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &cur;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest16[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate((@as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 0)))]))) << @intCast(8)) | @as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 1)))])))))));
                                dest16[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(@as(c_int, 65535)))));
                            }
                        }
                    } else {
                        _ = (img_n == @as(c_int, 3)) or ((blk: {
                            __assert_fail("img_n == 3", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 4843), "stbi__create_png_image_raw");
                            break :blk @as(c_int, 0);
                        }) != 0);
                        {
                            i = 0;
                            while (i < x) : (_ = blk: {
                                _ = blk_1: {
                                    i +%= 1;
                                    break :blk_1 blk_2: {
                                        const ref = &dest16;
                                        ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                                        break :blk_2 ref.*;
                                    };
                                };
                                break :blk blk_1: {
                                    const ref = &cur;
                                    ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 6)))));
                                    break :blk_1 ref.*;
                                };
                            }) {
                                dest16[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate((@as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 0)))]))) << @intCast(8)) | @as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 1)))])))))));
                                dest16[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate((@as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 2)))]))) << @intCast(8)) | @as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 3)))])))))));
                                dest16[@as(c_uint, @intCast(@as(c_int, 2)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate((@as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 4)))]))) << @intCast(8)) | @as(c_int, @bitCast(@as(c_uint, cur[@as(c_uint, @intCast(@as(c_int, 5)))])))))));
                                dest16[@as(c_uint, @intCast(@as(c_int, 3)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(@as(c_int, 65535)))));
                            }
                        }
                    }
                }
            }
        }
    }
    free(@as(?*anyopaque, @ptrCast(filter_buf)));
    if (!(all_ok != 0)) return 0;
    return 1;
}
pub fn stbi__create_png_image(arg_a: [*c]stbi__png, arg_image_data: [*c]stbi_uc, arg_image_data_len: stbi__uint32, arg_out_n: c_int, arg_depth: c_int, arg_color: c_int, arg_interlaced: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var image_data = arg_image_data;
    _ = &image_data;
    var image_data_len = arg_image_data_len;
    _ = &image_data_len;
    var out_n = arg_out_n;
    _ = &out_n;
    var depth = arg_depth;
    _ = &depth;
    var color = arg_color;
    _ = &color;
    var interlaced = arg_interlaced;
    _ = &interlaced;
    var bytes: c_int = if (depth == @as(c_int, 16)) @as(c_int, 2) else @as(c_int, 1);
    _ = &bytes;
    var out_bytes: c_int = out_n * bytes;
    _ = &out_bytes;
    var final: [*c]stbi_uc = undefined;
    _ = &final;
    var p: c_int = undefined;
    _ = &p;
    if (!(interlaced != 0)) return stbi__create_png_image_raw(a, image_data, image_data_len, out_n, a.*.s.*.img_x, a.*.s.*.img_y, depth, color);
    final = @as([*c]stbi_uc, @ptrCast(@alignCast(stbi__malloc_mad3(@as(c_int, @bitCast(a.*.s.*.img_x)), @as(c_int, @bitCast(a.*.s.*.img_y)), out_bytes, @as(c_int, 0)))));
    if (!(final != null)) return 0;
    {
        p = 0;
        while (p < @as(c_int, 7)) : (p += 1) {
            var xorig: [7]c_int = [7]c_int{
                0,
                4,
                0,
                2,
                0,
                1,
                0,
            };
            _ = &xorig;
            var yorig: [7]c_int = [7]c_int{
                0,
                0,
                4,
                0,
                2,
                0,
                1,
            };
            _ = &yorig;
            var xspc: [7]c_int = [7]c_int{
                8,
                8,
                4,
                4,
                2,
                2,
                1,
            };
            _ = &xspc;
            var yspc: [7]c_int = [7]c_int{
                8,
                8,
                8,
                4,
                4,
                2,
                2,
            };
            _ = &yspc;
            var i: c_int = undefined;
            _ = &i;
            var j: c_int = undefined;
            _ = &j;
            var x: c_int = undefined;
            _ = &x;
            var y: c_int = undefined;
            _ = &y;
            x = @as(c_int, @bitCast((((a.*.s.*.img_x -% @as(stbi__uint32, @bitCast(xorig[@as(c_uint, @intCast(p))]))) +% @as(stbi__uint32, @bitCast(xspc[@as(c_uint, @intCast(p))]))) -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))) / @as(stbi__uint32, @bitCast(xspc[@as(c_uint, @intCast(p))]))));
            y = @as(c_int, @bitCast((((a.*.s.*.img_y -% @as(stbi__uint32, @bitCast(yorig[@as(c_uint, @intCast(p))]))) +% @as(stbi__uint32, @bitCast(yspc[@as(c_uint, @intCast(p))]))) -% @as(stbi__uint32, @bitCast(@as(c_int, 1)))) / @as(stbi__uint32, @bitCast(yspc[@as(c_uint, @intCast(p))]))));
            if ((x != 0) and (y != 0)) {
                var img_len: stbi__uint32 = @as(stbi__uint32, @bitCast((((((a.*.s.*.img_n * x) * depth) + @as(c_int, 7)) >> @intCast(3)) + @as(c_int, 1)) * y));
                _ = &img_len;
                if (!(stbi__create_png_image_raw(a, image_data, image_data_len, out_n, @as(stbi__uint32, @bitCast(x)), @as(stbi__uint32, @bitCast(y)), depth, color) != 0)) {
                    free(@as(?*anyopaque, @ptrCast(final)));
                    return 0;
                }
                {
                    j = 0;
                    while (j < y) : (j += 1) {
                        {
                            i = 0;
                            while (i < x) : (i += 1) {
                                var out_y: c_int = (j * yspc[@as(c_uint, @intCast(p))]) + yorig[@as(c_uint, @intCast(p))];
                                _ = &out_y;
                                var out_x: c_int = (i * xspc[@as(c_uint, @intCast(p))]) + xorig[@as(c_uint, @intCast(p))];
                                _ = &out_x;
                                _ = memcpy(@as(?*anyopaque, @ptrCast((final + ((@as(stbi__uint32, @bitCast(out_y)) *% a.*.s.*.img_x) *% @as(stbi__uint32, @bitCast(out_bytes)))) + @as(usize, @bitCast(@as(isize, @intCast(out_x * out_bytes)))))), @as(?*const anyopaque, @ptrCast(a.*.out + @as(usize, @bitCast(@as(isize, @intCast(((j * x) + i) * out_bytes)))))), @as(c_ulong, @bitCast(@as(c_long, out_bytes))));
                            }
                        }
                    }
                }
                free(@as(?*anyopaque, @ptrCast(a.*.out)));
                image_data += img_len;
                image_data_len -%= img_len;
            }
        }
    }
    a.*.out = final;
    return 1;
}
pub fn stbi__compute_transparency(arg_z: [*c]stbi__png, arg_tc: [*c]stbi_uc, arg_out_n: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var tc = arg_tc;
    _ = &tc;
    var out_n = arg_out_n;
    _ = &out_n;
    var s: [*c]stbi__context = z.*.s;
    _ = &s;
    var i: stbi__uint32 = undefined;
    _ = &i;
    var pixel_count: stbi__uint32 = s.*.img_x *% s.*.img_y;
    _ = &pixel_count;
    var p: [*c]stbi_uc = z.*.out;
    _ = &p;
    _ = ((out_n == @as(c_int, 2)) or (out_n == @as(c_int, 4))) or ((blk: {
        __assert_fail("out_n == 2 || out_n == 4", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 4914), "stbi__compute_transparency");
        break :blk @as(c_int, 0);
    }) != 0);
    if (out_n == @as(c_int, 2)) {
        {
            i = 0;
            while (i < pixel_count) : (i +%= 1) {
                p[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(if (@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 0)))]))) == @as(c_int, @bitCast(@as(c_uint, tc[@as(c_uint, @intCast(@as(c_int, 0)))])))) @as(c_int, 0) else @as(c_int, 255)))));
                p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
            }
        }
    } else {
        {
            i = 0;
            while (i < pixel_count) : (i +%= 1) {
                if (((@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 0)))]))) == @as(c_int, @bitCast(@as(c_uint, tc[@as(c_uint, @intCast(@as(c_int, 0)))])))) and (@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 1)))]))) == @as(c_int, @bitCast(@as(c_uint, tc[@as(c_uint, @intCast(@as(c_int, 1)))]))))) and (@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 2)))]))) == @as(c_int, @bitCast(@as(c_uint, tc[@as(c_uint, @intCast(@as(c_int, 2)))]))))) {
                    p[@as(c_uint, @intCast(@as(c_int, 3)))] = 0;
                }
                p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            }
        }
    }
    return 1;
}
pub fn stbi__compute_transparency16(arg_z: [*c]stbi__png, arg_tc: [*c]stbi__uint16, arg_out_n: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var tc = arg_tc;
    _ = &tc;
    var out_n = arg_out_n;
    _ = &out_n;
    var s: [*c]stbi__context = z.*.s;
    _ = &s;
    var i: stbi__uint32 = undefined;
    _ = &i;
    var pixel_count: stbi__uint32 = s.*.img_x *% s.*.img_y;
    _ = &pixel_count;
    var p: [*c]stbi__uint16 = @as([*c]stbi__uint16, @ptrCast(@alignCast(z.*.out)));
    _ = &p;
    _ = ((out_n == @as(c_int, 2)) or (out_n == @as(c_int, 4))) or ((blk: {
        __assert_fail("out_n == 2 || out_n == 4", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 4939), "stbi__compute_transparency16");
        break :blk @as(c_int, 0);
    }) != 0);
    if (out_n == @as(c_int, 2)) {
        {
            i = 0;
            while (i < pixel_count) : (i +%= 1) {
                p[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(if (@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 0)))]))) == @as(c_int, @bitCast(@as(c_uint, tc[@as(c_uint, @intCast(@as(c_int, 0)))])))) @as(c_int, 0) else @as(c_int, 65535)))));
                p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))));
            }
        }
    } else {
        {
            i = 0;
            while (i < pixel_count) : (i +%= 1) {
                if (((@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 0)))]))) == @as(c_int, @bitCast(@as(c_uint, tc[@as(c_uint, @intCast(@as(c_int, 0)))])))) and (@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 1)))]))) == @as(c_int, @bitCast(@as(c_uint, tc[@as(c_uint, @intCast(@as(c_int, 1)))]))))) and (@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 2)))]))) == @as(c_int, @bitCast(@as(c_uint, tc[@as(c_uint, @intCast(@as(c_int, 2)))]))))) {
                    p[@as(c_uint, @intCast(@as(c_int, 3)))] = 0;
                }
                p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            }
        }
    }
    return 1;
}
pub fn stbi__expand_png_palette(arg_a: [*c]stbi__png, arg_palette: [*c]stbi_uc, arg_len: c_int, arg_pal_img_n: c_int) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var palette = arg_palette;
    _ = &palette;
    var len = arg_len;
    _ = &len;
    var pal_img_n = arg_pal_img_n;
    _ = &pal_img_n;
    var i: stbi__uint32 = undefined;
    _ = &i;
    var pixel_count: stbi__uint32 = a.*.s.*.img_x *% a.*.s.*.img_y;
    _ = &pixel_count;
    var p: [*c]stbi_uc = undefined;
    _ = &p;
    var temp_out: [*c]stbi_uc = undefined;
    _ = &temp_out;
    var orig: [*c]stbi_uc = a.*.out;
    _ = &orig;
    p = @as([*c]stbi_uc, @ptrCast(@alignCast(stbi__malloc_mad2(@as(c_int, @bitCast(pixel_count)), pal_img_n, @as(c_int, 0)))));
    if (p == @as([*c]stbi_uc, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return 0;
    temp_out = p;
    if (pal_img_n == @as(c_int, 3)) {
        {
            i = 0;
            while (i < pixel_count) : (i +%= 1) {
                var n: c_int = @as(c_int, @bitCast(@as(c_uint, orig[i]))) * @as(c_int, 4);
                _ = &n;
                p[@as(c_uint, @intCast(@as(c_int, 0)))] = (blk: {
                    const tmp = n;
                    if (tmp >= 0) break :blk palette + @as(usize, @intCast(tmp)) else break :blk palette - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                p[@as(c_uint, @intCast(@as(c_int, 1)))] = (blk: {
                    const tmp = n + @as(c_int, 1);
                    if (tmp >= 0) break :blk palette + @as(usize, @intCast(tmp)) else break :blk palette - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                p[@as(c_uint, @intCast(@as(c_int, 2)))] = (blk: {
                    const tmp = n + @as(c_int, 2);
                    if (tmp >= 0) break :blk palette + @as(usize, @intCast(tmp)) else break :blk palette - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
            }
        }
    } else {
        {
            i = 0;
            while (i < pixel_count) : (i +%= 1) {
                var n: c_int = @as(c_int, @bitCast(@as(c_uint, orig[i]))) * @as(c_int, 4);
                _ = &n;
                p[@as(c_uint, @intCast(@as(c_int, 0)))] = (blk: {
                    const tmp = n;
                    if (tmp >= 0) break :blk palette + @as(usize, @intCast(tmp)) else break :blk palette - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                p[@as(c_uint, @intCast(@as(c_int, 1)))] = (blk: {
                    const tmp = n + @as(c_int, 1);
                    if (tmp >= 0) break :blk palette + @as(usize, @intCast(tmp)) else break :blk palette - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                p[@as(c_uint, @intCast(@as(c_int, 2)))] = (blk: {
                    const tmp = n + @as(c_int, 2);
                    if (tmp >= 0) break :blk palette + @as(usize, @intCast(tmp)) else break :blk palette - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                p[@as(c_uint, @intCast(@as(c_int, 3)))] = (blk: {
                    const tmp = n + @as(c_int, 3);
                    if (tmp >= 0) break :blk palette + @as(usize, @intCast(tmp)) else break :blk palette - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            }
        }
    }
    free(@as(?*anyopaque, @ptrCast(a.*.out)));
    a.*.out = temp_out;
    _ = @sizeOf(c_int);
    return 1;
}
pub var stbi__unpremultiply_on_load_global: c_int = 0;
pub var stbi__de_iphone_flag_global: c_int = 0;
pub threadlocal var stbi__unpremultiply_on_load_local: c_int = @import("std").mem.zeroes(c_int);
pub threadlocal var stbi__unpremultiply_on_load_set: c_int = @import("std").mem.zeroes(c_int);
pub threadlocal var stbi__de_iphone_flag_local: c_int = @import("std").mem.zeroes(c_int);
pub threadlocal var stbi__de_iphone_flag_set: c_int = @import("std").mem.zeroes(c_int);
pub fn stbi__de_iphone(arg_z: [*c]stbi__png) callconv(.c) void {
    var z = arg_z;
    _ = &z;
    var s: [*c]stbi__context = z.*.s;
    _ = &s;
    var i: stbi__uint32 = undefined;
    _ = &i;
    var pixel_count: stbi__uint32 = s.*.img_x *% s.*.img_y;
    _ = &pixel_count;
    var p: [*c]stbi_uc = z.*.out;
    _ = &p;
    if (s.*.img_out_n == @as(c_int, 3)) {
        {
            i = 0;
            while (i < pixel_count) : (i +%= 1) {
                var t: stbi_uc = p[@as(c_uint, @intCast(@as(c_int, 0)))];
                _ = &t;
                p[@as(c_uint, @intCast(@as(c_int, 0)))] = p[@as(c_uint, @intCast(@as(c_int, 2)))];
                p[@as(c_uint, @intCast(@as(c_int, 2)))] = t;
                p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 3)))));
            }
        }
    } else {
        _ = (s.*.img_out_n == @as(c_int, 4)) or ((blk: {
            __assert_fail("s->img_out_n == 4", "/home/x/next/arcan/src/engine/external/stb_image.h", @as(c_int, 5047), "stbi__de_iphone");
            break :blk @as(c_int, 0);
        }) != 0);
        if ((if (stbi__unpremultiply_on_load_set != 0) stbi__unpremultiply_on_load_local else stbi__unpremultiply_on_load_global) != 0) {
            {
                i = 0;
                while (i < pixel_count) : (i +%= 1) {
                    var a: stbi_uc = p[@as(c_uint, @intCast(@as(c_int, 3)))];
                    _ = &a;
                    var t: stbi_uc = p[@as(c_uint, @intCast(@as(c_int, 0)))];
                    _ = &t;
                    if (a != 0) {
                        var half: stbi_uc = @as(stbi_uc, @bitCast(@as(i8, @truncate(@divTrunc(@as(c_int, @bitCast(@as(c_uint, a))), @as(c_int, 2))))));
                        _ = &half;
                        p[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(@divTrunc((@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 2)))]))) * @as(c_int, 255)) + @as(c_int, @bitCast(@as(c_uint, half))), @as(c_int, @bitCast(@as(c_uint, a))))))));
                        p[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(@divTrunc((@as(c_int, @bitCast(@as(c_uint, p[@as(c_uint, @intCast(@as(c_int, 1)))]))) * @as(c_int, 255)) + @as(c_int, @bitCast(@as(c_uint, half))), @as(c_int, @bitCast(@as(c_uint, a))))))));
                        p[@as(c_uint, @intCast(@as(c_int, 2)))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(@divTrunc((@as(c_int, @bitCast(@as(c_uint, t))) * @as(c_int, 255)) + @as(c_int, @bitCast(@as(c_uint, half))), @as(c_int, @bitCast(@as(c_uint, a))))))));
                    } else {
                        p[@as(c_uint, @intCast(@as(c_int, 0)))] = p[@as(c_uint, @intCast(@as(c_int, 2)))];
                        p[@as(c_uint, @intCast(@as(c_int, 2)))] = t;
                    }
                    p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                }
            }
        } else {
            {
                i = 0;
                while (i < pixel_count) : (i +%= 1) {
                    var t: stbi_uc = p[@as(c_uint, @intCast(@as(c_int, 0)))];
                    _ = &t;
                    p[@as(c_uint, @intCast(@as(c_int, 0)))] = p[@as(c_uint, @intCast(@as(c_int, 2)))];
                    p[@as(c_uint, @intCast(@as(c_int, 2)))] = t;
                    p += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
                }
            }
        }
    }
}
pub fn stbi__parse_png_file(arg_z: [*c]stbi__png, arg_scan: c_int, arg_req_comp: c_int) callconv(.c) c_int {
    var z = arg_z;
    _ = &z;
    var scan = arg_scan;
    _ = &scan;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var palette: [1024]stbi_uc = undefined;
    _ = &palette;
    var pal_img_n: stbi_uc = 0;
    _ = &pal_img_n;
    var has_trans: stbi_uc = 0;
    _ = &has_trans;
    var tc: [3]stbi_uc = [1]stbi_uc{
        0,
    } ++ [1]stbi_uc{@import("std").mem.zeroes(stbi_uc)} ** 2;
    _ = &tc;
    var tc16: [3]stbi__uint16 = undefined;
    _ = &tc16;
    var ioff: stbi__uint32 = 0;
    _ = &ioff;
    var idata_limit: stbi__uint32 = 0;
    _ = &idata_limit;
    var i: stbi__uint32 = undefined;
    _ = &i;
    var pal_len: stbi__uint32 = 0;
    _ = &pal_len;
    var first: c_int = 1;
    _ = &first;
    var k: c_int = undefined;
    _ = &k;
    var interlace: c_int = 0;
    _ = &interlace;
    var color: c_int = 0;
    _ = &color;
    var is_iphone: c_int = 0;
    _ = &is_iphone;
    var s: [*c]stbi__context = z.*.s;
    _ = &s;
    z.*.expanded = null;
    z.*.idata = null;
    z.*.out = null;
    if (!(stbi__check_png_header(s) != 0)) return 0;
    if (scan == STBI__SCAN_type) return 1;
    while (true) {
        var c: stbi__pngchunk = stbi__get_chunk_header(s);
        _ = &c;
        while (true) {
            switch (c.type) {
                @as(c_uint, 1130840649) => {
                    is_iphone = 1;
                    stbi__skip(s, @as(c_int, @bitCast(c.length)));
                    break;
                },
                @as(c_uint, 1229472850) => {
                    {
                        var comp: c_int = undefined;
                        _ = &comp;
                        var filter: c_int = undefined;
                        _ = &filter;
                        if (!(first != 0)) return 0;
                        first = 0;
                        if (c.length != @as(stbi__uint32, @bitCast(@as(c_int, 13)))) return 0;
                        s.*.img_x = stbi__get32be(s);
                        s.*.img_y = stbi__get32be(s);
                        if (s.*.img_y > @as(stbi__uint32, @bitCast(@as(c_int, 1) << @intCast(24)))) return 0;
                        if (s.*.img_x > @as(stbi__uint32, @bitCast(@as(c_int, 1) << @intCast(24)))) return 0;
                        z.*.depth = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
                        if (((((z.*.depth != @as(c_int, 1)) and (z.*.depth != @as(c_int, 2))) and (z.*.depth != @as(c_int, 4))) and (z.*.depth != @as(c_int, 8))) and (z.*.depth != @as(c_int, 16))) return 0;
                        color = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
                        if (color > @as(c_int, 6)) return 0;
                        if ((color == @as(c_int, 3)) and (z.*.depth == @as(c_int, 16))) return 0;
                        if (color == @as(c_int, 3)) {
                            pal_img_n = 3;
                        } else if ((color & @as(c_int, 1)) != 0) return 0;
                        comp = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
                        if (comp != 0) return 0;
                        filter = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
                        if (filter != 0) return 0;
                        interlace = @as(c_int, @bitCast(@as(c_uint, stbi__get8(s))));
                        if (interlace > @as(c_int, 1)) return 0;
                        if (!(s.*.img_x != 0) or !(s.*.img_y != 0)) return 0;
                        if (!(pal_img_n != 0)) {
                            s.*.img_n = (if ((color & @as(c_int, 2)) != 0) @as(c_int, 3) else @as(c_int, 1)) + (if ((color & @as(c_int, 4)) != 0) @as(c_int, 1) else @as(c_int, 0));
                            if (((@as(stbi__uint32, @bitCast(@as(c_int, 1) << @intCast(30))) / s.*.img_x) / @as(stbi__uint32, @bitCast(s.*.img_n))) < s.*.img_y) return 0;
                        } else {
                            s.*.img_n = 1;
                            if (((@as(stbi__uint32, @bitCast(@as(c_int, 1) << @intCast(30))) / s.*.img_x) / @as(stbi__uint32, @bitCast(@as(c_int, 4)))) < s.*.img_y) return 0;
                        }
                        break;
                    }
                },
                @as(c_uint, 1347179589) => {
                    {
                        if (first != 0) return 0;
                        if (c.length > @as(stbi__uint32, @bitCast(@as(c_int, 256) * @as(c_int, 3)))) return 0;
                        pal_len = c.length / @as(stbi__uint32, @bitCast(@as(c_int, 3)));
                        if ((pal_len *% @as(stbi__uint32, @bitCast(@as(c_int, 3)))) != c.length) return 0;
                        {
                            i = 0;
                            while (i < pal_len) : (i +%= 1) {
                                palette[(i *% @as(stbi__uint32, @bitCast(@as(c_int, 4)))) +% @as(stbi__uint32, @bitCast(@as(c_int, 0)))] = stbi__get8(s);
                                palette[(i *% @as(stbi__uint32, @bitCast(@as(c_int, 4)))) +% @as(stbi__uint32, @bitCast(@as(c_int, 1)))] = stbi__get8(s);
                                palette[(i *% @as(stbi__uint32, @bitCast(@as(c_int, 4)))) +% @as(stbi__uint32, @bitCast(@as(c_int, 2)))] = stbi__get8(s);
                                palette[(i *% @as(stbi__uint32, @bitCast(@as(c_int, 4)))) +% @as(stbi__uint32, @bitCast(@as(c_int, 3)))] = 255;
                            }
                        }
                        break;
                    }
                },
                @as(c_uint, 1951551059) => {
                    {
                        if (first != 0) return 0;
                        if (z.*.idata != null) return 0;
                        if (pal_img_n != 0) {
                            if (scan == STBI__SCAN_header) {
                                s.*.img_n = 4;
                                return 1;
                            }
                            if (pal_len == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) return 0;
                            if (c.length > pal_len) return 0;
                            pal_img_n = 4;
                            {
                                i = 0;
                                while (i < c.length) : (i +%= 1) {
                                    palette[(i *% @as(stbi__uint32, @bitCast(@as(c_int, 4)))) +% @as(stbi__uint32, @bitCast(@as(c_int, 3)))] = stbi__get8(s);
                                }
                            }
                        } else {
                            if (!((s.*.img_n & @as(c_int, 1)) != 0)) return 0;
                            if (c.length != (@as(stbi__uint32, @bitCast(s.*.img_n)) *% @as(stbi__uint32, @bitCast(@as(c_int, 2))))) return 0;
                            has_trans = 1;
                            if (scan == STBI__SCAN_header) {
                                s.*.img_n += 1;
                                return 1;
                            }
                            if (z.*.depth == @as(c_int, 16)) {
                                {
                                    k = 0;
                                    while ((k < s.*.img_n) and (k < @as(c_int, 3))) : (k += 1) {
                                        tc16[@as(c_uint, @intCast(k))] = @as(stbi__uint16, @bitCast(@as(c_short, @truncate(stbi__get16be(s)))));
                                    }
                                }
                            } else {
                                {
                                    k = 0;
                                    while ((k < s.*.img_n) and (k < @as(c_int, 3))) : (k += 1) {
                                        tc[@as(c_uint, @intCast(k))] = @as(stbi_uc, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, @as(stbi_uc, @bitCast(@as(i8, @truncate(stbi__get16be(s) & @as(c_int, 255)))))))) * @as(c_int, @bitCast(@as(c_uint, stbi__depth_scale_table[@as(c_uint, @intCast(z.*.depth))])))))));
                                    }
                                }
                            }
                        }
                        break;
                    }
                },
                @as(c_uint, 1229209940) => {
                    {
                        if (first != 0) return 0;
                        if ((@as(c_int, @bitCast(@as(c_uint, pal_img_n))) != 0) and !(pal_len != 0)) return 0;
                        if (scan == STBI__SCAN_header) {
                            if (pal_img_n != 0) {
                                s.*.img_n = @as(c_int, @bitCast(@as(c_uint, pal_img_n)));
                            }
                            return 1;
                        }
                        if (c.length > (@as(c_uint, 1) << @intCast(30))) return 0;
                        if (@as(c_int, @bitCast(ioff +% c.length)) < @as(c_int, @bitCast(ioff))) return 0;
                        if ((ioff +% c.length) > idata_limit) {
                            var idata_limit_old: stbi__uint32 = idata_limit;
                            _ = &idata_limit_old;
                            var p: [*c]stbi_uc = undefined;
                            _ = &p;
                            if (idata_limit == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) {
                                idata_limit = if (c.length > @as(stbi__uint32, @bitCast(@as(c_int, 4096)))) c.length else @as(stbi__uint32, @bitCast(@as(c_int, 4096)));
                            }
                            while ((ioff +% c.length) > idata_limit) {
                                idata_limit *%= @as(stbi__uint32, @bitCast(@as(c_int, 2)));
                            }
                            _ = @sizeOf(stbi__uint32);
                            p = @as([*c]stbi_uc, @ptrCast(@alignCast(realloc(@as(?*anyopaque, @ptrCast(z.*.idata)), @as(c_ulong, @bitCast(@as(c_ulong, idata_limit)))))));
                            if (p == @as([*c]stbi_uc, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return 0;
                            z.*.idata = p;
                        }
                        if (!(stbi__getn(s, z.*.idata + ioff, @as(c_int, @bitCast(c.length))) != 0)) return 0;
                        ioff +%= c.length;
                        break;
                    }
                },
                @as(c_uint, 1229278788) => {
                    {
                        var raw_len: stbi__uint32 = undefined;
                        _ = &raw_len;
                        var bpl: stbi__uint32 = undefined;
                        _ = &bpl;
                        if (first != 0) return 0;
                        if (scan != STBI__SCAN_load) return 1;
                        if (z.*.idata == @as([*c]stbi_uc, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return 0;
                        bpl = ((s.*.img_x *% @as(stbi__uint32, @bitCast(z.*.depth))) +% @as(stbi__uint32, @bitCast(@as(c_int, 7)))) / @as(stbi__uint32, @bitCast(@as(c_int, 8)));
                        raw_len = ((bpl *% s.*.img_y) *% @as(stbi__uint32, @bitCast(s.*.img_n))) +% s.*.img_y;
                        z.*.expanded = @as([*c]stbi_uc, @ptrCast(@alignCast(stbi_zlib_decode_malloc_guesssize_headerflag(@as([*c]u8, @ptrCast(@alignCast(z.*.idata))), @as(c_int, @bitCast(ioff)), @as(c_int, @bitCast(raw_len)), @as([*c]c_int, @ptrCast(@alignCast(&raw_len))), @intFromBool(!(is_iphone != 0))))));
                        if (z.*.expanded == @as([*c]stbi_uc, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return 0;
                        free(@as(?*anyopaque, @ptrCast(z.*.idata)));
                        z.*.idata = null;
                        if ((((req_comp == (s.*.img_n + @as(c_int, 1))) and (req_comp != @as(c_int, 3))) and !(pal_img_n != 0)) or (@as(c_int, @bitCast(@as(c_uint, has_trans))) != 0)) {
                            s.*.img_out_n = s.*.img_n + @as(c_int, 1);
                        } else {
                            s.*.img_out_n = s.*.img_n;
                        }
                        if (!(stbi__create_png_image(z, z.*.expanded, raw_len, s.*.img_out_n, z.*.depth, color, interlace) != 0)) return 0;
                        if (has_trans != 0) {
                            if (z.*.depth == @as(c_int, 16)) {
                                if (!(stbi__compute_transparency16(z, @as([*c]stbi__uint16, @ptrCast(@alignCast(&tc16[@as(usize, @intCast(0))]))), s.*.img_out_n) != 0)) return 0;
                            } else {
                                if (!(stbi__compute_transparency(z, @as([*c]stbi_uc, @ptrCast(@alignCast(&tc[@as(usize, @intCast(0))]))), s.*.img_out_n) != 0)) return 0;
                            }
                        }
                        if (((is_iphone != 0) and ((if (stbi__de_iphone_flag_set != 0) stbi__de_iphone_flag_local else stbi__de_iphone_flag_global) != 0)) and (s.*.img_out_n > @as(c_int, 2))) {
                            stbi__de_iphone(z);
                        }
                        if (pal_img_n != 0) {
                            s.*.img_n = @as(c_int, @bitCast(@as(c_uint, pal_img_n)));
                            s.*.img_out_n = @as(c_int, @bitCast(@as(c_uint, pal_img_n)));
                            if (req_comp >= @as(c_int, 3)) {
                                s.*.img_out_n = req_comp;
                            }
                            if (!(stbi__expand_png_palette(z, @as([*c]stbi_uc, @ptrCast(@alignCast(&palette[@as(usize, @intCast(0))]))), @as(c_int, @bitCast(pal_len)), s.*.img_out_n) != 0)) return 0;
                        } else if (has_trans != 0) {
                            s.*.img_n += 1;
                        }
                        free(@as(?*anyopaque, @ptrCast(z.*.expanded)));
                        z.*.expanded = null;
                        _ = stbi__get32be(s);
                        return 1;
                    }
                },
                else => {
                    if (first != 0) return 0;
                    if ((c.type & @as(stbi__uint32, @bitCast(@as(c_int, 1) << @intCast(29)))) == @as(stbi__uint32, @bitCast(@as(c_int, 0)))) {
                        return 0;
                    }
                    stbi__skip(s, @as(c_int, @bitCast(c.length)));
                    break;
                },
            }
            break;
        }
        _ = stbi__get32be(s);
    }
    return 0;
}
pub fn stbi__do_png(arg_p: [*c]stbi__png, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_n: [*c]c_int, arg_req_comp: c_int, arg_ri: [*c]stbi__result_info) callconv(.c) ?*anyopaque {
    var p = arg_p;
    _ = &p;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var n = arg_n;
    _ = &n;
    var req_comp = arg_req_comp;
    _ = &req_comp;
    var ri = arg_ri;
    _ = &ri;
    var result: ?*anyopaque = @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));
    _ = &result;
    if ((req_comp < @as(c_int, 0)) or (req_comp > @as(c_int, 4))) return @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))))));
    if (stbi__parse_png_file(p, STBI__SCAN_load, req_comp) != 0) {
        if (p.*.depth <= @as(c_int, 8)) {
            ri.*.bits_per_channel = 8;
        } else if (p.*.depth == @as(c_int, 16)) {
            ri.*.bits_per_channel = 16;
        } else return @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrFromInt(@as(usize, @intCast(@intFromPtr(if (false) @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))) else @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))))));
        result = @as(?*anyopaque, @ptrCast(p.*.out));
        p.*.out = null;
        if ((req_comp != 0) and (req_comp != p.*.s.*.img_out_n)) {
            if (ri.*.bits_per_channel == @as(c_int, 8)) {
                result = @as(?*anyopaque, @ptrCast(stbi__convert_format(@as([*c]u8, @ptrCast(@alignCast(result))), p.*.s.*.img_out_n, req_comp, p.*.s.*.img_x, p.*.s.*.img_y)));
            } else {
                result = @as(?*anyopaque, @ptrCast(stbi__convert_format16(@as([*c]stbi__uint16, @ptrCast(@alignCast(result))), p.*.s.*.img_out_n, req_comp, p.*.s.*.img_x, p.*.s.*.img_y)));
            }
            p.*.s.*.img_out_n = req_comp;
            if (result == @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))) return result;
        }
        x.* = @as(c_int, @bitCast(p.*.s.*.img_x));
        y.* = @as(c_int, @bitCast(p.*.s.*.img_y));
        if (n != null) {
            n.* = p.*.s.*.img_n;
        }
    }
    free(@as(?*anyopaque, @ptrCast(p.*.out)));
    p.*.out = null;
    free(@as(?*anyopaque, @ptrCast(p.*.expanded)));
    p.*.expanded = null;
    free(@as(?*anyopaque, @ptrCast(p.*.idata)));
    p.*.idata = null;
    return result;
}
pub fn stbi__png_info_raw(arg_p: [*c]stbi__png, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var p = arg_p;
    _ = &p;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    if (!(stbi__parse_png_file(p, STBI__SCAN_header, @as(c_int, 0)) != 0)) {
        stbi__rewind(p.*.s);
        return 0;
    }
    if (x != null) {
        x.* = @as(c_int, @bitCast(p.*.s.*.img_x));
    }
    if (y != null) {
        y.* = @as(c_int, @bitCast(p.*.s.*.img_y));
    }
    if (comp != null) {
        comp.* = p.*.s.*.img_n;
    }
    return 1;
}
pub fn stbi__info_main(arg_s: [*c]stbi__context, arg_x: [*c]c_int, arg_y: [*c]c_int, arg_comp: [*c]c_int) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    if (stbi__jpeg_info(s, x, y, comp) != 0) return 1;
    if (stbi__png_info(s, x, y, comp) != 0) return 1;
    return 0;
}
pub fn stbi__is_16_main(arg_s: [*c]stbi__context) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    if (stbi__png_is16(s) != 0) return 1;
    return 0;
}
pub extern var stbi_write_tga_with_rle: c_int;
pub export var stbi_write_png_compression_level: c_int = 8;
pub export var stbi_write_force_png_filter: c_int = -1;
pub fn stbi_write_png(arg_filename: [*c]const u8, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque, arg_stride_bytes: c_int) callconv(.c) c_int {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var stride_bytes = arg_stride_bytes;
    _ = &stride_bytes;
    var f: ?*FILE = undefined;
    _ = &f;
    var len: c_int = undefined;
    _ = &len;
    var png: [*c]u8 = stbi_write_png_to_mem(@as([*c]const u8, @ptrCast(@alignCast(data))), stride_bytes, x, y, comp, &len);
    _ = &png;
    if (png == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return 0;
    f = stbiw__fopen(filename, "wb");
    if (!(f != null)) {
        free(@as(?*anyopaque, @ptrCast(png)));
        return 0;
    }
    _ = fwrite(@as(?*const anyopaque, @ptrCast(png)), @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))), @as(c_ulong, @bitCast(@as(c_long, len))), f);
    _ = fclose(f);
    free(@as(?*anyopaque, @ptrCast(png)));
    return 1;
}
pub fn stbi_write_bmp(arg_filename: [*c]const u8, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque) callconv(.c) c_int {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var s: stbi__write_context = stbi__write_context{
        .func = null,
        .context = null,
        .buffer = @import("std").mem.zeroes([64]u8),
        .buf_used = 0,
    };
    _ = &s;
    if (stbi__start_write_file(&s, filename) != 0) {
        var r: c_int = stbi_write_bmp_core(&s, x, y, comp, data);
        _ = &r;
        stbi__end_write_file(&s);
        return r;
    } else return 0;
    return 0;
}
pub fn stbi_write_tga(arg_filename: [*c]const u8, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque) callconv(.c) c_int {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var s: stbi__write_context = stbi__write_context{
        .func = null,
        .context = null,
        .buffer = @import("std").mem.zeroes([64]u8),
        .buf_used = 0,
    };
    _ = &s;
    if (stbi__start_write_file(&s, filename) != 0) {
        var r: c_int = stbi_write_tga_core(&s, x, y, comp, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(data)))));
        _ = &r;
        stbi__end_write_file(&s);
        return r;
    } else return 0;
    return 0;
}
pub fn stbi_write_hdr(arg_filename: [*c]const u8, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: [*c]const f32) callconv(.c) c_int {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var s: stbi__write_context = stbi__write_context{
        .func = null,
        .context = null,
        .buffer = @import("std").mem.zeroes([64]u8),
        .buf_used = 0,
    };
    _ = &s;
    if (stbi__start_write_file(&s, filename) != 0) {
        var r: c_int = stbi_write_hdr_core(&s, x, y, comp, @as([*c]f32, @ptrCast(@constCast(@volatileCast(data)))));
        _ = &r;
        stbi__end_write_file(&s);
        return r;
    } else return 0;
    return 0;
}
pub fn stbi_write_jpg(arg_filename: [*c]const u8, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque, arg_quality: c_int) callconv(.c) c_int {
    var filename = arg_filename;
    _ = &filename;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var quality = arg_quality;
    _ = &quality;
    var s: stbi__write_context = stbi__write_context{
        .func = null,
        .context = null,
        .buffer = @import("std").mem.zeroes([64]u8),
        .buf_used = 0,
    };
    _ = &s;
    if (stbi__start_write_file(&s, filename) != 0) {
        var r: c_int = stbi_write_jpg_core(&s, x, y, comp, data, quality);
        _ = &r;
        stbi__end_write_file(&s);
        return r;
    } else return 0;
    return 0;
}
pub const stbi_write_func = fn (?*anyopaque, ?*anyopaque, c_int) callconv(.c) void;
pub fn stbi_write_png_to_func(arg_func: ?*const stbi_write_func, arg_context: ?*anyopaque, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque, arg_stride_bytes: c_int) callconv(.c) c_int {
    var func = arg_func;
    _ = &func;
    var context = arg_context;
    _ = &context;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var stride_bytes = arg_stride_bytes;
    _ = &stride_bytes;
    var len: c_int = undefined;
    _ = &len;
    var png: [*c]u8 = stbi_write_png_to_mem(@as([*c]const u8, @ptrCast(@alignCast(data))), stride_bytes, x, y, comp, &len);
    _ = &png;
    if (png == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return 0;
    func.?(context, @as(?*anyopaque, @ptrCast(png)), len);
    free(@as(?*anyopaque, @ptrCast(png)));
    return 1;
}
pub fn stbi_write_bmp_to_func(arg_func: ?*const stbi_write_func, arg_context: ?*anyopaque, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque) callconv(.c) c_int {
    var func = arg_func;
    _ = &func;
    var context = arg_context;
    _ = &context;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var s: stbi__write_context = stbi__write_context{
        .func = null,
        .context = null,
        .buffer = @import("std").mem.zeroes([64]u8),
        .buf_used = 0,
    };
    _ = &s;
    stbi__start_write_callbacks(&s, func, context);
    return stbi_write_bmp_core(&s, x, y, comp, data);
}
pub fn stbi_write_tga_to_func(arg_func: ?*const stbi_write_func, arg_context: ?*anyopaque, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque) callconv(.c) c_int {
    var func = arg_func;
    _ = &func;
    var context = arg_context;
    _ = &context;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var s: stbi__write_context = stbi__write_context{
        .func = null,
        .context = null,
        .buffer = @import("std").mem.zeroes([64]u8),
        .buf_used = 0,
    };
    _ = &s;
    stbi__start_write_callbacks(&s, func, context);
    return stbi_write_tga_core(&s, x, y, comp, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(data)))));
}
pub fn stbi_write_hdr_to_func(arg_func: ?*const stbi_write_func, arg_context: ?*anyopaque, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: [*c]const f32) callconv(.c) c_int {
    var func = arg_func;
    _ = &func;
    var context = arg_context;
    _ = &context;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var s: stbi__write_context = stbi__write_context{
        .func = null,
        .context = null,
        .buffer = @import("std").mem.zeroes([64]u8),
        .buf_used = 0,
    };
    _ = &s;
    stbi__start_write_callbacks(&s, func, context);
    return stbi_write_hdr_core(&s, x, y, comp, @as([*c]f32, @ptrCast(@constCast(@volatileCast(data)))));
}
pub fn stbi_write_jpg_to_func(arg_func: ?*const stbi_write_func, arg_context: ?*anyopaque, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque, arg_quality: c_int) callconv(.c) c_int {
    var func = arg_func;
    _ = &func;
    var context = arg_context;
    _ = &context;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var quality = arg_quality;
    _ = &quality;
    var s: stbi__write_context = stbi__write_context{
        .func = null,
        .context = null,
        .buffer = @import("std").mem.zeroes([64]u8),
        .buf_used = 0,
    };
    _ = &s;
    stbi__start_write_callbacks(&s, func, context);
    return stbi_write_jpg_core(&s, x, y, comp, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(data)))), quality);
}
pub fn stbi_flip_vertically_on_write(arg_flag: c_int) callconv(.c) void {
    var flag = arg_flag;
    _ = &flag;
    stbi__flip_vertically_on_write = flag;
}
pub var stbi__flip_vertically_on_write: c_int = 0;
pub const stbi__write_context = extern struct {
    func: ?*const stbi_write_func = @import("std").mem.zeroes(?*const stbi_write_func),
    context: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    buffer: [64]u8 = @import("std").mem.zeroes([64]u8),
    buf_used: c_int = @import("std").mem.zeroes(c_int),
};
pub fn stbi__start_write_callbacks(arg_s: [*c]stbi__write_context, arg_c: ?*const stbi_write_func, arg_context: ?*anyopaque) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var c = arg_c;
    _ = &c;
    var context = arg_context;
    _ = &context;
    s.*.func = c;
    s.*.context = context;
}
pub fn stbi__stdio_write(arg_context: ?*anyopaque, arg_data: ?*anyopaque, arg_size: c_int) callconv(.c) void {
    var context = arg_context;
    _ = &context;
    var data = arg_data;
    _ = &data;
    var size = arg_size;
    _ = &size;
    _ = fwrite(data, @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))), @as(c_ulong, @bitCast(@as(c_long, size))), @as(?*FILE, @ptrCast(context)));
}
pub fn stbiw__fopen(arg_filename: [*c]const u8, arg_mode: [*c]const u8) callconv(.c) ?*FILE {
    var filename = arg_filename;
    _ = &filename;
    var mode = arg_mode;
    _ = &mode;
    var f: ?*FILE = undefined;
    _ = &f;
    f = fopen(filename, mode);
    return f;
}
pub fn stbi__start_write_file(arg_s: [*c]stbi__write_context, arg_filename: [*c]const u8) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var filename = arg_filename;
    _ = &filename;
    var f: ?*FILE = stbiw__fopen(filename, "wb");
    _ = &f;
    stbi__start_write_callbacks(s, &stbi__stdio_write, @as(?*anyopaque, @ptrCast(f)));
    return @intFromBool(f != @as(?*FILE, @ptrCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))));
}
pub fn stbi__end_write_file(arg_s: [*c]stbi__write_context) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    _ = fclose(@as(?*FILE, @ptrCast(s.*.context)));
}
pub const stbiw_uint32 = c_uint;
pub const stb_image_write_test = [1]c_int;
// /usr/local/zig-aarch64-linux-0.15.2/lib/include/__stdarg_va_arg.h:20:26: warning: unsupported stmt class VAArgExprClass

// /home/x/next/arcan/src/engine/external/stb_image_write.h:349:13: warning: unable to translate function, demoted to extern
pub extern fn stbiw__writefv(arg_s: [*c]stbi__write_context, arg_fmt: [*c]const u8, arg_v: va_list) callconv(.c) void;
// /home/x/next/arcan/src/engine/external/stb_image_write.h:378:13: warning: TODO unable to translate variadic function, demoted to extern
pub extern fn stbiw__writef(s: [*c]stbi__write_context, fmt: [*c]const u8, ...) void;
pub fn stbiw__write_flush(arg_s: [*c]stbi__write_context) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    if (s.*.buf_used != 0) {
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(&s.*.buffer)), s.*.buf_used);
        s.*.buf_used = 0;
    }
}
pub fn stbiw__putc(arg_s: [*c]stbi__write_context, arg_c: u8) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var c = arg_c;
    _ = &c;
    s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(&c)), @as(c_int, 1));
}
pub fn stbiw__write1(arg_s: [*c]stbi__write_context, arg_a: u8) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var a = arg_a;
    _ = &a;
    if ((@as(usize, @bitCast(@as(c_long, s.*.buf_used))) +% @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) > @sizeOf([64]u8)) {
        stbiw__write_flush(s);
    }
    s.*.buffer[@as(c_uint, @intCast(blk: {
        const ref = &s.*.buf_used;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }))] = a;
}
pub fn stbiw__write3(arg_s: [*c]stbi__write_context, arg_a: u8, arg_b: u8, arg_c: u8) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var c = arg_c;
    _ = &c;
    var n: c_int = undefined;
    _ = &n;
    if ((@as(usize, @bitCast(@as(c_long, s.*.buf_used))) +% @as(usize, @bitCast(@as(c_long, @as(c_int, 3))))) > @sizeOf([64]u8)) {
        stbiw__write_flush(s);
    }
    n = s.*.buf_used;
    s.*.buf_used = n + @as(c_int, 3);
    s.*.buffer[@as(c_uint, @intCast(n + @as(c_int, 0)))] = a;
    s.*.buffer[@as(c_uint, @intCast(n + @as(c_int, 1)))] = b;
    s.*.buffer[@as(c_uint, @intCast(n + @as(c_int, 2)))] = c;
}
pub fn stbiw__write_pixel(arg_s: [*c]stbi__write_context, arg_rgb_dir: c_int, arg_comp: c_int, arg_write_alpha: c_int, arg_expand_mono: c_int, arg_d: [*c]u8) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var rgb_dir = arg_rgb_dir;
    _ = &rgb_dir;
    var comp = arg_comp;
    _ = &comp;
    var write_alpha = arg_write_alpha;
    _ = &write_alpha;
    var expand_mono = arg_expand_mono;
    _ = &expand_mono;
    var d = arg_d;
    _ = &d;
    var bg: [3]u8 = [3]u8{
        255,
        0,
        255,
    };
    _ = &bg;
    var px: [3]u8 = undefined;
    _ = &px;
    var k: c_int = undefined;
    _ = &k;
    if (write_alpha < @as(c_int, 0)) {
        stbiw__write1(s, (blk: {
            const tmp = comp - @as(c_int, 1);
            if (tmp >= 0) break :blk d + @as(usize, @intCast(tmp)) else break :blk d - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*);
    }
    while (true) {
        switch (comp) {
            @as(c_int, 2), @as(c_int, 1) => {
                if (expand_mono != 0) {
                    stbiw__write3(s, d[@as(c_uint, @intCast(@as(c_int, 0)))], d[@as(c_uint, @intCast(@as(c_int, 0)))], d[@as(c_uint, @intCast(@as(c_int, 0)))]);
                } else {
                    stbiw__write1(s, d[@as(c_uint, @intCast(@as(c_int, 0)))]);
                }
                break;
            },
            @as(c_int, 4) => {
                if (!(write_alpha != 0)) {
                    {
                        k = 0;
                        while (k < @as(c_int, 3)) : (k += 1) {
                            px[@as(c_uint, @intCast(k))] = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, bg[@as(c_uint, @intCast(k))]))) + @divTrunc((@as(c_int, @bitCast(@as(c_uint, (blk: {
                                const tmp = k;
                                if (tmp >= 0) break :blk d + @as(usize, @intCast(tmp)) else break :blk d - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).*))) - @as(c_int, @bitCast(@as(c_uint, bg[@as(c_uint, @intCast(k))])))) * @as(c_int, @bitCast(@as(c_uint, d[@as(c_uint, @intCast(@as(c_int, 3)))]))), @as(c_int, 255))))));
                        }
                    }
                    stbiw__write3(s, px[@as(c_uint, @intCast(@as(c_int, 1) - rgb_dir))], px[@as(c_uint, @intCast(@as(c_int, 1)))], px[@as(c_uint, @intCast(@as(c_int, 1) + rgb_dir))]);
                    break;
                }
                stbiw__write3(s, (blk: {
                    const tmp = @as(c_int, 1) - rgb_dir;
                    if (tmp >= 0) break :blk d + @as(usize, @intCast(tmp)) else break :blk d - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*, d[@as(c_uint, @intCast(@as(c_int, 1)))], (blk: {
                    const tmp = @as(c_int, 1) + rgb_dir;
                    if (tmp >= 0) break :blk d + @as(usize, @intCast(tmp)) else break :blk d - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*);
                break;
            },
            @as(c_int, 3) => {
                stbiw__write3(s, (blk: {
                    const tmp = @as(c_int, 1) - rgb_dir;
                    if (tmp >= 0) break :blk d + @as(usize, @intCast(tmp)) else break :blk d - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*, d[@as(c_uint, @intCast(@as(c_int, 1)))], (blk: {
                    const tmp = @as(c_int, 1) + rgb_dir;
                    if (tmp >= 0) break :blk d + @as(usize, @intCast(tmp)) else break :blk d - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*);
                break;
            },
            else => {},
        }
        break;
    }
    if (write_alpha > @as(c_int, 0)) {
        stbiw__write1(s, (blk: {
            const tmp = comp - @as(c_int, 1);
            if (tmp >= 0) break :blk d + @as(usize, @intCast(tmp)) else break :blk d - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*);
    }
}
pub fn stbiw__write_pixels(arg_s: [*c]stbi__write_context, arg_rgb_dir: c_int, arg_vdir: c_int, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*anyopaque, arg_write_alpha: c_int, arg_scanline_pad: c_int, arg_expand_mono: c_int) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var rgb_dir = arg_rgb_dir;
    _ = &rgb_dir;
    var vdir = arg_vdir;
    _ = &vdir;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var write_alpha = arg_write_alpha;
    _ = &write_alpha;
    var scanline_pad = arg_scanline_pad;
    _ = &scanline_pad;
    var expand_mono = arg_expand_mono;
    _ = &expand_mono;
    var zero: stbiw_uint32 = 0;
    _ = &zero;
    var i: c_int = undefined;
    _ = &i;
    var j: c_int = undefined;
    _ = &j;
    var j_end: c_int = undefined;
    _ = &j_end;
    if (y <= @as(c_int, 0)) return;
    if (stbi__flip_vertically_on_write != 0) {
        vdir *= -@as(c_int, 1);
    }
    if (vdir < @as(c_int, 0)) {
        j_end = -@as(c_int, 1);
        j = y - @as(c_int, 1);
    } else {
        j_end = y;
        j = 0;
    }
    while (j != j_end) : (j += vdir) {
        {
            i = 0;
            while (i < x) : (i += 1) {
                var d: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(data))) + @as(usize, @bitCast(@as(isize, @intCast(((j * x) + i) * comp))));
                _ = &d;
                stbiw__write_pixel(s, rgb_dir, comp, write_alpha, expand_mono, d);
            }
        }
        stbiw__write_flush(s);
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(&zero)), scanline_pad);
    }
}
// /home/x/next/arcan/src/engine/external/stb_image_write.h:478:12: warning: TODO unable to translate variadic function, demoted to extern
pub extern fn stbiw__outfile(s: [*c]stbi__write_context, rgb_dir: c_int, vdir: c_int, x: c_int, y: c_int, comp: c_int, expand_mono: c_int, data: ?*anyopaque, alpha: c_int, pad: c_int, fmt: [*c]const u8, ...) c_int;
pub fn stbi_write_bmp_core(arg_s: [*c]stbi__write_context, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*const anyopaque) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    if (comp != @as(c_int, 4)) {
        var pad: c_int = (-x * @as(c_int, 3)) & @as(c_int, 3);
        _ = &pad;
        return stbiw__outfile(s, -@as(c_int, 1), -@as(c_int, 1), x, y, comp, @as(c_int, 1), @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(data)))), @as(c_int, 0), pad, "11 4 22 44 44 22 444444", @as(c_int, 'B'), @as(c_int, 'M'), (@as(c_int, 14) + @as(c_int, 40)) + (((x * @as(c_int, 3)) + pad) * y), @as(c_int, 0), @as(c_int, 0), @as(c_int, 14) + @as(c_int, 40), @as(c_int, 40), x, y, @as(c_int, 1), @as(c_int, 24), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0));
    } else {
        return stbiw__outfile(s, -@as(c_int, 1), -@as(c_int, 1), x, y, comp, @as(c_int, 1), @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(data)))), @as(c_int, 1), @as(c_int, 0), "11 4 22 44 44 22 444444 4444 4 444 444 444 444", @as(c_int, 'B'), @as(c_int, 'M'), (@as(c_int, 14) + @as(c_int, 108)) + ((x * y) * @as(c_int, 4)), @as(c_int, 0), @as(c_int, 0), @as(c_int, 14) + @as(c_int, 108), @as(c_int, 108), x, y, @as(c_int, 1), @as(c_int, 32), @as(c_int, 3), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 16711680), @as(c_int, 65280), @as(c_int, 255), @as(c_uint, 4278190080), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0));
    }
    return 0;
}
pub fn stbi_write_tga_core(arg_s: [*c]stbi__write_context, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: ?*anyopaque) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var has_alpha: c_int = @intFromBool((comp == @as(c_int, 2)) or (comp == @as(c_int, 4)));
    _ = &has_alpha;
    var colorbytes: c_int = if (has_alpha != 0) comp - @as(c_int, 1) else comp;
    _ = &colorbytes;
    var format: c_int = if (colorbytes < @as(c_int, 2)) @as(c_int, 3) else @as(c_int, 2);
    _ = &format;
    if ((y < @as(c_int, 0)) or (x < @as(c_int, 0))) return 0;
    if (!(stbi_write_tga_with_rle != 0)) {
        return stbiw__outfile(s, -@as(c_int, 1), -@as(c_int, 1), x, y, comp, @as(c_int, 0), data, has_alpha, @as(c_int, 0), "111 221 2222 11", @as(c_int, 0), @as(c_int, 0), format, @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), x, y, (colorbytes + has_alpha) * @as(c_int, 8), has_alpha * @as(c_int, 8));
    } else {
        var i: c_int = undefined;
        _ = &i;
        var j: c_int = undefined;
        _ = &j;
        var k: c_int = undefined;
        _ = &k;
        var jend: c_int = undefined;
        _ = &jend;
        var jdir: c_int = undefined;
        _ = &jdir;
        stbiw__writef(s, "111 221 2222 11", @as(c_int, 0), @as(c_int, 0), format + @as(c_int, 8), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), x, y, (colorbytes + has_alpha) * @as(c_int, 8), has_alpha * @as(c_int, 8));
        if (stbi__flip_vertically_on_write != 0) {
            j = 0;
            jend = y;
            jdir = 1;
        } else {
            j = y - @as(c_int, 1);
            jend = -@as(c_int, 1);
            jdir = -@as(c_int, 1);
        }
        while (j != jend) : (j += jdir) {
            var row: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(data))) + @as(usize, @bitCast(@as(isize, @intCast((j * x) * comp))));
            _ = &row;
            var len: c_int = undefined;
            _ = &len;
            {
                i = 0;
                while (i < x) : (i += len) {
                    var begin: [*c]u8 = row + @as(usize, @bitCast(@as(isize, @intCast(i * comp))));
                    _ = &begin;
                    var diff: c_int = 1;
                    _ = &diff;
                    len = 1;
                    if (i < (x - @as(c_int, 1))) {
                        len += 1;
                        diff = memcmp(@as(?*const anyopaque, @ptrCast(begin)), @as(?*const anyopaque, @ptrCast(row + @as(usize, @bitCast(@as(isize, @intCast((i + @as(c_int, 1)) * comp)))))), @as(c_ulong, @bitCast(@as(c_long, comp))));
                        if (diff != 0) {
                            var prev: [*c]const u8 = begin;
                            _ = &prev;
                            {
                                k = i + @as(c_int, 2);
                                while ((k < x) and (len < @as(c_int, 128))) : (k += 1) {
                                    if (memcmp(@as(?*const anyopaque, @ptrCast(prev)), @as(?*const anyopaque, @ptrCast(row + @as(usize, @bitCast(@as(isize, @intCast(k * comp)))))), @as(c_ulong, @bitCast(@as(c_long, comp)))) != 0) {
                                        prev += @as(usize, @bitCast(@as(isize, @intCast(comp))));
                                        len += 1;
                                    } else {
                                        len -= 1;
                                        break;
                                    }
                                }
                            }
                        } else {
                            {
                                k = i + @as(c_int, 2);
                                while ((k < x) and (len < @as(c_int, 128))) : (k += 1) {
                                    if (!(memcmp(@as(?*const anyopaque, @ptrCast(begin)), @as(?*const anyopaque, @ptrCast(row + @as(usize, @bitCast(@as(isize, @intCast(k * comp)))))), @as(c_ulong, @bitCast(@as(c_long, comp)))) != 0)) {
                                        len += 1;
                                    } else {
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    if (diff != 0) {
                        var header: u8 = @as(u8, @bitCast(@as(i8, @truncate((len - @as(c_int, 1)) & @as(c_int, 255)))));
                        _ = &header;
                        stbiw__write1(s, header);
                        {
                            k = 0;
                            while (k < len) : (k += 1) {
                                stbiw__write_pixel(s, -@as(c_int, 1), comp, has_alpha, @as(c_int, 0), begin + @as(usize, @bitCast(@as(isize, @intCast(k * comp)))));
                            }
                        }
                    } else {
                        var header: u8 = @as(u8, @bitCast(@as(i8, @truncate((len - @as(c_int, 129)) & @as(c_int, 255)))));
                        _ = &header;
                        stbiw__write1(s, header);
                        stbiw__write_pixel(s, -@as(c_int, 1), comp, has_alpha, @as(c_int, 0), begin);
                    }
                }
            }
        }
        stbiw__write_flush(s);
    }
    return 1;
}
pub fn stbiw__linear_to_rgbe(arg_rgbe: [*c]u8, arg_linear: [*c]f32) callconv(.c) void {
    var rgbe = arg_rgbe;
    _ = &rgbe;
    var linear = arg_linear;
    _ = &linear;
    var exponent: c_int = undefined;
    _ = &exponent;
    var maxcomp: f32 = if (linear[@as(c_uint, @intCast(@as(c_int, 0)))] > (if (linear[@as(c_uint, @intCast(@as(c_int, 1)))] > linear[@as(c_uint, @intCast(@as(c_int, 2)))]) linear[@as(c_uint, @intCast(@as(c_int, 1)))] else linear[@as(c_uint, @intCast(@as(c_int, 2)))])) linear[@as(c_uint, @intCast(@as(c_int, 0)))] else if (linear[@as(c_uint, @intCast(@as(c_int, 1)))] > linear[@as(c_uint, @intCast(@as(c_int, 2)))]) linear[@as(c_uint, @intCast(@as(c_int, 1)))] else linear[@as(c_uint, @intCast(@as(c_int, 2)))];
    _ = &maxcomp;
    if (maxcomp < 0.00000000000000000000000000000001000000023742228) {
        rgbe[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
            const tmp = blk_1: {
                const tmp_2 = blk_2: {
                    const tmp_3 = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 0)))));
                    rgbe[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp_3;
                    break :blk_2 tmp_3;
                };
                rgbe[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                break :blk_1 tmp_2;
            };
            rgbe[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
            break :blk tmp;
        };
    } else {
        var normalize: f32 = (@as(f32, @floatCast(frexp(@as(f64, @floatCast(maxcomp)), &exponent))) * 256.0) / maxcomp;
        _ = &normalize;
        rgbe[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @intFromFloat(linear[@as(c_uint, @intCast(@as(c_int, 0)))] * normalize));
        rgbe[@as(c_uint, @intCast(@as(c_int, 1)))] = @as(u8, @intFromFloat(linear[@as(c_uint, @intCast(@as(c_int, 1)))] * normalize));
        rgbe[@as(c_uint, @intCast(@as(c_int, 2)))] = @as(u8, @intFromFloat(linear[@as(c_uint, @intCast(@as(c_int, 2)))] * normalize));
        rgbe[@as(c_uint, @intCast(@as(c_int, 3)))] = @as(u8, @bitCast(@as(i8, @truncate(exponent + @as(c_int, 128)))));
    }
}
pub fn stbiw__write_run_data(arg_s: [*c]stbi__write_context, arg_length: c_int, arg_databyte: u8) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var length = arg_length;
    _ = &length;
    var databyte = arg_databyte;
    _ = &databyte;
    var lengthbyte: u8 = @as(u8, @bitCast(@as(i8, @truncate((length + @as(c_int, 128)) & @as(c_int, 255)))));
    _ = &lengthbyte;
    _ = ((length + @as(c_int, 128)) <= @as(c_int, 255)) or ((blk: {
        __assert_fail("length+128 <= 255", "/home/x/next/arcan/src/engine/external/stb_image_write.h", @as(c_int, 659), "stbiw__write_run_data");
        break :blk @as(c_int, 0);
    }) != 0);
    s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(&lengthbyte)), @as(c_int, 1));
    s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(&databyte)), @as(c_int, 1));
}
pub fn stbiw__write_dump_data(arg_s: [*c]stbi__write_context, arg_length: c_int, arg_data: [*c]u8) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var length = arg_length;
    _ = &length;
    var data = arg_data;
    _ = &data;
    var lengthbyte: u8 = @as(u8, @bitCast(@as(i8, @truncate(length & @as(c_int, 255)))));
    _ = &lengthbyte;
    _ = (length <= @as(c_int, 128)) or ((blk: {
        __assert_fail("length <= 128", "/home/x/next/arcan/src/engine/external/stb_image_write.h", @as(c_int, 667), "stbiw__write_dump_data");
        break :blk @as(c_int, 0);
    }) != 0);
    s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(&lengthbyte)), @as(c_int, 1));
    s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(data)), length);
}
pub fn stbiw__write_hdr_scanline(arg_s: [*c]stbi__write_context, arg_width: c_int, arg_ncomp: c_int, arg_scratch: [*c]u8, arg_scanline: [*c]f32) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var width = arg_width;
    _ = &width;
    var ncomp = arg_ncomp;
    _ = &ncomp;
    var scratch = arg_scratch;
    _ = &scratch;
    var scanline = arg_scanline;
    _ = &scanline;
    var scanlineheader: [4]u8 = [4]u8{
        2,
        2,
        0,
        0,
    };
    _ = &scanlineheader;
    var rgbe: [4]u8 = undefined;
    _ = &rgbe;
    var linear: [3]f32 = undefined;
    _ = &linear;
    var x: c_int = undefined;
    _ = &x;
    scanlineheader[@as(c_uint, @intCast(@as(c_int, 2)))] = @as(u8, @bitCast(@as(i8, @truncate((width & @as(c_int, 65280)) >> @intCast(8)))));
    scanlineheader[@as(c_uint, @intCast(@as(c_int, 3)))] = @as(u8, @bitCast(@as(i8, @truncate(width & @as(c_int, 255)))));
    if ((width < @as(c_int, 8)) or (width >= @as(c_int, 32768))) {
        {
            x = 0;
            while (x < width) : (x += 1) {
                while (true) {
                    switch (ncomp) {
                        @as(c_int, 4), @as(c_int, 3) => {
                            linear[@as(c_uint, @intCast(@as(c_int, 2)))] = (blk: {
                                const tmp = (x * ncomp) + @as(c_int, 2);
                                if (tmp >= 0) break :blk scanline + @as(usize, @intCast(tmp)) else break :blk scanline - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).*;
                            linear[@as(c_uint, @intCast(@as(c_int, 1)))] = (blk: {
                                const tmp = (x * ncomp) + @as(c_int, 1);
                                if (tmp >= 0) break :blk scanline + @as(usize, @intCast(tmp)) else break :blk scanline - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).*;
                            linear[@as(c_uint, @intCast(@as(c_int, 0)))] = (blk: {
                                const tmp = (x * ncomp) + @as(c_int, 0);
                                if (tmp >= 0) break :blk scanline + @as(usize, @intCast(tmp)) else break :blk scanline - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).*;
                            break;
                        },
                        else => {
                            linear[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                const tmp = blk_1: {
                                    const tmp_2 = (blk_2: {
                                        const tmp_3 = (x * ncomp) + @as(c_int, 0);
                                        if (tmp_3 >= 0) break :blk_2 scanline + @as(usize, @intCast(tmp_3)) else break :blk_2 scanline - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                                    }).*;
                                    linear[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                    break :blk_1 tmp_2;
                                };
                                linear[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                break :blk tmp;
                            };
                            break;
                        },
                    }
                    break;
                }
                stbiw__linear_to_rgbe(@as([*c]u8, @ptrCast(@alignCast(&rgbe[@as(usize, @intCast(0))]))), @as([*c]f32, @ptrCast(@alignCast(&linear[@as(usize, @intCast(0))]))));
                s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&rgbe[@as(usize, @intCast(0))]))))), @as(c_int, 4));
            }
        }
    } else {
        var c: c_int = undefined;
        _ = &c;
        var r: c_int = undefined;
        _ = &r;
        {
            x = 0;
            while (x < width) : (x += 1) {
                while (true) {
                    switch (ncomp) {
                        @as(c_int, 4), @as(c_int, 3) => {
                            linear[@as(c_uint, @intCast(@as(c_int, 2)))] = (blk: {
                                const tmp = (x * ncomp) + @as(c_int, 2);
                                if (tmp >= 0) break :blk scanline + @as(usize, @intCast(tmp)) else break :blk scanline - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).*;
                            linear[@as(c_uint, @intCast(@as(c_int, 1)))] = (blk: {
                                const tmp = (x * ncomp) + @as(c_int, 1);
                                if (tmp >= 0) break :blk scanline + @as(usize, @intCast(tmp)) else break :blk scanline - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).*;
                            linear[@as(c_uint, @intCast(@as(c_int, 0)))] = (blk: {
                                const tmp = (x * ncomp) + @as(c_int, 0);
                                if (tmp >= 0) break :blk scanline + @as(usize, @intCast(tmp)) else break :blk scanline - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).*;
                            break;
                        },
                        else => {
                            linear[@as(c_uint, @intCast(@as(c_int, 0)))] = blk: {
                                const tmp = blk_1: {
                                    const tmp_2 = (blk_2: {
                                        const tmp_3 = (x * ncomp) + @as(c_int, 0);
                                        if (tmp_3 >= 0) break :blk_2 scanline + @as(usize, @intCast(tmp_3)) else break :blk_2 scanline - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                                    }).*;
                                    linear[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp_2;
                                    break :blk_1 tmp_2;
                                };
                                linear[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                                break :blk tmp;
                            };
                            break;
                        },
                    }
                    break;
                }
                stbiw__linear_to_rgbe(@as([*c]u8, @ptrCast(@alignCast(&rgbe[@as(usize, @intCast(0))]))), @as([*c]f32, @ptrCast(@alignCast(&linear[@as(usize, @intCast(0))]))));
                (blk: {
                    const tmp = x + (width * @as(c_int, 0));
                    if (tmp >= 0) break :blk scratch + @as(usize, @intCast(tmp)) else break :blk scratch - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = rgbe[@as(c_uint, @intCast(@as(c_int, 0)))];
                (blk: {
                    const tmp = x + (width * @as(c_int, 1));
                    if (tmp >= 0) break :blk scratch + @as(usize, @intCast(tmp)) else break :blk scratch - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = rgbe[@as(c_uint, @intCast(@as(c_int, 1)))];
                (blk: {
                    const tmp = x + (width * @as(c_int, 2));
                    if (tmp >= 0) break :blk scratch + @as(usize, @intCast(tmp)) else break :blk scratch - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = rgbe[@as(c_uint, @intCast(@as(c_int, 2)))];
                (blk: {
                    const tmp = x + (width * @as(c_int, 3));
                    if (tmp >= 0) break :blk scratch + @as(usize, @intCast(tmp)) else break :blk scratch - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).* = rgbe[@as(c_uint, @intCast(@as(c_int, 3)))];
            }
        }
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&scanlineheader[@as(usize, @intCast(0))]))))), @as(c_int, 4));
        {
            c = 0;
            while (c < @as(c_int, 4)) : (c += 1) {
                var comp: [*c]u8 = &(blk: {
                    const tmp = width * c;
                    if (tmp >= 0) break :blk scratch + @as(usize, @intCast(tmp)) else break :blk scratch - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*;
                _ = &comp;
                x = 0;
                while (x < width) {
                    r = x;
                    while ((r + @as(c_int, 2)) < width) {
                        if ((@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = r;
                            if (tmp >= 0) break :blk comp + @as(usize, @intCast(tmp)) else break :blk comp - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) == @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = r + @as(c_int, 1);
                            if (tmp >= 0) break :blk comp + @as(usize, @intCast(tmp)) else break :blk comp - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*)))) and (@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = r;
                            if (tmp >= 0) break :blk comp + @as(usize, @intCast(tmp)) else break :blk comp - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) == @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = r + @as(c_int, 2);
                            if (tmp >= 0) break :blk comp + @as(usize, @intCast(tmp)) else break :blk comp - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))))) break;
                        r += 1;
                    }
                    if ((r + @as(c_int, 2)) >= width) {
                        r = width;
                    }
                    while (x < r) {
                        var len: c_int = r - x;
                        _ = &len;
                        if (len > @as(c_int, 128)) {
                            len = 128;
                        }
                        stbiw__write_dump_data(s, len, &(blk: {
                            const tmp = x;
                            if (tmp >= 0) break :blk comp + @as(usize, @intCast(tmp)) else break :blk comp - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*);
                        x += len;
                    }
                    if ((r + @as(c_int, 2)) < width) {
                        while ((r < width) and (@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = r;
                            if (tmp >= 0) break :blk comp + @as(usize, @intCast(tmp)) else break :blk comp - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) == @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = x;
                            if (tmp >= 0) break :blk comp + @as(usize, @intCast(tmp)) else break :blk comp - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))))) {
                            r += 1;
                        }
                        while (x < r) {
                            var len: c_int = r - x;
                            _ = &len;
                            if (len > @as(c_int, 127)) {
                                len = 127;
                            }
                            stbiw__write_run_data(s, len, (blk: {
                                const tmp = x;
                                if (tmp >= 0) break :blk comp + @as(usize, @intCast(tmp)) else break :blk comp - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                            }).*);
                            x += len;
                        }
                    }
                }
            }
        }
    }
}
pub fn stbi_write_hdr_core(arg_s: [*c]stbi__write_context, arg_x: c_int, arg_y: c_int, arg_comp: c_int, arg_data: [*c]f32) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    if (((y <= @as(c_int, 0)) or (x <= @as(c_int, 0))) or (data == @as([*c]f32, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))) return 0 else {
        var scratch: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(malloc(@as(c_ulong, @bitCast(@as(c_long, x * @as(c_int, 4))))))));
        _ = &scratch;
        var i: c_int = undefined;
        _ = &i;
        var len: c_int = undefined;
        _ = &len;
        var buffer: [128]u8 = undefined;
        _ = &buffer;
        var header: [65:0]u8 = "#?RADIANCE\n# Written by stb_image_write.h\nFORMAT=32-bit_rle_rgbe\n".*;
        _ = &header;
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&header[@as(usize, @intCast(0))]))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([66]u8) -% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))))))));
        len = sprintf(@as([*c]u8, @ptrCast(@alignCast(&buffer[@as(usize, @intCast(0))]))), "EXPOSURE=          1.0000000000000\n\n-Y %d +X %d\n", y, x);
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&buffer[@as(usize, @intCast(0))]))))), len);
        {
            i = 0;
            while (i < y) : (i += 1) {
                stbiw__write_hdr_scanline(s, x, comp, scratch, data + @as(usize, @bitCast(@as(isize, @intCast((comp * x) * (if (stbi__flip_vertically_on_write != 0) (y - @as(c_int, 1)) - i else i))))));
            }
        }
        free(@as(?*anyopaque, @ptrCast(scratch)));
        return 1;
    }
    return 0;
}
pub fn stbiw__sbgrowf(arg_arr: [*c]?*anyopaque, arg_increment: c_int, arg_itemsize: c_int) callconv(.c) ?*anyopaque {
    var arr = arg_arr;
    _ = &arr;
    var increment = arg_increment;
    _ = &increment;
    var itemsize = arg_itemsize;
    _ = &itemsize;
    var m: c_int = if (arr.* != null) (@as(c_int, 2) * (@as([*c]c_int, @ptrCast(@alignCast(arr.*))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))]) + increment else increment + @as(c_int, 1);
    _ = &m;
    var p: ?*anyopaque = realloc(@as(?*anyopaque, @ptrCast(if (arr.* != null) @as([*c]c_int, @ptrCast(@alignCast(arr.*))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))) else null)), @as(c_ulong, @bitCast(@as(c_long, itemsize * m))) +% (@sizeOf(c_int) *% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 2))))));
    _ = &p;
    _ = (p != null) or ((blk: {
        __assert_fail("p", "/home/x/next/arcan/src/engine/external/stb_image_write.h", @as(c_int, 830), "stbiw__sbgrowf");
        break :blk @as(c_int, 0);
    }) != 0);
    if (p != null) {
        if (!(arr.* != null)) {
            @as([*c]c_int, @ptrCast(@alignCast(p)))[@as(c_uint, @intCast(@as(c_int, 1)))] = 0;
        }
        arr.* = @as(?*anyopaque, @ptrCast(@as([*c]c_int, @ptrCast(@alignCast(p))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2)))))));
        (@as([*c]c_int, @ptrCast(@alignCast(arr.*))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))] = m;
    }
    return arr.*;
}
pub fn stbiw__zlib_flushf(arg_data: [*c]u8, arg_bitbuffer: [*c]c_uint, arg_bitcount: [*c]c_int) callconv(.c) [*c]u8 {
    var data = arg_data;
    _ = &data;
    var bitbuffer = arg_bitbuffer;
    _ = &bitbuffer;
    var bitcount = arg_bitcount;
    _ = &bitcount;
    while (bitcount.* >= @as(c_int, 8)) {
        _ = blk: {
            _ = if ((data == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(data))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(data))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&data))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
            break :blk blk_1: {
                const tmp = @as(u8, @bitCast(@as(u8, @truncate(bitbuffer.* & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                (blk_2: {
                    const tmp_3 = blk_3: {
                        const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(data))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                        const tmp_4 = ref.*;
                        ref.* += 1;
                        break :blk_3 tmp_4;
                    };
                    if (tmp_3 >= 0) break :blk_2 data + @as(usize, @intCast(tmp_3)) else break :blk_2 data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                }).* = tmp;
                break :blk_1 tmp;
            };
        };
        bitbuffer.* >>= @intCast(@as(c_int, 8));
        bitcount.* -= @as(c_int, 8);
    }
    return data;
}
pub fn stbiw__zlib_bitrev(arg_code: c_int, arg_codebits: c_int) callconv(.c) c_int {
    var code = arg_code;
    _ = &code;
    var codebits = arg_codebits;
    _ = &codebits;
    var res: c_int = 0;
    _ = &res;
    while ((blk: {
        const ref = &codebits;
        const tmp = ref.*;
        ref.* -= 1;
        break :blk tmp;
    }) != 0) {
        res = (res << @intCast(1)) | (code & @as(c_int, 1));
        code >>= @intCast(@as(c_int, 1));
    }
    return res;
}
pub fn stbiw__zlib_countm(arg_a: [*c]u8, arg_b: [*c]u8, arg_limit: c_int) callconv(.c) c_uint {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var limit = arg_limit;
    _ = &limit;
    var i: c_int = undefined;
    _ = &i;
    {
        i = 0;
        while ((i < limit) and (i < @as(c_int, 258))) : (i += 1) if (@as(c_int, @bitCast(@as(c_uint, (blk: {
            const tmp = i;
            if (tmp >= 0) break :blk a + @as(usize, @intCast(tmp)) else break :blk a - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*))) != @as(c_int, @bitCast(@as(c_uint, (blk: {
            const tmp = i;
            if (tmp >= 0) break :blk b + @as(usize, @intCast(tmp)) else break :blk b - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*)))) break;
    }
    return @as(c_uint, @bitCast(i));
}
pub fn stbiw__zhash(arg_data: [*c]u8) callconv(.c) c_uint {
    var data = arg_data;
    _ = &data;
    var hash: stbiw_uint32 = @as(stbiw_uint32, @bitCast((@as(c_int, @bitCast(@as(c_uint, data[@as(c_uint, @intCast(@as(c_int, 0)))]))) + (@as(c_int, @bitCast(@as(c_uint, data[@as(c_uint, @intCast(@as(c_int, 1)))]))) << @intCast(8))) + (@as(c_int, @bitCast(@as(c_uint, data[@as(c_uint, @intCast(@as(c_int, 2)))]))) << @intCast(16))));
    _ = &hash;
    hash ^= hash << @intCast(3);
    hash +%= hash >> @intCast(5);
    hash ^= hash << @intCast(4);
    hash +%= hash >> @intCast(17);
    hash ^= hash << @intCast(25);
    hash +%= hash >> @intCast(6);
    return hash;
}
pub fn stbi_zlib_compress(arg_data: [*c]u8, arg_data_len: c_int, arg_out_len: [*c]c_int, arg_quality: c_int) callconv(.c) [*c]u8 {
    var data = arg_data;
    _ = &data;
    var data_len = arg_data_len;
    _ = &data_len;
    var out_len = arg_out_len;
    _ = &out_len;
    var quality = arg_quality;
    _ = &quality;
    const lengthc = struct {
        var static: [30]c_ushort = [30]c_ushort{
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            13,
            15,
            17,
            19,
            23,
            27,
            31,
            35,
            43,
            51,
            59,
            67,
            83,
            99,
            115,
            131,
            163,
            195,
            227,
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 258))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 259))))),
        };
    };
    _ = &lengthc;
    const lengtheb = struct {
        var static: [29]u8 = [29]u8{
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            1,
            1,
            1,
            2,
            2,
            2,
            2,
            3,
            3,
            3,
            3,
            4,
            4,
            4,
            4,
            5,
            5,
            5,
            5,
            0,
        };
    };
    _ = &lengtheb;
    const distc = struct {
        var static: [31]c_ushort = [31]c_ushort{
            1,
            2,
            3,
            4,
            5,
            7,
            9,
            13,
            17,
            25,
            33,
            49,
            65,
            97,
            129,
            193,
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 257))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 385))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 513))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 769))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1025))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1537))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2049))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 3073))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4097))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 6145))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 8193))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 12289))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 16385))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 24577))))),
            @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 32768))))),
        };
    };
    _ = &distc;
    const disteb = struct {
        var static: [30]u8 = [30]u8{
            0,
            0,
            0,
            0,
            1,
            1,
            2,
            2,
            3,
            3,
            4,
            4,
            5,
            5,
            6,
            6,
            7,
            7,
            8,
            8,
            9,
            9,
            10,
            10,
            11,
            11,
            12,
            12,
            13,
            13,
        };
    };
    _ = &disteb;
    var bitbuf: c_uint = 0;
    _ = &bitbuf;
    var i: c_int = undefined;
    _ = &i;
    var j: c_int = undefined;
    _ = &j;
    var bitcount: c_int = 0;
    _ = &bitcount;
    var out: [*c]u8 = null;
    _ = &out;
    var hash_table: [*c][*c][*c]u8 = @as([*c][*c][*c]u8, @ptrCast(@alignCast(malloc(@as(c_ulong, @bitCast(@as(c_long, @as(c_int, 16384)))) *% @sizeOf([*c][*c]u8)))));
    _ = &hash_table;
    if (hash_table == @as([*c][*c][*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) return null;
    if (quality < @as(c_int, 5)) {
        quality = 5;
    }
    _ = blk: {
        _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
        break :blk blk_1: {
            const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 120)))));
            (blk_2: {
                const tmp_3 = blk_3: {
                    const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                    const tmp_4 = ref.*;
                    ref.* += 1;
                    break :blk_3 tmp_4;
                };
                if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
            }).* = tmp;
            break :blk_1 tmp;
        };
    };
    _ = blk: {
        _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
        break :blk blk_1: {
            const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 94)))));
            (blk_2: {
                const tmp_3 = blk_3: {
                    const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                    const tmp_4 = ref.*;
                    ref.* += 1;
                    break :blk_3 tmp_4;
                };
                if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
            }).* = tmp;
            break :blk_1 tmp;
        };
    };
    _ = blk: {
        _ = blk_1: {
            bitbuf |= @as(c_uint, @bitCast(@as(c_int, 1) << @intCast(bitcount)));
            break :blk_1 blk_2: {
                const ref = &bitcount;
                ref.* += @as(c_int, 1);
                break :blk_2 ref.*;
            };
        };
        break :blk blk_1: {
            const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
            out = tmp;
            break :blk_1 tmp;
        };
    };
    _ = blk: {
        _ = blk_1: {
            bitbuf |= @as(c_uint, @bitCast(@as(c_int, 1) << @intCast(bitcount)));
            break :blk_1 blk_2: {
                const ref = &bitcount;
                ref.* += @as(c_int, 2);
                break :blk_2 ref.*;
            };
        };
        break :blk blk_1: {
            const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
            out = tmp;
            break :blk_1 tmp;
        };
    };
    {
        i = 0;
        while (i < @as(c_int, 16384)) : (i += 1) {
            (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = null;
        }
    }
    i = 0;
    while (i < (data_len - @as(c_int, 3))) {
        var h: c_int = @as(c_int, @bitCast(stbiw__zhash(data + @as(usize, @bitCast(@as(isize, @intCast(i))))) & @as(c_uint, @bitCast(@as(c_int, 16384) - @as(c_int, 1)))));
        _ = &h;
        var best: c_int = 3;
        _ = &best;
        var bestloc: [*c]u8 = null;
        _ = &bestloc;
        var hlist: [*c][*c]u8 = (blk: {
            const tmp = h;
            if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*;
        _ = &hlist;
        var n: c_int = if (hlist != null) (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(hlist))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] else @as(c_int, 0);
        _ = &n;
        {
            j = 0;
            while (j < n) : (j += 1) {
                if (@divExact(@as(c_long, @bitCast(@intFromPtr((blk: {
                    const tmp = j;
                    if (tmp >= 0) break :blk hlist + @as(usize, @intCast(tmp)) else break :blk hlist - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*) -% @intFromPtr(data))), @sizeOf(u8)) > @as(c_long, @bitCast(@as(c_long, i - @as(c_int, 32768))))) {
                    var d: c_int = @as(c_int, @bitCast(stbiw__zlib_countm((blk: {
                        const tmp = j;
                        if (tmp >= 0) break :blk hlist + @as(usize, @intCast(tmp)) else break :blk hlist - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).*, data + @as(usize, @bitCast(@as(isize, @intCast(i)))), data_len - i)));
                    _ = &d;
                    if (d >= best) {
                        best = d;
                        bestloc = (blk: {
                            const tmp = j;
                            if (tmp >= 0) break :blk hlist + @as(usize, @intCast(tmp)) else break :blk hlist - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*;
                    }
                }
            }
        }
        if (((blk: {
            const tmp = h;
            if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).* != null) and ((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast((blk: {
            const tmp = h;
            if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] == (@as(c_int, 2) * quality))) {
            _ = memmove(@as(?*anyopaque, @ptrCast((blk: {
                const tmp = h;
                if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*)), @as(?*const anyopaque, @ptrCast((blk: {
                const tmp = h;
                if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* + @as(usize, @bitCast(@as(isize, @intCast(quality)))))), @sizeOf([*c]u8) *% @as(c_ulong, @bitCast(@as(c_long, quality))));
            (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast((blk: {
                const tmp = h;
                if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] = quality;
        }
        _ = blk: {
            _ = if (((blk_1: {
                const tmp = h;
                if (tmp >= 0) break :blk_1 hash_table + @as(usize, @intCast(tmp)) else break :blk_1 hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast((blk_1: {
                const tmp = h;
                if (tmp >= 0) break :blk_1 hash_table + @as(usize, @intCast(tmp)) else break :blk_1 hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast((blk_1: {
                const tmp = h;
                if (tmp >= 0) break :blk_1 hash_table + @as(usize, @intCast(tmp)) else break :blk_1 hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&(blk_1: {
                const tmp = h;
                if (tmp >= 0) break :blk_1 hash_table + @as(usize, @intCast(tmp)) else break :blk_1 hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([*c]u8)))))) else null;
            break :blk blk_1: {
                const tmp = data + @as(usize, @bitCast(@as(isize, @intCast(i))));
                (blk_2: {
                    const tmp_3 = blk_3: {
                        const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast((blk_4: {
                            const tmp_5 = h;
                            if (tmp_5 >= 0) break :blk_4 hash_table + @as(usize, @intCast(tmp_5)) else break :blk_4 hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_5)) +% -1));
                        }).*))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                        const tmp_4 = ref.*;
                        ref.* += 1;
                        break :blk_3 tmp_4;
                    };
                    if (tmp_3 >= 0) break :blk_2 (blk_3: {
                        const tmp_4 = h;
                        if (tmp_4 >= 0) break :blk_3 hash_table + @as(usize, @intCast(tmp_4)) else break :blk_3 hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_4)) +% -1));
                    }).* + @as(usize, @intCast(tmp_3)) else break :blk_2 (blk_3: {
                        const tmp_4 = h;
                        if (tmp_4 >= 0) break :blk_3 hash_table + @as(usize, @intCast(tmp_4)) else break :blk_3 hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_4)) +% -1));
                    }).* - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                }).* = tmp;
                break :blk_1 tmp;
            };
        };
        if (bestloc != null) {
            h = @as(c_int, @bitCast(stbiw__zhash((data + @as(usize, @bitCast(@as(isize, @intCast(i))))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))) & @as(c_uint, @bitCast(@as(c_int, 16384) - @as(c_int, 1)))));
            hlist = (blk: {
                const tmp = h;
                if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*;
            n = if (hlist != null) (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(hlist))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] else @as(c_int, 0);
            {
                j = 0;
                while (j < n) : (j += 1) {
                    if (@divExact(@as(c_long, @bitCast(@intFromPtr((blk: {
                        const tmp = j;
                        if (tmp >= 0) break :blk hlist + @as(usize, @intCast(tmp)) else break :blk hlist - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).*) -% @intFromPtr(data))), @sizeOf(u8)) > @as(c_long, @bitCast(@as(c_long, i - @as(c_int, 32767))))) {
                        var e: c_int = @as(c_int, @bitCast(stbiw__zlib_countm((blk: {
                            const tmp = j;
                            if (tmp >= 0) break :blk hlist + @as(usize, @intCast(tmp)) else break :blk hlist - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*, (data + @as(usize, @bitCast(@as(isize, @intCast(i))))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))), (data_len - i) - @as(c_int, 1))));
                        _ = &e;
                        if (e > best) {
                            bestloc = null;
                            break;
                        }
                    }
                }
            }
        }
        if (bestloc != null) {
            var d: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(c_long, @bitCast(@intFromPtr(data + @as(usize, @bitCast(@as(isize, @intCast(i))))) -% @intFromPtr(bestloc))), @sizeOf(u8))))));
            _ = &d;
            _ = ((d <= @as(c_int, 32767)) and (best <= @as(c_int, 258))) or ((blk: {
                __assert_fail("d <= 32767 && best <= 258", "/home/x/next/arcan/src/engine/external/stb_image_write.h", @as(c_int, 959), "stbi_zlib_compress");
                break :blk @as(c_int, 0);
            }) != 0);
            {
                j = 0;
                while (best > (@as(c_int, @bitCast(@as(c_uint, lengthc.static[@as(c_uint, @intCast(j + @as(c_int, 1)))]))) - @as(c_int, 1))) : (j += 1) {}
            }
            _ = if ((j + @as(c_int, 257)) <= @as(c_int, 143)) blk: {
                _ = blk_1: {
                    bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev(@as(c_int, 48) + (j + @as(c_int, 257)), @as(c_int, 8)) << @intCast(bitcount)));
                    break :blk_1 blk_2: {
                        const ref = &bitcount;
                        ref.* += @as(c_int, 8);
                        break :blk_2 ref.*;
                    };
                };
                break :blk blk_1: {
                    const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                    out = tmp;
                    break :blk_1 tmp;
                };
            } else if ((j + @as(c_int, 257)) <= @as(c_int, 255)) blk: {
                _ = blk_1: {
                    bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev((@as(c_int, 400) + (j + @as(c_int, 257))) - @as(c_int, 144), @as(c_int, 9)) << @intCast(bitcount)));
                    break :blk_1 blk_2: {
                        const ref = &bitcount;
                        ref.* += @as(c_int, 9);
                        break :blk_2 ref.*;
                    };
                };
                break :blk blk_1: {
                    const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                    out = tmp;
                    break :blk_1 tmp;
                };
            } else if ((j + @as(c_int, 257)) <= @as(c_int, 279)) blk: {
                _ = blk_1: {
                    bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev((@as(c_int, 0) + (j + @as(c_int, 257))) - @as(c_int, 256), @as(c_int, 7)) << @intCast(bitcount)));
                    break :blk_1 blk_2: {
                        const ref = &bitcount;
                        ref.* += @as(c_int, 7);
                        break :blk_2 ref.*;
                    };
                };
                break :blk blk_1: {
                    const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                    out = tmp;
                    break :blk_1 tmp;
                };
            } else blk: {
                _ = blk_1: {
                    bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev((@as(c_int, 192) + (j + @as(c_int, 257))) - @as(c_int, 280), @as(c_int, 8)) << @intCast(bitcount)));
                    break :blk_1 blk_2: {
                        const ref = &bitcount;
                        ref.* += @as(c_int, 8);
                        break :blk_2 ref.*;
                    };
                };
                break :blk blk_1: {
                    const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                    out = tmp;
                    break :blk_1 tmp;
                };
            };
            if (lengtheb.static[@as(c_uint, @intCast(j))] != 0) {
                _ = blk: {
                    _ = blk_1: {
                        bitbuf |= @as(c_uint, @bitCast((best - @as(c_int, @bitCast(@as(c_uint, lengthc.static[@as(c_uint, @intCast(j))])))) << @intCast(bitcount)));
                        break :blk_1 blk_2: {
                            const ref = &bitcount;
                            ref.* += @as(c_int, @bitCast(@as(c_uint, lengtheb.static[@as(c_uint, @intCast(j))])));
                            break :blk_2 ref.*;
                        };
                    };
                    break :blk blk_1: {
                        const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                        out = tmp;
                        break :blk_1 tmp;
                    };
                };
            }
            {
                j = 0;
                while (d > (@as(c_int, @bitCast(@as(c_uint, distc.static[@as(c_uint, @intCast(j + @as(c_int, 1)))]))) - @as(c_int, 1))) : (j += 1) {}
            }
            _ = blk: {
                _ = blk_1: {
                    bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev(j, @as(c_int, 5)) << @intCast(bitcount)));
                    break :blk_1 blk_2: {
                        const ref = &bitcount;
                        ref.* += @as(c_int, 5);
                        break :blk_2 ref.*;
                    };
                };
                break :blk blk_1: {
                    const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                    out = tmp;
                    break :blk_1 tmp;
                };
            };
            if (disteb.static[@as(c_uint, @intCast(j))] != 0) {
                _ = blk: {
                    _ = blk_1: {
                        bitbuf |= @as(c_uint, @bitCast((d - @as(c_int, @bitCast(@as(c_uint, distc.static[@as(c_uint, @intCast(j))])))) << @intCast(bitcount)));
                        break :blk_1 blk_2: {
                            const ref = &bitcount;
                            ref.* += @as(c_int, @bitCast(@as(c_uint, disteb.static[@as(c_uint, @intCast(j))])));
                            break :blk_2 ref.*;
                        };
                    };
                    break :blk blk_1: {
                        const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                        out = tmp;
                        break :blk_1 tmp;
                    };
                };
            }
            i += best;
        } else {
            _ = if (@as(c_int, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk data + @as(usize, @intCast(tmp)) else break :blk data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))) <= @as(c_int, 143)) blk: {
                _ = blk_1: {
                    bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev(@as(c_int, 48) + @as(c_int, @bitCast(@as(c_uint, (blk_2: {
                        const tmp = i;
                        if (tmp >= 0) break :blk_2 data + @as(usize, @intCast(tmp)) else break :blk_2 data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).*))), @as(c_int, 8)) << @intCast(bitcount)));
                    break :blk_1 blk_2: {
                        const ref = &bitcount;
                        ref.* += @as(c_int, 8);
                        break :blk_2 ref.*;
                    };
                };
                break :blk blk_1: {
                    const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                    out = tmp;
                    break :blk_1 tmp;
                };
            } else blk: {
                _ = blk_1: {
                    bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev((@as(c_int, 400) + @as(c_int, @bitCast(@as(c_uint, (blk_2: {
                        const tmp = i;
                        if (tmp >= 0) break :blk_2 data + @as(usize, @intCast(tmp)) else break :blk_2 data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).*)))) - @as(c_int, 144), @as(c_int, 9)) << @intCast(bitcount)));
                    break :blk_1 blk_2: {
                        const ref = &bitcount;
                        ref.* += @as(c_int, 9);
                        break :blk_2 ref.*;
                    };
                };
                break :blk blk_1: {
                    const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                    out = tmp;
                    break :blk_1 tmp;
                };
            };
            i += 1;
        }
    }
    while (i < data_len) : (i += 1) {
        _ = if (@as(c_int, @bitCast(@as(c_uint, (blk: {
            const tmp = i;
            if (tmp >= 0) break :blk data + @as(usize, @intCast(tmp)) else break :blk data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*))) <= @as(c_int, 143)) blk: {
            _ = blk_1: {
                bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev(@as(c_int, 48) + @as(c_int, @bitCast(@as(c_uint, (blk_2: {
                    const tmp = i;
                    if (tmp >= 0) break :blk_2 data + @as(usize, @intCast(tmp)) else break :blk_2 data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*))), @as(c_int, 8)) << @intCast(bitcount)));
                break :blk_1 blk_2: {
                    const ref = &bitcount;
                    ref.* += @as(c_int, 8);
                    break :blk_2 ref.*;
                };
            };
            break :blk blk_1: {
                const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                out = tmp;
                break :blk_1 tmp;
            };
        } else blk: {
            _ = blk_1: {
                bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev((@as(c_int, 400) + @as(c_int, @bitCast(@as(c_uint, (blk_2: {
                    const tmp = i;
                    if (tmp >= 0) break :blk_2 data + @as(usize, @intCast(tmp)) else break :blk_2 data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*)))) - @as(c_int, 144), @as(c_int, 9)) << @intCast(bitcount)));
                break :blk_1 blk_2: {
                    const ref = &bitcount;
                    ref.* += @as(c_int, 9);
                    break :blk_2 ref.*;
                };
            };
            break :blk blk_1: {
                const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                out = tmp;
                break :blk_1 tmp;
            };
        };
    }
    _ = if (@as(c_int, 256) <= @as(c_int, 143)) blk: {
        _ = blk_1: {
            bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev(@as(c_int, 48) + @as(c_int, 256), @as(c_int, 8)) << @intCast(bitcount)));
            break :blk_1 blk_2: {
                const ref = &bitcount;
                ref.* += @as(c_int, 8);
                break :blk_2 ref.*;
            };
        };
        break :blk blk_1: {
            const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
            out = tmp;
            break :blk_1 tmp;
        };
    } else if (@as(c_int, 256) <= @as(c_int, 255)) blk: {
        _ = blk_1: {
            bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev((@as(c_int, 400) + @as(c_int, 256)) - @as(c_int, 144), @as(c_int, 9)) << @intCast(bitcount)));
            break :blk_1 blk_2: {
                const ref = &bitcount;
                ref.* += @as(c_int, 9);
                break :blk_2 ref.*;
            };
        };
        break :blk blk_1: {
            const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
            out = tmp;
            break :blk_1 tmp;
        };
    } else if (@as(c_int, 256) <= @as(c_int, 279)) blk: {
        _ = blk_1: {
            bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev((@as(c_int, 0) + @as(c_int, 256)) - @as(c_int, 256), @as(c_int, 7)) << @intCast(bitcount)));
            break :blk_1 blk_2: {
                const ref = &bitcount;
                ref.* += @as(c_int, 7);
                break :blk_2 ref.*;
            };
        };
        break :blk blk_1: {
            const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
            out = tmp;
            break :blk_1 tmp;
        };
    } else blk: {
        _ = blk_1: {
            bitbuf |= @as(c_uint, @bitCast(stbiw__zlib_bitrev((@as(c_int, 192) + @as(c_int, 256)) - @as(c_int, 280), @as(c_int, 8)) << @intCast(bitcount)));
            break :blk_1 blk_2: {
                const ref = &bitcount;
                ref.* += @as(c_int, 8);
                break :blk_2 ref.*;
            };
        };
        break :blk blk_1: {
            const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
            out = tmp;
            break :blk_1 tmp;
        };
    };
    while (bitcount != 0) {
        _ = blk: {
            _ = blk_1: {
                bitbuf |= @as(c_uint, @bitCast(@as(c_int, 0) << @intCast(bitcount)));
                break :blk_1 blk_2: {
                    const ref = &bitcount;
                    ref.* += @as(c_int, 1);
                    break :blk_2 ref.*;
                };
            };
            break :blk blk_1: {
                const tmp = stbiw__zlib_flushf(out, &bitbuf, &bitcount);
                out = tmp;
                break :blk_1 tmp;
            };
        };
    }
    {
        i = 0;
        while (i < @as(c_int, 16384)) : (i += 1) {
            _ = if ((blk: {
                const tmp = i;
                if (tmp >= 0) break :blk hash_table + @as(usize, @intCast(tmp)) else break :blk hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* != null) blk: {
                free(@as(?*anyopaque, @ptrCast(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast((blk_1: {
                    const tmp = i;
                    if (tmp >= 0) break :blk_1 hash_table + @as(usize, @intCast(tmp)) else break :blk_1 hash_table - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                }).*))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))));
                break :blk @as(c_int, 0);
            } else @as(c_int, 0);
        }
    }
    free(@as(?*anyopaque, @ptrCast(hash_table)));
    if ((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] > ((data_len + @as(c_int, 2)) + (@divTrunc(data_len + @as(c_int, 32766), @as(c_int, 32767)) * @as(c_int, 5)))) {
        (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] = 2;
        {
            j = 0;
            while (j < data_len) {
                var blocklen: c_int = data_len - j;
                _ = &blocklen;
                if (blocklen > @as(c_int, 32767)) {
                    blocklen = 32767;
                }
                _ = blk: {
                    _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
                    break :blk blk_1: {
                        const tmp = @as(u8, @intFromBool((data_len - j) == blocklen));
                        (blk_2: {
                            const tmp_3 = blk_3: {
                                const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                                const tmp_4 = ref.*;
                                ref.* += 1;
                                break :blk_3 tmp_4;
                            };
                            if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                        }).* = tmp;
                        break :blk_1 tmp;
                    };
                };
                _ = blk: {
                    _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
                    break :blk blk_1: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate(blocklen & @as(c_int, 255)))));
                        (blk_2: {
                            const tmp_3 = blk_3: {
                                const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                                const tmp_4 = ref.*;
                                ref.* += 1;
                                break :blk_3 tmp_4;
                            };
                            if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                        }).* = tmp;
                        break :blk_1 tmp;
                    };
                };
                _ = blk: {
                    _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
                    break :blk blk_1: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate((blocklen >> @intCast(8)) & @as(c_int, 255)))));
                        (blk_2: {
                            const tmp_3 = blk_3: {
                                const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                                const tmp_4 = ref.*;
                                ref.* += 1;
                                break :blk_3 tmp_4;
                            };
                            if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                        }).* = tmp;
                        break :blk_1 tmp;
                    };
                };
                _ = blk: {
                    _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
                    break :blk blk_1: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate(~blocklen & @as(c_int, 255)))));
                        (blk_2: {
                            const tmp_3 = blk_3: {
                                const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                                const tmp_4 = ref.*;
                                ref.* += 1;
                                break :blk_3 tmp_4;
                            };
                            if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                        }).* = tmp;
                        break :blk_1 tmp;
                    };
                };
                _ = blk: {
                    _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
                    break :blk blk_1: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate((~blocklen >> @intCast(8)) & @as(c_int, 255)))));
                        (blk_2: {
                            const tmp_3 = blk_3: {
                                const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                                const tmp_4 = ref.*;
                                ref.* += 1;
                                break :blk_3 tmp_4;
                            };
                            if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                        }).* = tmp;
                        break :blk_1 tmp;
                    };
                };
                _ = memcpy(@as(?*anyopaque, @ptrCast(out + @as(usize, @bitCast(@as(isize, @intCast((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))])))))), @as(?*const anyopaque, @ptrCast(data + @as(usize, @bitCast(@as(isize, @intCast(j)))))), @as(c_ulong, @bitCast(@as(c_long, blocklen))));
                (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] += blocklen;
                j += blocklen;
            }
        }
    }
    {
        var s1: c_uint = 1;
        _ = &s1;
        var s2: c_uint = 0;
        _ = &s2;
        var blocklen: c_int = @import("std").zig.c_translation.signedRemainder(data_len, @as(c_int, 5552));
        _ = &blocklen;
        j = 0;
        while (j < data_len) {
            {
                i = 0;
                while (i < blocklen) : (i += 1) {
                    s1 +%= @as(c_uint, @bitCast(@as(c_uint, (blk: {
                        const tmp = j + i;
                        if (tmp >= 0) break :blk data + @as(usize, @intCast(tmp)) else break :blk data - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).*)));
                    s2 +%= s1;
                }
            }
            s1 %= @as(c_uint, @bitCast(@as(c_int, 65521)));
            s2 %= @as(c_uint, @bitCast(@as(c_int, 65521)));
            j += blocklen;
            blocklen = 5552;
        }
        _ = blk: {
            _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
            break :blk blk_1: {
                const tmp = @as(u8, @bitCast(@as(u8, @truncate((s2 >> @intCast(8)) & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                (blk_2: {
                    const tmp_3 = blk_3: {
                        const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                        const tmp_4 = ref.*;
                        ref.* += 1;
                        break :blk_3 tmp_4;
                    };
                    if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                }).* = tmp;
                break :blk_1 tmp;
            };
        };
        _ = blk: {
            _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
            break :blk blk_1: {
                const tmp = @as(u8, @bitCast(@as(u8, @truncate(s2 & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                (blk_2: {
                    const tmp_3 = blk_3: {
                        const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                        const tmp_4 = ref.*;
                        ref.* += 1;
                        break :blk_3 tmp_4;
                    };
                    if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                }).* = tmp;
                break :blk_1 tmp;
            };
        };
        _ = blk: {
            _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
            break :blk blk_1: {
                const tmp = @as(u8, @bitCast(@as(u8, @truncate((s1 >> @intCast(8)) & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                (blk_2: {
                    const tmp_3 = blk_3: {
                        const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                        const tmp_4 = ref.*;
                        ref.* += 1;
                        break :blk_3 tmp_4;
                    };
                    if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                }).* = tmp;
                break :blk_1 tmp;
            };
        };
        _ = blk: {
            _ = if ((out == null) or (((@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))] + @as(c_int, 1)) >= (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 0)))])) stbiw__sbgrowf(@as([*c]?*anyopaque, @ptrCast(@alignCast(&out))), @as(c_int, 1), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(u8)))))) else null;
            break :blk blk_1: {
                const tmp = @as(u8, @bitCast(@as(u8, @truncate(s1 & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                (blk_2: {
                    const tmp_3 = blk_3: {
                        const ref = &(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
                        const tmp_4 = ref.*;
                        ref.* += 1;
                        break :blk_3 tmp_4;
                    };
                    if (tmp_3 >= 0) break :blk_2 out + @as(usize, @intCast(tmp_3)) else break :blk_2 out - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_3)) +% -1));
                }).* = tmp;
                break :blk_1 tmp;
            };
        };
    }
    out_len.* = (@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))[@as(c_uint, @intCast(@as(c_int, 1)))];
    _ = memmove(@as(?*anyopaque, @ptrCast(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))), @as(?*const anyopaque, @ptrCast(out)), @as(c_ulong, @bitCast(@as(c_long, out_len.*))));
    return @as([*c]u8, @ptrCast(@alignCast(@as([*c]c_int, @ptrCast(@alignCast(@as(?*anyopaque, @ptrCast(out))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 2))))))));
}
pub fn stbiw__crc32(arg_buffer: [*c]u8, arg_len: c_int) callconv(.c) c_uint {
    var buffer = arg_buffer;
    _ = &buffer;
    var len = arg_len;
    _ = &len;
    const crc_table = struct {
        var static: [256]c_uint = [256]c_uint{
            0,
            @as(c_uint, @bitCast(@as(c_int, 1996959894))),
            3993919788,
            2567524794,
            @as(c_uint, @bitCast(@as(c_int, 124634137))),
            @as(c_uint, @bitCast(@as(c_int, 1886057615))),
            3915621685,
            2657392035,
            @as(c_uint, @bitCast(@as(c_int, 249268274))),
            @as(c_uint, @bitCast(@as(c_int, 2044508324))),
            3772115230,
            2547177864,
            @as(c_uint, @bitCast(@as(c_int, 162941995))),
            @as(c_uint, @bitCast(@as(c_int, 2125561021))),
            3887607047,
            2428444049,
            @as(c_uint, @bitCast(@as(c_int, 498536548))),
            @as(c_uint, @bitCast(@as(c_int, 1789927666))),
            4089016648,
            2227061214,
            @as(c_uint, @bitCast(@as(c_int, 450548861))),
            @as(c_uint, @bitCast(@as(c_int, 1843258603))),
            4107580753,
            2211677639,
            @as(c_uint, @bitCast(@as(c_int, 325883990))),
            @as(c_uint, @bitCast(@as(c_int, 1684777152))),
            4251122042,
            2321926636,
            @as(c_uint, @bitCast(@as(c_int, 335633487))),
            @as(c_uint, @bitCast(@as(c_int, 1661365465))),
            4195302755,
            2366115317,
            @as(c_uint, @bitCast(@as(c_int, 997073096))),
            @as(c_uint, @bitCast(@as(c_int, 1281953886))),
            3579855332,
            2724688242,
            @as(c_uint, @bitCast(@as(c_int, 1006888145))),
            @as(c_uint, @bitCast(@as(c_int, 1258607687))),
            3524101629,
            2768942443,
            @as(c_uint, @bitCast(@as(c_int, 901097722))),
            @as(c_uint, @bitCast(@as(c_int, 1119000684))),
            3686517206,
            2898065728,
            @as(c_uint, @bitCast(@as(c_int, 853044451))),
            @as(c_uint, @bitCast(@as(c_int, 1172266101))),
            3705015759,
            2882616665,
            @as(c_uint, @bitCast(@as(c_int, 651767980))),
            @as(c_uint, @bitCast(@as(c_int, 1373503546))),
            3369554304,
            3218104598,
            @as(c_uint, @bitCast(@as(c_int, 565507253))),
            @as(c_uint, @bitCast(@as(c_int, 1454621731))),
            3485111705,
            3099436303,
            @as(c_uint, @bitCast(@as(c_int, 671266974))),
            @as(c_uint, @bitCast(@as(c_int, 1594198024))),
            3322730930,
            2970347812,
            @as(c_uint, @bitCast(@as(c_int, 795835527))),
            @as(c_uint, @bitCast(@as(c_int, 1483230225))),
            3244367275,
            3060149565,
            @as(c_uint, @bitCast(@as(c_int, 1994146192))),
            @as(c_uint, @bitCast(@as(c_int, 31158534))),
            2563907772,
            4023717930,
            @as(c_uint, @bitCast(@as(c_int, 1907459465))),
            @as(c_uint, @bitCast(@as(c_int, 112637215))),
            2680153253,
            3904427059,
            @as(c_uint, @bitCast(@as(c_int, 2013776290))),
            @as(c_uint, @bitCast(@as(c_int, 251722036))),
            2517215374,
            3775830040,
            @as(c_uint, @bitCast(@as(c_int, 2137656763))),
            @as(c_uint, @bitCast(@as(c_int, 141376813))),
            2439277719,
            3865271297,
            @as(c_uint, @bitCast(@as(c_int, 1802195444))),
            @as(c_uint, @bitCast(@as(c_int, 476864866))),
            2238001368,
            4066508878,
            @as(c_uint, @bitCast(@as(c_int, 1812370925))),
            @as(c_uint, @bitCast(@as(c_int, 453092731))),
            2181625025,
            4111451223,
            @as(c_uint, @bitCast(@as(c_int, 1706088902))),
            @as(c_uint, @bitCast(@as(c_int, 314042704))),
            2344532202,
            4240017532,
            @as(c_uint, @bitCast(@as(c_int, 1658658271))),
            @as(c_uint, @bitCast(@as(c_int, 366619977))),
            2362670323,
            4224994405,
            @as(c_uint, @bitCast(@as(c_int, 1303535960))),
            @as(c_uint, @bitCast(@as(c_int, 984961486))),
            2747007092,
            3569037538,
            @as(c_uint, @bitCast(@as(c_int, 1256170817))),
            @as(c_uint, @bitCast(@as(c_int, 1037604311))),
            2765210733,
            3554079995,
            @as(c_uint, @bitCast(@as(c_int, 1131014506))),
            @as(c_uint, @bitCast(@as(c_int, 879679996))),
            2909243462,
            3663771856,
            @as(c_uint, @bitCast(@as(c_int, 1141124467))),
            @as(c_uint, @bitCast(@as(c_int, 855842277))),
            2852801631,
            3708648649,
            @as(c_uint, @bitCast(@as(c_int, 1342533948))),
            @as(c_uint, @bitCast(@as(c_int, 654459306))),
            3188396048,
            3373015174,
            @as(c_uint, @bitCast(@as(c_int, 1466479909))),
            @as(c_uint, @bitCast(@as(c_int, 544179635))),
            3110523913,
            3462522015,
            @as(c_uint, @bitCast(@as(c_int, 1591671054))),
            @as(c_uint, @bitCast(@as(c_int, 702138776))),
            2966460450,
            3352799412,
            @as(c_uint, @bitCast(@as(c_int, 1504918807))),
            @as(c_uint, @bitCast(@as(c_int, 783551873))),
            3082640443,
            3233442989,
            3988292384,
            2596254646,
            @as(c_uint, @bitCast(@as(c_int, 62317068))),
            @as(c_uint, @bitCast(@as(c_int, 1957810842))),
            3939845945,
            2647816111,
            @as(c_uint, @bitCast(@as(c_int, 81470997))),
            @as(c_uint, @bitCast(@as(c_int, 1943803523))),
            3814918930,
            2489596804,
            @as(c_uint, @bitCast(@as(c_int, 225274430))),
            @as(c_uint, @bitCast(@as(c_int, 2053790376))),
            3826175755,
            2466906013,
            @as(c_uint, @bitCast(@as(c_int, 167816743))),
            @as(c_uint, @bitCast(@as(c_int, 2097651377))),
            4027552580,
            2265490386,
            @as(c_uint, @bitCast(@as(c_int, 503444072))),
            @as(c_uint, @bitCast(@as(c_int, 1762050814))),
            4150417245,
            2154129355,
            @as(c_uint, @bitCast(@as(c_int, 426522225))),
            @as(c_uint, @bitCast(@as(c_int, 1852507879))),
            4275313526,
            2312317920,
            @as(c_uint, @bitCast(@as(c_int, 282753626))),
            @as(c_uint, @bitCast(@as(c_int, 1742555852))),
            4189708143,
            2394877945,
            @as(c_uint, @bitCast(@as(c_int, 397917763))),
            @as(c_uint, @bitCast(@as(c_int, 1622183637))),
            3604390888,
            2714866558,
            @as(c_uint, @bitCast(@as(c_int, 953729732))),
            @as(c_uint, @bitCast(@as(c_int, 1340076626))),
            3518719985,
            2797360999,
            @as(c_uint, @bitCast(@as(c_int, 1068828381))),
            @as(c_uint, @bitCast(@as(c_int, 1219638859))),
            3624741850,
            2936675148,
            @as(c_uint, @bitCast(@as(c_int, 906185462))),
            @as(c_uint, @bitCast(@as(c_int, 1090812512))),
            3747672003,
            2825379669,
            @as(c_uint, @bitCast(@as(c_int, 829329135))),
            @as(c_uint, @bitCast(@as(c_int, 1181335161))),
            3412177804,
            3160834842,
            @as(c_uint, @bitCast(@as(c_int, 628085408))),
            @as(c_uint, @bitCast(@as(c_int, 1382605366))),
            3423369109,
            3138078467,
            @as(c_uint, @bitCast(@as(c_int, 570562233))),
            @as(c_uint, @bitCast(@as(c_int, 1426400815))),
            3317316542,
            2998733608,
            @as(c_uint, @bitCast(@as(c_int, 733239954))),
            @as(c_uint, @bitCast(@as(c_int, 1555261956))),
            3268935591,
            3050360625,
            @as(c_uint, @bitCast(@as(c_int, 752459403))),
            @as(c_uint, @bitCast(@as(c_int, 1541320221))),
            2607071920,
            3965973030,
            @as(c_uint, @bitCast(@as(c_int, 1969922972))),
            @as(c_uint, @bitCast(@as(c_int, 40735498))),
            2617837225,
            3943577151,
            @as(c_uint, @bitCast(@as(c_int, 1913087877))),
            @as(c_uint, @bitCast(@as(c_int, 83908371))),
            2512341634,
            3803740692,
            @as(c_uint, @bitCast(@as(c_int, 2075208622))),
            @as(c_uint, @bitCast(@as(c_int, 213261112))),
            2463272603,
            3855990285,
            @as(c_uint, @bitCast(@as(c_int, 2094854071))),
            @as(c_uint, @bitCast(@as(c_int, 198958881))),
            2262029012,
            4057260610,
            @as(c_uint, @bitCast(@as(c_int, 1759359992))),
            @as(c_uint, @bitCast(@as(c_int, 534414190))),
            2176718541,
            4139329115,
            @as(c_uint, @bitCast(@as(c_int, 1873836001))),
            @as(c_uint, @bitCast(@as(c_int, 414664567))),
            2282248934,
            4279200368,
            @as(c_uint, @bitCast(@as(c_int, 1711684554))),
            @as(c_uint, @bitCast(@as(c_int, 285281116))),
            2405801727,
            4167216745,
            @as(c_uint, @bitCast(@as(c_int, 1634467795))),
            @as(c_uint, @bitCast(@as(c_int, 376229701))),
            2685067896,
            3608007406,
            @as(c_uint, @bitCast(@as(c_int, 1308918612))),
            @as(c_uint, @bitCast(@as(c_int, 956543938))),
            2808555105,
            3495958263,
            @as(c_uint, @bitCast(@as(c_int, 1231636301))),
            @as(c_uint, @bitCast(@as(c_int, 1047427035))),
            2932959818,
            3654703836,
            @as(c_uint, @bitCast(@as(c_int, 1088359270))),
            @as(c_uint, @bitCast(@as(c_int, 936918000))),
            2847714899,
            3736837829,
            @as(c_uint, @bitCast(@as(c_int, 1202900863))),
            @as(c_uint, @bitCast(@as(c_int, 817233897))),
            3183342108,
            3401237130,
            @as(c_uint, @bitCast(@as(c_int, 1404277552))),
            @as(c_uint, @bitCast(@as(c_int, 615818150))),
            3134207493,
            3453421203,
            @as(c_uint, @bitCast(@as(c_int, 1423857449))),
            @as(c_uint, @bitCast(@as(c_int, 601450431))),
            3009837614,
            3294710456,
            @as(c_uint, @bitCast(@as(c_int, 1567103746))),
            @as(c_uint, @bitCast(@as(c_int, 711928724))),
            3020668471,
            3272380065,
            @as(c_uint, @bitCast(@as(c_int, 1510334235))),
            @as(c_uint, @bitCast(@as(c_int, 755167117))),
        };
    };
    _ = &crc_table;
    var crc: c_uint = ~@as(c_uint, 0);
    _ = &crc;
    var i: c_int = undefined;
    _ = &i;
    {
        i = 0;
        while (i < len) : (i += 1) {
            crc = (crc >> @intCast(8)) ^ crc_table.static[@as(c_uint, @bitCast(@as(c_uint, (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk buffer + @as(usize, @intCast(tmp)) else break :blk buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*))) ^ (crc & @as(c_uint, @bitCast(@as(c_int, 255))))];
        }
    }
    return ~crc;
}
pub fn stbiw__wpcrc(arg_data: [*c][*c]u8, arg_len: c_int) callconv(.c) void {
    var data = arg_data;
    _ = &data;
    var len = arg_len;
    _ = &len;
    var crc: c_uint = stbiw__crc32((data.* - @as(usize, @bitCast(@as(isize, @intCast(len))))) - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4))))), len + @as(c_int, 4));
    _ = &crc;
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    data.*[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(u8, @truncate((crc >> @intCast(24)) & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(u8, @truncate((crc >> @intCast(16)) & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                        data.*[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(u8, @truncate((crc >> @intCast(8)) & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                    data.*[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(u8, @truncate(crc & @as(c_uint, @bitCast(@as(c_int, 255)))))));
                data.*[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &data.*;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
}
pub fn stbiw__paeth(arg_a: c_int, arg_b: c_int, arg_c: c_int) callconv(.c) u8 {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var c = arg_c;
    _ = &c;
    var p: c_int = (a + b) - c;
    _ = &p;
    var pa: c_int = abs(p - a);
    _ = &pa;
    var pb: c_int = abs(p - b);
    _ = &pb;
    var pc: c_int = abs(p - c);
    _ = &pc;
    if ((pa <= pb) and (pa <= pc)) return @as(u8, @bitCast(@as(i8, @truncate(a & @as(c_int, 255)))));
    if (pb <= pc) return @as(u8, @bitCast(@as(i8, @truncate(b & @as(c_int, 255)))));
    return @as(u8, @bitCast(@as(i8, @truncate(c & @as(c_int, 255)))));
}
pub fn stbiw__encode_png_line(arg_pixels: [*c]u8, arg_stride_bytes: c_int, arg_width: c_int, arg_height: c_int, arg_y: c_int, arg_n: c_int, arg_filter_type: c_int, arg_line_buffer: [*c]i8) callconv(.c) void {
    var pixels = arg_pixels;
    _ = &pixels;
    var stride_bytes = arg_stride_bytes;
    _ = &stride_bytes;
    var width = arg_width;
    _ = &width;
    var height = arg_height;
    _ = &height;
    var y = arg_y;
    _ = &y;
    var n = arg_n;
    _ = &n;
    var filter_type = arg_filter_type;
    _ = &filter_type;
    var line_buffer = arg_line_buffer;
    _ = &line_buffer;
    const mapping = struct {
        var static: [5]c_int = [5]c_int{
            0,
            1,
            2,
            3,
            4,
        };
    };
    _ = &mapping;
    const firstmap = struct {
        var static: [5]c_int = [5]c_int{
            0,
            1,
            0,
            5,
            6,
        };
    };
    _ = &firstmap;
    var mymap: [*c]c_int = if (y != @as(c_int, 0)) @as([*c]c_int, @ptrCast(@alignCast(&mapping.static[@as(usize, @intCast(0))]))) else @as([*c]c_int, @ptrCast(@alignCast(&firstmap.static[@as(usize, @intCast(0))])));
    _ = &mymap;
    var i: c_int = undefined;
    _ = &i;
    var @"type": c_int = (blk: {
        const tmp = filter_type;
        if (tmp >= 0) break :blk mymap + @as(usize, @intCast(tmp)) else break :blk mymap - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*;
    _ = &@"type";
    var z: [*c]u8 = pixels + @as(usize, @bitCast(@as(isize, @intCast(stride_bytes * (if (stbi__flip_vertically_on_write != 0) (height - @as(c_int, 1)) - y else y)))));
    _ = &z;
    var signed_stride: c_int = if (stbi__flip_vertically_on_write != 0) -stride_bytes else stride_bytes;
    _ = &signed_stride;
    if (@"type" == @as(c_int, 0)) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(line_buffer)), @as(?*const anyopaque, @ptrCast(z)), @as(c_ulong, @bitCast(@as(c_long, width * n))));
        return;
    }
    {
        i = 0;
        while (i < n) : (i += 1) {
            while (true) {
                switch (@"type") {
                    @as(c_int, 1) => {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast((blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*));
                        break;
                    },
                    @as(c_int, 2) => {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - signed_stride;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*)))))));
                        break;
                    },
                    @as(c_int, 3) => {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - (@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - signed_stride;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) >> @intCast(1))))));
                        break;
                    },
                    @as(c_int, 4) => {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - @as(c_int, @bitCast(@as(c_uint, stbiw__paeth(@as(c_int, 0), @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - signed_stride;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))), @as(c_int, 0)))))))));
                        break;
                    },
                    @as(c_int, 5) => {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast((blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*));
                        break;
                    },
                    @as(c_int, 6) => {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast((blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*));
                        break;
                    },
                    else => {},
                }
                break;
            }
        }
    }
    while (true) {
        switch (@"type") {
            @as(c_int, 1) => {
                {
                    i = n;
                    while (i < (width * n)) : (i += 1) {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - n;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*)))))));
                    }
                }
                break;
            },
            @as(c_int, 2) => {
                {
                    i = n;
                    while (i < (width * n)) : (i += 1) {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - signed_stride;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*)))))));
                    }
                }
                break;
            },
            @as(c_int, 3) => {
                {
                    i = n;
                    while (i < (width * n)) : (i += 1) {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - ((@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - n;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) + @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - signed_stride;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*)))) >> @intCast(1))))));
                    }
                }
                break;
            },
            @as(c_int, 4) => {
                {
                    i = n;
                    while (i < (width * n)) : (i += 1) {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - @as(c_int, @bitCast(@as(c_uint, stbiw__paeth(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - n;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))), @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - signed_stride;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))), @as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = (i - signed_stride) - n;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*)))))))))));
                    }
                }
                break;
            },
            @as(c_int, 5) => {
                {
                    i = n;
                    while (i < (width * n)) : (i += 1) {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - (@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - n;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) >> @intCast(1))))));
                    }
                }
                break;
            },
            @as(c_int, 6) => {
                {
                    i = n;
                    while (i < (width * n)) : (i += 1) {
                        (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).* = @as(i8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))) - @as(c_int, @bitCast(@as(c_uint, stbiw__paeth(@as(c_int, @bitCast(@as(c_uint, (blk: {
                            const tmp = i - n;
                            if (tmp >= 0) break :blk z + @as(usize, @intCast(tmp)) else break :blk z - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                        }).*))), @as(c_int, 0), @as(c_int, 0)))))))));
                    }
                }
                break;
            },
            else => {},
        }
        break;
    }
}
pub export fn stbi_write_png_to_mem(arg_pixels: [*c]const u8, arg_stride_bytes: c_int, arg_x: c_int, arg_y: c_int, arg_n: c_int, arg_out_len: [*c]c_int) callconv(.c) [*c]u8 {
    var pixels = arg_pixels;
    _ = &pixels;
    var stride_bytes = arg_stride_bytes;
    _ = &stride_bytes;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var n = arg_n;
    _ = &n;
    var out_len = arg_out_len;
    _ = &out_len;
    var force_filter: c_int = stbi_write_force_png_filter;
    _ = &force_filter;
    var ctype: [5]c_int = [5]c_int{
        -@as(c_int, 1),
        0,
        4,
        2,
        6,
    };
    _ = &ctype;
    var sig: [8]u8 = [8]u8{
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
    };
    _ = &sig;
    var out: [*c]u8 = undefined;
    _ = &out;
    var o: [*c]u8 = undefined;
    _ = &o;
    var filt: [*c]u8 = undefined;
    _ = &filt;
    var zlib: [*c]u8 = undefined;
    _ = &zlib;
    var line_buffer: [*c]i8 = undefined;
    _ = &line_buffer;
    var j: c_int = undefined;
    _ = &j;
    var zlen: c_int = undefined;
    _ = &zlen;
    if (stride_bytes == @as(c_int, 0)) {
        stride_bytes = x * n;
    }
    if (force_filter >= @as(c_int, 5)) {
        force_filter = -@as(c_int, 1);
    }
    filt = @as([*c]u8, @ptrCast(@alignCast(malloc(@as(c_ulong, @bitCast(@as(c_long, ((x * n) + @as(c_int, 1)) * y)))))));
    if (!(filt != null)) return null;
    line_buffer = @as([*c]i8, @ptrCast(@alignCast(malloc(@as(c_ulong, @bitCast(@as(c_long, x * n)))))));
    if (!(line_buffer != null)) {
        free(@as(?*anyopaque, @ptrCast(filt)));
        return null;
    }
    {
        j = 0;
        while (j < y) : (j += 1) {
            var filter_type: c_int = undefined;
            _ = &filter_type;
            if (force_filter > -@as(c_int, 1)) {
                filter_type = force_filter;
                stbiw__encode_png_line(@as([*c]u8, @ptrCast(@constCast(@volatileCast(pixels)))), stride_bytes, x, y, j, n, force_filter, line_buffer);
            } else {
                var best_filter: c_int = 0;
                _ = &best_filter;
                var best_filter_val: c_int = 2147483647;
                _ = &best_filter_val;
                var est: c_int = undefined;
                _ = &est;
                var i: c_int = undefined;
                _ = &i;
                {
                    filter_type = 0;
                    while (filter_type < @as(c_int, 5)) : (filter_type += 1) {
                        stbiw__encode_png_line(@as([*c]u8, @ptrCast(@constCast(@volatileCast(pixels)))), stride_bytes, x, y, j, n, filter_type, line_buffer);
                        est = 0;
                        {
                            i = 0;
                            while (i < (x * n)) : (i += 1) {
                                est += abs(@as(c_int, @bitCast(@as(c_int, (blk: {
                                    const tmp = i;
                                    if (tmp >= 0) break :blk line_buffer + @as(usize, @intCast(tmp)) else break :blk line_buffer - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                }).*))));
                            }
                        }
                        if (est < best_filter_val) {
                            best_filter_val = est;
                            best_filter = filter_type;
                        }
                    }
                }
                if (filter_type != best_filter) {
                    stbiw__encode_png_line(@as([*c]u8, @ptrCast(@constCast(@volatileCast(pixels)))), stride_bytes, x, y, j, n, best_filter, line_buffer);
                    filter_type = best_filter;
                }
            }
            (blk: {
                const tmp = j * ((x * n) + @as(c_int, 1));
                if (tmp >= 0) break :blk filt + @as(usize, @intCast(tmp)) else break :blk filt - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).* = @as(u8, @bitCast(@as(i8, @truncate(filter_type))));
            _ = memmove(@as(?*anyopaque, @ptrCast((filt + @as(usize, @bitCast(@as(isize, @intCast(j * ((x * n) + @as(c_int, 1))))))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))))), @as(?*const anyopaque, @ptrCast(line_buffer)), @as(c_ulong, @bitCast(@as(c_long, x * n))));
        }
    }
    free(@as(?*anyopaque, @ptrCast(line_buffer)));
    zlib = stbi_zlib_compress(filt, y * ((x * n) + @as(c_int, 1)), &zlen, stbi_write_png_compression_level);
    free(@as(?*anyopaque, @ptrCast(filt)));
    if (!(zlib != null)) return null;
    out = @as([*c]u8, @ptrCast(@alignCast(malloc(@as(c_ulong, @bitCast(@as(c_long, ((((@as(c_int, 8) + @as(c_int, 12)) + @as(c_int, 13)) + @as(c_int, 12)) + zlen) + @as(c_int, 12))))))));
    if (!(out != null)) return null;
    out_len.* = ((((@as(c_int, 8) + @as(c_int, 12)) + @as(c_int, 13)) + @as(c_int, 12)) + zlen) + @as(c_int, 12);
    o = out;
    _ = memmove(@as(?*anyopaque, @ptrCast(o)), @as(?*const anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&sig[@as(usize, @intCast(0))]))))), @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 8)))));
    o += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 8)))));
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    o[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(i8, @truncate((@as(c_int, 13) >> @intCast(24)) & @as(c_int, 255)))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate((@as(c_int, 13) >> @intCast(16)) & @as(c_int, 255)))));
                        o[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate((@as(c_int, 13) >> @intCast(8)) & @as(c_int, 255)))));
                    o[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 13) & @as(c_int, 255)))));
                o[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &o;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    o[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IHDR"[@as(c_uint, @intCast(@as(c_int, 0)))]))) & @as(c_int, 255)))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IHDR"[@as(c_uint, @intCast(@as(c_int, 1)))]))) & @as(c_int, 255)))));
                        o[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IHDR"[@as(c_uint, @intCast(@as(c_int, 2)))]))) & @as(c_int, 255)))));
                    o[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IHDR"[@as(c_uint, @intCast(@as(c_int, 3)))]))) & @as(c_int, 255)))));
                o[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &o;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    o[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(i8, @truncate((x >> @intCast(24)) & @as(c_int, 255)))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate((x >> @intCast(16)) & @as(c_int, 255)))));
                        o[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate((x >> @intCast(8)) & @as(c_int, 255)))));
                    o[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(i8, @truncate(x & @as(c_int, 255)))));
                o[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &o;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    o[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(i8, @truncate((y >> @intCast(24)) & @as(c_int, 255)))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate((y >> @intCast(16)) & @as(c_int, 255)))));
                        o[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate((y >> @intCast(8)) & @as(c_int, 255)))));
                    o[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(i8, @truncate(y & @as(c_int, 255)))));
                o[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &o;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
    (blk: {
        const ref = &o;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).* = 8;
    (blk: {
        const ref = &o;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).* = @as(u8, @bitCast(@as(i8, @truncate(ctype[@as(c_uint, @intCast(n))] & @as(c_int, 255)))));
    (blk: {
        const ref = &o;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).* = 0;
    (blk: {
        const ref = &o;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).* = 0;
    (blk: {
        const ref = &o;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).* = 0;
    stbiw__wpcrc(&o, @as(c_int, 13));
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    o[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(i8, @truncate((zlen >> @intCast(24)) & @as(c_int, 255)))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate((zlen >> @intCast(16)) & @as(c_int, 255)))));
                        o[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate((zlen >> @intCast(8)) & @as(c_int, 255)))));
                    o[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(i8, @truncate(zlen & @as(c_int, 255)))));
                o[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &o;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    o[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IDAT"[@as(c_uint, @intCast(@as(c_int, 0)))]))) & @as(c_int, 255)))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IDAT"[@as(c_uint, @intCast(@as(c_int, 1)))]))) & @as(c_int, 255)))));
                        o[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IDAT"[@as(c_uint, @intCast(@as(c_int, 2)))]))) & @as(c_int, 255)))));
                    o[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IDAT"[@as(c_uint, @intCast(@as(c_int, 3)))]))) & @as(c_int, 255)))));
                o[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &o;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
    _ = memmove(@as(?*anyopaque, @ptrCast(o)), @as(?*const anyopaque, @ptrCast(zlib)), @as(c_ulong, @bitCast(@as(c_long, zlen))));
    o += @as(usize, @bitCast(@as(isize, @intCast(zlen))));
    free(@as(?*anyopaque, @ptrCast(zlib)));
    stbiw__wpcrc(&o, zlen);
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    o[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(i8, @truncate((@as(c_int, 0) >> @intCast(24)) & @as(c_int, 255)))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate((@as(c_int, 0) >> @intCast(16)) & @as(c_int, 255)))));
                        o[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate((@as(c_int, 0) >> @intCast(8)) & @as(c_int, 255)))));
                    o[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 0) & @as(c_int, 255)))));
                o[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &o;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
    _ = blk: {
        _ = blk_1: {
            _ = blk_2: {
                _ = blk_3: {
                    o[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IEND"[@as(c_uint, @intCast(@as(c_int, 0)))]))) & @as(c_int, 255)))));
                    break :blk_3 blk_4: {
                        const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IEND"[@as(c_uint, @intCast(@as(c_int, 1)))]))) & @as(c_int, 255)))));
                        o[@as(c_uint, @intCast(@as(c_int, 1)))] = tmp;
                        break :blk_4 tmp;
                    };
                };
                break :blk_2 blk_3: {
                    const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IEND"[@as(c_uint, @intCast(@as(c_int, 2)))]))) & @as(c_int, 255)))));
                    o[@as(c_uint, @intCast(@as(c_int, 2)))] = tmp;
                    break :blk_3 tmp;
                };
            };
            break :blk_1 blk_2: {
                const tmp = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, "IEND"[@as(c_uint, @intCast(@as(c_int, 3)))]))) & @as(c_int, 255)))));
                o[@as(c_uint, @intCast(@as(c_int, 3)))] = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            const ref = &o;
            ref.* += @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 4)))));
            break :blk_1 ref.*;
        };
    };
    stbiw__wpcrc(&o, @as(c_int, 0));
    _ = (o == (out + @as(usize, @bitCast(@as(isize, @intCast(out_len.*)))))) or ((blk: {
        __assert_fail("o == out + *out_len", "/home/x/next/arcan/src/engine/external/stb_image_write.h", @as(c_int, 1209), "stbi_write_png_to_mem");
        break :blk @as(c_int, 0);
    }) != 0);
    return out;
}
pub const stbiw__jpg_ZigZag: [64]u8 = [64]u8{
    0,
    1,
    5,
    6,
    14,
    15,
    27,
    28,
    2,
    4,
    7,
    13,
    16,
    26,
    29,
    42,
    3,
    8,
    12,
    17,
    25,
    30,
    41,
    43,
    9,
    11,
    18,
    24,
    31,
    40,
    44,
    53,
    10,
    19,
    23,
    32,
    39,
    45,
    52,
    54,
    20,
    22,
    33,
    38,
    46,
    51,
    55,
    60,
    21,
    34,
    37,
    47,
    50,
    56,
    59,
    61,
    35,
    36,
    48,
    49,
    57,
    58,
    62,
    63,
};
pub fn stbiw__jpg_writeBits(arg_s: [*c]stbi__write_context, arg_bitBufP: [*c]c_int, arg_bitCntP: [*c]c_int, arg_bs: [*c]const c_ushort) callconv(.c) void {
    var s = arg_s;
    _ = &s;
    var bitBufP = arg_bitBufP;
    _ = &bitBufP;
    var bitCntP = arg_bitCntP;
    _ = &bitCntP;
    var bs = arg_bs;
    _ = &bs;
    var bitBuf: c_int = bitBufP.*;
    _ = &bitBuf;
    var bitCnt: c_int = bitCntP.*;
    _ = &bitCnt;
    bitCnt += @as(c_int, @bitCast(@as(c_uint, bs[@as(c_uint, @intCast(@as(c_int, 1)))])));
    bitBuf |= @as(c_int, @bitCast(@as(c_uint, bs[@as(c_uint, @intCast(@as(c_int, 0)))]))) << @intCast(@as(c_int, 24) - bitCnt);
    while (bitCnt >= @as(c_int, 8)) {
        var c: u8 = @as(u8, @bitCast(@as(i8, @truncate((bitBuf >> @intCast(16)) & @as(c_int, 255)))));
        _ = &c;
        stbiw__putc(s, c);
        if (@as(c_int, @bitCast(@as(c_uint, c))) == @as(c_int, 255)) {
            stbiw__putc(s, @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 0))))));
        }
        bitBuf <<= @intCast(@as(c_int, 8));
        bitCnt -= @as(c_int, 8);
    }
    bitBufP.* = bitBuf;
    bitCntP.* = bitCnt;
}
pub fn stbiw__jpg_DCT(arg_d0p: [*c]f32, arg_d1p: [*c]f32, arg_d2p: [*c]f32, arg_d3p: [*c]f32, arg_d4p: [*c]f32, arg_d5p: [*c]f32, arg_d6p: [*c]f32, arg_d7p: [*c]f32) callconv(.c) void {
    var d0p = arg_d0p;
    _ = &d0p;
    var d1p = arg_d1p;
    _ = &d1p;
    var d2p = arg_d2p;
    _ = &d2p;
    var d3p = arg_d3p;
    _ = &d3p;
    var d4p = arg_d4p;
    _ = &d4p;
    var d5p = arg_d5p;
    _ = &d5p;
    var d6p = arg_d6p;
    _ = &d6p;
    var d7p = arg_d7p;
    _ = &d7p;
    var d0: f32 = d0p.*;
    _ = &d0;
    var d1: f32 = d1p.*;
    _ = &d1;
    var d2: f32 = d2p.*;
    _ = &d2;
    var d3: f32 = d3p.*;
    _ = &d3;
    var d4: f32 = d4p.*;
    _ = &d4;
    var d5: f32 = d5p.*;
    _ = &d5;
    var d6: f32 = d6p.*;
    _ = &d6;
    var d7: f32 = d7p.*;
    _ = &d7;
    var z1: f32 = undefined;
    _ = &z1;
    var z2: f32 = undefined;
    _ = &z2;
    var z3: f32 = undefined;
    _ = &z3;
    var z4: f32 = undefined;
    _ = &z4;
    var z5: f32 = undefined;
    _ = &z5;
    var z11: f32 = undefined;
    _ = &z11;
    var z13: f32 = undefined;
    _ = &z13;
    var tmp0: f32 = d0 + d7;
    _ = &tmp0;
    var tmp7: f32 = d0 - d7;
    _ = &tmp7;
    var tmp1: f32 = d1 + d6;
    _ = &tmp1;
    var tmp6: f32 = d1 - d6;
    _ = &tmp6;
    var tmp2: f32 = d2 + d5;
    _ = &tmp2;
    var tmp5: f32 = d2 - d5;
    _ = &tmp5;
    var tmp3: f32 = d3 + d4;
    _ = &tmp3;
    var tmp4: f32 = d3 - d4;
    _ = &tmp4;
    var tmp10: f32 = tmp0 + tmp3;
    _ = &tmp10;
    var tmp13: f32 = tmp0 - tmp3;
    _ = &tmp13;
    var tmp11: f32 = tmp1 + tmp2;
    _ = &tmp11;
    var tmp12: f32 = tmp1 - tmp2;
    _ = &tmp12;
    d0 = tmp10 + tmp11;
    d4 = tmp10 - tmp11;
    z1 = (tmp12 + tmp13) * 0.7071067690849304;
    d2 = tmp13 + z1;
    d6 = tmp13 - z1;
    tmp10 = tmp4 + tmp5;
    tmp11 = tmp5 + tmp6;
    tmp12 = tmp6 + tmp7;
    z5 = (tmp10 - tmp12) * 0.3826834261417389;
    z2 = (tmp10 * 0.5411961078643799) + z5;
    z4 = (tmp12 * 1.3065630197525024) + z5;
    z3 = tmp11 * 0.7071067690849304;
    z11 = tmp7 + z3;
    z13 = tmp7 - z3;
    d5p.* = z13 + z2;
    d3p.* = z13 - z2;
    d1p.* = z11 + z4;
    d7p.* = z11 - z4;
    d0p.* = d0;
    d2p.* = d2;
    d4p.* = d4;
    d6p.* = d6;
}
pub fn stbiw__jpg_calcBits(arg_val: c_int, arg_bits: [*c]c_ushort) callconv(.c) void {
    var val = arg_val;
    _ = &val;
    var bits = arg_bits;
    _ = &bits;
    var tmp1: c_int = if (val < @as(c_int, 0)) -val else val;
    _ = &tmp1;
    val = if (val < @as(c_int, 0)) val - @as(c_int, 1) else val;
    bits[@as(c_uint, @intCast(@as(c_int, 1)))] = 1;
    while ((blk: {
        const ref = &tmp1;
        ref.* >>= @intCast(@as(c_int, 1));
        break :blk ref.*;
    }) != 0) {
        bits[@as(c_uint, @intCast(@as(c_int, 1)))] +%= 1;
    }
    bits[@as(c_uint, @intCast(@as(c_int, 0)))] = @as(c_ushort, @bitCast(@as(c_short, @truncate(val & ((@as(c_int, 1) << @intCast(@as(c_int, @bitCast(@as(c_uint, bits[@as(c_uint, @intCast(@as(c_int, 1)))]))))) - @as(c_int, 1))))));
}
pub fn stbiw__jpg_processDU(arg_s: [*c]stbi__write_context, arg_bitBuf: [*c]c_int, arg_bitCnt: [*c]c_int, arg_CDU: [*c]f32, arg_du_stride: c_int, arg_fdtbl: [*c]f32, arg_DC: c_int, HTDC: [*c]const [2]c_ushort, HTAC: [*c]const [2]c_ushort) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var bitBuf = arg_bitBuf;
    _ = &bitBuf;
    var bitCnt = arg_bitCnt;
    _ = &bitCnt;
    var CDU = arg_CDU;
    _ = &CDU;
    var du_stride = arg_du_stride;
    _ = &du_stride;
    var fdtbl = arg_fdtbl;
    _ = &fdtbl;
    var DC = arg_DC;
    _ = &DC;
    _ = &HTDC;
    _ = &HTAC;
    const EOB: [2]c_ushort = [2]c_ushort{
        HTAC[@as(c_uint, @intCast(@as(c_int, 0)))][@as(c_uint, @intCast(@as(c_int, 0)))],
        HTAC[@as(c_uint, @intCast(@as(c_int, 0)))][@as(c_uint, @intCast(@as(c_int, 1)))],
    };
    _ = &EOB;
    const M16zeroes: [2]c_ushort = [2]c_ushort{
        HTAC[@as(c_uint, @intCast(@as(c_int, 240)))][@as(c_uint, @intCast(@as(c_int, 0)))],
        HTAC[@as(c_uint, @intCast(@as(c_int, 240)))][@as(c_uint, @intCast(@as(c_int, 1)))],
    };
    _ = &M16zeroes;
    var dataOff: c_int = undefined;
    _ = &dataOff;
    var i: c_int = undefined;
    _ = &i;
    var j: c_int = undefined;
    _ = &j;
    var n: c_int = undefined;
    _ = &n;
    var diff: c_int = undefined;
    _ = &diff;
    var end0pos: c_int = undefined;
    _ = &end0pos;
    var x: c_int = undefined;
    _ = &x;
    var y: c_int = undefined;
    _ = &y;
    var DU: [64]c_int = undefined;
    _ = &DU;
    {
        _ = blk: {
            dataOff = 0;
            break :blk blk_1: {
                const tmp = du_stride * @as(c_int, 8);
                n = tmp;
                break :blk_1 tmp;
            };
        };
        while (dataOff < n) : (dataOff += du_stride) {
            stbiw__jpg_DCT(&(blk: {
                const tmp = dataOff;
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + @as(c_int, 1);
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + @as(c_int, 2);
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + @as(c_int, 3);
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + @as(c_int, 4);
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + @as(c_int, 5);
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + @as(c_int, 6);
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + @as(c_int, 7);
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*);
        }
    }
    {
        dataOff = 0;
        while (dataOff < @as(c_int, 8)) : (dataOff += 1) {
            stbiw__jpg_DCT(&(blk: {
                const tmp = dataOff;
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + du_stride;
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + (du_stride * @as(c_int, 2));
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + (du_stride * @as(c_int, 3));
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + (du_stride * @as(c_int, 4));
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + (du_stride * @as(c_int, 5));
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + (du_stride * @as(c_int, 6));
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*, &(blk: {
                const tmp = dataOff + (du_stride * @as(c_int, 7));
                if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*);
        }
    }
    {
        _ = blk: {
            y = 0;
            break :blk blk_1: {
                const tmp = @as(c_int, 0);
                j = tmp;
                break :blk_1 tmp;
            };
        };
        while (y < @as(c_int, 8)) : (y += 1) {
            {
                x = 0;
                while (x < @as(c_int, 8)) : (_ = blk: {
                    x += 1;
                    break :blk blk_1: {
                        const ref = &j;
                        ref.* += 1;
                        break :blk_1 ref.*;
                    };
                }) {
                    var v: f32 = undefined;
                    _ = &v;
                    i = (y * du_stride) + x;
                    v = (blk: {
                        const tmp = i;
                        if (tmp >= 0) break :blk CDU + @as(usize, @intCast(tmp)) else break :blk CDU - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).* * (blk: {
                        const tmp = j;
                        if (tmp >= 0) break :blk fdtbl + @as(usize, @intCast(tmp)) else break :blk fdtbl - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).*;
                    DU[stbiw__jpg_ZigZag[@as(c_uint, @intCast(j))]] = @as(c_int, @intFromFloat(if (v < @as(f32, @floatFromInt(@as(c_int, 0)))) v - 0.5 else v + 0.5));
                }
            }
        }
    }
    diff = DU[@as(c_uint, @intCast(@as(c_int, 0)))] - DC;
    if (diff == @as(c_int, 0)) {
        stbiw__jpg_writeBits(s, bitBuf, bitCnt, @as([*c]const c_ushort, @ptrCast(@alignCast(&HTDC[@as(c_uint, @intCast(@as(c_int, 0)))][@as(usize, @intCast(0))]))));
    } else {
        var bits: [2]c_ushort = undefined;
        _ = &bits;
        stbiw__jpg_calcBits(diff, @as([*c]c_ushort, @ptrCast(@alignCast(&bits[@as(usize, @intCast(0))]))));
        stbiw__jpg_writeBits(s, bitBuf, bitCnt, @as([*c]const c_ushort, @ptrCast(@alignCast(&HTDC[bits[@as(c_uint, @intCast(@as(c_int, 1)))]][@as(usize, @intCast(0))]))));
        stbiw__jpg_writeBits(s, bitBuf, bitCnt, @as([*c]c_ushort, @ptrCast(@alignCast(&bits[@as(usize, @intCast(0))]))));
    }
    end0pos = 63;
    while ((end0pos > @as(c_int, 0)) and (DU[@as(c_uint, @intCast(end0pos))] == @as(c_int, 0))) : (end0pos -= 1) {}
    if (end0pos == @as(c_int, 0)) {
        stbiw__jpg_writeBits(s, bitBuf, bitCnt, @as([*c]const c_ushort, @ptrCast(@alignCast(&EOB[@as(usize, @intCast(0))]))));
        return DU[@as(c_uint, @intCast(@as(c_int, 0)))];
    }
    {
        i = 1;
        while (i <= end0pos) : (i += 1) {
            var startpos: c_int = i;
            _ = &startpos;
            var nrzeroes: c_int = undefined;
            _ = &nrzeroes;
            var bits: [2]c_ushort = undefined;
            _ = &bits;
            while ((DU[@as(c_uint, @intCast(i))] == @as(c_int, 0)) and (i <= end0pos)) : (i += 1) {}
            nrzeroes = i - startpos;
            if (nrzeroes >= @as(c_int, 16)) {
                var lng: c_int = nrzeroes >> @intCast(4);
                _ = &lng;
                var nrmarker: c_int = undefined;
                _ = &nrmarker;
                {
                    nrmarker = 1;
                    while (nrmarker <= lng) : (nrmarker += 1) {
                        stbiw__jpg_writeBits(s, bitBuf, bitCnt, @as([*c]const c_ushort, @ptrCast(@alignCast(&M16zeroes[@as(usize, @intCast(0))]))));
                    }
                }
                nrzeroes &= @as(c_int, 15);
            }
            stbiw__jpg_calcBits(DU[@as(c_uint, @intCast(i))], @as([*c]c_ushort, @ptrCast(@alignCast(&bits[@as(usize, @intCast(0))]))));
            stbiw__jpg_writeBits(s, bitBuf, bitCnt, @as([*c]const c_ushort, @ptrCast(@alignCast(&(blk: {
                const tmp = (nrzeroes << @intCast(4)) + @as(c_int, @bitCast(@as(c_uint, bits[@as(c_uint, @intCast(@as(c_int, 1)))])));
                if (tmp >= 0) break :blk HTAC + @as(usize, @intCast(tmp)) else break :blk HTAC - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*[@as(usize, @intCast(0))]))));
            stbiw__jpg_writeBits(s, bitBuf, bitCnt, @as([*c]c_ushort, @ptrCast(@alignCast(&bits[@as(usize, @intCast(0))]))));
        }
    }
    if (end0pos != @as(c_int, 63)) {
        stbiw__jpg_writeBits(s, bitBuf, bitCnt, @as([*c]const c_ushort, @ptrCast(@alignCast(&EOB[@as(usize, @intCast(0))]))));
    }
    return DU[@as(c_uint, @intCast(@as(c_int, 0)))];
}
pub fn stbi_write_jpg_core(arg_s: [*c]stbi__write_context, arg_width: c_int, arg_height: c_int, arg_comp: c_int, arg_data: ?*const anyopaque, arg_quality: c_int) callconv(.c) c_int {
    var s = arg_s;
    _ = &s;
    var width = arg_width;
    _ = &width;
    var height = arg_height;
    _ = &height;
    var comp = arg_comp;
    _ = &comp;
    var data = arg_data;
    _ = &data;
    var quality = arg_quality;
    _ = &quality;
    const std_dc_luminance_nrcodes = struct {
        const static: [17]u8 = [17]u8{
            0,
            0,
            1,
            5,
            1,
            1,
            1,
            1,
            1,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        };
    };
    _ = &std_dc_luminance_nrcodes;
    const std_dc_luminance_values = struct {
        const static: [12]u8 = [12]u8{
            0,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
        };
    };
    _ = &std_dc_luminance_values;
    const std_ac_luminance_nrcodes = struct {
        const static: [17]u8 = [17]u8{
            0,
            0,
            2,
            1,
            3,
            3,
            2,
            4,
            3,
            5,
            5,
            4,
            4,
            0,
            0,
            1,
            125,
        };
    };
    _ = &std_ac_luminance_nrcodes;
    const std_ac_luminance_values = struct {
        const static: [162]u8 = [162]u8{
            1,
            2,
            3,
            0,
            4,
            17,
            5,
            18,
            33,
            49,
            65,
            6,
            19,
            81,
            97,
            7,
            34,
            113,
            20,
            50,
            129,
            145,
            161,
            8,
            35,
            66,
            177,
            193,
            21,
            82,
            209,
            240,
            36,
            51,
            98,
            114,
            130,
            9,
            10,
            22,
            23,
            24,
            25,
            26,
            37,
            38,
            39,
            40,
            41,
            42,
            52,
            53,
            54,
            55,
            56,
            57,
            58,
            67,
            68,
            69,
            70,
            71,
            72,
            73,
            74,
            83,
            84,
            85,
            86,
            87,
            88,
            89,
            90,
            99,
            100,
            101,
            102,
            103,
            104,
            105,
            106,
            115,
            116,
            117,
            118,
            119,
            120,
            121,
            122,
            131,
            132,
            133,
            134,
            135,
            136,
            137,
            138,
            146,
            147,
            148,
            149,
            150,
            151,
            152,
            153,
            154,
            162,
            163,
            164,
            165,
            166,
            167,
            168,
            169,
            170,
            178,
            179,
            180,
            181,
            182,
            183,
            184,
            185,
            186,
            194,
            195,
            196,
            197,
            198,
            199,
            200,
            201,
            202,
            210,
            211,
            212,
            213,
            214,
            215,
            216,
            217,
            218,
            225,
            226,
            227,
            228,
            229,
            230,
            231,
            232,
            233,
            234,
            241,
            242,
            243,
            244,
            245,
            246,
            247,
            248,
            249,
            250,
        };
    };
    _ = &std_ac_luminance_values;
    const std_dc_chrominance_nrcodes = struct {
        const static: [17]u8 = [17]u8{
            0,
            0,
            3,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            0,
            0,
            0,
            0,
            0,
        };
    };
    _ = &std_dc_chrominance_nrcodes;
    const std_dc_chrominance_values = struct {
        const static: [12]u8 = [12]u8{
            0,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
        };
    };
    _ = &std_dc_chrominance_values;
    const std_ac_chrominance_nrcodes = struct {
        const static: [17]u8 = [17]u8{
            0,
            0,
            2,
            1,
            2,
            4,
            4,
            3,
            4,
            7,
            5,
            4,
            4,
            0,
            1,
            2,
            119,
        };
    };
    _ = &std_ac_chrominance_nrcodes;
    const std_ac_chrominance_values = struct {
        const static: [162]u8 = [162]u8{
            0,
            1,
            2,
            3,
            17,
            4,
            5,
            33,
            49,
            6,
            18,
            65,
            81,
            7,
            97,
            113,
            19,
            34,
            50,
            129,
            8,
            20,
            66,
            145,
            161,
            177,
            193,
            9,
            35,
            51,
            82,
            240,
            21,
            98,
            114,
            209,
            10,
            22,
            36,
            52,
            225,
            37,
            241,
            23,
            24,
            25,
            26,
            38,
            39,
            40,
            41,
            42,
            53,
            54,
            55,
            56,
            57,
            58,
            67,
            68,
            69,
            70,
            71,
            72,
            73,
            74,
            83,
            84,
            85,
            86,
            87,
            88,
            89,
            90,
            99,
            100,
            101,
            102,
            103,
            104,
            105,
            106,
            115,
            116,
            117,
            118,
            119,
            120,
            121,
            122,
            130,
            131,
            132,
            133,
            134,
            135,
            136,
            137,
            138,
            146,
            147,
            148,
            149,
            150,
            151,
            152,
            153,
            154,
            162,
            163,
            164,
            165,
            166,
            167,
            168,
            169,
            170,
            178,
            179,
            180,
            181,
            182,
            183,
            184,
            185,
            186,
            194,
            195,
            196,
            197,
            198,
            199,
            200,
            201,
            202,
            210,
            211,
            212,
            213,
            214,
            215,
            216,
            217,
            218,
            226,
            227,
            228,
            229,
            230,
            231,
            232,
            233,
            234,
            242,
            243,
            244,
            245,
            246,
            247,
            248,
            249,
            250,
        };
    };
    _ = &std_ac_chrominance_values;
    const YDC_HT = struct {
        const static: [256][2]c_ushort = [12][2]c_ushort{
            [2]c_ushort{
                0,
                2,
            },
            [2]c_ushort{
                2,
                3,
            },
            [2]c_ushort{
                3,
                3,
            },
            [2]c_ushort{
                4,
                3,
            },
            [2]c_ushort{
                5,
                3,
            },
            [2]c_ushort{
                6,
                3,
            },
            [2]c_ushort{
                14,
                4,
            },
            [2]c_ushort{
                30,
                5,
            },
            [2]c_ushort{
                62,
                6,
            },
            [2]c_ushort{
                126,
                7,
            },
            [2]c_ushort{
                254,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 510))))),
                9,
            },
        } ++ [1][2]c_ushort{@import("std").mem.zeroes([2]c_ushort)} ** 244;
    };
    _ = &YDC_HT;
    const UVDC_HT = struct {
        const static: [256][2]c_ushort = [12][2]c_ushort{
            [2]c_ushort{
                0,
                2,
            },
            [2]c_ushort{
                1,
                2,
            },
            [2]c_ushort{
                2,
                2,
            },
            [2]c_ushort{
                6,
                3,
            },
            [2]c_ushort{
                14,
                4,
            },
            [2]c_ushort{
                30,
                5,
            },
            [2]c_ushort{
                62,
                6,
            },
            [2]c_ushort{
                126,
                7,
            },
            [2]c_ushort{
                254,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 510))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1022))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2046))))),
                11,
            },
        } ++ [1][2]c_ushort{@import("std").mem.zeroes([2]c_ushort)} ** 244;
    };
    _ = &UVDC_HT;
    const YAC_HT = struct {
        const static: [256][2]c_ushort = [256][2]c_ushort{
            [2]c_ushort{
                10,
                4,
            },
            [2]c_ushort{
                0,
                2,
            },
            [2]c_ushort{
                1,
                2,
            },
            [2]c_ushort{
                4,
                3,
            },
            [2]c_ushort{
                11,
                4,
            },
            [2]c_ushort{
                26,
                5,
            },
            [2]c_ushort{
                120,
                7,
            },
            [2]c_ushort{
                248,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1014))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65410))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65411))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                12,
                4,
            },
            [2]c_ushort{
                27,
                5,
            },
            [2]c_ushort{
                121,
                7,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 502))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2038))))),
                11,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65412))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65413))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65414))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65415))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65416))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                28,
                5,
            },
            [2]c_ushort{
                249,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1015))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4084))))),
                12,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65417))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65418))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65419))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65420))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65421))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65422))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                58,
                6,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 503))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4085))))),
                12,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65423))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65424))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65425))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65426))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65427))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65428))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65429))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                59,
                6,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1016))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65430))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65431))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65432))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65433))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65434))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65435))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65436))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65437))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                122,
                7,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2039))))),
                11,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65438))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65439))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65440))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65441))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65442))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65443))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65444))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65445))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                123,
                7,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4086))))),
                12,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65446))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65447))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65448))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65449))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65450))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65451))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65452))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65453))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                250,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4087))))),
                12,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65454))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65455))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65456))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65457))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65458))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65459))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65460))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65461))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 504))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 32704))))),
                15,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65462))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65463))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65464))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65465))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65466))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65467))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65468))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65469))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 505))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65470))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65471))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65472))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65473))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65474))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65475))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65476))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65477))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65478))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 506))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65479))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65480))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65481))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65482))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65483))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65484))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65485))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65486))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65487))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1017))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65488))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65489))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65490))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65491))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65492))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65493))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65494))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65495))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65496))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1018))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65497))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65498))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65499))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65500))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65501))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65502))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65503))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65504))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65505))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2040))))),
                11,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65506))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65507))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65508))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65509))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65510))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65511))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65512))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65513))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65514))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65515))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65516))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65517))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65518))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65519))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65520))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65521))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65522))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65523))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65524))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2041))))),
                11,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65525))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65526))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65527))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65528))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65529))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65530))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65531))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65532))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65533))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65534))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
        };
    };
    _ = &YAC_HT;
    const UVAC_HT = struct {
        const static: [256][2]c_ushort = [256][2]c_ushort{
            [2]c_ushort{
                0,
                2,
            },
            [2]c_ushort{
                1,
                2,
            },
            [2]c_ushort{
                4,
                3,
            },
            [2]c_ushort{
                10,
                4,
            },
            [2]c_ushort{
                24,
                5,
            },
            [2]c_ushort{
                25,
                5,
            },
            [2]c_ushort{
                56,
                6,
            },
            [2]c_ushort{
                120,
                7,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 500))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1014))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4084))))),
                12,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                11,
                4,
            },
            [2]c_ushort{
                57,
                6,
            },
            [2]c_ushort{
                246,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 501))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2038))))),
                11,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4085))))),
                12,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65416))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65417))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65418))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65419))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                26,
                5,
            },
            [2]c_ushort{
                247,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1015))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4086))))),
                12,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 32706))))),
                15,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65420))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65421))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65422))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65423))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65424))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                27,
                5,
            },
            [2]c_ushort{
                248,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1016))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 4087))))),
                12,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65425))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65426))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65427))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65428))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65429))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65430))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                58,
                6,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 502))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65431))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65432))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65433))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65434))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65435))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65436))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65437))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65438))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                59,
                6,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1017))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65439))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65440))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65441))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65442))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65443))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65444))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65445))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65446))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                121,
                7,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2039))))),
                11,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65447))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65448))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65449))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65450))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65451))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65452))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65453))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65454))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                122,
                7,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2040))))),
                11,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65455))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65456))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65457))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65458))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65459))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65460))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65461))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65462))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                249,
                8,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65463))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65464))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65465))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65466))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65467))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65468))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65469))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65470))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65471))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 503))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65472))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65473))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65474))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65475))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65476))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65477))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65478))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65479))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65480))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 504))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65481))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65482))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65483))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65484))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65485))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65486))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65487))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65488))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65489))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 505))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65490))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65491))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65492))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65493))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65494))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65495))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65496))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65497))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65498))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 506))))),
                9,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65499))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65500))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65501))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65502))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65503))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65504))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65505))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65506))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65507))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 2041))))),
                11,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65508))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65509))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65510))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65511))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65512))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65513))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65514))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65515))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65516))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 16352))))),
                14,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65517))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65518))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65519))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65520))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65521))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65522))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65523))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65524))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65525))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1018))))),
                10,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 32707))))),
                15,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65526))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65527))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65528))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65529))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65530))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65531))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65532))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65533))))),
                16,
            },
            [2]c_ushort{
                @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 65534))))),
                16,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
            [2]c_ushort{
                0,
                0,
            },
        };
    };
    _ = &UVAC_HT;
    const YQT = struct {
        const static: [64]c_int = [64]c_int{
            16,
            11,
            10,
            16,
            24,
            40,
            51,
            61,
            12,
            12,
            14,
            19,
            26,
            58,
            60,
            55,
            14,
            13,
            16,
            24,
            40,
            57,
            69,
            56,
            14,
            17,
            22,
            29,
            51,
            87,
            80,
            62,
            18,
            22,
            37,
            56,
            68,
            109,
            103,
            77,
            24,
            35,
            55,
            64,
            81,
            104,
            113,
            92,
            49,
            64,
            78,
            87,
            103,
            121,
            120,
            101,
            72,
            92,
            95,
            98,
            112,
            100,
            103,
            99,
        };
    };
    _ = &YQT;
    const UVQT = struct {
        const static: [64]c_int = [64]c_int{
            17,
            18,
            24,
            47,
            99,
            99,
            99,
            99,
            18,
            21,
            26,
            66,
            99,
            99,
            99,
            99,
            24,
            26,
            56,
            99,
            99,
            99,
            99,
            99,
            47,
            66,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
            99,
        };
    };
    _ = &UVQT;
    const aasf = struct {
        const static: [8]f32 = [8]f32{
            1.0 * 2.8284270763397217,
            1.3870398998260498 * 2.8284270763397217,
            1.3065630197525024 * 2.8284270763397217,
            1.1758755445480347 * 2.8284270763397217,
            1.0 * 2.8284270763397217,
            0.78569495677948 * 2.8284270763397217,
            0.5411961078643799 * 2.8284270763397217,
            0.27589938044548035 * 2.8284270763397217,
        };
    };
    _ = &aasf;
    var row: c_int = undefined;
    _ = &row;
    var col: c_int = undefined;
    _ = &col;
    var i: c_int = undefined;
    _ = &i;
    var k: c_int = undefined;
    _ = &k;
    var subsample: c_int = undefined;
    _ = &subsample;
    var fdtbl_Y: [64]f32 = undefined;
    _ = &fdtbl_Y;
    var fdtbl_UV: [64]f32 = undefined;
    _ = &fdtbl_UV;
    var YTable: [64]u8 = undefined;
    _ = &YTable;
    var UVTable: [64]u8 = undefined;
    _ = &UVTable;
    if ((((!(data != null) or !(width != 0)) or !(height != 0)) or (comp > @as(c_int, 4))) or (comp < @as(c_int, 1))) {
        return 0;
    }
    quality = if (quality != 0) quality else @as(c_int, 90);
    subsample = if (quality <= @as(c_int, 90)) @as(c_int, 1) else @as(c_int, 0);
    quality = if (quality < @as(c_int, 1)) @as(c_int, 1) else if (quality > @as(c_int, 100)) @as(c_int, 100) else quality;
    quality = if (quality < @as(c_int, 50)) @divTrunc(@as(c_int, 5000), quality) else @as(c_int, 200) - (quality * @as(c_int, 2));
    {
        i = 0;
        while (i < @as(c_int, 64)) : (i += 1) {
            var uvti: c_int = undefined;
            _ = &uvti;
            var yti: c_int = @divTrunc((YQT.static[@as(c_uint, @intCast(i))] * quality) + @as(c_int, 50), @as(c_int, 100));
            _ = &yti;
            YTable[stbiw__jpg_ZigZag[@as(c_uint, @intCast(i))]] = @as(u8, @bitCast(@as(i8, @truncate(if (yti < @as(c_int, 1)) @as(c_int, 1) else if (yti > @as(c_int, 255)) @as(c_int, 255) else yti))));
            uvti = @divTrunc((UVQT.static[@as(c_uint, @intCast(i))] * quality) + @as(c_int, 50), @as(c_int, 100));
            UVTable[stbiw__jpg_ZigZag[@as(c_uint, @intCast(i))]] = @as(u8, @bitCast(@as(i8, @truncate(if (uvti < @as(c_int, 1)) @as(c_int, 1) else if (uvti > @as(c_int, 255)) @as(c_int, 255) else uvti))));
        }
    }
    {
        _ = blk: {
            row = 0;
            break :blk blk_1: {
                const tmp = @as(c_int, 0);
                k = tmp;
                break :blk_1 tmp;
            };
        };
        while (row < @as(c_int, 8)) : (row += 1) {
            {
                col = 0;
                while (col < @as(c_int, 8)) : (_ = blk: {
                    col += 1;
                    break :blk blk_1: {
                        const ref = &k;
                        ref.* += 1;
                        break :blk_1 ref.*;
                    };
                }) {
                    fdtbl_Y[@as(c_uint, @intCast(k))] = @as(f32, @floatFromInt(@as(c_int, 1))) / ((@as(f32, @floatFromInt(@as(c_int, @bitCast(@as(c_uint, YTable[stbiw__jpg_ZigZag[@as(c_uint, @intCast(k))]]))))) * aasf.static[@as(c_uint, @intCast(row))]) * aasf.static[@as(c_uint, @intCast(col))]);
                    fdtbl_UV[@as(c_uint, @intCast(k))] = @as(f32, @floatFromInt(@as(c_int, 1))) / ((@as(f32, @floatFromInt(@as(c_int, @bitCast(@as(c_uint, UVTable[stbiw__jpg_ZigZag[@as(c_uint, @intCast(k))]]))))) * aasf.static[@as(c_uint, @intCast(row))]) * aasf.static[@as(c_uint, @intCast(col))]);
                }
            }
        }
    }
    {
        const head0 = struct {
            const static: [25]u8 = [25]u8{
                255,
                216,
                255,
                224,
                0,
                16,
                'J',
                'F',
                'I',
                'F',
                0,
                1,
                1,
                0,
                0,
                1,
                0,
                1,
                0,
                0,
                255,
                219,
                0,
                132,
                0,
            };
        };
        _ = &head0;
        const head2 = struct {
            const static: [14]u8 = [14]u8{
                255,
                218,
                0,
                12,
                3,
                1,
                0,
                2,
                17,
                3,
                17,
                0,
                63,
                0,
            };
        };
        _ = &head2;
        const head1: [24]u8 = [24]u8{
            255,
            192,
            0,
            17,
            8,
            @as(u8, @bitCast(@as(i8, @truncate(height >> @intCast(8))))),
            @as(u8, @bitCast(@as(i8, @truncate(height & @as(c_int, 255))))),
            @as(u8, @bitCast(@as(i8, @truncate(width >> @intCast(8))))),
            @as(u8, @bitCast(@as(i8, @truncate(width & @as(c_int, 255))))),
            3,
            1,
            @as(u8, @bitCast(@as(i8, @truncate(if (subsample != 0) @as(c_int, 34) else @as(c_int, 17))))),
            0,
            2,
            17,
            1,
            3,
            17,
            1,
            255,
            196,
            1,
            162,
            0,
        };
        _ = &head1;
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&head0.static[@as(usize, @intCast(0))]))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([25]u8))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&YTable[@as(usize, @intCast(0))]))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([64]u8))))));
        stbiw__putc(s, @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 1))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&UVTable[@as(usize, @intCast(0))]))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([64]u8))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&head1[@as(usize, @intCast(0))]))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([24]u8))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&std_dc_luminance_nrcodes.static[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([17]u8) -% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&std_dc_luminance_values.static[@as(usize, @intCast(0))]))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([12]u8))))));
        stbiw__putc(s, @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 16))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&std_ac_luminance_nrcodes.static[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([17]u8) -% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&std_ac_luminance_values.static[@as(usize, @intCast(0))]))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([162]u8))))));
        stbiw__putc(s, @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 1))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&std_dc_chrominance_nrcodes.static[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([17]u8) -% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&std_dc_chrominance_values.static[@as(usize, @intCast(0))]))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([12]u8))))));
        stbiw__putc(s, @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 17))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&std_ac_chrominance_nrcodes.static[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([17]u8) -% @as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&std_ac_chrominance_values.static[@as(usize, @intCast(0))]))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([162]u8))))));
        s.*.func.?(s.*.context, @as(?*anyopaque, @ptrCast(@constCast(@volatileCast(@as([*c]const u8, @ptrCast(@alignCast(&head2.static[@as(usize, @intCast(0))]))))))), @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf([14]u8))))));
    }
    {
        const fillBits = struct {
            const static: [2]c_ushort = [2]c_ushort{
                127,
                7,
            };
        };
        _ = &fillBits;
        var DCY: c_int = 0;
        _ = &DCY;
        var DCU: c_int = 0;
        _ = &DCU;
        var DCV: c_int = 0;
        _ = &DCV;
        var bitBuf: c_int = 0;
        _ = &bitBuf;
        var bitCnt: c_int = 0;
        _ = &bitCnt;
        var ofsG: c_int = if (comp > @as(c_int, 2)) @as(c_int, 1) else @as(c_int, 0);
        _ = &ofsG;
        var ofsB: c_int = if (comp > @as(c_int, 2)) @as(c_int, 2) else @as(c_int, 0);
        _ = &ofsB;
        var dataR: [*c]const u8 = @as([*c]const u8, @ptrCast(@alignCast(data)));
        _ = &dataR;
        var dataG: [*c]const u8 = dataR + @as(usize, @bitCast(@as(isize, @intCast(ofsG))));
        _ = &dataG;
        var dataB: [*c]const u8 = dataR + @as(usize, @bitCast(@as(isize, @intCast(ofsB))));
        _ = &dataB;
        var x: c_int = undefined;
        _ = &x;
        var y: c_int = undefined;
        _ = &y;
        var pos: c_int = undefined;
        _ = &pos;
        if (subsample != 0) {
            {
                y = 0;
                while (y < height) : (y += @as(c_int, 16)) {
                    {
                        x = 0;
                        while (x < width) : (x += @as(c_int, 16)) {
                            var Y: [256]f32 = undefined;
                            _ = &Y;
                            var U: [256]f32 = undefined;
                            _ = &U;
                            var V: [256]f32 = undefined;
                            _ = &V;
                            {
                                _ = blk: {
                                    row = y;
                                    break :blk blk_1: {
                                        const tmp = @as(c_int, 0);
                                        pos = tmp;
                                        break :blk_1 tmp;
                                    };
                                };
                                while (row < (y + @as(c_int, 16))) : (row += 1) {
                                    var clamped_row: c_int = if (row < height) row else height - @as(c_int, 1);
                                    _ = &clamped_row;
                                    var base_p: c_int = ((if (stbi__flip_vertically_on_write != 0) (height - @as(c_int, 1)) - clamped_row else clamped_row) * width) * comp;
                                    _ = &base_p;
                                    {
                                        col = x;
                                        while (col < (x + @as(c_int, 16))) : (_ = blk: {
                                            col += 1;
                                            break :blk blk_1: {
                                                const ref = &pos;
                                                ref.* += 1;
                                                break :blk_1 ref.*;
                                            };
                                        }) {
                                            var p: c_int = base_p + ((if (col < width) col else width - @as(c_int, 1)) * comp);
                                            _ = &p;
                                            var r: f32 = @as(f32, @floatFromInt((blk: {
                                                const tmp = p;
                                                if (tmp >= 0) break :blk dataR + @as(usize, @intCast(tmp)) else break :blk dataR - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                            }).*));
                                            _ = &r;
                                            var g: f32 = @as(f32, @floatFromInt((blk: {
                                                const tmp = p;
                                                if (tmp >= 0) break :blk dataG + @as(usize, @intCast(tmp)) else break :blk dataG - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                            }).*));
                                            _ = &g;
                                            var b: f32 = @as(f32, @floatFromInt((blk: {
                                                const tmp = p;
                                                if (tmp >= 0) break :blk dataB + @as(usize, @intCast(tmp)) else break :blk dataB - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                            }).*));
                                            _ = &b;
                                            Y[@as(c_uint, @intCast(pos))] = (((0.29899999499320984 * r) + (0.5870000123977661 * g)) + (0.11400000005960464 * b)) - @as(f32, @floatFromInt(@as(c_int, 128)));
                                            U[@as(c_uint, @intCast(pos))] = ((-0.16874000430107117 * r) - (0.33125999569892883 * g)) + (0.5 * b);
                                            V[@as(c_uint, @intCast(pos))] = ((0.5 * r) - (0.4186899960041046 * g)) - (0.08130999654531479 * b);
                                        }
                                    }
                                }
                            }
                            DCY = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&Y[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 0))))), @as(c_int, 16), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_Y[@as(usize, @intCast(0))]))), DCY, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YAC_HT.static[@as(usize, @intCast(0))]))));
                            DCY = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&Y[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 8))))), @as(c_int, 16), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_Y[@as(usize, @intCast(0))]))), DCY, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YAC_HT.static[@as(usize, @intCast(0))]))));
                            DCY = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&Y[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 128))))), @as(c_int, 16), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_Y[@as(usize, @intCast(0))]))), DCY, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YAC_HT.static[@as(usize, @intCast(0))]))));
                            DCY = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&Y[@as(usize, @intCast(0))]))) + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 136))))), @as(c_int, 16), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_Y[@as(usize, @intCast(0))]))), DCY, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YAC_HT.static[@as(usize, @intCast(0))]))));
                            {
                                var subU: [64]f32 = undefined;
                                _ = &subU;
                                var subV: [64]f32 = undefined;
                                _ = &subV;
                                var yy: c_int = undefined;
                                _ = &yy;
                                var xx: c_int = undefined;
                                _ = &xx;
                                {
                                    _ = blk: {
                                        yy = 0;
                                        break :blk blk_1: {
                                            const tmp = @as(c_int, 0);
                                            pos = tmp;
                                            break :blk_1 tmp;
                                        };
                                    };
                                    while (yy < @as(c_int, 8)) : (yy += 1) {
                                        {
                                            xx = 0;
                                            while (xx < @as(c_int, 8)) : (_ = blk: {
                                                xx += 1;
                                                break :blk blk_1: {
                                                    const ref = &pos;
                                                    ref.* += 1;
                                                    break :blk_1 ref.*;
                                                };
                                            }) {
                                                var j: c_int = (yy * @as(c_int, 32)) + (xx * @as(c_int, 2));
                                                _ = &j;
                                                subU[@as(c_uint, @intCast(pos))] = (((U[@as(c_uint, @intCast(j + @as(c_int, 0)))] + U[@as(c_uint, @intCast(j + @as(c_int, 1)))]) + U[@as(c_uint, @intCast(j + @as(c_int, 16)))]) + U[@as(c_uint, @intCast(j + @as(c_int, 17)))]) * 0.25;
                                                subV[@as(c_uint, @intCast(pos))] = (((V[@as(c_uint, @intCast(j + @as(c_int, 0)))] + V[@as(c_uint, @intCast(j + @as(c_int, 1)))]) + V[@as(c_uint, @intCast(j + @as(c_int, 16)))]) + V[@as(c_uint, @intCast(j + @as(c_int, 17)))]) * 0.25;
                                            }
                                        }
                                    }
                                }
                                DCU = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&subU[@as(usize, @intCast(0))]))), @as(c_int, 8), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_UV[@as(usize, @intCast(0))]))), DCU, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&UVDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&UVAC_HT.static[@as(usize, @intCast(0))]))));
                                DCV = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&subV[@as(usize, @intCast(0))]))), @as(c_int, 8), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_UV[@as(usize, @intCast(0))]))), DCV, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&UVDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&UVAC_HT.static[@as(usize, @intCast(0))]))));
                            }
                        }
                    }
                }
            }
        } else {
            {
                y = 0;
                while (y < height) : (y += @as(c_int, 8)) {
                    {
                        x = 0;
                        while (x < width) : (x += @as(c_int, 8)) {
                            var Y: [64]f32 = undefined;
                            _ = &Y;
                            var U: [64]f32 = undefined;
                            _ = &U;
                            var V: [64]f32 = undefined;
                            _ = &V;
                            {
                                _ = blk: {
                                    row = y;
                                    break :blk blk_1: {
                                        const tmp = @as(c_int, 0);
                                        pos = tmp;
                                        break :blk_1 tmp;
                                    };
                                };
                                while (row < (y + @as(c_int, 8))) : (row += 1) {
                                    var clamped_row: c_int = if (row < height) row else height - @as(c_int, 1);
                                    _ = &clamped_row;
                                    var base_p: c_int = ((if (stbi__flip_vertically_on_write != 0) (height - @as(c_int, 1)) - clamped_row else clamped_row) * width) * comp;
                                    _ = &base_p;
                                    {
                                        col = x;
                                        while (col < (x + @as(c_int, 8))) : (_ = blk: {
                                            col += 1;
                                            break :blk blk_1: {
                                                const ref = &pos;
                                                ref.* += 1;
                                                break :blk_1 ref.*;
                                            };
                                        }) {
                                            var p: c_int = base_p + ((if (col < width) col else width - @as(c_int, 1)) * comp);
                                            _ = &p;
                                            var r: f32 = @as(f32, @floatFromInt((blk: {
                                                const tmp = p;
                                                if (tmp >= 0) break :blk dataR + @as(usize, @intCast(tmp)) else break :blk dataR - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                            }).*));
                                            _ = &r;
                                            var g: f32 = @as(f32, @floatFromInt((blk: {
                                                const tmp = p;
                                                if (tmp >= 0) break :blk dataG + @as(usize, @intCast(tmp)) else break :blk dataG - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                            }).*));
                                            _ = &g;
                                            var b: f32 = @as(f32, @floatFromInt((blk: {
                                                const tmp = p;
                                                if (tmp >= 0) break :blk dataB + @as(usize, @intCast(tmp)) else break :blk dataB - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                                            }).*));
                                            _ = &b;
                                            Y[@as(c_uint, @intCast(pos))] = (((0.29899999499320984 * r) + (0.5870000123977661 * g)) + (0.11400000005960464 * b)) - @as(f32, @floatFromInt(@as(c_int, 128)));
                                            U[@as(c_uint, @intCast(pos))] = ((-0.16874000430107117 * r) - (0.33125999569892883 * g)) + (0.5 * b);
                                            V[@as(c_uint, @intCast(pos))] = ((0.5 * r) - (0.4186899960041046 * g)) - (0.08130999654531479 * b);
                                        }
                                    }
                                }
                            }
                            DCY = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&Y[@as(usize, @intCast(0))]))), @as(c_int, 8), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_Y[@as(usize, @intCast(0))]))), DCY, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&YAC_HT.static[@as(usize, @intCast(0))]))));
                            DCU = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&U[@as(usize, @intCast(0))]))), @as(c_int, 8), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_UV[@as(usize, @intCast(0))]))), DCU, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&UVDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&UVAC_HT.static[@as(usize, @intCast(0))]))));
                            DCV = stbiw__jpg_processDU(s, &bitBuf, &bitCnt, @as([*c]f32, @ptrCast(@alignCast(&V[@as(usize, @intCast(0))]))), @as(c_int, 8), @as([*c]f32, @ptrCast(@alignCast(&fdtbl_UV[@as(usize, @intCast(0))]))), DCV, @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&UVDC_HT.static[@as(usize, @intCast(0))]))), @as([*c]const [2]c_ushort, @ptrCast(@alignCast(&UVAC_HT.static[@as(usize, @intCast(0))]))));
                        }
                    }
                }
            }
        }
        stbiw__jpg_writeBits(s, &bitBuf, &bitCnt, @as([*c]const c_ushort, @ptrCast(@alignCast(&fillBits.static[@as(usize, @intCast(0))]))));
    }
    stbiw__putc(s, @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 255))))));
    stbiw__putc(s, @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 217))))));
    return 1;
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
pub const __INT_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __LONG_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __WCHAR_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __WCHAR_WIDTH__ = @as(c_int, 32);
pub const __WINT_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __WINT_WIDTH__ = @as(c_int, 32);
pub const __INTMAX_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTMAX_WIDTH__ = @as(c_int, 64);
pub const __SIZE_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __SIZE_WIDTH__ = @as(c_int, 64);
pub const __UINTMAX_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTMAX_WIDTH__ = @as(c_int, 64);
pub const __PTRDIFF_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __PTRDIFF_WIDTH__ = @as(c_int, 64);
pub const __INTPTR_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTPTR_WIDTH__ = @as(c_int, 64);
pub const __UINTPTR_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
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
pub const __INTMAX_C = @import("std").zig.c_translation.Macros.L_SUFFIX;
pub const __UINTMAX_TYPE__ = c_ulong;
pub const __UINTMAX_FMTo__ = "lo";
pub const __UINTMAX_FMTu__ = "lu";
pub const __UINTMAX_FMTx__ = "lx";
pub const __UINTMAX_FMTX__ = "lX";
pub const __UINTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`");
// (no file):102:9
pub const __UINTMAX_C = @import("std").zig.c_translation.Macros.UL_SUFFIX;
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
pub const __SIG_ATOMIC_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
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
pub const __INT64_C = @import("std").zig.c_translation.Macros.L_SUFFIX;
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
pub const __UINT16_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __INT16_MAX__ = @as(c_int, 32767);
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `U`");
// (no file):234:9
pub const __UINT32_C = @import("std").zig.c_translation.Macros.U_SUFFIX;
pub const __UINT32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __INT32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __UINT64_TYPE__ = c_ulong;
pub const __UINT64_FMTo__ = "lo";
pub const __UINT64_FMTu__ = "lu";
pub const __UINT64_FMTx__ = "lx";
pub const __UINT64_FMTX__ = "lX";
pub const __UINT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`");
// (no file):243:9
pub const __UINT64_C = @import("std").zig.c_translation.Macros.UL_SUFFIX;
pub const __UINT64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __INT64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
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
pub const __UINT_LEAST16_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __UINT_LEAST16_FMTo__ = "ho";
pub const __UINT_LEAST16_FMTu__ = "hu";
pub const __UINT_LEAST16_FMTx__ = "hx";
pub const __UINT_LEAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_LEAST32_WIDTH__ = @as(c_int, 32);
pub const __INT_LEAST32_FMTd__ = "d";
pub const __INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __UINT_LEAST32_FMTo__ = "o";
pub const __UINT_LEAST32_FMTu__ = "u";
pub const __UINT_LEAST32_FMTx__ = "x";
pub const __UINT_LEAST32_FMTX__ = "X";
pub const __INT_LEAST64_TYPE__ = c_long;
pub const __INT_LEAST64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST64_WIDTH__ = @as(c_int, 64);
pub const __INT_LEAST64_FMTd__ = "ld";
pub const __INT_LEAST64_FMTi__ = "li";
pub const __UINT_LEAST64_TYPE__ = c_ulong;
pub const __UINT_LEAST64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
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
pub const __UINT_FAST16_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __UINT_FAST16_FMTo__ = "ho";
pub const __UINT_FAST16_FMTu__ = "hu";
pub const __UINT_FAST16_FMTx__ = "hx";
pub const __UINT_FAST16_FMTX__ = "hX";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_FAST32_WIDTH__ = @as(c_int, 32);
pub const __INT_FAST32_FMTd__ = "d";
pub const __INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __UINT_FAST32_FMTo__ = "o";
pub const __UINT_FAST32_FMTu__ = "u";
pub const __UINT_FAST32_FMTx__ = "x";
pub const __UINT_FAST32_FMTX__ = "X";
pub const __INT_FAST64_TYPE__ = c_long;
pub const __INT_FAST64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_FAST64_WIDTH__ = @as(c_int, 64);
pub const __INT_FAST64_FMTd__ = "ld";
pub const __INT_FAST64_FMTi__ = "li";
pub const __UINT_FAST64_TYPE__ = c_ulong;
pub const __UINT_FAST64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINT_FAST64_FMTo__ = "lo";
pub const __UINT_FAST64_FMTu__ = "lu";
pub const __UINT_FAST64_FMTx__ = "lx";
pub const __UINT_FAST64_FMTX__ = "lX";
pub const __USER_LABEL_PREFIX__ = "";
pub const __NO_MATH_ERRNO__ = @as(c_int, 1);
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
pub const __SSP_STRONG__ = @as(c_int, 2);
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
pub const __ARM_ACLE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 202420, .decimal);
pub const __FUNCTION_MULTI_VERSIONING_SUPPORT_LEVEL = @import("std").zig.c_translation.promoteIntLiteral(c_int, 202430, .decimal);
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
pub const STBI_ONLY_PNG = "";
pub const STBI_ONLY_JPEG = "";
pub const STBI_NO_FAILURE_STRINGS = "";
pub const STB_IMAGE_IMPLEMENTATION = "";
pub const STBI_INCLUDE_STB_IMAGE_H = "";
pub const _STDIO_H = "";
pub const _FEATURES_H = "";
pub const _BSD_SOURCE = @as(c_int, 1);
pub const _XOPEN_SOURCE = @as(c_int, 700);
pub const __restrict = @compileError("unable to translate C expr: unexpected token 'restrict'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/features.h:20:9
pub const __inline = @compileError("unable to translate C expr: unexpected token 'inline'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/features.h:26:9
pub const __REDIR = @compileError("unable to translate C expr: unexpected token '__typeof__'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/features.h:38:9
pub const __NEED_FILE = "";
pub const __NEED___isoc_va_list = "";
pub const __NEED_size_t = "";
pub const __NEED_ssize_t = "";
pub const __NEED_off_t = "";
pub const __NEED_va_list = "";
pub const _Addr = c_long;
pub const _Int64 = c_long;
pub const _Reg = c_long;
pub const __BYTE_ORDER = @as(c_int, 1234);
pub const __LONG_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_long, 0x7fffffffffffffff, .hex);
pub const __LITTLE_ENDIAN = @as(c_int, 1234);
pub const __BIG_ENDIAN = @as(c_int, 4321);
pub const __USE_TIME_BITS64 = @as(c_int, 1);
pub const __DEFINED_size_t = "";
pub const __DEFINED_ssize_t = "";
pub const __DEFINED_off_t = "";
pub const __DEFINED_FILE = "";
pub const __DEFINED_va_list = "";
pub const __DEFINED___isoc_va_list = "";
pub const NULL = @import("std").zig.c_translation.cast(?*anyopaque, @as(c_int, 0));
pub const EOF = -@as(c_int, 1);
pub const SEEK_SET = @as(c_int, 0);
pub const SEEK_CUR = @as(c_int, 1);
pub const SEEK_END = @as(c_int, 2);
pub const _IOFBF = @as(c_int, 0);
pub const _IOLBF = @as(c_int, 1);
pub const _IONBF = @as(c_int, 2);
pub const BUFSIZ = @as(c_int, 1024);
pub const FILENAME_MAX = @as(c_int, 4096);
pub const FOPEN_MAX = @as(c_int, 1000);
pub const TMP_MAX = @as(c_int, 10000);
pub const L_tmpnam = @as(c_int, 20);
pub const L_ctermid = @as(c_int, 20);
pub const P_tmpdir = "/tmp";
pub const L_cuserid = @as(c_int, 20);
pub const STBI_VERSION = @as(c_int, 1);
pub const _STDLIB_H = "";
pub const __NEED_wchar_t = "";
pub const __DEFINED_wchar_t = "";
pub const EXIT_FAILURE = @as(c_int, 1);
pub const EXIT_SUCCESS = @as(c_int, 0);
pub const MB_CUR_MAX = __ctype_get_mb_cur_max();
pub const RAND_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const WNOHANG = @as(c_int, 1);
pub const WUNTRACED = @as(c_int, 2);
pub inline fn WEXITSTATUS(s: anytype) @TypeOf((s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8)) {
    _ = &s;
    return (s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8);
}
pub inline fn WTERMSIG(s: anytype) @TypeOf(s & @as(c_int, 0x7f)) {
    _ = &s;
    return s & @as(c_int, 0x7f);
}
pub inline fn WSTOPSIG(s: anytype) @TypeOf(WEXITSTATUS(s)) {
    _ = &s;
    return WEXITSTATUS(s);
}
pub inline fn WIFEXITED(s: anytype) @TypeOf(!(WTERMSIG(s) != 0)) {
    _ = &s;
    return !(WTERMSIG(s) != 0);
}
pub inline fn WIFSTOPPED(s: anytype) @TypeOf(@import("std").zig.c_translation.cast(c_short, ((s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) * @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x10001, .hex)) >> @as(c_int, 8)) > @as(c_int, 0x7f00)) {
    _ = &s;
    return @import("std").zig.c_translation.cast(c_short, ((s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) * @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x10001, .hex)) >> @as(c_int, 8)) > @as(c_int, 0x7f00);
}
pub inline fn WIFSIGNALED(s: anytype) @TypeOf(((s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) - @as(c_uint, 1)) < @as(c_uint, 0xff)) {
    _ = &s;
    return ((s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) - @as(c_uint, 1)) < @as(c_uint, 0xff);
}
pub const _ALLOCA_H = "";
pub inline fn WCOREDUMP(s: anytype) @TypeOf(s & @as(c_int, 0x80)) {
    _ = &s;
    return s & @as(c_int, 0x80);
}
pub inline fn WIFCONTINUED(s: anytype) @TypeOf(s == @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) {
    _ = &s;
    return s == @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex);
}
pub const STBIDEF = @compileError("unable to translate C expr: unexpected token 'extern'");
// /home/x/next/arcan/src/engine/external/stb_image.h:398:9
pub const STBI_NO_BMP = "";
pub const STBI_NO_PSD = "";
pub const STBI_NO_TGA = "";
pub const STBI_NO_GIF = "";
pub const STBI_NO_HDR = "";
pub const STBI_NO_PIC = "";
pub const STBI_NO_PNM = "";
pub const __need___va_list = "";
pub const __need_va_list = "";
pub const __need_va_arg = "";
pub const __need___va_copy = "";
pub const __need_va_copy = "";
pub const __STDARG_H = "";
pub const __GNUC_VA_LIST = "";
pub const _VA_LIST = "";
pub const va_start = @compileError("unable to translate macro: undefined identifier `__builtin_va_start`");
// /usr/local/zig-aarch64-linux-0.15.2/lib/include/__stdarg_va_arg.h:17:9
pub const va_end = @compileError("unable to translate macro: undefined identifier `__builtin_va_end`");
// /usr/local/zig-aarch64-linux-0.15.2/lib/include/__stdarg_va_arg.h:19:9
pub const va_arg = @compileError("unable to translate C expr: unexpected token 'an identifier'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/include/__stdarg_va_arg.h:20:9
pub const __va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`");
// /usr/local/zig-aarch64-linux-0.15.2/lib/include/__stdarg___va_copy.h:11:9
pub const va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`");
// /usr/local/zig-aarch64-linux-0.15.2/lib/include/__stdarg_va_copy.h:11:9
pub const __need_ptrdiff_t = "";
pub const __need_size_t = "";
pub const __need_wchar_t = "";
pub const __need_NULL = "";
pub const __need_max_align_t = "";
pub const __need_offsetof = "";
pub const __STDDEF_H = "";
pub const _PTRDIFF_T = "";
pub const _SIZE_T = "";
pub const _WCHAR_T = "";
pub const __CLANG_MAX_ALIGN_T_DEFINED = "";
pub const offsetof = @compileError("unable to translate C expr: unexpected token 'an identifier'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/include/__stddef_offsetof.h:16:9
pub const _STRING_H = "";
pub const __NEED_locale_t = "";
pub const __DEFINED_locale_t = "";
pub const _STRINGS_H = "";
pub const __CLANG_LIMITS_H = "";
pub const _GCC_LIMITS_H_ = "";
pub const _LIMITS_H = "";
pub const CHAR_MIN = @as(c_int, 0);
pub const CHAR_MAX = @as(c_int, 255);
pub const CHAR_BIT = @as(c_int, 8);
pub const SCHAR_MIN = -@as(c_int, 128);
pub const SCHAR_MAX = @as(c_int, 127);
pub const UCHAR_MAX = @as(c_int, 255);
pub const SHRT_MIN = -@as(c_int, 1) - @as(c_int, 0x7fff);
pub const SHRT_MAX = @as(c_int, 0x7fff);
pub const USHRT_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex);
pub const INT_MIN = -@as(c_int, 1) - @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const INT_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const UINT_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0xffffffff, .hex);
pub const LONG_MIN = -LONG_MAX - @as(c_int, 1);
pub const LONG_MAX = __LONG_MAX;
pub const ULONG_MAX = (@as(c_ulong, 2) * LONG_MAX) + @as(c_int, 1);
pub const LLONG_MIN = -LLONG_MAX - @as(c_int, 1);
pub const LLONG_MAX = @as(c_longlong, 0x7fffffffffffffff);
pub const ULLONG_MAX = (@as(c_ulonglong, 2) * LLONG_MAX) + @as(c_int, 1);
pub const MB_LEN_MAX = @as(c_int, 4);
pub const PIPE_BUF = @as(c_int, 4096);
pub const FILESIZEBITS = @as(c_int, 64);
pub const NAME_MAX = @as(c_int, 255);
pub const PATH_MAX = @as(c_int, 4096);
pub const NGROUPS_MAX = @as(c_int, 32);
pub const ARG_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 131072, .decimal);
pub const IOV_MAX = @as(c_int, 1024);
pub const SYMLOOP_MAX = @as(c_int, 40);
pub const WORD_BIT = @as(c_int, 32);
pub const SSIZE_MAX = LONG_MAX;
pub const TZNAME_MAX = @as(c_int, 6);
pub const TTY_NAME_MAX = @as(c_int, 32);
pub const HOST_NAME_MAX = @as(c_int, 255);
pub const LONG_BIT = @as(c_int, 64);
pub const PTHREAD_KEYS_MAX = @as(c_int, 128);
pub const PTHREAD_STACK_MIN = @as(c_int, 2048);
pub const PTHREAD_DESTRUCTOR_ITERATIONS = @as(c_int, 4);
pub const SEM_VALUE_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const SEM_NSEMS_MAX = @as(c_int, 256);
pub const DELAYTIMER_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const MQ_PRIO_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 32768, .decimal);
pub const LOGIN_NAME_MAX = @as(c_int, 256);
pub const BC_BASE_MAX = @as(c_int, 99);
pub const BC_DIM_MAX = @as(c_int, 2048);
pub const BC_SCALE_MAX = @as(c_int, 99);
pub const BC_STRING_MAX = @as(c_int, 1000);
pub const CHARCLASS_NAME_MAX = @as(c_int, 14);
pub const COLL_WEIGHTS_MAX = @as(c_int, 2);
pub const EXPR_NEST_MAX = @as(c_int, 32);
pub const LINE_MAX = @as(c_int, 4096);
pub const RE_DUP_MAX = @as(c_int, 255);
pub const NL_ARGMAX = @as(c_int, 9);
pub const NL_MSGMAX = @as(c_int, 32767);
pub const NL_SETMAX = @as(c_int, 255);
pub const NL_TEXTMAX = @as(c_int, 2048);
pub const NZERO = @as(c_int, 20);
pub const NL_LANGMAX = @as(c_int, 32);
pub const NL_NMAX = @as(c_int, 16);
pub const _POSIX_AIO_LISTIO_MAX = @as(c_int, 2);
pub const _POSIX_AIO_MAX = @as(c_int, 1);
pub const _POSIX_ARG_MAX = @as(c_int, 4096);
pub const _POSIX_CHILD_MAX = @as(c_int, 25);
pub const _POSIX_CLOCKRES_MIN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 20000000, .decimal);
pub const _POSIX_DELAYTIMER_MAX = @as(c_int, 32);
pub const _POSIX_HOST_NAME_MAX = @as(c_int, 255);
pub const _POSIX_LINK_MAX = @as(c_int, 8);
pub const _POSIX_LOGIN_NAME_MAX = @as(c_int, 9);
pub const _POSIX_MAX_CANON = @as(c_int, 255);
pub const _POSIX_MAX_INPUT = @as(c_int, 255);
pub const _POSIX_MQ_OPEN_MAX = @as(c_int, 8);
pub const _POSIX_MQ_PRIO_MAX = @as(c_int, 32);
pub const _POSIX_NAME_MAX = @as(c_int, 14);
pub const _POSIX_NGROUPS_MAX = @as(c_int, 8);
pub const _POSIX_OPEN_MAX = @as(c_int, 20);
pub const _POSIX_PATH_MAX = @as(c_int, 256);
pub const _POSIX_PIPE_BUF = @as(c_int, 512);
pub const _POSIX_RE_DUP_MAX = @as(c_int, 255);
pub const _POSIX_RTSIG_MAX = @as(c_int, 8);
pub const _POSIX_SEM_NSEMS_MAX = @as(c_int, 256);
pub const _POSIX_SEM_VALUE_MAX = @as(c_int, 32767);
pub const _POSIX_SIGQUEUE_MAX = @as(c_int, 32);
pub const _POSIX_SSIZE_MAX = @as(c_int, 32767);
pub const _POSIX_STREAM_MAX = @as(c_int, 8);
pub const _POSIX_SS_REPL_MAX = @as(c_int, 4);
pub const _POSIX_SYMLINK_MAX = @as(c_int, 255);
pub const _POSIX_SYMLOOP_MAX = @as(c_int, 8);
pub const _POSIX_THREAD_DESTRUCTOR_ITERATIONS = @as(c_int, 4);
pub const _POSIX_THREAD_KEYS_MAX = @as(c_int, 128);
pub const _POSIX_THREAD_THREADS_MAX = @as(c_int, 64);
pub const _POSIX_TIMER_MAX = @as(c_int, 32);
pub const _POSIX_TRACE_EVENT_NAME_MAX = @as(c_int, 30);
pub const _POSIX_TRACE_NAME_MAX = @as(c_int, 8);
pub const _POSIX_TRACE_SYS_MAX = @as(c_int, 8);
pub const _POSIX_TRACE_USER_EVENT_MAX = @as(c_int, 32);
pub const _POSIX_TTY_NAME_MAX = @as(c_int, 9);
pub const _POSIX_TZNAME_MAX = @as(c_int, 6);
pub const _POSIX2_BC_BASE_MAX = @as(c_int, 99);
pub const _POSIX2_BC_DIM_MAX = @as(c_int, 2048);
pub const _POSIX2_BC_SCALE_MAX = @as(c_int, 99);
pub const _POSIX2_BC_STRING_MAX = @as(c_int, 1000);
pub const _POSIX2_CHARCLASS_NAME_MAX = @as(c_int, 14);
pub const _POSIX2_COLL_WEIGHTS_MAX = @as(c_int, 2);
pub const _POSIX2_EXPR_NEST_MAX = @as(c_int, 32);
pub const _POSIX2_LINE_MAX = @as(c_int, 2048);
pub const _POSIX2_RE_DUP_MAX = @as(c_int, 255);
pub const _XOPEN_IOV_MAX = @as(c_int, 16);
pub const _XOPEN_NAME_MAX = @as(c_int, 255);
pub const _XOPEN_PATH_MAX = @as(c_int, 1024);
pub const LONG_LONG_MAX = __LONG_LONG_MAX__;
pub const LONG_LONG_MIN = -__LONG_LONG_MAX__ - @as(c_longlong, 1);
pub const ULONG_LONG_MAX = (__LONG_LONG_MAX__ * @as(c_ulonglong, 2)) + @as(c_ulonglong, 1);
pub const _MATH_H = "";
pub const __NEED_float_t = "";
pub const __NEED_double_t = "";
pub const __DEFINED_float_t = "";
pub const __DEFINED_double_t = "";
pub const NAN = __builtin_nanf("");
pub const INFINITY = __builtin_inff();
pub const HUGE_VALF = INFINITY;
pub const HUGE_VAL = @import("std").zig.c_translation.cast(f64, INFINITY);
pub const HUGE_VALL = @compileError("unable to translate: TODO long double");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/math.h:24:9
pub const MATH_ERRNO = @as(c_int, 1);
pub const MATH_ERREXCEPT = @as(c_int, 2);
pub const math_errhandling = @as(c_int, 2);
pub const FP_ILOGBNAN = -@as(c_int, 1) - @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const FP_ILOGB0 = FP_ILOGBNAN;
pub const FP_NAN = @as(c_int, 0);
pub const FP_INFINITE = @as(c_int, 1);
pub const FP_ZERO = @as(c_int, 2);
pub const FP_SUBNORMAL = @as(c_int, 3);
pub const FP_NORMAL = @as(c_int, 4);
pub const FP_FAST_FMA = @as(c_int, 1);
pub const FP_FAST_FMAF = @as(c_int, 1);
pub inline fn fpclassify(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) __fpclassifyf(x) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) __fpclassify(x) else __fpclassifyl(x)) {
    _ = &x;
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) __fpclassifyf(x) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) __fpclassify(x) else __fpclassifyl(x);
}
pub inline fn isinf(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex)) == @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hex) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) == (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) == FP_INFINITE) {
    _ = &x;
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex)) == @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hex) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) == (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) == FP_INFINITE;
}
pub inline fn isnan(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex)) > @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hex) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) > (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) == FP_NAN) {
    _ = &x;
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex)) > @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hex) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) > (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) == FP_NAN;
}
pub inline fn isnormal(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) ((__FLOAT_BITS(x) + @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x00800000, .hex)) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex)) >= @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x01000000, .hex) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) ((__DOUBLE_BITS(x) + (@as(c_ulonglong, 1) << @as(c_int, 52))) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) >= (@as(c_ulonglong, 1) << @as(c_int, 53)) else __fpclassifyl(x) == FP_NORMAL) {
    _ = &x;
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) ((__FLOAT_BITS(x) + @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x00800000, .hex)) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex)) >= @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x01000000, .hex) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) ((__DOUBLE_BITS(x) + (@as(c_ulonglong, 1) << @as(c_int, 52))) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) >= (@as(c_ulonglong, 1) << @as(c_int, 53)) else __fpclassifyl(x) == FP_NORMAL;
}
pub inline fn isfinite(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex)) < @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hex) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) < (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) > FP_INFINITE) {
    _ = &x;
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex)) < @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hex) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) < (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) > FP_INFINITE;
}
pub inline fn signbit(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) @import("std").zig.c_translation.cast(c_int, __FLOAT_BITS(x) >> @as(c_int, 31)) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) @import("std").zig.c_translation.cast(c_int, __DOUBLE_BITS(x) >> @as(c_int, 63)) else __signbitl(x)) {
    _ = &x;
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) @import("std").zig.c_translation.cast(c_int, __FLOAT_BITS(x) >> @as(c_int, 31)) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) @import("std").zig.c_translation.cast(c_int, __DOUBLE_BITS(x) >> @as(c_int, 63)) else __signbitl(x);
}
pub inline fn isunordered(x: anytype, y: anytype) @TypeOf(if (isnan(x) != 0)
blk_2: {
    _ = @import("std").zig.c_translation.cast(anyopaque, y);
    break :blk_2 @as(c_int, 1);
} else isnan(y)) {
    _ = &x;
    _ = &y;
    return if (isnan(x) != 0) blk_2: {
        _ = @import("std").zig.c_translation.cast(anyopaque, y);
        break :blk_2 @as(c_int, 1);
    } else isnan(y);
}
pub const __ISREL_DEF = @compileError("unable to translate macro: undefined identifier `__is`");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/math.h:104:9
pub const __tg_pred_2 = @compileError("unable to translate macro: undefined identifier `f`");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/math.h:124:9
pub inline fn isless(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __isless)) {
    _ = &x;
    _ = &y;
    return __tg_pred_2(x, y, __isless);
}
pub inline fn islessequal(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __islessequal)) {
    _ = &x;
    _ = &y;
    return __tg_pred_2(x, y, __islessequal);
}
pub inline fn islessgreater(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __islessgreater)) {
    _ = &x;
    _ = &y;
    return __tg_pred_2(x, y, __islessgreater);
}
pub inline fn isgreater(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __isgreater)) {
    _ = &x;
    _ = &y;
    return __tg_pred_2(x, y, __isgreater);
}
pub inline fn isgreaterequal(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __isgreaterequal)) {
    _ = &x;
    _ = &y;
    return __tg_pred_2(x, y, __isgreaterequal);
}
pub const MAXFLOAT = @as(f32, 3.40282346638528859812e+38);
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
pub const HUGE = @as(f32, 3.40282346638528859812e+38);
pub const assert = @compileError("unable to translate macro: undefined identifier `__FILE__`");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/assert.h:8:9
pub const static_assert = @compileError("unable to translate C expr: unexpected token '_Static_assert'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/assert.h:12:9
pub inline fn STBI_ASSERT(x: anytype) @TypeOf(assert(x)) {
    _ = &x;
    return assert(x);
}
pub const STBI_EXTERN = @compileError("unable to translate C expr: unexpected token 'extern'");
// /home/x/next/arcan/src/engine/external/stb_image.h:609:9
pub const stbi_inline = "";
pub const STBI_THREAD_LOCAL = @compileError("unable to translate macro: undefined identifier `__thread`");
// /home/x/next/arcan/src/engine/external/stb_image.h:627:15
pub const __CLANG_STDINT_H = "";
pub const _STDINT_H = "";
pub const __NEED_int8_t = "";
pub const __NEED_int16_t = "";
pub const __NEED_int32_t = "";
pub const __NEED_int64_t = "";
pub const __NEED_uint8_t = "";
pub const __NEED_uint16_t = "";
pub const __NEED_uint32_t = "";
pub const __NEED_uint64_t = "";
pub const __NEED_intptr_t = "";
pub const __NEED_uintptr_t = "";
pub const __NEED_intmax_t = "";
pub const __NEED_uintmax_t = "";
pub const __DEFINED_uintptr_t = "";
pub const __DEFINED_intptr_t = "";
pub const __DEFINED_int8_t = "";
pub const __DEFINED_int16_t = "";
pub const __DEFINED_int32_t = "";
pub const __DEFINED_int64_t = "";
pub const __DEFINED_intmax_t = "";
pub const __DEFINED_uint8_t = "";
pub const __DEFINED_uint16_t = "";
pub const __DEFINED_uint32_t = "";
pub const __DEFINED_uint64_t = "";
pub const __DEFINED_uintmax_t = "";
pub const INT8_MIN = -@as(c_int, 1) - @as(c_int, 0x7f);
pub const INT16_MIN = -@as(c_int, 1) - @as(c_int, 0x7fff);
pub const INT32_MIN = -@as(c_int, 1) - @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const INT64_MIN = -@as(c_int, 1) - @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffffffffffff, .hex);
pub const INT8_MAX = @as(c_int, 0x7f);
pub const INT16_MAX = @as(c_int, 0x7fff);
pub const INT32_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const INT64_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffffffffffff, .hex);
pub const UINT8_MAX = @as(c_int, 0xff);
pub const UINT16_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex);
pub const UINT32_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0xffffffff, .hex);
pub const UINT64_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0xffffffffffffffff, .hex);
pub const INT_FAST8_MIN = INT8_MIN;
pub const INT_FAST64_MIN = INT64_MIN;
pub const INT_LEAST8_MIN = INT8_MIN;
pub const INT_LEAST16_MIN = INT16_MIN;
pub const INT_LEAST32_MIN = INT32_MIN;
pub const INT_LEAST64_MIN = INT64_MIN;
pub const INT_FAST8_MAX = INT8_MAX;
pub const INT_FAST64_MAX = INT64_MAX;
pub const INT_LEAST8_MAX = INT8_MAX;
pub const INT_LEAST16_MAX = INT16_MAX;
pub const INT_LEAST32_MAX = INT32_MAX;
pub const INT_LEAST64_MAX = INT64_MAX;
pub const UINT_FAST8_MAX = UINT8_MAX;
pub const UINT_FAST64_MAX = UINT64_MAX;
pub const UINT_LEAST8_MAX = UINT8_MAX;
pub const UINT_LEAST16_MAX = UINT16_MAX;
pub const UINT_LEAST32_MAX = UINT32_MAX;
pub const UINT_LEAST64_MAX = UINT64_MAX;
pub const INTMAX_MIN = INT64_MIN;
pub const INTMAX_MAX = INT64_MAX;
pub const UINTMAX_MAX = UINT64_MAX;
pub const WINT_MIN = @as(c_uint, 0);
pub const WINT_MAX = UINT32_MAX;
pub const WCHAR_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0xffffffff, .hex) + '\x00';
pub const WCHAR_MIN = @as(c_int, 0) + '\x00';
pub const SIG_ATOMIC_MIN = INT32_MIN;
pub const SIG_ATOMIC_MAX = INT32_MAX;
pub const INT_FAST16_MIN = INT32_MIN;
pub const INT_FAST32_MIN = INT32_MIN;
pub const INT_FAST16_MAX = INT32_MAX;
pub const INT_FAST32_MAX = INT32_MAX;
pub const UINT_FAST16_MAX = UINT32_MAX;
pub const UINT_FAST32_MAX = UINT32_MAX;
pub const INTPTR_MIN = INT64_MIN;
pub const INTPTR_MAX = INT64_MAX;
pub const UINTPTR_MAX = UINT64_MAX;
pub const PTRDIFF_MIN = INT64_MIN;
pub const PTRDIFF_MAX = INT64_MAX;
pub const SIZE_MAX = UINT64_MAX;
pub inline fn INT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn INT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn INT32_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const UINT32_C = @import("std").zig.c_translation.Macros.U_SUFFIX;
pub const INT64_C = @import("std").zig.c_translation.Macros.L_SUFFIX;
pub const UINT64_C = @import("std").zig.c_translation.Macros.UL_SUFFIX;
pub const INTMAX_C = @import("std").zig.c_translation.Macros.L_SUFFIX;
pub const UINTMAX_C = @import("std").zig.c_translation.Macros.UL_SUFFIX;
pub inline fn STBI_NOTUSED(v: anytype) anyopaque {
    _ = &v;
    return @import("std").zig.c_translation.cast(anyopaque, @import("std").zig.c_translation.sizeof(v));
}
pub inline fn stbi_lrot(x: anytype, y: anytype) @TypeOf((x << y) | (x >> (-y & @as(c_int, 31)))) {
    _ = &x;
    _ = &y;
    return (x << y) | (x >> (-y & @as(c_int, 31)));
}
pub inline fn STBI_MALLOC(sz: anytype) @TypeOf(malloc(sz)) {
    _ = &sz;
    return malloc(sz);
}
pub inline fn STBI_REALLOC(p: anytype, newsz: anytype) @TypeOf(realloc(p, newsz)) {
    _ = &p;
    _ = &newsz;
    return realloc(p, newsz);
}
pub inline fn STBI_FREE(p: anytype) @TypeOf(free(p)) {
    _ = &p;
    return free(p);
}
pub inline fn STBI_REALLOC_SIZED(p: anytype, oldsz: anytype, newsz: anytype) @TypeOf(STBI_REALLOC(p, newsz)) {
    _ = &p;
    _ = &oldsz;
    _ = &newsz;
    return STBI_REALLOC(p, newsz);
}
pub inline fn STBI_SIMD_ALIGN(@"type": anytype, name: anytype) @TypeOf(@"type" ++ name) {
    _ = &@"type";
    _ = &name;
    return @"type" ++ name;
}
pub const STBI_MAX_DIMENSIONS = @as(c_int, 1) << @as(c_int, 24);
pub inline fn stbi__err(x: anytype, y: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &x;
    _ = &y;
    return @as(c_int, 0);
}
pub inline fn stbi__errpf(x: anytype, y: anytype) [*c]f32 {
    _ = &x;
    _ = &y;
    return @import("std").zig.c_translation.cast([*c]f32, @import("std").zig.c_translation.cast(usize, if (stbi__err(x, y) != 0) NULL else NULL));
}
pub inline fn stbi__errpuc(x: anytype, y: anytype) [*c]u8 {
    _ = &x;
    _ = &y;
    return @import("std").zig.c_translation.cast([*c]u8, @import("std").zig.c_translation.cast(usize, if (stbi__err(x, y) != 0) NULL else NULL));
}
// /home/x/next/arcan/src/engine/external/stb_image.h:1132:9: warning: macro 'stbi__vertically_flip_on_load' contains a runtime value, translated to function
pub inline fn stbi__vertically_flip_on_load() @TypeOf(if (stbi__vertically_flip_on_load_set != 0) stbi__vertically_flip_on_load_local else stbi__vertically_flip_on_load_global) {
    return if (stbi__vertically_flip_on_load_set != 0) stbi__vertically_flip_on_load_local else stbi__vertically_flip_on_load_global;
}
pub inline fn STBI__BYTECAST(x: anytype) stbi_uc {
    _ = &x;
    return @import("std").zig.c_translation.cast(stbi_uc, x & @as(c_int, 255));
}
pub inline fn STBI__COMBO(a: anytype, b: anytype) @TypeOf((a * @as(c_int, 8)) + b) {
    _ = &a;
    _ = &b;
    return (a * @as(c_int, 8)) + b;
}
pub const STBI__CASE = @compileError("unable to translate macro: undefined identifier `i`");
// /home/x/next/arcan/src/engine/external/stb_image.h:1774:15
pub const FAST_BITS = @as(c_int, 9);
pub inline fn stbi__f2f(x: anytype) c_int {
    _ = &x;
    return @import("std").zig.c_translation.cast(c_int, (x * @as(c_int, 4096)) + @as(f64, 0.5));
}
pub inline fn stbi__fsh(x: anytype) @TypeOf(x * @as(c_int, 4096)) {
    _ = &x;
    return x * @as(c_int, 4096);
}
pub const STBI__IDCT_1D = @compileError("unable to translate macro: undefined identifier `t0`");
// /home/x/next/arcan/src/engine/external/stb_image.h:2430:9
pub const STBI__MARKER_none = @as(c_int, 0xff);
pub inline fn STBI__RESTART(x: anytype) @TypeOf((x >= @as(c_int, 0xd0)) and (x <= @as(c_int, 0xd7))) {
    _ = &x;
    return (x >= @as(c_int, 0xd0)) and (x <= @as(c_int, 0xd7));
}
pub inline fn stbi__DNL(x: anytype) @TypeOf(x == @as(c_int, 0xdc)) {
    _ = &x;
    return x == @as(c_int, 0xdc);
}
pub inline fn stbi__SOI(x: anytype) @TypeOf(x == @as(c_int, 0xd8)) {
    _ = &x;
    return x == @as(c_int, 0xd8);
}
pub inline fn stbi__EOI(x: anytype) @TypeOf(x == @as(c_int, 0xd9)) {
    _ = &x;
    return x == @as(c_int, 0xd9);
}
pub inline fn stbi__SOF(x: anytype) @TypeOf(((x == @as(c_int, 0xc0)) or (x == @as(c_int, 0xc1))) or (x == @as(c_int, 0xc2))) {
    _ = &x;
    return ((x == @as(c_int, 0xc0)) or (x == @as(c_int, 0xc1))) or (x == @as(c_int, 0xc2));
}
pub inline fn stbi__SOS(x: anytype) @TypeOf(x == @as(c_int, 0xda)) {
    _ = &x;
    return x == @as(c_int, 0xda);
}
pub inline fn stbi__SOF_progressive(x: anytype) @TypeOf(x == @as(c_int, 0xc2)) {
    _ = &x;
    return x == @as(c_int, 0xc2);
}
pub inline fn stbi__div4(x: anytype) stbi_uc {
    _ = &x;
    return @import("std").zig.c_translation.cast(stbi_uc, x >> @as(c_int, 2));
}
pub inline fn stbi__div16(x: anytype) stbi_uc {
    _ = &x;
    return @import("std").zig.c_translation.cast(stbi_uc, x >> @as(c_int, 4));
}
pub inline fn stbi__float2fixed(x: anytype) @TypeOf(@import("std").zig.c_translation.cast(c_int, (x * @as(f32, 4096.0)) + @as(f32, 0.5)) << @as(c_int, 8)) {
    _ = &x;
    return @import("std").zig.c_translation.cast(c_int, (x * @as(f32, 4096.0)) + @as(f32, 0.5)) << @as(c_int, 8);
}
pub const STBI__ZFAST_BITS = @as(c_int, 9);
pub const STBI__ZFAST_MASK = (@as(c_int, 1) << STBI__ZFAST_BITS) - @as(c_int, 1);
pub const STBI__ZNSYMS = @as(c_int, 288);
// /home/x/next/arcan/src/engine/external/stb_image.h:5025:9: warning: macro 'stbi__unpremultiply_on_load' contains a runtime value, translated to function
pub inline fn stbi__unpremultiply_on_load() @TypeOf(if (stbi__unpremultiply_on_load_set != 0) stbi__unpremultiply_on_load_local else stbi__unpremultiply_on_load_global) {
    return if (stbi__unpremultiply_on_load_set != 0) stbi__unpremultiply_on_load_local else stbi__unpremultiply_on_load_global;
}
// /home/x/next/arcan/src/engine/external/stb_image.h:5028:9: warning: macro 'stbi__de_iphone_flag' contains a runtime value, translated to function
pub inline fn stbi__de_iphone_flag() @TypeOf(if (stbi__de_iphone_flag_set != 0) stbi__de_iphone_flag_local else stbi__de_iphone_flag_global) {
    return if (stbi__de_iphone_flag_set != 0) stbi__de_iphone_flag_local else stbi__de_iphone_flag_global;
}
pub inline fn STBI__PNG_TYPE(a: anytype, b: anytype, c: anytype, d: anytype) @TypeOf((((@import("std").zig.c_translation.cast(c_uint, a) << @as(c_int, 24)) + (@import("std").zig.c_translation.cast(c_uint, b) << @as(c_int, 16))) + (@import("std").zig.c_translation.cast(c_uint, c) << @as(c_int, 8))) + @import("std").zig.c_translation.cast(c_uint, d)) {
    _ = &a;
    _ = &b;
    _ = &c;
    _ = &d;
    return (((@import("std").zig.c_translation.cast(c_uint, a) << @as(c_int, 24)) + (@import("std").zig.c_translation.cast(c_uint, b) << @as(c_int, 16))) + (@import("std").zig.c_translation.cast(c_uint, c) << @as(c_int, 8))) + @import("std").zig.c_translation.cast(c_uint, d);
}
pub const STB_IMAGE_WRITE_IMPLEMENTATION = "";
pub const INCLUDE_STB_IMAGE_WRITE_H = "";
pub const STBIWDEF = @compileError("unable to translate C expr: unexpected token 'extern'");
// /home/x/next/arcan/src/engine/external/stb_image_write.h:164:9
pub inline fn STBIW_MALLOC(sz: anytype) @TypeOf(malloc(sz)) {
    _ = &sz;
    return malloc(sz);
}
pub inline fn STBIW_REALLOC(p: anytype, newsz: anytype) @TypeOf(realloc(p, newsz)) {
    _ = &p;
    _ = &newsz;
    return realloc(p, newsz);
}
pub inline fn STBIW_FREE(p: anytype) @TypeOf(free(p)) {
    _ = &p;
    return free(p);
}
pub inline fn STBIW_REALLOC_SIZED(p: anytype, oldsz: anytype, newsz: anytype) @TypeOf(STBIW_REALLOC(p, newsz)) {
    _ = &p;
    _ = &oldsz;
    _ = &newsz;
    return STBIW_REALLOC(p, newsz);
}
pub inline fn STBIW_MEMMOVE(a: anytype, b: anytype, sz: anytype) @TypeOf(memmove(a, b, sz)) {
    _ = &a;
    _ = &b;
    _ = &sz;
    return memmove(a, b, sz);
}
pub inline fn STBIW_ASSERT(x: anytype) @TypeOf(assert(x)) {
    _ = &x;
    return assert(x);
}
pub inline fn STBIW_UCHAR(x: anytype) u8 {
    _ = &x;
    return @import("std").zig.c_translation.cast(u8, x & @as(c_int, 0xff));
}
pub inline fn stbiw__max(a: anytype, b: anytype) @TypeOf(if (a > b) a else b) {
    _ = &a;
    _ = &b;
    return if (a > b) a else b;
}
pub inline fn stbiw__sbraw(a: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]c_int, @import("std").zig.c_translation.cast(?*anyopaque, a)) - @as(c_int, 2)) {
    _ = &a;
    return @import("std").zig.c_translation.cast([*c]c_int, @import("std").zig.c_translation.cast(?*anyopaque, a)) - @as(c_int, 2);
}
pub inline fn stbiw__sbm(a: anytype) @TypeOf(stbiw__sbraw(a)[@as(usize, @intCast(@as(c_int, 0)))]) {
    _ = &a;
    return stbiw__sbraw(a)[@as(usize, @intCast(@as(c_int, 0)))];
}
pub inline fn stbiw__sbn(a: anytype) @TypeOf(stbiw__sbraw(a)[@as(usize, @intCast(@as(c_int, 1)))]) {
    _ = &a;
    return stbiw__sbraw(a)[@as(usize, @intCast(@as(c_int, 1)))];
}
pub inline fn stbiw__sbneedgrow(a: anytype, n: anytype) @TypeOf((a == @as(c_int, 0)) or ((stbiw__sbn(a) + n) >= stbiw__sbm(a))) {
    _ = &a;
    _ = &n;
    return (a == @as(c_int, 0)) or ((stbiw__sbn(a) + n) >= stbiw__sbm(a));
}
pub inline fn stbiw__sbmaybegrow(a: anytype, n: anytype) @TypeOf(if (stbiw__sbneedgrow(a, n) != 0) stbiw__sbgrow(a, n) else @as(c_int, 0)) {
    _ = &a;
    _ = &n;
    return if (stbiw__sbneedgrow(a, n) != 0) stbiw__sbgrow(a, n) else @as(c_int, 0);
}
pub const stbiw__sbgrow = @compileError("unable to translate C expr: expected ')' instead got '*'");
// /home/x/next/arcan/src/engine/external/stb_image_write.h:820:9
pub const stbiw__sbpush = @compileError("TODO postfix inc/dec expr");
// /home/x/next/arcan/src/engine/external/stb_image_write.h:822:9
pub inline fn stbiw__sbcount(a: anytype) @TypeOf(if (a != 0) stbiw__sbn(a) else @as(c_int, 0)) {
    _ = &a;
    return if (a != 0) stbiw__sbn(a) else @as(c_int, 0);
}
pub const stbiw__sbfree = @compileError("unable to translate C expr: expected ':' instead got ','");
// /home/x/next/arcan/src/engine/external/stb_image_write.h:824:9
pub const stbiw__zlib_flush = @compileError("unable to translate macro: undefined identifier `out`");
// /home/x/next/arcan/src/engine/external/stb_image_write.h:879:9
pub const stbiw__zlib_add = @compileError("unable to translate macro: undefined identifier `bitbuf`");
// /home/x/next/arcan/src/engine/external/stb_image_write.h:880:9
pub inline fn stbiw__zlib_huffa(b: anytype, c: anytype) @TypeOf(stbiw__zlib_add(stbiw__zlib_bitrev(b, c), c)) {
    _ = &b;
    _ = &c;
    return stbiw__zlib_add(stbiw__zlib_bitrev(b, c), c);
}
pub inline fn stbiw__zlib_huff1(n: anytype) @TypeOf(stbiw__zlib_huffa(@as(c_int, 0x30) + n, @as(c_int, 8))) {
    _ = &n;
    return stbiw__zlib_huffa(@as(c_int, 0x30) + n, @as(c_int, 8));
}
pub inline fn stbiw__zlib_huff2(n: anytype) @TypeOf(stbiw__zlib_huffa((@as(c_int, 0x190) + n) - @as(c_int, 144), @as(c_int, 9))) {
    _ = &n;
    return stbiw__zlib_huffa((@as(c_int, 0x190) + n) - @as(c_int, 144), @as(c_int, 9));
}
pub inline fn stbiw__zlib_huff3(n: anytype) @TypeOf(stbiw__zlib_huffa((@as(c_int, 0) + n) - @as(c_int, 256), @as(c_int, 7))) {
    _ = &n;
    return stbiw__zlib_huffa((@as(c_int, 0) + n) - @as(c_int, 256), @as(c_int, 7));
}
pub inline fn stbiw__zlib_huff4(n: anytype) @TypeOf(stbiw__zlib_huffa((@as(c_int, 0xc0) + n) - @as(c_int, 280), @as(c_int, 8))) {
    _ = &n;
    return stbiw__zlib_huffa((@as(c_int, 0xc0) + n) - @as(c_int, 280), @as(c_int, 8));
}
pub inline fn stbiw__zlib_huff(n: anytype) @TypeOf(if (n <= @as(c_int, 143)) stbiw__zlib_huff1(n) else if (n <= @as(c_int, 255)) stbiw__zlib_huff2(n) else if (n <= @as(c_int, 279)) stbiw__zlib_huff3(n) else stbiw__zlib_huff4(n)) {
    _ = &n;
    return if (n <= @as(c_int, 143)) stbiw__zlib_huff1(n) else if (n <= @as(c_int, 255)) stbiw__zlib_huff2(n) else if (n <= @as(c_int, 279)) stbiw__zlib_huff3(n) else stbiw__zlib_huff4(n);
}
pub inline fn stbiw__zlib_huffb(n: anytype) @TypeOf(if (n <= @as(c_int, 143)) stbiw__zlib_huff1(n) else stbiw__zlib_huff2(n)) {
    _ = &n;
    return if (n <= @as(c_int, 143)) stbiw__zlib_huff1(n) else stbiw__zlib_huff2(n);
}
pub const stbiw__ZHASH = @as(c_int, 16384);
pub const stbiw__wpng4 = @compileError("unable to translate C expr: expected ')' instead got '='");
// /home/x/next/arcan/src/engine/external/stb_image_write.h:1073:9
pub const stbiw__wp32 = @compileError("unable to translate C expr: unexpected token ';'");
// /home/x/next/arcan/src/engine/external/stb_image_write.h:1074:9
pub inline fn stbiw__wptag(data: anytype, s: anytype) @TypeOf(stbiw__wpng4(data, s[@as(usize, @intCast(@as(c_int, 0)))], s[@as(usize, @intCast(@as(c_int, 1)))], s[@as(usize, @intCast(@as(c_int, 2)))], s[@as(usize, @intCast(@as(c_int, 3)))])) {
    _ = &data;
    _ = &s;
    return stbiw__wpng4(data, s[@as(usize, @intCast(@as(c_int, 0)))], s[@as(usize, @intCast(@as(c_int, 1)))], s[@as(usize, @intCast(@as(c_int, 2)))], s[@as(usize, @intCast(@as(c_int, 3)))]);
}
pub const _IO_FILE = struct__IO_FILE;
pub const _G_fpos64_t = union__G_fpos64_t;
pub const __locale_struct = struct___locale_struct;
