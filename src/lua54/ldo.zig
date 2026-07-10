// ---- C builtins (translate-c) ----
const std = @import("std");
const c_builtins = std.zig.c_builtins;

// Used by luai_likely/luai_unlikely macro expansions throughout ldo
pub const __builtin_expect = c_builtins.__builtin_expect;
// Used by luaO_ceillog2 and _bsr
pub const __builtin_clz = c_builtins.__builtin_clz;
// Used by NAN/INFINITY constants and isinf/isnan helpers
pub const __builtin_nanf = c_builtins.__builtin_nanf;
pub const __builtin_inff = c_builtins.__builtin_inff;
pub const __builtin_isnan = c_builtins.__builtin_isnan;
pub const __builtin_isinf = c_builtins.__builtin_isinf;
pub const __builtin_isinf_sign = c_builtins.__builtin_isinf_sign;
pub const __builtin_signbit = c_builtins.__builtin_signbit;
// Used by inline string/memory helpers (strlcpy, strlcat, memccpy, etc.)
pub const __builtin_strlen = c_builtins.__builtin_strlen;
pub const __builtin_strcmp = c_builtins.__builtin_strcmp;
pub const __builtin_memcpy = c_builtins.__builtin_memcpy;
pub const __builtin_memset = c_builtins.__builtin_memset;
pub const __builtin_object_size = c_builtins.__builtin_object_size;
pub const __builtin___memset_chk = c_builtins.__builtin___memset_chk;
pub const __builtin___memcpy_chk = c_builtins.__builtin___memcpy_chk;
// Other builtins referenced by translated macros
pub const __builtin_mul_overflow = c_builtins.__builtin_mul_overflow;
pub const __builtin_constant_p = c_builtins.__builtin_constant_p;
pub const __builtin_unreachable = c_builtins.__builtin_unreachable;
pub const __builtin_assume = c_builtins.__builtin_assume;
pub const __has_builtin = c_builtins.__has_builtin;
// ---- C type aliases (needed by Lua type definitions and later declarations) ----
pub const ptrdiff_t = isize;
pub const sig_atomic_t = c_int;
pub const intmax_t = c_long;
pub const uintmax_t = c_ulong;
// Types needed by extern declarations after the cleanup boundary
pub const wchar_t = c_uint;
pub const char16_t = c_ushort;
pub const char32_t = c_uint;
pub const errno_t = c_int;
pub const wint_t = c_uint;
// POSIX/system externs omitted (unused by ldo.c — translate-c header expansion)
// Terminal/pty structs and externs omitted (unused by ldo.c)
pub const struct_termios = opaque {};
pub const struct_winsize = opaque {};
// stdlib/wchar/sort/alloc externs omitted (unused by ldo.c)

// ---- setjmp/longjmp (used by Lua error handling) ----
pub const jmp_buf = [22]c_long;
pub extern fn longjmp(buf: [*c]c_long, val: c_int) noreturn;
pub extern fn _setjmp(buf: [*c]c_long) c_int;

// ---- libc core (used by translated inline helpers) ----
pub extern fn abort() noreturn;
pub extern fn exit(status: c_int) noreturn;
pub extern fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;

// ---- va_list (used by lua_pushvfstring declarations) ----
pub const struct___va_list_1 = extern struct {
    __stack: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __gr_top: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __vr_top: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __gr_offs: c_int = @import("std").mem.zeroes(c_int),
    __vr_offs: c_int = @import("std").mem.zeroes(c_int),
};
pub const __builtin_va_list = struct___va_list_1;
// ---- memory/string (used by translated inline helpers) ----
pub extern fn memset(?*anyopaque, c_int, usize) ?*anyopaque;
pub extern fn memmove(?*anyopaque, ?*const anyopaque, usize) ?*anyopaque;
pub extern fn memcpy(?*anyopaque, ?*const anyopaque, usize) ?*anyopaque;
pub extern fn strlen([*c]const u8) c_ulong;
pub extern fn strncpy([*c]u8, [*c]const u8, usize) [*c]u8;
pub extern fn strncat([*c]u8, [*c]const u8, usize) [*c]u8;

// Freestanding-safe local implementations of libc functions
fn _Exit(status: c_int) noreturn {
    _ = status;
    while (true) asm volatile ("wfe");
}

fn strchr(s: [*c]const u8, char_arg: c_int) [*c]u8 {
    const ch: u8 = @intCast(char_arg & 0xFF);
    var i: usize = 0;
    while (true) {
        if (s[i] == ch) return @constCast(s) + i;
        if (s[i] == 0) return null;
        i += 1;
    }
}

// strtod replacement for freestanding (no libc strtod available)
fn strtod(s: [*c]const u8, endptr: [*c][*c]u8) f64 {
    const slice = std.mem.span(@as([*:0]const u8, @ptrCast(s)));
    const result = std.fmt.parseFloat(f64, slice) catch 0.0;
    if (@intFromPtr(endptr) != 0) {
        const parsed_ok = std.fmt.parseFloat(f64, slice) catch null;
        if (parsed_ok != null) {
            endptr.* = @constCast(s) + slice.len;
        } else {
            endptr.* = @constCast(s);
        }
    }
    return result;
}

// wchar/multibyte/string types needed by declarations after line 500
pub const mbstate_t = c_uint;

// Stub type for Elf64_Ehdr alias declared later (originally from header expansion)
pub const struct_Elf64_Ehdr = opaque {};

