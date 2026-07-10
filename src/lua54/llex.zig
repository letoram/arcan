// ---------------------------------------------------------------------------
// Lua 5.4 lexer (llex.c) -- translate-c output, cleaned up.
//
// Lines below this header replace ~500 lines of dead C library declarations
// (POSIX, math, stdio, string, stdlib, termios, etc.) that translate-c pulled
// in from system headers. Only declarations actually referenced by the Lua
// code that follows are retained.
// ---------------------------------------------------------------------------
const std = @import("std");
const mem = std.mem;
const c_builtins = std.zig.c_builtins;

// Builtin re-exports (used by _bsr, luai_likely/luai_unlikely macros)
pub const __builtin_clz = c_builtins.__builtin_clz;
pub const __builtin_expect = c_builtins.__builtin_expect;
pub const __builtin_nanf = c_builtins.__builtin_nanf;
pub const __builtin_inff = c_builtins.__builtin_inff;
pub const __builtin_isinf = c_builtins.__builtin_isinf;
pub const __builtin_isnan = c_builtins.__builtin_isnan;
pub const __builtin_signbit = c_builtins.__builtin_signbit;

// C type aliases (referenced by Lua internal structs and extern functions)
pub const wchar_t = c_uint;
pub const errno_t = c_int;
pub const ptrdiff_t = isize;
pub const wint_t = c_uint;
pub const intmax_t = c_long;
pub const uintmax_t = c_ulong;
pub const sig_atomic_t = c_int;

// Struct types (referenced by type aliases at end of file: termios, winsize)
pub const struct_termios = extern struct {
    c_iflag: u32 = 0,
    c_oflag: u32 = 0,
    c_cflag: u32 = 0,
    c_lflag: u32 = 0,
    c_cc: [20]u8 = mem.zeroes([20]u8),
    _c_ispeed: u32 = 0,
    _c_ospeed: u32 = 0,
};
pub const struct_winsize = extern struct {
    ws_row: u16 = 0,
    ws_col: u16 = 0,
    ws_xpixel: u16 = 0,
    ws_ypixel: u16 = 0,
};

// va_list (needed by lua_pushvfstring, luaO_pushvfstring, va_list alias)
pub const struct___va_list_1 = extern struct {
    __stack: ?*anyopaque = null,
    __gr_top: ?*anyopaque = null,
    __vr_top: ?*anyopaque = null,
    __gr_offs: c_int = 0,
    __vr_offs: c_int = 0,
};
pub const __builtin_va_list = struct___va_list_1;

