// -----------------------------------------------------------------------
// Minimal C builtins required by translated Lua 5.4 code
// -----------------------------------------------------------------------
const c_builtins = @import("std").zig.c_builtins;
pub const __builtin_signbit = c_builtins.__builtin_signbit;
pub const __builtin_clz = c_builtins.__builtin_clz;
pub const __builtin_expect = c_builtins.__builtin_expect;
pub const __builtin_nanf = c_builtins.__builtin_nanf;
pub const __builtin_inff = c_builtins.__builtin_inff;
pub const __builtin_isnan = c_builtins.__builtin_isnan;
pub const __builtin_isinf = c_builtins.__builtin_isinf;

// -----------------------------------------------------------------------
// C type aliases referenced by declarations after line 500
// -----------------------------------------------------------------------
pub const wchar_t = c_uint;
pub const errno_t = c_int;
pub const ptrdiff_t = c_long;
pub const wint_t = c_uint;
pub const uintmax_t = c_ulong;
pub const sig_atomic_t = c_int;

// -----------------------------------------------------------------------
// Structs referenced by type aliases at end of file (termios/winsize)
// -----------------------------------------------------------------------
pub const struct_termios = extern struct {
    c_iflag: u32 = 0,
    c_oflag: u32 = 0,
    c_cflag: u32 = 0,
    c_lflag: u32 = 0,
    c_cc: [20]u8 = [_]u8{0} ** 20,
    _c_ispeed: u32 = 0,
    _c_ospeed: u32 = 0,
};
pub const struct_winsize = extern struct {
    ws_row: u16 = 0,
    ws_col: u16 = 0,
    ws_xpixel: u16 = 0,
    ws_ypixel: u16 = 0,
};

// -----------------------------------------------------------------------
// va_list (needed by lua_pushvfstring, luaO_pushvfstring, stdio v* fns)
// -----------------------------------------------------------------------
pub const struct___va_list_1 = extern struct {
    __stack: ?*anyopaque = null,
    __gr_top: ?*anyopaque = null,
    __vr_top: ?*anyopaque = null,
    __gr_offs: c_int = 0,
    __vr_offs: c_int = 0,
};
pub const __builtin_va_list = struct___va_list_1;

// -----------------------------------------------------------------------
// Libc functions referenced by translated inline macros (post line 500)
// -----------------------------------------------------------------------
pub extern fn abort() noreturn;
pub extern fn realloc(?*anyopaque, c_ulong) ?*anyopaque;
pub extern fn strtod([*c]const u8, [*c][*c]u8) f64;
pub extern fn strlen([*c]const u8) c_ulong;
pub extern fn strncat([*c]u8, [*c]const u8, c_ulong) [*c]u8;
pub extern fn strncpy([*c]u8, [*c]const u8, c_ulong) [*c]u8;