// string search/compare, wchar, multibyte, random, temp file,
// assert, environ, sort, alloc externs omitted (unused by ldo.c)
pub const Elf64_Ehdr = struct_Elf64_Ehdr;
pub extern var __runlevel: u8;
pub extern var ftrace_stackdigs: c_int;
pub extern const kNtStdio: [3]i8;
pub const v_ntsubsystem: [*c]const u8 = @extern([*c]const u8, .{
    .name = "v_ntsubsystem",
});
pub const __fini_array_end: [*c]const usize = @extern([*c]const usize, .{
    .name = "__fini_array_end",
});
pub const __fini_array_start: [*c]const usize = @extern([*c]const usize, .{
    .name = "__fini_array_start",
});
pub const _tdata_start: [*c]u8 = @extern([*c]u8, .{
    .name = "_tdata_start",
});
pub const _tdata_end: [*c]u8 = @extern([*c]u8, .{
    .name = "_tdata_end",
});
pub const _tdata_size: [*c]u8 = @extern([*c]u8, .{
    .name = "_tdata_size",
});
pub const _tbss_start: [*c]u8 = @extern([*c]u8, .{
    .name = "_tbss_start",
});
pub const _tbss_end: [*c]u8 = @extern([*c]u8, .{
    .name = "_tbss_end",
});
pub const _tbss_size: [*c]u8 = @extern([*c]u8, .{
    .name = "_tbss_size",
});
pub const _tbss_offset: [*c]u8 = @extern([*c]u8, .{
    .name = "_tbss_offset",
});
pub const _tls_size: [*c]u8 = @extern([*c]u8, .{
    .name = "_tls_size",
});
pub const _tls_content: [*c]u8 = @extern([*c]u8, .{
    .name = "_tls_content",
});
pub extern fn _init() void;
pub extern fn __init_fds() void;
pub extern fn ftrace_init() c_int;
pub extern fn ftrace_hook() void;
pub extern fn __enable_tls() void;
pub extern fn GetDosArgv([*c]const char16_t, [*c]u8, usize, [*c][*c]u8, usize) c_int;
pub extern fn GetDosEnviron([*c]const char16_t, [*c]u8, usize, [*c][*c]u8, usize) c_int;
pub extern fn __intercept_flag([*c]c_int, [*c][*c]u8, [*c]const u8) bool;
pub extern fn __inflate(?*anyopaque, usize, ?*const anyopaque, usize) c_int;
pub extern fn __on_arithmetic_overflow() void;
pub extern fn __init_program_executable_name() void;
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
pub const lu_byte = u8;
pub const struct_GCObject = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
};
pub const lua_Alloc = ?*const fn (?*anyopaque, ?*anyopaque, usize, usize) callconv(.c) ?*anyopaque;
pub const l_mem = ptrdiff_t;
pub const lu_mem = usize;
const union_unnamed_2 = extern union {
    lnglen: usize,
    hnext: [*c]struct_TString,
};
pub const struct_TString = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    extra: lu_byte = @import("std").mem.zeroes(lu_byte),
    shrlen: lu_byte = @import("std").mem.zeroes(lu_byte),
    hash: c_uint = @import("std").mem.zeroes(c_uint),
    u: union_unnamed_2 = @import("std").mem.zeroes(union_unnamed_2),
    contents: [1]u8 = std.mem.zeroes([1]u8),
};
pub const TString = struct_TString;
pub const struct_stringtable = extern struct {
    hash: [*c][*c]TString = @import("std").mem.zeroes([*c][*c]TString),
    nuse: c_int = @import("std").mem.zeroes(c_int),
    size: c_int = @import("std").mem.zeroes(c_int),
};
pub const stringtable = struct_stringtable;
pub const lua_State = struct_lua_State;
pub const lua_CFunction = ?*const fn ([*c]lua_State) callconv(.c) c_int;
pub const lua_Integer = c_longlong;
pub const lua_Number = f64;
pub const union_Value = extern union {
    gc: [*c]struct_GCObject,
    p: ?*anyopaque,
    f: lua_CFunction,
    i: lua_Integer,
    n: lua_Number,
    ub: lu_byte,
};
pub const Value = union_Value;
pub const struct_TValue = extern struct {
    value_: Value = @import("std").mem.zeroes(Value),
    tt_: lu_byte = @import("std").mem.zeroes(lu_byte),
};
pub const TValue = struct_TValue;
pub const GCObject = struct_GCObject;
pub const struct_NodeKey_3 = extern struct {
    value_: Value = @import("std").mem.zeroes(Value),
    tt_: lu_byte = @import("std").mem.zeroes(lu_byte),
    key_tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    next: c_int = @import("std").mem.zeroes(c_int),
    key_val: Value = @import("std").mem.zeroes(Value),
};
pub const union_Node = extern union {
    u: struct_NodeKey_3,
    i_val: TValue,
};
pub const Node = union_Node;
pub const struct_Table = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    flags: lu_byte = @import("std").mem.zeroes(lu_byte),
    lsizenode: lu_byte = @import("std").mem.zeroes(lu_byte),
    alimit: c_uint = @import("std").mem.zeroes(c_uint),
    array: [*c]TValue = @import("std").mem.zeroes([*c]TValue),
    node: [*c]Node = @import("std").mem.zeroes([*c]Node),
    lastfree: [*c]Node = @import("std").mem.zeroes([*c]Node),
    metatable: [*c]struct_Table = @import("std").mem.zeroes([*c]struct_Table),
    gclist: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
};
pub const lua_WarnFunction = ?*const fn (?*anyopaque, [*c]const u8, c_int) callconv(.c) void;
pub const struct_global_State = extern struct {
    frealloc: lua_Alloc = @import("std").mem.zeroes(lua_Alloc),
    ud: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    totalbytes: l_mem = @import("std").mem.zeroes(l_mem),
    GCdebt: l_mem = @import("std").mem.zeroes(l_mem),
    GCestimate: lu_mem = @import("std").mem.zeroes(lu_mem),
    lastatomic: lu_mem = @import("std").mem.zeroes(lu_mem),
    strt: stringtable = @import("std").mem.zeroes(stringtable),
    l_registry: TValue = @import("std").mem.zeroes(TValue),
    nilvalue: TValue = @import("std").mem.zeroes(TValue),
    seed: c_uint = @import("std").mem.zeroes(c_uint),
    currentwhite: lu_byte = @import("std").mem.zeroes(lu_byte),
    gcstate: lu_byte = @import("std").mem.zeroes(lu_byte),
    gckind: lu_byte = @import("std").mem.zeroes(lu_byte),
    gcstopem: lu_byte = @import("std").mem.zeroes(lu_byte),
    genminormul: lu_byte = @import("std").mem.zeroes(lu_byte),
    genmajormul: lu_byte = @import("std").mem.zeroes(lu_byte),
    gcstp: lu_byte = @import("std").mem.zeroes(lu_byte),
    gcemergency: lu_byte = @import("std").mem.zeroes(lu_byte),
    gcpause: lu_byte = @import("std").mem.zeroes(lu_byte),
    gcstepmul: lu_byte = @import("std").mem.zeroes(lu_byte),
    gcstepsize: lu_byte = @import("std").mem.zeroes(lu_byte),
    allgc: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    sweepgc: [*c][*c]GCObject = @import("std").mem.zeroes([*c][*c]GCObject),
    finobj: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    gray: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    grayagain: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    weak: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    ephemeron: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    allweak: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    tobefnz: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    fixedgc: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    survival: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    old1: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    reallyold: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    firstold1: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    finobjsur: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    finobjold1: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    finobjrold: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    twups: [*c]struct_lua_State = @import("std").mem.zeroes([*c]struct_lua_State),
    panic: lua_CFunction = @import("std").mem.zeroes(lua_CFunction),
    mainthread: [*c]struct_lua_State = @import("std").mem.zeroes([*c]struct_lua_State),
    memerrmsg: [*c]TString = @import("std").mem.zeroes([*c]TString),
    tmname: [25][*c]TString = @import("std").mem.zeroes([25][*c]TString),
    mt: [9][*c]struct_Table = @import("std").mem.zeroes([9][*c]struct_Table),
    strcache: [53][2][*c]TString = @import("std").mem.zeroes([53][2][*c]TString),
    warnf: lua_WarnFunction = @import("std").mem.zeroes(lua_WarnFunction),
    ud_warn: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
};
pub const global_State = struct_global_State;
pub const l_uint32 = c_uint;
pub const Instruction = l_uint32;
const struct_unnamed_5 = extern struct {
    savedpc: [*c]const Instruction = @import("std").mem.zeroes([*c]const Instruction),
    trap: sig_atomic_t = @import("std").mem.zeroes(sig_atomic_t),
    nextraargs: c_int = @import("std").mem.zeroes(c_int),
};
pub const lua_KContext = isize;
pub const lua_KFunction = ?*const fn (?*anyopaque, c_int, lua_KContext) callconv(.c) c_int;
const struct_unnamed_6 = extern struct {
    k: lua_KFunction = @import("std").mem.zeroes(lua_KFunction),
    old_errfunc: ptrdiff_t = @import("std").mem.zeroes(ptrdiff_t),
    ctx: lua_KContext = @import("std").mem.zeroes(lua_KContext),
};
const union_unnamed_4 = extern union {
    l: struct_unnamed_5,
    c: struct_unnamed_6,
};
const struct_unnamed_8 = extern struct {
    ftransfer: c_ushort = @import("std").mem.zeroes(c_ushort),
    ntransfer: c_ushort = @import("std").mem.zeroes(c_ushort),
};
const union_unnamed_7 = extern union {
    funcidx: c_int,
    nyield: c_int,
    nres: c_int,
    transferinfo: struct_unnamed_8,
};
pub const struct_CallInfo = extern struct {
    func: StkIdRel = @import("std").mem.zeroes(StkIdRel),
    top: StkIdRel = @import("std").mem.zeroes(StkIdRel),
    previous: [*c]struct_CallInfo = @import("std").mem.zeroes([*c]struct_CallInfo),
    next: [*c]struct_CallInfo = @import("std").mem.zeroes([*c]struct_CallInfo),
    u: union_unnamed_4 = @import("std").mem.zeroes(union_unnamed_4),
    u2: union_unnamed_7 = @import("std").mem.zeroes(union_unnamed_7),
    nresults: c_short = @import("std").mem.zeroes(c_short),
    callstatus: c_ushort = @import("std").mem.zeroes(c_ushort),
};
pub const CallInfo = struct_CallInfo;
const union_unnamed_9 = extern union {
    p: [*c]TValue,
    offset: ptrdiff_t,
};
const struct_unnamed_11 = extern struct {
    next: [*c]struct_UpVal = @import("std").mem.zeroes([*c]struct_UpVal),
    previous: [*c][*c]struct_UpVal = @import("std").mem.zeroes([*c][*c]struct_UpVal),
};
const union_unnamed_10 = extern union {
    open: struct_unnamed_11,
    value: TValue,
};
pub const struct_UpVal = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    v: union_unnamed_9 = @import("std").mem.zeroes(union_unnamed_9),
    u: union_unnamed_10 = @import("std").mem.zeroes(union_unnamed_10),
};
pub const UpVal = struct_UpVal;
pub const struct_lua_longjmp = extern struct {
    previous: [*c]struct_lua_longjmp = @import("std").mem.zeroes([*c]struct_lua_longjmp),
    b: jmp_buf = @import("std").mem.zeroes(jmp_buf),
    status: c_int = @import("std").mem.zeroes(c_int),
};
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
    i_ci: [*c]struct_CallInfo = @import("std").mem.zeroes([*c]struct_CallInfo),
};
pub const lua_Debug = struct_lua_Debug;
pub const lua_Hook = ?*const fn ([*c]lua_State, [*c]lua_Debug) callconv(.c) void;
pub const struct_lua_State = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    status: lu_byte = @import("std").mem.zeroes(lu_byte),
    allowhook: lu_byte = @import("std").mem.zeroes(lu_byte),
    nci: c_ushort = @import("std").mem.zeroes(c_ushort),
    top: StkIdRel = @import("std").mem.zeroes(StkIdRel),
    l_G: [*c]global_State = @import("std").mem.zeroes([*c]global_State),
    ci: [*c]CallInfo = @import("std").mem.zeroes([*c]CallInfo),
    stack_last: StkIdRel = @import("std").mem.zeroes(StkIdRel),
    stack: StkIdRel = @import("std").mem.zeroes(StkIdRel),
    openupval: [*c]UpVal = @import("std").mem.zeroes([*c]UpVal),
    tbclist: StkIdRel = @import("std").mem.zeroes(StkIdRel),
    gclist: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    twups: [*c]struct_lua_State = @import("std").mem.zeroes([*c]struct_lua_State),
    errorJmp: [*c]struct_lua_longjmp = @import("std").mem.zeroes([*c]struct_lua_longjmp),
    base_ci: CallInfo = @import("std").mem.zeroes(CallInfo),
    hook: lua_Hook = @import("std").mem.zeroes(lua_Hook),
    errfunc: ptrdiff_t = @import("std").mem.zeroes(ptrdiff_t),
    nCcalls: l_uint32 = @import("std").mem.zeroes(l_uint32),
    oldpc: c_int = @import("std").mem.zeroes(c_int),
    basehookcount: c_int = @import("std").mem.zeroes(c_int),
    hookcount: c_int = @import("std").mem.zeroes(c_int),
    hookmask: sig_atomic_t = @import("std").mem.zeroes(sig_atomic_t),
};
pub const lua_Unsigned = c_ulonglong;
pub const lua_Reader = ?*const fn ([*c]lua_State, ?*anyopaque, [*c]usize) callconv(.c) [*c]const u8;
pub const lua_Writer = ?*const fn ([*c]lua_State, ?*const anyopaque, usize, ?*anyopaque) callconv(.c) c_int;
pub const lua_ident: [*c]const u8 = @extern([*c]const u8, .{
    .name = "lua_ident",
});
pub extern fn lua_newstate(f: lua_Alloc, ud: ?*anyopaque) [*c]lua_State;
pub extern fn lua_close(L: [*c]lua_State) void;
pub extern fn lua_newthread(L: [*c]lua_State) [*c]lua_State;
pub extern fn lua_closethread(L: [*c]lua_State, from: [*c]lua_State) c_int;
pub extern fn lua_resetthread(L: [*c]lua_State) c_int;
pub extern fn lua_atpanic(L: [*c]lua_State, panicf: lua_CFunction) lua_CFunction;
pub extern fn lua_version(L: [*c]lua_State) lua_Number;
pub extern fn lua_absindex(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_gettop(L: [*c]lua_State) c_int;
pub extern fn lua_settop(L: [*c]lua_State, idx: c_int) void;
pub extern fn lua_pushvalue(L: [*c]lua_State, idx: c_int) void;
pub extern fn lua_rotate(L: [*c]lua_State, idx: c_int, n: c_int) void;
pub extern fn lua_copy(L: [*c]lua_State, fromidx: c_int, toidx: c_int) void;
pub extern fn lua_checkstack(L: [*c]lua_State, n: c_int) c_int;
pub extern fn lua_xmove(from: [*c]lua_State, to: [*c]lua_State, n: c_int) void;
pub extern fn lua_isnumber(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_isstring(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_iscfunction(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_isinteger(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_isuserdata(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_type(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_typename(L: [*c]lua_State, tp: c_int) [*c]const u8;
pub extern fn lua_tonumberx(L: [*c]lua_State, idx: c_int, isnum: [*c]c_int) lua_Number;
pub extern fn lua_tointegerx(L: [*c]lua_State, idx: c_int, isnum: [*c]c_int) lua_Integer;
pub extern fn lua_toboolean(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_tolstring(L: [*c]lua_State, idx: c_int, len: [*c]usize) [*c]const u8;
pub extern fn lua_rawlen(L: [*c]lua_State, idx: c_int) lua_Unsigned;
pub extern fn lua_tocfunction(L: [*c]lua_State, idx: c_int) lua_CFunction;
pub extern fn lua_touserdata(L: [*c]lua_State, idx: c_int) ?*anyopaque;
pub extern fn lua_tothread(L: [*c]lua_State, idx: c_int) [*c]lua_State;
pub extern fn lua_topointer(L: [*c]lua_State, idx: c_int) ?*const anyopaque;
pub extern fn lua_arith(L: [*c]lua_State, op: c_int) void;
pub extern fn lua_rawequal(L: [*c]lua_State, idx1: c_int, idx2: c_int) c_int;
pub extern fn lua_compare(L: [*c]lua_State, idx1: c_int, idx2: c_int, op: c_int) c_int;
pub extern fn lua_pushnil(L: [*c]lua_State) void;
pub extern fn lua_pushnumber(L: [*c]lua_State, n: lua_Number) void;
pub extern fn lua_pushinteger(L: [*c]lua_State, n: lua_Integer) void;
pub extern fn lua_pushlstring(L: [*c]lua_State, s: [*c]const u8, len: usize) [*c]const u8;
pub extern fn lua_pushstring(L: [*c]lua_State, s: [*c]const u8) [*c]const u8;
pub extern fn lua_pushvfstring(L: [*c]lua_State, fmt: [*c]const u8, argp: __builtin_va_list) [*c]const u8;
pub extern fn lua_pushfstring(L: [*c]lua_State, fmt: [*c]const u8, ...) [*c]const u8;
pub extern fn lua_pushcclosure(L: [*c]lua_State, @"fn": lua_CFunction, n: c_int) void;
pub extern fn lua_pushboolean(L: [*c]lua_State, b: c_int) void;
pub extern fn lua_pushlightuserdata(L: [*c]lua_State, p: ?*anyopaque) void;
pub extern fn lua_pushthread(L: [*c]lua_State) c_int;
pub extern fn lua_getglobal(L: [*c]lua_State, name: [*c]const u8) c_int;
pub extern fn lua_gettable(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_getfield(L: [*c]lua_State, idx: c_int, k: [*c]const u8) c_int;
pub extern fn lua_geti(L: [*c]lua_State, idx: c_int, n: lua_Integer) c_int;
pub extern fn lua_rawget(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_rawgeti(L: [*c]lua_State, idx: c_int, n: lua_Integer) c_int;
pub extern fn lua_rawgetp(L: [*c]lua_State, idx: c_int, p: ?*const anyopaque) c_int;
pub extern fn lua_createtable(L: [*c]lua_State, narr: c_int, nrec: c_int) void;
pub extern fn lua_newuserdatauv(L: [*c]lua_State, sz: usize, nuvalue: c_int) ?*anyopaque;
pub extern fn lua_getmetatable(L: [*c]lua_State, objindex: c_int) c_int;
pub extern fn lua_getiuservalue(L: [*c]lua_State, idx: c_int, n: c_int) c_int;
pub extern fn lua_setglobal(L: [*c]lua_State, name: [*c]const u8) void;
pub extern fn lua_settable(L: [*c]lua_State, idx: c_int) void;
pub extern fn lua_setfield(L: [*c]lua_State, idx: c_int, k: [*c]const u8) void;
pub extern fn lua_seti(L: [*c]lua_State, idx: c_int, n: lua_Integer) void;
pub extern fn lua_rawset(L: [*c]lua_State, idx: c_int) void;
pub extern fn lua_rawseti(L: [*c]lua_State, idx: c_int, n: lua_Integer) void;
pub extern fn lua_rawsetp(L: [*c]lua_State, idx: c_int, p: ?*const anyopaque) void;
pub extern fn lua_setmetatable(L: [*c]lua_State, objindex: c_int) c_int;
pub extern fn lua_setiuservalue(L: [*c]lua_State, idx: c_int, n: c_int) c_int;
pub extern fn lua_callk(L: [*c]lua_State, nargs: c_int, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) void;
pub extern fn lua_pcallk(L: [*c]lua_State, nargs: c_int, nresults: c_int, errfunc: c_int, ctx: lua_KContext, k: lua_KFunction) c_int;
pub extern fn lua_load(L: [*c]lua_State, reader: lua_Reader, dt: ?*anyopaque, chunkname: [*c]const u8, mode: [*c]const u8) c_int;
pub extern fn lua_dump(L: [*c]lua_State, writer: lua_Writer, data: ?*anyopaque, strip: c_int) c_int;
pub export fn lua_yieldk(L: [*c]lua_State, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) callconv(.c) c_int {
    const ci: [*c]CallInfo = L.*.ci;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(!((L.*.nCcalls & @as(c_uint, 4294901760)) == @as(c_uint, @bitCast(@as(c_int, 0))))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        if (L != L.*.l_G.*.mainthread) {
            luaG_runerror(L, "attempt to yield across a C-call boundary");
        } else {
            luaG_runerror(L, "attempt to yield from outside a coroutine");
        }
    }
    L.*.status = 1;
    ci.*.u2.nyield = nresults;
    if (!((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(1))) != 0)) {
        // lua assert — no action needed
    } else {
        ci.*.u.c.k = k;
        if (k != @as(lua_KFunction, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
            ci.*.u.c.ctx = ctx;
        }
        luaD_throw(L, 1);
    }
    return 0;
}
const struct_unnamed_12 = extern struct {
    value_: Value = @import("std").mem.zeroes(Value),
    tt_: lu_byte = @import("std").mem.zeroes(lu_byte),
    delta: c_ushort = @import("std").mem.zeroes(c_ushort),
};
pub const union_StackValue = extern union {
    val: TValue,
    tbclist: struct_unnamed_12,
};
pub const StackValue = union_StackValue;
pub const StkId = [*c]StackValue;
pub export fn lua_resume(L: [*c]lua_State, from: [*c]lua_State, arg_nargs: c_int, nresults: [*c]c_int) callconv(.c) c_int {
    var nargs = arg_nargs;
    var status: c_int = undefined;
    if (@as(c_int, @bitCast(@as(c_uint, L.*.status))) == 0) {
        if (L.*.ci != (&L.*.base_ci)) return resume_error(L, "cannot resume non-suspended coroutine", nargs) else if (@divExact(@as(isize, @bitCast(@intFromPtr(L.*.top.p) -% @intFromPtr(L.*.ci.*.func.p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))))), @sizeOf(StackValue)) == @as(isize, @bitCast(@as(isize, nargs)))) return resume_error(L, "cannot resume dead coroutine", nargs);
    } else if (@as(c_int, @bitCast(@as(c_uint, L.*.status))) != 1) return resume_error(L, "cannot resume dead coroutine", nargs);
    L.*.nCcalls = if (from != null) from.*.nCcalls & @as(l_uint32, @bitCast(@as(c_int, 65535))) else @as(l_uint32, @bitCast(@as(c_int, 0)));
    if ((L.*.nCcalls & @as(l_uint32, @bitCast(@as(c_int, 65535)))) >= @as(l_uint32, @bitCast(@as(c_int, 200)))) return resume_error(L, "C stack overflow", nargs);
    L.*.nCcalls +%= 1;
    status = luaD_rawrunprotected(L, &@"resume", @as(?*anyopaque, @ptrCast(&nargs)));
    status = precover(L, status);
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(!(status > 1)) != @as(c_int, 0))), @as(c_long, @as(c_int, 1))) != 0) {
        // lua_assert — ok
    } else {
        L.*.status = @as(lu_byte, @bitCast(@as(i8, @truncate(status))));
        luaD_seterrorobj(L, status, L.*.top.p);
        L.*.ci.*.top.p = L.*.top.p;
    }
    nresults.* = if (status == 1) L.*.ci.*.u2.nyield else @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.top.p) -% @intFromPtr(L.*.ci.*.func.p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))))), @sizeOf(StackValue))))));
    return status;
}
pub extern fn lua_status(L: [*c]lua_State) c_int;
pub export fn lua_isyieldable(L: [*c]lua_State) callconv(.c) c_int {
    return @intFromBool((L.*.nCcalls & @as(c_uint, 4294901760)) == @as(c_uint, @bitCast(@as(c_int, 0))));
}
pub extern fn lua_setwarnf(L: [*c]lua_State, f: lua_WarnFunction, ud: ?*anyopaque) void;
pub extern fn lua_warning(L: [*c]lua_State, msg: [*c]const u8, tocont: c_int) void;
pub extern fn lua_gc(L: [*c]lua_State, what: c_int, ...) c_int;
pub extern fn lua_error(L: [*c]lua_State) c_int;
pub extern fn lua_next(L: [*c]lua_State, idx: c_int) c_int;
pub extern fn lua_concat(L: [*c]lua_State, n: c_int) void;
pub extern fn lua_len(L: [*c]lua_State, idx: c_int) void;
pub extern fn lua_stringtonumber(L: [*c]lua_State, s: [*c]const u8) usize;
pub extern fn lua_getallocf(L: [*c]lua_State, ud: [*c]?*anyopaque) lua_Alloc;
pub extern fn lua_setallocf(L: [*c]lua_State, f: lua_Alloc, ud: ?*anyopaque) void;
pub extern fn lua_toclose(L: [*c]lua_State, idx: c_int) void;
pub extern fn lua_closeslot(L: [*c]lua_State, idx: c_int) void;
pub extern fn lua_getstack(L: [*c]lua_State, level: c_int, ar: [*c]lua_Debug) c_int;
pub extern fn lua_getinfo(L: [*c]lua_State, what: [*c]const u8, ar: [*c]lua_Debug) c_int;
pub extern fn lua_getlocal(L: [*c]lua_State, ar: [*c]const lua_Debug, n: c_int) [*c]const u8;
pub extern fn lua_setlocal(L: [*c]lua_State, ar: [*c]const lua_Debug, n: c_int) [*c]const u8;
pub extern fn lua_getupvalue(L: [*c]lua_State, funcindex: c_int, n: c_int) [*c]const u8;
pub extern fn lua_setupvalue(L: [*c]lua_State, funcindex: c_int, n: c_int) [*c]const u8;
pub extern fn lua_upvalueid(L: [*c]lua_State, fidx: c_int, n: c_int) ?*anyopaque;
pub extern fn lua_upvaluejoin(L: [*c]lua_State, fidx1: c_int, n1: c_int, fidx2: c_int, n2: c_int) void;
pub extern fn lua_sethook(L: [*c]lua_State, func: lua_Hook, mask: c_int, count: c_int) void;
pub extern fn lua_gethook(L: [*c]lua_State) lua_Hook;
pub extern fn lua_gethookmask(L: [*c]lua_State) c_int;
pub extern fn lua_gethookcount(L: [*c]lua_State) c_int;
pub extern fn lua_setcstacklimit(L: [*c]lua_State, limit: c_uint) c_int;
pub extern var g_lua_path_default: [*c]const u8;
pub const ls_byte = i8;
pub const l_uacNumber = f64;
pub const l_uacInt = c_longlong;
pub const StkIdRel = extern union {
    p: StkId,
    offset: ptrdiff_t,
};
pub const union_UValue = extern union {
    uv: TValue,
    n: lua_Number,
    u: f64,
    s: ?*anyopaque,
    i: lua_Integer,
    l: c_long,
};
pub const UValue = union_UValue;
pub const struct_Udata = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    nuvalue: c_ushort = @import("std").mem.zeroes(c_ushort),
    len: usize = @import("std").mem.zeroes(usize),
    metatable: [*c]struct_Table = @import("std").mem.zeroes([*c]struct_Table),
    gclist: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    uv: [1]UValue = @import("std").mem.zeroes([1]UValue),
};
pub const Udata = struct_Udata;
const union_unnamed_13 = extern union {
    n: lua_Number,
    u: f64,
    s: ?*anyopaque,
    i: lua_Integer,
    l: c_long,
};
pub const struct_Udata0 = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    nuvalue: c_ushort = @import("std").mem.zeroes(c_ushort),
    len: usize = @import("std").mem.zeroes(usize),
    metatable: [*c]struct_Table = @import("std").mem.zeroes([*c]struct_Table),
    bindata: union_unnamed_13 = @import("std").mem.zeroes(union_unnamed_13),
};
pub const Udata0 = struct_Udata0;
pub const struct_Upvaldesc = extern struct {
    name: [*c]TString = @import("std").mem.zeroes([*c]TString),
    instack: lu_byte = @import("std").mem.zeroes(lu_byte),
    idx: lu_byte = @import("std").mem.zeroes(lu_byte),
    kind: lu_byte = @import("std").mem.zeroes(lu_byte),
};
pub const Upvaldesc = struct_Upvaldesc;
pub const struct_LocVar = extern struct {
    varname: [*c]TString = @import("std").mem.zeroes([*c]TString),
    startpc: c_int = @import("std").mem.zeroes(c_int),
    endpc: c_int = @import("std").mem.zeroes(c_int),
};
pub const LocVar = struct_LocVar;
pub const struct_AbsLineInfo = extern struct {
    pc: c_int = @import("std").mem.zeroes(c_int),
    line: c_int = @import("std").mem.zeroes(c_int),
};
pub const AbsLineInfo = struct_AbsLineInfo;
pub const struct_Proto = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    numparams: lu_byte = @import("std").mem.zeroes(lu_byte),
    is_vararg: lu_byte = @import("std").mem.zeroes(lu_byte),
    maxstacksize: lu_byte = @import("std").mem.zeroes(lu_byte),
    sizeupvalues: c_int = @import("std").mem.zeroes(c_int),
    sizek: c_int = @import("std").mem.zeroes(c_int),
    sizecode: c_int = @import("std").mem.zeroes(c_int),
    sizelineinfo: c_int = @import("std").mem.zeroes(c_int),
    sizep: c_int = @import("std").mem.zeroes(c_int),
    sizelocvars: c_int = @import("std").mem.zeroes(c_int),
    sizeabslineinfo: c_int = @import("std").mem.zeroes(c_int),
    linedefined: c_int = @import("std").mem.zeroes(c_int),
    lastlinedefined: c_int = @import("std").mem.zeroes(c_int),
    k: [*c]TValue = @import("std").mem.zeroes([*c]TValue),
    code: [*c]Instruction = @import("std").mem.zeroes([*c]Instruction),
    p: [*c][*c]struct_Proto = @import("std").mem.zeroes([*c][*c]struct_Proto),
    upvalues: [*c]Upvaldesc = @import("std").mem.zeroes([*c]Upvaldesc),
    lineinfo: [*c]ls_byte = @import("std").mem.zeroes([*c]ls_byte),
    abslineinfo: [*c]AbsLineInfo = @import("std").mem.zeroes([*c]AbsLineInfo),
    locvars: [*c]LocVar = @import("std").mem.zeroes([*c]LocVar),
    source: [*c]TString = @import("std").mem.zeroes([*c]TString),
    gclist: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
};
pub const Proto = struct_Proto;
pub const struct_CClosure = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    nupvalues: lu_byte = @import("std").mem.zeroes(lu_byte),
    gclist: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    f: lua_CFunction = @import("std").mem.zeroes(lua_CFunction),
    upvalue: [1]TValue = @import("std").mem.zeroes([1]TValue),
};
pub const CClosure = struct_CClosure;
pub const struct_LClosure = extern struct {
    next: [*c]struct_GCObject = @import("std").mem.zeroes([*c]struct_GCObject),
    tt: lu_byte = @import("std").mem.zeroes(lu_byte),
    marked: lu_byte = @import("std").mem.zeroes(lu_byte),
    nupvalues: lu_byte = @import("std").mem.zeroes(lu_byte),
    gclist: [*c]GCObject = @import("std").mem.zeroes([*c]GCObject),
    p: [*c]struct_Proto = @import("std").mem.zeroes([*c]struct_Proto),
    upvals: [1][*c]UpVal = @import("std").mem.zeroes([1][*c]UpVal),
};
pub const LClosure = struct_LClosure;
pub const union_Closure = extern union {
    c: CClosure,
    l: LClosure,
};
pub const Closure = union_Closure;
pub const Table = struct_Table;
pub extern fn luaO_utf8esc(buff: [*c]u8, x: c_ulong) c_int;
pub extern fn luaO_rawarith(L: [*c]lua_State, op: c_int, p1: [*c]const TValue, p2: [*c]const TValue, res: [*c]TValue) c_int;
pub extern fn luaO_arith(L: [*c]lua_State, op: c_int, p1: [*c]const TValue, p2: [*c]const TValue, res: StkId) void;
pub extern fn luaO_str2num(s: [*c]const u8, o: [*c]TValue) usize;
pub extern fn luaO_hexavalue(c: c_int) c_int;
pub extern fn luaO_tostring(L: [*c]lua_State, obj: [*c]TValue) void;
pub extern fn luaO_pushvfstring(L: [*c]lua_State, fmt: [*c]const u8, argp: __builtin_va_list) [*c]const u8;
pub extern fn luaO_pushfstring(L: [*c]lua_State, fmt: [*c]const u8, ...) [*c]const u8;
pub extern fn luaO_chunkid(out: [*c]u8, source: [*c]const u8, srclen: usize) void;
pub fn luaO_ceillog2(arg_x: c_uint) callconv(.c) c_int {
    var x = arg_x;
    x -%= 1;
    return if (x != 0) @as(c_int, 32) - __builtin_clz(x) else 0;
}
pub extern fn luaM_toobig(L: [*c]lua_State) noreturn;
pub extern fn luaM_realloc_(L: [*c]lua_State, block: ?*anyopaque, oldsize: usize, size: usize) ?*anyopaque;
pub extern fn luaM_saferealloc_(L: [*c]lua_State, block: ?*anyopaque, oldsize: usize, size: usize) ?*anyopaque;
pub extern fn luaM_free_(L: [*c]lua_State, block: ?*anyopaque, osize: usize) void;
pub extern fn luaM_growaux_(L: [*c]lua_State, block: ?*anyopaque, nelems: c_int, size: [*c]c_int, size_elem: c_int, limit: c_int, what: [*c]const u8) ?*anyopaque;
pub extern fn luaM_shrinkvector_(L: [*c]lua_State, block: ?*anyopaque, nelem: [*c]c_int, final_n: c_int, size_elem: c_int) ?*anyopaque;
pub extern fn luaM_malloc_(L: [*c]lua_State, size: usize, tag: c_int) ?*anyopaque;
pub const struct_Zio = extern struct {
    n: usize = @import("std").mem.zeroes(usize),
    p: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    reader: lua_Reader = @import("std").mem.zeroes(lua_Reader),
    data: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    L: [*c]lua_State = @import("std").mem.zeroes([*c]lua_State),
};
pub const ZIO = struct_Zio;
pub const struct_Mbuffer = extern struct {
    buffer: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    n: usize = @import("std").mem.zeroes(usize),
    buffsize: usize = @import("std").mem.zeroes(usize),
};
pub const Mbuffer = struct_Mbuffer;
pub extern fn luaZ_init(L: [*c]lua_State, z: [*c]ZIO, reader: lua_Reader, data: ?*anyopaque) void;
pub extern fn luaZ_read(z: [*c]ZIO, b: ?*anyopaque, n: usize) usize;
pub extern fn luaZ_fill(z: [*c]ZIO) c_int;
pub const TM_INDEX: c_int = 0;
pub const TM_NEWINDEX: c_int = 1;
pub const TM_GC: c_int = 2;
pub const TM_MODE: c_int = 3;
pub const TM_LEN: c_int = 4;
pub const TM_EQ: c_int = 5;
pub const TM_ADD: c_int = 6;
pub const TM_SUB: c_int = 7;
pub const TM_MUL: c_int = 8;
pub const TM_MOD: c_int = 9;
pub const TM_POW: c_int = 10;
pub const TM_DIV: c_int = 11;
pub const TM_IDIV: c_int = 12;
pub const TM_BAND: c_int = 13;
pub const TM_BOR: c_int = 14;
pub const TM_BXOR: c_int = 15;
pub const TM_SHL: c_int = 16;
pub const TM_SHR: c_int = 17;
pub const TM_UNM: c_int = 18;
pub const TM_BNOT: c_int = 19;
pub const TM_LT: c_int = 20;
pub const TM_LE: c_int = 21;
pub const TM_CONCAT: c_int = 22;
pub const TM_CALL: c_int = 23;
pub const TM_CLOSE: c_int = 24;
pub const TM_N: c_int = 25;
pub const TMS = c_uint;
pub const union_GCUnion = extern union {
    gc: GCObject,
    ts: struct_TString,
    u: struct_Udata,
    cl: union_Closure,
    h: struct_Table,
    p: struct_Proto,
    th: struct_lua_State,
    upv: struct_UpVal,
};
pub extern fn luaE_setdebt(g: [*c]global_State, debt: l_mem) void;
pub extern fn luaE_freethread(L: [*c]lua_State, L1: [*c]lua_State) void;
pub extern fn luaE_extendCI(L: [*c]lua_State) [*c]CallInfo;
pub extern fn luaE_freeCI(L: [*c]lua_State) void;
pub extern fn luaE_shrinkCI(L: [*c]lua_State) void;
pub extern fn luaE_checkcstack(L: [*c]lua_State) void;
pub extern fn luaE_incCstack(L: [*c]lua_State) void;
pub extern fn luaE_warning(L: [*c]lua_State, msg: [*c]const u8, tocont: c_int) void;
pub extern fn luaE_warnerror(L: [*c]lua_State, where: [*c]const u8) void;
pub extern fn luaE_resetthread(L: [*c]lua_State, status: c_int) c_int;
pub extern fn luaG_getfuncline(f: [*c]const Proto, pc: c_int) c_int;
pub extern fn luaG_findlocal(L: [*c]lua_State, ci: [*c]CallInfo, n: c_int, pos: [*c]StkId) [*c]const u8;
pub extern fn luaG_typeerror(L: [*c]lua_State, o: [*c]const TValue, opname: [*c]const u8) noreturn;
pub extern fn luaG_callerror(L: [*c]lua_State, o: [*c]const TValue) noreturn;
pub extern fn luaG_forerror(L: [*c]lua_State, o: [*c]const TValue, what: [*c]const u8) noreturn;
pub extern fn luaG_concaterror(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue) noreturn;
pub extern fn luaG_opinterror(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue, msg: [*c]const u8) noreturn;
pub extern fn luaG_tointerror(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue) noreturn;
pub extern fn luaG_ordererror(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue) noreturn;
pub extern fn luaG_runerror(L: [*c]lua_State, fmt: [*c]const u8, ...) noreturn;
pub extern fn luaG_addinfo(L: [*c]lua_State, msg: [*c]const u8, src: [*c]TString, line: c_int) [*c]const u8;
pub extern fn luaG_errormsg(L: [*c]lua_State) noreturn;
pub extern fn luaG_traceexec(L: [*c]lua_State, pc: [*c]const Instruction) c_int;
pub extern fn luaF_newproto(L: [*c]lua_State) [*c]Proto;
pub extern fn luaF_newCclosure(L: [*c]lua_State, nupvals: c_int) [*c]CClosure;
pub extern fn luaF_newLclosure(L: [*c]lua_State, nupvals: c_int) [*c]LClosure;
pub extern fn luaF_initupvals(L: [*c]lua_State, cl: [*c]LClosure) void;
pub extern fn luaF_findupval(L: [*c]lua_State, level: StkId) [*c]UpVal;
pub extern fn luaF_newtbcupval(L: [*c]lua_State, level: StkId) void;
pub extern fn luaF_closeupval(L: [*c]lua_State, level: StkId) void;
pub extern fn luaF_close(L: [*c]lua_State, level: StkId, status: c_int, yy: c_int) StkId;
pub extern fn luaF_unlinkupval(uv: [*c]UpVal) void;
pub extern fn luaF_freeproto(L: [*c]lua_State, f: [*c]Proto) void;
pub extern fn luaF_getlocalname(func: [*c]const Proto, local_number: c_int, pc: c_int) [*c]const u8;
pub extern fn luaC_fix(L: [*c]lua_State, o: [*c]GCObject) void;
pub extern fn luaC_freeallobjects(L: [*c]lua_State) void;
pub extern fn luaC_step(L: [*c]lua_State) void;
pub extern fn luaC_runtilstate(L: [*c]lua_State, statesmask: c_int) void;
pub extern fn luaC_fullgc(L: [*c]lua_State, isemergency: c_int) void;
pub extern fn luaC_newobj(L: [*c]lua_State, tt: c_int, sz: usize) [*c]GCObject;
pub extern fn luaC_newobjdt(L: [*c]lua_State, tt: c_int, sz: usize, offset: usize) [*c]GCObject;
pub extern fn luaC_barrier_(L: [*c]lua_State, o: [*c]GCObject, v: [*c]GCObject) void;
pub extern fn luaC_barrierback_(L: [*c]lua_State, o: [*c]GCObject) void;
pub extern fn luaC_checkfinalizer(L: [*c]lua_State, o: [*c]GCObject, mt: [*c]Table) void;
pub extern fn luaC_changemode(L: [*c]lua_State, newmode: c_int) void;
pub const iABC: c_int = 0;
pub const iABx: c_int = 1;
pub const iAsBx: c_int = 2;
pub const iAx: c_int = 3;
pub const isJ: c_int = 4;
pub const enum_OpMode = c_uint;
pub const OP_MOVE: c_int = 0;
pub const OP_LOADI: c_int = 1;
pub const OP_LOADF: c_int = 2;
pub const OP_LOADK: c_int = 3;
pub const OP_LOADKX: c_int = 4;
pub const OP_LOADFALSE: c_int = 5;
pub const OP_LFALSESKIP: c_int = 6;
pub const OP_LOADTRUE: c_int = 7;
pub const OP_LOADNIL: c_int = 8;
pub const OP_GETUPVAL: c_int = 9;
pub const OP_SETUPVAL: c_int = 10;
pub const OP_GETTABUP: c_int = 11;
pub const OP_GETTABLE: c_int = 12;
pub const OP_GETI: c_int = 13;
pub const OP_GETFIELD: c_int = 14;
pub const OP_SETTABUP: c_int = 15;
pub const OP_SETTABLE: c_int = 16;
pub const OP_SETI: c_int = 17;
pub const OP_SETFIELD: c_int = 18;
pub const OP_NEWTABLE: c_int = 19;
pub const OP_SELF: c_int = 20;
pub const OP_ADDI: c_int = 21;
pub const OP_ADDK: c_int = 22;
pub const OP_SUBK: c_int = 23;
pub const OP_MULK: c_int = 24;
pub const OP_MODK: c_int = 25;
pub const OP_POWK: c_int = 26;
pub const OP_DIVK: c_int = 27;
pub const OP_IDIVK: c_int = 28;
pub const OP_BANDK: c_int = 29;
pub const OP_BORK: c_int = 30;
pub const OP_BXORK: c_int = 31;
pub const OP_SHRI: c_int = 32;
pub const OP_SHLI: c_int = 33;
pub const OP_ADD: c_int = 34;
pub const OP_SUB: c_int = 35;
pub const OP_MUL: c_int = 36;
pub const OP_MOD: c_int = 37;
pub const OP_POW: c_int = 38;
pub const OP_DIV: c_int = 39;
pub const OP_IDIV: c_int = 40;
pub const OP_BAND: c_int = 41;
pub const OP_BOR: c_int = 42;
pub const OP_BXOR: c_int = 43;
pub const OP_SHL: c_int = 44;
pub const OP_SHR: c_int = 45;
pub const OP_MMBIN: c_int = 46;
pub const OP_MMBINI: c_int = 47;
pub const OP_MMBINK: c_int = 48;
pub const OP_UNM: c_int = 49;
pub const OP_BNOT: c_int = 50;
pub const OP_NOT: c_int = 51;
pub const OP_LEN: c_int = 52;
pub const OP_CONCAT: c_int = 53;
pub const OP_CLOSE: c_int = 54;
pub const OP_TBC: c_int = 55;
pub const OP_JMP: c_int = 56;
pub const OP_EQ: c_int = 57;
pub const OP_LT: c_int = 58;
pub const OP_LE: c_int = 59;
pub const OP_EQK: c_int = 60;
pub const OP_EQI: c_int = 61;
pub const OP_LTI: c_int = 62;
pub const OP_LEI: c_int = 63;
pub const OP_GTI: c_int = 64;
pub const OP_GEI: c_int = 65;
pub const OP_TEST: c_int = 66;
pub const OP_TESTSET: c_int = 67;
pub const OP_CALL: c_int = 68;
pub const OP_TAILCALL: c_int = 69;
pub const OP_RETURN: c_int = 70;
pub const OP_RETURN0: c_int = 71;
pub const OP_RETURN1: c_int = 72;
pub const OP_FORLOOP: c_int = 73;
pub const OP_FORPREP: c_int = 74;
pub const OP_TFORPREP: c_int = 75;
pub const OP_TFORCALL: c_int = 76;
pub const OP_TFORLOOP: c_int = 77;
pub const OP_SETLIST: c_int = 78;
pub const OP_CLOSURE: c_int = 79;
pub const OP_VARARG: c_int = 80;
pub const OP_VARARGPREP: c_int = 81;
pub const OP_EXTRAARG: c_int = 82;
pub const OpCode = c_uint;
pub extern const luaP_opmodes: [83]lu_byte;
pub const VVOID: c_int = 0;
pub const VNIL: c_int = 1;
pub const VTRUE: c_int = 2;
pub const VFALSE: c_int = 3;
pub const VK: c_int = 4;
pub const VKFLT: c_int = 5;
pub const VKINT: c_int = 6;
pub const VKSTR: c_int = 7;
pub const VNONRELOC: c_int = 8;
pub const VLOCAL: c_int = 9;
pub const VUPVAL: c_int = 10;
pub const VCONST: c_int = 11;
pub const VINDEXED: c_int = 12;
pub const VINDEXUP: c_int = 13;
pub const VINDEXI: c_int = 14;
pub const VINDEXSTR: c_int = 15;
pub const VJMP: c_int = 16;
pub const VRELOC: c_int = 17;
pub const VCALL: c_int = 18;
pub const VVARARG: c_int = 19;
pub const expkind = c_uint;
const struct_unnamed_15 = extern struct {
    idx: c_short = @import("std").mem.zeroes(c_short),
    t: lu_byte = @import("std").mem.zeroes(lu_byte),
};
const struct_unnamed_16 = extern struct {
    ridx: lu_byte = @import("std").mem.zeroes(lu_byte),
    vidx: c_ushort = @import("std").mem.zeroes(c_ushort),
};
const union_unnamed_14 = extern union {
    ival: lua_Integer,
    nval: lua_Number,
    strval: [*c]TString,
    info: c_int,
    ind: struct_unnamed_15,
    @"var": struct_unnamed_16,
};
pub const struct_expdesc = extern struct {
    k: expkind = @import("std").mem.zeroes(expkind),
    u: union_unnamed_14 = @import("std").mem.zeroes(union_unnamed_14),
    t: c_int = @import("std").mem.zeroes(c_int),
    f: c_int = @import("std").mem.zeroes(c_int),
};
pub const expdesc = struct_expdesc;
const struct_unnamed_17 = extern struct {
    value_: Value = @import("std").mem.zeroes(Value),
    tt_: lu_byte = @import("std").mem.zeroes(lu_byte),
    kind: lu_byte = @import("std").mem.zeroes(lu_byte),
    ridx: lu_byte = @import("std").mem.zeroes(lu_byte),
    pidx: c_short = @import("std").mem.zeroes(c_short),
    name: [*c]TString = @import("std").mem.zeroes([*c]TString),
};
pub const union_Vardesc = extern union {
    vd: struct_unnamed_17,
    k: TValue,
};
pub const Vardesc = union_Vardesc;
pub const struct_Labeldesc = extern struct {
    name: [*c]TString = @import("std").mem.zeroes([*c]TString),
    pc: c_int = @import("std").mem.zeroes(c_int),
    line: c_int = @import("std").mem.zeroes(c_int),
    nactvar: lu_byte = @import("std").mem.zeroes(lu_byte),
    close: lu_byte = @import("std").mem.zeroes(lu_byte),
};
pub const Labeldesc = struct_Labeldesc;
pub const struct_Labellist = extern struct {
    arr: [*c]Labeldesc = @import("std").mem.zeroes([*c]Labeldesc),
    n: c_int = @import("std").mem.zeroes(c_int),
    size: c_int = @import("std").mem.zeroes(c_int),
};
pub const Labellist = struct_Labellist;
const struct_unnamed_18 = extern struct {
    arr: [*c]Vardesc = @import("std").mem.zeroes([*c]Vardesc),
    n: c_int = @import("std").mem.zeroes(c_int),
    size: c_int = @import("std").mem.zeroes(c_int),
};
pub const struct_Dyndata = extern struct {
    actvar: struct_unnamed_18 = @import("std").mem.zeroes(struct_unnamed_18),
    gt: Labellist = @import("std").mem.zeroes(Labellist),
    label: Labellist = @import("std").mem.zeroes(Labellist),
};
pub const Dyndata = struct_Dyndata;
pub const struct_BlockCnt = opaque {};
pub const struct_LexState_19 = opaque {};
pub const struct_FuncState = extern struct {
    f: [*c]Proto = @import("std").mem.zeroes([*c]Proto),
    prev: [*c]struct_FuncState = @import("std").mem.zeroes([*c]struct_FuncState),
    ls: ?*struct_LexState_19 = @import("std").mem.zeroes(?*struct_LexState_19),
    bl: ?*struct_BlockCnt = @import("std").mem.zeroes(?*struct_BlockCnt),
    pc: c_int = @import("std").mem.zeroes(c_int),
    lasttarget: c_int = @import("std").mem.zeroes(c_int),
    previousline: c_int = @import("std").mem.zeroes(c_int),
    nk: c_int = @import("std").mem.zeroes(c_int),
    np: c_int = @import("std").mem.zeroes(c_int),
    nabslineinfo: c_int = @import("std").mem.zeroes(c_int),
    firstlocal: c_int = @import("std").mem.zeroes(c_int),
    firstlabel: c_int = @import("std").mem.zeroes(c_int),
    ndebugvars: c_short = @import("std").mem.zeroes(c_short),
    nactvar: lu_byte = @import("std").mem.zeroes(lu_byte),
    nups: lu_byte = @import("std").mem.zeroes(lu_byte),
    freereg: lu_byte = @import("std").mem.zeroes(lu_byte),
    iwthabs: lu_byte = @import("std").mem.zeroes(lu_byte),
    needclose: lu_byte = @import("std").mem.zeroes(lu_byte),
};
pub const FuncState = struct_FuncState;
pub extern fn luaY_nvarstack(fs: [*c]FuncState) c_int;
pub extern fn luaY_parser(L: [*c]lua_State, z: [*c]ZIO, buff: [*c]Mbuffer, dyd: [*c]Dyndata, name: [*c]const u8, firstchar: c_int) [*c]LClosure;
pub extern fn luaS_hash(str: [*c]const u8, l: usize, seed: c_uint) c_uint;
pub extern fn luaS_hashlongstr(ts: [*c]TString) c_uint;
pub extern fn luaS_eqlngstr(a: [*c]TString, b: [*c]TString) c_int;
pub extern fn luaS_resize(L: [*c]lua_State, newsize: c_int) void;
pub extern fn luaS_clearcache(g: [*c]global_State) void;
pub extern fn luaS_init(L: [*c]lua_State) void;
pub extern fn luaS_remove(L: [*c]lua_State, ts: [*c]TString) void;
pub extern fn luaS_newudata(L: [*c]lua_State, s: usize, nuvalue: c_int) [*c]Udata;
pub extern fn luaS_newlstr(L: [*c]lua_State, str: [*c]const u8, l: usize) [*c]TString;
pub extern fn luaS_new(L: [*c]lua_State, str: [*c]const u8) [*c]TString;
pub extern fn luaS_createlngstrobj(L: [*c]lua_State, l: usize) [*c]TString;
pub extern fn luaH_getint(t: [*c]Table, key: lua_Integer) [*c]const TValue;
pub extern fn luaH_setint(L: [*c]lua_State, t: [*c]Table, key: lua_Integer, value: [*c]TValue) void;
pub extern fn luaH_getshortstr(t: [*c]Table, key: [*c]TString) [*c]const TValue;
pub extern fn luaH_getstr(t: [*c]Table, key: [*c]TString) [*c]const TValue;
pub extern fn luaH_get(t: [*c]Table, key: [*c]const TValue) [*c]const TValue;
pub extern fn luaH_newkey(L: [*c]lua_State, t: [*c]Table, key: [*c]const TValue, value: [*c]TValue) void;
pub extern fn luaH_set(L: [*c]lua_State, t: [*c]Table, key: [*c]const TValue, value: [*c]TValue) void;
pub extern fn luaH_finishset(L: [*c]lua_State, t: [*c]Table, key: [*c]const TValue, slot: [*c]const TValue, value: [*c]TValue) void;
pub extern fn luaH_new(L: [*c]lua_State) [*c]Table;
pub extern fn luaH_resize(L: [*c]lua_State, t: [*c]Table, nasize: c_uint, nhsize: c_uint) void;
pub extern fn luaH_resizearray(L: [*c]lua_State, t: [*c]Table, nasize: c_uint) void;
pub extern fn luaH_free(L: [*c]lua_State, t: [*c]Table) void;
pub extern fn luaH_next(L: [*c]lua_State, t: [*c]Table, key: StkId) c_int;
pub extern fn luaH_getn(t: [*c]Table) lua_Unsigned;
pub extern fn luaH_realasize(t: [*c]const Table) c_uint;
pub extern const luaT_typenames_: [12][*c]const u8;
pub extern fn luaT_objtypename(L: [*c]lua_State, o: [*c]const TValue) [*c]const u8;
pub extern fn luaT_gettm(events: [*c]Table, event: TMS, ename: [*c]TString) [*c]const TValue;
pub extern fn luaT_gettmbyobj(L: [*c]lua_State, o: [*c]const TValue, event: TMS) [*c]const TValue;
pub extern fn luaT_init(L: [*c]lua_State) void;
pub extern fn luaT_callTM(L: [*c]lua_State, f: [*c]const TValue, p1: [*c]const TValue, p2: [*c]const TValue, p3: [*c]const TValue) void;
pub extern fn luaT_callTMres(L: [*c]lua_State, f: [*c]const TValue, p1: [*c]const TValue, p2: [*c]const TValue, p3: StkId) void;
pub extern fn luaT_trybinTM(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue, res: StkId, event: TMS) void;
pub extern fn luaT_tryconcatTM(L: [*c]lua_State) void;
pub extern fn luaT_trybinassocTM(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue, inv: c_int, res: StkId, event: TMS) void;
pub extern fn luaT_trybiniTM(L: [*c]lua_State, p1: [*c]const TValue, @"i2": lua_Integer, inv: c_int, res: StkId, event: TMS) void;
pub extern fn luaT_callorderTM(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue, event: TMS) c_int;
pub extern fn luaT_callorderiTM(L: [*c]lua_State, p1: [*c]const TValue, v2: c_int, inv: c_int, isfloat: c_int, event: TMS) c_int;
pub extern fn luaT_adjustvarargs(L: [*c]lua_State, nfixparams: c_int, ci: [*c]CallInfo, p: [*c]const Proto) void;
pub extern fn luaT_getvarargs(L: [*c]lua_State, ci: [*c]CallInfo, where: StkId, wanted: c_int) void;
pub extern fn luaU_undump(L: [*c]lua_State, Z: [*c]ZIO, name: [*c]const u8) [*c]LClosure;
pub extern fn luaU_dump(L: [*c]lua_State, f: [*c]const Proto, w: lua_Writer, data: ?*anyopaque, strip: c_int) c_int;
pub const Pfunc = ?*const fn ([*c]lua_State, ?*anyopaque) callconv(.c) void;
pub export fn luaD_seterrorobj(L: [*c]lua_State, errcode: c_int, oldtop: StkId) void {
    switch (errcode) {
        4 => {
            const io: [*c]TValue = &oldtop.*.val;
            const x_: [*c]TString = L.*.l_G.*.memerrmsg;
            io.*.value_.gc = &@as([*c]union_GCUnion, @ptrCast(@alignCast(x_))).*.gc;
            io.*.tt_ = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, x_.*.tt))) | (@as(c_int, 1) << @intCast(6))))));
        },
        5 => {
            const io: [*c]TValue = &oldtop.*.val;
            const x_: [*c]TString = luaS_newlstr(L, "error in error handling", (@sizeOf([24]u8) / @sizeOf(u8)) -% @as(usize, @bitCast(@as(isize, @as(c_int, 1)))));
            io.*.value_.gc = &@as([*c]union_GCUnion, @ptrCast(@alignCast(x_))).*.gc;
            io.*.tt_ = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, x_.*.tt))) | (@as(c_int, 1) << @intCast(6))))));
        },
        0 => {
            (&oldtop.*.val).*.tt_ = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
        },
        else => {
            const io1: [*c]TValue = &oldtop.*.val;
            const io2: [*c]const TValue = &(L.*.top.p - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).*.val;
            io1.*.value_ = io2.*.value_;
            io1.*.tt_ = io2.*.tt_;
        },
    }
    L.*.top.p = oldtop + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
}
pub const struct_SParser = extern struct {
    z: [*c]ZIO = @import("std").mem.zeroes([*c]ZIO),
    buff: Mbuffer = @import("std").mem.zeroes(Mbuffer),
    dyd: Dyndata = @import("std").mem.zeroes(Dyndata),
    mode: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    name: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
};
pub export fn luaD_protectedparser(L: [*c]lua_State, z: [*c]ZIO, name: [*c]const u8, mode: [*c]const u8) c_int {
    var p: struct_SParser = undefined;
    var status: c_int = undefined;
    L.*.nCcalls +%= @as(l_uint32, @bitCast(@as(c_int, 65536)));
    p.z = z;
    p.name = name;
    p.mode = mode;
    p.dyd.actvar.arr = null;
    p.dyd.actvar.size = 0;
    p.dyd.gt.arr = null;
    p.dyd.gt.size = 0;
    p.dyd.label.arr = null;
    p.dyd.label.size = 0;
    p.buff.buffer = null;
    p.buff.buffsize = @as(usize, @bitCast(@as(isize, @as(c_int, 0))));
    status = luaD_pcall(L, &f_parser, @as(?*anyopaque, @ptrCast(&p)), @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.top.p)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8)), L.*.errfunc);
    p.buff.buffer = @as([*c]u8, @ptrCast(@alignCast(luaM_saferealloc_(L, @as(?*anyopaque, @ptrCast(p.buff.buffer)), p.buff.buffsize *% @sizeOf(u8), @as(usize, @bitCast(@as(isize, @as(c_int, 0)))) *% @sizeOf(u8)))));
    p.buff.buffsize = @as(usize, @bitCast(@as(isize, @as(c_int, 0))));
    luaM_free_(L, @as(?*anyopaque, @ptrCast(p.dyd.actvar.arr)), @as(usize, @bitCast(@as(isize, p.dyd.actvar.size))) *% @sizeOf(Vardesc));
    luaM_free_(L, @as(?*anyopaque, @ptrCast(p.dyd.gt.arr)), @as(usize, @bitCast(@as(isize, p.dyd.gt.size))) *% @sizeOf(Labeldesc));
    luaM_free_(L, @as(?*anyopaque, @ptrCast(p.dyd.label.arr)), @as(usize, @bitCast(@as(isize, p.dyd.label.size))) *% @sizeOf(Labeldesc));
    L.*.nCcalls -%= @as(l_uint32, @bitCast(@as(c_int, 65536)));
    return status;
}
pub export fn luaD_hook(L: [*c]lua_State, event: c_int, line: c_int, ftransfer: c_int, ntransfer: c_int) void {
    const hook: lua_Hook = L.*.hook;
    if ((hook != null) and (@as(c_int, @bitCast(@as(c_uint, L.*.allowhook))) != 0)) {
        var mask: c_int = @as(c_int, 1) << @intCast(3);
        const ci: [*c]CallInfo = L.*.ci;
        const top: ptrdiff_t = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.top.p)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
        const ci_top: ptrdiff_t = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(ci.*.top.p)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
        var ar: lua_Debug = undefined;
        ar.event = event;
        ar.currentline = line;
        ar.i_ci = ci;
        if (ntransfer != 0) {
            mask |= @as(c_int, 1) << @intCast(8);
            ci.*.u2.transferinfo.ftransfer = @as(c_ushort, @bitCast(@as(c_short, @truncate(ftransfer))));
            ci.*.u2.transferinfo.ntransfer = @as(c_ushort, @bitCast(@as(c_short, @truncate(ntransfer))));
        }
        if (!((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(1))) != 0) and (L.*.top.p < ci.*.top.p)) {
            L.*.top.p = ci.*.top.p;
        }
        if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.top.p))), @sizeOf(StackValue)) <= @as(isize, @bitCast(@as(isize, @as(c_int, 20))))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
            _ = luaD_growstack(L, 20, 1);
        }
        if (ci.*.top.p < (L.*.top.p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 20))))))) {
            ci.*.top.p = L.*.top.p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 20)))));
        }
        L.*.allowhook = 0;
        ci.*.callstatus |= @as(c_ushort, @bitCast(@as(c_short, @truncate(mask))));
        hook.?(L, &ar);
        L.*.allowhook = 1;
        ci.*.top.p = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(ci_top))))));
        L.*.top.p = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(top))))));
        ci.*.callstatus &= @as(c_ushort, @bitCast(@as(c_short, @truncate(~mask))));
    }
}
pub export fn luaD_hookcall(L: [*c]lua_State, ci: [*c]CallInfo) void {
    L.*.oldpc = 0;
    if ((L.*.hookmask & (@as(c_int, 1) << @intCast(0))) != 0) {
        const event: c_int = if ((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(5))) != 0) 4 else 0;
        const p: [*c]Proto = (&@as([*c]union_GCUnion, @ptrCast(@alignCast((&ci.*.func.p.*.val).*.value_.gc))).*.cl.l).*.p;
        ci.*.u.l.savedpc += 1;
        luaD_hook(L, event, -@as(c_int, 1), 1, @as(c_int, @bitCast(@as(c_uint, p.*.numparams))));
        ci.*.u.l.savedpc -= 1;
    }
}
// Hand-translated from Lua 5.4 ldo.c — translate-c failed on `goto retry` (LabelStmtClass).
pub export fn luaD_pretailcall(arg_L: [*c]lua_State, arg_ci: [*c]CallInfo, arg_func: StkId, arg_narg1: c_int, arg_delta: c_int) c_int {
    var L = arg_L;
    _ = &L;
    var ci = arg_ci;
    _ = &ci;
    var func = arg_func;
    _ = &func;
    var narg1 = arg_narg1;
    _ = &narg1;
    var delta = arg_delta;
    _ = &delta;
    // retry loop replaces `goto retry`
    while (true) {
        const tag: c_int = @as(c_int, @bitCast(@as(c_uint, (&func.*.val).*.tt_))) & @as(c_int, 0x3F);
        switch (tag) {
            LUA_VCCL => {
                // C closure
                return precallC(L, func, LUA_MULTRET, (&@as([*c]union_GCUnion, @ptrCast(@alignCast((&func.*.val).*.value_.gc))).*.cl.c).*.f);
            },
            LUA_VLCF => {
                // light C function
                return precallC(L, func, LUA_MULTRET, (&func.*.val).*.value_.f);
            },
            LUA_VLCL => {
                // Lua function
                const p: [*c]Proto = (&@as([*c]union_GCUnion, @ptrCast(@alignCast((&func.*.val).*.value_.gc))).*.cl.l).*.p;
                const fsize: c_int = @as(c_int, @bitCast(@as(c_uint, p.*.maxstacksize)));
                const nfixparams: c_int = @as(c_int, @bitCast(@as(c_uint, p.*.numparams)));
                // checkstackGCp(L, fsize - delta, func) — inline expansion
                if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.top.p))), @sizeOf(StackValue)) <= @as(isize, @bitCast(@as(isize, fsize - delta)))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
                    var t__: ptrdiff_t = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(func)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
                    _ = &t__;
                    {
                        if (L.*.l_G.*.GCdebt > @as(l_mem, @bitCast(@as(isize, @as(c_int, 0))))) {
                            luaC_step(L);
                        }
                    }
                    _ = luaD_growstack(L, fsize - delta, @as(c_int, 1));
                    func = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(t__))))));
                }
                ci.*.func.p -= @as(usize, @bitCast(@as(isize, @intCast(delta))));
                // move down function and arguments
                {
                    var i: c_int = 0;
                    while (i < narg1) : (i += 1) {
                        // setobjs2s(L, ci->func.p + i, func + i) — inline
                        const io1: [*c]TValue = &(ci.*.func.p + @as(usize, @bitCast(@as(isize, @intCast(i))))).*.val;
                        const io2: [*c]const TValue = &(func + @as(usize, @bitCast(@as(isize, @intCast(i))))).*.val;
                        io1.*.value_ = io2.*.value_;
                        io1.*.tt_ = io2.*.tt_;
                    }
                }
                func = ci.*.func.p;
                // complete missing arguments
                {
                    var n1 = narg1;
                    while (n1 <= nfixparams) : (n1 += 1) {
                        // setnilvalue(s2v(func + n1))
                        (&(func + @as(usize, @bitCast(@as(isize, @intCast(n1))))).*.val).*.tt_ = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
                    }
                }
                ci.*.top.p = func + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1) + fsize))));
                _ = @as(c_int, 0); // lua_assert(ci->top.p <= L->stack_last.p)
                ci.*.u.l.savedpc = p.*.code;
                ci.*.callstatus |= @as(c_ushort, @bitCast(@as(c_short, @truncate(CIST_TAIL))));
                L.*.top.p = func + @as(usize, @bitCast(@as(isize, @intCast(narg1))));
                return -@as(c_int, 1);
            },
            else => {
                // not a function — try __call metamethod
                func = luaD_tryfuncTM(L, func);
                narg1 += 1;
                continue; // goto retry
            },
        }
    }
}