// C library functions (used by Lua inline helper macros: lua_str2number,
// l_sprintf, strlcpy, strlcat, xrealloc, __die)
pub extern fn strtod([*c]const u8, [*c][*c]u8) f64;
pub extern fn strlen([*c]const u8) c_ulong;
pub extern fn strncat([*c]u8, [*c]const u8, usize) [*c]u8;
pub extern fn strncpy([*c]u8, [*c]const u8, usize) [*c]u8;
pub extern fn realloc(?*anyopaque, usize) ?*anyopaque;
pub extern fn abort() noreturn;
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
pub const lua_KFunction = ?*const fn ([*c]lua_State, c_int, lua_KContext) callconv(.c) c_int;
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
pub const struct_lua_longjmp = opaque {};
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
    errorJmp: ?*struct_lua_longjmp = @import("std").mem.zeroes(?*struct_lua_longjmp),
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
pub extern fn lua_yieldk(L: [*c]lua_State, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) c_int;
pub extern fn lua_resume(L: [*c]lua_State, from: [*c]lua_State, narg: c_int, nres: [*c]c_int) c_int;
pub extern fn lua_status(L: [*c]lua_State) c_int;
pub extern fn lua_isyieldable(L: [*c]lua_State) c_int;
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
    _ = &x;
    return if ((blk: {
        const ref = &x;
        ref.* -%= 1;
        break :blk ref.*;
    }) != 0) @as(c_int, 32) - __builtin_clz(x) else @as(c_int, 0);
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
pub const TK_AND: c_int = 256;
pub const TK_BREAK: c_int = 257;
pub const TK_DO: c_int = 258;
pub const TK_ELSE: c_int = 259;
pub const TK_ELSEIF: c_int = 260;
pub const TK_END: c_int = 261;
pub const TK_FALSE: c_int = 262;
pub const TK_FOR: c_int = 263;
pub const TK_FUNCTION: c_int = 264;
pub const TK_GOTO: c_int = 265;
pub const TK_IF: c_int = 266;
pub const TK_IN: c_int = 267;
pub const TK_LOCAL: c_int = 268;
pub const TK_NIL: c_int = 269;
pub const TK_NOT: c_int = 270;
pub const TK_OR: c_int = 271;
pub const TK_REPEAT: c_int = 272;
pub const TK_RETURN: c_int = 273;
pub const TK_THEN: c_int = 274;
pub const TK_TRUE: c_int = 275;
pub const TK_UNTIL: c_int = 276;
pub const TK_WHILE: c_int = 277;
pub const TK_IDIV: c_int = 278;
pub const TK_CONCAT: c_int = 279;
pub const TK_DOTS: c_int = 280;
pub const TK_EQ: c_int = 281;
pub const TK_GE: c_int = 282;
pub const TK_LE: c_int = 283;
pub const TK_NE: c_int = 284;
pub const TK_SHL: c_int = 285;
pub const TK_SHR: c_int = 286;
pub const TK_DBCOLON: c_int = 287;
pub const TK_EOS: c_int = 288;
pub const TK_FLT: c_int = 289;
pub const TK_INT: c_int = 290;
pub const TK_NAME: c_int = 291;
pub const TK_STRING: c_int = 292;
pub const enum_RESERVED = c_uint;
pub const SemInfo = extern union {
    r: lua_Number,
    i: lua_Integer,
    ts: [*c]TString,
};
pub const struct_Token = extern struct {
    token: c_int = @import("std").mem.zeroes(c_int),
    seminfo: SemInfo = @import("std").mem.zeroes(SemInfo),
};
pub const Token = struct_Token;
pub const struct_BlockCnt = opaque {};
pub const struct_FuncState = extern struct {
    f: [*c]Proto = @import("std").mem.zeroes([*c]Proto),
    prev: [*c]struct_FuncState = @import("std").mem.zeroes([*c]struct_FuncState),
    ls: [*c]struct_LexState = @import("std").mem.zeroes([*c]struct_LexState),
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
const struct_unnamed_15 = extern struct {
    value_: Value = @import("std").mem.zeroes(Value),
    tt_: lu_byte = @import("std").mem.zeroes(lu_byte),
    kind: lu_byte = @import("std").mem.zeroes(lu_byte),
    ridx: lu_byte = @import("std").mem.zeroes(lu_byte),
    pidx: c_short = @import("std").mem.zeroes(c_short),
    name: [*c]TString = @import("std").mem.zeroes([*c]TString),
};
pub const union_Vardesc = extern union {
    vd: struct_unnamed_15,
    k: TValue,
};
pub const Vardesc = union_Vardesc;
const struct_unnamed_14 = extern struct {
    arr: [*c]Vardesc = @import("std").mem.zeroes([*c]Vardesc),
    n: c_int = @import("std").mem.zeroes(c_int),
    size: c_int = @import("std").mem.zeroes(c_int),
};
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
pub const struct_Dyndata = extern struct {
    actvar: struct_unnamed_14 = @import("std").mem.zeroes(struct_unnamed_14),
    gt: Labellist = @import("std").mem.zeroes(Labellist),
    label: Labellist = @import("std").mem.zeroes(Labellist),
};
pub const struct_LexState = extern struct {
    current: c_int = @import("std").mem.zeroes(c_int),
    linenumber: c_int = @import("std").mem.zeroes(c_int),
    lastline: c_int = @import("std").mem.zeroes(c_int),
    t: Token = @import("std").mem.zeroes(Token),
    lookahead: Token = @import("std").mem.zeroes(Token),
    fs: [*c]struct_FuncState = @import("std").mem.zeroes([*c]struct_FuncState),
    L: [*c]struct_lua_State = @import("std").mem.zeroes([*c]struct_lua_State),
    z: [*c]ZIO = @import("std").mem.zeroes([*c]ZIO),
    buff: [*c]Mbuffer = @import("std").mem.zeroes([*c]Mbuffer),
    h: [*c]Table = @import("std").mem.zeroes([*c]Table),
    dyd: [*c]struct_Dyndata = @import("std").mem.zeroes([*c]struct_Dyndata),
    source: [*c]TString = @import("std").mem.zeroes([*c]TString),
    envn: [*c]TString = @import("std").mem.zeroes([*c]TString),
};
pub const LexState = struct_LexState;
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
pub export fn luaX_init(arg_L: [*c]lua_State) void {
    var L = arg_L;
    _ = &L;
    var i: c_int = undefined;
    _ = &i;
    var e: [*c]TString = luaS_newlstr(L, "_ENV", (@sizeOf([5]u8) / @sizeOf(u8)) -% @as(usize, @bitCast(@as(isize, @as(c_int, 1)))));
    _ = &e;
    luaC_fix(L, blk: {
        _ = @as(c_int, 0);
        break :blk &@as([*c]union_GCUnion, @ptrCast(@alignCast(e))).*.gc;
    });
    {
        i = 0;
        while (i < ((TK_WHILE - (@as(c_int, 255) + @as(c_int, 1))) + @as(c_int, 1))) : (i += 1) {
            var ts: [*c]TString = luaS_new(L, luaX_tokens[@as(c_uint, @intCast(i))]);
            _ = &ts;
            luaC_fix(L, blk: {
                _ = @as(c_int, 0);
                break :blk &@as([*c]union_GCUnion, @ptrCast(@alignCast(ts))).*.gc;
            });
            ts.*.extra = @as(lu_byte, @bitCast(@as(i8, @truncate(i + @as(c_int, 1)))));
        }
    }
}
pub export fn luaX_setinput(arg_L: [*c]lua_State, arg_ls: [*c]LexState, arg_z: [*c]ZIO, arg_source: [*c]TString, arg_firstchar: c_int) void {
    var L = arg_L;
    _ = &L;
    var ls = arg_ls;
    _ = &ls;
    var z = arg_z;
    _ = &z;
    var source = arg_source;
    _ = &source;
    var firstchar = arg_firstchar;
    _ = &firstchar;
    ls.*.t.token = 0;
    ls.*.L = L;
    ls.*.current = firstchar;
    ls.*.lookahead.token = TK_EOS;
    ls.*.z = z;
    ls.*.fs = null;
    ls.*.linenumber = 1;
    ls.*.lastline = 1;
    ls.*.source = source;
    ls.*.envn = luaS_newlstr(L, "_ENV", (@sizeOf([5]u8) / @sizeOf(u8)) -% @as(usize, @bitCast(@as(isize, @as(c_int, 1)))));
    _ = blk: {
        ls.*.buff.*.buffer = @as([*c]u8, @ptrCast(@alignCast(luaM_saferealloc_(ls.*.L, @as(?*anyopaque, @ptrCast(ls.*.buff.*.buffer)), ls.*.buff.*.buffsize *% @sizeOf(u8), @as(usize, @bitCast(@as(isize, @as(c_int, 32)))) *% @sizeOf(u8)))));
        break :blk blk_1: {
            const tmp = @as(usize, @bitCast(@as(isize, @as(c_int, 32))));
            ls.*.buff.*.buffsize = tmp;
            break :blk_1 tmp;
        };
    };
}
pub export fn luaX_newstring(arg_ls: [*c]LexState, arg_str: [*c]const u8, arg_l: usize) [*c]TString {
    var ls = arg_ls;
    _ = &ls;
    var str = arg_str;
    _ = &str;
    var l = arg_l;
    _ = &l;
    var L: [*c]lua_State = ls.*.L;
    _ = &L;
    var ts: [*c]TString = luaS_newlstr(L, str, l);
    _ = &ts;
    var o: [*c]const TValue = luaH_getstr(ls.*.h, ts);
    _ = &o;
    if (!((@as(c_int, @bitCast(@as(c_uint, o.*.tt_))) & @as(c_int, 15)) == @as(c_int, 0))) {
        ts = blk: {
            _ = @as(c_int, 0);
            break :blk &@as([*c]union_GCUnion, @ptrCast(@alignCast(@as([*c]Node, @ptrCast(@constCast(@volatileCast(o)))).*.u.key_val.gc))).*.ts;
        };
    } else {
        var stv: [*c]TValue = &(blk: {
            const ref = &L.*.top.p;
            const tmp = ref.*;
            ref.* += 1;
            break :blk tmp;
        }).*.val;
        _ = &stv;
        {
            var io: [*c]TValue = stv;
            _ = &io;
            var x_: [*c]TString = ts;
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
        luaH_finishset(L, ls.*.h, stv, o, stv);
        {
            if (L.*.l_G.*.GCdebt > @as(l_mem, @bitCast(@as(isize, @as(c_int, 0))))) {
                _ = @as(c_int, 0);
                luaC_step(L);
                _ = @as(c_int, 0);
            }
            _ = @as(c_int, 0);
        }
        L.*.top.p -= 1;
    }
    return ts;
}
pub export fn luaX_next(arg_ls: [*c]LexState) void {
    var ls = arg_ls;
    _ = &ls;
    ls.*.lastline = ls.*.linenumber;
    if (ls.*.lookahead.token != TK_EOS) {
        ls.*.t = ls.*.lookahead;
        ls.*.lookahead.token = TK_EOS;
    } else {
        ls.*.t.token = llex(ls, &ls.*.t.seminfo);
    }
}
pub export fn luaX_lookahead(arg_ls: [*c]LexState) c_int {
    var ls = arg_ls;
    _ = &ls;
    _ = @as(c_int, 0);
    ls.*.lookahead.token = llex(ls, &ls.*.lookahead.seminfo);
    return ls.*.lookahead.token;
}
pub export fn luaX_syntaxerror(arg_ls: [*c]LexState, arg_msg: [*c]const u8) noreturn {
    var ls = arg_ls;
    _ = &ls;
    var msg = arg_msg;
    _ = &msg;
    lexerror(ls, msg, ls.*.t.token);
}
pub export fn luaX_token2str(arg_ls: [*c]LexState, arg_token: c_int) [*c]const u8 {
    var ls = arg_ls;
    _ = &ls;
    var token = arg_token;
    _ = &token;
    if (token < (@as(c_int, 255) + @as(c_int, 1))) {
        if ((blk: {
            var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(token))));
            _ = &c_;
            break :blk (@as(c_int, 32) <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 126));
        })) {
            var fmtbuf: [32]u8 = undefined;
            const result = std.fmt.bufPrintZ(&fmtbuf, "'{c}'", .{@as(u8, @bitCast(@as(i8, @truncate(token))))}) catch "'?'";
            return lua_pushstring(ls.*.L, result);
        } else {
            var fmtbuf: [32]u8 = undefined;
            const result = std.fmt.bufPrintZ(&fmtbuf, "'<\\{d}>'", .{token}) catch "'<?>'";
            return lua_pushstring(ls.*.L, result);
        }
    } else {
        var s: [*c]const u8 = luaX_tokens[@as(c_uint, @intCast(token - (@as(c_int, 255) + @as(c_int, 1))))];
        _ = &s;
        if (token < TK_EOS) {
            var fmtbuf: [64]u8 = undefined;
            const result = std.fmt.bufPrintZ(&fmtbuf, "'{s}'", .{std.mem.span(@as([*:0]const u8, @ptrCast(s)))}) catch "'?'";
            return lua_pushstring(ls.*.L, result);
        } else return s;
    }
    return null;
}
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
pub const Pfunc = ?*const fn ([*c]lua_State, ?*anyopaque) callconv(.c) void;
pub extern fn luaD_seterrorobj(L: [*c]lua_State, errcode: c_int, oldtop: StkId) void;
pub extern fn luaD_protectedparser(L: [*c]lua_State, z: [*c]ZIO, name: [*c]const u8, mode: [*c]const u8) c_int;
pub extern fn luaD_hook(L: [*c]lua_State, event: c_int, line: c_int, fTransfer: c_int, nTransfer: c_int) void;
pub extern fn luaD_hookcall(L: [*c]lua_State, ci: [*c]CallInfo) void;
pub extern fn luaD_pretailcall(L: [*c]lua_State, ci: [*c]CallInfo, func: StkId, narg1: c_int, delta: c_int) c_int;
pub extern fn luaD_precall(L: [*c]lua_State, func: StkId, nResults: c_int) [*c]CallInfo;
pub extern fn luaD_call(L: [*c]lua_State, func: StkId, nResults: c_int) void;
pub extern fn luaD_callnoyield(L: [*c]lua_State, func: StkId, nResults: c_int) void;
pub extern fn luaD_tryfuncTM(L: [*c]lua_State, func: StkId) StkId;
pub extern fn luaD_closeprotected(L: [*c]lua_State, level: ptrdiff_t, status: c_int) c_int;
pub extern fn luaD_pcall(L: [*c]lua_State, func: Pfunc, u: ?*anyopaque, oldtop: ptrdiff_t, ef: ptrdiff_t) c_int;
pub extern fn luaD_poscall(L: [*c]lua_State, ci: [*c]CallInfo, nres: c_int) void;
pub extern fn luaD_reallocstack(L: [*c]lua_State, newsize: c_int, raiseerror: c_int) c_int;
pub extern fn luaD_growstack(L: [*c]lua_State, n: c_int, raiseerror: c_int) c_int;
pub extern fn luaD_shrinkstack(L: [*c]lua_State) void;
pub extern fn luaD_inctop(L: [*c]lua_State) void;
pub extern fn luaD_throw(L: [*c]lua_State, errcode: c_int) noreturn;
pub extern fn luaD_rawrunprotected(L: [*c]lua_State, f: Pfunc, ud: ?*anyopaque) c_int;
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
const struct_unnamed_17 = extern struct {
    idx: c_short = @import("std").mem.zeroes(c_short),
    t: lu_byte = @import("std").mem.zeroes(lu_byte),
};
const struct_unnamed_18 = extern struct {
    ridx: lu_byte = @import("std").mem.zeroes(lu_byte),
    vidx: c_ushort = @import("std").mem.zeroes(c_ushort),
};
const union_unnamed_16 = extern union {
    ival: lua_Integer,
    nval: lua_Number,
    strval: [*c]TString,
    info: c_int,
    ind: struct_unnamed_17,
    @"var": struct_unnamed_18,
};
pub const struct_expdesc = extern struct {
    k: expkind = @import("std").mem.zeroes(expkind),
    u: union_unnamed_16 = @import("std").mem.zeroes(union_unnamed_16),
    t: c_int = @import("std").mem.zeroes(c_int),
    f: c_int = @import("std").mem.zeroes(c_int),
};
pub const expdesc = struct_expdesc;
pub const Dyndata = struct_Dyndata;
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
comptime {
    // asm (".section .yoink\n\tb\t\"lua_notice\"\n\t.previous");
}
pub const luaX_tokens: [37][*c]const u8 = [37][*c]const u8{
    "and",
    "break",
    "do",
    "else",
    "elseif",
    "end",
    "false",
    "for",
    "function",
    "goto",
    "if",
    "in",
    "local",
    "nil",
    "not",
    "or",
    "repeat",
    "return",
    "then",
    "true",
    "until",
    "while",
    "//",
    "..",
    "...",
    "==",
    ">=",
    "<=",
    "~=",
    "<<",
    ">>",
    "::",
    "<eof>",
    "<number>",
    "<integer>",
    "<name>",
    "<string>",
};
pub fn lexerror(arg_ls: [*c]LexState, arg_msg: [*c]const u8, arg_token: c_int) callconv(.c) noreturn {
    var ls = arg_ls;
    _ = &ls;
    var msg = arg_msg;
    _ = &msg;
    var token = arg_token;
    _ = &token;
    msg = luaG_addinfo(ls.*.L, msg, ls.*.source, ls.*.linenumber);
    if (token != 0) {
        {
            var fmtbuf: [512]u8 = undefined;
            const result = std.fmt.bufPrintZ(&fmtbuf, "{s} near {s}", .{
                std.mem.span(@as([*:0]const u8, @ptrCast(msg))),
                std.mem.span(@as([*:0]const u8, @ptrCast(txtToken(ls, token)))),
            }) catch "? near ?";
            _ = lua_pushstring(ls.*.L, result);
        }
    }
    luaD_throw(ls.*.L, @as(c_int, 3));
}
pub fn save(arg_ls: [*c]LexState, arg_c: c_int) callconv(.c) void {
    var ls = arg_ls;
    _ = &ls;
    var c = arg_c;
    _ = &c;
    var b: [*c]Mbuffer = ls.*.buff;
    _ = &b;
    if ((b.*.n +% @as(usize, @bitCast(@as(isize, @as(c_int, 1))))) > b.*.buffsize) {
        var newsize: usize = undefined;
        _ = &newsize;
        if (b.*.buffsize >= ((if (@sizeOf(usize) < @sizeOf(lua_Integer)) ~@as(usize, @bitCast(@as(isize, @as(c_int, 0)))) else @as(usize, @bitCast(@as(isize, @truncate(@as(c_longlong, 9223372036854775807)))))) / @as(usize, @bitCast(@as(isize, @as(c_int, 2)))))) {
            lexerror(ls, "lexical element too long", @as(c_int, 0));
        }
        newsize = b.*.buffsize *% @as(usize, @bitCast(@as(isize, @as(c_int, 2))));
        _ = blk: {
            b.*.buffer = @as([*c]u8, @ptrCast(@alignCast(luaM_saferealloc_(ls.*.L, @as(?*anyopaque, @ptrCast(b.*.buffer)), b.*.buffsize *% @sizeOf(u8), newsize *% @sizeOf(u8)))));
            break :blk blk_1: {
                const tmp = newsize;
                b.*.buffsize = tmp;
                break :blk_1 tmp;
            };
        };
    }
    b.*.buffer[blk: {
        const ref = &b.*.n;
        const tmp = ref.*;
        ref.* +%= 1;
        break :blk tmp;
    }] = @as(u8, @bitCast(@as(i8, @truncate(c))));
}
pub fn txtToken(arg_ls: [*c]LexState, arg_token: c_int) callconv(.c) [*c]const u8 {
    var ls = arg_ls;
    _ = &ls;
    var token = arg_token;
    _ = &token;
    while (true) {
        switch (token) {
            @as(c_int, 291), @as(c_int, 292), @as(c_int, 289), @as(c_int, 290) => {
                save(ls, @as(c_int, '\x00'));
                {
                    var fmtbuf: [512]u8 = undefined;
                    const result = std.fmt.bufPrintZ(&fmtbuf, "'{s}'", .{
                        std.mem.span(@as([*:0]const u8, @ptrCast(ls.*.buff.*.buffer))),
                    }) catch "'?'";
                    return lua_pushstring(ls.*.L, result);
                }
            },
            else => return luaX_token2str(ls, token),
        }
        break;
    }
    return null;
}
pub fn inclinenumber(arg_ls: [*c]LexState) callconv(.c) void {
    var ls = arg_ls;
    _ = &ls;
    var old: c_int = ls.*.current;
    _ = &old;
    _ = @as(c_int, 0);
    _ = blk: {
        const tmp = if ((blk_1: {
            const ref = &ls.*.z.*.n;
            const tmp_2 = ref.*;
            ref.* -%= 1;
            break :blk_1 tmp_2;
        }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
            const ref = &ls.*.z.*.p;
            const tmp_2 = ref.*;
            ref.* += 1;
            break :blk_1 tmp_2;
        }).*))))) else luaZ_fill(ls.*.z);
        ls.*.current = tmp;
        break :blk tmp;
    };
    if (((ls.*.current == @as(c_int, '\n')) or (ls.*.current == @as(c_int, '\r'))) and (ls.*.current != old)) {
        _ = blk: {
            const tmp = if ((blk_1: {
                const ref = &ls.*.z.*.n;
                const tmp_2 = ref.*;
                ref.* -%= 1;
                break :blk_1 tmp_2;
            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                const ref = &ls.*.z.*.p;
                const tmp_2 = ref.*;
                ref.* += 1;
                break :blk_1 tmp_2;
            }).*))))) else luaZ_fill(ls.*.z);
            ls.*.current = tmp;
            break :blk tmp;
        };
    }
    if ((blk: {
        const ref = &ls.*.linenumber;
        ref.* += 1;
        break :blk ref.*;
    }) >= @as(c_int, 2147483647)) {
        lexerror(ls, "chunk has too many lines", @as(c_int, 0));
    }
}
pub fn check_next1(arg_ls: [*c]LexState, arg_c: c_int) callconv(.c) c_int {
    var ls = arg_ls;
    _ = &ls;
    var c = arg_c;
    _ = &c;
    if (ls.*.current == c) {
        _ = blk: {
            const tmp = if ((blk_1: {
                const ref = &ls.*.z.*.n;
                const tmp_2 = ref.*;
                ref.* -%= 1;
                break :blk_1 tmp_2;
            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                const ref = &ls.*.z.*.p;
                const tmp_2 = ref.*;
                ref.* += 1;
                break :blk_1 tmp_2;
            }).*))))) else luaZ_fill(ls.*.z);
            ls.*.current = tmp;
            break :blk tmp;
        };
        return 1;
    } else return 0;
    return 0;
}
pub fn check_next2(arg_ls: [*c]LexState, arg_set: [*c]const u8) callconv(.c) c_int {
    var ls = arg_ls;
    _ = &ls;
    var set = arg_set;
    _ = &set;
    _ = @as(c_int, 0);
    if ((ls.*.current == @as(c_int, @bitCast(@as(c_uint, set[@as(c_uint, @intCast(@as(c_int, 0)))])))) or (ls.*.current == @as(c_int, @bitCast(@as(c_uint, set[@as(c_uint, @intCast(@as(c_int, 1)))]))))) {
        _ = blk: {
            save(ls, ls.*.current);
            break :blk blk_1: {
                const tmp = if ((blk_2: {
                    const ref = &ls.*.z.*.n;
                    const tmp_3 = ref.*;
                    ref.* -%= 1;
                    break :blk_2 tmp_3;
                }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                    const ref = &ls.*.z.*.p;
                    const tmp_3 = ref.*;
                    ref.* += 1;
                    break :blk_2 tmp_3;
                }).*))))) else luaZ_fill(ls.*.z);
                ls.*.current = tmp;
                break :blk_1 tmp;
            };
        };
        return 1;
    } else return 0;
    return 0;
}
pub fn read_numeral(arg_ls: [*c]LexState, arg_seminfo: [*c]SemInfo) callconv(.c) c_int {
    var ls = arg_ls;
    _ = &ls;
    var seminfo = arg_seminfo;
    _ = &seminfo;
    var obj: TValue = undefined;
    _ = &obj;
    var expo: [*c]const u8 = "Ee";
    _ = &expo;
    var first: c_int = ls.*.current;
    _ = &first;
    _ = @as(c_int, 0);
    _ = blk: {
        save(ls, ls.*.current);
        break :blk blk_1: {
            const tmp = if ((blk_2: {
                const ref = &ls.*.z.*.n;
                const tmp_3 = ref.*;
                ref.* -%= 1;
                break :blk_2 tmp_3;
            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                const ref = &ls.*.z.*.p;
                const tmp_3 = ref.*;
                ref.* += 1;
                break :blk_2 tmp_3;
            }).*))))) else luaZ_fill(ls.*.z);
            ls.*.current = tmp;
            break :blk_1 tmp;
        };
    };
    if ((first == @as(c_int, '0')) and (check_next2(ls, "xX") != 0)) {
        expo = "Pp";
    }
    while (true) {
        if (check_next2(ls, expo) != 0) {
            _ = check_next2(ls, "-+");
        } else if (((blk: {
            var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(ls.*.current))));
            _ = &c_;
            break :blk (((@as(c_int, '0') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, '9'))) or ((@as(c_int, 'A') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'F')))) or ((@as(c_int, 'a') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'f')));
        })) or (ls.*.current == @as(c_int, '.'))) {
            _ = blk: {
                save(ls, ls.*.current);
                break :blk blk_1: {
                    const tmp = if ((blk_2: {
                        const ref = &ls.*.z.*.n;
                        const tmp_3 = ref.*;
                        ref.* -%= 1;
                        break :blk_2 tmp_3;
                    }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                        const ref = &ls.*.z.*.p;
                        const tmp_3 = ref.*;
                        ref.* += 1;
                        break :blk_2 tmp_3;
                    }).*))))) else luaZ_fill(ls.*.z);
                    ls.*.current = tmp;
                    break :blk_1 tmp;
                };
            };
        } else break;
    }
    if ((blk: {
        var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(ls.*.current))));
        _ = &c_;
        break :blk (((@as(c_int, 'A') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'Z'))) or ((@as(c_int, 'a') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'z')))) or (@as(c_int, @bitCast(@as(c_uint, c_))) == @as(c_int, '_'));
    })) {
        _ = blk: {
            save(ls, ls.*.current);
            break :blk blk_1: {
                const tmp = if ((blk_2: {
                    const ref = &ls.*.z.*.n;
                    const tmp_3 = ref.*;
                    ref.* -%= 1;
                    break :blk_2 tmp_3;
                }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                    const ref = &ls.*.z.*.p;
                    const tmp_3 = ref.*;
                    ref.* += 1;
                    break :blk_2 tmp_3;
                }).*))))) else luaZ_fill(ls.*.z);
                ls.*.current = tmp;
                break :blk_1 tmp;
            };
        };
    }
    save(ls, @as(c_int, '\x00'));
    if (luaO_str2num(ls.*.buff.*.buffer, &obj) == @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) {
        lexerror(ls, "malformed number", TK_FLT);
    }
    if (@as(c_int, @bitCast(@as(c_uint, (&obj).*.tt_))) == (@as(c_int, 3) | (@as(c_int, 0) << @intCast(4)))) {
        seminfo.*.i = blk: {
            _ = @as(c_int, 0);
            break :blk (&obj).*.value_.i;
        };
        return TK_INT;
    } else {
        _ = @as(c_int, 0);
        seminfo.*.r = blk: {
            _ = @as(c_int, 0);
            break :blk (&obj).*.value_.n;
        };
        return TK_FLT;
    }
    return 0;
}
pub fn skip_sep(arg_ls: [*c]LexState) callconv(.c) usize {
    var ls = arg_ls;
    _ = &ls;
    var count: usize = 0;
    _ = &count;
    var s: c_int = ls.*.current;
    _ = &s;
    _ = @as(c_int, 0);
    _ = blk: {
        save(ls, ls.*.current);
        break :blk blk_1: {
            const tmp = if ((blk_2: {
                const ref = &ls.*.z.*.n;
                const tmp_3 = ref.*;
                ref.* -%= 1;
                break :blk_2 tmp_3;
            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                const ref = &ls.*.z.*.p;
                const tmp_3 = ref.*;
                ref.* += 1;
                break :blk_2 tmp_3;
            }).*))))) else luaZ_fill(ls.*.z);
            ls.*.current = tmp;
            break :blk_1 tmp;
        };
    };
    while (ls.*.current == @as(c_int, '=')) {
        _ = blk: {
            save(ls, ls.*.current);
            break :blk blk_1: {
                const tmp = if ((blk_2: {
                    const ref = &ls.*.z.*.n;
                    const tmp_3 = ref.*;
                    ref.* -%= 1;
                    break :blk_2 tmp_3;
                }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                    const ref = &ls.*.z.*.p;
                    const tmp_3 = ref.*;
                    ref.* += 1;
                    break :blk_2 tmp_3;
                }).*))))) else luaZ_fill(ls.*.z);
                ls.*.current = tmp;
                break :blk_1 tmp;
            };
        };
        count +%= 1;
    }
    return if (ls.*.current == s) count +% @as(usize, @bitCast(@as(isize, @as(c_int, 2)))) else @as(usize, @bitCast(@as(isize, if (count == @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, 1) else @as(c_int, 0))));
}
// Helper: next(ls) — zgetc inlined (translate-c failed on assignment + postfix inc)
fn llex_next(ls: [*c]LexState) void {
    const z = ls.*.z;
    if (z.*.n > 0) {
        z.*.n -= 1;
        ls.*.current = @as(c_int, @bitCast(@as(c_uint, z.*.p.*)));
        z.*.p += 1;
    } else {
        ls.*.current = luaZ_fill(z);
    }
}