// Freestanding-safe local implementations of libc functions
fn abs(x: c_int) c_int {
    return if (x < 0) -x else x;
}

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
    contents: [1]u8 = @import("std").mem.zeroes([1]u8),
};
pub const TString = struct_TString;
pub const struct_stringtable = extern struct {
    hash: [*c][*c]TString = @import("std").mem.zeroes([*c][*c]TString),
    nuse: c_int = @import("std").mem.zeroes(c_int),
    size: c_int = @import("std").mem.zeroes(c_int),
};
pub const stringtable = struct_stringtable;
pub const lua_State = struct_lua_State;
pub const lua_CFunction = ?*const fn (?*anyopaque) callconv(.c) c_int;
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
pub extern fn luaX_init(L: [*c]lua_State) void;
pub extern fn luaX_setinput(L: [*c]lua_State, ls: [*c]LexState, z: [*c]ZIO, source: [*c]TString, firstchar: c_int) void;
pub extern fn luaX_newstring(ls: [*c]LexState, str: [*c]const u8, l: usize) [*c]TString;
pub extern fn luaX_next(ls: [*c]LexState) void;
pub extern fn luaX_lookahead(ls: [*c]LexState) c_int;
pub extern fn luaX_syntaxerror(ls: [*c]LexState, s: [*c]const u8) noreturn;
pub extern fn luaX_token2str(ls: [*c]LexState, token: c_int) [*c]const u8;
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
pub const OPR_ADD: c_int = 0;
pub const OPR_SUB: c_int = 1;
pub const OPR_MUL: c_int = 2;
pub const OPR_MOD: c_int = 3;
pub const OPR_POW: c_int = 4;
pub const OPR_DIV: c_int = 5;
pub const OPR_IDIV: c_int = 6;
pub const OPR_BAND: c_int = 7;
pub const OPR_BOR: c_int = 8;
pub const OPR_BXOR: c_int = 9;
pub const OPR_SHL: c_int = 10;
pub const OPR_SHR: c_int = 11;
pub const OPR_CONCAT: c_int = 12;
pub const OPR_EQ: c_int = 13;
pub const OPR_LT: c_int = 14;
pub const OPR_LE: c_int = 15;
pub const OPR_NE: c_int = 16;
pub const OPR_GT: c_int = 17;
pub const OPR_GE: c_int = 18;
pub const OPR_AND: c_int = 19;
pub const OPR_OR: c_int = 20;
pub const OPR_NOBINOPR: c_int = 21;
pub const enum_BinOpr = c_uint;
pub const BinOpr = enum_BinOpr;
pub const OPR_MINUS: c_int = 0;
pub const OPR_BNOT: c_int = 1;
pub const OPR_NOT: c_int = 2;
pub const OPR_LEN: c_int = 3;
pub const OPR_NOUNOPR: c_int = 4;
pub const enum_UnOpr = c_uint;
pub const UnOpr = enum_UnOpr;
pub export fn luaK_code(arg_fs: [*c]FuncState, arg_i: Instruction) c_int {
    var fs = arg_fs;
    _ = &fs;
    var i = arg_i;
    _ = &i;
    var f: [*c]Proto = fs.*.f;
    _ = &f;
    _ = blk: {
        const tmp = @as([*c]Instruction, @ptrCast(@alignCast(luaM_growaux_(fs.*.ls.*.L, @as(?*anyopaque, @ptrCast(f.*.code)), fs.*.pc, &f.*.sizecode, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(Instruction))))), @as(c_int, @bitCast(if (@as(usize, @bitCast(@as(c_long, @as(c_int, 2147483647)))) <= (~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) / @sizeOf(Instruction))) @as(c_uint, @bitCast(@as(c_int, 2147483647))) else @as(c_uint, @bitCast(@as(c_uint, @truncate(~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) / @sizeOf(Instruction))))))), "opcodes"))));
        f.*.code = tmp;
        break :blk tmp;
    };
    (blk: {
        const tmp = blk_1: {
            const ref = &fs.*.pc;
            const tmp_2 = ref.*;
            ref.* += 1;
            break :blk_1 tmp_2;
        };
        if (tmp >= 0) break :blk f.*.code + @as(usize, @intCast(tmp)) else break :blk f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).* = i;
    savelineinfo(fs, f, fs.*.ls.*.lastline);
    return fs.*.pc - @as(c_int, 1);
}
pub export fn luaK_codeABx(arg_fs: [*c]FuncState, arg_o: OpCode, arg_a: c_int, arg_bc: c_uint) c_int {
    var fs = arg_fs;
    _ = &fs;
    var o = arg_o;
    _ = &o;
    var a = arg_a;
    _ = &a;
    var bc = arg_bc;
    _ = &bc;
    _ = @as(c_int, 0);
    _ = @as(c_int, 0);
    return luaK_code(fs, ((@as(Instruction, @bitCast(o)) << @intCast(0)) | (@as(Instruction, @bitCast(a)) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | (@as(Instruction, @bitCast(bc)) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))));
}
pub export fn luaK_codeAsBx(arg_fs: [*c]FuncState, arg_o: OpCode, arg_a: c_int, arg_bc: c_int) c_int {
    var fs = arg_fs;
    _ = &fs;
    var o = arg_o;
    _ = &o;
    var a = arg_a;
    _ = &a;
    var bc = arg_bc;
    _ = &bc;
    var b: c_uint = @as(c_uint, @bitCast(bc + (((@as(c_int, 1) << @intCast((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1))) - @as(c_int, 1)) >> @intCast(1))));
    _ = &b;
    _ = @as(c_int, 0);
    _ = @as(c_int, 0);
    return luaK_code(fs, ((@as(Instruction, @bitCast(o)) << @intCast(0)) | (@as(Instruction, @bitCast(a)) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | (@as(Instruction, @bitCast(b)) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))));
}
pub export fn luaK_codeABCk(arg_fs: [*c]FuncState, arg_o: OpCode, arg_a: c_int, arg_b: c_int, arg_c: c_int, arg_k: c_int) c_int {
    var fs = arg_fs;
    _ = &fs;
    var o = arg_o;
    _ = &o;
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var c = arg_c;
    _ = &c;
    var k = arg_k;
    _ = &k;
    _ = @as(c_int, 0);
    _ = @as(c_int, 0);
    return luaK_code(fs, ((((@as(Instruction, @bitCast(o)) << @intCast(0)) | (@as(Instruction, @bitCast(a)) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | (@as(Instruction, @bitCast(b)) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)))) | (@as(Instruction, @bitCast(c)) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8)))) | (@as(Instruction, @bitCast(k)) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))));
}
pub export fn luaK_isKint(arg_e: [*c]expdesc) c_int {
    var e = arg_e;
    _ = &e;
    return @intFromBool((e.*.k == @as(c_uint, @bitCast(VKINT))) and !(e.*.t != e.*.f));
}
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
pub export fn luaK_exp2const(arg_fs: [*c]FuncState, arg_e: [*c]const expdesc, arg_v: [*c]TValue) c_int {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var v = arg_v;
    _ = &v;
    if (e.*.t != e.*.f) return 0;
    while (true) {
        switch (e.*.k) {
            @as(c_uint, @bitCast(@as(c_int, 3))) => {
                _ = blk: {
                    const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 1) | (@as(c_int, 0) << @intCast(4))))));
                    v.*.tt_ = tmp;
                    break :blk tmp;
                };
                return 1;
            },
            @as(c_uint, @bitCast(@as(c_int, 2))) => {
                _ = blk: {
                    const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 1) | (@as(c_int, 1) << @intCast(4))))));
                    v.*.tt_ = tmp;
                    break :blk tmp;
                };
                return 1;
            },
            @as(c_uint, @bitCast(@as(c_int, 1))) => {
                _ = blk: {
                    const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
                    v.*.tt_ = tmp;
                    break :blk tmp;
                };
                return 1;
            },
            @as(c_uint, @bitCast(@as(c_int, 7))) => {
                {
                    {
                        var io: [*c]TValue = v;
                        _ = &io;
                        var x_: [*c]TString = e.*.u.strval;
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
                            _ = fs.*.ls.*.L;
                            break :blk if (!((@as(c_int, @bitCast(@as(c_uint, io.*.tt_))) & (@as(c_int, 1) << @intCast(6))) != 0) or (((@as(c_int, @bitCast(@as(c_uint, io.*.tt_))) & @as(c_int, 63)) == @as(c_int, @bitCast(@as(c_uint, (blk_1: {
                                _ = @as(c_int, 0);
                                break :blk_1 io.*.value_.gc;
                            }).*.tt)))) and ((fs.*.ls.*.L == @as([*c]struct_lua_State, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or !((@as(c_int, @bitCast(@as(c_uint, (blk_1: {
                                _ = @as(c_int, 0);
                                break :blk_1 io.*.value_.gc;
                            }).*.marked))) & (@as(c_int, @bitCast(@as(c_uint, fs.*.ls.*.L.*.l_G.*.currentwhite))) ^ ((@as(c_int, 1) << @intCast(@as(c_int, 3))) | (@as(c_int, 1) << @intCast(@as(c_int, 4)))))) != 0)))) @as(c_int, 0) else @as(c_int, 0);
                        };
                    }
                    return 1;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 11))) => {
                {
                    {
                        var io1: [*c]TValue = v;
                        _ = &io1;
                        var io2: [*c]const TValue = const2val(fs, e);
                        _ = &io2;
                        io1.*.value_ = io2.*.value_;
                        _ = blk: {
                            const tmp = io2.*.tt_;
                            io1.*.tt_ = tmp;
                            break :blk tmp;
                        };
                        _ = blk: {
                            _ = fs.*.ls.*.L;
                            break :blk if (!((@as(c_int, @bitCast(@as(c_uint, io1.*.tt_))) & (@as(c_int, 1) << @intCast(6))) != 0) or (((@as(c_int, @bitCast(@as(c_uint, io1.*.tt_))) & @as(c_int, 63)) == @as(c_int, @bitCast(@as(c_uint, (blk_1: {
                                _ = @as(c_int, 0);
                                break :blk_1 io1.*.value_.gc;
                            }).*.tt)))) and ((fs.*.ls.*.L == @as([*c]struct_lua_State, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or !((@as(c_int, @bitCast(@as(c_uint, (blk_1: {
                                _ = @as(c_int, 0);
                                break :blk_1 io1.*.value_.gc;
                            }).*.marked))) & (@as(c_int, @bitCast(@as(c_uint, fs.*.ls.*.L.*.l_G.*.currentwhite))) ^ ((@as(c_int, 1) << @intCast(@as(c_int, 3))) | (@as(c_int, 1) << @intCast(@as(c_int, 4)))))) != 0)))) @as(c_int, 0) else @as(c_int, 0);
                        };
                        _ = @as(c_int, 0);
                    }
                    return 1;
                }
            },
            else => return tonumeral(e, v),
        }
        break;
    }
    return 0;
}
pub export fn luaK_fixline(arg_fs: [*c]FuncState, arg_line: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var line = arg_line;
    _ = &line;
    removelastlineinfo(fs);
    savelineinfo(fs, fs.*.f, line);
}
pub export fn luaK_nil(arg_fs: [*c]FuncState, arg_from: c_int, arg_n: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var from = arg_from;
    _ = &from;
    var n = arg_n;
    _ = &n;
    var l: c_int = (from + n) - @as(c_int, 1);
    _ = &l;
    var previous: [*c]Instruction = previousinstruction(fs);
    _ = &previous;
    if (@as(c_uint, @bitCast((previous.* >> @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0))))) == @as(c_uint, @bitCast(OP_LOADNIL))) {
        var pfrom: c_int = @as(c_int, @bitCast((previous.* >> @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0)))));
        _ = &pfrom;
        var pl: c_int = pfrom + (blk: {
            _ = @as(c_int, 0);
            break :blk @as(c_int, @bitCast((previous.* >> @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0)))));
        });
        _ = &pl;
        if (((pfrom <= from) and (from <= (pl + @as(c_int, 1)))) or ((from <= pfrom) and (pfrom <= (l + @as(c_int, 1))))) {
            if (pfrom < from) {
                from = pfrom;
            }
            if (pl > l) {
                l = pl;
            }
            _ = blk: {
                const tmp = (previous.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | ((@as(Instruction, @bitCast(from)) << @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7))));
                previous.* = tmp;
                break :blk tmp;
            };
            _ = blk: {
                const tmp = (previous.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)))) | ((@as(Instruction, @bitCast(l - from)) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))));
                previous.* = tmp;
                break :blk tmp;
            };
            return;
        }
    }
    _ = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_LOADNIL)), from, n - @as(c_int, 1), @as(c_int, 0), @as(c_int, 0));
}
pub export fn luaK_reserveregs(arg_fs: [*c]FuncState, arg_n: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var n = arg_n;
    _ = &n;
    luaK_checkstack(fs, n);
    fs.*.freereg +%= @as(lu_byte, @bitCast(@as(i8, @truncate(n))));
}
pub export fn luaK_checkstack(arg_fs: [*c]FuncState, arg_n: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var n = arg_n;
    _ = &n;
    var newstack: c_int = @as(c_int, @bitCast(@as(c_uint, fs.*.freereg))) + n;
    _ = &newstack;
    if (newstack > @as(c_int, @bitCast(@as(c_uint, fs.*.f.*.maxstacksize)))) {
        if (newstack >= @as(c_int, 255)) {
            luaX_syntaxerror(fs.*.ls, "function or expression needs too many registers");
        }
        fs.*.f.*.maxstacksize = @as(lu_byte, @bitCast(@as(i8, @truncate(newstack))));
    }
}
pub export fn luaK_int(arg_fs: [*c]FuncState, arg_reg: c_int, arg_i: lua_Integer) void {
    var fs = arg_fs;
    _ = &fs;
    var reg = arg_reg;
    _ = &reg;
    var i = arg_i;
    _ = &i;
    if (fitsBx(i) != 0) {
        _ = luaK_codeAsBx(fs, @as(c_uint, @bitCast(OP_LOADI)), reg, @as(c_int, @bitCast(@as(c_int, @truncate(i)))));
    } else {
        _ = luaK_codek(fs, reg, luaK_intK(fs, i));
    }
}
pub export fn luaK_dischargevars(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    while (true) {
        switch (e.*.k) {
            @as(c_uint, @bitCast(@as(c_int, 11))) => {
                {
                    const2exp(const2val(fs, e), e);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 9))) => {
                {
                    e.*.u.info = @as(c_int, @bitCast(@as(c_uint, e.*.u.@"var".ridx)));
                    e.*.k = @as(c_uint, @bitCast(VNONRELOC));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 10))) => {
                {
                    e.*.u.info = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_GETUPVAL)), @as(c_int, 0), e.*.u.info, @as(c_int, 0), @as(c_int, 0));
                    e.*.k = @as(c_uint, @bitCast(VRELOC));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 13))) => {
                {
                    e.*.u.info = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_GETTABUP)), @as(c_int, 0), @as(c_int, @bitCast(@as(c_uint, e.*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, e.*.u.ind.idx))), @as(c_int, 0));
                    e.*.k = @as(c_uint, @bitCast(VRELOC));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 14))) => {
                {
                    freereg(fs, @as(c_int, @bitCast(@as(c_uint, e.*.u.ind.t))));
                    e.*.u.info = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_GETI)), @as(c_int, 0), @as(c_int, @bitCast(@as(c_uint, e.*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, e.*.u.ind.idx))), @as(c_int, 0));
                    e.*.k = @as(c_uint, @bitCast(VRELOC));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 15))) => {
                {
                    freereg(fs, @as(c_int, @bitCast(@as(c_uint, e.*.u.ind.t))));
                    e.*.u.info = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_GETFIELD)), @as(c_int, 0), @as(c_int, @bitCast(@as(c_uint, e.*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, e.*.u.ind.idx))), @as(c_int, 0));
                    e.*.k = @as(c_uint, @bitCast(VRELOC));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 12))) => {
                {
                    freeregs(fs, @as(c_int, @bitCast(@as(c_uint, e.*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, e.*.u.ind.idx))));
                    e.*.u.info = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_GETTABLE)), @as(c_int, 0), @as(c_int, @bitCast(@as(c_uint, e.*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, e.*.u.ind.idx))), @as(c_int, 0));
                    e.*.k = @as(c_uint, @bitCast(VRELOC));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 19))), @as(c_uint, @bitCast(@as(c_int, 18))) => {
                {
                    luaK_setoneret(fs, e);
                    break;
                }
            },
            else => break,
        }
        break;
    }
}
pub export fn luaK_exp2anyreg(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) c_int {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    luaK_dischargevars(fs, e);
    if (e.*.k == @as(c_uint, @bitCast(VNONRELOC))) {
        if (!(e.*.t != e.*.f)) return e.*.u.info;
        if (e.*.u.info >= luaY_nvarstack(fs)) {
            exp2reg(fs, e, e.*.u.info);
            return e.*.u.info;
        }
    }
    luaK_exp2nextreg(fs, e);
    return e.*.u.info;
}
pub export fn luaK_exp2anyregup(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    if ((e.*.k != @as(c_uint, @bitCast(VUPVAL))) or (e.*.t != e.*.f)) {
        _ = luaK_exp2anyreg(fs, e);
    }
}
pub export fn luaK_exp2nextreg(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    luaK_dischargevars(fs, e);
    freeexp(fs, e);
    luaK_reserveregs(fs, @as(c_int, 1));
    exp2reg(fs, e, @as(c_int, @bitCast(@as(c_uint, fs.*.freereg))) - @as(c_int, 1));
}
pub export fn luaK_exp2val(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    if (e.*.t != e.*.f) {
        _ = luaK_exp2anyreg(fs, e);
    } else {
        luaK_dischargevars(fs, e);
    }
}
pub export fn luaK_exp2RK(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) c_int {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    if (luaK_exp2K(fs, e) != 0) return 1 else {
        _ = luaK_exp2anyreg(fs, e);
        return 0;
    }
    return 0;
}
pub export fn luaK_self(arg_fs: [*c]FuncState, arg_e: [*c]expdesc, arg_key: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var key = arg_key;
    _ = &key;
    var ereg: c_int = undefined;
    _ = &ereg;
    _ = luaK_exp2anyreg(fs, e);
    ereg = e.*.u.info;
    freeexp(fs, e);
    e.*.u.info = @as(c_int, @bitCast(@as(c_uint, fs.*.freereg)));
    e.*.k = @as(c_uint, @bitCast(VNONRELOC));
    luaK_reserveregs(fs, @as(c_int, 2));
    codeABRK(fs, @as(c_uint, @bitCast(OP_SELF)), e.*.u.info, ereg, key);
    freeexp(fs, key);
}
pub export fn luaK_indexed(arg_fs: [*c]FuncState, arg_t: [*c]expdesc, arg_k: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var t = arg_t;
    _ = &t;
    var k = arg_k;
    _ = &k;
    if (k.*.k == @as(c_uint, @bitCast(VKSTR))) {
        str2K(fs, k);
    }
    _ = @as(c_int, 0);
    if ((t.*.k == @as(c_uint, @bitCast(VUPVAL))) and !(isKstr(fs, k) != 0)) {
        _ = luaK_exp2anyreg(fs, t);
    }
    if (t.*.k == @as(c_uint, @bitCast(VUPVAL))) {
        t.*.u.ind.t = @as(lu_byte, @bitCast(@as(i8, @truncate(t.*.u.info))));
        t.*.u.ind.idx = @as(c_short, @bitCast(@as(c_short, @truncate(k.*.u.info))));
        t.*.k = @as(c_uint, @bitCast(VINDEXUP));
    } else {
        t.*.u.ind.t = @as(lu_byte, @bitCast(@as(i8, @truncate(if (t.*.k == @as(c_uint, @bitCast(VLOCAL))) @as(c_int, @bitCast(@as(c_uint, t.*.u.@"var".ridx))) else t.*.u.info))));
        if (isKstr(fs, k) != 0) {
            t.*.u.ind.idx = @as(c_short, @bitCast(@as(c_short, @truncate(k.*.u.info))));
            t.*.k = @as(c_uint, @bitCast(VINDEXSTR));
        } else if (isCint(k) != 0) {
            t.*.u.ind.idx = @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, @bitCast(@as(c_int, @truncate(k.*.u.ival))))))));
            t.*.k = @as(c_uint, @bitCast(VINDEXI));
        } else {
            t.*.u.ind.idx = @as(c_short, @bitCast(@as(c_short, @truncate(luaK_exp2anyreg(fs, k)))));
            t.*.k = @as(c_uint, @bitCast(VINDEXED));
        }
    }
}
pub export fn luaK_goiftrue(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var pc: c_int = undefined;
    _ = &pc;
    luaK_dischargevars(fs, e);
    while (true) {
        switch (e.*.k) {
            @as(c_uint, @bitCast(@as(c_int, 16))) => {
                {
                    negatecondition(fs, e);
                    pc = e.*.u.info;
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 4))), @as(c_uint, @bitCast(@as(c_int, 5))), @as(c_uint, @bitCast(@as(c_int, 6))), @as(c_uint, @bitCast(@as(c_int, 7))), @as(c_uint, @bitCast(@as(c_int, 2))) => {
                {
                    pc = -@as(c_int, 1);
                    break;
                }
            },
            else => {
                {
                    pc = jumponcond(fs, e, @as(c_int, 0));
                    break;
                }
            },
        }
        break;
    }
    luaK_concat(fs, &e.*.f, pc);
    luaK_patchtohere(fs, e.*.t);
    e.*.t = -@as(c_int, 1);
}
pub export fn luaK_goiffalse(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var pc: c_int = undefined;
    _ = &pc;
    luaK_dischargevars(fs, e);
    while (true) {
        switch (e.*.k) {
            @as(c_uint, @bitCast(@as(c_int, 16))) => {
                {
                    pc = e.*.u.info;
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 1))), @as(c_uint, @bitCast(@as(c_int, 3))) => {
                {
                    pc = -@as(c_int, 1);
                    break;
                }
            },
            else => {
                {
                    pc = jumponcond(fs, e, @as(c_int, 1));
                    break;
                }
            },
        }
        break;
    }
    luaK_concat(fs, &e.*.t, pc);
    luaK_patchtohere(fs, e.*.f);
    e.*.f = -@as(c_int, 1);
}
pub export fn luaK_storevar(arg_fs: [*c]FuncState, arg_var: [*c]expdesc, arg_ex: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var @"var" = arg_var;
    _ = &@"var";
    var ex = arg_ex;
    _ = &ex;
    while (true) {
        switch (@"var".*.k) {
            @as(c_uint, @bitCast(@as(c_int, 9))) => {
                {
                    freeexp(fs, ex);
                    exp2reg(fs, ex, @as(c_int, @bitCast(@as(c_uint, @"var".*.u.@"var".ridx))));
                    return;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 10))) => {
                {
                    var e: c_int = luaK_exp2anyreg(fs, ex);
                    _ = &e;
                    _ = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_SETUPVAL)), e, @"var".*.u.info, @as(c_int, 0), @as(c_int, 0));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 13))) => {
                {
                    codeABRK(fs, @as(c_uint, @bitCast(OP_SETTABUP)), @as(c_int, @bitCast(@as(c_uint, @"var".*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, @"var".*.u.ind.idx))), ex);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 14))) => {
                {
                    codeABRK(fs, @as(c_uint, @bitCast(OP_SETI)), @as(c_int, @bitCast(@as(c_uint, @"var".*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, @"var".*.u.ind.idx))), ex);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 15))) => {
                {
                    codeABRK(fs, @as(c_uint, @bitCast(OP_SETFIELD)), @as(c_int, @bitCast(@as(c_uint, @"var".*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, @"var".*.u.ind.idx))), ex);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 12))) => {
                {
                    codeABRK(fs, @as(c_uint, @bitCast(OP_SETTABLE)), @as(c_int, @bitCast(@as(c_uint, @"var".*.u.ind.t))), @as(c_int, @bitCast(@as(c_int, @"var".*.u.ind.idx))), ex);
                    break;
                }
            },
            else => {
                _ = @as(c_int, 0);
            },
        }
        break;
    }
    freeexp(fs, ex);
}
pub export fn luaK_setreturns(arg_fs: [*c]FuncState, arg_e: [*c]expdesc, arg_nresults: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var nresults = arg_nresults;
    _ = &nresults;
    var pc: [*c]Instruction = &(blk: {
        const tmp = e.*.u.info;
        if (tmp >= 0) break :blk fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*;
    _ = &pc;
    if (e.*.k == @as(c_uint, @bitCast(VCALL))) {
        _ = blk: {
            const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8)))) | ((@as(Instruction, @bitCast(nresults + @as(c_int, 1))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))));
            pc.* = tmp;
            break :blk tmp;
        };
    } else {
        _ = @as(c_int, 0);
        _ = blk: {
            const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8)))) | ((@as(Instruction, @bitCast(nresults + @as(c_int, 1))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))));
            pc.* = tmp;
            break :blk tmp;
        };
        _ = blk: {
            const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | ((@as(Instruction, @bitCast(@as(c_uint, fs.*.freereg))) << @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7))));
            pc.* = tmp;
            break :blk tmp;
        };
        luaK_reserveregs(fs, @as(c_int, 1));
    }
}
pub export fn luaK_setoneret(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    if (e.*.k == @as(c_uint, @bitCast(VCALL))) {
        _ = @as(c_int, 0);
        e.*.k = @as(c_uint, @bitCast(VNONRELOC));
        e.*.u.info = @as(c_int, @bitCast(((blk: {
            const tmp = e.*.u.info;
            if (tmp >= 0) break :blk fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).* >> @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0)))));
    } else if (e.*.k == @as(c_uint, @bitCast(VVARARG))) {
        _ = blk: {
            const tmp = ((blk_1: {
                const tmp_2 = e.*.u.info;
                if (tmp_2 >= 0) break :blk_1 fs.*.f.*.code + @as(usize, @intCast(tmp_2)) else break :blk_1 fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_2)) +% -1));
            }).* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8)))) | ((@as(Instruction, @bitCast(@as(c_int, 2))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))));
            (blk_1: {
                const tmp_2 = e.*.u.info;
                if (tmp_2 >= 0) break :blk_1 fs.*.f.*.code + @as(usize, @intCast(tmp_2)) else break :blk_1 fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_2)) +% -1));
            }).* = tmp;
            break :blk tmp;
        };
        e.*.k = @as(c_uint, @bitCast(VRELOC));
    }
}
pub export fn luaK_jump(arg_fs: [*c]FuncState) c_int {
    var fs = arg_fs;
    _ = &fs;
    return codesJ(fs, @as(c_uint, @bitCast(OP_JMP)), -@as(c_int, 1), @as(c_int, 0));
}
pub export fn luaK_ret(arg_fs: [*c]FuncState, arg_first: c_int, arg_nret: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var first = arg_first;
    _ = &first;
    var nret = arg_nret;
    _ = &nret;
    var op: OpCode = undefined;
    _ = &op;
    while (true) {
        switch (nret) {
            @as(c_int, 0) => {
                op = @as(c_uint, @bitCast(OP_RETURN0));
                break;
            },
            @as(c_int, 1) => {
                op = @as(c_uint, @bitCast(OP_RETURN1));
                break;
            },
            else => {
                op = @as(c_uint, @bitCast(OP_RETURN));
                break;
            },
        }
        break;
    }
    _ = luaK_codeABCk(fs, op, first, nret + @as(c_int, 1), @as(c_int, 0), @as(c_int, 0));
}
pub export fn luaK_patchlist(arg_fs: [*c]FuncState, arg_list: c_int, arg_target: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var list = arg_list;
    _ = &list;
    var target = arg_target;
    _ = &target;
    _ = @as(c_int, 0);
    patchlistaux(fs, list, target, (@as(c_int, 1) << @intCast(8)) - @as(c_int, 1), target);
}
pub export fn luaK_patchtohere(arg_fs: [*c]FuncState, arg_list: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var list = arg_list;
    _ = &list;
    var hr: c_int = luaK_getlabel(fs);
    _ = &hr;
    luaK_patchlist(fs, list, hr);
}
pub export fn luaK_concat(arg_fs: [*c]FuncState, arg_l1: [*c]c_int, arg_l2: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var l1 = arg_l1;
    _ = &l1;
    var l2 = arg_l2;
    _ = &l2;
    if (l2 == -@as(c_int, 1)) return else if (l1.* == -@as(c_int, 1)) {
        l1.* = l2;
    } else {
        var list: c_int = l1.*;
        _ = &list;
        var next: c_int = undefined;
        _ = &next;
        while ((blk: {
            const tmp = getjump(fs, list);
            next = tmp;
            break :blk tmp;
        }) != -@as(c_int, 1)) {
            list = next;
        }
        fixjump(fs, list, l2);
    }
}
pub export fn luaK_getlabel(arg_fs: [*c]FuncState) c_int {
    var fs = arg_fs;
    _ = &fs;
    fs.*.lasttarget = fs.*.pc;
    return fs.*.pc;
}
pub export fn luaK_prefix(arg_fs: [*c]FuncState, arg_opr: UnOpr, arg_e: [*c]expdesc, arg_line: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e = arg_e;
    _ = &e;
    var line = arg_line;
    _ = &line;
    const ef = struct {
        const static: expdesc = expdesc{
            .k = @as(c_uint, @bitCast(VKINT)),
            .u = union_unnamed_16{
                .ival = @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 0)))),
            },
            .t = -@as(c_int, 1),
            .f = -@as(c_int, 1),
        };
    };
    _ = &ef;
    luaK_dischargevars(fs, e);
    while (true) {
        switch (opr) {
            @as(c_uint, @bitCast(@as(c_int, 0))), @as(c_uint, @bitCast(@as(c_int, 1))) => {
                if (constfolding(fs, @as(c_int, @bitCast(opr +% @as(c_uint, @bitCast(@as(c_int, 12))))), e, &ef.static) != 0) break;
                codeunexpval(fs, unopr2op(opr), e, line);
                break;
            },
            @as(c_uint, @bitCast(@as(c_int, 3))) => {
                codeunexpval(fs, unopr2op(opr), e, line);
                break;
            },
            @as(c_uint, @bitCast(@as(c_int, 2))) => {
                codenot(fs, e);
                break;
            },
            else => {
                _ = @as(c_int, 0);
            },
        }
        break;
    }
}
pub export fn luaK_infix(arg_fs: [*c]FuncState, arg_op: BinOpr, arg_v: [*c]expdesc) void {
    var fs = arg_fs;
    _ = &fs;
    var op = arg_op;
    _ = &op;
    var v = arg_v;
    _ = &v;
    luaK_dischargevars(fs, v);
    while (true) {
        switch (op) {
            @as(c_uint, @bitCast(@as(c_int, 19))) => {
                {
                    luaK_goiftrue(fs, v);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 20))) => {
                {
                    luaK_goiffalse(fs, v);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 12))) => {
                {
                    luaK_exp2nextreg(fs, v);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 0))), @as(c_uint, @bitCast(@as(c_int, 1))), @as(c_uint, @bitCast(@as(c_int, 2))), @as(c_uint, @bitCast(@as(c_int, 5))), @as(c_uint, @bitCast(@as(c_int, 6))), @as(c_uint, @bitCast(@as(c_int, 3))), @as(c_uint, @bitCast(@as(c_int, 4))), @as(c_uint, @bitCast(@as(c_int, 7))), @as(c_uint, @bitCast(@as(c_int, 8))), @as(c_uint, @bitCast(@as(c_int, 9))), @as(c_uint, @bitCast(@as(c_int, 10))), @as(c_uint, @bitCast(@as(c_int, 11))) => {
                {
                    if (!(tonumeral(v, null) != 0)) {
                        _ = luaK_exp2anyreg(fs, v);
                    }
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 13))), @as(c_uint, @bitCast(@as(c_int, 16))) => {
                {
                    if (!(tonumeral(v, null) != 0)) {
                        _ = luaK_exp2RK(fs, v);
                    }
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 14))), @as(c_uint, @bitCast(@as(c_int, 15))), @as(c_uint, @bitCast(@as(c_int, 17))), @as(c_uint, @bitCast(@as(c_int, 18))) => {
                {
                    var dummy: c_int = undefined;
                    _ = &dummy;
                    var dummy2: c_int = undefined;
                    _ = &dummy2;
                    if (!(isSCnumber(v, &dummy, &dummy2) != 0)) {
                        _ = luaK_exp2anyreg(fs, v);
                    }
                    break;
                }
            },
            else => {
                _ = @as(c_int, 0);
            },
        }
        break;
    }
}
pub export fn luaK_posfix(arg_fs: [*c]FuncState, arg_opr: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_line: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var line = arg_line;
    _ = &line;
    luaK_dischargevars(fs, e2);
    if ((opr <= @as(c_uint, @bitCast(OPR_SHR))) and (constfolding(fs, @as(c_int, @bitCast(opr +% @as(c_uint, @bitCast(@as(c_int, 0))))), e1, e2) != 0)) return;
    while (true) {
        switch (opr) {
            @as(c_uint, @bitCast(@as(c_int, 19))) => {
                {
                    _ = @as(c_int, 0);
                    luaK_concat(fs, &e2.*.f, e1.*.f);
                    e1.* = e2.*;
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 20))) => {
                {
                    _ = @as(c_int, 0);
                    luaK_concat(fs, &e2.*.t, e1.*.t);
                    e1.* = e2.*;
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 12))) => {
                {
                    luaK_exp2nextreg(fs, e2);
                    codeconcat(fs, e1, e2, line);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 0))), @as(c_uint, @bitCast(@as(c_int, 2))) => {
                {
                    codecommutative(fs, opr, e1, e2, line);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 1))) => {
                {
                    if (finishbinexpneg(fs, e1, e2, @as(c_uint, @bitCast(OP_ADDI)), line, @as(c_uint, @bitCast(TM_SUB))) != 0) break;
                }
                {
                    codearith(fs, opr, e1, e2, @as(c_int, 0), line);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 5))), @as(c_uint, @bitCast(@as(c_int, 6))), @as(c_uint, @bitCast(@as(c_int, 3))), @as(c_uint, @bitCast(@as(c_int, 4))) => {
                {
                    codearith(fs, opr, e1, e2, @as(c_int, 0), line);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 7))), @as(c_uint, @bitCast(@as(c_int, 8))), @as(c_uint, @bitCast(@as(c_int, 9))) => {
                {
                    codebitwise(fs, opr, e1, e2, line);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 10))) => {
                {
                    if (isSCint(e1) != 0) {
                        swapexps(e1, e2);
                        codebini(fs, @as(c_uint, @bitCast(OP_SHLI)), e1, e2, @as(c_int, 1), line, @as(c_uint, @bitCast(TM_SHL)));
                    } else if (finishbinexpneg(fs, e1, e2, @as(c_uint, @bitCast(OP_SHRI)), line, @as(c_uint, @bitCast(TM_SHL))) != 0) {} else {
                        codebinexpval(fs, opr, e1, e2, line);
                    }
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 11))) => {
                {
                    if (isSCint(e2) != 0) {
                        codebini(fs, @as(c_uint, @bitCast(OP_SHRI)), e1, e2, @as(c_int, 0), line, @as(c_uint, @bitCast(TM_SHR)));
                    } else {
                        codebinexpval(fs, opr, e1, e2, line);
                    }
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 13))), @as(c_uint, @bitCast(@as(c_int, 16))) => {
                {
                    codeeq(fs, opr, e1, e2);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 17))), @as(c_uint, @bitCast(@as(c_int, 18))) => {
                {
                    swapexps(e1, e2);
                    opr = (opr -% @as(c_uint, @bitCast(OPR_GT))) +% @as(c_uint, @bitCast(OPR_LT));
                }
                {
                    codeorder(fs, opr, e1, e2);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 14))), @as(c_uint, @bitCast(@as(c_int, 15))) => {
                {
                    codeorder(fs, opr, e1, e2);
                    break;
                }
            },
            else => {
                _ = @as(c_int, 0);
            },
        }
        break;
    }
}
pub export fn luaK_settablesize(arg_fs: [*c]FuncState, arg_pc: c_int, arg_ra: c_int, arg_asize: c_int, arg_hsize: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var pc = arg_pc;
    _ = &pc;
    var ra = arg_ra;
    _ = &ra;
    var asize = arg_asize;
    _ = &asize;
    var hsize = arg_hsize;
    _ = &hsize;
    var inst: [*c]Instruction = &(blk: {
        const tmp = pc;
        if (tmp >= 0) break :blk fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*;
    _ = &inst;
    var rb: c_int = if (hsize != @as(c_int, 0)) luaO_ceillog2(@as(c_uint, @bitCast(hsize))) + @as(c_int, 1) else @as(c_int, 0);
    _ = &rb;
    var extra: c_int = @divTrunc(asize, ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) + @as(c_int, 1));
    _ = &extra;
    var rc: c_int = @import("std").zig.c_translation.signedRemainder(asize, ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) + @as(c_int, 1));
    _ = &rc;
    var k: c_int = @intFromBool(extra > @as(c_int, 0));
    _ = &k;
    inst.* = ((((@as(Instruction, @bitCast(OP_NEWTABLE)) << @intCast(0)) | (@as(Instruction, @bitCast(ra)) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | (@as(Instruction, @bitCast(rb)) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)))) | (@as(Instruction, @bitCast(rc)) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8)))) | (@as(Instruction, @bitCast(k)) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)));
    (inst + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).* = (@as(Instruction, @bitCast(OP_EXTRAARG)) << @intCast(0)) | (@as(Instruction, @bitCast(extra)) << @intCast(@as(c_int, 0) + @as(c_int, 7)));
}
pub export fn luaK_setlist(arg_fs: [*c]FuncState, arg_base: c_int, arg_nelems: c_int, arg_tostore: c_int) void {
    var fs = arg_fs;
    _ = &fs;
    var base = arg_base;
    _ = &base;
    var nelems = arg_nelems;
    _ = &nelems;
    var tostore = arg_tostore;
    _ = &tostore;
    _ = @as(c_int, 0);
    if (tostore == -@as(c_int, 1)) {
        tostore = 0;
    }
    if (nelems <= ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1))) {
        _ = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_SETLIST)), base, tostore, nelems, @as(c_int, 0));
    } else {
        var extra: c_int = @divTrunc(nelems, ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) + @as(c_int, 1));
        _ = &extra;
        nelems = @import("std").zig.c_translation.signedRemainder(nelems, ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) + @as(c_int, 1));
        _ = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_SETLIST)), base, tostore, nelems, @as(c_int, 1));
        _ = codeextraarg(fs, extra);
    }
    fs.*.freereg = @as(lu_byte, @bitCast(@as(i8, @truncate(base + @as(c_int, 1)))));
}
pub export fn luaK_finish(arg_fs: [*c]FuncState) void {
    var fs = arg_fs;
    _ = &fs;
    var i: c_int = undefined;
    _ = &i;
    var p: [*c]Proto = fs.*.f;
    _ = &p;
    {
        i = 0;
        while (i < fs.*.pc) : (i += 1) {
            var pc: [*c]Instruction = &(blk: {
                const tmp = i;
                if (tmp >= 0) break :blk p.*.code + @as(usize, @intCast(tmp)) else break :blk p.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*;
            _ = &pc;
            _ = @as(c_int, 0);
            while (true) {
                switch (@as(c_uint, @bitCast((pc.* >> @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0)))))) {
                    @as(c_uint, @bitCast(@as(c_int, 71))), @as(c_uint, @bitCast(@as(c_int, 72))) => {
                        {
                            if (!((@as(c_int, @bitCast(@as(c_uint, fs.*.needclose))) != 0) or (@as(c_int, @bitCast(@as(c_uint, p.*.is_vararg))) != 0))) break;
                            _ = blk: {
                                const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0)))) | ((@as(Instruction, @bitCast(OP_RETURN)) << @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0))));
                                pc.* = tmp;
                                break :blk tmp;
                            };
                        }
                        {
                            if (fs.*.needclose != 0) {
                                _ = blk: {
                                    const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)))) | ((@as(Instruction, @bitCast(@as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))));
                                    pc.* = tmp;
                                    break :blk tmp;
                                };
                            }
                            if (p.*.is_vararg != 0) {
                                _ = blk: {
                                    const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8)))) | ((@as(Instruction, @bitCast(@as(c_int, @bitCast(@as(c_uint, p.*.numparams))) + @as(c_int, 1))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))));
                                    pc.* = tmp;
                                    break :blk tmp;
                                };
                            }
                            break;
                        }
                    },
                    @as(c_uint, @bitCast(@as(c_int, 70))), @as(c_uint, @bitCast(@as(c_int, 69))) => {
                        {
                            if (fs.*.needclose != 0) {
                                _ = blk: {
                                    const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)))) | ((@as(Instruction, @bitCast(@as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))));
                                    pc.* = tmp;
                                    break :blk tmp;
                                };
                            }
                            if (p.*.is_vararg != 0) {
                                _ = blk: {
                                    const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8)))) | ((@as(Instruction, @bitCast(@as(c_int, @bitCast(@as(c_uint, p.*.numparams))) + @as(c_int, 1))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))));
                                    pc.* = tmp;
                                    break :blk tmp;
                                };
                            }
                            break;
                        }
                    },
                    @as(c_uint, @bitCast(@as(c_int, 56))) => {
                        {
                            var target: c_int = finaltarget(p.*.code, i);
                            _ = &target;
                            fixjump(fs, i, target);
                            break;
                        }
                    },
                    else => break,
                }
                break;
            }
        }
    }
}
pub export fn luaK_semerror(arg_ls: [*c]LexState, arg_msg: [*c]const u8) noreturn {
    var ls = arg_ls;
    _ = &ls;
    var msg = arg_msg;
    _ = &msg;
    ls.*.t.token = 0;
    luaX_syntaxerror(ls, msg);
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
pub fn codesJ(arg_fs: [*c]FuncState, arg_o: OpCode, arg_sj: c_int, arg_k: c_int) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var o = arg_o;
    _ = &o;
    var sj = arg_sj;
    _ = &sj;
    var k = arg_k;
    _ = &k;
    var j: c_uint = @as(c_uint, @bitCast(sj + (((@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1)) >> @intCast(1))));
    _ = &j;
    _ = @as(c_int, 0);
    _ = @as(c_int, 0);
    return luaK_code(fs, ((@as(Instruction, @bitCast(o)) << @intCast(0)) | (@as(Instruction, @bitCast(j)) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | (@as(Instruction, @bitCast(k)) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))));
}
pub fn tonumeral(arg_e: [*c]const expdesc, arg_v: [*c]TValue) callconv(.c) c_int {
    var e = arg_e;
    _ = &e;
    var v = arg_v;
    _ = &v;
    if (e.*.t != e.*.f) return 0;
    while (true) {
        switch (e.*.k) {
            @as(c_uint, @bitCast(@as(c_int, 6))) => {
                if (v != null) {
                    var io: [*c]TValue = v;
                    _ = &io;
                    io.*.value_.i = e.*.u.ival;
                    _ = blk: {
                        const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 3) | (@as(c_int, 0) << @intCast(4))))));
                        io.*.tt_ = tmp;
                        break :blk tmp;
                    };
                }
                return 1;
            },
            @as(c_uint, @bitCast(@as(c_int, 5))) => {
                if (v != null) {
                    var io: [*c]TValue = v;
                    _ = &io;
                    io.*.value_.n = e.*.u.nval;
                    _ = blk: {
                        const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 3) | (@as(c_int, 1) << @intCast(4))))));
                        io.*.tt_ = tmp;
                        break :blk tmp;
                    };
                }
                return 1;
            },
            else => return 0,
        }
        break;
    }
    return 0;
}
pub fn const2val(arg_fs: [*c]FuncState, arg_e: [*c]const expdesc) callconv(.c) [*c]TValue {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    _ = @as(c_int, 0);
    return &(blk: {
        const tmp = e.*.u.info;
        if (tmp >= 0) break :blk fs.*.ls.*.dyd.*.actvar.arr + @as(usize, @intCast(tmp)) else break :blk fs.*.ls.*.dyd.*.actvar.arr - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*.k;
}
pub fn previousinstruction(arg_fs: [*c]FuncState) callconv(.c) [*c]Instruction {
    var fs = arg_fs;
    _ = &fs;
    const invalidinstruction = struct {
        const static: Instruction = ~@as(Instruction, @bitCast(@as(c_int, 0)));
    };
    _ = &invalidinstruction;
    if (fs.*.pc > fs.*.lasttarget) return &(blk: {
        const tmp = fs.*.pc - @as(c_int, 1);
        if (tmp >= 0) break :blk fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).* else return @as([*c]Instruction, @ptrCast(@constCast(@volatileCast(&invalidinstruction.static))));
    return null;
}
pub fn getjump(arg_fs: [*c]FuncState, arg_pc: c_int) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var pc = arg_pc;
    _ = &pc;
    var offset: c_int = blk: {
        _ = @as(c_int, 0);
        break :blk @as(c_int, @bitCast(((blk_1: {
            const tmp = pc;
            if (tmp >= 0) break :blk_1 fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk_1 fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).* >> @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) << @intCast(@as(c_int, 0))))) - (((@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1)) >> @intCast(1));
    };
    _ = &offset;
    if (offset == -@as(c_int, 1)) return -@as(c_int, 1) else return (pc + @as(c_int, 1)) + offset;
    return 0;
}
pub fn fixjump(arg_fs: [*c]FuncState, arg_pc: c_int, arg_dest: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var pc = arg_pc;
    _ = &pc;
    var dest = arg_dest;
    _ = &dest;
    var jmp: [*c]Instruction = &(blk: {
        const tmp = pc;
        if (tmp >= 0) break :blk fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*;
    _ = &jmp;
    var offset: c_int = dest - (pc + @as(c_int, 1));
    _ = &offset;
    _ = @as(c_int, 0);
    if (!((-(((@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1)) >> @intCast(1)) <= offset) and (offset <= (((@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1)) - (((@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1)) >> @intCast(1)))))) {
        luaX_syntaxerror(fs.*.ls, "control structure too long");
    }
    _ = @as(c_int, 0);
    _ = blk: {
        const tmp = (jmp.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | ((@as(Instruction, @bitCast(@as(c_uint, @bitCast(offset + (((@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1)) >> @intCast(1)))))) << @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7))));
        jmp.* = tmp;
        break :blk tmp;
    };
}
pub fn condjump(arg_fs: [*c]FuncState, arg_op: OpCode, arg_A: c_int, arg_B: c_int, arg_C: c_int, arg_k: c_int) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var op = arg_op;
    _ = &op;
    var A = arg_A;
    _ = &A;
    var B = arg_B;
    _ = &B;
    var C = arg_C;
    _ = &C;
    var k = arg_k;
    _ = &k;
    _ = luaK_codeABCk(fs, op, A, B, C, k);
    return luaK_jump(fs);
}
pub fn getjumpcontrol(arg_fs: [*c]FuncState, arg_pc: c_int) callconv(.c) [*c]Instruction {
    var fs = arg_fs;
    _ = &fs;
    var pc = arg_pc;
    _ = &pc;
    var pi: [*c]Instruction = &(blk: {
        const tmp = pc;
        if (tmp >= 0) break :blk fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*;
    _ = &pi;
    if ((pc >= @as(c_int, 1)) and ((@as(c_int, @bitCast(@as(c_uint, luaP_opmodes[@as(c_uint, @bitCast(((pi - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1)))))).* >> @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0)))))]))) & (@as(c_int, 1) << @intCast(4))) != 0)) return pi - @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))) else return pi;
    return null;
}
pub fn patchtestreg(arg_fs: [*c]FuncState, arg_node: c_int, arg_reg: c_int) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var node = arg_node;
    _ = &node;
    var reg = arg_reg;
    _ = &reg;
    var i: [*c]Instruction = getjumpcontrol(fs, node);
    _ = &i;
    if (@as(c_uint, @bitCast((i.* >> @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0))))) != @as(c_uint, @bitCast(OP_TESTSET))) return 0;
    if ((reg != ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1))) and (reg != (blk: {
        _ = @as(c_int, 0);
        break :blk @as(c_int, @bitCast((i.* >> @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0)))));
    }))) {
        _ = blk: {
            const tmp = (i.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | ((@as(Instruction, @bitCast(reg)) << @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7))));
            i.* = tmp;
            break :blk tmp;
        };
    } else {
        i.* = ((((@as(Instruction, @bitCast(OP_TEST)) << @intCast(0)) | (@as(Instruction, @bitCast(blk: {
            _ = @as(c_int, 0);
            break :blk @as(c_int, @bitCast((i.* >> @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0)))));
        })) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | (@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)))) | (@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast((((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8)))) | (@as(Instruction, @bitCast(blk: {
            _ = @as(c_int, 0);
            break :blk @as(c_int, @bitCast((i.* >> @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 1))) << @intCast(@as(c_int, 0)))));
        })) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)));
    }
    return 1;
}
pub fn removevalues(arg_fs: [*c]FuncState, arg_list: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var list = arg_list;
    _ = &list;
    while (list != -@as(c_int, 1)) : (list = getjump(fs, list)) {
        _ = patchtestreg(fs, list, (@as(c_int, 1) << @intCast(8)) - @as(c_int, 1));
    }
}
pub fn patchlistaux(arg_fs: [*c]FuncState, arg_list: c_int, arg_vtarget: c_int, arg_reg: c_int, arg_dtarget: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var list = arg_list;
    _ = &list;
    var vtarget = arg_vtarget;
    _ = &vtarget;
    var reg = arg_reg;
    _ = &reg;
    var dtarget = arg_dtarget;
    _ = &dtarget;
    while (list != -@as(c_int, 1)) {
        var next: c_int = getjump(fs, list);
        _ = &next;
        if (patchtestreg(fs, list, reg) != 0) {
            fixjump(fs, list, vtarget);
        } else {
            fixjump(fs, list, dtarget);
        }
        list = next;
    }
}
pub fn savelineinfo(arg_fs: [*c]FuncState, arg_f: [*c]Proto, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var f = arg_f;
    _ = &f;
    var line = arg_line;
    _ = &line;
    var linedif: c_int = line - fs.*.previousline;
    _ = &linedif;
    var pc: c_int = fs.*.pc - @as(c_int, 1);
    _ = &pc;
    if ((abs(linedif) >= @as(c_int, 128)) or (@as(c_int, @bitCast(@as(c_uint, blk: {
        const ref = &fs.*.iwthabs;
        const tmp = ref.*;
        ref.* +%= 1;
        break :blk tmp;
    }))) >= @as(c_int, 128))) {
        _ = blk: {
            const tmp = @as([*c]AbsLineInfo, @ptrCast(@alignCast(luaM_growaux_(fs.*.ls.*.L, @as(?*anyopaque, @ptrCast(f.*.abslineinfo)), fs.*.nabslineinfo, &f.*.sizeabslineinfo, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(AbsLineInfo))))), @as(c_int, @bitCast(if (@as(usize, @bitCast(@as(c_long, @as(c_int, 2147483647)))) <= (~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) / @sizeOf(AbsLineInfo))) @as(c_uint, @bitCast(@as(c_int, 2147483647))) else @as(c_uint, @bitCast(@as(c_uint, @truncate(~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) / @sizeOf(AbsLineInfo))))))), "lines"))));
            f.*.abslineinfo = tmp;
            break :blk tmp;
        };
        (blk: {
            const tmp = fs.*.nabslineinfo;
            if (tmp >= 0) break :blk f.*.abslineinfo + @as(usize, @intCast(tmp)) else break :blk f.*.abslineinfo - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*.pc = pc;
        (blk: {
            const tmp = blk_1: {
                const ref = &fs.*.nabslineinfo;
                const tmp_2 = ref.*;
                ref.* += 1;
                break :blk_1 tmp_2;
            };
            if (tmp >= 0) break :blk f.*.abslineinfo + @as(usize, @intCast(tmp)) else break :blk f.*.abslineinfo - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*.line = line;
        linedif = -@as(c_int, 128);
        fs.*.iwthabs = 1;
    }
    _ = blk: {
        const tmp = @as([*c]ls_byte, @ptrCast(@alignCast(luaM_growaux_(fs.*.ls.*.L, @as(?*anyopaque, @ptrCast(f.*.lineinfo)), pc, &f.*.sizelineinfo, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(ls_byte))))), @as(c_int, @bitCast(if (@as(usize, @bitCast(@as(c_long, @as(c_int, 2147483647)))) <= (~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) / @sizeOf(ls_byte))) @as(c_uint, @bitCast(@as(c_int, 2147483647))) else @as(c_uint, @bitCast(@as(c_uint, @truncate(~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) / @sizeOf(ls_byte))))))), "opcodes"))));
        f.*.lineinfo = tmp;
        break :blk tmp;
    };
    (blk: {
        const tmp = pc;
        if (tmp >= 0) break :blk f.*.lineinfo + @as(usize, @intCast(tmp)) else break :blk f.*.lineinfo - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).* = @as(ls_byte, @bitCast(@as(i8, @truncate(linedif))));
    fs.*.previousline = line;
}
pub fn removelastlineinfo(arg_fs: [*c]FuncState) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var f: [*c]Proto = fs.*.f;
    _ = &f;
    var pc: c_int = fs.*.pc - @as(c_int, 1);
    _ = &pc;
    if (@as(c_int, @bitCast(@as(c_int, (blk: {
        const tmp = pc;
        if (tmp >= 0) break :blk f.*.lineinfo + @as(usize, @intCast(tmp)) else break :blk f.*.lineinfo - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*))) != -@as(c_int, 128)) {
        fs.*.previousline -= @as(c_int, @bitCast(@as(c_int, (blk: {
            const tmp = pc;
            if (tmp >= 0) break :blk f.*.lineinfo + @as(usize, @intCast(tmp)) else break :blk f.*.lineinfo - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*)));
        fs.*.iwthabs -%= 1;
    } else {
        _ = @as(c_int, 0);
        fs.*.nabslineinfo -= 1;
        fs.*.iwthabs = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 128) + @as(c_int, 1)))));
    }
}
pub fn removelastinstruction(arg_fs: [*c]FuncState) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    removelastlineinfo(fs);
    fs.*.pc -= 1;
}
pub fn codeextraarg(arg_fs: [*c]FuncState, arg_a: c_int) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var a = arg_a;
    _ = &a;
    _ = @as(c_int, 0);
    return luaK_code(fs, (@as(Instruction, @bitCast(OP_EXTRAARG)) << @intCast(0)) | (@as(Instruction, @bitCast(a)) << @intCast(@as(c_int, 0) + @as(c_int, 7))));
}
pub fn luaK_codek(arg_fs: [*c]FuncState, arg_reg: c_int, arg_k: c_int) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var reg = arg_reg;
    _ = &reg;
    var k = arg_k;
    _ = &k;
    if (k <= ((@as(c_int, 1) << @intCast((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1))) - @as(c_int, 1))) return luaK_codeABx(fs, @as(c_uint, @bitCast(OP_LOADK)), reg, @as(c_uint, @bitCast(k))) else {
        var p: c_int = luaK_codeABx(fs, @as(c_uint, @bitCast(OP_LOADKX)), reg, @as(c_uint, @bitCast(@as(c_int, 0))));
        _ = &p;
        _ = codeextraarg(fs, k);
        return p;
    }
    return 0;
}
pub fn freereg(arg_fs: [*c]FuncState, arg_reg: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var reg = arg_reg;
    _ = &reg;
    if (reg >= luaY_nvarstack(fs)) {
        fs.*.freereg -%= 1;
        _ = @as(c_int, 0);
    }
}
pub fn freeregs(arg_fs: [*c]FuncState, arg_r1: c_int, arg_r2: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var r1 = arg_r1;
    _ = &r1;
    var r2 = arg_r2;
    _ = &r2;
    if (r1 > r2) {
        freereg(fs, r1);
        freereg(fs, r2);
    } else {
        freereg(fs, r2);
        freereg(fs, r1);
    }
}
pub fn freeexp(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    if (e.*.k == @as(c_uint, @bitCast(VNONRELOC))) {
        freereg(fs, e.*.u.info);
    }
}
pub fn freeexps(arg_fs: [*c]FuncState, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var r1: c_int = if (e1.*.k == @as(c_uint, @bitCast(VNONRELOC))) e1.*.u.info else -@as(c_int, 1);
    _ = &r1;
    var r2: c_int = if (e2.*.k == @as(c_uint, @bitCast(VNONRELOC))) e2.*.u.info else -@as(c_int, 1);
    _ = &r2;
    freeregs(fs, r1, r2);
}
pub fn addk(arg_fs: [*c]FuncState, arg_key: [*c]TValue, arg_v: [*c]TValue) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var key = arg_key;
    _ = &key;
    var v = arg_v;
    _ = &v;
    var val: TValue = undefined;
    _ = &val;
    var L: [*c]lua_State = fs.*.ls.*.L;
    _ = &L;
    var f: [*c]Proto = fs.*.f;
    _ = &f;
    var idx: [*c]const TValue = luaH_get(fs.*.ls.*.h, key);
    _ = &idx;
    var k: c_int = undefined;
    _ = &k;
    var oldsize: c_int = undefined;
    _ = &oldsize;
    if (@as(c_int, @bitCast(@as(c_uint, idx.*.tt_))) == (@as(c_int, 3) | (@as(c_int, 0) << @intCast(4)))) {
        k = @as(c_int, @bitCast(@as(c_int, @truncate(blk: {
            _ = @as(c_int, 0);
            break :blk idx.*.value_.i;
        }))));
        if (((k < fs.*.nk) and ((@as(c_int, @bitCast(@as(c_uint, (&(blk: {
            const tmp = k;
            if (tmp >= 0) break :blk f.*.k + @as(usize, @intCast(tmp)) else break :blk f.*.k - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*).*.tt_))) & @as(c_int, 63)) == (@as(c_int, @bitCast(@as(c_uint, v.*.tt_))) & @as(c_int, 63)))) and (luaV_equalobj(null, &(blk: {
            const tmp = k;
            if (tmp >= 0) break :blk f.*.k + @as(usize, @intCast(tmp)) else break :blk f.*.k - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*, v) != 0)) return k;
    }
    oldsize = f.*.sizek;
    k = fs.*.nk;
    {
        var io: [*c]TValue = &val;
        _ = &io;
        io.*.value_.i = @as(lua_Integer, @bitCast(@as(c_longlong, k)));
        _ = blk: {
            const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 3) | (@as(c_int, 0) << @intCast(4))))));
            io.*.tt_ = tmp;
            break :blk tmp;
        };
    }
    luaH_finishset(L, fs.*.ls.*.h, key, idx, &val);
    _ = blk: {
        const tmp = @as([*c]TValue, @ptrCast(@alignCast(luaM_growaux_(L, @as(?*anyopaque, @ptrCast(f.*.k)), k, &f.*.sizek, @as(c_int, @bitCast(@as(c_uint, @truncate(@sizeOf(TValue))))), @as(c_int, @bitCast(if (@as(usize, @bitCast(@as(c_long, (@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1)))) <= (~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) / @sizeOf(TValue))) @as(c_uint, @bitCast((@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1))) else @as(c_uint, @bitCast(@as(c_uint, @truncate(~@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))) / @sizeOf(TValue))))))), "constants"))));
        f.*.k = tmp;
        break :blk tmp;
    };
    while (oldsize < f.*.sizek) {
        _ = blk: {
            const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
            (&(blk_1: {
                const tmp_2 = blk_2: {
                    const ref = &oldsize;
                    const tmp_3 = ref.*;
                    ref.* += 1;
                    break :blk_2 tmp_3;
                };
                if (tmp_2 >= 0) break :blk_1 f.*.k + @as(usize, @intCast(tmp_2)) else break :blk_1 f.*.k - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_2)) +% -1));
            }).*).*.tt_ = tmp;
            break :blk tmp;
        };
    }
    {
        var io1: [*c]TValue = &(blk: {
            const tmp = k;
            if (tmp >= 0) break :blk f.*.k + @as(usize, @intCast(tmp)) else break :blk f.*.k - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*;
        _ = &io1;
        var io2: [*c]const TValue = v;
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
    fs.*.nk += 1;
    _ = if ((@as(c_int, @bitCast(@as(c_uint, v.*.tt_))) & (@as(c_int, 1) << @intCast(6))) != 0) if (((@as(c_int, @bitCast(@as(c_uint, f.*.marked))) & (@as(c_int, 1) << @intCast(@as(c_int, 5)))) != 0) and ((@as(c_int, @bitCast(@as(c_uint, (blk: {
        _ = @as(c_int, 0);
        break :blk v.*.value_.gc;
    }).*.marked))) & ((@as(c_int, 1) << @intCast(@as(c_int, 3))) | (@as(c_int, 1) << @intCast(@as(c_int, 4))))) != 0)) luaC_barrier_(L, blk: {
        _ = @as(c_int, 0);
        break :blk &@as([*c]union_GCUnion, @ptrCast(@alignCast(f))).*.gc;
    }, blk: {
        _ = @as(c_int, 0);
        break :blk &@as([*c]union_GCUnion, @ptrCast(@alignCast(blk_1: {
            _ = @as(c_int, 0);
            break :blk_1 v.*.value_.gc;
        }))).*.gc;
    }) else @as(c_int, 0) else @as(c_int, 0);
    return k;
}
pub fn stringK(arg_fs: [*c]FuncState, arg_s: [*c]TString) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var s = arg_s;
    _ = &s;
    var o: TValue = undefined;
    _ = &o;
    {
        var io: [*c]TValue = &o;
        _ = &io;
        var x_: [*c]TString = s;
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
            _ = fs.*.ls.*.L;
            break :blk if (!((@as(c_int, @bitCast(@as(c_uint, io.*.tt_))) & (@as(c_int, 1) << @intCast(6))) != 0) or (((@as(c_int, @bitCast(@as(c_uint, io.*.tt_))) & @as(c_int, 63)) == @as(c_int, @bitCast(@as(c_uint, (blk_1: {
                _ = @as(c_int, 0);
                break :blk_1 io.*.value_.gc;
            }).*.tt)))) and ((fs.*.ls.*.L == @as([*c]struct_lua_State, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or !((@as(c_int, @bitCast(@as(c_uint, (blk_1: {
                _ = @as(c_int, 0);
                break :blk_1 io.*.value_.gc;
            }).*.marked))) & (@as(c_int, @bitCast(@as(c_uint, fs.*.ls.*.L.*.l_G.*.currentwhite))) ^ ((@as(c_int, 1) << @intCast(@as(c_int, 3))) | (@as(c_int, 1) << @intCast(@as(c_int, 4)))))) != 0)))) @as(c_int, 0) else @as(c_int, 0);
        };
    }
    return addk(fs, &o, &o);
}
pub fn luaK_intK(arg_fs: [*c]FuncState, arg_n: lua_Integer) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var n = arg_n;
    _ = &n;
    var o: TValue = undefined;
    _ = &o;
    {
        var io: [*c]TValue = &o;
        _ = &io;
        io.*.value_.i = n;
        _ = blk: {
            const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 3) | (@as(c_int, 0) << @intCast(4))))));
            io.*.tt_ = tmp;
            break :blk tmp;
        };
    }
    return addk(fs, &o, &o);
}
pub fn luaK_numberK(arg_fs: [*c]FuncState, arg_r: lua_Number) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var r = arg_r;
    _ = &r;
    var o: TValue = undefined;
    _ = &o;
    var ik: lua_Integer = undefined;
    _ = &ik;
    {
        var io: [*c]TValue = &o;
        _ = &io;
        io.*.value_.n = r;
        _ = blk: {
            const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 3) | (@as(c_int, 1) << @intCast(4))))));
            io.*.tt_ = tmp;
            break :blk tmp;
        };
    }
    if (!(luaV_flttointeger(r, &ik, @as(c_uint, @bitCast(F2Ieq))) != 0)) return addk(fs, &o, &o) else {
        const nbm: c_int = @as(c_int, 53);
        _ = &nbm;
        const q: lua_Number = ldexp(1.0, -nbm + @as(c_int, 1));
        _ = &q;
        const k: lua_Number = if (ik == @as(lua_Integer, @bitCast(@as(c_longlong, @as(c_int, 0))))) q else r + (r * q);
        _ = &k;
        var kv: TValue = undefined;
        _ = &kv;
        {
            var io: [*c]TValue = &kv;
            _ = &io;
            io.*.value_.n = k;
            _ = blk: {
                const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 3) | (@as(c_int, 1) << @intCast(4))))));
                io.*.tt_ = tmp;
                break :blk tmp;
            };
        }
        _ = @as(c_int, 0);
        return addk(fs, &kv, &o);
    }
    return 0;
}
pub fn boolF(arg_fs: [*c]FuncState) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var o: TValue = undefined;
    _ = &o;
    _ = blk: {
        const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 1) | (@as(c_int, 0) << @intCast(4))))));
        (&o).*.tt_ = tmp;
        break :blk tmp;
    };
    return addk(fs, &o, &o);
}
pub fn boolT(arg_fs: [*c]FuncState) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var o: TValue = undefined;
    _ = &o;
    _ = blk: {
        const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 1) | (@as(c_int, 1) << @intCast(4))))));
        (&o).*.tt_ = tmp;
        break :blk tmp;
    };
    return addk(fs, &o, &o);
}
pub fn nilK(arg_fs: [*c]FuncState) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var k: TValue = undefined;
    _ = &k;
    var v: TValue = undefined;
    _ = &v;
    _ = blk: {
        const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate(@as(c_int, 0) | (@as(c_int, 0) << @intCast(4))))));
        (&v).*.tt_ = tmp;
        break :blk tmp;
    };
    {
        var io: [*c]TValue = &k;
        _ = &io;
        var x_: [*c]Table = fs.*.ls.*.h;
        _ = &x_;
        io.*.value_.gc = blk: {
            _ = @as(c_int, 0);
            break :blk &@as([*c]union_GCUnion, @ptrCast(@alignCast(x_))).*.gc;
        };
        _ = blk: {
            const tmp = @as(lu_byte, @bitCast(@as(i8, @truncate((@as(c_int, 5) | (@as(c_int, 0) << @intCast(4))) | (@as(c_int, 1) << @intCast(6))))));
            io.*.tt_ = tmp;
            break :blk tmp;
        };
        _ = blk: {
            _ = fs.*.ls.*.L;
            break :blk if (!((@as(c_int, @bitCast(@as(c_uint, io.*.tt_))) & (@as(c_int, 1) << @intCast(6))) != 0) or (((@as(c_int, @bitCast(@as(c_uint, io.*.tt_))) & @as(c_int, 63)) == @as(c_int, @bitCast(@as(c_uint, (blk_1: {
                _ = @as(c_int, 0);
                break :blk_1 io.*.value_.gc;
            }).*.tt)))) and ((fs.*.ls.*.L == @as([*c]struct_lua_State, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or !((@as(c_int, @bitCast(@as(c_uint, (blk_1: {
                _ = @as(c_int, 0);
                break :blk_1 io.*.value_.gc;
            }).*.marked))) & (@as(c_int, @bitCast(@as(c_uint, fs.*.ls.*.L.*.l_G.*.currentwhite))) ^ ((@as(c_int, 1) << @intCast(@as(c_int, 3))) | (@as(c_int, 1) << @intCast(@as(c_int, 4)))))) != 0)))) @as(c_int, 0) else @as(c_int, 0);
        };
    }
    return addk(fs, &k, &v);
}
pub fn fitsC(arg_i: lua_Integer) callconv(.c) c_int {
    var i = arg_i;
    _ = &i;
    return @intFromBool((@as(lua_Unsigned, @bitCast(i)) +% @as(lua_Unsigned, @bitCast(@as(c_longlong, ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) >> @intCast(1))))) <= @as(lua_Unsigned, @bitCast(@as(c_ulonglong, @as(c_uint, @bitCast((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)))))));
}
pub fn fitsBx(arg_i: lua_Integer) callconv(.c) c_int {
    var i = arg_i;
    _ = &i;
    return @intFromBool((@as(lua_Integer, @bitCast(@as(c_longlong, -(((@as(c_int, 1) << @intCast((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1))) - @as(c_int, 1)) >> @intCast(1))))) <= i) and (i <= @as(lua_Integer, @bitCast(@as(c_longlong, ((@as(c_int, 1) << @intCast((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1))) - @as(c_int, 1)) - (((@as(c_int, 1) << @intCast((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1))) - @as(c_int, 1)) >> @intCast(1)))))));
}
pub fn luaK_float(arg_fs: [*c]FuncState, arg_reg: c_int, arg_f: lua_Number) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var reg = arg_reg;
    _ = &reg;
    var f = arg_f;
    _ = &f;
    var fi: lua_Integer = undefined;
    _ = &fi;
    if ((luaV_flttointeger(f, &fi, @as(c_uint, @bitCast(F2Ieq))) != 0) and (fitsBx(fi) != 0)) {
        _ = luaK_codeAsBx(fs, @as(c_uint, @bitCast(OP_LOADF)), reg, @as(c_int, @bitCast(@as(c_int, @truncate(fi)))));
    } else {
        _ = luaK_codek(fs, reg, luaK_numberK(fs, f));
    }
}
pub fn const2exp(arg_v: [*c]TValue, arg_e: [*c]expdesc) callconv(.c) void {
    var v = arg_v;
    _ = &v;
    var e = arg_e;
    _ = &e;
    while (true) {
        switch (@as(c_int, @bitCast(@as(c_uint, v.*.tt_))) & @as(c_int, 63)) {
            @as(c_int, 3) => {
                e.*.k = @as(c_uint, @bitCast(VKINT));
                e.*.u.ival = blk: {
                    _ = @as(c_int, 0);
                    break :blk v.*.value_.i;
                };
                break;
            },
            @as(c_int, 19) => {
                e.*.k = @as(c_uint, @bitCast(VKFLT));
                e.*.u.nval = blk: {
                    _ = @as(c_int, 0);
                    break :blk v.*.value_.n;
                };
                break;
            },
            @as(c_int, 1) => {
                e.*.k = @as(c_uint, @bitCast(VFALSE));
                break;
            },
            @as(c_int, 17) => {
                e.*.k = @as(c_uint, @bitCast(VTRUE));
                break;
            },
            @as(c_int, 0) => {
                e.*.k = @as(c_uint, @bitCast(VNIL));
                break;
            },
            @as(c_int, 4), @as(c_int, 20) => {
                e.*.k = @as(c_uint, @bitCast(VKSTR));
                e.*.u.strval = blk: {
                    _ = @as(c_int, 0);
                    break :blk blk_1: {
                        _ = @as(c_int, 0);
                        break :blk_1 &@as([*c]union_GCUnion, @ptrCast(@alignCast(v.*.value_.gc))).*.ts;
                    };
                };
                break;
            },
            else => {
                _ = @as(c_int, 0);
            },
        }
        break;
    }
}
pub fn str2K(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    _ = @as(c_int, 0);
    e.*.u.info = stringK(fs, e.*.u.strval);
    e.*.k = @as(c_uint, @bitCast(VK));
}
pub fn discharge2reg(arg_fs: [*c]FuncState, arg_e: [*c]expdesc, arg_reg: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var reg = arg_reg;
    _ = &reg;
    luaK_dischargevars(fs, e);
    while (true) {
        switch (e.*.k) {
            @as(c_uint, @bitCast(@as(c_int, 1))) => {
                {
                    luaK_nil(fs, reg, @as(c_int, 1));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 3))) => {
                {
                    _ = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_LOADFALSE)), reg, @as(c_int, 0), @as(c_int, 0), @as(c_int, 0));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 2))) => {
                {
                    _ = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_LOADTRUE)), reg, @as(c_int, 0), @as(c_int, 0), @as(c_int, 0));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 7))) => {
                {
                    str2K(fs, e);
                }
                {
                    _ = luaK_codek(fs, reg, e.*.u.info);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 4))) => {
                {
                    _ = luaK_codek(fs, reg, e.*.u.info);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 5))) => {
                {
                    luaK_float(fs, reg, e.*.u.nval);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 6))) => {
                {
                    luaK_int(fs, reg, e.*.u.ival);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 17))) => {
                {
                    var pc: [*c]Instruction = &(blk: {
                        const tmp = e.*.u.info;
                        if (tmp >= 0) break :blk fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
                    }).*;
                    _ = &pc;
                    _ = blk: {
                        const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | ((@as(Instruction, @bitCast(reg)) << @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7))));
                        pc.* = tmp;
                        break :blk tmp;
                    };
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 8))) => {
                {
                    if (reg != e.*.u.info) {
                        _ = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_MOVE)), reg, e.*.u.info, @as(c_int, 0), @as(c_int, 0));
                    }
                    break;
                }
            },
            else => {
                {
                    _ = @as(c_int, 0);
                    return;
                }
            },
        }
        break;
    }
    e.*.u.info = reg;
    e.*.k = @as(c_uint, @bitCast(VNONRELOC));
}
pub fn discharge2anyreg(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    if (e.*.k != @as(c_uint, @bitCast(VNONRELOC))) {
        luaK_reserveregs(fs, @as(c_int, 1));
        discharge2reg(fs, e, @as(c_int, @bitCast(@as(c_uint, fs.*.freereg))) - @as(c_int, 1));
    }
}
pub fn code_loadbool(arg_fs: [*c]FuncState, arg_A: c_int, arg_op: OpCode) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var A = arg_A;
    _ = &A;
    var op = arg_op;
    _ = &op;
    _ = luaK_getlabel(fs);
    return luaK_codeABCk(fs, op, A, @as(c_int, 0), @as(c_int, 0), @as(c_int, 0));
}
pub fn need_value(arg_fs: [*c]FuncState, arg_list: c_int) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var list = arg_list;
    _ = &list;
    while (list != -@as(c_int, 1)) : (list = getjump(fs, list)) {
        var i: Instruction = getjumpcontrol(fs, list).*;
        _ = &i;
        if (@as(c_uint, @bitCast((i >> @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0))))) != @as(c_uint, @bitCast(OP_TESTSET))) return 1;
    }
    return 0;
}
pub fn exp2reg(arg_fs: [*c]FuncState, arg_e: [*c]expdesc, arg_reg: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var reg = arg_reg;
    _ = &reg;
    discharge2reg(fs, e, reg);
    if (e.*.k == @as(c_uint, @bitCast(VJMP))) {
        luaK_concat(fs, &e.*.t, e.*.u.info);
    }
    if (e.*.t != e.*.f) {
        var final: c_int = undefined;
        _ = &final;
        var p_f: c_int = -@as(c_int, 1);
        _ = &p_f;
        var p_t: c_int = -@as(c_int, 1);
        _ = &p_t;
        if ((need_value(fs, e.*.t) != 0) or (need_value(fs, e.*.f) != 0)) {
            var fj: c_int = if (e.*.k == @as(c_uint, @bitCast(VJMP))) -@as(c_int, 1) else luaK_jump(fs);
            _ = &fj;
            p_f = code_loadbool(fs, reg, @as(c_uint, @bitCast(OP_LFALSESKIP)));
            p_t = code_loadbool(fs, reg, @as(c_uint, @bitCast(OP_LOADTRUE)));
            luaK_patchtohere(fs, fj);
        }
        final = luaK_getlabel(fs);
        patchlistaux(fs, e.*.f, final, reg, p_f);
        patchlistaux(fs, e.*.t, final, reg, p_t);
    }
    e.*.f = blk: {
        const tmp = -@as(c_int, 1);
        e.*.t = tmp;
        break :blk tmp;
    };
    e.*.u.info = reg;
    e.*.k = @as(c_uint, @bitCast(VNONRELOC));
}
pub fn luaK_exp2K(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    if (!(e.*.t != e.*.f)) {
        var info: c_int = undefined;
        _ = &info;
        while (true) {
            switch (e.*.k) {
                @as(c_uint, @bitCast(@as(c_int, 2))) => {
                    info = boolT(fs);
                    break;
                },
                @as(c_uint, @bitCast(@as(c_int, 3))) => {
                    info = boolF(fs);
                    break;
                },
                @as(c_uint, @bitCast(@as(c_int, 1))) => {
                    info = nilK(fs);
                    break;
                },
                @as(c_uint, @bitCast(@as(c_int, 6))) => {
                    info = luaK_intK(fs, e.*.u.ival);
                    break;
                },
                @as(c_uint, @bitCast(@as(c_int, 5))) => {
                    info = luaK_numberK(fs, e.*.u.nval);
                    break;
                },
                @as(c_uint, @bitCast(@as(c_int, 7))) => {
                    info = stringK(fs, e.*.u.strval);
                    break;
                },
                @as(c_uint, @bitCast(@as(c_int, 4))) => {
                    info = e.*.u.info;
                    break;
                },
                else => return 0,
            }
            break;
        }
        if (info <= ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1))) {
            e.*.k = @as(c_uint, @bitCast(VK));
            e.*.u.info = info;
            return 1;
        }
    }
    return 0;
}
pub fn codeABRK(arg_fs: [*c]FuncState, arg_o: OpCode, arg_a: c_int, arg_b: c_int, arg_ec: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var o = arg_o;
    _ = &o;
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var ec = arg_ec;
    _ = &ec;
    var k: c_int = luaK_exp2RK(fs, ec);
    _ = &k;
    _ = luaK_codeABCk(fs, o, a, b, ec.*.u.info, k);
}
pub fn negatecondition(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var pc: [*c]Instruction = getjumpcontrol(fs, e.*.u.info);
    _ = &pc;
    _ = @as(c_int, 0);
    _ = blk: {
        const tmp = (pc.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)))) | ((@as(Instruction, @bitCast((blk_1: {
            _ = @as(c_int, 0);
            break :blk_1 @as(c_int, @bitCast((pc.* >> @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 1))) << @intCast(@as(c_int, 0)))));
        }) ^ @as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 1))) << @intCast((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8))));
        pc.* = tmp;
        break :blk tmp;
    };
}
pub fn jumponcond(arg_fs: [*c]FuncState, arg_e: [*c]expdesc, arg_cond: c_int) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    var cond = arg_cond;
    _ = &cond;
    if (e.*.k == @as(c_uint, @bitCast(VRELOC))) {
        var ie: Instruction = (blk: {
            const tmp = e.*.u.info;
            if (tmp >= 0) break :blk fs.*.f.*.code + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*;
        _ = &ie;
        if (@as(c_uint, @bitCast((ie >> @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0))))) == @as(c_uint, @bitCast(OP_NOT))) {
            removelastinstruction(fs);
            return condjump(fs, @as(c_uint, @bitCast(OP_TEST)), blk: {
                _ = @as(c_int, 0);
                break :blk @as(c_int, @bitCast((ie >> @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0)))));
            }, @as(c_int, 0), @as(c_int, 0), @intFromBool(!(cond != 0)));
        }
    }
    discharge2anyreg(fs, e);
    freeexp(fs, e);
    return condjump(fs, @as(c_uint, @bitCast(OP_TESTSET)), (@as(c_int, 1) << @intCast(8)) - @as(c_int, 1), e.*.u.info, @as(c_int, 0), cond);
}
pub fn codenot(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    while (true) {
        switch (e.*.k) {
            @as(c_uint, @bitCast(@as(c_int, 1))), @as(c_uint, @bitCast(@as(c_int, 3))) => {
                {
                    e.*.k = @as(c_uint, @bitCast(VTRUE));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 4))), @as(c_uint, @bitCast(@as(c_int, 5))), @as(c_uint, @bitCast(@as(c_int, 6))), @as(c_uint, @bitCast(@as(c_int, 7))), @as(c_uint, @bitCast(@as(c_int, 2))) => {
                {
                    e.*.k = @as(c_uint, @bitCast(VFALSE));
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 16))) => {
                {
                    negatecondition(fs, e);
                    break;
                }
            },
            @as(c_uint, @bitCast(@as(c_int, 17))), @as(c_uint, @bitCast(@as(c_int, 8))) => {
                {
                    discharge2anyreg(fs, e);
                    freeexp(fs, e);
                    e.*.u.info = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_NOT)), @as(c_int, 0), e.*.u.info, @as(c_int, 0), @as(c_int, 0));
                    e.*.k = @as(c_uint, @bitCast(VRELOC));
                    break;
                }
            },
            else => {
                _ = @as(c_int, 0);
            },
        }
        break;
    }
    {
        var temp: c_int = e.*.f;
        _ = &temp;
        e.*.f = e.*.t;
        e.*.t = temp;
    }
    removevalues(fs, e.*.f);
    removevalues(fs, e.*.t);
}
pub fn isKstr(arg_fs: [*c]FuncState, arg_e: [*c]expdesc) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var e = arg_e;
    _ = &e;
    return @intFromBool((((e.*.k == @as(c_uint, @bitCast(VK))) and !(e.*.t != e.*.f)) and (e.*.u.info <= ((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)))) and (@as(c_int, @bitCast(@as(c_uint, (&(blk: {
        const tmp = e.*.u.info;
        if (tmp >= 0) break :blk fs.*.f.*.k + @as(usize, @intCast(tmp)) else break :blk fs.*.f.*.k - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*).*.tt_))) == ((@as(c_int, 4) | (@as(c_int, 0) << @intCast(4))) | (@as(c_int, 1) << @intCast(6)))));
}
pub fn isCint(arg_e: [*c]expdesc) callconv(.c) c_int {
    var e = arg_e;
    _ = &e;
    return @intFromBool((luaK_isKint(e) != 0) and (@as(lua_Unsigned, @bitCast(e.*.u.ival)) <= @as(lua_Unsigned, @bitCast(@as(c_longlong, (@as(c_int, 1) << @intCast(8)) - @as(c_int, 1))))));
}
pub fn isSCint(arg_e: [*c]expdesc) callconv(.c) c_int {
    var e = arg_e;
    _ = &e;
    return @intFromBool((luaK_isKint(e) != 0) and (fitsC(e.*.u.ival) != 0));
}
pub fn isSCnumber(arg_e: [*c]expdesc, arg_pi: [*c]c_int, arg_isfloat: [*c]c_int) callconv(.c) c_int {
    var e = arg_e;
    _ = &e;
    var pi = arg_pi;
    _ = &pi;
    var isfloat = arg_isfloat;
    _ = &isfloat;
    var i: lua_Integer = undefined;
    _ = &i;
    if (e.*.k == @as(c_uint, @bitCast(VKINT))) {
        i = e.*.u.ival;
    } else if ((e.*.k == @as(c_uint, @bitCast(VKFLT))) and (luaV_flttointeger(e.*.u.nval, &i, @as(c_uint, @bitCast(F2Ieq))) != 0)) {
        isfloat.* = 1;
    } else return 0;
    if (!(e.*.t != e.*.f) and (fitsC(i) != 0)) {
        pi.* = @as(c_int, @bitCast(@as(c_int, @truncate(i)))) + (((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) >> @intCast(1));
        return 1;
    } else return 0;
    return 0;
}
pub fn validop(arg_op: c_int, arg_v1: [*c]TValue, arg_v2: [*c]TValue) callconv(.c) c_int {
    var op = arg_op;
    _ = &op;
    var v1 = arg_v1;
    _ = &v1;
    var v2 = arg_v2;
    _ = &v2;
    while (true) {
        switch (op) {
            @as(c_int, 7), @as(c_int, 8), @as(c_int, 9), @as(c_int, 10), @as(c_int, 11), @as(c_int, 13) => {
                {
                    var i: lua_Integer = undefined;
                    _ = &i;
                    return @intFromBool((luaV_tointegerns(v1, &i, @as(c_uint, @bitCast(F2Ieq))) != 0) and (luaV_tointegerns(v2, &i, @as(c_uint, @bitCast(F2Ieq))) != 0));
                }
            },
            @as(c_int, 5), @as(c_int, 6), @as(c_int, 3) => return @intFromBool((blk: {
                _ = @as(c_int, 0);
                break :blk if (@as(c_int, @bitCast(@as(c_uint, v2.*.tt_))) == (@as(c_int, 3) | (@as(c_int, 0) << @intCast(4)))) @as(lua_Number, @floatFromInt(blk_1: {
                    _ = @as(c_int, 0);
                    break :blk_1 v2.*.value_.i;
                })) else blk_1: {
                    _ = @as(c_int, 0);
                    break :blk_1 v2.*.value_.n;
                };
            }) != @as(lua_Number, @floatFromInt(@as(c_int, 0)))),
            else => return 1,
        }
        break;
    }
    return 0;
}
pub fn constfolding(arg_fs: [*c]FuncState, arg_op: c_int, arg_e1: [*c]expdesc, arg_e2: [*c]const expdesc) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var op = arg_op;
    _ = &op;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var v1: TValue = undefined;
    _ = &v1;
    var v2: TValue = undefined;
    _ = &v2;
    var res: TValue = undefined;
    _ = &res;
    if ((!(tonumeral(e1, &v1) != 0) or !(tonumeral(e2, &v2) != 0)) or !(validop(op, &v1, &v2) != 0)) return 0;
    _ = luaO_rawarith(fs.*.ls.*.L, op, &v1, &v2, &res);
    if (@as(c_int, @bitCast(@as(c_uint, (&res).*.tt_))) == (@as(c_int, 3) | (@as(c_int, 0) << @intCast(4)))) {
        e1.*.k = @as(c_uint, @bitCast(VKINT));
        e1.*.u.ival = blk: {
            _ = @as(c_int, 0);
            break :blk (&res).*.value_.i;
        };
    } else {
        var n: lua_Number = blk: {
            _ = @as(c_int, 0);
            break :blk (&res).*.value_.n;
        };
        _ = &n;
        if (!(n == n) or (n == @as(lua_Number, @floatFromInt(@as(c_int, 0))))) return 0;
        e1.*.k = @as(c_uint, @bitCast(VKFLT));
        e1.*.u.nval = n;
    }
    return 1;
}
pub fn binopr2op(arg_opr: BinOpr, arg_baser: BinOpr, arg_base: OpCode) callconv(.c) OpCode {
    var opr = arg_opr;
    _ = &opr;
    var baser = arg_baser;
    _ = &baser;
    var base = arg_base;
    _ = &base;
    _ = @as(c_int, 0);
    return @as(c_uint, @bitCast((@as(c_int, @bitCast(opr)) - @as(c_int, @bitCast(baser))) + @as(c_int, @bitCast(base))));
}
pub fn unopr2op(arg_opr: UnOpr) callconv(.c) OpCode {
    var opr = arg_opr;
    _ = &opr;
    return @as(c_uint, @bitCast((@as(c_int, @bitCast(opr)) - OPR_MINUS) + OP_UNM));
}
pub fn binopr2TM(arg_opr: BinOpr) callconv(.c) TMS {
    var opr = arg_opr;
    _ = &opr;
    _ = @as(c_int, 0);
    return @as(c_uint, @bitCast((@as(c_int, @bitCast(opr)) - OPR_ADD) + TM_ADD));
}
pub fn codeunexpval(arg_fs: [*c]FuncState, arg_op: OpCode, arg_e: [*c]expdesc, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var op = arg_op;
    _ = &op;
    var e = arg_e;
    _ = &e;
    var line = arg_line;
    _ = &line;
    var r: c_int = luaK_exp2anyreg(fs, e);
    _ = &r;
    freeexp(fs, e);
    e.*.u.info = luaK_codeABCk(fs, op, @as(c_int, 0), r, @as(c_int, 0), @as(c_int, 0));
    e.*.k = @as(c_uint, @bitCast(VRELOC));
    luaK_fixline(fs, line);
}
pub fn finishbinexpval(arg_fs: [*c]FuncState, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_op: OpCode, arg_v2: c_int, arg_flip: c_int, arg_line: c_int, arg_mmop: OpCode, arg_event: TMS) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var op = arg_op;
    _ = &op;
    var v2 = arg_v2;
    _ = &v2;
    var flip = arg_flip;
    _ = &flip;
    var line = arg_line;
    _ = &line;
    var mmop = arg_mmop;
    _ = &mmop;
    var event = arg_event;
    _ = &event;
    var v1: c_int = luaK_exp2anyreg(fs, e1);
    _ = &v1;
    var pc: c_int = luaK_codeABCk(fs, op, @as(c_int, 0), v1, v2, @as(c_int, 0));
    _ = &pc;
    freeexps(fs, e1, e2);
    e1.*.u.info = pc;
    e1.*.k = @as(c_uint, @bitCast(VRELOC));
    luaK_fixline(fs, line);
    _ = luaK_codeABCk(fs, mmop, v1, v2, @as(c_int, @bitCast(event)), flip);
    luaK_fixline(fs, line);
}
pub fn codebinexpval(arg_fs: [*c]FuncState, arg_opr: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var line = arg_line;
    _ = &line;
    var op: OpCode = binopr2op(opr, @as(c_uint, @bitCast(OPR_ADD)), @as(c_uint, @bitCast(OP_ADD)));
    _ = &op;
    var v2: c_int = luaK_exp2anyreg(fs, e2);
    _ = &v2;
    _ = @as(c_int, 0);
    _ = @as(c_int, 0);
    finishbinexpval(fs, e1, e2, op, v2, @as(c_int, 0), line, @as(c_uint, @bitCast(OP_MMBIN)), binopr2TM(opr));
}
pub fn codebini(arg_fs: [*c]FuncState, arg_op: OpCode, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_flip: c_int, arg_line: c_int, arg_event: TMS) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var op = arg_op;
    _ = &op;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var flip = arg_flip;
    _ = &flip;
    var line = arg_line;
    _ = &line;
    var event = arg_event;
    _ = &event;
    var v2: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(e2.*.u.ival)))) + (((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) >> @intCast(1));
    _ = &v2;
    _ = @as(c_int, 0);
    finishbinexpval(fs, e1, e2, op, v2, flip, line, @as(c_uint, @bitCast(OP_MMBINI)), event);
}
pub fn codebinK(arg_fs: [*c]FuncState, arg_opr: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_flip: c_int, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var flip = arg_flip;
    _ = &flip;
    var line = arg_line;
    _ = &line;
    var event: TMS = binopr2TM(opr);
    _ = &event;
    var v2: c_int = e2.*.u.info;
    _ = &v2;
    var op: OpCode = binopr2op(opr, @as(c_uint, @bitCast(OPR_ADD)), @as(c_uint, @bitCast(OP_ADDK)));
    _ = &op;
    finishbinexpval(fs, e1, e2, op, v2, flip, line, @as(c_uint, @bitCast(OP_MMBINK)), event);
}
pub fn finishbinexpneg(arg_fs: [*c]FuncState, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_op: OpCode, arg_line: c_int, arg_event: TMS) callconv(.c) c_int {
    var fs = arg_fs;
    _ = &fs;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var op = arg_op;
    _ = &op;
    var line = arg_line;
    _ = &line;
    var event = arg_event;
    _ = &event;
    if (!(luaK_isKint(e2) != 0)) return 0 else {
        var @"i2": lua_Integer = e2.*.u.ival;
        _ = &@"i2";
        if (!((fitsC(@"i2") != 0) and (fitsC(-@"i2") != 0))) return 0 else {
            var v2: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(@"i2"))));
            _ = &v2;
            finishbinexpval(fs, e1, e2, op, -v2 + (((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) >> @intCast(1)), @as(c_int, 0), line, @as(c_uint, @bitCast(OP_MMBINI)), event);
            _ = blk: {
                const tmp = ((blk_1: {
                    const tmp_2 = fs.*.pc - @as(c_int, 1);
                    if (tmp_2 >= 0) break :blk_1 fs.*.f.*.code + @as(usize, @intCast(tmp_2)) else break :blk_1 fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_2)) +% -1));
                }).* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)))) | ((@as(Instruction, @bitCast(v2 + (((@as(c_int, 1) << @intCast(8)) - @as(c_int, 1)) >> @intCast(1)))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))));
                (blk_1: {
                    const tmp_2 = fs.*.pc - @as(c_int, 1);
                    if (tmp_2 >= 0) break :blk_1 fs.*.f.*.code + @as(usize, @intCast(tmp_2)) else break :blk_1 fs.*.f.*.code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp_2)) +% -1));
                }).* = tmp;
                break :blk tmp;
            };
            return 1;
        }
    }
    return 0;
}
pub fn swapexps(arg_e1: [*c]expdesc, arg_e2: [*c]expdesc) callconv(.c) void {
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var temp: expdesc = e1.*;
    _ = &temp;
    e1.* = e2.*;
    e2.* = temp;
}
pub fn codebinNoK(arg_fs: [*c]FuncState, arg_opr: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_flip: c_int, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var flip = arg_flip;
    _ = &flip;
    var line = arg_line;
    _ = &line;
    if (flip != 0) {
        swapexps(e1, e2);
    }
    codebinexpval(fs, opr, e1, e2, line);
}
pub fn codearith(arg_fs: [*c]FuncState, arg_opr: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_flip: c_int, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var flip = arg_flip;
    _ = &flip;
    var line = arg_line;
    _ = &line;
    if ((tonumeral(e2, null) != 0) and (luaK_exp2K(fs, e2) != 0)) {
        codebinK(fs, opr, e1, e2, flip, line);
    } else {
        codebinNoK(fs, opr, e1, e2, flip, line);
    }
}
pub fn codecommutative(arg_fs: [*c]FuncState, arg_op: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var op = arg_op;
    _ = &op;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var line = arg_line;
    _ = &line;
    var flip: c_int = 0;
    _ = &flip;
    if (tonumeral(e1, null) != 0) {
        swapexps(e1, e2);
        flip = 1;
    }
    if ((op == @as(c_uint, @bitCast(OPR_ADD))) and (isSCint(e2) != 0)) {
        codebini(fs, @as(c_uint, @bitCast(OP_ADDI)), e1, e2, flip, line, @as(c_uint, @bitCast(TM_ADD)));
    } else {
        codearith(fs, op, e1, e2, flip, line);
    }
}
pub fn codebitwise(arg_fs: [*c]FuncState, arg_opr: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var line = arg_line;
    _ = &line;
    var flip: c_int = 0;
    _ = &flip;
    if (e1.*.k == @as(c_uint, @bitCast(VKINT))) {
        swapexps(e1, e2);
        flip = 1;
    }
    if ((e2.*.k == @as(c_uint, @bitCast(VKINT))) and (luaK_exp2K(fs, e2) != 0)) {
        codebinK(fs, opr, e1, e2, flip, line);
    } else {
        codebinNoK(fs, opr, e1, e2, flip, line);
    }
}
pub fn codeorder(arg_fs: [*c]FuncState, arg_opr: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var r1: c_int = undefined;
    _ = &r1;
    var r2: c_int = undefined;
    _ = &r2;
    var im: c_int = undefined;
    _ = &im;
    var isfloat: c_int = 0;
    _ = &isfloat;
    var op: OpCode = undefined;
    _ = &op;
    if (isSCnumber(e2, &im, &isfloat) != 0) {
        r1 = luaK_exp2anyreg(fs, e1);
        r2 = im;
        op = binopr2op(opr, @as(c_uint, @bitCast(OPR_LT)), @as(c_uint, @bitCast(OP_LTI)));
    } else if (isSCnumber(e1, &im, &isfloat) != 0) {
        r1 = luaK_exp2anyreg(fs, e2);
        r2 = im;
        op = binopr2op(opr, @as(c_uint, @bitCast(OPR_LT)), @as(c_uint, @bitCast(OP_GTI)));
    } else {
        r1 = luaK_exp2anyreg(fs, e1);
        r2 = luaK_exp2anyreg(fs, e2);
        op = binopr2op(opr, @as(c_uint, @bitCast(OPR_LT)), @as(c_uint, @bitCast(OP_LT)));
    }
    freeexps(fs, e1, e2);
    e1.*.u.info = condjump(fs, op, r1, r2, isfloat, @as(c_int, 1));
    e1.*.k = @as(c_uint, @bitCast(VJMP));
}
pub fn codeeq(arg_fs: [*c]FuncState, arg_opr: BinOpr, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var opr = arg_opr;
    _ = &opr;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var r1: c_int = undefined;
    _ = &r1;
    var r2: c_int = undefined;
    _ = &r2;
    var im: c_int = undefined;
    _ = &im;
    var isfloat: c_int = 0;
    _ = &isfloat;
    var op: OpCode = undefined;
    _ = &op;
    if (e1.*.k != @as(c_uint, @bitCast(VNONRELOC))) {
        _ = @as(c_int, 0);
        swapexps(e1, e2);
    }
    r1 = luaK_exp2anyreg(fs, e1);
    if (isSCnumber(e2, &im, &isfloat) != 0) {
        op = @as(c_uint, @bitCast(OP_EQI));
        r2 = im;
    } else if (luaK_exp2RK(fs, e2) != 0) {
        op = @as(c_uint, @bitCast(OP_EQK));
        r2 = e2.*.u.info;
    } else {
        op = @as(c_uint, @bitCast(OP_EQ));
        r2 = luaK_exp2anyreg(fs, e2);
    }
    freeexps(fs, e1, e2);
    e1.*.u.info = condjump(fs, op, r1, r2, isfloat, @intFromBool(opr == @as(c_uint, @bitCast(OPR_EQ))));
    e1.*.k = @as(c_uint, @bitCast(VJMP));
}
pub fn codeconcat(arg_fs: [*c]FuncState, arg_e1: [*c]expdesc, arg_e2: [*c]expdesc, arg_line: c_int) callconv(.c) void {
    var fs = arg_fs;
    _ = &fs;
    var e1 = arg_e1;
    _ = &e1;
    var e2 = arg_e2;
    _ = &e2;
    var line = arg_line;
    _ = &line;
    var ie2: [*c]Instruction = previousinstruction(fs);
    _ = &ie2;
    if (@as(c_uint, @bitCast((ie2.* >> @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0))))) == @as(c_uint, @bitCast(OP_CONCAT))) {
        var n: c_int = blk: {
            _ = @as(c_int, 0);
            break :blk @as(c_int, @bitCast((ie2.* >> @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0)))));
        };
        _ = &n;
        _ = @as(c_int, 0);
        freeexp(fs, e2);
        _ = blk: {
            const tmp = (ie2.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7)))) | ((@as(Instruction, @bitCast(e1.*.u.info)) << @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(@as(c_int, 0) + @as(c_int, 7))));
            ie2.* = tmp;
            break :blk tmp;
        };
        _ = blk: {
            const tmp = (ie2.* & ~(~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1)))) | ((@as(Instruction, @bitCast(n + @as(c_int, 1))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 8))) << @intCast(((@as(c_int, 0) + @as(c_int, 7)) + @as(c_int, 8)) + @as(c_int, 1))));
            ie2.* = tmp;
            break :blk tmp;
        };
    } else {
        _ = luaK_codeABCk(fs, @as(c_uint, @bitCast(OP_CONCAT)), e1.*.u.info, @as(c_int, 2), @as(c_int, 0), @as(c_int, 0));
        freeexp(fs, e2);
        luaK_fixline(fs, line);
    }
}
pub fn finaltarget(arg_code: [*c]Instruction, arg_i: c_int) callconv(.c) c_int {
    var code = arg_code;
    _ = &code;
    var i = arg_i;
    _ = &i;
    var count: c_int = undefined;
    _ = &count;
    {
        count = 0;
        while (count < @as(c_int, 100)) : (count += 1) {
            var pc: Instruction = (blk: {
                const tmp = i;
                if (tmp >= 0) break :blk code + @as(usize, @intCast(tmp)) else break :blk code - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            }).*;
            _ = &pc;
            if (@as(c_uint, @bitCast((pc >> @intCast(0)) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(@as(c_int, 7))) << @intCast(@as(c_int, 0))))) != @as(c_uint, @bitCast(OP_JMP))) break else {
                i += (blk: {
                    _ = @as(c_int, 0);
                    break :blk @as(c_int, @bitCast((pc >> @intCast(@as(c_int, 0) + @as(c_int, 7))) & (~(~@as(Instruction, @bitCast(@as(c_int, 0))) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) << @intCast(@as(c_int, 0))))) - (((@as(c_int, 1) << @intCast(((@as(c_int, 8) + @as(c_int, 8)) + @as(c_int, 1)) + @as(c_int, 8))) - @as(c_int, 1)) >> @intCast(1));
                }) + @as(c_int, 1);
            }
        }
    }
    return i;
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
pub const lcode_c = "";
pub const LUA_CORE = "";
pub const lcode_h = "";
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
pub const FIRST_RESERVED = UCHAR_MAX + @as(c_int, 1);
pub const LUA_ENV = "_ENV";
pub const NUM_RESERVED = cast_int((TK_WHILE - FIRST_RESERVED) + @as(c_int, 1));
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
pub const NO_JUMP = -@as(c_int, 1);
pub inline fn foldbinop(op: anytype) @TypeOf(op <= OPR_SHR) {
    _ = &op;
    return op <= OPR_SHR;
}
pub inline fn luaK_codeABC(fs: anytype, o: anytype, a: anytype, b: anytype, c: anytype) @TypeOf(luaK_codeABCk(fs, o, a, b, c, @as(c_int, 0))) {
    _ = &fs;
    _ = &o;
    _ = &a;
    _ = &b;
    _ = &c;
    return luaK_codeABCk(fs, o, a, b, c, @as(c_int, 0));
}
pub inline fn getinstruction(fs: anytype, e: anytype) @TypeOf(fs.*.f.*.code[@as(usize, @intCast(e.*.u.info))]) {
    _ = &fs;
    _ = &e;
    return fs.*.f.*.code[@as(usize, @intCast(e.*.u.info))];
}
pub inline fn luaK_setmultret(fs: anytype, e: anytype) @TypeOf(luaK_setreturns(fs, e, LUA_MULTRET)) {
    _ = &fs;
    _ = &e;
    return luaK_setreturns(fs, e, LUA_MULTRET);
}
pub inline fn luaK_jumpto(fs: anytype, t: anytype) @TypeOf(luaK_patchlist(fs, luaK_jump(fs), t)) {
    _ = &fs;
    _ = &t;
    return luaK_patchlist(fs, luaK_jump(fs), t);
}
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
pub const lvm_h = "";
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
pub const MAXREGS = @as(c_int, 255);
pub inline fn hasjumps(e: anytype) @TypeOf(e.*.t != e.*.f) {
    _ = &e;
    return e.*.t != e.*.f;
}
pub const LIMLINEDIFF = @as(c_int, 0x80);
pub const termios = struct_termios;
pub const winsize = struct_winsize;
pub const lconv = struct_lconv;
pub const lua_longjmp = struct_lua_longjmp;
pub const Zio = struct_Zio;
pub const RESERVED = enum_RESERVED;
pub const BlockCnt = struct_BlockCnt;
pub const OpMode = enum_OpMode;
pub const GCUnion = union_GCUnion;