// Hand-translated from Lua 5.4 ldo.c — translate-c failed on `goto retry` (LabelStmtClass).
pub export fn luaD_precall(arg_L: [*c]lua_State, arg_func: StkId, arg_nresults: c_int) [*c]CallInfo {
    var L = arg_L;
    _ = &L;
    var func = arg_func;
    _ = &func;
    var nresults = arg_nresults;
    _ = &nresults;
    // retry loop replaces `goto retry`
    while (true) {
        const tag: c_int = @as(c_int, @bitCast(@as(c_uint, (&func.*.val).*.tt_))) & @as(c_int, 0x3F);
        switch (tag) {
            LUA_VCCL => {
                // C closure
                _ = precallC(L, func, nresults, (&@as([*c]union_GCUnion, @ptrCast(@alignCast((&func.*.val).*.value_.gc))).*.cl.c).*.f);
                return null;
            },
            LUA_VLCF => {
                // light C function
                _ = precallC(L, func, nresults, (&func.*.val).*.value_.f);
                return null;
            },
            LUA_VLCL => {
                // Lua function
                var ci: [*c]CallInfo = undefined;
                _ = &ci;
                const p: [*c]Proto = (&@as([*c]union_GCUnion, @ptrCast(@alignCast((&func.*.val).*.value_.gc))).*.cl.l).*.p;
                const narg: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.top.p) -% @intFromPtr(func))), @sizeOf(StackValue)))))) - @as(c_int, 1);
                const nfixparams: c_int = @as(c_int, @bitCast(@as(c_uint, p.*.numparams)));
                const fsize: c_int = @as(c_int, @bitCast(@as(c_uint, p.*.maxstacksize)));
                // checkstackGCp(L, fsize, func) — inline expansion
                if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.top.p))), @sizeOf(StackValue)) <= @as(isize, @bitCast(@as(isize, fsize)))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
                    var t__: ptrdiff_t = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(func)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
                    _ = &t__;
                    {
                        if (L.*.l_G.*.GCdebt > @as(l_mem, @bitCast(@as(isize, @as(c_int, 0))))) {
                            luaC_step(L);
                        }
                    }
                    _ = luaD_growstack(L, fsize, @as(c_int, 1));
                    func = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(t__))))));
                }
                L.*.ci = blk: {
                    const tmp = prepCallInfo(L, func, nresults, @as(c_int, 0), func + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1) + fsize)))));
                    ci = tmp;
                    break :blk tmp;
                };
                ci.*.u.l.savedpc = p.*.code;
                // complete missing arguments
                {
                    var na = narg;
                    while (na < nfixparams) : (na += 1) {
                        // setnilvalue(s2v(L->top.p++))
                        (&L.*.top.p.*.val).*.tt_ = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
                        L.*.top.p += 1;
                    }
                }
                _ = @as(c_int, 0); // lua_assert(ci->top.p <= L->stack_last.p)
                return ci;
            },
            else => {
                // not a function — try __call metamethod
                func = luaD_tryfuncTM(L, func);
                continue; // goto retry
            },
        }
    }
}
pub export fn luaD_call(L: [*c]lua_State, func: StkId, nResults: c_int) void {
    ccall(L, func, nResults, @as(l_uint32, @bitCast(@as(c_int, 1))));
}
pub export fn luaD_callnoyield(L: [*c]lua_State, func: StkId, nResults: c_int) void {
    ccall(L, func, nResults, @as(l_uint32, @bitCast(@as(c_int, 65536) | @as(c_int, 1))));
}
pub export fn luaD_tryfuncTM(L: [*c]lua_State, arg_func: StkId) StkId {
    var func = arg_func;
    var tm: [*c]const TValue = undefined;
    var p: StkId = undefined;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.top.p))), @sizeOf(StackValue)) <= @as(c_long, @as(c_int, 1))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        const t__: ptrdiff_t = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(func)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
        if (L.*.l_G.*.GCdebt > @as(l_mem, @bitCast(@as(isize, @as(c_int, 0))))) {
            luaC_step(L);
        }
        _ = luaD_growstack(L, 1, 1);
        func = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(t__))))));
    }
    tm = luaT_gettmbyobj(L, &func.*.val, @as(c_uint, @bitCast(TM_CALL)));
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((@as(c_int, @bitCast(@as(c_uint, tm.*.tt_))) & @as(c_int, 15)) == 0) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        luaG_callerror(L, &func.*.val);
    }
    p = L.*.top.p;
    while (p > func) : (p -= 1) {
        const io1: [*c]TValue = &p.*.val;
        const io2: [*c]const TValue = &(p - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).*.val;
        io1.*.value_ = io2.*.value_;
        io1.*.tt_ = io2.*.tt_;
    }
    L.*.top.p += 1;
    {
        const io1: [*c]TValue = &func.*.val;
        const io2: [*c]const TValue = tm;
        io1.*.value_ = io2.*.value_;
        io1.*.tt_ = io2.*.tt_;
    }
    return func;
}
pub const struct_CloseP = extern struct {
    level: StkId = @import("std").mem.zeroes(StkId),
    status: c_int = @import("std").mem.zeroes(c_int),
};
pub export fn luaD_closeprotected(L: [*c]lua_State, level: ptrdiff_t, arg_status: c_int) c_int {
    var status = arg_status;
    const old_ci: [*c]CallInfo = L.*.ci;
    const old_allowhooks: lu_byte = L.*.allowhook;
    while (true) {
        var pcl: struct_CloseP = undefined;
        // bug 0008: C lua's lua_resetthread (lstate.zig:1844) and close_state
        // (lstate.zig:2252) pass literal level=1 as a "close-all sentinel".
        // In C, (char*)L->stack.p + 1 is fine because the pointer is only
        // compared, never dereferenced.  Modern Zig's @ptrFromInt to StkId
        // (= [*c]StackValue, align 8) panics if the computed address isn't
        // 8-byte aligned.  Round the offset down to a StackValue boundary
        // before constructing — for the `1` sentinel this collapses to 0
        // (= L.stack.p), which still means "close all upvals at or above
        // the stack base"; for savestack-derived offsets (always a multiple
        // of @sizeOf(StackValue)) the mask is a no-op.
        const align_mask = @sizeOf(StackValue) - 1;
        const offset_bytes = @as(usize, @bitCast(@as(isize, @intCast(level)))) & ~@as(usize, align_mask);
        pcl.level = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + offset_bytes));
        pcl.status = status;
        status = luaD_rawrunprotected(L, &closepaux, @as(?*anyopaque, @ptrCast(&pcl)));
        if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(status == 0) != @as(c_int, 0))), @as(c_long, @as(c_int, 1))) != 0) return pcl.status else {
            L.*.ci = old_ci;
            L.*.allowhook = old_allowhooks;
        }
    }
    return 0;
}
pub export fn luaD_pcall(L: [*c]lua_State, func: Pfunc, u: ?*anyopaque, old_top: ptrdiff_t, ef: ptrdiff_t) c_int {
    var status: c_int = undefined;
    const old_ci: [*c]CallInfo = L.*.ci;
    const old_allowhooks: lu_byte = L.*.allowhook;
    const old_errfunc: ptrdiff_t = L.*.errfunc;
    L.*.errfunc = ef;
    status = luaD_rawrunprotected(L, func, u);
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(status != 0) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        L.*.ci = old_ci;
        L.*.allowhook = old_allowhooks;
        status = luaD_closeprotected(L, old_top, status);
        // bug 0008: same alignment-panic risk as line 1699 above.  Round to
        // StackValue alignment so the @ptrFromInt never sees a non-aligned
        // address.  old_top is savestack-derived in all known callers, so
        // the mask is normally a no-op; this is defensive for parity with
        // the closeprotected fix.
        const align_mask_se = @sizeOf(StackValue) - 1;
        const old_top_bytes = @as(usize, @bitCast(@as(isize, @intCast(old_top)))) & ~@as(usize, align_mask_se);
        luaD_seterrorobj(L, status, @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + old_top_bytes)));
        luaD_shrinkstack(L);
    }
    L.*.errfunc = old_errfunc;
    return status;
}
pub export fn luaD_poscall(L: [*c]lua_State, ci: [*c]CallInfo, nres: c_int) void {
    const wanted: c_int = @as(c_int, @bitCast(@as(c_int, ci.*.nresults)));
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((L.*.hookmask != 0) and !(wanted < -@as(c_int, 1))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        rethook(L, ci, nres);
    }
    moveresults(L, ci.*.func.p, nres, wanted);
    L.*.ci = ci.*.previous;
}
pub export fn luaD_reallocstack(L: [*c]lua_State, newsize: c_int, raiseerror: c_int) c_int {
    const oldsize: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.stack.p))), @sizeOf(StackValue))))));
    var newstack: StkId = undefined;
    const oldgcstop: c_int = @as(c_int, @bitCast(@as(c_uint, L.*.l_G.*.gcstopem)));
    relstack(L);
    L.*.l_G.*.gcstopem = 1;
    newstack = @as([*c]StackValue, @ptrCast(@alignCast(luaM_realloc_(L, @as(?*anyopaque, @ptrCast(L.*.stack.p)), @as(usize, @bitCast(@as(isize, oldsize + @as(c_int, 5)))) *% @sizeOf(StackValue), @as(usize, @bitCast(@as(isize, newsize + @as(c_int, 5)))) *% @sizeOf(StackValue)))));
    L.*.l_G.*.gcstopem = @as(lu_byte, @bitCast(@as(i8, @truncate(oldgcstop))));
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(newstack == @as(StkId, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        correctstack(L);
        if (raiseerror != 0) {
            luaD_throw(L, 4);
        } else return 0;
    }
    L.*.stack.p = newstack;
    correctstack(L);
    L.*.stack_last.p = L.*.stack.p + @as(usize, @bitCast(@as(isize, @intCast(newsize))));
    {
        var i: c_int = oldsize + 5;
        while (i < (newsize + 5)) : (i += 1) {
            (&(newstack + @as(usize, @bitCast(@as(isize, @intCast(i))))).*.val).*.tt_ = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
        }
    }
    return 1;
}
pub export fn luaD_growstack(L: [*c]lua_State, n: c_int, raiseerror: c_int) c_int {
    const size: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.stack.p))), @sizeOf(StackValue))))));
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(size > 1000000) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        if (raiseerror != 0) {
            luaD_throw(L, 5);
        }
        return 0;
    } else if (n < 1000000) {
        var newsize: c_int = 2 * size;
        const needed: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.top.p) -% @intFromPtr(L.*.stack.p))), @sizeOf(StackValue)))))) + n;
        if (newsize > 1000000) {
            newsize = 1000000;
        }
        if (newsize < needed) {
            newsize = needed;
        }
        if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(newsize <= 1000000) != @as(c_int, 0))), @as(c_long, @as(c_int, 1))) != 0) return luaD_reallocstack(L, newsize, raiseerror);
    }
    _ = luaD_reallocstack(L, 1000000 + 200, raiseerror);
    if (raiseerror != 0) {
        luaG_runerror(L, "stack overflow");
    }
    return 0;
}
pub export fn luaD_shrinkstack(L: [*c]lua_State) void {
    const inuse: c_int = stackinuse(L);
    const max: c_int = if (inuse > @divTrunc(@as(c_int, 1000000), @as(c_int, 3))) 1000000 else inuse * 3;
    if ((inuse <= 1000000) and (@as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.stack.p))), @sizeOf(StackValue)))))) > max)) {
        const nsize: c_int = if (inuse > @divTrunc(@as(c_int, 1000000), @as(c_int, 2))) 1000000 else inuse * 2;
        _ = luaD_reallocstack(L, nsize, 0);
    }
    luaE_shrinkCI(L);
}
pub export fn luaD_inctop(L: [*c]lua_State) void {
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.top.p))), @sizeOf(StackValue)) <= @as(c_long, @as(c_int, 1))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        _ = luaD_growstack(L, 1, 1);
    }
    L.*.top.p += 1;
}
pub export fn luaD_throw(L: [*c]lua_State, arg_errcode: c_int) noreturn {
    var errcode = arg_errcode;
    if (L.*.errorJmp != null) {
        L.*.errorJmp.*.status = errcode;
        longjmp(@as([*c]c_long, @ptrCast(@alignCast(&L.*.errorJmp.*.b[@as(usize, @intCast(0))]))), 1);
    } else {
        const g: [*c]global_State = L.*.l_G;
        errcode = luaE_resetthread(L, errcode);
        if (g.*.mainthread.*.errorJmp != null) {
            {
                const io1: [*c]TValue = &(blk: {
                    const ref = &g.*.mainthread.*.top.p;
                    const tmp = ref.*;
                    ref.* += 1;
                    break :blk tmp;
                }).*.val;
                const io2: [*c]const TValue = &(L.*.top.p - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).*.val;
                io1.*.value_ = io2.*.value_;
                io1.*.tt_ = io2.*.tt_;
            }
            luaD_throw(g.*.mainthread, errcode);
        } else {
            if (g.*.panic != null) {
                _ = g.*.panic.?(L);
            }
            abort();
        }
    }
}
pub export fn luaD_rawrunprotected(arg_L: [*c]lua_State, arg_f: Pfunc, arg_ud: ?*anyopaque) c_int {
    var L = arg_L;
    _ = &L;
    var f = arg_f;
    _ = &f;
    var ud = arg_ud;
    _ = &ud;
    var oldnCcalls: l_uint32 = L.*.nCcalls;
    _ = &oldnCcalls;
    var lj: struct_lua_longjmp = undefined;
    _ = &lj;
    lj.status = 0;
    lj.previous = L.*.errorJmp;
    L.*.errorJmp = &lj;
    // Call _setjmp via inline asm — Zig optimizer doesn't know setjmp returns twice.
    // CRITICAL: declare ALL caller-saved registers as clobbers so Zig reloads
    // live values from the stack after longjmp "returns" from _setjmp.
    //
    // Indirect `blr` through a function-pointer input instead of a direct
    // `bl _setjmp`: the aarch64 SH backend's inline-asm parser (used by the
    // patched fork) does not recognise `bl <symbol>`. `blr` takes a register
    // and is supported; the linker resolves `_setjmp`'s address via the
    // extern decl at the top of this file.
    const jbuf_ptr = @intFromPtr(@as([*c]c_long, @ptrCast(@alignCast(&(&lj).*.b[@as(usize, @intCast(0))]))));
    const setjmp_fn: usize = @intFromPtr(&_setjmp);
    const sjret: c_int = asm volatile (
        \\ mov x0, %[buf]
        \\ blr %[fnp]
        : [ret] "={w0}" (-> c_int)
        : [buf] "r" (jbuf_ptr),
          [fnp] "r" (setjmp_fn),
        : .{ .x1 = true, .x2 = true, .x3 = true, .x4 = true,
             .x5 = true, .x6 = true, .x7 = true, .x8 = true,
             .x9 = true, .x10 = true, .x11 = true, .x12 = true,
             .x13 = true, .x14 = true, .x15 = true, .x16 = true,
             .x17 = true, .x18 = true, .x30 = true }
    );
    if (sjret == @as(c_int, 0)) {
        f.?(L, ud);
    }
    L.*.errorJmp = lj.previous;
    L.*.nCcalls = oldnCcalls;
    return lj.status;
}
pub const F2Ieq: c_int = 0;
pub const F2Ifloor: c_int = 1;
pub const F2Iceil: c_int = 2;
pub const F2Imod = c_uint;
pub extern fn luaV_equalobj(L: [*c]lua_State, t1: [*c]const TValue, t2: [*c]const TValue) c_int;
pub extern fn luaV_lessthan(L: [*c]lua_State, l: [*c]const TValue, r: [*c]const TValue) c_int;
pub extern fn luaV_lessequal(L: [*c]lua_State, l: [*c]const TValue, r: [*c]const TValue) c_int;
pub extern fn luaV_tonumber_(obj: [*c]const TValue, n: [*c]lua_Number) c_int;
pub extern fn luaV_tointeger(obj: [*c]const TValue, p: [*c]lua_Integer, mode: F2Imod) c_int;
pub extern fn luaV_tointegerns(obj: [*c]const TValue, p: [*c]lua_Integer, mode: F2Imod) c_int;
pub extern fn luaV_flttointeger(n: lua_Number, p: [*c]lua_Integer, mode: F2Imod) c_int;
pub extern fn luaV_finishget(L: [*c]lua_State, t: [*c]const TValue, key: [*c]TValue, val: StkId, slot: [*c]const TValue) void;
pub extern fn luaV_finishset(L: [*c]lua_State, t: [*c]const TValue, key: [*c]TValue, val: [*c]TValue, slot: [*c]const TValue) void;
pub extern fn luaV_finishOp(L: [*c]lua_State) void;
pub extern fn luaV_execute(L: [*c]lua_State, ci: [*c]CallInfo) void;
pub extern fn luaV_concat(L: [*c]lua_State, total: c_int) void;
pub extern fn luaV_idiv(L: [*c]lua_State, x: lua_Integer, y: lua_Integer) lua_Integer;
pub extern fn luaV_mod(L: [*c]lua_State, x: lua_Integer, y: lua_Integer) lua_Integer;
pub extern fn luaV_modf(L: [*c]lua_State, x: lua_Number, y: lua_Number) lua_Number;
pub extern fn luaV_shiftl(x: lua_Integer, y: lua_Integer) lua_Integer;
pub extern fn luaV_objlen(L: [*c]lua_State, ra: StkId, rb: [*c]const TValue) void;
comptime {
    // asm (".section .yoink\n\tb\t\"lua_notice\"\n\t.previous");
}
pub fn relstack(arg_L: [*c]lua_State) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var ci: [*c]CallInfo = undefined;
    _ = &ci;
    var up: [*c]UpVal = undefined;
    _ = &up;
    L.*.top.offset = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.top.p)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
    L.*.tbclist.offset = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.tbclist.p)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
    {
        up = L.*.openupval;
        while (up != @as([*c]UpVal, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) : (up = up.*.u.open.next) {
            up.*.v.offset = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(blk: {
                _ = @as(c_int, 0);
                break :blk @as(StkId, @ptrCast(@alignCast(up.*.v.p)));
            })))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
        }
    }
    {
        ci = L.*.ci;
        while (ci != @as([*c]CallInfo, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) : (ci = ci.*.previous) {
            ci.*.top.offset = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(ci.*.top.p)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
            ci.*.func.offset = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(ci.*.func.p)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
        }
    }
}
pub fn correctstack(arg_L: [*c]lua_State) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var ci: [*c]CallInfo = undefined;
    _ = &ci;
    var up: [*c]UpVal = undefined;
    _ = &up;
    L.*.top.p = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(L.*.top.offset))))));
    L.*.tbclist.p = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(L.*.tbclist.offset))))));
    {
        up = L.*.openupval;
        while (up != @as([*c]UpVal, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) : (up = up.*.u.open.next) {
            up.*.v.p = &@as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(up.*.v.offset)))))).*.val;
        }
    }
    {
        ci = L.*.ci;
        while (ci != @as([*c]CallInfo, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) : (ci = ci.*.previous) {
            ci.*.top.p = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(ci.*.top.offset))))));
            ci.*.func.p = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(ci.*.func.offset))))));
            if (!((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(1))) != 0)) {
                ci.*.u.l.trap = 1;
            }
        }
    }
}
pub fn stackinuse(arg_L: [*c]lua_State) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var ci: [*c]CallInfo = undefined;
    _ = &ci;
    var res: c_int = undefined;
    _ = &res;
    var lim: StkId = L.*.top.p;
    _ = &lim;
    {
        ci = L.*.ci;
        while (ci != @as([*c]CallInfo, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) : (ci = ci.*.previous) {
            if (lim < ci.*.top.p) {
                lim = ci.*.top.p;
            }
        }
    }
    _ = @as(c_int, 0);
    res = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(lim) -% @intFromPtr(L.*.stack.p))), @sizeOf(StackValue)))))) + @as(c_int, 1);
    if (res < @as(c_int, 20)) {
        res = 20;
    }
    return res;
}
pub fn rethook(arg_L: [*c]lua_State, arg_ci: [*c]CallInfo, arg_nres: c_int) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var ci = arg_ci;
    _ = &ci;
    var nres = arg_nres;
    _ = &nres;
    if ((L.*.hookmask & (@as(c_int, 1) << @intCast(1))) != 0) {
        var firstres: StkId = L.*.top.p - @as(usize, @bitCast(@as(isize, @intCast(nres))));
        _ = &firstres;
        var delta: c_int = 0;
        _ = &delta;
        var ftransfer: c_int = undefined;
        _ = &ftransfer;
        if (!((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(1))) != 0)) {
            var p: [*c]Proto = (blk: {
                _ = @as(c_int, 0);
                break :blk blk_1: {
                    _ = @as(c_int, 0);
                    break :blk_1 &@as([*c]union_GCUnion, @ptrCast(@alignCast((&ci.*.func.p.*.val).*.value_.gc))).*.cl.l;
                };
            }).*.p;
            _ = &p;
            if (p.*.is_vararg != 0) {
                delta = (ci.*.u.l.nextraargs + @as(c_int, @bitCast(@as(c_uint, p.*.numparams)))) + @as(c_int, 1);
            }
        }
        ci.*.func.p += @as(usize, @bitCast(@as(isize, @intCast(delta))));
        ftransfer = @as(c_int, @bitCast(@as(c_uint, @as(c_ushort, @bitCast(@as(c_short, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(firstres) -% @intFromPtr(ci.*.func.p))), @sizeOf(StackValue)))))))));
        luaD_hook(L, @as(c_int, 1), -@as(c_int, 1), ftransfer, nres);
        ci.*.func.p -= @as(usize, @bitCast(@as(isize, @intCast(delta))));
    }
    if (!((@as(c_int, @bitCast(@as(c_uint, (blk: {
        const tmp = ci.*.previous;
        ci = tmp;
        break :blk tmp;
    }).*.callstatus))) & (@as(c_int, 1) << @intCast(1))) != 0)) {
        L.*.oldpc = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(ci.*.u.l.savedpc) -% @intFromPtr((blk: {
            _ = @as(c_int, 0);
            break :blk blk_1: {
                _ = @as(c_int, 0);
                break :blk_1 &@as([*c]union_GCUnion, @ptrCast(@alignCast((&ci.*.func.p.*.val).*.value_.gc))).*.cl.l;
            };
        }).*.p.*.code))), @sizeOf(Instruction)))))) - @as(c_int, 1);
    }
}
pub fn moveresults(arg_L: [*c]lua_State, arg_res: StkId, arg_nres: c_int, arg_wanted: c_int) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var res = arg_res;
    _ = &res;
    var nres = arg_nres;
    _ = &nres;
    var wanted = arg_wanted;
    _ = &wanted;
    var firstresult: StkId = undefined;
    _ = &firstresult;
    var i: c_int = undefined;
    _ = &i;
    while (true) {
        switch (wanted) {
            @as(c_int, 0) => {
                L.*.top.p = res;
                return;
            },
            @as(c_int, 1) => {
                if (nres == @as(c_int, 0)) {
                    _ = blk: {
                        const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
                        (&res.*.val).*.tt_ = tmp;
                        break :blk tmp;
                    };
                } else {
                    var io1: [*c]TValue = &res.*.val;
                    _ = &io1;
                    var io2: [*c]const TValue = &(L.*.top.p - @as(usize, @bitCast(@as(isize, @intCast(nres))))).*.val;
                    _ = &io2;
                    io1.*.value_ = io2.*.value_;
                    _ = blk: {
                        const tmp = io2.*.tt_;
                        io1.*.tt_ = tmp;
                        break :blk tmp;
                    };
                    _ = blk: {
                        _ = &L;
                        break :blk if (!((@as(c_int, @bitCast(@as(c_uint, io1.*.tt_))) & (@as(c_int, 1) << @intCast(6))) != 0) or (((@as(c_int, @bitCast(@as(c_uint, io1.*.tt_))) & @as(c_int, 63)) == @as(c_int, @bitCast(@as(c_uint, (blk_1: {
                            _ = @as(c_int, 0);
                            break :blk_1 io1.*.value_.gc;
                        }).*.tt)))) and ((L == @as([*c]lua_State, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or !((@as(c_int, @bitCast(@as(c_uint, (blk_1: {
                            _ = @as(c_int, 0);
                            break :blk_1 io1.*.value_.gc;
                        }).*.marked))) & (@as(c_int, @bitCast(@as(c_uint, L.*.l_G.*.currentwhite))) ^ ((@as(c_int, 1) << @intCast(@as(c_int, 3))) | (@as(c_int, 1) << @intCast(@as(c_int, 4)))))) != 0)))) @as(c_int, 0) else @as(c_int, 0);
                    };
                    _ = @as(c_int, 0);
                }
                L.*.top.p = res + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))));
                return;
            },
            @as(c_int, -1) => {
                wanted = nres;
                break;
            },
            else => {
                if (wanted < -@as(c_int, 1)) {
                    L.*.ci.*.callstatus |= @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1) << @intCast(9)))));
                    L.*.ci.*.u2.nres = nres;
                    res = luaF_close(L, res, -@as(c_int, 1), @as(c_int, 1));
                    L.*.ci.*.callstatus &= @as(c_ushort, @bitCast(@as(c_short, @truncate(~(@as(c_int, 1) << @intCast(9))))));
                    if (L.*.hookmask != 0) {
                        var savedres: ptrdiff_t = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(res)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
                        _ = &savedres;
                        rethook(L, L.*.ci, nres);
                        res = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(savedres))))));
                    }
                    wanted = -wanted - @as(c_int, 3);
                    if (wanted == -@as(c_int, 1)) {
                        wanted = nres;
                    }
                }
                break;
            },
        }
        break;
    }
    firstresult = L.*.top.p - @as(usize, @bitCast(@as(isize, @intCast(nres))));
    if (nres > wanted) {
        nres = wanted;
    }
    {
        i = 0;
        while (i < nres) : (i += 1) {
            var io1: [*c]TValue = &(res + @as(usize, @bitCast(@as(isize, @intCast(i))))).*.val;
            _ = &io1;
            var io2: [*c]const TValue = &(firstresult + @as(usize, @bitCast(@as(isize, @intCast(i))))).*.val;
            _ = &io2;
            io1.*.value_ = io2.*.value_;
            _ = blk: {
                const tmp = io2.*.tt_;
                io1.*.tt_ = tmp;
                break :blk tmp;
            };
            _ = blk: {
                _ = &L;
                break :blk if (!((@as(c_int, @bitCast(@as(c_uint, io1.*.tt_))) & (@as(c_int, 1) << @intCast(6))) != 0) or (((@as(c_int, @bitCast(@as(c_uint, io1.*.tt_))) & @as(c_int, 63)) == @as(c_int, @bitCast(@as(c_uint, (blk_1: {
                    _ = @as(c_int, 0);
                    break :blk_1 io1.*.value_.gc;
                }).*.tt)))) and ((L == @as([*c]lua_State, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or !((@as(c_int, @bitCast(@as(c_uint, (blk_1: {
                    _ = @as(c_int, 0);
                    break :blk_1 io1.*.value_.gc;
                }).*.marked))) & (@as(c_int, @bitCast(@as(c_uint, L.*.l_G.*.currentwhite))) ^ ((@as(c_int, 1) << @intCast(@as(c_int, 3))) | (@as(c_int, 1) << @intCast(@as(c_int, 4)))))) != 0)))) @as(c_int, 0) else @as(c_int, 0);
            };
            _ = @as(c_int, 0);
        }
    }
    while (i < wanted) : (i += 1) {
        _ = blk: {
            const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
            (&(res + @as(usize, @bitCast(@as(isize, @intCast(i))))).*.val).*.tt_ = tmp;
            break :blk tmp;
        };
    }
    L.*.top.p = res + @as(usize, @bitCast(@as(isize, @intCast(wanted))));
}
pub fn prepCallInfo(arg_L: [*c]lua_State, arg_func: StkId, arg_nret: c_int, arg_mask: c_int, arg_top: StkId) callconv(.c) [*c]CallInfo {
    var L = arg_L;
    _ = &L;
    var func = arg_func;
    _ = &func;
    var nret = arg_nret;
    _ = &nret;
    var mask = arg_mask;
    _ = &mask;
    var top = arg_top;
    _ = &top;
    var ci: [*c]CallInfo = blk: {
        const tmp = if (L.*.ci.*.next != null) L.*.ci.*.next else luaE_extendCI(L);
        L.*.ci = tmp;
        break :blk tmp;
    };
    _ = &ci;
    ci.*.func.p = func;
    ci.*.nresults = @as(c_short, @bitCast(@as(c_short, @truncate(nret))));
    ci.*.callstatus = @as(c_ushort, @bitCast(@as(c_short, @truncate(mask))));
    ci.*.top.p = top;
    return ci;
}
pub fn precallC(arg_L: [*c]lua_State, arg_func: StkId, arg_nresults: c_int, arg_f: lua_CFunction) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var func = arg_func;
    _ = &func;
    var nresults = arg_nresults;
    _ = &nresults;
    var f = arg_f;
    _ = &f;
    var n: c_int = undefined;
    _ = &n;
    var ci: [*c]CallInfo = undefined;
    _ = &ci;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.top.p))), @sizeOf(StackValue)) <= @as(isize, @bitCast(@as(isize, @as(c_int, 20))))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        var t__: ptrdiff_t = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(func)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
        _ = &t__;
        {
            if (L.*.l_G.*.GCdebt > @as(l_mem, @bitCast(@as(isize, @as(c_int, 0))))) {
                _ = @as(c_int, 0);
                luaC_step(L);
                _ = @as(c_int, 0);
            }
            _ = @as(c_int, 0);
        }
        _ = luaD_growstack(L, @as(c_int, 20), @as(c_int, 1));
        func = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(t__))))));
    } else {
        _ = @as(c_int, 0);
    }
    L.*.ci = blk: {
        const tmp = prepCallInfo(L, func, nresults, @as(c_int, 1) << @intCast(1), L.*.top.p + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 20))))));
        ci = tmp;
        break :blk tmp;
    };
    _ = @as(c_int, 0);
    if (__builtin_expect(@as(c_long, @intFromBool((L.*.hookmask & (@as(c_int, 1) << @intCast(0))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        var narg: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.top.p) -% @intFromPtr(func))), @sizeOf(StackValue)))))) - @as(c_int, 1);
        _ = &narg;
        luaD_hook(L, @as(c_int, 0), -@as(c_int, 1), @as(c_int, 1), narg);
    }
    _ = @as(c_int, 0);
    n = f.?(L);
    _ = @as(c_int, 0);
    _ = blk: {
        _ = &L;
        break :blk @as(c_int, 0);
    };
    luaD_poscall(L, ci, n);
    return n;
}
pub fn ccall(arg_L: [*c]lua_State, arg_func: StkId, arg_nResults: c_int, arg_inc: l_uint32) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var func = arg_func;
    _ = &func;
    var nResults = arg_nResults;
    _ = &nResults;
    var inc = arg_inc;
    _ = &inc;
    var ci: [*c]CallInfo = undefined;
    _ = &ci;
    L.*.nCcalls +%= inc;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool((L.*.nCcalls & @as(l_uint32, @bitCast(@as(c_int, 65535)))) >= @as(l_uint32, @bitCast(@as(c_int, 200)))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
        if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(@divExact(@as(isize, @bitCast(@intFromPtr(L.*.stack_last.p) -% @intFromPtr(L.*.top.p))), @sizeOf(StackValue)) <= @as(c_long, @as(c_int, 0))) != @as(c_int, 0))), @as(c_long, @as(c_int, 0))) != 0) {
            var t__: ptrdiff_t = @divExact(@as(isize, @bitCast(@intFromPtr(@as([*c]u8, @ptrCast(@alignCast(func)))) -% @intFromPtr(@as([*c]u8, @ptrCast(@alignCast(L.*.stack.p)))))), @sizeOf(u8));
            _ = &t__;
            _ = luaD_growstack(L, @as(c_int, 0), @as(c_int, 1));
            func = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(t__))))));
        } else {
            _ = @as(c_int, 0);
        }
        luaE_checkcstack(L);
    }
    if ((blk: {
        const tmp = luaD_precall(L, func, nResults);
        ci = tmp;
        break :blk tmp;
    }) != @as([*c]CallInfo, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        ci.*.callstatus = @as(c_ushort, @bitCast(@as(c_short, @truncate(@as(c_int, 1) << @intCast(2)))));
        luaV_execute(L, ci);
    }
    L.*.nCcalls -%= inc;
}
pub fn finishpcallk(arg_L: [*c]lua_State, arg_ci: [*c]CallInfo) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var ci = arg_ci;
    _ = &ci;
    var status: c_int = (@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) >> @intCast(10)) & @as(c_int, 7);
    _ = &status;
    if (__builtin_expect(@as(c_long, @intFromBool(@intFromBool(status == @as(c_int, 0)) != @as(c_int, 0))), @as(c_long, @as(c_int, 1))) != 0) {
        status = 1;
    } else {
        var func: StkId = @as(StkId, @ptrFromInt(@intFromPtr(L.*.stack.p) + @as(usize, @bitCast(@as(isize, @intCast(ci.*.u2.funcidx))))));
        _ = &func;
        L.*.allowhook = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(0))))));
        func = luaF_close(L, func, status, @as(c_int, 1));
        luaD_seterrorobj(L, status, func);
        luaD_shrinkstack(L);
        _ = blk: {
            _ = @as(c_int, 0);
            break :blk blk_1: {
                const tmp = @as(c_ushort, @bitCast(@as(c_short, @truncate((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & ~(@as(c_int, 7) << @intCast(10))) | (@as(c_int, 0) << @intCast(10))))));
                ci.*.callstatus = tmp;
                break :blk_1 tmp;
            };
        };
    }
    ci.*.callstatus &= @as(c_ushort, @bitCast(@as(c_short, @truncate(~(@as(c_int, 1) << @intCast(4))))));
    L.*.errfunc = ci.*.u.c.old_errfunc;
    return status;
}
pub fn finishCcall(arg_L: [*c]lua_State, arg_ci: [*c]CallInfo) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var ci = arg_ci;
    _ = &ci;
    var n: c_int = undefined;
    _ = &n;
    if ((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(9))) != 0) {
        _ = @as(c_int, 0);
        n = ci.*.u2.nres;
    } else {
        var status: c_int = 1;
        _ = &status;
        _ = @as(c_int, 0);
        if ((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(4))) != 0) {
            status = finishpcallk(L, ci);
        }
        {
            if ((-@as(c_int, 1) <= -@as(c_int, 1)) and (L.*.ci.*.top.p < L.*.top.p)) {
                L.*.ci.*.top.p = L.*.top.p;
            }
        }
        _ = @as(c_int, 0);
        n = ci.*.u.c.k.?(L, status, ci.*.u.c.ctx);
        _ = @as(c_int, 0);
        _ = blk: {
            _ = &L;
            break :blk @as(c_int, 0);
        };
    }
    luaD_poscall(L, ci, n);
}
pub fn unroll(arg_L: [*c]lua_State, arg_ud: ?*anyopaque) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var ud = arg_ud;
    _ = &ud;
    var ci: [*c]CallInfo = undefined;
    _ = &ci;
    _ = &ud;
    while ((blk: {
        const tmp = L.*.ci;
        ci = tmp;
        break :blk tmp;
    }) != (&L.*.base_ci)) {
        if (!!((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(1))) != 0)) {
            finishCcall(L, ci);
        } else {
            luaV_finishOp(L);
            luaV_execute(L, ci);
        }
    }
}
pub fn findpcall(arg_L: [*c]lua_State) callconv(.c) [*c]CallInfo {
    var L = arg_L;
    _ = &L;
    var ci: [*c]CallInfo = undefined;
    _ = &ci;
    {
        ci = L.*.ci;
        while (ci != @as([*c]CallInfo, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) : (ci = ci.*.previous) {
            if ((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(4))) != 0) return ci;
        }
    }
    return null;
}
pub fn resume_error(arg_L: [*c]lua_State, arg_msg: [*c]const u8, arg_narg: c_int) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var msg = arg_msg;
    _ = &msg;
    var narg = arg_narg;
    _ = &narg;
    L.*.top.p -= @as(usize, @bitCast(@as(isize, @intCast(narg))));
    {
        var io: [*c]TValue = &L.*.top.p.*.val;
        _ = &io;
        var x_: [*c]TString = luaS_new(L, msg);
        _ = &x_;
        io.*.value_.gc = blk: {
            _ = @as(c_int, 0);
            break :blk &@as([*c]union_GCUnion, @ptrCast(@alignCast(x_))).*.gc;
        };
        _ = blk: {
            const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, x_.*.tt))) | (@as(c_int, 1) << @intCast(6))))));
            io.*.tt_ = tmp;
            break :blk tmp;
        };
        _ = blk: {
            _ = &L;
            break :blk if (!((@as(c_int, @bitCast(@as(c_uint, io.*.tt_))) & (@as(c_int, 1) << @intCast(6))) != 0) or (((@as(c_int, @bitCast(@as(c_uint, io.*.tt_))) & @as(c_int, 63)) == @as(c_int, @bitCast(@as(c_uint, (blk_1: {
                _ = @as(c_int, 0);
                break :blk_1 io.*.value_.gc;
            }).*.tt)))) and ((L == @as([*c]lua_State, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or !((@as(c_int, @bitCast(@as(c_uint, (blk_1: {
                _ = @as(c_int, 0);
                break :blk_1 io.*.value_.gc;
            }).*.marked))) & (@as(c_int, @bitCast(@as(c_uint, L.*.l_G.*.currentwhite))) ^ ((@as(c_int, 1) << @intCast(@as(c_int, 3))) | (@as(c_int, 1) << @intCast(@as(c_int, 4)))))) != 0)))) @as(c_int, 0) else @as(c_int, 0);
        };
    }
    {
        L.*.top.p += 1;
        _ = blk: {
            _ = &L;
            break :blk @as(c_int, 0);
        };
    }
    _ = @as(c_int, 0);
    return 2;
}
pub fn @"resume"(arg_L: [*c]lua_State, arg_ud: ?*anyopaque) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var ud = arg_ud;
    _ = &ud;
    var n: c_int = @as([*c]c_int, @ptrCast(@alignCast(ud))).*;
    _ = &n;
    var firstArg: StkId = L.*.top.p - @as(usize, @bitCast(@as(isize, @intCast(n))));
    _ = &firstArg;
    var ci: [*c]CallInfo = L.*.ci;
    _ = &ci;
    if (@as(c_int, @bitCast(@as(c_uint, L.*.status))) == @as(c_int, 0)) {
        ccall(L, firstArg - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))), -@as(c_int, 1), @as(l_uint32, @bitCast(@as(c_int, 0))));
    } else {
        _ = @as(c_int, 0);
        L.*.status = 0;
        if (!((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & (@as(c_int, 1) << @intCast(1))) != 0)) {
            L.*.top.p = firstArg;
            luaV_execute(L, ci);
        } else {
            if (ci.*.u.c.k != @as(lua_KFunction, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
                _ = @as(c_int, 0);
                n = ci.*.u.c.k.?(L, @as(c_int, 1), ci.*.u.c.ctx);
                _ = @as(c_int, 0);
                _ = blk: {
                    _ = &L;
                    break :blk @as(c_int, 0);
                };
            }
            luaD_poscall(L, ci, n);
        }
        unroll(L, @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))));
    }
}
pub fn precover(arg_L: [*c]lua_State, arg_status: c_int) callconv(.c) c_int {
    var L = arg_L;
    _ = &L;
    var status = arg_status;
    _ = &status;
    var ci: [*c]CallInfo = undefined;
    _ = &ci;
    while ((status > @as(c_int, 1)) and ((blk: {
        const tmp = findpcall(L);
        ci = tmp;
        break :blk tmp;
    }) != @as([*c]CallInfo, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))) {
        L.*.ci = ci;
        _ = blk: {
            _ = @as(c_int, 0);
            break :blk blk_1: {
                const tmp = @as(c_ushort, @bitCast(@as(c_short, @truncate((@as(c_int, @bitCast(@as(c_uint, ci.*.callstatus))) & ~(@as(c_int, 7) << @intCast(10))) | (status << @intCast(10))))));
                ci.*.callstatus = tmp;
                break :blk_1 tmp;
            };
        };
        status = luaD_rawrunprotected(L, &unroll, @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))));
    }
    return status;
}
pub fn closepaux(arg_L: [*c]lua_State, arg_ud: ?*anyopaque) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var ud = arg_ud;
    _ = &ud;
    var pcl: [*c]struct_CloseP = @as([*c]struct_CloseP, @ptrCast(@alignCast(ud)));
    _ = &pcl;
    _ = luaF_close(L, pcl.*.level, pcl.*.status, @as(c_int, 0));
}
pub fn checkmode(arg_L: [*c]lua_State, arg_mode: [*c]const u8, arg_x: [*c]const u8) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var mode = arg_mode;
    _ = &mode;
    var x = arg_x;
    _ = &x;
    if ((mode != null) and (strchr(mode, @as(c_int, @bitCast(@as(c_uint, x[@as(c_uint, @intCast(@as(c_int, 0)))])))) == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))) {
        {
            var fmtbuf: [512]u8 = undefined;
            const result = std.fmt.bufPrintZ(&fmtbuf, "attempt to load a {s} chunk (mode is '{s}')", .{
                std.mem.span(@as([*:0]const u8, @ptrCast(x))),
                std.mem.span(@as([*:0]const u8, @ptrCast(mode))),
            }) catch "attempt to load a ? chunk (mode is '?')";
            _ = lua_pushstring(L, result);
        }
        luaD_throw(L, @as(c_int, 3));
    }
}
pub fn f_parser(arg_L: [*c]lua_State, arg_ud: ?*anyopaque) callconv(.c) void {
    var L = arg_L;
    _ = &L;
    var ud = arg_ud;
    _ = &ud;
    var cl: [*c]LClosure = undefined;
    _ = &cl;
    var p: [*c]struct_SParser = @as([*c]struct_SParser, @ptrCast(@alignCast(ud)));
    _ = &p;
    var c: c_int = if ((blk: {
        const ref = &p.*.z.*.n;
        const tmp = ref.*;
        ref.* -%= 1;
        break :blk tmp;
    }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk: {
        const ref = &p.*.z.*.p;
        const tmp = ref.*;
        ref.* += 1;
        break :blk tmp;
    }).*))))) else luaZ_fill(p.*.z);
    _ = &c;
    if (c == @as(c_int, @bitCast(@as(c_uint, "\x1bLua"[@as(c_uint, @intCast(@as(c_int, 0)))])))) {
        checkmode(L, p.*.mode, "binary");
        cl = luaU_undump(L, p.*.z, p.*.name);
    } else {
        checkmode(L, p.*.mode, "text");
        cl = luaY_parser(L, p.*.z, &p.*.buff, &p.*.dyd, p.*.name, c);
    }
    _ = @as(c_int, 0);
    luaF_initupvals(L, cl);
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
pub const __COSMOPOLITAN_MAJOR__ = @as(c_int, 4);
pub const __COSMOPOLITAN_MINOR__ = @as(c_int, 0);
pub const __COSMOPOLITAN_PATCH__ = @as(c_int, 2);
pub const __COSMOPOLITAN__ = ((@import("std").zig.c_translation.promoteIntLiteral(c_int, 100000000, .decimal) * __COSMOPOLITAN_MAJOR__) + (@import("std").zig.c_translation.promoteIntLiteral(c_int, 1000000, .decimal) * __COSMOPOLITAN_MINOR__)) + __COSMOPOLITAN_PATCH__;
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
pub const NULL = @import("std").zig.c_translation.cast(?*anyopaque, @as(c_int, 0));
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
pub const vallocesque = libcesque ++ __wur ++ returnsaligned(@import("std").zig.c_translation.promoteIntLiteral(c_int, 65536, .decimal)) ++ returnspointerwithnoaliases;
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
pub const __WALL = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x40000000, .hex);
pub const __WCLONE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x80000000, .hex);
pub const SIG_ERR = @compileError("unable to translate C expr: expected ')' instead got '('");
// /src/cosmopolitan/libc/calls/calls.h:37:9
pub const SIG_DFL = @compileError("unable to translate C expr: expected ')' instead got '('");
// /src/cosmopolitan/libc/calls/calls.h:38:9
pub const SIG_IGN = @compileError("unable to translate C expr: expected ')' instead got '('");
// /src/cosmopolitan/libc/calls/calls.h:39:9
pub const CLOCKS_PER_SEC = @as(c_long, 1000000);
pub const MAP_FAILED = @import("std").zig.c_translation.cast(?*anyopaque, -@as(c_int, 1));
pub inline fn WEXITSTATUS(s: anytype) @TypeOf(s >> @as(c_int, 8)) {
    _ = &s;
    return s >> @as(c_int, 8);
}
pub inline fn WTERMSIG(s: anytype) @TypeOf(s & @as(c_int, 0x7f)) {
    _ = &s;
    return s & @as(c_int, 0x7f);
}
pub inline fn WSTOPSIG(s: anytype) @TypeOf((s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8)) {
    _ = &s;
    return (s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8);
}
pub inline fn WIFEXITED(s: anytype) @TypeOf(!(WTERMSIG(s) != 0)) {
    _ = &s;
    return !(WTERMSIG(s) != 0);
}
pub inline fn WIFSTOPPED(s: anytype) @TypeOf((s & @as(c_int, 0xff)) == @as(c_int, 0x7f)) {
    _ = &s;
    return (s & @as(c_int, 0xff)) == @as(c_int, 0x7f);
}
pub inline fn WIFSIGNALED(s: anytype) @TypeOf((@import("std").zig.c_translation.cast(i8, (s & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0)) {
    _ = &s;
    return (@import("std").zig.c_translation.cast(i8, (s & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0);
}
pub inline fn WCOREDUMP(s: anytype) @TypeOf(s & @as(c_int, 0x80)) {
    _ = &s;
    return s & @as(c_int, 0x80);
}
pub inline fn WIFCONTINUED(s: anytype) @TypeOf((s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) == @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) {
    _ = &s;
    return (s & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) == @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex);
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
pub const ARG_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 131074, .decimal);
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
pub const USHRT_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0xffffffff, .hex);
pub const ULONG_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 0xffffffffffffffff, .hex);
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
pub const UINTMAX_MIN = @import("std").zig.c_translation.cast(uintmax_t, @as(c_int, 0));
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
pub const SEM_VALUE_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const SEM_NSEMS_MAX = @as(c_int, 256);
pub const DELAYTIMER_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hex);
pub const MQ_PRIO_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 32768, .decimal);
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
pub const INVALID_CODEPOINT = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfffd, .hex);
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
    return @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0));
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
    return @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0));
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
pub inline fn GetStackPointer() ?*anyopaque {
    return @import("std").zig.c_translation.cast(?*anyopaque, @as(c_int, 0));
}
pub inline fn GetStackBottom() ?*anyopaque {
    return @import("std").zig.c_translation.cast(?*anyopaque, @as(c_int, 0));
}
pub inline fn isutf8(s: anytype, n: anytype) @TypeOf(@as(c_int, 1)) {
    _ = &s;
    _ = &n;
    return @as(c_int, 1);
}
pub inline fn rmrf(p: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &p;
    return @as(c_int, 0);
}
pub inline fn _weaken(x: anytype) ?*anyopaque {
    _ = &x;
    return @import("std").zig.c_translation.cast(?*anyopaque, @as(c_int, 0));
}
pub const ldo_c = "";
pub const LUA_CORE = "";
pub const COSMOPOLITAN_LIBC_BITS_WEAKEN_H_ = "";
pub const COSMOPOLITAN_LIBC_RUNTIME_INTERNAL_H_ = "";
pub const COSMOPOLITAN_LIBC_ELF_STRUCT_EHDR_H_ = "";
pub const COSMOPOLITAN_LIBC_ELF_SCALAR_H_ = "";
pub const Elf64_Addr = u64;
pub const Elf64_Half = u16;
pub const Elf64_Off = u64;
pub const Elf64_Section = u16;
pub const Elf64_Sword = i32;
pub const Elf64_Sxword = i64;
pub const Elf64_Versym = Elf64_Half;
pub const Elf64_Word = u32;
pub const Elf64_Xword = u64;
pub const Elf_Symndx = u32;
pub const RUNLEVEL_MALLOC = @as(c_int, 1);
pub const lapi_h = "";
pub const llimits_h = "";
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
pub const FP_ILOGB0 = -@import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const FP_ILOGBNAN = -@import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
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
pub const COSMOPOLITAN_THIRD_PARTY_LUA_LUA_H_ = "";
pub const luaconf_h = "";
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
        _ = @import("std").zig.c_translation.cast(anyopaque, L);
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
pub inline fn l_likely(x: anytype) @TypeOf(luai_likely(x)) {
    _ = &x;
    return luai_likely(x);
}
pub inline fn l_unlikely(x: anytype) @TypeOf(luai_unlikely(x)) {
    _ = &x;
    return luai_unlikely(x);
}
pub const LUAI_MAXSTACK = @import("std").zig.c_translation.promoteIntLiteral(c_int, 1000000, .decimal);
pub const LUA_EXTRASPACE = @import("std").zig.c_translation.sizeof(?*anyopaque);
pub const LUA_IDSIZE = @as(c_int, 60);
pub const LUAL_BUFFERSIZE = @import("std").zig.c_translation.cast(c_int, (@as(c_int, 16) * @import("std").zig.c_translation.sizeof(?*anyopaque)) * @import("std").zig.c_translation.sizeof(lua_Number));
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
    return @import("std").zig.c_translation.cast(?*anyopaque, @import("std").zig.c_translation.cast([*c]u8, L) - LUA_EXTRASPACE);
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
    return @import("std").zig.c_translation.cast(anyopaque, lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS));
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
pub const MAX_SIZET = @import("std").zig.c_translation.cast(usize, ~@import("std").zig.c_translation.cast(usize, @as(c_int, 0)));
pub const MAX_SIZE = if (@import("std").zig.c_translation.sizeof(usize) < @import("std").zig.c_translation.sizeof(lua_Integer)) MAX_SIZET else @import("std").zig.c_translation.cast(usize, LUA_MAXINTEGER);
pub const MAX_LUMEM = @import("std").zig.c_translation.cast(lu_mem, ~@import("std").zig.c_translation.cast(lu_mem, @as(c_int, 0)));
pub const MAX_LMEM = @import("std").zig.c_translation.cast(l_mem, MAX_LUMEM >> @as(c_int, 1));
pub const MAX_INT = INT_MAX;
pub inline fn log2maxs(t: anytype) @TypeOf((@import("std").zig.c_translation.sizeof(t) * @as(c_int, 8)) - @as(c_int, 2)) {
    _ = &t;
    return (@import("std").zig.c_translation.sizeof(t) * @as(c_int, 8)) - @as(c_int, 2);
}
pub inline fn ispow2(x: anytype) @TypeOf((x & (x - @as(c_int, 1))) == @as(c_int, 0)) {
    _ = &x;
    return (x & (x - @as(c_int, 1))) == @as(c_int, 0);
}
pub inline fn LL(x: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.div(@import("std").zig.c_translation.sizeof(x), @import("std").zig.c_translation.sizeof(u8)) - @as(c_int, 1)) {
    _ = &x;
    return @import("std").zig.c_translation.MacroArithmetic.div(@import("std").zig.c_translation.sizeof(x), @import("std").zig.c_translation.sizeof(u8)) - @as(c_int, 1);
}
pub const L_P2I = usize;
pub inline fn point2uint(p: anytype) c_uint {
    _ = &p;
    return @import("std").zig.c_translation.cast(c_uint, L_P2I(p) & UINT_MAX);
}
pub inline fn check_exp(c: anytype, e: anytype) @TypeOf(e) {
    _ = &c;
    _ = &e;
    return blk_1: {
        _ = lua_assert(c);
        break :blk_1 e;
    };
}
pub inline fn lua_longassert(c: anytype) @TypeOf(if (c != 0) @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)) else lua_assert(@as(c_int, 0))) {
    _ = &c;
    return if (c != 0) @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)) else lua_assert(@as(c_int, 0));
}
pub inline fn luai_apicheck(l: anytype, e: anytype) @TypeOf(lua_assert(e)) {
    _ = &l;
    _ = &e;
    return blk_1: {
        _ = @import("std").zig.c_translation.cast(anyopaque, l);
        break :blk_1 lua_assert(e);
    };
}
pub inline fn api_check(l: anytype, e: anytype, msg: anytype) @TypeOf(luai_apicheck(l, (e != 0) and (msg != 0))) {
    _ = &l;
    _ = &e;
    _ = &msg;
    return luai_apicheck(l, (e != 0) and (msg != 0));
}
pub const UNUSED = @import("std").zig.c_translation.Macros.DISCARD;
pub const cast = @import("std").zig.c_translation.Macros.CAST_OR_CALL;
pub inline fn cast_void(i: anytype) @TypeOf(cast(anyopaque, i)) {
    _ = &i;
    return cast(anyopaque, i);
}
pub inline fn cast_voidp(i: anytype) @TypeOf(cast(?*anyopaque, i)) {
    _ = &i;
    return cast(?*anyopaque, i);
}
pub inline fn cast_num(i: anytype) @TypeOf(cast(lua_Number, i)) {
    _ = &i;
    return cast(lua_Number, i);
}
pub inline fn cast_int(i: anytype) @TypeOf(cast(c_int, i)) {
    _ = &i;
    return cast(c_int, i);
}
pub inline fn cast_uint(i: anytype) @TypeOf(cast(c_uint, i)) {
    _ = &i;
    return cast(c_uint, i);
}
pub inline fn cast_byte(i: anytype) @TypeOf(cast(lu_byte, i)) {
    _ = &i;
    return cast(lu_byte, i);
}
pub inline fn cast_uchar(i: anytype) @TypeOf(cast(u8, i)) {
    _ = &i;
    return cast(u8, i);
}
pub inline fn cast_char(i: anytype) @TypeOf(cast(u8, i)) {
    _ = &i;
    return cast(u8, i);
}
pub inline fn cast_charp(i: anytype) @TypeOf(cast([*c]u8, i)) {
    _ = &i;
    return cast([*c]u8, i);
}
pub inline fn cast_sizet(i: anytype) @TypeOf(cast(usize, i)) {
    _ = &i;
    return cast(usize, i);
}
pub inline fn l_castS2U(i: anytype) lua_Unsigned {
    _ = &i;
    return @import("std").zig.c_translation.cast(lua_Unsigned, i);
}
pub inline fn l_castU2S(i: anytype) lua_Integer {
    _ = &i;
    return @import("std").zig.c_translation.cast(lua_Integer, i);
}
pub const l_noret = @compileError("unable to translate macro: undefined identifier `noreturn`");
// /src/cosmopolitan/third_party/lua/llimits.h:161:9
pub const l_inline = @compileError("unable to translate C expr: unexpected token 'inline'");
// /src/cosmopolitan/third_party/lua/llimits.h:175:9
pub const l_sinline = @compileError("unable to translate C expr: unexpected token 'static'");
// /src/cosmopolitan/third_party/lua/llimits.h:182:9
pub const LUAI_MAXSHORTLEN = @as(c_int, 40);
pub const MINSTRTABSIZE = @as(c_int, 128);
pub const STRCACHE_N = @as(c_int, 53);
pub const STRCACHE_M = @as(c_int, 2);
pub const LUA_MINBUFFER = @as(c_int, 32);
pub const LUAI_MAXCCALLS = @as(c_int, 200);
pub inline fn lua_lock(L: anytype) anyopaque {
    _ = &L;
    return @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0));
}
pub inline fn lua_unlock(L: anytype) anyopaque {
    _ = &L;
    return @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0));
}
pub const luai_threadyield = @compileError("unable to translate C expr: unexpected token '{'");
// /src/cosmopolitan/third_party/lua/llimits.h:263:9
pub inline fn luai_userstateopen(L: anytype) anyopaque {
    _ = &L;
    return @import("std").zig.c_translation.cast(anyopaque, L);
}
pub inline fn luai_userstateclose(L: anytype) anyopaque {
    _ = &L;
    return @import("std").zig.c_translation.cast(anyopaque, L);
}
pub inline fn luai_userstatethread(L: anytype, L1: anytype) anyopaque {
    _ = &L;
    _ = &L1;
    return @import("std").zig.c_translation.cast(anyopaque, L);
}
pub inline fn luai_userstatefree(L: anytype, L1: anytype) anyopaque {
    _ = &L;
    _ = &L1;
    return @import("std").zig.c_translation.cast(anyopaque, L);
}
pub inline fn luai_userstateresume(L: anytype, n: anytype) anyopaque {
    _ = &L;
    _ = &n;
    return @import("std").zig.c_translation.cast(anyopaque, L);
}
pub inline fn luai_userstateyield(L: anytype, n: anytype) anyopaque {
    _ = &L;
    _ = &n;
    return @import("std").zig.c_translation.cast(anyopaque, L);
}
pub inline fn luai_numidiv(L: anytype, a: anytype, b: anytype) @TypeOf(l_floor(luai_numdiv(L, a, b))) {
    _ = &L;
    _ = &a;
    _ = &b;
    return blk_1: {
        _ = @import("std").zig.c_translation.cast(anyopaque, L);
        break :blk_1 l_floor(luai_numdiv(L, a, b));
    };
}
pub inline fn luai_numdiv(L: anytype, a: anytype, b: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.div(a, b)) {
    _ = &L;
    _ = &a;
    _ = &b;
    return @import("std").zig.c_translation.MacroArithmetic.div(a, b);
}
pub const luai_nummod = @compileError("unable to translate C expr: unexpected token '{'");
// /src/cosmopolitan/third_party/lua/llimits.h:323:9
pub inline fn luai_numpow(L: anytype, a: anytype, b: anytype) @TypeOf(if (b == @as(c_int, 2)) a * a else l_mathop(pow)(a, b)) {
    _ = &L;
    _ = &a;
    _ = &b;
    return blk_1: {
        _ = @import("std").zig.c_translation.cast(anyopaque, L);
        break :blk_1 if (b == @as(c_int, 2)) a * a else l_mathop(pow)(a, b);
    };
}
pub inline fn luai_numadd(L: anytype, a: anytype, b: anytype) @TypeOf(a + b) {
    _ = &L;
    _ = &a;
    _ = &b;
    return a + b;
}
pub inline fn luai_numsub(L: anytype, a: anytype, b: anytype) @TypeOf(a - b) {
    _ = &L;
    _ = &a;
    _ = &b;
    return a - b;
}
pub inline fn luai_nummul(L: anytype, a: anytype, b: anytype) @TypeOf(a * b) {
    _ = &L;
    _ = &a;
    _ = &b;
    return a * b;
}
pub inline fn luai_numunm(L: anytype, a: anytype) @TypeOf(-a) {
    _ = &L;
    _ = &a;
    return -a;
}
pub inline fn luai_numeq(a: anytype, b: anytype) @TypeOf(a == b) {
    _ = &a;
    _ = &b;
    return a == b;
}
pub inline fn luai_numlt(a: anytype, b: anytype) @TypeOf(a < b) {
    _ = &a;
    _ = &b;
    return a < b;
}
pub inline fn luai_numle(a: anytype, b: anytype) @TypeOf(a <= b) {
    _ = &a;
    _ = &b;
    return a <= b;
}
pub inline fn luai_numgt(a: anytype, b: anytype) @TypeOf(a > b) {
    _ = &a;
    _ = &b;
    return a > b;
}
pub inline fn luai_numge(a: anytype, b: anytype) @TypeOf(a >= b) {
    _ = &a;
    _ = &b;
    return a >= b;
}
pub inline fn luai_numisnan(a: anytype) @TypeOf(!(luai_numeq(a, a) != 0)) {
    _ = &a;
    return !(luai_numeq(a, a) != 0);
}
pub inline fn condmovestack(L: anytype, pre: anytype, pos: anytype) anyopaque {
    _ = &L;
    _ = &pre;
    _ = &pos;
    return @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0));
}
pub inline fn condchangemem(L: anytype, pre: anytype, pos: anytype) anyopaque {
    _ = &L;
    _ = &pre;
    _ = &pos;
    return @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0));
}
pub const lstate_h = "";
pub const lobject_h = "";
pub const LUA_TUPVAL = LUA_NUMTYPES;
pub const LUA_TPROTO = LUA_NUMTYPES + @as(c_int, 1);
pub const LUA_TDEADKEY = LUA_NUMTYPES + @as(c_int, 2);
pub const LUA_TOTALTYPES = LUA_TPROTO + @as(c_int, 2);
pub inline fn makevariant(t: anytype, v: anytype) @TypeOf(t | (v << @as(c_int, 4))) {
    _ = &t;
    _ = &v;
    return t | (v << @as(c_int, 4));
}
pub const TValuefields = @compileError("unable to translate macro: undefined identifier `value_`");
// /src/cosmopolitan/third_party/lua/lobject.h:55:9
pub inline fn val_(o: anytype) @TypeOf(o.*.value_) {
    _ = &o;
    return o.*.value_;
}
pub inline fn valraw(o: anytype) @TypeOf(val_(o)) {
    _ = &o;
    return val_(o);
}
pub inline fn rawtt(o: anytype) @TypeOf(o.*.tt_) {
    _ = &o;
    return o.*.tt_;
}
pub inline fn novariant(t: anytype) @TypeOf(t & @as(c_int, 0x0F)) {
    _ = &t;
    return t & @as(c_int, 0x0F);
}
pub inline fn withvariant(t: anytype) @TypeOf(t & @as(c_int, 0x3F)) {
    _ = &t;
    return t & @as(c_int, 0x3F);
}
pub inline fn ttypetag(o: anytype) @TypeOf(withvariant(rawtt(o))) {
    _ = &o;
    return withvariant(rawtt(o));
}
pub inline fn ttype(o: anytype) @TypeOf(novariant(rawtt(o))) {
    _ = &o;
    return novariant(rawtt(o));
}
pub inline fn checktag(o: anytype, t: anytype) @TypeOf(rawtt(o) == t) {
    _ = &o;
    _ = &t;
    return rawtt(o) == t;
}
pub inline fn checktype(o: anytype, t: anytype) @TypeOf(ttype(o) == t) {
    _ = &o;
    _ = &t;
    return ttype(o) == t;
}
pub inline fn righttt(obj: anytype) @TypeOf(ttypetag(obj) == gcvalue(obj).*.tt) {
    _ = &obj;
    return ttypetag(obj) == gcvalue(obj).*.tt;
}
pub inline fn checkliveness(L: anytype, obj: anytype) @TypeOf(lua_longassert(!(iscollectable(obj) != 0) or ((righttt(obj) != 0) and ((L == NULL) or !(isdead(G(L), gcvalue(obj)) != 0))))) {
    _ = &L;
    _ = &obj;
    return blk_1: {
        _ = @import("std").zig.c_translation.cast(anyopaque, L);
        break :blk_1 lua_longassert(!(iscollectable(obj) != 0) or ((righttt(obj) != 0) and ((L == NULL) or !(isdead(G(L), gcvalue(obj)) != 0))));
    };
}
pub const settt_ = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lobject.h:104:9
pub const setobj = @compileError("unable to translate macro: undefined identifier `io1`");
// /src/cosmopolitan/third_party/lua/lobject.h:108:9
pub inline fn setobjs2s(L: anytype, o1: anytype, o2: anytype) @TypeOf(setobj(L, s2v(o1), s2v(o2))) {
    _ = &L;
    _ = &o1;
    _ = &o2;
    return setobj(L, s2v(o1), s2v(o2));
}
pub inline fn setobj2s(L: anytype, o1: anytype, o2: anytype) @TypeOf(setobj(L, s2v(o1), o2)) {
    _ = &L;
    _ = &o1;
    _ = &o2;
    return setobj(L, s2v(o1), o2);
}
pub const setobjt2t = setobj;
pub const setobj2n = setobj;
pub const setobj2t = setobj;
pub inline fn s2v(o: anytype) @TypeOf(&o.*.val) {
    _ = &o;
    return &o.*.val;
}
pub const LUA_VNIL = makevariant(LUA_TNIL, @as(c_int, 0));
pub const LUA_VEMPTY = makevariant(LUA_TNIL, @as(c_int, 1));
pub const LUA_VABSTKEY = makevariant(LUA_TNIL, @as(c_int, 2));
pub inline fn ttisnil(v: anytype) @TypeOf(checktype(v, LUA_TNIL)) {
    _ = &v;
    return checktype(v, LUA_TNIL);
}
pub inline fn ttisstrictnil(o: anytype) @TypeOf(checktag(o, LUA_VNIL)) {
    _ = &o;
    return checktag(o, LUA_VNIL);
}
pub inline fn setnilvalue(obj: anytype) @TypeOf(settt_(obj, LUA_VNIL)) {
    _ = &obj;
    return settt_(obj, LUA_VNIL);
}
pub inline fn isabstkey(v: anytype) @TypeOf(checktag(v, LUA_VABSTKEY)) {
    _ = &v;
    return checktag(v, LUA_VABSTKEY);
}
pub inline fn isnonstrictnil(v: anytype) @TypeOf((ttisnil(v) != 0) and !(ttisstrictnil(v) != 0)) {
    _ = &v;
    return (ttisnil(v) != 0) and !(ttisstrictnil(v) != 0);
}
pub inline fn isempty(v: anytype) @TypeOf(ttisnil(v)) {
    _ = &v;
    return ttisnil(v);
}
pub const ABSTKEYCONSTANT = @compileError("unable to translate C expr: unexpected token '{'");
// /src/cosmopolitan/third_party/lua/lobject.h:211:9
pub inline fn setempty(v: anytype) @TypeOf(settt_(v, LUA_VEMPTY)) {
    _ = &v;
    return settt_(v, LUA_VEMPTY);
}
pub const LUA_VFALSE = makevariant(LUA_TBOOLEAN, @as(c_int, 0));
pub const LUA_VTRUE = makevariant(LUA_TBOOLEAN, @as(c_int, 1));
pub inline fn ttisboolean(o: anytype) @TypeOf(checktype(o, LUA_TBOOLEAN)) {
    _ = &o;
    return checktype(o, LUA_TBOOLEAN);
}
pub inline fn ttisfalse(o: anytype) @TypeOf(checktag(o, LUA_VFALSE)) {
    _ = &o;
    return checktag(o, LUA_VFALSE);
}
pub inline fn ttistrue(o: anytype) @TypeOf(checktag(o, LUA_VTRUE)) {
    _ = &o;
    return checktag(o, LUA_VTRUE);
}
pub inline fn l_isfalse(o: anytype) @TypeOf((ttisfalse(o) != 0) or (ttisnil(o) != 0)) {
    _ = &o;
    return (ttisfalse(o) != 0) or (ttisnil(o) != 0);
}
pub inline fn setbfvalue(obj: anytype) @TypeOf(settt_(obj, LUA_VFALSE)) {
    _ = &obj;
    return settt_(obj, LUA_VFALSE);
}
pub inline fn setbtvalue(obj: anytype) @TypeOf(settt_(obj, LUA_VTRUE)) {
    _ = &obj;
    return settt_(obj, LUA_VTRUE);
}
pub const LUA_VTHREAD = makevariant(LUA_TTHREAD, @as(c_int, 0));
pub inline fn ttisthread(o: anytype) @TypeOf(checktag(o, ctb(LUA_VTHREAD))) {
    _ = &o;
    return checktag(o, ctb(LUA_VTHREAD));
}
pub inline fn thvalue(o: anytype) @TypeOf(check_exp(ttisthread(o), gco2th(val_(o).gc))) {
    _ = &o;
    return check_exp(ttisthread(o), gco2th(val_(o).gc));
}
pub const setthvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:258:9
pub inline fn setthvalue2s(L: anytype, o: anytype, t: anytype) @TypeOf(setthvalue(L, s2v(o), t)) {
    _ = &L;
    _ = &o;
    _ = &t;
    return setthvalue(L, s2v(o), t);
}
pub const CommonHeader = @compileError("unable to translate macro: undefined identifier `next`");
// /src/cosmopolitan/third_party/lua/lobject.h:278:9
pub const BIT_ISCOLLECTABLE = @as(c_int, 1) << @as(c_int, 6);
pub inline fn iscollectable(o: anytype) @TypeOf(rawtt(o) & BIT_ISCOLLECTABLE) {
    _ = &o;
    return rawtt(o) & BIT_ISCOLLECTABLE;
}
pub inline fn ctb(t: anytype) @TypeOf(t | BIT_ISCOLLECTABLE) {
    _ = &t;
    return t | BIT_ISCOLLECTABLE;
}
pub inline fn gcvalue(o: anytype) @TypeOf(check_exp(iscollectable(o), val_(o).gc)) {
    _ = &o;
    return check_exp(iscollectable(o), val_(o).gc);
}
pub inline fn gcvalueraw(v: anytype) @TypeOf(v.gc) {
    _ = &v;
    return v.gc;
}
pub const setgcovalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:299:9
pub const LUA_VNUMINT = makevariant(LUA_TNUMBER, @as(c_int, 0));
pub const LUA_VNUMFLT = makevariant(LUA_TNUMBER, @as(c_int, 1));
pub inline fn ttisnumber(o: anytype) @TypeOf(checktype(o, LUA_TNUMBER)) {
    _ = &o;
    return checktype(o, LUA_TNUMBER);
}
pub inline fn ttisfloat(o: anytype) @TypeOf(checktag(o, LUA_VNUMFLT)) {
    _ = &o;
    return checktag(o, LUA_VNUMFLT);
}
pub inline fn ttisinteger(o: anytype) @TypeOf(checktag(o, LUA_VNUMINT)) {
    _ = &o;
    return checktag(o, LUA_VNUMINT);
}
pub inline fn nvalue(o: anytype) @TypeOf(check_exp(ttisnumber(o), if (ttisinteger(o) != 0) cast_num(ivalue(o)) else fltvalue(o))) {
    _ = &o;
    return check_exp(ttisnumber(o), if (ttisinteger(o) != 0) cast_num(ivalue(o)) else fltvalue(o));
}
pub inline fn fltvalue(o: anytype) @TypeOf(check_exp(ttisfloat(o), val_(o).n)) {
    _ = &o;
    return check_exp(ttisfloat(o), val_(o).n);
}
pub inline fn ivalue(o: anytype) @TypeOf(check_exp(ttisinteger(o), val_(o).i)) {
    _ = &o;
    return check_exp(ttisinteger(o), val_(o).i);
}
pub inline fn fltvalueraw(v: anytype) @TypeOf(v.n) {
    _ = &v;
    return v.n;
}
pub inline fn ivalueraw(v: anytype) @TypeOf(v.i) {
    _ = &v;
    return v.i;
}
pub const setfltvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:328:9
pub const chgfltvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:331:9
pub const setivalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:334:9
pub const chgivalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:337:9
pub const LUA_VSHRSTR = makevariant(LUA_TSTRING, @as(c_int, 0));
pub const LUA_VLNGSTR = makevariant(LUA_TSTRING, @as(c_int, 1));
pub inline fn ttisstring(o: anytype) @TypeOf(checktype(o, LUA_TSTRING)) {
    _ = &o;
    return checktype(o, LUA_TSTRING);
}
pub inline fn ttisshrstring(o: anytype) @TypeOf(checktag(o, ctb(LUA_VSHRSTR))) {
    _ = &o;
    return checktag(o, ctb(LUA_VSHRSTR));
}
pub inline fn ttislngstring(o: anytype) @TypeOf(checktag(o, ctb(LUA_VLNGSTR))) {
    _ = &o;
    return checktag(o, ctb(LUA_VLNGSTR));
}
pub inline fn tsvalueraw(v: anytype) @TypeOf(gco2ts(v.gc)) {
    _ = &v;
    return gco2ts(v.gc);
}
pub inline fn tsvalue(o: anytype) @TypeOf(check_exp(ttisstring(o), gco2ts(val_(o).gc))) {
    _ = &o;
    return check_exp(ttisstring(o), gco2ts(val_(o).gc));
}
pub const setsvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:361:9
pub inline fn setsvalue2s(L: anytype, o: anytype, s: anytype) @TypeOf(setsvalue(L, s2v(o), s)) {
    _ = &L;
    _ = &o;
    _ = &s;
    return setsvalue(L, s2v(o), s);
}
pub const setsvalue2n = setsvalue;
pub inline fn getstr(ts: anytype) @TypeOf(ts.*.contents) {
    _ = &ts;
    return ts.*.contents;
}
pub inline fn svalue(o: anytype) @TypeOf(getstr(tsvalue(o))) {
    _ = &o;
    return getstr(tsvalue(o));
}
pub inline fn tsslen(s: anytype) @TypeOf(if (s.*.tt == LUA_VSHRSTR) s.*.shrlen else s.*.u.lnglen) {
    _ = &s;
    return if (s.*.tt == LUA_VSHRSTR) s.*.shrlen else s.*.u.lnglen;
}
pub inline fn vslen(o: anytype) @TypeOf(tsslen(tsvalue(o))) {
    _ = &o;
    return tsslen(tsvalue(o));
}
pub const LUA_VLIGHTUSERDATA = makevariant(LUA_TLIGHTUSERDATA, @as(c_int, 0));
pub const LUA_VUSERDATA = makevariant(LUA_TUSERDATA, @as(c_int, 0));
pub inline fn ttislightuserdata(o: anytype) @TypeOf(checktag(o, LUA_VLIGHTUSERDATA)) {
    _ = &o;
    return checktag(o, LUA_VLIGHTUSERDATA);
}
pub inline fn ttisfulluserdata(o: anytype) @TypeOf(checktag(o, ctb(LUA_VUSERDATA))) {
    _ = &o;
    return checktag(o, ctb(LUA_VUSERDATA));
}
pub inline fn pvalue(o: anytype) @TypeOf(check_exp(ttislightuserdata(o), val_(o).p)) {
    _ = &o;
    return check_exp(ttislightuserdata(o), val_(o).p);
}
pub inline fn uvalue(o: anytype) @TypeOf(check_exp(ttisfulluserdata(o), gco2u(val_(o).gc))) {
    _ = &o;
    return check_exp(ttisfulluserdata(o), gco2u(val_(o).gc));
}
pub inline fn pvalueraw(v: anytype) @TypeOf(v.p) {
    _ = &v;
    return v.p;
}
pub const setpvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:431:9
pub const setuvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:434:9
pub const udatamemoffset = @compileError("unable to translate macro: undefined identifier `bindata`");
// /src/cosmopolitan/third_party/lua/lobject.h:480:9
pub inline fn getudatamem(u: anytype) @TypeOf(cast_charp(u) + udatamemoffset(u.*.nuvalue)) {
    _ = &u;
    return cast_charp(u) + udatamemoffset(u.*.nuvalue);
}
pub inline fn sizeudata(nuv: anytype, nb: anytype) @TypeOf(udatamemoffset(nuv) + nb) {
    _ = &nuv;
    _ = &nb;
    return udatamemoffset(nuv) + nb;
}
pub const LUA_VPROTO = makevariant(LUA_TPROTO, @as(c_int, 0));
pub const LUA_VUPVAL = makevariant(LUA_TUPVAL, @as(c_int, 0));
pub const LUA_VLCL = makevariant(LUA_TFUNCTION, @as(c_int, 0));
pub const LUA_VLCF = makevariant(LUA_TFUNCTION, @as(c_int, 1));
pub const LUA_VCCL = makevariant(LUA_TFUNCTION, @as(c_int, 2));
pub inline fn ttisfunction(o: anytype) @TypeOf(checktype(o, LUA_TFUNCTION)) {
    _ = &o;
    return checktype(o, LUA_TFUNCTION);
}
pub inline fn ttisLclosure(o: anytype) @TypeOf(checktag(o, ctb(LUA_VLCL))) {
    _ = &o;
    return checktag(o, ctb(LUA_VLCL));
}
pub inline fn ttislcf(o: anytype) @TypeOf(checktag(o, LUA_VLCF)) {
    _ = &o;
    return checktag(o, LUA_VLCF);
}
pub inline fn ttisCclosure(o: anytype) @TypeOf(checktag(o, ctb(LUA_VCCL))) {
    _ = &o;
    return checktag(o, ctb(LUA_VCCL));
}
pub inline fn ttisclosure(o: anytype) @TypeOf((ttisLclosure(o) != 0) or (ttisCclosure(o) != 0)) {
    _ = &o;
    return (ttisLclosure(o) != 0) or (ttisCclosure(o) != 0);
}
pub inline fn isLfunction(o: anytype) @TypeOf(ttisLclosure(o)) {
    _ = &o;
    return ttisLclosure(o);
}
pub inline fn clvalue(o: anytype) @TypeOf(check_exp(ttisclosure(o), gco2cl(val_(o).gc))) {
    _ = &o;
    return check_exp(ttisclosure(o), gco2cl(val_(o).gc));
}
pub inline fn clLvalue(o: anytype) @TypeOf(check_exp(ttisLclosure(o), gco2lcl(val_(o).gc))) {
    _ = &o;
    return check_exp(ttisLclosure(o), gco2lcl(val_(o).gc));
}
pub inline fn fvalue(o: anytype) @TypeOf(check_exp(ttislcf(o), val_(o).f)) {
    _ = &o;
    return check_exp(ttislcf(o), val_(o).f);
}
pub inline fn clCvalue(o: anytype) @TypeOf(check_exp(ttisCclosure(o), gco2ccl(val_(o).gc))) {
    _ = &o;
    return check_exp(ttisCclosure(o), gco2ccl(val_(o).gc));
}
pub inline fn fvalueraw(v: anytype) @TypeOf(v.f) {
    _ = &v;
    return v.f;
}
pub const setclLvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:600:9
pub inline fn setclLvalue2s(L: anytype, o: anytype, cl: anytype) @TypeOf(setclLvalue(L, s2v(o), cl)) {
    _ = &L;
    _ = &o;
    _ = &cl;
    return setclLvalue(L, s2v(o), cl);
}
pub const setfvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:607:9
pub const setclCvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:610:9
pub const ClosureHeader = @compileError("unable to translate macro: undefined identifier `nupvalues`");
// /src/cosmopolitan/third_party/lua/lobject.h:636:9
pub inline fn getproto(o: anytype) @TypeOf(clLvalue(o).*.p) {
    _ = &o;
    return clLvalue(o).*.p;
}
pub const LUA_VTABLE = makevariant(LUA_TTABLE, @as(c_int, 0));
pub inline fn ttistable(o: anytype) @TypeOf(checktag(o, ctb(LUA_VTABLE))) {
    _ = &o;
    return checktag(o, ctb(LUA_VTABLE));
}
pub inline fn hvalue(o: anytype) @TypeOf(check_exp(ttistable(o), gco2t(val_(o).gc))) {
    _ = &o;
    return check_exp(ttistable(o), gco2t(val_(o).gc));
}
pub const sethvalue = @compileError("unable to translate macro: undefined identifier `io`");
// /src/cosmopolitan/third_party/lua/lobject.h:676:9
pub inline fn sethvalue2s(L: anytype, o: anytype, h: anytype) @TypeOf(sethvalue(L, s2v(o), h)) {
    _ = &L;
    _ = &o;
    _ = &h;
    return sethvalue(L, s2v(o), h);
}
pub const setnodekey = @compileError("unable to translate macro: undefined identifier `n_`");
// /src/cosmopolitan/third_party/lua/lobject.h:703:9
pub const getnodekey = @compileError("unable to translate macro: undefined identifier `io_`");
// /src/cosmopolitan/third_party/lua/lobject.h:710:9
pub const BITRAS = @as(c_int, 1) << @as(c_int, 7);
pub inline fn isrealasize(t: anytype) @TypeOf(!((t.*.flags & BITRAS) != 0)) {
    _ = &t;
    return !((t.*.flags & BITRAS) != 0);
}
pub const setrealasize = @compileError("unable to translate C expr: expected ')' instead got '&='");
// /src/cosmopolitan/third_party/lua/lobject.h:725:9
pub const setnorealasize = @compileError("unable to translate C expr: expected ')' instead got '|='");
// /src/cosmopolitan/third_party/lua/lobject.h:726:9
pub inline fn keytt(node: anytype) @TypeOf(node.*.u.key_tt) {
    _ = &node;
    return node.*.u.key_tt;
}
pub inline fn keyval(node: anytype) @TypeOf(node.*.u.key_val) {
    _ = &node;
    return node.*.u.key_val;
}
pub inline fn keyisnil(node: anytype) @TypeOf(keytt(node) == LUA_TNIL) {
    _ = &node;
    return keytt(node) == LUA_TNIL;
}
pub inline fn keyisinteger(node: anytype) @TypeOf(keytt(node) == LUA_VNUMINT) {
    _ = &node;
    return keytt(node) == LUA_VNUMINT;
}
pub inline fn keyival(node: anytype) @TypeOf(keyval(node).i) {
    _ = &node;
    return keyval(node).i;
}
pub inline fn keyisshrstr(node: anytype) @TypeOf(keytt(node) == ctb(LUA_VSHRSTR)) {
    _ = &node;
    return keytt(node) == ctb(LUA_VSHRSTR);
}
pub inline fn keystrval(node: anytype) @TypeOf(gco2ts(keyval(node).gc)) {
    _ = &node;
    return gco2ts(keyval(node).gc);
}
pub const setnilkey = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lobject.h:754:9
pub inline fn keyiscollectable(n: anytype) @TypeOf(keytt(n) & BIT_ISCOLLECTABLE) {
    _ = &n;
    return keytt(n) & BIT_ISCOLLECTABLE;
}
pub inline fn gckey(n: anytype) @TypeOf(keyval(n).gc) {
    _ = &n;
    return keyval(n).gc;
}
pub inline fn gckeyN(n: anytype) @TypeOf(if (keyiscollectable(n) != 0) gckey(n) else NULL) {
    _ = &n;
    return if (keyiscollectable(n) != 0) gckey(n) else NULL;
}
pub const setdeadkey = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lobject.h:768:9
pub inline fn keyisdead(node: anytype) @TypeOf(keytt(node) == LUA_TDEADKEY) {
    _ = &node;
    return keytt(node) == LUA_TDEADKEY;
}
pub inline fn lmod(s: anytype, size: anytype) @TypeOf(check_exp((size & (size - @as(c_int, 1))) == @as(c_int, 0), cast_int(s & (size - @as(c_int, 1))))) {
    _ = &s;
    _ = &size;
    return check_exp((size & (size - @as(c_int, 1))) == @as(c_int, 0), cast_int(s & (size - @as(c_int, 1))));
}
pub inline fn twoto(x: anytype) @TypeOf(@as(c_int, 1) << x) {
    _ = &x;
    return @as(c_int, 1) << x;
}
pub inline fn sizenode(t: anytype) @TypeOf(twoto(t.*.lsizenode)) {
    _ = &t;
    return twoto(t.*.lsizenode);
}
pub const UTF8BUFFSZ = @as(c_int, 8);
pub const lzio_h = "";
pub const lmem_h = "";
pub inline fn luaM_error(L: anytype) @TypeOf(luaD_throw(L, LUA_ERRMEM)) {
    _ = &L;
    return luaD_throw(L, LUA_ERRMEM);
}
pub inline fn luaM_testsize(n: anytype, e: anytype) @TypeOf((@import("std").zig.c_translation.sizeof(n) >= @import("std").zig.c_translation.sizeof(usize)) and ((cast_sizet(n) + @as(c_int, 1)) > @import("std").zig.c_translation.MacroArithmetic.div(MAX_SIZET, e))) {
    _ = &n;
    _ = &e;
    return (@import("std").zig.c_translation.sizeof(n) >= @import("std").zig.c_translation.sizeof(usize)) and ((cast_sizet(n) + @as(c_int, 1)) > @import("std").zig.c_translation.MacroArithmetic.div(MAX_SIZET, e));
}
pub inline fn luaM_checksize(L: anytype, n: anytype, e: anytype) @TypeOf(if (luaM_testsize(n, e) != 0) luaM_toobig(L) else cast_void(@as(c_int, 0))) {
    _ = &L;
    _ = &n;
    _ = &e;
    return if (luaM_testsize(n, e) != 0) luaM_toobig(L) else cast_void(@as(c_int, 0));
}
pub inline fn luaM_limitN(n: anytype, t: anytype) @TypeOf(if (cast_sizet(n) <= @import("std").zig.c_translation.MacroArithmetic.div(MAX_SIZET, @import("std").zig.c_translation.sizeof(t))) n else cast_uint(@import("std").zig.c_translation.MacroArithmetic.div(MAX_SIZET, @import("std").zig.c_translation.sizeof(t)))) {
    _ = &n;
    _ = &t;
    return if (cast_sizet(n) <= @import("std").zig.c_translation.MacroArithmetic.div(MAX_SIZET, @import("std").zig.c_translation.sizeof(t))) n else cast_uint(@import("std").zig.c_translation.MacroArithmetic.div(MAX_SIZET, @import("std").zig.c_translation.sizeof(t)));
}
pub inline fn luaM_reallocvchar(L: anytype, b: anytype, on: anytype, n: anytype) @TypeOf(cast_charp(luaM_saferealloc_(L, b, on * @import("std").zig.c_translation.sizeof(u8), n * @import("std").zig.c_translation.sizeof(u8)))) {
    _ = &L;
    _ = &b;
    _ = &on;
    _ = &n;
    return cast_charp(luaM_saferealloc_(L, b, on * @import("std").zig.c_translation.sizeof(u8), n * @import("std").zig.c_translation.sizeof(u8)));
}
pub inline fn luaM_freemem(L: anytype, b: anytype, s: anytype) @TypeOf(luaM_free_(L, b, s)) {
    _ = &L;
    _ = &b;
    _ = &s;
    return luaM_free_(L, b, s);
}
pub const luaM_free = @compileError("unable to translate C expr: unexpected token '*'");
// /src/cosmopolitan/third_party/lua/lmem.h:47:9
pub const luaM_freearray = @compileError("unable to translate C expr: unexpected token '*'");
// /src/cosmopolitan/third_party/lua/lmem.h:48:9
pub const luaM_new = @compileError("unable to translate C expr: unexpected token ','");
// /src/cosmopolitan/third_party/lua/lmem.h:50:9
pub const luaM_newvector = @compileError("unable to translate C expr: unexpected token ','");
// /src/cosmopolitan/third_party/lua/lmem.h:51:9
pub inline fn luaM_newvectorchecked(L: anytype, n: anytype, t: anytype) @TypeOf(luaM_newvector(L, n, t)) {
    _ = &L;
    _ = &n;
    _ = &t;
    return blk_1: {
        _ = luaM_checksize(L, n, @import("std").zig.c_translation.sizeof(t));
        break :blk_1 luaM_newvector(L, n, t);
    };
}
pub inline fn luaM_newobject(L: anytype, tag: anytype, s: anytype) @TypeOf(luaM_malloc_(L, s, tag)) {
    _ = &L;
    _ = &tag;
    _ = &s;
    return luaM_malloc_(L, s, tag);
}
pub const luaM_growvector = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lmem.h:57:9
pub const luaM_reallocvector = @compileError("unable to translate C expr: unexpected token ','");
// /src/cosmopolitan/third_party/lua/lmem.h:61:9
pub const luaM_shrinkvector = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lmem.h:65:9
pub const EOZ = -@as(c_int, 1);
pub const zgetc = @compileError("TODO postfix inc/dec expr");
// /src/cosmopolitan/third_party/lua/lzio.h:12:9
pub const luaZ_initbuffer = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lzio.h:21:9
pub inline fn luaZ_buffer(buff: anytype) @TypeOf(buff.*.buffer) {
    _ = &buff;
    return buff.*.buffer;
}
pub inline fn luaZ_sizebuffer(buff: anytype) @TypeOf(buff.*.buffsize) {
    _ = &buff;
    return buff.*.buffsize;
}
pub inline fn luaZ_bufflen(buff: anytype) @TypeOf(buff.*.n) {
    _ = &buff;
    return buff.*.n;
}
pub const luaZ_buffremove = @compileError("unable to translate C expr: expected ')' instead got '-='");
// /src/cosmopolitan/third_party/lua/lzio.h:27:9
pub const luaZ_resetbuffer = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lzio.h:28:9
pub const luaZ_resizebuffer = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lzio.h:31:9
pub inline fn luaZ_freebuffer(L: anytype, buff: anytype) @TypeOf(luaZ_resizebuffer(L, buff, @as(c_int, 0))) {
    _ = &L;
    _ = &buff;
    return luaZ_resizebuffer(L, buff, @as(c_int, 0));
}
pub const COSMOPOLITAN_THIRD_PARTY_LUA_TMS_H_ = "";
pub inline fn yieldable(L: anytype) @TypeOf((L.*.nCcalls & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff0000, .hex)) == @as(c_int, 0)) {
    _ = &L;
    return (L.*.nCcalls & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff0000, .hex)) == @as(c_int, 0);
}
pub inline fn getCcalls(L: anytype) @TypeOf(L.*.nCcalls & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex)) {
    _ = &L;
    return L.*.nCcalls & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex);
}
pub const incnny = @compileError("unable to translate C expr: expected ')' instead got '+='");
// /src/cosmopolitan/third_party/lua/lstate.h:103:9
pub const decnny = @compileError("unable to translate C expr: expected ')' instead got '-='");
// /src/cosmopolitan/third_party/lua/lstate.h:106:9
pub const nyci = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10000, .hex) | @as(c_int, 1);
pub const l_signalT = sig_atomic_t;
pub const EXTRA_STACK = @as(c_int, 5);
pub const BASIC_STACK_SIZE = @as(c_int, 2) * LUA_MINSTACK;
pub inline fn stacksize(th: anytype) @TypeOf(cast_int(th.*.stack_last.p - th.*.stack.p)) {
    _ = &th;
    return cast_int(th.*.stack_last.p - th.*.stack.p);
}
pub const KGC_INC = @as(c_int, 0);
pub const KGC_GEN = @as(c_int, 1);
pub const CIST_OAH = @as(c_int, 1) << @as(c_int, 0);
pub const CIST_C = @as(c_int, 1) << @as(c_int, 1);
pub const CIST_FRESH = @as(c_int, 1) << @as(c_int, 2);
pub const CIST_HOOKED = @as(c_int, 1) << @as(c_int, 3);
pub const CIST_YPCALL = @as(c_int, 1) << @as(c_int, 4);
pub const CIST_TAIL = @as(c_int, 1) << @as(c_int, 5);
pub const CIST_HOOKYIELD = @as(c_int, 1) << @as(c_int, 6);
pub const CIST_FIN = @as(c_int, 1) << @as(c_int, 7);
pub const CIST_TRAN = @as(c_int, 1) << @as(c_int, 8);
pub const CIST_CLSRET = @as(c_int, 1) << @as(c_int, 9);
pub const CIST_RECST = @as(c_int, 10);
pub inline fn getcistrecst(ci: anytype) @TypeOf((ci.*.callstatus >> CIST_RECST) & @as(c_int, 7)) {
    _ = &ci;
    return (ci.*.callstatus >> CIST_RECST) & @as(c_int, 7);
}
pub const setcistrecst = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lstate.h:225:9
pub inline fn isLua(ci: anytype) @TypeOf(!((ci.*.callstatus & CIST_C) != 0)) {
    _ = &ci;
    return !((ci.*.callstatus & CIST_C) != 0);
}
pub inline fn isLuacode(ci: anytype) @TypeOf(!((ci.*.callstatus & (CIST_C | CIST_HOOKED)) != 0)) {
    _ = &ci;
    return !((ci.*.callstatus & (CIST_C | CIST_HOOKED)) != 0);
}
pub const setoah = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lstate.h:238:9
pub inline fn getoah(st: anytype) @TypeOf(st & CIST_OAH) {
    _ = &st;
    return st & CIST_OAH;
}
pub inline fn G(L: anytype) @TypeOf(L.*.l_G) {
    _ = &L;
    return L.*.l_G;
}
pub inline fn completestate(g: anytype) @TypeOf(ttisnil(&g.*.nilvalue)) {
    _ = &g;
    return ttisnil(&g.*.nilvalue);
}
pub inline fn cast_u(o: anytype) @TypeOf(cast([*c]union_GCUnion, o)) {
    _ = &o;
    return cast([*c]union_GCUnion, o);
}
pub inline fn gco2ts(o: anytype) @TypeOf(check_exp(novariant(o.*.tt) == LUA_TSTRING, &cast_u(o).*.ts)) {
    _ = &o;
    return check_exp(novariant(o.*.tt) == LUA_TSTRING, &cast_u(o).*.ts);
}
pub inline fn gco2u(o: anytype) @TypeOf(check_exp(o.*.tt == LUA_VUSERDATA, &cast_u(o).*.u)) {
    _ = &o;
    return check_exp(o.*.tt == LUA_VUSERDATA, &cast_u(o).*.u);
}
pub inline fn gco2lcl(o: anytype) @TypeOf(check_exp(o.*.tt == LUA_VLCL, &cast_u(o).*.cl.l)) {
    _ = &o;
    return check_exp(o.*.tt == LUA_VLCL, &cast_u(o).*.cl.l);
}
pub inline fn gco2ccl(o: anytype) @TypeOf(check_exp(o.*.tt == LUA_VCCL, &cast_u(o).*.cl.c)) {
    _ = &o;
    return check_exp(o.*.tt == LUA_VCCL, &cast_u(o).*.cl.c);
}
pub inline fn gco2cl(o: anytype) @TypeOf(check_exp(novariant(o.*.tt) == LUA_TFUNCTION, &cast_u(o).*.cl)) {
    _ = &o;
    return check_exp(novariant(o.*.tt) == LUA_TFUNCTION, &cast_u(o).*.cl);
}
pub inline fn gco2t(o: anytype) @TypeOf(check_exp(o.*.tt == LUA_VTABLE, &cast_u(o).*.h)) {
    _ = &o;
    return check_exp(o.*.tt == LUA_VTABLE, &cast_u(o).*.h);
}
pub inline fn gco2p(o: anytype) @TypeOf(check_exp(o.*.tt == LUA_VPROTO, &cast_u(o).*.p)) {
    _ = &o;
    return check_exp(o.*.tt == LUA_VPROTO, &cast_u(o).*.p);
}
pub inline fn gco2th(o: anytype) @TypeOf(check_exp(o.*.tt == LUA_VTHREAD, &cast_u(o).*.th)) {
    _ = &o;
    return check_exp(o.*.tt == LUA_VTHREAD, &cast_u(o).*.th);
}
pub inline fn gco2upv(o: anytype) @TypeOf(check_exp(o.*.tt == LUA_VUPVAL, &cast_u(o).*.upv)) {
    _ = &o;
    return check_exp(o.*.tt == LUA_VUPVAL, &cast_u(o).*.upv);
}
pub inline fn obj2gco(v: anytype) @TypeOf(check_exp(v.*.tt >= LUA_TSTRING, &cast_u(v).*.gc)) {
    _ = &v;
    return check_exp(v.*.tt >= LUA_TSTRING, &cast_u(v).*.gc);
}
pub inline fn gettotalbytes(g: anytype) @TypeOf(cast(lu_mem, g.*.totalbytes + g.*.GCdebt)) {
    _ = &g;
    return cast(lu_mem, g.*.totalbytes + g.*.GCdebt);
}
pub const api_incr_top = @compileError("unable to translate C expr: unexpected token '{'");
// /src/cosmopolitan/third_party/lua/lapi.h:9:9
pub const adjustresults = @compileError("unable to translate C expr: unexpected token '{'");
// /src/cosmopolitan/third_party/lua/lapi.h:19:9
pub inline fn api_checknelems(L: anytype, n: anytype) @TypeOf(api_check(L, n < (L.*.top.p - L.*.ci.*.func.p), "not enough elements in the stack")) {
    _ = &L;
    _ = &n;
    return api_check(L, n < (L.*.top.p - L.*.ci.*.func.p), "not enough elements in the stack");
}
pub inline fn hastocloseCfunc(n: anytype) @TypeOf(n < LUA_MULTRET) {
    _ = &n;
    return n < LUA_MULTRET;
}
pub inline fn codeNresults(n: anytype) @TypeOf(-n - @as(c_int, 3)) {
    _ = &n;
    return -n - @as(c_int, 3);
}
pub inline fn decodeNresults(n: anytype) @TypeOf(-n - @as(c_int, 3)) {
    _ = &n;
    return -n - @as(c_int, 3);
}
pub const ldebug_h = "";
pub inline fn pcRel(pc: anytype, p: anytype) @TypeOf(cast_int(pc - p.*.code) - @as(c_int, 1)) {
    _ = &pc;
    _ = &p;
    return cast_int(pc - p.*.code) - @as(c_int, 1);
}
pub inline fn ci_func(ci: anytype) @TypeOf(clLvalue(s2v(ci.*.func.p))) {
    _ = &ci;
    return clLvalue(s2v(ci.*.func.p));
}
pub const resethookcount = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/ldebug.h:15:9
pub const ABSLINEINFO = -@as(c_int, 0x80);
pub const MAXIWTHABS = @as(c_int, 128);
pub const lfunc_h = "";
pub const sizeCclosure = @compileError("unable to translate macro: undefined identifier `upvalue`");
// /src/cosmopolitan/third_party/lua/lfunc.h:7:9
pub const sizeLclosure = @compileError("unable to translate macro: undefined identifier `upvals`");
// /src/cosmopolitan/third_party/lua/lfunc.h:10:9
pub inline fn isintwups(L: anytype) @TypeOf(L.*.twups != L) {
    _ = &L;
    return L.*.twups != L;
}
pub const MAXUPVAL = @as(c_int, 255);
pub inline fn upisopen(up: anytype) @TypeOf(up.*.v.p != (&up.*.u.value)) {
    _ = &up;
    return up.*.v.p != (&up.*.u.value);
}
pub inline fn uplevel(up: anytype) @TypeOf(check_exp(upisopen(up), cast(StkId, up.*.v.p))) {
    _ = &up;
    return check_exp(upisopen(up), cast(StkId, up.*.v.p));
}
pub const MAXMISS = @as(c_int, 10);
pub const CLOSEKTOP = -@as(c_int, 1);
pub const lgc_h = "";
pub const GCSpropagate = @as(c_int, 0);
pub const GCSenteratomic = @as(c_int, 1);
pub const GCSatomic = @as(c_int, 2);
pub const GCSswpallgc = @as(c_int, 3);
pub const GCSswpfinobj = @as(c_int, 4);
pub const GCSswptobefnz = @as(c_int, 5);
pub const GCSswpend = @as(c_int, 6);
pub const GCScallfin = @as(c_int, 7);
pub const GCSpause = @as(c_int, 8);
pub inline fn issweepphase(g: anytype) @TypeOf((GCSswpallgc <= g.*.gcstate) and (g.*.gcstate <= GCSswpend)) {
    _ = &g;
    return (GCSswpallgc <= g.*.gcstate) and (g.*.gcstate <= GCSswpend);
}
pub inline fn keepinvariant(g: anytype) @TypeOf(g.*.gcstate <= GCSatomic) {
    _ = &g;
    return g.*.gcstate <= GCSatomic;
}
pub const resetbits = @compileError("unable to translate C expr: expected ')' instead got '&='");
// /src/cosmopolitan/third_party/lua/lgc.h:54:9
pub const setbits = @compileError("unable to translate C expr: expected ')' instead got '|='");
// /src/cosmopolitan/third_party/lua/lgc.h:55:9
pub inline fn testbits(x: anytype, m: anytype) @TypeOf(x & m) {
    _ = &x;
    _ = &m;
    return x & m;
}
pub inline fn bitmask(b: anytype) @TypeOf(@as(c_int, 1) << b) {
    _ = &b;
    return @as(c_int, 1) << b;
}
pub inline fn bit2mask(b1: anytype, b2: anytype) @TypeOf(bitmask(b1) | bitmask(b2)) {
    _ = &b1;
    _ = &b2;
    return bitmask(b1) | bitmask(b2);
}
pub inline fn l_setbit(x: anytype, b: anytype) @TypeOf(setbits(x, bitmask(b))) {
    _ = &x;
    _ = &b;
    return setbits(x, bitmask(b));
}
pub inline fn resetbit(x: anytype, b: anytype) @TypeOf(resetbits(x, bitmask(b))) {
    _ = &x;
    _ = &b;
    return resetbits(x, bitmask(b));
}
pub inline fn testbit(x: anytype, b: anytype) @TypeOf(testbits(x, bitmask(b))) {
    _ = &x;
    _ = &b;
    return testbits(x, bitmask(b));
}
pub const WHITE0BIT = @as(c_int, 3);
pub const WHITE1BIT = @as(c_int, 4);
pub const BLACKBIT = @as(c_int, 5);
pub const FINALIZEDBIT = @as(c_int, 6);
pub const TESTBIT = @as(c_int, 7);
pub const WHITEBITS = bit2mask(WHITE0BIT, WHITE1BIT);
pub inline fn iswhite(x: anytype) @TypeOf(testbits(x.*.marked, WHITEBITS)) {
    _ = &x;
    return testbits(x.*.marked, WHITEBITS);
}
pub inline fn isblack(x: anytype) @TypeOf(testbit(x.*.marked, BLACKBIT)) {
    _ = &x;
    return testbit(x.*.marked, BLACKBIT);
}
pub inline fn isgray(x: anytype) @TypeOf(!(testbits(x.*.marked, WHITEBITS | bitmask(BLACKBIT)) != 0)) {
    _ = &x;
    return !(testbits(x.*.marked, WHITEBITS | bitmask(BLACKBIT)) != 0);
}
pub inline fn tofinalize(x: anytype) @TypeOf(testbit(x.*.marked, FINALIZEDBIT)) {
    _ = &x;
    return testbit(x.*.marked, FINALIZEDBIT);
}
pub inline fn otherwhite(g: anytype) @TypeOf(g.*.currentwhite ^ WHITEBITS) {
    _ = &g;
    return g.*.currentwhite ^ WHITEBITS;
}
pub inline fn isdeadm(ow: anytype, m: anytype) @TypeOf(m & ow) {
    _ = &ow;
    _ = &m;
    return m & ow;
}
pub inline fn isdead(g: anytype, v: anytype) @TypeOf(isdeadm(otherwhite(g), v.*.marked)) {
    _ = &g;
    _ = &v;
    return isdeadm(otherwhite(g), v.*.marked);
}
pub const changewhite = @compileError("unable to translate C expr: expected ')' instead got '^='");
// /src/cosmopolitan/third_party/lua/lgc.h:92:9
pub inline fn nw2black(x: anytype) @TypeOf(check_exp(!(iswhite(x) != 0), l_setbit(x.*.marked, BLACKBIT))) {
    _ = &x;
    return check_exp(!(iswhite(x) != 0), l_setbit(x.*.marked, BLACKBIT));
}
pub inline fn luaC_white(g: anytype) @TypeOf(cast_byte(g.*.currentwhite & WHITEBITS)) {
    _ = &g;
    return cast_byte(g.*.currentwhite & WHITEBITS);
}
pub const G_NEW = @as(c_int, 0);
pub const G_SURVIVAL = @as(c_int, 1);
pub const G_OLD0 = @as(c_int, 2);
pub const G_OLD1 = @as(c_int, 3);
pub const G_OLD = @as(c_int, 4);
pub const G_TOUCHED1 = @as(c_int, 5);
pub const G_TOUCHED2 = @as(c_int, 6);
pub const AGEBITS = @as(c_int, 7);
pub inline fn getage(o: anytype) @TypeOf(o.*.marked & AGEBITS) {
    _ = &o;
    return o.*.marked & AGEBITS;
}
pub const setage = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lgc.h:111:9
pub inline fn isold(o: anytype) @TypeOf(getage(o) > G_SURVIVAL) {
    _ = &o;
    return getage(o) > G_SURVIVAL;
}
pub const changeage = @compileError("unable to translate C expr: expected ',' or ')' instead got '^='");
// /src/cosmopolitan/third_party/lua/lgc.h:114:9
pub const LUAI_GENMAJORMUL = @as(c_int, 100);
pub const LUAI_GENMINORMUL = @as(c_int, 20);
pub const LUAI_GCPAUSE = @as(c_int, 200);
pub inline fn getgcparam(p: anytype) @TypeOf(p * @as(c_int, 4)) {
    _ = &p;
    return p * @as(c_int, 4);
}
pub const setgcparam = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lgc.h:130:9
pub const LUAI_GCMUL = @as(c_int, 100);
pub const LUAI_GCSTEPSIZE = @as(c_int, 13);
pub inline fn isdecGCmodegen(g: anytype) @TypeOf((g.*.gckind == KGC_GEN) or (g.*.lastatomic != @as(c_int, 0))) {
    _ = &g;
    return (g.*.gckind == KGC_GEN) or (g.*.lastatomic != @as(c_int, 0));
}
pub const GCSTPUSR = @as(c_int, 1);
pub const GCSTPGC = @as(c_int, 2);
pub const GCSTPCLS = @as(c_int, 4);
pub inline fn gcrunning(g: anytype) @TypeOf(g.*.gcstp == @as(c_int, 0)) {
    _ = &g;
    return g.*.gcstp == @as(c_int, 0);
}
pub const luaC_condGC = @compileError("unable to translate C expr: unexpected token '{'");
// /src/cosmopolitan/third_party/lua/lgc.h:161:9
pub inline fn luaC_checkGC(L: anytype) @TypeOf(luaC_condGC(L, @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)), @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)))) {
    _ = &L;
    return luaC_condGC(L, @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)), @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)));
}
pub inline fn luaC_objbarrier(L: anytype, p: anytype, o: anytype) @TypeOf(if ((isblack(p) != 0) and (iswhite(o) != 0)) luaC_barrier_(L, obj2gco(p), obj2gco(o)) else cast_void(@as(c_int, 0))) {
    _ = &L;
    _ = &p;
    _ = &o;
    return if ((isblack(p) != 0) and (iswhite(o) != 0)) luaC_barrier_(L, obj2gco(p), obj2gco(o)) else cast_void(@as(c_int, 0));
}
pub inline fn luaC_barrier(L: anytype, p: anytype, v: anytype) @TypeOf(if (iscollectable(v) != 0) luaC_objbarrier(L, p, gcvalue(v)) else cast_void(@as(c_int, 0))) {
    _ = &L;
    _ = &p;
    _ = &v;
    return if (iscollectable(v) != 0) luaC_objbarrier(L, p, gcvalue(v)) else cast_void(@as(c_int, 0));
}
pub inline fn luaC_objbarrierback(L: anytype, p: anytype, o: anytype) @TypeOf(if ((isblack(p) != 0) and (iswhite(o) != 0)) luaC_barrierback_(L, p) else cast_void(@as(c_int, 0))) {
    _ = &L;
    _ = &p;
    _ = &o;
    return if ((isblack(p) != 0) and (iswhite(o) != 0)) luaC_barrierback_(L, p) else cast_void(@as(c_int, 0));
}
pub inline fn luaC_barrierback(L: anytype, p: anytype, v: anytype) @TypeOf(if (iscollectable(v) != 0) luaC_objbarrierback(L, p, gcvalue(v)) else cast_void(@as(c_int, 0))) {
    _ = &L;
    _ = &p;
    _ = &v;
    return if (iscollectable(v) != 0) luaC_objbarrierback(L, p, gcvalue(v)) else cast_void(@as(c_int, 0));
}
pub const lopcodes_h = "";
pub const SIZE_C = @as(c_int, 8);
pub const SIZE_B = @as(c_int, 8);
pub const SIZE_Bx = (SIZE_C + SIZE_B) + @as(c_int, 1);
pub const SIZE_A = @as(c_int, 8);
pub const SIZE_Ax = SIZE_Bx + SIZE_A;
pub const SIZE_sJ = SIZE_Bx + SIZE_A;
pub const SIZE_OP = @as(c_int, 7);
pub const POS_OP = @as(c_int, 0);
pub const POS_A = POS_OP + SIZE_OP;
pub const POS_k = POS_A + SIZE_A;
pub const POS_B = POS_k + @as(c_int, 1);
pub const POS_C = POS_B + SIZE_B;
pub const POS_Bx = POS_k;
pub const POS_Ax = POS_A;
pub const POS_sJ = POS_A;
pub inline fn L_INTHASBITS(b: anytype) @TypeOf((UINT_MAX >> (b - @as(c_int, 1))) >= @as(c_int, 1)) {
    _ = &b;
    return (UINT_MAX >> (b - @as(c_int, 1))) >= @as(c_int, 1);
}
pub const MAXARG_Bx = (@as(c_int, 1) << SIZE_Bx) - @as(c_int, 1);
pub const OFFSET_sBx = MAXARG_Bx >> @as(c_int, 1);
pub const MAXARG_Ax = (@as(c_int, 1) << SIZE_Ax) - @as(c_int, 1);
pub const MAXARG_sJ = (@as(c_int, 1) << SIZE_sJ) - @as(c_int, 1);
pub const OFFSET_sJ = MAXARG_sJ >> @as(c_int, 1);
pub const MAXARG_A = (@as(c_int, 1) << SIZE_A) - @as(c_int, 1);
pub const MAXARG_B = (@as(c_int, 1) << SIZE_B) - @as(c_int, 1);
pub const MAXARG_C = (@as(c_int, 1) << SIZE_C) - @as(c_int, 1);
pub const OFFSET_sC = MAXARG_C >> @as(c_int, 1);
pub inline fn int2sC(i: anytype) @TypeOf(i + OFFSET_sC) {
    _ = &i;
    return i + OFFSET_sC;
}
pub inline fn sC2int(i: anytype) @TypeOf(i - OFFSET_sC) {
    _ = &i;
    return i - OFFSET_sC;
}
pub inline fn MASK1(n: anytype, p: anytype) @TypeOf(~(~@import("std").zig.c_translation.cast(Instruction, @as(c_int, 0)) << n) << p) {
    _ = &n;
    _ = &p;
    return ~(~@import("std").zig.c_translation.cast(Instruction, @as(c_int, 0)) << n) << p;
}
pub inline fn MASK0(n: anytype, p: anytype) @TypeOf(~MASK1(n, p)) {
    _ = &n;
    _ = &p;
    return ~MASK1(n, p);
}
pub inline fn GET_OPCODE(i: anytype) @TypeOf(cast(OpCode, (i >> POS_OP) & MASK1(SIZE_OP, @as(c_int, 0)))) {
    _ = &i;
    return cast(OpCode, (i >> POS_OP) & MASK1(SIZE_OP, @as(c_int, 0)));
}
pub const SET_OPCODE = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lopcodes.h:109:9
pub inline fn checkopm(i: anytype, m: anytype) @TypeOf(getOpMode(GET_OPCODE(i)) == m) {
    _ = &i;
    _ = &m;
    return getOpMode(GET_OPCODE(i)) == m;
}
pub inline fn getarg(i: anytype, pos: anytype, size: anytype) @TypeOf(cast_int((i >> pos) & MASK1(size, @as(c_int, 0)))) {
    _ = &i;
    _ = &pos;
    _ = &size;
    return cast_int((i >> pos) & MASK1(size, @as(c_int, 0)));
}
pub const setarg = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lopcodes.h:116:9
pub inline fn GETARG_A(i: anytype) @TypeOf(getarg(i, POS_A, SIZE_A)) {
    _ = &i;
    return getarg(i, POS_A, SIZE_A);
}
pub inline fn SETARG_A(i: anytype, v: anytype) @TypeOf(setarg(i, v, POS_A, SIZE_A)) {
    _ = &i;
    _ = &v;
    return setarg(i, v, POS_A, SIZE_A);
}
pub inline fn GETARG_B(i: anytype) @TypeOf(check_exp(checkopm(i, iABC), getarg(i, POS_B, SIZE_B))) {
    _ = &i;
    return check_exp(checkopm(i, iABC), getarg(i, POS_B, SIZE_B));
}
pub inline fn GETARG_sB(i: anytype) @TypeOf(sC2int(GETARG_B(i))) {
    _ = &i;
    return sC2int(GETARG_B(i));
}
pub inline fn SETARG_B(i: anytype, v: anytype) @TypeOf(setarg(i, v, POS_B, SIZE_B)) {
    _ = &i;
    _ = &v;
    return setarg(i, v, POS_B, SIZE_B);
}
pub inline fn GETARG_C(i: anytype) @TypeOf(check_exp(checkopm(i, iABC), getarg(i, POS_C, SIZE_C))) {
    _ = &i;
    return check_exp(checkopm(i, iABC), getarg(i, POS_C, SIZE_C));
}
pub inline fn GETARG_sC(i: anytype) @TypeOf(sC2int(GETARG_C(i))) {
    _ = &i;
    return sC2int(GETARG_C(i));
}
pub inline fn SETARG_C(i: anytype, v: anytype) @TypeOf(setarg(i, v, POS_C, SIZE_C)) {
    _ = &i;
    _ = &v;
    return setarg(i, v, POS_C, SIZE_C);
}
pub inline fn TESTARG_k(i: anytype) @TypeOf(check_exp(checkopm(i, iABC), cast_int(i & (@as(c_uint, 1) << POS_k)))) {
    _ = &i;
    return check_exp(checkopm(i, iABC), cast_int(i & (@as(c_uint, 1) << POS_k)));
}
pub inline fn GETARG_k(i: anytype) @TypeOf(check_exp(checkopm(i, iABC), getarg(i, POS_k, @as(c_int, 1)))) {
    _ = &i;
    return check_exp(checkopm(i, iABC), getarg(i, POS_k, @as(c_int, 1)));
}
pub inline fn SETARG_k(i: anytype, v: anytype) @TypeOf(setarg(i, v, POS_k, @as(c_int, 1))) {
    _ = &i;
    _ = &v;
    return setarg(i, v, POS_k, @as(c_int, 1));
}
pub inline fn GETARG_Bx(i: anytype) @TypeOf(check_exp(checkopm(i, iABx), getarg(i, POS_Bx, SIZE_Bx))) {
    _ = &i;
    return check_exp(checkopm(i, iABx), getarg(i, POS_Bx, SIZE_Bx));
}
pub inline fn SETARG_Bx(i: anytype, v: anytype) @TypeOf(setarg(i, v, POS_Bx, SIZE_Bx)) {
    _ = &i;
    _ = &v;
    return setarg(i, v, POS_Bx, SIZE_Bx);
}
pub inline fn GETARG_Ax(i: anytype) @TypeOf(check_exp(checkopm(i, iAx), getarg(i, POS_Ax, SIZE_Ax))) {
    _ = &i;
    return check_exp(checkopm(i, iAx), getarg(i, POS_Ax, SIZE_Ax));
}
pub inline fn SETARG_Ax(i: anytype, v: anytype) @TypeOf(setarg(i, v, POS_Ax, SIZE_Ax)) {
    _ = &i;
    _ = &v;
    return setarg(i, v, POS_Ax, SIZE_Ax);
}
pub inline fn GETARG_sBx(i: anytype) @TypeOf(check_exp(checkopm(i, iAsBx), getarg(i, POS_Bx, SIZE_Bx) - OFFSET_sBx)) {
    _ = &i;
    return check_exp(checkopm(i, iAsBx), getarg(i, POS_Bx, SIZE_Bx) - OFFSET_sBx);
}
pub inline fn SETARG_sBx(i: anytype, b: anytype) @TypeOf(SETARG_Bx(i, cast_uint(b + OFFSET_sBx))) {
    _ = &i;
    _ = &b;
    return SETARG_Bx(i, cast_uint(b + OFFSET_sBx));
}
pub inline fn GETARG_sJ(i: anytype) @TypeOf(check_exp(checkopm(i, isJ), getarg(i, POS_sJ, SIZE_sJ) - OFFSET_sJ)) {
    _ = &i;
    return check_exp(checkopm(i, isJ), getarg(i, POS_sJ, SIZE_sJ) - OFFSET_sJ);
}
pub inline fn SETARG_sJ(i: anytype, j: anytype) @TypeOf(setarg(i, cast_uint(j + OFFSET_sJ), POS_sJ, SIZE_sJ)) {
    _ = &i;
    _ = &j;
    return setarg(i, cast_uint(j + OFFSET_sJ), POS_sJ, SIZE_sJ);
}
pub inline fn CREATE_ABCk(o: anytype, a: anytype, b: anytype, c: anytype, k: anytype) @TypeOf(((((cast(Instruction, o) << POS_OP) | (cast(Instruction, a) << POS_A)) | (cast(Instruction, b) << POS_B)) | (cast(Instruction, c) << POS_C)) | (cast(Instruction, k) << POS_k)) {
    _ = &o;
    _ = &a;
    _ = &b;
    _ = &c;
    _ = &k;
    return ((((cast(Instruction, o) << POS_OP) | (cast(Instruction, a) << POS_A)) | (cast(Instruction, b) << POS_B)) | (cast(Instruction, c) << POS_C)) | (cast(Instruction, k) << POS_k);
}
pub inline fn CREATE_ABx(o: anytype, a: anytype, bc: anytype) @TypeOf(((cast(Instruction, o) << POS_OP) | (cast(Instruction, a) << POS_A)) | (cast(Instruction, bc) << POS_Bx)) {
    _ = &o;
    _ = &a;
    _ = &bc;
    return ((cast(Instruction, o) << POS_OP) | (cast(Instruction, a) << POS_A)) | (cast(Instruction, bc) << POS_Bx);
}
pub inline fn CREATE_Ax(o: anytype, a: anytype) @TypeOf((cast(Instruction, o) << POS_OP) | (cast(Instruction, a) << POS_Ax)) {
    _ = &o;
    _ = &a;
    return (cast(Instruction, o) << POS_OP) | (cast(Instruction, a) << POS_Ax);
}
pub inline fn CREATE_sJ(o: anytype, j: anytype, k: anytype) @TypeOf(((cast(Instruction, o) << POS_OP) | (cast(Instruction, j) << POS_sJ)) | (cast(Instruction, k) << POS_k)) {
    _ = &o;
    _ = &j;
    _ = &k;
    return ((cast(Instruction, o) << POS_OP) | (cast(Instruction, j) << POS_sJ)) | (cast(Instruction, k) << POS_k);
}
pub const MAXINDEXRK = MAXARG_B;
pub const NO_REG = MAXARG_A;
pub const NUM_OPCODES = @import("std").zig.c_translation.cast(c_int, OP_EXTRAARG) + @as(c_int, 1);
pub inline fn getOpMode(m: anytype) @TypeOf(cast(enum_OpMode, luaP_opmodes[@as(usize, @intCast(m))] & @as(c_int, 7))) {
    _ = &m;
    return cast(enum_OpMode, luaP_opmodes[@as(usize, @intCast(m))] & @as(c_int, 7));
}
pub inline fn testAMode(m: anytype) @TypeOf(luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 3))) {
    _ = &m;
    return luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 3));
}
pub inline fn testTMode(m: anytype) @TypeOf(luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 4))) {
    _ = &m;
    return luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 4));
}
pub inline fn testITMode(m: anytype) @TypeOf(luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 5))) {
    _ = &m;
    return luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 5));
}
pub inline fn testOTMode(m: anytype) @TypeOf(luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 6))) {
    _ = &m;
    return luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 6));
}
pub inline fn testMMMode(m: anytype) @TypeOf(luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 7))) {
    _ = &m;
    return luaP_opmodes[@as(usize, @intCast(m))] & (@as(c_int, 1) << @as(c_int, 7));
}
pub inline fn isOT(i: anytype) @TypeOf(((testOTMode(GET_OPCODE(i)) != 0) and (GETARG_C(i) == @as(c_int, 0))) or (GET_OPCODE(i) == OP_TAILCALL)) {
    _ = &i;
    return ((testOTMode(GET_OPCODE(i)) != 0) and (GETARG_C(i) == @as(c_int, 0))) or (GET_OPCODE(i) == OP_TAILCALL);
}
pub inline fn isIT(i: anytype) @TypeOf((testITMode(GET_OPCODE(i)) != 0) and (GETARG_B(i) == @as(c_int, 0))) {
    _ = &i;
    return (testITMode(GET_OPCODE(i)) != 0) and (GETARG_B(i) == @as(c_int, 0));
}
pub inline fn opmode(mm: anytype, ot: anytype, it: anytype, t: anytype, a: anytype, m: anytype) @TypeOf((((((mm << @as(c_int, 7)) | (ot << @as(c_int, 6))) | (it << @as(c_int, 5))) | (t << @as(c_int, 4))) | (a << @as(c_int, 3))) | m) {
    _ = &mm;
    _ = &ot;
    _ = &it;
    _ = &t;
    _ = &a;
    _ = &m;
    return (((((mm << @as(c_int, 7)) | (ot << @as(c_int, 6))) | (it << @as(c_int, 5))) | (t << @as(c_int, 4))) | (a << @as(c_int, 3))) | m;
}
pub const LFIELDS_PER_FLUSH = @as(c_int, 50);
pub const lparser_h = "";
pub inline fn vkisvar(k: anytype) @TypeOf((VLOCAL <= k) and (k <= VINDEXSTR)) {
    _ = &k;
    return (VLOCAL <= k) and (k <= VINDEXSTR);
}
pub inline fn vkisindexed(k: anytype) @TypeOf((VINDEXED <= k) and (k <= VINDEXSTR)) {
    _ = &k;
    return (VINDEXED <= k) and (k <= VINDEXSTR);
}
pub const VDKREG = @as(c_int, 0);
pub const RDKCONST = @as(c_int, 1);
pub const RDKTOCLOSE = @as(c_int, 2);
pub const RDKCTC = @as(c_int, 3);
pub const lprefix_h = "";
pub const _XOPEN_SOURCE = @as(c_int, 600);
pub const lstring_h = "";
pub const MEMERRMSG = "not enough memory";
pub const sizelstring = @compileError("unable to translate macro: undefined identifier `contents`");
// /src/cosmopolitan/third_party/lua/lstring.h:20:9
pub inline fn luaS_newliteral(L: anytype, s: anytype) @TypeOf(luaS_newlstr(L, "" ++ s, @import("std").zig.c_translation.MacroArithmetic.div(@import("std").zig.c_translation.sizeof(s), @import("std").zig.c_translation.sizeof(u8)) - @as(c_int, 1))) {
    _ = &L;
    _ = &s;
    return luaS_newlstr(L, "" ++ s, @import("std").zig.c_translation.MacroArithmetic.div(@import("std").zig.c_translation.sizeof(s), @import("std").zig.c_translation.sizeof(u8)) - @as(c_int, 1));
}
pub inline fn isreserved(s: anytype) @TypeOf((s.*.tt == LUA_VSHRSTR) and (s.*.extra > @as(c_int, 0))) {
    _ = &s;
    return (s.*.tt == LUA_VSHRSTR) and (s.*.extra > @as(c_int, 0));
}
pub inline fn eqshrstr(a: anytype, b: anytype) @TypeOf(check_exp(a.*.tt == LUA_VSHRSTR, a == b)) {
    _ = &a;
    _ = &b;
    return check_exp(a.*.tt == LUA_VSHRSTR, a == b);
}
pub const ltable_h = "";
pub inline fn gnode(t: anytype, i: anytype) @TypeOf(&t.*.node[@as(usize, @intCast(i))]) {
    _ = &t;
    _ = &i;
    return &t.*.node[@as(usize, @intCast(i))];
}
pub inline fn gval(n: anytype) @TypeOf(&n.*.i_val) {
    _ = &n;
    return &n.*.i_val;
}
pub inline fn gnext(n: anytype) @TypeOf(n.*.u.next) {
    _ = &n;
    return n.*.u.next;
}
pub const invalidateTMcache = @compileError("unable to translate C expr: expected ')' instead got '&='");
// /src/cosmopolitan/third_party/lua/ltable.h:17:9
pub inline fn isdummy(t: anytype) @TypeOf(t.*.lastfree == NULL) {
    _ = &t;
    return t.*.lastfree == NULL;
}
pub inline fn allocsizenode(t: anytype) @TypeOf(if (isdummy(t) != 0) @as(c_int, 0) else sizenode(t)) {
    _ = &t;
    return if (isdummy(t) != 0) @as(c_int, 0) else sizenode(t);
}
pub const nodefromval = @compileError("unable to translate C expr: unexpected token ','");
// /src/cosmopolitan/third_party/lua/ltable.h:29:9
pub const ltm_h = "";
pub const maskflags = ~(~@as(c_uint, 0) << (TM_EQ + @as(c_int, 1)));
pub inline fn notm(tm: anytype) @TypeOf(ttisnil(tm)) {
    _ = &tm;
    return ttisnil(tm);
}
pub inline fn gfasttm(g: anytype, et: anytype, e: anytype) @TypeOf(if (et == NULL) NULL else if ((et.*.flags & (@as(c_uint, 1) << e)) != 0) NULL else luaT_gettm(et, e, g.*.tmname[@as(usize, @intCast(e))])) {
    _ = &g;
    _ = &et;
    _ = &e;
    return if (et == NULL) NULL else if ((et.*.flags & (@as(c_uint, 1) << e)) != 0) NULL else luaT_gettm(et, e, g.*.tmname[@as(usize, @intCast(e))]);
}
pub inline fn fasttm(l: anytype, et: anytype, e: anytype) @TypeOf(gfasttm(G(l), et, e)) {
    _ = &l;
    _ = &et;
    _ = &e;
    return gfasttm(G(l), et, e);
}
pub inline fn ttypename(x: anytype) @TypeOf(luaT_typenames_[@as(usize, @intCast(x + @as(c_int, 1)))]) {
    _ = &x;
    return luaT_typenames_[@as(usize, @intCast(x + @as(c_int, 1)))];
}
pub const lundump_h = "";
pub const LUAC_DATA = "\x19\x93\r\n\x1a\n";
pub const LUAC_INT = @as(c_int, 0x5678);
pub const LUAC_NUM = cast_num(@as(f64, 370.5));
pub inline fn MYINT(s: anytype) @TypeOf(s[@as(usize, @intCast(@as(c_int, 0)))] - '0') {
    _ = &s;
    return s[@as(usize, @intCast(@as(c_int, 0)))] - '0';
}
pub const LUAC_VERSION = (MYINT(LUA_VERSION_MAJOR) * @as(c_int, 16)) + MYINT(LUA_VERSION_MINOR);
pub const LUAC_FORMAT = @as(c_int, 0);
pub const lvm_h = "";
pub const ldo_h = "";
pub const luaD_checkstackaux = @compileError("unable to translate C expr: unexpected token 'if'");
// /src/cosmopolitan/third_party/lua/ldo.h:18:9
pub inline fn luaD_checkstack(L: anytype, n: anytype) @TypeOf(luaD_checkstackaux(L, n, @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)), @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)))) {
    _ = &L;
    _ = &n;
    return luaD_checkstackaux(L, n, @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)), @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)));
}
pub inline fn savestack(L: anytype, pt: anytype) @TypeOf(cast_charp(pt) - cast_charp(L.*.stack.p)) {
    _ = &L;
    _ = &pt;
    return cast_charp(pt) - cast_charp(L.*.stack.p);
}
pub inline fn restorestack(L: anytype, n: anytype) @TypeOf(cast(StkId, cast_charp(L.*.stack.p) + n)) {
    _ = &L;
    _ = &n;
    return cast(StkId, cast_charp(L.*.stack.p) + n);
}
pub const checkstackp = @compileError("unable to translate macro: undefined identifier `t__`");
// /src/cosmopolitan/third_party/lua/ldo.h:33:9
pub const checkstackGCp = @compileError("unable to translate macro: undefined identifier `t__`");
// /src/cosmopolitan/third_party/lua/ldo.h:40:9
pub inline fn checkstackGC(L: anytype, fsize: anytype) @TypeOf(luaD_checkstackaux(L, fsize, luaC_checkGC(L), @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)))) {
    _ = &L;
    _ = &fsize;
    return luaD_checkstackaux(L, fsize, luaC_checkGC(L), @import("std").zig.c_translation.cast(anyopaque, @as(c_int, 0)));
}
pub inline fn cvt2str(o: anytype) @TypeOf(ttisnumber(o)) {
    _ = &o;
    return ttisnumber(o);
}
pub inline fn cvt2num(o: anytype) @TypeOf(ttisstring(o)) {
    _ = &o;
    return ttisstring(o);
}
pub const LUA_FLOORN2I = F2Ieq;
pub const tonumber = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lvm.h:44:9
pub const tonumberns = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lvm.h:49:9
pub const tointeger = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lvm.h:55:9
pub const tointegerns = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lvm.h:61:9
pub inline fn intop(op: anytype, v1: anytype, v2: anytype) @TypeOf(l_castU2S(l_castS2U(v1) ++ op ++ l_castS2U(v2))) {
    _ = &op;
    _ = &v1;
    _ = &v2;
    return l_castU2S(l_castS2U(v1) ++ op ++ l_castS2U(v2));
}
pub inline fn luaV_rawequalobj(t1: anytype, t2: anytype) @TypeOf(luaV_equalobj(NULL, t1, t2)) {
    _ = &t1;
    _ = &t2;
    return luaV_equalobj(NULL, t1, t2);
}
pub const luaV_fastget = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lvm.h:78:9
pub const luaV_fastgeti = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/lvm.h:89:9
pub const luaV_finishfastset = @compileError("unable to translate C expr: unexpected token '{'");
// /src/cosmopolitan/third_party/lua/lvm.h:101:9
pub const luaV_shiftr = @compileError("unable to translate C expr: unexpected token ','");
// /src/cosmopolitan/third_party/lua/lvm.h:109:9
pub inline fn errorstatus(s: anytype) @TypeOf(s > LUA_YIELD) {
    _ = &s;
    return s > LUA_YIELD;
}
pub inline fn LUAI_THROW(L: anytype, c: anytype) @TypeOf(longjmp(c.*.b, @as(c_int, 1))) {
    _ = &L;
    _ = &c;
    return longjmp(c.*.b, @as(c_int, 1));
}
pub const LUAI_TRY = @compileError("unable to translate C expr: unexpected token 'if'");
// /tmp/ldo_patched.c:86:9
pub const luai_jmpbuf = jmp_buf;
pub const ERRORSTACKSIZE = LUAI_MAXSTACK + @as(c_int, 200);
pub inline fn next_ci(L: anytype) @TypeOf(if (L.*.ci.*.next != 0) L.*.ci.*.next else luaE_extendCI(L)) {
    _ = &L;
    return if (L.*.ci.*.next != 0) L.*.ci.*.next else luaE_extendCI(L);
}
pub const termios = struct_termios;
pub const winsize = struct_winsize;
pub const lconv = struct_lconv;
pub const lua_longjmp = struct_lua_longjmp;
pub const Zio = struct_Zio;
pub const GCUnion = union_GCUnion;
pub const OpMode = enum_OpMode;
pub const BlockCnt = struct_BlockCnt;
pub const SParser = struct_SParser;
pub const CloseP = struct_CloseP;