// Helper: save_and_next(ls)
fn llex_save_and_next(ls: [*c]LexState) void {
    save(ls, ls.*.current);
    llex_next(ls);
}

// read_long_string — ported from llex.c (translate-c failed on goto endloop)
pub fn read_long_string(arg_ls: [*c]LexState, arg_seminfo: [*c]SemInfo, arg_sep: usize) callconv(.c) void {
    var ls = arg_ls;
    _ = &ls;
    const line = ls.*.linenumber;
    llex_save_and_next(ls); // skip 2nd '['
    if (currIsNewline(ls))
        inclinenumber(ls); // string starts with a newline — skip it
    while (true) {
        switch (ls.*.current) {
            EOZ => {
                const what: [*c]const u8 = if (arg_seminfo != null) "string" else "comment";
                var fmtbuf: [512]u8 = undefined;
                const msg = blk: {
                    const m = std.fmt.bufPrintZ(&fmtbuf, "unfinished long {s} (starting at line {d})", .{
                        std.mem.span(@as([*:0]const u8, @ptrCast(what))),
                        line,
                    }) catch "unfinished long ? (starting at line ?)";
                    break :blk lua_pushstring(@as([*c]lua_State, @ptrCast(ls.*.L)), m);
                };
                lexerror(ls, msg, TK_EOS);
            },
            ']' => {
                if (skip_sep(ls) == arg_sep) {
                    llex_save_and_next(ls); // skip 2nd ']'
                    break; // endloop
                }
            },
            '\n', '\r' => {
                save(ls, '\n');
                inclinenumber(ls);
                if (arg_seminfo == null) ls.*.buff.*.n = 0; // luaZ_resetbuffer
            },
            else => {
                if (arg_seminfo != null) {
                    llex_save_and_next(ls);
                } else {
                    llex_next(ls);
                }
            },
        }
    }
    // endloop:
    if (arg_seminfo != null) {
        arg_seminfo.*.ts = luaX_newstring(ls, ls.*.buff.*.buffer + arg_sep, ls.*.buff.*.n -% 2 *% arg_sep);
    }
}
pub fn esccheck(arg_ls: [*c]LexState, arg_c: c_int, arg_msg: [*c]const u8) callconv(.c) void {
    var ls = arg_ls;
    _ = &ls;
    var c = arg_c;
    _ = &c;
    var msg = arg_msg;
    _ = &msg;
    if (!(c != 0)) {
        if (ls.*.current != -@as(c_int, 1)) {
            _ = blk: {
                save(ls, ls.*.current);
                break :blk blk_1: {
                    const tmp = if ((blk_2: {
                        const ref = &ls.*.z.*.n;
                        const tmp_3 = ref.*;
                        ref.* -%= 1;
                        break :blk_2 tmp_3;
                    }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                        const ref = &ls.*.z.*.p;
                        const tmp_3 = ref.*;
                        ref.* += 1;
                        break :blk_2 tmp_3;
                    }).*))))) else luaZ_fill(ls.*.z);
                    ls.*.current = tmp;
                    break :blk_1 tmp;
                };
            };
        }
        lexerror(ls, msg, TK_STRING);
    }
}
pub fn gethexa(arg_ls: [*c]LexState) callconv(.c) c_int {
    var ls = arg_ls;
    _ = &ls;
    _ = blk: {
        save(ls, ls.*.current);
        break :blk blk_1: {
            const tmp = if ((blk_2: {
                const ref = &ls.*.z.*.n;
                const tmp_3 = ref.*;
                ref.* -%= 1;
                break :blk_2 tmp_3;
            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                const ref = &ls.*.z.*.p;
                const tmp_3 = ref.*;
                ref.* += 1;
                break :blk_2 tmp_3;
            }).*))))) else luaZ_fill(ls.*.z);
            ls.*.current = tmp;
            break :blk_1 tmp;
        };
    };
    esccheck(ls, @intFromBool(blk: {
        var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(ls.*.current))));
        _ = &c_;
        break :blk (((@as(c_int, '0') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, '9'))) or ((@as(c_int, 'A') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'F')))) or ((@as(c_int, 'a') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'f')));
    }), "hexadecimal digit expected");
    return luaO_hexavalue(ls.*.current);
}
pub fn readhexaesc(arg_ls: [*c]LexState) callconv(.c) c_int {
    var ls = arg_ls;
    _ = &ls;
    var r: c_int = gethexa(ls);
    _ = &r;
    r = (r << @intCast(4)) + gethexa(ls);
    _ = blk: {
        const ref = &ls.*.buff.*.n;
        ref.* -%= @as(usize, @bitCast(@as(isize, @as(c_int, 2))));
        break :blk ref.*;
    };
    return r;
}
pub fn readutf8esc(arg_ls: [*c]LexState) callconv(.c) usize {
    var ls = arg_ls;
    _ = &ls;
    var r: usize = undefined;
    _ = &r;
    var i: c_int = 4;
    _ = &i;
    _ = blk: {
        save(ls, ls.*.current);
        break :blk blk_1: {
            const tmp = if ((blk_2: {
                const ref = &ls.*.z.*.n;
                const tmp_3 = ref.*;
                ref.* -%= 1;
                break :blk_2 tmp_3;
            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                const ref = &ls.*.z.*.p;
                const tmp_3 = ref.*;
                ref.* += 1;
                break :blk_2 tmp_3;
            }).*))))) else luaZ_fill(ls.*.z);
            ls.*.current = tmp;
            break :blk_1 tmp;
        };
    };
    esccheck(ls, @intFromBool(ls.*.current == @as(c_int, '{')), "missing '{'");
    r = @as(usize, @bitCast(@as(isize, gethexa(ls))));
    while ((blk: {
        _ = blk_1: {
            save(ls, ls.*.current);
            break :blk_1 blk_2: {
                const tmp = if ((blk_3: {
                    const ref = &ls.*.z.*.n;
                    const tmp_4 = ref.*;
                    ref.* -%= 1;
                    break :blk_3 tmp_4;
                }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_3: {
                    const ref = &ls.*.z.*.p;
                    const tmp_4 = ref.*;
                    ref.* += 1;
                    break :blk_3 tmp_4;
                }).*))))) else luaZ_fill(ls.*.z);
                ls.*.current = tmp;
                break :blk_2 tmp;
            };
        };
        break :blk blk_1: {
            var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(ls.*.current))));
            _ = &c_;
            break :blk_1 (((@as(c_int, '0') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, '9'))) or ((@as(c_int, 'A') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'F')))) or ((@as(c_int, 'a') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'f')));
        };
    })) {
        i += 1;
        esccheck(ls, @intFromBool(r <= @as(usize, @bitCast(@as(usize, @as(c_uint, 2147483647) >> @intCast(4))))), "UTF-8 value too large");
        r = (r << @intCast(4)) +% @as(usize, @bitCast(@as(isize, luaO_hexavalue(ls.*.current))));
    }
    esccheck(ls, @intFromBool(ls.*.current == @as(c_int, '}')), "missing '}'");
    _ = blk: {
        const tmp = if ((blk_1: {
            const ref = &ls.*.z.*.n;
            const tmp_2 = ref.*;
            ref.* -%= 1;
            break :blk_1 tmp_2;
        }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
            const ref = &ls.*.z.*.p;
            const tmp_2 = ref.*;
            ref.* += 1;
            break :blk_1 tmp_2;
        }).*))))) else luaZ_fill(ls.*.z);
        ls.*.current = tmp;
        break :blk tmp;
    };
    _ = blk: {
        const ref = &ls.*.buff.*.n;
        ref.* -%= @as(usize, @bitCast(@as(isize, i)));
        break :blk ref.*;
    };
    return r;
}
pub fn utf8esc(arg_ls: [*c]LexState) callconv(.c) void {
    var ls = arg_ls;
    _ = &ls;
    var buff: [8]u8 = undefined;
    _ = &buff;
    var n: c_int = luaO_utf8esc(@as([*c]u8, @ptrCast(@alignCast(&buff[@as(usize, @intCast(0))]))), @intCast(readutf8esc(ls)));
    _ = &n;
    while (n > @as(c_int, 0)) : (n -= 1) {
        save(ls, @as(c_int, @bitCast(@as(c_uint, buff[@as(c_uint, @intCast(@as(c_int, 8) - n))]))));
    }
}
pub fn readdecesc(arg_ls: [*c]LexState) callconv(.c) c_int {
    var ls = arg_ls;
    _ = &ls;
    var i: c_int = undefined;
    _ = &i;
    var r: c_int = 0;
    _ = &r;
    {
        i = 0;
        while ((i < @as(c_int, 3)) and ((blk: {
            var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(ls.*.current))));
            _ = &c_;
            break :blk (@as(c_int, '0') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, '9'));
        }))) : (i += 1) {
            r = ((@as(c_int, 10) * r) + ls.*.current) - @as(c_int, '0');
            _ = blk: {
                save(ls, ls.*.current);
                break :blk blk_1: {
                    const tmp = if ((blk_2: {
                        const ref = &ls.*.z.*.n;
                        const tmp_3 = ref.*;
                        ref.* -%= 1;
                        break :blk_2 tmp_3;
                    }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                        const ref = &ls.*.z.*.p;
                        const tmp_3 = ref.*;
                        ref.* += 1;
                        break :blk_2 tmp_3;
                    }).*))))) else luaZ_fill(ls.*.z);
                    ls.*.current = tmp;
                    break :blk_1 tmp;
                };
            };
        }
    }
    esccheck(ls, @intFromBool(r <= @as(c_int, 255)), "decimal escape too large");
    _ = blk: {
        const ref = &ls.*.buff.*.n;
        ref.* -%= @as(usize, @bitCast(@as(isize, i)));
        break :blk ref.*;
    };
    return r;
}
// Inline helpers for lisdigit/lisspace (translate-c failed on GCC statement expressions)
fn llex_lisdigit(c_val: c_int) bool {
    if (c_val < 0) return false;
    const ch: u8 = @intCast(c_val & 0xff);
    return ch >= '0' and ch <= '9';
}
fn llex_lisspace(c_val: c_int) bool {
    if (c_val < 0) return false;
    const ch: u8 = @intCast(c_val & 0xff);
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' or ch == 0x0c or ch == 0x0b;
}

// read_string — ported from llex.c (translate-c failed on goto read_save/only_save/no_save)
pub fn read_string(arg_ls: [*c]LexState, arg_del: c_int, arg_seminfo: [*c]SemInfo) callconv(.c) void {
    var ls = arg_ls;
    _ = &ls;
    llex_save_and_next(ls); // keep delimiter (for error messages)
    while (ls.*.current != arg_del) {
        switch (ls.*.current) {
            EOZ => {
                lexerror(ls, "unfinished string", TK_EOS);
            },
            '\n', '\r' => {
                lexerror(ls, "unfinished string", TK_STRING);
            },
            '\\' => {
                // escape sequences
                var c: c_int = undefined;
                llex_save_and_next(ls); // keep '\\' for error messages
                // Action after inner switch:
                // 0 = no_save (just break), 1 = read_save, 2 = only_save
                var action: u2 = 0;
                switch (ls.*.current) {
                    'a' => { c = 0x07; action = 1; }, // \a
                    'b' => { c = 0x08; action = 1; }, // \b
                    'e' => { c = 0x1b; action = 1; }, // \e (extension)
                    'f' => { c = 0x0c; action = 1; }, // \f
                    'n' => { c = '\n'; action = 1; },
                    'r' => { c = '\r'; action = 1; },
                    't' => { c = '\t'; action = 1; },
                    'v' => { c = 0x0b; action = 1; }, // \v
                    'x' => { c = readhexaesc(ls); action = 1; },
                    'u' => { utf8esc(ls); action = 0; }, // no_save
                    '\n', '\r' => { inclinenumber(ls); c = '\n'; action = 2; }, // only_save
                    '\\', '"', '\'' => { c = ls.*.current; action = 1; }, // read_save
                    EOZ => { action = 0; }, // no_save — will raise error next loop
                    'z' => {
                        // zap following span of spaces
                        ls.*.buff.*.n -= 1; // luaZ_buffremove(ls->buff, 1)
                        llex_next(ls); // skip the 'z'
                        while (llex_lisspace(ls.*.current)) {
                            if (currIsNewline(ls)) {
                                inclinenumber(ls);
                            } else {
                                llex_next(ls);
                            }
                        }
                        action = 0; // no_save
                    },
                    else => {
                        esccheck(ls, @intFromBool(llex_lisdigit(ls.*.current)), "invalid escape sequence");
                        c = readdecesc(ls);
                        action = 2; // only_save
                    },
                }
                // Execute action:
                if (action == 1) {
                    // read_save: next(ls) then only_save
                    llex_next(ls);
                    // fall through to only_save
                    ls.*.buff.*.n -= 1; // luaZ_buffremove(ls->buff, 1) — remove '\\'
                    save(ls, c);
                } else if (action == 2) {
                    // only_save: remove '\\' then save(c)
                    ls.*.buff.*.n -= 1; // luaZ_buffremove(ls->buff, 1)
                    save(ls, c);
                }
                // action == 0: no_save — nothing to do
            },
            else => {
                llex_save_and_next(ls);
            },
        }
    }
    llex_save_and_next(ls); // skip delimiter
    arg_seminfo.*.ts = luaX_newstring(ls, ls.*.buff.*.buffer + 1, ls.*.buff.*.n -% 2);
}
pub fn llex(arg_ls: [*c]LexState, arg_seminfo: [*c]SemInfo) callconv(.c) c_int {
    var ls = arg_ls;
    _ = &ls;
    var seminfo = arg_seminfo;
    _ = &seminfo;
    _ = blk: {
        const tmp = @as(usize, @bitCast(@as(isize, @as(c_int, 0))));
        ls.*.buff.*.n = tmp;
        break :blk tmp;
    };
    while (true) {
        while (true) {
            switch (ls.*.current) {
                @as(c_int, 10), @as(c_int, 13) => {
                    {
                        inclinenumber(ls);
                        break;
                    }
                },
                @as(c_int, 32), @as(c_int, 12), @as(c_int, 9), @as(c_int, 11) => {
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        break;
                    }
                },
                @as(c_int, 45) => {
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (ls.*.current != @as(c_int, '-')) return '-';
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (ls.*.current == @as(c_int, '[')) {
                            var sep: usize = skip_sep(ls);
                            _ = &sep;
                            _ = blk: {
                                const tmp = @as(usize, @bitCast(@as(isize, @as(c_int, 0))));
                                ls.*.buff.*.n = tmp;
                                break :blk tmp;
                            };
                            if (sep >= @as(usize, @bitCast(@as(isize, @as(c_int, 2))))) {
                                read_long_string(ls, null, sep);
                                _ = blk: {
                                    const tmp = @as(usize, @bitCast(@as(isize, @as(c_int, 0))));
                                    ls.*.buff.*.n = tmp;
                                    break :blk tmp;
                                };
                                break;
                            }
                        }
                        while (!((ls.*.current == @as(c_int, '\n')) or (ls.*.current == @as(c_int, '\r'))) and (ls.*.current != -@as(c_int, 1))) {
                            _ = blk: {
                                const tmp = if ((blk_1: {
                                    const ref = &ls.*.z.*.n;
                                    const tmp_2 = ref.*;
                                    ref.* -%= 1;
                                    break :blk_1 tmp_2;
                                }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                    const ref = &ls.*.z.*.p;
                                    const tmp_2 = ref.*;
                                    ref.* += 1;
                                    break :blk_1 tmp_2;
                                }).*))))) else luaZ_fill(ls.*.z);
                                ls.*.current = tmp;
                                break :blk tmp;
                            };
                        }
                        break;
                    }
                },
                @as(c_int, 91) => {
                    {
                        var sep: usize = skip_sep(ls);
                        _ = &sep;
                        if (sep >= @as(usize, @bitCast(@as(isize, @as(c_int, 2))))) {
                            read_long_string(ls, seminfo, sep);
                            return TK_STRING;
                        } else if (sep == @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) {
                            lexerror(ls, "invalid long string delimiter", TK_STRING);
                        }
                        return '[';
                    }
                },
                @as(c_int, 61) => {
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_EQ else return '=';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_LE else if (check_next1(ls, @as(c_int, '<')) != 0) return TK_SHL else return '<';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_GE else if (check_next1(ls, @as(c_int, '>')) != 0) return TK_SHR else return '>';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '/')) != 0) return TK_IDIV else return '/';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_NE else return '~';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, ':')) != 0) return TK_DBCOLON else return ':';
                    }
                    {
                        read_string(ls, ls.*.current, seminfo);
                        return TK_STRING;
                    }
                },
                @as(c_int, 60) => {
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_LE else if (check_next1(ls, @as(c_int, '<')) != 0) return TK_SHL else return '<';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_GE else if (check_next1(ls, @as(c_int, '>')) != 0) return TK_SHR else return '>';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '/')) != 0) return TK_IDIV else return '/';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_NE else return '~';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, ':')) != 0) return TK_DBCOLON else return ':';
                    }
                    {
                        read_string(ls, ls.*.current, seminfo);
                        return TK_STRING;
                    }
                },
                @as(c_int, 62) => {
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_GE else if (check_next1(ls, @as(c_int, '>')) != 0) return TK_SHR else return '>';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '/')) != 0) return TK_IDIV else return '/';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_NE else return '~';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, ':')) != 0) return TK_DBCOLON else return ':';
                    }
                    {
                        read_string(ls, ls.*.current, seminfo);
                        return TK_STRING;
                    }
                },
                @as(c_int, 47) => {
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '/')) != 0) return TK_IDIV else return '/';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_NE else return '~';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, ':')) != 0) return TK_DBCOLON else return ':';
                    }
                    {
                        read_string(ls, ls.*.current, seminfo);
                        return TK_STRING;
                    }
                },
                @as(c_int, 126) => {
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, '=')) != 0) return TK_NE else return '~';
                    }
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, ':')) != 0) return TK_DBCOLON else return ':';
                    }
                    {
                        read_string(ls, ls.*.current, seminfo);
                        return TK_STRING;
                    }
                },
                @as(c_int, 58) => {
                    {
                        _ = blk: {
                            const tmp = if ((blk_1: {
                                const ref = &ls.*.z.*.n;
                                const tmp_2 = ref.*;
                                ref.* -%= 1;
                                break :blk_1 tmp_2;
                            }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                const ref = &ls.*.z.*.p;
                                const tmp_2 = ref.*;
                                ref.* += 1;
                                break :blk_1 tmp_2;
                            }).*))))) else luaZ_fill(ls.*.z);
                            ls.*.current = tmp;
                            break :blk tmp;
                        };
                        if (check_next1(ls, @as(c_int, ':')) != 0) return TK_DBCOLON else return ':';
                    }
                    {
                        read_string(ls, ls.*.current, seminfo);
                        return TK_STRING;
                    }
                },
                @as(c_int, 34), @as(c_int, 39) => {
                    {
                        read_string(ls, ls.*.current, seminfo);
                        return TK_STRING;
                    }
                },
                @as(c_int, 46) => {
                    {
                        _ = blk: {
                            save(ls, ls.*.current);
                            break :blk blk_1: {
                                const tmp = if ((blk_2: {
                                    const ref = &ls.*.z.*.n;
                                    const tmp_3 = ref.*;
                                    ref.* -%= 1;
                                    break :blk_2 tmp_3;
                                }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                                    const ref = &ls.*.z.*.p;
                                    const tmp_3 = ref.*;
                                    ref.* += 1;
                                    break :blk_2 tmp_3;
                                }).*))))) else luaZ_fill(ls.*.z);
                                ls.*.current = tmp;
                                break :blk_1 tmp;
                            };
                        };
                        if (check_next1(ls, @as(c_int, '.')) != 0) {
                            if (check_next1(ls, @as(c_int, '.')) != 0) return TK_DOTS else return TK_CONCAT;
                        } else if (!((blk: {
                            var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(ls.*.current))));
                            _ = &c_;
                            break :blk (@as(c_int, '0') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, '9'));
                        }))) return '.' else return read_numeral(ls, seminfo);
                    }
                    {
                        return read_numeral(ls, seminfo);
                    }
                },
                @as(c_int, 48), @as(c_int, 49), @as(c_int, 50), @as(c_int, 51), @as(c_int, 52), @as(c_int, 53), @as(c_int, 54), @as(c_int, 55), @as(c_int, 56), @as(c_int, 57) => {
                    {
                        return read_numeral(ls, seminfo);
                    }
                },
                @as(c_int, -1) => {
                    {
                        return TK_EOS;
                    }
                },
                else => {
                    {
                        if ((blk: {
                            var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(ls.*.current))));
                            _ = &c_;
                            break :blk (((@as(c_int, 'A') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'Z'))) or ((@as(c_int, 'a') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'z')))) or (@as(c_int, @bitCast(@as(c_uint, c_))) == @as(c_int, '_'));
                        })) {
                            var ts: [*c]TString = undefined;
                            _ = &ts;
                            while (true) {
                                _ = blk: {
                                    save(ls, ls.*.current);
                                    break :blk blk_1: {
                                        const tmp = if ((blk_2: {
                                            const ref = &ls.*.z.*.n;
                                            const tmp_3 = ref.*;
                                            ref.* -%= 1;
                                            break :blk_2 tmp_3;
                                        }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_2: {
                                            const ref = &ls.*.z.*.p;
                                            const tmp_3 = ref.*;
                                            ref.* += 1;
                                            break :blk_2 tmp_3;
                                        }).*))))) else luaZ_fill(ls.*.z);
                                        ls.*.current = tmp;
                                        break :blk_1 tmp;
                                    };
                                };
                                if (!((blk: {
                                    var c_: u8 = @as(u8, @bitCast(@as(i8, @truncate(ls.*.current))));
                                    _ = &c_;
                                    break :blk ((((@as(c_int, '0') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, '9'))) or ((@as(c_int, 'A') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'Z')))) or ((@as(c_int, 'a') <= @as(c_int, @bitCast(@as(c_uint, c_)))) and (@as(c_int, @bitCast(@as(c_uint, c_))) <= @as(c_int, 'z')))) or (@as(c_int, @bitCast(@as(c_uint, c_))) == @as(c_int, '_'));
                                }))) break;
                            }
                            ts = luaX_newstring(ls, ls.*.buff.*.buffer, ls.*.buff.*.n);
                            seminfo.*.ts = ts;
                            if ((@as(c_int, @bitCast(@as(c_uint, ts.*.tt))) == (@as(c_int, 4) | (@as(c_int, 0) << @intCast(4)))) and (@as(c_int, @bitCast(@as(c_uint, ts.*.extra))) > @as(c_int, 0))) return (@as(c_int, @bitCast(@as(c_uint, ts.*.extra))) - @as(c_int, 1)) + (@as(c_int, 255) + @as(c_int, 1)) else {
                                return TK_NAME;
                            }
                        } else {
                            var c: c_int = ls.*.current;
                            _ = &c;
                            _ = blk: {
                                const tmp = if ((blk_1: {
                                    const ref = &ls.*.z.*.n;
                                    const tmp_2 = ref.*;
                                    ref.* -%= 1;
                                    break :blk_1 tmp_2;
                                }) > @as(usize, @bitCast(@as(isize, @as(c_int, 0))))) @as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast((blk_1: {
                                    const ref = &ls.*.z.*.p;
                                    const tmp_2 = ref.*;
                                    ref.* += 1;
                                    break :blk_1 tmp_2;
                                }).*))))) else luaZ_fill(ls.*.z);
                                ls.*.current = tmp;
                                break :blk tmp;
                            };
                            return c;
                        }
                    }
                },
            }
            break;
        }
    }
    return 0;
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
pub const llex_c = "";
pub const LUA_CORE = "";
pub const llex_h = "";
pub const lobject_h = "";
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
pub const CommonHeader = @compileError("unable to translate macro: undefined identifier `tt`");
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
pub const FIRST_RESERVED = UCHAR_MAX + @as(c_int, 1);
pub const LUA_ENV = "_ENV";
pub const NUM_RESERVED = cast_int((TK_WHILE - FIRST_RESERVED) + @as(c_int, 1));
pub const lctype_h = "";
pub inline fn ltolower(c: anytype) @TypeOf(check_exp((('A' <= c) and (c <= 'Z')) or (c == (c | ('A' ^ 'a'))), c | ('A' ^ 'a'))) {
    _ = &c;
    return check_exp((('A' <= c) and (c <= 'Z')) or (c == (c | ('A' ^ 'a'))), c | ('A' ^ 'a'));
}
pub const lisdigit = @compileError("unable to translate macro: undefined identifier `c_`");
// /src/cosmopolitan/third_party/lua/lctype.h:18:9
pub const lislalpha = @compileError("unable to translate macro: undefined identifier `c_`");
// /src/cosmopolitan/third_party/lua/lctype.h:24:9
pub const lislalnum = @compileError("unable to translate macro: undefined identifier `c_`");
// /src/cosmopolitan/third_party/lua/lctype.h:30:9
pub const lisspace = @compileError("unable to translate macro: undefined identifier `c_`");
// /src/cosmopolitan/third_party/lua/lctype.h:37:9
pub const lisxdigit = @compileError("unable to translate macro: undefined identifier `c_`");
// /src/cosmopolitan/third_party/lua/lctype.h:44:9
pub const lisbdigit = @compileError("unable to translate macro: undefined identifier `c_`");
// /src/cosmopolitan/third_party/lua/lctype.h:51:9
pub const lisprint = @compileError("unable to translate macro: undefined identifier `c_`");
// /src/cosmopolitan/third_party/lua/lctype.h:57:9
pub const ldebug_h = "";
pub const lstate_h = "";
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
pub const invalidateTMcache = @compileError("unable to translate macro: undefined identifier `maskflags`");
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
pub const next = @compileError("unable to translate C expr: expected ')' instead got '='");
// /src/cosmopolitan/third_party/lua/llex.c:47:9
pub inline fn currIsNewline(ls: anytype) @TypeOf((ls.*.current == '\n') or (ls.*.current == '\r')) {
    _ = &ls;
    return (ls.*.current == '\n') or (ls.*.current == '\r');
}
pub inline fn save_and_next(ls: anytype) @TypeOf(next(ls)) {
    _ = &ls;
    return blk_1: {
        _ = save(ls, ls.*.current);
        break :blk_1 next(ls);
    };
}
pub const termios = struct_termios;
pub const winsize = struct_winsize;
pub const lconv = struct_lconv;
pub const lua_longjmp = struct_lua_longjmp;
pub const Zio = struct_Zio;
pub const RESERVED = enum_RESERVED;
pub const BlockCnt = struct_BlockCnt;
pub const GCUnion = union_GCUnion;
